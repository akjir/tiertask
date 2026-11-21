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
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';
import '../presentation/link_action_controller.dart';
import '../presentation/task_editor_controller.dart';
import '../presentation/ui_telemetry.dart';
import '../providers/config_providers.dart';
import '../providers/task_providers.dart';
import 'widgets/condition_editor_controller.dart';
import 'widgets/task_editor_conditions_section.dart';
import 'widgets/task_editor_history_section.dart';
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

/// Prerequisite task blocker card rendered when candidate tasks exist on [board].
class _EditTaskBlockedBySection extends StatelessWidget {
  /// Creates an [_EditTaskBlockedBySection].
  const _EditTaskBlockedBySection({required this.board, required this.state});

  /// Current [TaskBoard] snapshot.
  final TaskBoard board;

  /// Owning [_EditTaskScreenState].
  final _EditTaskScreenState state;

  @override
  Widget build(BuildContext context) {
    final candidates = TaskEditorBoardHelper.collectCandidateBlockerTasks(
      board: board,
      currentTaskId: state.widget.initialTask?.id,
      selectedBlockedByIds: state._blockedByIds,
    );
    if (candidates.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ValueListenableBuilder<TextEditingValue>(
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
    );
  }
}

/// Settings-style scrollable card column inside [EditTaskScreen].
class _EditTaskFormColumn extends StatelessWidget {
  /// Creates an [_EditTaskFormColumn].
  const _EditTaskFormColumn({
    required this.board,
    required this.configuration,
    required this.state,
  });

  /// Current [TaskBoard] snapshot.
  final TaskBoard board;

  /// Active workspace configuration for local wall-clock timestamp formatting.
  final WebDavConfig configuration;

  /// Owning [_EditTaskScreenState] coordinating form controllers and callbacks.
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
        _EditTaskSchedulingSection(state: state),
        const SizedBox(height: 10),
        _EditTaskSubtasksAndLinksSection(board: board, state: state),
        const SizedBox(height: 10),
        _EditTaskHistorySection(configuration: configuration, state: state),
        _EditTaskBlockedBySection(board: board, state: state),
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

/// History journal section wired to [_EditTaskScreenState].
class _EditTaskHistorySection extends StatelessWidget {
  /// Creates an [_EditTaskHistorySection].
  const _EditTaskHistorySection({
    required this.configuration,
    required this.state,
  });

  /// Active workspace configuration for local wall-clock timestamp formatting.
  final WebDavConfig configuration;

  /// Owning [_EditTaskScreenState].
  final _EditTaskScreenState state;

  @override
  Widget build(BuildContext context) {
    return TaskEditorHistorySection(
      configuration: configuration,
      editingIndex: state._editingHistoryIndex,
      entries: state._historyEntries,
      errorMessage: state._historyErrorMessage,
      onAddOrSaveEntry: state._addOrSaveHistoryEntry,
      onCancelEdit: state._cancelEditHistoryEntry,
      onClearTimestamp: state._clearHistoryTimestamp,
      onEditEntry: state._editHistoryEntry,
      onPickDate: state._pickHistoryDate,
      onPickTime: state._pickHistoryTime,
      onRemoveEntry: state._removeHistoryEntry,
      textController: state._historyTextController,
      timestampController: state._historyTimestampController,
    );
  }
}

/// Body layout inside [EditTaskScreen] separating scrollable form cards from bottom actions.
class _EditTaskScaffoldBody extends StatelessWidget {
  /// Creates an [_EditTaskScaffoldBody].
  const _EditTaskScaffoldBody({
    required this.board,
    required this.configuration,
    required this.isEditing,
    required this.state,
  });

  /// Current [TaskBoard] snapshot.
  final TaskBoard board;

  /// Active workspace configuration for local wall-clock timestamp formatting.
  final WebDavConfig configuration;

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
              child: _EditTaskFormColumn(
                board: board,
                configuration: configuration,
                state: state,
              ),
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

/// Scheduling card wired to [_EditTaskScreenState].
class _EditTaskSchedulingSection extends StatelessWidget {
  /// Creates an [_EditTaskSchedulingSection].
  const _EditTaskSchedulingSection({required this.state});

  /// Owning [_EditTaskScreenState].
  final _EditTaskScreenState state;

