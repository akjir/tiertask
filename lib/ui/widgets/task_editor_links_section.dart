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
import '../../models/tdf_metadata.dart';
import '../app_theme.dart';
import 'clearable_text_field.dart';
import 'task_editor_sections.dart';

/// Links (`link <title> <uri>`) editor card inside task and label editors.
class TaskEditorLinksSection extends StatelessWidget {
  /// Creates a [TaskEditorLinksSection].
  const TaskEditorLinksSection({
    super.key,
    required this.canAddLink,
    this.editingIndex,
    required this.errorMessage,
    required this.links,
    required this.titleController,
    required this.uriController,
    required this.onAddLink,
    this.onCancelEdit,
    this.onEditLink,
    this.onMoveLinkDown,
    this.onMoveLinkUp,
    required this.onOpenLink,
    required this.onRemoveLink,
  });

  /// Whether the add or update link button is enabled.
  final bool canAddLink;

  /// Active zero-based index being edited in place, or `null` when creating a link.
  final int? editingIndex;

  /// Optional inline validation error message, or `null` when valid.
  final String? errorMessage;

  /// Current list of links configured on the entity.
  final List<TaskLink> links;

  /// Callback invoked when the add/update button or Enter key is pressed.
  final VoidCallback onAddLink;

  /// Optional callback invoked to cancel an active inline link edit.
  final VoidCallback? onCancelEdit;

  /// Optional callback invoked with the zero-based index to begin editing a link row.
  final ValueChanged<int>? onEditLink;

  /// Optional callback invoked with the zero-based index to move a link row down.
  final ValueChanged<int>? onMoveLinkDown;

  /// Optional callback invoked with the zero-based index to move a link row up.
  final ValueChanged<int>? onMoveLinkUp;

  /// Callback invoked with the target URI when the open-link button on a link row is pressed.
  final ValueChanged<String> onOpenLink;

  /// Callback invoked with the zero-based index when a link row is removed.
  final ValueChanged<int> onRemoveLink;

  /// Controller for the link `<title>` input field.
  final TextEditingController titleController;

  /// Controller for the link `<uri>` input field.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return TaskEditorSectionCard(
      cardKey: const ValueKey('task_editor_links_card'),
      icon: Icons.link_rounded,
      title: localizations.linksSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (links.isNotEmpty) ...[
            _TaskEditorLinksList(
              editingIndex: editingIndex,
              links: links,
              onEditLink: onEditLink,
              onMoveLinkDown: onMoveLinkDown,
              onMoveLinkUp: onMoveLinkUp,
              onOpenLink: onOpenLink,
              onRemoveLink: onRemoveLink,
            ),
            const SizedBox(height: 8),
          ],
          _TaskEditorLinkInputRow(
            canAddLink: canAddLink,
            isEditing: editingIndex != null,
            titleController: titleController,
            uriController: uriController,
            onAddLink: onAddLink,
            onCancelEdit: onCancelEdit,
          ),
          if (errorMessage case final error?) _TaskEditorLinkErrorText(error),
        ],
      ),
    );
  }
}

/// Inline validation error label rendered below [_TaskEditorLinkInputRow].
class _TaskEditorLinkErrorText extends StatelessWidget {
  /// Creates a [_TaskEditorLinkErrorText].
  const _TaskEditorLinkErrorText(this.message);

  /// Localized validation error message.
  final String message;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        message,
        key: const ValueKey('editor_link_error_text'),
        style: TextStyle(color: errorColor, fontSize: 12),
      ),
    );
  }
}

/// Compact icon button used inside [_TaskEditorLinkRowActions].
class _TaskEditorLinkIconButton extends StatelessWidget {
  /// Creates a [_TaskEditorLinkIconButton].
  const _TaskEditorLinkIconButton({
    required this.buttonKey,
    this.color,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  /// Deterministic widget key attached to the [IconButton].
  final Key buttonKey;

  /// Optional foreground tint for [icon].
  final Color? color;

  /// Icon glyph to display.
  final IconData icon;

  /// Callback invoked on tap, or `null` when disabled.
  final VoidCallback? onPressed;

  /// Localized accessibility tooltip.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: color),
      onPressed: onPressed,
    );
  }
}

