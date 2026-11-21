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
import 'package:tiertask/presentation/shell_models.dart';
import 'package:tiertask/presentation/view_model_primitives.dart';
import 'package:tiertask/ui/ui_icon_mapper.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

void main() {
  group('UiIconMapper', () {
    test('maps every ShellTier, BadgeTone, BannerTone, NoticeTone, CardBadgeIconKey, SyncStatusKind, LocationStatusKind, ThemePresetKey, and ShellThemeMode exhaustively', () {
      for (final tier in ShellTier.values) {
        expect(
          UiIconMapper.tierIcon(tier),
          isA<IconData>(),
          reason: 'Every ShellTier must resolve a canonical icon',
        );
      }
      for (final tone in BadgeTone.values) {
        expect(
          UiIconMapper.pillTone(tone),
          isA<UiPillTone>(),
          reason: 'Every BadgeTone must resolve a UiPillTone',
        );
      }
      for (final tone in BannerTone.values) {
        expect(
          UiIconMapper.bannerTone(tone),
          isA<UiBannerTone>(),
          reason: 'Every BannerTone must resolve a UiBannerTone',
        );
      }
      for (final tone in NoticeTone.values) {
        expect(
          UiIconMapper.noticeTone(tone),
          isA<UiBannerTone>(),
          reason: 'Every NoticeTone must resolve a UiBannerTone',
        );
      }
      for (final iconKey in CardBadgeIconKey.values) {
        expect(
          UiIconMapper.badgeIcon(iconKey),
          isA<IconData>(),
          reason: 'Every CardBadgeIconKey must resolve an IconData',
        );
      }
      for (final status in ShellSyncStatusKind.values) {
        expect(
          UiIconMapper.syncIcon(status),
          isA<IconData>(),
          reason: 'Every ShellSyncStatusKind must resolve an icon',
        );
        expect(
          UiIconMapper.syncButtonTone(status),
          isA<UiButtonTone>(),
          reason: 'Every ShellSyncStatusKind must resolve a button tone',
        );
      }
      for (final locationStatus in ShellLocationStatusKind.values) {
        expect(
          UiIconMapper.locationIcon(locationStatus),
          isA<IconData>(),
          reason: 'Every ShellLocationStatusKind must resolve an icon',
        );
        expect(
          UiIconMapper.locationButtonTone(locationStatus),
          isA<UiButtonTone>(),
          reason: 'Every ShellLocationStatusKind must resolve a button tone',
        );
      }
      expect(
        UiIconMapper.locationButtonTone(ShellLocationStatusKind.found),
        equals(UiButtonTone.accent),
        reason: 'Active GPS fix must tint chrome location button in accent',
      );
      expect(
        UiIconMapper.locationButtonTone(ShellLocationStatusKind.searching),
        equals(UiButtonTone.neutral),
      );
      expect(
        UiIconMapper.locationButtonTone(ShellLocationStatusKind.unavailable),
        equals(UiButtonTone.neutral),
      );
      expect(
        UiIconMapper.locationButtonTone(ShellLocationStatusKind.disabled),
        equals(UiButtonTone.neutral),
      );
      expect(
        UiIconMapper.locationIcon(ShellLocationStatusKind.found),
        equals(Icons.my_location_rounded),
      );
      expect(
        UiIconMapper.locationIcon(ShellLocationStatusKind.searching),
        equals(Icons.refresh_rounded),
      );
      expect(
        UiIconMapper.locationIcon(ShellLocationStatusKind.unavailable),
        equals(Icons.location_disabled_rounded),
      );
      expect(
        UiIconMapper.locationIcon(ShellLocationStatusKind.disabled),
        equals(Icons.location_disabled_rounded),
      );

      expect(
        UiIconMapper.syncIcon(ShellSyncStatusKind.localOnly),
        equals(Icons.folder_outlined),
      );
      expect(
        UiIconMapper.syncIcon(ShellSyncStatusKind.synced),
        equals(Icons.cloud_done_outlined),
      );
      expect(
        UiIconMapper.syncIcon(ShellSyncStatusKind.syncing),
        equals(Icons.refresh_rounded),
      );
      expect(
        UiIconMapper.syncIcon(ShellSyncStatusKind.conflict),
        equals(Icons.warning_amber_rounded),
      );
      expect(
        UiIconMapper.syncIcon(ShellSyncStatusKind.error),
        equals(Icons.cloud_off_outlined),
      );
      expect(
        UiIconMapper.syncButtonTone(ShellSyncStatusKind.localOnly),
        equals(UiButtonTone.muted),
      );
      expect(
        UiIconMapper.syncButtonTone(ShellSyncStatusKind.synced),
        equals(UiButtonTone.muted),
      );
      expect(
        UiIconMapper.syncButtonTone(ShellSyncStatusKind.syncing),
        equals(UiButtonTone.muted),
      );
      expect(
        UiIconMapper.syncButtonTone(ShellSyncStatusKind.conflict),
        equals(UiButtonTone.warning),
      );
      expect(
        UiIconMapper.syncButtonTone(ShellSyncStatusKind.error),
        equals(UiButtonTone.danger),
      );
      for (final presetKey in AppThemePresetKey.values) {
        final preset = UiIconMapper.themePreset(presetKey);
        expect(
          preset.id,
          equals(presetKey.presetId),
          reason: 'UiThemePreset.id must match AppThemePresetKey.presetId',
        );
      }
      expect(
        UiIconMapper.flutterThemeMode(ShellThemeMode.system),
        equals(ThemeMode.system),
      );
      expect(
        UiIconMapper.flutterThemeMode(ShellThemeMode.light),
        equals(ThemeMode.light),
      );
      expect(
        UiIconMapper.flutterThemeMode(ShellThemeMode.dark),
        equals(ThemeMode.dark),
      );
    });
  });
}
