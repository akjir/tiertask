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
import '../../presentation/board_v2_view_models.dart';
import '../../presentation/entity_v2_controller.dart';
import '../../presentation/floating_notice_controller.dart';
import '../../presentation/task_v2_controller.dart';
import '../../presentation/ui_v2_shell_models.dart';
import '../dialogs/app_modals.dart';
import 'entity_section_widgets.dart';

/// Canonical display order for optional toggleable sections inside [TaskDraftCard].
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
/// configuration before committing to the `.tdf` document via [TaskV2Controller.createTaskDraft].
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

/// Read-only and inline-editable Due section for expanded Task cards (`U-CARD-002`..`003`).
class TaskDueSection extends ConsumerStatefulWidget {
  /// Creates a [TaskDueSection].
  const TaskDueSection({
    super.key,
    required this.task,
    required this.isEditing,
    required this.currentLocalDateTimeHint,
    required this.onStartEdit,
    required this.onCancelEdit,
  });

  /// Current workspace local wall-clock timestamp (`YYYY-MM-DD HH:MM`) seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Callback cancelling inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  ConsumerState<TaskDueSection> createState() => _TaskDueSectionState();
}

/// Always-visible live-interactive History Journal section on expanded Task cards (`U-CARD-004`, `U-COMP-006`).
class TaskHistorySection extends ConsumerStatefulWidget {
  /// Creates a [TaskHistorySection].
  const TaskHistorySection({
    super.key,
    required this.task,
    required this.currentLocalDateTimeHint,
  });

  /// Current workspace local wall-clock timestamp (`YYYY-MM-DD HH:MM`) seeding optional timestamp overrides.
  final String currentLocalDateTimeHint;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  ConsumerState<TaskHistorySection> createState() => _TaskHistorySectionState();
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

/// Read-only and inline-editable Prerequisites section with cycle prevention (`U-COMP-005`).
class TaskPrerequisitesSection extends ConsumerStatefulWidget {
  /// Creates a [TaskPrerequisitesSection].
  const TaskPrerequisitesSection({
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

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  ConsumerState<TaskPrerequisitesSection> createState() =>
      _TaskPrerequisitesSectionState();
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

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  ConsumerState<TaskRepeatSection> createState() => _TaskRepeatSectionState();
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

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  ConsumerState<TaskSubtasksSection> createState() =>
      _TaskSubtasksSectionState();
}

/// Read-only and inline-editable Suspended section supporting timed vs indefinite deferral and notes.
class TaskSuspendedSection extends ConsumerStatefulWidget {
  /// Creates a [TaskSuspendedSection].
  const TaskSuspendedSection({
    super.key,
    required this.task,
    required this.isEditing,
    required this.currentLocalDateTimeHint,
    required this.onStartEdit,
    required this.onCancelEdit,
  });

  /// Current workspace local wall-clock timestamp (`YYYY-MM-DD HH:MM`) seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Callback cancelling inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  ConsumerState<TaskSuspendedSection> createState() =>
      _TaskSuspendedSectionState();
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

/// Live-updating Activation Conditions section hosted inside [TaskDraftCard].
class _DraftConditionsCard extends StatelessWidget {
  /// Creates a [_DraftConditionsCard].
  const _DraftConditionsCard({
    required this.draft,
    required this.allLocations,
    required this.isSuspended,
    required this.timeStartController,
    required this.timeEndController,
    required this.timeInputError,
    required this.sectionError,
    required this.isBusy,
    required this.onDraftChanged,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
    required this.onClose,
  });

  /// Workspace locations selectable in the GPS condition dimension.
  final List<LocationOptionViewModel> allLocations;

  /// Current condition draft state.
  final ConditionDraftViewModel draft;

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Whether the draft task also has Suspended opened (dims condition controls).
  final bool isSuspended;

  /// Callback adding the typed `HH:MM`..`HH:MM` time window.
  final VoidCallback onAddTimeWindow;

  /// Callback hiding and clearing the draft conditions section.
  final VoidCallback onClose;

  /// Callback replacing the draft condition model.
  final ValueChanged<ConditionDraftViewModel> onDraftChanged;

  /// Callback removing a time window at index.
  final ValueChanged<int> onRemoveTimeWindow;

  /// Optional validation error returned for conditions.
  final String? sectionError;

  /// Controller for the end `HH:MM` input.
  final TextEditingController timeEndController;

  /// Optional inline error for malformed time window input.
  final String? timeInputError;

  /// Controller for the start `HH:MM` input.
  final TextEditingController timeStartController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final controlsEnabled = !isBusy && !isSuspended;

    return UiCard.inset(
      key: const ValueKey<String>('draft_conditions_card'),
      headerIcon: Icons.tune_rounded,
      headerTitle: localizations.taskConditionsSectionTitle,
      headerTrailing: UiButton(
        leadingIcon: Icons.close_rounded,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.sidebarDesktop,
        tooltip: localizations.actionClose,
        onPressed: isBusy ? null : onClose,
      ),
      child: Column(
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
                draft: draft,
                allLocations: allLocations,
                timeStartController: timeStartController,
                timeEndController: timeEndController,
                timeInputError: timeInputError,
                enabled: controlsEnabled,
                onDraftChanged: onDraftChanged,
                onAddTimeWindow: onAddTimeWindow,
                onRemoveTimeWindow: onRemoveTimeWindow,
              ),
            ),
          ),
          if (sectionError case final error?) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
            _InlineErrorText(message: error),
          ],
        ],
      ),
    );
  }
}

/// Interactive controls body inside [_DraftConditionsCard].
class _DraftConditionsControls extends StatelessWidget {
  /// Creates a [_DraftConditionsControls].
  const _DraftConditionsControls({
    required this.draft,
    required this.allLocations,
    required this.timeStartController,
    required this.timeEndController,
    required this.timeInputError,
    required this.enabled,
    required this.onDraftChanged,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
  });

  /// Workspace locations selectable in the GPS condition dimension.
  final List<LocationOptionViewModel> allLocations;

  /// Current condition draft model.
  final ConditionDraftViewModel draft;

  /// Whether controls accept interaction.
  final bool enabled;

  /// Callback adding a time window.
  final VoidCallback onAddTimeWindow;

  /// Callback updating the condition draft.
  final ValueChanged<ConditionDraftViewModel> onDraftChanged;

  /// Callback removing a time window by index.
  final ValueChanged<int> onRemoveTimeWindow;

  /// End time controller.
  final TextEditingController timeEndController;

  /// Inline time window error.
  final String? timeInputError;

  /// Start time controller.
  final TextEditingController timeStartController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
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
          onChanged: (value) =>
              onDraftChanged(draft.copyWith(ignoreAllLabelConditions: value)),
        ),
        if (!draft.ignoreAllLabelConditions) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _DraftDimensionSelector(
            label: localizations.conditionDayGroupTitle,
            mode: draft.daysMode,
            anyLabel: localizations.conditionDayAnyLabel,
            enabled: dimensionsEnabled,
            onModeChanged: (mode) =>
                onDraftChanged(draft.copyWith(daysMode: mode)),
          ),
          if (draft.daysMode == ConditionDimensionMode.custom) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
            _DraftWeekdaysWrap(
              selectedWeekdays: draft.selectedWeekdays,
              enabled: dimensionsEnabled,
              onToggleWeekday: _toggleWeekday,
            ),
          ],
          SizedBox(height: tokens.spacing.space2),
          _DraftDimensionSelector(
            label: localizations.conditionTimeGroupTitle,
            mode: draft.timesMode,
            anyLabel: localizations.conditionTimeAnyLabel,
            enabled: dimensionsEnabled,
            onModeChanged: (mode) =>
                onDraftChanged(draft.copyWith(timesMode: mode)),
          ),
          if (draft.timesMode == ConditionDimensionMode.custom) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
            _DraftTimeWindowsEditor(
              timeWindows: draft.timeWindows,
              startController: timeStartController,
              endController: timeEndController,
              errorText: timeInputError,
              enabled: dimensionsEnabled,
              onAdd: onAddTimeWindow,
              onRemove: onRemoveTimeWindow,
            ),
          ],
          SizedBox(height: tokens.spacing.space2),
          _DraftDimensionSelector(
            label: localizations.conditionLocationGroupTitle,
            mode: draft.locationsMode,
            anyLabel: localizations.conditionLocationAnyLabel,
            enabled: dimensionsEnabled,
            onModeChanged: (mode) =>
                onDraftChanged(draft.copyWith(locationsMode: mode)),
          ),
          if (draft.locationsMode == ConditionDimensionMode.custom) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
            _DraftLocationsWrap(
              allLocations: allLocations,
              selectedIds: draft.selectedLocationIds,
              enabled: dimensionsEnabled,
              onToggleLocation: _toggleLocation,
            ),
          ],
        ],
      ],
    );
  }

  /// Toggles [locationId] in [draft.selectedLocationIds].
  void _toggleLocation(String locationId) {
    final nextIds = List<String>.of(draft.selectedLocationIds);
    if (!nextIds.remove(locationId)) {
      nextIds.add(locationId);
    }
    onDraftChanged(draft.copyWith(selectedLocationIds: nextIds));
  }

  /// Toggles ISO weekday [weekday] (`1..7`) in [draft.selectedWeekdays].
  void _toggleWeekday(int weekday) {
    final nextDays = List<int>.of(draft.selectedWeekdays);
    if (!nextDays.remove(weekday)) {
      nextDays.add(weekday);
      nextDays.sort();
    }
    onDraftChanged(draft.copyWith(selectedWeekdays: nextDays));
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
  const _DraftDueCard({
    required this.dueController,
    required this.dueNoteController,
    required this.autoPrioritize,
    required this.currentLocalDateTimeHint,
    required this.dueError,
    required this.dueNoteError,
    required this.isBusy,
    required this.onDueChanged,
    required this.onAutoPrioritizeChanged,
    required this.onDueNoteChanged,
    required this.onClose,
  });

  /// Whether deadline lead-window auto-prioritization is checked.
  final bool autoPrioritize;

  /// Current workspace local wall-clock timestamp seeding pickers.
  final String currentLocalDateTimeHint;

  /// Controller for the due timestamp input.
  final TextEditingController dueController;

  /// Optional validation error for the due timestamp.
  final String? dueError;

  /// Controller for the optional deadline note.
  final TextEditingController dueNoteController;

  /// Optional validation error for the deadline note.
  final String? dueNoteError;

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Callback toggling [autoPrioritize].
  final ValueChanged<bool> onAutoPrioritizeChanged;

  /// Callback closing and clearing this optional section.
  final VoidCallback onClose;

  /// Callback notified when due text changes.
  final ValueChanged<String> onDueChanged;

  /// Callback notified when due note text changes.
  final ValueChanged<String> onDueNoteChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('draft_due_card'),
      headerIcon: Icons.calendar_today_outlined,
      headerTitle: localizations.taskInfoDueLabel,
      headerTrailing: UiButton(
        leadingIcon: Icons.close_rounded,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.sidebarDesktop,
        tooltip: localizations.actionClose,
        onPressed: isBusy ? null : onClose,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          EntityHybridDateTimeField(
            controller: dueController,
            label: localizations.taskDueButtonLabel,
            fallbackLocalDateTime: currentLocalDateTimeHint,
            enabled: !isBusy,
            errorText: dueError,
            onChanged: onDueChanged,
          ),
          SizedBox(height: tokens.spacing.space2),
          UiToggleRow(
            label: localizations.taskDueAutoPrioritizeLabel,
            description: localizations.taskDueAutoPrioritizeSubtitle,
            value: autoPrioritize,
            isDense: true,
            enabled: !isBusy,
            onChanged: onAutoPrioritizeChanged,
          ),
          SizedBox(height: tokens.spacing.space2),
          UiField(
            kind: UiFieldKind.multiline,
            controller: dueNoteController,
            label: localizations.taskDueNoteLabel,
            hintText: localizations.taskDueNoteHint,
            maxLength: _maxNoteLength,
            minLines: 2,
            maxLines: 4,
            enabled: !isBusy,
            errorText: dueNoteError,
            onChanged: onDueNoteChanged,
          ),
        ],
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

/// Assigned labels and inline/sheet picker section hosted inside [TaskDraftCard].
class _DraftLabelsSection extends StatelessWidget {
  /// Creates a [_DraftLabelsSection].
  const _DraftLabelsSection({
    required this.allLabels,
    required this.selectedIds,
    required this.hasBothScopedAndGlobal,
    required this.isInlinePickerOpen,
    required this.isCompact,
    required this.isBusy,
    required this.onToggleLabel,
    required this.onCreateAndAssign,
    required this.onOpenLabelInfo,
    required this.onOpenPicker,
    required this.onClosePicker,
  });

  /// All workspace labels.
  final List<LabelPickerOptionViewModel> allLabels;

  /// Whether workspace contains both scoped and global labels.
  final bool hasBothScopedAndGlobal;

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Whether viewport is compact (`<= 720`).
  final bool isCompact;

  /// Whether desktop inline label picker is currently expanded.
  final bool isInlinePickerOpen;

  /// Callback closing the desktop inline label picker.
  final VoidCallback onClosePicker;

  /// Callback creating and assigning a new label by name.
  final ValueChanged<String> onCreateAndAssign;

  /// Callback opening a label inside Labels manager.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback opening the inline picker (desktop) or bottom sheet (compact).
  final VoidCallback onOpenPicker;

  /// Callback toggling label assignment on the draft.
  final ValueChanged<String> onToggleLabel;

  /// Currently selected label identifiers.
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    if (isInlinePickerOpen && !isCompact) {
      return UiCard.inset(
        key: const ValueKey<String>('draft_labels_picker_card'),
        isEditing: true,
        headerIcon: Icons.label_outline_rounded,
        headerTitle: localizations.taskLabelsSectionTitle,
        headerBadge: UiPill(
          label: '${selectedIds.length}',
          variant: UiPillVariant.count,
        ),
        headerTrailing: UiButton(
          label: localizations.actionDone,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: onClosePicker,
        ),
        child: EntitySearchableLabelPicker(
          allLabels: allLabels,
          selectedIds: selectedIds,
          hasBothScopedAndGlobal: hasBothScopedAndGlobal,
          autoFocusSearch: true,
          onToggleLabel: onToggleLabel,
          onCreateAndAssign: onCreateAndAssign,
          onOpenLabelInfo: onOpenLabelInfo,
          onRequestClose: onClosePicker,
        ),
      );
    }

    final selectedOptions = _resolveSelectedLabels(allLabels, selectedIds);
    if (selectedOptions.isEmpty) {
      return const SizedBox.shrink();
    }
    return UiCard.inset(
      key: const ValueKey<String>('draft_labels_card'),
      headerIcon: Icons.label_outline_rounded,
      headerTitle: localizations.taskLabelsSectionTitle,
      headerBadge: UiPill(
        label: '${selectedOptions.length}',
        variant: UiPillVariant.count,
      ),
      child: Wrap(
        spacing: 6.0,
        runSpacing: 6.0,
        children: <Widget>[
          for (final option in selectedOptions)
            UiPill(
              label: option.name,
              variant: UiPillVariant.splitChip,
              colorDot: _resolveColorDot(option.colorValue, tokens),
              removeTooltip: localizations.labelPickerRemoveTooltip(
                option.name,
              ),
              enabled: !isBusy,
              onRemove: isBusy ? null : () => onToggleLabel(option.id),
            ),
          UiPill(
            label: localizations.actionAdd,
            icon: Icons.add_rounded,
            variant: UiPillVariant.addField,
            enabled: !isBusy,
            onPressed: isBusy ? null : onOpenPicker,
          ),
        ],
      ),
    );
  }
}

