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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../models/tdf_error.dart';
import '../../models/webdav_config.dart';
import '../../providers/board_actions_provider.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_segmented_control.dart';
import '../primitives/ui_toggle_row.dart';
import '../tokens/ui_color_tokens.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import '../widgets/entity_card_chrome.dart';
import '../widgets/entity_date_time_fields.dart';

/// Read-only and inline-editable Due section for expanded Task cards (`U-CARD-002`..`003`).
class TaskDueSection extends ConsumerStatefulWidget {
  /// Creates a [TaskDueSection].
  const TaskDueSection({
    super.key,
    required this.task,
    required this.isSomeday,
    required this.isEditing,
    required this.configuration,
    required this.nowUtc,
    required this.currentLocalDateTimeHint,
    required this.onStartEdit,
    required this.onCancelEdit,
  });

  /// Active workspace configuration supplying timezone and due lead-window settings.
  final WebDavConfig configuration;

  /// Current workspace local wall-clock timestamp (`YYYY-MM-DD HH:MM`) seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Whether [task] currently resides in Tier 5 (`Someday`).
  final bool isSomeday;

  /// Current evaluation UTC timestamp used for remaining/overdue formatting.
  final DateTime nowUtc;

  /// Callback cancelling inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  /// Domain task item rendered by this section.
  final TaskItem task;

  @override
  ConsumerState<TaskDueSection> createState() => _TaskDueSectionState();
}

/// Inline single-line task title editor rendered inside an expanded open Task card header.
class TaskInlineTitleEditor extends ConsumerStatefulWidget {
  /// Creates a [TaskInlineTitleEditor].
  const TaskInlineTitleEditor({
    super.key,
    required this.taskId,
    required this.initialTitle,
    required this.onCancel,
  });

  /// Current persisted task title seeding the input field.
  final String initialTitle;

  /// Callback cancelling inline title editing without saving.
  final VoidCallback onCancel;

  /// Canonical task identifier being renamed.
  final String taskId;

  @override
  ConsumerState<TaskInlineTitleEditor> createState() =>
      _TaskInlineTitleEditorState();
}

/// Read-only and inline-editable Repeat section supporting interval count, unit, and Mode 2 lead days.
class TaskRepeatSection extends ConsumerStatefulWidget {
  /// Creates a [TaskRepeatSection].
  const TaskRepeatSection({
    super.key,
    required this.task,
    required this.isEditing,
    required this.onStartEdit,
    required this.onCancelEdit,
  });

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Callback cancelling inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  /// Domain task item rendered by this section.
  final TaskItem task;

  @override
  ConsumerState<TaskRepeatSection> createState() => _TaskRepeatSectionState();
}

/// Read-only and inline-editable Suspended section supporting timed vs indefinite deferral and notes.
class TaskSuspendedSection extends ConsumerStatefulWidget {
  /// Creates a [TaskSuspendedSection].
  const TaskSuspendedSection({
    super.key,
    required this.task,
    required this.isEditing,
    required this.configuration,
    required this.nowUtc,
    required this.currentLocalDateTimeHint,
    required this.onStartEdit,
    required this.onCancelEdit,
  });

  /// Active workspace configuration supplying timezone settings.
  final WebDavConfig configuration;

  /// Current workspace local wall-clock timestamp (`YYYY-MM-DD HH:MM`) seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Current evaluation UTC timestamp used for remaining deferral formatting.
  final DateTime nowUtc;

  /// Callback cancelling inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  /// Domain task item rendered by this section.
  final TaskItem task;

  @override
  ConsumerState<TaskSuspendedSection> createState() =>
      _TaskSuspendedSectionState();
}

/// Multi-line optional note input shared by inline schedule edit cards.
class _ScheduleNoteField extends StatelessWidget {
  /// Creates a [_ScheduleNoteField].
  const _ScheduleNoteField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.enabled,
    required this.errorText,
    required this.onChanged,
  });

  /// Controller for the optional multi-line note text.
  final TextEditingController controller;

  /// Whether user input is enabled.
  final bool enabled;

  /// Optional inline validation error text.
  final String? errorText;

  /// Placeholder text displayed when empty.
  final String hintText;

  /// Visible field label.
  final String label;

  /// Callback clearing inline errors on text change.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return UiField(
      kind: UiFieldKind.multiline,
      controller: controller,
      label: label,
      hintText: hintText,
      maxLength: maxTdfNoteLength,
      minLines: 2,
      maxLines: 4,
      enabled: enabled,
      errorText: errorText,
      onChanged: onChanged,
    );
  }
}

/// Read-only multi-line note text spaced below primary schedule metadata.
class _ScheduleNoteReadText extends StatelessWidget {
  /// Creates a [_ScheduleNoteReadText].
  const _ScheduleNoteReadText({required this.note});

  /// Non-empty persisted schedule note text.
  final String note;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: Text(
        note,
        style: tokens.typography.meta.copyWith(color: tokens.colors.ink),
      ),
    );
  }
}

/// Compact header edit button shared by read-only schedule cards.
class _ScheduleSectionEditButton extends StatelessWidget {
  /// Creates a [_ScheduleSectionEditButton].
  const _ScheduleSectionEditButton({
    required this.buttonKey,
    required this.isBusy,
    required this.onPressed,
  });

  /// Deterministic widget key applied to the underlying [UiButton].
  final ValueKey<String> buttonKey;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback entering inline edit mode for the section.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiButton(
      key: buttonKey,
      leadingIcon: Icons.edit_outlined,
      variant: UiButtonVariant.icon,
      density: UiButtonDensity.sidebarDesktop,
      tooltip: localizations.actionEdit,
      onPressed: isBusy ? null : onPressed,
    );
  }
}

/// Auto-prioritize near deadline toggle row inside [_TaskDueEditFields].
class _TaskDueAutoPrioritizeToggle extends StatelessWidget {
  /// Creates a [_TaskDueAutoPrioritizeToggle].
  const _TaskDueAutoPrioritizeToggle({
    required this.value,
    required this.isBusy,
    required this.onChanged,
  });

  /// Whether a save or clear mutation is in flight.
  final bool isBusy;

  /// Callback updating the auto-prioritize toggle state.
  final ValueChanged<bool> onChanged;

