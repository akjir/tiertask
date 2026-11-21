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
import '../../presentation/sync_v2_controller.dart';
import '../../presentation/task_v2_controller.dart';
import '../../presentation/ui_v2_shell_models.dart';
import '../dialogs/app_modals.dart';
import '../ui_v2_icon_mapper.dart';
import 'entity_section_widgets.dart';
import 'task_card.dart';
import 'task_inline_editors.dart';

/// Minimum composer width required to place the segmented placement control inline on desktop.
const double _inlineDesktopComposerMinWidth = 760.0;

/// Maximum single-line task title length allowed by `TDF 0.8.0` (`maxTdfTextLength`).
const int _maxTaskTitleLength = 500;

/// Width of the horizontal placement segmented control on spacious desktop composer rows.
const double _placementWidthExpanded = 252.0;

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
    final colors = tokens.colors;

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
          child: Column(
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
                    tone: line.isReadable
                        ? UiPillTone.success
                        : UiPillTone.danger,
                  ),
                ],
              ),
              const SizedBox(height: 2.0),
              Text(
                line.statusText,
                style: tokens.typography.meta.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Adaptive wrapper hosting [UiQuickComposer] and switching narrow desktop widths to a stacked footer.
class _QuickAddAdaptiveComposer extends StatelessWidget {
  /// Creates a [_QuickAddAdaptiveComposer].
  const _QuickAddAdaptiveComposer({
    required this.titleController,
    required this.titleFocusNode,
    required this.headerTitle,
    required this.placement,
    required this.placementHint,
    required this.isCompact,
    required this.compactComposerOpen,
    required this.isBusy,
    required this.isPopoverOpen,
    required this.labelsBar,
    required this.popoverContent,
    required this.onCompactExpandedChanged,
    required this.onPlacementChanged,
    required this.onDismissPopover,
    required this.onExpandDraft,
    required this.onSubmit,
  });

  /// Whether compact Quick-Add is expanded.
  final bool compactComposerOpen;

  /// Active tier or Search heading title used inside the placeholder.
  final String headerTitle;

  /// Whether a task mutation is currently in flight.
  final bool isBusy;

  /// Whether viewport is in compact breakpoint class (`<= 720`).
  final bool isCompact;

  /// Whether the desktop label picker popover is open.
  final bool isPopoverOpen;

  /// Draft label chips and `+ Labels` trigger bar.
  final Widget labelsBar;

  /// Callback toggling compact expanded state.
  final ValueChanged<bool> onCompactExpandedChanged;

  /// Callback closing the desktop label picker popover.
  final VoidCallback onDismissPopover;

  /// Callback opening the full uncommitted Draft Card.
  final VoidCallback onExpandDraft;

  /// Callback updating the selected placement option.
  final ValueChanged<TaskPlacementOption> onPlacementChanged;

  /// Callback submitting Quick-Add.
  final VoidCallback onSubmit;

  /// Active placement selection.
  final TaskPlacementOption placement;

  /// Localized helper caption describing [placement].
  final String placementHint;

  /// Optional upward desktop popover content.
  final Widget? popoverContent;

  /// Controller for the Quick-Add title input.
  final TextEditingController titleController;

  /// Optional caller-owned focus node for the title input.
  final FocusNode? titleFocusNode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackDesktopControls =
            !isCompact && constraints.maxWidth < _inlineDesktopComposerMinWidth;
        return UiQuickComposer(
          key: const ValueKey<String>('tasks_quick_add_composer'),
          controller: titleController,
          focusNode: titleFocusNode,
          placeholder: localizations.quickAddHint(headerTitle),
          submitLabel: '+ ${localizations.actionAdd}',
          maxLength: _maxTaskTitleLength,
          enabled: !isBusy,
          expandDraftLabel: localizations.actionOpenAsDraft,
          isCollapsibleOnCompact: true,
          isCompactExpanded: compactComposerOpen,
          onCompactExpandedChanged: onCompactExpandedChanged,
          compactTriggerLabel: '+ ${localizations.actionNewTaskCompact}',
          compactCloseTooltip: localizations.actionCancel,
          modeWidget: stackDesktopControls
              ? null
              : _QuickAddPlacementControl(
                  isFullWidth: isCompact,
                  placement: placement,
                  enabled: !isBusy,
                  onChanged: onPlacementChanged,
                ),
          modeHint: stackDesktopControls ? null : placementHint,
          draftChips: stackDesktopControls
              ? _QuickAddNarrowFooter(
                  placement: placement,
                  placementHint: placementHint,
                  enabled: !isBusy,
                  onPlacementChanged: onPlacementChanged,
                  labelsBar: labelsBar,
                )
              : labelsBar,
          isPopoverOpen: isPopoverOpen,
          onDismissPopover: onDismissPopover,
          popoverContent: popoverContent,
          onExpandDraft: onExpandDraft,
          onSubmit: onSubmit,
        );
      },
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

/// Upward desktop popover body hosting [EntitySearchableLabelPicker] above [TasksQuickAddDock].
class _QuickAddLabelPopover extends StatelessWidget {
  /// Creates a [_QuickAddLabelPopover].
  const _QuickAddLabelPopover({
    required this.allLabels,
    required this.selectedIds,
    required this.hasBothScopedAndGlobal,
    required this.query,
    required this.onQueryChanged,
    required this.onToggleLabel,
    required this.onCreateAndAssign,
    required this.onOpenLabelInfo,
    required this.onClose,
  });

  /// All workspace label options.
  final List<LabelPickerOptionViewModel> allLabels;

  /// Whether both scoped and global labels exist.
  final bool hasBothScopedAndGlobal;

  /// Callback closing the desktop popover.
  final VoidCallback onClose;

  /// Callback creating and immediately assigning a new label to the draft.
  final ValueChanged<String> onCreateAndAssign;

  /// Callback opening a label inside Labels manager.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback updating the controlled label picker query.
  final ValueChanged<String> onQueryChanged;

  /// Callback toggling label selection on the Quick-Add draft.
  final ValueChanged<String> onToggleLabel;

  /// Controlled search query string.
  final String query;

  /// Currently selected draft label identifiers.
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Column(
      key: const ValueKey<String>('quick_add_label_popover'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
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
            UiPill(
              label: '${selectedIds.length}',
              variant: UiPillVariant.count,
            ),
            const Spacer(),
            UiButton(
              label: localizations.actionDone,
              variant: UiButtonVariant.secondary,
              density: UiButtonDensity.compact,
              onPressed: onClose,
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.space2),
        EntitySearchableLabelPicker(
          allLabels: allLabels,
          selectedIds: selectedIds,
          hasBothScopedAndGlobal: hasBothScopedAndGlobal,
          showSelectedChips: false,
          autoFocusSearch: true,
          query: query,
          onQueryChanged: onQueryChanged,
          onToggleLabel: onToggleLabel,
          onCreateAndAssign: onCreateAndAssign,
          onOpenLabelInfo: onOpenLabelInfo,
          onRequestClose: onClose,
        ),
      ],
    );
  }
}

