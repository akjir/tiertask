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
import '../../presentation/app_shell_controller.dart';
import '../../presentation/floating_notice_controller.dart';
import '../../presentation/shell_models.dart';
import '../../presentation/task_controller.dart';
import '../../presentation/tasks_view_model.dart';
import '../../presentation/ui_telemetry.dart';
import '../../presentation/view_model_primitives.dart';
import '../dialogs/compact_label_picker_sheet.dart';
import '../ui_icon_mapper.dart';
import '../widgets/entity_card_chrome.dart';
import '../widgets/entity_conditions_section.dart';
import '../widgets/entity_label_picker.dart';
import '../widgets/entity_links_section.dart';
import '../widgets/entity_note_section.dart';
import 'task_detail_editors.dart';
import 'task_schedule_editors.dart';

/// Expandable card rendering a single projected task and its inline editors (`U-CARD-001`..`005`).
class TaskCard extends ConsumerWidget {
  /// Creates a [TaskCard].
  const TaskCard({
    super.key,
    required this.task,
    required this.allLabels,
    required this.allLocations,
    required this.hasBothScopedAndGlobalLabels,
    required this.currentLocalDateTimeHint,
  });

  /// All workspace label options supplied to inline and sheet label pickers.
  final List<LabelPickerOptionViewModel> allLabels;

  /// All workspace locations supplied to activation condition pickers.
  final List<LocationOptionViewModel> allLocations;

  /// Current workspace local wall-clock timestamp (`YYYY-MM-DD HH:MM`) seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether workspace has both scoped and global labels (`U-COMP-005`).
  final bool hasBothScopedAndGlobalLabels;

  /// Projected immutable task view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entityRef = EntityRef(kind: EntityKind.task, id: task.id);
    final isExpanded = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.expandedEntity == entityRef,
      ),
    );
    final isTitleEditActive = ref.watch(
      appShellControllerProvider.select(
        (shell) =>
            shell.activeInlineEdit?.entity == entityRef &&
            shell.activeInlineEdit?.sectionKey == TaskSectionKind.title.name,
      ),
    );
    final isEditingTitle = isExpanded && !task.isCompleted && isTitleEditActive;

    return _TaskCardFrame(
      task: task,
      allLabels: allLabels,
      allLocations: allLocations,
      hasBothScopedAndGlobalLabels: hasBothScopedAndGlobalLabels,
      currentLocalDateTimeHint: currentLocalDateTimeHint,
      entityRef: entityRef,
      isExpanded: isExpanded,
      isEditingTitle: isEditingTitle,
    );
  }
}

/// Bottom `+ Add` dashed chips and solid direct `Priority` / `Someday` toggles bar (`U-CARD-002`).
class _TaskAddFieldsBar extends StatelessWidget {
  /// Creates a [_TaskAddFieldsBar].
  const _TaskAddFieldsBar({
    required this.task,
    required this.activeSection,
    required this.isInlineLabelPickerOpen,
    required this.isBusy,
    required this.onAddSection,
    required this.onSetPlacement,
  });

  /// Currently open inline section editor on this task, if any.
  final TaskSectionKind? activeSection;

  /// Whether a task mutation is currently in flight.
  final bool isBusy;

  /// Whether the desktop inline label picker is currently expanded.
  final bool isInlineLabelPickerOpen;

  /// Callback opening an unset section editor or label picker.
  final ValueChanged<TaskSectionKind> onAddSection;

  /// Callback immediately switching task placement (`Priority` or `Someday`).
  final ValueChanged<TaskPlacementOption> onSetPlacement;

  /// Projected task card view model.
  final TaskCardViewModel task;

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

  /// Builds unset dashed `+ Add` chips interleaved with direct `Priority`/`Someday` toggles in canonical order.
  List<Widget> _buildOrderedChips(AppLocalizations localizations) {
    final unset = task.unsetSections;
    final chips = <Widget>[];
    final showDirectPlacement = task.placement == TaskPlacementOption.queue;
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
        onPressed: isBusy
            ? null
            : () => onSetPlacement(TaskPlacementOption.priority),
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
        onPressed: isBusy
            ? null
            : () => onSetPlacement(TaskPlacementOption.someday),
      ),
    );
  }
}