  /// Current auto-prioritize toggle value.
  final bool value;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiToggleRow(
      label: localizations.taskDueAutoPrioritizeLabel,
      description: localizations.taskDueAutoPrioritizeSubtitle,
      value: value,
      isDense: true,
      enabled: !isBusy,
      onChanged: onChanged,
    );
  }
}

/// Inline editing card for [TaskDueSection].
class _TaskDueEditCard extends StatelessWidget {
  /// Creates a [_TaskDueEditCard].
  const _TaskDueEditCard({
    required this.dueController,
    required this.dueNoteController,
    required this.autoPrioritize,
    required this.hasExistingDue,
    required this.currentLocalDateTimeHint,
    required this.dueError,
    required this.dueNoteError,
    required this.submitError,
    required this.isBusy,
    required this.onChanged,
    required this.onAutoPrioritizeChanged,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
  });

  /// Auto-prioritize near deadline toggle state.
  final bool autoPrioritize;

  /// Current local timestamp seeding pickers.
  final String currentLocalDateTimeHint;

  /// Controller for the due timestamp field.
  final TextEditingController dueController;

  /// Optional due timestamp field error.
  final String? dueError;

  /// Controller for the deadline note field.
  final TextEditingController dueNoteController;

  /// Optional deadline note field error.
  final String? dueNoteError;

  /// Whether the persisted task currently has a due date (shows Clear button).
  final bool hasExistingDue;

  /// Whether a save or clear request is in flight.
  final bool isBusy;

  /// Callback toggling [autoPrioritize].
  final ValueChanged<bool> onAutoPrioritizeChanged;

  /// Callback cancelling inline edit.
  final VoidCallback onCancel;

  /// Callback clearing errors on edit.
  final ValueChanged<String> onChanged;

  /// Callback clearing the persisted due date.
  final VoidCallback onClear;

  /// Callback saving the edited due date.
  final VoidCallback onSave;

  /// Optional general persistence error.
  final String? submitError;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('task_due_edit_card'),
      isEditing: true,
      headerIcon: Icons.calendar_today_outlined,
      headerTitle: localizations.taskInfoDueLabel,
      footer: EntityInlineEditorFooter(
        errorText: submitError,
        clearLabel: hasExistingDue ? localizations.inlineClearAction : null,
        onClear: hasExistingDue ? onClear : null,
        onCancel: onCancel,
        onSave: onSave,
        isBusy: isBusy,
      ),
      child: _TaskDueEditFields(
        dueController: dueController,
        dueNoteController: dueNoteController,
        autoPrioritize: autoPrioritize,
        currentLocalDateTimeHint: currentLocalDateTimeHint,
        dueError: dueError,
        dueNoteError: dueNoteError,
        isBusy: isBusy,
        onChanged: onChanged,
        onAutoPrioritizeChanged: onAutoPrioritizeChanged,
        onSave: onSave,
      ),
    );
  }
}

/// Due timestamp, auto-prioritize toggle, and note inputs inside [_TaskDueEditCard].
class _TaskDueEditFields extends StatelessWidget {
  /// Creates a [_TaskDueEditFields].
  const _TaskDueEditFields({
    required this.dueController,
    required this.dueNoteController,
    required this.autoPrioritize,
    required this.currentLocalDateTimeHint,
    required this.dueError,
    required this.dueNoteError,
    required this.isBusy,
    required this.onChanged,
    required this.onAutoPrioritizeChanged,
    required this.onSave,
  });

  /// Auto-prioritize near deadline toggle state.
  final bool autoPrioritize;

  /// Current local timestamp seeding pickers.
  final String currentLocalDateTimeHint;

  /// Controller for the due timestamp field.
  final TextEditingController dueController;

  /// Optional due timestamp field error.
  final String? dueError;

  /// Controller for the deadline note field.
  final TextEditingController dueNoteController;

  /// Optional deadline note field error.
  final String? dueNoteError;

  /// Whether a save or clear request is in flight.
  final bool isBusy;

  /// Callback toggling [autoPrioritize].
  final ValueChanged<bool> onAutoPrioritizeChanged;

  /// Callback clearing errors on edit.
  final ValueChanged<String> onChanged;

  /// Callback saving the edited due date.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final spacing = UiThemeTokens.of(context).spacing.space2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        EntityHybridDateTimeField(
          controller: dueController,
          label: localizations.taskDueButtonLabel,
          fallbackLocalDateTime: currentLocalDateTimeHint,
          autofocus: true,
          enabled: !isBusy,
          errorText: dueError,
          onChanged: onChanged,
          onSubmitted: (_) => onSave(),
        ),
        SizedBox(height: spacing),
        _TaskDueAutoPrioritizeToggle(
          value: autoPrioritize,
          isBusy: isBusy,
          onChanged: onAutoPrioritizeChanged,
        ),
        SizedBox(height: spacing),
        _ScheduleNoteField(
          controller: dueNoteController,
          label: localizations.taskDueNoteLabel,
          hintText: localizations.taskDueNoteHint,
          enabled: !isBusy,
          errorText: dueNoteError,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Read-only due timestamp, auto-priority summary, anchor, and note inside [_TaskDueReadCard].
class _TaskDueReadBody extends StatelessWidget {
  /// Creates a [_TaskDueReadBody].
  const _TaskDueReadBody({
    required this.task,
    required this.dueAtUtc,
    required this.isSomeday,
    required this.configuration,
    required this.nowUtc,
  });

  /// Active workspace configuration supplying timezone and due lead-window settings.
  final WebDavConfig configuration;

  /// Non-null due UTC instant of [task].
  final DateTime dueAtUtc;

  /// Whether [task] currently resides in Tier 5 (`Someday`).
  final bool isSomeday;

  /// Current evaluation UTC timestamp used for remaining/overdue formatting.
  final DateTime nowUtc;

  /// Domain task item rendered by this body.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = UiThemeTokens.of(context).colors;
    final details = _computeDueReadout(localizations, colors);

    return _TaskDueReadLines(
      dueFormatted: details.dueFormatted,
      dueColor: details.dueColor,
      autoPriorityLabel: details.autoPriorityLabel,
      anchorFormatted: details.anchorFormatted,
      dueNote: task.dueNote,
    );
  }

  /// Computes formatted due readout strings and urgency color for [task].
  ({
    String dueFormatted,
    Color dueColor,
    String? autoPriorityLabel,
    String? anchorFormatted,
  })
  _computeDueReadout(AppLocalizations localizations, UiColorTokens colors) {
    final isActive = !task.isCompleted;
    final isOverdue = isActive && !dueAtUtc.isAfter(nowUtc);
    final isWithinLead =
        isActive &&
        !task.isDuePassive &&
        task.isWithinDueLeadWindow(
          nowUtc,
          configuration.dueLeadWindow.duration,
        );
    return (
      dueFormatted: TaskScheduleHelper.formatDueDetail(
        dueAtUtc: dueAtUtc,
        nowUtc: nowUtc,
        isOverdue: isOverdue,
        config: configuration,
        localizations: localizations,
      ),
      dueColor: _resolveDueColor(
        colors: colors,
        isOverdue: isOverdue,
        isWithinLead: isWithinLead,
      ),
      autoPriorityLabel: isActive
          ? TaskScheduleHelper.formatDueAutoPriorityLabel(
              task: task,
              isAutoPrioritized: !isSomeday && !task.isPriority && isWithinLead,
              dueLeadWindow: configuration.dueLeadWindow,
              localizations: localizations,
            )
          : null,
      anchorFormatted: TaskScheduleHelper.formatDueAnchor(
        task: task,
        config: configuration,
        localizations: localizations,
      ),
    );
  }

  /// Resolves semantic text color for the due date based on urgency.
  Color _resolveDueColor({
    required UiColorTokens colors,
    required bool isOverdue,
    required bool isWithinLead,
  }) {
    if (isOverdue) {
      return colors.danger;
    }
    if (isWithinLead) {
      return colors.warning;
    }
    return colors.ink;
  }
}