  @override
  Widget build(BuildContext context) {
    return TaskEditorSchedulingCard(
      autoPrioritizeDue: state._autoPrioritizeDue,
      dueController: state._dueController,
      dueErrorMessage: state._dueErrorMessage,
      dueNoteController: state._dueNoteController,
      dueNoteErrorMessage: state._dueNoteErrorMessage,
      hasDue: state._hasDue,
      isRepeating: state._isRepeating,
      isSuspended: state._isSuspended,
      mode: state._mode,
      onClearDue: state._dueController.clear,
      onClearSuspended: state._suspendedController.clear,
      onPickDueDate: state._pickDueDate,
      onPickDueTime: state._pickDueTime,
      onPickSuspendedDate: state._pickSuspendedDate,
      onPickSuspendedTime: state._pickSuspendedTime,
      onSelectRepeatUnit: state._selectRepeatUnit,
      onToggleAutoPrioritizeDue: state._toggleAutoPrioritizeDue,
      onToggleDue: state._toggleDue,
      onTogglePriority: state._togglePriorityMode,
      onToggleRepeat: state._toggleRepeat,
      onToggleSomeday: state._toggleSomedayMode,
      onToggleSuspended: state._toggleSuspended,
      repeatCountController: state._repeatCountController,
      repeatErrorMessage: state._repeatErrorMessage,
      repeatLeadDaysController: state._repeatLeadDaysController,
      repeatLeadDaysErrorMessage: state._repeatLeadDaysErrorMessage,
      repeatUnit: state._repeatUnit,
      showDueAutoPrioritizeToggle: !state._isCompletedTask,
      suspendedController: state._suspendedController,
      suspendedErrorMessage: state._suspendedErrorMessage,
      suspendedNoteController: state._suspendedNoteController,
      suspendedNoteErrorMessage: state._suspendedNoteErrorMessage,
    );
  }
}

/// State for [EditTaskScreen].
class _EditTaskScreenState extends ConsumerState<EditTaskScreen> {
  late bool _autoFinish;
  late bool _autoPrioritizeDue;
  late final Set<String> _blockedByIds;
  final _blockedSearchController = TextEditingController();
  late final ConditionEditorController _conditionController;
  ProviderSubscription<AsyncValue<WebDavConfig>>? _configSubscription;
  bool _didUserToggleAutoPrioritizeDue = false;
  late final TextEditingController _dueController;
  String? _dueErrorMessage;
  late final TextEditingController _dueNoteController;
  String? _dueNoteErrorMessage;
  int? _editingHistoryIndex;
  String? _editingHistoryInitialTimestampText;
  TaskHistoryEntry? _editingHistoryOriginalEntry;
  String? _errorMessage;
  late bool _hasDue;
  bool _hasSubtaskText = false;
  late List<TaskHistoryEntry> _historyEntries;
  String? _historyErrorMessage;
  final TextEditingController _historyTextController = TextEditingController();
  final TextEditingController _historyTimestampController =
      TextEditingController();
  late final TdfLocalDateTime? _initialDueAnchor;
  late final DateTime? _initialDueAt;
  late final String? _initialDueNote;
  late String _initialDueText;
  late final QuickAddMode _initialEditorMode;
  late final DateTime? _initialSuspendedAt;
  late final String? _initialSuspendedNote;
  late String _initialSuspendedText;
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
  late final TextEditingController _repeatLeadDaysController;
  String? _repeatLeadDaysErrorMessage;
  late RepeatUnit _repeatUnit;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final _subtaskController = TextEditingController();
  late final List<SubtaskItem> _subtasks;
  late final TextEditingController _suspendedController;
  String? _suspendedErrorMessage;
  late final TextEditingController _suspendedNoteController;
  String? _suspendedNoteErrorMessage;
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
    _initialEditorMode = _mode;
    _labelIds = Set.of(task?.labelIds ?? widget.initialLabelIds);
    _autoFinish = task?.subtasksAutoFinish ?? false;
    _subtasks = List.of(task?.subtasks ?? const []);
    _links = List.of(task?.links ?? const []);
    _historyEntries = List<TaskHistoryEntry>.of(
      task?.history ?? const <TaskHistoryEntry>[],
    );
    _blockedByIds = Set.of(task?.blockedByTaskIds ?? const []);
    final nowUtc = ref.read(clockProvider)().toUtc();
    final initialConfig =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final hasActiveSuspension = task?.hasActiveSuspendedAt(nowUtc) ?? false;
    _isSuspended = hasActiveSuspension;
    _initialSuspendedAt = hasActiveSuspension ? task?.suspendedAt : null;
    _initialSuspendedText = hasActiveSuspension
        ? TaskEditorSuspendedField.formatInitialText(
            _initialSuspendedAt,
            initialConfig,
          )
        : '';
    _suspendedController = TextEditingController(text: _initialSuspendedText)
      ..addListener(_handleSuspendedChanged);
    _initialSuspendedNote = hasActiveSuspension ? task?.suspendedNote : null;
    _suspendedNoteController = TextEditingController(
      text: _initialSuspendedNote ?? '',
    )..addListener(_handleSuspendedNoteChanged);
    _hasDue = task?.dueAt != null;
    _initialDueAt = task?.dueAt;
    _initialDueAnchor = task?.dueAnchor;
    _initialDueText = TaskEditorSuspendedField.formatLocalTimestamp(
      _initialDueAt,
      initialConfig,
    );
    _dueController = TextEditingController(text: _initialDueText)
      ..addListener(_handleDueChanged);
    _initialDueNote = _hasDue ? task?.dueNote : null;
    _dueNoteController = TextEditingController(text: _initialDueNote ?? '')
      ..addListener(_handleDueNoteChanged);
    _autoPrioritizeDue = !(task?.isDuePassive ?? false);
    _isRepeating = task?.repeatRule != null;
    _repeatCountController = TextEditingController(
      text: (task?.repeatRule?.count ?? 1).toString(),
    )..addListener(_handleRepeatCountChanged);
    final initialLeadDays = task?.repeatRule?.leadDays ?? 0;
    _repeatLeadDaysController = TextEditingController(
      text: initialLeadDays > 0 ? initialLeadDays.toString() : '',
    )..addListener(_handleRepeatLeadDaysChanged);
    _repeatUnit = task?.repeatRule?.unit ?? RepeatUnit.days;
    _conditionController = ConditionEditorController(
      initialConditions: task?.conditions ?? const [],
    );
    _subtaskController.addListener(_handleSubtaskInputChanged);
    _linkTitleController.addListener(_handleLinkInputChanged);
    _linkUriController.addListener(_handleLinkInputChanged);
    _historyTextController.addListener(_handleHistoryInputChanged);
    _historyTimestampController.addListener(_handleHistoryInputChanged);
    _configSubscription = ref.listenManual<AsyncValue<WebDavConfig>>(
      webDavConfigProvider,
      _handleConfigAsyncChanged,
    );
  }

