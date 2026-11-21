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

import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/view_model_primitives.dart';

/// Maximum character limit for the searchable label picker query (`maxTdfTextLength`).
const int _labelPickerSearchMaxLength = 500;

/// Scope filter identifier showing all labels.
const String _scopeAll = 'all';

/// Scope filter identifier showing global context labels only.
const String _scopeGlobal = 'global';

/// Scope filter identifier showing scoped queue labels only.
const String _scopeScoped = 'scoped';

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
    final effectiveScope = _resolveEffectiveScope();

    return UiSearchablePicker<String>(
      options: _buildPickerOptions(
        effectiveScope: effectiveScope,
        localizations: localizations,
      ),
      selectedIds: _resolveSelectedIdSet(widget.selectedIds),
      onToggleOption: _handleToggleOption,
      emptyText: _resolveEmptyText(localizations),
      searchMaxLength: _labelPickerSearchMaxLength,
      showSelectedChips: widget.showSelectedChips,
      autoFocusSearch: widget.autoFocusSearch && !widget.isCompactSheet,
      isCompactSheet: widget.isCompactSheet,
      scrollController: widget.scrollController,
      scopeFilters: _buildScopeFilters(localizations),
      activeScopeId: effectiveScope,
      onScopeChanged: _handleScopeChanged,
      query: widget.query,
      onQueryChanged: _handleQueryChanged,
      searchPlaceholder: localizations.labelPickerSearchPlaceholder,
      searchClearTooltip: localizations.tooltipClearSearch,
      infoTooltip: localizations.openLabelInManagerTooltip,
      onOptionInfo: _handleOptionInfo,
      removeChipTooltip: (option) =>
          localizations.labelPickerRemoveTooltip(option.label),
      inlineCreateLabel: localizations.labelPickerCreateAndAssign,
      onInlineCreate: _resolveInlineCreateCallback(),
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

  /// Forwards info-button presses to [EntitySearchableLabelPicker.onOpenLabelInfo].
  void _handleOptionInfo(UiPickerOption<String> option) {
    widget.onOpenLabelInfo(option.value);
  }

  /// Tracks the latest search text for cross-scope duplicate detection and forwards changes.
  void _handleQueryChanged(String nextQuery) {
    if (_localQuery != nextQuery) {
      setState(() => _localQuery = nextQuery);
    }
    widget.onQueryChanged?.call(nextQuery);
  }

  /// Updates the active scope filter tab when both label scopes exist.
  void _handleScopeChanged(String scopeId) {
    setState(() => _activeScopeId = scopeId);
  }

  /// Forwards option toggles to [EntitySearchableLabelPicker.onToggleLabel].
  void _handleToggleOption(UiPickerOption<String> option) {
    widget.onToggleLabel(option.value);
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

  /// Resolves the active scope identifier, falling back to [_scopeAll] when only one scope exists.
  String _resolveEffectiveScope() {
    return widget.hasBothScopedAndGlobal ? _activeScopeId : _scopeAll;
  }

  /// Resolves localized empty-state copy for an empty catalog vs unmatched search.
  String _resolveEmptyText(AppLocalizations localizations) {
    return widget.allLabels.isEmpty
        ? localizations.labelPickerEmptyHint
        : localizations.labelPickerNoMatches;
  }

  /// Disables inline label creation while [_localQuery] matches an existing label name.
  ValueChanged<String>? _resolveInlineCreateCallback() {
    return _hasExactLabelMatch(_localQuery) ? null : widget.onCreateAndAssign;
  }
}

/// Converts an optional ARGB integer [colorValue] into a [Color] without null assertions.
Color? _resolveOptionalColor(int? colorValue) {
  if (colorValue == null) {
    return null;
  }
  return Color(colorValue);
}

/// Returns [selectedIds] as a [Set] without copying when it is already a [Set].
Set<String> _resolveSelectedIdSet(Iterable<String> selectedIds) {
  return switch (selectedIds) {
    final Set<String> existingSet => existingSet,
    _ => selectedIds.toSet(),
  };
}
