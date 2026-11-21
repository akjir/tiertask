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
import '../../presentation/floating_notice_controller.dart';
import '../../presentation/shell_models.dart';
import '../../presentation/sync_controller.dart';
import '../../presentation/task_controller.dart';
import '../../presentation/tasks_view_model.dart';
import '../../presentation/view_model_primitives.dart';
import '../dialogs/compact_label_picker_sheet.dart';
import '../ui_icon_mapper.dart';
import '../widgets/entity_label_picker.dart';
import 'task_card.dart';
import 'task_draft_card.dart';

/// Maximum single-line task title length allowed by `TDF 0.8.0` (`maxTdfTextLength`).
const int _maxTaskTitleLength = 500;

/// Duration used for smooth `Scrollable.ensureVisible` entity card reveals (`U-LAYOUT-007`).
const Duration _revealDuration = Duration(milliseconds: 220);

/// Pinned bottom dock Task Quick-Add composer (`U-CARD-006`, `U-LAYOUT-005`).
///
/// Automatically hides while a Task Draft Card, initial loading state, or full-screen
/// file-read error is active. Collapses to a full-width `+ New task` button on compact viewports.
class TasksQuickAddDock extends ConsumerStatefulWidget {
  /// Creates a [TasksQuickAddDock].
  const TasksQuickAddDock({super.key, this.titleFocusNode});

  /// Optional caller-owned focus node allowing desktop `n` shortcut focus (`U-A11Y-002`).
  final FocusNode? titleFocusNode;

  @override
  ConsumerState<TasksQuickAddDock> createState() => _TasksQuickAddDockState();
}

/// Primary six-tier Tasks and Global Search view (`U-LAYOUT-004`, `U-UX-003`, `U-UX-007`).
class TasksView extends ConsumerStatefulWidget {
  /// Creates a [TasksView].
  const TasksView({
    super.key,
    this.scrollController,
    this.revealCardKeyBuilder,
  });

  /// Optional builder providing [GlobalKey] instances per task ID for card reveal scrolling.
  final GlobalKey Function(String taskId)? revealCardKeyBuilder;

  /// Optional caller-owned scroll controller preserving main list scroll position (`U-LAYOUT-007`).
  final ScrollController? scrollController;

  @override
  ConsumerState<TasksView> createState() => _TasksViewState();
}

/// Single diagnostic row rendered inside [_FileReadDiagnosticsCard].
class _FileReadDiagnosticRow extends StatelessWidget {
  /// Creates a [_FileReadDiagnosticRow].
  const _FileReadDiagnosticRow({
    required this.line,
    required this.okLabel,
    required this.unreadableLabel,
    required this.iconColor,
  });

  /// Leading status icon color.
  final Color iconColor;

  /// Per-target diagnostic entry.
  final FileReadDiagnosticLineViewModel line;

  /// Localized readable status pill text.
  final String okLabel;

  /// Localized unreadable status pill text.
  final String unreadableLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: ExcludeSemantics(
            child: Icon(
              line.isReadable
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              size: tokens.spacing.iconSm,
              color: iconColor,
            ),
          ),
        ),
        const SizedBox(width: 10.0),
        Expanded(
          child: _FileReadDiagnosticRowDetails(
            line: line,
            okLabel: okLabel,
            unreadableLabel: unreadableLabel,
          ),
        ),
      ],
    );
  }
}

/// Target heading, status pill, and detail message column inside [_FileReadDiagnosticRow].
class _FileReadDiagnosticRowDetails extends StatelessWidget {
  /// Creates a [_FileReadDiagnosticRowDetails].
  const _FileReadDiagnosticRowDetails({
    required this.line,
    required this.okLabel,
    required this.unreadableLabel,
  });

  /// Per-target diagnostic entry.
  final FileReadDiagnosticLineViewModel line;

  /// Localized readable status pill text.
  final String okLabel;

  /// Localized unreadable status pill text.
  final String unreadableLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              line.targetLabel,
              style: tokens.typography.control.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            UiPill(
              label: line.isReadable ? okLabel : unreadableLabel,
              variant: UiPillVariant.badge,
              tone: line.isReadable ? UiPillTone.success : UiPillTone.danger,
            ),
          ],
        ),
        const SizedBox(height: 2.0),
        Text(
          line.statusText,
          style: tokens.typography.meta.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}

/// Structured per-target Local/Remote diagnostics card embedded inside the full-screen file-read error view.
class _FileReadDiagnosticsCard extends StatelessWidget {
  /// Creates a [_FileReadDiagnosticsCard].
  const _FileReadDiagnosticsCard({required this.lines});

  /// Per-target readability diagnostics lines.
  final List<FileReadDiagnosticLineViewModel> lines;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return UiCard.standard(
      key: const ValueKey<String>('tasks_full_error_diagnostics_card'),
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < lines.length; i++) ...<Widget>[
            if (i > 0) SizedBox(height: tokens.spacing.space2),
            _FileReadDiagnosticRow(
              line: lines[i],
              okLabel: localizations.fileReadStatusOk,
              unreadableLabel: localizations.fileReadStatusUnreadable,
              iconColor: lines[i].isReadable ? colors.success : colors.danger,
            ),
          ],
        ],
      ),
    );
  }
}

/// Renders the design-system [UiQuickComposer] bound to shell expansion and popover handlers.
class _QuickAddComposerSurface extends ConsumerWidget {
  /// Creates a [_QuickAddComposerSurface].
  const _QuickAddComposerSurface({
    required this.session,
    required this.compactComposerOpen,
    required this.isBusy,
    required this.isCompact,
    required this.isPopoverOpen,
    required this.modeHint,
    required this.popoverContent,
  });

