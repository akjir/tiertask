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
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/ui_telemetry.dart';
import '../../presentation/view_model_primitives.dart';

const String _labelScopeAll = 'all';

/// Scope filter identifier showing only global context labels inside the compact label picker sheet.
const String _labelScopeGlobal = 'global';

/// Scope filter identifier showing only scoped queue labels inside the compact label picker sheet.
const String _labelScopeScoped = 'scoped';

/// Maximum Unicode scalar length for searchable label creation (`maxTdfTextLength`).
const int _maxLabelNameLength = 500;

/// Stateful body hosted inside the compact mobile label picker bottom sheet (`U-A11Y-003`).
class _CompactLabelPickerSheetBody extends StatefulWidget {
  /// Creates a [_CompactLabelPickerSheetBody].
  const _CompactLabelPickerSheetBody({
    required this.initialLabels,
    required this.hasBothScopedAndGlobal,
    required this.initialSelectedIds,
    required this.onToggleLabel,
    required this.onCreateAndAssign,
    required this.onOpenLabelInfo,
    required this.onRequestClose,
  });

  /// Whether conditional `All` / `Scoped` / `Global` filter pills are shown.
  final bool hasBothScopedAndGlobal;

  /// Initial label options supplied when opening the sheet.
  final List<LabelPickerOptionViewModel> initialLabels;

  /// Initial set of selected label identifiers.
  final Set<String> initialSelectedIds;

  /// Callback creating and assigning a new label by name.
  final ValueChanged<String> onCreateAndAssign;

  /// Callback navigating to the label manager card for a label identifier.
  final ValueChanged<String> onOpenLabelInfo;

  /// Callback closing the active bottom sheet route.
  final VoidCallback onRequestClose;

  /// Callback toggling selection of an existing label identifier.
  final ValueChanged<String> onToggleLabel;

  @override
  State<_CompactLabelPickerSheetBody> createState() =>
      _CompactLabelPickerSheetBodyState();
}

