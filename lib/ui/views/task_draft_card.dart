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
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/app_shell_controller.dart';
import '../../presentation/entity_controller.dart';
import '../../presentation/shell_models.dart';
import '../../presentation/task_controller.dart';
import '../../presentation/tasks_view_model.dart';
import '../../presentation/view_model_primitives.dart';
import '../dialogs/compact_label_picker_sheet.dart';
import '../widgets/entity_card_chrome.dart';
import '../widgets/entity_date_time_fields.dart';
import '../widgets/entity_label_picker.dart';
import 'task_detail_editors.dart';

/// Display order for optional sections inside [TaskDraftCard].
const List<TaskSectionKind> _draftOptionalSectionOrder = <TaskSectionKind>[
  TaskSectionKind.note,
  TaskSectionKind.links,
  TaskSectionKind.subtasks,
  TaskSectionKind.due,
  TaskSectionKind.repeat,
  TaskSectionKind.suspended,
  TaskSectionKind.prerequisites,
  TaskSectionKind.conditions,
];

/// Maximum reference links allowed per task (`TDF 0.8.0`).
const int _maxLinksPerTask = 20;

/// Maximum multi-line note length allowed by `TDF 0.8.0` (`maxTdfNoteLength`).
const int _maxNoteLength = 2000;

/// Maximum single-line text length allowed by `TDF 0.8.0` (`maxTdfTextLength`).
const int _maxSingleLineLength = 500;

/// Uncommitted accent-bordered Task Draft Card (`U-CARD-006`) allowing full task
/// configuration before committing to the `.tdf` document via [TaskController.createTaskDraft].
class TaskDraftCard extends ConsumerStatefulWidget {
  /// Creates a [TaskDraftCard].
  const TaskDraftCard({
    super.key,
    required this.allLabels,
    required this.allLocations,
    required this.hasBothScopedAndGlobalLabels,
    required this.currentLocalDateTimeHint,
  });

  /// Workspace labels available in the searchable label picker.
  final List<LabelPickerOptionViewModel> allLabels;

  /// Workspace locations available in the GPS conditions selector.
  final List<LocationOptionViewModel> allLocations;

  /// Current workspace local wall-clock timestamp (`YYYY-MM-DD HH:MM`) seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether workspace contains both scoped and global labels.
  final bool hasBothScopedAndGlobalLabels;

  @override
  ConsumerState<TaskDraftCard> createState() => _TaskDraftCardState();
}

/// Bottom dashed `+ Add` chips bar inside [TaskDraftCard] revealing optional draft sections on demand.
class _DraftAddSectionsBar extends StatelessWidget {
  /// Creates a [_DraftAddSectionsBar].
  const _DraftAddSectionsBar({
    required this.openSections,
    required this.showLabelsChip,
    required this.isBusy,
    required this.onOpenLabels,
    required this.onOpenSection,
  });

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Callback opening the label picker (inline on desktop or bottom sheet on compact).
  final VoidCallback onOpenLabels;

  /// Callback revealing an optional draft section.
  final ValueChanged<TaskSectionKind> onOpenSection;

  /// Currently open optional sections inside the draft card.
  final Set<TaskSectionKind> openSections;

  /// Whether `+ Labels` should appear because no labels are selected and the inline picker is closed.
  final bool showLabelsChip;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final chips = <Widget>[
      if (showLabelsChip)
        UiPill(
          key: const ValueKey<String>('draft_add_labels_chip'),
          label: localizations.inlineAddLabels,
          icon: Icons.label_outline_rounded,
          variant: UiPillVariant.addField,
          enabled: !isBusy,
          onPressed: isBusy ? null : onOpenLabels,
        ),
      for (final section in _draftOptionalSectionOrder)
        if (!openSections.contains(section))
          UiPill(
            key: ValueKey<String>('draft_add_${section.name}_chip'),
            label: _draftAddSectionLabel(section, localizations),
            icon: _draftAddSectionIcon(section),
            variant: UiPillVariant.addField,
            enabled: !isBusy,
            onPressed: isBusy ? null : () => onOpenSection(section),
          ),
    ];
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(spacing: 6.0, runSpacing: 6.0, children: chips);
  }
}

/// Immutable bundle of stable interaction callbacks owned by [_TaskDraftCardState].
@immutable
class _DraftCallbacks {
  /// Creates a [_DraftCallbacks].
  const _DraftCallbacks({
    required this.onAddSubtask,
    required this.onAddTimeWindow,
    required this.onAutoFinishChanged,
    required this.onCancelLinkEdit,
    required this.onClearFieldError,
    required this.onCloseLabelPicker,
    required this.onCloseSection,
    required this.onCommitLinkInput,
    required this.onConditionDraftChanged,
    required this.onCreateAndAssignLabel,
    required this.onDeleteLink,
    required this.onDeleteSubtask,
    required this.onDueAutoPrioritizeChanged,
    required this.onDueChanged,
    required this.onOpenLabelInfo,
    required this.onOpenLabelPicker,
    required this.onOpenSection,
    required this.onPlacementChanged,
    required this.onRemoveTimeWindow,
    required this.onReorderLinks,
    required this.onReorderSubtasks,
    required this.onRepeatUnitChanged,
    required this.onStartEditLink,
    required this.onSubmitTitle,
    required this.onSuspendedModeChanged,
    required this.onToggleLabel,
    required this.onTogglePrerequisite,
    required this.onToggleSubtaskDone,
  });

  /// Callback appending a subtask step.
  final VoidCallback onAddSubtask;

  /// Callback adding a time window.
  final VoidCallback onAddTimeWindow;

  /// Callback updating subtasks auto-finish flag.
  final ValueChanged<bool> onAutoFinishChanged;

  /// Callback cancelling active link row edit.
  final VoidCallback onCancelLinkEdit;

  /// Callback clearing field error by key.
  final ValueChanged<String> onClearFieldError;

  /// Callback closing desktop inline label picker.
  final VoidCallback onCloseLabelPicker;

  /// Callback closing an optional section.
  final ValueChanged<TaskSectionKind> onCloseSection;

  /// Callback adding or updating typed link input.
  final VoidCallback onCommitLinkInput;

  /// Callback updating condition draft.
  final ValueChanged<ConditionDraftViewModel> onConditionDraftChanged;

  /// Callback creating and assigning a new label.
  final ValueChanged<String> onCreateAndAssignLabel;

  /// Callback deleting a draft link row.
  final UiOrderedItemActionCallback<EntityLinkInput> onDeleteLink;

  /// Callback deleting a draft subtask row.
  final UiOrderedItemActionCallback<EditableSubtaskRow> onDeleteSubtask;

  /// Callback toggling due auto-prioritize flag.
  final ValueChanged<bool> onDueAutoPrioritizeChanged;

  /// Callback notified on due text change.
  final ValueChanged<String> onDueChanged;

  /// Callback navigating to a label card.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback opening the inline label picker or compact sheet.
  final ValueChanged<bool> onOpenLabelPicker;

  /// Callback revealing an optional draft section.
  final ValueChanged<TaskSectionKind> onOpenSection;

  /// Callback changing draft placement.
  final ValueChanged<TaskPlacementOption> onPlacementChanged;

  /// Callback removing a condition time window.
  final ValueChanged<int> onRemoveTimeWindow;

  /// Callback reordering draft links.
  final UiOrderedItemReorderCallback onReorderLinks;

  /// Callback reordering draft subtasks.
  final UiOrderedItemReorderCallback onReorderSubtasks;

  /// Callback changing recurrence unit.
  final ValueChanged<ShellRepeatUnit> onRepeatUnitChanged;

  /// Callback starting inline link row edit.
  final UiOrderedItemActionCallback<EntityLinkInput> onStartEditLink;

  /// Callback submitting draft on `Enter` in title input.
  final VoidCallback onSubmitTitle;

  /// Callback switching timed vs indefinite suspension.
  final ValueChanged<bool> onSuspendedModeChanged;

  /// Callback toggling a draft label.
  final ValueChanged<String> onToggleLabel;

  /// Callback toggling a prerequisite task.
  final ValueChanged<String> onTogglePrerequisite;

  /// Callback toggling completion of a draft subtask row.
  final ValueChanged<int> onToggleSubtaskDone;
}

/// Immutable rendering view combining controllers, callbacks, and state for [TaskDraftCard].
@immutable
class _DraftCardView {
  /// Creates a [_DraftCardView].
  const _DraftCardView({
    required this.callbacks,
    required this.controllers,
    required this.state,
  });

  /// Stable draft interaction callbacks.
  final _DraftCallbacks callbacks;

  /// Text controllers and focus nodes owned by [_TaskDraftCardState].
  final _DraftControllers controllers;

  /// Reactive draft form state snapshot for the current build pass.
  final _DraftViewState state;

  /// Whether the Due section is open with a non-empty timestamp.
  bool get hasDueDate =>
      state.openSections.contains(TaskSectionKind.due) &&
      controllers.due.text.trim().isNotEmpty;

  /// Whether the Suspended section is currently open on the draft.
  bool get isSuspendedOpen =>
      state.openSections.contains(TaskSectionKind.suspended);
}

/// Body column hosted inside [_DraftConditionsCard].
class _DraftConditionsBody extends StatelessWidget {
  /// Creates a [_DraftConditionsBody].
  const _DraftConditionsBody({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final isSuspended = view.isSuspendedOpen;
    final controlsEnabled = !view.state.isBusy && !isSuspended;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isSuspended) ...<Widget>[
          UiBanner(
            variant: UiBannerVariant.inlineWarning,
            message: localizations.taskSuspendedDisablesConditionsHint,
          ),
          SizedBox(height: tokens.spacing.space2),
        ],
        IgnorePointer(
          ignoring: isSuspended,
          child: Opacity(
            opacity: isSuspended ? tokens.focus.suspendedDimmedOpacity : 1.0,
            child: _DraftConditionsControls(
              view: view,
              enabled: controlsEnabled,
            ),
          ),
        ),
        if (view.state.fieldErrors['conditions'] case final error?) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          EntityInlineErrorText(message: error),
        ],
      ],
    );
  }
}

/// Live-updating Activation Conditions section hosted inside [TaskDraftCard].
class _DraftConditionsCard extends StatelessWidget {
  /// Creates a [_DraftConditionsCard].
  const _DraftConditionsCard({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: const ValueKey<String>('draft_conditions_card'),
      headerIcon: Icons.tune_rounded,
      headerTitle: localizations.taskConditionsSectionTitle,
      headerTrailing: _DraftSectionCloseButton(
        isBusy: view.state.isBusy,
        onClose: () =>
            view.callbacks.onCloseSection(TaskSectionKind.conditions),
      ),
      child: _DraftConditionsBody(view: view),
    );
  }
}

