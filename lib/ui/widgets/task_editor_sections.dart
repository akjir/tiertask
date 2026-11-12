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

/// Card inside `EditLabelScreen` for editing a label's optional `#RRGGBB` color via hex text input, custom color wheel dialog, or preset swatches.
class LabelEditorColorCard extends StatelessWidget {
  /// Creates a [LabelEditorColorCard].
  const LabelEditorColorCard({
    super.key,
    required this.colorController,
    required this.errorMessage,
    required this.onPickCustomColor,
    required this.onSelectPreset,
  });

  /// Preset `#RRGGBB` color swatches offered for quick selection.
  static const List<String> presetHexColors = <String>[
    '#2196F3',
    '#4CAF50',
    '#FF9100',
    '#E91E63',
    '#9C27B0',
    '#00BCD4',
    '#EB06FF',
    '#00E5FF',
  ];

  /// Controller for the `#RRGGBB` hexadecimal color input field.
  final TextEditingController colorController;

  /// Optional validation error message for the color input field.
  final String? errorMessage;

  /// Callback invoked when the custom color wheel button is tapped.
  final VoidCallback onPickCustomColor;

  /// Callback invoked when a preset color chip is tapped.
  final ValueChanged<String> onSelectPreset;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    final normalizedCurrent = TdfColor.normalizeHex(colorController.text);
    final previewColor = _resolveHexColor(
      normalizedCurrent,
      appTheme.mutedTextColor,
    );

    return TaskEditorSectionCard(
      cardKey: const ValueKey('label_editor_color_card'),
      icon: Icons.palette_outlined,
      title: localizations.labelColorSectionTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabelColorInputRow(
            colorController: colorController,
            errorMessage: errorMessage,
            previewColor: previewColor,
            onPickCustomColor: onPickCustomColor,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final hex in presetHexColors)
                TaskEditorChip(
                  chipKey: ValueKey('label_editor_color_preset_$hex'),
                  icon: Icons.palette_rounded,
                  label: hex,
                  isSelected: normalizedCurrent == hex,
                  accentColor: _resolveHexColor(hex, appTheme.primaryAccent),
                  onTap: () => onSelectPreset(hex),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Footer row inside the task editor containing Cancel, optional Delete, and Save actions.
class TaskEditorActionsRow extends StatelessWidget {
  /// Creates a [TaskEditorActionsRow].
  const TaskEditorActionsRow({
    super.key,
    required this.onCancel,
    this.onDelete,
    required this.onSave,
  });

  /// Callback invoked when Cancel is pressed.
  final VoidCallback onCancel;

  /// Optional callback invoked when Delete is pressed.
  final VoidCallback? onDelete;

  /// Callback invoked when Save is pressed.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: [
        if (onDelete case final deleteCallback?) ...[
          Expanded(child: _DeleteTaskActionButton(onPressed: deleteCallback)),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('task_editor_cancel_button'),
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            label: Text(
              localizations.actionCancel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            key: const ValueKey('task_editor_save_button'),
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              localizations.actionSave,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

/// Selectable chip used for labels, prerequisites, conditions, and mode toggles inside the task editor.
class TaskEditorChip extends StatelessWidget {
  /// Creates a [TaskEditorChip].
  const TaskEditorChip({
    super.key,
    required this.accentColor,
    required this.chipKey,
    required this.icon,
    required this.isSelected,
    required this.label,
    required this.onTap,
    this.isEnabled = true,
    this.tooltip,
  });

  /// Highlight color when selected.
  final Color accentColor;

  /// Deterministic widget key for the chip.
  final Key chipKey;

  /// Leading icon displayed inside the chip.
  final IconData icon;

  /// Whether this chip accepts user interaction.
  final bool isEnabled;

  /// Whether this chip is currently active.
  final bool isSelected;

  /// Text label displayed inside the chip.
  final String label;

  /// Callback invoked when the chip is tapped.
  final VoidCallback onTap;

  /// Optional tooltip displayed on hover or long press.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mutedColor = colorScheme.onSurfaceVariant;
    final canvasColor = theme.scaffoldBackgroundColor;

    return FilterChip(
      key: chipKey,
      tooltip: tooltip,
      selected: isSelected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected || isEnabled
            ? accentColor
            : mutedColor.withValues(alpha: 0.4),
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? colorScheme.onSurface
              : (isEnabled ? mutedColor : mutedColor.withValues(alpha: 0.4)),
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      backgroundColor: canvasColor,
      disabledColor: canvasColor.withValues(alpha: 0.5),
      selectedColor: accentColor.withValues(alpha: 0.22),
      side: BorderSide(
        color: isSelected
            ? accentColor
            : mutedColor.withValues(alpha: isEnabled ? 0.35 : 0.15),
      ),
      onSelected: isEnabled ? (_) => onTap() : null,
    );
  }
}

/// Multi-select label chip card inside the task editor.
class TaskEditorContextSection extends StatelessWidget {
  /// Creates a [TaskEditorContextSection].
  const TaskEditorContextSection({
    super.key,
    required this.labels,
    required this.selectedLabelIds,
    required this.onToggleLabel,
  });

  /// Available labels on the board.
  final List<TdfLabel> labels;

  /// Callback invoked when a label chip is tapped.
  final ValueChanged<String> onToggleLabel;

  /// Selected label IDs.
  final Set<String> selectedLabelIds;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return TaskEditorSectionCard(
      cardKey: const ValueKey('task_editor_labels_card'),
      icon: Icons.label_outline_rounded,
      title: localizations.taskLabelsSectionTitle,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final label in labels)
            TaskEditorChip(
              chipKey: ValueKey('task_editor_label_${label.id}'),
              icon: Icons.label_outline_rounded,
              label: label.name,
              isSelected: selectedLabelIds.contains(label.id),
              accentColor: _resolveHexColor(label.color, colorScheme.primary),
              onTap: () => onToggleLabel(label.id),
            ),
        ],
      ),
    );
  }
}

/// Card grouping the title/name and optional note fields inside the task and label editors.
class TaskEditorDetailsCard extends StatelessWidget {
  /// Creates a [TaskEditorDetailsCard].
  const TaskEditorDetailsCard({
    super.key,
    required this.errorMessage,
    required this.noteController,
    required this.titleController,
    required this.onSubmit,
    this.sectionTitle,
    this.titleLabel,
  });

