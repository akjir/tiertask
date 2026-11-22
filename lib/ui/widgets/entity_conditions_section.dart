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

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tdf_location.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../components/ui_ordered_item_list.dart';
import '../layout/ui_responsive_grid.dart';
import '../primitives/ui_banner.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_pill.dart';
import '../primitives/ui_segmented_control.dart';
import '../primitives/ui_toggle_row.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import 'entity_card_chrome.dart';
import 'entity_date_time_fields.dart';

/// Shared read-only and inline-editable Activation Conditions section for Tasks and Labels (`U-COMP-006`).
class EntityConditionsSection extends StatefulWidget {
  /// Creates an [EntityConditionsSection].
  const EntityConditionsSection({
    super.key,
    required this.isTask,
    required this.hasConditions,
    required this.conditionsSummary,
    required this.conditionDraft,
    required this.allLocations,
    required this.isEditing,
    required this.canEdit,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSave,
    required this.onClear,
    this.isSuspended = false,
    this.conditionsStatusLabel,
    this.onOpenLocation,
    this.isBusy = false,
  });

  /// Workspace locations selectable in the GPS locations condition dimension.
  final List<TdfLocation> allLocations;

  /// Whether this section can enter inline edit mode.
  final bool canEdit;

  /// Initial editable activation condition state.
  final ConditionDraft conditionDraft;

  /// Optional localized active/unmet condition status line.
  final String? conditionsStatusLabel;

  /// Read-only condition summary chips with optional clickable location targets.
  final List<ConditionSummaryChip> conditionsSummary;

  /// Whether this entity currently has explicit or inherited activation conditions.
  final bool hasConditions;

  /// Whether an asynchronous parent mutation is currently in progress.
  final bool isBusy;

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Whether the owning task is currently suspended (dims and disables condition controls).
  final bool isSuspended;

  /// Enables task-only global and per-dimension reset controls when true.
  final bool isTask;

  /// Callback closing inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback clearing all explicit conditions on the entity.
  final FutureOr<void> Function() onClear;

  /// Optional callback navigating to a referenced location in the Locations manager.
  final ValueChanged<String>? onOpenLocation;

  /// Callback validating and persisting an updated [ConditionDraft].
  final Future<ActionResult> Function(ConditionDraft draft) onSave;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  @override
  State<EntityConditionsSection> createState() =>
      _EntityConditionsSectionState();
}

/// Renders one condition dimension header, optional task `Inherit`/`Any`/`Custom` switch, and custom editor child.
class _EntityConditionDimensionGroup extends StatelessWidget {
  /// Creates an [_EntityConditionDimensionGroup].
  const _EntityConditionDimensionGroup({
    required this.title,
    required this.isTask,
    required this.anyLabel,
    required this.mode,
    required this.enabled,
    required this.onModeChanged,
    required this.customChild,
  });

  /// Localized label for the `ConditionDimensionMode.any` segment.
  final String anyLabel;

  /// Dimension-specific custom editor displayed when `!isTask` or `mode == custom`.
  final Widget customChild;

  /// Whether the segmented switch is interactive.
  final bool enabled;

  /// Displays the 3-way segmented control only for tasks.
  final bool isTask;

  /// Currently active dimension mode.
  final ConditionDimensionMode mode;

  /// Callback updating the active dimension mode.
  final ValueChanged<ConditionDimensionMode> onModeChanged;

  /// Localized dimension title.
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final showCustom = !isTask || mode == ConditionDimensionMode.custom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: tokens.typography.meta.copyWith(
            color: tokens.colors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (isTask) ...<Widget>[
          const SizedBox(height: 6.0),
          _EntityConditionModeControl(
            semanticLabel: title,
            anyLabel: anyLabel,
            mode: mode,
            enabled: enabled,
            onModeChanged: onModeChanged,
          ),
        ],
        if (showCustom) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          customChild,
        ],
      ],
    );
  }
}

/// Renders selectable location toggle pills for the GPS condition dimension.
class _EntityConditionLocationsPicker extends StatelessWidget {
  /// Creates an [_EntityConditionLocationsPicker].
  const _EntityConditionLocationsPicker({
    required this.allLocations,
    required this.selectedLocationIds,
    required this.enabled,
    required this.onToggleLocation,
  });

  /// Available workspace locations.
  final List<TdfLocation> allLocations;

  /// Whether location toggle pills accept input.
  final bool enabled;

  /// Callback toggling a location identifier.
  final ValueChanged<String> onToggleLocation;

  /// Currently selected location identifiers.
  final List<String> selectedLocationIds;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
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
            key: ValueKey<String>('cond_loc_${location.id}'),
            label: location.name,
            icon: Icons.place_outlined,
            variant: UiPillVariant.selectable,
            isSelected: selectedLocationIds.contains(location.id),
            enabled: enabled,
            onPressed: enabled ? () => onToggleLocation(location.id) : null,
          ),
      ],
    );
  }
}

/// Renders the task-only `Inherit` / `Any` / `Custom` segmented switch for one condition dimension.
class _EntityConditionModeControl extends StatelessWidget {
  /// Creates an [_EntityConditionModeControl].
  const _EntityConditionModeControl({
    required this.semanticLabel,
    required this.anyLabel,
    required this.mode,
    required this.enabled,
    required this.onModeChanged,
  });

