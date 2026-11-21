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

/// Material 3 task information overlay dialog displaying active task indicators, metadata, and the interactive History Journal.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_board.dart';
import '../../models/task_item.dart';
import '../../models/tdf_error.dart';
import '../../models/tdf_metadata.dart';
import '../../models/webdav_config.dart';
import '../../presentation/task_info_controller.dart';
import '../../presentation/ui_telemetry.dart';
import '../../providers/config_providers.dart';
import '../../providers/task_providers.dart';
import 'clearable_text_field.dart';
import 'label_hub_dialog.dart';
import 'task_editor_history_section.dart';
import 'tier_task_subtasks_section.dart';

/// Popup dialog displaying detailed status, indicator metadata, and an interactive History Journal for [task].
class TaskInfoDialog extends ConsumerStatefulWidget {
  /// Creates a [TaskInfoDialog].
  const TaskInfoDialog({
    super.key,
    this.initialIndicatorKeyPrefix,
    required this.task,
  });

  /// Optional indicator key prefix that triggered opening this dialog.
  final String? initialIndicatorKeyPrefix;

  /// Task item whose active indicators, metadata, and history journal are displayed.
  final TaskItem task;

  @override
  ConsumerState<TaskInfoDialog> createState() => _TaskInfoDialogState();
}

/// Dialog header displaying the localized dialog heading and [currentTask] title.
class _TaskInfoDialogTitle extends StatelessWidget {
  /// Creates a [_TaskInfoDialogTitle].
  const _TaskInfoDialogTitle({required this.currentTask});

