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
import '../../models/task_tier.dart';
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
import '../widgets/entity_inline_name_editor.dart';

/// Pure Due timestamp, auto-prioritize toggle, and deadline note form fields shared by live and draft task editors.
class TaskDueFields extends StatelessWidget {
  /// Creates a [TaskDueFields].
  const TaskDueFields({
    super.key,
    required this.dueController,
    required this.dueNoteController,
    required this.autoPrioritize,
    required this.currentLocalDateTimeHint,
    required this.dueError,
    required this.dueNoteError,
    required this.isBusy,
    required this.onDueChanged,
    required this.onDueNoteChanged,
    required this.onAutoPrioritizeChanged,
    this.autofocus = false,
    this.onSubmitted,
  });

  /// Auto-prioritize near deadline toggle state.
  final bool autoPrioritize;

  /// Requests initial focus on the due date input when mounted.
  final bool autofocus;

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

  /// Callback notified when due timestamp text changes.
  final ValueChanged<String> onDueChanged;

  /// Callback notified when deadline note text changes.
  final ValueChanged<String> onDueNoteChanged;

  /// Optional callback invoked when the due timestamp input submits.
  final VoidCallback? onSubmitted;

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
          autofocus: autofocus,
          enabled: !isBusy,
          errorText: dueError,
          onChanged: onDueChanged,
          onSubmitted: onSubmitted == null ? null : (_) => onSubmitted?.call(),
        ),
        SizedBox(height: spacing),
        UiToggleRow(
          label: localizations.taskDueAutoPrioritizeLabel,
          description: localizations.taskDueAutoPrioritizeSubtitle,
          value: autoPrioritize,
          isDense: true,
          enabled: !isBusy,
          onChanged: onAutoPrioritizeChanged,
        ),
        SizedBox(height: spacing),
        _ScheduleNoteField(
          controller: dueNoteController,
          label: localizations.taskDueNoteLabel,
          hintText: localizations.taskDueNoteHint,
          enabled: !isBusy,
          errorText: dueNoteError,
          onChanged: onDueNoteChanged,
        ),
      ],
    );
  }
}

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
class TaskInlineTitleEditor extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final isBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );
    return EntityInlineNameEditor(
      initialValue: initialTitle,
      hintText: localizations.taskNameLabel,
      semanticsLabel: localizations.inlineEditTitleTooltip,
      inputKey: ValueKey<String>('task_title_editor_input_$taskId'),
      saveKey: ValueKey<String>('task_title_editor_save_$taskId'),
      cancelKey: ValueKey<String>('task_title_editor_cancel_$taskId'),
      isBusy: isBusy,
      onCancel: onCancel,
      onSave: (value) => ref
          .read(boardActionsProvider.notifier)
          .saveTitle(taskId, value, locale: locale),
    );
  }
}

/// Queue & Priority segmented placement inset card shared by live task cards and [TaskDraftCard].
class TaskPlacementCard extends StatelessWidget {
  /// Creates a [TaskPlacementCard].
  const TaskPlacementCard({
    super.key,
    this.cardKey,
    this.controlKey,
    required this.placement,
    required this.isBusy,
    required this.onChanged,
    this.caption,
  });

  /// Optional explanatory caption rendered below the segmented control.
  final String? caption;

  /// Optional stable key placed on the outer [UiCard.inset].
  final Key? cardKey;

  /// Optional stable key placed on the [UiSegmentedControl].
  final Key? controlKey;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback updating the selected [QuickAddMode].
  final ValueChanged<QuickAddMode> onChanged;

  /// Currently selected placement mode.
  final QuickAddMode placement;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final segmented = _TaskPlacementSegmentedControl(
      controlKey: controlKey,
      placement: placement,
      isBusy: isBusy,
      onChanged: onChanged,
    );

