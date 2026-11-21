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

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/board_v2_view_models.dart';
import '../../presentation/floating_notice_controller.dart';
import '../../presentation/link_action_controller.dart';
import '../../presentation/task_v2_controller.dart';
import '../../presentation/ui_v2_shell_models.dart';

/// Lower date bound accepted by Material date pickers.
final DateTime _firstPickerDate = DateTime(2000);

/// Maximum character limit for the searchable label picker query (`maxTdfTextLength`).
const int _labelPickerSearchMaxLength = 500;

/// Upper date bound accepted by Material date pickers.
final DateTime _lastPickerDate = DateTime(2100, 12, 31);

/// Maximum reference links allowed per task or label (`TDF 0.8.0`).
const int _maxLinksPerEntity = 20;

/// Maximum note length allowed by `TDF 0.8.0` (`maxTdfNoteLength`).
const int _maxNoteLength = 2000;

/// Maximum single-line text length allowed by `TDF 0.8.0` (`maxTdfTextLength`).
const int _maxSingleLineLength = 500;

/// Scope filter identifier showing all labels.
const String _scopeAll = 'all';

/// Scope filter identifier showing global context labels only.
const String _scopeGlobal = 'global';

/// Scope filter identifier showing scoped queue labels only.
const String _scopeScoped = 'scoped';

/// Shared top meta bar inside expanded Task, Label, and Location cards (`U-CARD-002`).
class EntityCardMetaBar extends StatelessWidget {
  /// Creates an [EntityCardMetaBar].
  const EntityCardMetaBar({
    super.key,
    required this.entityId,
    required this.copyIdTooltip,
    required this.onCopyId,
    required this.deleteTooltip,
    required this.deleteConfirmMessage,
    required this.isConfirmingDelete,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
    this.statusPillLabel,
    this.statusPillTone = UiPillTone.neutral,
  });

  /// Tooltip for the compact Copy ID icon button.
  final String copyIdTooltip;

  /// Inline prompt message displayed while [isConfirmingDelete] is true.
  final String deleteConfirmMessage;

  /// Tooltip for the right-aligned Trash icon button.
  final String deleteTooltip;

  /// Canonical entity identifier displayed in monospace.
  final String entityId;

  /// Swaps the Trash icon button in-place into an inline delete confirmation banner.
  final bool isConfirmingDelete;

  /// Callback cancelling the inline delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback confirming deletion of the entity.
  final VoidCallback onConfirmDelete;

  /// Callback copying [entityId] and emitting confirmation feedback.
  final VoidCallback onCopyId;

  /// Callback requesting inline delete confirmation.
  final VoidCallback onRequestDelete;

  /// Optional contextual status pill label (e.g. completed read-only or open count).
  final String? statusPillLabel;

  /// Semantic visual tone for [statusPillLabel].
  final UiPillTone statusPillTone;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    final leadingMeta = _EntityMetaBarLeadingCluster(
      entityIdLabel: localizations.taskIdRowLabel(entityId),
      copyIdTooltip: copyIdTooltip,
      onCopyId: onCopyId,
      statusPillLabel: statusPillLabel,
      statusPillTone: statusPillTone,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: tokens.colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 10.0),
        child: _EntityMetaBarLayout(
          leadingMeta: leadingMeta,
          deleteTooltip: deleteTooltip,
          deleteConfirmMessage: deleteConfirmMessage,
          isConfirmingDelete: isConfirmingDelete,
          onRequestDelete: onRequestDelete,
          onCancelDelete: onCancelDelete,
          onConfirmDelete: onConfirmDelete,
        ),
      ),
    );
  }
}

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
  final List<LocationOptionViewModel> allLocations;

  /// Whether this section can enter inline edit mode.
  final bool canEdit;

  /// Initial editable activation condition state.
  final ConditionDraftViewModel conditionDraft;

  /// Optional localized active/unmet condition status line.
  final String? conditionsStatusLabel;

  /// Read-only condition summary chips with optional clickable location targets.
  final List<ConditionSummaryChipViewModel> conditionsSummary;

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

  /// Callback validating and persisting an updated [ConditionDraftViewModel].
  final Future<V2ActionResult> Function(ConditionDraftViewModel draft) onSave;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  @override
  State<EntityConditionsSection> createState() =>
      _EntityConditionsSectionState();
}

/// Editable monospace `YYYY-MM-DD HH:MM` input paired with Material date and 24-hour time pickers.
class EntityHybridDateTimeField extends StatelessWidget {
  /// Creates an [EntityHybridDateTimeField].
  const EntityHybridDateTimeField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.fallbackLocalDateTime,
    this.onChanged,
    this.onSubmitted,
  });

  /// Whether the text field requests focus automatically on mount.
  final bool autofocus;

  /// Caller-owned text controller holding the local timestamp string.
  final TextEditingController controller;

  /// Whether manual editing and picker triggers are enabled.
  final bool enabled;

  /// Optional inline validation error text.
  final String? errorText;

  /// Optional parseable `YYYY-MM-DD HH:MM` fallback seeding date and time pickers.
  final String? fallbackLocalDateTime;

  /// Optional caller-owned focus node.
  final FocusNode? focusNode;

  /// Optional helper text below the input.
  final String? helperText;

  /// Optional placeholder hint text (defaults to `YYYY-MM-DD HH:MM`).
  final String? hintText;

  /// Optional field label above the input.
  final String? label;

  /// Optional callback invoked when the timestamp text changes via typing or pickers.
  final ValueChanged<String>? onChanged;

  /// Optional callback invoked when the user submits the field.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      kind: UiFieldKind.text,
      controller: controller,
      focusNode: focusNode,
      label: label,
      hintText: hintText ?? localizations.historyTimestampHint,
      helperText: helperText,
      errorText: errorText,
      enabled: enabled,
      autofocus: autofocus,
      isMonospace: true,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      trailingAction: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiButton(
            leadingIcon: Icons.calendar_today_outlined,
            variant: UiButtonVariant.icon,
            density: UiButtonDensity.sidebarDesktop,
            tooltip: localizations.tooltipPickDate,
            onPressed: enabled ? () => _pickDate(context) : null,
          ),
          UiButton(
            leadingIcon: Icons.schedule_rounded,
            variant: UiButtonVariant.icon,
            density: UiButtonDensity.sidebarDesktop,
            tooltip: localizations.tooltipPickTime,
            onPressed: enabled ? () => _pickTime(context) : null,
          ),
        ],
      ),
    );
  }

  /// Opens a Material date picker and merges the picked date into `YYYY-MM-DD HH:MM`.
  Future<void> _pickDate(BuildContext context) async {
    final fallback = _parseFallbackDateTime(fallbackLocalDateTime);
    final initialDate = _clampPickerDate(
      _parseLocalDate(controller.text) ?? fallback,
    );
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _firstPickerDate,
      lastDate: _lastPickerDate,
    );
    if (!context.mounted || pickedDate == null) {
      return;
    }
    final datePart = _formatIsoDate(pickedDate);
    final timePart =
        _extractTimePart(controller.text) ??
        _extractTimePart(fallbackLocalDateTime ?? '') ??
        _formatTimeOfDay(
          TimeOfDay(hour: fallback.hour, minute: fallback.minute),
        );
    final formatted = '$datePart $timePart';
    controller.text = formatted;
    controller.selection = TextSelection.collapsed(offset: formatted.length);
    onChanged?.call(formatted);
  }

  /// Opens a 24-hour Material time picker and merges the picked time into `YYYY-MM-DD HH:MM`.
  Future<void> _pickTime(BuildContext context) async {
    final fallback = _parseFallbackDateTime(fallbackLocalDateTime);
    final initialTime =
        _parseTimeOfDay(controller.text) ??
        TimeOfDay(hour: fallback.hour, minute: fallback.minute);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: _build24HourTimePicker,
    );
    if (!context.mounted || pickedTime == null) {
      return;
    }
    final datePart =
        _extractDatePart(controller.text) ?? _formatIsoDate(fallback);
    final formatted = '$datePart ${_formatTimeOfDay(pickedTime)}';
    controller.text = formatted;
    controller.selection = TextSelection.collapsed(offset: formatted.length);
    onChanged?.call(formatted);
  }
}

