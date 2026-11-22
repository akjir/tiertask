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
import '../primitives/ui_banner.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_pill.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';

/// Shared top meta bar inside expanded Task, Label, and Location cards (`U-CARD-002`).
class EntityCardMetaBar extends StatelessWidget {
  /// Creates an [EntityCardMetaBar].
  const EntityCardMetaBar({
    super.key,
    required this.entityId,
    required this.copyIdTooltip,
    required this.onCopyId,
    required this.deleteTooltip,
    required this.deleteConfirmMessage,
    required this.isConfirmingDelete,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
    this.statusPillLabel,
    this.statusPillTone = UiPillTone.neutral,
  });

  /// Tooltip for the compact Copy ID icon button.
  final String copyIdTooltip;

  /// Inline prompt message displayed while [isConfirmingDelete] is true.
  final String deleteConfirmMessage;

  /// Tooltip for the right-aligned Trash icon button.
  final String deleteTooltip;

  /// Canonical entity identifier displayed in monospace.
  final String entityId;

  /// Swaps the Trash icon button in-place into an inline delete confirmation banner.
  final bool isConfirmingDelete;

  /// Callback cancelling the inline delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback confirming deletion of the entity.
  final VoidCallback onConfirmDelete;

  /// Callback copying [entityId] and emitting confirmation feedback.
  final VoidCallback onCopyId;

  /// Callback requesting inline delete confirmation.
  final VoidCallback onRequestDelete;

  /// Optional contextual status pill label (e.g. completed read-only or open count).
  final String? statusPillLabel;

  /// Semantic visual tone for [statusPillLabel].
  final UiPillTone statusPillTone;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    final leadingMeta = _EntityMetaBarLeadingCluster(
      entityIdLabel: localizations.taskIdRowLabel(entityId),
      copyIdTooltip: copyIdTooltip,
      onCopyId: onCopyId,
      statusPillLabel: statusPillLabel,
      statusPillTone: statusPillTone,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: tokens.colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 10.0),
        child: _EntityMetaBarLayout(
          leadingMeta: leadingMeta,
          deleteTooltip: deleteTooltip,
          deleteConfirmMessage: deleteConfirmMessage,
          isConfirmingDelete: isConfirmingDelete,
          onRequestDelete: onRequestDelete,
          onCancelDelete: onCancelDelete,
          onConfirmDelete: onConfirmDelete,
        ),
      ),
    );
  }
}

/// Shared footer rendered inside inline entity section editors (`U-CARD-003`).
class EntityInlineEditorFooter extends StatelessWidget {
  /// Creates an [EntityInlineEditorFooter].
  const EntityInlineEditorFooter({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.errorText,
    this.clearLabel,
    this.onClear,
    this.isBusy = false,
    this.saveLabel,
  });

  /// Optional label for the left-aligned destructive clear button.
  final String? clearLabel;

  /// Optional inline validation or persistence error text announced via live region.
  final String? errorText;

  /// Disables actions and spins the Save button indicator while true.
  final bool isBusy;

  /// Callback cancelling the active inline edit.
  final VoidCallback onCancel;

  /// Optional callback clearing the section value.
  final VoidCallback? onClear;

  /// Callback committing the active inline edit.
  final VoidCallback onSave;

  /// Optional custom label overriding the default localized Save copy.
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final errorMessage = errorText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (errorMessage != null && errorMessage.isNotEmpty) ...<Widget>[
          EntityInlineErrorText(message: errorMessage),
          SizedBox(height: tokens.spacing.space2),
        ],
        _EntityInlineEditorActionRow(
          clearLabel: clearLabel,
          onClear: onClear,
          onCancel: onCancel,
          onSave: onSave,
          isBusy: isBusy,
          saveLabel: saveLabel,
        ),
      ],
    );
  }
}

/// Renders an inline `danger` live-region validation or persistence error message.
class EntityInlineErrorText extends StatelessWidget {
  /// Creates an [EntityInlineErrorText].
  const EntityInlineErrorText({super.key, required this.message});