  /// Whether compact Quick-Add is expanded.
  final bool compactComposerOpen;

  /// Whether a task mutation is currently in flight.
  final bool isBusy;

  /// Whether viewport is in compact breakpoint class (`<= 720`).
  final bool isCompact;

  /// Whether the desktop label picker popover is open.
  final bool isPopoverOpen;

  /// Helper caption describing the active placement rendered below the composer card.
  final String modeHint;

  /// Optional upward desktop popover content.
  final Widget? popoverContent;

  /// Active Quick-Add draft session and callbacks.
  final _QuickAddSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final shellNotifier = ref.read(appShellControllerProvider.notifier);

    return UiQuickComposer(
      key: const ValueKey<String>('tasks_quick_add_composer'),
      controller: session.titleController,
      focusNode: session.titleFocusNode,
      placeholder: localizations.quickAddHint,
      submitLabel: localizations.actionAdd,
      maxLength: _maxTaskTitleLength,
      enabled: !isBusy,
      expandDraftLabel: localizations.actionOpenAsDraft,
      isCollapsibleOnCompact: true,
      isCompactExpanded: compactComposerOpen,
      onCompactExpandedChanged: shellNotifier.setCompactComposerOpen,
      compactTriggerLabel: '+ ${localizations.actionNewTaskCompact}',
      compactCloseTooltip: localizations.actionCancel,
      modeWidget: _QuickAddPlacementControl(
        placement: session.placement,
        enabled: !isBusy,
        onChanged: session.onPlacementChanged,
      ),
      modeHint: modeHint,
      draftChips: _QuickAddFooterSlot(
        session: session,
        isCompact: isCompact,
        isBusy: isBusy,
        isPopoverOpen: isPopoverOpen,
      ),
      isPopoverOpen: isPopoverOpen,
      onDismissPopover: () => shellNotifier.setLabelPickerOpen(false),
      popoverContent: popoverContent,
      onExpandDraft: () => session.onExpandDraft(session.selectedIds),
      onSubmit: () => session.onSubmit(session.selectedIds),
    );
  }
}

/// Draft label chips and `+ Labels` trigger rendered in the footer bar of [TasksQuickAddDock].
class _QuickAddDraftLabelsBar extends StatelessWidget {
  /// Creates a [_QuickAddDraftLabelsBar].
  const _QuickAddDraftLabelsBar({
    required this.selectedLabels,
    required this.isPickerOpen,
    required this.isBusy,
    required this.onRemoveLabel,
    required this.onOpenPicker,
  });

  /// Whether task creation is currently in flight.
  final bool isBusy;

  /// Whether the label picker popover or sheet is currently active.
  final bool isPickerOpen;

  /// Callback toggling the desktop popover or opening the compact label picker sheet.
  final VoidCallback onOpenPicker;

  /// Callback removing a selected label from the Quick-Add draft.
  final ValueChanged<String> onRemoveLabel;

  /// Resolved selected label options in alphabetical order.
  final List<LabelPickerOptionViewModel> selectedLabels;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final label in selectedLabels)
          UiPill(
            key: ValueKey<String>('quick_add_label_chip_${label.id}'),
            label: label.name,
            variant: UiPillVariant.splitChip,
            colorDot: switch (label.colorValue) {
              final value? => Color(value),
              null => tokens.colors.accent,
            },
            removeTooltip: localizations.labelPickerRemoveTooltip(label.name),
            enabled: !isBusy,
            onRemove: isBusy ? null : () => onRemoveLabel(label.id),
          ),
        UiPill(
          key: const ValueKey<String>('quick_add_labels_trigger'),
          label: selectedLabels.isEmpty
              ? localizations.inlineAddLabels
              : localizations.actionAdd,
          icon: selectedLabels.isEmpty
              ? Icons.label_outline_rounded
              : Icons.add_rounded,
          variant: UiPillVariant.addField,
          isSelected: isPickerOpen,
          enabled: !isBusy,
          onPressed: isBusy ? null : onOpenPicker,
        ),
      ],
    );
  }
}

/// Footer slot wiring [_QuickAddDraftLabelsBar] to desktop popover or compact label sheet triggers.
class _QuickAddFooterSlot extends ConsumerWidget {
  /// Creates a [_QuickAddFooterSlot].
  const _QuickAddFooterSlot({
    required this.session,
    required this.isCompact,
    required this.isBusy,
    required this.isPopoverOpen,
  });

  /// Whether a task mutation is currently in flight.
  final bool isBusy;

  /// Whether viewport is in compact breakpoint class (`<= 720`).
  final bool isCompact;

  /// Whether the desktop label picker popover is open.
  final bool isPopoverOpen;

  /// Active Quick-Add draft session and callbacks.
  final _QuickAddSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _QuickAddDraftLabelsBar(
      selectedLabels: session.selectedLabels,
      isPickerOpen: isPopoverOpen,
      isBusy: isBusy,
      onRemoveLabel: session.onToggleDraftLabel,
      onOpenPicker: () => _handleOpenPicker(ref),
    );
  }

  /// Toggles the desktop label popover or triggers the compact mobile label sheet.
  void _handleOpenPicker(WidgetRef ref) {
    if (!isCompact) {
      final shellNotifier = ref.read(appShellControllerProvider.notifier);
      if (ref.read(appShellControllerProvider).activeInlineEdit != null) {
        shellNotifier.closeInlineEdit();
      }
      shellNotifier.setLabelPickerOpen(!isPopoverOpen);
      return;
    }
    session.onOpenCompactLabelPicker(session.viewModel, session.selectedIds);
  }
}