/// Editable monospace `HH:MM` input paired with a 24-hour Material clock picker.
class EntityHybridTimeField extends StatelessWidget {
  /// Creates an [EntityHybridTimeField].
  const EntityHybridTimeField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.enabled = true,
    this.onSubmitted,
  });

  /// Caller-owned text controller holding the `HH:MM` value.
  final TextEditingController controller;

  /// Whether manual editing and the clock picker button are enabled.
  final bool enabled;

  /// Optional placeholder hint text (defaults to `HH:MM`).
  final String? hintText;

  /// Optional field label above the input.
  final String? label;

  /// Optional callback invoked when the user submits the field.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      kind: UiFieldKind.text,
      controller: controller,
      label: label,
      hintText: hintText ?? 'HH:MM',
      enabled: enabled,
      isMonospace: true,
      onSubmitted: onSubmitted,
      trailingAction: UiButton(
        leadingIcon: Icons.schedule_rounded,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.sidebarDesktop,
        tooltip: localizations.tooltipPickTime,
        onPressed: enabled ? () => _pickTime(context) : null,
      ),
    );
  }

  /// Opens a 24-hour Material time picker and writes canonical `HH:MM` into [controller].
  Future<void> _pickTime(BuildContext context) async {
    final initialTime =
        _parseTimeOfDay(controller.text) ?? const TimeOfDay(hour: 9, minute: 0);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: _build24HourTimePicker,
    );
    if (!context.mounted || pickedTime == null) {
      return;
    }
    final formatted = _formatTimeOfDay(pickedTime);
    controller.text = formatted;
    controller.selection = TextSelection.collapsed(offset: formatted.length);
  }
}

/// Shared footer rendered inside inline entity section editors (`U-CARD-003`).
class EntityInlineEditorFooter extends StatelessWidget {
  /// Creates an [EntityInlineEditorFooter].
  const EntityInlineEditorFooter({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.errorText,
    this.clearLabel,
    this.onClear,
    this.isBusy = false,
    this.saveLabel,
  });

  /// Optional label for the left-aligned destructive clear button.
  final String? clearLabel;

  /// Optional inline validation or persistence error text announced via live region.
  final String? errorText;

  /// Disables actions and spins the Save button indicator while true.
  final bool isBusy;

  /// Callback cancelling the active inline edit.
  final VoidCallback onCancel;

  /// Optional callback clearing the section value.
  final VoidCallback? onClear;

  /// Callback committing the active inline edit.
  final VoidCallback onSave;

  /// Optional custom label overriding the default localized Save copy.
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final errorMessage = errorText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (errorMessage != null && errorMessage.isNotEmpty) ...<Widget>[
          _EntityInlineErrorText(message: errorMessage),
          SizedBox(height: tokens.spacing.space2),
        ],
        _EntityInlineEditorActionRow(
          clearLabel: clearLabel,
          onClear: onClear,
          onCancel: onCancel,
          onSave: onSave,
          isBusy: isBusy,
          saveLabel: saveLabel,
        ),
      ],
    );
  }
}

/// Shared read-only and inline-editable Reference Links section for Tasks and Labels (`U-COMP-006`).
class EntityLinksSection extends ConsumerStatefulWidget {
  /// Creates an [EntityLinksSection].
  const EntityLinksSection({
    super.key,
    required this.links,
    required this.isEditing,
    required this.canEdit,
    required this.isLabel,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSave,
    this.isBusy = false,
  });

  /// Whether this section can enter inline edit mode.
  final bool canEdit;

  /// Whether an asynchronous parent mutation is currently in progress.
  final bool isBusy;

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Distinguishes label link limits from task link limits during validation.
  final bool isLabel;

  /// Persisted reference links attached to the entity.
  final List<EntityLinkViewModel> links;

  /// Callback closing inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback validating and persisting the edited links list.
  final Future<V2ActionResult> Function(List<EntityLinkViewModel> links) onSave;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  @override
  ConsumerState<EntityLinksSection> createState() => _EntityLinksSectionState();
}

/// Shared read-only and inline-editable multi-line Note section for Tasks, Labels, and Locations.
class EntityNoteSection extends ConsumerStatefulWidget {
  /// Creates an [EntityNoteSection].
  const EntityNoteSection({
    super.key,
    required this.note,
    required this.isEditing,
    required this.canEdit,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSave,
    required this.onClear,
    this.onNoteCopied,
    this.isBusy = false,
  });

  /// Whether this section can enter inline edit mode.
  final bool canEdit;

  /// Whether an asynchronous parent mutation is currently in progress.
  final bool isBusy;

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Persisted multi-line note text, or `null` when unset.
  final String? note;

  /// Callback closing inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback clearing the persisted note text.
  final FutureOr<void> Function() onClear;

  /// Optional callback notified after copying the note to clipboard (e.g. telemetry).
  final VoidCallback? onNoteCopied;

  /// Callback validating and persisting the edited note text.
  final Future<V2ActionResult> Function(String rawNote) onSave;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  @override
  ConsumerState<EntityNoteSection> createState() => _EntityNoteSectionState();
}

/// Domain adapter wrapping [UiSearchablePicker] for Task and Draft label selection (`U-COMP-005`).
class EntitySearchableLabelPicker extends StatefulWidget {
  /// Creates an [EntitySearchableLabelPicker].
  const EntitySearchableLabelPicker({
    super.key,
    required this.allLabels,
    required this.selectedIds,
    required this.hasBothScopedAndGlobal,
    required this.onToggleLabel,
    required this.onCreateAndAssign,
    required this.onOpenLabelInfo,
    this.showSelectedChips = true,
    this.autoFocusSearch = false,
    this.isCompactSheet = false,
    this.scrollController,
    this.query,
    this.onQueryChanged,
    this.onRequestClose,
  });

  /// All workspace label options sorted alphabetically.
  final List<LabelPickerOptionViewModel> allLabels;

  /// Requests initial search input focus on desktop; ignored when [isCompactSheet] is true.
  final bool autoFocusSearch;

  /// Shows `All`, `Scoped`, and `Global` filter pills only when both label scopes exist.
  final bool hasBothScopedAndGlobal;

  /// Enforces mobile sheet `44px` rows and disables search autofocus (`U-A11Y-003`).
  final bool isCompactSheet;

  /// Callback creating and immediately assigning a new label from the trimmed query.
  final ValueChanged<String> onCreateAndAssign;

  /// Callback opening a label in the Labels manager with context preservation.
  final ValueChanged<String> onOpenLabelInfo;

  /// Optional callback invoked whenever the search query text changes.
  final ValueChanged<String>? onQueryChanged;

  /// Optional callback invoked when `Escape` is pressed with an empty query.
  final VoidCallback? onRequestClose;

  /// Callback toggling assignment of a label identifier.
  final ValueChanged<String> onToggleLabel;

  /// Optional controlled search query string.
  final String? query;

  /// Optional caller-owned scroll controller preserving picker scroll offset.
  final ScrollController? scrollController;

