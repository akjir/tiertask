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
import '../../models/tdf_sync_metadata.dart';
import '../../models/webdav_config.dart';
import '../../providers/board_actions_provider.dart';
import '../../providers/board_providers.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../components/ui_ordered_item_list.dart';
import '../components/ui_searchable_picker.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_pill.dart';
import '../primitives/ui_toggle_row.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import '../widgets/entity_card_chrome.dart';
import '../widgets/entity_date_time_fields.dart';

/// Controller-backed mutable draft row for inline and draft subtask editors.
class EditableSubtaskRow {
  /// Creates an [EditableSubtaskRow].
  EditableSubtaskRow({
    required this.rowId,
    required String initialTitle,
    required this.isCompleted,
  }) : controller = TextEditingController(text: initialTitle);

  /// Owned text controller for this subtask step.
  final TextEditingController controller;

  /// Whether this subtask step is marked completed.
  bool isCompleted;

  /// Monotonically unique stable key identifier for list reordering.
  final int rowId;

  /// Disposes [controller].
  void dispose() => controller.dispose();
}

/// Always-visible live-interactive History Journal section on expanded Task cards (`U-CARD-004`, `U-COMP-006`).
class TaskHistorySection extends ConsumerStatefulWidget {
  /// Creates a [TaskHistorySection].
  const TaskHistorySection({
    super.key,
    required this.task,
    required this.configuration,
    required this.currentLocalDateTimeHint,
  });

  /// Active workspace configuration supplying local timezone formatting.
  final WebDavConfig configuration;

  /// Current workspace local wall-clock timestamp (`YYYY-MM-DD HH:MM`) seeding optional timestamp overrides.
  final String currentLocalDateTimeHint;

  /// Domain task item whose history journal is displayed and mutated.
  final TaskItem task;

  @override
  ConsumerState<TaskHistorySection> createState() => _TaskHistorySectionState();
}

/// Pure searchable prerequisite candidate picker body shared by live task cards and [TaskDraftCard].
class TaskPrerequisitesPickerBody extends StatelessWidget {
  /// Creates a [TaskPrerequisitesPickerBody].
  const TaskPrerequisitesPickerBody({
    super.key,
    required this.candidates,
    required this.selectedIds,
    required this.isBusy,
    required this.onToggleOption,
    this.showDescription = true,
    this.autoFocusSearch = true,
    this.onCancel,
  });

  /// Whether the search box automatically requests focus when mounted.
  final bool autoFocusSearch;

  /// Candidate open tasks including cycle-blocked markers.
  final List<PrerequisiteCandidate> candidates;

  /// Whether a save mutation is in flight.
  final bool isBusy;

  /// Optional callback closing the prerequisite picker on Escape.
  final VoidCallback? onCancel;

  /// Callback toggling selection of a candidate task identifier.
  final ValueChanged<String> onToggleOption;

  /// Currently selected prerequisite task identifiers.
  final Set<String> selectedIds;

  /// Whether the explanatory description line renders above the picker.
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final picker = UiSearchablePicker<String>(
      options: _pickerOptions(localizations),
      selectedIds: selectedIds,
      autoFocusSearch: autoFocusSearch,
      searchMaxLength: maxTdfTextLength,
      searchPlaceholder: localizations.blockedBySearchHint,
      searchClearTooltip: localizations.tooltipClearSearch,
      emptyText: localizations.blockedBySearchNoResults,
      onToggleOption: _handleToggleOption,
      onRequestClose: onCancel,
    );
    if (!showDescription) {
      return picker;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          localizations.taskBlockedBySectionDescription,
          style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
        ),
        SizedBox(height: tokens.spacing.space2),
        picker,
      ],
    );
  }

  /// Forwards picker option toggles when no mutation is in flight.
  void _handleToggleOption(UiPickerOption<String> option) {
    if (!isBusy) {
      onToggleOption(option.value);
    }
  }

  /// Maps prerequisite candidates into [UiPickerOption] entries.
  List<UiPickerOption<String>> _pickerOptions(AppLocalizations localizations) {
    return <UiPickerOption<String>>[
      for (final candidate in candidates)
        UiPickerOption<String>(
          id: candidate.id,
          value: candidate.id,
          label: candidate.title,
          enabled: !candidate.wouldCreateCycle,
          disabledHint: candidate.wouldCreateCycle
              ? localizations.prerequisiteCyclePreventedHint
              : null,
        ),
    ];
  }
}

