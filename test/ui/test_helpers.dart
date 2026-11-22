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

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/app_build_profile.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
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
import 'package:tiertask/repositories/window_control_repository.dart';
import 'package:tiertask/services/sha256_service.dart';
import 'package:tiertask/services/tdf_service.dart';
import 'package:tiertask/ui/tokens/ui_theme_tokens.dart';

/// Fake [LocalFileRepository] returning an in-memory `.tdf` document for widget tests.
class FakeLocalFileRepository extends LocalFileRepository {
  /// Creates a [FakeLocalFileRepository].
  FakeLocalFileRepository({required super.config, required this.initialTdf});

  /// Initial `.tdf` content returned by [loadTdf] before any mutations are saved.
  String initialTdf;

  @override
  bool get canWatchDirectory => false;

  @override
  bool directoryExists() => true;

  @override
  bool fileExists() => initialTdf.isNotEmpty;

  @override
  Future<String> loadTdf() async => initialTdf;

  @override
  Future<({String content, String? digest, bool exists})>
  readTdfWithDigest() async {
    final exists = initialTdf.isNotEmpty;
    final digest = exists
        ? Sha256Service.hashHex(utf8.encode(initialTdf))
        : null;
    return (content: initialTdf, digest: digest, exists: exists);
  }

  @override
  Future<void> saveTdf(String tdfContent) async {
    initialTdf = tdfContent;
  }

  @override
  Stream<void> watchTdfChanges() => const Stream<void>.empty();

  @override
  Future<T> withExclusiveTargetLock<T>(Future<T> Function() action) => action();
}

/// In-memory [TaskNotifier] test double that returns [initialBoard] and commits mutations in-memory without filesystem or network I/O.
class FakeTaskNotifier extends TaskNotifier {
  /// Creates a [FakeTaskNotifier] seeded with [initialBoard].
  FakeTaskNotifier([TaskBoard? initialBoard])
    : initialBoard = initialBoard ?? TaskBoard.empty();

  /// Initial [TaskBoard] snapshot returned by [build].
  final TaskBoard initialBoard;

  @override
  Future<TaskBoard> build() async {
    state = AsyncData(initialBoard);
    return initialBoard;
  }

  @override
  Future<bool> pushToRemote(
    TaskBoard board, {
    TaskBoard? fallbackBoard,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    int? mutationEpoch,
  }) async {
    state = AsyncData(board);
    return true;
  }

  @override
  Future<bool> reconcileExternalLocalChanges() async => false;
}

/// Fake [WebDavRepository] for deterministic widget tests of connection status banners.
class FakeWebDavRepository extends WebDavRepository {
  /// Creates a [FakeWebDavRepository].
  FakeWebDavRepository({
    required super.config,
    required this.shouldFail,
    this.remoteStore,
  });

  /// Optional in-memory remote file map keyed by endpoint path.
  final Map<String, String>? remoteStore;

  /// Callback returning whether WebDAV operations should throw a [WebDavException].
  final bool Function() shouldFail;

  @override
  Future<String> fetchTdf() async {
    if (shouldFail()) {
      throw const WebDavException(
        'Authentication failed. Please check username and app password.',
        statusCode: 401,
      );
    }
    final path = config.resolveEndpointUri()?.path;
    if (path != null && remoteStore != null) {
      return remoteStore![path] ?? '';
    }
    return '';
  }

  @override
  Future<void> saveTdf(String tdfContent) async {
    if (shouldFail()) {
      throw const WebDavException(
        'Authentication failed while saving. Please check app password.',
        statusCode: 401,
      );
    }
    final path = config.resolveEndpointUri()?.path;
    if (path != null && remoteStore != null) {
      remoteStore![path] = tdfContent;
    }
  }

  @override
  Future<void> wipeTdf({bool createBackup = false}) async {
    if (shouldFail()) {
      throw const WebDavException(
        'Authentication failed while saving. Please check app password.',
        statusCode: 401,
      );
    }
    final path = config.resolveEndpointUri()?.path;
    final store = remoteStore;
    if (path != null && store != null) {
      if (createBackup && store.containsKey(path)) {
        final existing = store[path] ?? '';
        for (
          var attempt = 0;
          attempt <= LocalFileRepository.maxBackupSuffix;
          attempt++
        ) {
          final candidate = LocalFileRepository.formatBackupPath(path, attempt);
          if (!store.containsKey(candidate)) {
            store[candidate] = existing;
            break;
          }
        }
      }
      store[path] = 'tdf ${TdfService.supportedVersion}\n';
    }
  }
}

/// Mounts a `lib/ui/` widget under test with [UiThemePresets], `AppLocalizations`,
/// explicit viewport [surfaceSize], and deterministic in-memory Riverpod overrides.
Future<ProviderContainer> pumpLeafWidget(
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
  bool supportsDesktopWindowControls = true,
  bool supportsLocalFileWatch = true,
  AppBuildProfile buildProfile = AppBuildProfile.release,
  LocationFix? locationFix,
  LocationRepository? locationRepository,
  LinkLauncherRepository? linkLauncherRepository,
  WindowControlRepository? windowControlRepository,
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
  final effectiveNow = nowUtc ?? DateTime.utc(2026, 11, 10, 12);
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
      supportsDesktopWindowControlsProvider.overrideWithValue(
        supportsDesktopWindowControls,
      ),
      supportsLocalFileWatchProvider.overrideWithValue(supportsLocalFileWatch),
      windowControlRepositoryProvider.overrideWithValue(
        windowControlRepository ?? FakeWindowControlRepository(),
      ),
      appBuildProfileProvider.overrideWithValue(buildProfile),
      appVersionProvider.overrideWith((ref) => 'v0.4.0+4.abc1234'),
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

/// Pumps a standalone design-system widget [child] inside a [MaterialApp] themed with [tokens] at [surfaceSize].
Future<void> pumpUiWidget(
  WidgetTester tester,
  Widget child, {
  UiThemeTokens? tokens,
  Size surfaceSize = const Size(1280, 800),
  bool wrapInScaffold = true,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = surfaceSize;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final activeTokens = tokens ?? UiThemePresets.calm.light;
  await tester.pumpWidget(
    MaterialApp(
      theme: activeTokens.toThemeData(),
      home: wrapInScaffold ? Scaffold(body: child) : child,
    ),
  );
  await tester.pump();
}