/// Interactive controls body inside [_DraftConditionsCard].
class _DraftConditionsControls extends StatelessWidget {
  /// Creates a [_DraftConditionsControls].
  const _DraftConditionsControls({required this.view, required this.enabled});

  /// Whether controls accept interaction.
  final bool enabled;

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final draft = view.state.conditionDraft;
    final dimensionsEnabled = enabled && !draft.ignoreAllLabelConditions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiToggleRow(
          label: localizations.conditionGlobalAnyLabel,
          value: draft.ignoreAllLabelConditions,
          isDense: true,
          enabled: enabled,
          onChanged: (value) => view.callbacks.onConditionDraftChanged(
            draft.copyWith(ignoreAllLabelConditions: value),
          ),
        ),
        if (!draft.ignoreAllLabelConditions) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _DraftDayConditionSection(view: view, enabled: dimensionsEnabled),
          SizedBox(height: tokens.spacing.space2),
          _DraftTimeConditionSection(view: view, enabled: dimensionsEnabled),
          SizedBox(height: tokens.spacing.space2),
          _DraftLocationConditionSection(
            view: view,
            enabled: dimensionsEnabled,
          ),
        ],
      ],
    );
  }
}

/// Lifecycle owner for all text controllers and focus nodes in [_TaskDraftCardState].
class _DraftControllers {
  /// Creates a [_DraftControllers] seeded with [initialTitle].
  _DraftControllers({required String initialTitle})
    : due = TextEditingController(),
      dueNote = TextEditingController(),
      linkTitle = TextEditingController(),
      linkUri = TextEditingController(),
      newSubtask = TextEditingController(),
      newSubtaskFocusNode = FocusNode(),
      note = TextEditingController(),
      repeatCount = TextEditingController(text: '1'),
      repeatLeadDays = TextEditingController(text: '0'),
      suspendedNote = TextEditingController(),
      suspendedUntil = TextEditingController(),
      timeEnd = TextEditingController(),
      timeStart = TextEditingController(),
      title = TextEditingController(text: initialTitle);

  /// Due timestamp controller.
  final TextEditingController due;

  /// Due note controller.
  final TextEditingController dueNote;

  /// Link title controller.
  final TextEditingController linkTitle;

  /// Link URI controller.
  final TextEditingController linkUri;

  /// New subtask controller.
  final TextEditingController newSubtask;

  /// New subtask focus node.
  final FocusNode newSubtaskFocusNode;

  /// Draft note controller.
  final TextEditingController note;

  /// Repeat interval count controller.
  final TextEditingController repeatCount;

  /// Repeat preparation lead days controller.
  final TextEditingController repeatLeadDays;

  /// Suspension deferral note controller.
  final TextEditingController suspendedNote;

  /// Timed suspension timestamp controller.
  final TextEditingController suspendedUntil;

  /// Condition time window end controller.
  final TextEditingController timeEnd;

  /// Condition time window start controller.
  final TextEditingController timeStart;

  /// Draft title controller.
  final TextEditingController title;

  /// Disposes every controller and focus node owned by this bundle.
  void dispose() {
    title.dispose();
    note.dispose();
    linkTitle.dispose();
    linkUri.dispose();
    newSubtask.dispose();
    newSubtaskFocusNode.dispose();
    due.dispose();
    dueNote.dispose();
    repeatCount.dispose();
    repeatLeadDays.dispose();
    suspendedUntil.dispose();
    suspendedNote.dispose();
    timeStart.dispose();
    timeEnd.dispose();
  }
}

/// Day-of-week condition dimension selector and weekday picker inside [_DraftConditionsControls].
class _DraftDayConditionSection extends StatelessWidget {
  /// Creates a [_DraftDayConditionSection].
  const _DraftDayConditionSection({required this.view, required this.enabled});

  /// Whether day condition controls accept interaction.
  final bool enabled;

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final draft = view.state.conditionDraft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _DraftDimensionSelector(
          label: localizations.conditionDayGroupTitle,
          mode: draft.daysMode,
          anyLabel: localizations.conditionDayAnyLabel,
          enabled: enabled,
          onModeChanged: (mode) => view.callbacks.onConditionDraftChanged(
            draft.copyWith(daysMode: mode),
          ),
        ),
        if (draft.daysMode == ConditionDimensionMode.custom) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _DraftWeekdaysWrap(
            selectedWeekdays: draft.selectedWeekdays,
            enabled: enabled,
            onToggleWeekday: _toggleWeekday,
          ),
        ],
      ],
    );
  }

  /// Toggles ISO weekday [weekday] (`1..7`) in the draft condition weekdays.
  void _toggleWeekday(int weekday) {
    final draft = view.state.conditionDraft;
    final nextDays = List<int>.of(draft.selectedWeekdays);
    if (!nextDays.remove(weekday)) {
      nextDays.add(weekday);
      nextDays.sort();
    }
    view.callbacks.onConditionDraftChanged(
      draft.copyWith(selectedWeekdays: nextDays),
    );
  }
}

/// Dimension override selector (`Inherit` / `Any` / `Custom`) used inside [_DraftConditionsControls].
class _DraftDimensionSelector extends StatelessWidget {
  /// Creates a [_DraftDimensionSelector].
  const _DraftDimensionSelector({
    required this.label,
    required this.mode,
    required this.anyLabel,
    required this.enabled,
    required this.onModeChanged,
  });

  /// Localized label for [ConditionDimensionMode.any].
  final String anyLabel;

  /// Whether the dropdown accepts changes.
  final bool enabled;

  /// Dimension heading label.
  final String label;

  /// Currently selected dimension mode.
  final ConditionDimensionMode mode;

  /// Callback notified when the mode changes.
  final ValueChanged<ConditionDimensionMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      kind: UiFieldKind.select,
      label: label,
      enabled: enabled,
      selectValue: mode.name,
      selectOptions: <UiSelectOption>[
        UiSelectOption(
          value: ConditionDimensionMode.inherit.name,
          label: localizations.conditionInheritLabel,
        ),
        UiSelectOption(value: ConditionDimensionMode.any.name, label: anyLabel),
        UiSelectOption(
          value: ConditionDimensionMode.custom.name,
          label: localizations.conditionCustomLabel,
        ),
      ],
      onSelectChanged: (value) {
        final next = _parseConditionDimensionMode(value);
        if (next != null) {
          onModeChanged(next);
        }
      },
    );
  }
}

/// Optional Due date section hosted inside [TaskDraftCard].
class _DraftDueCard extends StatelessWidget {
  /// Creates a [_DraftDueCard].
  const _DraftDueCard({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: const ValueKey<String>('draft_due_card'),
      headerIcon: Icons.calendar_today_outlined,
      headerTitle: localizations.taskInfoDueLabel,
      headerTrailing: _DraftSectionCloseButton(
        isBusy: view.state.isBusy,
        onClose: () => view.callbacks.onCloseSection(TaskSectionKind.due),
      ),
      child: _DraftDueCardBody(view: view),
    );
  }
}

/// Body column hosted inside [_DraftDueCard].
class _DraftDueCardBody extends StatelessWidget {
  /// Creates a [_DraftDueCardBody].
  const _DraftDueCardBody({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final state = view.state;
    final callbacks = view.callbacks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        EntityHybridDateTimeField(
          controller: view.controllers.due,
          label: localizations.taskDueButtonLabel,
          fallbackLocalDateTime: state.currentLocalDateTimeHint,
          enabled: !state.isBusy,
          errorText: state.fieldErrors['due'],
          onChanged: callbacks.onDueChanged,
        ),
        SizedBox(height: tokens.spacing.space2),
        UiToggleRow(
          label: localizations.taskDueAutoPrioritizeLabel,
          description: localizations.taskDueAutoPrioritizeSubtitle,
          value: state.dueAutoPrioritize,
          isDense: true,
          enabled: !state.isBusy,
          onChanged: callbacks.onDueAutoPrioritizeChanged,
        ),
        SizedBox(height: tokens.spacing.space2),
        _DraftDueNoteField(view: view),
      ],
    );
  }
}

/// Optional deadline note field hosted inside [_DraftDueCardBody].
class _DraftDueNoteField extends StatelessWidget {
  /// Creates a [_DraftDueNoteField].
  const _DraftDueNoteField({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      kind: UiFieldKind.multiline,
      controller: view.controllers.dueNote,
      label: localizations.taskDueNoteLabel,
      hintText: localizations.taskDueNoteHint,
      maxLength: _maxNoteLength,
      minLines: 2,
      maxLines: 4,
      enabled: !view.state.isBusy,
      errorText: view.state.fieldErrors['dueNote'],
      onChanged: (_) => view.callbacks.onClearFieldError('dueNote'),
    );
  }
}

/// Right-aligned `Cancel` and primary `Create task` footer for [TaskDraftCard].
class _DraftFooter extends StatelessWidget {
  /// Creates a [_DraftFooter].
  const _DraftFooter({
    required this.isBusy,
    required this.onCancel,
    required this.onCreate,
  });

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Callback cancelling the uncommitted draft.
  final VoidCallback onCancel;

  /// Callback validating and committing the draft.
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        UiButton(
          key: const ValueKey<String>('task_draft_cancel_button'),
          label: localizations.actionCancel,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: isBusy ? null : onCancel,
        ),
        const SizedBox(width: 8.0),
        UiButton(
          key: const ValueKey<String>('task_draft_create_button'),
          label: localizations.actionCreateTask,
          leadingIcon: isBusy ? Icons.sync_rounded : Icons.add_rounded,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          isLoading: isBusy,
          onPressed: isBusy ? null : onCreate,
        ),
      ],
    );
  }
}