  /// Currently selected label identifiers.
  final Iterable<String> selectedIds;

  /// Controls whether selected removable split chips render above the search bar.
  final bool showSelectedChips;

  @override
  State<EntitySearchableLabelPicker> createState() =>
      _EntitySearchableLabelPickerState();
}

/// Manages inline editing draft state for [EntityConditionsSection].
class _EntityConditionsSectionState extends State<EntityConditionsSection> {
  late final TextEditingController _timeEndController;
  late final TextEditingController _timeStartController;

  late ConditionDraftViewModel _draft;
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
    final startMinutes = _parseTimeMinutes(startToken);
    final endMinutes = _parseTimeMinutes(endToken);
    if (startMinutes == null ||
        endMinutes == null ||
        startMinutes == endMinutes) {
      setState(() {
        _timeInputError = localizations.conditionTimeErrorInvalid;
      });
      return false;
    }
    final nextWindows = <TimeWindowDraftViewModel>[
      ..._draft.timeWindows,
      TimeWindowDraftViewModel(start: startToken, end: endToken),
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
      _draft = _draft.copyWith(locationsMode: mode);
      _saveErrorText = null;
    });
  }

  /// Removes the time window at [index] from the draft.
  void _handleRemoveTimeWindow(TimeWindowDraftViewModel window, int index) {
    if (index < 0 || index >= _draft.timeWindows.length) {
      return;
    }
    final nextWindows = List<TimeWindowDraftViewModel>.of(_draft.timeWindows)
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
                _draft.timesMode == ConditionDimensionMode.custom)) &&
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
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _saveErrorText = message;
        });
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _saveErrorText = message;
        });
    }
  }

  /// Updates the time-window condition dimension mode.
  void _handleTimesModeChanged(ConditionDimensionMode mode) {
    setState(() {
      _draft = _draft.copyWith(timesMode: mode);
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
    final nextIds = List<String>.of(_draft.selectedLocationIds);
    if (!nextIds.remove(locationId)) {
      nextIds.add(locationId);
    }
    setState(() {
      _draft = _draft.copyWith(selectedLocationIds: nextIds);
      _saveErrorText = null;
    });
  }

  /// Toggles ISO weekday [isoWeekday] (`1..7`) and keeps the draft sorted ascending.
  void _handleToggleWeekday(int isoWeekday) {
    final nextDays = List<int>.of(_draft.selectedWeekdays);
    if (!nextDays.remove(isoWeekday)) {
      nextDays.add(isoWeekday);
      nextDays.sort();
    }
    setState(() {
      _draft = _draft.copyWith(selectedWeekdays: nextDays);
      _saveErrorText = null;
    });
  }
}

/// Manages inline link list editing and external link launching for [EntityLinksSection].
class _EntityLinksSectionState extends ConsumerState<EntityLinksSection> {
  late final TextEditingController _titleController;
  late final TextEditingController _uriController;

  List<EntityLinkViewModel> _draftLinks = const <EntityLinkViewModel>[];
  int? _editingIndex;
  String? _inputErrorText;
  bool _isSubmitting = false;
  String? _saveErrorText;

  @override
  void initState() {
    super.initState();
    _draftLinks = List<EntityLinkViewModel>.of(widget.links);
    _titleController = TextEditingController();
    _uriController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant EntityLinksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _draftLinks = List<EntityLinkViewModel>.of(widget.links);
      _editingIndex = null;
      _titleController.clear();
      _uriController.clear();
      _inputErrorText = null;
      _saveErrorText = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _editingIndex = null;
      _inputErrorText = null;
      _saveErrorText = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _uriController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditing) {
      return widget.links.isNotEmpty
          ? _EntityLinksReadOnlyCard(
              links: widget.links,
              canEdit: widget.canEdit,
              isBusy: widget.isBusy,
              onStartEdit: widget.onStartEdit,
              onOpenLink: _handleOpenLink,
            )
          : const SizedBox.shrink();
    }

    return _EntityLinksEditCard(
      draftLinks: _draftLinks,
      hasPersistedLinks: widget.links.isNotEmpty,
      editingIndex: _editingIndex,
      titleController: _titleController,
      uriController: _uriController,
      inputErrorText: _inputErrorText,
      saveErrorText: _saveErrorText,
      isBusy: widget.isBusy || _isSubmitting,
      onReorder: _handleReorder,
      onStartRowEdit: _handleStartRowEdit,
      onDeleteRow: _handleDeleteRow,
      onInputChanged: _handleInputChanged,
      onCommitLinkInput: _handleCommitLinkInput,
      onCancelRowEdit: _handleCancelRowEdit,
      onClearAll: _handleClearAll,
      onCancel: widget.onCancelEdit,
      onSave: _handleSave,
    );
  }

  /// Exits inline row editing and clears the title/URI inputs.
  void _handleCancelRowEdit() {
    setState(() {
      _editingIndex = null;
      _titleController.clear();
      _uriController.clear();
      _inputErrorText = null;
    });
  }

  /// Persists an empty links list when clearing all links.
  Future<void> _handleClearAll() => _submitLinks(const <EntityLinkViewModel>[]);

  /// Validates the inline title/URI inputs and inserts or updates the target link row.
  bool _handleCommitLinkInput() {
    final editingIndex = _editingIndex;
    final error = TaskV2Controller.validateLinkInput(
      rawTitle: _titleController.text,
      rawUri: _uriController.text,
      currentCount: _draftLinks.length,
      isEditingExisting: editingIndex != null,
      isLabel: widget.isLabel,
      locale: Localizations.localeOf(context),
    );
    if (error != null) {
      setState(() => _inputErrorText = error);
      return false;
    }
    final nextLink = EntityLinkViewModel(
      title: _titleController.text.trim(),
      uri: _uriController.text.trim(),
    );
    final nextLinks = List<EntityLinkViewModel>.of(_draftLinks);
    if (editingIndex != null &&
        editingIndex >= 0 &&
        editingIndex < nextLinks.length) {
      nextLinks[editingIndex] = nextLink;
    } else {
      nextLinks.add(nextLink);
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingIndex = null;
      _titleController.clear();
      _uriController.clear();
      _inputErrorText = null;
      _saveErrorText = null;
    });
    return true;
  }

  /// Deletes the draft link row at [index] and keeps [_editingIndex] consistent.
  void _handleDeleteRow(EntityLinkViewModel link, int index) {
    if (index < 0 || index >= _draftLinks.length) {
      return;
    }
    final nextLinks = List<EntityLinkViewModel>.of(_draftLinks)
      ..removeAt(index);
    int? nextEditingIndex = _editingIndex;
    if (nextEditingIndex == index) {
      nextEditingIndex = null;
      _titleController.clear();
      _uriController.clear();
    } else if (nextEditingIndex != null && nextEditingIndex > index) {
      nextEditingIndex -= 1;
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingIndex = nextEditingIndex;
      _inputErrorText = null;
      _saveErrorText = null;
    });
  }

  /// Clears transient inline input validation errors when typing resumes.
  void _handleInputChanged(String value) {
    if (_inputErrorText != null) {
      setState(() => _inputErrorText = null);
    }
  }

  /// Opens [uri] through [linkActionControllerProvider] and shows a danger notice on failure.
  Future<void> _handleOpenLink(String uri) async {
    final outcome = await ref.read(linkActionControllerProvider).openLink(uri);
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case LinkOpenOutcome.opened:
        return;
      case LinkOpenOutcome.failed:
        final localizations = AppLocalizations.of(context);
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(
              localizations.errorOpenLinkFailed,
              tone: NoticeTone.danger,
            );
    }
  }

  /// Reorders the draft links list between [oldIndex] and [newIndex].
  void _handleReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _draftLinks.length ||
        newIndex < 0 ||
        newIndex >= _draftLinks.length ||
        oldIndex == newIndex) {
      return;
    }
    final nextLinks = List<EntityLinkViewModel>.of(_draftLinks);
    final moved = nextLinks.removeAt(oldIndex);
    nextLinks.insert(newIndex, moved);
    int? nextEditingIndex = _editingIndex;
    if (nextEditingIndex == oldIndex) {
      nextEditingIndex = newIndex;
    } else if (nextEditingIndex == newIndex) {
      nextEditingIndex = oldIndex;
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingIndex = nextEditingIndex;
      _saveErrorText = null;
    });
  }

  /// Commits any typed pending link input and saves [_draftLinks].
  Future<void> _handleSave() async {
    final hasPendingInput =
        _titleController.text.trim().isNotEmpty ||
        _uriController.text.trim().isNotEmpty;
    if (hasPendingInput && !_handleCommitLinkInput()) {
      return;
    }
    await _submitLinks(_draftLinks);
  }

  /// Loads [link] at [index] into the inline link inputs for updating.
  void _handleStartRowEdit(EntityLinkViewModel link, int index) {
    setState(() {
      _editingIndex = index;
      _titleController.text = link.title;
      _uriController.text = link.uri;
      _inputErrorText = null;
    });
  }

  /// Submits [links] to [widget.onSave] and displays inline failure messages if rejected.
  Future<void> _submitLinks(List<EntityLinkViewModel> links) async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _saveErrorText = null;
    });
    final result = await widget.onSave(
      List<EntityLinkViewModel>.unmodifiable(links),
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _saveErrorText = message;
        });
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _saveErrorText = message;
        });
    }
  }
}