  /// Optional validation error message for the title/name field.
  final String? errorMessage;

  /// Controller for the optional note input.
  final TextEditingController noteController;

  /// Callback invoked when submitting from the title input field.
  final VoidCallback onSubmit;

  /// Optional custom section card title (defaults to [AppLocalizations.taskDetailsSectionTitle]).
  final String? sectionTitle;

  /// Controller for the title/name input.
  final TextEditingController titleController;

  /// Optional custom label text for the title field (defaults to [AppLocalizations.taskNameLabel]).
  final String? titleLabel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return TaskEditorSectionCard(
      cardKey: const ValueKey('task_editor_details_card'),
      icon: Icons.edit_note_rounded,
      title: sectionTitle ?? localizations.taskDetailsSectionTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TaskEditorTitleField(
            controller: titleController,
            errorMessage: errorMessage,
            titleLabel: titleLabel,
            onSubmit: onSubmit,
          ),
          const SizedBox(height: 8),
          TaskEditorNoteField(controller: noteController),
        ],
      ),
    );
  }
}

/// Optional task note input field inside the task editor.
class TaskEditorNoteField extends StatelessWidget {
  /// Creates a [TaskEditorNoteField].
  const TaskEditorNoteField({super.key, required this.controller});

  /// Controller for the note input.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return ClearableTextField(
      fieldKey: const ValueKey('task_editor_note_input'),
      controller: controller,
      cursorColor: appTheme.tertiaryAccent,
      clearIconColor: appTheme.mutedTextColor,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      minLines: 1,
      maxLines: 3,
      decoration: _buildTaskEditorInputDecoration(
        appTheme: appTheme,
        focusedColor: appTheme.tertiaryAccent,
        labelText: localizations.taskNoteLabel,
        hintText: localizations.taskNoteHint,
      ),
    );
  }
}

/// Shared Material 3 card container matching the section groupings on `SettingsScreen`.
class TaskEditorSectionCard extends StatelessWidget {
  /// Creates a [TaskEditorSectionCard].
  const TaskEditorSectionCard({
    super.key,
    required this.cardKey,
    required this.icon,
    required this.title,
    this.description,
    this.child,
    this.trailing,
  });

  /// Deterministic widget key for the card.
  final Key cardKey;

  /// Optional interactive content below the header or description.
  final Widget? child;

  /// Optional section subtitle description.
  final String? description;

  /// Leading header icon.
  final IconData icon;

  /// Section title text.
  final String title;

  /// Optional widget rendered on the right side of the header row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bodyChild = child;
    final subtitleText = description;

    return Card(
      key: cardKey,
      margin: EdgeInsets.zero,
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderRow(theme, colorScheme),
            if (subtitleText != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitleText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (bodyChild != null) ...[const SizedBox(height: 8), bodyChild],
          ],
        ),
      ),
    );
  }

  /// Builds the icon, title, and optional trailing widget row at the top of the card.
  Widget _buildHeaderRow(ThemeData theme, ColorScheme colorScheme) {
    final headerTrailing = trailing;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (headerTrailing != null) ...[
          const SizedBox(width: 8),
          headerTrailing,
        ],
      ],
    );
  }
}

