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

import '../primitives/ui_button.dart';
import '../primitives/ui_pill.dart';
import '../tokens/ui_theme_tokens.dart';

/// Minimum estimated row height (`32px`) used to switch bounded lists into lazy virtualization.
const double _minOrderedRowHeight = 32.0;

/// Signature building row content inside [UiOrderedItemList].
typedef UiOrderedItemBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  int index,
  bool isEditing,
);

/// Signature generating a deterministic widget [Key] for each item in [UiOrderedItemList].
typedef UiOrderedItemKeyBuilder<T> = Key Function(T item, int index);

/// Signature invoked when an item moves from [oldIndex] to [newIndex].
typedef UiOrderedItemReorderCallback = void Function(
  int oldIndex,
  int newIndex,
);

/// Signature invoked when an item edit or delete action is triggered.
typedef UiOrderedItemActionCallback<T> = void Function(T item, int index);

/// Repeatable ordered list composite for Subtasks, Reference Links, Time Windows, and History Journal (`U-COMP-006`).
class UiOrderedItemList<T> extends StatelessWidget {
  /// Creates a [UiOrderedItemList].
  const UiOrderedItemList({
    super.key,
    required this.items,
    required this.itemKey,
    required this.itemBuilder,
    this.title,
    this.countLabel,
    this.headerTrailing,
    this.progressValue,
    this.editingIndex,
    this.onReorder,
    this.moveUpTooltip,
    this.moveDownTooltip,
    this.onEdit,
    this.editTooltip,
    this.onDelete,
    this.deleteTooltip,
    this.emptyText,
    this.maxHeight,
    this.addBar,
    this.footer,
  });

  /// Optional bottom inline add bar (e.g. subtask or history input row).
  final Widget? addBar;

  /// Optional tabular count pill displayed beside [title] (e.g. `2 / 5`, `4 / 20`).
  final String? countLabel;

  /// Tooltip for per-row delete buttons.
  final String? deleteTooltip;

  /// Index of the row currently being edited inline (highlighted with `soft` fill).
  final int? editingIndex;

  /// Tooltip for per-row edit buttons.
  final String? editTooltip;

  /// Optional muted copy shown when [items] is empty.
  final String? emptyText;

  /// Optional trailing footer slot (e.g. Auto-finish toggle row).
  final Widget? footer;

  /// Optional trailing widget in the list header row.
  final Widget? headerTrailing;

  /// Builder rendering each item's primary content.
  final UiOrderedItemBuilder<T> itemBuilder;

  /// Deterministic widget key generator per item (`P-LAZY-LISTS`).
  final UiOrderedItemKeyBuilder<T> itemKey;

  /// Ordered items rendered in the list.
  final List<T> items;

  /// Optional scrollable height cap; when `null`, renders shrink-wrapped inside parent scroll views.
  final double? maxHeight;

  /// Tooltip for boundary-disabled move-down arrow buttons.
  final String? moveDownTooltip;

  /// Tooltip for boundary-disabled move-up arrow buttons.
  final String? moveUpTooltip;

  /// Optional delete action callback per row.
  final UiOrderedItemActionCallback<T>? onDelete;

  /// Optional edit action callback per row.
  final UiOrderedItemActionCallback<T>? onEdit;

  /// Optional reorder callback; move-up/move-down buttons render ONLY when non-null.
  final UiOrderedItemReorderCallback? onReorder;

  /// Optional progress ratio (`0.0..1.0`) rendering a `6px` `accent` bar on `radiusPill` track.
  final double? progressValue;

