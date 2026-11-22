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
import '../../models/task_board.dart';
import '../../models/task_board_evaluator.dart';
import '../../models/tdf_error.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../../providers/ui_telemetry.dart';
import '../components/ui_dialog_frame.dart';
import '../components/ui_searchable_picker.dart';
import '../tokens/ui_theme_tokens.dart';

/// Scope filter identifier showing all workspace labels inside [CompactLabelPickerSheet].
const String _labelScopeAll = 'all';

/// Scope filter identifier showing only global context labels inside [CompactLabelPickerSheet].
const String _labelScopeGlobal = 'global';

/// Scope filter identifier showing only scoped queue labels inside [CompactLabelPickerSheet].
const String _labelScopeScoped = 'scoped';

/// Live Riverpod-backed compact mobile label picker bottom sheet (`U-A11Y-003`).
///
/// Watches [taskNotifierProvider] for live workspace labels and, when [taskId] is non-null,
/// for live task label assignments. When [taskId] is `null`, tracks draft selections seeded
/// from [initialSelectedLabelIds] and real label IDs returned by [onCreateLabel].
class CompactLabelPickerSheet extends ConsumerStatefulWidget {
  /// Creates a [CompactLabelPickerSheet].
  const CompactLabelPickerSheet({
    super.key,
    this.taskId,
    this.initialSelectedLabelIds = const <String>{},
    required this.onToggleLabel,
    required this.onCreateLabel,
    required this.onOpenLabelInfo,
    required this.onRequestClose,
  });

  /// Initial selected label identifiers used in uncommitted draft mode (`taskId == null`).
  final Set<String> initialSelectedLabelIds;

  /// Async callback creating a new label by name and returning its [ActionResult].
  final Future<ActionResult> Function(String rawName) onCreateLabel;

  /// Callback navigating to the label manager card for a label identifier.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback closing the active bottom sheet route.
  final VoidCallback onRequestClose;

  /// Callback toggling selection of an existing label identifier.
  final ValueChanged<String> onToggleLabel;

  /// Optional persisted task identifier whose assigned labels are watched live from [taskNotifierProvider].
  final String? taskId;

  @override
  ConsumerState<CompactLabelPickerSheet> createState() =>
      _CompactLabelPickerSheetState();
}

