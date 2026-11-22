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

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/storage_file_read_localization_extension.dart';
import '../../l10n/tier_localization_extension.dart';
import '../../models/app_workspace.dart';
import '../../models/location_state.dart';
import '../../models/storage_file_read_status.dart';
import '../../models/task_board.dart';
import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import '../../models/tdf_error.dart';
import '../../models/tdf_location.dart';
import '../../models/tdf_metadata.dart';
import '../../models/tdf_sync_metadata.dart';
import '../../models/webdav_config.dart';
import '../../providers/board_actions_provider.dart';
import '../../providers/board_providers.dart';
import '../../providers/config_providers.dart';
import '../../providers/entity_actions_provider.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/sync_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../../providers/workspace_providers.dart';
import '../components/ui_quick_composer.dart';
import '../dialogs/compact_label_picker_sheet.dart';
import '../layout/ui_page_header.dart';
import '../primitives/ui_banner.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_pill.dart';
import '../primitives/ui_segmented_control.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../ui_domain_mappers.dart';
import '../widgets/entity_label_picker.dart';
import '../widgets/entity_reveal_scroll_controller.dart';
import 'task_card.dart';
import 'task_draft_card.dart';

/// Operational banner kinds displayed in priority order above the task list (`U-UX-007`).
enum _TasksBannerKind {
  /// WebDAV storage mode selected without complete server configuration.
  unconfiguredWebDav,

  /// `TDF-DEL-003` deletion conflict requiring user resolution.
  deletionConflict,

  /// `TDF-REC-002` generation recovery requiring user resolution.
  recoveryRequired,

  /// Partial file readability error where one active target still loaded cleanly.
  partialFileRead,

  /// Dismissible synchronization or generation rollback error.
  syncError,
}

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
  final FileReadDiagnosticLine line;

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
  final FileReadDiagnosticLine line;

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
  final List<FileReadDiagnosticLine> lines;

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

/// Immutable full-screen file-read or workspace load error descriptor.
@immutable
class _FullScreenFileReadError {
  /// Creates a [_FullScreenFileReadError].
  const _FullScreenFileReadError({
    required this.title,
    required this.summary,
    required this.lines,
  });

  /// Per-target local and remote readability lines.
  final List<FileReadDiagnosticLine> lines;

  /// Localized summary describing the load failure.
  final String summary;

  /// Localized error banner heading.
  final String title;
}

/// Immutable value-equality board slice watched by [_TasksQuickAddDockState].
@immutable
class _QuickAddBoardSlice {
  /// Creates a [_QuickAddBoardSlice].
  const _QuickAddBoardSlice({
    required this.isLoading,
    required this.hasFullError,
    required this.sortedLabels,
    required this.openLabelCounts,
  });

  /// Whether initial board loading failed without cached data.
  final bool hasFullError;

  /// Whether initial board loading is still in progress without cached data.
  final bool isLoading;

  /// Precomputed open task counts keyed by label identifier.
  final Map<String, int> openLabelCounts;

