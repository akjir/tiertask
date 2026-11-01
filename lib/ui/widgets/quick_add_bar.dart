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
import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import '../../providers/task_providers.dart';

const Color _accentBlue = Color(0xFF2196F3);
const Color _accentCyan = Color(0xFF00E5FF);
const Color _accentMagenta = Color(0xFFEB06FF);
const Color _canvasColor = Color(0xFF344FA1);
const Color _cardColor = Color(0xFF071A52);
const Color _mutedLabelColor = Color(0xFF9BA8E5);

/// Bottom task creation bar with mutually exclusive Priority and Someday toggles
/// and an extendable view for defining subtasks.
class QuickAddBar extends ConsumerStatefulWidget {
  /// Creates a [QuickAddBar] widget.
  const QuickAddBar({super.key, this.onSubmitted});

  /// Optional callback invoked after a non-empty task is submitted.
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

/// Mutually exclusive scheduling mode for creating a task in [QuickAddBar].
enum QuickAddMode {
  /// Default mode: adds the task to `# [3] Planned` (cascading up if slots are open).
  standard,

  /// Priority mode: marks the task as priority and places it into `# [1] Focus`.
  priority,

  /// Someday mode: places the task into `# [5] Someday` without automatic pull.
  someday;

  /// Target [TaskTier] corresponding to this mode.
  TaskTier get targetTier {
    return switch (this) {
      QuickAddMode.standard => TaskTier.planned,
      QuickAddMode.priority => TaskTier.focus,
      QuickAddMode.someday => TaskTier.someday,
    };
  }
}

/// Header row inside [_ExtendedQuickAddView] displaying the title and collapse icon.
class _ExtendedHeaderRow extends StatelessWidget {
  /// Creates an [_ExtendedHeaderRow].
  const _ExtendedHeaderRow({required this.onCollapse});

  /// Callback invoked when the collapse button is pressed.
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            localizations.advancedTaskTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('quick_add_collapse_button'),
          visualDensity: VisualDensity.compact,
          tooltip: localizations.actionClose,
          icon: const Icon(Icons.expand_more_rounded, color: _mutedLabelColor),
          onPressed: onCollapse,
        ),
      ],
    );
  }
}

/// Extended task creation view inside [QuickAddBar] supporting subtask definition.
class _ExtendedQuickAddView extends StatelessWidget {
  /// Creates an [_ExtendedQuickAddView].
  const _ExtendedQuickAddView({
    required this.controller,
    required this.hasTaskText,
    required this.hasSubtaskText,
    required this.mode,
    required this.subtaskController,
    required this.subtasks,
    required this.onAddSubtask,
    required this.onCollapse,
    required this.onRemoveSubtask,
    required this.onSubmit,
    required this.onTogglePriority,
    required this.onToggleSomeday,
  });

  /// Text controller for the main task title.
  final TextEditingController controller;

  /// Whether the subtask input currently contains non-whitespace text.
  final bool hasSubtaskText;

  /// Whether the main task input currently contains non-whitespace text.
  final bool hasTaskText;

  /// Active scheduling mode (`standard`, `priority`, or `someday`).
  final QuickAddMode mode;

  /// Callback to append the current subtask input to [subtasks].
  final VoidCallback onAddSubtask;

  /// Callback to return to the compact bar view.
  final VoidCallback onCollapse;

  /// Callback to remove the subtask at the given index.
  final ValueChanged<int> onRemoveSubtask;

  /// Callback to submit the task with its subtasks.
  final VoidCallback onSubmit;

  /// Callback to toggle Priority mode on or off.
  final VoidCallback onTogglePriority;

  /// Callback to toggle Someday mode on or off.
  final VoidCallback onToggleSomeday;

  /// Text controller for the subtask input field.
  final TextEditingController subtaskController;

  /// Ordered list of subtasks defined for the new task.
  final List<SubtaskItem> subtasks;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ExtendedHeaderRow(onCollapse: onCollapse),
        const SizedBox(height: 8),
        _QuickAddInputRow(
          controller: controller,
          effectiveTier: mode.targetTier,
          hasText: hasTaskText,
          onSubmit: onSubmit,
        ),
        const SizedBox(height: 8),
        _QuickAddActionRow(
          mode: mode,
          showAdvancedButton: false,
          onOpenAdvanced: onCollapse,
          onTogglePriority: onTogglePriority,
          onToggleSomeday: onToggleSomeday,
        ),
        const SizedBox(height: 12),
        _SubtaskEditorSection(
          hasSubtaskText: hasSubtaskText,
          subtaskController: subtaskController,
          subtasks: subtasks,
          onAddSubtask: onAddSubtask,
          onRemoveSubtask: onRemoveSubtask,
        ),
      ],
    );
  }
}

