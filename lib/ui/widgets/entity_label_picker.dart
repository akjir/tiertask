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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tdf_error.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../components/ui_searchable_picker.dart';

/// Scope filter identifier showing all labels.
const String _scopeAll = 'all';

/// Scope filter identifier showing global context labels only.
const String _scopeGlobal = 'global';

/// Scope filter identifier showing scoped queue labels only.
const String _scopeScoped = 'scoped';

/// Domain adapter wrapping [UiSearchablePicker] for Task and Draft label selection (`U-COMP-005`).
class EntitySearchableLabelPicker extends ConsumerStatefulWidget {
  /// Creates an [EntitySearchableLabelPicker].
  const EntitySearchableLabelPicker({
    super.key,
    required this.allLabels,
    required this.selectedIds,
    required this.onToggleLabel,
    required this.onCreateAndAssign,
    required this.onOpenLabelInfo,
    this.openCountsByLabelId = const <String, int>{},
    this.showSelectedChips = true,
    this.autoFocusSearch = false,
    this.isCompactSheet = false,
    this.useSharedQuery = false,
    this.scrollController,
    this.query,
    this.onQueryChanged,
    this.onRequestClose,
  });

  /// All workspace labels sorted alphabetically.
  final List<TdfLabel> allLabels;

  /// Requests initial search input focus on desktop; ignored when [isCompactSheet] is true.
  final bool autoFocusSearch;

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

  /// Optional map of label identifiers to open task counts (`0` when omitted).
  final Map<String, int> openCountsByLabelId;

  /// Optional controlled search query string (ignored when [useSharedQuery] is true).
  final String? query;

  /// Optional caller-owned scroll controller preserving picker scroll offset.
  final ScrollController? scrollController;

  /// Currently selected label identifiers.
  final Iterable<String> selectedIds;

  /// Controls whether selected removable split chips render above the search bar.
  final bool showSelectedChips;

  /// Watches and writes [labelPickerQueryProvider] directly without rebuilding parent cards or shell chrome.
  final bool useSharedQuery;

  @override
  ConsumerState<EntitySearchableLabelPicker> createState() =>
      _EntitySearchableLabelPickerState();
}