/// Upward desktop popover body hosting [EntitySearchableLabelPicker] above [TasksQuickAddDock].
class _QuickAddLabelPopover extends ConsumerWidget {
  /// Creates a [_QuickAddLabelPopover].
  const _QuickAddLabelPopover({required this.session});

  /// Active Quick-Add draft session and callbacks.
  final _QuickAddSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final query = ref.watch(
      appShellControllerProvider.select((shell) => shell.labelPickerQuery),
    );
    final shellNotifier = ref.read(appShellControllerProvider.notifier);

    return Column(
      key: const ValueKey<String>('quick_add_label_popover'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _QuickAddLabelPopoverHeader(
          selectedCount: session.selectedIds.length,
          onClose: () => shellNotifier.setLabelPickerOpen(false),
        ),
        SizedBox(height: tokens.spacing.space2),
        EntitySearchableLabelPicker(
          allLabels: session.viewModel.allLabels,
          selectedIds: session.selectedIds,
          hasBothScopedAndGlobal:
              session.viewModel.hasBothScopedAndGlobalLabels,
          showSelectedChips: false,
          autoFocusSearch: true,
          query: query,
          onQueryChanged: shellNotifier.setLabelPickerQuery,
          onToggleLabel: session.onToggleDraftLabel,
          onCreateAndAssign: session.onCreateAndAssignLabel,
          onOpenLabelInfo: session.onOpenLabelInfo,
          onRequestClose: () => shellNotifier.setLabelPickerOpen(false),
        ),
      ],
    );
  }
}

/// Header row displaying label title, selection count pill, and Done button inside [_QuickAddLabelPopover].
class _QuickAddLabelPopoverHeader extends StatelessWidget {
  /// Creates a [_QuickAddLabelPopoverHeader].
  const _QuickAddLabelPopoverHeader({
    required this.selectedCount,
    required this.onClose,
  });

  /// Callback closing the desktop popover.
  final VoidCallback onClose;

  /// Number of labels currently selected on the draft.
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(
            Icons.label_outline_rounded,
            size: tokens.spacing.iconSm,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: 8.0),
        Text(
          localizations.taskLabelsSectionTitle,
          style: tokens.typography.meta.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8.0),
        UiPill(label: '$selectedCount', variant: UiPillVariant.count),
        const Spacer(),
        UiButton(
          label: localizations.actionDone,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// Vertical combobox placement selector sizing intrinsically on desktop rows and stretching on compact (`U-CARD-006`).
class _QuickAddPlacementControl extends StatelessWidget {
  /// Creates a [_QuickAddPlacementControl].
  const _QuickAddPlacementControl({
    required this.placement,
    required this.enabled,
    required this.onChanged,
  });

  /// Whether interaction is enabled.
  final bool enabled;

  /// Callback notified when placement changes.
  final ValueChanged<TaskPlacementOption> onChanged;

  /// Active placement selection.
  final TaskPlacementOption placement;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiSegmentedControl<TaskPlacementOption>(
      key: const ValueKey<String>('quick_add_placement_control'),
      mode: UiSegmentedControlMode.vertical,
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
      enabled: enabled,
      semanticLabel: localizations.inlinePlacementSectionTitle,
      onChanged: onChanged,
    );
  }
}

/// Immutable bundle of active Quick-Add composer inputs, selected labels, and mutation callbacks.
@immutable
class _QuickAddSession {
  /// Creates a [_QuickAddSession] from pre-resolved selected labels.
  const _QuickAddSession._({
    required this.titleController,
    required this.titleFocusNode,
    required this.viewModel,
    required this.placement,
    required this.selectedLabels,
    required this.selectedIds,
    required this.onPlacementChanged,
    required this.onToggleDraftLabel,
    required this.onCreateAndAssignLabel,
    required this.onOpenLabelInfo,
    required this.onOpenCompactLabelPicker,
    required this.onExpandDraft,
    required this.onSubmit,
  });

  /// Resolves valid selected labels once and returns a [_QuickAddSession].
  factory _QuickAddSession.from({
    required TextEditingController titleController,
    required FocusNode? titleFocusNode,
    required TasksViewModel viewModel,
    required TaskPlacementOption placement,
    required Set<String> draftLabelIds,
    required ValueChanged<TaskPlacementOption> onPlacementChanged,
    required ValueChanged<String> onToggleDraftLabel,
    required ValueChanged<String> onCreateAndAssignLabel,
    required ValueChanged<String> onOpenLabelInfo,
    required void Function(TasksViewModel viewModel, Set<String> selectedIds)
    onOpenCompactLabelPicker,
    required ValueChanged<Set<String>> onExpandDraft,
    required ValueChanged<Set<String>> onSubmit,
  }) {
    final selectedLabels = _resolveValidSelectedLabels(
      viewModel.allLabels,
      draftLabelIds,
    );
    final selectedIds = <String>{for (final label in selectedLabels) label.id};
    return _QuickAddSession._(
      titleController: titleController,
      titleFocusNode: titleFocusNode,
      viewModel: viewModel,
      placement: placement,
      selectedLabels: selectedLabels,
      selectedIds: selectedIds,
      onPlacementChanged: onPlacementChanged,
      onToggleDraftLabel: onToggleDraftLabel,
      onCreateAndAssignLabel: onCreateAndAssignLabel,
      onOpenLabelInfo: onOpenLabelInfo,
      onOpenCompactLabelPicker: onOpenCompactLabelPicker,
      onExpandDraft: onExpandDraft,
      onSubmit: onSubmit,
    );
  }

  /// Callback creating and immediately assigning a new workspace label to the draft.
  final ValueChanged<String> onCreateAndAssignLabel;

  /// Callback opening the full uncommitted Task Draft Card.
  final ValueChanged<Set<String>> onExpandDraft;