  /// Localized label for the `ConditionDimensionMode.any` segment.
  final String anyLabel;

  /// Whether the segmented control accepts interaction.
  final bool enabled;

  /// Currently selected condition dimension mode.
  final ConditionDimensionMode mode;

  /// Callback updating the selected mode.
  final ValueChanged<ConditionDimensionMode> onModeChanged;

  /// Accessible label for the segmented control.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiSegmentedControl<ConditionDimensionMode>(
      semanticLabel: semanticLabel,
      value: mode,
      enabled: enabled,
      onChanged: onModeChanged,
      segments: <UiSegment<ConditionDimensionMode>>[
        UiSegment<ConditionDimensionMode>(
          value: ConditionDimensionMode.inherit,
          label: localizations.conditionInheritLabel,
        ),
        UiSegment<ConditionDimensionMode>(
          value: ConditionDimensionMode.any,
          label: anyLabel,
        ),
        UiSegment<ConditionDimensionMode>(
          value: ConditionDimensionMode.custom,
          label: localizations.conditionCustomLabel,
        ),
      ],
    );
  }
}

/// Renders one condition summary pill, navigating to Locations manager when `locationId` is set.
class _EntityConditionSummaryChip extends StatelessWidget {
  /// Creates an [_EntityConditionSummaryChip].
  const _EntityConditionSummaryChip({
    required this.chip,
    required this.onOpenLocation,
  });

  /// Condition summary chip model.
  final ConditionSummaryChip chip;

  /// Optional location navigation callback.
  final ValueChanged<String>? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final targetLocationId = chip.locationId;
    if (targetLocationId != null && onOpenLocation != null) {
      return UiPill(
        label: chip.label,
        variant: UiPillVariant.tag,
        icon: Icons.place_outlined,
        tooltip: localizations.openLocationInManagerTooltip,
        onPressed: () => onOpenLocation?.call(targetLocationId),
      );
    }
    return UiPill(
      label: chip.label,
      variant: UiPillVariant.tag,
      tone: chip.isInherited ? UiPillTone.soft : UiPillTone.neutral,
    );
  }
}

/// Renders read-only condition summary pills, wiring clickable location chips to [onOpenLocation].
class _EntityConditionSummaryChipWrap extends StatelessWidget {
  /// Creates an [_EntityConditionSummaryChipWrap].
  const _EntityConditionSummaryChipWrap({
    required this.chips,
    required this.onOpenLocation,
  });

  /// Condition summary chips to display.
  final List<ConditionSummaryChip> chips;

  /// Optional location navigation callback.
  final ValueChanged<String>? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final chip in chips)
          _EntityConditionSummaryChip(
            chip: chip,
            onOpenLocation: onOpenLocation,
          ),
      ],
    );
  }
}

/// Renders repeatable daily `HH:MM - HH:MM` time window items with hybrid clock inputs.
class _EntityConditionTimeWindowsPicker extends StatelessWidget {
  /// Creates an [_EntityConditionTimeWindowsPicker].
  const _EntityConditionTimeWindowsPicker({
    required this.timeWindows,
    required this.startController,
    required this.endController,
    required this.errorText,
    required this.enabled,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
  });

  /// Whether adding and removing time windows is enabled.
  final bool enabled;

  /// Controller for the end `HH:MM` input.
  final TextEditingController endController;

  /// Optional inline validation error for time window inputs.
  final String? errorText;

  /// Callback adding the current start/end inputs as a new time window.
  final VoidCallback onAddTimeWindow;

  /// Callback removing an existing time window row.
  final UiOrderedItemActionCallback<TimeWindowDraft> onRemoveTimeWindow;

  /// Controller for the start `HH:MM` input.
  final TextEditingController startController;

  /// Configured daily time windows.
  final List<TimeWindowDraft> timeWindows;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);

    return UiOrderedItemList<TimeWindowDraft>(
      items: timeWindows,
      itemKey: (window, index) =>
          ValueKey<String>('cond_time_${index}_${window.start}_${window.end}'),
      onDelete: enabled ? onRemoveTimeWindow : null,
      deleteTooltip: localizations.tooltipRemoveTimeCondition,
      itemBuilder: (context, window, index, isEditing) => Text(
        '${window.start} - ${window.end}',
        style: UiTypographyTokens.mono(
          tokens.typography.monoSmall.copyWith(color: tokens.colors.ink),
        ),
      ),
      addBar: _EntityTimeWindowAddBar(
        startController: startController,
        endController: endController,
        errorText: errorText,
        enabled: enabled,
        onAddTimeWindow: onAddTimeWindow,
      ),
    );
  }
}

/// Renders Monday through Sunday (`1..7`) selectable weekday pills.
class _EntityConditionWeekdaysPicker extends StatelessWidget {
  /// Creates an [_EntityConditionWeekdaysPicker].
  const _EntityConditionWeekdaysPicker({
    required this.selectedWeekdays,
    required this.enabled,
    required this.onToggleWeekday,
  });

  /// Whether weekday pills are interactive.
  final bool enabled;

  /// Callback toggling an ISO weekday (`1..7`).
  final ValueChanged<int> onToggleWeekday;