/// Manages clipboard copy, text controller, and inline save state for [EntityNoteSection].
class _EntityNoteSectionState extends ConsumerState<EntityNoteSection> {
  late final TextEditingController _controller;

  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note ?? '');
  }

  @override
  void didUpdateWidget(covariant EntityNoteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      final seeded = widget.note ?? '';
      _controller.text = seeded;
      _controller.selection = TextSelection.collapsed(offset: seeded.length);
      _errorText = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _errorText = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final persistedNote = widget.note ?? '';
    if (!widget.isEditing) {
      return persistedNote.isNotEmpty
          ? _EntityNoteReadOnlyCard(
              note: persistedNote,
              canEdit: widget.canEdit,
              isBusy: widget.isBusy,
              onCopyNote: _handleCopyNote,
              onStartEdit: widget.onStartEdit,
            )
          : const SizedBox.shrink();
    }

    return _EntityNoteEditCard(
      controller: _controller,
      hasExistingNote: persistedNote.isNotEmpty,
      errorText: _errorText,
      isBusy: widget.isBusy || _isSubmitting,
      onChanged: _handleChanged,
      onClear: _handleClear,
      onCancel: widget.onCancelEdit,
      onSave: _handleSave,
    );
  }

  /// Clears transient inline error text when the user edits the note text.
  void _handleChanged(String value) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  /// Invokes [widget.onClear] while guarding against overlapping submissions.
  Future<void> _handleClear() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      await widget.onClear();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Copies the persisted note to the system clipboard and shows confirmation notice.
  Future<void> _handleCopyNote() async {
    final text = widget.note;
    if (text == null || text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    ref
        .read(floatingNoticeControllerProvider.notifier)
        .showNotice(localizations.noteCopiedSnackBar);
    widget.onNoteCopied?.call();
  }

  /// Submits the edited note text to [widget.onSave] and displays any returned error inline.
  Future<void> _handleSave() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final result = await widget.onSave(_controller.text);
    if (!mounted) {
      return;
    }
    switch (result) {
      case V2ActionSucceeded():
        setState(() => _isSubmitting = false);
      case V2ActionValidationFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
      case V2ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _errorText = message;
        });
    }
  }
}

/// Manages local scope filter selection and duplicate checking for [EntitySearchableLabelPicker].
class _EntitySearchableLabelPickerState
    extends State<EntitySearchableLabelPicker> {
  String _activeScopeId = _scopeAll;
  String _localQuery = '';

  @override
  void initState() {
    super.initState();
    _localQuery = widget.query ?? '';
  }

  @override
  void didUpdateWidget(covariant EntitySearchableLabelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hasBothScopedAndGlobal && _activeScopeId != _scopeAll) {
      _activeScopeId = _scopeAll;
    }
    if (widget.query case final controlledQuery?
        when controlledQuery != _localQuery) {
      _localQuery = controlledQuery;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final effectiveScope = widget.hasBothScopedAndGlobal
        ? _activeScopeId
        : _scopeAll;
    final selectedSet = switch (widget.selectedIds) {
      final Set<String> existingSet => existingSet,
      _ => widget.selectedIds.toSet(),
    };

    return UiSearchablePicker<String>(
      options: _buildPickerOptions(
        effectiveScope: effectiveScope,
        localizations: localizations,
      ),
      selectedIds: selectedSet,
      onToggleOption: (option) => widget.onToggleLabel(option.value),
      emptyText: widget.allLabels.isEmpty
          ? localizations.labelPickerEmptyHint
          : localizations.labelPickerNoMatches,
      searchMaxLength: _labelPickerSearchMaxLength,
      showSelectedChips: widget.showSelectedChips,
      autoFocusSearch: widget.autoFocusSearch && !widget.isCompactSheet,
      isCompactSheet: widget.isCompactSheet,
      scrollController: widget.scrollController,
      scopeFilters: _buildScopeFilters(localizations),
      activeScopeId: effectiveScope,
      onScopeChanged: (scopeId) => setState(() => _activeScopeId = scopeId),
      query: widget.query,
      onQueryChanged: _handleQueryChanged,
      searchPlaceholder: localizations.labelPickerSearchPlaceholder,
      searchClearTooltip: localizations.tooltipClearSearch,
      infoTooltip: localizations.openLabelInManagerTooltip,
      onOptionInfo: (option) => widget.onOpenLabelInfo(option.value),
      removeChipTooltip: (option) =>
          localizations.labelPickerRemoveTooltip(option.label),
      inlineCreateLabel: localizations.labelPickerCreateAndAssign,
      onInlineCreate: _hasExactLabelMatch(_localQuery)
          ? null
          : widget.onCreateAndAssign,
      onRequestClose: widget.onRequestClose,
    );
  }

  /// Maps visible [LabelPickerOptionViewModel] entries into [UiPickerOption] models.
  List<UiPickerOption<String>> _buildPickerOptions({
    required String effectiveScope,
    required AppLocalizations localizations,
  }) {
    final results = <UiPickerOption<String>>[];
    for (final label in widget.allLabels) {
      if (effectiveScope == _scopeScoped && !label.isScoped) {
        continue;
      }
      if (effectiveScope == _scopeGlobal && label.isScoped) {
        continue;
      }
      results.add(
        UiPickerOption<String>(
          id: label.id,
          value: label.id,
          label: label.name,
          colorDot: _resolveOptionalColor(label.colorValue),
          badgeLabel: label.isScoped ? localizations.scopedQueueLabel : null,
          countLabel: localizations.openTasksCountPill('${label.openCount}'),
          hasInfoAction: true,
        ),
      );
    }
    return results;
  }

  /// Builds conditional `All`, `Scoped`, and `Global` filter pills when both scopes exist.
  List<UiPickerScopeFilter> _buildScopeFilters(AppLocalizations localizations) {
    if (!widget.hasBothScopedAndGlobal) {
      return const <UiPickerScopeFilter>[];
    }
    var scopedCount = 0;
    for (final label in widget.allLabels) {
      if (label.isScoped) {
        scopedCount++;
      }
    }
    final totalCount = widget.allLabels.length;
    final globalCount = totalCount - scopedCount;
    return <UiPickerScopeFilter>[
      UiPickerScopeFilter(
        id: _scopeAll,
        label: localizations.labelPickerFilterAll('$totalCount'),
      ),
      UiPickerScopeFilter(
        id: _scopeScoped,
        label: localizations.labelPickerFilterScoped('$scopedCount'),
      ),
      UiPickerScopeFilter(
        id: _scopeGlobal,
        label: localizations.labelPickerFilterGlobal('$globalCount'),
      ),
    ];
  }

  /// Tracks the latest search text for cross-scope duplicate detection and forwards changes.
  void _handleQueryChanged(String nextQuery) {
    if (_localQuery != nextQuery) {
      setState(() => _localQuery = nextQuery);
    }
    widget.onQueryChanged?.call(nextQuery);
  }

  /// Returns `true` when [rawQuery] matches any workspace label name case-insensitively.
  bool _hasExactLabelMatch(String rawQuery) {
    final normalized = rawQuery.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    for (final label in widget.allLabels) {
      if (label.name.trim().toLowerCase() == normalized) {
        return true;
      }
    }
    return false;
  }
}