/// Expanded desktop inline label picker card hosted inside [_DraftLabelsSection].
class _DraftLabelsInlinePickerCard extends StatelessWidget {
  /// Creates a [_DraftLabelsInlinePickerCard].
  const _DraftLabelsInlinePickerCard({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = view.state;
    final callbacks = view.callbacks;

    return UiCard.inset(
      key: const ValueKey<String>('draft_labels_picker_card'),
      isEditing: true,
      headerIcon: Icons.label_outline_rounded,
      headerTitle: localizations.taskLabelsSectionTitle,
      headerBadge: UiPill(
        label: '${state.selectedLabelIds.length}',
        variant: UiPillVariant.count,
      ),
      headerTrailing: UiButton(
        label: localizations.actionDone,
        variant: UiButtonVariant.secondary,
        density: UiButtonDensity.compact,
        onPressed: callbacks.onCloseLabelPicker,
      ),
      child: EntitySearchableLabelPicker(
        allLabels: state.allLabels,
        selectedIds: state.selectedLabelIds,
        hasBothScopedAndGlobal: state.hasBothScopedAndGlobalLabels,
        autoFocusSearch: true,
        onToggleLabel: callbacks.onToggleLabel,
        onCreateAndAssign: callbacks.onCreateAndAssignLabel,
        onOpenLabelInfo: callbacks.onOpenLabelInfo,
        onRequestClose: callbacks.onCloseLabelPicker,
      ),
    );
  }
}

/// Assigned labels and inline/sheet picker section hosted inside [TaskDraftCard].
class _DraftLabelsSection extends StatelessWidget {
  /// Creates a [_DraftLabelsSection].
  const _DraftLabelsSection({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final state = view.state;
    if (state.isInlineLabelPickerOpen && !state.isCompact) {
      return _DraftLabelsInlinePickerCard(view: view);
    }

    final selectedOptions = _resolveSelectedLabels(
      state.allLabels,
      state.selectedLabelIds,
    );
    if (selectedOptions.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DraftLabelsSummaryCard(
      view: view,
      selectedOptions: selectedOptions,
    );
  }
}

/// Selected draft label pills summary card hosted inside [_DraftLabelsSection].
class _DraftLabelsSummaryCard extends StatelessWidget {
  /// Creates a [_DraftLabelsSummaryCard].
  const _DraftLabelsSummaryCard({
    required this.view,
    required this.selectedOptions,
  });

  /// Resolved label view models currently assigned to the draft.
  final List<LabelPickerOptionViewModel> selectedOptions;

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: const ValueKey<String>('draft_labels_card'),
      headerIcon: Icons.label_outline_rounded,
      headerTitle: localizations.taskLabelsSectionTitle,
      headerBadge: UiPill(
        label: '${selectedOptions.length}',
        variant: UiPillVariant.count,
      ),
      child: _DraftSelectedLabelsWrap(
        view: view,
        selectedOptions: selectedOptions,
      ),
    );
  }
}

/// Save/add and cancel action buttons hosted inside [_DraftLinkAddForm].
class _DraftLinkAddActions extends StatelessWidget {
  /// Creates a [_DraftLinkAddActions].
  const _DraftLinkAddActions({
    required this.isEditingExisting,
    required this.isBusy,
    required this.onCommit,
    required this.onCancelEdit,
  });

  /// Whether draft submission is in flight.
  final bool isBusy;

  /// Whether currently updating an existing draft link row.
  final bool isEditingExisting;

  /// Callback cancelling the active row edit.
  final VoidCallback onCancelEdit;

  /// Callback adding or updating the link row.
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 8.0,
      runSpacing: 6.0,
      children: <Widget>[
        UiButton(
          label: isEditingExisting
              ? localizations.tooltipSaveLink
              : localizations.tooltipAddLink,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: isBusy ? null : onCommit,
        ),
        if (isEditingExisting)
          UiButton(
            label: localizations.actionCancel,
            variant: UiButtonVariant.text,
            density: UiButtonDensity.compact,
            onPressed: isBusy ? null : onCancelEdit,
          ),
      ],
    );
  }
}

/// Responsive title and URI input grid hosted inside [_DraftLinkAddForm].
class _DraftLinkAddFields extends StatelessWidget {
  /// Creates a [_DraftLinkAddFields].
  const _DraftLinkAddFields({
    required this.titleController,
    required this.uriController,
    required this.isBusy,
    required this.onCommit,
  });

  /// Whether draft submission is in flight.
  final bool isBusy;

  /// Callback committing the typed link on URI submit.
  final VoidCallback onCommit;

  /// Controller for the link title.
  final TextEditingController titleController;

  /// Controller for the link URI.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    return UiResponsiveGrid(
      preset: UiGridPreset.twoColumnCompactCollapse,
      spacing: tokens.spacing.space2,
      runSpacing: tokens.spacing.space2,
      children: <Widget>[
        UiField(
          kind: UiFieldKind.text,
          controller: titleController,
          hintText: localizations.linkTitleHint,
          maxLength: _maxSingleLineLength,
          enabled: !isBusy,
          textInputAction: TextInputAction.next,
        ),
        UiField(
          kind: UiFieldKind.text,
          controller: uriController,
          hintText: localizations.linkUriHint,
          maxLength: _maxSingleLineLength,
          isMonospace: true,
          enabled: !isBusy,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onCommit(),
        ),
      ],
    );
  }
}

/// Inline link title/URI input bar hosted inside [_DraftLinksCard].
class _DraftLinkAddForm extends StatelessWidget {
  /// Creates a [_DraftLinkAddForm].
  const _DraftLinkAddForm({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final state = view.state;
    final callbacks = view.callbacks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _DraftLinkAddFields(
          titleController: view.controllers.linkTitle,
          uriController: view.controllers.linkUri,
          isBusy: state.isBusy,
          onCommit: callbacks.onCommitLinkInput,
        ),
        if (state.linkInputError case final error?) ...<Widget>[
          SizedBox(height: tokens.spacing.space1),
          EntityInlineErrorText(message: error),
        ],
        SizedBox(height: tokens.spacing.space2),
        _DraftLinkAddActions(
          isEditingExisting: state.editingLinkIndex != null,
          isBusy: state.isBusy,
          onCommit: callbacks.onCommitLinkInput,
          onCancelEdit: callbacks.onCancelLinkEdit,
        ),
      ],
    );
  }
}

/// Single reference link title and monospace URI row inside [_DraftLinksCardBody].
class _DraftLinkRowContent extends StatelessWidget {
  /// Creates a [_DraftLinkRowContent].
  const _DraftLinkRowContent({required this.link});

  /// Draft link entry rendered by this row.
  final EntityLinkInput link;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          link.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.meta.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          link.uri,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}

/// Optional Reference Links section hosted inside [TaskDraftCard].
class _DraftLinksCard extends StatelessWidget {
  /// Creates a [_DraftLinksCard].
  const _DraftLinksCard({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: const ValueKey<String>('draft_links_card'),
      headerIcon: Icons.link_rounded,
      headerTitle: localizations.linksSectionTitle,
      headerBadge: UiPill(
        label: '${view.state.draftLinks.length} / $_maxLinksPerTask',
        variant: UiPillVariant.count,
      ),
      headerTrailing: _DraftSectionCloseButton(
        isBusy: view.state.isBusy,
        onClose: () => view.callbacks.onCloseSection(TaskSectionKind.links),
      ),
      child: _DraftLinksCardBody(view: view),
    );
  }
}

/// Ordered links list and validation error column inside [_DraftLinksCard].
class _DraftLinksCardBody extends StatelessWidget {
  /// Creates a [_DraftLinksCardBody].
  const _DraftLinksCardBody({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final state = view.state;
    final callbacks = view.callbacks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiOrderedItemList<EntityLinkInput>(
          items: state.draftLinks,
          editingIndex: state.editingLinkIndex,
          itemKey: (link, index) =>
              ValueKey<String>('draft_link_${index}_${link.title}_${link.uri}'),
          onReorder: state.isBusy ? null : callbacks.onReorderLinks,
          moveUpTooltip: localizations.tooltipMoveLinkUp,
          moveDownTooltip: localizations.tooltipMoveLinkDown,
          onEdit: state.isBusy ? null : callbacks.onStartEditLink,
          editTooltip: localizations.tooltipEditLink,
          onDelete: state.isBusy ? null : callbacks.onDeleteLink,
          deleteTooltip: localizations.tooltipRemoveLink,
          itemBuilder: (context, link, index, isEditing) =>
              _DraftLinkRowContent(link: link),
          addBar: _DraftLinkAddForm(view: view),
        ),
        if (state.fieldErrors['links'] case final error?) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          EntityInlineErrorText(message: error),
        ],
      ],
    );
  }
}

/// GPS location condition dimension selector and chips wrap inside [_DraftConditionsControls].
class _DraftLocationConditionSection extends StatelessWidget {
  /// Creates a [_DraftLocationConditionSection].
  const _DraftLocationConditionSection({
    required this.view,
    required this.enabled,
  });

  /// Whether location condition controls accept interaction.
  final bool enabled;

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final draft = view.state.conditionDraft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _DraftDimensionSelector(
          label: localizations.conditionLocationGroupTitle,
          mode: draft.locationsMode,
          anyLabel: localizations.conditionLocationAnyLabel,
          enabled: enabled,
          onModeChanged: (mode) => view.callbacks.onConditionDraftChanged(
            draft.copyWith(locationsMode: mode),
          ),
        ),
        if (draft.locationsMode == ConditionDimensionMode.custom) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _DraftLocationsWrap(
            allLocations: view.state.allLocations,
            selectedIds: draft.selectedLocationIds,
            enabled: enabled,
            onToggleLocation: _toggleLocation,
          ),
        ],
      ],
    );
  }

  /// Toggles [locationId] in the draft condition location identifiers.
  void _toggleLocation(String locationId) {
    final draft = view.state.conditionDraft;
    final nextIds = List<String>.of(draft.selectedLocationIds);
    if (!nextIds.remove(locationId)) {
      nextIds.add(locationId);
    }
    view.callbacks.onConditionDraftChanged(
      draft.copyWith(selectedLocationIds: nextIds),
    );
  }
}

/// Selectable GPS location chips wrap hosted inside [_DraftLocationConditionSection].
class _DraftLocationsWrap extends StatelessWidget {
  /// Creates a [_DraftLocationsWrap].
  const _DraftLocationsWrap({
    required this.allLocations,
    required this.selectedIds,
    required this.enabled,
    required this.onToggleLocation,
  });

  /// All workspace locations.
  final List<LocationOptionViewModel> allLocations;

  /// Whether chips are interactive.
  final bool enabled;

  /// Callback toggling selection of a location identifier.
  final ValueChanged<String> onToggleLocation;

  /// Selected location identifiers.
  final List<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    if (allLocations.isEmpty) {
      return Text(
        localizations.emptyLocationsHint,
        style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
      );
    }
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final location in allLocations)
          UiPill(
            label: location.name,
            icon: Icons.location_on_outlined,
            variant: UiPillVariant.selectable,
            isSelected: selectedIds.contains(location.id),
            enabled: enabled,
            onPressed: enabled ? () => onToggleLocation(location.id) : null,
          ),
      ],
    );
  }
}