  /// Live task item displayed in the dialog header.
  final TaskItem currentTask;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(localizations.taskInfoDialogTitle),
        const SizedBox(height: 4),
        Text(
          currentTask.title,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// State for [TaskInfoDialog] managing inline History Journal append, edit, and delete operations.
class _TaskInfoDialogState extends ConsumerState<TaskInfoDialog> {
  final TextEditingController _appendController = TextEditingController();
  final TextEditingController _editController = TextEditingController();
  TaskHistoryEntry? _editingEntry;
  String? _historyErrorMessage;
  bool _isMutatingHistory = false;

  @override
  void initState() {
    super.initState();
    _appendController.addListener(_clearHistoryError);
    _editController.addListener(_clearHistoryError);
  }

  @override
  void didUpdateWidget(covariant TaskInfoDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _editingEntry = null;
      _historyErrorMessage = null;
      _isMutatingHistory = false;
      _appendController.clear();
      _editController.clear();
    }
  }

  @override
  void dispose() {
    _appendController.dispose();
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<TaskBoard>>(
      taskNotifierProvider,
      _handleBoardChanged,
    );
    ref.watch(boundaryTickProvider);
    final localizations = AppLocalizations.of(context);
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final liveBoardTask = board.findTask(widget.task.id);
    final isBoardManaged = liveBoardTask != null;
    final currentTask = liveBoardTask ?? widget.task;
    final configuration =
        ref.watch(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final nowUtc = ref.watch(clockProvider)().toUtc();
    final sections = _TaskInfoSectionsBuilder.buildSections(
      board: board,
      configuration: configuration,
      currentTask: currentTask,
      localizations: localizations,
      nowUtc: nowUtc,
    );
    final activeEditingIndex = switch (_editingEntry) {
      final target? when isBoardManaged => currentTask.history.indexOf(target),
      _ => -1,
    };
    return AlertDialog(
      title: _TaskInfoDialogTitle(currentTask: currentTask),
      content: _buildDialogContent(
        activeEditingIndex: activeEditingIndex,
        canMutateHistory: isBoardManaged && !_isMutatingHistory,
        configuration: configuration,
        currentTask: currentTask,
        sections: sections,
      ),
      actions: [
        FilledButton(
          key: const ValueKey('task_info_dialog_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionClose),
        ),
      ],
    );
  }

  /// Validates and appends a single-line history entry stamped with the current UTC second.
  Future<void> _appendHistoryEntry(TaskItem currentTask) async {
    final controller = ref.read(taskInfoControllerProvider);
    if (_isMutatingHistory || !controller.isTaskOnBoard(currentTask.id)) {
      return;
    }
    final locale = Localizations.localeOf(context);
    setState(() {
      _isMutatingHistory = true;
      _historyErrorMessage = null;
    });
    final TaskHistoryMutationResult result;
    try {
      result = await controller.appendHistoryEntry(
        currentTask: currentTask,
        rawText: _appendController.text,
        locale: locale,
      );
    } finally {
      if (mounted) {
        setState(() => _isMutatingHistory = false);
      }
    }
    if (!mounted) {
      return;
    }
    switch (result) {
      case TaskHistoryMutationCommitted():
        _appendController.clear();
      case TaskHistoryMutationFailed(:final localizedMessage):
        setState(() => _historyErrorMessage = localizedMessage);
      case TaskHistoryMutationUnchanged():
      case TaskHistoryMutationNotApplied():
        break;
    }
  }

  /// Builds the tight-width scrollable dialog content column ending with [_TaskInfoHistoryCard].
  Widget _buildDialogContent({
    required int activeEditingIndex,
    required bool canMutateHistory,
    required WebDavConfig configuration,
    required TaskItem currentTask,
    required List<_TaskInfoSectionData> sections,
  }) {
    return SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _TaskInfoSectionCard(
                data: sections[i],
                isHighlighted:
                    sections[i].keyPrefix == widget.initialIndicatorKeyPrefix,
              ),
            ],
            if (sections.isNotEmpty) const SizedBox(height: 8),
            _TaskInfoHistoryCard(
              activeEditingIndex: activeEditingIndex,
              appendController: _appendController,
              canMutateHistory: canMutateHistory,
              configuration: configuration,
              editController: _editController,
              entries: currentTask.history,
              errorMessage: _historyErrorMessage,
              isHighlighted:
                  widget.initialIndicatorKeyPrefix == 'history_task_indicator',
              onAppend: () => _appendHistoryEntry(currentTask),
              onCancelEdit: _cancelInlineEdit,
              onDeleteEntry: (entry) => _deleteHistoryEntry(currentTask, entry),
              onSaveEdit: (entry) => _saveInlineEdit(currentTask, entry),
              onStartEdit: _startInlineEdit,
            ),
          ],
        ),
      ),
    );
  }

  /// Exits inline row editing and clears [_editController].
  void _cancelInlineEdit() {
    setState(() {
      _editingEntry = null;
      _historyErrorMessage = null;
      _editController.clear();
    });
  }

  /// Clears [_historyErrorMessage] when the user modifies an inline history text field.
  void _clearHistoryError() {
    if (_historyErrorMessage != null) {
      setState(() => _historyErrorMessage = null);
    }
  }

  /// Removes [entry] from [currentTask] via [taskInfoControllerProvider].
  Future<void> _deleteHistoryEntry(
    TaskItem currentTask,
    TaskHistoryEntry entry,
  ) async {
    final controller = ref.read(taskInfoControllerProvider);
    if (_isMutatingHistory || !controller.isTaskOnBoard(currentTask.id)) {
      return;
    }
    final locale = Localizations.localeOf(context);
    final wasEditingTarget = _editingEntry == entry;
    setState(() {
      _isMutatingHistory = true;
      _historyErrorMessage = null;
      if (wasEditingTarget) {
        _editingEntry = null;
        _editController.clear();
      }
    });
    final TaskHistoryMutationResult result;
    try {
      result = await controller.deleteHistoryEntry(
        taskId: currentTask.id,
        entry: entry,
        locale: locale,
      );
    } finally {
      if (mounted) {
        setState(() => _isMutatingHistory = false);
      }
    }
    if (!mounted) {
      return;
    }
    switch (result) {
      case TaskHistoryMutationFailed(:final localizedMessage):
        setState(() => _historyErrorMessage = localizedMessage);
      case TaskHistoryMutationCommitted():
      case TaskHistoryMutationUnchanged():
      case TaskHistoryMutationNotApplied():
        break;
    }
  }

  /// Clears stale inline edit state when an external board sync removes [widget.task] or [_editingEntry].
  void _handleBoardChanged(
    AsyncValue<TaskBoard>? previous,
    AsyncValue<TaskBoard> next,
  ) {
    final target = _editingEntry;
    if (target == null) {
      return;
    }
    final nextTask = next.asData?.value.findTask(widget.task.id);
    if (nextTask == null || !nextTask.history.contains(target)) {
      setState(() {
        _editingEntry = null;
        _editController.clear();
      });
    }
  }

  /// Validates and saves the active inline `<text>` edit for [originalEntry], preserving `timestampUtc`.
  Future<void> _saveInlineEdit(
    TaskItem currentTask,
    TaskHistoryEntry originalEntry,
  ) async {
    final controller = ref.read(taskInfoControllerProvider);
    if (_isMutatingHistory || !controller.isTaskOnBoard(currentTask.id)) {
      return;
    }
    final locale = Localizations.localeOf(context);
    setState(() {
      _isMutatingHistory = true;
      _historyErrorMessage = null;
    });
    final TaskHistoryMutationResult result;
    try {
      result = await controller.updateHistoryEntry(
        taskId: currentTask.id,
        originalEntry: originalEntry,
        rawText: _editController.text,
        locale: locale,
      );
    } finally {
      if (mounted) {
        setState(() => _isMutatingHistory = false);
      }
    }
    if (!mounted) {
      return;
    }
    switch (result) {
      case TaskHistoryMutationCommitted():
      case TaskHistoryMutationUnchanged():
        _cancelInlineEdit();
      case TaskHistoryMutationFailed(:final localizedMessage):
        setState(() => _historyErrorMessage = localizedMessage);
      case TaskHistoryMutationNotApplied():
        break;
    }
  }

  /// Activates inline `<text>` editing for [entry].
  void _startInlineEdit(TaskHistoryEntry entry) {
    if (_isMutatingHistory) {
      return;
    }
    setState(() {
      _historyErrorMessage = null;
      _editingEntry = entry;
      _editController.text = entry.text;
    });
  }
}

