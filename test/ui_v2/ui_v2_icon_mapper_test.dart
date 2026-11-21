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

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/presentation/board_v2_view_models.dart';
import 'package:tiertask/presentation/ui_v2_shell_models.dart';
import 'package:tiertask/ui_v2/ui_v2_icon_mapper.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

void main() {
  group('UiV2IconMapper', () {
    test('maps every ShellTier, BadgeTone, BannerTone, NoticeTone, CardBadgeIconKey, SyncStatusKind, LocationStatusKind, ThemePresetKey, and ShellThemeMode exhaustively', () {
      for (final tier in ShellTier.values) {
        expect(
          UiV2IconMapper.tierIcon(tier),
          isA<IconData>(),
          reason: 'Every ShellTier must resolve a canonical icon',
        );
      }
      for (final tone in BadgeTone.values) {
        expect(
          UiV2IconMapper.pillTone(tone),
          isA<UiPillTone>(),
          reason: 'Every BadgeTone must resolve a UiPillTone',
        );
      }
      for (final tone in BannerTone.values) {
        expect(
          UiV2IconMapper.bannerTone(tone),
          isA<UiBannerTone>(),
          reason: 'Every BannerTone must resolve a UiBannerTone',
        );
      }
      for (final tone in NoticeTone.values) {
        expect(
          UiV2IconMapper.noticeTone(tone),
          isA<UiBannerTone>(),
          reason: 'Every NoticeTone must resolve a UiBannerTone',
        );
      }
      for (final iconKey in CardBadgeIconKey.values) {
        expect(
          UiV2IconMapper.badgeIcon(iconKey),
          isA<IconData>(),
          reason: 'Every CardBadgeIconKey must resolve an IconData',
        );
      }
      for (final status in ShellSyncStatusKind.values) {
        expect(
          UiV2IconMapper.syncIcon(status),
          isA<IconData>(),
          reason: 'Every ShellSyncStatusKind must resolve an icon',
        );
        expect(
          UiV2IconMapper.syncButtonTone(status),
          isA<UiButtonTone>(),
          reason: 'Every ShellSyncStatusKind must resolve a button tone',
        );
      }
      for (final locationStatus in ShellLocationStatusKind.values) {
        expect(
          UiV2IconMapper.locationIcon(locationStatus),
          isA<IconData>(),
          reason: 'Every ShellLocationStatusKind must resolve an icon',
        );
        expect(
          UiV2IconMapper.locationButtonTone(locationStatus),
          isA<UiButtonTone>(),
          reason: 'Every ShellLocationStatusKind must resolve a button tone',
        );
      }
      expect(
        UiV2IconMapper.locationButtonTone(ShellLocationStatusKind.found),
        equals(UiButtonTone.accent),
        reason: 'Active GPS fix must tint chrome location button in accent',
      );
      expect(
        UiV2IconMapper.locationButtonTone(ShellLocationStatusKind.searching),
        equals(UiButtonTone.neutral),
      );
      expect(
        UiV2IconMapper.locationButtonTone(ShellLocationStatusKind.unavailable),
        equals(UiButtonTone.neutral),
      );
      expect(
        UiV2IconMapper.locationButtonTone(ShellLocationStatusKind.disabled),
        equals(UiButtonTone.neutral),
      );
      expect(
        UiV2IconMapper.locationIcon(ShellLocationStatusKind.found),
        equals(Icons.my_location_rounded),
      );
      expect(
        UiV2IconMapper.locationIcon(ShellLocationStatusKind.searching),
        equals(Icons.refresh_rounded),
      );
      expect(
        UiV2IconMapper.locationIcon(ShellLocationStatusKind.unavailable),
        equals(Icons.location_disabled_rounded),
      );
      expect(
        UiV2IconMapper.locationIcon(ShellLocationStatusKind.disabled),
        equals(Icons.location_disabled_rounded),
      );

      expect(
        UiV2IconMapper.syncIcon(ShellSyncStatusKind.localOnly),
        equals(Icons.folder_outlined),
      );
      expect(
        UiV2IconMapper.syncIcon(ShellSyncStatusKind.synced),
        equals(Icons.cloud_done_outlined),
      );
      expect(
        UiV2IconMapper.syncIcon(ShellSyncStatusKind.syncing),
        equals(Icons.refresh_rounded),
      );
      expect(
        UiV2IconMapper.syncIcon(ShellSyncStatusKind.conflict),
        equals(Icons.warning_amber_rounded),
      );
      expect(
        UiV2IconMapper.syncIcon(ShellSyncStatusKind.error),
        equals(Icons.cloud_off_outlined),
      );
      expect(
        UiV2IconMapper.syncButtonTone(ShellSyncStatusKind.localOnly),
        equals(UiButtonTone.muted),
      );
      expect(
        UiV2IconMapper.syncButtonTone(ShellSyncStatusKind.synced),
        equals(UiButtonTone.muted),
      );
      expect(
        UiV2IconMapper.syncButtonTone(ShellSyncStatusKind.syncing),
        equals(UiButtonTone.muted),
      );
      expect(
        UiV2IconMapper.syncButtonTone(ShellSyncStatusKind.conflict),
        equals(UiButtonTone.warning),
      );
      expect(
        UiV2IconMapper.syncButtonTone(ShellSyncStatusKind.error),
        equals(UiButtonTone.danger),
      );
      for (final presetKey in AppThemePresetKey.values) {
        final preset = UiV2IconMapper.themePreset(presetKey);
        expect(
          preset.id,
          equals(presetKey.presetId),
          reason: 'UiThemePreset.id must match AppThemePresetKey.presetId',
        );
      }
      expect(
        UiV2IconMapper.flutterThemeMode(ShellThemeMode.system),
        equals(ThemeMode.system),
      );
      expect(
        UiV2IconMapper.flutterThemeMode(ShellThemeMode.light),
        equals(ThemeMode.light),
      );
      expect(
        UiV2IconMapper.flutterThemeMode(ShellThemeMode.dark),
        equals(ThemeMode.dark),
      );
    });
  });
}