/// Input row for entering or updating a link `<title>` and `<uri>` inside [TaskEditorLinksSection].
class _TaskEditorLinkInputRow extends StatelessWidget {
  /// Creates a [_TaskEditorLinkInputRow].
  const _TaskEditorLinkInputRow({
    required this.canAddLink,
    required this.isEditing,
    required this.titleController,
    required this.uriController,
    required this.onAddLink,
    required this.onCancelEdit,
  });

  /// Whether the add or update link button is enabled.
  final bool canAddLink;

  /// Whether an existing link row is actively being edited in place.
  final bool isEditing;

  /// Callback invoked when the add/update button or Enter key is pressed.
  final VoidCallback onAddLink;

  /// Optional callback invoked when the cancel-edit button is pressed.
  final VoidCallback? onCancelEdit;

  /// Controller for the link `<title>` input field.
  final TextEditingController titleController;

  /// Controller for the link `<uri>` input field.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TaskEditorLinkTextField(
          controller: titleController,
          fieldKey: const ValueKey('editor_link_title_input'),
          hintText: localizations.linkTitleHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TaskEditorLinkTextField(
                controller: uriController,
                fieldKey: const ValueKey('editor_link_uri_input'),
                hintText: localizations.linkUriHint,
                textInputAction: TextInputAction.done,
                onSubmitted: onAddLink,
              ),
            ),
            const SizedBox(width: 8),
            _TaskEditorLinkSubmitButtons(
              canAddLink: canAddLink,
              isEditing: isEditing,
              onAddLink: onAddLink,
              onCancelEdit: onCancelEdit,
            ),
          ],
        ),
      ],
    );
  }
}

/// Move-up and move-down icon buttons inside [_TaskEditorLinkRowActions].
class _TaskEditorLinkReorderButtons extends StatelessWidget {
  /// Creates [_TaskEditorLinkReorderButtons].
  const _TaskEditorLinkReorderButtons({
    required this.index,
    required this.onMoveDown,
    required this.onMoveUp,
  });

  /// Zero-based index of the link row.
  final int index;

  /// Optional callback invoked when the move-down button is pressed.
  final VoidCallback? onMoveDown;

  /// Optional callback invoked when the move-up button is pressed.
  final VoidCallback? onMoveUp;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('editor_move_link_up_$index'),
          visualDensity: VisualDensity.compact,
          tooltip: localizations.tooltipMoveLinkUp,
          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          onPressed: onMoveUp,
        ),
        IconButton(
          key: ValueKey('editor_move_link_down_$index'),
          visualDensity: VisualDensity.compact,
          tooltip: localizations.tooltipMoveLinkDown,
          icon: const Icon(Icons.arrow_downward_rounded, size: 18),
          onPressed: onMoveDown,
        ),
      ],
    );
  }
}

/// Single row displaying an existing [TaskLink] with optional reorder, edit, open, and remove actions.
class _TaskEditorLinkRow extends StatelessWidget {
  /// Creates a [_TaskEditorLinkRow].
  const _TaskEditorLinkRow({
    required this.index,
    required this.isEditing,
    required this.link,
    required this.onEdit,
    required this.onMoveDown,
    required this.onMoveUp,
    required this.onOpen,
    required this.onRemove,
    required this.showReorderButtons,
  });

  /// Zero-based index of the link.
  final int index;

  /// Whether this row is actively being edited in place.
  final bool isEditing;

  /// Link item to display.
  final TaskLink link;

  /// Optional callback invoked to begin editing this link row.
  final VoidCallback? onEdit;

  /// Optional callback invoked to move this link row down.
  final VoidCallback? onMoveDown;

  /// Optional callback invoked to move this link row up.
  final VoidCallback? onMoveUp;

  /// Callback invoked when the open button is pressed.
  final VoidCallback onOpen;

  /// Callback invoked when the remove button is pressed.
  final VoidCallback onRemove;

