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
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/app_build_profile.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/settings_codec.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/board_providers.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/entity_actions_provider.dart';
import 'package:tiertask/providers/floating_notice_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/settings_draft_providers.dart';
import 'package:tiertask/providers/shell_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/app_version_repository.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/sha256_service.dart';
import 'package:tiertask/services/tdf_service.dart';
import 'package:tiertask/ui/components/ui_searchable_picker.dart';
import 'package:tiertask/ui/dialogs/compact_label_picker_sheet.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';
import 'package:tiertask/ui/primitives/ui_segmented_control.dart';
import 'package:tiertask/ui/primitives/ui_toggle_row.dart';
import 'package:tiertask/ui/tier_task_shell_screen.dart';
import 'package:tiertask/ui/tokens/ui_theme_tokens.dart';
import 'package:tiertask/ui/views/raw_tdf_view.dart';
import 'package:tiertask/ui/views/resolution_views.dart';
import 'package:tiertask/ui/views/task_detail_editors.dart';
import 'package:tiertask/ui/widgets/entity_note_section.dart';

import 'test_helpers.dart';

/// Controllable [LocationRepository] allowing tests to hold a lookup in the `searching` state.
class _CompleterLocationRepository extends FakeLocationRepository {
  Completer<LocationFix?> completer = Completer<LocationFix?>();

  @override
  Future<LocationFix?> determineLocation({bool forceRefresh = false}) {
    callCount++;
    return completer.future;
  }
}

/// Delayed [InMemorySettingsRepository] supporting async startup recovery notices, gated saves, and injectable load failures.
class _DelayedSettingsRepository extends InMemorySettingsRepository {
  _DelayedSettingsRepository({
    WebDavConfig initialConfig = const WebDavConfig(
      language: AppLanguage.english,
    ),
    required this.onLoad,
    this.onSave,
    SettingsRecoveryNotice? recoveryNotice,
  }) : _pendingNotice = recoveryNotice,
       super(initialConfig);

  final Future<void> Function() onLoad;
  final Future<void> Function()? onSave;
  SettingsRecoveryNotice? _emittedNotice;
  SettingsRecoveryNotice? _pendingNotice;

  @override
  Future<AppWorkspace> loadActiveWorkspace() async {
    await onLoad();
    _emittedNotice = _pendingNotice;
    _pendingNotice = null;
    return super.loadActiveWorkspace();
  }

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    if (onSave case final gate?) {
      await gate();
    }
    return super.saveConfig(config);
  }

  @override
  Future<void> saveConfigForWorkspace(
    String workspaceId,
    WebDavConfig config,
  ) async {
    if (onSave case final gate?) {
      await gate();
    }
    return super.saveConfigForWorkspace(workspaceId, config);
  }

  @override
  SettingsRecoveryNotice? takeLastRecoveryNotice() {
    final notice = _emittedNotice;
    _emittedNotice = null;
    return notice;
  }
}

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

  @override
  Future<void> saveConfigForWorkspace(
    String workspaceId,
    WebDavConfig config,
  ) async {
    final barrier = pendingSave;
    if (barrier != null) {
      await barrier.future;
    }
    await super.saveConfigForWorkspace(workspaceId, config);
  }
}

/// Counting [TdfService] subclass recording canonical `.tdf` serialization calls.
class _CountingTdfService extends TdfService {
  /// Creates a [_CountingTdfService].
  _CountingTdfService();

  /// Number of [serialize] invocations observed.
  int serializeCalls = 0;