  /// Alphabetically sorted workspace labels.
  final List<TdfLabel> sortedLabels;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _QuickAddBoardSlice &&
        other.isLoading == isLoading &&
        other.hasFullError == hasFullError &&
        listEquals(other.sortedLabels, sortedLabels) &&
        mapEquals(other.openLabelCounts, openLabelCounts);
  }

  @override
  int get hashCode => Object.hash(
    isLoading,
    hasFullError,
    Object.hashAll(sortedLabels),
    Object.hashAllUnordered(
      openLabelCounts.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
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
    final shellNotifier = ref.read(shellProvider.notifier);

    return UiQuickComposer(
      key: const ValueKey<String>('tasks_quick_add_composer'),
      controller: session.titleController,
      focusNode: session.titleFocusNode,
      placeholder: localizations.quickAddHint,
      submitLabel: localizations.actionAdd,
      maxLength: maxTdfTextLength,
      enabled: !isBusy,
      expandDraftLabel: localizations.actionOpenAsDraft,
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

  /// Resolved selected domain labels in alphabetical order.
  final List<TdfLabel> selectedLabels;

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
            colorDot: _resolveLabelColorDot(label.color, tokens),
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
      final shellNotifier = ref.read(shellProvider.notifier);
      if (ref.read(shellProvider).activeInlineEdit != null) {
        shellNotifier.closeInlineEdit();
      }
      shellNotifier.setLabelPickerOpen(!isPopoverOpen);
      return;
    }
    session.onOpenCompactLabelPicker(session.selectedIds);
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
    final shellNotifier = ref.read(shellProvider.notifier);

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
          allLabels: session.allLabels,
          selectedIds: session.selectedIds,
          openCountsByLabelId: session.openLabelCounts,
          showSelectedChips: false,
          autoFocusSearch: true,
          useSharedQuery: true,
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
  final ValueChanged<QuickAddMode> onChanged;

  /// Active placement selection.
  final QuickAddMode placement;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiSegmentedControl<QuickAddMode>(
      key: const ValueKey<String>('quick_add_placement_control'),
      mode: UiSegmentedControlMode.vertical,
      segments: <UiSegment<QuickAddMode>>[
        UiSegment<QuickAddMode>(
          value: QuickAddMode.standard,
          label: localizations.placementQueueOption,
        ),
        UiSegment<QuickAddMode>(
          value: QuickAddMode.priority,
          label: localizations.quickAddPriority,
        ),
        UiSegment<QuickAddMode>(
          value: QuickAddMode.someday,
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
    required this.allLabels,
    required this.openLabelCounts,
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
    required List<TdfLabel> allLabels,
    required Map<String, int> openLabelCounts,
    required QuickAddMode placement,
    required Set<String> draftLabelIds,
    required ValueChanged<QuickAddMode> onPlacementChanged,
    required ValueChanged<String> onToggleDraftLabel,
    required ValueChanged<String> onCreateAndAssignLabel,
    required ValueChanged<String> onOpenLabelInfo,
    required ValueChanged<Set<String>> onOpenCompactLabelPicker,
    required ValueChanged<Set<String>> onExpandDraft,
    required ValueChanged<Set<String>> onSubmit,
  }) {
    final selectedLabels = _resolveValidSelectedLabels(
      allLabels,
      draftLabelIds,
    );
    final selectedIds = <String>{for (final label in selectedLabels) label.id};
    return _QuickAddSession._(
      titleController: titleController,
      titleFocusNode: titleFocusNode,
      allLabels: allLabels,
      openLabelCounts: openLabelCounts,
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

  /// Sorted workspace labels available in the desktop popover.
  final List<TdfLabel> allLabels;

  /// Callback creating and immediately assigning a new workspace label to the draft.
  final ValueChanged<String> onCreateAndAssignLabel;

  /// Callback opening the full uncommitted Task Draft Card.
  final ValueChanged<Set<String>> onExpandDraft;

  /// Callback presenting the compact mobile label picker bottom sheet.
  final ValueChanged<Set<String>> onOpenCompactLabelPicker;

  /// Callback opening a label inside Labels manager.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback updating the selected placement option.
  final ValueChanged<QuickAddMode> onPlacementChanged;

  /// Callback submitting Quick-Add with the resolved selected label identifiers.
  final ValueChanged<Set<String>> onSubmit;

  /// Callback toggling label membership on the Quick-Add draft.
  final ValueChanged<String> onToggleDraftLabel;

  /// Precomputed open task counts keyed by label identifier.
  final Map<String, int> openLabelCounts;

  /// Active placement selection.
  final QuickAddMode placement;

  /// Resolved selected draft label identifiers still present in [allLabels].
  final Set<String> selectedIds;

  /// Resolved selected domain labels in alphabetical order.
  final List<TdfLabel> selectedLabels;

  /// Controller for the Quick-Add title input.
  final TextEditingController titleController;

  /// Optional caller-owned focus node for the title input.
  final FocusNode? titleFocusNode;
}

/// Immutable descriptor for one operational status banner rendered by [_TasksStatusBanners].
@immutable
class _TasksBannerEntry {
  /// Creates a [_TasksBannerEntry].
  const _TasksBannerEntry({
    required this.kind,
    required this.tone,
    required this.message,
    required this.dismissible,
    this.primaryActionLabel,
    this.secondaryActionLabel,
    this.diagnosticLines = const <FileReadDiagnosticLine>[],
  });

  /// Optional structured per-target diagnostics lines for partial file-read errors.
  final List<FileReadDiagnosticLine> diagnosticLines;

  /// Whether the user can dismiss this banner until a new error arrives.
  final bool dismissible;

  /// Operational banner category determining keys and action dispatch.
  final _TasksBannerKind kind;

  /// Primary localized banner message.
  final String message;

  /// Optional primary action button label.
  final String? primaryActionLabel;

  /// Optional secondary action button label.
  final String? secondaryActionLabel;

  /// Design-system semantic banner tone.
  final UiBannerTone tone;
}

/// Immutable per-evaluation snapshot shared across header, draft slot, and lazy task cards.
@immutable
class _TasksBoardContext {
  /// Creates a [_TasksBoardContext].
  const _TasksBoardContext({
    required this.board,
    required this.activeLabelId,
    required this.labelsById,
    required this.locationsById,
    required this.tasksById,
    required this.configuration,
    required this.nowUtc,
    required this.localNow,
    required this.activeFix,
    required this.currentLocalDateTimeHint,
    required this.resolveSearchMatches,
  });

  /// Active foreground GPS fix when status is [LocationStatus.found], or `null`.
  final LocationFix? activeFix;

  /// Active sidebar label filter identifier, or `null` for `All Tasks`.
  final String? activeLabelId;

  /// Evaluated task board snapshot for [activeLabelId].
  final TaskBoard board;

  /// Active workspace configuration supplying timezone and due lead-window settings.
  final WebDavConfig configuration;

  /// Current workspace local wall-clock timestamp formatted for date/time pickers.
  final String currentLocalDateTimeHint;

  /// Lookup map of workspace labels by identifier.
  final Map<String, TdfLabel> labelsById;

  /// Current local wall-clock evaluation timestamp in [configuration]'s timezone.
  final DateTime localNow;

  /// Lookup map of workspace locations by identifier.
  final Map<String, TdfLocation> locationsById;

  /// Current evaluation UTC timestamp.
  final DateTime nowUtc;

  /// Cached Global Search lookup returning matching `(task, tier)` entries for [board].
  final List<_VisibleTaskEntry> Function(String query) resolveSearchMatches;

  /// Lookup map of all workspace tasks by identifier for prerequisite evaluation.
  final Map<String, TaskItem> tasksById;
}

/// Compact viewport tier selector dropdown rendered above [UiPageHeader] when Search is closed.
class _TasksCompactTierSelect extends ConsumerWidget {
  /// Creates a [_TasksCompactTierSelect].
  const _TasksCompactTierSelect({
    required this.board,
    required this.activeTier,
  });

  /// Currently selected domain tier.
  final TaskTier activeTier;

  /// Evaluated board providing per-tier counts.
  final TaskBoard board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiField(
      key: const ValueKey<String>('compact_tier_select'),
      kind: UiFieldKind.select,
      height: tokens.spacing.touchTargetMobile,
      selectValue: activeTier.name,
      selectOptions: <UiSelectOption>[
        for (final tier in TaskTier.values)
          UiSelectOption(
            value: tier.name,
            label:
                '${localizations.tierName(tier)} · ${board.tasksForTier(tier).length}',
          ),
      ],
      semanticLabel: localizations.sectionTasksTitle,
      onSelectChanged: (value) {
        final nextTier = _parseTaskTier(value);
        if (nextTier != null) {
          ref.read(shellProvider.notifier).selectTier(nextTier);
        }
      },
    );
  }
}

/// Narrow-scoped Task Draft Card slot mounted only while [EntityDraftKind.task] is active.
class _TasksDraftCardSlot extends ConsumerWidget {
  /// Creates a [_TasksDraftCardSlot].
  const _TasksDraftCardSlot({required this.boardContext});

  /// Shared evaluated board context supplying labels, locations, open counts, and local timestamp hint.
  final _TasksBoardContext boardContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTaskDraftOpen = ref.watch(
      shellProvider.select(
        (shell) => shell.activeDraft == EntityDraftKind.task,
      ),
    );
    if (!isTaskDraftOpen) {
      return const SizedBox.shrink();
    }
    final tokens = UiThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(height: tokens.spacing.space4),
        TaskDraftCard(
          allLabels: boardContext.board.sortedLabels,
          allLocations: boardContext.board.sortedLocations,
          openLabelCounts: boardContext.board.openTaskCountsByLabel,
          currentLocalDateTimeHint: boardContext.currentLocalDateTimeHint,
        ),
      ],
    );
  }
}

