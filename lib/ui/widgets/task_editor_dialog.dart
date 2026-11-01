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
import '../../l10n/tier_localization_extension.dart';
import '../../models/task_board.dart';
import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/task_providers.dart';
import 'quick_add_bar.dart';

const Color _accentBlue = Color(0xFF2196F3);
const Color _accentCyan = Color(0xFF00E5FF);
const Color _accentMagenta = Color(0xFFEB06FF);
const Color _canvasColor = Color(0xFF344FA1);
const Color _cardColor = Color(0xFF071A52);
const Color _mutedLabelColor = Color(0xFF9BA8E5);

/// Shared modal dialog used for both extended task creation and editing an existing task.
class TaskEditorDialog extends ConsumerStatefulWidget {
  /// Creates a [TaskEditorDialog].
  const TaskEditorDialog({
    super.key,
    this.initialTask,
    this.initialTitle = '',
    this.initialMode = QuickAddMode.standard,
    this.initialLabelIds = const <String>{},
    this.onSubmitted,
  });

  /// Initial label IDs pre-selected when opening in creation mode.
  final Set<String> initialLabelIds;

  /// Initial scheduling mode when opening in creation mode.
  final QuickAddMode initialMode;

  /// Existing task to edit, or `null` when creating a new task.
  final TaskItem? initialTask;

  /// Initial draft title when opening in creation mode.
  final String initialTitle;

  /// Optional callback invoked after a task is created or updated.
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

/// Footer row inside [TaskEditorDialog] containing Cancel and Save actions.
class _TaskEditorActionsRow extends StatelessWidget {
  /// Creates a [_TaskEditorActionsRow].
  const _TaskEditorActionsRow({required this.onCancel, required this.onSave});

  /// Callback invoked when Cancel is pressed.
  final VoidCallback onCancel;

  /// Callback invoked when Save is pressed.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          key: const ValueKey('task_editor_cancel_button'),
          style: TextButton.styleFrom(foregroundColor: _mutedLabelColor),
          onPressed: onCancel,
          child: Text(localizations.actionCancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('task_editor_save_button'),
          style: FilledButton.styleFrom(
            backgroundColor: _accentMagenta,
            foregroundColor: Colors.white,
          ),
          onPressed: onSave,
          child: Text(localizations.actionSave),
        ),
      ],
    );
  }
}

/// Scrollable form content inside [TaskEditorDialog].
class _TaskEditorBody extends StatelessWidget {
  /// Creates a [_TaskEditorBody].
  const _TaskEditorBody({
    required this.errorMessage,
    required this.hasSubtaskText,
    required this.labels,
    required this.mode,
    required this.noteController,
    required this.selectedLabelIds,
    required this.subtaskController,
    required this.subtasks,
    required this.subtasksAutoFinish,
    required this.titleController,
    required this.onAddSubtask,
    required this.onRemoveSubtask,
    required this.onSubmit,
    required this.onToggleAutoFinish,
    required this.onToggleLabel,
    required this.onTogglePriority,
    required this.onToggleSomeday,
    required this.onToggleSubtaskStep,
  });

  /// Validation error message for the task title, or `null` when valid.
  final String? errorMessage;

  /// Whether the subtask input field contains non-whitespace text.
  final bool hasSubtaskText;

  /// Available labels on the board.
  final List<TdfLabel> labels;

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// Controller for the optional note input field.
  final TextEditingController noteController;

  /// Callback to append a new subtask step.
  final VoidCallback onAddSubtask;

  /// Callback to remove the subtask step at the given index.
  final ValueChanged<int> onRemoveSubtask;

  /// Callback to submit the form.
  final VoidCallback onSubmit;

  /// Callback to toggle `subtasks auto-finish`.
  final VoidCallback onToggleAutoFinish;

  /// Callback to toggle selection of a label ID.
  final ValueChanged<String> onToggleLabel;

  /// Callback to toggle Priority mode.
  final VoidCallback onTogglePriority;

  /// Callback to toggle Someday mode.
  final VoidCallback onToggleSomeday;