  @override
  String serialize(TaskBoard board) {
    serializeCalls++;
    return super.serialize(board);
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
  final baseTime = DateTime.utc(2026, 11, 10, 12);

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
          subtasks: const <SubtaskItem>[SubtaskItem(title: 'Only Step')],
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

  group('M-REAL-MECHANICS-TESTS', () {
    testWidgets(
      'Real TierTaskApp wires diagnostics, watcher, boundary timer, inline DEV pill, (Dev) title, UiThemePresets, and en/de locales without legacy Banner',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        final watchEvents = StreamController<void>.broadcast();
        addTearDown(watchEvents.close);

        final deferTarget = baseTime.add(const Duration(seconds: 10));
        const config = WebDavConfig(
          language: AppLanguage.english,
          themeMode: AppThemeMode.light,
          diagnosticsEnabled: true,
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
            supportsLocalFileWatchProvider.overrideWithValue(true),
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
                const WebDavConfig(language: AppLanguage.english),
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
        expect(container.read(shellProvider).activeInlineEdit, isNotNull);

        // Switch to Settings, edit WebDAV URL, suspend save on Completer, navigate away mid-flight.
        container.read(shellProvider.notifier).openView(ShellView.settings);
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
        expect(container.read(settingsDraftProvider).isDirty, isTrue);

        final settingsCompleter = Completer<void>();
        settingsRepo.pendingSave = settingsCompleter;
        await tester.tap(
          find.byKey(const ValueKey<String>('settings_dock_save_button')),
        );
        await tester.pump();

        // Navigate back to Tasks while Settings save is suspended in-flight.
        container.read(shellProvider.notifier).openView(ShellView.tasks);
        await tester.pump();

        // Complete the suspended Settings save after SettingsView has disposed.
        settingsCompleter.complete();
        settingsRepo.pendingSave = null;
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(container.read(shellProvider).view, equals(ShellView.tasks));
      },
    );

    testWidgets(
      'Real Directory.systemTemp external watcher edits and boundary timer preserve open inline text on benign updates, auto-close on external delete/complete, and preserve Undo on local Complete/Subtask auto-finish',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        final tempDir = Directory.systemTemp.createTempSync(
          'tiertask_real_mech_',
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
            supportsLocalFileWatchProvider.overrideWithValue(true),
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

        expect(container.read(shellProvider).expandedEntity, isNull);
        expect(container.read(shellProvider).activeInlineEdit, isNull);
        expect(
          container.read(floatingNoticeProvider)?.message,
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

        expect(container.read(shellProvider).activeInlineEdit, isNull);
        expect(
          container.read(shellProvider).expandedEntity?.id,
          equals('taskB00002'),
          reason: 'Externally completed task stays expanded in read-only completed mode',
        );
        expect(
          container.read(floatingNoticeProvider)?.message,
          contains('completed'),
          reason: 'External completion during non-History edit must emit taskCompletedExternallyNotice',
        );

        // 5. Local subtask auto-finish suppresses external-change notice so Undo toast + Ctrl+Z remain intact.
        await tester.tap(find.text('Checklist Focus Task'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Only Step'));
        await tester.pumpAndSettle();

        expect(
          container.read(floatingNoticeProvider)?.undoSequence,
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
        expect(container.read(taskUndoStateProvider).canUndo, isTrue);

        final shellNotifier = container.read(shellProvider.notifier);
        shellNotifier.selectLabelFilter('work000001');
        shellNotifier.openDraft(EntityDraftKind.task);
        shellNotifier.openView(ShellView.settings);
        await tester.pumpAndSettle();

        container
            .read(settingsDraftProvider.notifier)
            .updateWebDavDraft(serverUrl: 'https://dirty.example.com');
        await tester.pump();
        expect(container.read(settingsDraftProvider).isDirty, isTrue);

        // Switch workspace across await boundary.
        await container
            .read(workspaceActionsProvider.notifier)
            .switchWorkspace('ws_work');
        await tester.pumpAndSettle();

        final shellAfter = container.read(shellProvider);
        expect(shellAfter.activeDraft, isNull);
        expect(shellAfter.expandedEntity, isNull);
        expect(shellAfter.activeLabelId, isNull);
        expect(shellAfter.searchOpen, isFalse);
        expect(container.read(taskUndoStateProvider).canUndo, isFalse);
        expect(container.read(settingsDraftProvider).isDirty, isFalse);
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
        final placementControl = find.byKey(
          const ValueKey<String>('quick_add_placement_control'),
        );
        final placementTriggerRect = tester.getRect(placementControl);
        await tester.tap(placementControl);
        await tester.pumpAndSettle();
        final popupSurface = find.descendant(
          of: find.byType(CompositedTransformFollower),
          matching: find.byType(FadeTransition),
        );
        expect(
          tester.getRect(popupSurface).bottom,
          lessThanOrEqualTo(placementTriggerRect.top),
          reason:
              'Quick-Add vertical placement popup must open upward from dock',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(CompositedTransformFollower),
            matching: find.text('Someday'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pumpAndSettle();

        expect(
          container.read(shellProvider).activeTier,
          equals(TaskTier.focus),
          reason: 'Quick-Add must never jump tiers on task creation',
        );
        expect(
          container.read(shellProvider).expandedEntity,
          isNull,
          reason: 'Quick-Add must not auto-expand newly created tasks',
        );
        expect(
          container.read(floatingNoticeProvider)?.message,
          contains('Someday'),
        );

        // Seed an Undo entry, then trigger TDF-DEL-003 deletion conflict.
        await tester.tap(
          find.byKey(const ValueKey<String>('task_complete_taskB00002')),
        );
        await tester.pumpAndSettle();
        expect(container.read(taskUndoStateProvider).canUndo, isTrue);

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
        expect(container.read(shellProvider).view, equals(ShellView.conflict));

        await tester.tap(
          find.byKey(const ValueKey<String>('resolution_apply_button')),
        );
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.tasks));
        expect(
          container.read(taskUndoStateProvider).canUndo,
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
        expect(container.read(shellProvider).view, equals(ShellView.recovery));

        await tester.tap(
          find.byKey(const ValueKey<String>('resolution_apply_button')),
        );
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.tasks));
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
        final shellNotifier = container.read(shellProvider.notifier);
        shellNotifier.openSearch();
        shellNotifier.openDraft(EntityDraftKind.task);
        shellNotifier.setLabelPickerOpen(true);
        container.read(labelPickerQueryProvider.notifier).setQuery('wo');
        shellNotifier.toggleSidebarLabelsFilter();
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(labelPickerQueryProvider),
          isEmpty,
          reason: 'Layer 1 Escape must clear label picker query first',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(shellProvider).sidebarLabelsFilterOpen,
          isFalse,
          reason: 'Layer 2 Escape must close open sidebar filter second',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(shellProvider).labelPickerOpen,
          isFalse,
          reason: 'Layer 4 Escape must close inline label picker',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(shellProvider).activeDraft,
          isNull,
          reason: 'Layer 5 Escape must cancel uncommitted draft card',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(shellProvider).searchOpen,
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
          container.read(shellProvider).activeInlineEdit,
          isNull,
          reason: 'Layer 7 Escape must cancel active inline section edit',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(shellProvider).activeDeleteConfirm,
          isNull,
          reason: 'Layer 8 Escape must cancel active inline delete confirm',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          container.read(shellProvider).expandedEntity,
          isNull,
          reason: 'Layer 9 Escape must collapse expanded entity card',
        );

        // Tablet (> 720px) PopScope unwind: Layer 2 persistent sidebar filter closes before Settings -> Tasks.
        shellNotifier.openView(ShellView.settings);
        shellNotifier.toggleSidebarLabelsFilter();
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).sidebarLabelsFilterOpen, isTrue);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          container.read(shellProvider).sidebarLabelsFilterOpen,
          isFalse,
          reason: 'Tablet PopScope must close open Layer 2 sidebar filter before unwinding view',
        );
        expect(container.read(shellProvider).view, equals(ShellView.settings));

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.tasks));

        // Compact <= 720px: Quick-Add + Labels bottom sheet must NOT auto-focus search input (U-A11Y-003).
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();

        await tester.tap(find.text('New task'));
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

    testWidgets(
      'TierTaskApp pauses localFileWatcherProvider when Local Watch is toggled off in SettingsView and catches up on re-enable',
      (WidgetTester tester) async {
        _setViewport(tester, const Size(1280, 860));
        final tempDir = Directory.systemTemp.createTempSync(
          'tiertask_watch_pause_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final tdfPath = '${tempDir.path}${Platform.pathSeparator}tasks.tdf';
        File(tdfPath).writeAsStringSync(
          'tdf 0.8.0\n\n'
          'queue {\n'
          '  modified 2026-11-10 08:00:00\n'
          '  task 000001OkD2\n'
          '}\n\n'
          'task 000001OkD2 {\n'
          '  name "Initial Focus Task"\n'
          '  created 2026-11-10 08:00:00\n'
          '  modified 2026-11-10 08:00:00\n'
          '}\n',
          flush: true,
        );
        final watchEvents = StreamController<void>.broadcast();
        addTearDown(watchEvents.close);

        final settingsRepository = InMemorySettingsRepository(
          WebDavConfig(
            localFilePath: tdfPath,
            storageMode: StorageMode.local,
            language: AppLanguage.english,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(settingsRepository),
              localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
              localFileRepositoryProvider.overrideWith((ref) {
                final currentConfig =
                    ref.watch(webDavConfigProvider).asData?.value ??
                    WebDavConfig(localFilePath: tdfPath);
                return _DiskBackedWatchLocalFileRepository(
                  config: currentConfig,
                  baseDirectoryPath: tempDir.path,
                  watchStream: watchEvents.stream,
                );
              }),
              clockProvider.overrideWithValue(() => baseTime),
              supportsLocalFileWatchProvider.overrideWithValue(true),
            ],
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Initial Focus Task'), findsOneWidget);
        expect(
          watchEvents.hasListener,
          isTrue,
          reason: 'TierTaskApp must subscribe to localFileWatcherProvider',
        );

        // Open SettingsView and disable Local Watch.
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        final watchToggle = find.byKey(
          const ValueKey<String>('settings_local_watch_toggle'),
        );
        await tester.ensureVisible(watchToggle);
        await tester.tap(watchToggle);
        await tester.pumpAndSettle();

        expect(
          watchEvents.hasListener,
          isFalse,
          reason:
              'Disabling localWatchEnabled must cancel directory watch stream',
        );

        // External write while paused must NOT merge into the board.
        File(tdfPath).writeAsStringSync(
          'tdf 0.8.0\n\n'
          'queue {\n'
          '  modified 2026-11-10 08:45:00\n'
          '  task 000001OkD2\n'
          '  task 000002OkD2\n'
          '}\n\n'
          'task 000001OkD2 {\n'
          '  name "Initial Focus Task"\n'
          '  created 2026-11-10 08:00:00\n'
          '  modified 2026-11-10 08:00:00\n'
          '}\n'
          'task 000002OkD2 {\n'
          '  name "Saved While Paused"\n'
          '  created 2026-11-10 08:45:00\n'
          '  modified 2026-11-10 08:45:00\n'
          '}\n',
          flush: true,
        );
        watchEvents.add(null);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('chrome_brand_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Saved While Paused'),
          findsNothing,
          reason: 'External write must not merge while watcher is disabled',
        );

        // Re-enable Local Watch and verify immediate catch-up reconciliation.
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(watchToggle);
        await tester.tap(watchToggle);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(watchEvents.hasListener, isTrue);
        await tester.tap(
          find.byKey(const ValueKey<String>('chrome_brand_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Saved While Paused'),
          findsOneWidget,
          reason:
              'Re-enabling watcher must catch up external edits immediately',
        );
      },
    );

    testWidgets(
      'TierTaskApp disables localFileWatcherProvider and hides Local Watch toggle on Android',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        _setViewport(tester, const Size(390, 844));
        final tempDir = Directory.systemTemp.createTempSync(
          'tiertask_android_no_watch_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final tdfPath = '${tempDir.path}${Platform.pathSeparator}tasks.tdf';
        File(tdfPath).writeAsStringSync(
          'tdf 0.8.0\n\n'
          'queue {\n'
          '  modified 2026-11-10 08:00:00\n'
          '  task 000001OkD2\n'
          '}\n\n'
          'task 000001OkD2 {\n'
          '  name "Android Task"\n'
          '  created 2026-11-10 08:00:00\n'
          '  modified 2026-11-10 08:00:00\n'
          '}\n',
          flush: true,
        );
        final watchEvents = StreamController<void>.broadcast();
        addTearDown(watchEvents.close);

        final settingsRepository = InMemorySettingsRepository(
          WebDavConfig(
            localFilePath: tdfPath,
            storageMode: StorageMode.local,
            language: AppLanguage.english,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(settingsRepository),
              localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
              localFileRepositoryProvider.overrideWith((ref) {
                final currentConfig =
                    ref.watch(webDavConfigProvider).asData?.value ??
                    WebDavConfig(localFilePath: tdfPath);
                return _DiskBackedWatchLocalFileRepository(
                  config: currentConfig,
                  baseDirectoryPath: tempDir.path,
                  watchStream: watchEvents.stream,
                );
              }),
              clockProvider.overrideWithValue(() => baseTime),
            ],
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Android Task'), findsOneWidget);
        expect(
          watchEvents.hasListener,
          isFalse,
          reason: 'TierTaskApp on Android must not subscribe to localFileWatcherProvider',
        );

        await tester.tap(find.byIcon(Icons.menu_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('settings_local_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('settings_local_watch_toggle')),
          findsNothing,
          reason: 'Android SettingsView must hide the Local Watch toggle',
        );
      },
    );

    testWidgets(
      'TierTaskApp enables foreground GPS in SettingsView, transitions location icon states, and promotes location-conditioned task from Blocked to Focus',
      (WidgetTester tester) async {
        _setViewport(tester, const Size(1280, 860));
        const tdfWithLocationTask = '''
tdf 0.8.0

queue {
  modified 2026-11-10 08:00:00
  task loc100OkD2
}

location locErfOkD2 {
  name "Erfurt"
  coordinates 50.9787 11.0328
  radius 500
}

task loc100OkD2 priority {
  name "Buy local specialty in Erfurt"
  created 2026-11-10 08:00:00
  modified 2026-11-10 08:00:00
  condition location locErfOkD2
}
''';
        const config = WebDavConfig(language: AppLanguage.english);
        final settingsRepository = InMemorySettingsRepository(config);
        final locationRepo = _CompleterLocationRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clockProvider.overrideWithValue(() => baseTime),
              settingsRepositoryProvider.overrideWithValue(settingsRepository),
              localFileRepositoryProvider.overrideWithValue(
                _ControllableLocalFileRepository(
                  config: config,
                  content: tdfWithLocationTask,
                ),
              ),
              locationRepositoryProvider.overrideWithValue(locationRepo),
            ],
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        // While location determination is off, chrome location icon is hidden and unknown location does not block tasks.
        expect(
          find.byKey(const ValueKey<String>('chrome_location_button')),
          findsNothing,
          reason:
              'Location icon must stay hidden while locationEnabled is false',
        );
        expect(find.text('Buy local specialty in Erfurt'), findsOneWidget);

        // Enable foreground location determination in SettingsView.
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        final locationControl = find.byKey(
          const ValueKey<String>('settings_location_control'),
        );
        await tester.ensureVisible(locationControl);
        await tester.tap(
          find.descendant(of: locationControl, matching: find.text('On')),
        );
        await tester.pump();
        await tester.pump();

        // Top-bar Location Status icon appears in searching state while lookup is pending.
        final locationButton = find.byKey(
          const ValueKey<String>('chrome_location_button'),
        );
        expect(locationButton, findsOneWidget);
        expect(
          find.descendant(
            of: locationButton,
            matching: find.byIcon(Icons.refresh_rounded),
          ),
          findsOneWidget,
          reason: 'Chrome location icon must display searching state while fix resolves',
        );

        // Resolve non-matching GPS fix (Berlin): icon shows found and task moves to Blocked.
        locationRepo.completer.complete(
          const LocationFix(
            latitude: 52.5200,
            longitude: 13.4050,
            placeName: 'Berlin, Germany',
            source: LocationSource.gps,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: locationButton,
            matching: find.byIcon(Icons.my_location_rounded),
          ),
          findsOneWidget,
          reason: 'Chrome location icon must transition to found state once fix arrives',
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('chrome_brand_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Buy local specialty in Erfurt'),
          findsNothing,
          reason: 'Non-matching GPS fix must move location-conditioned task out of Focus into Blocked',
        );

        // Refresh location with matching Erfurt fix via Location Status modal: task promotes back to Focus.
        locationRepo.completer = Completer<LocationFix?>();
        await tester.tap(locationButton);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('location_status_refresh_button')),
        );
        await tester.pump();
        locationRepo.completer.complete(
          const LocationFix(
            latitude: 50.9787,
            longitude: 11.0328,
            placeName: 'Erfurt, Germany',
            source: LocationSource.gps,
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(
          find.text('Buy local specialty in Erfurt'),
          findsOneWidget,
          reason: 'Matching GPS fix must promote location-conditioned task from Blocked to Focus',
        );
      },
    );

    testWidgets(
      'TierTaskApp swaps Calm/Plum Umber and Light/Dark themes at runtime via SettingsView and updates live UiThemeTokens',
      (WidgetTester tester) async {
        _setViewport(tester, const Size(1280, 860));
        const initialConfig = WebDavConfig(
          language: AppLanguage.english,
          themeMode: AppThemeMode.light,
        );
        final settingsRepository = InMemorySettingsRepository(initialConfig);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clockProvider.overrideWithValue(() => baseTime),
              settingsRepositoryProvider.overrideWithValue(settingsRepository),
              localFileRepositoryProvider.overrideWithValue(
                _ControllableLocalFileRepository(
                  config: initialConfig,
                  content: buildSeedTdf(),
                ),
              ),
            ],
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        UiThemeTokens readLiveTokens() =>
            UiThemeTokens.of(tester.element(find.byType(TierTaskShellScreen)));

        final calmLight = readLiveTokens();
        expect(
          calmLight.colors.bg,
          equals(UiThemePresets.calm.light.colors.bg),
        );
        expect(
          calmLight.colors.panel,
          equals(UiThemePresets.calm.light.colors.panel),
        );
        expect(
          calmLight.colors.accent,
          equals(UiThemePresets.calm.light.colors.accent),
        );
        expect(
          calmLight.colors.onAccent,
          equals(UiThemePresets.calm.light.colors.onAccent),
        );

        // Open SettingsView and switch palette to Plum Umber and brightness to Dark.
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        final paletteControl = find.byKey(
          const ValueKey<String>('settings_theme_palette_control'),
        );
        await tester.ensureVisible(paletteControl);
        await tester.tap(
          find.descendant(
            of: paletteControl,
            matching: find.text('Plum Umber'),
          ),
        );
        await tester.pumpAndSettle();

        final plumLight = readLiveTokens();
        expect(
          plumLight.colors.bg,
          equals(UiThemePresets.plumUmber.light.colors.bg),
        );
        expect(
          plumLight.colors.panel,
          equals(UiThemePresets.plumUmber.light.colors.panel),
        );
        expect(
          plumLight.colors.accent,
          equals(UiThemePresets.plumUmber.light.colors.accent),
        );
        expect(
          plumLight.colors.onAccent,
          equals(UiThemePresets.plumUmber.light.colors.onAccent),
        );

        final modeControl = find.byKey(
          const ValueKey<String>('settings_theme_mode_control'),
        );
        await tester.ensureVisible(modeControl);
        await tester.tap(
          find.descendant(of: modeControl, matching: find.text('Dark')),
        );
        await tester.pumpAndSettle();

        // Return to Tasks view and verify live Plum Umber Dark tokens across views.
        await tester.tap(
          find.byKey(const ValueKey<String>('chrome_brand_button')),
        );
        await tester.pumpAndSettle();

        final plumDark = readLiveTokens();
        expect(
          plumDark.colors.bg,
          equals(UiThemePresets.plumUmber.dark.colors.bg),
        );
        expect(
          plumDark.colors.panel,
          equals(UiThemePresets.plumUmber.dark.colors.panel),
        );
        expect(
          plumDark.colors.accent,
          equals(UiThemePresets.plumUmber.dark.colors.accent),
        );
        expect(
          plumDark.colors.onAccent,
          equals(UiThemePresets.plumUmber.dark.colors.onAccent),
        );
      },
    );

    testWidgets(
      'TierTaskApp displays localized unsupportedSettingsSchemaVersion full-screen error and invalidates activeWorkspaceProvider on Retry',
      (WidgetTester tester) async {
        _setViewport(tester, const Size(1280, 860));
        var loadAttempts = 0;
        var failWithFutureSchema = true;
        final settingsRepo = _DelayedSettingsRepository(
          onLoad: () async {
            loadAttempts++;
            if (failWithFutureSchema) {
              throw const WorkspaceException(
                WorkspaceErrorKind.unsupportedSettingsSchemaVersion,
                'Settings schemaVersion 2 is newer than supported version 1.',
              );
            }
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(settingsRepo),
              localFileRepositoryProvider.overrideWithValue(
                _ControllableLocalFileRepository(
                  config: const WebDavConfig(language: AppLanguage.english),
                  content: buildSeedTdf(),
                ),
              ),
              clockProvider.overrideWithValue(() => baseTime),
              supportsLocalFileWatchProvider.overrideWithValue(true),
            ],
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(loadAttempts, equals(1));
        expect(
          find.text(
            'Settings were created by a newer TierTask version. Update TierTask to avoid data loss.',
          ),
          findsOneWidget,
          reason: 'TierTaskApp must display localized errorSettingsUnsupportedVersion instead of raw WorkspaceException.toString()',
        );

        // Retry must invalidate activeWorkspaceProvider and reload cleanly.
        failWithFutureSchema = false;
        await tester.tap(
          find.byKey(const ValueKey<String>('tasks_full_error_retry_button')),
        );
        await tester.pumpAndSettle();

        expect(
          loadAttempts,
          greaterThanOrEqualTo(2),
          reason: 'Retry button must invalidate activeWorkspaceProvider and re-attempt settings load',
        );
        expect(
          find.text(
            'Settings were created by a newer TierTask version. Update TierTask to avoid data loss.',
          ),
          findsNothing,
        );
        expect(find.text('Primary Focus Task'), findsOneWidget);
      },
    );

    testWidgets(
      'TierTaskApp consumes one-shot startup settings recovery notices as persistent warning toasts for both early-resolved and async-resolved loads',
      (WidgetTester tester) async {
        _setViewport(tester, const Size(1280, 860));

        // Case 1: Workspace resolves immediately (recoveredFromBackup).
        final earlyRepo = InMemorySettingsRepository.withRecoveryNotice(
          initialConfig: const WebDavConfig(language: AppLanguage.english),
          recoveryNotice: const SettingsRecoveryNotice(
            kind: SettingsRecoveryKind.recoveredFromBackup,
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(earlyRepo),
              localFileRepositoryProvider.overrideWithValue(
                _ControllableLocalFileRepository(
                  config: const WebDavConfig(language: AppLanguage.english),
                  content: buildSeedTdf(),
                ),
              ),
              clockProvider.overrideWithValue(() => baseTime),
              supportsLocalFileWatchProvider.overrideWithValue(true),
            ],
            child: const TierTaskApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Settings were restored from backup after a file error.'),
          findsOneWidget,
          reason: 'Early-resolved recovery notice must display localized persistent backup toast',
        );
        expect(
          earlyRepo.takeLastRecoveryNotice(),
          isNull,
          reason: 'Recovery notice must be consumed once',
        );

        // Case 2: Workspace resolves asynchronously after mount (resetAfterQuarantine).
        final loadGate = Completer<void>();
        final delayedRepo = _DelayedSettingsRepository(
          onLoad: () => loadGate.future,
          recoveryNotice: const SettingsRecoveryNotice(
            kind: SettingsRecoveryKind.resetAfterQuarantine,
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              settingsRepositoryProvider.overrideWithValue(delayedRepo),
              localFileRepositoryProvider.overrideWithValue(
                _ControllableLocalFileRepository(
                  config: const WebDavConfig(language: AppLanguage.english),
                  content: buildSeedTdf(),
                ),
              ),
              clockProvider.overrideWithValue(() => baseTime),
              supportsLocalFileWatchProvider.overrideWithValue(true),
            ],
            child: const TierTaskApp(),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Corrupt settings were backed up and reset to defaults.'),
          findsNothing,
          reason: 'Async recovery notice must not appear before load finishes',
        );

        loadGate.complete();
        await tester.pumpAndSettle();
        expect(
          find.text('Corrupt settings were backed up and reset to defaults.'),
          findsOneWidget,
          reason: 'Async-resolved workspace load must display localized persistent quarantine reset toast',
        );
      },
    );

    testWidgets(
      'Logs -> Settings -> Palette segmented control switch transitions monotonically without AsyncLoading bounce, TaskNotifier resync, or element remounts',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        AppLogger.resetForTesting();
        addTearDown(AppLogger.resetForTesting);

        const initialConfig = WebDavConfig(
          language: AppLanguage.english,
          themeMode: AppThemeMode.light,
          storageMode: StorageMode.local,
          diagnosticsEnabled: true,
          logLevel: LogLevel.debug,
          timeZoneMode: AppTimeZoneMode.manual,
        );
        Completer<void>? saveGate;
        final settingsRepo = _DelayedSettingsRepository(
          initialConfig: initialConfig,
          onLoad: () async {},
          onSave: () async {
            if (saveGate case final gate?) {
              await gate.future;
            }
          },
        );
        final localRepo = _ControllableLocalFileRepository(
          config: initialConfig,
          content: buildSeedTdf(),
        );
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
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

        // Reproduce user flow: Logs -> Settings -> click Plum Umber.
        container.read(shellProvider.notifier).openView(ShellView.logs);
        await tester.pumpAndSettle();
        AppLogger.clear();
        container.read(shellProvider.notifier).openView(ShellView.settings);
        await tester.pumpAndSettle();

        final configTransitions = <AsyncValue<WebDavConfig>>[];
        final taskTransitions = <AsyncValue<TaskBoard>>[];
        final paletteTransitions = <AppThemePalette>[];
        final configSub = container.listen(
          webDavConfigProvider,
          (_, next) => configTransitions.add(next),
        );
        final taskSub = container.listen(
          taskNotifierProvider,
          (_, next) => taskTransitions.add(next),
        );
        final paletteSub = container.listen(
          appThemePaletteProvider,
          (_, next) => paletteTransitions.add(next),
        );
        addTearDown(() {
          configSub.close();
          taskSub.close();
          paletteSub.close();
        });

        final paletteControl = find.byKey(
          const ValueKey<String>('settings_theme_palette_control'),
        );
        final plumTabContainer = find
            .descendant(
              of: paletteControl,
              matching: find.ancestor(
                of: find.text('Plum Umber'),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .first;
        final plumElementBefore = tester.element(plumTabContainer);

        saveGate = Completer<void>();
        await tester.tap(
          find.descendant(
            of: paletteControl,
            matching: find.text('Plum Umber'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(
          tester
              .widget<UiSegmentedControl<AppThemePalette>>(paletteControl)
              .value,
          equals(AppThemePalette.plumUmber),
          reason: 'Mid-flight segmented control must hold Plum Umber without bouncing back',
        );
        expect(
          tester.element(plumTabContainer),
          same(plumElementBefore),
          reason:
              'Mid-flight segmented control must not remount segment elements',
        );

        saveGate.complete();
        saveGate = null;
        await tester.pumpAndSettle();

        expect(
          paletteTransitions,
          equals(const <AppThemePalette>[AppThemePalette.plumUmber]),
          reason: 'Palette selection must transition monotonically once from Calm to Plum Umber',
        );
        expect(
          configTransitions.any((state) => state is AsyncLoading<WebDavConfig>),
          isFalse,
          reason: 'webDavConfigProvider must not bounce through AsyncLoading on palette update',
        );
        expect(
          taskTransitions,
          isEmpty,
          reason: 'Palette update must not rebuild or re-sync TaskNotifier',
        );
        expect(
          tester.element(plumTabContainer),
          same(plumElementBefore),
          reason: 'Post-save segmented control must preserve segment element identity',
        );
        expect(
          AppLogger.fullLogText,
          isNot(contains('domain.lead_window.reevaluated')),
          reason: 'Palette update must not trigger spurious lead-window re-evaluation',
        );
      },
    );

    testWidgets(
      'Rapid sequential preference toggles (Palette -> ThemeMode -> Language) while save is suspended apply optimistically without dropping clicks, AsyncLoading bounce, TaskNotifier resync, WebDavRepository ETag reset, or duplicate log rewrites',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        AppLogger.resetForTesting();
        addTearDown(AppLogger.resetForTesting);

        final tempDirectory = Directory.systemTemp.createTempSync(
          'tiertask_rapid_prefs_',
        );
        addTearDown(() {
          if (tempDirectory.existsSync()) {
            tempDirectory.deleteSync(recursive: true);
          }
        });
        final tdfPath =
            '${tempDirectory.path}${Platform.pathSeparator}tasks.tdf';
        File(tdfPath).writeAsStringSync(buildSeedTdf(), flush: true);

        final initialConfig = WebDavConfig(
          language: AppLanguage.english,
          themeMode: AppThemeMode.light,
          storageMode: StorageMode.local,
          localFilePath: tdfPath,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
          diagnosticsEnabled: true,
        );
        Completer<void>? saveGate;
        final settingsRepository = _DelayedSettingsRepository(
          initialConfig: initialConfig,
          onLoad: () async {},
          onSave: () async {
            if (saveGate case final gate?) {
              await gate.future;
            }
          },
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            localStorageDirectoryPathProvider.overrideWithValue(
              tempDirectory.path,
            ),
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

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        final paletteControl = find.byKey(
          const ValueKey<String>('settings_theme_palette_control'),
        );
        final modeControl = find.byKey(
          const ValueKey<String>('settings_theme_mode_control'),
        );
        final languageControl = find.byKey(
          const ValueKey<String>('settings_language_control'),
        );
        await tester.ensureVisible(paletteControl);
        await tester.ensureVisible(modeControl);
        await tester.ensureVisible(languageControl);

        final webDavRepositoryBefore = container.read(webDavRepositoryProvider);
        final localRepositoryBefore = container.read(
          localFileRepositoryProvider,
        );
        final logRevisionBefore = AppLogger.revision.value;

        final configTransitions = <AsyncValue<WebDavConfig>>[];
        final taskTransitions = <AsyncValue<TaskBoard>>[];
        final configSubscription = container.listen(
          webDavConfigProvider,
          (_, next) => configTransitions.add(next),
        );
        final taskSubscription = container.listen(
          taskNotifierProvider,
          (_, next) => taskTransitions.add(next),
        );
        addTearDown(() {
          configSubscription.close();
          taskSubscription.close();
        });

        saveGate = Completer<void>();

        // Tap 1: Plum Umber palette while disk save is suspended.
        await tester.tap(
          find.descendant(
            of: paletteControl,
            matching: find.text('Plum Umber'),
          ),
        );
        await tester.pump();

        expect(
          container.read(webDavConfigProvider).requireValue.themePalette,
          equals(AppThemePalette.plumUmber),
          reason: 'Palette tap must apply optimistically before save completes',
        );
        expect(
          tester.widget<UiSegmentedControl<AppThemeMode>>(modeControl).enabled,
          isTrue,
          reason:
              'Theme mode control must remain enabled during suspended save',
        );
        expect(
          container.read(webDavRepositoryProvider),
          same(webDavRepositoryBefore),
          reason: 'Palette toggle must keep WebDavRepository instance and ETag cache intact',
        );
        expect(
          container.read(localFileRepositoryProvider),
          same(localRepositoryBefore),
          reason:
              'Palette toggle must keep LocalFileRepository instance intact',
        );
        expect(
          AppLogger.revision.value,
          equals(logRevisionBefore),
          reason: 'Palette toggle must not trigger diagnostic log rewrites',
        );

        // Tap 2: Dark theme mode while disk save is still suspended.
        await tester.tap(
          find.descendant(of: modeControl, matching: find.text('Dark')),
        );
        await tester.pump();

        final afterSecondTap = container
            .read(webDavConfigProvider)
            .requireValue;
        expect(afterSecondTap.themePalette, equals(AppThemePalette.plumUmber));
        expect(
          afterSecondTap.themeMode,
          equals(AppThemeMode.dark),
          reason: 'Second rapid preference click must compose onto first without dropping input',
        );
        expect(
          tester
              .widget<UiSegmentedControl<AppLanguage>>(languageControl)
              .enabled,
          isTrue,
          reason: 'Language control must remain enabled during suspended save',
        );
        expect(
          container.read(webDavRepositoryProvider),
          same(webDavRepositoryBefore),
          reason: 'Theme mode toggle must keep WebDavRepository instance and ETag cache intact',
        );
        expect(
          container.read(localFileRepositoryProvider),
          same(localRepositoryBefore),
          reason:
              'Theme mode toggle must keep LocalFileRepository instance intact',
        );
        expect(
          AppLogger.revision.value,
          equals(logRevisionBefore),
          reason: 'Theme mode toggle must not trigger diagnostic log rewrites',
        );

        // Tap 3: Deutsch language while disk save is still suspended.
        await tester.tap(
          find.descendant(of: languageControl, matching: find.text('Deutsch')),
        );
        await tester.pump();
        // Advance AnimatedTheme (200ms) while disk save Completer remains suspended.
        await tester.pump(const Duration(milliseconds: 250));

        final afterThirdTap = container.read(webDavConfigProvider).requireValue;
        expect(afterThirdTap.themePalette, equals(AppThemePalette.plumUmber));
        expect(afterThirdTap.themeMode, equals(AppThemeMode.dark));
        expect(
          afterThirdTap.language,
          equals(AppLanguage.german),
          reason: 'Third rapid preference click must apply optimistically before save completes',
        );
        final midFlightContext = tester.element(
          find.byType(TierTaskShellScreen),
        );
        expect(
          UiThemeTokens.of(midFlightContext).colors.bg,
          equals(UiThemePresets.plumUmber.dark.colors.bg),
          reason: 'Live theme tokens must reflect Plum Umber Dark immediately',
        );
        expect(
          AppLocalizations.of(midFlightContext).settingsTitle,
          equals('Einstellungen'),
          reason: 'Live locale must reflect German immediately',
        );
        expect(
          AppLogger.revision.value,
          equals(logRevisionBefore + 1),
          reason: 'Locale update must refresh diagnostic log header at most once without double-writing',
        );
        final webDavRepositoryAfterLanguage = container.read(
          webDavRepositoryProvider,
        );
        expect(
          webDavRepositoryAfterLanguage,
          same(webDavRepositoryBefore),
          reason: 'Language toggle must keep WebDavRepository instance and ETag cache intact',
        );
        expect(
          container.read(localFileRepositoryProvider),
          same(localRepositoryBefore),
          reason:
              'Language toggle must keep LocalFileRepository instance intact',
        );

        // Release suspended Completer and settle all queued persistence writes.
        saveGate.complete();
        saveGate = null;
        await tester.pumpAndSettle();

        expect(
          configTransitions.any((state) => state is AsyncLoading<WebDavConfig>),
          isFalse,
          reason: 'Rapid sequential preference saves must never bounce webDavConfigProvider through AsyncLoading',
        );
        expect(
          taskTransitions,
          isEmpty,
          reason:
              'Preference toggles must never resync or rebuild TaskNotifier',
        );
        expect(
          container.read(webDavRepositoryProvider),
          same(webDavRepositoryAfterLanguage),
          reason: 'Completing queued preference writes must not recreate WebDavRepository',
        );

        final persistedConfig = await settingsRepository.loadConfig();
        expect(persistedConfig.themePalette, equals(AppThemePalette.plumUmber));
        expect(persistedConfig.themeMode, equals(AppThemeMode.dark));
        expect(persistedConfig.language, equals(AppLanguage.german));
        expect(
          AppLogger.fullLogText,
          contains('@meta locale=de'),
          reason: 'Diagnostic log header must persist updated locale',
        );
        expect(
          AppLogger.revision.value,
          equals(logRevisionBefore + 4),
          reason: 'Completing 3 preference saves must emit only 1 locale header refresh plus 3 config.update lines without double-writing',
        );
      },
    );

    testWidgets(
      'Leaving RawTdfView auto-disposes rawTdfPreviewProvider so subsequent task mutations perform zero background serializations',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        final countingTdfService = _CountingTdfService();
        final seedBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[
            TaskItem(
              id: 'taskA00001',
              title: 'Primary Focus Task',
              createdAt: baseTime,
              modifiedAt: baseTime,
            ),
            TaskItem(
              id: 'taskB00002',
              title: 'Second Focus Task',
              createdAt: baseTime,
              modifiedAt: baseTime,
            ),
          ],
          queueBlock: TdfQueueBlock(
            modifiedAt: baseTime,
            taskIds: const <String>['taskA00001', 'taskB00002'],
          ),
          evaluationTime: baseTime,
          localEvaluationTime: baseTime,
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.english),
              ),
            ),
            taskNotifierProvider.overrideWith(
              () => FakeTaskNotifier(seedBoard),
            ),
            tdfServiceProvider.overrideWithValue(countingTdfService),
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

        expect(
          countingTdfService.serializeCalls,
          equals(0),
          reason: 'TasksView must not eagerly compute rawTdfPreviewProvider',
        );

        // Open RawTdfView via the sidebar navigation link.
        await tester.tap(find.text('TDF Source'));
        await tester.pumpAndSettle();

        expect(find.byType(RawTdfView), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('raw_tdf_code_block')),
          findsOneWidget,
        );
        expect(
          countingTdfService.serializeCalls,
          equals(1),
          reason: 'Opening RawTdfView must serialize the board exactly once',
        );

        // Navigate back to TasksView so auto-disposed rawTdfPreviewProvider tears down.
        await tester.tap(find.text('Back to tasks'));
        await tester.pumpAndSettle();

        expect(find.byType(RawTdfView), findsNothing);
        expect(container.read(shellProvider).view, equals(ShellView.tasks));

        // Perform multiple real UI task mutations on TasksView.
        await tester.tap(
          find.byKey(const ValueKey<String>('task_complete_taskA00001')),
        );
        await tester.pumpAndSettle();

        final quickAddInput = find.descendant(
          of: find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(quickAddInput, 'Mutated After Leaving Raw View');
        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Second Focus Task'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('task_edit_title_taskB00002')),
        );
        await tester.pumpAndSettle();
        final titleInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('task_title_editor_input_taskB00002'),
          ),
          matching: find.byType(EditableText),
        );
        await tester.enterText(titleInput, 'Renamed After Leaving Raw View');
        await tester.tap(
          find.byKey(
            const ValueKey<String>('task_title_editor_save_taskB00002'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          countingTdfService.serializeCalls,
          equals(1),
          reason: 'Auto-disposed rawTdfPreviewProvider must execute zero background serializations after leaving RawTdfView',
        );

        // Re-opening RawTdfView recomputes fresh serialized output once.
        await tester.tap(find.text('TDF Source'));
        await tester.pumpAndSettle();
        expect(
          countingTdfService.serializeCalls,
          equals(2),
          reason: 'Re-entering RawTdfView must recompute preview once',
        );
        expect(
          find.textContaining('Renamed After Leaving Raw View'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'DeletionConflictView and GenerationRecoveryView decisions survive live locale updates and background board updates without resetting',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        const config = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.both,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
        );
        // Seed 3 Focus tasks (filling soft WIP limit) plus 36h and 4d deadlines so
        // 24h -> 48h and 48h -> 7d lead-window switches genuinely promote tasks.
        final seedBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[
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
            TaskItem(
              id: 'taskC00003',
              title: 'Third Focus Task',
              createdAt: baseTime,
              modifiedAt: baseTime,
            ),
            TaskItem(
              id: 'taskDue48h',
              title: 'Deadline Within 48 Hours',
              dueAt: baseTime.add(const Duration(hours: 36)),
              createdAt: baseTime,
              modifiedAt: baseTime,
            ),
            TaskItem(
              id: 'taskDue7d0',
              title: 'Deadline Within 7 Days',
              dueAt: baseTime.add(const Duration(days: 4)),
              createdAt: baseTime,
              modifiedAt: baseTime,
            ),
          ],
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
            taskIds: const <String>[
              'taskA00001',
              'taskB00002',
              'taskC00003',
              'taskDue48h',
              'taskDue7d0',
            ],
          ),
          evaluationTime: baseTime,
          localEvaluationTime: baseTime,
          dueLeadWindow: config.dueLeadWindow.duration,
        );
        final seedTdf = tdfService.serialize(seedBoard);
        final localRepository = _ControllableLocalFileRepository(
          config: config,
          content: seedTdf,
        );
        final webDavRepository = _InMemoryWebDavRepository(
          config: config,
          remoteTdf: seedTdf,
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(config),
            ),
            localFileRepositoryProvider.overrideWith((ref) => localRepository),
            webDavRepositoryProvider.overrideWith((ref) => webDavRepository),
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

        var boardEmissionCount = 0;
        final boardSubscription = container.listen(taskNotifierProvider, (
          _,
          next,
        ) {
          if (next.hasValue) {
            boardEmissionCount++;
          }
        });
        addTearDown(boardSubscription.close);

        // Part 1: DeletionConflictView decision survival across locale and board updates.
        container
            .read(syncStateProvider.notifier)
            .setConflict(
              'Deletion conflict',
              outcome: const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.deletionConflict,
                message: 'Deletion conflict',
                conflictedTaskIds: <String>['taskA00001'],
              ),
            );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('chrome_sync_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DeletionConflictView), findsOneWidget);

        final conflictCard = find.byKey(
          const ValueKey<String>('conflict_card_task_taskA00001'),
        );
        final conflictSegmented = find.descendant(
          of: conflictCard,
          matching: find.byType(UiSegmentedControl<TdfDeletionResolution>),
        );
        expect(
          tester
              .widget<UiSegmentedControl<TdfDeletionResolution>>(
                conflictSegmented,
              )
              .value,
          equals(TdfDeletionResolution.undelete),
          reason: 'Deletion conflict decision must default to undelete',
        );

        await tester.tap(
          find.descendant(
            of: conflictCard,
            matching: find.text('Confirm Deletion'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<UiSegmentedControl<TdfDeletionResolution>>(
                conflictSegmented,
              )
              .value,
          equals(TdfDeletionResolution.delete),
        );

        final boardEmissionsBeforeConflictUpdates = boardEmissionCount;
        await container
            .read(webDavConfigProvider.notifier)
            .updateLanguage(AppLanguage.german);
        await container
            .read(webDavConfigProvider.notifier)
            .updateDueLeadWindow(DueLeadWindow.hours48);
        await tester.pumpAndSettle();

        expect(
          boardEmissionCount,
          greaterThan(boardEmissionsBeforeConflictUpdates),
          reason: 'Background board re-evaluation must emit a real TaskBoard update',
        );
        expect(container.read(appLocaleProvider), equals(const Locale('de')));
        expect(
          tester
              .widget<UiSegmentedControl<TdfDeletionResolution>>(
                conflictSegmented,
              )
              .value,
          equals(TdfDeletionResolution.delete),
          reason: 'Selected DeletionConflict decision in UI card must survive locale and background board updates',
        );
        expect(
          container.read(conflictDecisionsProvider)[resolutionDecisionKey(
            'task',
            'taskA00001',
          )],
          equals(TdfDeletionResolution.delete),
        );

        // Part 2: GenerationRecoveryView decision survival across locale and board updates.
        await container
            .read(webDavConfigProvider.notifier)
            .updateLanguage(AppLanguage.english);
        await tester.pumpAndSettle();

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
        expect(find.byType(GenerationRecoveryView), findsOneWidget);

        final recoveryCard = find.byKey(
          const ValueKey<String>('recovery_card_task_taskA00001'),
        );
        final recoverySegmented = find.descendant(
          of: recoveryCard,
          matching: find.byType(UiSegmentedControl<TdfRecoveryResolution>),
        );
        expect(
          tester
              .widget<UiSegmentedControl<TdfRecoveryResolution>>(
                recoverySegmented,
              )
              .value,
          equals(TdfRecoveryResolution.recoverAsNew),
          reason: 'Generation recovery decision must default to recoverAsNew',
        );

        await tester.tap(
          find.descendant(
            of: recoveryCard,
            matching: find.text('Discard Local Change'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<UiSegmentedControl<TdfRecoveryResolution>>(
                recoverySegmented,
              )
              .value,
          equals(TdfRecoveryResolution.discard),
        );

        final boardEmissionsBeforeRecoveryUpdates = boardEmissionCount;
        await container
            .read(webDavConfigProvider.notifier)
            .updateLanguage(AppLanguage.german);
        await container
            .read(webDavConfigProvider.notifier)
            .updateDueLeadWindow(DueLeadWindow.days7);
        await tester.pumpAndSettle();

        expect(
          boardEmissionCount,
          greaterThan(boardEmissionsBeforeRecoveryUpdates),
          reason: 'Background board re-evaluation must emit a real TaskBoard update during recovery',
        );
        expect(container.read(appLocaleProvider), equals(const Locale('de')));
        expect(
          tester
              .widget<UiSegmentedControl<TdfRecoveryResolution>>(
                recoverySegmented,
              )
              .value,
          equals(TdfRecoveryResolution.discard),
          reason: 'Selected GenerationRecovery decision in UI card must survive locale and background board updates',
        );
        expect(
          container.read(recoveryDecisionsProvider)[resolutionDecisionKey(
            'task',
            'taskA00001',
          )],
          equals(TdfRecoveryResolution.discard),
        );
      },
    );

    testWidgets(
      'Offline StorageMode.both inline Title and Note edits commit locally, close inline editors, and keep sync error banner visible',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        final tempDirectory = Directory.systemTemp.createTempSync(
          'tiertask_offline_both_',
        );
        addTearDown(() {
          if (tempDirectory.existsSync()) {
            tempDirectory.deleteSync(recursive: true);
          }
        });
        final tdfPath =
            '${tempDirectory.path}${Platform.pathSeparator}tasks.tdf';
        final seedTdf = buildSeedTdf();
        File(tdfPath).writeAsStringSync(seedTdf, flush: true);

        final config = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.both,
          localFilePath: tdfPath,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
        );
        var isWebDavOffline = false;
        final remoteStore = <String, String>{
          config.resolveEndpointUri()?.path ?? '': seedTdf,
        };
        final webDavRepository = FakeWebDavRepository(
          config: config,
          shouldFail: () => isWebDavOffline,
          remoteStore: remoteStore,
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(config),
            ),
            localStorageDirectoryPathProvider.overrideWithValue(
              tempDirectory.path,
            ),
            webDavRepositoryProvider.overrideWith((ref) => webDavRepository),
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

        // Transition WebDAV offline before inline edits begin.
        isWebDavOffline = true;

        // 1. Expand taskA00001 and commit an inline Title edit while offline.
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
        await tester.enterText(titleInput, 'Offline Edited Focus Title');
        await tester.tap(
          find.byKey(
            const ValueKey<String>('task_title_editor_save_taskA00001'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(shellProvider).activeInlineEdit,
          isNull,
          reason: 'Offline dual-storage local title commit must close inline editor cleanly',
        );
        expect(
          find.byKey(
            const ValueKey<String>('task_title_editor_input_taskA00001'),
          ),
          findsNothing,
        );
        expect(
          find.text('Offline Edited Focus Title'),
          findsOneWidget,
          reason: 'Updated task title must render immediately on the card',
        );
        expect(
          File(tdfPath).readAsStringSync(),
          contains('Offline Edited Focus Title'),
          reason: 'Updated task title must be persisted to local .tdf on disk',
        );
        expect(
          find.byKey(
            const ValueKey<String>('tasks_status_banner_partialFileRead'),
          ),
          findsOneWidget,
          reason: 'Offline remote failure in StorageMode.both must keep the partial file-read danger banner visible',
        );
        expect(
          container.read(syncStateProvider).fileReadReport?.remote?.isReadable,
          isFalse,
        );
        expect(container.read(syncStateProvider).errorMessage, isNotNull);

        // 2. Commit an inline Note edit while sync error banner is already active.
        final addNoteChip = find.byKey(
          const ValueKey<String>('task_add_note_taskA00001'),
        );
        await tester.ensureVisible(addNoteChip);
        await tester.pumpAndSettle();
        await tester.tap(addNoteChip);
        await tester.pumpAndSettle();

        final noteSection = find.byType(EntityNoteSection);
        final noteInput = find.descendant(
          of: noteSection,
          matching: find.byType(EditableText),
        );
        await tester.enterText(noteInput, 'Persisted Offline Local Note');
        await tester.tap(
          find.descendant(
            of: noteSection,
            matching: find.widgetWithText(UiButton, 'Save'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(shellProvider).activeInlineEdit,
          isNull,
          reason: 'Offline dual-storage local note commit must close inline editor cleanly',
        );
        expect(
          find.text('Persisted Offline Local Note'),
          findsOneWidget,
          reason: 'Updated task note must render on the card',
        );
        expect(
          File(tdfPath).readAsStringSync(),
          contains('Persisted Offline Local Note'),
          reason: 'Updated task note must be persisted to local .tdf on disk',
        );
        expect(
          find.byKey(
            const ValueKey<String>('tasks_status_banner_partialFileRead'),
          ),
          findsOneWidget,
          reason: 'Sync error banner must remain visible after offline local note edit',
        );
      },
    );

    testWidgets(
      'saveSubtasks auto-finish and createAndAssignLabel each commit in a single atomic saveTdf write and preserve Undo',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        const config = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.local,
        );
        final localRepository = _ControllableLocalFileRepository(
          config: config,
          content: buildSeedTdf(includeSubtaskTask: true),
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(config),
            ),
            localFileRepositoryProvider.overrideWith((ref) => localRepository),
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

        // Part 1: Inline subtasks editor check-all with auto-finish commits in 1 saveTdf call and supports Undo.
        final saveCallsBeforeSubtasks = localRepository.saveCalls;
        await tester.tap(find.text('Checklist Focus Task'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey<String>('task_subtasks_edit_button_taskS00003'),
          ),
        );
        await tester.pumpAndSettle();

        final subtasksEditor = find.byKey(
          const ValueKey<String>('task_subtasks_edit_taskS00003'),
        );
        expect(subtasksEditor, findsOneWidget);
        expect(
          tester
              .widget<UiToggleRow>(
                find.byKey(
                  const ValueKey<String>(
                    'subtask_auto_finish_toggle_taskS00003',
                  ),
                ),
              )
              .value,
          isTrue,
        );

        await tester.tap(
          find.descendant(
            of: subtasksEditor,
            matching: find.byType(TaskSubtaskCheckBoxButton),
          ),
        );
        await tester.pumpAndSettle();

        final subtasksSaveButton = find.descendant(
          of: subtasksEditor,
          matching: find.widgetWithText(UiButton, 'Save'),
        );
        await tester.ensureVisible(subtasksSaveButton);
        await tester.pumpAndSettle();
        await tester.tap(subtasksSaveButton);
        await tester.pumpAndSettle();

        expect(
          localRepository.saveCalls,
          equals(saveCallsBeforeSubtasks + 1),
          reason: 'saveSubtasks auto-finish must execute exactly one atomic saveTdf write',
        );
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('taskS00003')
              ?.isCompleted,
          isTrue,
        );
        expect(
          container.read(floatingNoticeProvider)?.hasUndoAction,
          isTrue,
          reason: 'Atomic subtask auto-finish must present Undo toast',
        );

        await tester.tap(find.widgetWithText(UiButton, 'Undo'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('taskS00003')
              ?.isCompleted,
          isFalse,
          reason: 'Undo after atomic saveSubtasks auto-finish must restore task to open state',
        );

        // Part 2: Inline label picker create-and-assign commits in 1 saveTdf call.
        final saveCallsBeforeLabelCreate = localRepository.saveCalls;
        await tester.tap(find.text('Second Focus Task'));
        await tester.pumpAndSettle();

        final addLabelsChip = find.byKey(
          const ValueKey<String>('task_add_labels_taskB00002'),
        );
        await tester.ensureVisible(addLabelsChip);
        await tester.pumpAndSettle();
        await tester.tap(addLabelsChip);
        await tester.pumpAndSettle();

        final inlineLabelPicker = find.byKey(
          const ValueKey<String>('task_labels_picker_taskB00002'),
        );
        expect(inlineLabelPicker, findsOneWidget);

        final pickerSearchInput = find.descendant(
          of: inlineLabelPicker,
          matching: find.byType(EditableText),
        );
        await tester.enterText(pickerSearchInput, 'AtomicLabel');
        await tester.pumpAndSettle();

        final createRow = find.text('Create & assign "AtomicLabel"');
        await tester.ensureVisible(createRow);
        await tester.pumpAndSettle();
        await tester.tap(createRow);
        await tester.pumpAndSettle();

        expect(
          localRepository.saveCalls,
          equals(saveCallsBeforeLabelCreate + 1),
          reason: 'createAndAssignLabel must execute exactly one atomic saveTdf write',
        );

        final boardAfterLabelCreate = container
            .read(taskNotifierProvider)
            .requireValue;
        final createdLabel = boardAfterLabelCreate.labels.firstWhere(
          (label) => label.name == 'AtomicLabel',
        );
        expect(
          createdLabel.id,
          isNot(startsWith('_')),
          reason: 'Created label must carry a real persisted TDF ID',
        );
        expect(
          boardAfterLabelCreate.findTask('taskB00002')?.labelIds,
          contains(createdLabel.id),
          reason: 'Created label must be assigned to taskB00002',
        );
        expect(
          localRepository.content,
          contains('AtomicLabel'),
          reason: 'Atomic label creation must persist to .tdf storage',
        );
      },
    );

    testWidgets(
      'Compact mobile CompactLabelPickerSheet reactively creates real persisted label IDs without synthetic IDs, toggles live, and displays the real chip on close',
      (tester) async {
        _setViewport(tester, const Size(390, 844));
        const config = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.local,
        );
        final localRepository = _ControllableLocalFileRepository(
          config: config,
          content: buildSeedTdf(),
        );

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(config),
            ),
            localFileRepositoryProvider.overrideWith((ref) => localRepository),
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

        // Expand taskB00002 and open the compact mobile label picker bottom sheet.
        await tester.tap(find.text('Second Focus Task'));
        await tester.pumpAndSettle();

        final addLabelsChip = find.byKey(
          const ValueKey<String>('task_add_labels_taskB00002'),
        );
        await tester.ensureVisible(addLabelsChip);
        await tester.tap(addLabelsChip);
        await tester.pumpAndSettle();

        expect(find.byType(CompactLabelPickerSheet), findsOneWidget);
        final pickerFinder = find.byKey(
          const ValueKey<String>('compact_label_picker'),
        );
        expect(pickerFinder, findsOneWidget);

        // Type a brand-new label name and tap Create inside the open sheet.
        final sheetSearchInput = find.descendant(
          of: pickerFinder,
          matching: find.byType(EditableText),
        );
        await tester.enterText(sheetSearchInput, 'MobileTag');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Create & assign "MobileTag"'));
        await tester.pumpAndSettle();

        final boardAfterCreate = container
            .read(taskNotifierProvider)
            .requireValue;
        final createdLabel = boardAfterCreate.labels.firstWhere(
          (label) => label.name == 'MobileTag',
        );
        expect(
          createdLabel.id,
          isNot(startsWith('_')),
          reason: 'Compact sheet creation must use real persisted TdfLabel.id instead of synthetic _created_0 ID',
        );
        expect(
          boardAfterCreate.findTask('taskB00002')?.labelIds,
          contains(createdLabel.id),
        );

        final searchablePickerFinder = find.descendant(
          of: pickerFinder,
          matching: find.byType(UiSearchablePicker<String>),
        );
        final pickerAfterCreate = tester.widget<UiSearchablePicker<String>>(
          searchablePickerFinder,
        );
        expect(
          pickerAfterCreate.selectedIds,
          equals(<String>{createdLabel.id}),
          reason: 'Open compact sheet must immediately show real persisted ID selected with zero synthetic IDs',
        );
        expect(
          find.byKey(ValueKey<String>('picker_opt_${createdLabel.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey<String>('picker_chip_${createdLabel.id}')),
          findsOneWidget,
        );

        // Toggle the real label off inside the still-open sheet.
        final optionRow = find.byKey(
          ValueKey<String>('picker_opt_${createdLabel.id}'),
        );
        await tester.tap(optionRow);
        await tester.pumpAndSettle();

        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('taskB00002')
              ?.labelIds,
          isNot(contains(createdLabel.id)),
          reason: 'Toggling newly created label off inside compact sheet must immediately update real board',
        );
        expect(
          tester
              .widget<UiSearchablePicker<String>>(searchablePickerFinder)
              .selectedIds,
          isEmpty,
        );

        // Toggle the real label back on inside the still-open sheet.
        await tester.tap(optionRow);
        await tester.pumpAndSettle();

        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('taskB00002')
              ?.labelIds,
          contains(createdLabel.id),
          reason: 'Toggling newly created label back on inside compact sheet must immediately update real board',
        );
        expect(
          tester
              .widget<UiSearchablePicker<String>>(searchablePickerFinder)
              .selectedIds,
          equals(<String>{createdLabel.id}),
        );

        // Close the sheet and verify the real label chip is rendered on the expanded card.
        await tester.tap(find.widgetWithText(UiButton, 'Done'));
        await tester.pumpAndSettle();

        expect(find.byType(CompactLabelPickerSheet), findsNothing);
        expect(
          find.byKey(
            ValueKey<String>(
              'task_expanded_label_taskB00002_${createdLabel.id}',
            ),
          ),
          findsOneWidget,
          reason: 'Closing compact sheet must display the real persisted label chip on the card',
        );
        expect(find.text('MobileTag'), findsOneWidget);
      },
    );

    testWidgets(
      'TierTaskApp skips remote log flush on inactive, deduplicates background flushes, and drains WorkspaceUnloadCoordinator on exit',
      (tester) async {
        _setViewport(tester, const Size(1280, 860));
        const config = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.both,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
          diagnosticsEnabled: true,
          logStorageMode: StorageMode.both,
        );
        final settingsRepo = InMemorySettingsRepository(config);
        final localRepo = _ControllableLocalFileRepository(
          config: config,
          content: 'tdf 0.8.0\n',
        );
        final saveLogGate = Completer<void>();
        var saveLogCount = 0;
        final webDavRepo = _GatedLogWebDavRepository(
          config: config,
          onSaveLog: () async {
            saveLogCount++;
            await saveLogGate.future;
          },
        );
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            localFileRepositoryProvider.overrideWithValue(localRepo),
            webDavRepositoryProvider.overrideWithValue(webDavRepo),
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

        // Desktop focus loss (inactive) must NOT flood WebDAV with remote log PUTs.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(
          saveLogCount,
          equals(0),
          reason: 'AppLifecycleState.inactive must not trigger remote WebDAV log uploads',
        );

        // Backgrounding (hidden -> paused) must flush once and deduplicate overlapping flushes.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(
          saveLogCount,
          equals(1),
          reason: 'Concurrent hidden and paused transitions must deduplicate into one remote log upload',
        );
        saveLogGate.complete();
        await tester.pump();

        // onExitRequested must drain WorkspaceUnloadCoordinator before flushing AppLogger and approving exit.
        final exitDrainGate = Completer<void>();
        var unloadDrained = false;
        container.read(workspaceUnloadCoordinatorProvider).register(() async {
          await exitDrainGate.future;
          unloadDrained = true;
        });

        final exitFuture = tester.binding.handleRequestAppExit();
        await tester.pump();
        expect(
          unloadDrained,
          isFalse,
          reason: 'onExitRequested must wait for WorkspaceUnloadCoordinator before exiting',
        );

        exitDrainGate.complete();
        final exitResponse = await exitFuture;
        expect(unloadDrained, isTrue);
        expect(exitResponse, equals(AppExitResponse.exit));
        expect(
          AppLogger.lines.any((line) => line.contains('session.exit')),
          isTrue,
          reason: 'onExitRequested must flush AppLogger after draining unload',
        );
      },
    );
  });
}

class _GatedLogWebDavRepository extends FakeWebDavRepository {
  _GatedLogWebDavRepository({required super.config, required this.onSaveLog})
    : super(shouldFail: () => false);

  final Future<void> Function() onSaveLog;

  @override
  Future<void> saveLog(String logFileName, [String? logContent]) => onSaveLog();
}
