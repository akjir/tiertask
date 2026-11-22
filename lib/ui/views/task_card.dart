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

import '../../l10n/app_localizations.dart';
import '../../models/location_state.dart';
import '../../models/task_board_evaluator.dart';
import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import '../../models/tdf_location.dart';
import '../../models/tdf_metadata.dart';
import '../../models/webdav_config.dart';
import '../../providers/board_actions_provider.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../../providers/ui_telemetry.dart';
import '../dialogs/compact_label_picker_sheet.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_pill.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../ui_domain_mappers.dart';
import '../widgets/entity_card_chrome.dart';
import '../widgets/entity_conditions_section.dart';
import '../widgets/entity_label_picker.dart';
import '../widgets/entity_links_section.dart';
import '../widgets/entity_note_section.dart';
import 'task_detail_editors.dart';
import 'task_schedule_editors.dart';

/// Expandable card rendering a single domain [TaskItem] and its inline editors (`U-CARD-001`..`005`).
class TaskCard extends ConsumerWidget {
  /// Creates a [TaskCard].
  const TaskCard({
    super.key,
    required this.task,
    required this.tier,
    required this.labelsById,
    required this.locationsById,
    required this.tasksById,
    required this.allLabels,
    required this.allLocations,
    required this.openLabelCounts,
    required this.isSearchMode,
    required this.activeLabelId,
    required this.configuration,
    required this.nowUtc,
    required this.localNow,
    required this.activeFix,
  });

  /// Active foreground GPS fix when status is [LocationStatus.found], or `null`.
  final LocationFix? activeFix;

  /// Active sidebar label filter identifier, or `null` for `All Tasks`.
  final String? activeLabelId;

  /// All sorted workspace labels supplied to inline and sheet label pickers.
  final List<TdfLabel> allLabels;

  /// All sorted workspace locations supplied to activation condition pickers.
  final List<TdfLocation> allLocations;

  /// Active workspace configuration supplying timezone and due lead-window settings.
  final WebDavConfig configuration;

  /// Whether Global Search mode is active (adds a tier pill to collapsed badges).
  final bool isSearchMode;

  /// Lookup map of workspace labels by identifier.
  final Map<String, TdfLabel> labelsById;

  /// Current local wall-clock evaluation timestamp in the workspace timezone.
  final DateTime localNow;

  /// Lookup map of workspace locations by identifier.
  final Map<String, TdfLocation> locationsById;

  /// Current evaluation UTC timestamp.
  final DateTime nowUtc;

  /// Precomputed map of open task counts keyed by label identifier.
  final Map<String, int> openLabelCounts;

  /// Domain task item rendered by this card.
  final TaskItem task;

  /// Lookup map of all workspace tasks by identifier for prerequisite evaluation.
  final Map<String, TaskItem> tasksById;

  /// Evaluated tier containing [task].
  final TaskTier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entityRef = EntityRef(kind: EntityKind.task, id: task.id);
    final headerSlice = ref.watch(
      shellProvider.select(
        (shell) => (
          isExpanded: shell.expandedEntity == entityRef,
          isTitleEditActive:
              shell.activeInlineEdit?.entity == entityRef &&
              shell.activeInlineEdit?.sectionKey == TaskSectionKind.title.name,
        ),
      ),
    );
    final isEditingTitle =
        headerSlice.isExpanded &&
        !task.isCompleted &&
        headerSlice.isTitleEditActive;

    return RepaintBoundary(
      child: _TaskCardFrame(
        contextData: _TaskCardContext(
          task: task,
          tier: tier,
          labelsById: labelsById,
          locationsById: locationsById,
          tasksById: tasksById,
          allLabels: allLabels,
          allLocations: allLocations,
          openLabelCounts: openLabelCounts,
          isSearchMode: isSearchMode,
          activeLabelId: activeLabelId,
          configuration: configuration,
          nowUtc: nowUtc,
          localNow: localNow,
          activeFix: activeFix,
        ),
        entityRef: entityRef,
        isExpanded: headerSlice.isExpanded,
        isEditingTitle: isEditingTitle,
      ),
    );
  }
}

/// Bottom `+ Add` dashed chips and solid direct `Priority` / `Someday` toggles bar (`U-CARD-002`).
class _TaskAddFieldsBar extends StatelessWidget {
  /// Creates a [_TaskAddFieldsBar].
  const _TaskAddFieldsBar({
    required this.task,
    required this.assignedLabels,
    required this.flags,
    required this.activeSection,
    required this.isInlineLabelPickerOpen,
    required this.isBusy,
    required this.onAddSection,
    required this.onSetPlacement,
  });

  /// Currently open inline section editor on this task, if any.
  final TaskSectionKind? activeSection;

  /// Resolved labels currently assigned to [task].
  final List<TdfLabel> assignedLabels;

  /// Lazily computed suspension, conditions, and placement flags.
  final _ExpandedPanelFlags flags;

  /// Whether a task mutation is currently in flight.
  final bool isBusy;

  /// Whether the desktop inline label picker is currently expanded.
  final bool isInlineLabelPickerOpen;

  /// Callback opening an unset section editor or label picker.
  final ValueChanged<TaskSectionKind> onAddSection;

  /// Callback immediately switching task placement (`Priority` or `Someday`).
  final ValueChanged<QuickAddMode> onSetPlacement;

  /// Domain task item.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    if (task.isCompleted) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    final chips = _buildOrderedChips(localizations);
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      key: ValueKey<String>('task_add_fields_bar_${task.id}'),
      spacing: 6.0,
      runSpacing: 6.0,
      children: chips,
    );
  }

  /// Appends solid 1-click `Priority` and `Someday` toggle chips (`isDirect: true`).
  void _appendDirectPlacementChips(
    List<Widget> chips,
    AppLocalizations localizations,
  ) {
    chips.add(
      UiPill(
        key: ValueKey<String>('task_direct_priority_${task.id}'),
        label: localizations.quickAddPriority,
        icon: Icons.bolt_outlined,
        variant: UiPillVariant.addField,
        isDirect: true,
        enabled: !isBusy,
        onPressed: isBusy ? null : () => onSetPlacement(QuickAddMode.priority),
      ),
    );
    chips.add(
      UiPill(
        key: ValueKey<String>('task_direct_someday_${task.id}'),
        label: localizations.tier5Name,
        icon: Icons.lightbulb_outline_rounded,
        variant: UiPillVariant.addField,
        isDirect: true,
        enabled: !isBusy,
        onPressed: isBusy ? null : () => onSetPlacement(QuickAddMode.someday),
      ),
    );
  }

  /// Builds unset dashed `+ Add` chips interleaved with direct `Priority`/`Someday` toggles in canonical order.
  List<Widget> _buildOrderedChips(AppLocalizations localizations) {
    final unset = _collectUnsetTaskSections(
      task: task,
      hasAssignedLabels: assignedLabels.isNotEmpty,
      isSuspended: flags.isSuspended,
      hasConditions: flags.hasConditions,
    );
    final chips = <Widget>[];
    final showDirectPlacement = flags.placement == QuickAddMode.standard;
    var insertedDirect = false;

    for (final section in unset) {
      if (showDirectPlacement && !insertedDirect && _comesAfterDue(section)) {
        _appendDirectPlacementChips(chips, localizations);
        insertedDirect = true;
      }
      if (section == activeSection ||
          (section == TaskSectionKind.labels && isInlineLabelPickerOpen)) {
        continue;
      }
      chips.add(
        UiPill(
          key: ValueKey<String>('task_add_${section.name}_${task.id}'),
          label: _taskAddChipLabel(section, localizations),
          icon: _taskAddChipIcon(section),
          variant: UiPillVariant.addField,
          enabled: !isBusy,
          onPressed: isBusy ? null : () => onAddSection(section),
        ),
      );
    }
    if (showDirectPlacement && !insertedDirect) {
      _appendDirectPlacementChips(chips, localizations);
    }
    return chips;
  }
}