  /// Callback to toggle completion of the subtask step at the given index.
  final ValueChanged<int> onToggleSubtaskStep;

  /// Selected label IDs.
  final Set<String> selectedLabelIds;

  /// Controller for the subtask input field.
  final TextEditingController subtaskController;

  /// Ordered subtask steps.
  final List<SubtaskItem> subtasks;

  /// Whether `subtasks auto-finish` is enabled.
  final bool subtasksAutoFinish;

  /// Controller for the task title input field.
  final TextEditingController titleController;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TaskEditorTitleField(
              controller: titleController,
              errorMessage: errorMessage,
              onSubmit: onSubmit,
            ),
            const SizedBox(height: 8),
            _TaskEditorNoteField(controller: noteController),
            const SizedBox(height: 8),
            _TaskEditorModeRow(
              mode: mode,
              onTogglePriority: onTogglePriority,
              onToggleSomeday: onToggleSomeday,
            ),
            _TaskEditorContextSection(
              labels: labels,
              selectedLabelIds: selectedLabelIds,
              onToggleLabel: onToggleLabel,
            ),
            const SizedBox(height: 8),
            _TaskEditorSubtasksSection(
              hasSubtaskText: hasSubtaskText,
              subtaskController: subtaskController,
              subtasks: subtasks,
              subtasksAutoFinish: subtasksAutoFinish,
              onAddSubtask: onAddSubtask,
              onRemoveSubtask: onRemoveSubtask,
              onToggleAutoFinish: onToggleAutoFinish,
              onToggleSubtaskStep: onToggleSubtaskStep,
            ),
          ],
        ),
      ),
    );
  }
}

/// Selectable chip used for labels and mode toggles inside [TaskEditorDialog].
class _TaskEditorChip extends StatelessWidget {
  /// Creates a [_TaskEditorChip].
  const _TaskEditorChip({
    required this.accentColor,
    required this.chipKey,
    required this.icon,
    required this.isSelected,
    required this.label,
    required this.onTap,
  });

  /// Highlight color when selected.
  final Color accentColor;

  /// Deterministic widget key for the chip.
  final Key chipKey;

  /// Leading icon displayed inside the chip.
  final IconData icon;

  /// Whether this chip is currently active.
  final bool isSelected;

  /// Text label displayed inside the chip.
  final String label;

  /// Callback invoked when the chip is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      key: chipKey,
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : accentColor,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : _mutedLabelColor,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      backgroundColor: _canvasColor,
      selectedColor: accentColor,
      side: BorderSide(
        color: isSelected
            ? accentColor
            : _mutedLabelColor.withValues(alpha: 0.35),
      ),
      onSelected: (_) => onTap(),
    );
  }
}

/// Multi-select label chip group inside [TaskEditorDialog].
class _TaskEditorContextSection extends StatelessWidget {
  /// Creates a [_TaskEditorContextSection].
  const _TaskEditorContextSection({
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          localizations.sectionLabels,
          style: const TextStyle(
            color: _mutedLabelColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final label in labels)
              _TaskEditorChip(
                chipKey: ValueKey('task_editor_label_${label.id}'),
                icon: Icons.label_outline_rounded,
                label: label.name,
                isSelected: selectedLabelIds.contains(label.id),
                accentColor: _resolveColor(label.color, _accentMagenta),
                onTap: () => onToggleLabel(label.id),
              ),
          ],
        ),
      ],
    );
  }

  /// Resolves a `#RRGGBB` color string or falls back to [fallback].
  Color _resolveColor(String? rawHex, Color fallback) {
    final parsed = TdfColor.tryParseArgb(rawHex);
    return parsed != null ? Color(parsed) : fallback;
  }
}

/// State for [TaskEditorDialog].
class _TaskEditorDialogState extends ConsumerState<TaskEditorDialog> {
  String? _errorMessage;
  late QuickAddMode _mode;
  late final TextEditingController _noteController;
  late final Set<String> _selectedLabelIds;
  final TextEditingController _subtaskController = TextEditingController();
  late final List<SubtaskItem> _subtasks;
  late bool _subtasksAutoFinish;
  late final TextEditingController _titleController;