/// Manages local scope filter selection, optional shared query wiring, and duplicate checking for [EntitySearchableLabelPicker].
class _EntitySearchableLabelPickerState
    extends ConsumerState<EntitySearchableLabelPicker> {
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
    if (!_countLabelScopes(widget.allLabels).hasBoth &&
        _activeScopeId != _scopeAll) {
      _activeScopeId = _scopeAll;
    }
    if (!widget.useSharedQuery) {
      if (widget.query case final controlledQuery?
          when controlledQuery != _localQuery) {
        _localQuery = controlledQuery;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final counts = _countLabelScopes(widget.allLabels);
    final effectiveScope = counts.hasBoth ? _activeScopeId : _scopeAll;
    final sharedQuery = _watchSharedQuery();
    final activeQuery = sharedQuery ?? widget.query ?? _localQuery;

    return UiSearchablePicker<String>(
      options: _buildPickerOptions(effectiveScope, localizations),
      selectedIds: _resolveSelectedIdSet(widget.selectedIds),
      onToggleOption: _handleToggleOption,
      emptyText: _resolveEmptyText(localizations),
      searchMaxLength: maxTdfTextLength,
      showSelectedChips: widget.showSelectedChips,
      autoFocusSearch: widget.autoFocusSearch && !widget.isCompactSheet,
      isCompactSheet: widget.isCompactSheet,
      scrollController: widget.scrollController,
      scopeFilters: _buildScopeFilters(localizations, counts),
      activeScopeId: effectiveScope,
      onScopeChanged: _handleScopeChanged,
      query: sharedQuery ?? widget.query,
      onQueryChanged: _handleQueryChanged,
      searchPlaceholder: localizations.labelPickerSearchPlaceholder,
      searchClearTooltip: localizations.tooltipClearSearch,
      infoTooltip: localizations.openLabelInManagerTooltip,
      onOptionInfo: _handleOptionInfo,
      removeChipTooltip: (option) =>
          localizations.labelPickerRemoveTooltip(option.label),
      inlineCreateLabel: localizations.labelPickerCreateAndAssign,
      onInlineCreate: _resolveInlineCreateCallback(activeQuery),
      onRequestClose: widget.onRequestClose,
    );
  }

  /// Maps visible [TdfLabel] entries into [UiPickerOption] models.
  List<UiPickerOption<String>> _buildPickerOptions(
    String effectiveScope,
    AppLocalizations localizations,
  ) {
    final results = <UiPickerOption<String>>[];
    for (final label in widget.allLabels) {
      if (effectiveScope == _scopeScoped && !label.isScoped) {
        continue;
      }
      if (effectiveScope == _scopeGlobal && label.isScoped) {
        continue;
      }
      final openCount = widget.openCountsByLabelId[label.id] ?? 0;
      results.add(
        UiPickerOption<String>(
          id: label.id,
          value: label.id,
          label: label.name,
          colorDot: _resolveOptionalColor(
            TaskScheduleHelper.parseLabelColorValue(label.color),
          ),
          badgeLabel: label.isScoped ? localizations.scopedQueueLabel : null,
          countLabel: localizations.openTasksCountPill('$openCount'),
          hasInfoAction: true,
        ),
      );
    }
    return results;
  }

  /// Builds conditional `All`, `Scoped`, and `Global` filter pills when both scopes exist.
  List<UiPickerScopeFilter> _buildScopeFilters(
    AppLocalizations localizations,
    ({int scoped, int global, bool hasBoth}) counts,
  ) {
    if (!counts.hasBoth) {
      return const <UiPickerScopeFilter>[];
    }
    final totalCount = widget.allLabels.length;
    return <UiPickerScopeFilter>[
      UiPickerScopeFilter(
        id: _scopeAll,
        label: localizations.labelPickerFilterAll('$totalCount'),
      ),
      UiPickerScopeFilter(
        id: _scopeScoped,
        label: localizations.labelPickerFilterScoped('${counts.scoped}'),
      ),
      UiPickerScopeFilter(
        id: _scopeGlobal,
        label: localizations.labelPickerFilterGlobal('${counts.global}'),
      ),
    ];
  }

  /// Forwards info-button presses to [EntitySearchableLabelPicker.onOpenLabelInfo].
  void _handleOptionInfo(UiPickerOption<String> option) {
    widget.onOpenLabelInfo(option.value);
  }

  /// Tracks the latest search text for cross-scope duplicate detection and forwards changes.
  void _handleQueryChanged(String nextQuery) {
    if (widget.useSharedQuery) {
      ref.read(labelPickerQueryProvider.notifier).setQuery(nextQuery);
    } else if (_localQuery != nextQuery) {
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

  /// Resolves localized empty-state copy for an empty catalog vs unmatched search.
  String _resolveEmptyText(AppLocalizations localizations) {
    return widget.allLabels.isEmpty
        ? localizations.labelPickerEmptyHint
        : localizations.labelPickerNoMatches;
  }

  /// Disables inline label creation while [activeQuery] matches an existing label name.
  ValueChanged<String>? _resolveInlineCreateCallback(String activeQuery) {
    return _hasExactLabelMatch(activeQuery) ? null : widget.onCreateAndAssign;
  }

  /// Watches [labelPickerQueryProvider] only when [EntitySearchableLabelPicker.useSharedQuery] is enabled.
  String? _watchSharedQuery() {
    return widget.useSharedQuery ? ref.watch(labelPickerQueryProvider) : null;
  }
}

/// Counts scoped and global labels across [labels] in a single pass.
({int scoped, int global, bool hasBoth}) _countLabelScopes(
  List<TdfLabel> labels,
) {
  var scopedCount = 0;
  for (final label in labels) {
    if (label.isScoped) {
      scopedCount++;
    }
  }
  final globalCount = labels.length - scopedCount;
  return (
    scoped: scopedCount,
    global: globalCount,
    hasBoth: scopedCount > 0 && globalCount > 0,
  );
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
