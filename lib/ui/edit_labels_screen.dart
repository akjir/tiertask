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

import '../l10n/app_localizations.dart';
import '../models/task_board.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../providers/task_providers.dart';
import '../services/app_logger.dart';
import 'widgets/clearable_text_field.dart';
import 'widgets/condition_editor_controller.dart';
import 'widgets/label_color_picker_dialog.dart';
import 'widgets/task_editor_conditions_section.dart';
import 'widgets/task_editor_sections.dart';

/// Dedicated panel screen for editing all properties of an existing TDF `label` block (`name`, `color`, `note`, and `condition`).
class EditLabelScreen extends ConsumerStatefulWidget {
  /// Creates an [EditLabelScreen].
  const EditLabelScreen({super.key, required this.label});

  /// Label block to edit.
  final TdfLabel label;

  @override
  ConsumerState<EditLabelScreen> createState() => _EditLabelScreenState();
}

/// Overview screen for creating, deleting, and opening the editor panel for labels while displaying open task counts in alphabetical order.
class EditLabelsScreen extends ConsumerStatefulWidget {
  /// Creates an [EditLabelsScreen] widget.
  const EditLabelsScreen({super.key, this.autofocusCreate = false});

  /// Whether the create-label text field should request focus automatically when opened.
  final bool autofocusCreate;

  @override
  ConsumerState<EditLabelsScreen> createState() => _EditLabelsScreenState();
}

/// Leading clear/add icon button inside [_CreateLabelRow].
class _CreateLabelClearButton extends StatelessWidget {
  /// Creates a [_CreateLabelClearButton].
  const _CreateLabelClearButton({required this.hasText, required this.onClear});

  /// Whether the input field currently contains non-whitespace text.
  final bool hasText;

  /// Callback invoked when the clear button is pressed.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('create_label_clear_button'),
      tooltip: hasText ? localizations.actionCancel : localizations.actionAdd,
      icon: Icon(
        hasText ? Icons.close_rounded : Icons.add_rounded,
        color: colorScheme.onSurfaceVariant,
      ),
      onPressed: hasText ? onClear : null,
    );
  }
}

/// Top row inside [EditLabelsScreen] for creating a new label.
class _CreateLabelRow extends StatelessWidget {
  /// Creates a [_CreateLabelRow].
  const _CreateLabelRow({
    required this.autofocus,
    required this.controller,
    required this.hasText,
    required this.onClear,
    required this.onSubmit,
  });

  /// Whether the text field requests focus automatically.
  final bool autofocus;

  /// Controller for the new label name input.
  final TextEditingController controller;

  /// Whether the input field currently contains non-whitespace text.
  final bool hasText;

  /// Callback invoked when the leading clear or add icon is pressed.
  final VoidCallback onClear;

  /// Callback invoked when the new label is submitted.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _CreateLabelClearButton(hasText: hasText, onClear: onClear),
          const SizedBox(width: 8),
          Expanded(
            child: _CreateLabelTextField(
              autofocus: autofocus,
              controller: controller,
              onClear: onClear,
              onSubmit: onSubmit,
            ),
          ),
          IconButton(
            key: const ValueKey('create_label_submit_button'),
            tooltip: localizations.actionAdd,
            icon: Icon(
              Icons.check_rounded,
              color: hasText
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            onPressed: hasText ? onSubmit : null,
          ),
        ],
      ),
    );
  }
}

/// Text field inside [_CreateLabelRow] for entering a new label name.
class _CreateLabelTextField extends StatelessWidget {
  /// Creates a [_CreateLabelTextField].
  const _CreateLabelTextField({
    required this.autofocus,
    required this.controller,
    required this.onClear,
    required this.onSubmit,
  });

  /// Whether the text field requests focus automatically.
  final bool autofocus;

  /// Controller for the new label name input.
  final TextEditingController controller;

  /// Callback invoked when the input is cleared.
  final VoidCallback onClear;

  /// Callback invoked when the new label is submitted.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return ClearableTextField(
      fieldKey: const ValueKey('create_label_input'),
      controller: controller,
      autofocus: autofocus,
      cursorColor: colorScheme.primary,
      style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
      textInputAction: TextInputAction.done,
      onCleared: onClear,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        filled: false,
        hintText: localizations.createNewLabel,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
      ),
    );
  }
}

/// Scrollable card column inside [EditLabelScreen].
class _EditLabelForm extends StatelessWidget {
  /// Creates an [_EditLabelForm].
  const _EditLabelForm({
    required this.colorController,
    required this.colorErrorMessage,
    required this.conditionController,
    required this.isScoped,
    required this.nameController,
    required this.nameErrorMessage,
    required this.noteController,
    required this.onPickCustomColor,
    required this.onScopedChanged,
    required this.onSelectPresetColor,
    required this.onSubmit,
  });