  /// Whether up/down reorder buttons are rendered for this section.
  final bool showReorderButtons;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    final decoration = isEditing
        ? BoxDecoration(
            color: appTheme.primaryAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: appTheme.primaryAccent.withValues(alpha: 0.45),
            ),
          )
        : const BoxDecoration();
    return Container(
      key: ValueKey('editor_link_item_$index'),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: EdgeInsets.symmetric(horizontal: isEditing ? 8 : 0, vertical: 2),
      decoration: decoration,
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 18, color: appTheme.primaryAccent),
          const SizedBox(width: 10),
          Expanded(child: _TaskEditorLinkRowTexts(link: link)),
          _TaskEditorLinkRowActions(
            index: index,
            onEdit: onEdit,
            onMoveDown: onMoveDown,
            onMoveUp: onMoveUp,
            onOpen: onOpen,
            onRemove: onRemove,
            showReorderButtons: showReorderButtons,
          ),
        ],
      ),
    );
  }
}

/// Trailing icon actions inside [_TaskEditorLinkRow].
class _TaskEditorLinkRowActions extends StatelessWidget {
  /// Creates [_TaskEditorLinkRowActions].
  const _TaskEditorLinkRowActions({
    required this.index,
    required this.onEdit,
    required this.onMoveDown,
    required this.onMoveUp,
    required this.onOpen,
    required this.onRemove,
    required this.showReorderButtons,
  });

  /// Zero-based index of the link row.
  final int index;

  /// Optional callback invoked when the edit button is pressed.
  final VoidCallback? onEdit;

  /// Optional callback invoked when the move-down button is pressed.
  final VoidCallback? onMoveDown;

  /// Optional callback invoked when the move-up button is pressed.
  final VoidCallback? onMoveUp;

  /// Callback invoked when the open button is pressed.
  final VoidCallback onOpen;

  /// Callback invoked when the remove button is pressed.
  final VoidCallback onRemove;

  /// Whether move-up and move-down buttons are rendered.
  final bool showReorderButtons;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showReorderButtons)
          _TaskEditorLinkReorderButtons(
            index: index,
            onMoveDown: onMoveDown,
            onMoveUp: onMoveUp,
          ),
        if (onEdit != null)
          _TaskEditorLinkIconButton(
            buttonKey: ValueKey('editor_edit_link_$index'),
            color: appTheme.primaryAccent,
            icon: Icons.edit_outlined,
            onPressed: onEdit,
            tooltip: localizations.tooltipEditLink,
          ),
        _TaskEditorLinkIconButton(
          buttonKey: ValueKey('editor_open_link_$index'),
          color: appTheme.primaryAccent,
          icon: Icons.open_in_new_rounded,
          onPressed: onOpen,
          tooltip: localizations.tooltipOpenLink,
        ),
        _TaskEditorLinkIconButton(
          buttonKey: ValueKey('editor_remove_link_$index'),
          color: appTheme.mutedTextColor,
          icon: Icons.close_rounded,
          onPressed: onRemove,
          tooltip: localizations.tooltipRemoveLink,
        ),
      ],
    );
  }
}

/// Title and URI text stack inside [_TaskEditorLinkRow].
class _TaskEditorLinkRowTexts extends StatelessWidget {
  /// Creates [_TaskEditorLinkRowTexts].
  const _TaskEditorLinkRowTexts({required this.link});

  /// Link item whose title and URI are displayed.
  final TaskLink link;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          link.title,
          style: TextStyle(
            color: appTheme.primaryTextColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          link.uri,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: appTheme.mutedTextColor, fontSize: 12),
        ),
      ],
    );
  }
}

/// Submit and optional cancel-edit buttons inside [_TaskEditorLinkInputRow].
class _TaskEditorLinkSubmitButtons extends StatelessWidget {
  /// Creates [_TaskEditorLinkSubmitButtons].
  const _TaskEditorLinkSubmitButtons({
    required this.canAddLink,
    required this.isEditing,
    required this.onAddLink,
    required this.onCancelEdit,
  });

  /// Whether the submit button is enabled.
  final bool canAddLink;

  /// Whether an existing link row is actively being edited.
  final bool isEditing;