/// Renders an inline `danger` live-region validation or persistence error message.
class _EntityInlineErrorText extends StatelessWidget {
  /// Creates an [_EntityInlineErrorText].
  const _EntityInlineErrorText({required this.message});

  /// Localized error copy to announce.
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

/// Renders the bordered action row inside [EntityInlineEditorFooter].
class _EntityInlineEditorActionRow extends StatelessWidget {
  /// Creates an [_EntityInlineEditorActionRow].
  const _EntityInlineEditorActionRow({
    required this.clearLabel,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
    required this.isBusy,
    required this.saveLabel,
  });

  /// Optional left clear button label.
  final String? clearLabel;

  /// Disables actions and spins Save indicator while true.
  final bool isBusy;

  /// Cancel callback.
  final VoidCallback onCancel;

  /// Optional clear callback.
  final VoidCallback? onClear;

  /// Save callback.
  final VoidCallback onSave;

  /// Optional custom Save label.
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    final showClear = clearLabel != null && onClear != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: tokens.colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: tokens.spacing.space2),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: tokens.spacing.space2,
          runSpacing: tokens.spacing.space2,
          children: <Widget>[
            if (showClear)
              UiButton(
                label: clearLabel,
                variant: UiButtonVariant.danger,
                density: UiButtonDensity.compact,
                onPressed: isBusy ? null : onClear,
              )
            else
              const SizedBox.shrink(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                UiButton(
                  label: localizations.actionCancel,
                  variant: UiButtonVariant.secondary,
                  density: UiButtonDensity.compact,
                  onPressed: isBusy ? null : onCancel,
                ),
                const SizedBox(width: 6.0),
                UiButton(
                  label: saveLabel ?? localizations.actionSave,
                  leadingIcon: isBusy ? Icons.sync_rounded : null,
                  variant: UiButtonVariant.primary,
                  density: UiButtonDensity.compact,
                  isLoading: isBusy,
                  onPressed: isBusy ? null : onSave,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the left-side ID, copy trigger, and optional contextual status pill inside [EntityCardMetaBar].
class _EntityMetaBarLeadingCluster extends StatelessWidget {
  /// Creates an [_EntityMetaBarLeadingCluster].
  const _EntityMetaBarLeadingCluster({
    required this.entityIdLabel,
    required this.copyIdTooltip,
    required this.onCopyId,
    required this.statusPillLabel,
    required this.statusPillTone,
  });

  /// Tooltip for the compact copy button.
  final String copyIdTooltip;

  /// Localized `ID: <id>` string.
  final String entityIdLabel;

  /// Callback invoked when Copy ID is pressed.
  final VoidCallback onCopyId;

  /// Optional status pill text.
  final String? statusPillLabel;

  /// Visual tone for [statusPillLabel].
  final UiPillTone statusPillTone;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final pillText = statusPillLabel;

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          entityIdLabel,
          style: UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: tokens.colors.muted),
          ),
        ),
        UiButton(
          leadingIcon: Icons.copy_outlined,
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.dense,
          tooltip: copyIdTooltip,
          onPressed: onCopyId,
        ),
        if (pillText != null && pillText.isNotEmpty)
          UiPill(
            label: pillText,
            variant: UiPillVariant.badge,
            tone: statusPillTone,
          ),
      ],
    );
  }
}

/// Arranges [leadingMeta] and the right-aligned Trash button or inline delete confirmation banner.
class _EntityMetaBarLayout extends StatelessWidget {
  /// Creates an [_EntityMetaBarLayout].
  const _EntityMetaBarLayout({
    required this.leadingMeta,
    required this.deleteTooltip,
    required this.deleteConfirmMessage,
    required this.isConfirmingDelete,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
  });

  /// Prompt shown inside the inline confirmation banner.
  final String deleteConfirmMessage;

  /// Tooltip for the Trash icon button.
  final String deleteTooltip;

  /// Whether the inline delete confirmation banner replaces the Trash icon button.
  final bool isConfirmingDelete;

  /// Left-aligned ID, copy trigger, and optional status pill cluster.
  final Widget leadingMeta;

  /// Callback cancelling delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback confirming deletion.
  final VoidCallback onConfirmDelete;

  /// Callback opening inline delete confirmation.
  final VoidCallback onRequestDelete;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (isConfirmingDelete) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8.0,
        runSpacing: 8.0,
        children: <Widget>[
          leadingMeta,
          UiBanner(
            variant: UiBannerVariant.inlineConfirm,
            message: deleteConfirmMessage,
            cancelLabel: localizations.actionKeep,
            confirmLabel: localizations.actionConfirmDelete,
            onCancel: onCancelDelete,
            onConfirm: onConfirmDelete,
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: leadingMeta),
        const SizedBox(width: 8.0),
        UiButton(
          leadingIcon: Icons.delete_outline_rounded,
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.dense,
          isDangerHover: true,
          tooltip: deleteTooltip,
          onPressed: onRequestDelete,
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
  final List<ConditionSummaryChipViewModel> conditionsSummary;

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
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    final statusLine = conditionsStatusLabel;

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
      child: Column(
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
              style: tokens.typography.meta.copyWith(
                color: tokens.colors.muted,
              ),
            ),
            SizedBox(height: tokens.spacing.space2),
          ],
          if (conditionsSummary.isNotEmpty)
            _EntityConditionSummaryChipWrap(
              chips: conditionsSummary,
              onOpenLocation: onOpenLocation,
            ),
        ],
      ),
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
  final List<ConditionSummaryChipViewModel> chips;

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

/// Renders one condition summary pill, navigating to Locations manager when `locationId` is set.
class _EntityConditionSummaryChip extends StatelessWidget {
  /// Creates an [_EntityConditionSummaryChip].
  const _EntityConditionSummaryChip({
    required this.chip,
    required this.onOpenLocation,
  });

  /// Condition summary view model.
  final ConditionSummaryChipViewModel chip;

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
  final List<LocationOptionViewModel> allLocations;

