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

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_board_sync.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  late Directory tempDir;
  late String logFilePath;
  final fixedUtc = DateTime.utc(2026, 11, 3, 22, 5, 14, 128);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tiertask_logger_test_');
    logFilePath =
        '${tempDir.path}${Platform.pathSeparator}'
        'tiertask_2026-11-03_linux_default.log';
    AppLogger.resetForTesting(
      clock: () => fixedUtc,
      sink: const LocalFileLogSink(),
    );
  });

  tearDown(() async {
    AppLogger.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group(
    'AppLogger Opt-In Activation, Metadata Header & Immediate Deletion',
    () {
      test('performs zero disk I/O when disabled and deletes workspace log files immediately when disabled', () {
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

        const metadata = LogMetadata(
          appVersion: '0.2.3+1',
          platform: 'linux',
          osVersion: 'Linux 6.12',
          locale: 'en_US',
          timeZone: 'UTC (+00:00)',
          workspaceId: 'default',
          workspaceName: 'Default',
          storageMode: 'both',
          logStorageMode: 'local',
        );
        AppLogger.setEnabled(
          true,
          logFilePath: logFilePath,
          minimumLevel: LogLevel.info,
          metadata: metadata,
        );
        expect(
          AppLogger.isEnabled,
          isTrue,
          reason: 'AppLogger must report enabled after setEnabled(true)',
        );
        expect(
          logFile.existsSync(),
          isTrue,
          reason: 'Enabling logging must create the dated log file with header',
        );
        AppLogger.event(
          LogLevel.info,
          LogTag.lifecycle,
          'custom.event',
          fields: <String, Object?>{'key': 'value'},
        );
        final diskContent = logFile.readAsStringSync();
        expect(
          diskContent,
          contains('=== TIERTASK DIAGNOSTIC LOG ==='),
          reason: 'Fresh session must start with @meta header block',
        );
        expect(
          diskContent,
          contains(
            '@meta workspace_id=default workspace_name="Default" '
            'storage_mode=both log_storage=local min_level=INFO',
          ),
          reason: 'Metadata header must include workspace and storage fields',
        );
        expect(
          diskContent,
          contains(
            '2026-11-03T22:05:14.128Z [INFO ] [LIFECYCLE] session.start |',
          ),
          reason: 'Fresh session must emit session.start entry in UTC ISO-8601',
        );
        expect(
          diskContent,
          contains(
            '2026-11-03T22:05:14.128Z [INFO ] [LIFECYCLE] '
            'custom.event | key=value',
          ),
          reason: 'Active log entry must be written synchronously to disk',
        );

        AppLogger.setEnabled(
          false,
          logFilePath: logFilePath,
          metadata: metadata,
        );
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
          reason: 'Disabling logging must immediately delete the log file',
        );
      });

      test(
        'formats deterministic dated log filenames and sanitizes workspace IDs',
        () {
          final fileName = AppLogger.formatLogFileName(
            utcNow: fixedUtc,
            platform: 'Linux Desktop',
            workspaceId: 'work/space:01',
          );
          expect(
            fileName,
            equals('tiertask_2026-11-03_linux_desktop_work_space_01.log'),
            reason: 'formatLogFileName must produce canonical dated filename',
          );
        },
      );
    },
  );

  group(
    'Structured Format, Level Thresholding, Sanitization & Rolling Cap',
    () {
      test('formats 5-char padded LogLevel and 9-char padded LogTag variants and redacts secrets', () {
        AppLogger.setEnabled(
          true,
          logFilePath: logFilePath,
          minimumLevel: LogLevel.debug,
          secretToRedact: 'MySuperSecretWebDavPass!2026',
        );

        AppLogger.event(
          LogLevel.debug,
          LogTag.tdf,
          'tdf.parse',
          fields: <String, Object?>{
            'header': 'Authorization: Basic YWxpY2U6c2VjcmV0',
          },
        );
        AppLogger.event(
          LogLevel.info,
          LogTag.domain,
          'task.add',
          fields: <String, Object?>{
            'endpoint': 'https://alice:urlPass123@cloud.example.com/dav',
          },
        );
        AppLogger.event(
          LogLevel.warn,
          LogTag.sync,
          'sync.conflict',
          fields: <String, Object?>{
            'detail': 'password=inlinePassword99 and Basic dXNlcjpwYXNz',
          },
        );
        AppLogger.event(
          LogLevel.error,
          LogTag.storage,
          'webdav.get',
          fields: <String, Object?>{
            'error': 'Failed with secret MySuperSecretWebDavPass!2026',
          },
        );
        AppLogger.event(
          LogLevel.info,
          LogTag.ui,
          'ui.dialog.open',
          fields: <String, Object?>{'dialog': 'log_viewer'},
        );

        final diskText = File(logFilePath).readAsStringSync();
        expect(
          diskText,
          contains('2026-11-03T22:05:14.128Z [DEBUG] [TDF      ] tdf.parse |'),
          reason: 'DEBUG level (5 chars) and TDF tag (9 chars) must be padded',
        );
        expect(
          diskText,
          contains('2026-11-03T22:05:14.128Z [INFO ] [DOMAIN   ] task.add |'),
          reason:
              'INFO level (5 chars) and DOMAIN tag (9 chars) must be padded',
        );
        expect(
          diskText,
          contains(
            '2026-11-03T22:05:14.128Z [WARN ] [SYNC     ] sync.conflict |',
          ),
          reason: 'WARN level (5 chars) and SYNC tag (9 chars) must be padded',
        );
        expect(
          diskText,
          contains('2026-11-03T22:05:14.128Z [ERROR] [STORAGE  ] webdav.get |'),
          reason: 'ERROR level and STORAGE tag must be padded',
        );
        expect(
          diskText,
          contains(
            '2026-11-03T22:05:14.128Z [INFO ] [UI       ] '
            'ui.dialog.open | dialog=log_viewer',
          ),
          reason: 'UI tag (9 chars) must match structured format',
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

      test(
        'enforces minimumLevel filtering while always allowing CRASH entries',
        () {
          AppLogger.setEnabled(
            true,
            logFilePath: logFilePath,
            minimumLevel: LogLevel.warn,
          );

          expect(AppLogger.shouldLog(LogLevel.debug), isFalse);
          expect(AppLogger.shouldLog(LogLevel.info), isFalse);
          expect(AppLogger.shouldLog(LogLevel.warn), isTrue);
          expect(AppLogger.shouldLog(LogLevel.error), isTrue);
          expect(AppLogger.shouldLog(LogLevel.crash), isTrue);

          AppLogger.debug(LogTag.domain, 'Filtered debug');
          AppLogger.info(LogTag.domain, 'Filtered info');
          AppLogger.warn(LogTag.domain, 'Retained warning');
          AppLogger.error(LogTag.domain, 'Retained error');
          AppLogger.crash(StateError('Retained crash'), StackTrace.empty);

          final text = AppLogger.fullLogText;
          expect(text, isNot(contains('Filtered debug')));
          expect(text, isNot(contains('Filtered info')));
          expect(text, contains('Retained warning'));
          expect(text, contains('Retained error'));
          expect(text, contains('Retained crash'));
        },
      );

      test('matchesFilter filters lines by LogLevel threshold and LogTag', () {
        const debugTdfLine =
            '2026-11-03T22:05:14.128Z [DEBUG] [TDF      ] tdf.parse | tasks=2';
        const warnSyncLine =
            '2026-11-03T22:05:14.128Z [WARN ] [SYNC     ] sync.conflict | id=1';

        expect(
          AppLogger.matchesFilter(debugTdfLine, minimumLevel: LogLevel.info),
          isFalse,
        );
        expect(
          AppLogger.matchesFilter(
            debugTdfLine,
            minimumLevel: LogLevel.debug,
            tag: LogTag.tdf,
          ),
          isTrue,
        );
        expect(
          AppLogger.matchesFilter(
            warnSyncLine,
            minimumLevel: LogLevel.info,
            tag: LogTag.sync,
          ),
          isTrue,
        );
        expect(
          AppLogger.matchesFilter(
            warnSyncLine,
            minimumLevel: LogLevel.info,
            tag: LogTag.tdf,
          ),
          isFalse,
        );
      });

      test('trims oldest 20% of regular entries when maxLines is exceeded while preserving @meta header and crash blocks', () {
        File(logFilePath).writeAsStringSync(
          '2026-11-03T21:00:00.000Z [CRASH] [LIFECYCLE] '
          'crash.unhandled | error="Previous fatal error"\n'
          '2026-11-03T21:00:00.000Z [CRASH] [LIFECYCLE] '
          'crash.stack | trace="#0 main (main.dart:10)"\n',
          flush: true,
        );

        AppLogger.setEnabled(
          true,
          logFilePath: logFilePath,
          minimumLevel: LogLevel.debug,
          maxLines: 25,
        );

        for (var i = 1; i <= 30; i++) {
          AppLogger.info(LogTag.domain, 'Regular log line $i');
        }

        final currentLines = AppLogger.lines;
        expect(
          currentLines.length <= 25,
          isTrue,
          reason: 'Line buffer must stay within maxLines after 20% pruning',
        );
        expect(
          currentLines.first,
          equals('=== TIERTASK DIAGNOSTIC LOG ==='),
          reason: '@meta header block must remain at top of file after pruning',
        );
        expect(
          currentLines.any((line) => line.contains('Previous fatal error')),
          isTrue,
          reason:
              'Unacknowledged [CRASH] lines must be preserved during pruning',
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
          contains('Regular log line 30'),
          reason: 'Newest log entries must be retained after pruning',
        );
      });
    },
  );

  group('Lifecycle State Machine, Session Preservation & Crash Recovery', () {
    test('sleep states and clean detached exit preserve log file and record session.exit without triggering false recovery on next start', () {
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
          reason: 'Transition to ${state.name} must preserve log file',
        );
        expect(
          fileContent,
          contains('lifecycle.state | state=${state.name}'),
          reason: 'Transition to ${state.name} must record lifecycle.state',
        );
      }

      AppLogger.handleAppLifecycleState(AppLifecycleState.detached);
      final afterDetached = File(logFilePath).readAsStringSync();
      expect(
        afterDetached,
        isNotEmpty,
        reason: 'Clean exit (detached) must preserve session log on disk',
      );
      expect(
        afterDetached,
        contains('session.exit | state=detached crashed=false'),
        reason: 'Clean exit must record session.exit with crashed=false',
      );

      final nextBootUtc = DateTime.utc(2026, 11, 3, 22, 15, 0, 0);
      AppLogger.resetForTesting(
        clock: () => nextBootUtc,
        sink: const LocalFileLogSink(),
      );
      AppLogger.setEnabled(true, logFilePath: logFilePath);
      final nextSessionContent = File(logFilePath).readAsStringSync();
      expect(
        nextSessionContent,
        isNot(contains('RECOVERED UNCLEAN EXIT / CRASH LOG ABOVE')),
        reason: 'Clean detached exit must NOT trigger unclean exit recovery banner on next start',
      );
      expect(
        nextSessionContent,
        contains('Task added before sleep'),
        reason: 'Previous clean session entries on the same day must be kept',
      );
    });

    test('AppLogger.crash flushes stack trace and next startup after unclean exit inserts recovery banner and session.recover event', () {
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
        contains('[CRASH] [LIFECYCLE] crash.unhandled |'),
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
      expect(
        crashedFileContent,
        contains('session.exit | state=detached crashed=true'),
        reason: 'Detached after crash must record crashed=true',
      );

      final nextBootUtc = DateTime.utc(2026, 11, 3, 22, 10, 0, 0);
      AppLogger.resetForTesting(
        clock: () => nextBootUtc,
        sink: const LocalFileLogSink(),
      );
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
          '=== RECOVERED UNCLEAN EXIT / CRASH LOG ABOVE | '
          'NEW SESSION START 2026-11-03T22:10:00.000Z ===',
        ),
        reason: 'Startup after unclean exit must append the recovery banner',
      );
      expect(
        recoveredContent,
        contains('session.recover | reason=unclean_exit_or_crash'),
        reason: 'Startup after unclean exit must log session.recover event',
      );
      expect(
        recoveredContent,
        contains('First entry in new session'),
        reason: 'New session entries must be appended below recovery banner',
      );
    });
  });

  group('Core Domain, TDF, Evaluator & Sync Subsystem Instrumentation', () {
    test('instruments TdfService, TaskBoard mutations, deduplicated DEBUG evaluator traces, and TaskBoardSync.merge', () {
      AppLogger.setEnabled(
        true,
        logFilePath: logFilePath,
        minimumLevel: LogLevel.debug,
      );

      const tdfService = TdfService();
      expect(
        () => tdfService.parse('invalid header'),
        throwsA(isA<TdfException>()),
        reason: 'Malformed TDF must throw TdfException',
      );
      expect(
        AppLogger.fullLogText,
        contains('[ERROR] [TDF      ] tdf.error |'),
        reason:
            'TdfService.parse failure must log [ERROR] [TDF      ] tdf.error',
      );

      const locationCondition = LocationTaskCondition(
        locationIds: <String>['munichOkD2'],
      );
      var board = TaskBoard.empty()
          .addLocation(
            'Munich',
            latitude: 48.137154,
            longitude: 11.576124,
            radius: 200,
            currentDate: fixedUtc,
            id: 'munichOkD2',
          )
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
            'Location-blocked task',
            targetTier: TaskTier.ready,
            conditions: const <TaskCondition>[locationCondition],
            currentDate: fixedUtc,
          );

      final labelId = board.labels.first.id;
      final firstTaskId = board.allTasks.first.id;
      final secondTaskId = board.allTasks.last.id;

      board = board
          .updateLabel(labelId, name: 'Engineering', currentDate: fixedUtc)
          .updateTask(
            secondTaskId,
            title: 'Location-blocked task updated',
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
        evaluationTime: fixedUtc,
        currentLatitude: 52.520008,
        currentLongitude: 13.404954,
      );
      final countAfterFirstEval = AppLogger.lines
          .where((line) => line.contains('eval.summary |'))
          .length;
      parsed.evaluateForContext(
        evaluationTime: fixedUtc,
        currentLatitude: 52.520008,
        currentLongitude: 13.404954,
      );
      final countAfterDuplicateEval = AppLogger.lines
          .where((line) => line.contains('eval.summary |'))
          .length;
      expect(
        countAfterDuplicateEval,
        equals(countAfterFirstEval),
        reason: 'Identical consecutive evaluateForContext calls must deduplicate eval.summary logs',
      );

      final modifiedPrimary = board.updateTask(
        secondTaskId,
        title: 'Primary conflict title',
        currentDate: fixedUtc.add(const Duration(seconds: 10)),
      );
      final modifiedSecondary = parsed.updateTask(
        secondTaskId,
        title: 'Secondary conflict title',
        currentDate: fixedUtc.add(const Duration(seconds: 5)),
      );

      TaskBoardSync.merge(
        primary: modifiedPrimary,
        secondary: modifiedSecondary,
        evaluationTime: fixedUtc.add(const Duration(seconds: 15)),
      );

      final logOutput = AppLogger.fullLogText;
      expect(
        logOutput,
        contains('[INFO ] [TDF      ] tdf.serialize |'),
        reason: 'TdfService.serialize must emit structured tdf.serialize',
      );
      expect(
        logOutput,
        contains('[INFO ] [TDF      ] tdf.parse |'),
        reason: 'TdfService.parse must emit structured tdf.parse',
      );
      expect(
        logOutput,
        contains('[INFO ] [DOMAIN   ] task.add |'),
        reason: 'TaskBoard mutations must emit structured task.add',
      );
      expect(
        logOutput,
        contains('focus='),
        reason: 'Domain logs must include lowercase 6-tier counts',
      );
      expect(
        logOutput,
        contains('[DEBUG] [DOMAIN   ] eval.blocked |'),
        reason: 'DEBUG level must emit eval.blocked for location-blocked task',
      );
      expect(
        logOutput,
        isNot(contains('48.137154')),
        reason: 'Raw GPS latitude must never be written to diagnostic logs',
      );
      expect(
        logOutput,
        isNot(contains('Secret Street 42')),
        reason: 'Reverse-geocoded street names must never be written to diagnostic logs',
      );
      expect(
        logOutput,
        contains('[INFO ] [SYNC     ] sync.merge |'),
        reason: 'TaskBoardSync.merge must emit structured sync.merge',
      );
      expect(
        logOutput,
        contains('[DEBUG] [SYNC     ] sync.reconcile.task |'),
        reason: 'DEBUG level must emit per-task LWW reconciliation trace',
      );
    });
  });
}
