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

import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_board_sync.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  late Directory tempDir;
  late String logFilePath;
  final fixedUtc = DateTime.utc(2026, 11, 3, 22, 5, 14, 128);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tiertask_logger_test_');
    logFilePath = '${tempDir.path}${Platform.pathSeparator}tiertask.log';
    AppLogger.resetForTesting(clock: () => fixedUtc);
  });

  tearDown(() async {
    AppLogger.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AppLogger Opt-In Activation & Immediate Deletion', () {
    test('performs zero disk I/O when disabled and deletes tiertask.log immediately when disabled', () {
      expect(
        AppLogger.isEnabled,
        isFalse,
        reason: 'AppLogger must be disabled by default',
      );

      AppLogger.debug(LogTag.lifecycle, 'Ignored debug message');
      AppLogger.info(LogTag.domain, 'Ignored info message');
      AppLogger.warn(LogTag.sync, 'Ignored warn message');
      AppLogger.error(LogTag.storage, 'Ignored error message');
      AppLogger.crash(StateError('Ignored crash'), StackTrace.current);

      final logFile = File(logFilePath);
      expect(
        logFile.existsSync(),
        isFalse,
        reason: 'No log file may be created while logging is disabled',
      );
      expect(
        AppLogger.lines,
        isEmpty,
        reason: 'In-memory log buffer must remain empty while disabled',
      );

      AppLogger.setEnabled(true, logFilePath: logFilePath);
      expect(
        AppLogger.isEnabled,
        isTrue,
        reason: 'AppLogger must report enabled after setEnabled(true)',
      );
      expect(
        logFile.existsSync(),
        isTrue,
        reason: 'Enabling logging must create tiertask.log with session start',
      );
      AppLogger.info(LogTag.lifecycle, 'Active log entry');
      expect(
        logFile.readAsStringSync(),
        contains('=== SESSION START 2026-11-03 22:05:14.128'),
        reason: 'Fresh session must start with SESSION START header',
      );
      expect(
        logFile.readAsStringSync(),
        contains('2026-11-03 22:05:14.128 [INFO] [LIFECYCLE] Active log entry'),
        reason: 'Active log entry must be written synchronously to disk',
      );

      AppLogger.setEnabled(false, logFilePath: logFilePath);
      expect(
        AppLogger.isEnabled,
        isFalse,
        reason: 'AppLogger must report disabled after setEnabled(false)',
      );
      expect(
        AppLogger.lines,
        isEmpty,
        reason: 'Disabling logging must clear the in-memory log buffer',
      );
      expect(
        logFile.existsSync(),
        isFalse,
        reason: 'Disabling logging must immediately delete tiertask.log',
      );
    });
  });

  group('Structured Format, Credential Sanitization & Rolling Cap', () {
    test('formats all LogLevel and LogTag variants consistently and redacts credentials and Authorization headers', () {
      AppLogger.setEnabled(
        true,
        logFilePath: logFilePath,
        secretToRedact: 'MySuperSecretWebDavPass!2026',
      );

      AppLogger.debug(
        LogTag.tdf,
        'Debug TDF message with Authorization: Basic YWxpY2U6c2VjcmV0',
      );
      AppLogger.info(
        LogTag.domain,
        'Connected to https://alice:urlPass123@cloud.example.com/dav',
      );
      AppLogger.warn(
        LogTag.sync,
        'Retry with password=inlinePassword99 and Basic dXNlcjpwYXNz',
      );
      AppLogger.error(
        LogTag.storage,
        'Failed with secret MySuperSecretWebDavPass!2026',
      );
      AppLogger.info(LogTag.ui, 'Opened Log Viewer');

      final diskText = File(logFilePath).readAsStringSync();
      expect(
        diskText,
        contains('2026-11-03 22:05:14.128 [DEBUG] [TDF]'),
        reason: 'DEBUG level and TDF tag must match structured format',
      );
      expect(
        diskText,
        contains('2026-11-03 22:05:14.128 [INFO] [DOMAIN]'),
        reason: 'INFO level and DOMAIN tag must match structured format',
      );
      expect(
        diskText,
        contains('2026-11-03 22:05:14.128 [WARN] [SYNC]'),
        reason: 'WARN level and SYNC tag must match structured format',
      );
      expect(
        diskText,
        contains('2026-11-03 22:05:14.128 [ERROR] [STORAGE]'),
        reason: 'ERROR level and STORAGE tag must match structured format',
      );
      expect(
        diskText,
        contains('2026-11-03 22:05:14.128 [INFO] [UI] Opened Log Viewer'),
        reason: 'UI tag must match structured format',
      );

      expect(
        diskText,
        isNot(contains('YWxpY2U6c2VjcmV0')),
        reason: 'Base64 Basic Auth token must be redacted',
      );
      expect(
        diskText,
        isNot(contains('urlPass123')),
        reason: 'Embedded URL userinfo password must be redacted',
      );
      expect(
        diskText,
        isNot(contains('inlinePassword99')),
        reason: 'password=... value must be redacted',
      );
      expect(
        diskText,
        isNot(contains('dXNlcjpwYXNz')),
        reason: 'Standalone Basic token must be redacted',
      );
      expect(
        diskText,
        isNot(contains('MySuperSecretWebDavPass!2026')),
        reason: 'Registered WebDAV password must be redacted',
      );
      expect(
        diskText,
        contains('[REDACTED]'),
        reason: 'Redacted secrets must be replaced with [REDACTED]',
      );
    });

    test('trims oldest 20% of regular entries when maxLines is exceeded while preserving session header and crash blocks', () {
      File(logFilePath).writeAsStringSync(
        '2026-11-03 21:00:00.000 [CRASH] [LIFECYCLE] Previous fatal error\n'
        '2026-11-03 21:00:00.000 [CRASH] [LIFECYCLE] #0 main (main.dart:10)\n',
        flush: true,
      );

      AppLogger.setEnabled(true, logFilePath: logFilePath, maxLines: 20);

      for (var i = 1; i <= 25; i++) {
        AppLogger.info(LogTag.domain, 'Regular log line $i');
      }

      final currentLines = AppLogger.lines;
      expect(
        currentLines.length <= 20,
        isTrue,
        reason: 'Line buffer must stay within maxLines after 20% pruning',
      );
      expect(
        currentLines.any((line) => line.contains('Previous fatal error')),
        isTrue,
        reason: 'Unacknowledged [CRASH] lines must be preserved during pruning',
      );
      expect(
        currentLines.any(
          (line) => line.contains('RECOVERED UNCLEAN EXIT / CRASH LOG ABOVE'),
        ),
        isTrue,
        reason: 'Recovery banner must be preserved during pruning',
      );
      expect(
        currentLines.last,
        contains('Regular log line 25'),
        reason: 'Newest log entries must be retained after pruning',
      );
    });
  });

  group('Lifecycle State Machine & Crash Preservation', () {
    test('sleep states (inactive, hidden, paused, resumed) preserve log file, whereas detached truncates tiertask.log to 0 bytes', () {
      AppLogger.setEnabled(true, logFilePath: logFilePath);
      AppLogger.info(LogTag.domain, 'Task added before sleep');

      for (final state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.resumed,
      ]) {
        AppLogger.handleAppLifecycleState(state);
        final fileContent = File(logFilePath).readAsStringSync();
        expect(
          fileContent,
          isNotEmpty,
          reason:
              'Transition to ${state.name} must never truncate tiertask.log',
        );
        expect(
          fileContent,
          contains('[LIFECYCLE]'),
          reason: 'Transition to ${state.name} must record a LIFECYCLE entry',
        );
        expect(
          fileContent,
          contains(state.name),
          reason: 'LIFECYCLE entry must mention ${state.name}',
        );
      }

      AppLogger.handleAppLifecycleState(AppLifecycleState.detached);
      final afterDetached = File(logFilePath).readAsStringSync();
      expect(
        afterDetached,
        isEmpty,
        reason: 'Clean exit (AppLifecycleState.detached) must truncate tiertask.log to 0 bytes',
      );
    });

    test('AppLogger.crash flushes stack trace, prevents truncation on detached, and next startup preserves crash log with recovery banner', () {
      AppLogger.setEnabled(true, logFilePath: logFilePath);
      AppLogger.info(LogTag.domain, 'Operation before crash');

      final trace = StackTrace.fromString(
        '#0      TaskBoard.completeTask (package:tiertask/models/task_board.dart:450)\n'
        '#1      main (package:tiertask/main.dart:60)',
      );
      AppLogger.crash(StateError('Simulated fatal defect'), trace);

      AppLogger.handleAppLifecycleState(AppLifecycleState.detached);
      final crashedFileContent = File(logFilePath).readAsStringSync();
      expect(
        crashedFileContent,
        isNotEmpty,
        reason: 'Detached after AppLogger.crash must NOT truncate tiertask.log',
      );
      expect(
        crashedFileContent,
        contains('[CRASH] [LIFECYCLE]'),
        reason: 'Crash entry must be logged with CRASH level and LIFECYCLE tag',
      );
      expect(
        crashedFileContent,
        contains('Simulated fatal defect'),
        reason: 'Crash entry must include the exception description',
      );
      expect(
        crashedFileContent,
        contains('TaskBoard.completeTask'),
        reason: 'Crash entry must include the stack trace',
      );

      final nextBootUtc = DateTime.utc(2026, 11, 3, 22, 10, 0, 0);
      AppLogger.resetForTesting(clock: () => nextBootUtc);
      AppLogger.setEnabled(true, logFilePath: logFilePath);
      AppLogger.info(LogTag.lifecycle, 'First entry in new session');

      final recoveredContent = File(logFilePath).readAsStringSync();
      expect(
        recoveredContent,
        contains('Simulated fatal defect'),
        reason: 'Startup after unclean exit must preserve previous crash log',
      );
      expect(
        recoveredContent,
        contains(
          '=== RECOVERED UNCLEAN EXIT / CRASH LOG ABOVE | NEW SESSION START 2026-11-03 22:10:00.000',
        ),
        reason: 'Startup after unclean exit must append the recovery banner',
      );
      expect(
        recoveredContent,
        contains('First entry in new session'),
        reason: 'New session entries must be appended below recovery banner',
      );
    });
  });

  group('Full Subsystem Instrumentation', () {
    test('instruments TdfService, TaskBoard mutations, TaskBoardSync.merge, LocalFileRepository, and WebDavRepository', () async {
      AppLogger.setEnabled(true, logFilePath: logFilePath);

      const tdfService = TdfService();
      expect(
        () => tdfService.parse('invalid header'),
        throwsA(isA<TdfException>()),
        reason: 'Malformed TDF must throw TdfException',
      );
      expect(
        AppLogger.fullLogText,
        contains('[ERROR] [TDF]'),
        reason: 'TdfService.parse failure must log [ERROR] [TDF]',
      );

      var board = TaskBoard.empty()
          .addLabel('Work', color: '#4CAF50', currentDate: fixedUtc)
          .addTask(
            'Recurring backup',
            targetTier: TaskTier.focus,
            isPriority: true,
            repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
            subtasksAutoFinish: true,
            subtasks: const [SubtaskItem(title: 'Verify checksums')],
            currentDate: fixedUtc,
          )
          .addTask(
            'Secondary task',
            targetTier: TaskTier.ready,
            currentDate: fixedUtc,
          );

      final labelId = board.labels.first.id;
      final firstTaskId = board.allTasks.first.id;
      final secondTaskId = board.allTasks.last.id;

      board = board
          .updateLabel(labelId, name: 'Engineering', currentDate: fixedUtc)
          .updateTask(
            secondTaskId,
            title: 'Secondary task updated',
            currentDate: fixedUtc,
          )
          .downgradeTask(secondTaskId, currentDate: fixedUtc)
          .scheduleTask(secondTaskId, currentDate: fixedUtc)
          .blockTask(secondTaskId, currentDate: fixedUtc)
          .toggleSubtask(firstTaskId, 0, currentDate: fixedUtc);

      final expiredTask = TaskItem(
        id: 'exp100OkD2',
        title: 'Expired Completed Task',
        isCompleted: true,
        createdAt: fixedUtc.subtract(const Duration(days: 40)),
        queuedAt: fixedUtc.subtract(const Duration(days: 40)),
        completedAt: fixedUtc.subtract(const Duration(days: 35)),
        modifiedAt: fixedUtc.subtract(const Duration(days: 35)),
      );
      board = board
          .copyWith(completed: [expiredTask])
          .pruneCompletedTasks(currentDate: fixedUtc)
          .deleteLabel(labelId, currentDate: fixedUtc);

      final serialized = tdfService.serialize(board);
      final parsed = tdfService.parse(serialized, evaluationTime: fixedUtc);
      parsed.evaluateForContext(
        activeLabelId: labelId,
        evaluationTime: fixedUtc,
      );

      TaskBoardSync.merge(
        primary: board,
        secondary: parsed,
        evaluationTime: fixedUtc,
      );

      final localRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'instrumented.tdf'),
        baseDirectoryPath: tempDir.path,
      );
      await localRepo.saveTdf(serialized);
      await localRepo.loadTdf();

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.write(serialized);
        await request.response.close();
      });

      final webDavRepo = WebDavRepository(
        config: WebDavConfig(
          serverUrl: 'http://${server.address.host}:${server.port}',
          username: 'alice',
          password: 'secret-webdav-password',
          filePath: 'instrumented.tdf',
          storageMode: StorageMode.webdav,
        ),
      );
      await webDavRepo.fetchTdf();
      await webDavRepo.saveTdf(serialized);

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(
                localFilePath: 'notifier.tdf',
                diagnosticsEnabled: true,
              ),
            ),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedUtc),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);
      await container
          .read(taskNotifierProvider.notifier)
          .addTask('Notifier task', isPriority: true, currentDate: fixedUtc);
      final notifierTaskId = container
          .read(taskNotifierProvider)
          .requireValue
          .allTasks
          .first
          .id;
      await container
          .read(taskNotifierProvider.notifier)
          .completeTask(notifierTaskId, currentDate: fixedUtc);
      await container
          .read(taskNotifierProvider.notifier)
          .restoreTask(notifierTaskId, currentDate: fixedUtc);

      final logOutput = AppLogger.fullLogText;
      expect(
        logOutput,
        contains('[TDF]'),
        reason: 'TdfService parse and serialize must emit [TDF] logs',
      );
      expect(
        logOutput,
        contains('[DOMAIN]'),
        reason: 'TaskBoard mutations must emit [DOMAIN] logs',
      );
      expect(
        logOutput,
        contains('Focus='),
        reason: 'Domain logs must include 6-tier distribution counts',
      );
      expect(
        logOutput,
        contains('[SYNC]'),
        reason: 'TaskBoardSync and TaskNotifier sync must emit [SYNC] logs',
      );
      expect(
        logOutput,
        contains('[STORAGE]'),
        reason:
            'LocalFileRepository and WebDavRepository must emit [STORAGE] logs',
      );
      expect(
        logOutput,
        isNot(contains('secret-webdav-password')),
        reason: 'WebDavRepository logs must never leak the password',
      );
    });
  });
}