  /// Callback presenting the compact mobile label picker bottom sheet.
  final void Function(TasksViewModel viewModel, Set<String> selectedIds)
  onOpenCompactLabelPicker;

  /// Callback opening a label inside Labels manager.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback updating the selected placement option.
  final ValueChanged<TaskPlacementOption> onPlacementChanged;

  /// Callback submitting Quick-Add with the resolved selected label identifiers.
  final ValueChanged<Set<String>> onSubmit;

  /// Callback toggling label membership on the Quick-Add draft.
  final ValueChanged<String> onToggleDraftLabel;

  /// Active placement selection.
  final TaskPlacementOption placement;

  /// Resolved selected draft label identifiers still present in [viewModel].
  final Set<String> selectedIds;

  /// Resolved selected label options in alphabetical order.
  final List<LabelPickerOptionViewModel> selectedLabels;

  /// Controller for the Quick-Add title input.
  final TextEditingController titleController;

  /// Optional caller-owned focus node for the title input.
  final FocusNode? titleFocusNode;

  /// Projected Tasks view model.
  final TasksViewModel viewModel;
}

/// Compact viewport tier selector dropdown rendered above [UiPageHeader] when Search is closed.
class _TasksCompactTierSelect extends ConsumerWidget {
  /// Creates a [_TasksCompactTierSelect].
  const _TasksCompactTierSelect({required this.tierOptions});

  /// Projected tier option labels and task counts.
  final List<CompactTierOptionViewModel> tierOptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final activeTier = ref.watch(
      appShellControllerProvider.select((shell) => shell.activeTier),
    );

    return UiField(
      key: const ValueKey<String>('compact_tier_select'),
      kind: UiFieldKind.select,
      height: tokens.spacing.touchTargetMobile,
      selectValue: activeTier.name,
      selectOptions: <UiSelectOption>[
        for (final option in tierOptions)
          UiSelectOption(
            value: option.tier.name,
            label: '${option.label} · ${option.count}',
          ),
      ],
      semanticLabel: localizations.sectionTasksTitle,
      onSelectChanged: (value) {
        final nextTier = _parseShellTier(value);
        if (nextTier != null) {
          ref.read(appShellControllerProvider.notifier).selectTier(nextTier);
        }
      },
    );
  }
}

/// Full-screen file-read error state replacing [TasksView] when all active targets fail (`U-UX-007`).
class _TasksFullScreenErrorBody extends StatelessWidget {
  /// Creates a [_TasksFullScreenErrorBody].
  const _TasksFullScreenErrorBody({
    required this.errorReport,
    required this.isSyncing,
    required this.onOpenSettings,
    required this.onRetry,
  });

  /// Structured file-read diagnostics report.
  final FileReadReportViewModel errorReport;

  /// Whether retry synchronization is currently in flight.
  final bool isSyncing;

  /// Callback navigating to Settings view.
  final VoidCallback onOpenSettings;

  /// Callback retrying file load / sync.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);

    return Center(
      child: SingleChildScrollView(
        padding: tokens.spacing.mainContentPadding(viewport),
        child: UiBanner(
          key: const ValueKey<String>('tasks_full_error_banner'),
          variant: UiBannerVariant.fullError,
          icon: Icons.cloud_off_outlined,
          title: errorReport.title,
          message: errorReport.summary,
          detailsChild: errorReport.lines.isNotEmpty
              ? _FileReadDiagnosticsCard(lines: errorReport.lines)
              : null,
          actions: <Widget>[
            UiButton(
              key: const ValueKey<String>('tasks_full_error_settings_button'),
              label: localizations.actionSettings,
              leadingIcon: Icons.settings_outlined,
              variant: UiButtonVariant.secondary,
              onPressed: onOpenSettings,
            ),
            UiButton(
              key: const ValueKey<String>('tasks_full_error_retry_button'),
              label: localizations.actionRetry,
              leadingIcon: Icons.refresh_rounded,
              variant: UiButtonVariant.primary,
              isLoading: isSyncing,
              onPressed: isSyncing ? null : onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// Top non-card sliver of [TasksView]: page header, status banners, and optional Task Draft Card.
class _TasksHeaderAndBannersSliver extends StatelessWidget {
  /// Creates a [_TasksHeaderAndBannersSliver].
  const _TasksHeaderAndBannersSliver({
    required this.viewModel,
    required this.isTaskDraftOpen,
    required this.isCompact,
    required this.isSyncing,
    required this.padding,
    required this.onRetrySync,
  });

  /// Whether viewport is compact (`<= 720`).
  final bool isCompact;

  /// Whether a synchronization retry is currently in flight.
  final bool isSyncing;

  /// Whether the uncommitted Task Draft Card is open.
  final bool isTaskDraftOpen;

  /// Callback retrying synchronization.
  final VoidCallback onRetrySync;

  /// Outer sliver padding around header, banners, and draft card.
  final EdgeInsets padding;

  /// Projected Tasks view model.
  final TasksViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return SliverPadding(
      padding: padding,
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _TasksPageHeaderSection(viewModel: viewModel, isCompact: isCompact),
            if (viewModel.banners.isNotEmpty)
              _TasksStatusBannersList(
                banners: viewModel.banners,
                isSyncing: isSyncing,
                onRetrySync: onRetrySync,
              ),
            if (isTaskDraftOpen) ...<Widget>[
              SizedBox(height: tokens.spacing.space4),
              TaskDraftCard(
                allLabels: viewModel.allLabels,
                allLocations: viewModel.allLocations,
                hasBothScopedAndGlobalLabels:
                    viewModel.hasBothScopedAndGlobalLabels,
                currentLocalDateTimeHint: viewModel.currentLocalDateTimeHint,
              ),
            ],
            SizedBox(height: tokens.spacing.space4),
          ],
        ),
      ),
    );
  }
}

/// Single task card row wrapped in list spacing and reveal [KeyedSubtree].
class _TasksListCardItem extends StatelessWidget {
  /// Creates a [_TasksListCardItem].
  const _TasksListCardItem({
    required this.task,
    required this.isLast,
    required this.viewModel,
    required this.revealKey,
  });

  /// Whether this item is the last visible task card in the list.
  final bool isLast;

  /// Stable [GlobalKey] used for post-frame reveal scrolling.
  final GlobalKey revealKey;

  /// Projected task card view model.
  final TaskCardViewModel task;

  /// Projected Tasks view model providing shared labels, locations, and hints.
  final TasksViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: isLast ? 0.0 : tokens.spacing.cardListGap,
      ),
      child: KeyedSubtree(
        key: revealKey,
        child: TaskCard(
          key: ValueKey<String>('task_card_${task.id}'),
          task: task,
          allLabels: viewModel.allLabels,
          allLocations: viewModel.allLocations,
          hasBothScopedAndGlobalLabels: viewModel.hasBothScopedAndGlobalLabels,
          currentLocalDateTimeHint: viewModel.currentLocalDateTimeHint,
        ),
      ),
    );
  }
}