/// Read-only and inline-editable Prerequisites section with cycle prevention (`U-COMP-005`).
class TaskPrerequisitesSection extends ConsumerStatefulWidget {
  /// Creates a [TaskPrerequisitesSection].
  const TaskPrerequisitesSection({
    super.key,
    required this.task,
    required this.tasksById,
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

  /// Domain task item whose prerequisites are displayed and edited.
  final TaskItem task;

  /// Lookup map of all workspace tasks by identifier for resolving prerequisite titles and status.
  final Map<String, TaskItem> tasksById;

  @override
  ConsumerState<TaskPrerequisitesSection> createState() =>
      _TaskPrerequisitesSectionState();
}

/// Compact accessible checkbox button used inside inline subtask edit rows (no Material Switch).
class TaskSubtaskCheckBoxButton extends StatefulWidget {
  /// Creates a [TaskSubtaskCheckBoxButton].
  const TaskSubtaskCheckBoxButton({
    super.key,
    required this.checked,
    required this.enabled,
    required this.semanticLabel,
    required this.onToggle,
  });

  /// Whether this subtask step is checked.
  final bool checked;

  /// Whether interaction is enabled.
  final bool enabled;

  /// Callback toggling checked state.
  final VoidCallback onToggle;

  /// Accessible description of this subtask step.
  final String semanticLabel;

  @override
  State<TaskSubtaskCheckBoxButton> createState() =>
      _TaskSubtaskCheckBoxButtonState();
}

/// Pure ordered subtasks list, inline add bar, and auto-finish toggle shared by live and draft task editors.
class TaskSubtasksEditorBody extends StatelessWidget {
  /// Creates a [TaskSubtasksEditorBody].
  const TaskSubtasksEditorBody({
    super.key,
    required this.rows,
    required this.newStepController,
    required this.newStepFocusNode,
    required this.autoFinish,
    required this.isBusy,
    required this.onReorder,
    required this.onToggleRowDone,
    required this.onDeleteRow,
    required this.onAddRow,
    required this.onAutoFinishChanged,
    required this.itemKeyPrefix,
    required this.addInputKey,
    this.addButtonKey,
    this.autoFinishKey,
    this.autofocusAddInput = false,
  });

  /// Optional stable key placed on the Add button.
  final Key? addButtonKey;

  /// Stable key placed on the new-subtask input field.
  final Key addInputKey;

  /// Auto-finish toggle state.
  final bool autoFinish;

  /// Optional stable key placed on the auto-finish toggle row.
  final Key? autoFinishKey;

  /// Whether the new-subtask input requests focus automatically when mounted.
  final bool autofocusAddInput;

  /// Whether a save or commit mutation is in flight.
  final bool isBusy;

  /// Deterministic prefix applied to each ordered subtask row [ValueKey].
  final String itemKeyPrefix;

  /// Controller for the bottom new-subtask input.
  final TextEditingController newStepController;

  /// Focus node for the bottom new-subtask input.
  final FocusNode newStepFocusNode;

  /// Callback adding the typed subtask and refocusing the input.
  final VoidCallback onAddRow;

  /// Callback updating [autoFinish].
  final ValueChanged<bool> onAutoFinishChanged;

  /// Callback deleting a subtask row.
  final UiOrderedItemActionCallback<EditableSubtaskRow> onDeleteRow;

  /// Callback reordering subtask rows.
  final UiOrderedItemReorderCallback onReorder;

  /// Callback toggling completion of a subtask row.
  final ValueChanged<int> onToggleRowDone;

  /// Editable subtask rows.
  final List<EditableSubtaskRow> rows;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiOrderedItemList<EditableSubtaskRow>(
      items: rows,
      itemKey: (row, index) =>
          ValueKey<String>('${itemKeyPrefix}_${row.rowId}'),
      onReorder: isBusy ? null : onReorder,
      onDelete: isBusy ? null : onDeleteRow,
      deleteTooltip: localizations.tooltipRemoveSubtask,
      itemBuilder: (context, row, index, isEditing) => _SubtaskEditRow(
        row: row,
        isBusy: isBusy,
        onToggleDone: () => onToggleRowDone(index),
      ),
      addBar: _SubtaskAddBar(
        inputKey: addInputKey,
        buttonKey: addButtonKey,
        controller: newStepController,
        focusNode: newStepFocusNode,
        autofocus: autofocusAddInput,
        isBusy: isBusy,
        onAddRow: onAddRow,
      ),
      footer: UiToggleRow(
        key: autoFinishKey,
        label: localizations.subtasksAutoFinishLabel,
        description: localizations.tooltipTaskEditorAutoFinish,
        value: autoFinish,
        isDense: true,
        enabled: !isBusy,
        onChanged: onAutoFinishChanged,
      ),
    );
  }
}

/// Read-only live-checkbox and inline-editable Subtasks section (`U-CARD-002`..`004`, `U-COMP-006`).
class TaskSubtasksSection extends ConsumerStatefulWidget {
  /// Creates a [TaskSubtasksSection].
  const TaskSubtasksSection({
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

  /// Domain task item whose subtasks are displayed and edited.
  final TaskItem task;

  @override
  ConsumerState<TaskSubtasksSection> createState() =>
      _TaskSubtasksSectionState();
}

/// Bottom live add bar inside [TaskHistorySection] with optional clock-toggled timestamp override.
class _HistoryAddBar extends StatelessWidget {
  /// Creates a [_HistoryAddBar].
  const _HistoryAddBar({
    required this.taskId,
    required this.textController,
    required this.timestampController,
    required this.showTimestamp,
    required this.currentLocalDateTimeHint,
    required this.errorText,
    required this.isBusy,
    required this.onChanged,
    required this.onToggleTimestamp,
    required this.onAdd,
  });

  /// Current workspace local timestamp seeding the picker fallback.
  final String currentLocalDateTimeHint;

  /// Optional inline validation or duplicate error message.
  final String? errorText;

  /// Whether a history mutation is currently in flight.
  final bool isBusy;

  /// Callback submitting a new history entry.
  final VoidCallback onAdd;

  /// Callback clearing errors when text changes.
  final ValueChanged<String> onChanged;

  /// Callback toggling the optional timestamp override field.
  final VoidCallback onToggleTimestamp;

  /// Whether the optional timestamp override field is visible.
  final bool showTimestamp;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  /// Controller for the single-line history entry text.
  final TextEditingController textController;

  /// Controller for the optional local timestamp override.
  final TextEditingController timestampController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _HistoryAddInputRow(
          taskId: taskId,
          textController: textController,
          showTimestamp: showTimestamp,
          isBusy: isBusy,
          onChanged: onChanged,
          onToggleTimestamp: onToggleTimestamp,
          onAdd: onAdd,
        ),
        if (showTimestamp) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          EntityHybridDateTimeField(
            key: ValueKey<String>('history_add_timestamp_$taskId'),
            controller: timestampController,
            label: localizations.historyTimestampLabel,
            fallbackLocalDateTime: currentLocalDateTimeHint,
            enabled: !isBusy,
            onChanged: onChanged,
            onSubmitted: (_) => onAdd(),
          ),
        ],
        if (errorText case final error?) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          EntityInlineErrorText(message: error),
        ],
      ],
    );
  }
}

/// Primary input and action button row inside [_HistoryAddBar].
class _HistoryAddInputRow extends StatelessWidget {
  /// Creates a [_HistoryAddInputRow].
  const _HistoryAddInputRow({
    required this.taskId,
    required this.textController,
    required this.showTimestamp,
    required this.isBusy,
    required this.onChanged,
    required this.onToggleTimestamp,
    required this.onAdd,
  });

  /// Whether a history mutation is currently in flight.
  final bool isBusy;

  /// Callback submitting a new history entry.
  final VoidCallback onAdd;

  /// Callback clearing errors when text changes.
  final ValueChanged<String> onChanged;

  /// Callback toggling the optional timestamp override field.
  final VoidCallback onToggleTimestamp;

  /// Whether the optional timestamp override field is visible.
  final bool showTimestamp;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  /// Controller for the single-line history entry text.
  final TextEditingController textController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: _HistoryAddTextField(
            taskId: taskId,
            controller: textController,
            isBusy: isBusy,
            onChanged: onChanged,
            onSubmitted: onAdd,
          ),
        ),
        const SizedBox(width: 6.0),
        UiButton(
          key: ValueKey<String>('history_timestamp_toggle_$taskId'),
          leadingIcon: Icons.schedule_rounded,
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.compact,
          isActive: showTimestamp,
          tooltip: localizations.historyTimestampToggleTooltip,
          onPressed: isBusy ? null : onToggleTimestamp,
        ),
        const SizedBox(width: 6.0),
        UiButton(
          key: ValueKey<String>('history_add_button_$taskId'),
          label: localizations.actionAdd,
          density: UiButtonDensity.compact,
          tooltip: localizations.tooltipAddHistoryEntry,
          onPressed: isBusy ? null : onAdd,
        ),
      ],
    );
  }
}

/// Single-line text field for composing a new history entry in [_HistoryAddInputRow].
class _HistoryAddTextField extends StatelessWidget {
  /// Creates a [_HistoryAddTextField].
  const _HistoryAddTextField({
    required this.taskId,
    required this.controller,
    required this.isBusy,
    required this.onChanged,
    required this.onSubmitted,
  });

  /// Controller for the single-line history entry text.
  final TextEditingController controller;

  /// Whether a history mutation is currently in flight.
  final bool isBusy;

  /// Callback clearing errors when text changes.
  final ValueChanged<String> onChanged;