  /// Controller for the hex color input.
  final TextEditingController colorController;

  /// Validation error message for the color input, if any.
  final String? colorErrorMessage;

  /// Controller for the label conditions editor.
  final ConditionEditorController conditionController;

  /// Whether the `scoped` modifier is enabled on the label.
  final bool isScoped;

  /// Controller for the label name input.
  final TextEditingController nameController;

  /// Validation error message for the label name input, if any.
  final String? nameErrorMessage;

  /// Controller for the label note input.
  final TextEditingController noteController;

  /// Callback invoked to open the custom color wheel dialog.
  final VoidCallback onPickCustomColor;

  /// Callback invoked when the `scoped` switch changes.
  final ValueChanged<bool> onScopedChanged;

  /// Callback invoked when a preset color swatch is selected.
  final ValueChanged<String> onSelectPresetColor;

  /// Callback invoked when the form is submitted.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TaskEditorDetailsCard(
            sectionTitle: localizations.labelDetailsSectionTitle,
            titleLabel: localizations.labelNameLabel,
            titleController: nameController,
            noteController: noteController,
            errorMessage: nameErrorMessage,
            onSubmit: onSubmit,
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: colorController,
            builder: (context, _, _) => LabelEditorColorCard(
              colorController: colorController,
              errorMessage: colorErrorMessage,
              onPickCustomColor: onPickCustomColor,
              onSelectPreset: onSelectPresetColor,
            ),
          ),
          const SizedBox(height: 10),
          _LabelScopedCard(isScoped: isScoped, onChanged: onScopedChanged),
          const SizedBox(height: 10),
          _LabelConditionsSection(controller: conditionController),
        ],
      ),
    );
  }
}

