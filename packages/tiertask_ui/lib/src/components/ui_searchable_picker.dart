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

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../primitives/ui_button.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_pill.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';

/// Selection behavior for [UiSearchablePicker].
enum UiPickerSelectionMode {
  /// Multi-select listbox with `16x16px` checkboxes (Labels, Prerequisites).
  multiple,

  /// Single-select listbox with `soft`/`accent` highlight (Local `.tdf` Files, Geocoding Candidates).
  single,
}

/// Immutable selectable row model rendered inside [UiSearchablePicker].
@immutable
class UiPickerOption<T> {
  /// Creates a [UiPickerOption].
  const UiPickerOption({
    required this.id,
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.colorDot,
    this.badgeLabel,
    this.countLabel,
    this.disabledHint,
    this.isMonospace = false,
    this.enabled = true,
    this.hasInfoAction = false,
  });

  /// Optional secondary micro badge (e.g. `Scoped Queue`).
  final String? badgeLabel;

  /// Optional leading square color dot.
  final Color? colorDot;

  /// Optional trailing tabular count text.
  final String? countLabel;

  /// Optional inline explanation shown when [enabled] is false (e.g. `Cycle prevented`).
  final String? disabledHint;

  /// Whether the option can be toggled (`0.50` opacity when false).
  final bool enabled;

  /// Whether a trailing info icon button is displayed for this row.
  final bool hasInfoAction;

  /// Optional leading outline icon glyph.
  final IconData? icon;

  /// Stable option identifier.
  final String id;

  /// Uses monospace label styling (filenames, paths, coordinates).
  final bool isMonospace;

  /// Primary caller-supplied option label.
  final String label;

  /// Optional secondary muted line below [label].
  final String? subtitle;

  /// Strongly typed backing value.
  final T value;
}

/// Immutable scope filter chip definition rendered when `scopeFilters.length >= 2`.
@immutable
class UiPickerScopeFilter {
  /// Creates a [UiPickerScopeFilter].
  const UiPickerScopeFilter({required this.id, required this.label});

  /// Stable scope identifier.
  final String id;

  /// Caller-supplied filter chip label.
  final String label;
}

/// Reusable searchable multi-select and single-select picker composite (`U-COMP-005`, `U-A11Y-002`..`003`).
class UiSearchablePicker<T> extends StatefulWidget {
  /// Creates a [UiSearchablePicker].
  const UiSearchablePicker({
    super.key,
    required this.options,
    required this.selectedIds,
    required this.onToggleOption,
    required this.emptyText,
    this.selectionMode = UiPickerSelectionMode.multiple,
    this.showSearch = true,
    this.searchMaxLength = 120,
    this.showSelectedChips = true,
    this.autoFocusSearch = false,
    this.isCompactSheet = false,
    this.scrollController,
    this.scopeFilters = const <UiPickerScopeFilter>[],
    this.activeScopeId,
    this.onScopeChanged,
    this.query,
    this.onQueryChanged,
    this.searchPlaceholder,
    this.searchClearTooltip,
    this.infoTooltip,
    this.onOptionInfo,
    this.removeChipTooltip,
    this.inlineCreateLabel,
    this.onInlineCreate,
    this.onRequestClose,
    this.maxListHeight = 224.0,
  });

  /// Active scope filter identifier when [scopeFilters] has `>= 2` items.
  final String? activeScopeId;

  /// Auto-focuses the search field on desktop; strictly ignored when [isCompactSheet] is true (`U-A11Y-003`).
  final bool autoFocusSearch;

  /// Muted empty text rendered when no options match and inline create is unavailable.
  final String emptyText;

  /// Accessible tooltip for per-row info buttons.
  final String? infoTooltip;

  /// Formats the inline creation row text from a unique `1..120`-char trimmed query.
  final String Function(String trimmedQuery)? inlineCreateLabel;

  /// Enforces `44px` compact touch rows and disables search auto-focus inside mobile bottom sheets.
  final bool isCompactSheet;

  /// Maximum desktop list height (`224px` default; unbounded flex height inside compact sheets).
  final double? maxListHeight;