/// Title/name input field with inline validation error display inside the task and label editors.
class TaskEditorTitleField extends StatelessWidget {
  /// Creates a [TaskEditorTitleField].
  const TaskEditorTitleField({
    super.key,
    required this.controller,
    required this.errorMessage,
    required this.onSubmit,
    this.titleLabel,
  });

  /// Controller for the title/name input.
  final TextEditingController controller;

  /// Optional validation error message.
  final String? errorMessage;

  /// Callback invoked when the user submits from the keyboard.
  final VoidCallback onSubmit;

  /// Optional custom label text (defaults to [AppLocalizations.taskNameLabel]).
  final String? titleLabel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return ClearableTextField(
      fieldKey: const ValueKey('task_editor_title_input'),
      controller: controller,
      autofocus: true,
      cursorColor: appTheme.primaryAccent,
      clearIconColor: appTheme.mutedTextColor,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 15),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: _buildTaskEditorInputDecoration(
        appTheme: appTheme,
        focusedColor: appTheme.primaryAccent,
        labelText: titleLabel ?? localizations.taskNameLabel,
        errorText: errorMessage,
      ),
    );
  }
}

/// Destructive Delete action button inside [TaskEditorActionsRow].
class _DeleteTaskActionButton extends StatelessWidget {
  /// Creates a [_DeleteTaskActionButton].
  const _DeleteTaskActionButton({required this.onPressed});

  /// Callback invoked when the Delete button is pressed.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      key: const ValueKey('task_editor_delete_button'),
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.error,
        side: BorderSide(color: colorScheme.error),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.delete_outline_rounded),
      label: Text(
        localizations.actionDelete,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Row combining the `#RRGGBB` hexadecimal text field and the custom color wheel trigger button inside [LabelEditorColorCard].
class _LabelColorInputRow extends StatelessWidget {
  /// Creates a [_LabelColorInputRow].
  const _LabelColorInputRow({
    required this.colorController,
    required this.errorMessage,
    required this.onPickCustomColor,
    required this.previewColor,
  });

  /// Controller for the `#RRGGBB` hexadecimal color input field.
  final TextEditingController colorController;

  /// Optional validation error message for the color input field.
  final String? errorMessage;

  /// Callback invoked when the custom color wheel button is tapped.
  final VoidCallback onPickCustomColor;

  /// Resolved preview color for the leading dot and color wheel icon.
  final Color previewColor;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClearableTextField(
            fieldKey: const ValueKey('label_editor_color_input'),
            controller: colorController,
            cursorColor: appTheme.primaryAccent,
            clearIconColor: appTheme.mutedTextColor,
            style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
            decoration: _buildTaskEditorInputDecoration(
              appTheme: appTheme,
              focusedColor: appTheme.primaryAccent,
              labelText: localizations.labelColorSectionTitle,
              hintText: localizations.labelColorHint,
              errorText: errorMessage,
              prefixIcon: Icon(
                Icons.circle_rounded,
                size: 16,
                color: previewColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          key: const ValueKey('label_editor_color_wheel_button'),
          style: IconButton.styleFrom(
            backgroundColor: appTheme.secondaryContainerColor,
            foregroundColor: appTheme.onSecondaryContainerColor,
          ),
          tooltip: localizations.tooltipPickCustomColor,
          onPressed: onPickCustomColor,
          icon: Icon(Icons.color_lens_rounded, color: previewColor),
        ),
      ],
    );
  }
}

/// Builds a shared [InputDecoration] for task and label editor text fields.
InputDecoration _buildTaskEditorInputDecoration({
  required AppTheme appTheme,
  required Color focusedColor,
  required String labelText,
  String? hintText,
  String? errorText,
  Widget? prefixIcon,
}) {
  final borderRadius = BorderRadius.circular(14);
  final defaultBorder = OutlineInputBorder(
    borderRadius: borderRadius,
    borderSide: BorderSide(
      color: appTheme.mutedTextColor.withValues(alpha: 0.35),
    ),
  );
  return InputDecoration(
    labelText: labelText,
    labelStyle: TextStyle(color: appTheme.mutedTextColor),
    hintText: hintText,
    hintStyle: hintText != null
        ? TextStyle(color: appTheme.mutedTextColor)
        : null,
    errorText: errorText,
    prefixIcon: prefixIcon,
    isDense: true,
    filled: true,
    fillColor: appTheme.canvasColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: defaultBorder,
    enabledBorder: defaultBorder,
    focusedBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: focusedColor, width: 1.6),
    ),
  );
}

/// Resolves a `#RRGGBB` color string or falls back to [fallback].
Color _resolveHexColor(String? rawHex, Color fallback) {
  final parsed = TdfColor.tryParseArgb(rawHex);
  return parsed != null ? Color(parsed) : fallback;
}