/// State for [EditLabelScreen].
class _EditLabelScreenState extends ConsumerState<EditLabelScreen> {
  late final TextEditingController _colorController;
  String? _colorErrorMessage;
  late final ConditionEditorController _conditionController;
  late bool _isScoped;
  late final TextEditingController _nameController;
  String? _nameErrorMessage;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    final label = widget.label;
    _nameController = TextEditingController(text: label.name);
    _noteController = TextEditingController(text: label.note ?? '');
    _colorController = TextEditingController(text: label.color ?? '');
    _isScoped = label.isScoped;
    _conditionController = ConditionEditorController(
      initialConditions: label.conditions,
      allowResets: false,
    );
    _nameController.addListener(_handleNameChanged);
    _colorController.addListener(_handleColorChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleNameChanged);
    _colorController.removeListener(_handleColorChanged);
    _nameController.dispose();
    _noteController.dispose();
    _colorController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('edit_label_screen'),
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(localizations.editLabelTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _EditLabelForm(
                colorController: _colorController,
                colorErrorMessage: _colorErrorMessage,
                conditionController: _conditionController,
                isScoped: _isScoped,
                nameController: _nameController,
                nameErrorMessage: _nameErrorMessage,
                noteController: _noteController,
                onPickCustomColor: _pickCustomColor,
                onScopedChanged: _handleScopedChanged,
                onSelectPresetColor: _selectPresetColor,
                onSubmit: _submit,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TaskEditorActionsRow(
                onCancel: () => Navigator.of(context).pop(),
                onSave: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Clears any color validation error when [_colorController] changes.
  void _handleColorChanged() {
    if (_colorErrorMessage == null) {
      return;
    }
    setState(() {
      _colorErrorMessage = null;
    });
  }

  /// Clears any name validation error when [_nameController] changes.
  void _handleNameChanged() {
    if (_nameErrorMessage == null) {
      return;
    }
    setState(() {
      _nameErrorMessage = null;
    });
  }

  /// Updates the `scoped` modifier state when toggled.
  void _handleScopedChanged(bool value) {
    setState(() {
      _isScoped = value;
    });
  }

  /// Opens [LabelColorPickerDialog] and populates [_colorController] with the selected `#RRGGBB` color.
  Future<void> _pickCustomColor() async {
    final selectedHex = await showLabelColorPickerDialog(
      context,
      initialHex: _colorController.text,
    );
    if (!mounted || selectedHex == null) {
      return;
    }
    setState(() {
      _colorController.text = selectedHex;
      _colorErrorMessage = null;
    });
  }

  /// Populates or clears [hex] in [_colorController] when a preset color chip is tapped.
  void _selectPresetColor(String hex) {
    final normalizedCurrent = TdfColor.normalizeHex(_colorController.text);
    setState(() {
      _colorController.text = normalizedCurrent == hex ? '' : hex;
      _colorErrorMessage = null;
    });
  }

  /// Validates the label inputs and persists the updated [TdfLabel].
  Future<void> _submit() async {
    final board =
        ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);
    final nameError = _validateName(board, localizations);
    if (nameError != null) {
      setState(() {
        _nameErrorMessage = nameError;
      });
      return;
    }

    final rawColor = _colorController.text.trim();
    final normalizedColor = TdfColor.normalizeHex(rawColor);
    if (rawColor.isNotEmpty && normalizedColor == null) {
      setState(() {
        _colorErrorMessage = localizations.labelColorErrorInvalid;
      });
      return;
    }

    final trimmedNote = _noteController.text.trim();
    await ref
        .read(taskNotifierProvider.notifier)
        .updateLabel(
          widget.label.id,
          name: _nameController.text.trim(),
          color: normalizedColor,
          clearColor: rawColor.isEmpty,
          note: trimmedNote.isEmpty ? null : trimmedNote,
          clearNote: trimmedNote.isEmpty,
          isScoped: _isScoped,
          conditions: _conditionController.buildConditions(),
        );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  /// Validates the entered label name against empty and duplicate constraints.
  String? _validateName(TaskBoard board, AppLocalizations localizations) {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) {
      return localizations.labelNameErrorEmpty;
    }
    if (board.hasDuplicateLabelName(
      trimmed,
      excludingLabelId: widget.label.id,
    )) {
      return localizations.labelNameErrorDuplicate;
    }
    return null;
  }
}

/// State for [EditLabelsScreen].
class _EditLabelsScreenState extends ConsumerState<EditLabelsScreen> {
  final TextEditingController _createController = TextEditingController();
  bool _hasCreateText = false;

  @override
  void initState() {
    super.initState();
    _createController.addListener(_handleCreateInputChanged);
  }

  @override
  void dispose() {
    _createController.removeListener(_handleCreateInputChanged);
    _createController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      key: const ValueKey('edit_labels_screen'),
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(localizations.editLabelsTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: theme.cardColor,
              child: _CreateLabelRow(
                autofocus: widget.autofocusCreate,
                controller: _createController,
                hasText: _hasCreateText,
                onClear: _clearCreateInput,
                onSubmit: _submitCreateLabel,
              ),
            ),
            Divider(height: 1, color: theme.scaffoldBackgroundColor),
            Expanded(
              child: _LabelsListSection(
                board: board,
                onDeleteLabel: _deleteLabel,
                sortedLabels: board.sortedLabels,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Clears the create-label input field.
  void _clearCreateInput() {
    _createController.clear();
  }

  /// Deletes the label with [labelId].
  Future<void> _deleteLabel(String labelId) async {
    await ref.read(taskNotifierProvider.notifier).deleteLabel(labelId);
  }

  /// Rebuilds when the non-whitespace state of [_createController] changes.
  void _handleCreateInputChanged() {
    final hasText = _createController.text.trim().isNotEmpty;
    if (hasText == _hasCreateText) {
      return;
    }
    setState(() {
      _hasCreateText = hasText;
    });
  }

  /// Creates a new label from [_createController] and clears the input field.
  Future<void> _submitCreateLabel() async {
    final trimmed = _createController.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _createController.clear();
    await ref.read(taskNotifierProvider.notifier).addLabel(trimmed);
  }
}

/// Single existing label row inside [EditLabelsScreen] with quick delete button, colored icon, title, open task count badge, and edit button.
class _EditableLabelRow extends StatelessWidget {
  /// Creates an [_EditableLabelRow].
  const _EditableLabelRow({
    super.key,
    required this.label,
    required this.openTaskCount,
    required this.onDelete,
    required this.onEdit,
  });

  /// Label displayed by this row.
  final TdfLabel label;

  /// Callback invoked when the delete icon button is tapped.
  final VoidCallback onDelete;

  /// Callback invoked when the edit icon button is tapped.
  final VoidCallback onEdit;

  /// Number of open tasks referencing [label].
  final int openTaskCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final variantColor = colorScheme.onSurfaceVariant;
    final iconColor = _resolveLabelColor(label.color, variantColor);
    return _LabelRowCard(
      child: Row(
        children: [
          IconButton(
            key: ValueKey('delete_label_button_${label.id}'),
            tooltip: AppLocalizations.of(context).tooltipDeleteLabel,
            icon: Icon(Icons.delete_outline_rounded, color: variantColor),
            onPressed: onDelete,
          ),
          Icon(Icons.label_outline_rounded, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label.name,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _EditableLabelTrailing(
            labelId: label.id,
            onEdit: onEdit,
            openTaskCount: openTaskCount,
          ),
        ],
      ),
    );
  }
}

/// Trailing open-task count badge and edit button inside [_EditableLabelRow].
class _EditableLabelTrailing extends StatelessWidget {
  /// Creates an [_EditableLabelTrailing].
  const _EditableLabelTrailing({
    required this.labelId,
    required this.onEdit,
    required this.openTaskCount,
  });

  /// Identifier of the label for widget keys.
  final String labelId;

  /// Callback invoked when the edit icon button is tapped.
  final VoidCallback onEdit;

  /// Number of open tasks referencing the label.
  final int openTaskCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Badge.count(
          key: ValueKey('edit_label_badge_$labelId'),
          count: openTaskCount,
        ),
        const SizedBox(width: 4),
        IconButton(
          key: ValueKey('edit_label_button_$labelId'),
          tooltip: localizations.tooltipEditLabel,
          icon: Icon(Icons.edit_outlined, color: colorScheme.onSurfaceVariant),
          onPressed: onEdit,
        ),
      ],
    );
  }
}

/// Empty-state message shown in [EditLabelsScreen] when no labels exist.
class _EmptyLabelsView extends StatelessWidget {
  /// Creates an [_EmptyLabelsView].
  const _EmptyLabelsView({required this.message});

  /// Localized empty-state message text.
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
        ),
      ),
    );
  }
}