  bool get _hasSubtaskText => _subtaskController.text.trim().isNotEmpty;

  bool get _isEditMode => widget.initialTask != null;

  @override
  void initState() {
    super.initState();
    final task = widget.initialTask;
    _titleController = TextEditingController(
      text: task?.title ?? widget.initialTitle,
    );
    _noteController = TextEditingController(text: task?.note ?? '');
    _mode = task != null ? _resolveInitialMode(task) : widget.initialMode;
    _selectedLabelIds = <String>{
      ...(task != null ? task.labelIds : widget.initialLabelIds),
    };
    _subtasksAutoFinish = task?.subtasksAutoFinish ?? false;
    _subtasks = <SubtaskItem>[if (task != null) ...task.subtasks];

    _titleController.addListener(_handleTitleChanged);
    _subtaskController.addListener(_handleSubtaskInputChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
    _subtaskController.removeListener(_handleSubtaskInputChanged);
    _titleController.dispose();
    _noteController.dispose();
    _subtaskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);
    final headerTitle = _isEditMode
        ? localizations.editTaskTitle
        : localizations.advancedTaskTitle;

    return Dialog(
      key: const ValueKey('task_editor_dialog'),
      backgroundColor: _cardColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: _canvasColor, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TaskEditorHeader(
                title: headerTitle,
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 8),
              _TaskEditorBody(
                errorMessage: _errorMessage,
                hasSubtaskText: _hasSubtaskText,
                labels: board.labels,
                mode: _mode,
                noteController: _noteController,
                selectedLabelIds: _selectedLabelIds,
                subtaskController: _subtaskController,
                subtasks: _subtasks,
                subtasksAutoFinish: _subtasksAutoFinish,
                titleController: _titleController,
                onAddSubtask: _addSubtask,
                onRemoveSubtask: _removeSubtask,
                onSubmit: _submit,
                onToggleAutoFinish: _toggleAutoFinish,
                onToggleLabel: _toggleLabel,
                onTogglePriority: _togglePriority,
                onToggleSomeday: _toggleSomeday,
                onToggleSubtaskStep: _toggleSubtaskStep,
              ),
              const SizedBox(height: 12),
              _TaskEditorActionsRow(
                onCancel: () => Navigator.of(context).pop(),
                onSave: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Appends the current non-empty subtask text to [_subtasks].
  void _addSubtask() {
    final text = _subtaskController.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _subtasks.add(SubtaskItem(title: text));
      _subtaskController.clear();
    });
  }

  /// Collects selected label IDs in canonical board declaration order.
  List<String> _collectOrderedLabelIds(TaskBoard board) {
    return <String>[
      for (final label in board.labels)
        if (_selectedLabelIds.contains(label.id)) label.id,
    ];
  }

  /// Rebuilds when the subtask input field text changes.
  void _handleSubtaskInputChanged() {
    setState(() {});
  }

  /// Clears any validation error when the user edits the title field.
  void _handleTitleChanged() {
    if (_errorMessage == null) {
      return;
    }
    setState(() {
      _errorMessage = null;
    });
  }

  /// Persists the created or edited task through [TaskNotifier].
  Future<void> _persistTask(
    TaskBoard board,
    String title,
    List<SubtaskItem> subtasks,
  ) async {
    final labelIds = _collectOrderedLabelIds(board);
    final noteText = _noteController.text.trim();
    final notifier = ref.read(taskNotifierProvider.notifier);

    if (widget.initialTask case final existingTask?) {
      await notifier.updateTask(
        existingTask.id,
        title: title,
        note: noteText,
        targetTier: _mode.targetTier,
        isPriority: _mode == QuickAddMode.priority,
        subtasksAutoFinish: _subtasksAutoFinish,
        subtasks: subtasks,
        labelIds: labelIds,
      );
      return;
    }

    await notifier.addTask(
      title,
      note: noteText.isEmpty ? null : noteText,
      targetTier: _mode.targetTier,
      isPriority: _mode == QuickAddMode.priority,
      subtasksAutoFinish: _subtasksAutoFinish,
      subtasks: subtasks,
      labelIds: labelIds,
    );
  }

  /// Removes the subtask step at [index].
  void _removeSubtask(int index) {
    setState(() {
      _subtasks.removeAt(index);
    });
  }

  /// Derives the initial [QuickAddMode] for an existing [task].
  static QuickAddMode _resolveInitialMode(TaskItem task) {
    if (task.isPriority) {
      return QuickAddMode.priority;
    }
    if (task.queuedAt == null && !task.isCompleted) {
      return QuickAddMode.someday;
    }
    return QuickAddMode.standard;
  }

  /// Validates the task title and saves the created or updated task.
  Future<void> _submit() async {
    final board =
        ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);
    final validationError = _validateTitle(board, localizations);
    if (validationError != null) {
      setState(() {
        _errorMessage = validationError;
      });
      return;
    }

    final pendingSubtask = _subtaskController.text.trim();
    final effectiveSubtasks = <SubtaskItem>[
      ..._subtasks,
      if (pendingSubtask.isNotEmpty) SubtaskItem(title: pendingSubtask),
    ];

    await _persistTask(board, _titleController.text.trim(), effectiveSubtasks);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    widget.onSubmitted?.call();
  }