/// Read-only display card for [TaskDueSection].
class _TaskDueReadCard extends StatelessWidget {
  /// Creates a [_TaskDueReadCard].
  const _TaskDueReadCard({
    required this.task,
    required this.dueAtUtc,
    required this.isSomeday,
    required this.configuration,
    required this.nowUtc,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Active workspace configuration supplying timezone and due lead-window settings.
  final WebDavConfig configuration;

  /// Non-null due UTC instant of [task].
  final DateTime dueAtUtc;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Whether [task] currently resides in Tier 5 (`Someday`).
  final bool isSomeday;

  /// Current evaluation UTC timestamp used for remaining/overdue formatting.
  final DateTime nowUtc;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  /// Domain task item rendered by this card.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: ValueKey<String>('task_due_read_${task.id}'),
      headerIcon: Icons.calendar_today_outlined,
      headerTitle: localizations.taskInfoDueLabel,
      headerTrailing: task.isCompleted
          ? null
          : _ScheduleSectionEditButton(
              buttonKey: ValueKey<String>('task_due_edit_button_${task.id}'),
              isBusy: isBusy,
              onPressed: onStartEdit,
            ),
      child: _TaskDueReadBody(
        task: task,
        dueAtUtc: dueAtUtc,
        isSomeday: isSomeday,
        configuration: configuration,
        nowUtc: nowUtc,
      ),
    );
  }
}

/// Vertical readout column rendering formatted due lines inside [_TaskDueReadBody].
class _TaskDueReadLines extends StatelessWidget {
  /// Creates a [_TaskDueReadLines].
  const _TaskDueReadLines({
    required this.dueFormatted,
    required this.dueColor,
    required this.autoPriorityLabel,
    required this.anchorFormatted,
    required this.dueNote,
  });

  /// Optional formatted schedule anchor readout.
  final String? anchorFormatted;

  /// Optional auto-priority explanation shown on active tasks.
  final String? autoPriorityLabel;

  /// Semantic urgency text color for [dueFormatted].
  final Color dueColor;

  /// Formatted due timestamp and remaining/overdue detail.
  final String dueFormatted;

  /// Optional persisted deadline note.
  final String? dueNote;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          dueFormatted,
          style: tokens.typography.control.copyWith(color: dueColor),
        ),
        if (autoPriorityLabel case final label?) ...<Widget>[
          const SizedBox(height: 4.0),
          Text(
            label,
            style: tokens.typography.meta.copyWith(color: colors.muted),
          ),
        ],
        if (anchorFormatted case final anchor?) ...<Widget>[
          const SizedBox(height: 4.0),
          Text(
            anchor,
            style: UiTypographyTokens.mono(
              tokens.typography.monoSmall.copyWith(color: colors.muted),
            ),
          ),
        ],
        if (dueNote case final note? when note.isNotEmpty)
          _ScheduleNoteReadText(note: note),
      ],
    );
  }
}

/// Manages inline editing controllers and submission for [TaskDueSection].
class _TaskDueSectionState extends ConsumerState<TaskDueSection> {
  late final TextEditingController _dueController;
  late final TextEditingController _dueNoteController;

  late bool _autoPrioritize;
  String? _dueError;
  String? _dueNoteError;
  bool _isSubmitting = false;
  String? _submitError;

  /// Formatted initial local due timestamp string (`''` when unset).
  String get _initialDueInput => widget.task.dueAt != null
      ? TaskScheduleHelper.formatLocalTimestamp(
          widget.task.dueAt,
          widget.configuration,
        )
      : '';

  @override
  void initState() {
    super.initState();
    _dueController = TextEditingController(text: _initialDueInput);
    _dueNoteController = TextEditingController(text: widget.task.dueNote ?? '');
    _autoPrioritize = !widget.task.isDuePassive;
  }