/// Optional multi-line Note section hosted inside [TaskDraftCard].
class _DraftNoteCard extends StatelessWidget {
  /// Creates a [_DraftNoteCard].
  const _DraftNoteCard({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = view.state;
    final callbacks = view.callbacks;

    return UiCard.inset(
      key: const ValueKey<String>('draft_note_card'),
      headerIcon: Icons.description_outlined,
      headerTitle: localizations.taskNoteLabel,
      headerTrailing: _DraftSectionCloseButton(
        isBusy: state.isBusy,
        onClose: () => callbacks.onCloseSection(TaskSectionKind.note),
      ),
      child: UiField(
        kind: UiFieldKind.multiline,
        controller: view.controllers.note,
        hintText: localizations.taskNoteHint,
        maxLength: _maxNoteLength,
        minLines: 3,
        maxLines: 6,
        enabled: !state.isBusy,
        errorText: state.fieldErrors['note'],
        onChanged: (_) => callbacks.onClearFieldError('note'),
      ),
    );
  }
}

/// Dispatches an individual open optional draft [section] to its section card widget.
class _DraftOptionalSectionCard extends StatelessWidget {
  /// Creates a [_DraftOptionalSectionCard].
  const _DraftOptionalSectionCard({required this.section, required this.view});

  /// Optional draft section kind to render.
  final TaskSectionKind section;

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      TaskSectionKind.title => const SizedBox.shrink(),
      TaskSectionKind.note => _DraftNoteCard(view: view),
      TaskSectionKind.links => _DraftLinksCard(view: view),
      TaskSectionKind.subtasks => _DraftSubtasksCard(view: view),
      TaskSectionKind.labels => const SizedBox.shrink(),
      TaskSectionKind.due => _DraftDueCard(view: view),
      TaskSectionKind.repeat => _DraftRepeatCard(view: view),
      TaskSectionKind.suspended => _DraftSuspendedCard(view: view),
      TaskSectionKind.prerequisites => _DraftPrerequisitesCard(view: view),
      TaskSectionKind.conditions => _DraftConditionsCard(view: view),
    };
  }
}

/// Always-visible Queue & Priority placement selector hosted inside [TaskDraftCard].
class _DraftPlacementCard extends StatelessWidget {
  /// Creates a [_DraftPlacementCard].
  const _DraftPlacementCard({
    required this.placement,
    required this.isBusy,
    required this.onChanged,
  });

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Callback notified when placement changes.
  final ValueChanged<TaskPlacementOption> onChanged;

  /// Currently selected placement mode.
  final TaskPlacementOption placement;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: const ValueKey<String>('draft_placement_card'),
      headerIcon: Icons.bolt_outlined,
      headerTitle: localizations.inlinePlacementSectionTitle,
      child: _DraftPlacementCardBody(
        placement: placement,
        isBusy: isBusy,
        onChanged: onChanged,
      ),
    );
  }
}

/// Segmented placement control and caption hosted inside [_DraftPlacementCard].
class _DraftPlacementCardBody extends StatelessWidget {
  /// Creates a [_DraftPlacementCardBody].
  const _DraftPlacementCardBody({
    required this.placement,
    required this.isBusy,
    required this.onChanged,
  });

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Callback notified when placement changes.
  final ValueChanged<TaskPlacementOption> onChanged;

  /// Currently selected placement mode.
  final TaskPlacementOption placement;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiSegmentedControl<TaskPlacementOption>(
          segments: <UiSegment<TaskPlacementOption>>[
            UiSegment<TaskPlacementOption>(
              value: TaskPlacementOption.queue,
              label: localizations.placementQueueOption,
            ),
            UiSegment<TaskPlacementOption>(
              value: TaskPlacementOption.priority,
              label: localizations.quickAddPriority,
            ),
            UiSegment<TaskPlacementOption>(
              value: TaskPlacementOption.someday,
              label: localizations.tier5Name,
            ),
          ],
          value: placement,
          enabled: !isBusy,
          semanticLabel: localizations.inlinePlacementSectionTitle,
          onChanged: onChanged,
        ),
        SizedBox(height: tokens.spacing.space2),
        Text(
          _placementHint(placement, localizations),
          style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
        ),
      ],
    );
  }
}

/// Optional Prerequisite tasks selector hosted inside [TaskDraftCard].
class _DraftPrerequisitesCard extends StatelessWidget {
  /// Creates a [_DraftPrerequisitesCard].
  const _DraftPrerequisitesCard({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: const ValueKey<String>('draft_prerequisites_card'),
      headerIcon: Icons.lock_outline_rounded,
      headerTitle: localizations.taskBlockedBySectionTitle,
      headerBadge: UiPill(
        label: '${view.state.selectedPrerequisiteIds.length}',
        variant: UiPillVariant.count,
      ),
      headerTrailing: _DraftSectionCloseButton(
        isBusy: view.state.isBusy,
        onClose: () =>
            view.callbacks.onCloseSection(TaskSectionKind.prerequisites),
      ),
      child: _DraftPrerequisitesCardBody(view: view),
    );
  }
}

/// Searchable prerequisite picker and error column inside [_DraftPrerequisitesCard].
class _DraftPrerequisitesCardBody extends StatelessWidget {
  /// Creates a [_DraftPrerequisitesCardBody].
  const _DraftPrerequisitesCardBody({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _DraftPrerequisitesPicker(view: view),
        if (view.state.fieldErrors['prerequisites']
            case final error?) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          EntityInlineErrorText(message: error),
        ],
      ],
    );
  }
}

/// Searchable prerequisite candidate picker hosted inside [_DraftPrerequisitesCardBody].
class _DraftPrerequisitesPicker extends StatelessWidget {
  /// Creates a [_DraftPrerequisitesPicker].
  const _DraftPrerequisitesPicker({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = view.state;

    return UiSearchablePicker<String>(
      options: <UiPickerOption<String>>[
        for (final candidate in state.prerequisiteCandidates)
          UiPickerOption<String>(
            id: candidate.id,
            value: candidate.id,
            label: candidate.title,
            enabled: !candidate.wouldCreateCycle,
            disabledHint: candidate.wouldCreateCycle
                ? localizations.prerequisiteCyclePreventedHint
                : null,
          ),
      ],
      selectedIds: state.selectedPrerequisiteIds,
      searchMaxLength: _maxSingleLineLength,
      searchPlaceholder: localizations.blockedBySearchHint,
      searchClearTooltip: localizations.tooltipClearSearch,
      emptyText: localizations.blockedBySearchNoResults,
      onToggleOption: (option) {
        if (!state.isBusy) {
          view.callbacks.onTogglePrerequisite(option.value);
        }
      },
    );
  }
}

/// Optional Repeat section hosted inside [TaskDraftCard].
class _DraftRepeatCard extends StatelessWidget {
  /// Creates a [_DraftRepeatCard].
  const _DraftRepeatCard({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: const ValueKey<String>('draft_repeat_card'),
      headerIcon: Icons.repeat_rounded,
      headerTitle: localizations.repeatFlagLabel,
      headerTrailing: _DraftSectionCloseButton(
        isBusy: view.state.isBusy,
        onClose: () => view.callbacks.onCloseSection(TaskSectionKind.repeat),
      ),
      child: _DraftRepeatCardBody(view: view),
    );
  }
}

/// Interval, unit, and lead-days column hosted inside [_DraftRepeatCard].
class _DraftRepeatCardBody extends StatelessWidget {
  /// Creates a [_DraftRepeatCardBody].
  const _DraftRepeatCardBody({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final state = view.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiField(
          kind: UiFieldKind.text,
          controller: view.controllers.repeatCount,
          label: localizations.repeatIntervalLabel,
          hintText: '1',
          keyboardType: TextInputType.number,
          enabled: !state.isBusy,
          errorText: state.fieldErrors['repeatCount'],
          onChanged: (_) => view.callbacks.onClearFieldError('repeatCount'),
        ),
        SizedBox(height: tokens.spacing.space2),
        _DraftRepeatUnitControl(
          unit: state.repeatUnit,
          isBusy: state.isBusy,
          onUnitChanged: view.callbacks.onRepeatUnitChanged,
        ),
        SizedBox(height: tokens.spacing.space2),
        _DraftRepeatLeadDaysField(view: view),
      ],
    );
  }
}

/// Preparation lead-days field hosted inside [_DraftRepeatCardBody].
class _DraftRepeatLeadDaysField extends StatelessWidget {
  /// Creates a [_DraftRepeatLeadDaysField].
  const _DraftRepeatLeadDaysField({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final hasDueDate = view.hasDueDate;
    return UiField(
      kind: UiFieldKind.text,
      controller: view.controllers.repeatLeadDays,
      label: localizations.repeatLeadDaysLabel,
      hintText: localizations.repeatLeadDaysHint,
      helperText: hasDueDate
          ? null
          : localizations.inlineRepeatLeadNeedsDueHint,
      keyboardType: TextInputType.number,
      enabled: !view.state.isBusy && hasDueDate,
      errorText: view.state.fieldErrors['repeatLeadDays'],
      onChanged: (_) => view.callbacks.onClearFieldError('repeatLeadDays'),
    );
  }
}

/// Recurrence unit segmented control hosted inside [_DraftRepeatCardBody].
class _DraftRepeatUnitControl extends StatelessWidget {
  /// Creates a [_DraftRepeatUnitControl].
  const _DraftRepeatUnitControl({
    required this.unit,
    required this.isBusy,
    required this.onUnitChanged,
  });

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Callback notified when recurrence unit changes.
  final ValueChanged<ShellRepeatUnit> onUnitChanged;

  /// Selected recurrence unit.
  final ShellRepeatUnit unit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiSegmentedControl<ShellRepeatUnit>(
      segments: <UiSegment<ShellRepeatUnit>>[
        UiSegment<ShellRepeatUnit>(
          value: ShellRepeatUnit.days,
          label: localizations.repeatUnitDays,
        ),
        UiSegment<ShellRepeatUnit>(
          value: ShellRepeatUnit.weeks,
          label: localizations.repeatUnitWeeks,
        ),
        UiSegment<ShellRepeatUnit>(
          value: ShellRepeatUnit.months,
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

/// Standard close icon button placed in optional draft section card headers.
class _DraftSectionCloseButton extends StatelessWidget {
  /// Creates a [_DraftSectionCloseButton].
  const _DraftSectionCloseButton({required this.isBusy, required this.onClose});

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Callback closing and resetting the enclosing optional draft section.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      leadingIcon: Icons.close_rounded,
      variant: UiButtonVariant.icon,
      density: UiButtonDensity.sidebarDesktop,
      tooltip: localizations.actionClose,
      onPressed: isBusy ? null : onClose,
    );
  }
}

/// Wrap of selected draft label split chips and `+ Add` trigger inside [_DraftLabelsSummaryCard].
class _DraftSelectedLabelsWrap extends StatelessWidget {
  /// Creates a [_DraftSelectedLabelsWrap].
  const _DraftSelectedLabelsWrap({
    required this.view,
    required this.selectedOptions,
  });

  /// Resolved label view models currently assigned to the draft.
  final List<LabelPickerOptionViewModel> selectedOptions;

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final state = view.state;
    final callbacks = view.callbacks;

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final option in selectedOptions)
          UiPill(
            label: option.name,
            variant: UiPillVariant.splitChip,
            colorDot: _resolveColorDot(option.colorValue, tokens),
            removeTooltip: localizations.labelPickerRemoveTooltip(option.name),
            enabled: !state.isBusy,
            onRemove: state.isBusy
                ? null
                : () => callbacks.onToggleLabel(option.id),
          ),
        UiPill(
          label: localizations.actionAdd,
          icon: Icons.add_rounded,
          variant: UiPillVariant.addField,
          enabled: !state.isBusy,
          onPressed: state.isBusy
              ? null
              : () => callbacks.onOpenLabelPicker(state.isCompact),
        ),
      ],
    );
  }
}

