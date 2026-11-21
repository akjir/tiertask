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

import 'ui_breakpoints.dart';

/// Immutable spacing, touch-target density, icon size, and shell layout tokens (`U-TOKEN-002`..`003`).
@immutable
class UiSpacingTokens {
  /// Creates a [UiSpacingTokens] token set.
  const UiSpacingTokens({
    required this.space1,
    required this.space2,
    required this.space3,
    required this.space4,
    required this.space5,
    required this.space6,
    required this.touchTarget,
    required this.touchTargetMobile,
    required this.navRowHeight,
    required this.fieldCompactHeight,
    required this.chromeControlHeight,
    required this.buttonCompactHeight,
    required this.buttonDenseHeight,
    required this.sidebarActionDesktop,
    required this.sidebarActionCompact,
    required this.chromeHeight,
    required this.sidebarWidth,
    required this.drawerMaxWidth,
    required this.shellMaxWidth,
    required this.minConsoleHeight,
    required this.floatingNoticeInsetDesktop,
    required this.floatingNoticeInsetCompact,
    required this.cardListGap,
    required this.sectionGridGap,
    required this.chromePaddingDesktop,
    required this.chromePaddingCompact,
    required this.mainPaddingDesktop,
    required this.mainPaddingCompact,
    required this.dockPaddingDesktop,
    required this.dockPaddingCompact,
    required this.iconXs,
    required this.iconSm,
    required this.iconMd,
    required this.iconLg,
  });

  /// Canonical TierTask spacing and dimension token set.
  static const UiSpacingTokens standard = UiSpacingTokens(
    space1: 4.0,
    space2: 8.0,
    space3: 12.0,
    space4: 16.0,
    space5: 20.0,
    space6: 24.0,
    touchTarget: 40.0,
    touchTargetMobile: 44.0,
    navRowHeight: 38.0,
    fieldCompactHeight: 36.0,
    chromeControlHeight: 34.0,
    buttonCompactHeight: 32.0,
    buttonDenseHeight: 30.0,
    sidebarActionDesktop: 26.0,
    sidebarActionCompact: 34.0,
    chromeHeight: 62.0,
    sidebarWidth: 244.0,
    drawerMaxWidth: 300.0,
    shellMaxWidth: 1280.0,
    minConsoleHeight: 220.0,
    floatingNoticeInsetDesktop: 12.0,
    floatingNoticeInsetCompact: 10.0,
    cardListGap: 11.0,
    sectionGridGap: 14.0,
    chromePaddingDesktop: EdgeInsets.symmetric(
      horizontal: 16.0,
      vertical: 10.0,
    ),
    chromePaddingCompact: EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
    mainPaddingDesktop: EdgeInsets.fromLTRB(26.0, 22.0, 26.0, 24.0),
    mainPaddingCompact: EdgeInsets.fromLTRB(14.0, 16.0, 14.0, 20.0),
    dockPaddingDesktop: EdgeInsets.fromLTRB(26.0, 10.0, 26.0, 12.0),
    dockPaddingCompact: EdgeInsets.fromLTRB(14.0, 10.0, 14.0, 12.0),
    iconXs: 13.0,
    iconSm: 15.0,
    iconMd: 18.0,
    iconLg: 34.0,
  );

  /// Compact button height (`32px`).
  final double buttonCompactHeight;

  /// Dense / text button height (`30px`).
  final double buttonDenseHeight;

  /// Vertical gap between sibling entity cards (`11px`).
  final double cardListGap;

  /// Height of chrome workspace/sync pills and segmented tabs (`34px`).
  final double chromeControlHeight;

  /// Minimum height of the top chrome bar (`62px`).
  final double chromeHeight;

  /// Compact top chrome bar padding (`8x10`).
  final EdgeInsets chromePaddingCompact;

  /// Desktop top chrome bar padding (`10x16`).
  final EdgeInsets chromePaddingDesktop;

  /// Compact bottom dock padding (`10, 14, 12`).
  final EdgeInsets dockPaddingCompact;

  /// Desktop bottom dock padding (`10, 26, 12`).
  final EdgeInsets dockPaddingDesktop;

  /// Maximum width of the compact slide-over navigation drawer (`300px`).
  final double drawerMaxWidth;

  /// Compact search/field height (`36px`).
  final double fieldCompactHeight;

  /// Compact floating notice inset above the scroll viewport bottom (`10px`).
  final double floatingNoticeInsetCompact;

  /// Desktop floating notice inset above the scroll viewport bottom (`12px`).
  final double floatingNoticeInsetDesktop;

  /// Full-screen error hero icon size (`34px`).
  final double iconLg;

  /// Navigation, primary chrome, modal close, and location icon size (`18px`).
  final double iconMd;

  /// Standard button, section header, banner, and card action icon size (`15px`).
  final double iconSm;

  /// Badge, compact button, add chip, and row control icon size (`13px`).
  final double iconXs;

  /// Compact main viewport content padding (`16, 14, 20`).
  final EdgeInsets mainPaddingCompact;