  @override
  void didUpdateWidget(covariant TaskDueSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _dueController.text = _initialDueInput;
      _dueNoteController.text = widget.task.dueNote ?? '';
      _autoPrioritize = !widget.task.isDuePassive;
      _dueError = null;
      _dueNoteError = null;
      _submitError = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _dueError = null;
      _dueNoteError = null;
      _submitError = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _dueController.dispose();
    _dueNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isControllerBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;
    final dueAt = widget.task.dueAt;

    if (!widget.isEditing || widget.task.isCompleted) {
      return dueAt == null
          ? const SizedBox.shrink()
          : _TaskDueReadCard(
              task: widget.task,
              dueAtUtc: dueAt,
              isSomeday: widget.isSomeday,
              configuration: widget.configuration,
              nowUtc: widget.nowUtc,
              isBusy: isBusy,
              onStartEdit: widget.onStartEdit,
            );
    }

    return _TaskDueEditCard(
      dueController: _dueController,
      dueNoteController: _dueNoteController,
      autoPrioritize: _autoPrioritize,
      hasExistingDue: dueAt != null,
      currentLocalDateTimeHint: widget.currentLocalDateTimeHint,
      dueError: _dueError,
      dueNoteError: _dueNoteError,
      submitError: _submitError,
      isBusy: isBusy,
      onChanged: _handleChanged,
      onAutoPrioritizeChanged: (value) =>
          setState(() => _autoPrioritize = value),
      onClear: _triggerClear,
      onCancel: widget.onCancelEdit,
      onSave: _triggerSave,
    );
  }

  /// Clears inline errors when the user edits due fields.
  void _handleChanged(String _) {
    if (_dueError != null || _dueNoteError != null || _submitError != null) {
      setState(() {
        _dueError = null;
        _dueNoteError = null;
        _submitError = null;
      });
    }
  }

  /// Clears the persisted due date via [BoardActionsNotifier.clearDue].
  Future<void> _handleClear() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    final result = await ref
        .read(boardActionsProvider.notifier)
        .clearDue(widget.task.id, locale: Localizations.localeOf(context));
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Saves the edited due date via [BoardActionsNotifier.saveDue].
  Future<void> _handleSave() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _dueError = null;
      _dueNoteError = null;
      _submitError = null;
    });
    final result = await ref
        .read(boardActionsProvider.notifier)
        .saveDue(
          widget.task.id,
          rawDue: _dueController.text,
          autoPrioritize: _autoPrioritize,
          rawDueNote: _dueNoteController.text,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _dueError = fieldErrors['due'];
          _dueNoteError = fieldErrors['dueNote'];
          _submitError = (_dueError == null && _dueNoteError == null)
              ? message
              : null;
        });
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Dispatches async clear from synchronous footer callbacks.
  void _triggerClear() => unawaited(_handleClear());

  /// Dispatches async save from synchronous footer callbacks.
  void _triggerSave() => unawaited(_handleSave());
}

/// Single-line title input and save/cancel buttons rendered inside [TaskInlineTitleEditor].
class _TaskInlineTitleEditorRow extends StatelessWidget {
  /// Creates a [_TaskInlineTitleEditorRow].
  const _TaskInlineTitleEditorRow({
    required this.taskId,
    required this.controller,
    required this.errorText,
    required this.isBusy,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
  });

  /// Controller for the edited task title.
  final TextEditingController controller;

  /// Optional validation or persistence error text.
  final String? errorText;

  /// Whether a save mutation is in flight.
  final bool isBusy;

  /// Callback cancelling inline title editing.
  final VoidCallback onCancel;

  /// Callback clearing errors when typing resumes.
  final ValueChanged<String> onChanged;

  /// Callback saving the edited title.
  final VoidCallback onSave;

  /// Canonical task identifier for deterministic keys.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: _TaskInlineTitleField(
            taskId: taskId,
            controller: controller,
            errorText: errorText,
            isBusy: isBusy,
            onChanged: onChanged,
            onSubmitted: onSave,
          ),
        ),
        const SizedBox(width: 6.0),
        UiButton(
          key: ValueKey<String>('task_title_editor_save_$taskId'),
          label: localizations.actionSave,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          isLoading: isBusy,
          onPressed: isBusy ? null : onSave,
        ),
        const SizedBox(width: 6.0),
        UiButton(
          key: ValueKey<String>('task_title_editor_cancel_$taskId'),
          label: localizations.actionCancel,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: isBusy ? null : onCancel,
        ),
      ],
    );
  }
}

/// Manages inline title editing state and validation readout for [TaskInlineTitleEditor].
class _TaskInlineTitleEditorState extends ConsumerState<TaskInlineTitleEditor> {
  late final TextEditingController _controller;

  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
    _controller.selection = TextSelection.collapsed(
      offset: widget.initialTitle.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isControllerBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TaskInlineTitleEditorRow(
          taskId: widget.taskId,
          controller: _controller,
          errorText: _errorText,
          isBusy: isBusy,
          onChanged: _handleChanged,
          onSave: _triggerSave,
          onCancel: widget.onCancel,
        ),
      ],
    );
  }

  /// Clears inline error text when the user resumes typing.
  void _handleChanged(String _) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  /// Persists the edited title through [BoardActionsNotifier.saveTitle].
  Future<void> _handleSave() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await ref
        .read(boardActionsProvider.notifier)
        .saveTitle(
          widget.taskId,
          _controller.text,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }

  /// Dispatches async title save from synchronous field/button callbacks.
  void _triggerSave() => unawaited(_handleSave());
}

/// Single-line title input field inside [_TaskInlineTitleEditorRow].
class _TaskInlineTitleField extends StatelessWidget {
  /// Creates a [_TaskInlineTitleField].
  const _TaskInlineTitleField({
    required this.taskId,
    required this.controller,
    required this.errorText,
    required this.isBusy,
    required this.onChanged,
    required this.onSubmitted,
  });

  /// Controller for the edited task title.
  final TextEditingController controller;

  /// Optional validation or persistence error text.
  final String? errorText;

  /// Whether a save mutation is in flight.
  final bool isBusy;

  /// Callback clearing errors when typing resumes.
  final ValueChanged<String> onChanged;

  /// Callback submitting the edited title.
  final VoidCallback onSubmitted;

  /// Canonical task identifier for deterministic keys.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiField(
      key: ValueKey<String>('task_title_editor_input_$taskId'),
      kind: UiFieldKind.text,
      controller: controller,
      maxLength: maxTdfTextLength,
      autofocus: true,
      enabled: !isBusy,
      errorText: errorText,
      semanticLabel: localizations.inlineEditTitleTooltip,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

/// Numeric repeat interval count input inside [_TaskRepeatEditFields].
class _TaskRepeatCountField extends StatelessWidget {
  /// Creates a [_TaskRepeatCountField].
  const _TaskRepeatCountField({
    required this.controller,
    required this.errorText,
    required this.isBusy,
    required this.onChanged,
    required this.onSave,
  });