  /// Callback submitting the composed history entry.
  final VoidCallback onSubmitted;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiField(
      key: ValueKey<String>('history_add_text_$taskId'),
      controller: controller,
      hintText: localizations.historyEntryTextHint,
      maxLength: maxTdfTextLength,
      enabled: !isBusy,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

/// Save and cancel action buttons inside [_HistoryEditRow].
class _HistoryEditActions extends StatelessWidget {
  /// Creates a [_HistoryEditActions].
  const _HistoryEditActions({
    required this.taskId,
    required this.index,
    required this.isBusy,
    required this.onSave,
    required this.onCancel,
  });

  /// Row index in the history list.
  final int index;

  /// Whether a history mutation is in flight.
  final bool isBusy;

  /// Callback cancelling the active row edit.
  final VoidCallback onCancel;

  /// Callback persisting the edited history entry.
  final VoidCallback onSave;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        UiButton(
          key: ValueKey<String>('history_edit_save_${taskId}_$index'),
          label: localizations.actionSave,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          tooltip: localizations.tooltipSaveHistoryEntry,
          onPressed: isBusy ? null : onSave,
        ),
        UiButton(
          key: ValueKey<String>('history_edit_cancel_${taskId}_$index'),
          label: localizations.actionCancel,
          density: UiButtonDensity.compact,
          tooltip: localizations.tooltipCancelEditHistoryEntry,
          onPressed: isBusy ? null : onCancel,
        ),
      ],
    );
  }
}

/// Inline row editor inside [TaskHistorySection] for updating a history entry's timestamp and text.
class _HistoryEditRow extends StatelessWidget {
  /// Creates a [_HistoryEditRow].
  const _HistoryEditRow({
    required this.taskId,
    required this.index,
    required this.fallbackLocalTimestamp,
    required this.textController,
    required this.timestampController,
    required this.isBusy,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
  });

  /// Persisted local timestamp seeding pickers if input is cleared.
  final String fallbackLocalTimestamp;

  /// Row index in the history list.
  final int index;

  /// Whether a history mutation is in flight.
  final bool isBusy;

  /// Callback cancelling the active row edit.
  final VoidCallback onCancel;

  /// Callback clearing errors when text changes.
  final ValueChanged<String> onChanged;

  /// Callback persisting the edited history entry.
  final VoidCallback onSave;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  /// Controller for the edited history text.
  final TextEditingController textController;

  /// Controller for the edited local timestamp.
  final TextEditingController timestampController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final spacing = UiThemeTokens.of(context).spacing.space2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        EntityHybridDateTimeField(
          key: ValueKey<String>('history_edit_timestamp_${taskId}_$index'),
          controller: timestampController,
          label: localizations.historyTimestampLabel,
          fallbackLocalDateTime: fallbackLocalTimestamp,
          enabled: !isBusy,
          onChanged: onChanged,
          onSubmitted: (_) => onSave(),
        ),
        SizedBox(height: spacing),
        _HistoryEditTextField(
          taskId: taskId,
          index: index,
          controller: textController,
          isBusy: isBusy,
          onChanged: onChanged,
          onSave: onSave,
        ),
        SizedBox(height: spacing),
        _HistoryEditActions(
          taskId: taskId,
          index: index,
          isBusy: isBusy,
          onSave: onSave,
          onCancel: onCancel,
        ),
      ],
    );
  }
}

/// Single-line text field for editing an existing history entry in [_HistoryEditRow].
class _HistoryEditTextField extends StatelessWidget {
  /// Creates a [_HistoryEditTextField].
  const _HistoryEditTextField({
    required this.taskId,
    required this.index,
    required this.controller,
    required this.isBusy,
    required this.onChanged,
    required this.onSave,
  });

  /// Controller for the edited history text.
  final TextEditingController controller;

  /// Row index in the history list.
  final int index;

  /// Whether a history mutation is in flight.
  final bool isBusy;

  /// Callback clearing errors when text changes.
  final ValueChanged<String> onChanged;

  /// Callback persisting the edited history entry.
  final VoidCallback onSave;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiField(
      key: ValueKey<String>('history_edit_text_${taskId}_$index'),
      controller: controller,
      maxLength: maxTdfTextLength,
      autofocus: true,
      enabled: !isBusy,
      semanticLabel: localizations.historyEntryTextLabel,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: (_) => onSave(),
    );
  }
}

/// Read-only display row for a single [TaskHistoryEntry].
class _HistoryReadRow extends StatelessWidget {
  /// Creates a [_HistoryReadRow].
  const _HistoryReadRow({
    required this.formattedLocalTimestamp,
    required this.text,
  });

  /// Entry timestamp formatted in the active workspace timezone.
  final String formattedLocalTimestamp;

  /// Single-line history entry description text.
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          formattedLocalTimestamp,
          style: UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: colors.muted),
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          text,
          style: tokens.typography.control.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// Read-only prerequisite status row inside [_TaskPrerequisitesReadCard].
class _PrerequisiteReadRow extends StatelessWidget {
  /// Creates a [_PrerequisiteReadRow].
  const _PrerequisiteReadRow({required this.title, required this.isSatisfied});

  /// Whether the prerequisite completion threshold is currently met.
  final bool isSatisfied;

  /// Resolved prerequisite task title or fallback task identifier.
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(
              isSatisfied
                  ? Icons.check_circle_outline_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: tokens.spacing.iconSm,
              color: isSatisfied ? colors.success : colors.warning,
            ),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              title,
              style: tokens.typography.control.copyWith(
                color: isSatisfied ? colors.muted : colors.ink,
                decoration: isSatisfied ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom new-step input and add button row inside [TaskSubtasksEditorBody].
class _SubtaskAddBar extends StatelessWidget {
  /// Creates a [_SubtaskAddBar].
  const _SubtaskAddBar({
    required this.inputKey,
    required this.buttonKey,
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.isBusy,
    required this.onAddRow,
  });

  /// Whether the add input requests focus automatically.
  final bool autofocus;

  /// Optional deterministic key for the Add button.
  final Key? buttonKey;

  /// Controller for the new-subtask text input.
  final TextEditingController controller;

  /// Focus node for the new-subtask text input.
  final FocusNode focusNode;

  /// Deterministic key for the new-subtask text input.
  final Key inputKey;

  /// Whether a subtask save mutation is in flight.
  final bool isBusy;

  /// Callback appending the typed subtask row.
  final VoidCallback onAddRow;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: UiField(
            key: inputKey,
            controller: controller,
            focusNode: focusNode,
            hintText: localizations.subtaskInputHint,
            maxLength: maxTdfTextLength,
            autofocus: autofocus,
            enabled: !isBusy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onAddRow(),
          ),
        ),
        const SizedBox(width: 8.0),
        UiButton(
          key: buttonKey,
          label: localizations.actionAdd,
          density: UiButtonDensity.compact,
          tooltip: localizations.tooltipAddSubtask,
          onPressed: isBusy ? null : onAddRow,
        ),
      ],
    );
  }
}

/// Visual box and optional focus ring rendered inside [TaskSubtaskCheckBoxButton].
class _SubtaskCheckBoxVisual extends StatelessWidget {
  /// Creates a [_SubtaskCheckBoxVisual].
  const _SubtaskCheckBoxVisual({
    required this.checked,
    required this.enabled,
    required this.showFocusRing,
  });

  /// Whether this subtask step is checked.
  final bool checked;

  /// Whether interaction is enabled.
  final bool enabled;