/// Stacked placement, wrapping hint, and label chips footer used on narrow desktop widths (`< 760px`).
class _QuickAddNarrowFooter extends StatelessWidget {
  /// Creates a [_QuickAddNarrowFooter].
  const _QuickAddNarrowFooter({
    required this.placement,
    required this.placementHint,
    required this.enabled,
    required this.onPlacementChanged,
    required this.labelsBar,
  });

  /// Whether interaction is enabled.
  final bool enabled;

  /// Draft label chips and `+ Labels` trigger bar.
  final Widget labelsBar;

  /// Callback notified when placement changes.
  final ValueChanged<TaskPlacementOption> onPlacementChanged;

  /// Active placement selection.
  final TaskPlacementOption placement;

  /// Localized helper caption describing [placement].
  final String placementHint;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _QuickAddPlacementControl(
          isFullWidth: true,
          placement: placement,
          enabled: enabled,
          onChanged: onPlacementChanged,
        ),
        const SizedBox(height: 6.0),
        Text(
          placementHint,
          style: tokens.typography.eyebrow.copyWith(
            color: tokens.colors.muted,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.0,
          ),
        ),
        const SizedBox(height: 6.0),
        labelsBar,
      ],
    );
  }
}

/// Adaptive placement segmented selector sized safely for compact, narrow desktop, and wide desktop rows.
class _QuickAddPlacementControl extends StatelessWidget {
  /// Creates a [_QuickAddPlacementControl].
  const _QuickAddPlacementControl({
    required this.isFullWidth,
    required this.placement,
    required this.enabled,
    required this.onChanged,
  });