/// Optional Reference Links section hosted inside [TaskDraftCard].
class _DraftLinksCard extends StatelessWidget {
  /// Creates a [_DraftLinksCard].
  const _DraftLinksCard({
    required this.links,
    required this.editingIndex,
    required this.titleController,
    required this.uriController,
    required this.inputError,
    required this.sectionError,
    required this.isBusy,
    required this.onReorder,
    required this.onStartEdit,
    required this.onDelete,
    required this.onCommitInput,
    required this.onCancelRowEdit,
    required this.onClose,
  });

  /// Active link index being edited inline, if any.
  final int? editingIndex;

  /// Validation error for the inline link form.
  final String? inputError;

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Draft link entries.
  final List<EntityLinkInput> links;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback hiding and clearing this optional section.
  final VoidCallback onClose;

  /// Callback validating and appending/updating the typed link input.
  final VoidCallback onCommitInput;

  /// Callback deleting a link row.
  final UiOrderedItemActionCallback<EntityLinkInput> onDelete;

  /// Callback reordering link rows.
  final UiOrderedItemReorderCallback onReorder;

  /// Callback starting inline edit of an existing link row.
  final UiOrderedItemActionCallback<EntityLinkInput> onStartEdit;

  /// Validation error returned for links on draft submit.
  final String? sectionError;

  /// Controller for the link title field.
  final TextEditingController titleController;

  /// Controller for the link URI field.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return UiCard.inset(
      key: const ValueKey<String>('draft_links_card'),
      headerIcon: Icons.link_rounded,
      headerTitle: localizations.linksSectionTitle,
      headerBadge: UiPill(
        label: '${links.length} / $_maxLinksPerTask',
        variant: UiPillVariant.count,
      ),
      headerTrailing: UiButton(
        leadingIcon: Icons.close_rounded,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.sidebarDesktop,
        tooltip: localizations.actionClose,
        onPressed: isBusy ? null : onClose,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiOrderedItemList<EntityLinkInput>(
            items: links,
            editingIndex: editingIndex,
            itemKey: (link, index) => ValueKey<String>(
              'draft_link_${index}_${link.title}_${link.uri}',
            ),
            onReorder: isBusy ? null : onReorder,
            moveUpTooltip: localizations.tooltipMoveLinkUp,
            moveDownTooltip: localizations.tooltipMoveLinkDown,
            onEdit: isBusy ? null : onStartEdit,
            editTooltip: localizations.tooltipEditLink,
            onDelete: isBusy ? null : onDelete,
            deleteTooltip: localizations.tooltipRemoveLink,
            itemBuilder: (context, link, index, isEditing) => Column(
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
            ),
            addBar: _DraftLinkAddForm(
              titleController: titleController,
              uriController: uriController,
              isEditingExisting: editingIndex != null,
              errorText: inputError,
              isBusy: isBusy,
              onCommit: onCommitInput,
              onCancelEdit: onCancelRowEdit,
            ),
          ),
          if (sectionError case final error?) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
            _InlineErrorText(message: error),
          ],
        ],
      ),
    );
  }
}

/// Inline link title/URI input bar hosted inside [_DraftLinksCard].
class _DraftLinkAddForm extends StatelessWidget {
  /// Creates a [_DraftLinkAddForm].
  const _DraftLinkAddForm({
    required this.titleController,
    required this.uriController,
    required this.isEditingExisting,
    required this.errorText,
    required this.isBusy,
    required this.onCommit,
    required this.onCancelEdit,
  });

  /// Inline validation error for the link fields.
  final String? errorText;

  /// Whether draft submission is in flight.
  final bool isBusy;

  /// Whether currently updating an existing draft link row.
  final bool isEditingExisting;

  /// Callback cancelling the active row edit.
  final VoidCallback onCancelEdit;

  /// Callback adding or updating the link row.
  final VoidCallback onCommit;

  /// Controller for the link title.
  final TextEditingController titleController;

  /// Controller for the link URI.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiResponsiveGrid(
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
        ),
        if (errorText case final error?) ...<Widget>[
          SizedBox(height: tokens.spacing.space1),
          _InlineErrorText(message: error),
        ],
        SizedBox(height: tokens.spacing.space2),
        Wrap(
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
        ),
      ],
    );
  }
}

/// Selectable GPS location chips wrap hosted inside [_DraftConditionsControls].
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
  const _DraftNoteCard({
    required this.controller,
    required this.errorText,
    required this.isBusy,
    required this.onChanged,
    required this.onClose,
  });

  /// Controller for the draft note text.
  final TextEditingController controller;

  /// Optional validation error for the note.
  final String? errorText;

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Callback notified when note text changes.
  final ValueChanged<String> onChanged;

  /// Callback closing and clearing this optional section.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: const ValueKey<String>('draft_note_card'),
      headerIcon: Icons.description_outlined,
      headerTitle: localizations.taskNoteLabel,
      headerTrailing: UiButton(
        leadingIcon: Icons.close_rounded,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.sidebarDesktop,
        tooltip: localizations.actionClose,
        onPressed: isBusy ? null : onClose,
      ),
      child: UiField(
        kind: UiFieldKind.multiline,
        controller: controller,
        hintText: localizations.taskNoteHint,
        maxLength: _maxNoteLength,
        minLines: 3,
        maxLines: 6,
        enabled: !isBusy,
        errorText: errorText,
        onChanged: onChanged,
      ),
    );
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
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('draft_placement_card'),
      headerIcon: Icons.bolt_outlined,
      headerTitle: localizations.inlinePlacementSectionTitle,
      child: Column(
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
      ),
    );
  }
}

/// Optional Prerequisite tasks selector hosted inside [TaskDraftCard].
class _DraftPrerequisitesCard extends StatelessWidget {
  /// Creates a [_DraftPrerequisitesCard].
  const _DraftPrerequisitesCard({
    required this.candidates,
    required this.selectedIds,
    required this.errorText,
    required this.isBusy,
    required this.onTogglePrerequisite,
    required this.onClose,
  });

  /// Selectable open task candidates.
  final List<PrerequisiteCandidateViewModel> candidates;

  /// Optional validation error for prerequisites.
  final String? errorText;

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Callback hiding and clearing this optional section.
  final VoidCallback onClose;

  /// Callback toggling selection of a prerequisite task ID.
  final ValueChanged<String> onTogglePrerequisite;

  /// Selected prerequisite task IDs.
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('draft_prerequisites_card'),
      headerIcon: Icons.lock_outline_rounded,
      headerTitle: localizations.taskBlockedBySectionTitle,
      headerBadge: UiPill(
        label: '${selectedIds.length}',
        variant: UiPillVariant.count,
      ),
      headerTrailing: UiButton(
        leadingIcon: Icons.close_rounded,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.sidebarDesktop,
        tooltip: localizations.actionClose,
        onPressed: isBusy ? null : onClose,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiSearchablePicker<String>(
            options: <UiPickerOption<String>>[
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
            ],
            selectedIds: selectedIds,
            searchMaxLength: _maxSingleLineLength,
            searchPlaceholder: localizations.blockedBySearchHint,
            searchClearTooltip: localizations.tooltipClearSearch,
            emptyText: localizations.blockedBySearchNoResults,
            onToggleOption: (option) {
              if (!isBusy) {
                onTogglePrerequisite(option.value);
              }
            },
          ),
          if (errorText case final error?) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
            _InlineErrorText(message: error),
          ],
        ],
      ),
    );
  }
}

/// Optional Repeat section hosted inside [TaskDraftCard].
class _DraftRepeatCard extends StatelessWidget {
  /// Creates a [_DraftRepeatCard].
  const _DraftRepeatCard({
    required this.countController,
    required this.unit,
    required this.leadDaysController,
    required this.hasDueDate,
    required this.countError,
    required this.leadError,
    required this.isBusy,
    required this.onCountChanged,
    required this.onUnitChanged,
    required this.onLeadChanged,
    required this.onClose,
  });

  /// Controller for the repeat count (`1..3650`).
  final TextEditingController countController;

  /// Optional validation error for the repeat count.
  final String? countError;

  /// Whether a due timestamp is currently entered on the draft.
  final bool hasDueDate;

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Controller for preparation lead days (`0..3650`).
  final TextEditingController leadDaysController;

  /// Optional validation error for lead days.
  final String? leadError;

  /// Callback closing and clearing this optional section.
  final VoidCallback onClose;

  /// Callback notified when repeat count text changes.
  final ValueChanged<String> onCountChanged;

  /// Callback notified when lead days text changes.
  final ValueChanged<String> onLeadChanged;

  /// Callback notified when recurrence unit changes.
  final ValueChanged<ShellRepeatUnit> onUnitChanged;

