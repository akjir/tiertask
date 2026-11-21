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

import '../presentation/board_v2_view_models.dart';
import '../presentation/ui_v2_shell_models.dart';

/// Pure Rank 7 mapper converting model-free presentation enums to `packages/tiertask_ui/`
/// tokens, tones, theme presets, and outline icons (`U-BRAND-003`..`004`).
class UiV2IconMapper {
  /// Prevents instantiation of this stateless helper class.
  const UiV2IconMapper._();

  /// Maps a collapsed badge [iconKey] to its outline [IconData].
  static IconData badgeIcon(CardBadgeIconKey iconKey) {
    return switch (iconKey) {
      CardBadgeIconKey.tierFocus => tierIcon(ShellTier.focus),
      CardBadgeIconKey.tierReady => tierIcon(ShellTier.ready),
      CardBadgeIconKey.tierPlanned => tierIcon(ShellTier.planned),
      CardBadgeIconKey.tierBlocked => tierIcon(ShellTier.blocked),
      CardBadgeIconKey.tierSomeday => tierIcon(ShellTier.someday),
      CardBadgeIconKey.tierCompleted => tierIcon(ShellTier.completed),
      CardBadgeIconKey.due => Icons.calendar_today_outlined,
      CardBadgeIconKey.priority => Icons.bolt_outlined,
      CardBadgeIconKey.suspended => Icons.pause_circle_outline_rounded,
      CardBadgeIconKey.blockedBy => Icons.lock_outline_rounded,
      CardBadgeIconKey.conditions => Icons.tune_rounded,
      CardBadgeIconKey.subtasks => Icons.checklist_rounded,
      CardBadgeIconKey.subtasksAutoFinish => Icons.check_box_outlined,
      CardBadgeIconKey.repeat => Icons.repeat_rounded,
      CardBadgeIconKey.note => Icons.description_outlined,
      CardBadgeIconKey.links => Icons.link_rounded,
      CardBadgeIconKey.history => Icons.history_rounded,
    };
  }

  /// Maps presentation [BannerTone] to design-system [UiBannerTone].
  static UiBannerTone bannerTone(BannerTone tone) {
    return switch (tone) {
      BannerTone.warning => UiBannerTone.warning,
      BannerTone.danger => UiBannerTone.danger,
      BannerTone.success => UiBannerTone.success,
    };
  }

  /// Maps presentation [ShellThemeMode] to Flutter [ThemeMode].
  static ThemeMode flutterThemeMode(ShellThemeMode mode) {
    return switch (mode) {
      ShellThemeMode.system => ThemeMode.system,
      ShellThemeMode.light => ThemeMode.light,
      ShellThemeMode.dark => ThemeMode.dark,
    };
  }

  /// Maps presentation [ShellLocationStatusKind] to its outline [IconData].
  static IconData locationIcon(ShellLocationStatusKind status) {
    return switch (status) {
      ShellLocationStatusKind.disabled => Icons.location_off_outlined,
      ShellLocationStatusKind.searching => Icons.gps_not_fixed_rounded,
      ShellLocationStatusKind.found => Icons.my_location_rounded,
      ShellLocationStatusKind.unavailable => Icons.location_searching_rounded,
    };
  }

  /// Maps presentation [NoticeTone] to design-system [UiBannerTone].
  static UiBannerTone noticeTone(NoticeTone tone) {
    return switch (tone) {
      NoticeTone.neutral || NoticeTone.accent => UiBannerTone.neutral,
      NoticeTone.warning => UiBannerTone.warning,
      NoticeTone.danger => UiBannerTone.danger,
      NoticeTone.success => UiBannerTone.success,
    };
  }

  /// Maps presentation [BadgeTone] to design-system [UiPillTone].
  static UiPillTone pillTone(BadgeTone tone) {
    return switch (tone) {
      BadgeTone.neutral => UiPillTone.neutral,
      BadgeTone.soft => UiPillTone.soft,
      BadgeTone.accent => UiPillTone.accent,
      BadgeTone.warning => UiPillTone.warning,
      BadgeTone.danger => UiPillTone.danger,
      BadgeTone.success => UiPillTone.success,
    };
  }

  /// Maps presentation [ShellSyncStatusKind] to its chrome [UiButtonTone].
  static UiButtonTone syncButtonTone(ShellSyncStatusKind status) {
    return switch (status) {
      ShellSyncStatusKind.localOnly ||
      ShellSyncStatusKind.synced ||
      ShellSyncStatusKind.syncing => UiButtonTone.neutral,
      ShellSyncStatusKind.conflict => UiButtonTone.warning,
      ShellSyncStatusKind.error => UiButtonTone.danger,
    };
  }

  /// Maps presentation [ShellSyncStatusKind] to its outline [IconData].
  static IconData syncIcon(ShellSyncStatusKind status) {
    return switch (status) {
      ShellSyncStatusKind.localOnly => Icons.cloud_off_outlined,
      ShellSyncStatusKind.synced => Icons.cloud_done_outlined,
      ShellSyncStatusKind.syncing => Icons.sync_rounded,
      ShellSyncStatusKind.conflict => Icons.warning_amber_rounded,
      ShellSyncStatusKind.error => Icons.error_outline_rounded,
    };
  }

  /// Maps presentation [AppThemePresetKey] to its WCAG AA [UiThemePreset].
  static UiThemePreset themePreset(AppThemePresetKey key) =>
      UiThemePresets.byId(key.presetId);

  /// Maps presentation [ShellTier] to its canonical outline icon (`U-BRAND-004`).
  static IconData tierIcon(ShellTier tier) {
    return switch (tier) {
      ShellTier.focus => Icons.bolt_outlined,
      ShellTier.ready => Icons.format_list_numbered_rounded,
      ShellTier.planned => Icons.calendar_today_outlined,
      ShellTier.blocked => Icons.block_outlined,
      ShellTier.someday => Icons.lightbulb_outline_rounded,
      ShellTier.completed => Icons.check_circle_outline_rounded,
    };
  }
}