/// Assigned label chips and `+ Add` trigger rendered inside [_TaskLabelsReadCard].
class _TaskAssignedLabelsWrap extends StatelessWidget {
  /// Creates a [_TaskAssignedLabelsWrap].
  const _TaskAssignedLabelsWrap({
    required this.task,
    required this.assignedLabels,
    required this.isBusy,
    required this.onToggleLabel,
    required this.onOpenLabelInfo,
    required this.onOpenPicker,
  });

  /// Resolved labels currently assigned to [task].
  final List<TdfLabel> assignedLabels;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback navigating to a label in Labels manager preserving `returnContext`.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback opening the label picker (desktop inline or compact sheet).
  final VoidCallback onOpenPicker;

  /// Callback toggling label assignment on the task.
  final ValueChanged<String> onToggleLabel;

  /// Domain task item.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final label in assignedLabels)
          UiPill(
            key: ValueKey<String>('task_expanded_label_${task.id}_${label.id}'),
            label: label.name,
            variant: UiPillVariant.splitChip,
            colorDot: _resolveLabelColor(label.color, tokens),
            tooltip: localizations.openLabelInManagerTooltip,
            removeTooltip: localizations.labelPickerRemoveTooltip(label.name),
            onPressed: () => onOpenLabelInfo(label.id),
            onRemove: task.isCompleted || isBusy
                ? null
                : () => onToggleLabel(label.id),
          ),
        if (!task.isCompleted)
          UiPill(
            key: ValueKey<String>('task_labels_add_button_${task.id}'),
            label: localizations.actionAdd,
            icon: Icons.add_rounded,
            variant: UiPillVariant.addField,
            enabled: !isBusy,
            onPressed: isBusy ? null : onOpenPicker,
          ),
      ],
    );
  }
}

/// Immutable domain bundle passed across [TaskCard] private subtrees.
@immutable
class _TaskCardContext {
  /// Creates a [_TaskCardContext].
  const _TaskCardContext({
    required this.task,
    required this.tier,
    required this.labelsById,
    required this.locationsById,
    required this.tasksById,
    required this.allLabels,
    required this.allLocations,
    required this.openLabelCounts,
    required this.isSearchMode,
    required this.activeLabelId,
    required this.configuration,
    required this.nowUtc,
    required this.localNow,
    required this.activeFix,
  });

  /// Active foreground GPS fix when status is [LocationStatus.found], or `null`.
  final LocationFix? activeFix;

  /// Active sidebar label filter identifier, or `null` for `All Tasks`.
  final String? activeLabelId;

  /// All sorted workspace labels.
  final List<TdfLabel> allLabels;

  /// All sorted workspace locations.
  final List<TdfLocation> allLocations;

  /// Active workspace configuration.
  final WebDavConfig configuration;

  /// Whether Global Search mode is active.
  final bool isSearchMode;

  /// Lookup map of workspace labels by identifier.
  final Map<String, TdfLabel> labelsById;

  /// Current local wall-clock evaluation timestamp.
  final DateTime localNow;

  /// Lookup map of workspace locations by identifier.
  final Map<String, TdfLocation> locationsById;

  /// Current evaluation UTC timestamp.
  final DateTime nowUtc;

  /// Precomputed map of open task counts keyed by label identifier.
  final Map<String, int> openLabelCounts;

  /// Domain task item.
  final TaskItem task;

  /// Lookup map of all workspace tasks by identifier.
  final Map<String, TaskItem> tasksById;

  /// Evaluated tier containing [task].
  final TaskTier tier;

  /// Whether the downgrade chevron action is available for [task].
  bool get canDowngrade =>
      !task.isCompleted &&
      (tier == TaskTier.focus ||
          tier == TaskTier.ready ||
          tier == TaskTier.planned);

  /// Whether [task] currently resides in Tier 5 (`Someday`).
  bool get isSomeday => tier == TaskTier.someday;
}

/// Expandable card chrome wiring header controls, collapsed metadata, and expanded panel for [TaskCard].
class _TaskCardFrame extends ConsumerWidget {
  /// Creates a [_TaskCardFrame].
  const _TaskCardFrame({
    required this.contextData,
    required this.entityRef,
    required this.isExpanded,
    required this.isEditingTitle,
  });

  /// Domain context bundle for the rendered task.
  final _TaskCardContext contextData;

  /// Entity reference identifying this task inside shell state.
  final EntityRef entityRef;

  /// Whether the inline title editor is currently active.
  final bool isEditingTitle;

  /// Whether this task card is currently expanded.
  final bool isExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = contextData.task;
    final assignedLabels = _resolveAssignedLabels(task, contextData.labelsById);
    final collapsedMetadata = isExpanded
        ? null
        : _buildCollapsedMetadata(context, assignedLabels);

    return UiCard.expandable(
      title: task.title,
      isExpanded: isExpanded,
      isCompleted: task.isCompleted,
      isEditingTitle: isEditingTitle,
      titleEditor: isEditingTitle
          ? TaskInlineTitleEditor(
              taskId: task.id,
              initialTitle: task.title,
              onCancel: () => _closeInlineEdit(ref),
            )
          : null,
      onToggleExpand: () => _toggleExpand(ref),
      leading: _TaskCompleteAction(task: task),
      trailingActions: isEditingTitle
          ? const <Widget>[]
          : <Widget>[
              if (isExpanded && !task.isCompleted)
                _TaskEditTitleButton(taskId: task.id),
              if (isExpanded) _TaskDeleteButton(taskId: task.id),
              if (contextData.canDowngrade)
                _TaskDowngradeButton(taskId: task.id),
            ],
      collapsedMetadata: collapsedMetadata,
      expandedChild: isExpanded
          ? _TaskExpandedPanel(
              contextData: contextData,
              assignedLabels: assignedLabels,
            )
          : null,
    );
  }

  /// Lazily builds the collapsed badge strip only when the card is collapsed.
  Widget? _buildCollapsedMetadata(
    BuildContext context,
    List<TdfLabel> assignedLabels,
  ) {
    final localizations = AppLocalizations.of(context);
    final badges = UiDomainMappers.buildTaskCollapsedBadges(
      task: contextData.task,
      tier: contextData.tier,
      isSearchMode: contextData.isSearchMode,
      activeLabelId: contextData.activeLabelId,
      labelsById: contextData.labelsById,
      locationsById: contextData.locationsById,
      tasksById: contextData.tasksById,
      config: contextData.configuration,
      nowUtc: contextData.nowUtc,
      localNow: contextData.localNow,
      activeFix: contextData.activeFix,
      localizations: localizations,
    );
    final hasAny =
        assignedLabels.isNotEmpty ||
        badges.primary.isNotEmpty ||
        badges.visibleSecondary.isNotEmpty ||
        badges.overflowCount > 0;
    if (!hasAny) {
      return null;
    }
    return _TaskCollapsedMetadataStrip(
      taskId: contextData.task.id,
      entityRef: entityRef,
      isSearchMode: contextData.isSearchMode,
      assignedLabels: assignedLabels,
      primaryBadges: badges.primary,
      visibleSecondaryBadges: badges.visibleSecondary,
      overflowSecondaryCount: badges.overflowCount,
    );
  }

  /// Closes the currently active inline title editor in shell state.
  void _closeInlineEdit(WidgetRef ref) {
    ref.read(shellProvider.notifier).closeInlineEdit();
  }

  /// Toggles card expansion for [entityRef].
  void _toggleExpand(WidgetRef ref) {
    ref.read(shellProvider.notifier).toggleExpandEntity(entityRef);
  }
}