/// Empty-state sliver displayed when the active tier or search view has zero visible tasks.
class _TasksEmptySliver extends StatelessWidget {
  /// Creates a [_TasksEmptySliver].
  const _TasksEmptySliver({required this.activeTier, required this.searchOpen});

  /// Active domain tier when not in Global Search.
  final TaskTier activeTier;

  /// Whether Global Search mode is active.
  final bool searchOpen;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SliverToBoxAdapter(
      child: UiBanner(
        key: const ValueKey<String>('tasks_empty_banner'),
        variant: UiBannerVariant.emptyState,
        message: searchOpen
            ? localizations.searchEmptyHint
            : UiDomainMappers.tierEmptyHint(activeTier, localizations),
      ),
    );
  }
}

/// Full-screen file-read error banner card rendered inside [_TasksFullScreenErrorBody].
class _TasksFullScreenErrorBanner extends StatelessWidget {
  /// Creates a [_TasksFullScreenErrorBanner].
  const _TasksFullScreenErrorBanner({
    required this.errorReport,
    required this.isSyncing,
    required this.onOpenSettings,
    required this.onRetry,
  });

  /// Structured file-read diagnostics report.
  final _FullScreenFileReadError errorReport;

  /// Whether a synchronization retry is currently in flight.
  final bool isSyncing;

  /// Callback navigating to Settings view.
  final VoidCallback onOpenSettings;

  /// Callback retrying file load / sync.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiBanner(
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
    );
  }
}

/// Full-screen file-read error state replacing [TasksView] when all active targets fail (`U-UX-007`).
class _TasksFullScreenErrorBody extends ConsumerWidget {
  /// Creates a [_TasksFullScreenErrorBody].
  const _TasksFullScreenErrorBody({
    required this.errorReport,
    required this.onOpenSettings,
    required this.onRetry,
  });

  /// Structured file-read diagnostics report.
  final _FullScreenFileReadError errorReport;

  /// Callback navigating to Settings view.
  final VoidCallback onOpenSettings;

  /// Callback retrying file load / sync.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);
    final isSyncing = ref.watch(
      syncActionsProvider.select((state) => state.isBusy),
    );

    return Center(
      child: SingleChildScrollView(
        padding: tokens.spacing.mainContentPadding(viewport),
        child: _TasksFullScreenErrorBanner(
          errorReport: errorReport,
          isSyncing: isSyncing,
          onOpenSettings: onOpenSettings,
          onRetry: onRetry,
        ),
      ),
    );
  }
}

/// Top non-card sliver of [TasksView]: page header, decoupled status banners, and optional Task Draft Card.
class _TasksHeaderAndBannersSliver extends StatelessWidget {
  /// Creates a [_TasksHeaderAndBannersSliver].
  const _TasksHeaderAndBannersSliver({
    required this.boardContext,
    required this.isCompact,
    required this.padding,
    required this.onRetrySync,
  });

  /// Shared evaluated board snapshot.
  final _TasksBoardContext boardContext;

  /// Whether viewport is compact (`<= 720`).
  final bool isCompact;

  /// Callback retrying synchronization.
  final VoidCallback onRetrySync;

  /// Outer sliver padding around header, banners, and draft card.
  final EdgeInsets padding;

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
            _TasksPageHeaderSection(
              boardContext: boardContext,
              isCompact: isCompact,
            ),
            _TasksStatusBanners(onRetrySync: onRetrySync),
            _TasksDraftCardSlot(boardContext: boardContext),
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
    required this.tier,
    required this.isSearchMode,
    required this.isLast,
    required this.boardContext,
    required this.revealKey,
  });

  /// Shared evaluated board context providing lookup maps, configuration, and evaluation clock.
  final _TasksBoardContext boardContext;

  /// Whether this item is the last visible task card in the list.
  final bool isLast;

  /// Whether Global Search mode is active.
  final bool isSearchMode;

  /// Stable [GlobalKey] used for post-frame reveal scrolling.
  final GlobalKey revealKey;

  /// Domain task item rendered by this row.
  final TaskItem task;

  /// Evaluated tier containing [task].
  final TaskTier tier;

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
          tier: tier,
          labelsById: boardContext.labelsById,
          locationsById: boardContext.locationsById,
          tasksById: boardContext.tasksById,
          allLabels: boardContext.board.sortedLabels,
          allLocations: boardContext.board.sortedLocations,
          openLabelCounts: boardContext.board.openTaskCountsByLabel,
          isSearchMode: isSearchMode,
          activeLabelId: boardContext.activeLabelId,
          configuration: boardContext.configuration,
          nowUtc: boardContext.nowUtc,
          localNow: boardContext.localNow,
          activeFix: boardContext.activeFix,
        ),
      ),
    );
  }
}

/// Lazy task list or empty-state sliver rendered inside [_TasksScrollableBody].
class _TasksListSliver extends ConsumerWidget {
  /// Creates a [_TasksListSliver].
  const _TasksListSliver({
    required this.boardContext,
    required this.resolveRevealCardKey,
  });

  /// Shared evaluated board snapshot.
  final _TasksBoardContext boardContext;

  /// Callback resolving stable [GlobalKey]s for reveal targeting.
  final GlobalKey Function(String taskId) resolveRevealCardKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shellState = ref.watch(shellProvider.select(_selectListShellSlice));
    final searchQuery = shellState.searchOpen
        ? ref.watch(searchQueryProvider)
        : '';
    final visibleEntries = shellState.searchOpen
        ? boardContext.resolveSearchMatches(searchQuery)
        : _collectTierTasks(boardContext.board, shellState.activeTier);
    if (visibleEntries.isEmpty && !shellState.isTaskDraftOpen) {
      return _TasksEmptySliver(
        activeTier: shellState.activeTier,
        searchOpen: shellState.searchOpen,
      );
    }