  /// Whether interaction is enabled.
  final bool enabled;

  /// Whether the control stretches to fill its parent width instead of using a fixed inline width.
  final bool isFullWidth;

  /// Callback notified when placement changes.
  final ValueChanged<TaskPlacementOption> onChanged;

  /// Active placement selection.
  final TaskPlacementOption placement;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final control = UiSegmentedControl<TaskPlacementOption>(
      key: const ValueKey<String>('quick_add_placement_control'),
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

    return isFullWidth
        ? control
        : SizedBox(width: _placementWidthExpanded, child: control);
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

/// Top non-card section of [TasksView]: compact tier select, page header, status banners, and optional Task Draft Card.
class _TasksHeaderAndBannersSliver extends StatelessWidget {
  /// Creates a [_TasksHeaderAndBannersSliver].
  const _TasksHeaderAndBannersSliver({
    required this.viewModel,
    required this.activeTier,
    required this.searchOpen,
    required this.isTaskDraftOpen,
    required this.isCompact,
    required this.isSyncing,
    required this.onSelectTier,
    required this.onClearActiveFilter,
    required this.onOpenView,
    required this.onRetrySync,
    required this.onDismissSyncError,
    required this.onDismissFileRead,
  });

  /// Currently selected task tier.
  final ShellTier activeTier;

  /// Whether viewport is compact (`<= 720`).
  final bool isCompact;

  /// Whether a synchronization retry is currently in flight.
  final bool isSyncing;

  /// Whether the uncommitted Task Draft Card is open.
  final bool isTaskDraftOpen;

  /// Callback clearing the active sidebar label filter.
  final VoidCallback onClearActiveFilter;

  /// Callback dismissing the partial file-read banner.
  final VoidCallback onDismissFileRead;

  /// Callback dismissing the sync error banner.
  final VoidCallback onDismissSyncError;

  /// Callback navigating to a top-level shell view (`settings`, `conflict`, `recovery`).
  final ValueChanged<ShellView> onOpenView;

  /// Callback retrying synchronization.
  final VoidCallback onRetrySync;

  /// Callback changing the active tier from the compact dropdown.
  final ValueChanged<ShellTier> onSelectTier;

  /// Whether Global Search mode is active.
  final bool searchOpen;

  /// Projected Tasks view model.
  final TasksViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isCompact && !searchOpen) ...<Widget>[
          UiField(
            key: const ValueKey<String>('compact_tier_select'),
            kind: UiFieldKind.select,
            height: tokens.spacing.touchTargetMobile,
            selectValue: activeTier.name,
            selectOptions: <UiSelectOption>[
              for (final option in viewModel.tierOptions)
                UiSelectOption(
                  value: option.tier.name,
                  label: '${option.label} · ${option.count}',
                ),
            ],
            semanticLabel: localizations.sectionTasksTitle,
            onSelectChanged: (value) {
              final nextTier = _parseShellTier(value);
              if (nextTier != null) {
                onSelectTier(nextTier);
              }
            },
          ),
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
              ? onClearActiveFilter
              : null,
          showInlineFilterOnCompact: searchOpen,
        ),
        for (final banner in viewModel.banners) ...<Widget>[
          SizedBox(height: tokens.spacing.space3),
          _TasksStatusBanner(
            banner: banner,
            isSyncing: isSyncing,
            onOpenView: onOpenView,
            onRetrySync: onRetrySync,
            onDismissSyncError: onDismissSyncError,
            onDismissFileRead: onDismissFileRead,
          ),
        ],
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

    final localizations = AppLocalizations.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);
    final isCompact = viewport == UiViewportClass.compact;
    final compactComposerOpen = ref.watch(
      appShellControllerProvider.select((shell) => shell.compactComposerOpen),
    );
    final activeInlineEdit = ref.watch(
      appShellControllerProvider.select((shell) => shell.activeInlineEdit),
    );
    final labelPickerOpen = ref.watch(
      appShellControllerProvider.select((shell) => shell.labelPickerOpen),
    );
    final labelPickerQuery = ref.watch(
      appShellControllerProvider.select((shell) => shell.labelPickerQuery),
    );
    final isBusy = ref.watch(
      taskV2ControllerProvider.select((state) => state.isBusy),
    );
    final selectedLabels = _resolveValidSelectedLabels(
      viewModel.allLabels,
      _draftLabelIds,
    );
    final effectiveSelectedIds = <String>{
      for (final label in selectedLabels) label.id,
    };
    final isPopoverOpen =
        !isCompact && labelPickerOpen && activeInlineEdit == null;

