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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/ui/app_theme.dart';

/// Fake [LocalFileRepository] returning an in-memory `.tdf` document for widget tests.
class FakeLocalFileRepository extends LocalFileRepository {
  /// Creates a [FakeLocalFileRepository].
  FakeLocalFileRepository({required super.config, required this.initialTdf});

  /// Initial `.tdf` content returned by [loadTdf] before any mutations are saved.
  String initialTdf;

  @override
  Future<String> loadTdf() async => initialTdf;

  @override
  Future<void> saveTdf(String tdfContent) async {
    initialTdf = tdfContent;
  }
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
  Future<void> pushToRemote(TaskBoard board, {TaskBoard? fallbackBoard}) async {
    state = AsyncData(board);
  }
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
      store[path] = 'tdf 0.5.1\n';
    }
  }
}

/// Opens the top-left navigation drawer and navigates to SettingsScreen.
Future<void> openSettingsFromMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

/// Mounts [child] inside an isolated in-memory [ProviderScope] and [MaterialApp] without booting `HomeScreen` or `TdfService.parse`.
Future<ProviderContainer> pumpLeafWidget(
  WidgetTester tester,
  Widget child, {
  TaskBoard? board,
  WebDavConfig config = const WebDavConfig(),
  Locale locale = const Locale('en'),
  AppThemeSet? themeSet,
  ThemeMode themeMode = ThemeMode.light,
  DateTime Function()? clock,
  bool wrapInScaffold = true,
}) async {
  final effectiveThemeSet =
      themeSet ?? AppThemeSet.forPalette(config.themePalette);
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(config),
      ),
      localFileRepositoryProvider.overrideWith(
        (ref) =>
            FakeLocalFileRepository(config: config, initialTdf: 'tdf 0.5.1\n'),
      ),
      webDavRepositoryProvider.overrideWith(
        (ref) => FakeWebDavRepository(config: config, shouldFail: () => false),
      ),
      clockProvider.overrideWithValue(
        clock ?? () => DateTime.utc(2026, 11, 1, 12, 0),
      ),
      taskNotifierProvider.overrideWith(() => FakeTaskNotifier(board)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(taskNotifierProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: effectiveThemeSet.light.toThemeData(),
        darkTheme: effectiveThemeSet.dark.toThemeData(),
        themeMode: themeMode,
        home: wrapInScaffold ? Scaffold(body: child) : child,
      ),
    ),
  );
  return container;
}