  /// Whether keyboard focus highlight is active.
  final bool showFocusRing;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final surface = UiSurfaceScope.of(context);
    final uncheckedFill = surface == UiSurfaceLevel.insetWell
        ? colors.panel
        : colors.bg;
    final checkbox = AnimatedContainer(
      duration: tokens.focus.hoverDuration,
      width: 16.0,
      height: 16.0,
      decoration: BoxDecoration(
        color: checked ? colors.accent : uncheckedFill,
        borderRadius: BorderRadius.circular(tokens.radii.dotLg),
        border: Border.all(
          color: checked ? colors.accent : colors.line,
          width: tokens.radii.borderWidth,
        ),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: 12.0, color: colors.onAccent)
          : null,
    );
    if (!showFocusRing || !enabled) {
      return checkbox;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radii.sm),
        border: Border.all(color: colors.accent, width: tokens.focus.ringWidth),
      ),
      child: Padding(padding: const EdgeInsets.all(2.0), child: checkbox),
    );
  }
}

/// Inline editable row with completion checkbox and text input inside [_TaskSubtasksEditList].
class _SubtaskEditRow extends StatelessWidget {
  /// Creates a [_SubtaskEditRow].
  const _SubtaskEditRow({
    required this.row,
    required this.isBusy,
    required this.onToggleDone,
  });

  /// Whether a subtask save mutation is in flight.
  final bool isBusy;

  /// Callback toggling completion of this editable row.
  final VoidCallback onToggleDone;

  /// Mutable controller-backed subtask draft row.
  final EditableSubtaskRow row;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Row(
      children: <Widget>[
        TaskSubtaskCheckBoxButton(
          checked: row.isCompleted,
          enabled: !isBusy,
          semanticLabel: row.controller.text,
          onToggle: onToggleDone,
        ),
        const SizedBox(width: 6.0),
        Expanded(
          child: UiField(
            controller: row.controller,
            maxLength: maxTdfTextLength,
            enabled: !isBusy,
            semanticLabel: localizations.subtasksSectionTitle,
          ),
        ),
      ],
    );
  }
}

/// Horizontal `6px` accent progress bar displayed inside read-only [TaskSubtasksSection].
class _SubtaskProgressBar extends StatelessWidget {
  /// Creates a [_SubtaskProgressBar].
  const _SubtaskProgressBar({required this.ratio});

  /// Normalized completion ratio (`0.0..1.0`).
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radii.pill),
      child: Container(
        height: 6.0,
        color: colors.line,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: ratio.clamp(0.0, 1.0),
          child: ColoredBox(color: colors.accent),
        ),
      ),
    );
  }
}

/// Inset card frame and count header for [TaskHistorySection].
class _TaskHistoryCardShell extends StatelessWidget {
  /// Creates a [_TaskHistoryCardShell].
  const _TaskHistoryCardShell({required this.task, required this.child});

  /// Body widget rendered inside the inset history card.
  final Widget child;

  /// Domain task item whose history journal is displayed.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: ValueKey<String>('task_history_section_${task.id}'),
      headerIcon: Icons.history_rounded,
      headerTitle: localizations.historySectionTitle,
      headerBadge: UiPill(
        label: '${task.history.length} / $maxTdfHistoryPerTask',
        variant: UiPillVariant.count,
      ),
      child: child,
    );
  }
}

/// Ordered live history list switching rows between [_HistoryReadRow] and [_HistoryEditRow].
class _TaskHistoryOrderedList extends StatelessWidget {
  /// Creates a [_TaskHistoryOrderedList].
  const _TaskHistoryOrderedList({
    required this.task,
    required this.configuration,
    required this.editingIndex,
    required this.editTextController,
    required this.editTimestampController,
    required this.isBusy,
    required this.onStartEdit,
    required this.onDeleteEntry,
    required this.onInputChanged,
    required this.onSaveEdit,
    required this.onCancelEdit,
    required this.addBar,
  });

  /// Bottom live add bar widget.
  final Widget addBar;

  /// Active workspace configuration supplying local timezone formatting.
  final WebDavConfig configuration;

  /// Controller for the edited history text.
  final TextEditingController editTextController;

  /// Controller for the edited local timestamp.
  final TextEditingController editTimestampController;

  /// Index of the row currently open for inline editing, if any.
  final int? editingIndex;

  /// Whether a history mutation is in flight.
  final bool isBusy;

  /// Callback cancelling the active row edit.
  final VoidCallback onCancelEdit;

  /// Callback deleting a history entry row.
  final UiOrderedItemActionCallback<TaskHistoryEntry> onDeleteEntry;

  /// Callback clearing errors when text changes.
  final ValueChanged<String> onInputChanged;

  /// Callback persisting the edited history entry.
  final VoidCallback onSaveEdit;

  /// Callback starting inline editing for a history entry row.
  final UiOrderedItemActionCallback<TaskHistoryEntry> onStartEdit;

  /// Domain task item whose history journal is rendered.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiOrderedItemList<TaskHistoryEntry>(
      items: task.history,
      editingIndex: editingIndex,
      emptyText: localizations.historyEmptyHint,
      itemKey: (entry, index) => ValueKey<String>(
        'history_entry_${task.id}_${index}_${entry.timestampUtc.toIso8601String()}',
      ),
      onEdit: isBusy ? null : onStartEdit,
      editTooltip: localizations.tooltipEditHistoryEntry,
      onDelete: isBusy ? null : onDeleteEntry,
      deleteTooltip: localizations.tooltipDeleteHistoryEntry,
      itemBuilder: (context, entry, index, isEditing) {
        final formattedTimestamp = TaskScheduleHelper.formatLocalTimestamp(
          entry.timestampUtc,
          configuration,
        );
        return isEditing
            ? _HistoryEditRow(
                taskId: task.id,
                index: index,
                fallbackLocalTimestamp: formattedTimestamp,
                textController: editTextController,
                timestampController: editTimestampController,
                isBusy: isBusy,
                onChanged: onInputChanged,
                onSave: onSaveEdit,
                onCancel: onCancelEdit,
              )
            : _HistoryReadRow(
                formattedLocalTimestamp: formattedTimestamp,
                text: entry.text,
              );
      },
      addBar: addBar,
    );
  }
}

/// Manages live history add, inline row edit, timestamp override, and delete state for [TaskHistorySection].
class _TaskHistorySectionState extends ConsumerState<TaskHistorySection> {
  late final TextEditingController _addTextController;
  late final TextEditingController _addTimestampController;
  late final TextEditingController _editTextController;
  late final TextEditingController _editTimestampController;

  int? _editingIndex;
  String? _editingOldText;
  String? _editingOldTimestampUtcIso;
  String? _errorText;
  bool _isSubmitting = false;
  bool _showAddTimestamp = false;