  /// Selected ISO weekdays (`1..7`).
  final List<int> selectedWeekdays;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (var isoDay = DateTime.monday; isoDay <= DateTime.sunday; isoDay++)
          UiPill(
            key: ValueKey<String>('cond_day_$isoDay'),
            label: _weekdayLabel(isoDay, localizations),
            variant: UiPillVariant.selectable,
            isSelected: selectedWeekdays.contains(isoDay),
            enabled: enabled,
            onPressed: enabled ? () => onToggleWeekday(isoDay) : null,
          ),
      ],
    );
  }
}

/// Renders global reset toggle plus weekday, time-window, and location condition groups.
class _EntityConditionsControlsBody extends StatelessWidget {
  /// Creates an [_EntityConditionsControlsBody].
  const _EntityConditionsControlsBody({
    required this.isTask,
    required this.draft,
    required this.allLocations,
    required this.timeStartController,
    required this.timeEndController,
    required this.timeInputError,
    required this.isBusy,
    required this.onToggleIgnoreAll,
    required this.onDaysModeChanged,
    required this.onToggleWeekday,
    required this.onTimesModeChanged,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
    required this.onLocationsModeChanged,
    required this.onToggleLocation,
  });

  /// Available workspace locations.
  final List<TdfLocation> allLocations;

  /// Current editable condition draft.
  final ConditionDraft draft;

  /// Disables interactive controls while submitting.
  final bool isBusy;

  /// Enables task reset switches when true.
  final bool isTask;

  /// Callback adding a time window.
  final VoidCallback onAddTimeWindow;

  /// Callback changing weekday mode.
  final ValueChanged<ConditionDimensionMode> onDaysModeChanged;

  /// Callback changing location mode.
  final ValueChanged<ConditionDimensionMode> onLocationsModeChanged;

  /// Callback removing a time window.
  final UiOrderedItemActionCallback<TimeWindowDraft> onRemoveTimeWindow;

  /// Callback changing time-window mode.
  final ValueChanged<ConditionDimensionMode> onTimesModeChanged;

  /// Callback toggling `ignoreAllLabelConditions`.
  final ValueChanged<bool> onToggleIgnoreAll;

  /// Callback toggling a location identifier.
  final ValueChanged<String> onToggleLocation;

  /// Callback toggling an ISO weekday.
  final ValueChanged<int> onToggleWeekday;

  /// End time controller (`HH:MM`).
  final TextEditingController timeEndController;

  /// Optional inline time input error message.
  final String? timeInputError;

  /// Start time controller (`HH:MM`).
  final TextEditingController timeStartController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final dimensionsEnabled =
        !isBusy && (!isTask || !draft.ignoreAllLabelConditions);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _EntityConditionsGlobalAndDaysGroup(
          isTask: isTask,
          draft: draft,
          isBusy: isBusy,
          dimensionsEnabled: dimensionsEnabled,
          onToggleIgnoreAll: onToggleIgnoreAll,
          onDaysModeChanged: onDaysModeChanged,
          onToggleWeekday: onToggleWeekday,
        ),
        SizedBox(height: tokens.spacing.space3),
        _EntityConditionsTimesAndLocationsGroup(
          isTask: isTask,
          draft: draft,
          allLocations: allLocations,
          timeStartController: timeStartController,
          timeEndController: timeEndController,
          timeInputError: timeInputError,
          dimensionsEnabled: dimensionsEnabled,
          onTimesModeChanged: onTimesModeChanged,
          onAddTimeWindow: onAddTimeWindow,
          onRemoveTimeWindow: onRemoveTimeWindow,
          onLocationsModeChanged: onLocationsModeChanged,
          onToggleLocation: onToggleLocation,
        ),
      ],
    );
  }
}

/// Renders the task-level global reset toggle or label conditions helper copy.
class _EntityConditionsControlsHeader extends StatelessWidget {
  /// Creates an [_EntityConditionsControlsHeader].
  const _EntityConditionsControlsHeader({
    required this.isTask,
    required this.ignoreAllLabelConditions,
    required this.enabled,
    required this.onToggleIgnoreAll,
  });

  /// Whether the toggle control accepts input.
  final bool enabled;

  /// Current `condition any` toggle state for tasks.
  final bool ignoreAllLabelConditions;

  /// Displays the global reset toggle for tasks and descriptive text for labels.
  final bool isTask;

  /// Callback toggling `ignoreAllLabelConditions`.
  final ValueChanged<bool> onToggleIgnoreAll;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (isTask) {
      return UiToggleRow(
        label: localizations.conditionGlobalAnyLabel,
        value: ignoreAllLabelConditions,
        isDense: true,
        enabled: enabled,
        onChanged: onToggleIgnoreAll,
      );
    }
    final tokens = UiThemeTokens.of(context);
    return Text(
      localizations.labelConditionsSectionDescription,
      style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
    );
  }
}

/// Renders the weekday activation condition dimension group.
class _EntityConditionsDaysSection extends StatelessWidget {
  /// Creates an [_EntityConditionsDaysSection].
  const _EntityConditionsDaysSection({
    required this.isTask,
    required this.draft,
    required this.enabled,
    required this.onDaysModeChanged,
    required this.onToggleWeekday,
  });