/// Assigned label chips and `+ Add` trigger rendered inside [_TaskLabelsReadCard].
class _TaskAssignedLabelsWrap extends StatelessWidget {
  /// Creates a [_TaskAssignedLabelsWrap].
  const _TaskAssignedLabelsWrap({
    required this.task,
    required this.isBusy,
    required this.onToggleLabel,
    required this.onOpenLabelInfo,
    required this.onOpenPicker,
  });

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback navigating to a label in Labels manager preserving `returnContext`.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback opening the label picker (desktop inline or compact sheet).
  final VoidCallback onOpenPicker;

  /// Callback toggling label assignment on the task.
  final ValueChanged<String> onToggleLabel;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final chip in task.assignedLabels)
          UiPill(
            key: ValueKey<String>('task_expanded_label_${task.id}_${chip.id}'),
            label: chip.name,
            variant: UiPillVariant.splitChip,
            colorDot: _resolveLabelColor(chip.colorValue, tokens),
            tooltip: localizations.openLabelInManagerTooltip,
            removeTooltip: localizations.labelPickerRemoveTooltip(chip.name),
            onPressed: () => onOpenLabelInfo(chip.id),
            onRemove: task.isCompleted || isBusy
                ? null
                : () => onToggleLabel(chip.id),
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

/// Expandable card chrome wiring header controls, collapsed metadata, and expanded panel for [TaskCard].
class _TaskCardFrame extends ConsumerWidget {
  /// Creates a [_TaskCardFrame].
  const _TaskCardFrame({
    required this.task,
    required this.allLabels,
    required this.allLocations,
    required this.hasBothScopedAndGlobalLabels,
    required this.currentLocalDateTimeHint,
    required this.entityRef,
    required this.isExpanded,
    required this.isEditingTitle,
  });

  /// All workspace label options supplied to inline and sheet label pickers.
  final List<LabelPickerOptionViewModel> allLabels;

  /// All workspace locations supplied to activation condition pickers.
  final List<LocationOptionViewModel> allLocations;

  /// Current workspace local wall-clock timestamp (`YYYY-MM-DD HH:MM`) seeding pickers.
  final String currentLocalDateTimeHint;

  /// Entity reference identifying this task inside shell state.
  final EntityRef entityRef;

  /// Whether workspace has both scoped and global labels (`U-COMP-005`).
  final bool hasBothScopedAndGlobalLabels;

  /// Whether the inline title editor is currently active.
  final bool isEditingTitle;

  /// Whether this task card is currently expanded.
  final bool isExpanded;

  /// Projected immutable task view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              if (task.canDowngrade) _TaskDowngradeButton(taskId: task.id),
            ],
      collapsedMetadata: _hasCollapsedMetadata(task)
          ? _TaskCollapsedMetadataStrip(task: task, entityRef: entityRef)
          : null,
      expandedChild: isExpanded
          ? _TaskExpandedPanel(
              task: task,
              allLabels: allLabels,
              allLocations: allLocations,
              hasBothScopedAndGlobalLabels: hasBothScopedAndGlobalLabels,
              currentLocalDateTimeHint: currentLocalDateTimeHint,
            )
          : null,
    );
  }

  /// Closes the currently active inline title editor in shell state.
  void _closeInlineEdit(WidgetRef ref) {
    ref.read(appShellControllerProvider.notifier).closeInlineEdit();
  }

  /// Toggles card expansion for [entityRef].
  void _toggleExpand(WidgetRef ref) {
    ref.read(appShellControllerProvider.notifier).toggleExpandEntity(entityRef);
  }
}