  @override
  void initState() {
    super.initState();
    _addTextController = TextEditingController();
    _addTimestampController = TextEditingController();
    _editTextController = TextEditingController();
    _editTimestampController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant TaskHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _editingIndex = null;
      _editingOldText = null;
      _editingOldTimestampUtcIso = null;
      _showAddTimestamp = false;
      _errorText = null;
      _isSubmitting = false;
      _addTextController.clear();
      _addTimestampController.clear();
      _editTextController.clear();
      _editTimestampController.clear();
    } else if (_editingIndex case final activeIndex?
        when activeIndex >= widget.task.history.length) {
      _editingIndex = null;
      _editingOldText = null;
      _editingOldTimestampUtcIso = null;
    }
  }

  @override
  void dispose() {
    _addTextController.dispose();
    _addTimestampController.dispose();
    _editTextController.dispose();
    _editTimestampController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isControllerBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;

    return _TaskHistoryCardShell(
      task: widget.task,
      child: _TaskHistoryOrderedList(
        task: widget.task,
        configuration: widget.configuration,
        editingIndex: _editingIndex,
        editTextController: _editTextController,
        editTimestampController: _editTimestampController,
        isBusy: isBusy,
        onStartEdit: _handleStartEdit,
        onDeleteEntry: _triggerDeleteEntry,
        onInputChanged: _handleInputChanged,
        onSaveEdit: _triggerSaveEdit,
        onCancelEdit: _handleCancelEdit,
        addBar: _HistoryAddBar(
          taskId: widget.task.id,
          textController: _addTextController,
          timestampController: _addTimestampController,
          showTimestamp: _showAddTimestamp,
          currentLocalDateTimeHint: widget.currentLocalDateTimeHint,
          errorText: _errorText,
          isBusy: isBusy,
          onChanged: _handleInputChanged,
          onToggleTimestamp: _handleToggleAddTimestamp,
          onAdd: _triggerAddEntry,
        ),
      ),
    );
  }

  /// Applies [result] from appending a history entry to inline form state.
  void _applyAddResult(ActionResult result) {
    switch (result) {
      case ActionSucceeded():
        setState(() {
          _errorText = null;
          _showAddTimestamp = false;
          _addTextController.clear();
          _addTimestampController.clear();
        });
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() => _errorText = message);
    }
  }

  /// Applies [result] from deleting history entry at [index] to inline edit state.
  void _applyDeleteResult(ActionResult result, int index) {
    switch (result) {
      case ActionSucceeded():
        if (_editingIndex == index) {
          setState(() {
            _editingIndex = null;
            _editingOldText = null;
            _editingOldTimestampUtcIso = null;
          });
        }
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() => _errorText = message);
    }
  }

  /// Applies [result] from updating an existing history entry to inline edit state.
  void _applySaveEditResult(ActionResult result) {
    switch (result) {
      case ActionSucceeded():
        setState(() {
          _editingIndex = null;
          _editingOldText = null;
          _editingOldTimestampUtcIso = null;
          _errorText = null;
        });
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() => _errorText = message);
    }
  }

  /// Appends a new history entry via [BoardActionsNotifier.addHistoryEntry].
  Future<void> _handleAddEntry() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await ref
          .read(boardActionsProvider.notifier)
          .addHistoryEntry(
            widget.task.id,
            rawText: _addTextController.text,
            rawTimestampOverride: _showAddTimestamp
                ? _addTimestampController.text
                : null,
            locale: Localizations.localeOf(context),
          );
      if (!mounted) {
        return;
      }
      _applyAddResult(result);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Exits inline row editing without modifying persisted history.
  void _handleCancelEdit() {
    setState(() {
      _editingIndex = null;
      _editingOldText = null;
      _editingOldTimestampUtcIso = null;
      _errorText = null;
    });
  }

  /// Removes [entry] via [BoardActionsNotifier.deleteHistoryEntry].
  Future<void> _handleDeleteEntry(TaskHistoryEntry entry, int index) async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await ref
          .read(boardActionsProvider.notifier)
          .deleteHistoryEntry(
            widget.task.id,
            timestampUtcIso: entry.timestampUtc.toIso8601String(),
            text: entry.text,
            locale: Localizations.localeOf(context),
          );
      if (!mounted) {
        return;
      }
      _applyDeleteResult(result, index);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Clears transient inline history error text when typing resumes.
  void _handleInputChanged(String _) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  /// Commits the inline edit targeting [_editingOldTimestampUtcIso] and [_editingOldText].
  Future<void> _handleSaveEdit() async {
    final oldTimestampUtcIso = _editingOldTimestampUtcIso;
    final oldText = _editingOldText;
    if (_isSubmitting || oldTimestampUtcIso == null || oldText == null) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await ref
          .read(boardActionsProvider.notifier)
          .updateHistoryEntry(
            widget.task.id,
            oldTimestampUtcIso: oldTimestampUtcIso,
            oldText: oldText,
            rawNewText: _editTextController.text,
            rawNewTimestamp: _editTimestampController.text,
            locale: Localizations.localeOf(context),
          );
      if (!mounted) {
        return;
      }
      _applySaveEditResult(result);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Opens inline editing for [entry] at [index].
  void _handleStartEdit(TaskHistoryEntry entry, int index) {
    setState(() {
      _editingIndex = index;
      _editingOldTimestampUtcIso = entry.timestampUtc.toIso8601String();
      _editingOldText = entry.text;
      _editTextController.text = entry.text;
      _editTimestampController.text = TaskScheduleHelper.formatLocalTimestamp(
        entry.timestampUtc,
        widget.configuration,
      );
      _errorText = null;
    });
  }

  /// Toggles the optional local timestamp override input on the bottom add bar.
  void _handleToggleAddTimestamp() {
    setState(() {
      _showAddTimestamp = !_showAddTimestamp;
      if (_showAddTimestamp) {
        if (_addTimestampController.text.trim().isEmpty) {
          _addTimestampController.text = widget.currentLocalDateTimeHint;
        }
      } else {
        _addTimestampController.clear();
      }
      _errorText = null;
    });
  }

  /// Dispatches async history add from synchronous UI callbacks.
  void _triggerAddEntry() => unawaited(_handleAddEntry());

  /// Dispatches async history delete from synchronous list callbacks.
  void _triggerDeleteEntry(TaskHistoryEntry entry, int index) {
    unawaited(_handleDeleteEntry(entry, index));
  }

  /// Dispatches async history row save from synchronous UI callbacks.
  void _triggerSaveEdit() => unawaited(_handleSaveEdit());
}

/// Inline prerequisite picker card for [TaskPrerequisitesSection].
class _TaskPrerequisitesEditCard extends StatelessWidget {
  /// Creates a [_TaskPrerequisitesEditCard].
  const _TaskPrerequisitesEditCard({
    required this.candidates,
    required this.selectedIds,
    required this.hasExistingPrerequisites,
    required this.errorText,
    required this.isBusy,
    required this.onToggleOption,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
  });

  /// Candidate open tasks including cycle-blocked markers.
  final List<PrerequisiteCandidate> candidates;

  /// Optional validation or persistence error text.
  final String? errorText;

  /// Whether the task currently has persisted prerequisites (shows Clear button).
  final bool hasExistingPrerequisites;

  /// Whether a save mutation is in flight.
  final bool isBusy;

  /// Callback cancelling inline edit.
  final VoidCallback onCancel;

  /// Callback clearing all prerequisites.
  final VoidCallback onClear;

  /// Callback saving selected prerequisites.
  final VoidCallback onSave;