  /// Controller for the repeat interval count (`1..3650`).
  final TextEditingController controller;

  /// Optional count validation error.
  final String? errorText;

  /// Whether a save or disable mutation is in flight.
  final bool isBusy;

  /// Callback clearing inline errors when typing resumes.
  final ValueChanged<String> onChanged;

  /// Callback saving the edited recurrence rule.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiField(
      kind: UiFieldKind.text,
      controller: controller,
      label: localizations.repeatIntervalLabel,
      hintText: '1',
      keyboardType: TextInputType.number,
      autofocus: true,
      enabled: !isBusy,
      errorText: errorText,
      onChanged: onChanged,
      onSubmitted: (_) => onSave(),
    );
  }
}

/// Inline editing card for [TaskRepeatSection].
class _TaskRepeatEditCard extends StatelessWidget {
  /// Creates a [_TaskRepeatEditCard].
  const _TaskRepeatEditCard({
    required this.countController,
    required this.unit,
    required this.leadDaysController,
    required this.hasDueDate,
    required this.hasExistingRepeat,
    required this.countError,
    required this.leadError,
    required this.submitError,
    required this.isBusy,
    required this.onChanged,
    required this.onUnitChanged,
    required this.onDisable,
    required this.onCancel,
    required this.onSave,
  });

  /// Controller for the repeat interval count (`1..3650`).
  final TextEditingController countController;

  /// Optional count validation error.
  final String? countError;

  /// Whether the task has a due date enabling preparation lead days.
  final bool hasDueDate;

  /// Whether the task currently repeats (shows Disable repeat button).
  final bool hasExistingRepeat;

  /// Whether a save or disable mutation is in flight.
  final bool isBusy;

  /// Controller for preparation lead days (`0..3650`).
  final TextEditingController leadDaysController;

  /// Optional lead-days validation error.
  final String? leadError;

  /// Callback cancelling inline edit.
  final VoidCallback onCancel;

  /// Callback clearing inline errors when typing resumes.
  final ValueChanged<String> onChanged;

  /// Callback disabling recurrence on the task.
  final VoidCallback onDisable;

  /// Callback saving the edited recurrence rule.
  final VoidCallback onSave;

  /// Callback changing recurrence unit.
  final ValueChanged<RepeatUnit> onUnitChanged;

  /// Optional general persistence error.
  final String? submitError;

  /// Selected recurrence unit.
  final RepeatUnit unit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('task_repeat_edit_card'),
      isEditing: true,
      headerIcon: Icons.repeat_rounded,
      headerTitle: localizations.repeatFlagLabel,
      footer: EntityInlineEditorFooter(
        errorText: submitError,
        clearLabel: hasExistingRepeat
            ? localizations.inlineDisableRepeatAction
            : null,
        onClear: hasExistingRepeat ? onDisable : null,
        onCancel: onCancel,
        onSave: onSave,
        isBusy: isBusy,
      ),
      child: _TaskRepeatEditFields(
        countController: countController,
        unit: unit,
        leadDaysController: leadDaysController,
        hasDueDate: hasDueDate,
        countError: countError,
        leadError: leadError,
        isBusy: isBusy,
        onChanged: onChanged,
        onUnitChanged: onUnitChanged,
        onSave: onSave,
      ),
    );
  }
}

/// Interval count, recurrence unit, and lead-days inputs inside [_TaskRepeatEditCard].
class _TaskRepeatEditFields extends StatelessWidget {
  /// Creates a [_TaskRepeatEditFields].
  const _TaskRepeatEditFields({
    required this.countController,
    required this.unit,
    required this.leadDaysController,
    required this.hasDueDate,
    required this.countError,
    required this.leadError,
    required this.isBusy,
    required this.onChanged,
    required this.onUnitChanged,
    required this.onSave,
  });

  /// Controller for the repeat interval count (`1..3650`).
  final TextEditingController countController;

  /// Optional count validation error.
  final String? countError;

  /// Whether the task has a due date enabling preparation lead days.
  final bool hasDueDate;

  /// Whether a save or disable mutation is in flight.
  final bool isBusy;

  /// Controller for preparation lead days (`0..3650`).
  final TextEditingController leadDaysController;

  /// Optional lead-days validation error.
  final String? leadError;

  /// Callback clearing inline errors when typing resumes.
  final ValueChanged<String> onChanged;

  /// Callback saving the edited recurrence rule.
  final VoidCallback onSave;

  /// Callback changing recurrence unit.
  final ValueChanged<RepeatUnit> onUnitChanged;

  /// Selected recurrence unit.
  final RepeatUnit unit;

  @override
  Widget build(BuildContext context) {
    final spacing = UiThemeTokens.of(context).spacing.space2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TaskRepeatCountField(
          controller: countController,
          errorText: countError,
          isBusy: isBusy,
          onChanged: onChanged,
          onSave: onSave,
        ),
        SizedBox(height: spacing),
        _TaskRepeatUnitControl(
          unit: unit,
          isBusy: isBusy,
          onUnitChanged: onUnitChanged,
        ),
        SizedBox(height: spacing),
        _TaskRepeatLeadDaysField(
          controller: leadDaysController,
          hasDueDate: hasDueDate,
          errorText: leadError,
          isBusy: isBusy,
          onChanged: onChanged,
          onSave: onSave,
        ),
      ],
    );
  }
}

/// Preparation lead-days input inside [_TaskRepeatEditFields].
class _TaskRepeatLeadDaysField extends StatelessWidget {
  /// Creates a [_TaskRepeatLeadDaysField].
  const _TaskRepeatLeadDaysField({
    required this.controller,
    required this.hasDueDate,
    required this.errorText,
    required this.isBusy,
    required this.onChanged,
    required this.onSave,
  });

  /// Controller for preparation lead days (`0..3650`).
  final TextEditingController controller;

  /// Optional lead-days validation error.
  final String? errorText;

  /// Whether the task has a due date enabling preparation lead days.
  final bool hasDueDate;

  /// Whether a save or disable mutation is in flight.
  final bool isBusy;

  /// Callback clearing inline errors when typing resumes.
  final ValueChanged<String> onChanged;