/// Single collapsed metadata badge pill rendered inside [_TaskCollapsedMetadataStrip].
class _TaskCollapsedBadgePill extends StatelessWidget {
  /// Creates a [_TaskCollapsedBadgePill].
  const _TaskCollapsedBadgePill({required this.badge, required this.onPressed});

  /// Projected card badge view model.
  final CardBadgeViewModel badge;

  /// Optional tap callback toggling card expansion.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return UiPill(
      label: badge.label,
      icon: UiIconMapper.badgeIcon(badge.iconKey),
      variant: UiPillVariant.badge,
      tone: UiIconMapper.pillTone(badge.tone),
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

  /// Assigned label chip projection.
  final EntityLabelChipViewModel label;

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
      colorDot: _resolveLabelColor(label.colorValue, tokens),
      tooltip: localizations.openLabelInManagerTooltip,
      onPressed: () => onOpenLabel(label.id),
    );
  }
}

/// Collapsed task metadata strip enforcing `U-CARD-005` exact order and `3 + N` secondary overflow cap.
class _TaskCollapsedMetadataStrip extends ConsumerWidget {
  /// Creates a [_TaskCollapsedMetadataStrip].
  const _TaskCollapsedMetadataStrip({
    required this.task,
    required this.entityRef,
  });

  /// Entity reference identifying this task for expand toggling.
  final EntityRef entityRef;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);

    return Wrap(
      key: ValueKey<String>('task_collapsed_metadata_${task.id}'),
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final label in task.assignedLabels)
          _TaskCollapsedLabelPill(
            taskId: task.id,
            label: label,
            onOpenLabel: (labelId) => _openLabel(ref, labelId),
          ),
        for (final badge in task.primaryBadges)
          _TaskCollapsedBadgePill(
            badge: badge,
            onPressed: badge.iconKey == CardBadgeIconKey.due
                ? () => _toggleExpand(ref)
                : null,
          ),
        for (final badge in task.visibleSecondaryBadges)
          _TaskCollapsedBadgePill(
            badge: badge,
            onPressed: () => _toggleExpand(ref),
          ),
        if (task.overflowSecondaryCount > 0)
          UiPill(
            key: ValueKey<String>('task_more_badges_${task.id}'),
            label: localizations.badgeMoreIndicators(
              '${task.overflowSecondaryCount}',
            ),
            variant: UiPillVariant.badge,
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
    ref.read(appShellControllerProvider.notifier).toggleExpandEntity(entityRef);
  }
}

/// Leading task completion/restore action watching busy state for [_TaskCompleteCircleButton].
class _TaskCompleteAction extends ConsumerWidget {
  /// Creates a [_TaskCompleteAction].
  const _TaskCompleteAction({required this.task});

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      taskControllerProvider.select((state) => state.isBusy),
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

  /// Triggers completion or restoration of [task] through [TaskController].
  void _completeOrRestore(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      _reportTaskActionFailure(
        ref,
        ref
            .read(taskControllerProvider.notifier)
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
      onTap: onTap,
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
      taskControllerProvider.select((state) => state.isBusy),
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

  /// Triggers downgrade of active task [taskId] through [TaskController].
  void _downgrade(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      _reportTaskActionFailure(
        ref,
        ref
            .read(taskControllerProvider.notifier)
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
      taskControllerProvider.select((state) => state.isBusy),
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
        .read(appShellControllerProvider.notifier)
        .openInlineEdit(InlineEditTarget.task(taskId, TaskSectionKind.title));
  }
}

/// Top metadata and inline delete confirmation bar inside [_TaskExpandedPanelBody].
class _TaskExpandedMetaBar extends ConsumerWidget {
  /// Creates a [_TaskExpandedMetaBar].
  const _TaskExpandedMetaBar({required this.task});

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final entityRef = EntityRef(kind: EntityKind.task, id: task.id);
    final isConfirmingDelete = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.activeDeleteConfirm == entityRef,
      ),
    );
    final shellNotifier = ref.read(appShellControllerProvider.notifier);

    return EntityCardMetaBar(
      entityId: task.id,
      copyIdTooltip: localizations.tooltipCopyTaskId,
      onCopyId: () => _copyTaskId(context, ref),
      statusPillLabel: task.isCompleted
          ? localizations.completedReadOnlyPill
          : null,
      deleteTooltip: localizations.actionDelete,
      deleteConfirmMessage: localizations.inlineDeleteTaskConfirm,
      isConfirmingDelete: isConfirmingDelete,
      onRequestDelete: () => shellNotifier.requestInlineDelete(entityRef),
      onCancelDelete: shellNotifier.cancelInlineDelete,
      onConfirmDelete: () => _deleteTask(context, ref),
    );
  }