  /// Callback toggling selection of a candidate task identifier.
  final ValueChanged<String> onToggleOption;

  /// Currently selected prerequisite task identifiers.
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('task_prerequisites_edit_card'),
      isEditing: true,
      headerIcon: Icons.lock_outline_rounded,
      headerTitle: localizations.taskBlockedBySectionTitle,
      headerBadge: UiPill(
        label: '${selectedIds.length}',
        variant: UiPillVariant.count,
      ),
      footer: EntityInlineEditorFooter(
        errorText: errorText,
        clearLabel: hasExistingPrerequisites
            ? localizations.inlineClearAction
            : null,
        onClear: hasExistingPrerequisites ? onClear : null,
        onCancel: onCancel,
        onSave: onSave,
        isBusy: isBusy,
      ),
      child: TaskPrerequisitesPickerBody(
        candidates: candidates,
        selectedIds: selectedIds,
        isBusy: isBusy,
        onToggleOption: onToggleOption,
        onCancel: onCancel,
      ),
    );
  }
}

/// Read-only display card for [TaskPrerequisitesSection].
class _TaskPrerequisitesReadCard extends StatelessWidget {
  /// Creates a [_TaskPrerequisitesReadCard].
  const _TaskPrerequisitesReadCard({
    required this.task,
    required this.tasksById,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  /// Domain task item whose dependencies are displayed.
  final TaskItem task;

  /// Lookup map of all workspace tasks by identifier.
  final Map<String, TaskItem> tasksById;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final rows = _resolveRows();
    final satisfiedCount = _countSatisfied(rows);

    return UiCard.inset(
      key: ValueKey<String>('task_prerequisites_read_${task.id}'),
      headerIcon: Icons.lock_outline_rounded,
      headerTitle: localizations.taskBlockedBySectionTitle,
      headerBadge: UiPill(
        label: localizations.taskInfoBlockedByProgress(
          '$satisfiedCount',
          '${rows.length}',
        ),
        variant: UiPillVariant.count,
      ),
      headerTrailing: task.isCompleted
          ? null
          : _TaskSectionEditButton(
              buttonKey: ValueKey<String>(
                'task_prerequisites_edit_button_${task.id}',
              ),
              isBusy: isBusy,
              onPressed: onStartEdit,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final row in rows)
            _PrerequisiteReadRow(
              title: row.title,
              isSatisfied: row.isSatisfied,
            ),
        ],
      ),
    );
  }

  /// Counts how many resolved prerequisite rows are currently satisfied.
  int _countSatisfied(List<({String title, bool isSatisfied})> rows) {
    var count = 0;
    for (final row in rows) {
      if (row.isSatisfied) {
        count++;
      }
    }
    return count;
  }

  /// Resolves a single dependency's display title and satisfaction against [tasksById].
  ({String title, bool isSatisfied}) _resolveDependency(
    TdfTaskDependency dependency,
  ) {
    final target = tasksById[dependency.taskId];
    return (
      title: target?.title ?? dependency.taskId,
      isSatisfied:
          target != null && target.completions >= dependency.requiredCompletion,
    );
  }

  /// Resolves display title and completion satisfaction for every dependency on [task].
  List<({String title, bool isSatisfied})> _resolveRows() {
    return <({String title, bool isSatisfied})>[
      for (final dependency in task.dependencies)
        _resolveDependency(dependency),
    ];
  }
}