  /// Callback invoked when the inline creation row is activated.
  final ValueChanged<String>? onInlineCreate;

  /// Callback invoked when a row's trailing info action is tapped.
  final ValueChanged<UiPickerOption<T>>? onOptionInfo;

  /// Callback invoked whenever the search query text changes.
  final ValueChanged<String>? onQueryChanged;

  /// Callback invoked on second `Escape` when the query is already empty.
  final VoidCallback? onRequestClose;

  /// Callback invoked when a scope filter pill is tapped.
  final ValueChanged<String>? onScopeChanged;

  /// Callback toggling or selecting an option.
  final ValueChanged<UiPickerOption<T>> onToggleOption;

  /// Candidate options supplied by caller.
  final List<UiPickerOption<T>> options;

  /// Optional controlled search query string.
  final String? query;

  /// Builds accessible remove-chip tooltips for selected chips.
  final String Function(UiPickerOption<T> option)? removeChipTooltip;

  /// Optional scope filter pills (rendered ONLY when `length >= 2`).
  final List<UiPickerScopeFilter> scopeFilters;

  /// Optional caller-owned scroll controller preserving picker scroll position (`U-LAYOUT-007`).
  final ScrollController? scrollController;

  /// Tooltip for the search input clear button.
  final String? searchClearTooltip;

  /// Maximum search input character length (`120` default).
  final int? searchMaxLength;

  /// Search input placeholder copy.
  final String? searchPlaceholder;

  /// Identifier set of currently selected options.
  final Set<String> selectedIds;

  /// Multi-select vs single-select row presentation.
  final UiPickerSelectionMode selectionMode;

  /// Whether the search input box is rendered.
  final bool showSearch;

  /// Whether selected split chips render above the search bar (set `false` in desktop composer popover).
  final bool showSelectedChips;

  @override
  State<UiSearchablePicker<T>> createState() => _UiSearchablePickerState<T>();
}

/// Manages local query filtering, keyboard `ArrowUp`/`ArrowDown`/`Enter`/`Escape`, and highlight index for [UiSearchablePicker].
class _UiSearchablePickerState<T> extends State<UiSearchablePicker<T>> {
  /// Internal search text controller.
  late final TextEditingController _searchController;

  /// Focus node attached to the search input.
  late final FocusNode _searchFocusNode;