  /// Editable condition draft containing weekday mode and selection.
  final ConditionDraft draft;

  /// Whether dimension controls accept input.
  final bool enabled;

  /// Shows the 3-way task mode switch when true.
  final bool isTask;

  /// Callback changing weekday mode.
  final ValueChanged<ConditionDimensionMode> onDaysModeChanged;

  /// Callback toggling an ISO weekday.
  final ValueChanged<int> onToggleWeekday;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _EntityConditionDimensionGroup(
      title: localizations.conditionDayGroupTitle,
      isTask: isTask,
      anyLabel: localizations.conditionDayAnyLabel,
      mode: draft.daysMode,
      enabled: enabled,
      onModeChanged: onDaysModeChanged,
      customChild: _EntityConditionWeekdaysPicker(
        selectedWeekdays: draft.weekdays,
        enabled: enabled,
        onToggleWeekday: onToggleWeekday,
      ),
    );
  }
}

/// Renders the inline editing inset card for [EntityConditionsSection].
class _EntityConditionsEditorCard extends StatelessWidget {
  /// Creates an [_EntityConditionsEditorCard].
  const _EntityConditionsEditorCard({
    required this.isTask,
    required this.isSuspended,
    required this.hasConditions,
    required this.draft,
    required this.allLocations,
    required this.timeStartController,
    required this.timeEndController,
    required this.timeInputError,
    required this.saveErrorText,
    required this.isBusy,
    required this.onToggleIgnoreAll,
    required this.onDaysModeChanged,
    required this.onToggleWeekday,
    required this.onTimesModeChanged,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
    required this.onLocationsModeChanged,
    required this.onToggleLocation,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
  });

  /// Workspace locations selectable in the GPS dimension.
  final List<TdfLocation> allLocations;

  /// Current editable condition draft.
  final ConditionDraft draft;

  /// Whether existing conditions are set (controls Clear button visibility).
  final bool hasConditions;

  /// Disables actions while submitting.
  final bool isBusy;

  /// Dims and blocks condition controls when true.
  final bool isSuspended;

  /// Enables task-only global and per-dimension switches when true.
  final bool isTask;

  /// Callback adding a time window from the start/end inputs.
  final VoidCallback onAddTimeWindow;

  /// Callback cancelling inline editing.
  final VoidCallback onCancel;

  /// Callback clearing all persisted conditions.
  final VoidCallback onClear;

  /// Callback updating the days dimension mode.
  final ValueChanged<ConditionDimensionMode> onDaysModeChanged;

  /// Callback updating the locations dimension mode.
  final ValueChanged<ConditionDimensionMode> onLocationsModeChanged;

  /// Callback removing a draft time window row.
  final UiOrderedItemActionCallback<TimeWindowDraft> onRemoveTimeWindow;

  /// Callback submitting the draft.
  final VoidCallback onSave;

  /// Callback updating the times dimension mode.
  final ValueChanged<ConditionDimensionMode> onTimesModeChanged;

  /// Callback toggling global `ignoreAllLabelConditions`.
  final ValueChanged<bool> onToggleIgnoreAll;

  /// Callback toggling a location identifier.
  final ValueChanged<String> onToggleLocation;

  /// Callback toggling an ISO weekday (`1..7`).
  final ValueChanged<int> onToggleWeekday;

  /// Optional inline save error text.
  final String? saveErrorText;

  /// End time controller (`HH:MM`).
  final TextEditingController timeEndController;

  /// Optional validation error for time window inputs.
  final String? timeInputError;

  /// Start time controller (`HH:MM`).
  final TextEditingController timeStartController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      isEditing: true,
      headerIcon: Icons.tune_rounded,
      headerTitle: localizations.taskConditionsSectionTitle,
      footer: EntityInlineEditorFooter(
        errorText: saveErrorText,
        clearLabel: hasConditions ? localizations.inlineClearAction : null,
        onClear: hasConditions ? onClear : null,
        onCancel: onCancel,
        onSave: onSave,
        isBusy: isBusy,
      ),
      child: _EntityConditionsSuspendedControls(
        isSuspended: isSuspended,
        child: _EntityConditionsControlsBody(
          isTask: isTask,
          draft: draft,
          allLocations: allLocations,
          timeStartController: timeStartController,
          timeEndController: timeEndController,
          timeInputError: timeInputError,
          isBusy: isBusy,
          onToggleIgnoreAll: onToggleIgnoreAll,
          onDaysModeChanged: onDaysModeChanged,
          onToggleWeekday: onToggleWeekday,
          onTimesModeChanged: onTimesModeChanged,
          onAddTimeWindow: onAddTimeWindow,
          onRemoveTimeWindow: onRemoveTimeWindow,
          onLocationsModeChanged: onLocationsModeChanged,
          onToggleLocation: onToggleLocation,
        ),
      ),
    );
  }
}

/// Groups the global reset header and weekday dimension inside [_EntityConditionsControlsBody].
class _EntityConditionsGlobalAndDaysGroup extends StatelessWidget {
  /// Creates an [_EntityConditionsGlobalAndDaysGroup].
  const _EntityConditionsGlobalAndDaysGroup({
    required this.isTask,
    required this.draft,
    required this.isBusy,
    required this.dimensionsEnabled,
    required this.onToggleIgnoreAll,
    required this.onDaysModeChanged,
    required this.onToggleWeekday,
  });