  /// Copies `task.id` to the system clipboard, logs telemetry, and emits confirmation toast.
  void _copyTaskId(BuildContext context, WidgetRef ref) {
    final copiedMessage = AppLocalizations.of(context).taskIdCopiedSnackBar;
    unawaited(_performCopyTaskId(ref, task.id, copiedMessage));
  }

  /// Deletes [task] via [TaskController.deleteTask].
  void _deleteTask(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    unawaited(
      _reportTaskActionFailure(
        ref,
        ref
            .read(taskControllerProvider.notifier)
            .deleteTask(task.id, locale: locale),
      ),
    );
  }
}

/// Watches inline edit and mutation state for the expanded Task accordion panel (`U-CARD-002`..`004`).
class _TaskExpandedPanel extends ConsumerWidget {
  /// Creates a [_TaskExpandedPanel].
  const _TaskExpandedPanel({
    required this.task,
    required this.allLabels,
    required this.allLocations,
    required this.hasBothScopedAndGlobalLabels,
    required this.currentLocalDateTimeHint,
  });

  /// All workspace labels.
  final List<LabelPickerOptionViewModel> allLabels;

  /// All workspace locations.
  final List<LocationOptionViewModel> allLocations;

  /// Current local wall-clock timestamp seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether both scoped and global labels exist.
  final bool hasBothScopedAndGlobalLabels;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entityRef = EntityRef(kind: EntityKind.task, id: task.id);
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final editState = ref.watch(
      appShellControllerProvider.select(
        (shell) => (
          sectionKey: shell.activeInlineEdit?.entity == entityRef
              ? shell.activeInlineEdit?.sectionKey
              : null,
          labelPickerOpen: shell.labelPickerOpen,
        ),
      ),
    );
    final isBusy = ref.watch(
      taskControllerProvider.select((state) => state.isBusy),
    );
    final activeSection = _parseTaskSectionKind(editState.sectionKey);
    final isInlineLabelPickerOpen =
        !isCompact &&
        !task.isCompleted &&
        activeSection == TaskSectionKind.labels &&
        editState.labelPickerOpen;

