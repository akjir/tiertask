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
import '../models/webdav_config.dart';
import '../providers/task_providers.dart';
import '../repositories/link_launcher_repository.dart';
import '../services/app_logger.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/task_editor_conditions_section.dart';
import 'widgets/task_editor_links_section.dart';
import 'widgets/task_editor_sections.dart';

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

/// State for [EditTaskScreen].
class _EditTaskScreenState extends ConsumerState<EditTaskScreen> {
  late final Set<String> _blockedByTaskIds;
  final TextEditingController _blockedSearchController =
      TextEditingController();
  late final ConditionEditorController _conditionController;
  String? _errorMessage;
  late bool _isRepeating;
  late bool _isSuspended;
  String? _linkErrorMessage;
  final TextEditingController _linkTitleController = TextEditingController();
  final TextEditingController _linkUriController = TextEditingController();
  late final List<TaskLink> _links;
  late QuickAddMode _mode;
  late final TextEditingController _noteController;
  late final TextEditingController _repeatCountController;
  String? _repeatErrorMessage;
  late RepeatUnit _repeatUnit;
  late final Set<String> _selectedLabelIds;
  final TextEditingController _subtaskController = TextEditingController();
  late final List<SubtaskItem> _subtasks;
  late bool _subtasksAutoFinish;
  late final TextEditingController _suspendedController;
  String? _suspendedErrorMessage;
  late final TextEditingController _titleController;

  /// Whether the add-link button is currently enabled.
  bool get _canAddLink =>
      _links.length < TaskLink.maxLinksPerTask &&
      (_linkTitleController.text.trim().isNotEmpty ||
          _linkUriController.text.trim().isNotEmpty);

  /// Whether the subtask input field currently contains non-whitespace text.
  bool get _hasSubtaskText => _subtaskController.text.trim().isNotEmpty;

  /// Whether [EditTaskScreen] is currently editing a completed task.
  bool get _isCompletedTask {
    if (widget.initialTask case final task?) {
      return task.isCompleted || task.completedAt != null;
    }
    return false;
  }

  /// Whether [EditTaskScreen] is editing an existing task rather than creating a new task.
  bool get _isEditMode => widget.initialTask != null;