    final placementHint = _quickAddPlacementHint(_placement, localizations);
    final labelsBar = _QuickAddDraftLabelsBar(
      selectedLabels: selectedLabels,
      isPickerOpen: isPopoverOpen,
      isBusy: isBusy,
      onRemoveLabel: _handleToggleDraftLabel,
      onOpenPicker: () => _handleOpenLabelPicker(
        isCompact: isCompact,
        isPopoverOpen: isPopoverOpen,
        viewModel: viewModel,
        selectedIds: effectiveSelectedIds,
      ),
    );
    final popover = isPopoverOpen
        ? _QuickAddLabelPopover(
            allLabels: viewModel.allLabels,
            selectedIds: effectiveSelectedIds,
            hasBothScopedAndGlobal: viewModel.hasBothScopedAndGlobalLabels,
            query: labelPickerQuery,
            onQueryChanged: (query) => ref
                .read(appShellControllerProvider.notifier)
                .setLabelPickerQuery(query),
            onToggleLabel: _handleToggleDraftLabel,
            onCreateAndAssign: _triggerCreateAndAssignLabel,
            onOpenLabelInfo: _handleOpenLabelInfo,
            onClose: () => ref
                .read(appShellControllerProvider.notifier)
                .setLabelPickerOpen(false),
          )
        : null;