  /// Desktop main viewport content padding (`22, 26, 24`).
  final EdgeInsets mainPaddingDesktop;

  /// Minimum height for Diagnostic Log Console and Raw TDF code blocks (`220px`).
  final double minConsoleHeight;

  /// Sidebar navigation row height (`38px`).
  final double navRowHeight;

  /// Gap between responsive grid cards (`14px`).
  final double sectionGridGap;

  /// Maximum outer desktop shell width (`1280px`).
  final double shellMaxWidth;

  /// Compact sidebar section header icon button size (`34px`).
  final double sidebarActionCompact;

  /// Desktop sidebar section header icon button size (`26px`).
  final double sidebarActionDesktop;

  /// Persistent desktop left sidebar width (`244px`).
  final double sidebarWidth;

  /// Base spacing unit (`4px`).
  final double space1;

  /// Small spacing unit (`8px`).
  final double space2;

  /// Medium-small spacing unit (`12px`).
  final double space3;

  /// Standard spacing unit (`16px`).
  final double space4;

  /// Medium-large spacing unit (`20px`).
  final double space5;

  /// Large spacing unit (`24px`).
  final double space6;

  /// Desktop primary hit-target height (`40px`).
  final double touchTarget;

  /// Compact/mobile primary hit-target height (`44px`).
  final double touchTargetMobile;

  /// Returns top chrome padding for [viewport].
  EdgeInsets chromePadding(UiViewportClass viewport) {
    return switch (viewport) {
      UiViewportClass.compact => chromePaddingCompact,
      UiViewportClass.medium ||
      UiViewportClass.expanded => chromePaddingDesktop,
    };
  }

  /// Returns pinned bottom dock padding for [viewport].
  EdgeInsets dockPadding(UiViewportClass viewport) {
    return switch (viewport) {
      UiViewportClass.compact => dockPaddingCompact,
      UiViewportClass.medium || UiViewportClass.expanded => dockPaddingDesktop,
    };
  }

  /// Linearly interpolates between two [UiSpacingTokens] instances at factor [t].
  static UiSpacingTokens lerp(UiSpacingTokens a, UiSpacingTokens b, double t) {
    if (t <= 0.0) {
      return a;
    }
    if (t >= 1.0) {
      return b;
    }
    return UiSpacingTokens(
      space1: lerpDouble(a.space1, b.space1, t) ?? a.space1,
      space2: lerpDouble(a.space2, b.space2, t) ?? a.space2,
      space3: lerpDouble(a.space3, b.space3, t) ?? a.space3,
      space4: lerpDouble(a.space4, b.space4, t) ?? a.space4,
      space5: lerpDouble(a.space5, b.space5, t) ?? a.space5,
      space6: lerpDouble(a.space6, b.space6, t) ?? a.space6,
      touchTarget: lerpDouble(a.touchTarget, b.touchTarget, t) ?? a.touchTarget,
      touchTargetMobile:
          lerpDouble(a.touchTargetMobile, b.touchTargetMobile, t) ??
          a.touchTargetMobile,
      navRowHeight:
          lerpDouble(a.navRowHeight, b.navRowHeight, t) ?? a.navRowHeight,
      fieldCompactHeight:
          lerpDouble(a.fieldCompactHeight, b.fieldCompactHeight, t) ??
          a.fieldCompactHeight,
      chromeControlHeight:
          lerpDouble(a.chromeControlHeight, b.chromeControlHeight, t) ??
          a.chromeControlHeight,
      buttonCompactHeight:
          lerpDouble(a.buttonCompactHeight, b.buttonCompactHeight, t) ??
          a.buttonCompactHeight,
      buttonDenseHeight:
          lerpDouble(a.buttonDenseHeight, b.buttonDenseHeight, t) ??
          a.buttonDenseHeight,
      sidebarActionDesktop:
          lerpDouble(a.sidebarActionDesktop, b.sidebarActionDesktop, t) ??
          a.sidebarActionDesktop,
      sidebarActionCompact:
          lerpDouble(a.sidebarActionCompact, b.sidebarActionCompact, t) ??
          a.sidebarActionCompact,
      chromeHeight:
          lerpDouble(a.chromeHeight, b.chromeHeight, t) ?? a.chromeHeight,
      sidebarWidth:
          lerpDouble(a.sidebarWidth, b.sidebarWidth, t) ?? a.sidebarWidth,
      drawerMaxWidth:
          lerpDouble(a.drawerMaxWidth, b.drawerMaxWidth, t) ?? a.drawerMaxWidth,
      shellMaxWidth:
          lerpDouble(a.shellMaxWidth, b.shellMaxWidth, t) ?? a.shellMaxWidth,
      minConsoleHeight:
          lerpDouble(a.minConsoleHeight, b.minConsoleHeight, t) ??
          a.minConsoleHeight,
      floatingNoticeInsetDesktop:
          lerpDouble(
            a.floatingNoticeInsetDesktop,
            b.floatingNoticeInsetDesktop,
            t,
          ) ??
          a.floatingNoticeInsetDesktop,
      floatingNoticeInsetCompact:
          lerpDouble(
            a.floatingNoticeInsetCompact,
            b.floatingNoticeInsetCompact,
            t,
          ) ??
          a.floatingNoticeInsetCompact,
      cardListGap: lerpDouble(a.cardListGap, b.cardListGap, t) ?? a.cardListGap,
      sectionGridGap:
          lerpDouble(a.sectionGridGap, b.sectionGridGap, t) ?? a.sectionGridGap,
      chromePaddingDesktop:
          EdgeInsets.lerp(a.chromePaddingDesktop, b.chromePaddingDesktop, t) ??
          a.chromePaddingDesktop,
      chromePaddingCompact:
          EdgeInsets.lerp(a.chromePaddingCompact, b.chromePaddingCompact, t) ??
          a.chromePaddingCompact,
      mainPaddingDesktop:
          EdgeInsets.lerp(a.mainPaddingDesktop, b.mainPaddingDesktop, t) ??
          a.mainPaddingDesktop,
      mainPaddingCompact:
          EdgeInsets.lerp(a.mainPaddingCompact, b.mainPaddingCompact, t) ??
          a.mainPaddingCompact,
      dockPaddingDesktop:
          EdgeInsets.lerp(a.dockPaddingDesktop, b.dockPaddingDesktop, t) ??
          a.dockPaddingDesktop,
      dockPaddingCompact:
          EdgeInsets.lerp(a.dockPaddingCompact, b.dockPaddingCompact, t) ??
          a.dockPaddingCompact,
      iconXs: lerpDouble(a.iconXs, b.iconXs, t) ?? a.iconXs,
      iconSm: lerpDouble(a.iconSm, b.iconSm, t) ?? a.iconSm,
      iconMd: lerpDouble(a.iconMd, b.iconMd, t) ?? a.iconMd,
      iconLg: lerpDouble(a.iconLg, b.iconLg, t) ?? a.iconLg,
    );
  }