/// Single collapsed metadata badge pill rendered inside [_TaskCollapsedMetadataStrip].
class _TaskCollapsedBadgePill extends StatelessWidget {
  /// Creates a [_TaskCollapsedBadgePill].
  const _TaskCollapsedBadgePill({required this.badge, required this.onPressed});

  /// Mapped domain task badge.
  final TaskCardBadge badge;

  /// Optional tap callback toggling card expansion.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return UiPill(
      label: badge.label,
      icon: badge.icon,
      variant: UiPillVariant.meta,
      tone: badge.tone,
      onPressed: onPressed,
    );
  }
}

/// Single assigned label pill rendered inside [_TaskCollapsedMetadataStrip].
class _TaskCollapsedLabelPill extends StatelessWidget {
  /// Creates a [_TaskCollapsedLabelPill].
  const _TaskCollapsedLabelPill({
    required this.taskId,
    required this.label,
    required this.onOpenLabel,
  });

  /// Assigned domain label.
  final TdfLabel label;

  /// Callback navigating to this label in Labels manager.
  final ValueChanged<String> onOpenLabel;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiPill(
      key: ValueKey<String>('task_label_chip_${taskId}_${label.id}'),
      label: label.name,
      variant: UiPillVariant.tag,
      colorDot: _resolveLabelColor(label.color, tokens),
      tooltip: localizations.openLabelInManagerTooltip,
      onPressed: () => onOpenLabel(label.id),
    );
  }
}

/// Collapsed task metadata strip enforcing `U-CARD-005` exact order and `3 + N` secondary overflow cap.
class _TaskCollapsedMetadataStrip extends ConsumerWidget {
  /// Creates a [_TaskCollapsedMetadataStrip].
  const _TaskCollapsedMetadataStrip({
    required this.taskId,
    required this.entityRef,
    required this.isSearchMode,
    required this.assignedLabels,
    required this.primaryBadges,
    required this.visibleSecondaryBadges,
    required this.overflowSecondaryCount,
  });

  /// Assigned domain labels (exempt from secondary overflow cap).
  final List<TdfLabel> assignedLabels;

  /// Entity reference identifying this task for expand toggling.
  final EntityRef entityRef;

  /// Whether Global Search mode is active (index `0` in [primaryBadges] is the tier pill).
  final bool isSearchMode;

  /// Number of hidden secondary badges beyond the 3-pill cap.
  final int overflowSecondaryCount;

  /// Primary badges exempt from secondary overflow (Search tier pill and Due/Overdue badge).
  final List<TaskCardBadge> primaryBadges;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  /// Up to 3 visible secondary badges in strict `U-CARD-005` priority order.
  final List<TaskCardBadge> visibleSecondaryBadges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);

    return Wrap(
      key: ValueKey<String>('task_collapsed_metadata_$taskId'),
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final label in assignedLabels)
          _TaskCollapsedLabelPill(
            taskId: taskId,
            label: label,
            onOpenLabel: (labelId) => _openLabel(ref, labelId),
          ),
        for (var i = 0; i < primaryBadges.length; i++)
          _TaskCollapsedBadgePill(
            badge: primaryBadges[i],
            onPressed: isSearchMode && i == 0 ? null : () => _toggleExpand(ref),
          ),
        for (final badge in visibleSecondaryBadges)
          _TaskCollapsedBadgePill(
            badge: badge,
            onPressed: () => _toggleExpand(ref),
          ),
        if (overflowSecondaryCount > 0)
          UiPill(
            key: ValueKey<String>('task_more_badges_$taskId'),
            label: localizations.badgeMoreIndicators('$overflowSecondaryCount'),
            variant: UiPillVariant.meta,
            onPressed: () => _toggleExpand(ref),
          ),
      ],
    );
  }

  /// Opens [labelId] inside Labels manager preserving `returnContext`.
  void _openLabel(WidgetRef ref, String labelId) {
    _openEntityInManager(ref, EntityRef(kind: EntityKind.label, id: labelId));
  }

  /// Toggles expansion for [entityRef].
  void _toggleExpand(WidgetRef ref) {
    ref.read(shellProvider.notifier).toggleExpandEntity(entityRef);
  }
}

/// Leading task completion/restore action watching busy state for [_TaskCompleteCircleButton].
class _TaskCompleteAction extends ConsumerWidget {
  /// Creates a [_TaskCompleteAction].
  const _TaskCompleteAction({required this.task});

  /// Domain task item.
  final TaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );
    final actionLabel = task.isCompleted
        ? localizations.actionRestore
        : localizations.actionComplete;

    return _TaskCompleteCircleButton(
      key: ValueKey<String>('task_complete_${task.id}'),
      isCompleted: task.isCompleted,
      enabled: !isBusy,
      semanticLabel: '${task.title} $actionLabel',
      onPressed: () => _completeOrRestore(context, ref),
    );
  }

  /// Triggers completion or restoration of [task] through [BoardActionsNotifier].
  void _completeOrRestore(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      _reportTaskActionFailure(
        ref,
        ref
            .read(boardActionsProvider.notifier)
            .completeOrRestoreTask(task.id, locale: locale),
      ),
    );
  }
}

/// Optical `34x34px` hit box wrapping the `21px` circular task completion/restore button (`U-CARD-001`, `U-A11Y-005`).
class _TaskCompleteCircleButton extends StatefulWidget {
  /// Creates a [_TaskCompleteCircleButton].
  const _TaskCompleteCircleButton({
    super.key,
    required this.isCompleted,
    required this.enabled,
    required this.semanticLabel,
    required this.onPressed,
  });

  /// Whether the button accepts interaction.
  final bool enabled;

  /// Renders accent-filled check circle when true.
  final bool isCompleted;

  /// Callback toggling task completion or restoration.
  final VoidCallback onPressed;

  /// Explicit accessible label (`"<title> Complete|Restore"`).
  final String semanticLabel;

  @override
  State<_TaskCompleteCircleButton> createState() =>
      _TaskCompleteCircleButtonState();
}

