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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/app_build_profile.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/board_boundary_timer.dart';
import 'package:tiertask/presentation/board_presentation_providers.dart';
import 'package:tiertask/presentation/board_v2_view_models.dart';
import 'package:tiertask/presentation/floating_notice_controller.dart';
import 'package:tiertask/presentation/settings_v2_controller.dart';
import 'package:tiertask/presentation/ui_v2_shell_models.dart';
import 'package:tiertask/presentation/workspace_v2_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/app_version_repository.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/sha256_service.dart';
import 'package:tiertask/services/tdf_service.dart';
import 'package:tiertask/ui_v2/tier_task_shell_screen.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

/// Controllable in-memory [LocalFileRepository] supporting suspended `Completer` saves for mid-flight UI tests.
class _ControllableLocalFileRepository extends LocalFileRepository {
  /// Creates a [_ControllableLocalFileRepository].
  _ControllableLocalFileRepository({
    required super.config,
    required this.content,
    this.watchStream,
  });

  /// Current stored `.tdf` content.
  String content;

  /// Optional pending save barrier checked by [saveTdf].
  Completer<void>? pendingSave;

  /// Number of [saveTdf] calls observed.
  int saveCalls = 0;

  /// Optional external watch stream used to assert root `localFileWatcherProvider` subscription.
  final Stream<void>? watchStream;

  @override
  bool get canWatchDirectory => watchStream != null;

  @override
  bool directoryExists() => true;

  @override
  bool fileExists() => content.isNotEmpty;

  @override
  Future<String> loadTdf() async => content;

  @override
  Future<({String content, String? digest, bool exists})>
  readTdfWithDigest() async {
    final exists = content.isNotEmpty;
    final digest = exists ? Sha256Service.hashHex(utf8.encode(content)) : null;
    return (content: content, digest: digest, exists: exists);
  }

  @override
  Future<void> saveTdf(String tdfContent) async {
    saveCalls++;
    final barrier = pendingSave;
    if (barrier != null) {
      await barrier.future;
    }
    content = tdfContent;
  }

  @override
  Stream<void> watchTdfChanges() => watchStream ?? const Stream<void>.empty();

  @override
  Future<T> withExclusiveTargetLock<T>(Future<T> Function() action) => action();
}

/// Controllable [InMemorySettingsRepository] that can suspend `saveConfig` on a `Completer`.
class _ControllableSettingsRepository extends InMemorySettingsRepository {
  /// Creates a [_ControllableSettingsRepository].
  _ControllableSettingsRepository(super.config);

  /// Optional barrier delaying settings persistence.
  Completer<void>? pendingSave;

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    final barrier = pendingSave;
    if (barrier != null) {
      await barrier.future;
    }
    await super.saveConfig(config);
  }
}

/// Real temp-file-backed [LocalFileRepository] with deterministic injected watch stream.
class _DiskBackedWatchLocalFileRepository extends LocalFileRepository {
  /// Creates a [_DiskBackedWatchLocalFileRepository].
  _DiskBackedWatchLocalFileRepository({
    required super.config,
    required super.baseDirectoryPath,
    required this.watchStream,
  });

  /// Deterministic stream simulating OS filesystem watcher notifications.
  final Stream<void> watchStream;

  @override
  bool get canWatchDirectory => true;

  @override
  Stream<void> watchTdfChanges() => watchStream;
}

/// In-memory [WebDavRepository] supporting deterministic conflict and recovery resolution cycles.
class _InMemoryWebDavRepository extends WebDavRepository {
  /// Creates an [_InMemoryWebDavRepository].
  _InMemoryWebDavRepository({required super.config, required this.remoteTdf});

  /// Current remote `.tdf` document string.
  String remoteTdf;

  /// Number of remote PUT saves observed.
  int saveCalls = 0;

  @override
  Future<String> fetchTdf() async => remoteTdf;

  @override
  Future<void> saveTdf(String tdfContent) async {
    saveCalls++;
    remoteTdf = tdfContent;
  }
}