  /// Callback saving the edited recurrence rule.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiField(
      kind: UiFieldKind.text,
      controller: controller,
      label: localizations.repeatLeadDaysLabel,
      hintText: localizations.repeatLeadDaysHint,
      helperText: hasDueDate
          ? null
          : localizations.inlineRepeatLeadNeedsDueHint,
      keyboardType: TextInputType.number,
      enabled: !isBusy && hasDueDate,
      errorText: errorText,
      onChanged: onChanged,
      onSubmitted: (_) => onSave(),
    );
  }
}

/// Read-only recurrence summary, completions count, and lead label inside [_TaskRepeatReadCard].
class _TaskRepeatReadBody extends StatelessWidget {
  /// Creates a [_TaskRepeatReadBody].
  const _TaskRepeatReadBody({required this.task, required this.repeatRule});

  /// Non-null recurrence rule configured on [task].
  final TaskRepeatRule repeatRule;

  /// Domain task item rendered by this body.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final labels = _formatRepeatLabels(localizations);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          labels.summary,
          style: tokens.typography.control.copyWith(color: colors.ink),
        ),
        if (labels.completions case final completions?) ...<Widget>[
          const SizedBox(height: 4.0),
          Text(
            completions,
            style: tokens.typography.meta.copyWith(color: colors.muted),
          ),
        ],
        if (labels.lead case final lead?) ...<Widget>[
          const SizedBox(height: 4.0),
          Text(
            lead,
            style: tokens.typography.meta.copyWith(color: colors.muted),
          ),
        ],
      ],
    );
  }

  /// Formats the recurrence summary, completions count, and lead-days labels.
  ({String summary, String? completions, String? lead}) _formatRepeatLabels(
    AppLocalizations localizations,
  ) {
    return (
      summary: TaskScheduleHelper.formatRepeatPhrase(repeatRule, localizations),
      completions: task.completions > 0
          ? localizations.taskInfoRepeatCompletions('${task.completions}')
          : null,
      lead: repeatRule.leadDays > 0
          ? localizations.taskInfoRepeatLeadDays('${repeatRule.leadDays}')
          : null,
    );
  }
}

/// Read-only display card for [TaskRepeatSection].
class _TaskRepeatReadCard extends StatelessWidget {
  /// Creates a [_TaskRepeatReadCard].
  const _TaskRepeatReadCard({
    required this.task,
    required this.repeatRule,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  /// Non-null recurrence rule configured on [task].
  final TaskRepeatRule repeatRule;

  /// Domain task item rendered by this card.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: ValueKey<String>('task_repeat_read_${task.id}'),
      headerIcon: Icons.repeat_rounded,
      headerTitle: localizations.repeatFlagLabel,
      headerTrailing: task.isCompleted
          ? null
          : _ScheduleSectionEditButton(
              buttonKey: ValueKey<String>('task_repeat_edit_button_${task.id}'),
              isBusy: isBusy,
              onPressed: onStartEdit,
            ),
      child: _TaskRepeatReadBody(task: task, repeatRule: repeatRule),
    );
  }
}

/// Manages inline recurrence editing controllers and submission for [TaskRepeatSection].
class _TaskRepeatSectionState extends ConsumerState<TaskRepeatSection> {
  late final TextEditingController _countController;
  late final TextEditingController _leadDaysController;

  String? _countError;
  bool _isSubmitting = false;
  String? _leadError;
  String? _submitError;
  late RepeatUnit _unit;

  @override
  void initState() {
    super.initState();
    final rule = widget.task.repeatRule;
    _countController = TextEditingController(text: '${rule?.count ?? 1}');
    _leadDaysController = TextEditingController(text: '${rule?.leadDays ?? 0}');
    _unit = rule?.unit ?? RepeatUnit.days;
  }

  @override
  void didUpdateWidget(covariant TaskRepeatSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      final rule = widget.task.repeatRule;
      _countController.text = '${rule?.count ?? 1}';
      _leadDaysController.text = '${rule?.leadDays ?? 0}';
      _unit = rule?.unit ?? RepeatUnit.days;
      _countError = null;
      _leadError = null;
      _submitError = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _countError = null;
      _leadError = null;
      _submitError = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _countController.dispose();
    _leadDaysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isControllerBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;
    final repeatRule = widget.task.repeatRule;

    if (!widget.isEditing || widget.task.isCompleted) {
      return repeatRule == null
          ? const SizedBox.shrink()
          : _TaskRepeatReadCard(
              task: widget.task,
              repeatRule: repeatRule,
              isBusy: isBusy,
              onStartEdit: widget.onStartEdit,
            );
    }

    return _TaskRepeatEditCard(
      countController: _countController,
      unit: _unit,
      leadDaysController: _leadDaysController,
      hasDueDate: widget.task.dueAt != null,
      hasExistingRepeat: repeatRule != null,
      countError: _countError,
      leadError: _leadError,
      submitError: _submitError,
      isBusy: isBusy,
      onChanged: _handleChanged,
      onUnitChanged: (nextUnit) => setState(() => _unit = nextUnit),
      onDisable: _triggerDisable,
      onCancel: widget.onCancelEdit,
      onSave: _triggerSave,
    );
  }

  /// Clears inline validation errors when typing resumes.
  void _handleChanged(String _) {
    if (_countError != null || _leadError != null || _submitError != null) {
      setState(() {
        _countError = null;
        _leadError = null;
        _submitError = null;
      });
    }
  }

  /// Disables recurrence via [BoardActionsNotifier.disableRepeat].
  Future<void> _handleDisable() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    final result = await ref
        .read(boardActionsProvider.notifier)
        .disableRepeat(widget.task.id, locale: Localizations.localeOf(context));
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Saves edited recurrence parameters via [BoardActionsNotifier.saveRepeat].
  Future<void> _handleSave() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _countError = null;
      _leadError = null;
      _submitError = null;
    });
    final result = await ref
        .read(boardActionsProvider.notifier)
        .saveRepeat(
          widget.task.id,
          rawCount: _countController.text,
          unit: _unit,
          rawLeadDays: _leadDaysController.text,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _countError = fieldErrors['repeatCount'];
          _leadError = fieldErrors['repeatLeadDays'];
          _submitError = (_countError == null && _leadError == null)
              ? message
              : null;
        });
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Dispatches async repeat disable from synchronous callbacks.
  void _triggerDisable() => unawaited(_handleDisable());

  /// Dispatches async repeat save from synchronous callbacks.
  void _triggerSave() => unawaited(_handleSave());
}

