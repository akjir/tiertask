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
import '../../models/tdf_location.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/board_actions_provider.dart';
import '../../providers/board_providers.dart';
import '../../providers/entity_actions_provider.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../components/ui_ordered_item_list.dart';
import '../dialogs/compact_label_picker_sheet.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_pill.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../widgets/entity_card_chrome.dart';
import '../widgets/entity_conditions_section.dart';
import '../widgets/entity_date_time_fields.dart';
import '../widgets/entity_label_picker.dart';
import '../widgets/entity_links_section.dart';
import 'task_detail_editors.dart';
import 'task_schedule_editors.dart';

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

/// Uncommitted accent-bordered Task Draft Card (`U-CARD-006`) allowing full task
/// configuration before committing to the `.tdf` document via [BoardActionsNotifier.createTaskDraft].
class TaskDraftCard extends ConsumerStatefulWidget {
  /// Creates a [TaskDraftCard].
  const TaskDraftCard({
    super.key,
    required this.allLabels,
    required this.allLocations,
    required this.openLabelCounts,
    required this.currentLocalDateTimeHint,
  });

  /// Workspace labels available in the searchable label picker.
  final List<TdfLabel> allLabels;

  /// Workspace locations available in the GPS conditions selector.
  final List<TdfLocation> allLocations;

  /// Current workspace local wall-clock timestamp (`YYYY-MM-DD HH:MM`) seeding pickers.
  final String currentLocalDateTimeHint;

  /// Open task counts keyed by label identifier for the searchable label picker.
  final Map<String, int> openLabelCounts;

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
  final ValueChanged<ConditionDraft> onConditionDraftChanged;

  /// Callback creating and assigning a new label.
  final ValueChanged<String> onCreateAndAssignLabel;

  /// Callback deleting a draft link row.
  final UiOrderedItemActionCallback<TaskLink> onDeleteLink;

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
  final ValueChanged<QuickAddMode> onPlacementChanged;

  /// Callback removing a condition time window.
  final ValueChanged<int> onRemoveTimeWindow;

  /// Callback reordering draft links.
  final UiOrderedItemReorderCallback onReorderLinks;

  /// Callback reordering draft subtasks.
  final UiOrderedItemReorderCallback onReorderSubtasks;

  /// Callback changing recurrence unit.
  final ValueChanged<RepeatUnit> onRepeatUnitChanged;

  /// Callback starting inline link row edit.
  final UiOrderedItemActionCallback<TaskLink> onStartEditLink;

  /// Callback submitting draft on `Enter` in title input.
  final VoidCallback onSubmitTitle;