    return UiCard.inset(
      key: cardKey,
      headerIcon: Icons.bolt_outlined,
      headerTitle: localizations.inlinePlacementSectionTitle,
      child: caption == null
          ? segmented
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                segmented,
                SizedBox(height: tokens.spacing.space2),
                Text(
                  caption ?? '',
                  style: tokens.typography.meta.copyWith(
                    color: tokens.colors.muted,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Pure recurrence interval count, unit, and preparation lead-days fields shared by live and draft task editors.
class TaskRepeatFields extends StatelessWidget {
  /// Creates a [TaskRepeatFields].
  const TaskRepeatFields({
    super.key,
    required this.countController,
    required this.unit,
    required this.leadDaysController,
    required this.hasDueDate,
    required this.countError,
    required this.leadError,
    required this.isBusy,
    required this.onCountChanged,
    required this.onLeadDaysChanged,
    required this.onUnitChanged,
    this.autofocus = false,
    this.onSubmitted,
  });

  /// Requests initial focus on the repeat interval count input when mounted.
  final bool autofocus;

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

  /// Callback notified when interval count text changes.
  final ValueChanged<String> onCountChanged;

  /// Callback notified when lead-days text changes.
  final ValueChanged<String> onLeadDaysChanged;

  /// Optional callback invoked when a repeat text field submits.
  final VoidCallback? onSubmitted;

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
          autofocus: autofocus,
          errorText: countError,
          isBusy: isBusy,
          onChanged: onCountChanged,
          onSubmitted: onSubmitted,
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
          onChanged: onLeadDaysChanged,
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }
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

/// Pure suspension mode, optional until timestamp, and deferral note fields shared by live and draft task editors.
class TaskSuspendedFields extends StatelessWidget {
  /// Creates a [TaskSuspendedFields].
  const TaskSuspendedFields({
    super.key,
    required this.indefinitely,
    required this.untilController,
    required this.noteController,
    required this.currentLocalDateTimeHint,
    required this.untilError,
    required this.noteError,
    required this.isBusy,
    required this.onModeChanged,
    required this.onUntilChanged,
    required this.onNoteChanged,
    this.autofocus = false,
    this.onSubmitted,
  });

  /// Requests initial focus on the timed until input when mounted.
  final bool autofocus;

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

  /// Callback toggling between timed (`false`) and indefinite (`true`) suspension.
  final ValueChanged<bool> onModeChanged;

  /// Callback notified when deferral note text changes.
  final ValueChanged<String> onNoteChanged;

  /// Optional callback invoked when the until timestamp submits.
  final VoidCallback? onSubmitted;

  /// Callback notified when timed until timestamp text changes.
  final ValueChanged<String> onUntilChanged;

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
            autofocus: autofocus,
            enabled: !isBusy,
            errorText: untilError,
            onChanged: onUntilChanged,
            onSubmitted: onSubmitted == null ? null : _handleSubmitted,
          ),
        ],
        SizedBox(height: spacing),
        _ScheduleNoteField(
          controller: noteController,
          label: localizations.taskSuspendedNoteLabel,
          hintText: localizations.taskSuspendedNoteHint,
          enabled: !isBusy,
          errorText: noteError,
          onChanged: onNoteChanged,
        ),
      ],
    );
  }

  /// Forwards keyboard submit events from the timed suspension field to [onSubmitted].
  void _handleSubmitted(String _) => onSubmitted?.call();
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
      child: TaskDueFields(
        dueController: dueController,
        dueNoteController: dueNoteController,
        autoPrioritize: autoPrioritize,
        currentLocalDateTimeHint: currentLocalDateTimeHint,
        autofocus: true,
        dueError: dueError,
        dueNoteError: dueNoteError,
        isBusy: isBusy,
        onDueChanged: onChanged,
        onDueNoteChanged: onChanged,
        onAutoPrioritizeChanged: onAutoPrioritizeChanged,
        onSubmitted: onSave,
      ),
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
    try {
      final result = await ref
          .read(boardActionsProvider.notifier)
          .clearDue(widget.task.id, locale: Localizations.localeOf(context));
      if (!mounted) {
        return;
      }
      switch (result) {
        case ActionSucceeded():
          break;
        case ActionValidationFailed(:final message):
        case ActionPersistFailed(:final message):
          setState(() => _submitError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
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
    try {
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
          break;
        case ActionValidationFailed(:final message, :final fieldErrors):
          setState(() {
            _dueError = fieldErrors['due'];
            _dueNoteError = fieldErrors['dueNote'];
            _submitError = (_dueError == null && _dueNoteError == null)
                ? message
                : null;
          });
        case ActionPersistFailed(:final message):
          setState(() => _submitError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Dispatches async clear from synchronous footer callbacks.
  void _triggerClear() => unawaited(_handleClear());

  /// Dispatches async save from synchronous footer callbacks.
  void _triggerSave() => unawaited(_handleSave());
}

/// Three-way `Queue` / `Priority` / `Someday` segmented control inside [TaskPlacementCard].
class _TaskPlacementSegmentedControl extends StatelessWidget {
  /// Creates a [_TaskPlacementSegmentedControl].
  const _TaskPlacementSegmentedControl({
    required this.controlKey,
    required this.placement,
    required this.isBusy,
    required this.onChanged,
  });

  /// Optional deterministic widget key applied to the segmented control.
  final Key? controlKey;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback changing task placement.
  final ValueChanged<QuickAddMode> onChanged;

  /// Selected placement mode.
  final QuickAddMode placement;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiSegmentedControl<QuickAddMode>(
      key: controlKey,
      segments: <UiSegment<QuickAddMode>>[
        UiSegment<QuickAddMode>(
          value: QuickAddMode.standard,
          label: localizations.placementQueueOption,
        ),
        UiSegment<QuickAddMode>(
          value: QuickAddMode.priority,
          label: localizations.quickAddPriority,
        ),
        UiSegment<QuickAddMode>(
          value: QuickAddMode.someday,
          label: localizations.tier5Name,
        ),
      ],
      value: placement,
      enabled: !isBusy,
      semanticLabel: localizations.inlinePlacementSectionTitle,
      onChanged: onChanged,
    );
  }
}

/// Numeric repeat interval count input inside [TaskRepeatFields].
class _TaskRepeatCountField extends StatelessWidget {
  /// Creates a [_TaskRepeatCountField].
  const _TaskRepeatCountField({
    required this.controller,
    required this.autofocus,
    required this.errorText,
    required this.isBusy,
    required this.onChanged,
    required this.onSubmitted,
  });

  /// Whether the input requests initial focus when mounted.
  final bool autofocus;

  /// Controller for the repeat interval count (`1..3650`).
  final TextEditingController controller;

  /// Optional count validation error.
  final String? errorText;

  /// Whether a save or disable mutation is in flight.
  final bool isBusy;

  /// Callback clearing inline errors when typing resumes.
  final ValueChanged<String> onChanged;

  /// Optional callback saving the edited recurrence rule on submit.
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiField(
      controller: controller,
      label: localizations.repeatIntervalLabel,
      hintText: '1',
      keyboardType: TextInputType.number,
      autofocus: autofocus,
      enabled: !isBusy,
      errorText: errorText,
      onChanged: onChanged,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted?.call(),
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
      child: TaskRepeatFields(
        countController: countController,
        unit: unit,
        leadDaysController: leadDaysController,
        hasDueDate: hasDueDate,
        autofocus: true,
        countError: countError,
        leadError: leadError,
        isBusy: isBusy,
        onCountChanged: onChanged,
        onLeadDaysChanged: onChanged,
        onUnitChanged: onUnitChanged,
        onSubmitted: onSave,
      ),
    );
  }
}

/// Preparation lead-days input inside [TaskRepeatFields].
class _TaskRepeatLeadDaysField extends StatelessWidget {
  /// Creates a [_TaskRepeatLeadDaysField].
  const _TaskRepeatLeadDaysField({
    required this.controller,
    required this.hasDueDate,
    required this.errorText,
    required this.isBusy,
    required this.onChanged,
    required this.onSubmitted,
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

  /// Optional callback saving the edited recurrence rule on submit.
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiField(
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
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted?.call(),
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
    try {
      final result = await ref
          .read(boardActionsProvider.notifier)
          .disableRepeat(
            widget.task.id,
            locale: Localizations.localeOf(context),
          );
      if (!mounted) {
        return;
      }
      switch (result) {
        case ActionSucceeded():
          break;
        case ActionValidationFailed(:final message):
        case ActionPersistFailed(:final message):
          setState(() => _submitError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
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
    try {
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
          break;
        case ActionValidationFailed(:final message, :final fieldErrors):
          setState(() {
            _countError = fieldErrors['repeatCount'];
            _leadError = fieldErrors['repeatLeadDays'];
            _submitError = (_countError == null && _leadError == null)
                ? message
                : null;
          });
        case ActionPersistFailed(:final message):
          setState(() => _submitError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
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
      child: TaskSuspendedFields(
        indefinitely: indefinitely,
        untilController: untilController,
        noteController: noteController,
        currentLocalDateTimeHint: currentLocalDateTimeHint,
        autofocus: true,
        untilError: untilError,
        noteError: noteError,
        isBusy: isBusy,
        onModeChanged: onModeChanged,
        onUntilChanged: onChanged,
        onNoteChanged: onChanged,
        onSubmitted: onSave,
      ),
    );
  }
}

/// Two-way timed vs indefinite suspension segmented control inside [TaskSuspendedFields].
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
    try {
      final result = await ref
          .read(boardActionsProvider.notifier)
          .resumeTask(widget.task.id, locale: Localizations.localeOf(context));
      if (!mounted) {
        return;
      }
      switch (result) {
        case ActionSucceeded():
          break;
        case ActionValidationFailed(:final message):
        case ActionPersistFailed(:final message):
          setState(() => _submitError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
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
    try {
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
          break;
        case ActionValidationFailed(:final message, :final fieldErrors):
          setState(() {
            _untilError = fieldErrors['suspended'];
            _noteError = fieldErrors['suspendedNote'];
            _submitError = (_untilError == null && _noteError == null)
                ? message
                : null;
          });
        case ActionPersistFailed(:final message):
          setState(() => _submitError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Dispatches async resume from synchronous callbacks.
  void _triggerResume() => unawaited(_handleResume());

  /// Dispatches async suspension save from synchronous callbacks.
  void _triggerSave() => unawaited(_handleSave());
}