    final shellNotifier = ref.read(appShellControllerProvider.notifier);
    return _QuickAddAdaptiveComposer(
      titleController: _titleController,
      titleFocusNode: widget.titleFocusNode,
      headerTitle: viewModel.headerTitle,
      placement: _placement,
      placementHint: placementHint,
      isCompact: isCompact,
      compactComposerOpen: compactComposerOpen,
      isBusy: isBusy,
      isPopoverOpen: isPopoverOpen,
      labelsBar: labelsBar,
      popoverContent: popover,
      onCompactExpandedChanged: shellNotifier.setCompactComposerOpen,
      onPlacementChanged: (nextPlacement) =>
          setState(() => _placement = nextPlacement),
      onDismissPopover: () => shellNotifier.setLabelPickerOpen(false),
      onExpandDraft: () => _handleExpandDraft(effectiveSelectedIds),
      onSubmit: () => _triggerQuickAdd(effectiveSelectedIds),
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
            _draftLabelIds = <String>{..._draftLabelIds, entityId};
          });
        }
      case V2ActionValidationFailed(:final message):
      case V2ActionPersistFailed(:final message):
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

  /// Opens [labelId] inside Labels manager preserving `returnContext`.
  void _handleOpenLabelInfo(String labelId) {
    ref
        .read(appShellControllerProvider.notifier)
        .openEntityInManager(
          EntityRef(kind: EntityKind.label, id: labelId),
          preserveReturnContext: true,
        );
  }

  /// Toggles the upward desktop label popover or presents the compact mobile bottom sheet.
  void _handleOpenLabelPicker({
    required bool isCompact,
    required bool isPopoverOpen,
    required TasksViewModel viewModel,
    required Set<String> selectedIds,
  }) {
    if (!isCompact) {
      final shellNotifier = ref.read(appShellControllerProvider.notifier);
      if (ref.read(appShellControllerProvider).activeInlineEdit != null) {
        shellNotifier.closeInlineEdit();
      }
      shellNotifier.setLabelPickerOpen(!isPopoverOpen);
      return;
    }
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

  /// Submits Quick-Add via [TaskV2Controller.quickAddTask], clearing title ONLY on [V2ActionSucceeded] (`U-CARD-006`).
  Future<void> _handleQuickAdd(Set<String> selectedIds) async {
    final localizations = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final result = await ref
        .read(taskV2ControllerProvider.notifier)
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
      case V2ActionSucceeded():
        _titleController.clear();
      case V2ActionValidationFailed(:final message):
        if (message.isNotEmpty &&
            message != localizations.taskNameErrorDuplicate) {
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(message, tone: NoticeTone.danger);
        }
      case V2ActionPersistFailed(:final message):
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
    final activeTier = ref.watch(
      appShellControllerProvider.select((shell) => shell.activeTier),
    );
    final searchOpen = ref.watch(
      appShellControllerProvider.select((shell) => shell.searchOpen),
    );
    final isTaskDraftOpen = ref.watch(
      appShellControllerProvider.select(
        (shell) => shell.activeDraft == EntityDraftKind.task,
      ),
    );
    final shellNotifier = ref.read(appShellControllerProvider.notifier);
    final padding = tokens.spacing.mainContentPadding(viewport);

    return CustomScrollView(
      key: const ValueKey<String>('tasks_scroll_view'),
      controller: scrollController,
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            0.0,
          ),
          sliver: SliverToBoxAdapter(
            child: _TasksHeaderAndBannersSliver(
              viewModel: viewModel,
              activeTier: activeTier,
              searchOpen: searchOpen,
              isTaskDraftOpen: isTaskDraftOpen,
              isCompact: viewport == UiViewportClass.compact,
              isSyncing: isSyncing,
              onSelectTier: shellNotifier.selectTier,
              onClearActiveFilter: () => shellNotifier.selectLabelFilter(null),
              onOpenView: shellNotifier.openView,
              onRetrySync: onRetrySync,
              onDismissSyncError: shellNotifier.dismissSyncErrorBanner,
              onDismissFileRead: shellNotifier.dismissFileReadBanner,
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            0.0,
            padding.right,
            padding.bottom,
          ),
          sliver: viewModel.tasks.isEmpty && !isTaskDraftOpen
              ? SliverToBoxAdapter(
                  child: UiBanner(
                    key: const ValueKey<String>('tasks_empty_banner'),
                    variant: UiBannerVariant.emptyState,
                    message: viewModel.emptyHint,
                  ),
                )
              : SliverList.builder(
                  itemCount: viewModel.tasks.length,
                  itemBuilder: (context, index) {
                    final task = viewModel.tasks[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index + 1 < viewModel.tasks.length
                            ? tokens.spacing.cardListGap
                            : 0.0,
                      ),
                      child: KeyedSubtree(
                        key: resolveRevealCardKey(task.id),
                        child: TaskCard(
                          key: ValueKey<String>('task_card_${task.id}'),
                          task: task,
                          allLabels: viewModel.allLabels,
                          allLocations: viewModel.allLocations,
                          hasBothScopedAndGlobalLabels:
                              viewModel.hasBothScopedAndGlobalLabels,
                          currentLocalDateTimeHint:
                              viewModel.currentLocalDateTimeHint,
                        ),
                      ),
                    );
                  },
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
      tone: UiV2IconMapper.bannerTone(banner.tone),
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
      (previous, next) {
        if (next != null && next.kind == EntityKind.task) {
          _scheduleRevealTask(next.id);
        }
      },
    );
    ref.listen<EntityDraftKind?>(
      appShellControllerProvider.select((shell) => shell.activeDraft),
      (previous, next) {
        if (next == EntityDraftKind.task && previous != EntityDraftKind.task) {
          _scrollToTop();
        }
      },
    );

    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final viewModel = ref.watch(tasksViewModelProvider);
    final isSyncing = ref.watch(
      syncV2ControllerProvider.select((syncState) => syncState.isBusy),
    );

    if (viewModel.isLoading) {
      return Center(
        child: Padding(
          padding: tokens.spacing.mainContentPadding(
            UiBreakpoints.classify(MediaQuery.sizeOf(context).width),
          ),
          child: UiBanner(
            key: const ValueKey<String>('tasks_loading_banner'),
            variant: UiBannerVariant.loadingState,
            title: localizations.loadingBoardTitle,
            message: localizations.loadingBoardSubtitle,
          ),
        ),
      );
    }

    if (viewModel.fullScreenFileReadError case final errorReport?) {
      return _TasksFullScreenErrorBody(
        errorReport: errorReport,
        isSyncing: isSyncing,
        onOpenSettings: () => ref
            .read(appShellControllerProvider.notifier)
            .openView(ShellView.settings),
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

  /// Triggers immediate synchronization or initial load retry through [SyncV2Controller].
  void _triggerSyncNow() {
    final locale = Localizations.localeOf(context);
    unawaited(
      ref.read(syncV2ControllerProvider.notifier).syncNow(locale: locale),
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