/// Manages pointer hover and `1px` keyboard focus ring for [_TaskCompleteCircleButton].
class _TaskCompleteCircleButtonState extends State<_TaskCompleteCircleButton> {
  bool _isHovered = false;
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: widget.isCompleted,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowHoverHighlight: _handleHoverHighlightChanged,
        onShowFocusHighlight: _handleFocusHighlightChanged,
        actions: _buildActions(),
        child: _TaskCompleteCircleTarget(
          isCompleted: widget.isCompleted,
          enabled: widget.enabled,
          isHovered: _isHovered,
          showFocusRing: _showFocusRing,
          onTap: widget.enabled ? widget.onPressed : null,
        ),
      ),
    );
  }

  /// Builds keyboard activation actions for Enter and Space presses.
  Map<Type, Action<Intent>> _buildActions() {
    return <Type, Action<Intent>>{
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          _handleActivate();
          return null;
        },
      ),
      ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
        onInvoke: (_) {
          _handleActivate();
          return null;
        },
      ),
    };
  }

  /// Invokes [widget.onPressed] when the button is enabled.
  void _handleActivate() {
    if (widget.enabled) {
      widget.onPressed();
    }
  }

  /// Updates keyboard focus-ring visibility when focus state changes.
  void _handleFocusHighlightChanged(bool focused) {
    if (_showFocusRing != focused) {
      setState(() => _showFocusRing = focused);
    }
  }

  /// Updates pointer hover highlight state when hover changes.
  void _handleHoverHighlightChanged(bool hovered) {
    if (_isHovered != hovered) {
      setState(() => _isHovered = hovered);
    }
  }
}

/// Animated `21px` circular check glyph inside [_TaskCompleteCircleTarget].
class _TaskCompleteCircleGlyph extends StatelessWidget {
  /// Creates a [_TaskCompleteCircleGlyph].
  const _TaskCompleteCircleGlyph({
    required this.isCompleted,
    required this.enabled,
    required this.isHovered,
  });

  /// Whether the button accepts interaction.
  final bool enabled;

  /// Whether the task is completed.
  final bool isCompleted;

  /// Whether a pointer currently hovers the control.
  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final borderColor = isCompleted || (isHovered && enabled)
        ? colors.accent
        : colors.line;

    return AnimatedContainer(
      duration: tokens.focus.hoverDuration,
      width: 21.0,
      height: 21.0,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted ? colors.accent : Colors.transparent,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: isCompleted
          ? Icon(
              Icons.check_rounded,
              size: tokens.spacing.iconXs,
              color: colors.onAccent,
            )
          : null,
    );
  }
}

/// Hit box, disabled opacity, and optional keyboard focus ring around [_TaskCompleteCircleGlyph].
class _TaskCompleteCircleTarget extends StatelessWidget {
  /// Creates a [_TaskCompleteCircleTarget].
  const _TaskCompleteCircleTarget({
    required this.isCompleted,
    required this.enabled,
    required this.isHovered,
    required this.showFocusRing,
    required this.onTap,
  });

  /// Whether the button accepts interaction.
  final bool enabled;

  /// Whether the task is completed.
  final bool isCompleted;

  /// Whether a pointer currently hovers the control.
  final bool isHovered;

  /// Optional tap handler when enabled.
  final VoidCallback? onTap;

  /// Whether the keyboard focus ring should wrap the circular glyph.
  final bool showFocusRing;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final glyph = _TaskCompleteCircleGlyph(
      isCompleted: isCompleted,
      enabled: enabled,
      isHovered: isHovered,
    );
    final framed = showFocusRing && enabled
        ? DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: tokens.colors.accent,
                width: tokens.focus.ringWidth,
              ),
            ),
            child: Padding(padding: const EdgeInsets.all(2.0), child: glyph),
          )
        : glyph;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: !enabled,
      onTap: enabled ? onTap : _ignoreDisabledCompleteTap,
      child: Opacity(
        opacity: enabled ? 1.0 : tokens.focus.disabledOpacity,
        child: SizedBox(
          width: tokens.spacing.chromeControlHeight,
          height: tokens.spacing.chromeControlHeight,
          child: Center(child: framed),
        ),
      ),
    );
  }
}

/// Trailing danger-styled delete icon button shown on expanded task cards (`U-CARD-001`).
class _TaskDeleteButton extends ConsumerWidget {
  /// Creates a [_TaskDeleteButton].
  const _TaskDeleteButton({required this.taskId});

  /// Identifier of the task to delete.
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final entityRef = EntityRef(kind: EntityKind.task, id: taskId);
    final isConfirmingDelete = ref.watch(
      shellProvider.select((shell) => shell.activeDeleteConfirm == entityRef),
    );
    final isBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );

    return EntityHeaderDeleteButton(
      key: ValueKey<String>('task_delete_$taskId'),
      tooltip: localizations.actionDelete,
      isConfirmingDelete: isConfirmingDelete,
      isBusy: isBusy,
      onRequestDelete: () =>
          ref.read(shellProvider.notifier).requestInlineDelete(entityRef),
    );
  }
}

/// Trailing downgrade icon button for eligible active tasks.
class _TaskDowngradeButton extends ConsumerWidget {
  /// Creates a [_TaskDowngradeButton].
  const _TaskDowngradeButton({required this.taskId});

  /// Identifier of the task to downgrade.
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );

    return UiButton(
      key: ValueKey<String>('task_downgrade_$taskId'),
      leadingIcon: Icons.chevron_right_rounded,
      variant: UiButtonVariant.icon,
      density: UiButtonDensity.compact,
      tooltip: localizations.tooltipDowngradeTask,
      onPressed: isBusy ? null : () => _downgrade(context, ref),
    );
  }

  /// Triggers downgrade of active task [taskId] through [BoardActionsNotifier].
  void _downgrade(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      _reportTaskActionFailure(
        ref,
        ref
            .read(boardActionsProvider.notifier)
            .downgradeTask(taskId, locale: locale),
      ),
    );
  }
}

/// Trailing edit-title icon button shown on expanded active task cards.
class _TaskEditTitleButton extends ConsumerWidget {
  /// Creates a [_TaskEditTitleButton].
  const _TaskEditTitleButton({required this.taskId});

  /// Identifier of the task whose title editor opens on press.
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );

    return UiButton(
      key: ValueKey<String>('task_edit_title_$taskId'),
      leadingIcon: Icons.edit_outlined,
      variant: UiButtonVariant.icon,
      density: UiButtonDensity.compact,
      tooltip: localizations.inlineEditTitleTooltip,
      onPressed: isBusy ? null : () => _openTitleEdit(ref),
    );
  }

  /// Opens the inline title editor for [taskId].
  void _openTitleEdit(WidgetRef ref) {
    ref
        .read(shellProvider.notifier)
        .openInlineEdit(InlineEditTarget.task(taskId, TaskSectionKind.title));
  }
}

/// Top metadata and inline delete confirmation bar inside [_TaskExpandedPanelBody].
class _TaskExpandedMetaBar extends ConsumerWidget {
  /// Creates a [_TaskExpandedMetaBar].
  const _TaskExpandedMetaBar({required this.task});

  /// Domain task item.
  final TaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final entityRef = EntityRef(kind: EntityKind.task, id: task.id);
    final isConfirmingDelete = ref.watch(
      shellProvider.select((shell) => shell.activeDeleteConfirm == entityRef),
    );
    final shellNotifier = ref.read(shellProvider.notifier);

