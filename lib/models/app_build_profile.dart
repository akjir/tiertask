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

import 'package:flutter/foundation.dart';

/// Build storage profile separating development data from release data.
enum AppBuildProfile {
  /// Production release profile using default directories and secure storage keys.
  release,

  /// Development profile using isolated directories and secure storage keys.
  dev;

  /// Compile-time environment key (`--dart-define=TIERTASK_ENV=dev|release`).
  static const String environmentKey = 'TIERTASK_ENV';

  /// Raw compile-time value supplied via `--dart-define=TIERTASK_ENV=...`.
  static const String rawEnvironmentValue = String.fromEnvironment(
    environmentKey,
  );

  /// Active build profile resolved from [rawEnvironmentValue] and [kReleaseMode].
  static AppBuildProfile get current =>
      resolve(rawEnvironment: rawEnvironmentValue, isReleaseMode: kReleaseMode);

  /// Local user data directory leaf name (`tiertask` for release, `tiertask-dev` for dev).
  String get dataDirectoryName => switch (this) {
    AppBuildProfile.release => 'tiertask',
    AppBuildProfile.dev => 'tiertask-dev',
  };

  /// Whether this profile is the isolated development profile.
  bool get isDev => this == AppBuildProfile.dev;

  /// Encrypted storage key for persisted workspace settings (`t2_settings_v1` or `t2_dev_settings_v1`).
  String get settingsStorageKey => switch (this) {
    AppBuildProfile.release => 't2_settings_v1',
    AppBuildProfile.dev => 't2_dev_settings_v1',
  };

  /// Encrypted storage key prefix for per-workspace sync baselines (`t2_sync_v1_` or `t2_dev_sync_v1_`).
  String get syncStorageKeyPrefix => switch (this) {
    AppBuildProfile.release => 't2_sync_v1_',
    AppBuildProfile.dev => 't2_dev_sync_v1_',
  };

  /// Formats [baseTitle] for window and task switcher titles, appending `(Dev)` in development builds.
  String formatWindowTitle(String baseTitle) => switch (this) {
    AppBuildProfile.release => baseTitle,
    AppBuildProfile.dev => '$baseTitle (Dev)',
  };

  /// Resolves the active [AppBuildProfile] from [rawEnvironment] (`dev` or `release`) with [isReleaseMode] fallback.
  static AppBuildProfile resolve({
    required String rawEnvironment,
    required bool isReleaseMode,
  }) {
    final normalized = rawEnvironment.trim().toLowerCase();
    if (normalized == 'dev') {
      return AppBuildProfile.dev;
    }
    if (normalized == 'release') {
      return AppBuildProfile.release;
    }
    return isReleaseMode ? AppBuildProfile.release : AppBuildProfile.dev;
  }
}
