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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/app_build_profile.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../ui/test_helpers.dart';

/// Mounts a `lib/ui_v2/` widget under test with [UiThemePresets], `AppLocalizations`,
/// explicit viewport [surfaceSize], and deterministic in-memory Riverpod overrides.
Future<ProviderContainer> pumpV2Widget(
  WidgetTester tester,
  Widget child, {
  TaskBoard? board,
  TaskNotifier Function()? taskNotifierFactory,
  WebDavConfig config = const WebDavConfig(language: AppLanguage.english),
  SettingsRepository? settingsRepository,
  LocalFileRepository? localFileRepository,
  WebDavRepository? webDavRepository,
  DateTime? nowUtc,
  Size surfaceSize = const Size(1280, 860),
  String presetId = 'calm',
  ThemeMode themeMode = ThemeMode.light,
  Locale locale = const Locale('en'),
  bool supportsNativeDirectoryPicker = true,
  AppBuildProfile buildProfile = AppBuildProfile.release,
  LocationFix? locationFix,
  LocationRepository? locationRepository,
  LinkLauncherRepository? linkLauncherRepository,
  bool settle = true,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final effectiveSettingsRepo =
      settingsRepository ?? InMemorySettingsRepository(config);
  final effectiveNow = nowUtc ?? DateTime.utc(2026, 11, 10, 12, 0);
  final preset = UiThemePresets.byId(presetId);

  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(effectiveSettingsRepo),
      if (localFileRepository != null)
        localFileRepositoryProvider.overrideWithValue(localFileRepository),
      if (webDavRepository != null)
        webDavRepositoryProvider.overrideWithValue(webDavRepository),
      taskNotifierProvider.overrideWith(
        taskNotifierFactory ??
            () => FakeTaskNotifier(board ?? TaskBoard.empty()),
      ),
      clockProvider.overrideWithValue(() => effectiveNow),
      supportsDirectoryPickerProvider.overrideWithValue(
        supportsNativeDirectoryPicker,
      ),
      appBuildProfileProvider.overrideWithValue(buildProfile),
      appVersionProvider.overrideWith((ref) async => 'v0.4.0+4.abc1234'),
      locationRepositoryProvider.overrideWithValue(
        locationRepository ?? FakeLocationRepository(initialFix: locationFix),
      ),
      if (linkLauncherRepository != null)
        linkLauncherRepositoryProvider.overrideWithValue(
          linkLauncherRepository,
        ),
    ],
  );
  addTearDown(container.dispose);

  await container.read(webDavConfigProvider.future);
  await container.read(appVersionProvider.future);
  if (settle) {
    try {
      await container.read(taskNotifierProvider.future);
    } on Object {
      // Allow error-state widget tests to pump error UI cleanly.
    }
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        themeMode: themeMode,
        theme: preset.light.toThemeData(),
        darkTheme: preset.dark.toThemeData(),
        home: child,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return container;
}
