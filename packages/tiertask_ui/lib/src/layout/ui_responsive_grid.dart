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

import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';

/// Canonical responsive column collapse presets mapped to [UiBreakpoints] (`U-LAYOUT-006`).
enum UiGridPreset {
  /// Two columns on `expanded` (`> 820px`), collapsing to one column at `<= 820px`.
  twoColumnMediumCollapse,

  /// Two columns above `compact` (`> 720px`), collapsing to one column at `<= 720px`.
  twoColumnCompactCollapse,

  /// Four action columns above `compact` (`> 720px`), collapsing to `2x2` at `<= 720px`.
  fourActionCompactTwo,
}

/// Equal-width, top-aligned adaptive grid honoring `UiBreakpoints` with zero horizontal overflow (`U-LAYOUT-006`).
class UiResponsiveGrid extends StatelessWidget {
  /// Creates a [UiResponsiveGrid].
  const UiResponsiveGrid({
    super.key,
    required this.preset,
    required this.children,
    this.spacing,
    this.runSpacing,
  });

  /// Grid items laid out in equal-width columns.
  final List<Widget> children;

  /// Responsive breakpoint collapse preset.
  final UiGridPreset preset;

  /// Optional vertical gap between rows (defaults to `tokens.spacing.sectionGridGap`).
  final double? runSpacing;

  /// Optional horizontal gap between columns (defaults to `tokens.spacing.sectionGridGap`).
  final double? spacing;

  /// Resolves the deterministic column count for [preset] at [width].
  static int columnsForWidth(UiGridPreset preset, double width) {
    return switch (preset) {
      UiGridPreset.twoColumnMediumCollapse =>
        UiBreakpoints.isExpanded(width) ? 2 : 1,
      UiGridPreset.twoColumnCompactCollapse =>
        UiBreakpoints.isCompact(width) ? 1 : 2,
      UiGridPreset.fourActionCompactTwo =>
        UiBreakpoints.isCompact(width) ? 2 : 4,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = UiThemeTokens.of(context);
    final gapX = spacing ?? tokens.spacing.sectionGridGap;
    final gapY = runSpacing ?? tokens.spacing.sectionGridGap;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final columns = columnsForWidth(preset, width);
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          if (rows.isNotEmpty) {
            rows.add(SizedBox(height: gapY));
          }
          rows.add(
            _UiGridRow(
              startIndex: start,
              columns: columns,
              spacing: gapX,
              children: children,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }
}

/// Renders one equal-width, top-aligned row slice inside [UiResponsiveGrid].
class _UiGridRow extends StatelessWidget {
  /// Creates a [_UiGridRow].
  const _UiGridRow({
    required this.children,
    required this.startIndex,
    required this.columns,
    required this.spacing,
  });

  /// Full grid child list.
  final List<Widget> children;

  /// Column count for this row.
  final int columns;

  /// Horizontal gap between sibling columns.
  final double spacing;

  /// First item index in [children] for this row.
  final int startIndex;

  @override
  Widget build(BuildContext context) {
    final rowWidgets = <Widget>[];
    for (var col = 0; col < columns; col++) {
      if (col > 0) {
        rowWidgets.add(SizedBox(width: spacing));
      }
      final itemIndex = startIndex + col;
      rowWidgets.add(
        Expanded(
          child: itemIndex < children.length
              ? children[itemIndex]
              : const SizedBox.shrink(),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rowWidgets,
    );
  }
}