/// Bottom input and Add button bar hosted inside [_DraftSubtasksCardBody].
class _DraftSubtaskAddBar extends StatelessWidget {
  /// Creates a [_DraftSubtaskAddBar].
  const _DraftSubtaskAddBar({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isBusy = view.state.isBusy;
    final onAdd = view.callbacks.onAddSubtask;

    return Row(
      children: <Widget>[
        Expanded(
          child: UiField(
            key: const ValueKey<String>('draft_subtask_add_input'),
            kind: UiFieldKind.text,
            controller: view.controllers.newSubtask,
            focusNode: view.controllers.newSubtaskFocusNode,
            hintText: localizations.subtaskInputHint,
            maxLength: _maxSingleLineLength,
            enabled: !isBusy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8.0),
        UiButton(
          label: localizations.actionAdd,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          tooltip: localizations.tooltipAddSubtask,
          onPressed: isBusy ? null : onAdd,
        ),
      ],
    );
  }
}

/// Single editable subtask row hosted inside [_DraftSubtasksCardBody].
class _DraftSubtaskRowItem extends StatelessWidget {
  /// Creates a [_DraftSubtaskRowItem].
  const _DraftSubtaskRowItem({
    required this.row,
    required this.isBusy,
    required this.onToggleDone,
  });

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Callback toggling completion of this subtask row.
  final VoidCallback onToggleDone;

  /// Editable subtask row model.
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
            kind: UiFieldKind.text,
            controller: row.controller,
            maxLength: _maxSingleLineLength,
            enabled: !isBusy,
            semanticLabel: localizations.subtasksSectionTitle,
          ),
        ),
      ],
    );
  }
}

/// Auto-finish toggle footer hosted inside [_DraftSubtasksCardBody].
class _DraftSubtasksAutoFinishToggle extends StatelessWidget {
  /// Creates a [_DraftSubtasksAutoFinishToggle].
  const _DraftSubtasksAutoFinishToggle({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiToggleRow(
      label: localizations.subtasksAutoFinishLabel,
      description: localizations.tooltipTaskEditorAutoFinish,
      value: view.state.subtasksAutoFinish,
      isDense: true,
      enabled: !view.state.isBusy,
      onChanged: view.callbacks.onAutoFinishChanged,
    );
  }
}

/// Optional Subtasks section hosted inside [TaskDraftCard].
class _DraftSubtasksCard extends StatelessWidget {
  /// Creates a [_DraftSubtasksCard].
  const _DraftSubtasksCard({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = view.state;

    return UiCard.inset(
      key: const ValueKey<String>('draft_subtasks_card'),
      headerIcon: state.subtasksAutoFinish
          ? Icons.check_box_outlined
          : Icons.checklist_rounded,
      headerTitle: localizations.subtasksSectionTitle,
      headerBadge: UiPill(
        label: '${state.subtaskRows.length}',
        variant: UiPillVariant.count,
      ),
      headerTrailing: _DraftSectionCloseButton(
        isBusy: state.isBusy,
        onClose: () => view.callbacks.onCloseSection(TaskSectionKind.subtasks),
      ),
      child: _DraftSubtasksCardBody(view: view),
    );
  }
}

/// Ordered subtasks list and validation error column inside [_DraftSubtasksCard].
class _DraftSubtasksCardBody extends StatelessWidget {
  /// Creates a [_DraftSubtasksCardBody].
  const _DraftSubtasksCardBody({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final state = view.state;
    final callbacks = view.callbacks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiOrderedItemList<EditableSubtaskRow>(
          items: state.subtaskRows,
          itemKey: (row, index) =>
              ValueKey<String>('draft_subtask_row_${row.rowId}'),
          onReorder: state.isBusy ? null : callbacks.onReorderSubtasks,
          onDelete: state.isBusy ? null : callbacks.onDeleteSubtask,
          deleteTooltip: localizations.tooltipRemoveSubtask,
          itemBuilder: (context, row, index, isEditing) => _DraftSubtaskRowItem(
            row: row,
            isBusy: state.isBusy,
            onToggleDone: () => callbacks.onToggleSubtaskDone(index),
          ),
          addBar: _DraftSubtaskAddBar(view: view),
          footer: _DraftSubtasksAutoFinishToggle(view: view),
        ),
        if (state.fieldErrors['subtasks'] case final error?) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          EntityInlineErrorText(message: error),
        ],
      ],
    );
  }
}

/// Optional Suspended section hosted inside [TaskDraftCard].
class _DraftSuspendedCard extends StatelessWidget {
  /// Creates a [_DraftSuspendedCard].
  const _DraftSuspendedCard({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: const ValueKey<String>('draft_suspended_card'),
      headerIcon: Icons.pause_circle_outline_rounded,
      headerTitle: localizations.taskSuspendedLabel,
      headerTrailing: _DraftSectionCloseButton(
        isBusy: view.state.isBusy,
        onClose: () => view.callbacks.onCloseSection(TaskSectionKind.suspended),
      ),
      child: _DraftSuspendedCardBody(view: view),
    );
  }
}

/// Suspension mode, timestamp, and deferral note column inside [_DraftSuspendedCard].
class _DraftSuspendedCardBody extends StatelessWidget {
  /// Creates a [_DraftSuspendedCardBody].
  const _DraftSuspendedCardBody({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final state = view.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _DraftSuspendedModeControl(
          indefinitely: state.suspendedIndefinitely,
          isBusy: state.isBusy,
          onModeChanged: view.callbacks.onSuspendedModeChanged,
        ),
        if (!state.suspendedIndefinitely) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          EntityHybridDateTimeField(
            controller: view.controllers.suspendedUntil,
            label: localizations.taskSuspendedUntilLabel,
            fallbackLocalDateTime: state.currentLocalDateTimeHint,
            enabled: !state.isBusy,
            errorText: state.fieldErrors['suspended'],
            onChanged: (_) => view.callbacks.onClearFieldError('suspended'),
          ),
        ],
        SizedBox(height: tokens.spacing.space2),
        _DraftSuspendedNoteField(view: view),
      ],
    );
  }
}

/// Timed versus indefinite suspension segmented control inside [_DraftSuspendedCardBody].
class _DraftSuspendedModeControl extends StatelessWidget {
  /// Creates a [_DraftSuspendedModeControl].
  const _DraftSuspendedModeControl({
    required this.indefinitely,
    required this.isBusy,
    required this.onModeChanged,
  });

  /// Whether indefinite suspension is selected.
  final bool indefinitely;

  /// Whether draft creation is currently in flight.
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

/// Deferral note multiline field hosted inside [_DraftSuspendedCardBody].
class _DraftSuspendedNoteField extends StatelessWidget {
  /// Creates a [_DraftSuspendedNoteField].
  const _DraftSuspendedNoteField({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      kind: UiFieldKind.multiline,
      controller: view.controllers.suspendedNote,
      label: localizations.taskSuspendedNoteLabel,
      hintText: localizations.taskSuspendedNoteHint,
      maxLength: _maxNoteLength,
      minLines: 2,
      maxLines: 4,
      enabled: !view.state.isBusy,
      errorText: view.state.fieldErrors['suspendedNote'],
      onChanged: (_) => view.callbacks.onClearFieldError('suspendedNote'),
    );
  }
}

/// Time-of-day condition dimension selector and time windows editor inside [_DraftConditionsControls].
class _DraftTimeConditionSection extends StatelessWidget {
  /// Creates a [_DraftTimeConditionSection].
  const _DraftTimeConditionSection({required this.view, required this.enabled});

  /// Whether time condition controls accept interaction.
  final bool enabled;

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final draft = view.state.conditionDraft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _DraftDimensionSelector(
          label: localizations.conditionTimeGroupTitle,
          mode: draft.timesMode,
          anyLabel: localizations.conditionTimeAnyLabel,
          enabled: enabled,
          onModeChanged: (mode) => view.callbacks.onConditionDraftChanged(
            draft.copyWith(timesMode: mode),
          ),
        ),
        if (draft.timesMode == ConditionDimensionMode.custom) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _DraftTimeWindowsEditor(view: view, enabled: enabled),
        ],
      ],
    );
  }
}

/// `HH:MM` start/end add bar hosted inside [_DraftTimeWindowsEditor].
class _DraftTimeWindowAddBar extends StatelessWidget {
  /// Creates a [_DraftTimeWindowAddBar].
  const _DraftTimeWindowAddBar({required this.view, required this.enabled});

  /// Whether inputs and add button accept interaction.
  final bool enabled;

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _DraftTimeWindowAddFields(view: view, enabled: enabled),
        if (view.state.timeInputError case final error?) ...<Widget>[
          SizedBox(height: tokens.spacing.space1),
          EntityInlineErrorText(message: error),
        ],
        SizedBox(height: tokens.spacing.space2),
        Align(
          alignment: Alignment.centerLeft,
          child: UiButton(
            label: localizations.tooltipAddTimeCondition,
            variant: UiButtonVariant.secondary,
            density: UiButtonDensity.compact,
            onPressed: enabled ? view.callbacks.onAddTimeWindow : null,
          ),
        ),
      ],
    );
  }
}

/// Responsive start and end `HH:MM` fields grid hosted inside [_DraftTimeWindowAddBar].
class _DraftTimeWindowAddFields extends StatelessWidget {
  /// Creates a [_DraftTimeWindowAddFields].
  const _DraftTimeWindowAddFields({required this.view, required this.enabled});

  /// Whether time inputs accept interaction.
  final bool enabled;

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    return UiResponsiveGrid(
      preset: UiGridPreset.twoColumnCompactCollapse,
      spacing: tokens.spacing.space2,
      runSpacing: tokens.spacing.space2,
      children: <Widget>[
        EntityHybridTimeField(
          controller: view.controllers.timeStart,
          hintText: localizations.conditionTimeStartHint,
          enabled: enabled,
        ),
        EntityHybridTimeField(
          controller: view.controllers.timeEnd,
          hintText: localizations.conditionTimeEndHint,
          enabled: enabled,
          onSubmitted: (_) => view.callbacks.onAddTimeWindow(),
        ),
      ],
    );
  }
}

