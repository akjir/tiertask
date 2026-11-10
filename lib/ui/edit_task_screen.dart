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

import '../l10n/app_localizations.dart';
import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/webdav_config.dart';
import '../providers/config_providers.dart';
import '../providers/task_providers.dart';
import '../repositories/link_launcher_repository.dart';
import '../services/app_logger.dart';
import 'widgets/condition_editor_controller.dart';
import 'widgets/task_editor_conditions_section.dart';
import 'widgets/task_editor_links_section.dart';
import 'widgets/task_editor_scheduling_card.dart';
import 'widgets/task_editor_sections.dart';
import 'widgets/task_editor_subtasks_and_blockers.dart';

/// Dedicated panel screen used for both extended task creation and editing an existing task.
class EditTaskScreen extends ConsumerStatefulWidget {
  /// Creates an [EditTaskScreen].
  const EditTaskScreen({
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
  ConsumerState<EditTaskScreen> createState() => _EditTaskScreenState();
}

/// Confirmation dialog shown before deleting an existing task from [EditTaskScreen].
class _DeleteTaskConfirmDialog extends StatelessWidget {
  /// Creates a [_DeleteTaskConfirmDialog].
  const _DeleteTaskConfirmDialog({required this.taskTitle});

  /// Title of the task pending deletion.
  final String taskTitle;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('delete_task_confirm_dialog'),
      title: Text(localizations.deleteTaskDialogTitle),
      content: Text(localizations.deleteTaskConfirmMessage(taskTitle)),
      actions: [
        TextButton(
          key: const ValueKey('delete_task_cancel_button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(localizations.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('delete_task_confirm_button'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(localizations.actionDelete),
        ),
      ],
    );
  }
}

/// Settings-style scrollable card column inside [EditTaskScreen].
class _EditTaskFormColumn extends StatelessWidget {
  /// Creates an [_EditTaskFormColumn].
  const _EditTaskFormColumn({required this.board, required this.state});

  /// Current [TaskBoard] snapshot.
  final TaskBoard board;

  /// Owning [_EditTaskScreenState] coordinating form controllers and callbacks.
  final _EditTaskScreenState state;

  @override
  Widget build(BuildContext context) {
    final candidates = TaskEditorBoardHelper.collectCandidateBlockerTasks(
      board: board,
      currentTaskId: state.widget.initialTask?.id,
      selectedBlockedByIds: state._blockedByIds,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditTaskSchedulingSection(state: state),
        const SizedBox(height: 10),
        _EditTaskSubtasksAndLinksSection(board: board, state: state),
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: state._blockedSearchController,
            builder: (context, searchValue, _) => TaskEditorBlockedBySection(
              candidateTasks: candidates,
              disabledTaskIds: TaskEditorBoardHelper.collectDisabledBlockerIds(
                board: board,
                currentTask: state.widget.initialTask,
                candidates: candidates,
              ),
              searchController: state._blockedSearchController,
              searchQuery: searchValue.text,
              selectedBlockedByIds: state._blockedByIds,
              onClearSearch: state._blockedSearchController.clear,
              onToggleBlockedBy: (id) => state._toggleBlockedBy(board, id),
            ),
          ),
        ],
        const SizedBox(height: 10),
        TaskEditorConditionsSection(
          controller: state._conditionController,
          availableLocations: board.sortedLocations,
          isSuspended: state._isSuspended,
        ),
      ],
    );
  }
}

/// Body layout inside [EditTaskScreen] separating scrollable form cards from bottom actions.
class _EditTaskScaffoldBody extends StatelessWidget {
  /// Creates an [_EditTaskScaffoldBody].
  const _EditTaskScaffoldBody({
    required this.board,
    required this.isEditing,
    required this.state,
  });

  /// Current [TaskBoard] snapshot.
  final TaskBoard board;

  /// Whether [EditTaskScreen] is editing an existing task.
  final bool isEditing;