  /// Whether per-dimension controls accept interaction.
  final bool dimensionsEnabled;

  /// Current editable condition draft.
  final ConditionDraft draft;

  /// Disables the global toggle while submitting.
  final bool isBusy;

  /// Enables task-only controls when true.
  final bool isTask;

  /// Callback changing weekday mode.
  final ValueChanged<ConditionDimensionMode> onDaysModeChanged;

  /// Callback toggling `ignoreAllLabelConditions`.
  final ValueChanged<bool> onToggleIgnoreAll;

  /// Callback toggling an ISO weekday.
  final ValueChanged<int> onToggleWeekday;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _EntityConditionsControlsHeader(
          isTask: isTask,
          ignoreAllLabelConditions: draft.ignoreAllLabelConditions,
          enabled: !isBusy,
          onToggleIgnoreAll: onToggleIgnoreAll,
        ),
        SizedBox(height: tokens.spacing.space3),
        _EntityConditionsDaysSection(
          isTask: isTask,
          draft: draft,
          enabled: dimensionsEnabled,
          onDaysModeChanged: onDaysModeChanged,
          onToggleWeekday: onToggleWeekday,
        ),
      ],
    );
  }
}

/// Renders the GPS locations activation condition dimension group.
class _EntityConditionsLocationsSection extends StatelessWidget {
  /// Creates an [_EntityConditionsLocationsSection].
  const _EntityConditionsLocationsSection({
    required this.isTask,
    required this.draft,
    required this.allLocations,
    required this.enabled,
    required this.onLocationsModeChanged,
    required this.onToggleLocation,
  });

  /// Available workspace locations.
  final List<TdfLocation> allLocations;

  /// Editable condition draft containing location mode and selection.
  final ConditionDraft draft;

  /// Whether location dimension controls accept input.
  final bool enabled;

  /// Shows the 3-way task mode switch when true.
  final bool isTask;

  /// Callback changing location mode.
  final ValueChanged<ConditionDimensionMode> onLocationsModeChanged;

  /// Callback toggling a location identifier.
  final ValueChanged<String> onToggleLocation;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _EntityConditionDimensionGroup(
      title: localizations.conditionLocationGroupTitle,
      isTask: isTask,
      anyLabel: localizations.conditionLocationAnyLabel,
      mode: draft.locationMode,
      enabled: enabled,
      onModeChanged: onLocationsModeChanged,
      customChild: _EntityConditionLocationsPicker(
        allLocations: allLocations,
        selectedLocationIds: draft.locationIds,
        enabled: enabled,
        onToggleLocation: onToggleLocation,
      ),
    );
  }
}

/// Renders the read-only suspended warning, status line, and summary chips inside [_EntityConditionsReadOnlyView].
class _EntityConditionsReadOnlyBody extends StatelessWidget {
  /// Creates an [_EntityConditionsReadOnlyBody].
  const _EntityConditionsReadOnlyBody({
    required this.isSuspended,
    required this.conditionsStatusLabel,
    required this.conditionsSummary,
    required this.onOpenLocation,
  });

  /// Optional localized active/unmet condition status line.
  final String? conditionsStatusLabel;

  /// Read-only condition summary chips.
  final List<ConditionSummaryChip> conditionsSummary;

  /// Shows suspended inline warning when true.
  final bool isSuspended;

  /// Optional callback invoked when a clickable location chip is tapped.
  final ValueChanged<String>? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    final statusLine = conditionsStatusLabel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (isSuspended) ...<Widget>[
          UiBanner(
            variant: UiBannerVariant.inlineWarning,
            message: localizations.taskSuspendedDisablesConditionsHint,
          ),
          SizedBox(height: tokens.spacing.space2),
        ],
        if (statusLine != null && statusLine.isNotEmpty) ...<Widget>[
          Text(
            statusLine,
            style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
          ),
          SizedBox(height: tokens.spacing.space2),
        ],
        if (conditionsSummary.isNotEmpty)
          _EntityConditionSummaryChipWrap(
            chips: conditionsSummary,
            onOpenLocation: onOpenLocation,
          ),
      ],
    );
  }
}

/// Renders read-only Activation Conditions card with status line, optional suspended warning, and summary pills.
class _EntityConditionsReadOnlyView extends StatelessWidget {
  /// Creates an [_EntityConditionsReadOnlyView].
  const _EntityConditionsReadOnlyView({
    required this.isSuspended,
    required this.conditionsStatusLabel,
    required this.conditionsSummary,
    required this.canEdit,
    required this.isBusy,
    required this.onStartEdit,
    required this.onOpenLocation,
  });

  /// Whether the edit pencil button is displayed.
  final bool canEdit;

  /// Optional localized active/unmet condition status line.
  final String? conditionsStatusLabel;

  /// Read-only condition summary chips.
  final List<ConditionSummaryChip> conditionsSummary;

  /// Whether parent mutations are in progress.
  final bool isBusy;

  /// Shows suspended inline warning when true.
  final bool isSuspended;