/// Three-way recurrence unit segmented control inside [_TaskRepeatEditFields].
class _TaskRepeatUnitControl extends StatelessWidget {
  /// Creates a [_TaskRepeatUnitControl].
  const _TaskRepeatUnitControl({
    required this.unit,
    required this.isBusy,
    required this.onUnitChanged,
  });

  /// Whether a save or disable mutation is in flight.
  final bool isBusy;

  /// Callback changing recurrence unit.
  final ValueChanged<RepeatUnit> onUnitChanged;

  /// Selected recurrence unit.
  final RepeatUnit unit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiSegmentedControl<RepeatUnit>(
      segments: <UiSegment<RepeatUnit>>[
        UiSegment<RepeatUnit>(
          value: RepeatUnit.days,
          label: localizations.repeatUnitDays,
        ),
        UiSegment<RepeatUnit>(
          value: RepeatUnit.weeks,
          label: localizations.repeatUnitWeeks,
        ),
        UiSegment<RepeatUnit>(
          value: RepeatUnit.months,
          label: localizations.repeatUnitMonths,
        ),
      ],
      value: unit,
      enabled: !isBusy,
      semanticLabel: localizations.repeatFlagLabel,
      onChanged: onUnitChanged,
    );
  }
}

/// Inline editing card for [TaskSuspendedSection].
class _TaskSuspendedEditCard extends StatelessWidget {
  /// Creates a [_TaskSuspendedEditCard].
  const _TaskSuspendedEditCard({
    required this.indefinitely,
    required this.untilController,
    required this.noteController,
    required this.hasExistingSuspension,
    required this.currentLocalDateTimeHint,
    required this.untilError,
    required this.noteError,
    required this.submitError,
    required this.isBusy,
    required this.onModeChanged,
    required this.onChanged,
    required this.onResume,
    required this.onCancel,
    required this.onSave,
  });

  /// Current local timestamp seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether the task is currently suspended (shows Resume task button).
  final bool hasExistingSuspension;

  /// Whether indefinite suspension is selected.
  final bool indefinitely;

  /// Whether a save or resume mutation is in flight.
  final bool isBusy;

  /// Controller for the optional deferral note.
  final TextEditingController noteController;

  /// Optional deferral note validation error.
  final String? noteError;

  /// Callback cancelling inline edit.
  final VoidCallback onCancel;

  /// Callback clearing errors when text changes.
  final ValueChanged<String> onChanged;

  /// Callback toggling between timed (`false`) and indefinite (`true`) suspension.
  final ValueChanged<bool> onModeChanged;

  /// Callback resuming the suspended task.
  final VoidCallback onResume;

  /// Callback saving suspension settings.
  final VoidCallback onSave;

  /// Optional general persistence error.
  final String? submitError;

  /// Controller for the timed suspension timestamp.
  final TextEditingController untilController;

  /// Optional timed suspension timestamp error.
  final String? untilError;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('task_suspended_edit_card'),
      isEditing: true,
      headerIcon: Icons.pause_circle_outline_rounded,
      headerTitle: localizations.taskSuspendedLabel,
      footer: EntityInlineEditorFooter(
        errorText: submitError,
        clearLabel: hasExistingSuspension
            ? localizations.inlineResumeTaskAction
            : null,
        onClear: hasExistingSuspension ? onResume : null,
        onCancel: onCancel,
        onSave: onSave,
        isBusy: isBusy,
      ),
      child: _TaskSuspendedEditFields(
        indefinitely: indefinitely,
        untilController: untilController,
        noteController: noteController,
        currentLocalDateTimeHint: currentLocalDateTimeHint,
        untilError: untilError,
        noteError: noteError,
        isBusy: isBusy,
        onModeChanged: onModeChanged,
        onChanged: onChanged,
        onSave: onSave,
      ),
    );
  }
}

/// Deferral mode toggle, optional until timestamp, and note input inside [_TaskSuspendedEditCard].
class _TaskSuspendedEditFields extends StatelessWidget {
  /// Creates a [_TaskSuspendedEditFields].
  const _TaskSuspendedEditFields({
    required this.indefinitely,
    required this.untilController,
    required this.noteController,
    required this.currentLocalDateTimeHint,
    required this.untilError,
    required this.noteError,
    required this.isBusy,
    required this.onModeChanged,
    required this.onChanged,
    required this.onSave,
  });

  /// Current local timestamp seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether indefinite suspension is selected.
  final bool indefinitely;

  /// Whether a save or resume mutation is in flight.
  final bool isBusy;

  /// Controller for the optional deferral note.
  final TextEditingController noteController;

  /// Optional deferral note validation error.
  final String? noteError;

  /// Callback clearing errors when text changes.
  final ValueChanged<String> onChanged;

  /// Callback toggling between timed (`false`) and indefinite (`true`) suspension.
  final ValueChanged<bool> onModeChanged;

  /// Callback saving suspension settings.
  final VoidCallback onSave;

  /// Controller for the timed suspension timestamp.
  final TextEditingController untilController;