    return _TaskExpandedPanelBody(
      task: task,
      allLabels: allLabels,
      allLocations: allLocations,
      hasBothScopedAndGlobalLabels: hasBothScopedAndGlobalLabels,
      currentLocalDateTimeHint: currentLocalDateTimeHint,
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
    required this.task,
    required this.allLabels,
    required this.allLocations,
    required this.hasBothScopedAndGlobalLabels,
    required this.currentLocalDateTimeHint,
    required this.activeSection,
    required this.isInlineLabelPickerOpen,
    required this.isCompact,
    required this.isBusy,
  });

  /// Currently open inline section editor on this task, if any.
  final TaskSectionKind? activeSection;

  /// All workspace labels.
  final List<LabelPickerOptionViewModel> allLabels;

  /// All workspace locations.
  final List<LocationOptionViewModel> allLocations;

  /// Current local wall-clock timestamp seeding pickers.
  final String currentLocalDateTimeHint;

  /// Whether both scoped and global labels exist.
  final bool hasBothScopedAndGlobalLabels;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Whether the viewport is compact (`<= 720`).
  final bool isCompact;

  /// Whether the desktop inline label picker is currently expanded.
  final bool isInlineLabelPickerOpen;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);

    return Column(
      key: ValueKey<String>('task_expanded_panel_${task.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TaskExpandedMetaBar(task: task),
        SizedBox(height: tokens.spacing.space2),
        _TaskExpandedSectionsList(
          task: task,
          allLabels: allLabels,
          allLocations: allLocations,
          hasBothScopedAndGlobalLabels: hasBothScopedAndGlobalLabels,
          currentLocalDateTimeHint: currentLocalDateTimeHint,
          activeSection: activeSection,
          isInlineLabelPickerOpen: isInlineLabelPickerOpen,
          isBusy: isBusy,
          onOpenLabelPicker: () => _openLabelPicker(context, ref),
        ),
        if (!task.isCompleted) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _TaskAddFieldsBar(
            task: task,
            activeSection: activeSection,
            isInlineLabelPickerOpen: isInlineLabelPickerOpen,
            isBusy: isBusy,
            onAddSection: (section) => _handleAddSection(context, ref, section),
            onSetPlacement: (placement) =>
                _setPlacement(context, ref, placement),
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
        .read(appShellControllerProvider.notifier)
        .openInlineEdit(InlineEditTarget.task(task.id, section));
  }

  /// Opens the desktop inline label picker or compact mobile bottom sheet.
  void _openLabelPicker(BuildContext context, WidgetRef ref) {
    if (!isCompact) {
      ref
          .read(appShellControllerProvider.notifier)
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
        allLabels: allLabels,
        hasBothScopedAndGlobal: hasBothScopedAndGlobalLabels,
        selectedIds: <String>{for (final chip in task.assignedLabels) chip.id},
        onToggleLabel: (labelId) => unawaited(
          _reportTaskActionFailure(
            ref,
            ref
                .read(taskControllerProvider.notifier)
                .toggleLabel(task.id, labelId, locale: locale),
          ),
        ),
        onCreateAndAssign: (rawName) => unawaited(
          _reportTaskActionFailure(
            ref,
            ref
                .read(taskControllerProvider.notifier)
                .createAndAssignLabel(task.id, rawName, locale: locale),
          ),
        ),
        onOpenLabelInfo: (labelId) => _openEntityInManager(
          ref,
          EntityRef(kind: EntityKind.label, id: labelId),
        ),
      ),
    );
  }

  /// Updates live task placement via [TaskController.setPlacement].
  void _setPlacement(
    BuildContext context,
    WidgetRef ref,
    TaskPlacementOption placement,
  ) {
    final locale = Localizations.localeOf(context);
    unawaited(
      _reportTaskActionFailure(
        ref,
        ref
            .read(taskControllerProvider.notifier)
            .setPlacement(task.id, placement, locale: locale),
      ),
    );
  }
}

/// Renders populated-only expanded Task sections in canonical vertical order (`U-CARD-002`).
class _TaskExpandedSectionsList extends ConsumerWidget {
  /// Creates a [_TaskExpandedSectionsList].
  const _TaskExpandedSectionsList({
    required this.task,
    required this.allLabels,
    required this.allLocations,
    required this.hasBothScopedAndGlobalLabels,
    required this.currentLocalDateTimeHint,
    required this.activeSection,
    required this.isInlineLabelPickerOpen,
    required this.isBusy,
    required this.onOpenLabelPicker,
  });

  /// Currently active inline section editor on this task, if any.
  final TaskSectionKind? activeSection;

  /// Workspace labels for the searchable label picker.
  final List<LabelPickerOptionViewModel> allLabels;

  /// Workspace locations for the activation conditions section.
  final List<LocationOptionViewModel> allLocations;

  /// Current local wall-clock timestamp hint.
  final String currentLocalDateTimeHint;

  /// Whether both scoped and global labels exist.
  final bool hasBothScopedAndGlobalLabels;

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Whether the desktop inline label picker is currently open.
  final bool isInlineLabelPickerOpen;

  /// Callback opening the inline label picker or compact bottom sheet.
  final VoidCallback onOpenLabelPicker;