/// Lazy task list or empty-state sliver rendered inside [_TasksScrollableBody].
class _TasksListSliver extends StatelessWidget {
  /// Creates a [_TasksListSliver].
  const _TasksListSliver({
    required this.viewModel,
    required this.isTaskDraftOpen,
    required this.resolveRevealCardKey,
  });

  /// Whether the uncommitted Task Draft Card is open.
  final bool isTaskDraftOpen;

  /// Callback resolving stable [GlobalKey]s for reveal targeting.
  final GlobalKey Function(String taskId) resolveRevealCardKey;

  /// Projected Tasks view model.
  final TasksViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.tasks.isEmpty && !isTaskDraftOpen) {
      return SliverToBoxAdapter(
        child: UiBanner(
          key: const ValueKey<String>('tasks_empty_banner'),
          variant: UiBannerVariant.emptyState,
          message: viewModel.emptyHint,
        ),
      );
    }

    return SliverList.builder(
      itemCount: viewModel.tasks.length,
      itemBuilder: (context, index) {
        final task = viewModel.tasks[index];
        return _TasksListCardItem(
          task: task,
          isLast: index + 1 >= viewModel.tasks.length,
          viewModel: viewModel,
          revealKey: resolveRevealCardKey(task.id),
        );
      },
    );
  }
}

/// Centered initial loading state banner replacing [TasksView] while the workspace loads.
class _TasksLoadingBody extends StatelessWidget {
  /// Creates a [_TasksLoadingBody].
  const _TasksLoadingBody();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);

    return Center(
      child: Padding(
        padding: tokens.spacing.mainContentPadding(viewport),
        child: UiBanner(
          key: const ValueKey<String>('tasks_loading_banner'),
          variant: UiBannerVariant.loadingState,
          title: localizations.loadingBoardTitle,
          message: localizations.loadingBoardSubtitle,
        ),
      ),
    );
  }
}

/// Compact tier dropdown (when Search is closed) and [UiPageHeader] section for [TasksView].
class _TasksPageHeaderSection extends ConsumerWidget {
  /// Creates a [_TasksPageHeaderSection].
  const _TasksPageHeaderSection({
    required this.viewModel,
    required this.isCompact,
  });

  /// Whether viewport is compact (`<= 720`).
  final bool isCompact;

  /// Projected Tasks view model.
  final TasksViewModel viewModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final searchOpen = ref.watch(
      appShellControllerProvider.select((shell) => shell.searchOpen),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isCompact && !searchOpen) ...<Widget>[
          _TasksCompactTierSelect(tierOptions: viewModel.tierOptions),
          SizedBox(height: tokens.spacing.space3),
        ],
        UiPageHeader(
          key: const ValueKey<String>('tasks_page_header'),
          title: viewModel.headerTitle,
          subtitle: viewModel.headerSubtitle,
          countLabel: viewModel.headerCountLabel,
          activeFilterLabel: viewModel.activeFilterLabelName,
          activeFilterTooltip: localizations.activeFilterClearTooltip,
          onClearActiveFilter: viewModel.activeFilterLabelId != null
              ? () => ref
                    .read(appShellControllerProvider.notifier)
                    .selectLabelFilter(null)
              : null,
          showInlineFilterOnCompact: searchOpen,
        ),
      ],
    );
  }
}

/// Watches composer shell and busy selectors to build [_QuickAddComposerSurface] for [TasksQuickAddDock].
class _TasksQuickAddDockBody extends ConsumerWidget {
  /// Creates a [_TasksQuickAddDockBody].
  const _TasksQuickAddDockBody({required this.session});

  /// Active Quick-Add draft session and callbacks.
  final _QuickAddSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final shellState = ref.watch(
      appShellControllerProvider.select(
        (shell) => (
          compactComposerOpen: shell.compactComposerOpen,
          hasInlineEdit: shell.activeInlineEdit != null,
          labelPickerOpen: shell.labelPickerOpen,
        ),
      ),
    );
    final isBusy = ref.watch(
      taskControllerProvider.select((state) => state.isBusy),
    );
    final isPopoverOpen =
        !isCompact && shellState.labelPickerOpen && !shellState.hasInlineEdit;

    return _QuickAddComposerSurface(
      session: session,
      modeHint: _quickAddPlacementHint(session.placement, localizations),
      isCompact: isCompact,
      compactComposerOpen: shellState.compactComposerOpen,
      isBusy: isBusy,
      isPopoverOpen: isPopoverOpen,
      popoverContent: isPopoverOpen
          ? _QuickAddLabelPopover(session: session)
          : null,
    );
  }
}