  /// Selected recurrence unit.
  final ShellRepeatUnit unit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('draft_repeat_card'),
      headerIcon: Icons.repeat_rounded,
      headerTitle: localizations.repeatFlagLabel,
      headerTrailing: UiButton(
        leadingIcon: Icons.close_rounded,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.sidebarDesktop,
        tooltip: localizations.actionClose,
        onPressed: isBusy ? null : onClose,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiField(
            kind: UiFieldKind.text,
            controller: countController,
            label: localizations.repeatIntervalLabel,
            hintText: '1',
            keyboardType: TextInputType.number,
            enabled: !isBusy,
            errorText: countError,
            onChanged: onCountChanged,
          ),
          SizedBox(height: tokens.spacing.space2),
          UiSegmentedControl<ShellRepeatUnit>(
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
          ),
          SizedBox(height: tokens.spacing.space2),
          UiField(
            kind: UiFieldKind.text,
            controller: leadDaysController,
            label: localizations.repeatLeadDaysLabel,
            hintText: localizations.repeatLeadDaysHint,
            helperText: hasDueDate
                ? null
                : localizations.inlineRepeatLeadNeedsDueHint,
            keyboardType: TextInputType.number,
            enabled: !isBusy && hasDueDate,
            errorText: leadError,
            onChanged: onLeadChanged,
          ),
        ],
      ),
    );
  }
}

/// Optional Subtasks section hosted inside [TaskDraftCard].
class _DraftSubtasksCard extends StatelessWidget {
  /// Creates a [_DraftSubtasksCard].
  const _DraftSubtasksCard({
    required this.rows,
    required this.newStepController,
    required this.newStepFocusNode,
    required this.autoFinish,
    required this.errorText,
    required this.isBusy,
    required this.onReorder,
    required this.onToggleRowDone,
    required this.onDeleteRow,
    required this.onAddRow,
    required this.onAutoFinishChanged,
    required this.onClose,
  });

  /// Whether auto-finish is toggled on.
  final bool autoFinish;

  /// Optional validation error for subtasks.
  final String? errorText;

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Controller for the bottom new-subtask input.
  final TextEditingController newStepController;

  /// Focus node for the bottom new-subtask input.
  final FocusNode newStepFocusNode;

  /// Callback adding the typed subtask step and refocusing the input.
  final VoidCallback onAddRow;

  /// Callback updating [autoFinish].
  final ValueChanged<bool> onAutoFinishChanged;

  /// Callback closing and clearing this optional section.
  final VoidCallback onClose;

  /// Callback deleting a subtask row.
  final UiOrderedItemActionCallback<_EditableSubtaskRow> onDeleteRow;

  /// Callback reordering subtask rows.
  final UiOrderedItemReorderCallback onReorder;

  /// Callback toggling completion of a subtask row.
  final ValueChanged<int> onToggleRowDone;

  /// Editable subtask rows.
  final List<_EditableSubtaskRow> rows;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('draft_subtasks_card'),
      headerIcon: autoFinish
          ? Icons.check_box_outlined
          : Icons.checklist_rounded,
      headerTitle: localizations.subtasksSectionTitle,
      headerBadge: UiPill(
        label: '${rows.length}',
        variant: UiPillVariant.count,
      ),
      headerTrailing: UiButton(
        leadingIcon: Icons.close_rounded,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.sidebarDesktop,
        tooltip: localizations.actionClose,
        onPressed: isBusy ? null : onClose,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiOrderedItemList<_EditableSubtaskRow>(
            items: rows,
            itemKey: (row, index) =>
                ValueKey<String>('draft_subtask_row_${row.rowId}'),
            onReorder: isBusy ? null : onReorder,
            onDelete: isBusy ? null : onDeleteRow,
            deleteTooltip: localizations.tooltipRemoveSubtask,
            itemBuilder: (context, row, index, isEditing) => Row(
              children: <Widget>[
                _SubtaskCheckBoxButton(
                  checked: row.isCompleted,
                  enabled: !isBusy,
                  semanticLabel: row.controller.text,
                  onToggle: () => onToggleRowDone(index),
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
            ),
            addBar: Row(
              children: <Widget>[
                Expanded(
                  child: UiField(
                    key: const ValueKey<String>('draft_subtask_add_input'),
                    kind: UiFieldKind.text,
                    controller: newStepController,
                    focusNode: newStepFocusNode,
                    hintText: localizations.subtaskInputHint,
                    maxLength: _maxSingleLineLength,
                    enabled: !isBusy,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onAddRow(),
                  ),
                ),
                const SizedBox(width: 8.0),
                UiButton(
                  label: localizations.actionAdd,
                  variant: UiButtonVariant.secondary,
                  density: UiButtonDensity.compact,
                  tooltip: localizations.tooltipAddSubtask,
                  onPressed: isBusy ? null : onAddRow,
                ),
              ],
            ),
            footer: UiToggleRow(
              label: localizations.subtasksAutoFinishLabel,
              description: localizations.tooltipTaskEditorAutoFinish,
              value: autoFinish,
              isDense: true,
              enabled: !isBusy,
              onChanged: onAutoFinishChanged,
            ),
          ),
          if (errorText case final error?) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
            _InlineErrorText(message: error),
          ],
        ],
      ),
    );
  }
}

/// Optional Suspended section hosted inside [TaskDraftCard].
class _DraftSuspendedCard extends StatelessWidget {
  /// Creates a [_DraftSuspendedCard].
  const _DraftSuspendedCard({
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
    required this.onClose,
  });

  /// Current workspace local wall-clock timestamp seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether indefinite suspension is selected.
  final bool indefinitely;

  /// Whether draft creation is currently in flight.
  final bool isBusy;

  /// Controller for the optional deferral note.
  final TextEditingController noteController;

  /// Optional validation error for the deferral note.
  final String? noteError;

  /// Callback closing and clearing this optional section.
  final VoidCallback onClose;

  /// Callback toggling between timed (`false`) and indefinite (`true`) suspension.
  final ValueChanged<bool> onModeChanged;

  /// Callback notified when deferral note changes.
  final ValueChanged<String> onNoteChanged;

  /// Callback notified when timed suspension input changes.
  final ValueChanged<String> onUntilChanged;

  /// Controller for the timed suspension timestamp.
  final TextEditingController untilController;

  /// Optional validation error for the timed suspension timestamp.
  final String? untilError;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('draft_suspended_card'),
      headerIcon: Icons.pause_circle_outline_rounded,
      headerTitle: localizations.taskSuspendedLabel,
      headerTrailing: UiButton(
        leadingIcon: Icons.close_rounded,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.sidebarDesktop,
        tooltip: localizations.actionClose,
        onPressed: isBusy ? null : onClose,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiSegmentedControl<bool>(
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
          ),
          if (!indefinitely) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
            EntityHybridDateTimeField(
              controller: untilController,
              label: localizations.taskSuspendedUntilLabel,
              fallbackLocalDateTime: currentLocalDateTimeHint,
              enabled: !isBusy,
              errorText: untilError,
              onChanged: onUntilChanged,
            ),
          ],
          SizedBox(height: tokens.spacing.space2),
          UiField(
            kind: UiFieldKind.multiline,
            controller: noteController,
            label: localizations.taskSuspendedNoteLabel,
            hintText: localizations.taskSuspendedNoteHint,
            maxLength: _maxNoteLength,
            minLines: 2,
            maxLines: 4,
            enabled: !isBusy,
            errorText: noteError,
            onChanged: onNoteChanged,
          ),
        ],
      ),
    );
  }
}