  /// Current editable condition draft.
  final ConditionDraftViewModel draft;

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
  final UiOrderedItemActionCallback<TimeWindowDraftViewModel>
  onRemoveTimeWindow;

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
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    final controls = _EntityConditionsControlsBody(
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
    );

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
      child: Column(
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
            child: IgnorePointer(ignoring: isSuspended, child: controls),
          ),
        ],
      ),
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
  final List<LocationOptionViewModel> allLocations;

  /// Current editable condition draft.
  final ConditionDraftViewModel draft;

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
  final UiOrderedItemActionCallback<TimeWindowDraftViewModel>
  onRemoveTimeWindow;

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
    final localizations = AppLocalizations.of(context);
    final dimensionsEnabled =
        !isBusy && (!isTask || !draft.ignoreAllLabelConditions);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (isTask)
          UiToggleRow(
            label: localizations.conditionGlobalAnyLabel,
            value: draft.ignoreAllLabelConditions,
            isDense: true,
            enabled: !isBusy,
            onChanged: onToggleIgnoreAll,
          )
        else
          Text(
            localizations.labelConditionsSectionDescription,
            style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
          ),
        SizedBox(height: tokens.spacing.space3),
        _EntityConditionDimensionGroup(
          title: localizations.conditionDayGroupTitle,
          isTask: isTask,
          anyLabel: localizations.conditionDayAnyLabel,
          mode: draft.daysMode,
          enabled: dimensionsEnabled,
          onModeChanged: onDaysModeChanged,
          customChild: _EntityConditionWeekdaysPicker(
            selectedWeekdays: draft.selectedWeekdays,
            enabled: dimensionsEnabled,
            onToggleWeekday: onToggleWeekday,
          ),
        ),
        SizedBox(height: tokens.spacing.space3),
        _EntityConditionDimensionGroup(
          title: localizations.conditionTimeGroupTitle,
          isTask: isTask,
          anyLabel: localizations.conditionTimeAnyLabel,
          mode: draft.timesMode,
          enabled: dimensionsEnabled,
          onModeChanged: onTimesModeChanged,
          customChild: _EntityConditionTimeWindowsPicker(
            timeWindows: draft.timeWindows,
            startController: timeStartController,
            endController: timeEndController,
            errorText: timeInputError,
            enabled: dimensionsEnabled,
            onAddTimeWindow: onAddTimeWindow,
            onRemoveTimeWindow: onRemoveTimeWindow,
          ),
        ),
        SizedBox(height: tokens.spacing.space3),
        _EntityConditionDimensionGroup(
          title: localizations.conditionLocationGroupTitle,
          isTask: isTask,
          anyLabel: localizations.conditionLocationAnyLabel,
          mode: draft.locationsMode,
          enabled: dimensionsEnabled,
          onModeChanged: onLocationsModeChanged,
          customChild: _EntityConditionLocationsPicker(
            allLocations: allLocations,
            selectedLocationIds: draft.selectedLocationIds,
            enabled: dimensionsEnabled,
            onToggleLocation: onToggleLocation,
          ),
        ),
      ],
    );
  }
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
    final localizations = AppLocalizations.of(context);
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
          UiSegmentedControl<ConditionDimensionMode>(
            semanticLabel: title,
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
  final UiOrderedItemActionCallback<TimeWindowDraftViewModel>
  onRemoveTimeWindow;

  /// Controller for the start `HH:MM` input.
  final TextEditingController startController;

  /// Configured daily time windows.
  final List<TimeWindowDraftViewModel> timeWindows;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);

    return UiOrderedItemList<TimeWindowDraftViewModel>(
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
        UiResponsiveGrid(
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
        ),
        if (error != null && error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6.0),
          _EntityInlineErrorText(message: error),
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
  final List<LocationOptionViewModel> allLocations;

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

/// Renders read-only Reference Links card with clickable `panel` link rows.
class _EntityLinksReadOnlyCard extends StatelessWidget {
  /// Creates an [_EntityLinksReadOnlyCard].
  const _EntityLinksReadOnlyCard({
    required this.links,
    required this.canEdit,
    required this.isBusy,
    required this.onStartEdit,
    required this.onOpenLink,
  });

  /// Whether the edit pencil button is displayed.
  final bool canEdit;

  /// Disables edit trigger while busy.
  final bool isBusy;

  /// Reference links to display.
  final List<EntityLinkViewModel> links;

  /// Callback launching a link URI.
  final ValueChanged<String> onOpenLink;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.link_rounded,
      headerTitle: localizations.linksSectionTitle,
      headerBadge: UiPill(
        label: '${links.length} / $_maxLinksPerEntity',
        variant: UiPillVariant.count,
      ),
      headerTrailing: canEdit
          ? UiButton(
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.dense,
              tooltip: localizations.actionEdit,
              onPressed: isBusy ? null : onStartEdit,
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < links.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 6.0),
            _EntityReadOnlyLinkRow(
              link: links[index],
              onTap: () => onOpenLink(links[index].uri),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-width clickable `panel` link card rendered inside a `bg` inset well (`U-COMP-006`).
class _EntityReadOnlyLinkRow extends StatefulWidget {
  /// Creates an [_EntityReadOnlyLinkRow].
  const _EntityReadOnlyLinkRow({required this.link, required this.onTap});

  /// Link title and target URI.
  final EntityLinkViewModel link;

  /// Callback launching [link].
  final VoidCallback onTap;

  @override
  State<_EntityReadOnlyLinkRow> createState() => _EntityReadOnlyLinkRowState();
}

/// Manages pointer hover border and keyboard focus ring for [_EntityReadOnlyLinkRow].
class _EntityReadOnlyLinkRowState extends State<_EntityReadOnlyLinkRow> {
  bool _isHovered = false;
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: '${widget.link.title} (${localizations.tooltipOpenLink})',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (hovered) {
          if (_isHovered != hovered) {
            setState(() => _isHovered = hovered);
          }
        },
        onShowFocusHighlight: (focused) {
          if (_showFocusRing != focused) {
            setState(() => _showFocusRing = focused);
          }
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: _EntityReadOnlyLinkSurface(
            link: widget.link,
            isHovered: _isHovered,
            showFocusRing: _showFocusRing,
          ),
        ),
      ),
    );
  }
}

/// Paints the `panel` card body and optional `1px` `accent` focus ring for [_EntityReadOnlyLinkRow].
class _EntityReadOnlyLinkSurface extends StatelessWidget {
  /// Creates an [_EntityReadOnlyLinkSurface].
  const _EntityReadOnlyLinkSurface({
    required this.link,
    required this.isHovered,
    required this.showFocusRing,
  });

  /// Highlights the border and trailing icon in `accent` while hovered.
  final bool isHovered;

  /// Link title and target URI.
  final EntityLinkViewModel link;

  /// Renders an outer `1px` `accent` keyboard focus ring when true.
  final bool showFocusRing;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final radius = tokens.radii.md;
    final card = AnimatedContainer(
      duration: tokens.focus.hoverDuration,
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isHovered ? colors.accent : colors.line,
          width: tokens.radii.borderWidth,
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: _EntityLinkListItem(link: link)),
          const SizedBox(width: 10.0),
          ExcludeSemantics(
            child: Icon(
              Icons.open_in_new_rounded,
              size: tokens.spacing.iconSm,
              color: isHovered ? colors.accent : colors.muted,
            ),
          ),
        ],
      ),
    );

    if (!showFocusRing) {
      return card;
    }
    return _EntityFocusRingBox(radius: radius, child: card);
  }
}

/// Wraps [child] with the canonical `1px` offset `accent` keyboard focus ring (`U-A11Y-001`).
class _EntityFocusRingBox extends StatelessWidget {
  /// Creates an [_EntityFocusRingBox].
  const _EntityFocusRingBox({required this.radius, required this.child});