  @override
  void dispose() {
    _configSubscription?.close();
    _titleController.dispose();
    _noteController.dispose();
    _subtaskController.dispose();
    _linkTitleController.dispose();
    _linkUriController.dispose();
    _historyTextController.dispose();
    _historyTimestampController.dispose();
    _suspendedController.dispose();
    _suspendedNoteController.dispose();
    _dueController.dispose();
    _dueNoteController.dispose();
    _repeatCountController.dispose();
    _repeatLeadDaysController.dispose();
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
    final configuration = ref.watch(
      webDavConfigProvider.select(
        (asyncConfig) => asyncConfig.asData?.value ?? const WebDavConfig(),
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
          configuration: configuration,
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

  /// Validates and commits the current history timestamp and text into [_historyEntries].
  void _addOrSaveHistoryEntry() {
    final configuration =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final localizations = AppLocalizations.of(context);
    final hasPending =
        _editingHistoryIndex != null ||
        _historyTimestampController.text.trim().isNotEmpty ||
        _historyTextController.text.isNotEmpty;
    if (!hasPending) {
      setState(
        () => _historyErrorMessage = localizations.historyErrorTextEmpty,
      );
      return;
    }
    final candidateResult = ref
        .read(taskEditorControllerProvider)
        .resolvePendingHistoryCandidate(
          configuration: configuration,
          localizations: localizations,
          editingHistoryIndex: _editingHistoryIndex,
          editingHistoryOriginalEntry: _editingHistoryOriginalEntry,
          editingHistoryInitialTimestampText:
              _editingHistoryInitialTimestampText,
          rawTimestamp: _historyTimestampController.text,
          rawText: _historyTextController.text,
        );
    final candidate = candidateResult.candidate;
    if (candidate == null) {
      setState(() => _historyErrorMessage = candidateResult.error);
      return;
    }
    final activeIndex = _editingHistoryIndex;
    final nextEntries = TaskHistoryEntry.normalizeList(<TaskHistoryEntry>[
      for (var i = 0; i < _historyEntries.length; i++)
        if (i != activeIndex) _historyEntries[i],
      candidate,
    ]);
    if (nextEntries.length > maxTdfHistoryPerTask) {
      setState(
        () => _historyErrorMessage = localizations.historyErrorMaxExceeded,
      );
      return;
    }
    setState(() {
      _historyEntries = List<TaskHistoryEntry>.of(nextEntries);
      _resetHistoryEditInputs();
    });
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

  /// Applies controller-reported field validation or persistence [errors] into widget state.
  void _applyFieldErrors(TaskEditorFieldErrors errors) {
    _errorMessage = errors.titleError;
    _suspendedErrorMessage = errors.suspendedError;
    _suspendedNoteErrorMessage = errors.suspendedNoteError;
    _dueErrorMessage = errors.dueError;
    _dueNoteErrorMessage = errors.dueNoteError;
    _repeatErrorMessage = errors.repeatError;
    _repeatLeadDaysErrorMessage = errors.repeatLeadDaysError;
    _historyErrorMessage = errors.historyError;
    if (errors.linkError != null) {
      _linkErrorMessage = errors.linkError;
    }
  }

  /// Cancels an active draft history row edit and clears the history input fields.
  void _cancelEditHistoryEntry() {
    setState(_resetHistoryEditInputs);
  }

  /// Clears the history timestamp input and resets [_historyErrorMessage].
  void _clearHistoryTimestamp() {
    setState(() {
      _historyErrorMessage = null;
      _historyTimestampController.clear();
    });
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
    await ref.read(taskEditorControllerProvider).deleteTask(existingTask.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Loads the draft history entry at [index] into the editor timestamp and text inputs.
  void _editHistoryEntry(int index) {
    if (index < 0 || index >= _historyEntries.length) return;
    final configuration =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final entry = _historyEntries[index];
    final formattedTimestamp = TaskItem.formatTdfTimestamp(
      configuration.toLocalWallClock(entry.timestampUtc),
    );
    setState(() {
      _historyErrorMessage = null;
      _editingHistoryIndex = index;
      _editingHistoryOriginalEntry = entry;
      _editingHistoryInitialTimestampText = formattedTimestamp;
      _historyTimestampController.text = formattedTimestamp;
      _historyTextController.text = entry.text;
    });
  }

  /// Synchronously updates local timestamp baseline snapshots and unedited controller texts when [webDavConfigProvider] resolves (`DECISION-14`).
  void _handleConfigAsyncChanged(
    AsyncValue<WebDavConfig>? previous,
    AsyncValue<WebDavConfig> next,
  ) {
    final nextConfig = next.asData?.value;
    if (nextConfig == null) return;
    if (_initialDueAt case final dueAt?) {
      final previousInitialText = _initialDueText;
      final wasUnedited = _dueController.text.trim() == previousInitialText;
      final nextDueText = TaskEditorSuspendedField.formatLocalTimestamp(
        dueAt,
        nextConfig,
      );
      _initialDueText = nextDueText;
      if (wasUnedited && nextDueText != previousInitialText) {
        _dueController.text = nextDueText;
      }
    }
    if (_initialSuspendedAt case final suspendedAt?) {
      final previousInitialText = _initialSuspendedText;
      final wasUnedited =
          _suspendedController.text.trim() == previousInitialText;
      final nextSuspendedText = TaskEditorSuspendedField.formatInitialText(
        suspendedAt,
        nextConfig,
      );
      _initialSuspendedText = nextSuspendedText;
      if (wasUnedited && nextSuspendedText != previousInitialText) {
        _suspendedController.text = nextSuspendedText;
      }
    }
    if (_editingHistoryOriginalEntry case final entry?) {
      final previousInitialText = _editingHistoryInitialTimestampText;
      final wasUnedited =
          _historyTimestampController.text.trim() == previousInitialText;
      final nextHistoryText = TaskEditorSuspendedField.formatLocalTimestamp(
        entry.timestampUtc,
        nextConfig,
      );
      _editingHistoryInitialTimestampText = nextHistoryText;
      if (wasUnedited && nextHistoryText != previousInitialText) {
        _historyTimestampController.text = nextHistoryText;
      }
    }
  }

  /// Clears any due validation error and auto-resets passive status when the due timestamp changes without manual switch interaction.
  void _handleDueChanged() {
    final configuration =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final controller = ref.read(taskEditorControllerProvider);
    final candidateDue = controller.resolveDueDraft(
      configuration: configuration,
      hasDue: _hasDue,
      rawDueText: _dueController.text,
      initialDueAt: _initialDueAt,
      initialDueAnchor: _initialDueAnchor,
      initialDueText: _initialDueText,
    );
    final shouldResetAutoPrioritize = controller.shouldResetAutoPrioritizeDue(
      didUserToggleAutoPrioritizeDue: _didUserToggleAutoPrioritizeDue,
      autoPrioritizeDue: _autoPrioritizeDue,
      hasDue: _hasDue,
      candidateDue: candidateDue,
      initialDueAt: _initialDueAt,
      initialDueAnchor: _initialDueAnchor,
    );
    if (_dueErrorMessage != null || shouldResetAutoPrioritize) {
      setState(() {
        _dueErrorMessage = null;
        if (shouldResetAutoPrioritize) {
          _autoPrioritizeDue = true;
        }
      });
    }
  }

  /// Clears any deadline note validation error when the user edits [_dueNoteController].
  void _handleDueNoteChanged() {
    if (_dueNoteErrorMessage != null) {
      setState(() => _dueNoteErrorMessage = null);
    }
  }

  /// Clears any history validation error when the user edits the history timestamp or text inputs.
  void _handleHistoryInputChanged() {
    if (_historyErrorMessage != null) {
      setState(() => _historyErrorMessage = null);
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

  /// Clears any preparation lead validation error when the user edits [_repeatLeadDaysController].
  void _handleRepeatLeadDaysChanged() {
    if (_repeatLeadDaysErrorMessage != null) {
      setState(() => _repeatLeadDaysErrorMessage = null);
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

  /// Clears any deferral note validation error when the user edits [_suspendedNoteController].
  void _handleSuspendedNoteChanged() {
    if (_suspendedNoteErrorMessage != null) {
      setState(() => _suspendedNoteErrorMessage = null);
    }
  }

  /// Clears any validation error when the user edits the title field.
  void _handleTitleChanged() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  /// Opens [uri] via [linkActionControllerProvider] and displays a SnackBar if launching fails.
  Future<void> _openLink(String uri) async {
    switch (await ref.read(linkActionControllerProvider).openLink(uri)) {
      case LinkOpenOutcome.opened:
        return;
      case LinkOpenOutcome.failed:
        if (!mounted) return;
        final text = AppLocalizations.of(context).errorOpenLinkFailed;
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(text)),
        );
    }
  }

  /// Opens the Material 3 date picker for [_dueController].
  Future<void> _pickDueDate() =>
      _pickDueTimestamp(TaskEditorSuspendedField.pickSuspendedDate);

  /// Opens the 24-hour time picker for [_dueController].
  Future<void> _pickDueTime() =>
      _pickDueTimestamp(TaskEditorSuspendedField.pickSuspendedTime);

  /// Opens [picker] and updates [_dueController] with the selected date or time.
  Future<void> _pickDueTimestamp(
    Future<String?> Function({
      required BuildContext context,
      required String currentText,
      required DateTime fallbackDate,
    })
    picker,
  ) async {
    final configuration =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final now = ref
        .read(taskEditorControllerProvider)
        .currentLocalWallClock(configuration);
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

  /// Opens the Material 3 date picker for [_historyTimestampController].
  Future<void> _pickHistoryDate() =>
      _pickHistoryTimestamp(TaskEditorHistorySection.pickHistoryDate);

  /// Opens the 24-hour time picker for [_historyTimestampController].
  Future<void> _pickHistoryTime() =>
      _pickHistoryTimestamp(TaskEditorHistorySection.pickHistoryTime);

  /// Opens [picker] and updates [_historyTimestampController] with the selected local date or time.
  Future<void> _pickHistoryTimestamp(
    Future<String?> Function({
      required BuildContext context,
      required String currentText,
      required DateTime fallbackLocal,
    })
    picker,
  ) async {
    final configuration =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final fallbackLocal = ref
        .read(taskEditorControllerProvider)
        .currentLocalWallClock(configuration);
    final updated = await picker(
      context: context,
      currentText: _historyTimestampController.text,
      fallbackLocal: fallbackLocal,
    );
    if (!mounted || updated == null) return;
    setState(() {
      _historyErrorMessage = null;
      _historyTimestampController.text = updated;
    });
  }

  /// Opens the Material 3 date picker for [_suspendedController].
  Future<void> _pickSuspendedDate() =>
      _pickSuspendedTimestamp(TaskEditorSuspendedField.pickSuspendedDate);

  /// Opens the 24-hour time picker for [_suspendedController].
  Future<void> _pickSuspendedTime() =>
      _pickSuspendedTimestamp(TaskEditorSuspendedField.pickSuspendedTime);

  /// Opens [picker] and updates [_suspendedController] with the selected date or time.
  Future<void> _pickSuspendedTimestamp(
    Future<String?> Function({
      required BuildContext context,
      required String currentText,
      required DateTime fallbackDate,
    })
    picker,
  ) async {
    final configuration =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final now = ref
        .read(taskEditorControllerProvider)
        .currentLocalWallClock(configuration);
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

  /// Removes the draft history entry at [index] while maintaining [_editingHistoryIndex] coherence.
  void _removeHistoryEntry(int index) {
    if (index < 0 || index >= _historyEntries.length) return;
    setState(() {
      _historyEntries.removeAt(index);
      _historyErrorMessage = null;
      final activeIndex = _editingHistoryIndex;
      if (activeIndex == index) {
        _resetHistoryEditInputs();
      } else if (activeIndex != null && index < activeIndex) {
        _editingHistoryIndex = activeIndex - 1;
      }
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

  /// Clears active draft history edit tracking and resets both history input controllers.
  void _resetHistoryEditInputs() {
    _historyErrorMessage = null;
    _editingHistoryIndex = null;
    _editingHistoryOriginalEntry = null;
    _editingHistoryInitialTimestampText = null;
    _historyTimestampController.clear();
    _historyTextController.clear();
  }

  /// Updates the active [RepeatUnit] selection.
  void _selectRepeatUnit(RepeatUnit unit) {
    setState(() => _repeatUnit = unit);
  }

  /// Validates the task inputs and saves the created or updated task.
  Future<void> _submit() async {
    final board =
        ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final configuration =
        ref.read(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final locale = Localizations.localeOf(context);
    final result = await ref
        .read(taskEditorControllerProvider)
        .submitDraft(
          TaskEditorDraftInput(
            autoFinish: _autoFinish,
            autoPrioritizeDue: _autoPrioritizeDue,
            board: board,
            conditions: _conditionController.buildConditions(),
            configuration: configuration,
            editingHistoryIndex: _editingHistoryIndex,
            editingHistoryInitialTimestampText:
                _editingHistoryInitialTimestampText,
            editingHistoryOriginalEntry: _editingHistoryOriginalEntry,
            existingTask: widget.initialTask,
            hasDue: _hasDue,
            historyEntries: _historyEntries,
            initialDueAnchor: _initialDueAnchor,
            initialDueAt: _initialDueAt,
            initialDueNote: _initialDueNote,
            initialDueText: _initialDueText,
            initialEditorMode: _initialEditorMode,
            initialSuspendedAt: _initialSuspendedAt,
            initialSuspendedNote: _initialSuspendedNote,
            initialSuspendedText: _initialSuspendedText,
            isRepeating: _isRepeating,
            isSuspended: _isSuspended,
            links: _links,
            mode: _mode,
            pendingLinkTitle: _linkTitleController.text,
            pendingLinkUri: _linkUriController.text,
            pendingSubtaskText: _subtaskController.text,
            rawDueNote: _dueNoteController.text,
            rawDueText: _dueController.text,
            rawHistoryText: _historyTextController.text,
            rawHistoryTimestamp: _historyTimestampController.text,
            rawNote: _noteController.text,
            rawRepeatCount: _repeatCountController.text,
            rawRepeatLeadDays: _repeatLeadDaysController.text,
            rawSuspendedNote: _suspendedNoteController.text,
            rawSuspendedText: _suspendedController.text,
            rawTitle: _titleController.text,
            repeatUnit: _repeatUnit,
            selectedBlockedByIds: _blockedByIds,
            selectedLabelIds: _labelIds,
            subtasks: _subtasks,
          ),
          locale: locale,
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case TaskEditorSubmitted():
        Navigator.of(context).pop();
        widget.onSubmitted?.call();
      case TaskEditorValidationFailed(:final errors):
        setState(() => _applyFieldErrors(errors));
      case TaskEditorPersistFailed(
        :final errors,
        :final committedHistoryEntries,
        :final committedLinks,
      ):
        setState(() {
          if (committedHistoryEntries != null) {
            _historyEntries = List<TaskHistoryEntry>.of(
              committedHistoryEntries,
            );
            _resetHistoryEditInputs();
          }
          if (committedLinks != null) {
            _links = List<TaskLink>.of(committedLinks);
            _lastCanAddLink = false;
            _linkErrorMessage = null;
            _linkTitleController.clear();
            _linkUriController.clear();
          }
          _applyFieldErrors(errors);
        });
    }
  }

  /// Updates [_autoPrioritizeDue] from explicit user interaction.
  void _toggleAutoPrioritizeDue(bool value) {
    setState(() {
      _autoPrioritizeDue = value;
      _didUserToggleAutoPrioritizeDue = true;
    });
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

  /// Toggles [_hasDue] and clears deadline-dependent validation errors when disabled.
  void _toggleDue() {
    setState(() {
      _hasDue = !_hasDue;
      if (!_hasDue) {
        _dueErrorMessage = null;
        _dueNoteErrorMessage = null;
        _repeatLeadDaysErrorMessage = null;
        _autoPrioritizeDue = true;
        _didUserToggleAutoPrioritizeDue = false;
      }
    });
  }

  /// Toggles [_mode] between [target] and [QuickAddMode.standard], resetting passive due status on Priority promotion.
  void _toggleMode(QuickAddMode target) {
    final nextMode = _mode == target ? QuickAddMode.standard : target;
    setState(() {
      _mode = nextMode;
      if (nextMode == QuickAddMode.priority &&
          !_didUserToggleAutoPrioritizeDue &&
          !_autoPrioritizeDue) {
        _autoPrioritizeDue = true;
      }
    });
  }

  /// Toggles the `Priority` scheduling chip.
  void _togglePriorityMode() => _toggleMode(QuickAddMode.priority);

  /// Toggles [_isRepeating] and clears repeat validation errors when disabled.
  void _toggleRepeat() {
    setState(() {
      _isRepeating = !_isRepeating;
      if (!_isRepeating) {
        _repeatErrorMessage = null;
        _repeatLeadDaysErrorMessage = null;
      }
    });
  }

  /// Toggles the `Someday` scheduling chip.
  void _toggleSomedayMode() => _toggleMode(QuickAddMode.someday);

  /// Toggles completion state of the subtask step at [index].
  void _toggleSubtaskStep(int index) {
    if (_isCompletedTask || index < 0 || index >= _subtasks.length) return;
    final step = _subtasks[index];
    setState(
      () => _subtasks[index] = step.copyWith(isCompleted: !step.isCompleted),
    );
  }

  /// Toggles [_isSuspended] and clears deferral validation errors when disabled.
  void _toggleSuspended() {
    setState(() {
      _isSuspended = !_isSuspended;
      if (!_isSuspended) {
        _suspendedErrorMessage = null;
        _suspendedNoteErrorMessage = null;
      }
    });
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

/// Pushes [EditTaskScreen] onto the navigation stack for extended task creation or task editing.
Future<void> openEditTaskScreen(
  BuildContext context, {
  TaskItem? initialTask,
  String initialTitle = '',
  QuickAddMode initialMode = QuickAddMode.standard,
  Set<String> initialLabelIds = const <String>{},
  VoidCallback? onSubmitted,
}) {
  UiTelemetry.logScreenOpened(
    'EditTaskScreen',
    entityKey: 'task',
    entityId: initialTask?.id ?? 'new',
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