  /// Callback invoked when the submit button is pressed.
  final VoidCallback onAddLink;

  /// Optional callback invoked when the cancel-edit button is pressed.
  final VoidCallback? onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          key: const ValueKey('editor_add_link_button'),
          tooltip: isEditing
              ? localizations.tooltipSaveLink
              : localizations.tooltipAddLink,
          onPressed: canAddLink ? onAddLink : null,
          icon: Icon(
            isEditing ? Icons.check_rounded : Icons.add_rounded,
            size: 20,
          ),
        ),
        if (isEditing) ...[
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('editor_cancel_edit_link_button'),
            tooltip: localizations.tooltipCancelEditLink,
            onPressed: onCancelEdit,
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: appTheme.mutedTextColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// Styled [ClearableTextField] for the link `<title>` or `<uri>` input.
class _TaskEditorLinkTextField extends StatelessWidget {
  /// Creates a [_TaskEditorLinkTextField].
  const _TaskEditorLinkTextField({
    required this.controller,
    required this.fieldKey,
    required this.hintText,
    this.onSubmitted,
    required this.textInputAction,
  });

  /// Text controller bound to the input field.
  final TextEditingController controller;

  /// Deterministic widget key for the input field.
  final Key fieldKey;

  /// Localized placeholder text.
  final String hintText;

  /// Optional submit callback invoked when the keyboard action triggers.
  final VoidCallback? onSubmitted;

  /// Keyboard action displayed on soft keyboards.
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );
    return ClearableTextField(
      fieldKey: fieldKey,
      controller: controller,
      cursorColor: appTheme.primaryAccent,
      clearIconColor: appTheme.mutedTextColor,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      textInputAction: textInputAction,
      onSubmitted: onSubmitted != null ? (_) => onSubmitted?.call() : null,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: appTheme.mutedTextColor),
        isDense: true,
        filled: true,
        fillColor: appTheme.canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: appTheme.primaryAccent, width: 1.6),
        ),
      ),
    );
  }
}

/// Column of existing [_TaskEditorLinkRow] items inside [TaskEditorLinksSection].
class _TaskEditorLinksList extends StatelessWidget {
  /// Creates a [_TaskEditorLinksList].
  const _TaskEditorLinksList({
    required this.editingIndex,
    required this.links,
    required this.onEditLink,
    required this.onMoveLinkDown,
    required this.onMoveLinkUp,
    required this.onOpenLink,
    required this.onRemoveLink,
  });

  /// Active zero-based index being edited in place, or `null`.
  final int? editingIndex;

  /// Current list of links.
  final List<TaskLink> links;

  /// Optional callback invoked with the zero-based index to begin editing a row.
  final ValueChanged<int>? onEditLink;

  /// Optional callback invoked with the zero-based index to move a row down.
  final ValueChanged<int>? onMoveLinkDown;

  /// Optional callback invoked with the zero-based index to move a row up.
  final ValueChanged<int>? onMoveLinkUp;

  /// Callback invoked with the target URI to open a row.
  final ValueChanged<String> onOpenLink;

  /// Callback invoked with the zero-based index to remove a row.
  final ValueChanged<int> onRemoveLink;

  @override
  Widget build(BuildContext context) {
    final showReorder = onMoveLinkUp != null || onMoveLinkDown != null;
    final editCallback = onEditLink;
    final moveUpCallback = onMoveLinkUp;
    final moveDownCallback = onMoveLinkDown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < links.length; i++)
          _TaskEditorLinkRow(
            index: i,
            isEditing: editingIndex == i,
            link: links[i],
            showReorderButtons: showReorder,
            onEdit: editCallback != null ? () => editCallback(i) : null,
            onMoveUp: moveUpCallback != null && i > 0
                ? () => moveUpCallback(i)
                : null,
            onMoveDown: moveDownCallback != null && i + 1 < links.length
                ? () => moveDownCallback(i)
                : null,
            onOpen: () => onOpenLink(links[i].uri),
            onRemove: () => onRemoveLink(i),
          ),
      ],
    );
  }
}
