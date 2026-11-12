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
import '../../models/task_item.dart';
import '../app_theme.dart';
import 'clearable_text_field.dart';
import 'task_editor_sections.dart';

/// Links (`link <title> <uri>`) editor card inside the task editor.
class TaskEditorLinksSection extends StatelessWidget {
  /// Creates a [TaskEditorLinksSection].
  const TaskEditorLinksSection({
    super.key,
    required this.canAddLink,
    required this.errorMessage,
    required this.links,
    required this.titleController,
    required this.uriController,
    required this.onAddLink,
    required this.onOpenLink,
    required this.onRemoveLink,
  });

  /// Whether the add-link button is enabled.
  final bool canAddLink;

  /// Optional inline validation error message, or `null` when valid.
  final String? errorMessage;

  /// Current list of links configured on the task.
  final List<TaskLink> links;

  /// Callback invoked when the add-link button or Enter key is pressed.
  final VoidCallback onAddLink;

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
    final colorScheme = Theme.of(context).colorScheme;

    return TaskEditorSectionCard(
      cardKey: const ValueKey('task_editor_links_card'),
      icon: Icons.link_rounded,
      title: localizations.linksSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (links.isNotEmpty) ...[
            for (var i = 0; i < links.length; i++)
              _TaskEditorLinkRow(
                index: i,
                link: links[i],
                onOpen: () => onOpenLink(links[i].uri),
                onRemove: () => onRemoveLink(i),
              ),
            const SizedBox(height: 8),
          ],
          _TaskEditorLinkInputRow(
            canAddLink: canAddLink,
            titleController: titleController,
            uriController: uriController,
            onAddLink: onAddLink,
          ),
          if (errorMessage case final error?) ...[
            const SizedBox(height: 6),
            Text(
              error,
              key: const ValueKey('editor_link_error_text'),
              style: TextStyle(color: colorScheme.error, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// Input row for entering a new link `<title>` and `<uri>` inside [TaskEditorLinksSection].
class _TaskEditorLinkInputRow extends StatelessWidget {
  /// Creates a [_TaskEditorLinkInputRow].
  const _TaskEditorLinkInputRow({
    required this.canAddLink,
    required this.titleController,
    required this.uriController,
    required this.onAddLink,
  });

  /// Whether the add-link button is enabled.
  final bool canAddLink;

  /// Callback invoked when the add-link button or Enter key is pressed.
  final VoidCallback onAddLink;

  /// Controller for the link `<title>` input field.
  final TextEditingController titleController;

  /// Controller for the link `<uri>` input field.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputField(
          appTheme: appTheme,
          controller: titleController,
          fieldKey: const ValueKey('editor_link_title_input'),
          hintText: localizations.linkTitleHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                appTheme: appTheme,
                controller: uriController,
                fieldKey: const ValueKey('editor_link_uri_input'),
                hintText: localizations.linkUriHint,
                textInputAction: TextInputAction.done,
                onSubmitted: onAddLink,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('editor_add_link_button'),
              tooltip: localizations.tooltipAddLink,
              onPressed: canAddLink ? onAddLink : null,
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds a styled [ClearableTextField] for the link title or URI input.
  Widget _buildInputField({
    required AppTheme appTheme,
    required TextEditingController controller,
    required Key fieldKey,
    required String hintText,
    required TextInputAction textInputAction,
    VoidCallback? onSubmitted,
  }) {
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
      onSubmitted: onSubmitted != null ? (_) => onSubmitted() : null,
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

/// Single row displaying an existing [TaskLink] with open and remove actions inside [TaskEditorLinksSection].
class _TaskEditorLinkRow extends StatelessWidget {
  /// Creates a [_TaskEditorLinkRow].
  const _TaskEditorLinkRow({
    required this.index,
    required this.link,
    required this.onOpen,
    required this.onRemove,
  });

  /// Zero-based index of the link.
  final int index;

  /// Link item to display.
  final TaskLink link;

  /// Callback invoked when the open button is pressed.
  final VoidCallback onOpen;

  /// Callback invoked when the remove button is pressed.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);

    return Padding(
      key: ValueKey('editor_link_item_$index'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 18, color: appTheme.primaryAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
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
                  style: TextStyle(
                    color: appTheme.mutedTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('editor_open_link_$index'),
            visualDensity: VisualDensity.compact,
            tooltip: localizations.tooltipOpenLink,
            icon: Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: appTheme.primaryAccent,
            ),
            onPressed: onOpen,
          ),
          IconButton(
            key: ValueKey('editor_remove_link_$index'),
            visualDensity: VisualDensity.compact,
            tooltip: localizations.tooltipRemoveLink,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: appTheme.mutedTextColor,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