/// Time windows list and `HH:MM` add bar hosted inside [_DraftTimeConditionSection].
class _DraftTimeWindowsEditor extends StatelessWidget {
  /// Creates a [_DraftTimeWindowsEditor].
  const _DraftTimeWindowsEditor({required this.view, required this.enabled});

  /// Whether inputs and buttons accept interaction.
  final bool enabled;

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiOrderedItemList<TimeWindowDraftViewModel>(
      items: view.state.conditionDraft.timeWindows,
      itemKey: (window, index) => ValueKey<String>(
        'draft_time_window_${index}_${window.start}_${window.end}',
      ),
      onDelete: enabled
          ? (window, index) => view.callbacks.onRemoveTimeWindow(index)
          : null,
      deleteTooltip: localizations.tooltipRemoveTimeCondition,
      itemBuilder: (context, window, index, isEditing) => Text(
        '${window.start} - ${window.end}',
        style: UiTypographyTokens.mono(
          tokens.typography.monoSmall.copyWith(color: tokens.colors.ink),
        ),
      ),
      addBar: _DraftTimeWindowAddBar(view: view, enabled: enabled),
    );
  }
}

/// Draft task title input hosted at the top of [_TaskDraftCardBody].
class _DraftTitleField extends StatelessWidget {
  /// Creates a [_DraftTitleField].
  const _DraftTitleField({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      key: const ValueKey<String>('task_draft_title_input'),
      kind: UiFieldKind.text,
      controller: view.controllers.title,
      hintText: localizations.taskNameLabel,
      maxLength: _maxSingleLineLength,
      autofocus: true,
      enabled: !view.state.isBusy,
      errorText: view.state.fieldErrors['title'],
      textInputAction: TextInputAction.done,
      onChanged: (_) => view.callbacks.onClearFieldError('title'),
      onSubmitted: (_) => view.callbacks.onSubmitTitle(),
    );
  }
}

/// Immutable snapshot of reactive draft form values passed down [TaskDraftCard].
@immutable
class _DraftViewState {
  /// Creates a [_DraftViewState].
  const _DraftViewState({
    required this.allLabels,
    required this.allLocations,
    required this.conditionDraft,
    required this.currentLocalDateTimeHint,
    required this.draftLinks,
    required this.dueAutoPrioritize,
    required this.editingLinkIndex,
    required this.fieldErrors,
    required this.hasBothScopedAndGlobalLabels,
    required this.isBusy,
    required this.isCompact,
    required this.isInlineLabelPickerOpen,
    required this.linkInputError,
    required this.openSections,
    required this.placement,
    required this.prerequisiteCandidates,
    required this.repeatUnit,
    required this.selectedLabelIds,
    required this.selectedPrerequisiteIds,
    required this.spacing,
    required this.subtaskRows,
    required this.subtasksAutoFinish,
    required this.suspendedIndefinitely,
    required this.timeInputError,
  });

  /// All workspace labels.
  final List<LabelPickerOptionViewModel> allLabels;

  /// All workspace locations.
  final List<LocationOptionViewModel> allLocations;

  /// Current condition draft model.
  final ConditionDraftViewModel conditionDraft;

  /// Current local timestamp hint.
  final String currentLocalDateTimeHint;

  /// Draft links list.
  final List<EntityLinkInput> draftLinks;

  /// Auto-prioritize near deadline flag.
  final bool dueAutoPrioritize;

  /// Active link index being edited inline.
  final int? editingLinkIndex;

  /// Per-field validation errors keyed by logical field name.
  final Map<String, String> fieldErrors;

  /// Whether both scoped and global labels exist.
  final bool hasBothScopedAndGlobalLabels;

  /// Whether commit is in flight.
  final bool isBusy;

  /// Whether viewport is compact (`<= 720`).
  final bool isCompact;

  /// Whether desktop inline label picker is expanded.
  final bool isInlineLabelPickerOpen;

  /// Inline validation error for link input row.
  final String? linkInputError;

  /// Open optional sections.
  final Set<TaskSectionKind> openSections;

  /// Selected placement mode.
  final TaskPlacementOption placement;

  /// Prerequisite candidate tasks.
  final List<PrerequisiteCandidateViewModel> prerequisiteCandidates;

  /// Selected repeat unit.
  final ShellRepeatUnit repeatUnit;

  /// Selected label identifiers.
  final Set<String> selectedLabelIds;

  /// Selected prerequisite task identifiers.
  final Set<String> selectedPrerequisiteIds;

  /// Vertical spacing between draft sections.
  final double spacing;

  /// Draft subtask rows.
  final List<EditableSubtaskRow> subtaskRows;

  /// Subtasks auto-finish flag.
  final bool subtasksAutoFinish;

  /// Whether indefinite suspension is chosen.
  final bool suspendedIndefinitely;

  /// Time window inline error.
  final String? timeInputError;
}

/// Selectable Mon..Sun weekday pills wrap hosted inside [_DraftDayConditionSection].
class _DraftWeekdaysWrap extends StatelessWidget {
  /// Creates a [_DraftWeekdaysWrap].
  const _DraftWeekdaysWrap({
    required this.selectedWeekdays,
    required this.enabled,
    required this.onToggleWeekday,
  });

  /// Whether weekday chips accept taps.
  final bool enabled;

  /// Callback toggling an ISO weekday (`1..7`).
  final ValueChanged<int> onToggleWeekday;

  /// Currently selected ISO weekdays.
  final List<int> selectedWeekdays;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final labels = <String>[
      localizations.weekdayMon,
      localizations.weekdayTue,
      localizations.weekdayWed,
      localizations.weekdayThu,
      localizations.weekdayFri,
      localizations.weekdaySat,
      localizations.weekdaySun,
    ];
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (var i = 0; i < labels.length; i++)
          UiPill(
            label: labels[i],
            variant: UiPillVariant.selectable,
            isSelected: selectedWeekdays.contains(i + 1),
            enabled: enabled,
            onPressed: enabled ? () => onToggleWeekday(i + 1) : null,
          ),
      ],
    );
  }
}

/// Composed vertical body of [TaskDraftCard] keeping [_TaskDraftCardState.build] concise.
class _TaskDraftCardBody extends StatelessWidget {
  /// Creates a [_TaskDraftCardBody].
  const _TaskDraftCardBody({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final state = view.state;
    final callbacks = view.callbacks;
    final showLabelsSection =
        state.selectedLabelIds.isNotEmpty ||
        (state.isInlineLabelPickerOpen && !state.isCompact);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _DraftTitleField(view: view),
        SizedBox(height: state.spacing),
        _DraftPlacementCard(
          placement: state.placement,
          isBusy: state.isBusy,
          onChanged: callbacks.onPlacementChanged,
        ),
        if (showLabelsSection) ...<Widget>[
          SizedBox(height: state.spacing),
          _DraftLabelsSection(view: view),
        ],
        _TaskDraftOptionalSections(view: view),
        SizedBox(height: state.spacing),
        _DraftAddSectionsBar(
          openSections: state.openSections,
          showLabelsChip: !showLabelsSection,
          isBusy: state.isBusy,
          onOpenLabels: () => callbacks.onOpenLabelPicker(state.isCompact),
          onOpenSection: callbacks.onOpenSection,
        ),
      ],
    );
  }
}

/// Manages uncommitted task draft controllers, optional sections, and commit flow for [TaskDraftCard].
class _TaskDraftCardState extends ConsumerState<TaskDraftCard> {
  late final _DraftCallbacks _callbacks;
  late final _DraftControllers _controllers;
  final Set<TaskSectionKind> _openSections = <TaskSectionKind>{};
  final Set<String> _selectedPrerequisiteIds = <String>{};
  final List<EditableSubtaskRow> _subtaskRows = <EditableSubtaskRow>[];

  ConditionDraftViewModel _conditionDraft = ConditionDraftViewModel();
  List<EntityLinkInput> _draftLinks = const <EntityLinkInput>[];
  bool _dueAutoPrioritize = true;
  int? _editingLinkIndex;
  Map<String, String> _fieldErrors = const <String, String>{};
  bool _isSubmitting = false;
  bool _labelPickerOpen = false;
  String? _linkInputError;
  int _nextSubtaskRowId = 1;
  late TaskPlacementOption _placement;
  ShellRepeatUnit _repeatUnit = ShellRepeatUnit.days;
  late Set<String> _selectedLabelIds;
  String? _submitError;
  bool _subtasksAutoFinish = false;
  bool _suspendedIndefinitely = false;
  String? _timeInputError;

  @override
  void initState() {
    super.initState();
    final shellState = ref.read(appShellControllerProvider);
    _placement = shellState.draftSeedPlacement;
    _selectedLabelIds = Set<String>.of(shellState.draftSeedLabelIds);
    _controllers = _DraftControllers(initialTitle: shellState.draftSeedTitle);
    _callbacks = _DraftCallbacks(
      onAddSubtask: _handleAddSubtask,
      onAddTimeWindow: _handleAddTimeWindow,
      onAutoFinishChanged: _handleAutoFinishChanged,
      onCancelLinkEdit: _handleCancelLinkEdit,
      onClearFieldError: _clearFieldError,
      onCloseLabelPicker: _handleCloseLabelPicker,
      onCloseSection: _handleCloseSection,
      onCommitLinkInput: _handleCommitLinkInput,
      onConditionDraftChanged: _handleConditionDraftChanged,
      onCreateAndAssignLabel: _triggerCreateAndAssignLabel,
      onDeleteLink: _handleDeleteLink,
      onDeleteSubtask: _handleDeleteSubtask,
      onDueAutoPrioritizeChanged: _handleDueAutoPrioritizeChanged,
      onDueChanged: _handleDueChanged,
      onOpenLabelInfo: _handleOpenLabelInfo,
      onOpenLabelPicker: _handleOpenLabelPicker,
      onOpenSection: _handleOpenSection,
      onPlacementChanged: _handlePlacementChanged,
      onRemoveTimeWindow: _handleRemoveTimeWindow,
      onReorderLinks: _handleReorderLinks,
      onReorderSubtasks: _handleReorderSubtasks,
      onRepeatUnitChanged: _handleRepeatUnitChanged,
      onStartEditLink: _handleStartEditLink,
      onSubmitTitle: _triggerCommit,
      onSuspendedModeChanged: _handleSuspendedModeChanged,
      onToggleLabel: _handleToggleLabel,
      onTogglePrerequisite: _handleTogglePrerequisite,
      onToggleSubtaskDone: _handleToggleSubtaskDone,
    );
  }