  /// Toggles the `subtasks auto-finish` option.
  void _toggleAutoFinish() {
    setState(() {
      _subtasksAutoFinish = !_subtasksAutoFinish;
    });
  }

  /// Toggles selection of [labelId].
  void _toggleLabel(String labelId) {
    setState(() {
      if (!_selectedLabelIds.remove(labelId)) {
        _selectedLabelIds.add(labelId);
      }
    });
  }

  /// Toggles Priority mode on or off.
  void _togglePriority() {
    setState(() {
      _mode = _mode == QuickAddMode.priority
          ? QuickAddMode.standard
          : QuickAddMode.priority;
    });
  }

  /// Toggles Someday mode on or off.
  void _toggleSomeday() {
    setState(() {
      _mode = _mode == QuickAddMode.someday
          ? QuickAddMode.standard
          : QuickAddMode.someday;
    });
  }

  /// Toggles completion state of the subtask step at [index].
  void _toggleSubtaskStep(int index) {
    final current = _subtasks[index];
    setState(() {
      _subtasks[index] = current.copyWith(isCompleted: !current.isCompleted);
    });
  }

  /// Validates the entered task title against empty and duplicate constraints.
  String? _validateTitle(TaskBoard board, AppLocalizations localizations) {
    final trimmed = _titleController.text.trim();
    if (trimmed.isEmpty) {
      return localizations.taskNameErrorEmpty;
    }
    if (board.hasDuplicateTaskTitle(
      trimmed,
      excludingTaskId: widget.initialTask?.id,
    )) {
      return localizations.taskNameErrorDuplicate;
    }
    return null;
  }
}

/// Header row inside [TaskEditorDialog] displaying the dialog title and close button.
class _TaskEditorHeader extends StatelessWidget {
  /// Creates a [_TaskEditorHeader].
  const _TaskEditorHeader({required this.title, required this.onClose});

  /// Callback invoked when the close button is pressed.
  final VoidCallback onClose;

  /// Dialog header title text.
  final String title;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: localizations.actionClose,
          icon: const Icon(Icons.close_rounded, color: _mutedLabelColor),
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// Row of mutually exclusive Priority and Someday chips inside [TaskEditorDialog].
class _TaskEditorModeRow extends StatelessWidget {
  /// Creates a [_TaskEditorModeRow].
  const _TaskEditorModeRow({
    required this.mode,
    required this.onTogglePriority,
    required this.onToggleSomeday,
  });

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// Callback invoked when Priority is tapped.
  final VoidCallback onTogglePriority;