/// Manages local live selection, scope filtering, and inline label creation inside [_CompactLabelPickerSheetBody].
class _CompactLabelPickerSheetBodyState
    extends State<_CompactLabelPickerSheetBody> {
  String _activeScopeId = _labelScopeAll;
  late List<LabelPickerOptionViewModel> _labels;
  String _query = '';
  late Set<String> _selectedIds;
  final Set<String> _syntheticIds = <String>{};

  @override
  void initState() {
    super.initState();
    _labels = List<LabelPickerOptionViewModel>.of(widget.initialLabels);
    _selectedIds = Set<String>.of(widget.initialSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final hasDuplicate = _hasLabelNamed(_labels, _query.trim());

    return UiSearchablePicker<String>(
      key: const ValueKey<String>('compact_label_picker'),
      options: _buildOptions(localizations, tokens),
      selectedIds: _selectedIds,
      selectionMode: UiPickerSelectionMode.multiple,
      isCompactSheet: true,
      autoFocusSearch: false,
      searchMaxLength: _maxLabelNameLength,
      query: _query,
      onQueryChanged: _handleQueryChanged,
      searchPlaceholder: localizations.labelPickerSearchPlaceholder,
      searchClearTooltip: localizations.tooltipClearSearch,
      scopeFilters: _buildScopeFilters(localizations),
      activeScopeId: _activeScopeId,
      onScopeChanged: _handleScopeChanged,
      emptyText: _labels.isEmpty
          ? localizations.labelPickerEmptyHint
          : localizations.labelPickerNoMatches,
      infoTooltip: localizations.openLabelInManagerTooltip,
      onToggleOption: _handleToggleOption,
      onOptionInfo: _handleOptionInfo,
      removeChipTooltip: (option) =>
          localizations.labelPickerRemoveTooltip(option.label),
      inlineCreateLabel: (trimmed) =>
          localizations.labelPickerCreateAndAssign(trimmed),
      onInlineCreate: hasDuplicate ? null : _handleInlineCreate,
      onRequestClose: widget.onRequestClose,
    );
  }

  /// Builds picker option rows filtered by [_activeScopeId].
  List<UiPickerOption<String>> _buildOptions(
    AppLocalizations localizations,
    UiThemeTokens tokens,
  ) {
    final options = <UiPickerOption<String>>[];
    for (final label in _labels) {
      if (_activeScopeId == _labelScopeScoped && !label.isScoped) {
        continue;
      }
      if (_activeScopeId == _labelScopeGlobal && label.isScoped) {
        continue;
      }
      final colorDot = switch (label.colorValue) {
        final value? => Color(value),
        null => tokens.colors.accent,
      };
      options.add(
        UiPickerOption<String>(
          id: label.id,
          value: label.id,
          label: label.name,
          colorDot: colorDot,
          badgeLabel: label.isScoped ? localizations.scopedQueueLabel : null,
          countLabel: localizations.openTasksCountPill('${label.openCount}'),
          hasInfoAction: !_syntheticIds.contains(label.id),
        ),
      );
    }
    return options;
  }

  /// Builds conditional `All`, `Scoped`, and `Global` filter pills when both scopes exist.
  List<UiPickerScopeFilter> _buildScopeFilters(AppLocalizations localizations) {
    if (!widget.hasBothScopedAndGlobal) {
      return const <UiPickerScopeFilter>[];
    }
    var scopedCount = 0;
    for (final label in _labels) {
      if (label.isScoped) {
        scopedCount++;
      }
    }
    final globalCount = _labels.length - scopedCount;
    return <UiPickerScopeFilter>[
      UiPickerScopeFilter(
        id: _labelScopeAll,
        label: localizations.labelPickerFilterAll('${_labels.length}'),
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

  /// Invokes inline label creation and reflects the new selection optimistically inside the sheet.
  void _handleInlineCreate(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    widget.onCreateAndAssign(trimmed);
    final syntheticId = '_created_${_syntheticIds.length}';
    final createdOption = LabelPickerOptionViewModel(
      id: syntheticId,
      name: trimmed,
      isScoped: false,
      openCount: 0,
    );
    setState(() {
      _syntheticIds.add(syntheticId);
      _labels = <LabelPickerOptionViewModel>[..._labels, createdOption]
        ..sort(
          (first, second) =>
              first.name.toLowerCase().compareTo(second.name.toLowerCase()),
        );
      _selectedIds = <String>{..._selectedIds, syntheticId};
      _query = '';
      if (_activeScopeId == _labelScopeScoped) {
        _activeScopeId = _labelScopeAll;
      }
    });
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

  /// Toggles local selection state and forwards existing label IDs to the caller.
  void _handleToggleOption(UiPickerOption<String> option) {
    final nextSelected = Set<String>.of(_selectedIds);
    if (!nextSelected.add(option.id)) {
      nextSelected.remove(option.id);
    }
    setState(() => _selectedIds = nextSelected);
    if (!_syntheticIds.contains(option.id)) {
      widget.onToggleLabel(option.value);
    }
  }
}

/// Presents the focus-trapped compact mobile label picker bottom sheet without search auto-focus (`U-A11Y-003`).
Future<void> showCompactLabelPickerSheet(
  BuildContext context, {
  required String title,
  required List<LabelPickerOptionViewModel> allLabels,
  required bool hasBothScopedAndGlobal,
  required Set<String> selectedIds,
  required ValueChanged<String> onToggleLabel,
  required ValueChanged<String> onCreateAndAssign,
  required ValueChanged<String> onOpenLabelInfo,
}) {
  UiTelemetry.logDialogOpened('label_picker_sheet');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showBottomSheet<void>(
    context: context,
    title: title,
    icon: Icons.label_outline_rounded,
    countLabel: '${selectedIds.length}',
    doneLabel: localizations.actionDone,
    barrierLabel: title,
    builder: (modalContext) => _CompactLabelPickerSheetBody(
      initialLabels: allLabels,
      hasBothScopedAndGlobal: hasBothScopedAndGlobal,
      initialSelectedIds: selectedIds,
      onToggleLabel: onToggleLabel,
      onCreateAndAssign: onCreateAndAssign,
      onOpenLabelInfo: onOpenLabelInfo,
      onRequestClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}

/// Returns `true` when any option in [labels] matches [trimmedName] case-insensitively.
bool _hasLabelNamed(
  List<LabelPickerOptionViewModel> labels,
  String trimmedName,
) {
  if (trimmedName.isEmpty) {
    return false;
  }
  final normalized = trimmedName.toLowerCase();
  for (final label in labels) {
    if (label.name.trim().toLowerCase() == normalized) {
      return true;
    }
  }
  return false;
}