/// Manages title controller, placement selection, auto-seeded draft labels, and label picker overlay for [TasksQuickAddDock].
class _TasksQuickAddDockState extends ConsumerState<TasksQuickAddDock> {
  late final TextEditingController _titleController;

  late Set<String> _draftLabelIds;
  TaskPlacementOption _placement = TaskPlacementOption.queue;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    final initialActiveLabelId = ref
        .read(appShellControllerProvider)
        .activeLabelId;
    _draftLabelIds = initialActiveLabelId != null
        ? <String>{initialActiveLabelId}
        : <String>{};
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      appShellControllerProvider.select((shell) => shell.activeLabelId),
      _handleActiveLabelFilterChanged,
    );

    final viewModel = ref.watch(tasksViewModelProvider);
    final activeDraft = ref.watch(
      appShellControllerProvider.select((shell) => shell.activeDraft),
    );
    if (viewModel.isLoading ||
        viewModel.fullScreenFileReadError != null ||
        activeDraft == EntityDraftKind.task) {
      return const SizedBox.shrink();
    }

    return _TasksQuickAddDockBody(
      session: _QuickAddSession.from(
        titleController: _titleController,
        titleFocusNode: widget.titleFocusNode,
        viewModel: viewModel,
        placement: _placement,
        draftLabelIds: _draftLabelIds,
        onPlacementChanged: _handlePlacementChanged,
        onToggleDraftLabel: _handleToggleDraftLabel,
        onCreateAndAssignLabel: _triggerCreateAndAssignLabel,
        onOpenLabelInfo: _handleOpenLabelInfo,
        onOpenCompactLabelPicker: _handleOpenCompactLabelPicker,
        onExpandDraft: _handleExpandDraft,
        onSubmit: _triggerQuickAdd,
      ),
    );
  }

  /// Auto-seeds or resets draft labels whenever the sidebar active label filter changes (`U-LAYOUT-004`).
  void _handleActiveLabelFilterChanged(
    String? previousLabelId,
    String? nextLabelId,
  ) {
    if (previousLabelId == nextLabelId) {
      return;
    }
    setState(() {
      _draftLabelIds = nextLabelId != null ? <String>{nextLabelId} : <String>{};
    });
  }

  /// Creates a new workspace label from [rawName] and selects it on the Quick-Add draft.
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
            _draftLabelIds = <String>{..._draftLabelIds, entityId};
          });
        }
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        if (message.isNotEmpty) {
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(message, tone: NoticeTone.danger);
        }
    }
  }

  /// Transfers typed Quick-Add inputs into an uncommitted Task Draft Card and resets composer state (`U-CARD-006`).
  void _handleExpandDraft(Set<String> selectedIds) {
    final seedTitle = _titleController.text;
    final seedPlacement = _placement;
    final seedLabelIds = selectedIds.toList(growable: false);
    final activeLabelId = ref.read(appShellControllerProvider).activeLabelId;
    ref
        .read(appShellControllerProvider.notifier)
        .openDraft(
          EntityDraftKind.task,
          seedTitle: seedTitle,
          seedPlacement: seedPlacement,
          seedLabelIds: seedLabelIds,
        );
    setState(() {
      _titleController.clear();
      _placement = TaskPlacementOption.queue;
      _draftLabelIds = activeLabelId != null
          ? <String>{activeLabelId}
          : <String>{};
    });
  }

  /// Presents the compact mobile label picker bottom sheet for the Quick-Add draft.
  void _handleOpenCompactLabelPicker(
    TasksViewModel viewModel,
    Set<String> selectedIds,
  ) {
    final localizations = AppLocalizations.of(context);
    unawaited(
      showCompactLabelPickerSheet(
        context,
        title: localizations.taskLabelsSectionTitle,
        allLabels: viewModel.allLabels,
        hasBothScopedAndGlobal: viewModel.hasBothScopedAndGlobalLabels,
        selectedIds: selectedIds,
        onToggleLabel: _handleToggleDraftLabel,
        onCreateAndAssign: _triggerCreateAndAssignLabel,
        onOpenLabelInfo: _handleOpenLabelInfo,
      ),
    );
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

  /// Updates the active Quick-Add placement option.
  void _handlePlacementChanged(TaskPlacementOption nextPlacement) {
    setState(() => _placement = nextPlacement);
  }

  /// Submits Quick-Add via [TaskController.quickAddTask], clearing title ONLY on [ActionSucceeded] (`U-CARD-006`).
  Future<void> _handleQuickAdd(Set<String> selectedIds) async {
    final localizations = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final result = await ref
        .read(taskControllerProvider.notifier)
        .quickAddTask(
          rawTitle: _titleController.text,
          placement: _placement,
          labelIds: selectedIds.toList(growable: false),
          locale: locale,
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        _titleController.clear();
      case ActionValidationFailed(:final message):
        if (message.isNotEmpty &&
            message != localizations.taskNameErrorDuplicate) {
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(message, tone: NoticeTone.danger);
        }
      case ActionPersistFailed(:final message):
        if (message.isNotEmpty) {
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(message, tone: NoticeTone.danger);
        }
    }
  }

  /// Toggles [labelId] in [_draftLabelIds].
  void _handleToggleDraftLabel(String labelId) {
    final next = Set<String>.of(_draftLabelIds);
    if (!next.add(labelId)) {
      next.remove(labelId);
    }
    setState(() => _draftLabelIds = next);
  }

  /// Dispatches async label creation from synchronous picker callbacks.
  void _triggerCreateAndAssignLabel(String rawName) {
    unawaited(_handleCreateAndAssignLabel(rawName));
  }

  /// Dispatches async Quick-Add submission from synchronous composer callbacks.
  void _triggerQuickAdd(Set<String> selectedIds) {
    unawaited(_handleQuickAdd(selectedIds));
  }
}