  /// Optional list header title.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final hasHeader =
        title != null || countLabel != null || headerTrailing != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (hasHeader) ...<Widget>[
          Row(
            children: <Widget>[
              if (title case final heading?)
                Flexible(
                  child: Text(
                    heading,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.meta.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (countLabel case final count?) ...<Widget>[
                const SizedBox(width: 8.0),
                UiPill(label: count, variant: UiPillVariant.count),
              ],
              const Spacer(),
              ?headerTrailing,
            ],
          ),
          SizedBox(height: tokens.spacing.space2),
        ],
        if (progressValue case final ratio?) ...<Widget>[
          _UiProgressTrack(value: ratio.clamp(0.0, 1.0)),
          SizedBox(height: tokens.spacing.space2),
        ],
        if (items.isEmpty)
          if (emptyText case final empty?)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                empty,
                style: tokens.typography.meta.copyWith(color: colors.muted),
              ),
            )
          else
            const SizedBox.shrink()
        else
          _buildListView(),
        if (addBar case final addWidget?) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          addWidget,
        ],
        if (footer case final footerWidget?) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          footerWidget,
        ],
      ],
    );
  }

  /// Builds either a height-capped lazily virtualized or parent-scroll-friendly `ListView.builder`.
  Widget _buildListView() {
    final limit = maxHeight;
    final virtualizeBounded =
        limit != null && items.length * _minOrderedRowHeight >= limit;
    final listView = ListView.builder(
      shrinkWrap: !virtualizeBounded,
      physics: limit == null ? const NeverScrollableScrollPhysics() : null,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isEditing = editingIndex == index;
        return _UiOrderedRow<T>(
          key: itemKey(item, index),
          index: index,
          totalCount: items.length,
          isEditing: isEditing,
          onReorder: onReorder,
          moveUpTooltip: moveUpTooltip,
          moveDownTooltip: moveDownTooltip,
          onEdit: onEdit != null ? () => onEdit?.call(item, index) : null,
          editTooltip: editTooltip,
          onDelete: onDelete != null ? () => onDelete?.call(item, index) : null,
          deleteTooltip: deleteTooltip,
          child: itemBuilder(context, item, index, isEditing),
        );
      },
    );

    if (limit != null) {
      if (virtualizeBounded) {
        return SizedBox(height: limit, child: listView);
      }
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: limit),
        child: listView,
      );
    }
    return listView;
  }
}

/// Horizontal `6px` progress track rendered for subtask completion ratios (`U-CARD-002`).
class _UiProgressTrack extends StatelessWidget {
  /// Creates a [_UiProgressTrack].
  const _UiProgressTrack({required this.value});

  /// Normalized completion ratio (`0.0..1.0`).
  final double value;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radii.pill),
      child: Container(
        height: 6.0,
        color: colors.line,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value,
          child: ColoredBox(color: colors.accent),
        ),
      ),
    );
  }
}

/// Single row inside [UiOrderedItemList] with optional highlight, reorder arrows, edit, and delete triggers.
class _UiOrderedRow<T> extends StatelessWidget {
  /// Creates a [_UiOrderedRow].
  const _UiOrderedRow({
    super.key,
    required this.index,
    required this.totalCount,
    required this.isEditing,
    required this.onReorder,
    required this.moveUpTooltip,
    required this.moveDownTooltip,
    required this.onEdit,
    required this.editTooltip,
    required this.onDelete,
    required this.deleteTooltip,
    required this.child,
  });

  /// Row content supplied by `itemBuilder`.
  final Widget child;

  /// Delete button tooltip.
  final String? deleteTooltip;

  /// Edit button tooltip.
  final String? editTooltip;

  /// Zero-based item index.
  final int index;

  /// Highlights this row with `soft` background when currently edited inline.
  final bool isEditing;

  /// Move-down button tooltip.
  final String? moveDownTooltip;

  /// Move-up button tooltip.
  final String? moveUpTooltip;

  /// Optional delete callback.
  final VoidCallback? onDelete;

  /// Optional edit callback.
  final VoidCallback? onEdit;

  /// Optional reorder callback.
  final UiOrderedItemReorderCallback? onReorder;

  /// Total list length for disabling boundary move buttons.
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final canMoveUp = index > 0;
    final canMoveDown = index < totalCount - 1;

    return Padding(
      padding: EdgeInsets.only(bottom: index < totalCount - 1 ? 4.0 : 0.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: isEditing ? colors.soft : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radii.md),
        ),
        child: Row(
          children: <Widget>[
            Expanded(child: child),
            if (onReorder case final reorder?) ...<Widget>[
              const SizedBox(width: 4.0),
              UiButton(
                leadingIcon: Icons.arrow_upward_rounded,
                variant: UiButtonVariant.icon,
                density: UiButtonDensity.sidebarDesktop,
                tooltip: moveUpTooltip,
                onPressed: canMoveUp ? () => reorder(index, index - 1) : null,
              ),
              UiButton(
                leadingIcon: Icons.arrow_downward_rounded,
                variant: UiButtonVariant.icon,
                density: UiButtonDensity.sidebarDesktop,
                tooltip: moveDownTooltip,
                onPressed: canMoveDown ? () => reorder(index, index + 1) : null,
              ),
            ],
            if (onEdit != null)
              UiButton(
                leadingIcon: Icons.edit_outlined,
                variant: UiButtonVariant.icon,
                density: UiButtonDensity.sidebarDesktop,
                tooltip: editTooltip,
                onPressed: onEdit,
              ),
            if (onDelete != null)
              UiButton(
                leadingIcon: Icons.delete_outline_rounded,
                variant: UiButtonVariant.icon,
                density: UiButtonDensity.sidebarDesktop,
                isDangerHover: true,
                tooltip: deleteTooltip,
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