  /// Owning [_EditTaskScreenState].
  final _EditTaskScreenState state;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _EditTaskFormColumn(board: board, state: state),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TaskEditorActionsRow(
              onCancel: () => Navigator.of(context).pop(),
              onDelete: isEditing ? state._confirmDeleteTask : null,
              onSave: state._submit,
            ),
          ),
        ],
      ),
    );
  }
}

/// Details and scheduling cards wired to [_EditTaskScreenState].
class _EditTaskSchedulingSection extends StatelessWidget {
  /// Creates an [_EditTaskSchedulingSection].
  const _EditTaskSchedulingSection({required this.state});

  /// Owning [_EditTaskScreenState].
  final _EditTaskScreenState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskEditorDetailsCard(
          titleController: state._titleController,
          noteController: state._noteController,
          errorMessage: state._errorMessage,
          onSubmit: state._submit,
        ),
        const SizedBox(height: 10),
        TaskEditorSchedulingCard(
          dueController: state._dueController,
          dueErrorMessage: state._dueErrorMessage,
          hasDue: state._hasDue,
          isRepeating: state._isRepeating,
          isSuspended: state._isSuspended,
          mode: state._mode,
          repeatCountController: state._repeatCountController,
          repeatErrorMessage: state._repeatErrorMessage,
          repeatUnit: state._repeatUnit,
          suspendedController: state._suspendedController,
          suspendedErrorMessage: state._suspendedErrorMessage,
          onClearDue: state._dueController.clear,
          onClearSuspended: state._suspendedController.clear,
          onPickDueDate: () => state._pickDueTimestamp(
            TaskEditorSuspendedField.pickSuspendedDate,
          ),
          onPickDueTime: () => state._pickDueTimestamp(
            TaskEditorSuspendedField.pickSuspendedTime,
          ),
          onPickSuspendedDate: () => state._pickSuspendedTimestamp(
            TaskEditorSuspendedField.pickSuspendedDate,
          ),
          onPickSuspendedTime: () => state._pickSuspendedTimestamp(
            TaskEditorSuspendedField.pickSuspendedTime,
          ),
          onSelectRepeatUnit: (unit) =>
              state._update(() => state._repeatUnit = unit),
          onToggleDue: () =>
              state._update(() => state._hasDue = !state._hasDue),
          onTogglePriority: () => state._toggleMode(QuickAddMode.priority),
          onToggleRepeat: () =>
              state._update(() => state._isRepeating = !state._isRepeating),
          onToggleSomeday: () => state._toggleMode(QuickAddMode.someday),
          onToggleSuspended: () =>
              state._update(() => state._isSuspended = !state._isSuspended),
        ),
      ],
    );
  }
}

/// State for [EditTaskScreen].
class _EditTaskScreenState extends ConsumerState<EditTaskScreen> {
  late bool _autoFinish;
  late final Set<String> _blockedByIds;
  final _blockedSearchController = TextEditingController();
  late final ConditionEditorController _conditionController;
  late final TextEditingController _dueController;
  String? _dueErrorMessage;
  String? _errorMessage;
  late bool _hasDue;
  bool _hasSubtaskText = false;
  late bool _isRepeating;
  late bool _isSuspended;
  late final Set<String> _labelIds;
  bool _lastCanAddLink = false;
  String? _linkErrorMessage;
  final _linkTitleController = TextEditingController();
  final _linkUriController = TextEditingController();
  late final List<TaskLink> _links;
  late QuickAddMode _mode;
  late final TextEditingController _noteController;
  late final TextEditingController _repeatCountController;
  String? _repeatErrorMessage;
  late RepeatUnit _repeatUnit;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final _subtaskController = TextEditingController();
  late final List<SubtaskItem> _subtasks;
  late final TextEditingController _suspendedController;
  String? _suspendedErrorMessage;
  late final TextEditingController _titleController;

  /// Whether the add-link button is currently enabled.
  bool get _canAddLink =>
      _links.length < TaskLink.maxLinksPerTask &&
      (_linkTitleController.text.trim().isNotEmpty ||
          _linkUriController.text.trim().isNotEmpty);

  /// Whether [EditTaskScreen] is currently editing a completed task.
  bool get _isCompletedTask =>
      (widget.initialTask?.isCompleted ?? false) ||
      widget.initialTask?.completedAt != null;