/// Manages selected prerequisite identifiers and submission for [TaskPrerequisitesSection].
class _TaskPrerequisitesSectionState
    extends ConsumerState<TaskPrerequisitesSection> {
  String? _errorText;
  bool _isSubmitting = false;
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = <String>{
      for (final dependency in widget.task.dependencies) dependency.taskId,
    };
  }

  @override
  void didUpdateWidget(covariant TaskPrerequisitesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _selectedIds = <String>{
        for (final dependency in widget.task.dependencies) dependency.taskId,
      };
      _errorText = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _errorText = null;
      _isSubmitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isControllerBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;

    if (!widget.isEditing || widget.task.isCompleted) {
      return widget.task.dependencies.isEmpty
          ? const SizedBox.shrink()
          : _TaskPrerequisitesReadCard(
              task: widget.task,
              tasksById: widget.tasksById,
              isBusy: isBusy,
              onStartEdit: widget.onStartEdit,
            );
    }

    final candidates = ref.watch(
      taskPrerequisiteCandidatesProvider(widget.task.id),
    );
    return _TaskPrerequisitesEditCard(
      candidates: candidates,
      selectedIds: _selectedIds,
      hasExistingPrerequisites: widget.task.dependencies.isNotEmpty,
      errorText: _errorText,
      isBusy: isBusy,
      onToggleOption: _handleToggleOption,
      onClear: _triggerClear,
      onCancel: widget.onCancelEdit,
      onSave: _triggerSave,
    );
  }

  /// Toggles candidate [taskId] inside [_selectedIds].
  void _handleToggleOption(String taskId) {
    final next = Set<String>.of(_selectedIds);
    if (!next.add(taskId)) {
      next.remove(taskId);
    }
    setState(() {
      _selectedIds = next;
      _errorText = null;
    });
  }

  /// Persists [prerequisiteIds] via [BoardActionsNotifier.savePrerequisites].
  Future<void> _submitPrerequisites(List<String> prerequisiteIds) async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await ref
          .read(boardActionsProvider.notifier)
          .savePrerequisites(
            widget.task.id,
            prerequisiteIds,
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
          setState(() => _errorText = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Dispatches clearing all prerequisites.
  void _triggerClear() => unawaited(_submitPrerequisites(const <String>[]));

  /// Dispatches saving selected prerequisites.
  void _triggerSave() =>
      unawaited(_submitPrerequisites(_selectedIds.toList(growable: false)));
}

/// Compact header edit button shared by read-only task detail cards.
class _TaskSectionEditButton extends StatelessWidget {
  /// Creates a [_TaskSectionEditButton].
  const _TaskSectionEditButton({
    required this.buttonKey,
    required this.isBusy,
    required this.onPressed,
  });

  /// Deterministic test and widget key applied to the underlying [UiButton].
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

/// Tracks keyboard focus ring state for [TaskSubtaskCheckBoxButton].
class _TaskSubtaskCheckBoxButtonState extends State<TaskSubtaskCheckBoxButton> {
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: widget.checked,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowFocusHighlight: _handleShowFocusHighlight,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: _handleActivate,
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onToggle : null,
          child: SizedBox(
            width: 30.0,
            height: 30.0,
            child: Center(
              child: _SubtaskCheckBoxVisual(
                checked: widget.checked,
                enabled: widget.enabled,
                showFocusRing: _showFocusRing,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Toggles the checkbox on keyboard activation when enabled.
  Object? _handleActivate(ActivateIntent _) {
    if (widget.enabled) {
      widget.onToggle();
    }
    return null;
  }

  /// Synchronizes keyboard focus ring visibility with focus traversal state.
  void _handleShowFocusHighlight(bool focused) {
    if (_showFocusRing != focused) {
      setState(() => _showFocusRing = focused);
    }
  }
}

/// Inline editing card for [TaskSubtasksSection].
class _TaskSubtasksEditCard extends StatelessWidget {
  /// Creates a [_TaskSubtasksEditCard].
  const _TaskSubtasksEditCard({
    required this.taskId,
    required this.rows,
    required this.newStepController,
    required this.newStepFocusNode,
    required this.autoFinish,
    required this.hasExistingSubtasks,
    required this.errorText,
    required this.isBusy,
    required this.onReorder,
    required this.onToggleRowDone,
    required this.onDeleteRow,
    required this.onAddRow,
    required this.onAutoFinishChanged,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
  });

  /// Auto-finish toggle state.
  final bool autoFinish;

  /// Optional inline validation or persistence error text.
  final String? errorText;

  /// Whether persisted subtasks currently exist (shows Clear button).
  final bool hasExistingSubtasks;

  /// Whether a save mutation is in flight.
  final bool isBusy;

  /// Controller for the bottom new-subtask input.
  final TextEditingController newStepController;

  /// Focus node for the bottom new-subtask input.
  final FocusNode newStepFocusNode;

  /// Callback adding the typed subtask and refocusing the input.
  final VoidCallback onAddRow;

  /// Callback updating [autoFinish].
  final ValueChanged<bool> onAutoFinishChanged;

  /// Callback cancelling inline edit.
  final VoidCallback onCancel;

  /// Callback clearing all subtasks.
  final VoidCallback onClear;

  /// Callback deleting a subtask row.
  final UiOrderedItemActionCallback<EditableSubtaskRow> onDeleteRow;

  /// Callback reordering subtask rows.
  final UiOrderedItemReorderCallback onReorder;

  /// Callback saving edited subtasks.
  final VoidCallback onSave;

  /// Callback toggling completion of a subtask row.
  final ValueChanged<int> onToggleRowDone;

  /// Editable subtask rows.
  final List<EditableSubtaskRow> rows;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return _TaskSubtasksEditShell(
      taskId: taskId,
      autoFinish: autoFinish,
      rowCount: rows.length,
      footer: EntityInlineEditorFooter(
        errorText: errorText,
        clearLabel: hasExistingSubtasks
            ? localizations.inlineClearAction
            : null,
        onClear: hasExistingSubtasks ? onClear : null,
        onCancel: onCancel,
        onSave: onSave,
        isBusy: isBusy,
      ),
      child: TaskSubtasksEditorBody(
        rows: rows,
        newStepController: newStepController,
        newStepFocusNode: newStepFocusNode,
        autoFinish: autoFinish,
        isBusy: isBusy,
        itemKeyPrefix: 'subtask_edit_row_$taskId',
        addInputKey: ValueKey<String>('subtask_add_input_$taskId'),
        addButtonKey: ValueKey<String>('subtask_add_button_$taskId'),
        autoFinishKey: ValueKey<String>('subtask_auto_finish_toggle_$taskId'),
        autofocusAddInput: rows.isEmpty,
        onReorder: onReorder,
        onToggleRowDone: onToggleRowDone,
        onDeleteRow: onDeleteRow,
        onAddRow: onAddRow,
        onAutoFinishChanged: onAutoFinishChanged,
      ),
    );
  }
}

/// Inset card frame and count badge header for [_TaskSubtasksEditCard].
class _TaskSubtasksEditShell extends StatelessWidget {
  /// Creates a [_TaskSubtasksEditShell].
  const _TaskSubtasksEditShell({
    required this.taskId,
    required this.autoFinish,
    required this.rowCount,
    required this.footer,
    required this.child,
  });

  /// Auto-finish toggle state selecting the header icon.
  final bool autoFinish;

  /// Body widget rendered inside the inset card.
  final Widget child;

  /// Footer action bar rendered inside the inset card.
  final Widget footer;

  /// Number of editable subtask rows shown in the header count pill.
  final int rowCount;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: ValueKey<String>('task_subtasks_edit_$taskId'),
      isEditing: true,
      headerIcon: autoFinish
          ? Icons.check_box_outlined
          : Icons.checklist_rounded,
      headerTitle: localizations.subtasksSectionTitle,
      headerBadge: UiPill(label: '$rowCount', variant: UiPillVariant.count),
      footer: footer,
      child: child,
    );
  }
}

/// Progress bar, auto-finish note, and live subtask checkboxes inside [_TaskSubtasksReadCard].
class _TaskSubtasksReadBody extends StatelessWidget {
  /// Creates a [_TaskSubtasksReadBody].
  const _TaskSubtasksReadBody({
    required this.task,
    required this.completedCount,
    required this.isBusy,
    required this.onToggleSubtask,
  });

  /// Number of completed subtask steps on [task].
  final int completedCount;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback toggling live subtask completion at step index.
  final ValueChanged<int> onToggleSubtask;

  /// Domain task item whose subtasks are rendered.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final ratio = task.subtasks.isEmpty
        ? 0.0
        : completedCount / task.subtasks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SubtaskProgressBar(ratio: ratio),
        if (task.subtasksAutoFinish) ...<Widget>[
          const SizedBox(height: 6.0),
          Text(
            localizations.taskInfoSubtasksAutoFinishSuffix,
            style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
          ),
        ],
        const SizedBox(height: 6.0),
        for (var i = 0; i < task.subtasks.length; i++)
          UiToggleRow(
            key: ValueKey<String>('task_subtask_toggle_${task.id}_$i'),
            label: task.subtasks[i].title,
            value: task.subtasks[i].isCompleted,
            isDense: true,
            enabled: !task.isCompleted && !isBusy,
            onChanged: task.isCompleted || isBusy
                ? null
                : (_) => onToggleSubtask(i),
          ),
      ],
    );
  }
}

/// Read-only display card with live checkboxes and `6px` progress bar for [TaskSubtasksSection].
class _TaskSubtasksReadCard extends StatelessWidget {
  /// Creates a [_TaskSubtasksReadCard].
  const _TaskSubtasksReadCard({
    required this.task,
    required this.isBusy,
    required this.onStartEdit,
    required this.onToggleSubtask,
  });

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback opening inline subtask edit mode.
  final VoidCallback onStartEdit;

  /// Callback toggling live subtask completion at step index.
  final ValueChanged<int> onToggleSubtask;

  /// Domain task item whose subtasks are rendered.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final completedCount = _countCompletedSubtasks(task.subtasks);

    return UiCard.inset(
      key: ValueKey<String>('task_subtasks_read_${task.id}'),
      headerIcon: task.subtasksAutoFinish
          ? Icons.check_box_outlined
          : Icons.checklist_rounded,
      headerTitle: localizations.subtasksSectionTitle,
      headerBadge: UiPill(
        label: localizations.taskInfoSubtasksProgress(
          '$completedCount',
          '${task.subtasks.length}',
        ),
        variant: UiPillVariant.count,
      ),
      headerTrailing: task.isCompleted
          ? null
          : _TaskSectionEditButton(
              buttonKey: ValueKey<String>(
                'task_subtasks_edit_button_${task.id}',
              ),
              isBusy: isBusy,
              onPressed: onStartEdit,
            ),
      child: _TaskSubtasksReadBody(
        task: task,
        completedCount: completedCount,
        isBusy: isBusy,
        onToggleSubtask: onToggleSubtask,
      ),
    );
  }
}