/// Scrollable tier/search body hosting compact tier select, header, banners, draft card, and lazy task cards.
class _TasksScrollableBody extends ConsumerWidget {
  /// Creates a [_TasksScrollableBody].
  const _TasksScrollableBody({
    required this.scrollController,
    required this.viewModel,
    required this.isSyncing,
    required this.resolveRevealCardKey,
    required this.onRetrySync,
  });

  /// Whether a synchronization retry is currently in flight.
  final bool isSyncing;

  /// Callback retrying synchronization from status banners.
  final VoidCallback onRetrySync;

  /// Callback resolving stable [GlobalKey]s for reveal targeting.
  final GlobalKey Function(String taskId) resolveRevealCardKey;

  /// Optional caller-owned scroll controller.
  final ScrollController? scrollController;

  /// Projected Tasks view model.
  final TasksViewModel viewModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);
    final isTaskDraftOpen = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.activeDraft == EntityDraftKind.task,
      ),
    );
    final padding = tokens.spacing.mainContentPadding(viewport);

    return CustomScrollView(
      key: const ValueKey<String>('tasks_scroll_view'),
      controller: scrollController,
      slivers: <Widget>[
        _TasksHeaderAndBannersSliver(
          viewModel: viewModel,
          isTaskDraftOpen: isTaskDraftOpen,
          isCompact: viewport == UiViewportClass.compact,
          isSyncing: isSyncing,
          padding: padding.copyWith(bottom: 0.0),
          onRetrySync: onRetrySync,
        ),
        SliverPadding(
          padding: padding.copyWith(top: 0.0),
          sliver: _TasksListSliver(
            viewModel: viewModel,
            isTaskDraftOpen: isTaskDraftOpen,
            resolveRevealCardKey: resolveRevealCardKey,
          ),
        ),
      ],
    );
  }
}

/// Renders one operational [ShellBannerViewModel] mapped to its design-system [UiBanner] and actions (`U-UX-007`).
class _TasksStatusBanner extends StatelessWidget {
  /// Creates a [_TasksStatusBanner].
  const _TasksStatusBanner({
    required this.banner,
    required this.isSyncing,
    required this.onOpenView,
    required this.onRetrySync,
    required this.onDismissSyncError,
    required this.onDismissFileRead,
  });

  /// Status banner projection.
  final ShellBannerViewModel banner;

  /// Whether a synchronization retry is currently in flight.
  final bool isSyncing;

  /// Callback dismissing the partial file-read banner.
  final VoidCallback onDismissFileRead;

  /// Callback dismissing the sync error banner.
  final VoidCallback onDismissSyncError;

  /// Callback navigating to a shell view (`settings`, `conflict`, `recovery`).
  final ValueChanged<ShellView> onOpenView;

  /// Callback triggering immediate synchronization retry.
  final VoidCallback onRetrySync;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final sublines = <String>[
      for (final line in banner.diagnosticLines)
        localizations.fileReadStatusEntryLine(
          line.targetLabel,
          line.statusText,
        ),
    ];

    return UiBanner(
      key: ValueKey<String>('tasks_status_banner_${banner.kind.name}'),
      variant: UiBannerVariant.status,
      tone: UiIconMapper.bannerTone(banner.tone),
      message: banner.message,
      sublines: sublines,
      actions: _buildActions(localizations),
      dismissTooltip: banner.dismissible ? localizations.actionDismiss : null,
      onDismiss: banner.dismissible ? _resolveDismissHandler() : null,
    );
  }

  /// Maps [banner.kind] exhaustively to its interactive banner action buttons.
  List<Widget> _buildActions(AppLocalizations localizations) {
    return switch (banner.kind) {
      ShellBannerKind.unconfiguredWebDav => <Widget>[
        UiButton(
          label: banner.primaryActionLabel ?? localizations.actionConfigure,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: () => onOpenView(ShellView.settings),
        ),
      ],
      ShellBannerKind.syncError || ShellBannerKind.partialFileRead => <Widget>[
        UiButton(
          label: banner.primaryActionLabel ?? localizations.actionRetry,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          isLoading: isSyncing,
          onPressed: isSyncing ? null : onRetrySync,
        ),
        UiButton(
          label: banner.secondaryActionLabel ?? localizations.actionSettings,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: () => onOpenView(ShellView.settings),
        ),
      ],
      ShellBannerKind.deletionConflict => <Widget>[
        UiButton(
          label:
              banner.primaryActionLabel ?? localizations.actionResolveConflict,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          onPressed: () => onOpenView(ShellView.conflict),
        ),
      ],
      ShellBannerKind.recoveryRequired => <Widget>[
        UiButton(
          label:
              banner.primaryActionLabel ?? localizations.actionResolveRecovery,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          onPressed: () => onOpenView(ShellView.recovery),
        ),
      ],
    };
  }

  /// Returns the matching banner dismissal callback for dismissible banner kinds.
  VoidCallback? _resolveDismissHandler() {
    return switch (banner.kind) {
      ShellBannerKind.syncError => onDismissSyncError,
      ShellBannerKind.partialFileRead => onDismissFileRead,
      ShellBannerKind.unconfiguredWebDav ||
      ShellBannerKind.deletionConflict ||
      ShellBannerKind.recoveryRequired => null,
    };
  }
}

