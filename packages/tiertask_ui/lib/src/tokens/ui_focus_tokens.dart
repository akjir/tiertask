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

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

/// Immutable focus ring, motion duration, dimmed opacity, and allowlisted shadow tokens (`U-SURFACE-002`, `U-A11Y-004`).
@immutable
class UiFocusTokens {
  /// Creates a [UiFocusTokens] token set.
  const UiFocusTokens({
    required this.ringWidth,
    required this.ringOffset,
    required this.hoverDuration,
    required this.expandDuration,
    required this.fadeDuration,
    required this.spinDuration,
    required this.loadingSpinDuration,
    required this.disabledOpacity,
    required this.prereqDisabledOpacity,
    required this.suspendedDimmedOpacity,
    required this.readonlyOpacity,
    required this.segmentedShadow,
    required this.toastShadow,
    required this.popoverShadow,
    required this.bottomSheetShadow,
    required this.modalShadow,
  });

  /// Canonical TierTask focus, motion, opacity, and shadow tokens.
  static const UiFocusTokens standard = UiFocusTokens(
    ringWidth: 1.0,
    ringOffset: 1.0,
    hoverDuration: Duration(milliseconds: 120),
    expandDuration: Duration(milliseconds: 220),
    fadeDuration: Duration(milliseconds: 180),
    spinDuration: Duration(milliseconds: 1000),
    loadingSpinDuration: Duration(milliseconds: 850),
    disabledOpacity: 0.48,
    prereqDisabledOpacity: 0.50,
    suspendedDimmedOpacity: 0.45,
    readonlyOpacity: 0.72,
    segmentedShadow: <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.06),
        offset: Offset(0, 1),
        blurRadius: 2.0,
      ),
    ],
    toastShadow: <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.20),
        offset: Offset(0, 8),
        blurRadius: 24.0,
      ),
    ],
    popoverShadow: <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.24),
        offset: Offset(0, 14),
        blurRadius: 36.0,
      ),
    ],
    bottomSheetShadow: <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.28),
        offset: Offset(0, -10),
        blurRadius: 30.0,
      ),
    ],
    modalShadow: <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.24),
        offset: Offset(0, 18),
        blurRadius: 42.0,
      ),
    ],
  );

  /// Compact modal bottom sheet elevation shadow (`0 -10px 30px rgba(0, 0, 0, 0.28)`).
  final List<BoxShadow> bottomSheetShadow;

  /// Standard disabled interactive control opacity (`0.48`).
  final double disabledOpacity;

  /// Entity card accordion expand/collapse size duration (`220ms`).
  final Duration expandDuration;

  /// Entity card accordion opacity reveal duration (`180ms`).
  final Duration fadeDuration;

  /// Crisp hover/border state transition duration (`120ms`).
  final Duration hoverDuration;

  /// Initial loading indicator spin rotation duration (`850ms`).
  final Duration loadingSpinDuration;

  /// Centered modal dialog elevation shadow (`0 18px 42px rgba(0, 0, 0, 0.24)`).
  final List<BoxShadow> modalShadow;

  /// Desktop upward popover elevation shadow (`0 14px 36px rgba(0, 0, 0, 0.24)`).
  final List<BoxShadow> popoverShadow;

  /// Cycle-prevented prerequisite row opacity (`0.50`).
  final double prereqDisabledOpacity;

  /// Read-only field display opacity (`0.72`).
  final double readonlyOpacity;

  /// Outer focus-visible ring offset in logical pixels (`1.0px`).
  final double ringOffset;

  /// Outer focus-visible ring border width in logical pixels (`1.0px`).
  final double ringWidth;

  /// Selected segmented control tab shadow (`0 1px 2px rgba(0, 0, 0, 0.06)`).
  final List<BoxShadow> segmentedShadow;

  /// Active sync/location icon rotation duration (`1000ms`).
  final Duration spinDuration;

  /// Suspended-task disabled condition control opacity (`0.45`).
  final double suspendedDimmedOpacity;

  /// Floating toast / Undo overlay shadow (`0 8px 24px rgba(0, 0, 0, 0.20)`).
  final List<BoxShadow> toastShadow;

  /// Linearly interpolates between two [UiFocusTokens] instances at factor [t].
  static UiFocusTokens lerp(UiFocusTokens a, UiFocusTokens b, double t) {
    if (t <= 0.0) {
      return a;
    }
    if (t >= 1.0) {
      return b;
    }
    return UiFocusTokens(
      ringWidth: lerpDouble(a.ringWidth, b.ringWidth, t) ?? a.ringWidth,
      ringOffset: lerpDouble(a.ringOffset, b.ringOffset, t) ?? a.ringOffset,
      hoverDuration: t < 0.5 ? a.hoverDuration : b.hoverDuration,
      expandDuration: t < 0.5 ? a.expandDuration : b.expandDuration,
      fadeDuration: t < 0.5 ? a.fadeDuration : b.fadeDuration,
      spinDuration: t < 0.5 ? a.spinDuration : b.spinDuration,
      loadingSpinDuration: t < 0.5
          ? a.loadingSpinDuration
          : b.loadingSpinDuration,
      disabledOpacity:
          lerpDouble(a.disabledOpacity, b.disabledOpacity, t) ??
          a.disabledOpacity,
      prereqDisabledOpacity:
          lerpDouble(a.prereqDisabledOpacity, b.prereqDisabledOpacity, t) ??
          a.prereqDisabledOpacity,
      suspendedDimmedOpacity:
          lerpDouble(a.suspendedDimmedOpacity, b.suspendedDimmedOpacity, t) ??
          a.suspendedDimmedOpacity,
      readonlyOpacity:
          lerpDouble(a.readonlyOpacity, b.readonlyOpacity, t) ??
          a.readonlyOpacity,
      segmentedShadow:
          BoxShadow.lerpList(a.segmentedShadow, b.segmentedShadow, t) ??
          a.segmentedShadow,
      toastShadow:
          BoxShadow.lerpList(a.toastShadow, b.toastShadow, t) ?? a.toastShadow,
      popoverShadow:
          BoxShadow.lerpList(a.popoverShadow, b.popoverShadow, t) ??
          a.popoverShadow,
      bottomSheetShadow:
          BoxShadow.lerpList(a.bottomSheetShadow, b.bottomSheetShadow, t) ??
          a.bottomSheetShadow,
      modalShadow:
          BoxShadow.lerpList(a.modalShadow, b.modalShadow, t) ?? a.modalShadow,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is UiFocusTokens &&
        other.ringWidth == ringWidth &&
        other.ringOffset == ringOffset &&
        other.hoverDuration == hoverDuration &&
        other.expandDuration == expandDuration &&
        other.fadeDuration == fadeDuration &&
        other.spinDuration == spinDuration &&
        other.loadingSpinDuration == loadingSpinDuration &&
        other.disabledOpacity == disabledOpacity &&
        other.prereqDisabledOpacity == prereqDisabledOpacity &&
        other.suspendedDimmedOpacity == suspendedDimmedOpacity &&
        other.readonlyOpacity == readonlyOpacity &&
        listEquals(other.segmentedShadow, segmentedShadow) &&
        listEquals(other.toastShadow, toastShadow) &&
        listEquals(other.popoverShadow, popoverShadow) &&
        listEquals(other.bottomSheetShadow, bottomSheetShadow) &&
        listEquals(other.modalShadow, modalShadow);
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    ringWidth,
    ringOffset,
    hoverDuration,
    expandDuration,
    fadeDuration,
    spinDuration,
    loadingSpinDuration,
    disabledOpacity,
    prereqDisabledOpacity,
    suspendedDimmedOpacity,
    readonlyOpacity,
    Object.hashAll(segmentedShadow),
    Object.hashAll(toastShadow),
    Object.hashAll(popoverShadow),
    Object.hashAll(bottomSheetShadow),
    Object.hashAll(modalShadow),
  ]);
}