/// Quick single-line history append row inside [_TaskInfoHistoryCard].
class _TaskInfoHistoryAppendRow extends StatelessWidget {
  /// Creates a [_TaskInfoHistoryAppendRow].
  const _TaskInfoHistoryAppendRow({
    required this.canAppend,
    required this.canMutateHistory,
    required this.controller,
    required this.onAppend,
  });

  /// Whether the add button is enabled (`canMutateHistory && entries.length < maxTdfHistoryPerTask`).
  final bool canAppend;

  /// Whether the text field is enabled for user input.
  final bool canMutateHistory;

  /// Controller bound to the quick-append input field.
  final TextEditingController controller;

  /// Callback invoked when `Enter` or the add button is triggered.
  final VoidCallback onAppend;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: ClearableTextField(
            fieldKey: const ValueKey('task_info_history_input'),
            clearButtonKey: const ValueKey('task_info_history_clear_button'),
            showClearWhenUnfocused: true,
            enabled: canMutateHistory,
            controller: controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onAppend(),
            decoration: InputDecoration(
              hintText: localizations.historyEntryTextHint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          key: const ValueKey('task_info_history_add_button'),
          visualDensity: VisualDensity.compact,
          tooltip: localizations.tooltipAddHistoryEntry,
          onPressed: canAppend ? onAppend : null,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    );
  }
}

/// Always-visible interactive History Journal section card inside [TaskInfoDialog].
class _TaskInfoHistoryCard extends StatelessWidget {
  /// Creates a [_TaskInfoHistoryCard].
  const _TaskInfoHistoryCard({
    required this.activeEditingIndex,
    required this.appendController,
    required this.canMutateHistory,
    required this.configuration,
    required this.editController,
    required this.entries,
    required this.errorMessage,
    required this.isHighlighted,
    required this.onAppend,
    required this.onCancelEdit,
    required this.onDeleteEntry,
    required this.onSaveEdit,
    required this.onStartEdit,
  });

  /// Zero-based index of the entry currently being edited inline, or `-1` when none.
  final int activeEditingIndex;

  /// Controller for the single-line quick-append input field.
  final TextEditingController appendController;

  /// Whether inline mutations are currently permitted.
  final bool canMutateHistory;

  /// Active workspace configuration for local wall-clock timestamp formatting.
  final WebDavConfig configuration;

  /// Controller for the active inline row `<text>` editor.
  final TextEditingController editController;

  /// Chronologically normalized history entries on the task.
  final List<TaskHistoryEntry> entries;

  /// Optional localized validation or persistence error message.
  final String? errorMessage;

  /// Whether `history_task_indicator` opened this dialog.
  final bool isHighlighted;

  /// Callback invoked when appending a new entry.
  final VoidCallback onAppend;

  /// Callback invoked to cancel an active inline row edit.
  final VoidCallback onCancelEdit;

  /// Callback invoked to delete a specific [TaskHistoryEntry].
  final ValueChanged<TaskHistoryEntry> onDeleteEntry;

  /// Callback invoked to save an edited [TaskHistoryEntry].
  final ValueChanged<TaskHistoryEntry> onSaveEdit;

  /// Callback invoked to begin inline editing of a [TaskHistoryEntry].
  final ValueChanged<TaskHistoryEntry> onStartEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('task_info_section_history_task_indicator'),
      padding: const EdgeInsets.all(12),
      decoration: _TaskInfoSectionCard.buildCardDecoration(
        colorScheme,
        isHighlighted: isHighlighted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeaderRow(context, localizations, colorScheme),
          const SizedBox(height: 8),
          entries.isEmpty
              ? Text(
                  localizations.historyEmptyHint,
                  key: const ValueKey('task_info_history_empty_hint'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                )
              : _TaskInfoHistoryList(
                  activeEditingIndex: activeEditingIndex,
                  canMutateHistory: canMutateHistory,
                  configuration: configuration,
                  editController: editController,
                  entries: entries,
                  onCancelEdit: onCancelEdit,
                  onDeleteEntry: onDeleteEntry,
                  onSaveEdit: onSaveEdit,
                  onStartEdit: onStartEdit,
                ),
          const SizedBox(height: 8),
          _TaskInfoHistoryAppendRow(
            canAppend:
                canMutateHistory && entries.length < maxTdfHistoryPerTask,
            canMutateHistory: canMutateHistory,
            controller: appendController,
            onAppend: onAppend,
          ),
          if (errorMessage case final error?) _TaskInfoHistoryErrorText(error),
        ],
      ),
    );
  }

  /// Builds the leading icon and localized section heading row.
  Widget _buildHeaderRow(
    BuildContext context,
    AppLocalizations localizations,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Icon(Icons.history_rounded, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            localizations.historySectionTitle,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Inline validation error label rendered inside [_TaskInfoHistoryCard].
class _TaskInfoHistoryErrorText extends StatelessWidget {
  /// Creates a [_TaskInfoHistoryErrorText].
  const _TaskInfoHistoryErrorText(this.message);

  /// Localized validation or persistence error message.
  final String message;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        message,
        key: const ValueKey('task_info_history_error_text'),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: errorColor),
      ),
    );
  }
}