/// Row containing the mutually exclusive Priority and Someday toggles and optional Advanced button.
class _QuickAddActionRow extends StatelessWidget {
  /// Creates a [_QuickAddActionRow].
  const _QuickAddActionRow({
    required this.mode,
    required this.showAdvancedButton,
    required this.onOpenAdvanced,
    required this.onTogglePriority,
    required this.onToggleSomeday,
  });

  /// Active scheduling mode (`standard`, `priority`, or `someday`).
  final QuickAddMode mode;

  /// Callback invoked when the Advanced button is pressed.
  final VoidCallback onOpenAdvanced;

  /// Callback invoked when the Priority toggle is pressed.
  final VoidCallback onTogglePriority;

  /// Callback invoked when the Someday toggle is pressed.
  final VoidCallback onToggleSomeday;

  /// Whether to render the button that opens the extended subtask view.
  final bool showAdvancedButton;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _QuickAddModeChip(
          chipKey: const ValueKey('quick_add_priority_button'),
          icon: Icons.bolt_rounded,
          label: localizations.quickAddPriority,
          selected: mode == QuickAddMode.priority,
          selectedColor: _accentMagenta,
          onToggle: onTogglePriority,
        ),
        _QuickAddModeChip(
          chipKey: const ValueKey('quick_add_someday_button'),
          icon: Icons.lightbulb_outline_rounded,
          label: localizations.tierName(TaskTier.someday),
          selected: mode == QuickAddMode.someday,
          selectedColor: _accentBlue,
          onToggle: onToggleSomeday,
        ),
        if (showAdvancedButton)
          TextButton.icon(
            key: const ValueKey('quick_add_advanced_button'),
            style: TextButton.styleFrom(foregroundColor: _mutedLabelColor),
            onPressed: onOpenAdvanced,
            icon: const Icon(Icons.tune_rounded, size: 18, color: _accentCyan),
            label: Text(localizations.quickAddAdvanced),
          ),
      ],
    );
  }
}

/// State for [QuickAddBar].
class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final TextEditingController _controller = TextEditingController();
  QuickAddMode _mode = QuickAddMode.standard;
  final TextEditingController _subtaskController = TextEditingController();
  final List<SubtaskItem> _subtasks = <SubtaskItem>[];
  _QuickAddViewState _viewState = _QuickAddViewState.compact;

  bool get _hasSubtaskText => _subtaskController.text.trim().isNotEmpty;

  bool get _hasTaskText => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
    _subtaskController.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _subtaskController.removeListener(_handleControllerChanged);
    _controller.dispose();
    _subtaskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: _cardColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: switch (_viewState) {
            _QuickAddViewState.compact => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _QuickAddInputRow(
                  controller: _controller,
                  effectiveTier: _mode.targetTier,
                  hasText: _hasTaskText,
                  onSubmit: _submit,
                ),
                const SizedBox(height: 8),
                _QuickAddActionRow(
                  mode: _mode,
                  showAdvancedButton: true,
                  onOpenAdvanced: _openExtendedView,
                  onTogglePriority: _togglePriority,
                  onToggleSomeday: _toggleSomeday,
                ),
              ],
            ),
            _QuickAddViewState.extended => _ExtendedQuickAddView(
              controller: _controller,
              hasTaskText: _hasTaskText,
              hasSubtaskText: _hasSubtaskText,
              mode: _mode,
              subtaskController: _subtaskController,
              subtasks: List<SubtaskItem>.unmodifiable(_subtasks),
              onAddSubtask: _addSubtask,
              onCollapse: _collapseExtendedView,
              onRemoveSubtask: _removeSubtask,
              onSubmit: _submit,
              onTogglePriority: _togglePriority,
              onToggleSomeday: _toggleSomeday,
            ),
          },
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

  /// Switches back from the extended subtask view to the compact quick-add bar.
  void _collapseExtendedView() {
    setState(() {
      _viewState = _QuickAddViewState.compact;
    });
  }

  /// Rebuilds the widget when the task or subtask text changes.
  void _handleControllerChanged() {
    setState(() {});
  }

  /// Switches from the compact quick-add bar to the extended subtask view.
  void _openExtendedView() {
    setState(() {
      _viewState = _QuickAddViewState.extended;
    });
  }

  /// Removes the subtask at [index].
  void _removeSubtask(int index) {
    if (index < 0 || index >= _subtasks.length) {
      return;
    }
    setState(() {
      _subtasks.removeAt(index);
    });
  }

  /// Submits the entered task title, priority/someday selection, and any defined subtasks.
  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    final pendingSubtask = _subtaskController.text.trim();
    final submittedSubtasks = <SubtaskItem>[
      ..._subtasks,
      if (pendingSubtask.isNotEmpty) SubtaskItem(title: pendingSubtask),
    ];
    final selectedMode = _mode;

    _controller.clear();
    _subtaskController.clear();
    setState(() {
      _subtasks.clear();
      _mode = QuickAddMode.standard;
      _viewState = _QuickAddViewState.compact;
    });

    await ref
        .read(taskNotifierProvider.notifier)
        .addTask(
          text,
          targetTier: selectedMode.targetTier,
          isPriority: selectedMode == QuickAddMode.priority,
          subtasks: submittedSubtasks,
        );
    widget.onSubmitted?.call();
  }

  /// Toggles Priority on or off, automatically turning Someday off when enabled.
  void _togglePriority() {
    setState(() {
      _mode = _mode == QuickAddMode.priority
          ? QuickAddMode.standard
          : QuickAddMode.priority;
    });
  }

  /// Toggles Someday on or off, automatically turning Priority off when enabled.
  void _toggleSomeday() {
    setState(() {
      _mode = _mode == QuickAddMode.someday
          ? QuickAddMode.standard
          : QuickAddMode.someday;
    });
  }
}

