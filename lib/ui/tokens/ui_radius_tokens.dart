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

import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

/// Immutable corner radius and stroke width tokens (`U-TOKEN-004`).
@immutable
class UiRadiusTokens {
  /// Creates a [UiRadiusTokens] token set.
  const UiRadiusTokens({
    required this.logoBar,
    required this.dotSm,
    required this.dotLg,
    required this.tag,
    required this.sm,
    required this.md,
    required this.tierSelect,
    required this.row,
    required this.card,
    required this.shell,
    required this.pill,
    required this.borderWidth,
    required this.circleBorderWidth,
    required this.spinnerStrokeWidth,
  });

  /// Canonical TierTask radius and border width tokens.
  static const UiRadiusTokens standard = UiRadiusTokens(
    logoBar: 2.0,
    dotSm: 3.0,
    dotLg: 4.0,
    tag: 6.0,
    sm: 7.0,
    md: 8.0,
    tierSelect: 9.0,
    row: 11.0,
    card: 13.0,
    shell: 16.0,
    pill: 999.0,
    borderWidth: 1.0,
    circleBorderWidth: 1.7,
    spinnerStrokeWidth: 2.5,
  );

  /// Standard hairline border width (`1.0px`).
  final double borderWidth;

  /// Top-level entity, draft, static, and console card radius (`13.0px`).
  final double card;

  /// Task completion circle stroke width (`1.7px`).
  final double circleBorderWidth;

  /// Large color dot, custom checkbox, keyboard hint, and log line radius (`4.0px`).
  final double dotLg;

  /// Small `8px` color dot radius (`3.0px`).
  final double dotSm;

  /// Logo bar corner radius (`2.0px`).
  final double logoBar;

  /// Standard buttons, inputs, selects, segmented trough, and nav row radius (`8.0px`).
  final double md;

  /// Full pill capsule radius (`999.0px`).
  final double pill;

  /// Nested inset well, banner, toast, and workspace card radius (`11.0px`).
  final double row;

  /// App shell frame, modal dialog, and bottom sheet top radius (`16.0px`).
  final double shell;

  /// Sidebar header icon buttons, inline filter chip, and picker row radius (`7.0px`).
  final double sm;

  /// Loading spinner stroke width (`2.5px`).
  final double spinnerStrokeWidth;

  /// Badge, chip, pill, segmented button, and `DEV` badge radius (`6.0px`).
  final double tag;

  /// Compact mobile tier dropdown radius (`9.0px`).
  final double tierSelect;

  /// Linearly interpolates between two [UiRadiusTokens] instances at factor [t].
  static UiRadiusTokens lerp(UiRadiusTokens a, UiRadiusTokens b, double t) {
    if (t <= 0.0) {
      return a;
    }
    if (t >= 1.0) {
      return b;
    }
    return UiRadiusTokens(
      logoBar: lerpDouble(a.logoBar, b.logoBar, t) ?? a.logoBar,
      dotSm: lerpDouble(a.dotSm, b.dotSm, t) ?? a.dotSm,
      dotLg: lerpDouble(a.dotLg, b.dotLg, t) ?? a.dotLg,
      tag: lerpDouble(a.tag, b.tag, t) ?? a.tag,
      sm: lerpDouble(a.sm, b.sm, t) ?? a.sm,
      md: lerpDouble(a.md, b.md, t) ?? a.md,
      tierSelect: lerpDouble(a.tierSelect, b.tierSelect, t) ?? a.tierSelect,
      row: lerpDouble(a.row, b.row, t) ?? a.row,
      card: lerpDouble(a.card, b.card, t) ?? a.card,
      shell: lerpDouble(a.shell, b.shell, t) ?? a.shell,
      pill: lerpDouble(a.pill, b.pill, t) ?? a.pill,
      borderWidth: lerpDouble(a.borderWidth, b.borderWidth, t) ?? a.borderWidth,
      circleBorderWidth:
          lerpDouble(a.circleBorderWidth, b.circleBorderWidth, t) ??
          a.circleBorderWidth,
      spinnerStrokeWidth:
          lerpDouble(a.spinnerStrokeWidth, b.spinnerStrokeWidth, t) ??
          a.spinnerStrokeWidth,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is UiRadiusTokens &&
        other.logoBar == logoBar &&
        other.dotSm == dotSm &&
        other.dotLg == dotLg &&
        other.tag == tag &&
        other.sm == sm &&
        other.md == md &&
        other.tierSelect == tierSelect &&
        other.row == row &&
        other.card == card &&
        other.shell == shell &&
        other.pill == pill &&
        other.borderWidth == borderWidth &&
        other.circleBorderWidth == circleBorderWidth &&
        other.spinnerStrokeWidth == spinnerStrokeWidth;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    logoBar,
    dotSm,
    dotLg,
    tag,
    sm,
    md,
    tierSelect,
    row,
    card,
    shell,
    pill,
    borderWidth,
    circleBorderWidth,
    spinnerStrokeWidth,
  ]);
}