    return SliverList.builder(
      itemCount: visibleEntries.length,
      itemBuilder: (context, index) {
        final entry = visibleEntries[index];
        return _TasksListCardItem(
          task: entry.task,
          tier: entry.tier,
          isSearchMode: shellState.searchOpen,
          isLast: index + 1 >= visibleEntries.length,
          boardContext: boardContext,
          revealKey: resolveRevealCardKey(entry.task.id),
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
    required this.boardContext,
    required this.isCompact,
  });

  /// Shared evaluated board snapshot.
  final _TasksBoardContext boardContext;

  /// Whether viewport is compact (`<= 720`).
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final shellState = ref.watch(shellProvider.select(_selectHeaderShellSlice));
    final searchQuery = shellState.searchOpen
        ? ref.watch(searchQueryProvider)
        : '';
    final meta = _computeHeaderMeta(localizations, shellState, searchQuery);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isCompact && !shellState.searchOpen) ...<Widget>[
          _TasksCompactTierSelect(
            board: boardContext.board,
            activeTier: shellState.activeTier,
          ),
          SizedBox(height: tokens.spacing.space3),
        ],
        UiPageHeader(
          key: const ValueKey<String>('tasks_page_header'),
          title: meta.title,
          subtitle: meta.subtitle,
          countLabel: meta.countLabel,
          activeFilterLabel: meta.activeFilterLabel?.name,
          activeFilterTooltip: localizations.activeFilterClearTooltip,
          onClearActiveFilter: meta.activeFilterLabel != null
              ? () => ref.read(shellProvider.notifier).selectLabelFilter(null)
              : null,
          showInlineFilterOnCompact: shellState.searchOpen,
        ),
      ],
    );
  }

  /// Resolves localized title, subtitle, count badge, and active label filter for the header.
  ({
    String title,
    String subtitle,
    String countLabel,
    TdfLabel? activeFilterLabel,
  })
  _computeHeaderMeta(
    AppLocalizations localizations,
    _HeaderShellSlice shellState,
    String searchQuery,
  ) {
    final visibleCount = shellState.searchOpen
        ? boardContext.resolveSearchMatches(searchQuery).length
        : boardContext.board.tasksForTier(shellState.activeTier).length;
    final wipLimit = shellState.searchOpen
        ? null
        : TaskScheduleHelper.tierWipLimit(shellState.activeTier);
    final activeFilterLabel = switch (boardContext.activeLabelId) {
      final labelId? => boardContext.labelsById[labelId],
      null => null,
    };
    return (
      title: shellState.searchOpen
          ? localizations.searchViewTitle
          : localizations.tierName(shellState.activeTier),
      subtitle: shellState.searchOpen
          ? localizations.searchViewSubtitle
          : UiDomainMappers.tierSubtitle(shellState.activeTier, localizations),
      countLabel: wipLimit != null
          ? '$visibleCount / $wipLimit'
          : '$visibleCount',
      activeFilterLabel: activeFilterLabel,
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
      shellProvider.select(
        (shell) => (
          compactComposerOpen: shell.compactComposerOpen,
          hasInlineEdit: shell.activeInlineEdit != null,
          labelPickerOpen: shell.labelPickerOpen,
        ),
      ),
    );
    final isBusy = ref.watch(
      boardActionsProvider.select((state) => state.isBusy),
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
  QuickAddMode _placement = QuickAddMode.standard;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    final initialActiveLabelId = ref.read(shellProvider).activeLabelId;
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
      shellProvider.select((shell) => shell.activeLabelId),
      _handleActiveLabelFilterChanged,
    );
    final hasWorkspaceError = ref.watch(
      activeWorkspaceProvider.select((workspace) => workspace.hasError),
    );
    final boardSlice = ref.watch(
      taskNotifierProvider.select(_selectQuickAddBoardSlice),
    );
    final isTaskDraftOpen = ref.watch(
      shellProvider.select(
        (shell) => shell.activeDraft == EntityDraftKind.task,
      ),
    );
    if (hasWorkspaceError ||
        boardSlice.hasFullError ||
        boardSlice.isLoading ||
        isTaskDraftOpen) {
      return const SizedBox.shrink();
    }
    return _TasksQuickAddDockBody(session: _buildSession(boardSlice));
  }

  /// Creates the [_QuickAddSession] snapshot for the current Quick-Add render pass.
  _QuickAddSession _buildSession(_QuickAddBoardSlice boardSlice) {
    return _QuickAddSession.from(
      titleController: _titleController,
      titleFocusNode: widget.titleFocusNode,
      allLabels: boardSlice.sortedLabels,
      openLabelCounts: boardSlice.openLabelCounts,
      placement: _placement,
      draftLabelIds: _draftLabelIds,
      onPlacementChanged: _handlePlacementChanged,
      onToggleDraftLabel: _handleToggleDraftLabel,
      onCreateAndAssignLabel: _triggerCreateAndAssignLabel,
      onOpenLabelInfo: _handleOpenLabelInfo,
      onOpenCompactLabelPicker: _handleOpenCompactLabelPicker,
      onExpandDraft: _handleExpandDraft,
      onSubmit: _triggerQuickAdd,
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

  /// Creates a new workspace label from [rawName], selects it on the Quick-Add draft, and returns the [ActionResult].
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
            _draftLabelIds = <String>{..._draftLabelIds, entityId};
          });
        }
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

  /// Transfers typed Quick-Add inputs into an uncommitted Task Draft Card and resets composer state (`U-CARD-006`).
  void _handleExpandDraft(Set<String> selectedIds) {
    final seedTitle = _titleController.text;
    final seedPlacement = _placement;
    final seedLabelIds = selectedIds.toList(growable: false);
    final activeLabelId = ref.read(shellProvider).activeLabelId;
    ref
        .read(shellProvider.notifier)
        .openDraft(
          EntityDraftKind.task,
          seedTitle: seedTitle,
          seedPlacement: seedPlacement,
          seedLabelIds: seedLabelIds,
        );
    setState(() {
      _titleController.clear();
      _placement = QuickAddMode.standard;
      _draftLabelIds = activeLabelId != null
          ? <String>{activeLabelId}
          : <String>{};
    });
  }

  /// Presents the compact mobile label picker bottom sheet for the Quick-Add draft.
  void _handleOpenCompactLabelPicker(Set<String> selectedIds) {
    final localizations = AppLocalizations.of(context);
    unawaited(
      showCompactLabelPickerSheet(
        context,
        title: localizations.taskLabelsSectionTitle,
        initialSelectedLabelIds: selectedIds,
        onToggleLabel: _handleToggleDraftLabel,
        onCreateLabel: _handleCreateAndAssignLabel,
        onOpenLabelInfo: _handleOpenLabelInfo,
      ),
    );
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

  /// Updates the active Quick-Add placement option.
  void _handlePlacementChanged(QuickAddMode nextPlacement) {
    setState(() => _placement = nextPlacement);
  }

  /// Submits Quick-Add via [BoardActionsNotifier.quickAddTask], clearing title ONLY on [ActionSucceeded] (`U-CARD-006`).
  Future<void> _handleQuickAdd(Set<String> selectedIds) async {
    final localizations = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final result = await ref
        .read(boardActionsProvider.notifier)
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
              .read(floatingNoticeProvider.notifier)
              .showNotice(message, tone: FloatingNoticeTone.danger);
        }
      case ActionPersistFailed(:final message):
        if (message.isNotEmpty) {
          ref
              .read(floatingNoticeProvider.notifier)
              .showNotice(message, tone: FloatingNoticeTone.danger);
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
class _TasksScrollableBody extends StatelessWidget {
  /// Creates a [_TasksScrollableBody].
  const _TasksScrollableBody({
    required this.scrollController,
    required this.boardContext,
    required this.resolveRevealCardKey,
    required this.onRetrySync,
  });

  /// Shared evaluated board snapshot.
  final _TasksBoardContext boardContext;

  /// Callback retrying synchronization from status banners.
  final VoidCallback onRetrySync;

  /// Callback resolving stable [GlobalKey]s for reveal targeting.
  final GlobalKey Function(String taskId) resolveRevealCardKey;

  /// Optional caller-owned scroll controller.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);
    final padding = tokens.spacing.mainContentPadding(viewport);

    return CustomScrollView(
      key: const ValueKey<String>('tasks_scroll_view'),
      controller: scrollController,
      slivers: <Widget>[
        _TasksHeaderAndBannersSliver(
          boardContext: boardContext,
          isCompact: viewport == UiViewportClass.compact,
          padding: padding.copyWith(bottom: 0.0),
          onRetrySync: onRetrySync,
        ),
        SliverPadding(
          padding: padding.copyWith(top: 0.0),
          sliver: _TasksListSliver(
            boardContext: boardContext,
            resolveRevealCardKey: resolveRevealCardKey,
          ),
        ),
      ],
    );
  }
}

/// Renders one operational [_TasksBannerEntry] mapped to its design-system [UiBanner] and actions (`U-UX-007`).
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

  /// Operational banner descriptor.
  final _TasksBannerEntry banner;

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
      tone: banner.tone,
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
      _TasksBannerKind.unconfiguredWebDav => <Widget>[
        UiButton(
          label: banner.primaryActionLabel ?? localizations.actionConfigure,
          density: UiButtonDensity.compact,
          onPressed: () => onOpenView(ShellView.settings),
        ),
      ],
      _TasksBannerKind.syncError ||
      _TasksBannerKind.partialFileRead => <Widget>[
        UiButton(
          label: banner.primaryActionLabel ?? localizations.actionRetry,
          density: UiButtonDensity.compact,
          isLoading: isSyncing,
          onPressed: isSyncing ? null : onRetrySync,
        ),
        UiButton(
          label: banner.secondaryActionLabel ?? localizations.actionSettings,
          density: UiButtonDensity.compact,
          onPressed: () => onOpenView(ShellView.settings),
        ),
      ],
      _TasksBannerKind.deletionConflict => <Widget>[
        UiButton(
          label:
              banner.primaryActionLabel ?? localizations.actionResolveConflict,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          onPressed: () => onOpenView(ShellView.conflict),
        ),
      ],
      _TasksBannerKind.recoveryRequired => <Widget>[
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
      _TasksBannerKind.syncError => onDismissSyncError,
      _TasksBannerKind.partialFileRead => onDismissFileRead,
      _TasksBannerKind.unconfiguredWebDav ||
      _TasksBannerKind.deletionConflict ||
      _TasksBannerKind.recoveryRequired => null,
    };
  }
}