/// Manages live label projection, scope filtering, and inline creation inside [CompactLabelPickerSheet].
class _CompactLabelPickerSheetState
    extends ConsumerState<CompactLabelPickerSheet> {
  String _activeScopeId = _labelScopeAll;
  late Set<String> _draftSelectedIds;
  bool _isCreating = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _draftSelectedIds = Set<String>.of(widget.initialSelectedLabelIds);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final board = ref.watch(
      taskNotifierProvider.select((asyncBoard) => asyncBoard.asData?.value),
    );
    final snapshot = _buildPickerSnapshot(
      board: board,
      localizations: localizations,
      tokens: UiThemeTokens.of(context),
    );

    return UiSearchablePicker<String>(
      key: const ValueKey<String>('compact_label_picker'),
      options: snapshot.options,
      selectedIds: snapshot.selectedIds,
      selectionMode: UiPickerSelectionMode.multiple,
      isCompactSheet: true,
      autoFocusSearch: false,
      searchMaxLength: maxTdfTextLength,
      query: _query,
      onQueryChanged: _handleQueryChanged,
      searchPlaceholder: localizations.labelPickerSearchPlaceholder,
      searchClearTooltip: localizations.tooltipClearSearch,
      scopeFilters: snapshot.scopeFilters,
      activeScopeId: snapshot.effectiveScopeId,
      onScopeChanged: _handleScopeChanged,
      emptyText: snapshot.emptyText,
      infoTooltip: localizations.openLabelInManagerTooltip,
      onToggleOption: _handleToggleOption,
      onOptionInfo: _handleOptionInfo,
      removeChipTooltip: (option) =>
          localizations.labelPickerRemoveTooltip(option.label),
      inlineCreateLabel: localizations.labelPickerCreateAndAssign,
      onInlineCreate: snapshot.hasDuplicate ? null : _triggerInlineCreate,
      onRequestClose: widget.onRequestClose,
    );
  }

  /// Builds picker option rows filtered by [effectiveScopeId] from live workspace [labels].
  List<UiPickerOption<String>> _buildOptions({
    required TaskBoard? board,
    required List<TdfLabel> labels,
    required String effectiveScopeId,
    required AppLocalizations localizations,
    required UiThemeTokens tokens,
  }) {
    final options = <UiPickerOption<String>>[];
    for (final label in labels) {
      if (effectiveScopeId == _labelScopeScoped && !label.isScoped) {
        continue;
      }
      if (effectiveScopeId == _labelScopeGlobal && label.isScoped) {
        continue;
      }
      final colorDot = switch (TaskScheduleHelper.parseLabelColorValue(
        label.color,
      )) {
        final value? => Color(value),
        null => tokens.colors.accent,
      };
      final openCount = board?.openTaskCountForLabel(label.id) ?? 0;
      options.add(
        UiPickerOption<String>(
          id: label.id,
          value: label.id,
          label: label.name,
          colorDot: colorDot,
          badgeLabel: label.isScoped ? localizations.scopedQueueLabel : null,
          countLabel: localizations.openTasksCountPill('$openCount'),
          hasInfoAction: true,
        ),
      );
    }
    return options;
  }

  /// Computes the live sorted options, scope filters, and selected label IDs from [board].
  _CompactLabelPickerSnapshot _buildPickerSnapshot({
    required TaskBoard? board,
    required AppLocalizations localizations,
    required UiThemeTokens tokens,
  }) {
    final sortedLabels = board == null
        ? const <TdfLabel>[]
        : TaskBoardEvaluator.sortLabelsAlphabetically(board.labels);
    final scopedCount = _countScopedLabels(sortedLabels);
    final hasBothScopes = scopedCount > 0 && scopedCount < sortedLabels.length;
    final effectiveScopeId = hasBothScopes ? _activeScopeId : _labelScopeAll;
    return (
      effectiveScopeId: effectiveScopeId,
      emptyText: sortedLabels.isEmpty
          ? localizations.labelPickerEmptyHint
          : localizations.labelPickerNoMatches,
      hasDuplicate: board?.hasDuplicateLabelName(_query) ?? false,
      options: _buildOptions(
        board: board,
        labels: sortedLabels,
        effectiveScopeId: effectiveScopeId,
        localizations: localizations,
        tokens: tokens,
      ),
      scopeFilters: hasBothScopes
          ? _buildScopeFilters(
              localizations: localizations,
              totalCount: sortedLabels.length,
              scopedCount: scopedCount,
            )
          : const <UiPickerScopeFilter>[],
      selectedIds: _resolveSelectedIds(board),
    );
  }

  /// Builds conditional `All`, `Scoped`, and `Global` filter pills when both scopes exist.
  List<UiPickerScopeFilter> _buildScopeFilters({
    required AppLocalizations localizations,
    required int totalCount,
    required int scopedCount,
  }) {
    final globalCount = totalCount - scopedCount;
    return <UiPickerScopeFilter>[
      UiPickerScopeFilter(
        id: _labelScopeAll,
        label: localizations.labelPickerFilterAll('$totalCount'),
      ),
      UiPickerScopeFilter(
        id: _labelScopeScoped,
        label: localizations.labelPickerFilterScoped('$scopedCount'),
      ),
      UiPickerScopeFilter(
        id: _labelScopeGlobal,
        label: localizations.labelPickerFilterGlobal('$globalCount'),
      ),
    ];
  }

  /// Creates a new real label via [CompactLabelPickerSheet.onCreateLabel] and selects its committed ID.
  Future<void> _handleInlineCreate(String rawName) async {
    if (_isCreating) {
      return;
    }
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _isCreating = true;
    try {
      final result = await widget.onCreateLabel(trimmed);
      if (!mounted) {
        return;
      }
      switch (result) {
        case ActionSucceeded(:final entityId):
          setState(() {
            if (widget.taskId == null && entityId != null) {
              _draftSelectedIds = <String>{..._draftSelectedIds, entityId};
            }
            _query = '';
            if (_activeScopeId == _labelScopeScoped) {
              _activeScopeId = _labelScopeAll;
            }
          });
        case ActionValidationFailed():
        case ActionPersistFailed():
          break;
      }
    } finally {
      _isCreating = false;
    }
  }

  /// Closes the bottom sheet and notifies the caller to inspect [option] in Labels manager.
  void _handleOptionInfo(UiPickerOption<String> option) {
    widget.onOpenLabelInfo(option.value);
    widget.onRequestClose();
  }

  /// Updates the controlled search query inside the sheet.
  void _handleQueryChanged(String nextQuery) {
    setState(() => _query = nextQuery);
  }

  /// Switches the active scope filter pill.
  void _handleScopeChanged(String nextScopeId) {
    setState(() => _activeScopeId = nextScopeId);
  }

  /// Updates draft selection when `taskId == null` and forwards the toggled label ID to the caller.
  void _handleToggleOption(UiPickerOption<String> option) {
    if (widget.taskId == null) {
      final nextSelected = Set<String>.of(_draftSelectedIds);
      if (!nextSelected.add(option.id)) {
        nextSelected.remove(option.id);
      }
      setState(() => _draftSelectedIds = nextSelected);
    }
    widget.onToggleLabel(option.value);
  }

  /// Resolves the live selected label ID set from [board] in task mode or [_draftSelectedIds] in draft mode.
  Set<String> _resolveSelectedIds(TaskBoard? board) {
    if (widget.taskId case final targetTaskId?) {
      final assignedIds = board?.findTask(targetTaskId)?.labelIds;
      if (assignedIds == null || assignedIds.isEmpty) {
        return const <String>{};
      }
      return Set<String>.of(assignedIds);
    }
    return _draftSelectedIds;
  }

  /// Dispatches async inline label creation from [UiSearchablePicker.onInlineCreate].
  void _triggerInlineCreate(String rawName) {
    unawaited(_handleInlineCreate(rawName));
  }
}