/// Inline single-line `<text>` editor rendered for the active row in [_TaskInfoHistoryList].
class _TaskInfoHistoryInlineEditor extends StatelessWidget {
  /// Creates a [_TaskInfoHistoryInlineEditor].
  const _TaskInfoHistoryInlineEditor({
    required this.canMutateHistory,
    required this.controller,
    required this.index,
    required this.localTimestampText,
    required this.onCancel,
    required this.onSave,
  });

  /// Whether the inline editor controls are enabled.
  final bool canMutateHistory;

  /// Controller bound to the edited `<text>` input.
  final TextEditingController controller;

  /// Zero-based index of the edited row.
  final int index;

  /// Formatted local wall-clock timestamp displayed above the editor field.
  final String localTimestampText;

  /// Callback invoked to cancel the inline edit.
  final VoidCallback onCancel;

  /// Callback invoked to save the inline edit.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey('task_info_history_row_$index'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            localTimestampText,
            key: ValueKey('task_info_history_timestamp_$index'),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ClearableTextField(
                  fieldKey: ValueKey('task_info_history_edit_input_$index'),
                  clearButtonKey: ValueKey(
                    'task_info_history_edit_clear_$index',
                  ),
                  showClearWhenUnfocused: true,
                  enabled: canMutateHistory,
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSave(),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('task_info_history_edit_save_$index'),
                visualDensity: VisualDensity.compact,
                tooltip: localizations.tooltipSaveHistoryEntry,
                onPressed: canMutateHistory ? onSave : null,
                icon: Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
              IconButton(
                key: ValueKey('task_info_history_edit_cancel_$index'),
                visualDensity: VisualDensity.compact,
                tooltip: localizations.tooltipCancelEditHistoryEntry,
                onPressed: canMutateHistory ? onCancel : null,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Renders chronological history entries inside a [Column] (`<= 5` entries) or virtualized [ListView.builder] (`> 5` entries).
class _TaskInfoHistoryList extends StatelessWidget {
  /// Creates a [_TaskInfoHistoryList].
  const _TaskInfoHistoryList({
    required this.activeEditingIndex,
    required this.canMutateHistory,
    required this.configuration,
    required this.editController,
    required this.entries,
    required this.onCancelEdit,
    required this.onDeleteEntry,
    required this.onSaveEdit,
    required this.onStartEdit,
  });

  /// Fixed viewport height when virtualizing `> 5` entries inside [AlertDialog].
  static const double virtualizedViewportHeight = 220;

  /// Zero-based index of the entry currently being edited inline, or `-1`.
  final int activeEditingIndex;

  /// Whether row edit/delete buttons are enabled.
  final bool canMutateHistory;

  /// Active workspace configuration for local wall-clock timestamp formatting.
  final WebDavConfig configuration;

  /// Controller for the active inline row `<text>` editor.
  final TextEditingController editController;

  /// Chronologically normalized history entries.
  final List<TaskHistoryEntry> entries;

  /// Callback invoked to cancel an active inline edit.
  final VoidCallback onCancelEdit;

  /// Callback invoked to delete a specific entry.
  final ValueChanged<TaskHistoryEntry> onDeleteEntry;

  /// Callback invoked to save an edited entry.
  final ValueChanged<TaskHistoryEntry> onSaveEdit;

  /// Callback invoked to start inline editing of an entry.
  final ValueChanged<TaskHistoryEntry> onStartEdit;

  @override
  Widget build(BuildContext context) {
    if (entries.length <= TaskEditorHistorySection.maxInlineColumnRows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < entries.length; i++) _buildItem(i)],
      );
    }
    return SizedBox(
      height: virtualizedViewportHeight,
      child: ListView.builder(
        key: const ValueKey('task_info_history_list'),
        itemCount: entries.length,
        itemBuilder: (_, index) => _buildItem(index),
      ),
    );
  }

  /// Builds either a display row or inline editor row for zero-based [index].
  Widget _buildItem(int index) {
    final entry = entries[index];
    final localTimestampText = TaskItem.formatTdfTimestamp(
      configuration.toLocalWallClock(entry.timestampUtc),
    );
    if (index == activeEditingIndex) {
      return _TaskInfoHistoryInlineEditor(
        canMutateHistory: canMutateHistory,
        controller: editController,
        index: index,
        localTimestampText: localTimestampText,
        onCancel: onCancelEdit,
        onSave: () => onSaveEdit(entry),
      );
    }
    return _TaskInfoHistoryRow(
      canMutateHistory: canMutateHistory,
      entry: entry,
      index: index,
      localTimestampText: localTimestampText,
      onDelete: () => onDeleteEntry(entry),
      onEdit: () => onStartEdit(entry),
    );
  }
}