  /// Projected task card view model.
  final TaskCardViewModel task;

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

  /// Collects only populated or actively edited sections in canonical `U-CARD-002` order.
  List<Widget> _collectVisibleSections(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    final shellNotifier = ref.read(appShellControllerProvider.notifier);
    final taskNotifier = ref.read(taskControllerProvider.notifier);
    final sections = <Widget>[];
    final hasNote =
        task.note != null && (task.note?.trim().isNotEmpty ?? false);

    if (hasNote || activeSection == TaskSectionKind.note) {
      sections.add(
        EntityNoteSection(
          note: task.note,
          isEditing: activeSection == TaskSectionKind.note && !task.isCompleted,
          canEdit: !task.isCompleted,
          isBusy: isBusy,
          onStartEdit: () => shellNotifier.openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.note),
          ),
          onCancelEdit: shellNotifier.closeInlineEdit,
          onSave: (rawNote) =>
              taskNotifier.saveNote(task.id, rawNote, locale: locale),
          onClear: () => taskNotifier.clearNote(task.id, locale: locale),
          onNoteCopied: () =>
              UiTelemetry.logTaskNoteCopied((task.note ?? '').length),
        ),
      );
    }

    if (task.links.isNotEmpty || activeSection == TaskSectionKind.links) {
      sections.add(
        EntityLinksSection(
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
          onSave: (links) => taskNotifier.saveLinks(task.id, <EntityLinkInput>[
            for (final link in links)
              EntityLinkInput(title: link.title, uri: link.uri),
          ], locale: locale),
        ),
      );
    }

    if (task.subtasks.isNotEmpty || activeSection == TaskSectionKind.subtasks) {
      sections.add(
        TaskSubtasksSection(
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
        task: task,
        currentLocalDateTimeHint: currentLocalDateTimeHint,
      ),
    );

    if (task.assignedLabels.isNotEmpty || isInlineLabelPickerOpen) {
      sections.add(
        _TaskLabelsSection(
          task: task,
          allLabels: allLabels,
          hasBothScopedAndGlobal: hasBothScopedAndGlobalLabels,
          isInlinePickerOpen: isInlineLabelPickerOpen,
          isBusy: isBusy,
          onQueryChanged: shellNotifier.setLabelPickerQuery,
          onToggleLabel: (labelId) => unawaited(
            _reportTaskActionFailure(
              ref,
              taskNotifier.toggleLabel(task.id, labelId, locale: locale),
            ),
          ),
          onCreateAndAssign: (rawName) => unawaited(
            _reportTaskActionFailure(
              ref,
              taskNotifier.createAndAssignLabel(
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

    if (task.dueFormatted != null || activeSection == TaskSectionKind.due) {
      sections.add(
        TaskDueSection(
          task: task,
          isEditing: activeSection == TaskSectionKind.due && !task.isCompleted,
          currentLocalDateTimeHint: currentLocalDateTimeHint,
          onStartEdit: () => shellNotifier.openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.due),
          ),
          onCancelEdit: shellNotifier.closeInlineEdit,
        ),
      );
    }

    if (!task.isCompleted && (task.isPriority || task.isSomeday)) {
      sections.add(
        _TaskPlacementSection(
          taskId: task.id,
          placement: task.placement,
          isBusy: isBusy,
          onChanged: (nextPlacement) => unawaited(
            _reportTaskActionFailure(
              ref,
              taskNotifier.setPlacement(task.id, nextPlacement, locale: locale),
            ),
          ),
        ),
      );
    }

    if (task.repeatSummary != null || activeSection == TaskSectionKind.repeat) {
      sections.add(
        TaskRepeatSection(
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

    if (task.isSuspended || activeSection == TaskSectionKind.suspended) {
      sections.add(
        TaskSuspendedSection(
          task: task,
          isEditing:
              activeSection == TaskSectionKind.suspended && !task.isCompleted,
          currentLocalDateTimeHint: currentLocalDateTimeHint,
          onStartEdit: () => shellNotifier.openInlineEdit(
            InlineEditTarget.task(task.id, TaskSectionKind.suspended),
          ),
          onCancelEdit: shellNotifier.closeInlineEdit,
        ),
      );
    }

    if (task.prerequisites.isNotEmpty ||
        activeSection == TaskSectionKind.prerequisites) {
      sections.add(
        TaskPrerequisitesSection(
          task: task,
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

    if (task.hasConditions || activeSection == TaskSectionKind.conditions) {
      sections.add(
        EntityConditionsSection(
          isTask: true,
          hasConditions: task.hasConditions,
          conditionsSummary: task.conditionsSummary,
          conditionDraft: task.conditionDraft,
          allLocations: allLocations,
          isEditing:
              activeSection == TaskSectionKind.conditions && !task.isCompleted,
          canEdit: !task.isCompleted,
          isSuspended: task.isSuspended,
          conditionsStatusLabel: task.conditionsStatusLabel,
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
              taskNotifier.saveConditions(task.id, draft, locale: locale),
          onClear: () => taskNotifier.clearConditions(task.id, locale: locale),
        ),
      );
    }

    return sections;
  }
}

/// Inline desktop label picker inset card rendered when [_TaskLabelsSection] is actively editing.
class _TaskLabelsPickerCard extends ConsumerWidget {
  /// Creates a [_TaskLabelsPickerCard].
  const _TaskLabelsPickerCard({
    required this.task,
    required this.allLabels,
    required this.hasBothScopedAndGlobal,
    required this.onQueryChanged,
    required this.onToggleLabel,
    required this.onCreateAndAssign,
    required this.onOpenLabelInfo,
    required this.onClosePicker,
  });

  /// Workspace labels for the searchable picker.
  final List<LabelPickerOptionViewModel> allLabels;

  /// Whether both scoped and global labels exist.
  final bool hasBothScopedAndGlobal;

  /// Callback closing the desktop inline label picker.
  final VoidCallback onClosePicker;

  /// Callback creating and immediately assigning a new label.
  final ValueChanged<String> onCreateAndAssign;

  /// Callback navigating to a label in Labels manager preserving `returnContext`.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback synchronizing label picker query with shell state.
  final ValueChanged<String> onQueryChanged;

  /// Callback toggling label assignment on the task.
  final ValueChanged<String> onToggleLabel;

  /// Projected task card view model.
  final TaskCardViewModel task;

  /// Identifiers of labels currently assigned to [task].
  Set<String> get _selectedIds => <String>{
    for (final chip in task.assignedLabels) chip.id,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final pickerQuery = ref.watch(
      appShellControllerProvider.select((shell) => shell.labelPickerQuery),
    );

    return UiCard.inset(
      key: ValueKey<String>('task_labels_picker_${task.id}'),
      isEditing: true,
      headerIcon: Icons.label_outline_rounded,
      headerTitle: localizations.taskLabelsSectionTitle,
      headerBadge: UiPill(
        label: '${task.assignedLabels.length}',
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
        selectedIds: _selectedIds,
        hasBothScopedAndGlobal: hasBothScopedAndGlobal,
        autoFocusSearch: true,
        query: pickerQuery,
        onQueryChanged: onQueryChanged,
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
    required this.isBusy,
    required this.onToggleLabel,
    required this.onOpenLabelInfo,
    required this.onOpenPicker,
  });

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback navigating to a label in Labels manager preserving `returnContext`.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback opening the label picker (desktop inline or compact sheet).
  final VoidCallback onOpenPicker;

  /// Callback toggling label assignment on the task.
  final ValueChanged<String> onToggleLabel;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      key: ValueKey<String>('task_labels_read_${task.id}'),
      headerIcon: Icons.label_outline_rounded,
      headerTitle: localizations.taskLabelsSectionTitle,
      headerBadge: UiPill(
        label: '${task.assignedLabels.length}',
        variant: UiPillVariant.count,
      ),
      child: _TaskAssignedLabelsWrap(
        task: task,
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
    required this.task,
    required this.allLabels,
    required this.hasBothScopedAndGlobal,
    required this.isInlinePickerOpen,
    required this.isBusy,
    required this.onQueryChanged,
    required this.onToggleLabel,
    required this.onCreateAndAssign,
    required this.onOpenLabelInfo,
    required this.onOpenPicker,
    required this.onClosePicker,
  });

  /// Workspace labels for the searchable picker.
  final List<LabelPickerOptionViewModel> allLabels;

  /// Whether both scoped and global labels exist.
  final bool hasBothScopedAndGlobal;

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

  /// Callback synchronizing label picker query with shell state.
  final ValueChanged<String> onQueryChanged;

  /// Callback toggling label assignment on the task.
  final ValueChanged<String> onToggleLabel;

  /// Projected task card view model.
  final TaskCardViewModel task;

  @override
  Widget build(BuildContext context) {
    if (isInlinePickerOpen && !task.isCompleted) {
      return _TaskLabelsPickerCard(
        task: task,
        allLabels: allLabels,
        hasBothScopedAndGlobal: hasBothScopedAndGlobal,
        onQueryChanged: onQueryChanged,
        onToggleLabel: onToggleLabel,
        onCreateAndAssign: onCreateAndAssign,
        onOpenLabelInfo: onOpenLabelInfo,
        onClosePicker: onClosePicker,
      );
    }

    return _TaskLabelsReadCard(
      task: task,
      isBusy: isBusy,
      onToggleLabel: onToggleLabel,
      onOpenLabelInfo: onOpenLabelInfo,
      onOpenPicker: onOpenPicker,
    );
  }
}

/// Live Queue & Priority segmented switch rendered on active Priority or Someday tasks (`U-CARD-002`..`003`).
class _TaskPlacementSection extends StatelessWidget {
  /// Creates a [_TaskPlacementSection].
  const _TaskPlacementSection({
    required this.taskId,
    required this.placement,
    required this.isBusy,
    required this.onChanged,
  });

  /// Whether a task mutation is in flight.
  final bool isBusy;

  /// Callback committing the new placement immediately.
  final ValueChanged<TaskPlacementOption> onChanged;

  /// Current task placement option.
  final TaskPlacementOption placement;

  /// Owning task identifier for deterministic keys.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      key: ValueKey<String>('task_placement_section_$taskId'),
      headerIcon: Icons.bolt_outlined,
      headerTitle: localizations.inlinePlacementSectionTitle,
      child: UiSegmentedControl<TaskPlacementOption>(
        key: ValueKey<String>('task_placement_control_$taskId'),
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
    );
  }
}

/// Returns `true` when [section] renders after Due in the canonical `+ Add` chips order.
bool _comesAfterDue(TaskSectionKind section) {
  return section == TaskSectionKind.repeat ||
      section == TaskSectionKind.suspended ||
      section == TaskSectionKind.prerequisites ||
      section == TaskSectionKind.conditions;
}

/// Returns `true` when [task] has at least one collapsed label chip or badge to render.
bool _hasCollapsedMetadata(TaskCardViewModel task) {
  return task.assignedLabels.isNotEmpty ||
      task.primaryBadges.isNotEmpty ||
      task.visibleSecondaryBadges.isNotEmpty ||
      task.overflowSecondaryCount > 0;
}

/// Navigates to [entity] in its manager view while preserving Tasks/Search `returnContext`.
void _openEntityInManager(WidgetRef ref, EntityRef entity) {
  ref
      .read(appShellControllerProvider.notifier)
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
  ref.read(floatingNoticeControllerProvider.notifier).showNotice(copiedMessage);
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
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(message, tone: NoticeTone.danger);
      }
  }
}

/// Resolves an optional ARGB label color value, falling back to `tokens.colors.accent`.
Color _resolveLabelColor(int? colorValue, UiThemeTokens tokens) {
  return switch (colorValue) {
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