/// Vertical stack of operational status banners rendered below [_TasksPageHeaderSection].
class _TasksStatusBannersList extends ConsumerWidget {
  /// Creates a [_TasksStatusBannersList].
  const _TasksStatusBannersList({
    required this.banners,
    required this.isSyncing,
    required this.onRetrySync,
  });

  /// Active status banners to display in priority order.
  final List<ShellBannerViewModel> banners;

  /// Whether a synchronization retry is currently in flight.
  final bool isSyncing;

  /// Callback triggering immediate synchronization retry.
  final VoidCallback onRetrySync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final shellNotifier = ref.read(appShellControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final banner in banners) ...<Widget>[
          SizedBox(height: tokens.spacing.space3),
          _TasksStatusBanner(
            banner: banner,
            isSyncing: isSyncing,
            onOpenView: shellNotifier.openView,
            onRetrySync: onRetrySync,
            onDismissSyncError: shellNotifier.dismissSyncErrorBanner,
            onDismissFileRead: shellNotifier.dismissFileReadBanner,
          ),
        ],
      ],
    );
  }
}

/// Manages smooth entity reveal scrolling, draft scroll-to-top, and card keys for [TasksView].
class _TasksViewState extends ConsumerState<TasksView> {
  final Map<String, GlobalKey> _ownedCardKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    final pendingReveal = ref
        .read(appShellControllerProvider)
        .revealEntityRequest;
    if (pendingReveal != null && pendingReveal.kind == EntityKind.task) {
      _scheduleRevealTask(pendingReveal.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<EntityRef?>(
      appShellControllerProvider.select((shell) => shell.revealEntityRequest),
      _handleRevealEntityRequested,
    );
    ref.listen<EntityDraftKind?>(
      appShellControllerProvider.select((shell) => shell.activeDraft),
      _handleActiveDraftChanged,
    );

    final viewModel = ref.watch(tasksViewModelProvider);
    final isSyncing = ref.watch(
      syncControllerProvider.select((syncState) => syncState.isBusy),
    );

    if (viewModel.isLoading) {
      return const _TasksLoadingBody();
    }
    if (viewModel.fullScreenFileReadError case final errorReport?) {
      return _TasksFullScreenErrorBody(
        errorReport: errorReport,
        isSyncing: isSyncing,
        onOpenSettings: _openSettings,
        onRetry: _triggerSyncNow,
      );
    }
    return _TasksScrollableBody(
      scrollController: widget.scrollController,
      viewModel: viewModel,
      isSyncing: isSyncing,
      resolveRevealCardKey: _resolveRevealCardKey,
      onRetrySync: _triggerSyncNow,
    );
  }

  /// Scrolls the list to top when a Task Draft Card transitions from closed to open.
  void _handleActiveDraftChanged(
    EntityDraftKind? previous,
    EntityDraftKind? next,
  ) {
    if (next == EntityDraftKind.task && previous != EntityDraftKind.task) {
      _scrollToTop();
    }
  }

  /// Schedules reveal scrolling when the shell requests focusing a task card.
  void _handleRevealEntityRequested(EntityRef? previous, EntityRef? next) {
    if (next != null && next.kind == EntityKind.task) {
      _scheduleRevealTask(next.id);
    }
  }

  /// Opens the Settings view from the full-screen file-read error banner.
  void _openSettings() {
    ref.read(appShellControllerProvider.notifier).openView(ShellView.settings);
  }

  /// Resolves the stable [GlobalKey] for revealing [taskId].
  GlobalKey _resolveRevealCardKey(String taskId) {
    if (widget.revealCardKeyBuilder case final builder?) {
      return builder(taskId);
    }
    return _ownedCardKeys.putIfAbsent(taskId, GlobalKey.new);
  }

  /// Schedules a post-frame `Scrollable.ensureVisible` reveal for [taskId] and clears the shell request.
  void _scheduleRevealTask(String taskId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final revealKey = _resolveRevealCardKey(taskId);
      final cardContext = revealKey.currentContext;
      if (cardContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            cardContext,
            duration: _revealDuration,
            curve: Curves.easeOut,
            alignment: 0.15,
          ),
        );
      }
      ref.read(appShellControllerProvider.notifier).clearRevealRequest();
    });
  }

  /// Scrolls the main task list smoothly to top (`0.0`) when opening a Task Draft Card (`U-CARD-006`).
  void _scrollToTop() {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) {
        return;
      }
      unawaited(
        controller.animateTo(
          0.0,
          duration: _revealDuration,
          curve: Curves.easeOut,
        ),
      );
    });
  }

  /// Triggers immediate synchronization or initial load retry through [SyncController].
  void _triggerSyncNow() {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref.read(syncControllerProvider.notifier).syncNow(locale: locale),
    );
  }
}

/// Parses a serialized [ShellTier] name safely without unchecked casts.
ShellTier? _parseShellTier(String value) {
  for (final tier in ShellTier.values) {
    if (tier.name == value) {
      return tier;
    }
  }
  return null;
}

/// Returns the localized helper caption describing [placement] in [TasksQuickAddDock].
String _quickAddPlacementHint(
  TaskPlacementOption placement,
  AppLocalizations localizations,
) {
  return switch (placement) {
    TaskPlacementOption.queue => localizations.placementQueueHint,
    TaskPlacementOption.priority => localizations.placementPriorityHint,
    TaskPlacementOption.someday => localizations.placementSomedayHint,
  };
}

/// Resolves selected [LabelPickerOptionViewModel] entries still present in [allLabels].
List<LabelPickerOptionViewModel> _resolveValidSelectedLabels(
  List<LabelPickerOptionViewModel> allLabels,
  Set<String> selectedIds,
) {
  return <LabelPickerOptionViewModel>[
    for (final label in allLabels)
      if (selectedIds.contains(label.id)) label,
  ];
}