/// Decoupled status banner stack watching sync, WebDAV config, and banner dismissal slices independently of the task list.
class _TasksStatusBanners extends ConsumerWidget {
  /// Creates a [_TasksStatusBanners].
  const _TasksStatusBanners({required this.onRetrySync});

  /// Callback triggering immediate synchronization retry.
  final VoidCallback onRetrySync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final isSyncing = ref.watch(
      syncActionsProvider.select((state) => state.isBusy),
    );
    final banners = _buildStatusBanners(
      syncSlice: ref.watch(syncStateProvider.select(_selectSyncBannerSlice)),
      webDavSlice: ref.watch(
        webDavConfigProvider.select(_selectWebDavBannerSlice),
      ),
      shellSlice: ref.watch(shellProvider.select(_selectBannerShellSlice)),
      localizations: localizations,
    );
    if (banners.isEmpty) {
      return const SizedBox.shrink();
    }
    final shellNotifier = ref.read(shellProvider.notifier);

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

/// Manages smooth entity reveal scrolling, draft scroll-to-top, memoized lookups, and pruned card keys for [TasksView].
class _TasksViewState extends ConsumerState<TasksView>
    with EntityRevealScrollMixin<TasksView> {
  Map<String, TdfLabel> _cachedLabelsById = const <String, TdfLabel>{};
  Map<String, TdfLocation> _cachedLocationsById = const <String, TdfLocation>{};
  TaskBoard? _cachedLookupBoard;
  TaskBoard? _cachedSearchBoard;
  List<_VisibleTaskEntry> _cachedSearchMatches = const <_VisibleTaskEntry>[];
  String? _cachedSearchNeedle;
  Map<String, TaskItem> _cachedTasksById = const <String, TaskItem>{};

  @override
  ScrollController? get externalScrollController => widget.scrollController;

  @override
  GlobalKey Function(String entityId)? get revealCardKeyBuilder =>
      widget.revealCardKeyBuilder;

  @override
  EntityDraftKind get revealDraftKind => EntityDraftKind.task;

  @override
  EntityKind get revealEntityKind => EntityKind.task;

  @override
  void initState() {
    super.initState();
    initRevealScroll();
  }

  @override
  void didUpdateWidget(covariant TasksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    handleScrollControllerSwap(oldWidget.scrollController);
  }

  @override
  void dispose() {
    disposeRevealScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _registerShellListeners();
    final activeLabelId = ref.watch(
      shellProvider.select((shell) => shell.activeLabelId),
    );
    final workspaceError = ref.watch(
      activeWorkspaceProvider.select(_selectWorkspaceError),
    );
    final evaluatedAsync = ref.watch(evaluatedBoardProvider(activeLabelId));
    final fullScreenError = _resolveFullScreenFileReadError(
      evaluatedAsync: evaluatedAsync,
      workspaceError: workspaceError,
      localizations: AppLocalizations.of(context),
    );
    if (fullScreenError == null &&
        evaluatedAsync.isLoading &&
        !evaluatedAsync.hasValue) {
      schedulePruneOwnedCardKeys();
      return const _TasksLoadingBody();
    }
    if (fullScreenError case final errorReport?) {
      schedulePruneOwnedCardKeys();
      return _TasksFullScreenErrorBody(
        errorReport: errorReport,
        onOpenSettings: _openSettings,
        onRetry: _triggerSyncNow,
      );
    }
    return _TasksScrollableBody(
      scrollController: effectiveScrollController,
      boardContext: _buildBoardContext(
        board: evaluatedAsync.asData?.value ?? TaskBoard.empty(),
        activeLabelId: activeLabelId,
      ),
      resolveRevealCardKey: resolveRevealCardKey,
      onRetrySync: _triggerSyncNow,
    );
  }

  @override
  List<String> collectVisibleEntityIds() {
    final visibleEntries = _collectCurrentVisibleTasks();
    return <String>[for (final entry in visibleEntries) entry.task.id];
  }

  /// Builds the shared [_TasksBoardContext] snapshot for the current evaluated [board], reusing memoized lookup maps.
  _TasksBoardContext _buildBoardContext({
    required TaskBoard board,
    required String? activeLabelId,
  }) {
    _syncLookupCache(board);
    final configuration = _readCurrentConfig(ref);
    final nowUtc = ref.read(clockProvider)().toUtc();
    final locationState = ref.read(locationStateProvider);
    final activeFix = locationState.status == LocationStatus.found
        ? locationState.fix
        : null;
    return _TasksBoardContext(
      board: board,
      activeLabelId: activeLabelId,
      labelsById: _cachedLabelsById,
      locationsById: _cachedLocationsById,
      tasksById: _cachedTasksById,
      configuration: configuration,
      nowUtc: nowUtc,
      localNow: configuration.toLocalWallClock(nowUtc),
      activeFix: activeFix,
      currentLocalDateTimeHint: TaskScheduleHelper.formatLocalTimestamp(
        nowUtc,
        configuration,
      ),
      resolveSearchMatches: (query) => _resolveSearchMatches(board, query),
    );
  }

  /// Collects the currently visible task entries matching active tier or Global Search state.
  List<_VisibleTaskEntry> _collectCurrentVisibleTasks() {
    final shellState = ref.read(shellProvider);
    final board =
        ref
            .read(evaluatedBoardProvider(shellState.activeLabelId))
            .asData
            ?.value ??
        TaskBoard.empty();
    if (shellState.searchOpen) {
      return _resolveSearchMatches(board, ref.read(searchQueryProvider));
    }
    return _collectTierTasks(board, shellState.activeTier);
  }

  /// Opens the Settings view from the full-screen file-read error banner.
  void _openSettings() {
    ref.read(shellProvider.notifier).openView(ShellView.settings);
  }

  /// Registers reveal, draft-open, and list-scope listeners for [TasksView].
  void _registerShellListeners() {
    registerRevealShellListeners();
    ref.listen<({TaskTier tier, bool searchOpen, String? labelId})>(
      shellProvider.select(
        (shell) => (
          tier: shell.activeTier,
          searchOpen: shell.searchOpen,
          labelId: shell.activeLabelId,
        ),
      ),
      (previous, next) {
        if (previous != null && previous != next) {
          schedulePruneOwnedCardKeys();
        }
      },
    );
    ref.listen<String>(searchQueryProvider, (_, _) {
      if (hasOwnedCardKeys) {
        schedulePruneOwnedCardKeys();
      }
    });
  }

  /// Returns cached Global Search matches for [board] and [query], scanning all tiers at most once per pair.
  List<_VisibleTaskEntry> _resolveSearchMatches(TaskBoard board, String query) {
    final needle = query.trim().toLowerCase();
    if (identical(_cachedSearchBoard, board) && _cachedSearchNeedle == needle) {
      return _cachedSearchMatches;
    }
    final matches = _collectSearchMatches(board, needle);
    _cachedSearchBoard = board;
    _cachedSearchNeedle = needle;
    _cachedSearchMatches = matches;
    return matches;
  }

  /// Refreshes memoized board lookup maps when [board] changes identity and schedules stale key pruning.
  void _syncLookupCache(TaskBoard board) {
    if (identical(_cachedLookupBoard, board)) {
      return;
    }
    _cachedLookupBoard = board;
    _cachedLabelsById = Map<String, TdfLabel>.unmodifiable(<String, TdfLabel>{
      for (final label in board.labels) label.id: label,
    });
    _cachedLocationsById = Map<String, TdfLocation>.unmodifiable(
      <String, TdfLocation>{
        for (final location in board.locations) location.id: location,
      },
    );
    _cachedTasksById = Map<String, TaskItem>.unmodifiable(<String, TaskItem>{
      for (final task in board.allTasks) task.id: task,
    });
    schedulePruneOwnedCardKeys();
  }

  /// Triggers immediate synchronization or initial load retry through [SyncActionsNotifier].
  void _triggerSyncNow() {
    final locale = Localizations.localeOf(context);
    unawaited(ref.read(syncActionsProvider.notifier).syncNow(locale: locale));
  }
}

/// Narrow shell banner-suppression and dismissal slice watched by [_TasksStatusBanners].
typedef _BannerShellSlice = ({
  bool syncErrorDismissed,
  bool fileReadDismissed,
  ShellView activeView,
});

/// Narrow shell tier and search-mode slice watched by [_TasksPageHeaderSection].
typedef _HeaderShellSlice = ({TaskTier activeTier, bool searchOpen});

/// Narrow shell tier, search-mode, and draft slice watched by [_TasksListSliver].
typedef _ListShellSlice = ({
  TaskTier activeTier,
  bool searchOpen,
  bool isTaskDraftOpen,
});

/// Narrow sync state slice watched by [_TasksStatusBanners].
typedef _SyncBannerSlice = ({
  bool hasOpenConflict,
  TdfSyncOutcomeException? syncOutcome,
  StorageFileReadReport? fileReadReport,
  String? errorMessage,
});

/// Paired task item and evaluated tier displayed in [_TasksListSliver].
typedef _VisibleTaskEntry = ({TaskItem task, TaskTier tier});

/// Narrow WebDAV readiness slice watched by [_TasksStatusBanners].
typedef _WebDavBannerSlice = ({bool usesWebDav, bool isConfigured});

/// Appends tasks in [tierTasks] matching lowercase [needle] into [results].
void _appendTierSearchMatches(
  List<TaskItem> tierTasks,
  TaskTier tier,
  String needle,
  List<_VisibleTaskEntry> results,
) {
  for (final task in tierTasks) {
    if (needle.isEmpty || _matchesSearchQuery(task, needle)) {
      results.add((task: task, tier: tier));
    }
  }
}

/// Builds the ordered operational status banners for [TasksView] (`U-UX-007`).
List<_TasksBannerEntry> _buildStatusBanners({
  required _SyncBannerSlice syncSlice,
  required _WebDavBannerSlice webDavSlice,
  required _BannerShellSlice shellSlice,
  required AppLocalizations localizations,
}) {
  final banners = <_TasksBannerEntry>[];
  if (webDavSlice.usesWebDav && !webDavSlice.isConfigured) {
    banners.add(
      _TasksBannerEntry(
        kind: _TasksBannerKind.unconfiguredWebDav,
        tone: UiBannerTone.warning,
        message: localizations.unconfiguredBannerText,
        dismissible: false,
        primaryActionLabel: localizations.actionConfigure,
      ),
    );
  }
  final syncOutcome = syncSlice.syncOutcome;
  final errorMessage = syncSlice.errorMessage;
  if (syncSlice.hasOpenConflict && syncOutcome != null) {
    switch (syncOutcome.kind) {
      case TdfSyncOutcomeKind.deletionConflict:
        if (shellSlice.activeView != ShellView.conflict) {
          banners.add(
            _TasksBannerEntry(
              kind: _TasksBannerKind.deletionConflict,
              tone: UiBannerTone.warning,
              message: errorMessage ?? localizations.syncConflictDeletionBanner,
              dismissible: false,
              primaryActionLabel: localizations.actionResolveConflict,
            ),
          );
        }
      case TdfSyncOutcomeKind.recoveryRequired:
        if (shellSlice.activeView != ShellView.recovery) {
          banners.add(
            _TasksBannerEntry(
              kind: _TasksBannerKind.recoveryRequired,
              tone: UiBannerTone.warning,
              message: errorMessage ?? localizations.syncConflictRecoveryBanner,
              dismissible: false,
              primaryActionLabel: localizations.actionResolveRecovery,
            ),
          );
        }
      case TdfSyncOutcomeKind.syncGenerationRollback:
        if (!shellSlice.syncErrorDismissed) {
          banners.add(
            _TasksBannerEntry(
              kind: _TasksBannerKind.syncError,
              tone: UiBannerTone.danger,
              message:
                  errorMessage ??
                  localizations.syncErrorGenerationRollbackBanner,
              dismissible: true,
              primaryActionLabel: localizations.actionRetry,
              secondaryActionLabel: localizations.actionSettings,
            ),
          );
        }
    }
  } else if (syncSlice.fileReadReport case final report?) {
    if (!shellSlice.fileReadDismissed && report.hasFailure) {
      final scope = report.failureScope;
      banners.add(
        _TasksBannerEntry(
          kind: _TasksBannerKind.partialFileRead,
          tone: UiBannerTone.danger,
          message: scope != null
              ? localizations.storageFileReadSummary(scope)
              : localizations.fileReadErrorTitle,
          dismissible: true,
          primaryActionLabel: localizations.actionRetry,
          secondaryActionLabel: localizations.actionSettings,
          diagnosticLines: TaskScheduleHelper.formatFileReadDiagnosticLines(
            report,
            localizations,
          ),
        ),
      );
    }
  } else if (errorMessage case final currentErrorMessage?) {
    if (!shellSlice.syncErrorDismissed && currentErrorMessage.isNotEmpty) {
      banners.add(
        _TasksBannerEntry(
          kind: _TasksBannerKind.syncError,
          tone: UiBannerTone.danger,
          message: currentErrorMessage,
          dismissible: true,
          primaryActionLabel: localizations.actionRetry,
          secondaryActionLabel: localizations.actionSettings,
        ),
      );
    }
  }
  return banners;
}

/// Collects matching `(task, tier)` entries across all six tiers for lowercase [needle].
List<_VisibleTaskEntry> _collectSearchMatches(TaskBoard board, String needle) {
  final results = <_VisibleTaskEntry>[];
  for (final tier in TaskTier.values) {
    _appendTierSearchMatches(board.tasksForTier(tier), tier, needle, results);
  }
  return List<_VisibleTaskEntry>.unmodifiable(results);
}

/// Collects `(task, tier)` entries for a single [activeTier].
List<_VisibleTaskEntry> _collectTierTasks(
  TaskBoard board,
  TaskTier activeTier,
) {
  final tasks = board.tasksForTier(activeTier);
  return <_VisibleTaskEntry>[
    for (final task in tasks) (task: task, tier: activeTier),
  ];
}

/// Checks whether [task] matches lowercase Global Search query [needle].
bool _matchesSearchQuery(TaskItem task, String needle) {
  if (task.title.toLowerCase().contains(needle)) {
    return true;
  }
  if (task.note?.toLowerCase().contains(needle) ?? false) {
    return true;
  }
  for (final subtask in task.subtasks) {
    if (subtask.title.toLowerCase().contains(needle)) {
      return true;
    }
  }
  for (final link in task.links) {
    if (link.title.toLowerCase().contains(needle) ||
        link.uri.toLowerCase().contains(needle)) {
      return true;
    }
  }
  return false;
}

/// Parses a serialized [TaskTier] name safely without unchecked casts.
TaskTier? _parseTaskTier(String value) {
  for (final tier in TaskTier.values) {
    if (tier.name == value) {
      return tier;
    }
  }
  return null;
}

/// Returns the localized helper caption describing [placement] in [TasksQuickAddDock].
String _quickAddPlacementHint(
  QuickAddMode placement,
  AppLocalizations localizations,
) {
  return switch (placement) {
    QuickAddMode.standard => localizations.placementQueueHint,
    QuickAddMode.priority => localizations.placementPriorityHint,
    QuickAddMode.someday => localizations.placementSomedayHint,
  };
}

/// Reads the current [WebDavConfig] synchronously from [ref] with workspace fallback.
WebDavConfig _readCurrentConfig(WidgetRef ref) {
  return ref.read(webDavConfigProvider).asData?.value ??
      ref.read(activeWorkspaceProvider).asData?.value.config ??
      const WebDavConfig();
}

/// Resolves a full-screen file-read or workspace error descriptor when initial load fails.
_FullScreenFileReadError? _resolveFullScreenFileReadError({
  required AsyncValue<TaskBoard> evaluatedAsync,
  required Object? workspaceError,
  required AppLocalizations localizations,
}) {
  final error =
      workspaceError ??
      ((evaluatedAsync.hasError && !evaluatedAsync.hasValue)
          ? evaluatedAsync.error
          : null);
  if (error == null) {
    return null;
  }
  if (error is StorageFileReadException) {
    final report = error.report;
    final scope = report.failureScope;
    return _FullScreenFileReadError(
      title: localizations.fileReadErrorTitle,
      summary: scope != null
          ? localizations.storageFileReadSummary(scope)
          : localizations.fileReadErrorTitle,
      lines: TaskScheduleHelper.formatFileReadDiagnosticLines(
        report,
        localizations,
      ),
    );
  }
  if (error is WorkspaceException) {
    return _FullScreenFileReadError(
      title: localizations.fileReadErrorTitle,
      summary: localizations.localizeWorkspaceError(error),
      lines: const <FileReadDiagnosticLine>[],
    );
  }
  return _FullScreenFileReadError(
    title: localizations.fileReadErrorTitle,
    summary: TaskScheduleHelper.formatSyncError(error, localizations),
    lines: const <FileReadDiagnosticLine>[],
  );
}

/// Resolves an optional `#RRGGBB` label color string, falling back to `tokens.colors.accent`.
Color _resolveLabelColorDot(String? colorHex, UiThemeTokens tokens) {
  return switch (TaskScheduleHelper.parseLabelColorValue(colorHex)) {
    final value? => Color(value),
    null => tokens.colors.accent,
  };
}

/// Resolves selected [TdfLabel] entries still present in [allLabels].
List<TdfLabel> _resolveValidSelectedLabels(
  List<TdfLabel> allLabels,
  Set<String> selectedIds,
) {
  return <TdfLabel>[
    for (final label in allLabels)
      if (selectedIds.contains(label.id)) label,
  ];
}

/// Extracts banner dismissal and conflict/recovery suppression view state from [shell].
_BannerShellSlice _selectBannerShellSlice(ShellState shell) {
  return (
    syncErrorDismissed: shell.syncErrorBannerDismissed,
    fileReadDismissed: shell.fileReadBannerDismissed,
    activeView:
        shell.view == ShellView.conflict || shell.view == ShellView.recovery
        ? shell.view
        : ShellView.tasks,
  );
}

/// Extracts active tier and search state from [shell] for [_TasksPageHeaderSection].
_HeaderShellSlice _selectHeaderShellSlice(ShellState shell) {
  return (activeTier: shell.activeTier, searchOpen: shell.searchOpen);
}

/// Extracts active tier, search state, and task draft flag from [shell] for [_TasksListSliver].
_ListShellSlice _selectListShellSlice(ShellState shell) {
  return (
    activeTier: shell.activeTier,
    searchOpen: shell.searchOpen,
    isTaskDraftOpen: shell.activeDraft == EntityDraftKind.task,
  );
}

/// Extracts Quick-Add load status, sorted labels, and open label counts from [boardAsync].
_QuickAddBoardSlice _selectQuickAddBoardSlice(
  AsyncValue<TaskBoard> boardAsync,
) {
  final board = boardAsync.asData?.value;
  return _QuickAddBoardSlice(
    isLoading: boardAsync.isLoading && !boardAsync.hasValue,
    hasFullError: boardAsync.hasError && !boardAsync.hasValue,
    sortedLabels: board?.sortedLabels ?? const <TdfLabel>[],
    openLabelCounts: board?.openTaskCountsByLabel ?? const <String, int>{},
  );
}

/// Extracts operational banner fields from [syncState].
_SyncBannerSlice _selectSyncBannerSlice(SyncState syncState) {
  return (
    hasOpenConflict: syncState.hasOpenConflict,
    syncOutcome: syncState.syncOutcome,
    fileReadReport: syncState.fileReadReport,
    errorMessage: syncState.errorMessage,
  );
}

/// Extracts WebDAV usage and readiness flags from [asyncConfig].
_WebDavBannerSlice _selectWebDavBannerSlice(
  AsyncValue<WebDavConfig> asyncConfig,
) {
  final config = asyncConfig.asData?.value ?? const WebDavConfig();
  return (
    usesWebDav: config.storageMode.usesWebDav,
    isConfigured: config.isWebDavConfigured,
  );
}

/// Extracts the error object from [workspace] when active workspace loading failed.
Object? _selectWorkspaceError(AsyncValue<AppWorkspace> workspace) {
  return workspace.hasError ? workspace.error : null;
}