  /// Focusable surface widget.
  final Widget child;

  /// Base corner radius of [child].
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final ringInset = tokens.focus.ringOffset + tokens.focus.ringWidth;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        Positioned.fill(
          left: -ringInset,
          top: -ringInset,
          right: -ringInset,
          bottom: -ringInset,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius + ringInset),
                border: Border.all(
                  color: tokens.colors.accent,
                  width: tokens.focus.ringWidth,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders the inline editing inset card for [EntityLinksSection].
class _EntityLinksEditCard extends StatelessWidget {
  /// Creates an [_EntityLinksEditCard].
  const _EntityLinksEditCard({
    required this.draftLinks,
    required this.hasPersistedLinks,
    required this.editingIndex,
    required this.titleController,
    required this.uriController,
    required this.inputErrorText,
    required this.saveErrorText,
    required this.isBusy,
    required this.onReorder,
    required this.onStartRowEdit,
    required this.onDeleteRow,
    required this.onInputChanged,
    required this.onCommitLinkInput,
    required this.onCancelRowEdit,
    required this.onClearAll,
    required this.onCancel,
    required this.onSave,
  });

  /// Editable draft links list.
  final List<EntityLinkViewModel> draftLinks;

  /// Row index currently being updated inline, or `null` when adding.
  final int? editingIndex;

  /// Controls whether the footer Clear button is shown.
  final bool hasPersistedLinks;

  /// Optional validation error for the inline link form inputs.
  final String? inputErrorText;

  /// Disables controls while submitting.
  final bool isBusy;

  /// Callback cancelling the whole links section edit.
  final VoidCallback onCancel;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback clearing all persisted links.
  final VoidCallback onClearAll;

  /// Callback adding or updating the typed link row.
  final VoidCallback onCommitLinkInput;

  /// Callback removing a link row.
  final UiOrderedItemActionCallback<EntityLinkViewModel> onDeleteRow;

  /// Callback clearing input validation error when text changes.
  final ValueChanged<String> onInputChanged;

  /// Callback moving a link row up or down.
  final UiOrderedItemReorderCallback onReorder;

  /// Callback saving the entire links list.
  final VoidCallback onSave;

  /// Callback starting inline edit on a link row.
  final UiOrderedItemActionCallback<EntityLinkViewModel> onStartRowEdit;

  /// Optional persistence or validation error returned by `onSave`.
  final String? saveErrorText;

  /// Title text controller.
  final TextEditingController titleController;

  /// URI text controller.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      isEditing: true,
      headerIcon: Icons.link_rounded,
      headerTitle: localizations.linksSectionTitle,
      headerBadge: UiPill(
        label: '${draftLinks.length} / $_maxLinksPerEntity',
        variant: UiPillVariant.count,
      ),
      footer: EntityInlineEditorFooter(
        errorText: saveErrorText,
        clearLabel: hasPersistedLinks ? localizations.inlineClearAction : null,
        onClear: hasPersistedLinks ? onClearAll : null,
        onCancel: onCancel,
        onSave: onSave,
        isBusy: isBusy,
      ),
      child: UiOrderedItemList<EntityLinkViewModel>(
        items: draftLinks,
        itemKey: (link, index) =>
            ValueKey<String>('entity_link_${index}_${link.uri}'),
        editingIndex: editingIndex,
        onReorder: isBusy ? null : onReorder,
        moveUpTooltip: localizations.tooltipMoveLinkUp,
        moveDownTooltip: localizations.tooltipMoveLinkDown,
        onEdit: isBusy ? null : onStartRowEdit,
        editTooltip: localizations.tooltipEditLink,
        onDelete: isBusy ? null : onDeleteRow,
        deleteTooltip: localizations.tooltipRemoveLink,
        itemBuilder: (context, link, index, isEditingRow) =>
            _EntityLinkListItem(link: link),
        addBar: _EntityLinkFormBar(
          titleController: titleController,
          uriController: uriController,
          isEditingExisting: editingIndex != null,
          errorText: inputErrorText,
          enabled: !isBusy,
          onChanged: onInputChanged,
          onSubmitLink: onCommitLinkInput,
          onCancelRowEdit: onCancelRowEdit,
        ),
      ),
    );
  }
}

/// Renders one link title and monospace URI stack inside read-only cards and [UiOrderedItemList].
class _EntityLinkListItem extends StatelessWidget {
  /// Creates an [_EntityLinkListItem].
  const _EntityLinkListItem({required this.link});

  /// Reference link displayed in this row.
  final EntityLinkViewModel link;

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
          style: tokens.typography.control.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2.0),
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

/// Renders inline title + URI fields, validation error, and Add/Update link buttons.
class _EntityLinkFormBar extends StatelessWidget {
  /// Creates an [_EntityLinkFormBar].
  const _EntityLinkFormBar({
    required this.titleController,
    required this.uriController,
    required this.isEditingExisting,
    required this.errorText,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitLink,
    required this.onCancelRowEdit,
  });

  /// Whether inputs and submit button are enabled.
  final bool enabled;

  /// Optional inline link validation error text.
  final String? errorText;

  /// Swaps `Add link` to `Update link` + `Cancel` when true.
  final bool isEditingExisting;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback notified when either input changes.
  final ValueChanged<String> onChanged;

  /// Callback validating and committing the typed link row.
  final VoidCallback onSubmitLink;

  /// Link title controller.
  final TextEditingController titleController;

  /// Link URI controller.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    final error = errorText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
              autofocus: true,
              enabled: enabled,
              onChanged: onChanged,
              onSubmitted: (_) => onSubmitLink(),
            ),
            UiField(
              kind: UiFieldKind.text,
              controller: uriController,
              hintText: localizations.linkUriHint,
              isMonospace: true,
              enabled: enabled,
              onChanged: onChanged,
              onSubmitted: (_) => onSubmitLink(),
            ),
          ],
        ),
        if (error != null && error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6.0),
          _EntityInlineErrorText(message: error),
        ],
        SizedBox(height: tokens.spacing.space2),
        _EntityLinkFormActions(
          isEditingExisting: isEditingExisting,
          enabled: enabled,
          onSubmitLink: onSubmitLink,
          onCancelRowEdit: onCancelRowEdit,
        ),
      ],
    );
  }
}

/// Renders the Add/Update link button and optional row-edit Cancel button.
class _EntityLinkFormActions extends StatelessWidget {
  /// Creates an [_EntityLinkFormActions].
  const _EntityLinkFormActions({
    required this.isEditingExisting,
    required this.enabled,
    required this.onSubmitLink,
    required this.onCancelRowEdit,
  });

  /// Whether buttons accept interaction.
  final bool enabled;

  /// Switches label from `Add link` to `Update link` and exposes `Cancel`.
  final bool isEditingExisting;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback adding or updating the link row.
  final VoidCallback onSubmitLink;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        UiButton(
          label: isEditingExisting
              ? localizations.tooltipSaveLink
              : localizations.tooltipAddLink,
          leadingIcon: isEditingExisting ? null : Icons.add_rounded,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: enabled ? onSubmitLink : null,
        ),
        if (isEditingExisting)
          UiButton(
            label: localizations.actionCancel,
            variant: UiButtonVariant.text,
            density: UiButtonDensity.compact,
            tooltip: localizations.tooltipCancelEditLink,
            onPressed: enabled ? onCancelRowEdit : null,
          ),
      ],
    );
  }
}