/// Conditions editor section inside [EditLabelScreen] scoped to board locations.
class _LabelConditionsSection extends ConsumerWidget {
  /// Creates a [_LabelConditionsSection].
  const _LabelConditionsSection({required this.controller});

  /// Controller managing label activation conditions.
  final ConditionEditorController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final availableLocations = ref.watch(
      taskNotifierProvider.select(
        (asyncBoard) =>
            asyncBoard.asData?.value.sortedLocations ?? const <TdfLocation>[],
      ),
    );
    return TaskEditorConditionsSection(
      controller: controller,
      availableLocations: availableLocations,
      descriptionOverride: localizations.labelConditionsSectionDescription,
    );
  }
}

/// Rounded card container for an [_EditableLabelRow].
class _LabelRowCard extends StatelessWidget {
  /// Creates a [_LabelRowCard].
  const _LabelRowCard({required this.child});

  /// Row content displayed inside the card.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: child,
        ),
      ),
    );
  }
}

/// Card inside [EditLabelScreen] for toggling the TDF 0.6.0 `scoped` modifier on a label.
class _LabelScopedCard extends StatelessWidget {
  /// Creates a [_LabelScopedCard].
  const _LabelScopedCard({required this.isScoped, required this.onChanged});

  /// Whether the `scoped` modifier is enabled on the label.
  final bool isScoped;

  /// Callback invoked when the switch is toggled.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return TaskEditorSectionCard(
      cardKey: const ValueKey('label_editor_scoped_card'),
      icon: Icons.visibility_off_outlined,
      title: localizations.labelScopedSectionTitle,
      child: SwitchListTile(
        key: const ValueKey('label_editor_scoped_switch'),
        contentPadding: EdgeInsets.zero,
        title: Text(localizations.labelScopedSwitchTitle),
        subtitle: Text(localizations.labelScopedSwitchSubtitle),
        value: isScoped,
        onChanged: onChanged,
      ),
    );
  }
}

/// Body list inside [EditLabelsScreen] rendering either [_EmptyLabelsView] or the alphabetical label rows.
class _LabelsListSection extends StatelessWidget {
  /// Creates a [_LabelsListSection].
  const _LabelsListSection({
    required this.board,
    required this.onDeleteLabel,
    required this.sortedLabels,
  });

  /// Active task board used to compute open task counts per label.
  final TaskBoard board;

  /// Callback invoked when a label row's delete button is pressed.
  final ValueChanged<String> onDeleteLabel;

  /// Alphabetically sorted labels to display.
  final List<TdfLabel> sortedLabels;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (sortedLabels.isEmpty) {
      return _EmptyLabelsView(message: localizations.emptyLabelsHint);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedLabels.length,
      itemBuilder: (context, index) {
        final label = sortedLabels[index];
        return _EditableLabelRow(
          key: ValueKey('edit_label_row_${label.id}'),
          label: label,
          openTaskCount: board.openTaskCountForLabel(label.id),
          onDelete: () => onDeleteLabel(label.id),
          onEdit: () => openEditLabelScreen(context, label: label),
        );
      },
    );
  }
}

/// Pushes [EditLabelScreen] onto the navigation stack to edit [label].
Future<void> openEditLabelScreen(
  BuildContext context, {
  required TdfLabel label,
}) {
  AppLogger.info(LogTag.ui, 'Opened EditLabelScreen label=${label.id}');
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => EditLabelScreen(label: label)),
  );
}

/// Resolves the optional `#RRGGBB` color of [rawHex] or falls back to [fallback].
Color _resolveLabelColor(String? rawHex, Color fallback) {
  final parsed = TdfColor.tryParseArgb(rawHex);
  return parsed != null ? Color(parsed) : fallback;
}