  /// Callback switching timed versus indefinite suspension.
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

/// Body column hosted inside [_DraftConditionsCard] delegating to [EntityConditionsEditorBody].
class _DraftConditionsBody extends StatelessWidget {
  /// Creates a [_DraftConditionsBody].
  const _DraftConditionsBody({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final state = view.state;
    final callbacks = view.callbacks;
    return _DraftSectionErrorHost(
      errorText: state.fieldErrors['conditions'],
      child: EntityConditionsEditorBody(
        isTask: true,
        isSuspended: view.isSuspendedOpen,
        draft: state.conditionDraft,
        allLocations: state.allLocations,
        timeStartController: view.controllers.timeStart,
        timeEndController: view.controllers.timeEnd,
        timeInputError: state.timeInputError,
        enabled: !state.isBusy,
        onToggleIgnoreAll: _toggleIgnoreAll,
        onDaysModeChanged: _setDaysMode,
        onToggleWeekday: _toggleWeekday,
        onTimesModeChanged: _setTimesMode,
        onAddTimeWindow: callbacks.onAddTimeWindow,
        onRemoveTimeWindow: (window, index) =>
            callbacks.onRemoveTimeWindow(index),
        onLocationsModeChanged: _setLocationsMode,
        onToggleLocation: _toggleLocation,
      ),
    );
  }

  /// Updates the weekday condition dimension [mode] on the draft.
  void _setDaysMode(ConditionDimensionMode mode) {
    view.callbacks.onConditionDraftChanged(
      view.state.conditionDraft.copyWith(daysMode: mode),
    );
  }

  /// Updates the GPS locations condition dimension [mode] on the draft.
  void _setLocationsMode(ConditionDimensionMode mode) {
    view.callbacks.onConditionDraftChanged(
      view.state.conditionDraft.copyWith(locationMode: mode),
    );
  }

  /// Updates the time-window condition dimension [mode] on the draft.
  void _setTimesMode(ConditionDimensionMode mode) {
    view.callbacks.onConditionDraftChanged(
      view.state.conditionDraft.copyWith(timeMode: mode),
    );
  }

  /// Toggles task-level `ignoreAllLabelConditions` on the draft.
  void _toggleIgnoreAll(bool value) {
    view.callbacks.onConditionDraftChanged(
      view.state.conditionDraft.copyWith(ignoreAllLabelConditions: value),
    );
  }

  /// Toggles [locationId] inside the draft condition locations list.
  void _toggleLocation(String locationId) {
    final draft = view.state.conditionDraft;
    final nextIds = List<String>.of(draft.locationIds);
    if (!nextIds.remove(locationId)) {
      nextIds.add(locationId);
    }
    view.callbacks.onConditionDraftChanged(
      draft.copyWith(locationIds: nextIds),
    );
  }

  /// Toggles ISO weekday [weekday] (`1..7`) inside the draft condition weekdays.
  void _toggleWeekday(int weekday) {
    final draft = view.state.conditionDraft;
    final nextDays = List<int>.of(draft.weekdays);
    if (!nextDays.remove(weekday)) {
      nextDays.add(weekday);
      nextDays.sort();
    }
    view.callbacks.onConditionDraftChanged(draft.copyWith(weekdays: nextDays));
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

/// Optional Due date section hosted inside [TaskDraftCard].
class _DraftDueCard extends StatelessWidget {
  /// Creates a [_DraftDueCard].
  const _DraftDueCard({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = view.state;
    final callbacks = view.callbacks;

    return UiCard.inset(
      key: const ValueKey<String>('draft_due_card'),
      headerIcon: Icons.calendar_today_outlined,
      headerTitle: localizations.taskInfoDueLabel,
      headerTrailing: _DraftSectionCloseButton(
        isBusy: state.isBusy,
        onClose: () => callbacks.onCloseSection(TaskSectionKind.due),
      ),
      child: TaskDueFields(
        dueController: view.controllers.due,
        dueNoteController: view.controllers.dueNote,
        autoPrioritize: state.dueAutoPrioritize,
        currentLocalDateTimeHint: state.currentLocalDateTimeHint,
        dueError: state.fieldErrors['due'],
        dueNoteError: state.fieldErrors['dueNote'],
        isBusy: state.isBusy,
        onDueChanged: callbacks.onDueChanged,
        onDueNoteChanged: (_) => callbacks.onClearFieldError('dueNote'),
        onAutoPrioritizeChanged: callbacks.onDueAutoPrioritizeChanged,
      ),
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
        density: UiButtonDensity.compact,
        onPressed: callbacks.onCloseLabelPicker,
      ),
      child: EntitySearchableLabelPicker(
        allLabels: state.allLabels,
        selectedIds: state.selectedLabelIds,
        openCountsByLabelId: state.openLabelCounts,
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

    final selectedLabels = _resolveSelectedLabels(
      state.allLabels,
      state.selectedLabelIds,
    );
    if (selectedLabels.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DraftLabelsSummaryCard(view: view, selectedLabels: selectedLabels);
  }
}

/// Selected draft label pills summary card hosted inside [_DraftLabelsSection].
class _DraftLabelsSummaryCard extends StatelessWidget {
  /// Creates a [_DraftLabelsSummaryCard].
  const _DraftLabelsSummaryCard({
    required this.view,
    required this.selectedLabels,
  });

  /// Resolved domain labels currently assigned to the draft.
  final List<TdfLabel> selectedLabels;

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
        label: '${selectedLabels.length}',
        variant: UiPillVariant.count,
      ),
      child: _DraftSelectedLabelsWrap(
        view: view,
        selectedLabels: selectedLabels,
      ),
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
        label: '${view.state.draftLinks.length} / $maxTdfLinksPerTask',
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
    final state = view.state;
    final callbacks = view.callbacks;
    return _DraftSectionErrorHost(
      errorText: state.fieldErrors['links'],
      child: EntityLinksEditorBody(
        links: state.draftLinks,
        editingIndex: state.editingLinkIndex,
        titleController: view.controllers.linkTitle,
        uriController: view.controllers.linkUri,
        inputErrorText: state.linkInputError,
        enabled: !state.isBusy,
        itemKeyPrefix: 'draft_link',
        onReorder: callbacks.onReorderLinks,
        onStartRowEdit: callbacks.onStartEditLink,
        onDeleteRow: callbacks.onDeleteLink,
        onCommitLink: callbacks.onCommitLinkInput,
        onCancelRowEdit: callbacks.onCancelLinkEdit,
      ),
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
        maxLength: maxTdfNoteLength,
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
    final state = view.state;
    return _DraftSectionErrorHost(
      errorText: state.fieldErrors['prerequisites'],
      child: TaskPrerequisitesPickerBody(
        candidates: state.prerequisiteCandidates,
        selectedIds: state.selectedPrerequisiteIds,
        isBusy: state.isBusy,
        showDescription: false,
        autoFocusSearch: false,
        onToggleOption: view.callbacks.onTogglePrerequisite,
      ),
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
    final state = view.state;
    final callbacks = view.callbacks;

    return UiCard.inset(
      key: const ValueKey<String>('draft_repeat_card'),
      headerIcon: Icons.repeat_rounded,
      headerTitle: localizations.repeatFlagLabel,
      headerTrailing: _DraftSectionCloseButton(
        isBusy: state.isBusy,
        onClose: () => callbacks.onCloseSection(TaskSectionKind.repeat),
      ),
      child: TaskRepeatFields(
        countController: view.controllers.repeatCount,
        unit: state.repeatUnit,
        leadDaysController: view.controllers.repeatLeadDays,
        hasDueDate: view.hasDueDate,
        countError: state.fieldErrors['repeatCount'],
        leadError: state.fieldErrors['repeatLeadDays'],
        isBusy: state.isBusy,
        onCountChanged: (_) => callbacks.onClearFieldError('repeatCount'),
        onLeadDaysChanged: (_) => callbacks.onClearFieldError('repeatLeadDays'),
        onUnitChanged: callbacks.onRepeatUnitChanged,
      ),
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

/// Wraps an optional draft section body with an inline validation error message when present.
class _DraftSectionErrorHost extends StatelessWidget {
  /// Creates a [_DraftSectionErrorHost].
  const _DraftSectionErrorHost({required this.errorText, required this.child});

  /// Section body widget rendered above the optional error line.
  final Widget child;

  /// Optional section-level validation error message.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final error = errorText;
    if (error == null) {
      return child;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        child,
        SizedBox(height: UiThemeTokens.of(context).spacing.space2),
        EntityInlineErrorText(message: error),
      ],
    );
  }
}

/// Wrap of selected draft label split chips and `+ Add` trigger inside [_DraftLabelsSummaryCard].
class _DraftSelectedLabelsWrap extends StatelessWidget {
  /// Creates a [_DraftSelectedLabelsWrap].
  const _DraftSelectedLabelsWrap({
    required this.view,
    required this.selectedLabels,
  });

  /// Resolved domain labels currently assigned to the draft.
  final List<TdfLabel> selectedLabels;

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
        for (final label in selectedLabels)
          UiPill(
            label: label.name,
            variant: UiPillVariant.splitChip,
            colorDot: _resolveColorDot(
              TaskScheduleHelper.parseLabelColorValue(label.color),
              tokens,
            ),
            removeTooltip: localizations.labelPickerRemoveTooltip(label.name),
            enabled: !state.isBusy,
            onRemove: state.isBusy
                ? null
                : () => callbacks.onToggleLabel(label.id),
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
    final state = view.state;
    final callbacks = view.callbacks;
    return _DraftSectionErrorHost(
      errorText: state.fieldErrors['subtasks'],
      child: TaskSubtasksEditorBody(
        rows: state.subtaskRows,
        newStepController: view.controllers.newSubtask,
        newStepFocusNode: view.controllers.newSubtaskFocusNode,
        autoFinish: state.subtasksAutoFinish,
        isBusy: state.isBusy,
        itemKeyPrefix: 'draft_subtask_row',
        addInputKey: const ValueKey<String>('draft_subtask_add_input'),
        onReorder: callbacks.onReorderSubtasks,
        onToggleRowDone: callbacks.onToggleSubtaskDone,
        onDeleteRow: callbacks.onDeleteSubtask,
        onAddRow: callbacks.onAddSubtask,
        onAutoFinishChanged: callbacks.onAutoFinishChanged,
      ),
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
    final state = view.state;
    final callbacks = view.callbacks;

    return UiCard.inset(
      key: const ValueKey<String>('draft_suspended_card'),
      headerIcon: Icons.pause_circle_outline_rounded,
      headerTitle: localizations.taskSuspendedLabel,
      headerTrailing: _DraftSectionCloseButton(
        isBusy: state.isBusy,
        onClose: () => callbacks.onCloseSection(TaskSectionKind.suspended),
      ),
      child: TaskSuspendedFields(
        indefinitely: state.suspendedIndefinitely,
        untilController: view.controllers.suspendedUntil,
        noteController: view.controllers.suspendedNote,
        currentLocalDateTimeHint: state.currentLocalDateTimeHint,
        untilError: state.fieldErrors['suspended'],
        noteError: state.fieldErrors['suspendedNote'],
        isBusy: state.isBusy,
        onModeChanged: callbacks.onSuspendedModeChanged,
        onUntilChanged: (_) => callbacks.onClearFieldError('suspended'),
        onNoteChanged: (_) => callbacks.onClearFieldError('suspendedNote'),
      ),
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
      controller: view.controllers.title,
      hintText: localizations.taskNameLabel,
      maxLength: maxTdfTextLength,
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
    required this.isBusy,
    required this.isCompact,
    required this.isInlineLabelPickerOpen,
    required this.linkInputError,
    required this.openLabelCounts,
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
  final List<TdfLabel> allLabels;

  /// All workspace locations.
  final List<TdfLocation> allLocations;

  /// Current condition draft model.
  final ConditionDraft conditionDraft;

  /// Current local timestamp hint.
  final String currentLocalDateTimeHint;

  /// Draft links list.
  final List<TaskLink> draftLinks;

  /// Auto-prioritize near deadline flag.
  final bool dueAutoPrioritize;

  /// Active link index being edited inline.
  final int? editingLinkIndex;

  /// Per-field validation errors keyed by logical field name.
  final Map<String, String> fieldErrors;

  /// Whether commit is in flight.
  final bool isBusy;

  /// Whether viewport is compact (`<= 720`).
  final bool isCompact;

  /// Whether desktop inline label picker is expanded.
  final bool isInlineLabelPickerOpen;

  /// Inline validation error for link input row.
  final String? linkInputError;

  /// Open task counts keyed by label identifier.
  final Map<String, int> openLabelCounts;

  /// Open optional sections.
  final Set<TaskSectionKind> openSections;

  /// Selected placement mode.
  final QuickAddMode placement;

  /// Prerequisite candidate tasks.
  final List<PrerequisiteCandidate> prerequisiteCandidates;

  /// Selected repeat unit.
  final RepeatUnit repeatUnit;

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

/// Composed vertical body of [TaskDraftCard] keeping [_TaskDraftCardState.build] concise.
class _TaskDraftCardBody extends StatelessWidget {
  /// Creates a [_TaskDraftCardBody].
  const _TaskDraftCardBody({required this.view});

  /// Shared draft card controllers, callbacks, and state snapshot.
  final _DraftCardView view;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
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
        TaskPlacementCard(
          cardKey: const ValueKey<String>('draft_placement_card'),
          placement: state.placement,
          isBusy: state.isBusy,
          caption: _placementHint(state.placement, localizations),
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
  final List<EditableSubtaskRow> _pendingDisposals = <EditableSubtaskRow>[];
  final Set<String> _selectedPrerequisiteIds = <String>{};
  final List<EditableSubtaskRow> _subtaskRows = <EditableSubtaskRow>[];

  ConditionDraft _conditionDraft = ConditionDraft();
  List<TaskLink> _draftLinks = const <TaskLink>[];
  bool _dueAutoPrioritize = true;
  int? _editingLinkIndex;
  Map<String, String> _fieldErrors = const <String, String>{};
  bool _isDisposalScheduled = false;
  bool _isSubmitting = false;
  bool _labelPickerOpen = false;
  String? _linkInputError;
  int _nextSubtaskRowId = 1;
  late QuickAddMode _placement;
  RepeatUnit _repeatUnit = RepeatUnit.days;
  late Set<String> _selectedLabelIds;
  String? _submitError;
  bool _subtasksAutoFinish = false;
  bool _suspendedIndefinitely = false;
  String? _timeInputError;

  @override
  void initState() {
    super.initState();
    final shellState = ref.read(shellProvider);
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
    _flushPendingDisposals();
    _controllers.dispose();
    for (final row in _subtaskRows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<_DraftSeedSnapshot>(
      shellProvider.select(_selectDraftSeed),
      _handleDraftSeedChanged,
    );
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final isBusy =
        _isSubmitting ||
        ref.watch(boardActionsProvider.select((state) => state.isBusy));
    final prerequisiteCandidates =
        _openSections.contains(TaskSectionKind.prerequisites)
        ? ref.watch(taskPrerequisiteCandidatesProvider(null))
        : const <PrerequisiteCandidate>[];
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
    required List<PrerequisiteCandidate> prerequisiteCandidates,
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
        isBusy: isBusy,
        isCompact: isCompact,
        isInlineLabelPickerOpen: _labelPickerOpen,
        linkInputError: _linkInputError,
        openLabelCounts: widget.openLabelCounts,
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

  /// Queues a removed [row] for post-frame disposal after its draft field detaches.
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

  /// Disposes all queued draft subtask row controllers after the frame or during unmount.
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
        timeWindows: <TimeWindowDraft>[
          ..._conditionDraft.timeWindows,
          TimeWindowDraft(start: startToken, end: endToken),
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
    ref.read(shellProvider.notifier).cancelDraft();
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

  /// Validates and commits the entire draft via [BoardActionsNotifier.createTaskDraft].
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
    final submittedSubtasks = <SubtaskItem>[
      if (_openSections.contains(TaskSectionKind.subtasks)) ...<SubtaskItem>[
        for (final row in _subtaskRows)
          SubtaskItem(title: row.controller.text, isCompleted: row.isCompleted),
        if (_controllers.newSubtask.text.trim().isNotEmpty)
          SubtaskItem(title: _controllers.newSubtask.text.trim()),
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
          : const <TaskLink>[],
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
      conditions: _openSections.contains(TaskSectionKind.conditions)
          ? _conditionDraft
          : null,
    );

    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _fieldErrors = const <String, String>{};
    });
    try {
      final result = await ref
          .read(boardActionsProvider.notifier)
          .createTaskDraft(input, locale: Localizations.localeOf(context));
      if (!mounted) {
        return;
      }
      switch (result) {
        case ActionSucceeded():
          break;
        case ActionValidationFailed(:final message, :final fieldErrors):
          setState(() {
            _fieldErrors = fieldErrors;
            _submitError = message;
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

  /// Validates and appends/updates the link currently typed into the draft link fields.
  bool _handleCommitLinkInput() {
    final editingIndex = _editingLinkIndex;
    final error = TaskScheduleHelper.validateLinkInput(
      rawTitle: _controllers.linkTitle.text,
      rawUri: _controllers.linkUri.text,
      currentCount: _draftLinks.length,
      localizations: AppLocalizations.of(context),
      isEditingExisting: editingIndex != null,
    );
    if (error != null) {
      setState(() => _linkInputError = error);
      return false;
    }
    final nextLink = TaskLink(
      title: _controllers.linkTitle.text.trim(),
      uri: _controllers.linkUri.text.trim(),
    );
    final nextLinks = List<TaskLink>.of(_draftLinks);
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
  void _handleConditionDraftChanged(ConditionDraft nextDraft) {
    setState(() => _conditionDraft = nextDraft);
    _clearFieldError('conditions');
  }

  /// Creates a new workspace label from [rawName], selects it on this draft, and returns the [ActionResult].
  Future<ActionResult> _handleCreateAndAssignLabel(String rawName) async {
    final locale = Localizations.localeOf(context);
    final result = await ref
        .read(entityActionsProvider.notifier)
        .quickCreateLabel(rawName, locale: locale);
    if (!mounted) {
      return result;
    }
    switch (result) {
      case ActionSucceeded(:final entityId):
        if (entityId != null) {
          final shell = ref.read(shellProvider);
          if (shell.expandedEntity ==
              EntityRef(kind: EntityKind.label, id: entityId)) {
            ref.read(shellProvider.notifier).collapseEntity();
          }
          setState(() {
            _selectedLabelIds = <String>{..._selectedLabelIds, entityId};
          });
        }
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() => _submitError = message);
    }
    return result;
  }

  /// Removes a link row at [index] from [_draftLinks].
  void _handleDeleteLink(TaskLink link, int index) {
    if (index < 0 || index >= _draftLinks.length) {
      return;
    }
    final nextLinks = List<TaskLink>.of(_draftLinks)..removeAt(index);
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

  /// Removes a subtask row at [index] and defers disposing its controller.
  void _handleDeleteSubtask(EditableSubtaskRow row, int index) {
    if (index < 0 || index >= _subtaskRows.length) {
      return;
    }
    final removed = _subtaskRows.removeAt(index);
    _enqueueDisposal(removed);
    setState(() {});
  }

  /// Applies updated shell draft seeds if [ShellNotifier.openDraft] re-seeds while mounted.
  void _handleDraftSeedChanged(
    _DraftSeedSnapshot? previous,
    _DraftSeedSnapshot next,
  ) {
    if (ref.read(shellProvider).activeDraft != EntityDraftKind.task) {
      return;
    }
    final sameTitle = previous?.title == next.title;
    final samePlacement = previous?.placement == next.placement;
    final sameLabels =
        previous != null && _equalStringLists(previous.labelIds, next.labelIds);
    if (sameTitle && samePlacement && sameLabels) {
      return;
    }
    setState(() {
      if (!sameTitle) {
        _controllers.title.text = next.title;
      }
      if (!samePlacement) {
        _placement = next.placement;
      }
      if (!sameLabels) {
        _selectedLabelIds = Set<String>.of(next.labelIds);
      }
    });
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
        .read(shellProvider.notifier)
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
        initialSelectedLabelIds: Set<String>.of(_selectedLabelIds),
        onToggleLabel: _handleToggleLabel,
        onCreateLabel: _handleCreateAndAssignLabel,
        onOpenLabelInfo: _handleOpenLabelInfo,
      ),
    );
  }

  /// Reveals optional draft [section].
  void _handleOpenSection(TaskSectionKind section) {
    setState(() => _openSections.add(section));
  }

  /// Updates the draft placement selection.
  void _handlePlacementChanged(QuickAddMode nextPlacement) {
    setState(() => _placement = nextPlacement);
  }

  /// Removes the condition time window at [index].
  void _handleRemoveTimeWindow(int index) {
    if (index < 0 || index >= _conditionDraft.timeWindows.length) {
      return;
    }
    final nextWindows = List<TimeWindowDraft>.of(_conditionDraft.timeWindows)
      ..removeAt(index);
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
    final nextLinks = List<TaskLink>.of(_draftLinks);
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
  void _handleRepeatUnitChanged(RepeatUnit nextUnit) {
    setState(() => _repeatUnit = nextUnit);
  }

  /// Loads an existing draft link row into the inline edit inputs.
  void _handleStartEditLink(TaskLink link, int index) {
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
        _draftLinks = const <TaskLink>[];
        _editingLinkIndex = null;
        _controllers.linkTitle.clear();
        _controllers.linkUri.clear();
        _linkInputError = null;
      case TaskSectionKind.subtasks:
        for (final row in _subtaskRows) {
          _enqueueDisposal(row);
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
        _repeatUnit = RepeatUnit.days;
        _controllers.repeatLeadDays.text = '0';
      case TaskSectionKind.suspended:
        _suspendedIndefinitely = false;
        _controllers.suspendedUntil.clear();
        _controllers.suspendedNote.clear();
      case TaskSectionKind.prerequisites:
        _selectedPrerequisiteIds.clear();
      case TaskSectionKind.conditions:
        _conditionDraft = ConditionDraft();
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

/// Narrow shell seed slice watched by [_TaskDraftCardState].
typedef _DraftSeedSnapshot = ({
  String title,
  QuickAddMode placement,
  List<String> labelIds,
});

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

/// Compares two string lists element-by-element without extra imports.
bool _equalStringLists(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

/// Returns the localized helper caption for [placement].
String _placementHint(QuickAddMode placement, AppLocalizations localizations) {
  return switch (placement) {
    QuickAddMode.standard => localizations.placementQueueHint,
    QuickAddMode.priority => localizations.placementPriorityHint,
    QuickAddMode.someday => localizations.placementSomedayHint,
  };
}

/// Resolves an optional ARGB label color integer, falling back to `tokens.colors.accent`.
Color _resolveColorDot(int? colorValue, UiThemeTokens tokens) {
  return switch (colorValue) {
    final value? => Color(value),
    null => tokens.colors.accent,
  };
}

/// Collects [TdfLabel] entries whose IDs exist in [selectedIds].
List<TdfLabel> _resolveSelectedLabels(
  List<TdfLabel> allLabels,
  Set<String> selectedIds,
) {
  return <TdfLabel>[
    for (final label in allLabels)
      if (selectedIds.contains(label.id)) label,
  ];
}

/// Extracts the task draft seed slice from [shell].
_DraftSeedSnapshot _selectDraftSeed(ShellState shell) {
  return (
    title: shell.draftSeedTitle,
    placement: shell.draftSeedPlacement,
    labelIds: shell.draftSeedLabelIds,
  );
}