  /// Callback invoked when Someday is tapped.
  final VoidCallback onToggleSomeday;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _TaskEditorChip(
          chipKey: const ValueKey('task_editor_priority_button'),
          icon: Icons.bolt_rounded,
          label: localizations.quickAddPriority,
          isSelected: mode == QuickAddMode.priority,
          accentColor: _accentMagenta,
          onTap: onTogglePriority,
        ),
        _TaskEditorChip(
          chipKey: const ValueKey('task_editor_someday_button'),
          icon: Icons.lightbulb_outline_rounded,
          label: localizations.tierName(TaskTier.someday),
          isSelected: mode == QuickAddMode.someday,
          accentColor: _accentBlue,
          onTap: onToggleSomeday,
        ),
      ],
    );
  }
}

/// Optional task note input field inside [TaskEditorDialog].
class _TaskEditorNoteField extends StatelessWidget {
  /// Creates a [_TaskEditorNoteField].
  const _TaskEditorNoteField({required this.controller});

  /// Controller for the note input.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: _mutedLabelColor.withValues(alpha: 0.35)),
    );

    return TextField(
      key: const ValueKey('task_editor_note_input'),
      controller: controller,
      cursorColor: _accentCyan,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      minLines: 1,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: localizations.taskNoteLabel,
        labelStyle: const TextStyle(color: _mutedLabelColor),
        hintText: localizations.taskNoteHint,
        hintStyle: const TextStyle(color: _mutedLabelColor),
        isDense: true,
        filled: true,
        fillColor: _canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: _accentCyan, width: 1.6),
        ),
      ),
    );
  }
}

/// Input row for adding a subtask step inside [_TaskEditorSubtasksSection].
class _TaskEditorSubtaskInputRow extends StatelessWidget {
  /// Creates a [_TaskEditorSubtaskInputRow].
  const _TaskEditorSubtaskInputRow({
    required this.controller,
    required this.hasText,
    required this.onAddSubtask,
  });

  /// Controller for the subtask input field.
  final TextEditingController controller;

  /// Whether the input field currently contains non-whitespace text.
  final bool hasText;