  @override
  void initState() {
    super.initState();
    final task = widget.initialTask;
    _titleController = TextEditingController(
      text: task?.title ?? widget.initialTitle,
    );
    _noteController = TextEditingController(text: task?.note ?? '');
    final initialBoard =
        ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    _mode = task != null
        ? _resolveInitialMode(task, initialBoard)
        : widget.initialMode;
    _selectedLabelIds = <String>{
      ...(task != null ? task.labelIds : widget.initialLabelIds),
    };
    _subtasksAutoFinish = task?.subtasksAutoFinish ?? false;
    _subtasks = <SubtaskItem>[if (task != null) ...task.subtasks];
    _links = <TaskLink>[if (task != null) ...task.links];
    _blockedByTaskIds = <String>{if (task != null) ...task.blockedByTaskIds};
    _isSuspended = task?.suspendedAt != null;
    _suspendedController = TextEditingController(
      text: _formatInitialSuspendedText(task?.suspendedAt),
    );
    _isRepeating = task?.repeatRule != null;
    _repeatCountController = TextEditingController(
      text: (task?.repeatRule?.count ?? 1).toString(),
    );
    _repeatUnit = task?.repeatRule?.unit ?? RepeatUnit.days;
    _conditionController = ConditionEditorController(
      initialConditions: task?.conditions ?? const [],
    );

    _titleController.addListener(_handleTitleChanged);
    _subtaskController.addListener(_handleInputStateChanged);
    _linkTitleController.addListener(_handleLinkInputChanged);
    _linkUriController.addListener(_handleLinkInputChanged);
    _suspendedController.addListener(_handleInputStateChanged);
    _repeatCountController.addListener(_handleRepeatCountChanged);
    _blockedSearchController.addListener(_handleInputStateChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
    _subtaskController.removeListener(_handleInputStateChanged);
    _linkTitleController.removeListener(_handleLinkInputChanged);
    _linkUriController.removeListener(_handleLinkInputChanged);
    _suspendedController.removeListener(_handleInputStateChanged);
    _repeatCountController.removeListener(_handleRepeatCountChanged);
    _blockedSearchController.removeListener(_handleInputStateChanged);
    _titleController.dispose();
    _noteController.dispose();
    _subtaskController.dispose();
    _linkTitleController.dispose();
    _linkUriController.dispose();
    _suspendedController.dispose();
    _repeatCountController.dispose();
    _blockedSearchController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);
    final headerTitle = _isEditMode
        ? localizations.editTaskTitle
        : localizations.advancedTaskTitle;

    return Scaffold(
      key: const ValueKey('edit_task_screen'),
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(headerTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _buildFormColumn(board),
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

  /// Validates and appends the current link title and URI to [_links].
  void _addLink() {
    final localizations = AppLocalizations.of(context);
    if (_links.length >= TaskLink.maxLinksPerTask) {
      setState(() {
        _linkErrorMessage = localizations.linkErrorMaxExceeded;
      });
      return;
    }
    final parsed = TaskLink.tryParse(
      rawTitle: _linkTitleController.text,
      rawUri: _linkUriController.text,
    );
    if (parsed == null) {
      setState(() {
        _linkErrorMessage = localizations.linkErrorInvalid;
      });
      return;
    }
    setState(() {
      _links.add(parsed);
      _linkTitleController.clear();
      _linkUriController.clear();
      _linkErrorMessage = null;
    });
  }

  /// Appends the current non-empty subtask text to [_subtasks].
  void _addSubtask() {
    final text = _subtaskController.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _subtasks.add(SubtaskItem(title: text, isCompleted: _isCompletedTask));
      _subtaskController.clear();
    });
  }

  /// Wraps a [showTimePicker] dialog in a 24-hour [MediaQuery] configuration.
  static Widget _build24HourTimePicker(BuildContext context, Widget? child) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child ?? const SizedBox.shrink(),
    );
  }

  /// Builds the Settings-style card column inside [EditTaskScreen].
  Widget _buildFormColumn(TaskBoard board) {
    final candidateTasks = _collectCandidateBlockerTasks(board);
    final disabledIds = _collectDisabledBlockerIds(board, candidateTasks);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskEditorDetailsCard(
          titleController: _titleController,
          noteController: _noteController,
          errorMessage: _errorMessage,
          onSubmit: _submit,
        ),
        const SizedBox(height: 10),
        TaskEditorSchedulingCard(
          isRepeating: _isRepeating,
          isSuspended: _isSuspended,
          mode: _mode,
          repeatCountController: _repeatCountController,
          repeatErrorMessage: _repeatErrorMessage,
          repeatUnit: _repeatUnit,
          suspendedController: _suspendedController,
          suspendedErrorMessage: _suspendedErrorMessage,
          onClearSuspended: _clearSuspendedTimestamp,
          onPickSuspendedDate: _pickSuspendedDate,
          onPickSuspendedTime: _pickSuspendedTime,
          onSelectRepeatUnit: _selectRepeatUnit,
          onTogglePriority: _togglePriority,
          onToggleRepeat: _toggleRepeat,
          onToggleSomeday: _toggleSomeday,
          onToggleSuspended: _toggleSuspended,
        ),
        if (board.sortedLabels.isNotEmpty) ...[
          const SizedBox(height: 10),
          TaskEditorContextSection(
            labels: board.sortedLabels,
            selectedLabelIds: _selectedLabelIds,
            onToggleLabel: _toggleLabel,
          ),
        ],
        const SizedBox(height: 10),
        TaskEditorSubtasksSection(
          hasSubtaskText: _hasSubtaskText,
          subtaskController: _subtaskController,
          subtasks: _subtasks,
          subtasksAutoFinish: _subtasksAutoFinish,
          onAddSubtask: _addSubtask,
          onRemoveSubtask: _removeSubtask,
          onToggleAutoFinish: _toggleAutoFinish,
          onToggleSubtaskStep: _isCompletedTask ? null : _toggleSubtaskStep,
        ),
        const SizedBox(height: 10),
        TaskEditorLinksSection(
          canAddLink: _canAddLink,
          errorMessage: _linkErrorMessage,
          links: _links,
          titleController: _linkTitleController,
          uriController: _linkUriController,
          onAddLink: _addLink,
          onOpenLink: _openLink,
          onRemoveLink: _removeLink,
        ),
        if (candidateTasks.isNotEmpty) ...[
          const SizedBox(height: 10),
          TaskEditorBlockedBySection(
            candidateTasks: candidateTasks,
            disabledTaskIds: disabledIds,
            searchController: _blockedSearchController,
            searchQuery: _blockedSearchController.text,
            selectedBlockedByIds: _blockedByTaskIds,
            onClearSearch: _clearBlockedSearch,
            onToggleBlockedBy: (taskId) => _toggleBlockedBy(board, taskId),
          ),
        ],
        const SizedBox(height: 10),
        TaskEditorConditionsSection(
          controller: _conditionController,
          isSuspended: _isSuspended,
        ),
      ],
    );
  }

  /// Clears the prerequisite task search input field.
  void _clearBlockedSearch() {
    _blockedSearchController.clear();
  }

  /// Clears the optional `suspended` timestamp field.
  void _clearSuspendedTimestamp() {
    setState(() {
      _suspendedController.clear();
      _suspendedErrorMessage = null;
    });
  }

  /// Collects open tasks on [board] that can be referenced in the prerequisites section.
  List<TaskItem> _collectCandidateBlockerTasks(TaskBoard board) {
    final currentId = widget.initialTask?.id;
    return <TaskItem>[
      for (final task in board.allTasks)
        if (task.id != currentId &&
            ((!task.isCompleted && task.completedAt == null) ||
                _blockedByTaskIds.contains(task.id)))
          task,
    ];
  }

  /// Collects candidate prerequisite task IDs that would create a dependency cycle.
  Set<String> _collectDisabledBlockerIds(
    TaskBoard board,
    List<TaskItem> candidates,
  ) {
    final currentTask = widget.initialTask;
    if (currentTask == null) {
      return const <String>{};
    }
    return <String>{
      for (final candidate in candidates)
        if (board.wouldCreateDependencyCycle(currentTask.id, candidate.id))
          candidate.id,
    };
  }

  /// Collects selected prerequisite task IDs in canonical board declaration order.
  List<String> _collectOrderedBlockedByIds(TaskBoard board) {
    return <String>[
      for (final task in board.allTasks)
        if (_blockedByTaskIds.contains(task.id)) task.id,
    ];
  }

  /// Collects selected label IDs in canonical board declaration order.
  List<String> _collectOrderedLabelIds(TaskBoard board) {
    return <String>[
      for (final label in board.labels)
        if (_selectedLabelIds.contains(label.id)) label.id,
    ];
  }

  /// Extracts a valid `YYYY-MM-DD` date prefix from [rawInput], or `null` if invalid.
  static String? _extractDatePart(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.length < 10) {
      return null;
    }
    final candidate = trimmed.substring(0, 10);
    return TaskItem.tryParseIsoDate(candidate) != null ? candidate : null;
  }

  /// Parses [rawTime] (`HH:MM`) into a [TimeOfDay], or returns [fallback] if invalid.
  static TimeOfDay _extractTimeOfDay(String rawTime, TimeOfDay fallback) {
    final minutes = TaskItem.tryParseTimeMinutes(rawTime.trim());
    if (minutes == null) {
      return fallback;
    }
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  /// Extracts a valid `HH:MM` suffix from a `YYYY-MM-DD HH:MM` timestamp string, or `null`.
  static String? _extractTimeSuffix(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.length <= 10) {
      return null;
    }
    final remainder = trimmed.substring(10).trim();
    if (remainder.length >= 5) {
      final hhMm = remainder.substring(0, 5);
      if (TaskItem.tryParseTimeMinutes(hhMm) != null) {
        return hhMm;
      }
    }
    return null;
  }

  /// Formats an initial `suspended` timestamp for the input field (omitting `defaultSuspendedAt`).
  static String _formatInitialSuspendedText(DateTime? suspendedAt) {
    if (suspendedAt == null || suspendedAt == TaskItem.defaultSuspendedAt) {
      return '';
    }
    return TaskItem.formatTdfTimestamp(suspendedAt);
  }

  /// Formats [time] as a zero-padded 24-hour `HH:MM` string.
  static String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Rebuilds when subtask, suspended, or prerequisite search text changes.
  void _handleInputStateChanged() {
    setState(() {});
  }

  /// Rebuilds and clears link validation errors when the link title or URI input changes.
  void _handleLinkInputChanged() {
    setState(() {
      _linkErrorMessage = null;
    });
  }

  /// Clears any repeat interval validation error when the user edits the repeat count field.
  void _handleRepeatCountChanged() {
    if (_repeatErrorMessage == null) {
      return;
    }
    setState(() {
      _repeatErrorMessage = null;
    });
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

  /// Opens [uri] via [linkLauncherRepositoryProvider] and displays a SnackBar if launching fails.
  Future<void> _openLink(String uri) async {
    try {
      await ref.read(linkLauncherRepositoryProvider).openLink(uri);
    } on LinkLaunchException {
      if (!mounted) return;
      final localizations = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.errorOpenLinkFailed)),
      );
    }
  }

  /// Persists the created or edited task through [TaskNotifier].
  Future<void> _persistTask(
    TaskBoard board,
    String title,
    List<SubtaskItem> subtasks,
    List<TaskLink> links,
    DateTime? suspendedAt,
    TaskRepeatRule? repeatRule,
  ) async {
    final labelIds = _collectOrderedLabelIds(board);
    final blockedByIds = _collectOrderedBlockedByIds(board);
    final conditions = _conditionController.buildConditions();
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
        suspendedAt: suspendedAt,
        clearSuspendedAt: !_isSuspended,
        repeatRule: repeatRule,
        clearRepeatRule: !_isRepeating,
        blockedByTaskIds: blockedByIds,
        links: links,
        conditions: conditions,
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
      suspendedAt: suspendedAt,
      repeatRule: repeatRule,
      blockedByTaskIds: blockedByIds,
      links: links,
      conditions: conditions,
    );
  }

  /// Opens a Material 3 date picker and updates [_suspendedController] with `YYYY-MM-DD`.
  Future<void> _pickSuspendedDate() async {
    final config =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final now = config.toLocalWallClock(ref.read(clockProvider)().toUtc());
    final initialDate = _resolveInitialSuspendedDate(now);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100, 12, 31),
    );
    if (!mounted || pickedDate == null) {
      return;
    }
    final formattedDate = TaskItem.formatIsoDate(pickedDate);
    final existingTime = _extractTimeSuffix(_suspendedController.text);
    setState(() {
      _suspendedController.text = existingTime != null
          ? '$formattedDate $existingTime'
          : formattedDate;
      _suspendedErrorMessage = null;
    });
  }

  /// Opens a 24-hour Material 3 time picker and updates the `HH:MM` portion of [_suspendedController].
  Future<void> _pickSuspendedTime() async {
    final config =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final now = config.toLocalWallClock(ref.read(clockProvider)().toUtc());
    final existingTimeSuffix = _extractTimeSuffix(_suspendedController.text);
    final initialTime = _extractTimeOfDay(
      existingTimeSuffix ?? '',
      const TimeOfDay(hour: 9, minute: 0),
    );
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: _build24HourTimePicker,
    );
    if (!mounted || pickedTime == null) {
      return;
    }
    final datePart =
        _extractDatePart(_suspendedController.text) ??
        TaskItem.formatIsoDate(now);
    final formattedTime = _formatTimeOfDay(pickedTime);
    setState(() {
      _suspendedController.text = '$datePart $formattedTime';
      _suspendedErrorMessage = null;
    });
  }

  /// Removes the link at [index].
  void _removeLink(int index) {
    setState(() {
      _links.removeAt(index);
      _linkErrorMessage = null;
    });
  }

  /// Removes the subtask step at [index].
  void _removeSubtask(int index) {
    setState(() {
      _subtasks.removeAt(index);
    });
  }

  /// Resolves the final list of [TaskLink]s on save, validating any pending link input.
  List<TaskLink>? _resolveEffectiveLinks(AppLocalizations localizations) {
    final pendingTitle = _linkTitleController.text.trim();
    final pendingUri = _linkUriController.text.trim();
    if (pendingTitle.isEmpty && pendingUri.isEmpty) {
      return _links;
    }
    if (_links.length >= TaskLink.maxLinksPerTask) {
      setState(() {
        _linkErrorMessage = localizations.linkErrorMaxExceeded;
      });
      return null;
    }
    final parsed = TaskLink.tryParse(
      rawTitle: pendingTitle,
      rawUri: pendingUri,
    );
    if (parsed == null) {
      setState(() {
        _linkErrorMessage = localizations.linkErrorInvalid;
      });
      return null;
    }
    return <TaskLink>[..._links, parsed];
  }

  /// Derives the initial [QuickAddMode] for an existing [task] on [board].
  static QuickAddMode _resolveInitialMode(TaskItem task, TaskBoard board) {
    if (task.isCompleted || task.completedAt != null) {
      return QuickAddMode.standard;
    }
    if (task.isPriority) {
      return QuickAddMode.priority;
    }
    if (board.someday.any((candidate) => candidate.id == task.id) ||
        (board.allTasks.any((candidate) => candidate.id == task.id) &&
            !board.queueTaskIds.contains(task.id))) {
      return QuickAddMode.someday;
    }
    return QuickAddMode.standard;
  }

  /// Resolves the initial [DateTime] for the suspended date picker from [_suspendedController] or [fallback].
  DateTime _resolveInitialSuspendedDate(DateTime fallback) {
    final datePart = _extractDatePart(_suspendedController.text);
    if (datePart != null) {
      final parsed = TaskItem.tryParseIsoDate(datePart);
      if (parsed != null && parsed.year >= 2000 && parsed.year <= 2100) {
        return parsed;
      }
    }
    return DateTime.utc(fallback.year, fallback.month, fallback.day);
  }

  /// Resolves the `repeat` rule when [_isRepeating] is enabled, or `null` when disabled or invalid.
  TaskRepeatRule? _resolveRepeatRule() {
    if (!_isRepeating) {
      return null;
    }
    final parsedCount = int.tryParse(_repeatCountController.text.trim());
    if (parsedCount == null ||
        parsedCount < 1 ||
        parsedCount > TaskRepeatRule.maxRepeatCount) {
      return null;
    }
    return TaskRepeatRule(count: parsedCount, unit: _repeatUnit);
  }

  /// Resolves the `suspendedAt` timestamp when [_isSuspended] is enabled, or `null` when disabled.
  DateTime? _resolveSuspendedTimestamp() {
    if (!_isSuspended) {
      return null;
    }
    final rawText = _suspendedController.text.trim();
    if (rawText.isEmpty) {
      return TaskItem.defaultSuspendedAt;
    }
    return TaskItem.tryParseTdfTimestampInput(rawText);
  }

  /// Selects [unit] as the recurrence interval unit.
  void _selectRepeatUnit(RepeatUnit unit) {
    setState(() {
      _repeatUnit = unit;
    });
  }

  /// Validates the task inputs and saves the created or updated task.
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

    final suspendedTimestamp = _resolveSuspendedTimestamp();
    if (_isSuspended && suspendedTimestamp == null) {
      setState(() {
        _suspendedErrorMessage = localizations.taskSuspendedErrorInvalid;
      });
      return;
    }

    final repeatRule = _resolveRepeatRule();
    if (_isRepeating && repeatRule == null) {
      setState(() {
        _repeatErrorMessage = localizations.repeatErrorInvalid;
      });
      return;
    }

    final effectiveLinks = _resolveEffectiveLinks(localizations);
    if (effectiveLinks == null) {
      return;
    }

    final pendingSubtask = _subtaskController.text.trim();
    final effectiveSubtasks = <SubtaskItem>[
      ..._subtasks,
      if (pendingSubtask.isNotEmpty)
        SubtaskItem(title: pendingSubtask, isCompleted: _isCompletedTask),
    ];

    await _persistTask(
      board,
      _titleController.text.trim(),
      effectiveSubtasks,
      effectiveLinks,
      suspendedTimestamp,
      repeatRule,
    );
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

  /// Toggles prerequisite [blockerTaskId] if it does not introduce a dependency cycle.
  void _toggleBlockedBy(TaskBoard board, String blockerTaskId) {
    if (widget.initialTask case final currentTask?
        when board.wouldCreateDependencyCycle(currentTask.id, blockerTaskId)) {
      return;
    }
    setState(() {
      if (!_blockedByTaskIds.remove(blockerTaskId)) {
        _blockedByTaskIds.add(blockerTaskId);
      }
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

  /// Toggles `repeat` state on or off.
  void _toggleRepeat() {
    setState(() {
      _isRepeating = !_isRepeating;
      _repeatErrorMessage = null;
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
    if (_isCompletedTask) {
      return;
    }
    final current = _subtasks[index];
    setState(() {
      _subtasks[index] = current.copyWith(isCompleted: !current.isCompleted);
    });
  }

  /// Toggles `suspended` state on or off.
  void _toggleSuspended() {
    setState(() {
      _isSuspended = !_isSuspended;
      _suspendedErrorMessage = null;
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
