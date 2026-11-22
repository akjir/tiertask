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
import '../../models/tdf_metadata.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/ui_telemetry.dart';
import '../components/ui_dialog_frame.dart';
import '../widgets/entity_label_picker.dart';

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

/// Manages live Riverpod label projection and draft selection state for [CompactLabelPickerSheet].
class _CompactLabelPickerSheetState
    extends ConsumerState<CompactLabelPickerSheet> {
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
    final board = ref.watch(
      taskNotifierProvider.select((asyncBoard) => asyncBoard.asData?.value),
    );
    final sortedLabels = board?.sortedLabels ?? const <TdfLabel>[];

    return EntitySearchableLabelPicker(
      key: const ValueKey<String>('compact_label_picker'),
      allLabels: sortedLabels,
      selectedIds: _resolveSelectedIds(board),
      openCountsByLabelId: _buildOpenCountsByLabelId(board, sortedLabels),
      isCompactSheet: true,
      query: _query,
      onQueryChanged: _handleQueryChanged,
      onToggleLabel: _handleToggleLabel,
      onCreateAndAssign: _triggerInlineCreate,
      onOpenLabelInfo: _handleOpenLabelInfo,
      onRequestClose: widget.onRequestClose,
    );
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
          });
        case ActionValidationFailed():
        case ActionPersistFailed():
          break;
      }
    } finally {
      _isCreating = false;
    }
  }

  /// Closes the bottom sheet and notifies the caller to inspect [labelId] in Labels manager.
  void _handleOpenLabelInfo(String labelId) {
    widget.onOpenLabelInfo(labelId);
    widget.onRequestClose();
  }

  /// Updates the controlled search query inside the sheet.
  void _handleQueryChanged(String nextQuery) {
    if (_query != nextQuery) {
      setState(() => _query = nextQuery);
    }
  }

  /// Updates draft selection when `taskId == null` and forwards [labelId] to the caller.
  void _handleToggleLabel(String labelId) {
    if (widget.taskId == null) {
      final nextSelected = Set<String>.of(_draftSelectedIds);
      if (!nextSelected.add(labelId)) {
        nextSelected.remove(labelId);
      }
      setState(() => _draftSelectedIds = nextSelected);
    }
    widget.onToggleLabel(labelId);
  }

  /// Resolves live selected label IDs from [board] in task mode or [_draftSelectedIds] in draft mode.
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

  /// Dispatches async inline label creation from [EntitySearchableLabelPicker.onCreateAndAssign].
  void _triggerInlineCreate(String rawName) {
    unawaited(_handleInlineCreate(rawName));
  }
}

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

/// Builds a map of open task counts per label ID for [EntitySearchableLabelPicker].
Map<String, int> _buildOpenCountsByLabelId(
  TaskBoard? board,
  List<TdfLabel> labels,
) {
  if (board == null || labels.isEmpty) {
    return const <String, int>{};
  }
  return <String, int>{
    for (final label in labels) label.id: board.openTaskCountForLabel(label.id),
  };
}