  /// Returns main viewport content padding for [viewport].
  EdgeInsets mainContentPadding(UiViewportClass viewport) {
    return switch (viewport) {
      UiViewportClass.compact => mainPaddingCompact,
      UiViewportClass.medium || UiViewportClass.expanded => mainPaddingDesktop,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is UiSpacingTokens &&
        other.space1 == space1 &&
        other.space2 == space2 &&
        other.space3 == space3 &&
        other.space4 == space4 &&
        other.space5 == space5 &&
        other.space6 == space6 &&
        other.touchTarget == touchTarget &&
        other.touchTargetMobile == touchTargetMobile &&
        other.navRowHeight == navRowHeight &&
        other.fieldCompactHeight == fieldCompactHeight &&
        other.chromeControlHeight == chromeControlHeight &&
        other.buttonCompactHeight == buttonCompactHeight &&
        other.buttonDenseHeight == buttonDenseHeight &&
        other.sidebarActionDesktop == sidebarActionDesktop &&
        other.sidebarActionCompact == sidebarActionCompact &&
        other.chromeHeight == chromeHeight &&
        other.sidebarWidth == sidebarWidth &&
        other.drawerMaxWidth == drawerMaxWidth &&
        other.shellMaxWidth == shellMaxWidth &&
        other.minConsoleHeight == minConsoleHeight &&
        other.floatingNoticeInsetDesktop == floatingNoticeInsetDesktop &&
        other.floatingNoticeInsetCompact == floatingNoticeInsetCompact &&
        other.cardListGap == cardListGap &&
        other.sectionGridGap == sectionGridGap &&
        other.chromePaddingDesktop == chromePaddingDesktop &&
        other.chromePaddingCompact == chromePaddingCompact &&
        other.mainPaddingDesktop == mainPaddingDesktop &&
        other.mainPaddingCompact == mainPaddingCompact &&
        other.dockPaddingDesktop == dockPaddingDesktop &&
        other.dockPaddingCompact == dockPaddingCompact &&
        other.iconXs == iconXs &&
        other.iconSm == iconSm &&
        other.iconMd == iconMd &&
        other.iconLg == iconLg;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    space1,
    space2,
    space3,
    space4,
    space5,
    space6,
    touchTarget,
    touchTargetMobile,
    navRowHeight,
    fieldCompactHeight,
    chromeControlHeight,
    buttonCompactHeight,
    buttonDenseHeight,
    sidebarActionDesktop,
    sidebarActionCompact,
    chromeHeight,
    sidebarWidth,
    drawerMaxWidth,
    shellMaxWidth,
    minConsoleHeight,
    floatingNoticeInsetDesktop,
    floatingNoticeInsetCompact,
    cardListGap,
    sectionGridGap,
    chromePaddingDesktop,
    chromePaddingCompact,
    mainPaddingDesktop,
    mainPaddingCompact,
    dockPaddingDesktop,
    dockPaddingCompact,
    iconXs,
    iconSm,
    iconMd,
    iconLg,
  ]);
}