  /// Subtask step toggle callback, or `null` when editing a completed task.
  ValueChanged<int>? get _subtaskStepToggle =>
      _isCompletedTask ? null : _toggleSubtaskStep;

  @override
  void initState() {
    super.initState();
    final task = widget.initialTask;
    final initialBoard =
        ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    _titleController = TextEditingController(
      text: task?.title ?? widget.initialTitle,
    )..addListener(_handleTitleChanged);
    _noteController = TextEditingController(text: task?.note ?? '');
    _mode = task != null
        ? TaskEditorBoardHelper.resolveInitialMode(task, initialBoard)
        : widget.initialMode;
    _labelIds = Set.of(task?.labelIds ?? widget.initialLabelIds);
    _autoFinish = task?.subtasksAutoFinish ?? false;
    _subtasks = List.of(task?.subtasks ?? const []);
    _links = List.of(task?.links ?? const []);
    _blockedByIds = Set.of(task?.blockedByTaskIds ?? const []);
    _isSuspended = task?.suspendedAt != null;
    _suspendedController = TextEditingController(
      text: TaskEditorSuspendedField.formatInitialText(task?.suspendedAt),
    )..addListener(_handleSuspendedChanged);
    _hasDue = task?.dueAt != null;
    _dueController = TextEditingController(
      text: TaskEditorSuspendedField.formatInitialText(task?.dueAt),
    )..addListener(_handleDueChanged);
    _isRepeating = task?.repeatRule != null;
    _repeatCountController = TextEditingController(
      text: (task?.repeatRule?.count ?? 1).toString(),
    )..addListener(_handleRepeatCountChanged);
    _repeatUnit = task?.repeatRule?.unit ?? RepeatUnit.days;
    _conditionController = ConditionEditorController(
      initialConditions: task?.conditions ?? const [],
    );
    _subtaskController.addListener(_handleSubtaskInputChanged);
    _linkTitleController.addListener(_handleLinkInputChanged);
    _linkUriController.addListener(_handleLinkInputChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _subtaskController.dispose();
    _linkTitleController.dispose();
    _linkUriController.dispose();
    _suspendedController.dispose();
    _dueController.dispose();
    _repeatCountController.dispose();
    _blockedSearchController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(
      taskNotifierProvider.select(
        (asyncBoard) => asyncBoard.asData?.value ?? TaskBoard.empty(),
      ),
    );
    final localizations = AppLocalizations.of(context);
    final isEditing = widget.initialTask != null;
    final title = isEditing
        ? localizations.editTaskTitle
        : localizations.advancedTaskTitle;
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        key: const ValueKey('edit_task_screen'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: Text(title)),
        body: _EditTaskScaffoldBody(
          board: board,
          isEditing: isEditing,
          state: this,
        ),
      ),
    );
  }

  /// Validates and appends the current link title and URI to [_links].
  bool _addLink() {
    final localizations = AppLocalizations.of(context);
    if (_links.length >= TaskLink.maxLinksPerTask) {
      setState(() => _linkErrorMessage = localizations.linkErrorMaxExceeded);
      return false;
    }
    final parsed = TaskLink.tryParse(
      rawTitle: _linkTitleController.text,
      rawUri: _linkUriController.text,
    );
    if (parsed == null) {
      setState(() => _linkErrorMessage = localizations.linkErrorInvalid);
      return false;
    }
    setState(() {
      _links.add(parsed);
      _lastCanAddLink = false;
      _linkErrorMessage = null;
      _linkTitleController.clear();
      _linkUriController.clear();
    });
    return true;
  }

  /// Appends the current non-empty subtask text to [_subtasks].
  void _addSubtask() {
    final text = _subtaskController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add(SubtaskItem(title: text, isCompleted: _isCompletedTask));
      _hasSubtaskText = false;
      _subtaskController.clear();
    });
  }

  /// Validates any pending link input and assembles the [_ValidatedTaskDraft] for saving.
  _ValidatedTaskDraft? _buildDraft(
    TaskBoard board,
    DateTime? suspendedAt,
    DateTime? dueAt,
    TaskRepeatRule? repeatRule,
  ) {
    final hasPendingLink =
        _linkTitleController.text.trim().isNotEmpty ||
        _linkUriController.text.trim().isNotEmpty;
    if (hasPendingLink && !_addLink()) return null;
    final pendingSubtask = _subtaskController.text.trim();
    return (
      blockedByIds: TaskEditorBoardHelper.collectOrderedBlockedByIds(
        board,
        _blockedByIds,
      ),
      dueAt: dueAt,
      labelIds: TaskEditorBoardHelper.collectOrderedLabelIds(board, _labelIds),
      links: _links,
      repeatRule: repeatRule,
      subtasks: <SubtaskItem>[
        ..._subtasks,
        if (pendingSubtask.isNotEmpty)
          SubtaskItem(title: pendingSubtask, isCompleted: _isCompletedTask),
      ],
      suspendedAt: suspendedAt,
    );
  }

  /// Prompts for confirmation and deletes [EditTaskScreen.initialTask] when confirmed.
  Future<void> _confirmDeleteTask() async {
    final existingTask = widget.initialTask;
    if (existingTask == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteTaskConfirmDialog(taskTitle: existingTask.title),
    );
    if (!mounted || confirmed != true) return;
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.delete_task.confirmed',
      fields: <String, Object?>{'id': existingTask.id},
    );
    await ref.read(taskNotifierProvider.notifier).deleteTask(existingTask.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Clears any due timestamp validation error when the user edits the due field.
  void _handleDueChanged() {
    if (_dueErrorMessage != null) {
      setState(() => _dueErrorMessage = null);
    }
  }

  /// Rebuilds when the add-link button state changes or clears any active link validation error.
  void _handleLinkInputChanged() {
    final canAdd = _canAddLink;
    if (canAdd == _lastCanAddLink && _linkErrorMessage == null) return;
    setState(() {
      _lastCanAddLink = canAdd;
      _linkErrorMessage = null;
    });
  }

  /// Clears any repeat interval validation error when the user edits the repeat count field.
  void _handleRepeatCountChanged() {
    if (_repeatErrorMessage != null) {
      setState(() => _repeatErrorMessage = null);
    }
  }

  /// Rebuilds only when the subtask text transitions between empty and non-empty.
  void _handleSubtaskInputChanged() {
    final hasText = _subtaskController.text.trim().isNotEmpty;
    if (hasText != _hasSubtaskText) {
      setState(() => _hasSubtaskText = hasText);
    }
  }

  /// Clears any suspended timestamp validation error when the user edits the suspended field.
  void _handleSuspendedChanged() {
    if (_suspendedErrorMessage != null) {
      setState(() => _suspendedErrorMessage = null);
    }
  }

  /// Clears any validation error when the user edits the title field.
  void _handleTitleChanged() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  /// Opens [uri] via [linkLauncherRepositoryProvider] and displays a SnackBar if launching fails.
  Future<void> _openLink(String uri) async {
    try {
      await ref.read(linkLauncherRepositoryProvider).openLink(uri);
    } on LinkLaunchException {
      if (!mounted) return;
      final text = AppLocalizations.of(context).errorOpenLinkFailed;
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(text)),
      );
    }
  }

  /// Persists the validated [draft] through [TaskNotifier].
  Future<void> _persistTask(_ValidatedTaskDraft draft) {
    final note = _noteController.text.trim();
    final notifier = ref.read(taskNotifierProvider.notifier);
    if (widget.initialTask case final existingTask?) {
      return notifier.updateTask(
        existingTask.id,
        title: _titleController.text.trim(),
        note: note,
        targetTier: _mode.targetTier,
        isPriority: _mode == QuickAddMode.priority,
        subtasksAutoFinish: _autoFinish,
        subtasks: draft.subtasks,
        labelIds: draft.labelIds,
        dueAt: draft.dueAt,
        clearDueAt: !_hasDue,
        origin: existingTask.origin,
        suspendedAt: draft.suspendedAt,
        clearSuspendedAt: !_isSuspended,
        repeatRule: draft.repeatRule,
        clearRepeatRule: !_isRepeating,
        blockedByTaskIds: draft.blockedByIds,
        links: draft.links,
        conditions: _conditionController.buildConditions(),
      );
    }
    return notifier.addTask(
      _titleController.text.trim(),
      note: note.isEmpty ? null : note,
      targetTier: _mode.targetTier,
      isPriority: _mode == QuickAddMode.priority,
      subtasksAutoFinish: _autoFinish,
      subtasks: draft.subtasks,
      labelIds: draft.labelIds,
      dueAt: draft.dueAt,
      suspendedAt: draft.suspendedAt,
      repeatRule: draft.repeatRule,
      blockedByTaskIds: draft.blockedByIds,
      links: draft.links,
      conditions: _conditionController.buildConditions(),
    );
  }

  /// Opens [picker] and updates [_dueController] with the selected date or time.
  Future<void> _pickDueTimestamp(
    Future<String?> Function({
      required BuildContext context,
      required String currentText,
      required DateTime fallbackDate,
    })
    picker,
  ) async {
    final config =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final now = config.toLocalWallClock(ref.read(clockProvider)().toUtc());
    final updated = await picker(
      context: context,
      currentText: _dueController.text,
      fallbackDate: now,
    );
    if (!mounted || updated == null) return;
    setState(() {
      _dueController.text = updated;
      _dueErrorMessage = null;
    });
  }

  /// Opens [picker] and updates [_suspendedController] with the selected date or time.
  Future<void> _pickSuspendedTimestamp(
    Future<String?> Function({
      required BuildContext context,
      required String currentText,
      required DateTime fallbackDate,
    })
    picker,
  ) async {
    final config =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final now = config.toLocalWallClock(ref.read(clockProvider)().toUtc());
    final updated = await picker(
      context: context,
      currentText: _suspendedController.text,
      fallbackDate: now,
    );
    if (!mounted || updated == null) return;
    setState(() {
      _suspendedController.text = updated;
      _suspendedErrorMessage = null;
    });
  }

  /// Removes the link at [index].
  void _removeLink(int index) {
    if (index < 0 || index >= _links.length) return;
    setState(() {
      _links.removeAt(index);
      _lastCanAddLink = _canAddLink;
      _linkErrorMessage = null;
    });
  }

  /// Removes the subtask step at [index].
  void _removeSubtask(int index) {
    if (index < 0 || index >= _subtasks.length) return;
    setState(() => _subtasks.removeAt(index));
  }

  /// Validates the task inputs and saves the created or updated task.
  Future<void> _submit() async {
    final board =
        ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);
    final titleError = TaskEditorBoardHelper.validateTitle(
      board: board,
      rawTitle: _titleController.text,
      excludingTaskId: widget.initialTask?.id,
      localizations: localizations,
    );
    final suspendedAt = TaskEditorSuspendedField.parseSuspendedTimestamp(
      isSuspended: _isSuspended,
      rawText: _suspendedController.text,
    );
    final dueAt = _hasDue
        ? TaskItem.tryParseTdfTimestampInput(_dueController.text.trim())
        : null;
    final repeatRule = TaskEditorRepeatField.parseRepeatRule(
      isRepeating: _isRepeating,
      rawCount: _repeatCountController.text,
      unit: _repeatUnit,
    );
    if (titleError != null ||
        (_isSuspended && suspendedAt == null) ||
        (_hasDue && dueAt == null) ||
        (_isRepeating && repeatRule == null)) {
      setState(() {
        _errorMessage = titleError;
        if (titleError == null && _isSuspended && suspendedAt == null) {
          _suspendedErrorMessage = localizations.taskSuspendedErrorInvalid;
        } else if (titleError == null && _hasDue && dueAt == null) {
          _dueErrorMessage = localizations.taskSuspendedErrorInvalid;
        } else if (titleError == null) {
          _repeatErrorMessage = localizations.repeatErrorInvalid;
        }
      });
      return;
    }
    final draft = _buildDraft(board, suspendedAt, dueAt, repeatRule);
    if (draft == null) return;
    await _persistTask(draft);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onSubmitted?.call();
  }

  /// Toggles prerequisite [taskId] if it does not introduce a dependency cycle.
  void _toggleBlockedBy(TaskBoard board, String taskId) {
    if (widget.initialTask case final currentTask?
        when board.wouldCreateDependencyCycle(currentTask.id, taskId)) {
      return;
    }
    setState(() {
      if (!_blockedByIds.remove(taskId)) _blockedByIds.add(taskId);
    });
  }

  /// Toggles [_mode] between [target] and [QuickAddMode.standard].
  void _toggleMode(QuickAddMode target) {
    setState(() => _mode = _mode == target ? QuickAddMode.standard : target);
  }

  /// Toggles completion state of the subtask step at [index].
  void _toggleSubtaskStep(int index) {
    if (_isCompletedTask || index < 0 || index >= _subtasks.length) return;
    final step = _subtasks[index];
    setState(
      () => _subtasks[index] = step.copyWith(isCompleted: !step.isCompleted),
    );
  }

  /// Applies [callback] inside [setState] to update form state.
  void _update(VoidCallback callback) => setState(callback);
}