  @override
  void dispose() {
    _controllers.dispose();
    for (final row in _subtaskRows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final isControllerBusy = ref.watch(
      taskControllerProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;
    final prerequisiteCandidates =
        _openSections.contains(TaskSectionKind.prerequisites)
        ? ref.watch(taskPrerequisiteCandidatesProvider(null))
        : const <PrerequisiteCandidateViewModel>[];
    final view = _createDraftCardView(
      isBusy: isBusy,
      isCompact: isCompact,
      prerequisiteCandidates: prerequisiteCandidates,
      spacing: tokens.spacing.space3,
    );

    return UiCard.draft(
      key: const ValueKey<String>('task_draft_card'),
      title: localizations.draftNewTaskTitle,
      subtitle: localizations.draftUncommittedHint,
      errorText: _submitError,
      closeTooltip: localizations.actionCancel,
      onClose: isBusy ? null : _handleCancel,
      footer: _DraftFooter(
        isBusy: isBusy,
        onCancel: _handleCancel,
        onCreate: _triggerCommit,
      ),
      child: _TaskDraftCardBody(view: view),
    );
  }

  /// Clears [fieldKey] from [_fieldErrors] and resets [_submitError].
  void _clearFieldError(String fieldKey) {
    if (!_fieldErrors.containsKey(fieldKey) && _submitError == null) {
      return;
    }
    final nextErrors = Map<String, String>.of(_fieldErrors)..remove(fieldKey);
    setState(() {
      _fieldErrors = Map<String, String>.unmodifiable(nextErrors);
      _submitError = null;
    });
  }

  /// Builds the immutable [_DraftCardView] snapshot for the current render pass.
  _DraftCardView _createDraftCardView({
    required bool isBusy,
    required bool isCompact,
    required List<PrerequisiteCandidateViewModel> prerequisiteCandidates,
    required double spacing,
  }) {
    return _DraftCardView(
      callbacks: _callbacks,
      controllers: _controllers,
      state: _DraftViewState(
        allLabels: widget.allLabels,
        allLocations: widget.allLocations,
        conditionDraft: _conditionDraft,
        currentLocalDateTimeHint: widget.currentLocalDateTimeHint,
        draftLinks: _draftLinks,
        dueAutoPrioritize: _dueAutoPrioritize,
        editingLinkIndex: _editingLinkIndex,
        fieldErrors: _fieldErrors,
        hasBothScopedAndGlobalLabels: widget.hasBothScopedAndGlobalLabels,
        isBusy: isBusy,
        isCompact: isCompact,
        isInlineLabelPickerOpen: _labelPickerOpen,
        linkInputError: _linkInputError,
        openSections: _openSections,
        placement: _placement,
        prerequisiteCandidates: prerequisiteCandidates,
        repeatUnit: _repeatUnit,
        selectedLabelIds: _selectedLabelIds,
        selectedPrerequisiteIds: _selectedPrerequisiteIds,
        spacing: spacing,
        subtaskRows: _subtaskRows,
        subtasksAutoFinish: _subtasksAutoFinish,
        suspendedIndefinitely: _suspendedIndefinitely,
        timeInputError: _timeInputError,
      ),
    );
  }

  /// Appends a new editable subtask row and refocuses the new-subtask input.
  void _handleAddSubtask() {
    final trimmed = _controllers.newSubtask.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    setState(() {
      _subtaskRows.add(
        EditableSubtaskRow(
          rowId: _nextSubtaskRowId++,
          initialTitle: trimmed,
          isCompleted: false,
        ),
      );
      _controllers.newSubtask.clear();
      _submitError = null;
    });
    _clearFieldError('subtasks');
    _controllers.newSubtaskFocusNode.requestFocus();
  }

  /// Validates and appends a `HH:MM`..`HH:MM` window onto [_conditionDraft].
  void _handleAddTimeWindow() {
    final localizations = AppLocalizations.of(context);
    final startToken = _controllers.timeStart.text.trim();
    final endToken = _controllers.timeEnd.text.trim();
    final startMinutes = parseEntityTimeMinutes(startToken);
    final endMinutes = parseEntityTimeMinutes(endToken);
    if (startMinutes == null ||
        endMinutes == null ||
        startMinutes == endMinutes) {
      setState(() => _timeInputError = localizations.conditionTimeErrorInvalid);
      return;
    }
    setState(() {
      _conditionDraft = _conditionDraft.copyWith(
        timeWindows: <TimeWindowDraftViewModel>[
          ..._conditionDraft.timeWindows,
          TimeWindowDraftViewModel(start: startToken, end: endToken),
        ],
      );
      _controllers.timeStart.clear();
      _controllers.timeEnd.clear();
      _timeInputError = null;
      _submitError = null;
    });
    _clearFieldError('conditions');
  }

  /// Updates the subtasks auto-finish flag on the draft.
  void _handleAutoFinishChanged(bool value) {
    setState(() => _subtasksAutoFinish = value);
  }

  /// Cancels and discards this uncommitted task draft.
  void _handleCancel() {
    ref.read(appShellControllerProvider.notifier).cancelDraft();
  }

  /// Exits inline draft link editing and clears link inputs.
  void _handleCancelLinkEdit() {
    setState(() {
      _editingLinkIndex = null;
      _controllers.linkTitle.clear();
      _controllers.linkUri.clear();
      _linkInputError = null;
    });
  }

  /// Closes the desktop inline label picker inside the draft card.
  void _handleCloseLabelPicker() {
    setState(() => _labelPickerOpen = false);
  }

  /// Closes and resets an optional draft [section].
  void _handleCloseSection(TaskSectionKind section) {
    setState(() {
      _openSections.remove(section);
      _resetDraftSection(section);
    });
  }

  /// Validates and commits the entire draft via [TaskController.createTaskDraft].
  Future<void> _handleCommit() async {
    if (_isSubmitting) {
      return;
    }
    if (_openSections.contains(TaskSectionKind.links)) {
      final hasPendingLink =
          _controllers.linkTitle.text.trim().isNotEmpty ||
          _controllers.linkUri.text.trim().isNotEmpty;
      if (hasPendingLink && !_handleCommitLinkInput()) {
        return;
      }
    }
    final submittedSubtasks = <SubtaskInput>[
      if (_openSections.contains(TaskSectionKind.subtasks)) ...<SubtaskInput>[
        for (final row in _subtaskRows)
          SubtaskInput(
            title: row.controller.text,
            isCompleted: row.isCompleted,
          ),
        if (_controllers.newSubtask.text.trim().isNotEmpty)
          SubtaskInput(title: _controllers.newSubtask.text.trim()),
      ],
    ];
    final input = TaskDraftInput(
      title: _controllers.title.text,
      note: _openSections.contains(TaskSectionKind.note)
          ? _controllers.note.text
          : '',
      placement: _placement,
      labelIds: _selectedLabelIds,
      links: _openSections.contains(TaskSectionKind.links)
          ? _draftLinks
          : const <EntityLinkInput>[],
      subtasks: submittedSubtasks,
      subtasksAutoFinish:
          _openSections.contains(TaskSectionKind.subtasks) &&
          _subtasksAutoFinish,
      rawDue: _openSections.contains(TaskSectionKind.due)
          ? _controllers.due.text
          : '',
      autoPrioritizeDue: _dueAutoPrioritize,
      rawDueNote: _openSections.contains(TaskSectionKind.due)
          ? _controllers.dueNote.text
          : '',
      isRepeating: _openSections.contains(TaskSectionKind.repeat),
      rawRepeatCount: _controllers.repeatCount.text,
      repeatUnit: _repeatUnit,
      rawRepeatLeadDays: _controllers.repeatLeadDays.text,
      isSuspended: _openSections.contains(TaskSectionKind.suspended),
      suspendedIndefinitely: _suspendedIndefinitely,
      rawSuspendedUntil: _controllers.suspendedUntil.text,
      rawSuspendedNote: _controllers.suspendedNote.text,
      prerequisiteTaskIds: _openSections.contains(TaskSectionKind.prerequisites)
          ? _selectedPrerequisiteIds
          : const <String>[],
      conditionDraft: _openSections.contains(TaskSectionKind.conditions)
          ? _conditionDraft
          : null,
    );

    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _fieldErrors = const <String, String>{};
    });
    final result = await ref
        .read(taskControllerProvider.notifier)
        .createTaskDraft(input, locale: Localizations.localeOf(context));
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _fieldErrors = fieldErrors;
          _submitError = message;
        });
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Validates and appends/updates the link currently typed into the draft link fields.
  bool _handleCommitLinkInput() {
    final editingIndex = _editingLinkIndex;
    final error = TaskController.validateLinkInput(
      rawTitle: _controllers.linkTitle.text,
      rawUri: _controllers.linkUri.text,
      currentCount: _draftLinks.length,
      isEditingExisting: editingIndex != null,
      isLabel: false,
      locale: Localizations.localeOf(context),
    );
    if (error != null) {
      setState(() => _linkInputError = error);
      return false;
    }
    final nextLink = EntityLinkInput(
      title: _controllers.linkTitle.text.trim(),
      uri: _controllers.linkUri.text.trim(),
    );
    final nextLinks = List<EntityLinkInput>.of(_draftLinks);
    if (editingIndex != null &&
        editingIndex >= 0 &&
        editingIndex < nextLinks.length) {
      nextLinks[editingIndex] = nextLink;
    } else {
      nextLinks.add(nextLink);
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingLinkIndex = null;
      _controllers.linkTitle.clear();
      _controllers.linkUri.clear();
      _linkInputError = null;
      _submitError = null;
    });
    _clearFieldError('links');
    return true;
  }

  /// Updates [_conditionDraft] when condition controls change.
  void _handleConditionDraftChanged(ConditionDraftViewModel nextDraft) {
    setState(() => _conditionDraft = nextDraft);
    _clearFieldError('conditions');
  }

  /// Creates a new workspace label from [rawName] and selects it on this draft.
  Future<void> _handleCreateAndAssignLabel(String rawName) async {
    final locale = Localizations.localeOf(context);
    final result = await ref
        .read(entityControllerProvider.notifier)
        .quickCreateLabel(rawName, locale: locale);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded(:final entityId):
        if (entityId != null) {
          final shell = ref.read(appShellControllerProvider);
          if (shell.expandedEntity ==
              EntityRef(kind: EntityKind.label, id: entityId)) {
            ref.read(appShellControllerProvider.notifier).collapseEntity();
          }
          setState(() {
            _selectedLabelIds = <String>{..._selectedLabelIds, entityId};
          });
        }
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() => _submitError = message);
    }
  }

  /// Removes a link row at [index] from [_draftLinks].
  void _handleDeleteLink(EntityLinkInput link, int index) {
    if (index < 0 || index >= _draftLinks.length) {
      return;
    }
    final nextLinks = List<EntityLinkInput>.of(_draftLinks)..removeAt(index);
    var nextEditing = _editingLinkIndex;
    if (nextEditing == index) {
      nextEditing = null;
      _controllers.linkTitle.clear();
      _controllers.linkUri.clear();
    } else if (nextEditing != null && nextEditing > index) {
      nextEditing -= 1;
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingLinkIndex = nextEditing;
      _linkInputError = null;
    });
  }

  /// Removes and disposes a subtask row at [index].
  void _handleDeleteSubtask(EditableSubtaskRow row, int index) {
    if (index < 0 || index >= _subtaskRows.length) {
      return;
    }
    final removed = _subtaskRows.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  /// Updates the due auto-prioritize flag on the draft.
  void _handleDueAutoPrioritizeChanged(bool value) {
    setState(() => _dueAutoPrioritize = value);
  }

  /// Clears due validation errors and refreshes lead-days gating when due text changes.
  void _handleDueChanged(String _) {
    _clearFieldError('due');
    setState(() {});
  }

  /// Opens [labelId] inside Labels manager preserving `returnContext`.
  void _handleOpenLabelInfo(String labelId) {
    ref
        .read(appShellControllerProvider.notifier)
        .openEntityInManager(
          EntityRef(kind: EntityKind.label, id: labelId),
          preserveReturnContext: true,
        );
  }

  /// Opens the inline label picker on desktop or the compact bottom sheet on mobile.
  void _handleOpenLabelPicker(bool isCompact) {
    if (!isCompact) {
      setState(() => _labelPickerOpen = true);
      return;
    }
    final localizations = AppLocalizations.of(context);
    unawaited(
      showCompactLabelPickerSheet(
        context,
        title: localizations.taskLabelsSectionTitle,
        allLabels: widget.allLabels,
        hasBothScopedAndGlobal: widget.hasBothScopedAndGlobalLabels,
        selectedIds: Set<String>.of(_selectedLabelIds),
        onToggleLabel: _handleToggleLabel,
        onCreateAndAssign: _triggerCreateAndAssignLabel,
        onOpenLabelInfo: _handleOpenLabelInfo,
      ),
    );
  }

  /// Reveals optional draft [section].
  void _handleOpenSection(TaskSectionKind section) {
    setState(() => _openSections.add(section));
  }

  /// Updates the draft placement selection.
  void _handlePlacementChanged(TaskPlacementOption nextPlacement) {
    setState(() => _placement = nextPlacement);
  }

  /// Removes the condition time window at [index].
  void _handleRemoveTimeWindow(int index) {
    if (index < 0 || index >= _conditionDraft.timeWindows.length) {
      return;
    }
    final nextWindows = List<TimeWindowDraftViewModel>.of(
      _conditionDraft.timeWindows,
    )..removeAt(index);
    setState(() {
      _conditionDraft = _conditionDraft.copyWith(timeWindows: nextWindows);
    });
  }

  /// Reorders [_draftLinks] from [oldIndex] to [newIndex].
  void _handleReorderLinks(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _draftLinks.length ||
        newIndex < 0 ||
        newIndex >= _draftLinks.length ||
        oldIndex == newIndex) {
      return;
    }
    final nextLinks = List<EntityLinkInput>.of(_draftLinks);
    final moved = nextLinks.removeAt(oldIndex);
    nextLinks.insert(newIndex, moved);
    setState(() => _draftLinks = nextLinks);
  }

  /// Reorders [_subtaskRows] from [oldIndex] to [newIndex].
  void _handleReorderSubtasks(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _subtaskRows.length ||
        newIndex < 0 ||
        newIndex >= _subtaskRows.length ||
        oldIndex == newIndex) {
      return;
    }
    final moved = _subtaskRows.removeAt(oldIndex);
    _subtaskRows.insert(newIndex, moved);
    setState(() {});
  }

  /// Updates the recurrence unit on the draft.
  void _handleRepeatUnitChanged(ShellRepeatUnit nextUnit) {
    setState(() => _repeatUnit = nextUnit);
  }

  /// Loads an existing draft link row into the inline edit inputs.
  void _handleStartEditLink(EntityLinkInput link, int index) {
    setState(() {
      _editingLinkIndex = index;
      _controllers.linkTitle.text = link.title;
      _controllers.linkUri.text = link.uri;
      _linkInputError = null;
    });
  }

  /// Switches between timed and indefinite suspension on the draft.
  void _handleSuspendedModeChanged(bool indefinitely) {
    setState(() => _suspendedIndefinitely = indefinitely);
    _clearFieldError('suspended');
  }

  /// Toggles assignment of [labelId] on the draft.
  void _handleToggleLabel(String labelId) {
    final next = Set<String>.of(_selectedLabelIds);
    if (!next.add(labelId)) {
      next.remove(labelId);
    }
    setState(() => _selectedLabelIds = next);
  }

  /// Toggles selection of prerequisite [taskId] on the draft.
  void _handleTogglePrerequisite(String taskId) {
    setState(() {
      if (!_selectedPrerequisiteIds.add(taskId)) {
        _selectedPrerequisiteIds.remove(taskId);
      }
    });
    _clearFieldError('prerequisites');
  }

  /// Toggles completion state of subtask row [index].
  void _handleToggleSubtaskDone(int index) {
    if (index < 0 || index >= _subtaskRows.length) {
      return;
    }
    setState(() {
      _subtaskRows[index].isCompleted = !_subtaskRows[index].isCompleted;
    });
  }

  /// Clears stored state for closed optional draft [section].
  void _resetDraftSection(TaskSectionKind section) {
    switch (section) {
      case TaskSectionKind.title || TaskSectionKind.labels:
        return;
      case TaskSectionKind.note:
        _controllers.note.clear();
      case TaskSectionKind.links:
        _draftLinks = const <EntityLinkInput>[];
        _editingLinkIndex = null;
        _controllers.linkTitle.clear();
        _controllers.linkUri.clear();
        _linkInputError = null;
      case TaskSectionKind.subtasks:
        for (final row in _subtaskRows) {
          row.dispose();
        }
        _subtaskRows.clear();
        _controllers.newSubtask.clear();
        _subtasksAutoFinish = false;
      case TaskSectionKind.due:
        _controllers.due.clear();
        _controllers.dueNote.clear();
        _dueAutoPrioritize = true;
      case TaskSectionKind.repeat:
        _controllers.repeatCount.text = '1';
        _repeatUnit = ShellRepeatUnit.days;
        _controllers.repeatLeadDays.text = '0';
      case TaskSectionKind.suspended:
        _suspendedIndefinitely = false;
        _controllers.suspendedUntil.clear();
        _controllers.suspendedNote.clear();
      case TaskSectionKind.prerequisites:
        _selectedPrerequisiteIds.clear();
      case TaskSectionKind.conditions:
        _conditionDraft = ConditionDraftViewModel();
        _controllers.timeStart.clear();
        _controllers.timeEnd.clear();
        _timeInputError = null;
    }
  }

  /// Dispatches async draft commit from synchronous UI callbacks.
  void _triggerCommit() {
    unawaited(_handleCommit());
  }

  /// Dispatches async label creation from synchronous picker callbacks.
  void _triggerCreateAndAssignLabel(String rawName) {
    unawaited(_handleCreateAndAssignLabel(rawName));
  }
}

