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

/// Canonical viewport width class derived from [UiBreakpoints].
enum UiViewportClass {
  /// Compact mobile viewport (`width <= 720`).
  compact,

  /// Medium tablet or narrow desktop viewport (`720 < width <= 820`).
  medium,

  /// Expanded desktop viewport (`width > 820`).
  expanded,
}

/// Stateless non-overlapping breakpoint partition helpers (`U-LAYOUT-001`).
class UiBreakpoints {
  const UiBreakpoints._();

  /// Maximum logical width classified as [UiViewportClass.compact].
  static const double compactMaxWidth = 720.0;

  /// Maximum logical width classified as [UiViewportClass.medium].
  static const double mediumMaxWidth = 820.0;

  /// Classifies [width] into one of the three canonical viewport classes.
  static UiViewportClass classify(double width) {
    if (width <= compactMaxWidth) {
      return UiViewportClass.compact;
    }
    if (width <= mediumMaxWidth) {
      return UiViewportClass.medium;
    }
    return UiViewportClass.expanded;
  }

  /// Returns whether [width] falls in [UiViewportClass.compact] (`<= 720`).
  static bool isCompact(double width) => width <= compactMaxWidth;

  /// Returns whether [width] falls in [UiViewportClass.expanded] (`> 820`).
  static bool isExpanded(double width) => width > mediumMaxWidth;

  /// Returns whether [width] is compact or medium (`<= 820`).
  static bool isMediumOrSmaller(double width) => width <= mediumMaxWidth;
}