/// Display row rendering a single [TaskHistoryEntry]'s local timestamp, passive [SelectableText], and edit/delete buttons.
class _TaskInfoHistoryRow extends StatelessWidget {
  /// Creates a [_TaskInfoHistoryRow].
  const _TaskInfoHistoryRow({
    required this.canMutateHistory,
    required this.entry,
    required this.index,
    required this.localTimestampText,
    required this.onDelete,
    required this.onEdit,
  });

  /// Whether the edit and delete buttons are enabled.
  final bool canMutateHistory;

  /// History entry rendered in this row.
  final TaskHistoryEntry entry;

  /// Zero-based index of [entry].
  final int index;

  /// Formatted local wall-clock timestamp string.
  final String localTimestampText;

  /// Callback invoked when the delete button is pressed.
  final VoidCallback onDelete;

  /// Callback invoked when the edit button is pressed.
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey('task_info_history_row_$index'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  localTimestampText,
                  key: ValueKey('task_info_history_timestamp_$index'),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  entry.text,
                  key: ValueKey('task_info_history_text_$index'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('task_info_history_edit_$index'),
            visualDensity: VisualDensity.compact,
            tooltip: localizations.tooltipEditHistoryEntry,
            onPressed: canMutateHistory ? onEdit : null,
            icon: Icon(
              Icons.edit_outlined,
              size: 16,
              color: colorScheme.primary,
            ),
          ),
          IconButton(
            key: ValueKey('task_info_history_delete_$index'),
            visualDensity: VisualDensity.compact,
            tooltip: localizations.tooltipDeleteHistoryEntry,
            onPressed: canMutateHistory ? onDelete : null,
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive colored label [ActionChip] wrap inside [TaskInfoDialog].
class _TaskInfoLabelChips extends StatelessWidget {
  /// Creates [_TaskInfoLabelChips].
  const _TaskInfoLabelChips({required this.labels});

  /// Assigned labels to render.
  final List<TdfLabel> labels;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final fallbackColor = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final label in labels)
          ActionChip(
            key: ValueKey('task_info_label_chip_${label.id}'),
            tooltip: localizations.tooltipOpenLabelHub,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            avatar: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _resolveLabelColor(label.color, fallbackColor),
                shape: BoxShape.circle,
              ),
            ),
            label: Text(label.name),
            onPressed: () => showLabelHubDialog(context, labelId: label.id),
          ),
      ],
    );
  }

  /// Resolves the `#RRGGBB` color of [rawHex] or returns [fallback].
  static Color _resolveLabelColor(String? rawHex, Color fallback) {
    final parsed = TdfColor.tryParseArgb(rawHex);
    return parsed != null ? Color(parsed) : fallback;
  }
}

/// Multi-line selectable scheduling note block rendered inside [_TaskInfoSectionCard].
class _TaskInfoNoteBody extends StatelessWidget {
  /// Creates a [_TaskInfoNoteBody].
  const _TaskInfoNoteBody({required this.note, this.noteKey});

  /// Multi-line scheduling note text.
  final String note;