  /// Localized error copy to announce.
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: tokens.typography.meta.copyWith(
          color: tokens.colors.danger,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Shared right-aligned `Cancel` + primary/danger action footer for confirmation modals.
class EntityModalActionFooter extends StatelessWidget {
  /// Creates a [EntityModalActionFooter].
  const EntityModalActionFooter({
    super.key,
    required this.cancelKey,
    required this.confirmKey,
    required this.confirmLabel,
    required this.confirmVariant,
    required this.isBusy,
    required this.onCancel,
    required this.onConfirm,
  });

  /// Stable key for the cancel button.
  final Key cancelKey;

  /// Stable key for the confirm button.
  final Key confirmKey;

  /// Localized label for the confirm button.
  final String confirmLabel;

  /// Visual button variant (`primary` or `danger`).
  final UiButtonVariant confirmVariant;

  /// Whether an asynchronous action is currently in flight.
  final bool isBusy;

  /// Cancel callback.
  final VoidCallback onCancel;

  /// Confirm callback, or `null` when confirmation is disabled.
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      alignment: WrapAlignment.end,
      children: <Widget>[
        UiButton(
          key: cancelKey,
          label: localizations.actionCancel,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: isBusy ? null : onCancel,
        ),
        UiButton(
          key: confirmKey,
          label: confirmLabel,
          variant: confirmVariant,
          density: UiButtonDensity.compact,
          isLoading: isBusy,
          onPressed: isBusy ? null : onConfirm,
        ),
      ],
    );
  }
}

/// Renders the optional destructive clear button alongside the Cancel/Save action group.
class _EntityInlineEditorActionButtons extends StatelessWidget {
  /// Creates an [_EntityInlineEditorActionButtons].
  const _EntityInlineEditorActionButtons({
    required this.clearLabel,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
    required this.isBusy,
    required this.saveLabel,
  });

  /// Optional left clear button label.
  final String? clearLabel;

  /// Disables actions and spins the Save indicator while true.
  final bool isBusy;

  /// Cancel callback.
  final VoidCallback onCancel;

  /// Optional clear callback.
  final VoidCallback? onClear;

  /// Save callback.
  final VoidCallback onSave;

  /// Optional custom Save label.
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final showClear = clearLabel != null && onClear != null;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: tokens.spacing.space2,
      runSpacing: tokens.spacing.space2,
      children: <Widget>[
        if (showClear)
          UiButton(
            label: clearLabel,
            variant: UiButtonVariant.danger,
            density: UiButtonDensity.compact,
            onPressed: isBusy ? null : onClear,
          )
        else
          const SizedBox.shrink(),
        _EntityInlineEditorCommitButtons(
          isBusy: isBusy,
          onCancel: onCancel,
          onSave: onSave,
          saveLabel: saveLabel,
        ),
      ],
    );
  }
}

/// Renders the bordered action row inside [EntityInlineEditorFooter].
class _EntityInlineEditorActionRow extends StatelessWidget {
  /// Creates an [_EntityInlineEditorActionRow].
  const _EntityInlineEditorActionRow({
    required this.clearLabel,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
    required this.isBusy,
    required this.saveLabel,
  });

  /// Optional left clear button label.
  final String? clearLabel;

  /// Disables actions and spins Save indicator while true.
  final bool isBusy;

  /// Cancel callback.
  final VoidCallback onCancel;

  /// Optional clear callback.
  final VoidCallback? onClear;

  /// Save callback.
  final VoidCallback onSave;

  /// Optional custom Save label.
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: tokens.colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: tokens.spacing.space2),
        child: _EntityInlineEditorActionButtons(
          clearLabel: clearLabel,
          onClear: onClear,
          onCancel: onCancel,
          onSave: onSave,
          isBusy: isBusy,
          saveLabel: saveLabel,
        ),
      ),
    );
  }
}