/// Labels, subtasks, and links sections wired to [_EditTaskScreenState].
class _EditTaskSubtasksAndLinksSection extends StatelessWidget {
  /// Creates an [_EditTaskSubtasksAndLinksSection].
  const _EditTaskSubtasksAndLinksSection({
    required this.board,
    required this.state,
  });

  /// Current [TaskBoard] snapshot.
  final TaskBoard board;

  /// Owning [_EditTaskScreenState].
  final _EditTaskScreenState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskEditorContextSection(
          labels: board.sortedLabels,
          selectedLabelIds: state._labelIds,
          onToggleLabel: (id) => state._update(() {
            if (!state._labelIds.remove(id)) state._labelIds.add(id);
          }),
        ),
        if (board.sortedLabels.isNotEmpty) const SizedBox(height: 10),
        TaskEditorSubtasksSection(
          hasSubtaskText: state._hasSubtaskText,
          subtaskController: state._subtaskController,
          subtasks: state._subtasks,
          subtasksAutoFinish: state._autoFinish,
          onAddSubtask: state._addSubtask,
          onRemoveSubtask: state._removeSubtask,
          onToggleAutoFinish: () =>
              state._update(() => state._autoFinish = !state._autoFinish),
          onToggleSubtaskStep: state._subtaskStepToggle,
        ),
        const SizedBox(height: 10),
        TaskEditorLinksSection(
          canAddLink: state._canAddLink,
          errorMessage: state._linkErrorMessage,
          links: state._links,
          titleController: state._linkTitleController,
          uriController: state._linkUriController,
          onAddLink: state._addLink,
          onOpenLink: state._openLink,
          onRemoveLink: state._removeLink,
        ),
      ],
    );
  }
}

/// Validated task collections and scheduling metadata passed to [_EditTaskScreenState._persistTask].
typedef _ValidatedTaskDraft = ({
  List<String> blockedByIds,
  DateTime? dueAt,
  List<String> labelIds,
  List<TaskLink> links,
  TaskRepeatRule? repeatRule,
  List<SubtaskItem> subtasks,
  DateTime? suspendedAt,
});

/// Pushes [EditTaskScreen] onto the navigation stack for extended task creation or task editing.
Future<void> openEditTaskScreen(
  BuildContext context, {
  TaskItem? initialTask,
  String initialTitle = '',
  QuickAddMode initialMode = QuickAddMode.standard,
  Set<String> initialLabelIds = const <String>{},
  VoidCallback? onSubmitted,
}) {
  AppLogger.info(
    LogTag.ui,
    'Opened EditTaskScreen task=${initialTask?.id ?? "new"}',
  );
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => EditTaskScreen(
        initialTask: initialTask,
        initialTitle: initialTitle,
        initialMode: initialMode,
        initialLabelIds: initialLabelIds,
        onSubmitted: onSubmitted,
      ),
    ),
  );
}