  /// Optional timed suspension timestamp error.
  final String? untilError;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final spacing = UiThemeTokens.of(context).spacing.space2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TaskSuspendedModeControl(
          indefinitely: indefinitely,
          isBusy: isBusy,
          onModeChanged: onModeChanged,
        ),
        if (!indefinitely) ...<Widget>[
          SizedBox(height: spacing),
          EntityHybridDateTimeField(
            controller: untilController,
            label: localizations.taskSuspendedUntilLabel,
            fallbackLocalDateTime: currentLocalDateTimeHint,
            autofocus: true,
            enabled: !isBusy,
            errorText: untilError,
            onChanged: onChanged,
            onSubmitted: (_) => onSave(),
          ),
        ],
        SizedBox(height: spacing),
        _ScheduleNoteField(
          controller: noteController,
          label: localizations.taskSuspendedNoteLabel,
          hintText: localizations.taskSuspendedNoteHint,
          enabled: !isBusy,
          errorText: noteError,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Two-way timed vs indefinite suspension segmented control inside [_TaskSuspendedEditFields].
class _TaskSuspendedModeControl extends StatelessWidget {
  /// Creates a [_TaskSuspendedModeControl].
  const _TaskSuspendedModeControl({
    required this.indefinitely,
    required this.isBusy,
    required this.onModeChanged,
  });

  /// Whether indefinite suspension is selected.
  final bool indefinitely;

  /// Whether a save or resume mutation is in flight.
  final bool isBusy;

  /// Callback toggling between timed (`false`) and indefinite (`true`) suspension.
  final ValueChanged<bool> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiSegmentedControl<bool>(
      segments: <UiSegment<bool>>[
        UiSegment<bool>(
          value: false,
          label: localizations.suspendedUntilModeLabel,
        ),
        UiSegment<bool>(
          value: true,
          label: localizations.suspendedForeverModeLabel,
        ),
      ],
      value: indefinitely,
      enabled: !isBusy,
      semanticLabel: localizations.taskSuspendedLabel,
      onChanged: onModeChanged,
    );
  }
}

/// Read-only display card for [TaskSuspendedSection].
class _TaskSuspendedReadCard extends StatelessWidget {
  /// Creates a [_TaskSuspendedReadCard].
  const _TaskSuspendedReadCard({
    required this.task,
    required this.configuration,
    required this.nowUtc,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Active workspace configuration supplying timezone settings.
  final WebDavConfig configuration;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Current evaluation UTC timestamp used for remaining deferral formatting.
  final DateTime nowUtc;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  /// Domain task item rendered by this card.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final suspendedSummary = TaskScheduleHelper.formatSuspendedDetail(
      task: task,
      nowUtc: nowUtc,
      config: configuration,
      localizations: localizations,
    );

    return UiCard.inset(
      key: ValueKey<String>('task_suspended_read_${task.id}'),
      headerIcon: Icons.pause_circle_outline_rounded,
      headerTitle: localizations.taskSuspendedLabel,
      headerTrailing: task.isCompleted
          ? null
          : _ScheduleSectionEditButton(
              buttonKey: ValueKey<String>(
                'task_suspended_edit_button_${task.id}',
              ),
              isBusy: isBusy,
              onPressed: onStartEdit,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            suspendedSummary,
            style: tokens.typography.control.copyWith(color: colors.ink),
          ),
          if (task.suspendedNote case final note? when note.isNotEmpty)
            _ScheduleNoteReadText(note: note),
        ],
      ),
    );
  }
}

/// Manages inline suspension editing controllers and submission for [TaskSuspendedSection].
class _TaskSuspendedSectionState extends ConsumerState<TaskSuspendedSection> {
  late final TextEditingController _noteController;
  late final TextEditingController _untilController;

  late bool _indefinitely;
  bool _isSubmitting = false;
  String? _noteError;
  String? _submitError;
  String? _untilError;

  /// Formatted initial local suspended-until timestamp string (`''` when unset or forever).
  String get _initialUntilInput =>
      TaskScheduleHelper.formatInitialSuspendedText(
        widget.task.suspendedAt,
        widget.configuration,
      );

  /// Whether [widget.task] currently carries an active finite or indefinite suspension.
  bool get _isSuspended =>
      widget.task.isSuspendedForever ||
      widget.task.hasActiveSuspendedAt(widget.nowUtc);

  @override
  void initState() {
    super.initState();
    _indefinitely = widget.task.isSuspendedForever;
    _untilController = TextEditingController(text: _initialUntilInput);
    _noteController = TextEditingController(
      text: widget.task.suspendedNote ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant TaskSuspendedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _indefinitely = widget.task.isSuspendedForever;
      _untilController.text = _initialUntilInput;
      _noteController.text = widget.task.suspendedNote ?? '';
      _untilError = null;
      _noteError = null;
      _submitError = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _untilError = null;
      _noteError = null;
      _submitError = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _untilController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isControllerBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;
    final isSuspended = _isSuspended;

    if (!widget.isEditing || widget.task.isCompleted) {
      return !isSuspended
          ? const SizedBox.shrink()
          : _TaskSuspendedReadCard(
              task: widget.task,
              configuration: widget.configuration,
              nowUtc: widget.nowUtc,
              isBusy: isBusy,
              onStartEdit: widget.onStartEdit,
            );
    }

    return _TaskSuspendedEditCard(
      indefinitely: _indefinitely,
      untilController: _untilController,
      noteController: _noteController,
      hasExistingSuspension: isSuspended,
      currentLocalDateTimeHint: widget.currentLocalDateTimeHint,
      untilError: _untilError,
      noteError: _noteError,
      submitError: _submitError,
      isBusy: isBusy,
      onModeChanged: (indefinitely) => setState(() {
        _indefinitely = indefinitely;
        _untilError = null;
      }),
      onChanged: _handleChanged,
      onResume: _triggerResume,
      onCancel: widget.onCancelEdit,
      onSave: _triggerSave,
    );
  }

  /// Clears inline validation errors when typing resumes.
  void _handleChanged(String _) {
    if (_untilError != null || _noteError != null || _submitError != null) {
      setState(() {
        _untilError = null;
        _noteError = null;
        _submitError = null;
      });
    }
  }

  /// Resumes the suspended task via [BoardActionsNotifier.resumeTask].
  Future<void> _handleResume() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    final result = await ref
        .read(boardActionsProvider.notifier)
        .resumeTask(widget.task.id, locale: Localizations.localeOf(context));
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Saves edited suspension parameters via [BoardActionsNotifier.saveSuspended].
  Future<void> _handleSave() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _untilError = null;
      _noteError = null;
      _submitError = null;
    });
    final result = await ref
        .read(boardActionsProvider.notifier)
        .saveSuspended(
          widget.task.id,
          indefinitely: _indefinitely,
          rawUntil: _untilController.text,
          rawNote: _noteController.text,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _untilError = fieldErrors['suspended'];
          _noteError = fieldErrors['suspendedNote'];
          _submitError = (_untilError == null && _noteError == null)
              ? message
              : null;
        });
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Dispatches async resume from synchronous callbacks.
  void _triggerResume() => unawaited(_handleResume());

  /// Dispatches async suspension save from synchronous callbacks.
  void _triggerSave() => unawaited(_handleSave());
}