    return EntityCardMetaBar(
      entityId: task.id,
      copyIdTooltip: localizations.tooltipCopyTaskId,
      onCopyId: () => _copyTaskId(context, ref),
      statusPillLabel: task.isCompleted
          ? localizations.completedReadOnlyPill
          : null,
      deleteConfirmMessage: localizations.inlineDeleteTaskConfirm,
      isConfirmingDelete: isConfirmingDelete,
      onCancelDelete: shellNotifier.cancelInlineDelete,
      onConfirmDelete: () => _deleteTask(context, ref),
    );
  }

  /// Copies `task.id` to the system clipboard, logs telemetry, and emits confirmation toast.
  void _copyTaskId(BuildContext context, WidgetRef ref) {
    final copiedMessage = AppLocalizations.of(context).taskIdCopiedSnackBar;
    unawaited(_performCopyTaskId(ref, task.id, copiedMessage));
  }

  /// Deletes [task] via [BoardActionsNotifier.deleteTask].
  void _deleteTask(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      _reportTaskActionFailure(
        ref,
        ref
            .read(boardActionsProvider.notifier)
            .deleteTask(task.id, locale: locale),
      ),
    );
  }
}

/// Watches inline edit and mutation state for the expanded Task accordion panel (`U-CARD-002`..`004`).
class _TaskExpandedPanel extends ConsumerWidget {
  /// Creates a [_TaskExpandedPanel].
  const _TaskExpandedPanel({
    required this.contextData,
    required this.assignedLabels,
  });

  /// Resolved labels assigned to the task.
  final List<TdfLabel> assignedLabels;

  /// Domain context bundle for the expanded task.
  final _TaskCardContext contextData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = contextData.task;
    final entityRef = EntityRef(kind: EntityKind.task, id: task.id);
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final editState = ref.watch(
      shellProvider.select(
        (shell) => (
          sectionKey: shell.activeInlineEdit?.entity == entityRef
              ? shell.activeInlineEdit?.sectionKey
              : null,
          labelPickerOpen: shell.labelPickerOpen,
        ),
      ),
    );
    final isBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
    );
    final activeSection = _parseTaskSectionKind(editState.sectionKey);
    final isInlineLabelPickerOpen =
        !isCompact &&
        !task.isCompleted &&
        activeSection == TaskSectionKind.labels &&
        editState.labelPickerOpen;

    return _TaskExpandedPanelBody(
      contextData: contextData,
      assignedLabels: assignedLabels,
      activeSection: activeSection,
      isInlineLabelPickerOpen: isInlineLabelPickerOpen,
      isCompact: isCompact,
      isBusy: isBusy,
    );
  }
}

/// Expanded accordion body rendering [_TaskExpandedMetaBar], canonical populated-only sections, and `+ Add` chips.
class _TaskExpandedPanelBody extends ConsumerWidget {
  /// Creates a [_TaskExpandedPanelBody].
  const _TaskExpandedPanelBody({
    required this.contextData,
    required this.assignedLabels,
    required this.activeSection,
    required this.isInlineLabelPickerOpen,
    required this.isCompact,
    required this.isBusy,
  });

  /// Currently open inline section editor on this task, if any.
  final TaskSectionKind? activeSection;

  /// Resolved labels assigned to the task.
  final List<TdfLabel> assignedLabels;

  /// Domain context bundle for the expanded task.
  final _TaskCardContext contextData;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Whether the viewport is compact (`<= 720`).
  final bool isCompact;

  /// Whether the desktop inline label picker is currently expanded.
  final bool isInlineLabelPickerOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final task = contextData.task;
    final flags = _resolvePanelFlags();

    return Column(
      key: ValueKey<String>('task_expanded_panel_${task.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TaskExpandedMetaBar(task: task),
        SizedBox(height: tokens.spacing.space2),
        _TaskExpandedSectionsList(
          contextData: contextData,
          assignedLabels: assignedLabels,
          flags: flags,
          activeSection: activeSection,
          isInlineLabelPickerOpen: isInlineLabelPickerOpen,
          isBusy: isBusy,
          onOpenLabelPicker: () => _openLabelPicker(context, ref),
        ),
        if (!task.isCompleted) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _TaskAddFieldsBar(
            task: task,
            assignedLabels: assignedLabels,
            flags: flags,
            activeSection: activeSection,
            isInlineLabelPickerOpen: isInlineLabelPickerOpen,
            isBusy: isBusy,
            onAddSection: (section) => _handleAddSection(context, ref, section),
            onSetPlacement: (nextPlacement) =>
                _setPlacement(context, ref, nextPlacement),
          ),
        ],
      ],
    );
  }

  /// Opens the label picker or the inline section editor for an unset [section].
  void _handleAddSection(
    BuildContext context,
    WidgetRef ref,
    TaskSectionKind section,
  ) {
    if (section == TaskSectionKind.labels) {
      _openLabelPicker(context, ref);
      return;
    }
    ref
        .read(shellProvider.notifier)
        .openInlineEdit(InlineEditTarget.task(contextData.task.id, section));
  }

  /// Opens the desktop inline label picker or compact mobile bottom sheet.
  void _openLabelPicker(BuildContext context, WidgetRef ref) {
    final task = contextData.task;
    if (!isCompact) {
      ref
          .read(shellProvider.notifier)
          .openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.labels),
          );
      return;
    }
    final localizations = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    unawaited(
      showCompactLabelPickerSheet(
        context,
        title: localizations.taskLabelsSectionTitle,
        taskId: task.id,
        onToggleLabel: (labelId) => unawaited(
          _reportTaskActionFailure(
            ref,
            ref
                .read(boardActionsProvider.notifier)
                .toggleLabel(task.id, labelId, locale: locale),
          ),
        ),
        onCreateLabel: (rawName) => _createAndAssignLabelForSheet(
          ref,
          task.id,
          rawName,
          locale: locale,
        ),
        onOpenLabelInfo: (labelId) => _openEntityInManager(
          ref,
          EntityRef(kind: EntityKind.label, id: labelId),
        ),
      ),
    );
  }

  /// Computes expanded-panel suspension, condition, and placement flags lazily.
  _ExpandedPanelFlags _resolvePanelFlags() {
    final task = contextData.task;
    final inheritedConditions = _collectInheritedConditions(
      task,
      contextData.labelsById,
    );
    return (
      isSuspended:
          task.isSuspendedForever ||
          task.hasActiveSuspendedAt(contextData.nowUtc),
      inheritedConditions: inheritedConditions,
      hasConditions:
          task.conditions.isNotEmpty || inheritedConditions.isNotEmpty,
      placement: task.isPriority
          ? QuickAddMode.priority
          : (contextData.isSomeday
                ? QuickAddMode.someday
                : QuickAddMode.standard),
    );
  }

  /// Updates live task placement via [BoardActionsNotifier.setPlacement].
  void _setPlacement(
    BuildContext context,
    WidgetRef ref,
    QuickAddMode placement,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      _reportTaskActionFailure(
        ref,
        ref
            .read(boardActionsProvider.notifier)
            .setPlacement(contextData.task.id, placement, locale: locale),
      ),
    );
  }
}

/// Renders populated-only expanded Task sections in canonical vertical order (`U-CARD-002`).
class _TaskExpandedSectionsList extends ConsumerWidget {
  /// Creates a [_TaskExpandedSectionsList].
  const _TaskExpandedSectionsList({
    required this.contextData,
    required this.assignedLabels,
    required this.flags,
    required this.activeSection,
    required this.isInlineLabelPickerOpen,
    required this.isBusy,
    required this.onOpenLabelPicker,
  });