/// Renders the right-aligned Cancel and Save buttons inside [_EntityInlineEditorActionButtons].
class _EntityInlineEditorCommitButtons extends StatelessWidget {
  /// Creates an [_EntityInlineEditorCommitButtons].
  const _EntityInlineEditorCommitButtons({
    required this.isBusy,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
  });

  /// Disables buttons and spins the Save indicator while true.
  final bool isBusy;

  /// Cancel callback.
  final VoidCallback onCancel;

  /// Save callback.
  final VoidCallback onSave;

  /// Optional custom Save label overriding localized default copy.
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiButton(
          label: localizations.actionCancel,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: isBusy ? null : onCancel,
        ),
        const SizedBox(width: 6.0),
        UiButton(
          label: saveLabel ?? localizations.actionSave,
          leadingIcon: isBusy ? Icons.sync_rounded : null,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          isLoading: isBusy,
          onPressed: isBusy ? null : onSave,
        ),
      ],
    );
  }
}

/// Arranges [leadingMeta] and the right-aligned Trash button or inline delete confirmation banner.
class _EntityMetaBarLayout extends StatelessWidget {
  /// Creates an [_EntityMetaBarLayout].
  const _EntityMetaBarLayout({
    required this.leadingMeta,
    required this.deleteTooltip,
    required this.deleteConfirmMessage,
    required this.isConfirmingDelete,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
  });

  /// Prompt shown inside the inline confirmation banner.
  final String deleteConfirmMessage;

  /// Tooltip for the Trash icon button.
  final String deleteTooltip;

  /// Whether the inline delete confirmation banner replaces the Trash icon button.
  final bool isConfirmingDelete;

  /// Left-aligned ID, copy trigger, and optional status pill cluster.
  final Widget leadingMeta;

  /// Callback cancelling delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback confirming deletion.
  final VoidCallback onConfirmDelete;

  /// Callback opening inline delete confirmation.
  final VoidCallback onRequestDelete;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (isConfirmingDelete) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8.0,
        runSpacing: 8.0,
        children: <Widget>[
          leadingMeta,
          UiBanner(
            variant: UiBannerVariant.inlineConfirm,
            message: deleteConfirmMessage,
            cancelLabel: localizations.actionKeep,
            confirmLabel: localizations.actionConfirmDelete,
            onCancel: onCancelDelete,
            onConfirm: onConfirmDelete,
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: leadingMeta),
        const SizedBox(width: 8.0),
        UiButton(
          leadingIcon: Icons.delete_outline_rounded,
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.dense,
          isDangerHover: true,
          tooltip: deleteTooltip,
          onPressed: onRequestDelete,
        ),
      ],
    );
  }
}

/// Renders the left-side ID, copy trigger, and optional contextual status pill inside [EntityCardMetaBar].
class _EntityMetaBarLeadingCluster extends StatelessWidget {
  /// Creates an [_EntityMetaBarLeadingCluster].
  const _EntityMetaBarLeadingCluster({
    required this.entityIdLabel,
    required this.copyIdTooltip,
    required this.onCopyId,
    required this.statusPillLabel,
    required this.statusPillTone,
  });

  /// Tooltip for the compact copy button.
  final String copyIdTooltip;

  /// Localized `ID: <id>` string.
  final String entityIdLabel;

  /// Callback invoked when Copy ID is pressed.
  final VoidCallback onCopyId;

  /// Optional status pill text.
  final String? statusPillLabel;

  /// Visual tone for [statusPillLabel].
  final UiPillTone statusPillTone;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final pillText = statusPillLabel;

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          entityIdLabel,
          style: UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: tokens.colors.muted),
          ),
        ),
        UiButton(
          leadingIcon: Icons.copy_outlined,
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.dense,
          tooltip: copyIdTooltip,
          onPressed: onCopyId,
        ),
        if (pillText != null && pillText.isNotEmpty)
          UiPill(
            label: pillText,
            variant: UiPillVariant.badge,
            tone: statusPillTone,
          ),
      ],
    );
  }
}