/// Configures the test viewport to [size] with 1.0 DPR and restores it on tearDown.
void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  const tdfService = TdfService();
  final baseTime = DateTime.utc(2026, 11, 10, 12, 0);

  String buildSeedTdf({
    DateTime? deferTaskTime,
    bool includeSubtaskTask = false,
  }) {
    final tasks = <TaskItem>[
      TaskItem(
        id: 'taskA00001',
        title: 'Primary Focus Task',
        labelIds: const <String>['work000001'],
        createdAt: baseTime,
        modifiedAt: baseTime,
      ),
      TaskItem(
        id: 'taskB00002',
        title: 'Second Focus Task',
        createdAt: baseTime,
        modifiedAt: baseTime,
      ),
      if (includeSubtaskTask)
        TaskItem(
          id: 'taskS00003',
          title: 'Checklist Focus Task',
          subtasks: const <SubtaskItem>[
            SubtaskItem(title: 'Only Step', isCompleted: false),
          ],
          subtasksAutoFinish: true,
          createdAt: baseTime,
          modifiedAt: baseTime,
        ),
      if (deferTaskTime != null)
        TaskItem(
          id: 'taskD00004',
          title: 'Deferred Boundary Task',
          suspendedAt: deferTaskTime,
          createdAt: baseTime,
          modifiedAt: baseTime,
        ),
    ];
    final board = TaskBoard.evaluate(
      tasks: tasks,
      labels: <TdfLabel>[
        TdfLabel(
          id: 'work000001',
          name: 'Work',
          color: '#2196F3',
          modifiedAt: baseTime,
        ),
      ],
      queueBlock: TdfQueueBlock(
        modifiedAt: baseTime,
        taskIds: <String>[
          'taskA00001',
          'taskB00002',
          if (includeSubtaskTask) 'taskS00003',
          if (deferTaskTime != null) 'taskD00004',
        ],
      ),
      evaluationTime: baseTime,
      localEvaluationTime: baseTime,
    );
    return tdfService.serialize(board);
  }

  group('M-REAL-MECHANICS-TESTS (Phase 3 v2 shell)', () {
    testWidgets(
      'Real TierTaskApp wires diagnostics, watcher, boundary timer, inline DEV pill, (Dev) title, UiThemePresets, and en/de locales without legacy Banner',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        final watchEvents = StreamController<void>.broadcast();
        addTearDown(watchEvents.close);

        final deferTarget = baseTime.add(const Duration(seconds: 10));
        const config = WebDavConfig(
          language: AppLanguage.english,
          themePalette: AppThemePalette.calm,
          themeMode: AppThemeMode.light,
          diagnosticsEnabled: true,
          localWatchEnabled: true,
        );
        final settingsRepo = InMemorySettingsRepository(config);
        final localRepo = _ControllableLocalFileRepository(
          config: config,
          content: buildSeedTdf(deferTaskTime: deferTarget),
          watchStream: watchEvents.stream,
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            localFileRepositoryProvider.overrideWith((ref) => localRepo),
            clockProvider.overrideWithValue(() => baseTime),
            appBuildProfileProvider.overrideWithValue(AppBuildProfile.dev),
            appVersionRepositoryProvider.overrideWithValue(
              const FakeAppVersionRepository(version: '0.4.0+7.deadbee'),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          AppLogger.shouldLog(LogLevel.info),
          isTrue,
          reason: 'TierTaskApp must watch diagnosticsEnabledProvider',
        );
        expect(
          watchEvents.hasListener,
          isTrue,
          reason: 'TierTaskApp must subscribe to localFileWatcherProvider',
        );
        expect(
          container.read(boardBoundaryTimerProvider),
          equals(deferTarget),
          reason: 'TierTaskShellScreen must watch boardBoundaryTimerProvider and schedule the upcoming defer boundary',
        );

        final materialApp = tester.widget<MaterialApp>(
          find.byType(MaterialApp),
        );
        expect(materialApp.title, equals('TierTask (Dev)'));
        expect(
          find.byKey(const ValueKey<String>('chrome_dev_pill')),
          findsOneWidget,
          reason: 'Inline DEV pill must appear in dev profile',
        );
        expect(
          find.byKey(const ValueKey<String>('dev_build_banner')),
          findsNothing,
          reason: 'Legacy corner DEV Banner must be removed after cutover',
        );

        final shellContext = tester.element(find.byType(TierTaskShellScreen));
        expect(
          UiThemeTokens.of(shellContext).colors.bg,
          equals(UiThemePresets.calm.light.colors.bg),
        );

        // Switch live to Plum Umber Dark and German locale.
        await container
            .read(webDavConfigProvider.notifier)
            .updateThemePalette(AppThemePalette.plumUmber);
        await container
            .read(webDavConfigProvider.notifier)
            .updateThemeMode(AppThemeMode.dark);
        await container
            .read(webDavConfigProvider.notifier)
            .updateLanguage(AppLanguage.german);
        await tester.pumpAndSettle();

        final updatedContext = tester.element(find.byType(TierTaskShellScreen));
        expect(
          UiThemeTokens.of(updatedContext).colors.bg,
          equals(UiThemePresets.plumUmber.dark.colors.bg),
        );
        expect(find.text('Alle Aufgaben'), findsWidgets);
        expect(
          MaterialLocalizations.of(updatedContext).okButtonLabel,
          isNotEmpty,
        );
        expect(
          AppLocalizations.of(updatedContext).settingsTitle,
          equals('Einstellungen'),
        );

        // Release profile hides DEV pill and strips (Dev) suffix.
        final releaseContainer = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(
                  language: AppLanguage.english,
                  diagnosticsEnabled: false,
                ),
              ),
            ),
            localFileRepositoryProvider.overrideWith(
              (ref) => _ControllableLocalFileRepository(
                config: config,
                content: buildSeedTdf(),
              ),
            ),
            clockProvider.overrideWithValue(() => baseTime),
            appBuildProfileProvider.overrideWithValue(AppBuildProfile.release),
          ],
        );
        addTearDown(releaseContainer.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: releaseContainer,
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();
        final releaseApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(releaseApp.title, equals('TierTask'));
        expect(
          find.byKey(const ValueKey<String>('chrome_dev_pill')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Mid-flight Completer saves prevent duplicate submit, preserve inline text buffer + error on failure, and dispose cleanly across view switches',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        const config = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.both,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
        );
        final settingsRepo = _ControllableSettingsRepository(config);
        final localRepo = _ControllableLocalFileRepository(
          config: config,
          content: buildSeedTdf(),
        );
        final webDavRepo = _InMemoryWebDavRepository(
          config: config,
          remoteTdf: localRepo.content,
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            localFileRepositoryProvider.overrideWith((ref) => localRepo),
            webDavRepositoryProvider.overrideWith((ref) => webDavRepo),
            clockProvider.overrideWithValue(() => baseTime),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Expand taskA00001 and open inline Title editor.
        await tester.tap(find.text('Primary Focus Task'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('task_edit_title_taskA00001')),
        );
        await tester.pumpAndSettle();

        final titleInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('task_title_editor_input_taskA00001'),
          ),
          matching: find.byType(EditableText),
        );
        await tester.enterText(titleInput, 'Mid-Flight Title');
        await tester.pump();

        // Suspend saveTdf on a Completer.
        final saveCompleter = Completer<void>();
        localRepo.pendingSave = saveCompleter;
        final initialCalls = localRepo.saveCalls;

        final saveButton = find.byKey(
          const ValueKey<String>('task_title_editor_save_taskA00001'),
        );
        await tester.tap(saveButton);
        await tester.pump();

        expect(
          localRepo.saveCalls,
          equals(initialCalls + 1),
          reason: 'First Save tap must dispatch persistence once',
        );

        // Second tap mid-flight must be ignored by busy guard.
        await tester.tap(saveButton, warnIfMissed: false);
        await tester.pump();
        expect(
          localRepo.saveCalls,
          equals(initialCalls + 1),
          reason: 'Busy guard must block duplicate concurrent inline saves',
        );

        // Fail persistence -> inline editor retains typed buffer and shows error.
        saveCompleter.completeError(const LocalFileException('Disk full'));
        localRepo.pendingSave = null;
        await tester.pumpAndSettle();

        final editableAfterError = tester.widget<EditableText>(titleInput);
        expect(
          editableAfterError.controller.text,
          equals('Mid-Flight Title'),
          reason: 'Failed inline save must preserve user text buffer',
        );
        expect(
          container.read(appShellControllerProvider).activeInlineEdit,
          isNotNull,
        );

        // Switch to Settings, edit WebDAV URL, suspend save on Completer, navigate away mid-flight.
        container
            .read(appShellControllerProvider.notifier)
            .openView(ShellView.settings);
        await tester.pumpAndSettle();

        final urlField = find.descendant(
          of: find.byKey(
            const ValueKey<String>('settings_webdav_server_url_field'),
          ),
          matching: find.byType(EditableText),
        );
        await tester.ensureVisible(urlField);
        await tester.enterText(urlField, 'https://next.example.com');
        await tester.pumpAndSettle();
        expect(
          container.read(settingsV2ControllerProvider).isWebDavDirty,
          isTrue,
        );

        final settingsCompleter = Completer<void>();
        settingsRepo.pendingSave = settingsCompleter;
        await tester.tap(
          find.byKey(const ValueKey<String>('settings_dock_save_button')),
        );
        await tester.pump();

        // Navigate back to Tasks while Settings save is suspended in-flight.
        container
            .read(appShellControllerProvider.notifier)
            .openView(ShellView.tasks);
        await tester.pump();

        // Complete the suspended Settings save after SettingsView has disposed.
        settingsCompleter.complete();
        settingsRepo.pendingSave = null;
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.tasks),
        );
      },
    );

    testWidgets(
      'Real Directory.systemTemp external watcher edits and boundary timer preserve open inline text on benign updates, auto-close on external delete/complete, and preserve Undo on local Complete/Subtask auto-finish',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        final tempDir = Directory.systemTemp.createTempSync(
          'tiertask_v2_real_mech_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final watchEvents = StreamController<void>.broadcast();
        addTearDown(watchEvents.close);

        var currentNow = baseTime;
        final deferTarget = baseTime.add(const Duration(seconds: 5));
        final tdfPath = '${tempDir.path}${Platform.pathSeparator}tasks.tdf';
        final config = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.local,
          localFilePath: tdfPath,
          localWatchEnabled: true,
        );
        final realLocalRepo = _DiskBackedWatchLocalFileRepository(
          config: config,
          baseDirectoryPath: tempDir.path,
          watchStream: watchEvents.stream,
        );
        final seedTdf = buildSeedTdf(
          deferTaskTime: deferTarget,
          includeSubtaskTask: true,
        );
        File(tdfPath).writeAsStringSync(seedTdf, flush: true);

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(config),
            ),
            localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
            localFileRepositoryProvider.overrideWith((ref) => realLocalRepo),
            clockProvider.overrideWithValue(() => currentNow),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(watchEvents.hasListener, isTrue);

        // Expand taskA00001 and enter unsaved text into inline Title editor.
        await tester.tap(find.text('Primary Focus Task'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('task_edit_title_taskA00001')),
        );
        await tester.pumpAndSettle();

        final titleInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('task_title_editor_input_taskA00001'),
          ),
          matching: find.byType(EditableText),
        );
        await tester.enterText(titleInput, 'Unsaved User Draft');
        await tester.pump();

        // 1. Benign external file edit adds an external task on disk and triggers real watcher stream.
        final currentBoard = container.read(taskNotifierProvider).requireValue;
        final boardWithExternal = currentBoard.addTask(
          'External Disk Task',
          currentDate: baseTime.add(const Duration(seconds: 1)),
        );
        File(tdfPath).writeAsStringSync(
          tdfService.serialize(boardWithExternal),
          flush: true,
        );
        watchEvents.add(null);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .allTasks
              .any((task) => task.title == 'External Disk Task'),
          isTrue,
          reason: 'Watcher stream must reconcile external disk addition',
        );
        expect(
          tester.widget<EditableText>(titleInput).controller.text,
          equals('Unsaved User Draft'),
          reason: 'Benign external file refresh must not clobber active inline text buffer',
        );

        // 2. Real boardBoundaryTimerProvider timer fires after deferTarget while inline edit stays intact.
        currentNow = deferTarget.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(
          container
              .read(evaluatedBoardProvider(null))
              .requireValue
              .ready
              .any((task) => task.id == 'taskD00004'),
          isTrue,
          reason: 'Real boundary timer wakeup must promote deferred task out of Planned',
        );
        expect(
          tester.widget<EditableText>(titleInput).controller.text,
          equals('Unsaved User Draft'),
          reason: 'Boundary timer wakeup must preserve active inline text',
        );

        // 3. External deletion of taskA00001 auto-closes card + editor and emits external removal notice.
        final boardDeletedA = container
            .read(taskNotifierProvider)
            .requireValue
            .deleteTask(
              'taskA00001',
              currentDate: baseTime.add(const Duration(seconds: 2)),
            );
        File(
          tdfPath,
        ).writeAsStringSync(tdfService.serialize(boardDeletedA), flush: true);
        watchEvents.add(null);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(
          container.read(appShellControllerProvider).expandedEntity,
          isNull,
        );
        expect(
          container.read(appShellControllerProvider).activeInlineEdit,
          isNull,
        );
        expect(
          container.read(floatingNoticeControllerProvider)?.message,
          contains('removed'),
          reason: 'External deletion must show entityRemovedExternallyNotice',
        );

        // 4. External completion of taskB00002 while editing Title cancels editor and shows external completed notice.
        await tester.tap(find.text('Second Focus Task'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('task_edit_title_taskB00002')),
        );
        await tester.pumpAndSettle();

        final boardCompletedB = container
            .read(taskNotifierProvider)
            .requireValue
            .completeTask(
              'taskB00002',
              currentDate: baseTime.add(const Duration(seconds: 3)),
            );
        File(
          tdfPath,
        ).writeAsStringSync(tdfService.serialize(boardCompletedB), flush: true);
        watchEvents.add(null);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(
          container.read(appShellControllerProvider).activeInlineEdit,
          isNull,
        );
        expect(
          container.read(appShellControllerProvider).expandedEntity?.id,
          equals('taskB00002'),
          reason: 'Externally completed task stays expanded in read-only completed mode',
        );
        expect(
          container.read(floatingNoticeControllerProvider)?.message,
          contains('completed'),
          reason: 'External completion during non-History edit must emit taskCompletedExternallyNotice',
        );

        // 5. Local subtask auto-finish suppresses external-change notice so Undo toast + Ctrl+Z remain intact.
        await tester.tap(find.text('Checklist Focus Task'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Only Step'));
        await tester.pumpAndSettle();

        expect(
          container.read(floatingNoticeControllerProvider)?.undoSequence,
          isNotNull,
          reason: 'Local subtask auto-finish must keep Undo floating notice without external-change clobber',
        );
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('taskS00003')
              ?.isCompleted,
          isTrue,
        );

        // Ctrl+Z restores taskS00003 back to open state.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('taskS00003')
              ?.isCompleted,
          isFalse,
          reason: 'Ctrl+Z must undo local subtask auto-finish completion',
        );
      },
    );

    testWidgets(
      'Workspace switch across await cancels drafts, discards dirty WebDAV Settings silently, resets filters/expanded state, and clears Undo stack',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        const defaultConfig = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.both,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
          filePath: 'default.tdf',
          localFilePath: 'default.tdf',
        );
        const workConfig = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.local,
          filePath: 'work.tdf',
          localFilePath: 'work.tdf',
        );
        final settingsRepo = InMemorySettingsRepository(defaultConfig);
        await settingsRepo.createWorkspace(
          'Work',
          id: 'ws_work',
          config: workConfig,
        );
        final defaultTdf = buildSeedTdf();
        final workTdf = tdfService.serialize(
          TaskBoard.evaluate(
            tasks: <TaskItem>[
              TaskItem(
                id: 'workT00001',
                title: 'Work Workspace Task',
                createdAt: baseTime,
                modifiedAt: baseTime,
              ),
            ],
            queueBlock: TdfQueueBlock(
              modifiedAt: baseTime,
              taskIds: const <String>['workT00001'],
            ),
            evaluationTime: baseTime,
            localEvaluationTime: baseTime,
          ),
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            localFileRepositoryProvider.overrideWith((ref) {
              final activeConfig =
                  ref.watch(webDavConfigProvider).asData?.value ??
                  defaultConfig;
              return _ControllableLocalFileRepository(
                config: activeConfig,
                content: activeConfig.localFilePath == 'work.tdf'
                    ? workTdf
                    : defaultTdf,
              );
            }),
            webDavRepositoryProvider.overrideWith((ref) {
              final activeConfig =
                  ref.watch(webDavConfigProvider).asData?.value ??
                  defaultConfig;
              return _InMemoryWebDavRepository(
                config: activeConfig,
                remoteTdf: defaultTdf,
              );
            }),
            clockProvider.overrideWithValue(() => baseTime),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Populate Undo stack, active label filter, draft card, and dirty WebDAV Settings.
        await tester.tap(
          find.byKey(const ValueKey<String>('task_complete_taskA00001')),
        );
        await tester.pumpAndSettle();
        expect(container.read(boardChromeViewModelProvider).canUndo, isTrue);

        final shellNotifier = container.read(
          appShellControllerProvider.notifier,
        );
        shellNotifier.selectLabelFilter('work000001');
        shellNotifier.openDraft(EntityDraftKind.task);
        shellNotifier.openView(ShellView.settings);
        await tester.pumpAndSettle();

        container
            .read(settingsV2ControllerProvider.notifier)
            .updateWebDavDraft(serverUrl: 'https://dirty.example.com');
        await tester.pump();
        expect(
          container.read(settingsV2ControllerProvider).isWebDavDirty,
          isTrue,
        );

        // Switch workspace across await boundary.
        await container
            .read(workspaceV2ControllerProvider.notifier)
            .switchWorkspace('ws_work');
        await tester.pumpAndSettle();

        final shellAfter = container.read(appShellControllerProvider);
        expect(shellAfter.activeDraft, isNull);
        expect(shellAfter.expandedEntity, isNull);
        expect(shellAfter.activeLabelId, isNull);
        expect(shellAfter.searchOpen, isFalse);
        expect(container.read(boardChromeViewModelProvider).canUndo, isFalse);
        expect(
          container.read(settingsV2ControllerProvider).isWebDavDirty,
          isFalse,
        );
        expect(find.text('Work Workspace Task'), findsOneWidget);
      },
    );

    testWidgets(
      'Quick-Add creates task without jumping tiers and full TDF-DEL-003 / TDF-REC-002 resolution clears Undo and resumes sync',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        const config = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.both,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
        );
        final seedTdf = buildSeedTdf();
        final localRepo = _ControllableLocalFileRepository(
          config: config,
          content: seedTdf,
        );
        final webDavRepo = _InMemoryWebDavRepository(
          config: config,
          remoteTdf: seedTdf,
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(config),
            ),
            localFileRepositoryProvider.overrideWith((ref) => localRepo),
            webDavRepositoryProvider.overrideWith((ref) => webDavRepo),
            clockProvider.overrideWithValue(() => baseTime),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Quick-Add a Someday task while viewing Focus -> does not jump to Someday or auto-expand.
        final quickAddInput = find.descendant(
          of: find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(quickAddInput, 'Later Someday Idea');
        await tester.tap(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('quick_add_placement_control'),
            ),
            matching: find.text('Someday'),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('+ Add'));
        await tester.pumpAndSettle();

        expect(
          container.read(appShellControllerProvider).activeTier,
          equals(ShellTier.focus),
          reason: 'Quick-Add must never jump tiers on task creation',
        );
        expect(
          container.read(appShellControllerProvider).expandedEntity,
          isNull,
          reason: 'Quick-Add must not auto-expand newly created tasks',
        );
        expect(
          container.read(floatingNoticeControllerProvider)?.message,
          contains('Someday'),
        );

        // Seed an Undo entry, then trigger TDF-DEL-003 deletion conflict.
        await tester.tap(
          find.byKey(const ValueKey<String>('task_complete_taskB00002')),
        );
        await tester.pumpAndSettle();
        expect(container.read(boardChromeViewModelProvider).canUndo, isTrue);

        container
            .read(syncStateProvider.notifier)
            .setConflict(
              'Conflict',
              outcome: const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.deletionConflict,
                message: 'Conflict',
                conflictedTaskIds: <String>['taskA00001'],
              ),
            );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('chrome_sync_button')),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.conflict),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('resolution_apply_button')),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.tasks),
        );
        expect(
          container.read(boardChromeViewModelProvider).canUndo,
          isFalse,
          reason: 'Conflict resolution must clear stale Undo history',
        );

        // Trigger TDF-REC-002 recovery required -> route to Recovery view -> Apply & Sync.
        container
            .read(syncStateProvider.notifier)
            .setConflict(
              'Recovery required',
              outcome: const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.recoveryRequired,
                message: 'Recovery required',
                ambiguousTaskIds: <String>['taskA00001'],
              ),
            );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('chrome_sync_button')),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.recovery),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('resolution_apply_button')),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.tasks),
        );
      },
    );

    testWidgets(
      'Unwinds 9-layer Escape stack, Android PopScope including tablet Layer 2 sidebar filter, and disables compact bottom-sheet search autofocus (U-A11Y-003)',
      (tester) async {
        _setViewport(tester, const Size(1024, 768));
        const config = WebDavConfig(language: AppLanguage.english);
        final localRepo = _ControllableLocalFileRepository(
          config: config,
          content: buildSeedTdf(),
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(config),
            ),
            localFileRepositoryProvider.overrideWith((ref) => localRepo),
            clockProvider.overrideWithValue(() => baseTime),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Layer 3: Modal dialog dismisses on Escape without touching underlying shell state.
        await tester.tap(
          find.byKey(const ValueKey<String>('chrome_workspace_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('workspaces_modal')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('workspaces_modal')),
          findsNothing,
        );

        // Layers 1 -> 2 -> 4 -> 5 -> 6 via live Escape key events.
        final shellNotifier = container.read(
          appShellControllerProvider.notifier,
        );
        shellNotifier.openSearch();
        shellNotifier.openDraft(EntityDraftKind.task);
        shellNotifier.setLabelPickerOpen(true);
        shellNotifier.setLabelPickerQuery('wo');
        shellNotifier.toggleSidebarLabelsFilter();
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).labelPickerQuery,
          isEmpty,
          reason: 'Layer 1 Escape must clear label picker query first',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).sidebarLabelsFilterOpen,
          isFalse,
          reason: 'Layer 2 Escape must close open sidebar filter second',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).labelPickerOpen,
          isFalse,
          reason: 'Layer 4 Escape must close inline label picker',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).activeDraft,
          isNull,
          reason: 'Layer 5 Escape must cancel uncommitted draft card',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).searchOpen,
          isFalse,
          reason: 'Layer 6 Escape must close Global Search',
        );

        // Layers 7 -> 8 -> 9 via live Escape key events.
        const taskEntity = EntityRef(kind: EntityKind.task, id: 'taskA00001');
        shellNotifier.expandEntity(taskEntity);
        shellNotifier.requestInlineDelete(taskEntity);
        shellNotifier.openInlineEdit(
          const InlineEditTarget(entity: taskEntity, sectionKey: 'title'),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).activeInlineEdit,
          isNull,
          reason: 'Layer 7 Escape must cancel active inline section edit',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).activeDeleteConfirm,
          isNull,
          reason: 'Layer 8 Escape must cancel active inline delete confirm',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).expandedEntity,
          isNull,
          reason: 'Layer 9 Escape must collapse expanded entity card',
        );

        // Tablet (> 720px) PopScope unwind: Layer 2 persistent sidebar filter closes before Settings -> Tasks.
        shellNotifier.openView(ShellView.settings);
        shellNotifier.toggleSidebarLabelsFilter();
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).sidebarLabelsFilterOpen,
          isTrue,
        );

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).sidebarLabelsFilterOpen,
          isFalse,
          reason: 'Tablet PopScope must close open Layer 2 sidebar filter before unwinding view',
        );
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.settings),
        );

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.tasks),
        );

        // Compact <= 720px: Quick-Add + Labels bottom sheet must NOT auto-focus search input (U-A11Y-003).
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();

        await tester.tap(find.text('+ New task'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('quick_add_labels_trigger')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(UiSearchablePicker<String>), findsOneWidget);
        final focusedEditable = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>();
        expect(
          focusedEditable,
          isNull,
          reason: 'Compact label picker bottom sheet must disable search autofocus per U-A11Y-003',
        );
      },
    );
  });
}