  /// Callback invoked when the add subtask button or Enter key is pressed.
  final VoidCallback onAddSubtask;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: _mutedLabelColor.withValues(alpha: 0.35)),
    );

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('task_editor_subtask_input'),
            controller: controller,
            cursorColor: _accentCyan,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onAddSubtask(),
            decoration: InputDecoration(
              hintText: localizations.subtaskInputHint,
              hintStyle: const TextStyle(color: _mutedLabelColor),
              isDense: true,
              filled: true,
              fillColor: _canvasColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: defaultBorder,
              enabledBorder: defaultBorder,
              focusedBorder: OutlineInputBorder(
                borderRadius: borderRadius,
                borderSide: const BorderSide(color: _accentCyan, width: 1.6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          key: const ValueKey('task_editor_subtask_add_button'),
          style: IconButton.styleFrom(
            backgroundColor: _accentBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _canvasColor.withValues(alpha: 0.55),
            disabledForegroundColor: _mutedLabelColor.withValues(alpha: 0.6),
          ),
          tooltip: localizations.tooltipAddSubtask,
          onPressed: hasText ? onAddSubtask : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// Single subtask row inside [_TaskEditorSubtasksSection] with completion toggle and remove action.
class _TaskEditorSubtaskRow extends StatelessWidget {
  /// Creates a [_TaskEditorSubtaskRow].
  const _TaskEditorSubtaskRow({
    required this.index,
    required this.subtask,
    required this.onRemove,
    required this.onToggle,
  });

  /// Zero-based index of [subtask].
  final int index;

  /// Callback to remove this subtask.
  final VoidCallback onRemove;

  /// Callback to toggle completion of this subtask.
  final VoidCallback onToggle;

  /// Subtask item to display.
  final SubtaskItem subtask;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          InkWell(
            key: ValueKey('task_editor_toggle_subtask_$index'),
            borderRadius: BorderRadius.circular(12),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                subtask.isCompleted
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: subtask.isCompleted ? _accentCyan : _mutedLabelColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtask.title,
              style: TextStyle(
                color: subtask.isCompleted ? _mutedLabelColor : Colors.white,
                decoration: subtask.isCompleted
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
          IconButton(
            key: ValueKey('task_editor_remove_subtask_$index'),
            visualDensity: VisualDensity.compact,
            tooltip: localizations.tooltipRemoveSubtask,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: _mutedLabelColor,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Subtasks editor section inside [TaskEditorDialog] with `auto-finish` toggle, list, and input row.
class _TaskEditorSubtasksSection extends StatelessWidget {
  /// Creates a [_TaskEditorSubtasksSection].
  const _TaskEditorSubtasksSection({
    required this.hasSubtaskText,
    required this.subtaskController,
    required this.subtasks,
    required this.subtasksAutoFinish,
    required this.onAddSubtask,
    required this.onRemoveSubtask,
    required this.onToggleAutoFinish,
    required this.onToggleSubtaskStep,
  });

  /// Whether the subtask input field contains non-whitespace text.
  final bool hasSubtaskText;

  /// Callback to append a new subtask step.
  final VoidCallback onAddSubtask;

  /// Callback to remove the subtask step at the given index.
  final ValueChanged<int> onRemoveSubtask;

  /// Callback to toggle `subtasks auto-finish`.
  final VoidCallback onToggleAutoFinish;

  /// Callback to toggle completion of the subtask step at the given index.
  final ValueChanged<int> onToggleSubtaskStep;

  /// Controller for the subtask input field.
  final TextEditingController subtaskController;

  /// Ordered subtask steps.
  final List<SubtaskItem> subtasks;

  /// Whether `subtasks auto-finish` is enabled.
  final bool subtasksAutoFinish;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.subtasksSectionTitle,
                style: const TextStyle(
                  color: _mutedLabelColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _TaskEditorChip(
              chipKey: const ValueKey('task_editor_auto_finish_toggle'),
              icon: Icons.done_all_rounded,
              label: localizations.subtasksAutoFinishLabel,
              isSelected: subtasksAutoFinish,
              accentColor: _accentCyan,
              onTap: onToggleAutoFinish,
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < subtasks.length; i++)
          _TaskEditorSubtaskRow(
            index: i,
            subtask: subtasks[i],
            onRemove: () => onRemoveSubtask(i),
            onToggle: () => onToggleSubtaskStep(i),
          ),
        _TaskEditorSubtaskInputRow(
          controller: subtaskController,
          hasText: hasSubtaskText,
          onAddSubtask: onAddSubtask,
        ),
      ],
    );
  }
}

/// Task title input field with inline validation error display inside [TaskEditorDialog].
class _TaskEditorTitleField extends StatelessWidget {
  /// Creates a [_TaskEditorTitleField].
  const _TaskEditorTitleField({
    required this.controller,
    required this.errorMessage,
    required this.onSubmit,
  });

  /// Controller for the task title input.
  final TextEditingController controller;

  /// Optional validation error message.
  final String? errorMessage;

  /// Callback invoked when the user submits from the keyboard.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: _mutedLabelColor.withValues(alpha: 0.35)),
    );

    return TextField(
      key: const ValueKey('task_editor_title_input'),
      controller: controller,
      autofocus: true,
      cursorColor: _accentMagenta,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        labelText: localizations.taskNameLabel,
        labelStyle: const TextStyle(color: _mutedLabelColor),
        errorText: errorMessage,
        isDense: true,
        filled: true,
        fillColor: _canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: _accentMagenta, width: 1.6),
        ),
      ),
    );
  }
}

/// Opens [TaskEditorDialog] as a modal dialog for extended task creation or task editing.
Future<void> showTaskEditorDialog(
  BuildContext context, {
  TaskItem? initialTask,
  String initialTitle = '',
  QuickAddMode initialMode = QuickAddMode.standard,
  Set<String> initialLabelIds = const <String>{},
  VoidCallback? onSubmitted,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => TaskEditorDialog(
      initialTask: initialTask,
      initialTitle: initialTitle,
      initialMode: initialMode,
      initialLabelIds: initialLabelIds,
      onSubmitted: onSubmitted,
    ),
  );
}