/// Optional toggleable sections list inside [_TaskDraftCardBody].
class _TaskDraftOptionalSections extends StatelessWidget {
  /// Creates a [_TaskDraftOptionalSections].
  const _TaskDraftOptionalSections({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final state = view.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final section in _draftOptionalSectionOrder)
          if (state.openSections.contains(section)) ...<Widget>[
            SizedBox(height: state.spacing),
            _DraftOptionalSectionCard(section: section, view: view),
          ],
      ],
    );
  }
}

/// Returns the outline icon for an optional draft section `+ Add` chip.
IconData _draftAddSectionIcon(TaskSectionKind section) {
  return switch (section) {
    TaskSectionKind.title => Icons.edit_outlined,
    TaskSectionKind.note => Icons.description_outlined,
    TaskSectionKind.links => Icons.link_rounded,
    TaskSectionKind.subtasks => Icons.checklist_rounded,
    TaskSectionKind.labels => Icons.label_outline_rounded,
    TaskSectionKind.due => Icons.calendar_today_outlined,
    TaskSectionKind.repeat => Icons.repeat_rounded,
    TaskSectionKind.suspended => Icons.pause_circle_outline_rounded,
    TaskSectionKind.prerequisites => Icons.lock_outline_rounded,
    TaskSectionKind.conditions => Icons.tune_rounded,
  };
}

/// Returns the localized `+ Add` chip label for optional draft [section].
String _draftAddSectionLabel(
  TaskSectionKind section,
  AppLocalizations localizations,
) {
  return switch (section) {
    TaskSectionKind.title => localizations.inlineEditTitleTooltip,
    TaskSectionKind.note => localizations.inlineAddNote,
    TaskSectionKind.links => localizations.inlineAddLinks,
    TaskSectionKind.subtasks => localizations.inlineAddSubtasks,
    TaskSectionKind.labels => localizations.inlineAddLabels,
    TaskSectionKind.due => localizations.inlineAddDue,
    TaskSectionKind.repeat => localizations.inlineAddRepeat,
    TaskSectionKind.suspended => localizations.inlineAddSuspend,
    TaskSectionKind.prerequisites => localizations.inlineAddPrerequisites,
    TaskSectionKind.conditions => localizations.inlineAddConditions,
  };
}

/// Parses a serialized [ConditionDimensionMode] name safely without unchecked casts.
ConditionDimensionMode? _parseConditionDimensionMode(String value) {
  for (final mode in ConditionDimensionMode.values) {
    if (mode.name == value) {
      return mode;
    }
  }
  return null;
}

/// Returns the localized helper caption for [placement].
String _placementHint(
  TaskPlacementOption placement,
  AppLocalizations localizations,
) {
  return switch (placement) {
    TaskPlacementOption.queue => localizations.placementQueueHint,
    TaskPlacementOption.priority => localizations.placementPriorityHint,
    TaskPlacementOption.someday => localizations.placementSomedayHint,
  };
}

/// Resolves an optional ARGB label color integer, falling back to `tokens.colors.accent`.
Color _resolveColorDot(int? colorValue, UiThemeTokens tokens) {
  return switch (colorValue) {
    final value? => Color(value),
    null => tokens.colors.accent,
  };
}

/// Collects [LabelPickerOptionViewModel] entries whose IDs exist in [selectedIds].
List<LabelPickerOptionViewModel> _resolveSelectedLabels(
  List<LabelPickerOptionViewModel> allLabels,
  Set<String> selectedIds,
) {
  return <LabelPickerOptionViewModel>[
    for (final option in allLabels)
      if (selectedIds.contains(option.id)) option,
  ];
}