  /// Shared empty placeholder draft reused while [EntityConditionsSection] is read-only.
  static final ConditionDraft _readOnlyConditionDraft = ConditionDraft();

  /// Currently active inline section editor on this task, if any.
  final TaskSectionKind? activeSection;

  /// Resolved labels assigned to the task.
  final List<TdfLabel> assignedLabels;

  /// Domain context bundle for the expanded task.
  final _TaskCardContext contextData;

  /// Lazily computed suspension, conditions, and placement flags.
  final _ExpandedPanelFlags flags;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Whether the desktop inline label picker is currently open.
  final bool isInlineLabelPickerOpen;

  /// Callback opening the inline label picker or compact bottom sheet.
  final VoidCallback onOpenLabelPicker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final sections = _collectVisibleSections(context, ref);
    final children = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) {
        children.add(SizedBox(height: tokens.spacing.space2));
      }
      children.add(sections[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// Lazily builds the [EntityConditionsSection] only when conditions exist or are being edited.
  Widget _buildConditionsSection(
    BuildContext context,
    WidgetRef ref, {
    required Locale locale,
  }) {
    final localizations = AppLocalizations.of(context);
    final task = contextData.task;
    final shellNotifier = ref.read(shellProvider.notifier);
    final boardActions = ref.read(boardActionsProvider.notifier);
    final conditionsSatisfied =
        !flags.hasConditions ||
        TaskBoardEvaluator.areTaskConditionsSatisfied(
          task,
          contextData.labelsById,
          contextData.locationsById,
          contextData.localNow,
          contextData.activeLabelId,
          contextData.activeFix?.latitude,
          contextData.activeFix?.longitude,
        );
    final conditionsSummary = TaskScheduleHelper.buildConditionSummaryChips(
      ownRules: task.conditions,
      inheritedRules: flags.inheritedConditions,
      locationsById: contextData.locationsById,
      localizations: localizations,
    );
    final isEditing =
        activeSection == TaskSectionKind.conditions && !task.isCompleted;
    final conditionDraft = isEditing
        ? TaskScheduleHelper.buildConditionDraft(task.conditions, isTask: true)
        : _readOnlyConditionDraft;

    return EntityConditionsSection(
      key: ValueKey<String>('task_section_conditions_${task.id}'),
      isTask: true,
      hasConditions: flags.hasConditions,
      conditionsSummary: conditionsSummary,
      conditionDraft: conditionDraft,
      allLocations: contextData.allLocations,
      isEditing: isEditing,
      canEdit: !task.isCompleted,
      isSuspended: flags.isSuspended,
      conditionsStatusLabel: conditionsSatisfied
          ? localizations.conditionSatisfiedStatus
          : localizations.conditionBlockedStatus,
      isBusy: isBusy,
      onOpenLocation: (locationId) => _openEntityInManager(
        ref,
        EntityRef(kind: EntityKind.location, id: locationId),
      ),
      onStartEdit: () => shellNotifier.openInlineEdit(
        InlineEditTarget.task(task.id, TaskSectionKind.conditions),
      ),
      onCancelEdit: shellNotifier.closeInlineEdit,
      onSave: (draft) =>
          boardActions.saveConditions(task.id, draft, locale: locale),
      onClear: () => boardActions.clearConditions(task.id, locale: locale),
    );
  }

  /// Collects only populated or actively edited sections in canonical `U-CARD-002` order.
  List<Widget> _collectVisibleSections(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    final task = contextData.task;
    final shellNotifier = ref.read(shellProvider.notifier);
    final boardActions = ref.read(boardActionsProvider.notifier);
    final currentLocalDateTimeHint = TaskScheduleHelper.formatLocalTimestamp(
      contextData.nowUtc,
      contextData.configuration,
    );
    final sections = <Widget>[];
    final hasNote =
        task.note != null && (task.note?.trim().isNotEmpty ?? false);

    if (hasNote || activeSection == TaskSectionKind.note) {
      sections.add(
        EntityNoteSection(
          key: ValueKey<String>('task_section_note_${task.id}'),
          note: task.note,
          isEditing: activeSection == TaskSectionKind.note && !task.isCompleted,
          canEdit: !task.isCompleted,
          isBusy: isBusy,
          onStartEdit: () => shellNotifier.openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.note),
          ),
          onCancelEdit: shellNotifier.closeInlineEdit,
          onSave: (rawNote) =>
              boardActions.saveNote(task.id, rawNote, locale: locale),
          onClear: () => boardActions.clearNote(task.id, locale: locale),
          onNoteCopied: () =>
              UiTelemetry.logTaskNoteCopied((task.note ?? '').length),
        ),
      );
    }

    if (task.links.isNotEmpty || activeSection == TaskSectionKind.links) {
      sections.add(
        EntityLinksSection(
          key: ValueKey<String>('task_section_links_${task.id}'),
          links: task.links,
          isEditing:
              activeSection == TaskSectionKind.links && !task.isCompleted,
          canEdit: !task.isCompleted,
          isLabel: false,
          isBusy: isBusy,
          onStartEdit: () => shellNotifier.openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.links),
          ),
          onCancelEdit: shellNotifier.closeInlineEdit,
          onSave: (links) =>
              boardActions.saveLinks(task.id, links, locale: locale),
        ),
      );
    }

    if (task.subtasks.isNotEmpty || activeSection == TaskSectionKind.subtasks) {
      sections.add(
        TaskSubtasksSection(
          key: ValueKey<String>('task_section_subtasks_${task.id}'),
          task: task,
          isEditing:
              activeSection == TaskSectionKind.subtasks && !task.isCompleted,
          onStartEdit: () => shellNotifier.openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.subtasks),
          ),
          onCancelEdit: shellNotifier.closeInlineEdit,
        ),
      );
    }

    // History is ALWAYS visible and live interactive even on Completed tasks (U-CARD-004).
    sections.add(
      TaskHistorySection(
        key: ValueKey<String>('task_section_history_${task.id}'),
        task: task,
        configuration: contextData.configuration,
        currentLocalDateTimeHint: currentLocalDateTimeHint,
      ),
    );

    if (assignedLabels.isNotEmpty || isInlineLabelPickerOpen) {
      sections.add(
        _TaskLabelsSection(
          key: ValueKey<String>('task_section_labels_${task.id}'),
          task: task,
          assignedLabels: assignedLabels,
          allLabels: contextData.allLabels,
          openLabelCounts: contextData.openLabelCounts,
          isInlinePickerOpen: isInlineLabelPickerOpen,
          isBusy: isBusy,
          onToggleLabel: (labelId) => unawaited(
            _reportTaskActionFailure(
              ref,
              boardActions.toggleLabel(task.id, labelId, locale: locale),
            ),
          ),
          onCreateAndAssign: (rawName) => unawaited(
            _reportTaskActionFailure(
              ref,
              boardActions.createAndAssignLabel(
                task.id,
                rawName,
                locale: locale,
              ),
            ),
          ),
          onOpenLabelInfo: (labelId) => _openEntityInManager(
            ref,
            EntityRef(kind: EntityKind.label, id: labelId),
          ),
          onOpenPicker: onOpenLabelPicker,
          onClosePicker: shellNotifier.closeInlineEdit,
        ),
      );
    }

    if (task.dueAt != null || activeSection == TaskSectionKind.due) {
      sections.add(
        TaskDueSection(
          key: ValueKey<String>('task_section_due_${task.id}'),
          task: task,
          isSomeday: contextData.isSomeday,
          isEditing: activeSection == TaskSectionKind.due && !task.isCompleted,
          configuration: contextData.configuration,
          nowUtc: contextData.nowUtc,
          currentLocalDateTimeHint: currentLocalDateTimeHint,
          onStartEdit: () => shellNotifier.openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.due),
          ),
          onCancelEdit: shellNotifier.closeInlineEdit,
        ),
      );
    }

    if (!task.isCompleted && (task.isPriority || contextData.isSomeday)) {
      sections.add(
        TaskPlacementCard(
          key: ValueKey<String>('task_section_placement_${task.id}'),
          cardKey: ValueKey<String>('task_placement_section_${task.id}'),
          controlKey: ValueKey<String>('task_placement_control_${task.id}'),
          placement: flags.placement,
          isBusy: isBusy,
          onChanged: (nextPlacement) => unawaited(
            _reportTaskActionFailure(
              ref,
              boardActions.setPlacement(task.id, nextPlacement, locale: locale),
            ),
          ),
        ),
      );
    }

    if (task.repeatRule != null || activeSection == TaskSectionKind.repeat) {
      sections.add(
        TaskRepeatSection(
          key: ValueKey<String>('task_section_repeat_${task.id}'),
          task: task,
          isEditing:
              activeSection == TaskSectionKind.repeat && !task.isCompleted,
          onStartEdit: () => shellNotifier.openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.repeat),
          ),
          onCancelEdit: shellNotifier.closeInlineEdit,
        ),
      );
    }

    if (flags.isSuspended || activeSection == TaskSectionKind.suspended) {
      sections.add(
        TaskSuspendedSection(
          key: ValueKey<String>('task_section_suspended_${task.id}'),
          task: task,
          isEditing:
              activeSection == TaskSectionKind.suspended && !task.isCompleted,
          configuration: contextData.configuration,
          nowUtc: contextData.nowUtc,
          currentLocalDateTimeHint: currentLocalDateTimeHint,
          onStartEdit: () => shellNotifier.openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.suspended),
          ),
          onCancelEdit: shellNotifier.closeInlineEdit,
        ),
      );
    }

    if (task.dependencies.isNotEmpty ||
        activeSection == TaskSectionKind.prerequisites) {
      sections.add(
        TaskPrerequisitesSection(
          key: ValueKey<String>('task_section_prerequisites_${task.id}'),
          task: task,
          tasksById: contextData.tasksById,
          isEditing:
              activeSection == TaskSectionKind.prerequisites &&
              !task.isCompleted,
          onStartEdit: () => shellNotifier.openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.prerequisites),
          ),
          onCancelEdit: shellNotifier.closeInlineEdit,
        ),
      );
    }

    if (flags.hasConditions || activeSection == TaskSectionKind.conditions) {
      sections.add(_buildConditionsSection(context, ref, locale: locale));
    }

    return sections;
  }
}