  /// Optional callback invoked when a clickable location chip is tapped.
  final ValueChanged<String>? onOpenLocation;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.tune_rounded,
      headerTitle: localizations.taskConditionsSectionTitle,
      headerTrailing: canEdit
          ? UiButton(
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.dense,
              tooltip: localizations.actionEdit,
              onPressed: isBusy ? null : onStartEdit,
            )
          : null,
      child: _EntityConditionsReadOnlyBody(
        isSuspended: isSuspended,
        conditionsStatusLabel: conditionsStatusLabel,
        conditionsSummary: conditionsSummary,
        onOpenLocation: onOpenLocation,
      ),
    );
  }
}

/// Manages inline editing draft state for [EntityConditionsSection].
class _EntityConditionsSectionState extends State<EntityConditionsSection> {
  late final TextEditingController _timeEndController;
  late final TextEditingController _timeStartController;

  late ConditionDraft _draft;
  bool _isSubmitting = false;
  String? _saveErrorText;
  String? _timeInputError;

  @override
  void initState() {
    super.initState();
    _draft = widget.conditionDraft;
    _timeStartController = TextEditingController();
    _timeEndController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant EntityConditionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _draft = widget.conditionDraft;
      _timeStartController.clear();
      _timeEndController.clear();
      _timeInputError = null;
      _saveErrorText = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _timeInputError = null;
      _saveErrorText = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _timeStartController.dispose();
    _timeEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditing) {
      return widget.hasConditions
          ? _EntityConditionsReadOnlyView(
              isSuspended: widget.isSuspended,
              conditionsStatusLabel: widget.conditionsStatusLabel,
              conditionsSummary: widget.conditionsSummary,
              canEdit: widget.canEdit,
              isBusy: widget.isBusy,
              onStartEdit: widget.onStartEdit,
              onOpenLocation: widget.onOpenLocation,
            )
          : const SizedBox.shrink();
    }

    return _EntityConditionsEditorCard(
      isTask: widget.isTask,
      isSuspended: widget.isSuspended,
      hasConditions: widget.hasConditions,
      draft: _draft,
      allLocations: widget.allLocations,
      timeStartController: _timeStartController,
      timeEndController: _timeEndController,
      timeInputError: _timeInputError,
      saveErrorText: _saveErrorText,
      isBusy: widget.isBusy || _isSubmitting,
      onToggleIgnoreAll: _handleToggleIgnoreAll,
      onDaysModeChanged: _handleDaysModeChanged,
      onToggleWeekday: _handleToggleWeekday,
      onTimesModeChanged: _handleTimesModeChanged,
      onAddTimeWindow: _handleAddTimeWindow,
      onRemoveTimeWindow: _handleRemoveTimeWindow,
      onLocationsModeChanged: _handleLocationsModeChanged,
      onToggleLocation: _handleToggleLocation,
      onClear: _handleClear,
      onCancel: widget.onCancelEdit,
      onSave: _handleSave,
    );
  }

  /// Validates and appends a `HH:MM`..`HH:MM` window from the start/end text controllers.
  bool _handleAddTimeWindow() {
    final localizations = AppLocalizations.of(context);
    final startToken = _timeStartController.text.trim();
    final endToken = _timeEndController.text.trim();
    final startMinutes = parseEntityTimeMinutes(startToken);
    final endMinutes = parseEntityTimeMinutes(endToken);
    if (startMinutes == null ||
        endMinutes == null ||
        startMinutes == endMinutes) {
      setState(() {
        _timeInputError = localizations.conditionTimeErrorInvalid;
      });
      return false;
    }
    final nextWindows = <TimeWindowDraft>[
      ..._draft.timeWindows,
      TimeWindowDraft(start: startToken, end: endToken),
    ];
    setState(() {
      _draft = _draft.copyWith(timeWindows: nextWindows);
      _timeStartController.clear();
      _timeEndController.clear();
      _timeInputError = null;
      _saveErrorText = null;
    });
    return true;
  }

  /// Clears all persisted activation conditions while guarding against double-submit.
  Future<void> _handleClear() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _saveErrorText = null;
    });
    try {
      await widget.onClear();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Updates the weekday condition dimension mode.
  void _handleDaysModeChanged(ConditionDimensionMode mode) {
    setState(() {
      _draft = _draft.copyWith(daysMode: mode);
      _saveErrorText = null;
    });
  }

  /// Updates the locations condition dimension mode.
  void _handleLocationsModeChanged(ConditionDimensionMode mode) {
    setState(() {
      _draft = _draft.copyWith(locationMode: mode);
      _saveErrorText = null;
    });
  }

  /// Removes the time window at [index] from the draft.
  void _handleRemoveTimeWindow(TimeWindowDraft window, int index) {
    if (index < 0 || index >= _draft.timeWindows.length) {
      return;
    }
    final nextWindows = List<TimeWindowDraft>.of(_draft.timeWindows)
      ..removeAt(index);
    setState(() {
      _draft = _draft.copyWith(timeWindows: nextWindows);
      _saveErrorText = null;
    });
  }

  /// Commits any pending valid time window input and submits [_draft] to [widget.onSave].
  Future<void> _handleSave() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    final canAddPendingTime =
        (!widget.isTask ||
            (!_draft.ignoreAllLabelConditions &&
                _draft.timeMode == ConditionDimensionMode.custom)) &&
        (_timeStartController.text.trim().isNotEmpty ||
            _timeEndController.text.trim().isNotEmpty);
    if (canAddPendingTime && !_handleAddTimeWindow()) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _saveErrorText = null;
    });
    final result = await widget.onSave(_draft);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _saveErrorText = message;
        });
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _saveErrorText = message;
        });
    }
  }

  /// Updates the time-window condition dimension mode.
  void _handleTimesModeChanged(ConditionDimensionMode mode) {
    setState(() {
      _draft = _draft.copyWith(timeMode: mode);
      _timeInputError = null;
      _saveErrorText = null;
    });
  }

  /// Toggles task-level `condition any` (ignore all inherited label conditions).
  void _handleToggleIgnoreAll(bool value) {
    setState(() {
      _draft = _draft.copyWith(ignoreAllLabelConditions: value);
      _saveErrorText = null;
    });
  }

  /// Toggles [locationId] inside the draft selected locations list.
  void _handleToggleLocation(String locationId) {
    final nextIds = List<String>.of(_draft.locationIds);
    if (!nextIds.remove(locationId)) {
      nextIds.add(locationId);
    }
    setState(() {
      _draft = _draft.copyWith(locationIds: nextIds);
      _saveErrorText = null;
    });
  }

  /// Toggles ISO weekday [isoWeekday] (`1..7`) and keeps the draft sorted ascending.
  void _handleToggleWeekday(int isoWeekday) {
    final nextDays = List<int>.of(_draft.weekdays);
    if (!nextDays.remove(isoWeekday)) {
      nextDays.add(isoWeekday);
      nextDays.sort();
    }
    setState(() {
      _draft = _draft.copyWith(weekdays: nextDays);
      _saveErrorText = null;
    });
  }
}