/// Renders read-only Note inset card with Copy Note trigger, optional Edit pencil, and [SelectableText].
class _EntityNoteReadOnlyCard extends StatelessWidget {
  /// Creates an [_EntityNoteReadOnlyCard].
  const _EntityNoteReadOnlyCard({
    required this.note,
    required this.canEdit,
    required this.isBusy,
    required this.onCopyNote,
    required this.onStartEdit,
  });

  /// Whether the Edit pencil trigger is displayed.
  final bool canEdit;

  /// Disables the Edit pencil while busy.
  final bool isBusy;

  /// Multi-line note body preserving line breaks.
  final String note;

  /// Callback copying [note] to clipboard.
  final VoidCallback onCopyNote;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      headerIcon: Icons.description_outlined,
      headerTitle: localizations.taskNoteLabel,
      headerTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiButton(
            leadingIcon: Icons.copy_outlined,
            variant: UiButtonVariant.icon,
            density: UiButtonDensity.dense,
            tooltip: localizations.tooltipCopyNote,
            onPressed: onCopyNote,
          ),
          if (canEdit)
            UiButton(
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.dense,
              tooltip: localizations.actionEdit,
              onPressed: isBusy ? null : onStartEdit,
            ),
        ],
      ),
      child: SelectableText(
        note,
        style: tokens.typography.control.copyWith(
          color: tokens.colors.ink,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// Renders inline-editing Note inset card with multiline [UiField] and [EntityInlineEditorFooter].
class _EntityNoteEditCard extends StatelessWidget {
  /// Creates an [_EntityNoteEditCard].
  const _EntityNoteEditCard({
    required this.controller,
    required this.hasExistingNote,
    required this.errorText,
    required this.isBusy,
    required this.onChanged,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
  });

  /// Multiline note text controller.
  final TextEditingController controller;

  /// Optional inline validation or persistence error message.
  final String? errorText;

  /// Shows the Clear button only when an existing note is persisted.
  final bool hasExistingNote;

  /// Disables input and footer controls while saving.
  final bool isBusy;

  /// Callback cancelling inline edit mode.
  final VoidCallback onCancel;

  /// Callback invoked when the note text changes.
  final ValueChanged<String> onChanged;

  /// Callback clearing the existing note.
  final VoidCallback onClear;

  /// Callback saving the edited note.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      isEditing: true,
      headerIcon: Icons.description_outlined,
      headerTitle: localizations.taskNoteLabel,
      footer: EntityInlineEditorFooter(
        errorText: errorText,
        clearLabel: hasExistingNote ? localizations.inlineClearAction : null,
        onClear: hasExistingNote ? onClear : null,
        onCancel: onCancel,
        onSave: onSave,
        isBusy: isBusy,
      ),
      child: UiField(
        kind: UiFieldKind.multiline,
        controller: controller,
        hintText: localizations.taskNoteHint,
        maxLength: _maxNoteLength,
        autofocus: true,
        enabled: !isBusy,
        onChanged: onChanged,
      ),
    );
  }
}

/// Wraps [showTimePicker] in a 24-hour [MediaQuery] configuration.
Widget _build24HourTimePicker(BuildContext context, Widget? child) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
    child: child ?? const SizedBox.shrink(),
  );
}

/// Clamps [date] into the inclusive `2000-01-01..2100-12-31` Material date picker bounds.
DateTime _clampPickerDate(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  if (normalized.isBefore(_firstPickerDate)) {
    return _firstPickerDate;
  }
  if (normalized.isAfter(_lastPickerDate)) {
    return _lastPickerDate;
  }
  return normalized;
}

/// Extracts a validated `YYYY-MM-DD` date prefix from [rawInput], or `null` if invalid.
String? _extractDatePart(String rawInput) {
  final parsed = _parseLocalDate(rawInput);
  if (parsed == null) {
    return null;
  }
  return _formatIsoDate(parsed);
}

/// Extracts a validated `HH:MM` time suffix from [rawInput], or `null` if absent or invalid.
String? _extractTimePart(String rawInput) {
  final trimmed = rawInput.trim();
  if (trimmed.length == 5) {
    return _parseTimeMinutes(trimmed) != null ? trimmed : null;
  }
  if (trimmed.length < 16) {
    return null;
  }
  final separator = trimmed.codeUnitAt(10);
  if (separator != 0x20 && separator != 0x54) {
    return null;
  }
  final candidate = trimmed.substring(11, 16);
  if (trimmed.length > 16 && trimmed.substring(16).trim().isNotEmpty) {
    return null;
  }
  return _parseTimeMinutes(candidate) != null ? candidate : null;
}

/// Formats [date] into canonical `YYYY-MM-DD`.
String _formatIsoDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Formats [time] into zero-padded 24-hour `HH:MM`.
String _formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Parses [length] ASCII digits starting at [start] in [text], or `null` on non-digit input.
int? _parseAsciiDigits(String text, int start, int length) {
  if (start < 0 || start + length > text.length) {
    return null;
  }
  var value = 0;
  for (var offset = 0; offset < length; offset++) {
    final digit = text.codeUnitAt(start + offset) - 0x30;
    if (digit < 0 || digit > 9) {
      return null;
    }
    value = value * 10 + digit;
  }
  return value;
}

/// Parses an optional `YYYY-MM-DD [HH:MM]` fallback timestamp into a local [DateTime], falling back to `DateTime.now()`.
DateTime _parseFallbackDateTime(String? rawFallback) {
  if (rawFallback == null) {
    return DateTime.now();
  }
  final date = _parseLocalDate(rawFallback);
  if (date == null) {
    return DateTime.now();
  }
  final time = _parseTimeOfDay(rawFallback);
  if (time == null) {
    return DateTime(date.year, date.month, date.day);
  }
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Parses a `YYYY-MM-DD` date prefix from [rawInput], verifying real calendar dates.
DateTime? _parseLocalDate(String rawInput) {
  final trimmed = rawInput.trim();
  if (trimmed.length < 10) {
    return null;
  }
  if (trimmed.codeUnitAt(4) != 0x2D || trimmed.codeUnitAt(7) != 0x2D) {
    return null;
  }
  if (trimmed.length > 10) {
    final separator = trimmed.codeUnitAt(10);
    if (separator != 0x20 && separator != 0x54) {
      return null;
    }
  }
  final year = _parseAsciiDigits(trimmed, 0, 4);
  final month = _parseAsciiDigits(trimmed, 5, 2);
  final day = _parseAsciiDigits(trimmed, 8, 2);
  if (year == null ||
      month == null ||
      day == null ||
      year < 1 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31) {
    return null;
  }
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

/// Parses an exact 24-hour `HH:MM` token into minutes since midnight (`0..1439`), or `null` if invalid.
int? _parseTimeMinutes(String rawToken) {
  if (rawToken.length != 5 || rawToken.codeUnitAt(2) != 0x3A) {
    return null;
  }
  final hour = _parseAsciiDigits(rawToken, 0, 2);
  final minute = _parseAsciiDigits(rawToken, 3, 2);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

/// Parses a `HH:MM` token or timestamp time suffix into a [TimeOfDay], or `null` if invalid.
TimeOfDay? _parseTimeOfDay(String rawInput) {
  final timeToken = _extractTimePart(rawInput);
  if (timeToken == null) {
    return null;
  }
  final minutes = _parseTimeMinutes(timeToken);
  if (minutes == null) {
    return null;
  }
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

/// Converts an optional ARGB integer [colorValue] into a [Color] without null assertions.
Color? _resolveOptionalColor(int? colorValue) {
  if (colorValue == null) {
    return null;
  }
  return Color(colorValue);
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