/// Inline desktop label picker inset card rendered when [_TaskLabelsSection] is actively editing.
class _TaskLabelsPickerCard extends StatelessWidget {
  /// Creates a [_TaskLabelsPickerCard].
  const _TaskLabelsPickerCard({
    required this.taskId,
    required this.assignedLabels,
    required this.allLabels,
    required this.openLabelCounts,
    required this.onToggleLabel,
    required this.onCreateAndAssign,
    required this.onOpenLabelInfo,
    required this.onClosePicker,
  });

  /// Workspace labels for the searchable picker.
  final List<TdfLabel> allLabels;

  /// Resolved labels currently assigned to the task.
  final List<TdfLabel> assignedLabels;

  /// Callback closing the desktop inline label picker.
  final VoidCallback onClosePicker;

  /// Callback creating and immediately assigning a new label.
  final ValueChanged<String> onCreateAndAssign;

  /// Callback navigating to a label in Labels manager preserving `returnContext`.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback toggling label assignment on the task.
  final ValueChanged<String> onToggleLabel;

  /// Precomputed map of open task counts keyed by label identifier.
  final Map<String, int> openLabelCounts;

  /// Canonical task identifier for deterministic widget keys.
  final String taskId;

  /// Identifiers of labels currently assigned to the task.
  Set<String> get _selectedIds => <String>{
    for (final label in assignedLabels) label.id,
  };

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: ValueKey<String>('task_labels_picker_$taskId'),
      isEditing: true,
      headerIcon: Icons.label_outline_rounded,
      headerTitle: localizations.taskLabelsSectionTitle,
      headerBadge: UiPill(
        label: '${assignedLabels.length}',
        variant: UiPillVariant.count,
      ),
      headerTrailing: UiButton(
        label: localizations.actionDone,
        density: UiButtonDensity.compact,
        onPressed: onClosePicker,
      ),
      child: EntitySearchableLabelPicker(
        allLabels: allLabels,
        selectedIds: _selectedIds,
        openCountsByLabelId: openLabelCounts,
        autoFocusSearch: true,
        useSharedQuery: true,
        onToggleLabel: onToggleLabel,
        onCreateAndAssign: onCreateAndAssign,
        onOpenLabelInfo: onOpenLabelInfo,
        onRequestClose: onClosePicker,
      ),
    );
  }
}

/// Read-mode inset card showing assigned task label chips and `+ Add` trigger.
class _TaskLabelsReadCard extends StatelessWidget {
  /// Creates a [_TaskLabelsReadCard].
  const _TaskLabelsReadCard({
    required this.task,
    required this.assignedLabels,
    required this.isBusy,
    required this.onToggleLabel,
    required this.onOpenLabelInfo,
    required this.onOpenPicker,
  });

  /// Resolved labels currently assigned to [task].
  final List<TdfLabel> assignedLabels;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback navigating to a label in Labels manager preserving `returnContext`.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback opening the label picker (desktop inline or compact sheet).
  final VoidCallback onOpenPicker;

  /// Callback toggling label assignment on the task.
  final ValueChanged<String> onToggleLabel;

  /// Domain task item.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: ValueKey<String>('task_labels_read_${task.id}'),
      headerIcon: Icons.label_outline_rounded,
      headerTitle: localizations.taskLabelsSectionTitle,
      headerBadge: UiPill(
        label: '${assignedLabels.length}',
        variant: UiPillVariant.count,
      ),
      child: _TaskAssignedLabelsWrap(
        task: task,
        assignedLabels: assignedLabels,
        isBusy: isBusy,
        onToggleLabel: onToggleLabel,
        onOpenLabelInfo: onOpenLabelInfo,
        onOpenPicker: onOpenPicker,
      ),
    );
  }
}

/// Assigned labels and inline desktop / compact bottom-sheet picker section on an expanded Task card.
class _TaskLabelsSection extends StatelessWidget {
  /// Creates a [_TaskLabelsSection].
  const _TaskLabelsSection({
    super.key,
    required this.task,
    required this.assignedLabels,
    required this.allLabels,
    required this.openLabelCounts,
    required this.isInlinePickerOpen,
    required this.isBusy,
    required this.onToggleLabel,
    required this.onCreateAndAssign,
    required this.onOpenLabelInfo,
    required this.onOpenPicker,
    required this.onClosePicker,
  });