  /// Optional deterministic widget key for testing.
  final Key? noteKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SelectableText(
        note,
        key: noteKey,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// Card rendering a single active indicator section inside [TaskInfoDialog].
class _TaskInfoSectionCard extends StatelessWidget {
  /// Creates a [_TaskInfoSectionCard].
  const _TaskInfoSectionCard({required this.data, required this.isHighlighted});

  /// Section data to display.
  final _TaskInfoSectionData data;

  /// Whether this section matches the indicator that opened the dialog.
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('task_info_section_${data.keyPrefix}'),
      padding: const EdgeInsets.all(12),
      decoration: buildCardDecoration(
        Theme.of(context).colorScheme,
        isHighlighted: isHighlighted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeaderRow(context),
          if (data.progressValue case final progress?) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
          ],
          if (data.labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TaskInfoLabelChips(labels: data.labels),
          ],
          if (data.details.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildDetailsList(context),
          ],
          if (data.noteBody case final note? when note.isNotEmpty)
            _TaskInfoNoteBody(note: note, noteKey: data.noteKey),
        ],
      ),
    );
  }

  /// Builds the highlighted or neutral card decoration for [colorScheme].
  static BoxDecoration buildCardDecoration(
    ColorScheme colorScheme, {
    required bool isHighlighted,
  }) {
    final borderColor = isHighlighted
        ? colorScheme.primary.withValues(alpha: 0.5)
        : colorScheme.outlineVariant.withValues(alpha: 0.4);
    final backgroundColor = isHighlighted
        ? colorScheme.primaryContainer.withValues(alpha: 0.25)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
    );
  }

  /// Builds the secondary detail lines beneath the primary section value.
  Widget _buildDetailsList(BuildContext context) {
    final detailStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final detail in data.details)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(detail, style: detailStyle),
          ),
      ],
    );
  }

  /// Builds the section header row with leading icon, title, and primary value text.
  Widget _buildHeaderRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(data.icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.title,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (data.value.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(data.value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Immutable view model for a single section in [TaskInfoDialog].
class _TaskInfoSectionData {
  /// Creates a [_TaskInfoSectionData].
  const _TaskInfoSectionData({
    this.details = const <String>[],
    required this.icon,
    required this.keyPrefix,
    this.labels = const <TdfLabel>[],
    this.noteBody,
    this.noteKey,
    this.progressValue,
    required this.title,
    required this.value,
  });

  /// Additional detail lines rendered beneath [value].
  final List<String> details;

  /// Leading icon representing this indicator category.
  final IconData icon;

  /// Indicator key prefix (`<prefix>_task_indicator` or `due_task_badge`).
  final String keyPrefix;

  /// Resolved labels when rendering the labels section.
  final List<TdfLabel> labels;

  /// Optional multi-line scheduling note rendered below [details].
  final String? noteBody;

  /// Optional widget key attached to the rendered [SelectableText] note body.
  final Key? noteKey;

  /// Optional progress fraction (`0.0` to `1.0`) for completion bars.
  final double? progressValue;

  /// Localized section heading.
  final String title;

  /// Primary localized status value.
  final String value;
}

/// Stateless builder assembling active metadata indicator cards for [TaskInfoDialog].
class _TaskInfoSectionsBuilder {
  const _TaskInfoSectionsBuilder._();

  /// Collects all active [_TaskInfoSectionData] entries for [currentTask].
  static List<_TaskInfoSectionData> buildSections({
    required TaskBoard board,
    required WebDavConfig configuration,
    required TaskItem currentTask,
    required AppLocalizations localizations,
    required DateTime nowUtc,
  }) {
    return <_TaskInfoSectionData>[
      ?_buildPrioritySection(currentTask, localizations),
      ?_buildSuspendedSection(
        currentTask,
        configuration,
        localizations,
        nowUtc,
      ),
      ?_buildDueSection(currentTask, configuration, localizations, nowUtc),
      ?_buildBlockedBySection(currentTask, board, localizations),
      ?_buildConditionsSection(currentTask, board, localizations),
      ?_buildRepeatSection(currentTask, localizations),
      ?_buildLabelsSection(currentTask, board, localizations),
      ?_buildNoteSection(currentTask, localizations),
      ?_buildLinksSection(currentTask, localizations),
      ?_buildSubtasksSection(currentTask, localizations),
    ];
  }

  /// Builds the prerequisite tasks section when [task] is actively blocked by prerequisites on [board].
  static _TaskInfoSectionData? _buildBlockedBySection(
    TaskItem task,
    TaskBoard board,
    AppLocalizations localizations,
  ) {
    if (task.dependencies.isEmpty) {
      return null;
    }
    var satisfiedCount = 0;
    var hasUnsatisfied = false;
    final details = <String>[];
    for (final dependency in task.dependencies) {
      if (board.deletedBlock.findTaskRecord(dependency.taskId) != null) {
        continue;
      }
      final target = board.findTask(dependency.taskId);
      final isSatisfied =
          target == null || target.completions >= dependency.requiredCompletion;
      if (isSatisfied) {
        satisfiedCount++;
      } else {
        hasUnsatisfied = true;
      }
      details.add(target?.title ?? dependency.taskId);
    }
    if (!hasUnsatisfied) {
      return null;
    }
    return _TaskInfoSectionData(
      details: details,
      icon: Icons.lock_outline_rounded,
      keyPrefix: 'blocked_by_task_indicator',
      title: localizations.taskBlockedBySectionTitle,
      value: localizations.taskInfoBlockedByProgress(
        satisfiedCount.toString(),
        details.length.toString(),
      ),
    );
  }

  /// Builds the activation conditions section when [task] declares conditions.
  static _TaskInfoSectionData? _buildConditionsSection(
    TaskItem task,
    TaskBoard board,
    AppLocalizations localizations,
  ) {
    if (task.conditions.isEmpty) {
      return null;
    }
    final formattedConditions = <String>[
      for (final condition in task.conditions)
        formatConditionSummary(condition, board.locations, localizations),
    ];
    return _TaskInfoSectionData(
      details: formattedConditions.skip(1).toList(),
      icon: Icons.tune_rounded,
      keyPrefix: 'conditions_task_indicator',
      title: localizations.taskConditionsSectionTitle,
      value: formattedConditions.first,
    );
  }

  /// Builds the due deadline section when [task] has a `due` timestamp.
  static _TaskInfoSectionData? _buildDueSection(
    TaskItem task,
    WebDavConfig configuration,
    AppLocalizations localizations,
    DateTime nowUtc,
  ) {
    final dueAt = task.dueAt;
    if (dueAt == null) {
      return null;
    }
    final normalizedNow = TaskItem.normalizeTimestamp(nowUtc);
    final localDue = configuration.toLocalWallClock(dueAt);
    final timestamp = TaskItem.formatTdfTimestamp(localDue);
    final valueText = dueAt.isAfter(normalizedNow)
        ? localizations.taskInfoDueAt(
            timestamp,
            TaskInfoController.formatRemainingDuration(
              dueAt.difference(normalizedNow),
              localizations,
            ),
          )
        : localizations.taskInfoDueOverdue(timestamp);
    return _TaskInfoSectionData(
      details: _buildDueStatusDetails(
        task,
        configuration,
        localizations,
        normalizedNow,
        localDue,
      ),
      icon: Icons.event_rounded,
      keyPrefix: 'due_task_badge',
      noteBody: task.dueNote,
      noteKey: const ValueKey('task_info_due_note'),
      title: localizations.taskInfoDueLabel,
      value: valueText,
    );
  }

  /// Resolves the exhaustive deadline auto-priority status and schedule-anchor detail lines for [task].
  static List<String> _buildDueStatusDetails(
    TaskItem task,
    WebDavConfig configuration,
    AppLocalizations localizations,
    DateTime normalizedNow,
    DateTime localDue,
  ) {
    if (task.isCompleted || task.completedAt != null) {
      return const <String>[];
    }
    final statusLine = _resolvePrimaryDueStatusLine(
      task,
      configuration,
      localizations,
      normalizedNow,
    );
    if (task.dueAnchor case final anchor?
        when TaskInfoController.differsFromWallClock(anchor, localDue)) {
      return <String>[
        statusLine,
        localizations.taskInfoDueAnchorDetail(anchor.formatCompact()),
      ];
    }
    return <String>[statusLine];
  }

  /// Builds the assigned labels section when [task] references defined labels.
  static _TaskInfoSectionData? _buildLabelsSection(
    TaskItem task,
    TaskBoard board,
    AppLocalizations localizations,
  ) {
    if (task.labelIds.isEmpty) {
      return null;
    }
    final resolvedLabels = resolveTaskLabels(board.sortedLabels, task.labelIds);
    if (resolvedLabels.isEmpty) {
      return null;
    }
    return _TaskInfoSectionData(
      icon: Icons.label_outline_rounded,
      keyPrefix: 'labels_task_indicator',
      labels: resolvedLabels,
      title: localizations.taskLabelsSectionTitle,
      value: '',
    );
  }

  /// Builds the links section when [task] has attached links.
  static _TaskInfoSectionData? _buildLinksSection(
    TaskItem task,
    AppLocalizations localizations,
  ) {
    if (task.links.isEmpty) {
      return null;
    }
    final details = <String>[for (final link in task.links) link.title];
    return _TaskInfoSectionData(
      details: details,
      icon: Icons.link_rounded,
      keyPrefix: 'links_task_indicator',
      title: localizations.linksSectionTitle,
      value: localizations.taskInfoLinksCount(task.links.length.toString()),
    );
  }

  /// Builds the note section when [task] has a non-empty note.
  static _TaskInfoSectionData? _buildNoteSection(
    TaskItem task,
    AppLocalizations localizations,
  ) {
    final note = task.note;
    if (note == null || note.isEmpty) {
      return null;
    }
    return _TaskInfoSectionData(
      icon: Icons.notes_rounded,
      keyPrefix: 'note_task_indicator',
      title: localizations.taskNoteLabel,
      value: note,
    );
  }

  /// Builds the priority section when [task] is marked as priority.
  static _TaskInfoSectionData? _buildPrioritySection(
    TaskItem task,
    AppLocalizations localizations,
  ) {
    if (!task.isPriority) {
      return null;
    }
    return _TaskInfoSectionData(
      icon: Icons.priority_high_rounded,
      keyPrefix: 'priority_task_indicator',
      title: localizations.quickAddPriority,
      value: localizations.taskInfoPriorityValue,
    );
  }

  /// Builds the repeat recurrence section when [task] has a `repeat` rule.
  static _TaskInfoSectionData? _buildRepeatSection(
    TaskItem task,
    AppLocalizations localizations,
  ) {
    final repeatRule = task.repeatRule;
    if (repeatRule == null) {
      return null;
    }
    final unitLabel = _formatRepeatUnit(repeatRule.unit, localizations);
    final details = <String>[
      if (task.completions > 0)
        localizations.taskInfoRepeatCompletions(task.completions.toString()),
      if (repeatRule.leadDays > 0 && task.dueAt != null)
        localizations.taskInfoRepeatLeadDays(repeatRule.leadDays.toString()),
    ];
    return _TaskInfoSectionData(
      details: details,
      icon: Icons.repeat_rounded,
      keyPrefix: 'repeat_task_indicator',
      title: localizations.repeatFlagLabel,
      value: localizations.taskInfoRepeatEvery(
        repeatRule.count.toString(),
        unitLabel,
      ),
    );
  }

  /// Builds the subtasks progress section when [task] has subtasks.
  static _TaskInfoSectionData? _buildSubtasksSection(
    TaskItem task,
    AppLocalizations localizations,
  ) {
    if (task.subtasks.isEmpty) {
      return null;
    }
    var completedCount = 0;
    for (final subtask in task.subtasks) {
      if (subtask.isCompleted) {
        completedCount++;
      }
    }
    final totalCount = task.subtasks.length;
    final details = <String>[
      if (task.subtasksAutoFinish)
        localizations.taskInfoSubtasksAutoFinishSuffix,
    ];
    return _TaskInfoSectionData(
      details: details,
      icon: task.subtasksAutoFinish
          ? Icons.task_alt_rounded
          : Icons.checklist_rounded,
      keyPrefix: 'subtasks_task_indicator',
      progressValue: completedCount / totalCount,
      title: localizations.subtasksSectionTitle,
      value: localizations.taskInfoSubtasksProgress(
        completedCount.toString(),
        totalCount.toString(),
      ),
    );
  }

  /// Builds the suspension section when [task] has an active deferral at [nowUtc].
  static _TaskInfoSectionData? _buildSuspendedSection(
    TaskItem task,
    WebDavConfig configuration,
    AppLocalizations localizations,
    DateTime nowUtc,
  ) {
    if (!task.hasActiveSuspendedAt(nowUtc)) {
      return null;
    }
    final suspendedAt = task.suspendedAt;
    if (task.isSuspendedForever ||
        suspendedAt == null ||
        suspendedAt == TaskItem.defaultSuspendedAt) {
      return _TaskInfoSectionData(
        icon: Icons.pause_circle_outline_rounded,
        keyPrefix: 'suspended_task_indicator',
        noteBody: task.suspendedNote,
        noteKey: const ValueKey('task_info_suspended_note'),
        title: localizations.taskSuspendedLabel,
        value: localizations.taskInfoSuspendedForever,
      );
    }
    final localSuspended = configuration.toLocalWallClock(suspendedAt);
    final timestamp = TaskItem.formatTdfTimestamp(localSuspended);
    final valueText = localizations.taskInfoSuspendedUntil(
      timestamp,
      TaskInfoController.formatRemainingDuration(
        suspendedAt.difference(TaskItem.normalizeTimestamp(nowUtc)),
        localizations,
      ),
    );
    return _TaskInfoSectionData(
      icon: Icons.pause_circle_outline_rounded,
      keyPrefix: 'suspended_task_indicator',
      noteBody: task.suspendedNote,
      noteKey: const ValueKey('task_info_suspended_note'),
      title: localizations.taskSuspendedLabel,
      value: valueText,
    );
  }

  /// Resolves the localized label for [unit].
  static String _formatRepeatUnit(
    RepeatUnit unit,
    AppLocalizations localizations,
  ) {
    return switch (unit) {
      RepeatUnit.days => localizations.repeatUnitDays,
      RepeatUnit.weeks => localizations.repeatUnitWeeks,
      RepeatUnit.months => localizations.repeatUnitMonths,
    };
  }

  /// Resolves the primary deadline auto-priority status line for an open [task].
  static String _resolvePrimaryDueStatusLine(
    TaskItem task,
    WebDavConfig configuration,
    AppLocalizations localizations,
    DateTime normalizedNow,
  ) {
    if (task.isDuePassive) {
      return localizations.taskInfoDuePassiveHint;
    }
    final leadWindow = configuration.dueLeadWindow;
    if (leadWindow == DueLeadWindow.off) {
      return localizations.taskInfoDueLeadWindowOffHint;
    }
    if (task.isWithinDueLeadWindow(normalizedNow, leadWindow.duration)) {
      return localizations.taskInfoDueAutoPromotedActive;
    }
    return switch (leadWindow) {
      DueLeadWindow.off => localizations.taskInfoDueLeadWindowOffHint,
      DueLeadWindow.atDue => localizations.taskInfoDueAutoPromoteAtDue,
      DueLeadWindow.hours12 => localizations.taskInfoDueAutoPromoteScheduled(
        localizations.dueLeadWindowShort12Hours,
      ),
      DueLeadWindow.hours24 => localizations.taskInfoDueAutoPromoteScheduled(
        localizations.dueLeadWindowShort24Hours,
      ),
      DueLeadWindow.hours48 => localizations.taskInfoDueAutoPromoteScheduled(
        localizations.dueLeadWindowShort48Hours,
      ),
      DueLeadWindow.days7 => localizations.taskInfoDueAutoPromoteScheduled(
        localizations.dueLeadWindowShort7Days,
      ),
    };
  }
}

/// Opens [TaskInfoDialog] as a modal overlay for [task].
Future<void> showTaskInfoDialog(
  BuildContext context, {
  String? initialIndicatorKeyPrefix,
  required TaskItem task,
}) {
  UiTelemetry.logTaskInfoDialogOpened(
    taskId: task.id,
    initialIndicatorKeyPrefix: initialIndicatorKeyPrefix,
  );
  return showDialog<void>(
    context: context,
    builder: (_) => TaskInfoDialog(
      initialIndicatorKeyPrefix: initialIndicatorKeyPrefix,
      task: task,
    ),
  );
}