/// Text input field and submit button row inside [QuickAddBar].
class _QuickAddInputRow extends StatelessWidget {
  /// Creates a [_QuickAddInputRow].
  const _QuickAddInputRow({
    required this.controller,
    required this.effectiveTier,
    required this.hasText,
    required this.onSubmit,
  });

  /// Text controller for the task title input.
  final TextEditingController controller;

  /// Currently active target tier based on the selected [QuickAddMode].
  final TaskTier effectiveTier;

  /// Whether the input field currently contains non-whitespace text.
  final bool hasText;

  /// Callback invoked when the user submits the task.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickAddTextField(
            controller: controller,
            effectiveTier: effectiveTier,
            onSubmit: onSubmit,
          ),
        ),
        const SizedBox(width: 8),
        _QuickAddSubmitButton(
          controller: controller,
          hasText: hasText,
          onSubmit: onSubmit,
        ),
      ],
    );
  }
}

/// Styled [ChoiceChip] matching the landing page color language for Priority and Someday toggles.
class _QuickAddModeChip extends StatelessWidget {
  /// Creates a [_QuickAddModeChip].
  const _QuickAddModeChip({
    required this.chipKey,
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onToggle,
  });

  /// Deterministic widget key for the chip.
  final Key chipKey;

  /// Leading icon displayed inside the chip avatar.
  final IconData icon;

  /// Localized chip label text.
  final String label;

  /// Callback invoked when the chip is tapped.
  final VoidCallback onToggle;

  /// Whether this mode is currently active.
  final bool selected;

  /// Accent fill color used when [selected] is true.
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      key: chipKey,
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? Colors.white : selectedColor,
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      backgroundColor: _canvasColor,
      selectedColor: selectedColor,
      labelStyle: TextStyle(
        color: selected ? Colors.white : _mutedLabelColor,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected
            ? selectedColor
            : _mutedLabelColor.withValues(alpha: 0.35),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      visualDensity: VisualDensity.compact,
      onSelected: (_) => onToggle(),
    );
  }
}

/// Add button that is enabled only when the task input field contains text.
class _QuickAddSubmitButton extends StatelessWidget {
  /// Creates a [_QuickAddSubmitButton].
  const _QuickAddSubmitButton({
    required this.controller,
    required this.hasText,
    required this.onSubmit,
  });

  /// Text controller used to check synchronous input state.
  final TextEditingController controller;

  /// Whether the input field had non-whitespace text during the last build.
  final bool hasText;

  /// Callback invoked when submitting a non-empty task.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (!hasText && controller.text.trim().isNotEmpty) {
          onSubmit();
        }
      },
      child: FilledButton.icon(
        key: const ValueKey('quick_add_submit_button'),
        style: FilledButton.styleFrom(
          backgroundColor: _accentMagenta,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _canvasColor.withValues(alpha: 0.55),
          disabledForegroundColor: _mutedLabelColor.withValues(alpha: 0.6),
        ),
        onPressed: hasText ? onSubmit : null,
        icon: const Icon(Icons.add_rounded),
        label: Text(localizations.actionAdd),
      ),
    );
  }
}