/// Wraps condition editor controls with the optional suspended warning banner and dimmed ignore layer.
class _EntityConditionsSuspendedControls extends StatelessWidget {
  /// Creates an [_EntityConditionsSuspendedControls].
  const _EntityConditionsSuspendedControls({
    required this.isSuspended,
    required this.child,
  });

  /// Condition controls rendered beneath the optional suspended banner.
  final Widget child;

  /// Shows the warning banner and dims/disables [child] when true.
  final bool isSuspended;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (isSuspended) ...<Widget>[
          UiBanner(
            variant: UiBannerVariant.inlineWarning,
            message: localizations.taskSuspendedDisablesConditionsHint,
          ),
          SizedBox(height: tokens.spacing.space3),
        ],
        Opacity(
          opacity: isSuspended ? tokens.focus.suspendedDimmedOpacity : 1.0,
          child: IgnorePointer(ignoring: isSuspended, child: child),
        ),
      ],
    );
  }
}

/// Groups the time-window and GPS location dimensions inside [_EntityConditionsControlsBody].
class _EntityConditionsTimesAndLocationsGroup extends StatelessWidget {
  /// Creates an [_EntityConditionsTimesAndLocationsGroup].
  const _EntityConditionsTimesAndLocationsGroup({
    required this.isTask,
    required this.draft,
    required this.allLocations,
    required this.timeStartController,
    required this.timeEndController,
    required this.timeInputError,
    required this.dimensionsEnabled,
    required this.onTimesModeChanged,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
    required this.onLocationsModeChanged,
    required this.onToggleLocation,
  });

  /// Available workspace locations.
  final List<TdfLocation> allLocations;

  /// Whether per-dimension controls accept interaction.
  final bool dimensionsEnabled;

  /// Current editable condition draft.
  final ConditionDraft draft;

  /// Enables task-only controls when true.
  final bool isTask;

  /// Callback adding a time window.
  final VoidCallback onAddTimeWindow;

  /// Callback changing location mode.
  final ValueChanged<ConditionDimensionMode> onLocationsModeChanged;

  /// Callback removing a time window.
  final UiOrderedItemActionCallback<TimeWindowDraft> onRemoveTimeWindow;

  /// Callback changing time-window mode.
  final ValueChanged<ConditionDimensionMode> onTimesModeChanged;

  /// Callback toggling a location identifier.
  final ValueChanged<String> onToggleLocation;

  /// End time controller (`HH:MM`).
  final TextEditingController timeEndController;

  /// Optional inline time input error message.
  final String? timeInputError;

  /// Start time controller (`HH:MM`).
  final TextEditingController timeStartController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _EntityConditionsTimesSection(
          isTask: isTask,
          draft: draft,
          startController: timeStartController,
          endController: timeEndController,
          errorText: timeInputError,
          enabled: dimensionsEnabled,
          onTimesModeChanged: onTimesModeChanged,
          onAddTimeWindow: onAddTimeWindow,
          onRemoveTimeWindow: onRemoveTimeWindow,
        ),
        SizedBox(height: tokens.spacing.space3),
        _EntityConditionsLocationsSection(
          isTask: isTask,
          draft: draft,
          allLocations: allLocations,
          enabled: dimensionsEnabled,
          onLocationsModeChanged: onLocationsModeChanged,
          onToggleLocation: onToggleLocation,
        ),
      ],
    );
  }
}