  /// Current keyboard highlight index across filtered visible options + optional inline create row.
  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query ?? '');
    _searchFocusNode = FocusNode(onKeyEvent: _handleKeyEvent);
  }

  @override
  void didUpdateWidget(covariant UiSearchablePicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != null && widget.query != _searchController.text) {
      _searchController.text = widget.query ?? '';
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final trimmedQuery = _searchController.text.trim();
    final filteredOptions = _filterOptions(trimmedQuery);
    final canCreate = _canInlineCreate(trimmedQuery);
    final totalRows = filteredOptions.length + (canCreate ? 1 : 0);
    final safeHighlight = totalRows == 0
        ? -1
        : _highlightedIndex.clamp(0, totalRows - 1);
    final selectedOptions = _selectedOptions();

    final listContent = _buildListContent(
      tokens,
      filteredOptions: filteredOptions,
      trimmedQuery: trimmedQuery,
      canCreate: canCreate,
      highlightedIndex: safeHighlight,
    );

    return Column(
      mainAxisSize: widget.isCompactSheet ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showSelectedChips && selectedOptions.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: 6.0,
            runSpacing: 6.0,
            children: <Widget>[
              for (final option in selectedOptions)
                UiPill(
                  key: ValueKey<String>('picker_chip_${option.id}'),
                  label: option.label,
                  variant: UiPillVariant.splitChip,
                  colorDot: option.colorDot,
                  onRemove: () => widget.onToggleOption(option),
                  removeTooltip: widget.removeChipTooltip?.call(option),
                ),
            ],
          ),
          const SizedBox(height: 8.0),
        ],
        if (widget.showSearch) ...<Widget>[
          UiField(
            kind: UiFieldKind.search,
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: widget.autoFocusSearch && !widget.isCompactSheet,
            maxLength: widget.searchMaxLength,
            hintText: widget.searchPlaceholder,
            clearTooltip: widget.searchClearTooltip,
            onChanged: _handleQueryChanged,
          ),
          const SizedBox(height: 8.0),
        ],
        if (widget.scopeFilters.length >= 2) ...<Widget>[
          Wrap(
            spacing: 6.0,
            runSpacing: 6.0,
            children: <Widget>[
              for (final scope in widget.scopeFilters)
                UiPill(
                  key: ValueKey<String>('picker_scope_${scope.id}'),
                  label: scope.label,
                  variant: UiPillVariant.selectable,
                  isSelected: scope.id == widget.activeScopeId,
                  onPressed: () => widget.onScopeChanged?.call(scope.id),
                ),
            ],
          ),
          const SizedBox(height: 8.0),
        ],
        if (widget.isCompactSheet)
          Expanded(child: _wrapListContainer(tokens, listContent))
        else
          _wrapListContainer(tokens, listContent),
      ],
    );
  }

  /// Builds the lazy `ListView.builder` or muted empty-state message.
  Widget _buildListContent(
    UiThemeTokens tokens, {
    required List<UiPickerOption<T>> filteredOptions,
    required String trimmedQuery,
    required bool canCreate,
    required int highlightedIndex,
  }) {
    final totalRows = filteredOptions.length + (canCreate ? 1 : 0);
    if (totalRows == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 14.0),
        child: Text(
          widget.emptyText,
          style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
        ),
      );
    }

    final listView = ListView.builder(
      controller: widget.scrollController,
      shrinkWrap: !widget.isCompactSheet,
      padding: const EdgeInsets.all(4.0),
      itemCount: totalRows,
      itemBuilder: (context, index) {
        if (index < filteredOptions.length) {
          final option = filteredOptions[index];
          return _UiPickerOptionRow<T>(
            key: ValueKey<String>('picker_opt_${option.id}'),
            option: option,
            selectionMode: widget.selectionMode,
            isSelected: widget.selectedIds.contains(option.id),
            isHighlighted: index == highlightedIndex,
            isCompactSheet: widget.isCompactSheet,
            infoTooltip: widget.infoTooltip,
            onTap: option.enabled ? () => widget.onToggleOption(option) : null,
            onInfoTap: option.hasInfoAction && widget.onOptionInfo != null
                ? () => widget.onOptionInfo?.call(option)
                : null,
          );
        }
        final createText =
            widget.inlineCreateLabel?.call(trimmedQuery) ?? trimmedQuery;
        return _UiPickerCreateRow(
          label: createText,
          isHighlighted: index == highlightedIndex,
          isCompactSheet: widget.isCompactSheet,
          onTap: () => widget.onInlineCreate?.call(trimmedQuery),
        );
      },
    );

    if (!widget.isCompactSheet && widget.maxListHeight != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxListHeight ?? 224.0),
        child: listView,
      );
    }
    return listView;
  }

  /// Returns true when trimmed query is `1..120` chars and not a case-insensitive duplicate.
  bool _canInlineCreate(String trimmedQuery) {
    if (widget.onInlineCreate == null || widget.inlineCreateLabel == null) {
      return false;
    }
    if (trimmedQuery.isEmpty || trimmedQuery.length > 120) {
      return false;
    }
    final normalized = trimmedQuery.toLowerCase();
    for (final option in widget.options) {
      if (option.label.trim().toLowerCase() == normalized) {
        return false;
      }
    }
    return true;
  }

  /// Filters candidate options against [trimmedQuery] case-insensitively.
  List<UiPickerOption<T>> _filterOptions(String trimmedQuery) {
    if (trimmedQuery.isEmpty) {
      return widget.options;
    }
    final needle = trimmedQuery.toLowerCase();
    return widget.options
        .where(
          (option) =>
              option.label.toLowerCase().contains(needle) ||
              (option.subtitle?.toLowerCase().contains(needle) ?? false),
        )
        .toList();
  }

  /// Handles `ArrowDown`, `ArrowUp`, `Enter`, and two-step `Escape` on the search focus node.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final trimmedQuery = _searchController.text.trim();
    final filtered = _filterOptions(trimmedQuery);
    final canCreate = _canInlineCreate(trimmedQuery);
    final totalRows = filtered.length + (canCreate ? 1 : 0);

    if (key == LogicalKeyboardKey.escape) {
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
        _handleQueryChanged('');
        return KeyEventResult.handled;
      }
      widget.onRequestClose?.call();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (totalRows > 0) {
        setState(() {
          _highlightedIndex = (_highlightedIndex + 1) % totalRows;
        });
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (totalRows > 0) {
        setState(() {
          _highlightedIndex = (_highlightedIndex - 1 + totalRows) % totalRows;
        });
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (totalRows == 0) {
        return KeyEventResult.ignored;
      }
      final activeIndex = _highlightedIndex.clamp(0, totalRows - 1);
      if (activeIndex < filtered.length) {
        final target = filtered[activeIndex];
        if (target.enabled) {
          widget.onToggleOption(target);
        }
      } else if (canCreate) {
        widget.onInlineCreate?.call(trimmedQuery);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Resets highlight index and notifies caller whenever query text changes.
  void _handleQueryChanged(String next) {
    setState(() => _highlightedIndex = 0);
    widget.onQueryChanged?.call(next);
  }

  /// Returns options currently present in `widget.selectedIds` in display order.
  List<UiPickerOption<T>> _selectedOptions() {
    if (widget.selectedIds.isEmpty) {
      return const <UiPickerOption<Never>>[];
    }
    return widget.options
        .where((option) => widget.selectedIds.contains(option.id))
        .toList();
  }

  /// Wraps the listbox in a flat bordered surface honoring [UiSurfaceScope].
  Widget _wrapListContainer(UiThemeTokens tokens, Widget child) {
    final surfaceLevel = UiSurfaceScope.of(context);
    final fill = surfaceLevel == UiSurfaceLevel.insetWell
        ? tokens.colors.panel
        : tokens.colors.bg;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(tokens.radii.md),
        border: Border.all(
          color: tokens.colors.line,
          width: tokens.radii.borderWidth,
        ),
      ),
      child: child,
    );
  }
}