/// Rounded task title [TextField] inside [QuickAddBar].
class _QuickAddTextField extends StatelessWidget {
  /// Creates a [_QuickAddTextField].
  const _QuickAddTextField({
    required this.controller,
    required this.effectiveTier,
    required this.onSubmit,
  });

  /// Text controller for the task title input.
  final TextEditingController controller;

  /// Target tier used to format the localized placeholder hint.
  final TaskTier effectiveTier;

  /// Callback invoked when the user submits from the keyboard.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final heading = localizations.tierName(effectiveTier);
    final borderRadius = BorderRadius.circular(20);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: _mutedLabelColor.withValues(alpha: 0.35)),
    );

    return TextField(
      key: const ValueKey('quick_add_input'),
      controller: controller,
      cursorColor: _accentMagenta,
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        hintText: localizations.quickAddHint(heading),
        hintStyle: const TextStyle(color: _mutedLabelColor),
        isDense: true,
        filled: true,
        fillColor: _canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: _accentMagenta, width: 1.8),
        ),
      ),
    );
  }
}

/// Visual layout state of [QuickAddBar].
enum _QuickAddViewState { compact, extended }

/// Subtask list and input section inside [_ExtendedQuickAddView].
class _SubtaskEditorSection extends StatelessWidget {
  /// Creates a [_SubtaskEditorSection].
  const _SubtaskEditorSection({
    required this.hasSubtaskText,
    required this.subtaskController,
    required this.subtasks,
    required this.onAddSubtask,
    required this.onRemoveSubtask,
  });

  /// Whether the subtask text field currently contains non-whitespace text.
  final bool hasSubtaskText;

  /// Callback to append a new subtask.
  final VoidCallback onAddSubtask;

  /// Callback to remove the subtask at the given index.
  final ValueChanged<int> onRemoveSubtask;

  /// Controller for the subtask input field.
  final TextEditingController subtaskController;

  /// Current subtasks defined for the task.
  final List<SubtaskItem> subtasks;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.subtasksSectionTitle,
          style: const TextStyle(
            color: _mutedLabelColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < subtasks.length; i++)
          _SubtaskListTile(
            index: i,
            subtask: subtasks[i],
            onRemove: () => onRemoveSubtask(i),
          ),
        _SubtaskInputRow(
          controller: subtaskController,
          hasText: hasSubtaskText,
          onAddSubtask: onAddSubtask,
        ),
      ],
    );
  }
}

/// Input row for adding a single subtask inside [_SubtaskEditorSection].
class _SubtaskInputRow extends StatelessWidget {
  /// Creates a [_SubtaskInputRow].
  const _SubtaskInputRow({
    required this.controller,
    required this.hasText,
    required this.onAddSubtask,
  });

  /// Controller for the subtask title field.
  final TextEditingController controller;

  /// Whether the subtask field currently contains non-whitespace text.
  final bool hasText;

  /// Callback to append the subtask to the list.
  final VoidCallback onAddSubtask;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: _SubtaskTextField(
            controller: controller,
            onSubmit: onAddSubtask,
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          key: const ValueKey('quick_add_subtask_add_button'),
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

/// Displays a single pending subtask with a remove button inside [_SubtaskEditorSection].
class _SubtaskListTile extends StatelessWidget {
  /// Creates a [_SubtaskListTile].
  const _SubtaskListTile({
    required this.index,
    required this.subtask,
    required this.onRemove,
  });

  /// Zero-based position of [subtask] in the list.
  final int index;

  /// Callback invoked when the remove button is pressed.
  final VoidCallback onRemove;

  /// Subtask item to display.
  final SubtaskItem subtask;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: 18,
            color: _accentCyan,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtask.title,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          IconButton(
            key: ValueKey('quick_add_remove_subtask_$index'),
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

/// Rounded subtask title [TextField] inside [_SubtaskInputRow].
class _SubtaskTextField extends StatelessWidget {
  /// Creates a [_SubtaskTextField].
  const _SubtaskTextField({required this.controller, required this.onSubmit});

  /// Controller for the subtask title field.
  final TextEditingController controller;

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
      key: const ValueKey('quick_add_subtask_input'),
      controller: controller,
      cursorColor: _accentCyan,
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
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
    );
  }
}