/// Renders the daily time-windows activation condition dimension group.
class _EntityConditionsTimesSection extends StatelessWidget {
  /// Creates an [_EntityConditionsTimesSection].
  const _EntityConditionsTimesSection({
    required this.isTask,
    required this.draft,
    required this.startController,
    required this.endController,
    required this.errorText,
    required this.enabled,
    required this.onTimesModeChanged,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
  });

  /// Editable condition draft containing time-window mode and list.
  final ConditionDraft draft;

  /// Whether time-window controls accept input.
  final bool enabled;

  /// End time controller (`HH:MM`).
  final TextEditingController endController;

  /// Optional inline time input error text.
  final String? errorText;

  /// Shows the 3-way task mode switch when true.
  final bool isTask;

  /// Callback adding a time window.
  final VoidCallback onAddTimeWindow;

  /// Callback removing a time window.
  final UiOrderedItemActionCallback<TimeWindowDraft> onRemoveTimeWindow;

  /// Callback changing time-window mode.
  final ValueChanged<ConditionDimensionMode> onTimesModeChanged;

  /// Start time controller (`HH:MM`).
  final TextEditingController startController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _EntityConditionDimensionGroup(
      title: localizations.conditionTimeGroupTitle,
      isTask: isTask,
      anyLabel: localizations.conditionTimeAnyLabel,
      mode: draft.timeMode,
      enabled: enabled,
      onModeChanged: onTimesModeChanged,
      customChild: _EntityConditionTimeWindowsPicker(
        timeWindows: draft.timeWindows,
        startController: startController,
        endController: endController,
        errorText: errorText,
        enabled: enabled,
        onAddTimeWindow: onAddTimeWindow,
        onRemoveTimeWindow: onRemoveTimeWindow,
      ),
    );
  }
}

/// Renders the start/end hybrid time fields, error slot, and Add time window button.
class _EntityTimeWindowAddBar extends StatelessWidget {
  /// Creates an [_EntityTimeWindowAddBar].
  const _EntityTimeWindowAddBar({
    required this.startController,
    required this.endController,
    required this.errorText,
    required this.enabled,
    required this.onAddTimeWindow,
  });

  /// Whether the fields and Add button are enabled.
  final bool enabled;

  /// End time controller (`HH:MM`).
  final TextEditingController endController;

  /// Optional inline validation error message.
  final String? errorText;

  /// Callback committing the typed time window.
  final VoidCallback onAddTimeWindow;

  /// Start time controller (`HH:MM`).
  final TextEditingController startController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    final error = errorText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _EntityTimeWindowFieldsGrid(
          startController: startController,
          endController: endController,
          enabled: enabled,
          onAddTimeWindow: onAddTimeWindow,
        ),
        if (error != null && error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6.0),
          EntityInlineErrorText(message: error),
        ],
        SizedBox(height: tokens.spacing.space2),
        Align(
          alignment: Alignment.centerLeft,
          child: UiButton(
            label: localizations.tooltipAddTimeCondition,
            leadingIcon: Icons.add_rounded,
            variant: UiButtonVariant.secondary,
            density: UiButtonDensity.compact,
            onPressed: enabled ? onAddTimeWindow : null,
          ),
        ),
      ],
    );
  }
}

/// Renders the responsive two-column start and end hybrid time inputs inside [_EntityTimeWindowAddBar].
class _EntityTimeWindowFieldsGrid extends StatelessWidget {
  /// Creates an [_EntityTimeWindowFieldsGrid].
  const _EntityTimeWindowFieldsGrid({
    required this.startController,
    required this.endController,
    required this.enabled,
    required this.onAddTimeWindow,
  });

  /// Whether the time inputs accept interaction.
  final bool enabled;

  /// End time controller (`HH:MM`).
  final TextEditingController endController;

  /// Callback committing the typed time window when submitting from either field.
  final VoidCallback onAddTimeWindow;

  /// Start time controller (`HH:MM`).
  final TextEditingController startController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    return UiResponsiveGrid(
      preset: UiGridPreset.twoColumnCompactCollapse,
      spacing: tokens.spacing.space2,
      runSpacing: tokens.spacing.space2,
      children: <Widget>[
        EntityHybridTimeField(
          controller: startController,
          hintText: localizations.conditionTimeStartHint,
          enabled: enabled,
          onSubmitted: (_) => onAddTimeWindow(),
        ),
        EntityHybridTimeField(
          controller: endController,
          hintText: localizations.conditionTimeEndHint,
          enabled: enabled,
          onSubmitted: (_) => onAddTimeWindow(),
        ),
      ],
    );
  }
}

/// Resolves the localized short weekday label for ISO weekday [isoWeekday] (`1..7`).
String _weekdayLabel(int isoWeekday, AppLocalizations localizations) {
  return switch (isoWeekday) {
    DateTime.monday => localizations.weekdayMon,
    DateTime.tuesday => localizations.weekdayTue,
    DateTime.wednesday => localizations.weekdayWed,
    DateTime.thursday => localizations.weekdayThu,
    DateTime.friday => localizations.weekdayFri,
    DateTime.saturday => localizations.weekdaySat,
    _ => localizations.weekdaySun,
  };
}