/// Option row rendered inside [UiSearchablePicker].
class _UiPickerOptionRow<T> extends StatelessWidget {
  /// Creates a [_UiPickerOptionRow].
  const _UiPickerOptionRow({
    super.key,
    required this.option,
    required this.selectionMode,
    required this.isSelected,
    required this.isHighlighted,
    required this.isCompactSheet,
    required this.infoTooltip,
    required this.onTap,
    required this.onInfoTap,
  });

  /// Tooltip for trailing info trigger.
  final String? infoTooltip;

  /// Enforces `44px` minimum row height inside compact bottom sheets.
  final bool isCompactSheet;

  /// Whether keyboard highlight is currently on this row.
  final bool isHighlighted;

  /// Whether this option is selected.
  final bool isSelected;

  /// Info button callback.
  final VoidCallback? onInfoTap;

  /// Primary row toggle callback.
  final VoidCallback? onTap;

  /// Backing option data.
  final UiPickerOption<T> option;

  /// Multiple vs single selection mode.
  final UiPickerSelectionMode selectionMode;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final minHeight = isCompactSheet ? tokens.spacing.touchTargetMobile : 36.0;
    final rowBackground = isSelected
        ? colors.soft
        : (isHighlighted ? colors.panel : Colors.transparent);
    final borderColor = isSelected && isHighlighted
        ? colors.accent
        : Colors.transparent;
    final labelStyle =
        (option.isMonospace
                ? UiTypographyTokens.mono(tokens.typography.monoSmall)
                : tokens.typography.control)
            .copyWith(
              color: isSelected ? colors.accent : colors.ink,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            );