  /// Workspace labels for the searchable picker.
  final List<TdfLabel> allLabels;

  /// Resolved labels currently assigned to [task].
  final List<TdfLabel> assignedLabels;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Whether the desktop inline label picker is currently expanded.
  final bool isInlinePickerOpen;

  /// Callback closing the desktop inline label picker.
  final VoidCallback onClosePicker;

  /// Callback creating and immediately assigning a new label.
  final ValueChanged<String> onCreateAndAssign;

  /// Callback navigating to a label in Labels manager preserving `returnContext`.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback opening the label picker (desktop inline or compact sheet).
  final VoidCallback onOpenPicker;

  /// Callback toggling label assignment on the task.
  final ValueChanged<String> onToggleLabel;

  /// Precomputed map of open task counts keyed by label identifier.
  final Map<String, int> openLabelCounts;

  /// Domain task item.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    if (isInlinePickerOpen && !task.isCompleted) {
      return _TaskLabelsPickerCard(
        taskId: task.id,
        assignedLabels: assignedLabels,
        allLabels: allLabels,
        openLabelCounts: openLabelCounts,
        onToggleLabel: onToggleLabel,
        onCreateAndAssign: onCreateAndAssign,
        onOpenLabelInfo: onOpenLabelInfo,
        onClosePicker: onClosePicker,
      );
    }

    return _TaskLabelsReadCard(
      task: task,
      assignedLabels: assignedLabels,
      isBusy: isBusy,
      onToggleLabel: onToggleLabel,
      onOpenLabelInfo: onOpenLabelInfo,
      onOpenPicker: onOpenPicker,
    );
  }
}

/// Lazily computed expanded-panel suspension, condition, and placement flags.
typedef _ExpandedPanelFlags = ({
  bool isSuspended,
  List<TaskCondition> inheritedConditions,
  bool hasConditions,
  QuickAddMode placement,
});

/// Collects activation condition rules inherited from labels assigned to [task].
List<TaskCondition> _collectInheritedConditions(
  TaskItem task,
  Map<String, TdfLabel> labelsById,
) {
  return <TaskCondition>[
    for (final labelId in task.labelIds)
      if (labelsById[labelId] case final label?) ...label.conditions,
  ];
}

/// Collects visible unset editable sections for the bottom `+ Add` chips bar on open tasks.
List<TaskSectionKind> _collectUnsetTaskSections({
  required TaskItem task,
  required bool hasAssignedLabels,
  required bool isSuspended,
  required bool hasConditions,
}) {
  final taskNote = task.note;
  return <TaskSectionKind>[
    if (taskNote == null || taskNote.trim().isEmpty) TaskSectionKind.note,
    if (task.links.isEmpty) TaskSectionKind.links,
    if (task.subtasks.isEmpty) TaskSectionKind.subtasks,
    if (!hasAssignedLabels) TaskSectionKind.labels,
    if (task.dueAt == null) TaskSectionKind.due,
    if (task.repeatRule == null) TaskSectionKind.repeat,
    if (!isSuspended) TaskSectionKind.suspended,
    if (task.dependencies.isEmpty) TaskSectionKind.prerequisites,
    if (!hasConditions) TaskSectionKind.conditions,
  ];
}

/// Returns `true` when [section] renders after Due in the canonical `+ Add` chips order.
bool _comesAfterDue(TaskSectionKind section) {
  return section == TaskSectionKind.repeat ||
      section == TaskSectionKind.suspended ||
      section == TaskSectionKind.prerequisites ||
      section == TaskSectionKind.conditions;
}

/// Creates and assigns a label from the compact label sheet, emitting a danger toast on failure.
Future<ActionResult> _createAndAssignLabelForSheet(
  WidgetRef ref,
  String taskId,
  String rawName, {
  required Locale locale,
}) async {
  final result = await ref
      .read(boardActionsProvider.notifier)
      .createAndAssignLabel(taskId, rawName, locale: locale);
  if (!ref.context.mounted) {
    return result;
  }
  switch (result) {
    case ActionSucceeded():
      break;
    case ActionValidationFailed(:final message):
    case ActionPersistFailed(:final message):
      if (message.isNotEmpty) {
        ref
            .read(floatingNoticeProvider.notifier)
            .showNotice(message, tone: FloatingNoticeTone.danger);
      }
  }
  return result;
}

/// Absorbs pointer taps on disabled task completion buttons so they do not bubble to collapsed card expansion.
void _ignoreDisabledCompleteTap() {}

/// Navigates to [entity] in its manager view while preserving Tasks/Search `returnContext`.
void _openEntityInManager(WidgetRef ref, EntityRef entity) {
  ref
      .read(shellProvider.notifier)
      .openEntityInManager(entity, preserveReturnContext: true);
}

/// Parses an optional [TaskSectionKind] name string safely.
TaskSectionKind? _parseTaskSectionKind(String? sectionKey) {
  if (sectionKey == null) {
    return null;
  }
  for (final kind in TaskSectionKind.values) {
    if (kind.name == sectionKey) {
      return kind;
    }
  }
  return null;
}

/// Copies [taskId] to the clipboard, emits redacted telemetry, and displays [copiedMessage].
Future<void> _performCopyTaskId(
  WidgetRef ref,
  String taskId,
  String copiedMessage,
) async {
  await Clipboard.setData(ClipboardData(text: taskId));
  UiTelemetry.logTaskIdCopied(taskId);
  if (!ref.context.mounted) {
    return;
  }
  ref.read(floatingNoticeProvider.notifier).showNotice(copiedMessage);
}

/// Awaits [actionFuture] and presents a floating danger toast if validation or persistence failed.
Future<void> _reportTaskActionFailure(
  WidgetRef ref,
  Future<ActionResult> actionFuture,
) async {
  final result = await actionFuture;
  if (!ref.context.mounted) {
    return;
  }
  switch (result) {
    case ActionSucceeded():
      return;
    case ActionValidationFailed(:final message):
    case ActionPersistFailed(:final message):
      if (message.isNotEmpty) {
        ref
            .read(floatingNoticeProvider.notifier)
            .showNotice(message, tone: FloatingNoticeTone.danger);
      }
  }
}

/// Resolves assigned [TdfLabel] entries on [task] in assignment order.
List<TdfLabel> _resolveAssignedLabels(
  TaskItem task,
  Map<String, TdfLabel> labelsById,
) {
  return <TdfLabel>[for (final labelId in task.labelIds) ?labelsById[labelId]];
}

/// Resolves an optional `#RRGGBB` label color string, falling back to `tokens.colors.accent`.
Color _resolveLabelColor(String? colorHex, UiThemeTokens tokens) {
  return switch (TaskScheduleHelper.parseLabelColorValue(colorHex)) {
    final value? => Color(value),
    null => tokens.colors.accent,
  };
}

/// Returns the outline icon for an unset [TaskSectionKind] `+ Add` chip.
IconData _taskAddChipIcon(TaskSectionKind section) {
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

/// Returns the localized `+ Add` chip label for unset [section].
String _taskAddChipLabel(
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