/// Immutable per-frame picker projection computed for [CompactLabelPickerSheet].
typedef _CompactLabelPickerSnapshot = ({
  String effectiveScopeId,
  String emptyText,
  bool hasDuplicate,
  List<UiPickerOption<String>> options,
  List<UiPickerScopeFilter> scopeFilters,
  Set<String> selectedIds,
});

/// Presents the focus-trapped compact mobile label picker bottom sheet without search auto-focus (`U-A11Y-003`).
Future<void> showCompactLabelPickerSheet(
  BuildContext context, {
  required String title,
  String? taskId,
  Set<String> initialSelectedLabelIds = const <String>{},
  required ValueChanged<String> onToggleLabel,
  required Future<ActionResult> Function(String rawName) onCreateLabel,
  required ValueChanged<String> onOpenLabelInfo,
}) {
  UiTelemetry.logDialogOpened('label_picker_sheet');
  final localizations = AppLocalizations.of(context);
  final initialCount = switch (taskId) {
    final targetTaskId? =>
      ProviderScope.containerOf(context, listen: false)
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findTask(targetTaskId)
              ?.labelIds
              .length ??
          initialSelectedLabelIds.length,
    null => initialSelectedLabelIds.length,
  };
  return UiDialogFrame.showBottomSheet<void>(
    context: context,
    title: title,
    icon: Icons.label_outline_rounded,
    countLabel: '$initialCount',
    doneLabel: localizations.actionDone,
    barrierLabel: title,
    builder: (modalContext) => CompactLabelPickerSheet(
      taskId: taskId,
      initialSelectedLabelIds: initialSelectedLabelIds,
      onToggleLabel: onToggleLabel,
      onCreateLabel: onCreateLabel,
      onOpenLabelInfo: onOpenLabelInfo,
      onRequestClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}

/// Counts scoped queue labels in [labels] in a single linear pass.
int _countScopedLabels(Iterable<TdfLabel> labels) {
  var count = 0;
  for (final label in labels) {
    if (label.isScoped) {
      count++;
    }
  }
  return count;
}