/// Time windows list and `HH:MM` add bar hosted inside [_DraftConditionsControls].
class _DraftTimeWindowsEditor extends StatelessWidget {
  /// Creates a [_DraftTimeWindowsEditor].
  const _DraftTimeWindowsEditor({
    required this.timeWindows,
    required this.startController,
    required this.endController,
    required this.errorText,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  /// Whether inputs and buttons accept interaction.
  final bool enabled;

  /// End `HH:MM` controller.
  final TextEditingController endController;

  /// Inline error message for invalid `HH:MM` tokens.
  final String? errorText;

  /// Callback adding the typed time window.
  final VoidCallback onAdd;

  /// Callback removing a time window at index.
  final ValueChanged<int> onRemove;

  /// Start `HH:MM` controller.
  final TextEditingController startController;

  /// Configured time windows in the draft.
  final List<TimeWindowDraftViewModel> timeWindows;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiOrderedItemList<TimeWindowDraftViewModel>(
      items: timeWindows,
      itemKey: (window, index) => ValueKey<String>(
        'draft_time_window_${index}_${window.start}_${window.end}',
      ),
      onDelete: enabled ? (window, index) => onRemove(index) : null,
      deleteTooltip: localizations.tooltipRemoveTimeCondition,
      itemBuilder: (context, window, index, isEditing) => Text(
        '${window.start} - ${window.end}',
        style: UiTypographyTokens.mono(
          tokens.typography.monoSmall.copyWith(color: tokens.colors.ink),
        ),
      ),
      addBar: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiResponsiveGrid(
            preset: UiGridPreset.twoColumnCompactCollapse,
            spacing: tokens.spacing.space2,
            runSpacing: tokens.spacing.space2,
            children: <Widget>[
              EntityHybridTimeField(
                controller: startController,
                hintText: localizations.conditionTimeStartHint,
                enabled: enabled,
              ),
              EntityHybridTimeField(
                controller: endController,
                hintText: localizations.conditionTimeEndHint,
                enabled: enabled,
                onSubmitted: (_) => onAdd(),
              ),
            ],
          ),
          if (errorText case final error?) ...<Widget>[
            SizedBox(height: tokens.spacing.space1),
            _InlineErrorText(message: error),
          ],
          SizedBox(height: tokens.spacing.space2),
          Align(
            alignment: Alignment.centerLeft,
            child: UiButton(
              label: localizations.tooltipAddTimeCondition,
              variant: UiButtonVariant.secondary,
              density: UiButtonDensity.compact,
              onPressed: enabled ? onAdd : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable Mon..Sun weekday pills wrap hosted inside [_DraftConditionsControls].
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

/// Controller-backed mutable draft row for inline and draft subtask editors.
class _EditableSubtaskRow {
  /// Creates an [_EditableSubtaskRow].
  _EditableSubtaskRow({
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
        Row(
          children: <Widget>[
            Expanded(
              child: UiField(
                key: ValueKey<String>('history_add_text_$taskId'),
                kind: UiFieldKind.text,
                controller: textController,
                hintText: localizations.historyEntryTextHint,
                maxLength: _maxSingleLineLength,
                enabled: !isBusy,
                textInputAction: TextInputAction.done,
                onChanged: onChanged,
                onSubmitted: (_) => onAdd(),
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
              variant: UiButtonVariant.secondary,
              density: UiButtonDensity.compact,
              tooltip: localizations.tooltipAddHistoryEntry,
              onPressed: isBusy ? null : onAdd,
            ),
          ],
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
          _InlineErrorText(message: error),
        ],
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
    final tokens = UiThemeTokens.of(context);

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
        SizedBox(height: tokens.spacing.space2),
        UiField(
          key: ValueKey<String>('history_edit_text_${taskId}_$index'),
          kind: UiFieldKind.text,
          controller: textController,
          maxLength: _maxSingleLineLength,
          autofocus: true,
          enabled: !isBusy,
          semanticLabel: localizations.historyEntryTextLabel,
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
          onSubmitted: (_) => onSave(),
        ),
        SizedBox(height: tokens.spacing.space2),
        Wrap(
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
              variant: UiButtonVariant.secondary,
              density: UiButtonDensity.compact,
              tooltip: localizations.tooltipCancelEditHistoryEntry,
              onPressed: isBusy ? null : onCancel,
            ),
          ],
        ),
      ],
    );
  }
}

/// Read-only display row for a single [HistoryEntryViewModel].
class _HistoryReadRow extends StatelessWidget {
  /// Creates a [_HistoryReadRow].
  const _HistoryReadRow({required this.entry});

  /// History journal entry projection.
  final HistoryEntryViewModel entry;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          entry.formattedLocalTimestamp,
          style: UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: colors.muted),
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          entry.text,
          style: tokens.typography.control.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// Live-region inline danger validation or persistence error caption.
class _InlineErrorText extends StatelessWidget {
  /// Creates an [_InlineErrorText].
  const _InlineErrorText({required this.message});

  /// Localized error text.
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: tokens.typography.meta.copyWith(
          color: tokens.colors.danger,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Compact accessible checkbox button used inside inline subtask edit rows (no Material Switch).
class _SubtaskCheckBoxButton extends StatefulWidget {
  /// Creates a [_SubtaskCheckBoxButton].
  const _SubtaskCheckBoxButton({
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
  State<_SubtaskCheckBoxButton> createState() => _SubtaskCheckBoxButtonState();
}

/// Tracks keyboard focus ring state for [_SubtaskCheckBoxButton].
class _SubtaskCheckBoxButtonState extends State<_SubtaskCheckBoxButton> {
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final surface = UiSurfaceScope.of(context);
    final uncheckedFill = surface == UiSurfaceLevel.insetWell
        ? colors.panel
        : colors.bg;

    Widget checkbox = AnimatedContainer(
      duration: tokens.focus.hoverDuration,
      width: 16.0,
      height: 16.0,
      decoration: BoxDecoration(
        color: widget.checked ? colors.accent : uncheckedFill,
        borderRadius: BorderRadius.circular(tokens.radii.dotLg),
        border: Border.all(
          color: widget.checked ? colors.accent : colors.line,
          width: tokens.radii.borderWidth,
        ),
      ),
      child: widget.checked
          ? Icon(Icons.check_rounded, size: 12.0, color: colors.onAccent)
          : null,
    );

    if (_showFocusRing && widget.enabled) {
      checkbox = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radii.sm),
          border: Border.all(
            color: colors.accent,
            width: tokens.focus.ringWidth,
          ),
        ),
        child: Padding(padding: const EdgeInsets.all(2.0), child: checkbox),
      );
    }

    return Semantics(
      checked: widget.checked,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowFocusHighlight: (focused) {
          if (_showFocusRing != focused) {
            setState(() => _showFocusRing = focused);
          }
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (widget.enabled) {
                widget.onToggle();
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onToggle : null,
          child: SizedBox(
            width: 30.0,
            height: 30.0,
            child: Center(child: checkbox),
          ),
        ),
      ),
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

/// Manages uncommitted task draft controllers, optional sections, and commit flow for [TaskDraftCard].
class _TaskDraftCardState extends ConsumerState<TaskDraftCard> {
  late final TextEditingController _dueController;
  late final TextEditingController _dueNoteController;
  late final TextEditingController _linkTitleController;
  late final TextEditingController _linkUriController;
  late final TextEditingController _newSubtaskController;
  late final FocusNode _newSubtaskFocusNode;
  late final TextEditingController _noteController;
  late final TextEditingController _repeatCountController;
  late final TextEditingController _repeatLeadDaysController;
  late final TextEditingController _suspendedNoteController;
  late final TextEditingController _suspendedUntilController;
  late final TextEditingController _timeEndController;
  late final TextEditingController _timeStartController;
  late final TextEditingController _titleController;

  ConditionDraftViewModel _conditionDraft = ConditionDraftViewModel();
  List<EntityLinkInput> _draftLinks = const <EntityLinkInput>[];
  bool _dueAutoPrioritize = true;
  int? _editingLinkIndex;
  Map<String, String> _fieldErrors = const <String, String>{};
  bool _isSubmitting = false;
  bool _labelPickerOpen = false;
  String? _linkInputError;
  int _nextSubtaskRowId = 1;
  final Set<TaskSectionKind> _openSections = <TaskSectionKind>{};
  late TaskPlacementOption _placement;
  ShellRepeatUnit _repeatUnit = ShellRepeatUnit.days;
  late Set<String> _selectedLabelIds;
  final Set<String> _selectedPrerequisiteIds = <String>{};
  String? _submitError;
  final List<_EditableSubtaskRow> _subtaskRows = <_EditableSubtaskRow>[];
  bool _subtasksAutoFinish = false;
  bool _suspendedIndefinitely = false;
  String? _timeInputError;

  @override
  void initState() {
    super.initState();
    final shellState = ref.read(appShellControllerProvider);
    _titleController = TextEditingController(text: shellState.draftSeedTitle);
    _placement = shellState.draftSeedPlacement;
    _selectedLabelIds = Set<String>.of(shellState.draftSeedLabelIds);
    _noteController = TextEditingController();
    _linkTitleController = TextEditingController();
    _linkUriController = TextEditingController();
    _newSubtaskController = TextEditingController();
    _newSubtaskFocusNode = FocusNode();
    _dueController = TextEditingController();
    _dueNoteController = TextEditingController();
    _repeatCountController = TextEditingController(text: '1');
    _repeatLeadDaysController = TextEditingController(text: '0');
    _suspendedUntilController = TextEditingController();
    _suspendedNoteController = TextEditingController();
    _timeStartController = TextEditingController();
    _timeEndController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _linkTitleController.dispose();
    _linkUriController.dispose();
    _newSubtaskController.dispose();
    _newSubtaskFocusNode.dispose();
    _dueController.dispose();
    _dueNoteController.dispose();
    _repeatCountController.dispose();
    _repeatLeadDaysController.dispose();
    _suspendedUntilController.dispose();
    _suspendedNoteController.dispose();
    _timeStartController.dispose();
    _timeEndController.dispose();
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
      taskV2ControllerProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;
    final prerequisiteCandidates =
        _openSections.contains(TaskSectionKind.prerequisites)
        ? ref.watch(taskPrerequisiteCandidatesProvider(null))
        : const <PrerequisiteCandidateViewModel>[];

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
      child: _TaskDraftCardBody(
        titleController: _titleController,
        placement: _placement,
        allLabels: widget.allLabels,
        allLocations: widget.allLocations,
        prerequisiteCandidates: prerequisiteCandidates,
        hasBothScopedAndGlobalLabels: widget.hasBothScopedAndGlobalLabels,
        currentLocalDateTimeHint: widget.currentLocalDateTimeHint,
        selectedLabelIds: _selectedLabelIds,
        isInlineLabelPickerOpen: _labelPickerOpen,
        isCompact: isCompact,
        openSections: _openSections,
        noteController: _noteController,
        draftLinks: _draftLinks,
        editingLinkIndex: _editingLinkIndex,
        linkTitleController: _linkTitleController,
        linkUriController: _linkUriController,
        linkInputError: _linkInputError,
        subtaskRows: _subtaskRows,
        newSubtaskController: _newSubtaskController,
        newSubtaskFocusNode: _newSubtaskFocusNode,
        subtasksAutoFinish: _subtasksAutoFinish,
        dueController: _dueController,
        dueNoteController: _dueNoteController,
        dueAutoPrioritize: _dueAutoPrioritize,
        repeatCountController: _repeatCountController,
        repeatUnit: _repeatUnit,
        repeatLeadDaysController: _repeatLeadDaysController,
        suspendedIndefinitely: _suspendedIndefinitely,
        suspendedUntilController: _suspendedUntilController,
        suspendedNoteController: _suspendedNoteController,
        selectedPrerequisiteIds: _selectedPrerequisiteIds,
        conditionDraft: _conditionDraft,
        timeStartController: _timeStartController,
        timeEndController: _timeEndController,
        timeInputError: _timeInputError,
        fieldErrors: _fieldErrors,
        isBusy: isBusy,
        spacing: tokens.spacing.space3,
        onClearFieldError: _clearFieldError,
        onSubmitTitle: _triggerCommit,
        onPlacementChanged: _handlePlacementChanged,
        onToggleLabel: _handleToggleLabel,
        onCreateAndAssignLabel: _triggerCreateAndAssignLabel,
        onOpenLabelInfo: _handleOpenLabelInfo,
        onOpenLabelPicker: () => _handleOpenLabelPicker(isCompact: isCompact),
        onCloseLabelPicker: _handleCloseLabelPicker,
        onOpenSection: _handleOpenSection,
        onCloseSection: _handleCloseSection,
        onReorderLinks: _handleReorderLinks,
        onStartEditLink: _handleStartEditLink,
        onDeleteLink: _handleDeleteLink,
        onCommitLinkInput: _handleCommitLinkInput,
        onCancelLinkEdit: _handleCancelLinkEdit,
        onReorderSubtasks: _handleReorderSubtasks,
        onToggleSubtaskDone: _handleToggleSubtaskDone,
        onDeleteSubtask: _handleDeleteSubtask,
        onAddSubtask: _handleAddSubtask,
        onAutoFinishChanged: _handleAutoFinishChanged,
        onDueChanged: _handleDueChanged,
        onDueAutoPrioritizeChanged: _handleDueAutoPrioritizeChanged,
        onRepeatUnitChanged: _handleRepeatUnitChanged,
        onSuspendedModeChanged: _handleSuspendedModeChanged,
        onTogglePrerequisite: _handleTogglePrerequisite,
        onConditionDraftChanged: _handleConditionDraftChanged,
        onAddTimeWindow: _handleAddTimeWindow,
        onRemoveTimeWindow: _handleRemoveTimeWindow,
      ),
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

  /// Appends a new editable subtask row and refocuses [_newSubtaskFocusNode].
  void _handleAddSubtask() {
    final trimmed = _newSubtaskController.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    setState(() {
      _subtaskRows.add(
        _EditableSubtaskRow(
          rowId: _nextSubtaskRowId++,
          initialTitle: trimmed,
          isCompleted: false,
        ),
      );
      _newSubtaskController.clear();
      _submitError = null;
    });
    _clearFieldError('subtasks');
    _newSubtaskFocusNode.requestFocus();
  }

  /// Validates and appends a `HH:MM`..`HH:MM` window onto [_conditionDraft].
  void _handleAddTimeWindow() {
    final localizations = AppLocalizations.of(context);
    final startToken = _timeStartController.text.trim();
    final endToken = _timeEndController.text.trim();
    final startMinutes = _parseTimeMinutes(startToken);
    final endMinutes = _parseTimeMinutes(endToken);
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
      _timeStartController.clear();
      _timeEndController.clear();
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
      _linkTitleController.clear();
      _linkUriController.clear();
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

  /// Validates and commits the entire draft via [TaskV2Controller.createTaskDraft].
  Future<void> _handleCommit() async {
    if (_isSubmitting) {
      return;
    }
    if (_openSections.contains(TaskSectionKind.links)) {
      final hasPendingLink =
          _linkTitleController.text.trim().isNotEmpty ||
          _linkUriController.text.trim().isNotEmpty;
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
        if (_newSubtaskController.text.trim().isNotEmpty)
          SubtaskInput(title: _newSubtaskController.text.trim()),
      ],
    ];
    final input = TaskDraftInput(
      title: _titleController.text,
      note: _openSections.contains(TaskSectionKind.note)
          ? _noteController.text
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
          ? _dueController.text
          : '',
      autoPrioritizeDue: _dueAutoPrioritize,
      rawDueNote: _openSections.contains(TaskSectionKind.due)
          ? _dueNoteController.text
          : '',
      isRepeating: _openSections.contains(TaskSectionKind.repeat),
      rawRepeatCount: _repeatCountController.text,
      repeatUnit: _repeatUnit,
      rawRepeatLeadDays: _repeatLeadDaysController.text,
      isSuspended: _openSections.contains(TaskSectionKind.suspended),
      suspendedIndefinitely: _suspendedIndefinitely,
      rawSuspendedUntil: _suspendedUntilController.text,
      rawSuspendedNote: _suspendedNoteController.text,
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
        .read(taskV2ControllerProvider.notifier)
        .createTaskDraft(input, locale: Localizations.localeOf(context));
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _fieldErrors = fieldErrors;
          _submitError = message;
        });
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Validates and appends/updates the link currently typed into the draft link fields.
  bool _handleCommitLinkInput() {
    final editingIndex = _editingLinkIndex;
    final error = TaskV2Controller.validateLinkInput(
      rawTitle: _linkTitleController.text,
      rawUri: _linkUriController.text,
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
      title: _linkTitleController.text.trim(),
      uri: _linkUriController.text.trim(),
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
      _linkTitleController.clear();
      _linkUriController.clear();
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
        .read(entityV2ControllerProvider.notifier)
        .quickCreateLabel(rawName, locale: locale);
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded(:final entityId):
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
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
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
      _linkTitleController.clear();
      _linkUriController.clear();
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
  void _handleDeleteSubtask(_EditableSubtaskRow row, int index) {
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
  void _handleOpenLabelPicker({required bool isCompact}) {
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
      _linkTitleController.text = link.title;
      _linkUriController.text = link.uri;
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
        _noteController.clear();
      case TaskSectionKind.links:
        _draftLinks = const <EntityLinkInput>[];
        _editingLinkIndex = null;
        _linkTitleController.clear();
        _linkUriController.clear();
        _linkInputError = null;
      case TaskSectionKind.subtasks:
        for (final row in _subtaskRows) {
          row.dispose();
        }
        _subtaskRows.clear();
        _newSubtaskController.clear();
        _subtasksAutoFinish = false;
      case TaskSectionKind.due:
        _dueController.clear();
        _dueNoteController.clear();
        _dueAutoPrioritize = true;
      case TaskSectionKind.repeat:
        _repeatCountController.text = '1';
        _repeatUnit = ShellRepeatUnit.days;
        _repeatLeadDaysController.text = '0';
      case TaskSectionKind.suspended:
        _suspendedIndefinitely = false;
        _suspendedUntilController.clear();
        _suspendedNoteController.clear();
      case TaskSectionKind.prerequisites:
        _selectedPrerequisiteIds.clear();
      case TaskSectionKind.conditions:
        _conditionDraft = ConditionDraftViewModel();
        _timeStartController.clear();
        _timeEndController.clear();
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

/// Composed vertical body of [TaskDraftCard] keeping [_TaskDraftCardState.build] concise.
class _TaskDraftCardBody extends StatelessWidget {
  /// Creates a [_TaskDraftCardBody].
  const _TaskDraftCardBody({
    required this.titleController,
    required this.placement,
    required this.allLabels,
    required this.allLocations,
    required this.prerequisiteCandidates,
    required this.hasBothScopedAndGlobalLabels,
    required this.currentLocalDateTimeHint,
    required this.selectedLabelIds,
    required this.isInlineLabelPickerOpen,
    required this.isCompact,
    required this.openSections,
    required this.noteController,
    required this.draftLinks,
    required this.editingLinkIndex,
    required this.linkTitleController,
    required this.linkUriController,
    required this.linkInputError,
    required this.subtaskRows,
    required this.newSubtaskController,
    required this.newSubtaskFocusNode,
    required this.subtasksAutoFinish,
    required this.dueController,
    required this.dueNoteController,
    required this.dueAutoPrioritize,
    required this.repeatCountController,
    required this.repeatUnit,
    required this.repeatLeadDaysController,
    required this.suspendedIndefinitely,
    required this.suspendedUntilController,
    required this.suspendedNoteController,
    required this.selectedPrerequisiteIds,
    required this.conditionDraft,
    required this.timeStartController,
    required this.timeEndController,
    required this.timeInputError,
    required this.fieldErrors,
    required this.isBusy,
    required this.spacing,
    required this.onClearFieldError,
    required this.onSubmitTitle,
    required this.onPlacementChanged,
    required this.onToggleLabel,
    required this.onCreateAndAssignLabel,
    required this.onOpenLabelInfo,
    required this.onOpenLabelPicker,
    required this.onCloseLabelPicker,
    required this.onOpenSection,
    required this.onCloseSection,
    required this.onReorderLinks,
    required this.onStartEditLink,
    required this.onDeleteLink,
    required this.onCommitLinkInput,
    required this.onCancelLinkEdit,
    required this.onReorderSubtasks,
    required this.onToggleSubtaskDone,
    required this.onDeleteSubtask,
    required this.onAddSubtask,
    required this.onAutoFinishChanged,
    required this.onDueChanged,
    required this.onDueAutoPrioritizeChanged,
    required this.onRepeatUnitChanged,
    required this.onSuspendedModeChanged,
    required this.onTogglePrerequisite,
    required this.onConditionDraftChanged,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
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

  /// Due timestamp controller.
  final TextEditingController dueController;

  /// Due note controller.
  final TextEditingController dueNoteController;

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

  /// Link title controller.
  final TextEditingController linkTitleController;

  /// Link URI controller.
  final TextEditingController linkUriController;

  /// New subtask controller.
  final TextEditingController newSubtaskController;

  /// New subtask focus node.
  final FocusNode newSubtaskFocusNode;

  /// Note controller.
  final TextEditingController noteController;

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
  final UiOrderedItemActionCallback<_EditableSubtaskRow> onDeleteSubtask;

  /// Callback toggling due auto-prioritize flag.
  final ValueChanged<bool> onDueAutoPrioritizeChanged;

  /// Callback notified on due text change.
  final ValueChanged<String> onDueChanged;

  /// Callback navigating to a label card.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback opening the label picker.
  final VoidCallback onOpenLabelPicker;

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

  /// Open optional sections.
  final Set<TaskSectionKind> openSections;

  /// Selected placement mode.
  final TaskPlacementOption placement;

  /// Prerequisite candidate tasks.
  final List<PrerequisiteCandidateViewModel> prerequisiteCandidates;

  /// Repeat count controller.
  final TextEditingController repeatCountController;

  /// Repeat lead days controller.
  final TextEditingController repeatLeadDaysController;

  /// Selected repeat unit.
  final ShellRepeatUnit repeatUnit;

  /// Selected label identifiers.
  final Set<String> selectedLabelIds;

  /// Selected prerequisite task identifiers.
  final Set<String> selectedPrerequisiteIds;

  /// Vertical spacing between draft sections.
  final double spacing;

  /// Draft subtask rows.
  final List<_EditableSubtaskRow> subtaskRows;

  /// Subtasks auto-finish flag.
  final bool subtasksAutoFinish;

  /// Whether indefinite suspension is chosen.
  final bool suspendedIndefinitely;

  /// Suspension note controller.
  final TextEditingController suspendedNoteController;

  /// Suspension until timestamp controller.
  final TextEditingController suspendedUntilController;

  /// Time window end controller.
  final TextEditingController timeEndController;

  /// Time window inline error.
  final String? timeInputError;

  /// Time window start controller.
  final TextEditingController timeStartController;

  /// Draft title controller.
  final TextEditingController titleController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final showLabelsSection =
        selectedLabelIds.isNotEmpty || (isInlineLabelPickerOpen && !isCompact);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiField(
          key: const ValueKey<String>('task_draft_title_input'),
          kind: UiFieldKind.text,
          controller: titleController,
          hintText: localizations.taskNameLabel,
          maxLength: _maxSingleLineLength,
          autofocus: true,
          enabled: !isBusy,
          errorText: fieldErrors['title'],
          textInputAction: TextInputAction.done,
          onChanged: (_) => onClearFieldError('title'),
          onSubmitted: (_) => onSubmitTitle(),
        ),
        SizedBox(height: spacing),
        _DraftPlacementCard(
          placement: placement,
          isBusy: isBusy,
          onChanged: onPlacementChanged,
        ),
        if (showLabelsSection) ...<Widget>[
          SizedBox(height: spacing),
          _DraftLabelsSection(
            allLabels: allLabels,
            selectedIds: selectedLabelIds,
            hasBothScopedAndGlobal: hasBothScopedAndGlobalLabels,
            isInlinePickerOpen: isInlineLabelPickerOpen,
            isCompact: isCompact,
            isBusy: isBusy,
            onToggleLabel: onToggleLabel,
            onCreateAndAssign: onCreateAndAssignLabel,
            onOpenLabelInfo: onOpenLabelInfo,
            onOpenPicker: onOpenLabelPicker,
            onClosePicker: onCloseLabelPicker,
          ),
        ],
        _TaskDraftOptionalSections(
          openSections: openSections,
          spacing: spacing,
          noteController: noteController,
          draftLinks: draftLinks,
          editingLinkIndex: editingLinkIndex,
          linkTitleController: linkTitleController,
          linkUriController: linkUriController,
          linkInputError: linkInputError,
          subtaskRows: subtaskRows,
          newSubtaskController: newSubtaskController,
          newSubtaskFocusNode: newSubtaskFocusNode,
          subtasksAutoFinish: subtasksAutoFinish,
          dueController: dueController,
          dueNoteController: dueNoteController,
          dueAutoPrioritize: dueAutoPrioritize,
          currentLocalDateTimeHint: currentLocalDateTimeHint,
          repeatCountController: repeatCountController,
          repeatUnit: repeatUnit,
          repeatLeadDaysController: repeatLeadDaysController,
          suspendedIndefinitely: suspendedIndefinitely,
          suspendedUntilController: suspendedUntilController,
          suspendedNoteController: suspendedNoteController,
          prerequisiteCandidates: prerequisiteCandidates,
          selectedPrerequisiteIds: selectedPrerequisiteIds,
          conditionDraft: conditionDraft,
          allLocations: allLocations,
          timeStartController: timeStartController,
          timeEndController: timeEndController,
          timeInputError: timeInputError,
          fieldErrors: fieldErrors,
          isBusy: isBusy,
          onClearFieldError: onClearFieldError,
          onCloseSection: onCloseSection,
          onReorderLinks: onReorderLinks,
          onStartEditLink: onStartEditLink,
          onDeleteLink: onDeleteLink,
          onCommitLinkInput: onCommitLinkInput,
          onCancelLinkEdit: onCancelLinkEdit,
          onReorderSubtasks: onReorderSubtasks,
          onToggleSubtaskDone: onToggleSubtaskDone,
          onDeleteSubtask: onDeleteSubtask,
          onAddSubtask: onAddSubtask,
          onAutoFinishChanged: onAutoFinishChanged,
          onDueChanged: onDueChanged,
          onDueAutoPrioritizeChanged: onDueAutoPrioritizeChanged,
          onRepeatUnitChanged: onRepeatUnitChanged,
          onSuspendedModeChanged: onSuspendedModeChanged,
          onTogglePrerequisite: onTogglePrerequisite,
          onConditionDraftChanged: onConditionDraftChanged,
          onAddTimeWindow: onAddTimeWindow,
          onRemoveTimeWindow: onRemoveTimeWindow,
        ),
        SizedBox(height: spacing),
        _DraftAddSectionsBar(
          openSections: openSections,
          showLabelsChip: !showLabelsSection,
          isBusy: isBusy,
          onOpenLabels: onOpenLabelPicker,
          onOpenSection: onOpenSection,
        ),
      ],
    );
  }
}

/// Optional toggleable sections list inside [_TaskDraftCardBody].
class _TaskDraftOptionalSections extends StatelessWidget {
  /// Creates a [_TaskDraftOptionalSections].
  const _TaskDraftOptionalSections({
    required this.openSections,
    required this.spacing,
    required this.noteController,
    required this.draftLinks,
    required this.editingLinkIndex,
    required this.linkTitleController,
    required this.linkUriController,
    required this.linkInputError,
    required this.subtaskRows,
    required this.newSubtaskController,
    required this.newSubtaskFocusNode,
    required this.subtasksAutoFinish,
    required this.dueController,
    required this.dueNoteController,
    required this.dueAutoPrioritize,
    required this.currentLocalDateTimeHint,
    required this.repeatCountController,
    required this.repeatUnit,
    required this.repeatLeadDaysController,
    required this.suspendedIndefinitely,
    required this.suspendedUntilController,
    required this.suspendedNoteController,
    required this.prerequisiteCandidates,
    required this.selectedPrerequisiteIds,
    required this.conditionDraft,
    required this.allLocations,
    required this.timeStartController,
    required this.timeEndController,
    required this.timeInputError,
    required this.fieldErrors,
    required this.isBusy,
    required this.onClearFieldError,
    required this.onCloseSection,
    required this.onReorderLinks,
    required this.onStartEditLink,
    required this.onDeleteLink,
    required this.onCommitLinkInput,
    required this.onCancelLinkEdit,
    required this.onReorderSubtasks,
    required this.onToggleSubtaskDone,
    required this.onDeleteSubtask,
    required this.onAddSubtask,
    required this.onAutoFinishChanged,
    required this.onDueChanged,
    required this.onDueAutoPrioritizeChanged,
    required this.onRepeatUnitChanged,
    required this.onSuspendedModeChanged,
    required this.onTogglePrerequisite,
    required this.onConditionDraftChanged,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
  });

  /// Workspace locations.
  final List<LocationOptionViewModel> allLocations;

  /// Condition draft model.
  final ConditionDraftViewModel conditionDraft;

  /// Current local timestamp hint.
  final String currentLocalDateTimeHint;

  /// Draft links list.
  final List<EntityLinkInput> draftLinks;

  /// Auto-prioritize due flag.
  final bool dueAutoPrioritize;

  /// Due controller.
  final TextEditingController dueController;

  /// Due note controller.
  final TextEditingController dueNoteController;

  /// Active inline link edit index.
  final int? editingLinkIndex;

  /// Field validation errors.
  final Map<String, String> fieldErrors;

  /// Whether commit is in flight.
  final bool isBusy;

  /// Inline link input error.
  final String? linkInputError;

  /// Link title controller.
  final TextEditingController linkTitleController;

  /// Link URI controller.
  final TextEditingController linkUriController;

  /// New subtask controller.
  final TextEditingController newSubtaskController;

  /// New subtask focus node.
  final FocusNode newSubtaskFocusNode;

  /// Note controller.
  final TextEditingController noteController;

  /// Callback adding a subtask.
  final VoidCallback onAddSubtask;

  /// Callback adding a time window.
  final VoidCallback onAddTimeWindow;

  /// Callback updating auto-finish.
  final ValueChanged<bool> onAutoFinishChanged;

  /// Callback cancelling link row edit.
  final VoidCallback onCancelLinkEdit;

  /// Callback clearing a field error.
  final ValueChanged<String> onClearFieldError;

  /// Callback closing an optional section.
  final ValueChanged<TaskSectionKind> onCloseSection;

  /// Callback committing typed link input.
  final VoidCallback onCommitLinkInput;

  /// Callback updating condition draft.
  final ValueChanged<ConditionDraftViewModel> onConditionDraftChanged;

  /// Callback deleting a link row.
  final UiOrderedItemActionCallback<EntityLinkInput> onDeleteLink;

  /// Callback deleting a subtask row.
  final UiOrderedItemActionCallback<_EditableSubtaskRow> onDeleteSubtask;

  /// Callback toggling due auto-prioritize.
  final ValueChanged<bool> onDueAutoPrioritizeChanged;

  /// Callback notified on due text change.
  final ValueChanged<String> onDueChanged;

  /// Callback removing a time window.
  final ValueChanged<int> onRemoveTimeWindow;

  /// Callback reordering links.
  final UiOrderedItemReorderCallback onReorderLinks;

  /// Callback reordering subtasks.
  final UiOrderedItemReorderCallback onReorderSubtasks;

  /// Callback updating repeat unit.
  final ValueChanged<ShellRepeatUnit> onRepeatUnitChanged;

  /// Callback starting inline link row edit.
  final UiOrderedItemActionCallback<EntityLinkInput> onStartEditLink;

  /// Callback changing suspension mode.
  final ValueChanged<bool> onSuspendedModeChanged;

  /// Callback toggling a prerequisite task.
  final ValueChanged<String> onTogglePrerequisite;

  /// Callback toggling a subtask row's completion.
  final ValueChanged<int> onToggleSubtaskDone;

  /// Currently open optional sections.
  final Set<TaskSectionKind> openSections;

  /// Selectable prerequisite tasks.
  final List<PrerequisiteCandidateViewModel> prerequisiteCandidates;

  /// Repeat count controller.
  final TextEditingController repeatCountController;

  /// Repeat lead days controller.
  final TextEditingController repeatLeadDaysController;

  /// Selected repeat unit.
  final ShellRepeatUnit repeatUnit;

  /// Selected prerequisite IDs.
  final Set<String> selectedPrerequisiteIds;

  /// Vertical section spacing.
  final double spacing;

  /// Subtask rows.
  final List<_EditableSubtaskRow> subtaskRows;

  /// Auto-finish flag.
  final bool subtasksAutoFinish;

  /// Indefinite suspension flag.
  final bool suspendedIndefinitely;

  /// Deferral note controller.
  final TextEditingController suspendedNoteController;

  /// Suspended until controller.
  final TextEditingController suspendedUntilController;

  /// Time window end controller.
  final TextEditingController timeEndController;

  /// Time window error text.
  final String? timeInputError;

  /// Time window start controller.
  final TextEditingController timeStartController;

  @override
  Widget build(BuildContext context) {
    final hasDueDate =
        openSections.contains(TaskSectionKind.due) &&
        dueController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (openSections.contains(TaskSectionKind.note)) ...<Widget>[
          SizedBox(height: spacing),
          _DraftNoteCard(
            controller: noteController,
            errorText: fieldErrors['note'],
            isBusy: isBusy,
            onChanged: (_) => onClearFieldError('note'),
            onClose: () => onCloseSection(TaskSectionKind.note),
          ),
        ],
        if (openSections.contains(TaskSectionKind.links)) ...<Widget>[
          SizedBox(height: spacing),
          _DraftLinksCard(
            links: draftLinks,
            editingIndex: editingLinkIndex,
            titleController: linkTitleController,
            uriController: linkUriController,
            inputError: linkInputError,
            sectionError: fieldErrors['links'],
            isBusy: isBusy,
            onReorder: onReorderLinks,
            onStartEdit: onStartEditLink,
            onDelete: onDeleteLink,
            onCommitInput: onCommitLinkInput,
            onCancelRowEdit: onCancelLinkEdit,
            onClose: () => onCloseSection(TaskSectionKind.links),
          ),
        ],
        if (openSections.contains(TaskSectionKind.subtasks)) ...<Widget>[
          SizedBox(height: spacing),
          _DraftSubtasksCard(
            rows: subtaskRows,
            newStepController: newSubtaskController,
            newStepFocusNode: newSubtaskFocusNode,
            autoFinish: subtasksAutoFinish,
            errorText: fieldErrors['subtasks'],
            isBusy: isBusy,
            onReorder: onReorderSubtasks,
            onToggleRowDone: onToggleSubtaskDone,
            onDeleteRow: onDeleteSubtask,
            onAddRow: onAddSubtask,
            onAutoFinishChanged: onAutoFinishChanged,
            onClose: () => onCloseSection(TaskSectionKind.subtasks),
          ),
        ],
        if (openSections.contains(TaskSectionKind.due)) ...<Widget>[
          SizedBox(height: spacing),
          _DraftDueCard(
            dueController: dueController,
            dueNoteController: dueNoteController,
            autoPrioritize: dueAutoPrioritize,
            currentLocalDateTimeHint: currentLocalDateTimeHint,
            dueError: fieldErrors['due'],
            dueNoteError: fieldErrors['dueNote'],
            isBusy: isBusy,
            onDueChanged: onDueChanged,
            onAutoPrioritizeChanged: onDueAutoPrioritizeChanged,
            onDueNoteChanged: (_) => onClearFieldError('dueNote'),
            onClose: () => onCloseSection(TaskSectionKind.due),
          ),
        ],
        if (openSections.contains(TaskSectionKind.repeat)) ...<Widget>[
          SizedBox(height: spacing),
          _DraftRepeatCard(
            countController: repeatCountController,
            unit: repeatUnit,
            leadDaysController: repeatLeadDaysController,
            hasDueDate: hasDueDate,
            countError: fieldErrors['repeatCount'],
            leadError: fieldErrors['repeatLeadDays'],
            isBusy: isBusy,
            onCountChanged: (_) => onClearFieldError('repeatCount'),
            onUnitChanged: onRepeatUnitChanged,
            onLeadChanged: (_) => onClearFieldError('repeatLeadDays'),
            onClose: () => onCloseSection(TaskSectionKind.repeat),
          ),
        ],
        if (openSections.contains(TaskSectionKind.suspended)) ...<Widget>[
          SizedBox(height: spacing),
          _DraftSuspendedCard(
            indefinitely: suspendedIndefinitely,
            untilController: suspendedUntilController,
            noteController: suspendedNoteController,
            currentLocalDateTimeHint: currentLocalDateTimeHint,
            untilError: fieldErrors['suspended'],
            noteError: fieldErrors['suspendedNote'],
            isBusy: isBusy,
            onModeChanged: onSuspendedModeChanged,
            onUntilChanged: (_) => onClearFieldError('suspended'),
            onNoteChanged: (_) => onClearFieldError('suspendedNote'),
            onClose: () => onCloseSection(TaskSectionKind.suspended),
          ),
        ],
        if (openSections.contains(TaskSectionKind.prerequisites)) ...<Widget>[
          SizedBox(height: spacing),
          _DraftPrerequisitesCard(
            candidates: prerequisiteCandidates,
            selectedIds: selectedPrerequisiteIds,
            errorText: fieldErrors['prerequisites'],
            isBusy: isBusy,
            onTogglePrerequisite: onTogglePrerequisite,
            onClose: () => onCloseSection(TaskSectionKind.prerequisites),
          ),
        ],
        if (openSections.contains(TaskSectionKind.conditions)) ...<Widget>[
          SizedBox(height: spacing),
          _DraftConditionsCard(
            draft: conditionDraft,
            allLocations: allLocations,
            isSuspended: openSections.contains(TaskSectionKind.suspended),
            timeStartController: timeStartController,
            timeEndController: timeEndController,
            timeInputError: timeInputError,
            sectionError: fieldErrors['conditions'],
            isBusy: isBusy,
            onDraftChanged: onConditionDraftChanged,
            onAddTimeWindow: onAddTimeWindow,
            onRemoveTimeWindow: onRemoveTimeWindow,
            onClose: () => onCloseSection(TaskSectionKind.conditions),
          ),
        ],
      ],
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
    final tokens = UiThemeTokens.of(context);

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
      child: Column(
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
          SizedBox(height: tokens.spacing.space2),
          UiToggleRow(
            label: localizations.taskDueAutoPrioritizeLabel,
            description: localizations.taskDueAutoPrioritizeSubtitle,
            value: autoPrioritize,
            isDense: true,
            enabled: !isBusy,
            onChanged: onAutoPrioritizeChanged,
          ),
          SizedBox(height: tokens.spacing.space2),
          UiField(
            kind: UiFieldKind.multiline,
            controller: dueNoteController,
            label: localizations.taskDueNoteLabel,
            hintText: localizations.taskDueNoteHint,
            maxLength: _maxNoteLength,
            minLines: 2,
            maxLines: 4,
            enabled: !isBusy,
            errorText: dueNoteError,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Read-only display card for [TaskDueSection].
class _TaskDueReadCard extends StatelessWidget {
  /// Creates a [_TaskDueReadCard].
  const _TaskDueReadCard({
    required this.task,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final dueColor = !task.isCompleted && task.isOverdue
        ? colors.danger
        : (!task.isCompleted && task.isWithinDueLeadWindow
              ? colors.warning
              : colors.ink);

    return UiCard.inset(
      key: ValueKey<String>('task_due_read_${task.id}'),
      headerIcon: Icons.calendar_today_outlined,
      headerTitle: localizations.taskInfoDueLabel,
      headerTrailing: task.isCompleted
          ? null
          : UiButton(
              key: ValueKey<String>('task_due_edit_button_${task.id}'),
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.sidebarDesktop,
              tooltip: localizations.actionEdit,
              onPressed: isBusy ? null : onStartEdit,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            task.dueFormatted ?? '',
            style: tokens.typography.control.copyWith(color: dueColor),
          ),
          if (!task.isCompleted &&
              task.dueAutoPriorityLabel != null) ...<Widget>[
            const SizedBox(height: 4.0),
            Text(
              task.dueAutoPriorityLabel ?? '',
              style: tokens.typography.meta.copyWith(color: colors.muted),
            ),
          ],
          if (task.dueAnchorFormatted case final anchor?) ...<Widget>[
            const SizedBox(height: 4.0),
            Text(
              anchor,
              style: UiTypographyTokens.mono(
                tokens.typography.monoSmall.copyWith(color: colors.muted),
              ),
            ),
          ],
          if (task.dueNote case final note? when note.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6.0),
            Text(
              note,
              style: tokens.typography.meta.copyWith(color: colors.ink),
            ),
          ],
        ],
      ),
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

  @override
  void initState() {
    super.initState();
    _dueController = TextEditingController(text: widget.task.dueInputInitial);
    _dueNoteController = TextEditingController(text: widget.task.dueNote ?? '');
    _autoPrioritize = !widget.task.isDuePassive;
  }

  @override
  void didUpdateWidget(covariant TaskDueSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _dueController.text = widget.task.dueInputInitial;
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
      taskV2ControllerProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;

    if (!widget.isEditing || widget.task.isCompleted) {
      return widget.task.dueFormatted == null
          ? const SizedBox.shrink()
          : _TaskDueReadCard(
              task: widget.task,
              isBusy: isBusy,
              onStartEdit: widget.onStartEdit,
            );
    }

    return _TaskDueEditCard(
      dueController: _dueController,
      dueNoteController: _dueNoteController,
      autoPrioritize: _autoPrioritize,
      hasExistingDue: widget.task.dueFormatted != null,
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

  /// Clears the persisted due date via [TaskV2Controller.clearDue].
  Future<void> _handleClear() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
        .clearDue(widget.task.id, locale: Localizations.localeOf(context));
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Saves the edited due date via [TaskV2Controller.saveDue].
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
        .read(taskV2ControllerProvider.notifier)
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
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _dueError = fieldErrors['due'];
          _dueNoteError = fieldErrors['dueNote'];
          _submitError = (_dueError == null && _dueNoteError == null)
              ? message
              : null;
        });
      case V2ActionPersistFailed(:final message):
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
    final localizations = AppLocalizations.of(context);
    final isControllerBusy = ref.watch(
      taskV2ControllerProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;

    return UiCard.inset(
      key: ValueKey<String>('task_history_section_${widget.task.id}'),
      headerIcon: Icons.history_rounded,
      headerTitle: localizations.historySectionTitle,
      headerBadge: UiPill(
        label: '${widget.task.history.length} / ${widget.task.maxHistoryCount}',
        variant: UiPillVariant.count,
      ),
      child: UiOrderedItemList<HistoryEntryViewModel>(
        items: widget.task.history,
        editingIndex: _editingIndex,
        emptyText: localizations.historyEmptyHint,
        itemKey: (entry, index) => ValueKey<String>(
          'history_entry_${widget.task.id}_${entry.index}_${entry.timestampUtcIso}',
        ),
        onEdit: isBusy ? null : _handleStartEdit,
        editTooltip: localizations.tooltipEditHistoryEntry,
        onDelete: isBusy ? null : _triggerDeleteEntry,
        deleteTooltip: localizations.tooltipDeleteHistoryEntry,
        itemBuilder: (context, entry, index, isEditing) => isEditing
            ? _HistoryEditRow(
                taskId: widget.task.id,
                index: index,
                fallbackLocalTimestamp: entry.formattedLocalTimestamp,
                textController: _editTextController,
                timestampController: _editTimestampController,
                isBusy: isBusy,
                onChanged: _handleInputChanged,
                onSave: _triggerSaveEdit,
                onCancel: _handleCancelEdit,
              )
            : _HistoryReadRow(entry: entry),
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

  /// Appends a new history entry via [TaskV2Controller.addHistoryEntry].
  Future<void> _handleAddEntry() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
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
    switch (result) {
      case V2ActionSucceeded():
        setState(() {
          _isSubmitting = false;
          _errorText = null;
          _showAddTimestamp = false;
          _addTextController.clear();
          _addTimestampController.clear();
        });
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
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

  /// Removes [entry] via [TaskV2Controller.deleteHistoryEntry].
  Future<void> _handleDeleteEntry(
    HistoryEntryViewModel entry,
    int index,
  ) async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
        .deleteHistoryEntry(
          widget.task.id,
          timestampUtcIso: entry.timestampUtcIso,
          text: entry.text,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() {
          _isSubmitting = false;
          if (_editingIndex == index) {
            _editingIndex = null;
            _editingOldText = null;
            _editingOldTimestampUtcIso = null;
          }
        });
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
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
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
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
    switch (result) {
      case V2ActionSucceeded():
        setState(() {
          _isSubmitting = false;
          _editingIndex = null;
          _editingOldText = null;
          _editingOldTimestampUtcIso = null;
          _errorText = null;
        });
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }

  /// Opens inline editing for [entry] at [index].
  void _handleStartEdit(HistoryEntryViewModel entry, int index) {
    setState(() {
      _editingIndex = index;
      _editingOldTimestampUtcIso = entry.timestampUtcIso;
      _editingOldText = entry.text;
      _editTextController.text = entry.text;
      _editTimestampController.text = entry.formattedLocalTimestamp;
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
  void _triggerDeleteEntry(HistoryEntryViewModel entry, int index) {
    unawaited(_handleDeleteEntry(entry, index));
  }

  /// Dispatches async history row save from synchronous UI callbacks.
  void _triggerSaveEdit() => unawaited(_handleSaveEdit());
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
    final localizations = AppLocalizations.of(context);
    final isControllerBusy = ref.watch(
      taskV2ControllerProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: UiField(
                key: ValueKey<String>(
                  'task_title_editor_input_${widget.taskId}',
                ),
                kind: UiFieldKind.text,
                controller: _controller,
                maxLength: _maxSingleLineLength,
                autofocus: true,
                enabled: !isBusy,
                errorText: _errorText,
                semanticLabel: localizations.inlineEditTitleTooltip,
                textInputAction: TextInputAction.done,
                onChanged: _handleChanged,
                onSubmitted: (_) => _triggerSave(),
              ),
            ),
            const SizedBox(width: 6.0),
            UiButton(
              key: ValueKey<String>('task_title_editor_save_${widget.taskId}'),
              label: localizations.actionSave,
              variant: UiButtonVariant.primary,
              density: UiButtonDensity.compact,
              isLoading: isBusy,
              onPressed: isBusy ? null : _triggerSave,
            ),
            const SizedBox(width: 6.0),
            UiButton(
              key: ValueKey<String>(
                'task_title_editor_cancel_${widget.taskId}',
              ),
              label: localizations.actionCancel,
              variant: UiButtonVariant.secondary,
              density: UiButtonDensity.compact,
              onPressed: isBusy ? null : widget.onCancel,
            ),
          ],
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

  /// Persists the edited title through [TaskV2Controller.saveTitle].
  Future<void> _handleSave() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
        .saveTitle(
          widget.taskId,
          _controller.text,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }

  /// Dispatches async title save from synchronous field/button callbacks.
  void _triggerSave() => unawaited(_handleSave());
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
  final List<PrerequisiteCandidateViewModel> candidates;

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
    final tokens = UiThemeTokens.of(context);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            localizations.taskBlockedBySectionDescription,
            style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
          ),
          SizedBox(height: tokens.spacing.space2),
          UiSearchablePicker<String>(
            options: <UiPickerOption<String>>[
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
            ],
            selectedIds: selectedIds,
            autoFocusSearch: true,
            searchMaxLength: _maxSingleLineLength,
            searchPlaceholder: localizations.blockedBySearchHint,
            searchClearTooltip: localizations.tooltipClearSearch,
            emptyText: localizations.blockedBySearchNoResults,
            onToggleOption: (option) {
              if (!isBusy) {
                onToggleOption(option.value);
              }
            },
            onRequestClose: onCancel,
          ),
        ],
      ),
    );
  }
}

/// Read-only display card for [TaskPrerequisitesSection].
class _TaskPrerequisitesReadCard extends StatelessWidget {
  /// Creates a [_TaskPrerequisitesReadCard].
  const _TaskPrerequisitesReadCard({
    required this.task,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return UiCard.inset(
      key: ValueKey<String>('task_prerequisites_read_${task.id}'),
      headerIcon: Icons.lock_outline_rounded,
      headerTitle: localizations.taskBlockedBySectionTitle,
      headerBadge: task.prerequisitesProgressLabel != null
          ? UiPill(
              label: task.prerequisitesProgressLabel ?? '',
              variant: UiPillVariant.count,
            )
          : null,
      headerTrailing: task.isCompleted
          ? null
          : UiButton(
              key: ValueKey<String>(
                'task_prerequisites_edit_button_${task.id}',
              ),
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.sidebarDesktop,
              tooltip: localizations.actionEdit,
              onPressed: isBusy ? null : onStartEdit,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final item in task.prerequisites)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Row(
                children: <Widget>[
                  ExcludeSemantics(
                    child: Icon(
                      item.isSatisfied
                          ? Icons.check_circle_outline_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: tokens.spacing.iconSm,
                      color: item.isSatisfied ? colors.success : colors.warning,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      item.title,
                      style: tokens.typography.control.copyWith(
                        color: item.isSatisfied ? colors.muted : colors.ink,
                        decoration: item.isSatisfied
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
      for (final item in widget.task.prerequisites) item.id,
    };
  }

  @override
  void didUpdateWidget(covariant TaskPrerequisitesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _selectedIds = <String>{
        for (final item in widget.task.prerequisites) item.id,
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
      taskV2ControllerProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;

    if (!widget.isEditing || widget.task.isCompleted) {
      return widget.task.prerequisites.isEmpty
          ? const SizedBox.shrink()
          : _TaskPrerequisitesReadCard(
              task: widget.task,
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
      hasExistingPrerequisites: widget.task.prerequisites.isNotEmpty,
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

  /// Persists [prerequisiteIds] via [TaskV2Controller.savePrerequisites].
  Future<void> _submitPrerequisites(List<String> prerequisiteIds) async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
        .savePrerequisites(
          widget.task.id,
          prerequisiteIds,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }

  /// Dispatches clearing all prerequisites.
  void _triggerClear() => unawaited(_submitPrerequisites(const <String>[]));

  /// Dispatches saving selected prerequisites.
  void _triggerSave() =>
      unawaited(_submitPrerequisites(_selectedIds.toList(growable: false)));
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
  final ValueChanged<ShellRepeatUnit> onUnitChanged;

  /// Optional general persistence error.
  final String? submitError;

  /// Selected recurrence unit.
  final ShellRepeatUnit unit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiField(
            kind: UiFieldKind.text,
            controller: countController,
            label: localizations.repeatIntervalLabel,
            hintText: '1',
            keyboardType: TextInputType.number,
            autofocus: true,
            enabled: !isBusy,
            errorText: countError,
            onChanged: onChanged,
            onSubmitted: (_) => onSave(),
          ),
          SizedBox(height: tokens.spacing.space2),
          UiSegmentedControl<ShellRepeatUnit>(
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
          ),
          SizedBox(height: tokens.spacing.space2),
          UiField(
            kind: UiFieldKind.text,
            controller: leadDaysController,
            label: localizations.repeatLeadDaysLabel,
            hintText: localizations.repeatLeadDaysHint,
            helperText: hasDueDate
                ? null
                : localizations.inlineRepeatLeadNeedsDueHint,
            keyboardType: TextInputType.number,
            enabled: !isBusy && hasDueDate,
            errorText: leadError,
            onChanged: onChanged,
            onSubmitted: (_) => onSave(),
          ),
        ],
      ),
    );
  }
}

/// Read-only display card for [TaskRepeatSection].
class _TaskRepeatReadCard extends StatelessWidget {
  /// Creates a [_TaskRepeatReadCard].
  const _TaskRepeatReadCard({
    required this.task,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return UiCard.inset(
      key: ValueKey<String>('task_repeat_read_${task.id}'),
      headerIcon: Icons.repeat_rounded,
      headerTitle: localizations.repeatFlagLabel,
      headerTrailing: task.isCompleted
          ? null
          : UiButton(
              key: ValueKey<String>('task_repeat_edit_button_${task.id}'),
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.sidebarDesktop,
              tooltip: localizations.actionEdit,
              onPressed: isBusy ? null : onStartEdit,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            task.repeatSummary ?? '',
            style: tokens.typography.control.copyWith(color: colors.ink),
          ),
          if (task.repeatCompletionsLabel case final completions?) ...<Widget>[
            const SizedBox(height: 4.0),
            Text(
              completions,
              style: tokens.typography.meta.copyWith(color: colors.muted),
            ),
          ],
          if (task.repeatLeadLabel case final lead?) ...<Widget>[
            const SizedBox(height: 4.0),
            Text(
              lead,
              style: tokens.typography.meta.copyWith(color: colors.muted),
            ),
          ],
        ],
      ),
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
  late ShellRepeatUnit _unit;

  @override
  void initState() {
    super.initState();
    _countController = TextEditingController(
      text: '${widget.task.repeatCount ?? 1}',
    );
    _leadDaysController = TextEditingController(
      text: '${widget.task.repeatLeadDays ?? 0}',
    );
    _unit = widget.task.repeatUnit ?? ShellRepeatUnit.days;
  }

  @override
  void didUpdateWidget(covariant TaskRepeatSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _countController.text = '${widget.task.repeatCount ?? 1}';
      _leadDaysController.text = '${widget.task.repeatLeadDays ?? 0}';
      _unit = widget.task.repeatUnit ?? ShellRepeatUnit.days;
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
      taskV2ControllerProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;

    if (!widget.isEditing || widget.task.isCompleted) {
      return widget.task.repeatSummary == null
          ? const SizedBox.shrink()
          : _TaskRepeatReadCard(
              task: widget.task,
              isBusy: isBusy,
              onStartEdit: widget.onStartEdit,
            );
    }

    return _TaskRepeatEditCard(
      countController: _countController,
      unit: _unit,
      leadDaysController: _leadDaysController,
      hasDueDate: widget.task.dueFormatted != null,
      hasExistingRepeat: widget.task.repeatSummary != null,
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

  /// Disables recurrence via [TaskV2Controller.disableRepeat].
  Future<void> _handleDisable() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
        .disableRepeat(widget.task.id, locale: Localizations.localeOf(context));
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Saves edited recurrence parameters via [TaskV2Controller.saveRepeat].
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
        .read(taskV2ControllerProvider.notifier)
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
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _countError = fieldErrors['repeatCount'];
          _leadError = fieldErrors['repeatLeadDays'];
          _submitError = (_countError == null && _leadError == null)
              ? message
              : null;
        });
      case V2ActionPersistFailed(:final message):
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
  final UiOrderedItemActionCallback<_EditableSubtaskRow> onDeleteRow;

  /// Callback reordering subtask rows.
  final UiOrderedItemReorderCallback onReorder;

  /// Callback saving edited subtasks.
  final VoidCallback onSave;

  /// Callback toggling completion of a subtask row.
  final ValueChanged<int> onToggleRowDone;

  /// Editable subtask rows.
  final List<_EditableSubtaskRow> rows;

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
      headerBadge: UiPill(
        label: '${rows.length}',
        variant: UiPillVariant.count,
      ),
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
      child: UiOrderedItemList<_EditableSubtaskRow>(
        items: rows,
        itemKey: (row, index) =>
            ValueKey<String>('subtask_edit_row_${taskId}_${row.rowId}'),
        onReorder: isBusy ? null : onReorder,
        onDelete: isBusy ? null : onDeleteRow,
        deleteTooltip: localizations.tooltipRemoveSubtask,
        itemBuilder: (context, row, index, isEditing) => Row(
          children: <Widget>[
            _SubtaskCheckBoxButton(
              checked: row.isCompleted,
              enabled: !isBusy,
              semanticLabel: row.controller.text,
              onToggle: () => onToggleRowDone(index),
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
        ),
        addBar: Row(
          children: <Widget>[
            Expanded(
              child: UiField(
                key: ValueKey<String>('subtask_add_input_$taskId'),
                kind: UiFieldKind.text,
                controller: newStepController,
                focusNode: newStepFocusNode,
                hintText: localizations.subtaskInputHint,
                maxLength: _maxSingleLineLength,
                autofocus: rows.isEmpty,
                enabled: !isBusy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAddRow(),
              ),
            ),
            const SizedBox(width: 8.0),
            UiButton(
              key: ValueKey<String>('subtask_add_button_$taskId'),
              label: localizations.actionAdd,
              variant: UiButtonVariant.secondary,
              density: UiButtonDensity.compact,
              tooltip: localizations.tooltipAddSubtask,
              onPressed: isBusy ? null : onAddRow,
            ),
          ],
        ),
        footer: UiToggleRow(
          key: ValueKey<String>('subtask_auto_finish_toggle_$taskId'),
          label: localizations.subtasksAutoFinishLabel,
          description: localizations.tooltipTaskEditorAutoFinish,
          value: autoFinish,
          isDense: true,
          enabled: !isBusy,
          onChanged: onAutoFinishChanged,
        ),
      ),
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

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final ratio = task.subtasks.isEmpty
        ? 0.0
        : task.subtasksCompletedCount / task.subtasks.length;

    return UiCard.inset(
      key: ValueKey<String>('task_subtasks_read_${task.id}'),
      headerIcon: task.subtasksAutoFinish
          ? Icons.check_box_outlined
          : Icons.checklist_rounded,
      headerTitle: localizations.subtasksSectionTitle,
      headerBadge: task.subtasksProgressLabel != null
          ? UiPill(
              label: task.subtasksProgressLabel ?? '',
              variant: UiPillVariant.count,
            )
          : null,
      headerTrailing: task.isCompleted
          ? null
          : UiButton(
              key: ValueKey<String>('task_subtasks_edit_button_${task.id}'),
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.sidebarDesktop,
              tooltip: localizations.actionEdit,
              onPressed: isBusy ? null : onStartEdit,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SubtaskProgressBar(ratio: ratio),
          if (task.subtasksAutoFinish) ...<Widget>[
            const SizedBox(height: 6.0),
            Text(
              localizations.taskInfoSubtasksAutoFinishSuffix,
              style: tokens.typography.meta.copyWith(
                color: tokens.colors.muted,
              ),
            ),
          ],
          const SizedBox(height: 6.0),
          for (final subtask in task.subtasks)
            UiToggleRow(
              key: ValueKey<String>(
                'task_subtask_toggle_${task.id}_${subtask.index}',
              ),
              label: subtask.title,
              value: subtask.isCompleted,
              isDense: true,
              enabled: !task.isCompleted && !isBusy,
              onChanged: task.isCompleted || isBusy
                  ? null
                  : (_) => onToggleSubtask(subtask.index),
            ),
        ],
      ),
    );
  }
}

/// Manages live subtask toggling and inline subtask editing state for [TaskSubtasksSection].
class _TaskSubtasksSectionState extends ConsumerState<TaskSubtasksSection> {
  late final TextEditingController _newStepController;
  late final FocusNode _newStepFocusNode;

  bool _autoFinish = false;
  String? _errorText;
  bool _isSubmitting = false;
  int _nextRowId = 1;
  final List<_EditableSubtaskRow> _rows = <_EditableSubtaskRow>[];

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
      _disposeRows();
      _errorText = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _disposeRows();
    _newStepController.dispose();
    _newStepFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isControllerBusy = ref.watch(
      taskV2ControllerProvider.select((state) => state.isBusy),
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

  /// Disposes and clears all active [_EditableSubtaskRow] controllers.
  void _disposeRows() {
    for (final row in _rows) {
      row.dispose();
    }
    _rows.clear();
  }

  /// Appends a new step from [_newStepController] and refocuses the add input.
  void _handleAddRow() {
    final trimmed = _newStepController.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    setState(() {
      _rows.add(
        _EditableSubtaskRow(
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

  /// Removes and disposes the editable subtask row at [index].
  void _handleDeleteRow(_EditableSubtaskRow row, int index) {
    if (index < 0 || index >= _rows.length) {
      return;
    }
    final removed = _rows.removeAt(index);
    removed.dispose();
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

  /// Toggles a live subtask step directly via [TaskV2Controller.toggleSubtask].
  Future<void> _handleToggleSubtask(int stepIndex) async {
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
        .toggleSubtask(
          widget.task.id,
          stepIndex,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        return;
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(message, tone: NoticeTone.danger);
    }
  }

  /// Rebuilds [_rows] and [_autoFinish] from `widget.task`.
  void _seedRowsFromTask() {
    _disposeRows();
    for (final step in widget.task.subtasks) {
      _rows.add(
        _EditableSubtaskRow(
          rowId: _nextRowId++,
          initialTitle: step.title,
          isCompleted: step.isCompleted,
        ),
      );
    }
    _autoFinish = widget.task.subtasksAutoFinish;
  }

  /// Persists [inputs] and [autoFinish] via [TaskV2Controller.saveSubtasks].
  Future<void> _submitSubtasks(
    List<SubtaskInput> inputs, {
    required bool autoFinish,
  }) async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
        .saveSubtasks(
          widget.task.id,
          inputs,
          autoFinish: autoFinish,
          locale: Localizations.localeOf(context),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }

  /// Dispatches clearing all subtasks.
  void _triggerClear() {
    unawaited(_submitSubtasks(const <SubtaskInput>[], autoFinish: false));
  }

  /// Dispatches saving current editable subtasks (including any typed pending row).
  void _triggerSave() {
    final inputs = <SubtaskInput>[
      for (final row in _rows)
        SubtaskInput(title: row.controller.text, isCompleted: row.isCompleted),
      if (_newStepController.text.trim().isNotEmpty)
        SubtaskInput(title: _newStepController.text.trim()),
    ];
    unawaited(_submitSubtasks(inputs, autoFinish: _autoFinish));
  }

  /// Dispatches live subtask checkbox toggle.
  void _triggerToggleSubtask(int stepIndex) {
    unawaited(_handleToggleSubtask(stepIndex));
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
    final tokens = UiThemeTokens.of(context);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiSegmentedControl<bool>(
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
          ),
          if (!indefinitely) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
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
          SizedBox(height: tokens.spacing.space2),
          UiField(
            kind: UiFieldKind.multiline,
            controller: noteController,
            label: localizations.taskSuspendedNoteLabel,
            hintText: localizations.taskSuspendedNoteHint,
            maxLength: _maxNoteLength,
            minLines: 2,
            maxLines: 4,
            enabled: !isBusy,
            errorText: noteError,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Read-only display card for [TaskSuspendedSection].
class _TaskSuspendedReadCard extends StatelessWidget {
  /// Creates a [_TaskSuspendedReadCard].
  const _TaskSuspendedReadCard({
    required this.task,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return UiCard.inset(
      key: ValueKey<String>('task_suspended_read_${task.id}'),
      headerIcon: Icons.pause_circle_outline_rounded,
      headerTitle: localizations.taskSuspendedLabel,
      headerTrailing: task.isCompleted
          ? null
          : UiButton(
              key: ValueKey<String>('task_suspended_edit_button_${task.id}'),
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.sidebarDesktop,
              tooltip: localizations.actionEdit,
              onPressed: isBusy ? null : onStartEdit,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            task.suspendedSummary ?? '',
            style: tokens.typography.control.copyWith(color: colors.ink),
          ),
          if (task.suspendedNote case final note?
              when note.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6.0),
            Text(
              note,
              style: tokens.typography.meta.copyWith(color: colors.ink),
            ),
          ],
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

  @override
  void initState() {
    super.initState();
    _indefinitely = widget.task.isSuspendedIndefinitely;
    _untilController = TextEditingController(
      text: widget.task.suspendedInputInitial,
    );
    _noteController = TextEditingController(
      text: widget.task.suspendedNote ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant TaskSuspendedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _indefinitely = widget.task.isSuspendedIndefinitely;
      _untilController.text = widget.task.suspendedInputInitial;
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
      taskV2ControllerProvider.select((state) => state.isBusy),
    );
    final isBusy = _isSubmitting || isControllerBusy;

    if (!widget.isEditing || widget.task.isCompleted) {
      return (!widget.task.isSuspended || widget.task.suspendedSummary == null)
          ? const SizedBox.shrink()
          : _TaskSuspendedReadCard(
              task: widget.task,
              isBusy: isBusy,
              onStartEdit: widget.onStartEdit,
            );
    }

    return _TaskSuspendedEditCard(
      indefinitely: _indefinitely,
      untilController: _untilController,
      noteController: _noteController,
      hasExistingSuspension: widget.task.isSuspended,
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

  /// Resumes the suspended task via [TaskV2Controller.resumeTask].
  Future<void> _handleResume() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
        .resumeTask(widget.task.id, locale: Localizations.localeOf(context));
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _submitError = message;
        });
    }
  }

  /// Saves edited suspension parameters via [TaskV2Controller.saveSuspended].
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
        .read(taskV2ControllerProvider.notifier)
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
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _isSubmitting = false;
          _untilError = fieldErrors['suspended'];
          _noteError = fieldErrors['suspendedNote'];
          _submitError = (_untilError == null && _noteError == null)
              ? message
              : null;
        });
      case V2ActionPersistFailed(:final message):
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

/// Parses a strict 24-hour `HH:MM` token into minutes since midnight, or `null` when invalid.
int? _parseTimeMinutes(String token) {
  if (token.length != 5 || token.codeUnitAt(2) != 0x3A) {
    return null;
  }
  final hour = int.tryParse(token.substring(0, 2));
  final minute = int.tryParse(token.substring(3, 5));
  if (hour == null || minute == null) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
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