    final rowContent = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 5.0),
        decoration: BoxDecoration(
          color: rowBackground,
          borderRadius: BorderRadius.circular(tokens.radii.sm),
          border: Border.all(
            color: borderColor,
            width: tokens.radii.borderWidth,
          ),
        ),
        child: Row(
          children: <Widget>[
            if (selectionMode == UiPickerSelectionMode.multiple) ...<Widget>[
              _UiPickerCheckbox(isSelected: isSelected),
              const SizedBox(width: 8.0),
            ],
            if (option.colorDot case final dotColor?) ...<Widget>[
              ExcludeSemantics(
                child: Container(
                  width: 8.0,
                  height: 8.0,
                  decoration: BoxDecoration(
                    color: dotColor,
                    borderRadius: BorderRadius.circular(tokens.radii.dotSm),
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
            ] else if (option.icon case final glyph?) ...<Widget>[
              ExcludeSemantics(
                child: Icon(
                  glyph,
                  size: tokens.spacing.iconSm,
                  color: isSelected ? colors.accent : colors.muted,
                ),
              ),
              const SizedBox(width: 8.0),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(option.label, style: labelStyle),
                  if (option.subtitle case final sub?)
                    Text(
                      sub,
                      style: tokens.typography.micro.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  if (!option.enabled && option.disabledHint != null)
                    Text(
                      option.disabledHint ?? '',
                      style: tokens.typography.micro.copyWith(
                        color: colors.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            if (option.badgeLabel case final badge?) ...<Widget>[
              const SizedBox(width: 6.0),
              UiPill(label: badge, variant: UiPillVariant.badge),
            ],
            if (option.countLabel case final count?) ...<Widget>[
              const SizedBox(width: 6.0),
              Text(
                count,
                style: UiTypographyTokens.tabular(
                  tokens.typography.eyebrow.copyWith(
                    color: colors.muted,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.0,
                  ),
                ),
              ),
            ],
            if (onInfoTap != null) ...<Widget>[
              const SizedBox(width: 4.0),
              UiButton(
                leadingIcon: Icons.info_outline_rounded,
                variant: UiButtonVariant.icon,
                density: UiButtonDensity.sidebarDesktop,
                tooltip: infoTooltip,
                onPressed: onInfoTap,
              ),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      button: option.enabled,
      selected: isSelected,
      enabled: option.enabled,
      label: option.label,
      child: Opacity(
        opacity: option.enabled ? 1.0 : tokens.focus.prereqDisabledOpacity,
        child: rowContent,
      ),
    );
  }
}

/// Custom `16x16px` flat checkbox rendered in multi-select picker rows.
class _UiPickerCheckbox extends StatelessWidget {
  /// Creates a [_UiPickerCheckbox].
  const _UiPickerCheckbox({required this.isSelected});

  /// Whether the checkbox is checked.
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: 16.0,
        height: 16.0,
        decoration: BoxDecoration(
          color: isSelected ? colors.accent : colors.panel,
          borderRadius: BorderRadius.circular(tokens.radii.dotLg),
          border: Border.all(
            color: isSelected ? colors.accent : colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
        child: isSelected
            ? Icon(Icons.check_rounded, size: 12.0, color: colors.onAccent)
            : null,
      ),
    );
  }
}

/// Inline creation action row rendered at the bottom of [UiSearchablePicker].
class _UiPickerCreateRow extends StatelessWidget {
  /// Creates a [_UiPickerCreateRow].
  const _UiPickerCreateRow({
    required this.label,
    required this.isHighlighted,
    required this.isCompactSheet,
    required this.onTap,
  });

  /// Enforces `44px` touch target inside compact bottom sheets.
  final bool isCompactSheet;

  /// Whether keyboard highlight is active on this create row.
  final bool isHighlighted;

  /// Caller-formatted creation prompt.
  final String label;

  /// Creation callback.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final minHeight = isCompactSheet ? tokens.spacing.touchTargetMobile : 36.0;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: isHighlighted ? colors.soft : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radii.sm),
          ),
          child: Row(
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  Icons.add_rounded,
                  size: tokens.spacing.iconSm,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  label,
                  style: tokens.typography.control.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