/// Manages live subtask toggling and inline subtask editing state for [TaskSubtasksSection].
class _TaskSubtasksSectionState extends ConsumerState<TaskSubtasksSection> {
  late final TextEditingController _newStepController;
  late final FocusNode _newStepFocusNode;
  final List<EditableSubtaskRow> _pendingDisposals = <EditableSubtaskRow>[];
  final List<EditableSubtaskRow> _rows = <EditableSubtaskRow>[];

  bool _autoFinish = false;
  String? _errorText;
  bool _isDisposalScheduled = false;
  bool _isSubmitting = false;
  int _nextRowId = 1;

  @override
  void initState() {
    super.initState();
    _newStepController = TextEditingController();
    _newStepFocusNode = FocusNode();
    if (widget.isEditing) {
      _seedRowsFromTask();
    }
  }

  @override
  void didUpdateWidget(covariant TaskSubtasksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _seedRowsFromTask();
      _newStepController.clear();
      _errorText = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _deferDisposeRows();
      _errorText = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _flushPendingDisposals();
    for (final row in _rows) {
      row.dispose();
    }
    _rows.clear();
    _newStepController.dispose();
    _newStepFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isControllerBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;

    if (!widget.isEditing || widget.task.isCompleted) {
      return widget.task.subtasks.isEmpty
          ? const SizedBox.shrink()
          : _TaskSubtasksReadCard(
              task: widget.task,
              isBusy: isBusy,
              onStartEdit: widget.onStartEdit,
              onToggleSubtask: _triggerToggleSubtask,
            );
    }

    return _TaskSubtasksEditCard(
      taskId: widget.task.id,
      rows: _rows,
      newStepController: _newStepController,
      newStepFocusNode: _newStepFocusNode,
      autoFinish: _autoFinish,
      hasExistingSubtasks: widget.task.subtasks.isNotEmpty,
      errorText: _errorText,
      isBusy: isBusy,
      onReorder: _handleReorder,
      onToggleRowDone: _handleToggleRowDone,
      onDeleteRow: _handleDeleteRow,
      onAddRow: _handleAddRow,
      onAutoFinishChanged: (value) => setState(() => _autoFinish = value),
      onClear: _triggerClear,
      onCancel: widget.onCancelEdit,
      onSave: _triggerSave,
    );
  }

  /// Queues all active [EditableSubtaskRow] controllers for post-frame disposal and clears [_rows].
  void _deferDisposeRows() {
    if (_rows.isEmpty) {
      return;
    }
    for (final row in _rows) {
      _enqueueDisposal(row);
    }
    _rows.clear();
  }

  /// Queues a removed [row] for post-frame disposal after its child field detaches.
  void _enqueueDisposal(EditableSubtaskRow row) {
    _pendingDisposals.add(row);
    if (_isDisposalScheduled) {
      return;
    }
    _isDisposalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushPendingDisposals();
    });
  }

  /// Disposes all queued subtask row controllers after the frame or during unmount.
  void _flushPendingDisposals() {
    _isDisposalScheduled = false;
    if (_pendingDisposals.isEmpty) {
      return;
    }
    final rows = List<EditableSubtaskRow>.of(_pendingDisposals);
    _pendingDisposals.clear();
    for (final row in rows) {
      row.dispose();
    }
  }

  /// Appends a new step from [_newStepController] and refocuses the add input.
  void _handleAddRow() {
    final trimmed = _newStepController.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    setState(() {
      _rows.add(
        EditableSubtaskRow(
          rowId: _nextRowId++,
          initialTitle: trimmed,
          isCompleted: false,
        ),
      );
      _newStepController.clear();
      _errorText = null;
    });
    _newStepFocusNode.requestFocus();
  }

  /// Removes the editable subtask row at [index] and defers disposing its controller.
  void _handleDeleteRow(EditableSubtaskRow row, int index) {
    if (index < 0 || index >= _rows.length) {
      return;
    }
    final removed = _rows.removeAt(index);
    _enqueueDisposal(removed);
    setState(() => _errorText = null);
  }

  /// Reorders editable subtask rows from [oldIndex] to [newIndex].
  void _handleReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _rows.length ||
        newIndex < 0 ||
        newIndex >= _rows.length ||
        oldIndex == newIndex) {
      return;
    }
    final moved = _rows.removeAt(oldIndex);
    _rows.insert(newIndex, moved);
    setState(() => _errorText = null);
  }

  /// Toggles completion state of editable row [index].
  void _handleToggleRowDone(int index) {
    if (index < 0 || index >= _rows.length) {
      return;
    }
    setState(() {
      _rows[index].isCompleted = !_rows[index].isCompleted;
      _errorText = null;
    });
  }

  /// Toggles a live subtask step directly via [BoardActionsNotifier.toggleSubtask].
  Future<void> _handleToggleSubtask(int stepIndex) async {
    final result = await ref
        .read(boardActionsProvider.notifier)
        .toggleSubtask(
          widget.task.id,
          stepIndex,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        return;
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        ref
            .read(floatingNoticeProvider.notifier)
            .showNotice(message, tone: FloatingNoticeTone.danger);
    }
  }

  /// Rebuilds [_rows] and [_autoFinish] from `widget.task`.
  void _seedRowsFromTask() {
    _deferDisposeRows();
    for (final step in widget.task.subtasks) {
      _rows.add(
        EditableSubtaskRow(
          rowId: _nextRowId++,
          initialTitle: step.title,
          isCompleted: step.isCompleted,
        ),
      );
    }
    _autoFinish = widget.task.subtasksAutoFinish;
  }

  /// Persists [subtasks] and [autoFinish] via [BoardActionsNotifier.saveSubtasks].
  Future<void> _submitSubtasks(
    List<SubtaskItem> subtasks, {
    required bool autoFinish,
  }) async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await ref
          .read(boardActionsProvider.notifier)
          .saveSubtasks(
            widget.task.id,
            subtasks,
            autoFinish: autoFinish,
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
          setState(() => _errorText = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Dispatches clearing all subtasks.
  void _triggerClear() {
    unawaited(_submitSubtasks(const <SubtaskItem>[], autoFinish: false));
  }

  /// Dispatches saving current editable subtasks (including any typed pending row).
  void _triggerSave() {
    final subtasks = <SubtaskItem>[
      for (final row in _rows)
        SubtaskItem(title: row.controller.text, isCompleted: row.isCompleted),
      if (_newStepController.text.trim().isNotEmpty)
        SubtaskItem(title: _newStepController.text.trim()),
    ];
    unawaited(_submitSubtasks(subtasks, autoFinish: _autoFinish));
  }

  /// Dispatches live subtask checkbox toggle.
  void _triggerToggleSubtask(int stepIndex) {
    unawaited(_handleToggleSubtask(stepIndex));
  }
}

/// Counts completed steps across [subtasks] in a single linear pass.
int _countCompletedSubtasks(List<SubtaskItem> subtasks) {
  var count = 0;
  for (final step in subtasks) {
    if (step.isCompleted) {
      count++;
    }
  }
  return count;
}
