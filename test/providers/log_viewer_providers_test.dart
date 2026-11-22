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
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/log_viewer_providers.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';

class _SpyWebDavRepository extends WebDavRepository {
  _SpyWebDavRepository({required super.config});

  Object? syncError;
  int syncCalls = 0;

  @override
  Future<void> saveLog(String logFileName, [String? logContent]) async {
    syncCalls++;
    if (syncError case final error?) {
      throw error;
    }
  }
}

class _TestWebDavConfigNotifier extends WebDavConfigNotifier {
  _TestWebDavConfigNotifier({required this.initialConfig});

  final WebDavConfig initialConfig;

  @override
  Future<WebDavConfig> build() async => initialConfig;

  void emitConfig(WebDavConfig next) {
    state = AsyncData<WebDavConfig>(next);
  }
}

void main() {
  setUp(() {
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 12));
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  group('Diagnostic log models and constants', () {
    test('configurableDiagnosticLogLevels lists all configurable LogLevel values in ascending order', () {
      expect(
        configurableDiagnosticLogLevels,
        equals(const <LogLevel>[
          LogLevel.debug,
          LogLevel.info,
          LogLevel.warn,
          LogLevel.error,
        ]),
      );
      expect(
        configurableDiagnosticLogLevels,
        equals(LogLevel.configurableLevels),
      );
      expect(configurableDiagnosticLogLevels, isNot(contains(LogLevel.crash)));
    });

    test('DiagnosticLogLine, DiagnosticLogSnapshot, and LogSyncResult implement value equality and immutability', () {
      const lineA = DiagnosticLogLine(
        text: '2026-11-21T12:00:00.000Z [WARN ] [SYNC     ] warn',
        severity: DiagnosticLogSeverity.warn,
      );
      const lineB = DiagnosticLogLine(
        text: '2026-11-21T12:00:00.000Z [WARN ] [SYNC     ] warn',
        severity: DiagnosticLogSeverity.warn,
      );
      const lineC = DiagnosticLogLine(
        text: '2026-11-21T12:00:00.000Z [ERROR] [SYNC     ] error',
        severity: DiagnosticLogSeverity.error,
      );
      expect(lineA, equals(lineB));
      expect(lineA.hashCode, equals(lineB.hashCode));
      expect(lineA, isNot(equals(lineC)));

      final mutableLines = <DiagnosticLogLine>[lineA];
      final snapshotA = DiagnosticLogSnapshot(
        canSyncWebDav: true,
        errorCount: 0,
        filteredLines: mutableLines,
        hasEntries: true,
        headerSummary: 'header',
        minimumLevel: LogLevel.info,
        selectedTag: LogTag.sync,
        totalEntries: 1,
        warningCount: 1,
      );
      final snapshotB = DiagnosticLogSnapshot(
        canSyncWebDav: true,
        errorCount: 0,
        filteredLines: const <DiagnosticLogLine>[lineB],
        hasEntries: true,
        headerSummary: 'header',
        minimumLevel: LogLevel.info,
        selectedTag: LogTag.sync,
        totalEntries: 1,
        warningCount: 1,
      );
      mutableLines.add(lineC);
      expect(snapshotA.filteredLines.length, equals(1));
      expect(() => snapshotA.filteredLines.add(lineC), throwsUnsupportedError);
      expect(snapshotA, equals(snapshotB));
      expect(snapshotA.hashCode, equals(snapshotB.hashCode));

      const failedA = LogSyncFailed('offline');
      const failedB = LogSyncFailed('offline');
      const failedC = LogSyncFailed('timeout');
      expect(failedA, equals(failedB));
      expect(failedA.hashCode, equals(failedB.hashCode));
      expect(failedA, isNot(equals(failedC)));
      expect(const LogSyncSucceeded(), isA<LogSyncResult>());
    });
  });

  group('LogViewerNotifier', () {
    test('computes header summary, stats, severities, and live updates on AppLogger.revision', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
        metadata: const LogMetadata(
          appVersion: '0.4.0+4',
          platform: 'linux',
          workspaceId: 'work',
        ),
      );
      AppLogger.debug(LogTag.domain, 'debug event');
      AppLogger.warn(LogTag.sync, 'sync warning');
      AppLogger.error(LogTag.storage, 'storage failure');
      AppLogger.crash(StateError('boom'), StackTrace.empty);

      final container = ProviderContainer(
        overrides: [
          webDavConfigProvider.overrideWith(
            () => _TestWebDavConfigNotifier(
              initialConfig: const WebDavConfig(
                serverUrl: 'https://cloud.example.com/dav/',
                username: 'user',
                password: 'secret',
                logStorageMode: StorageMode.both,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(webDavConfigProvider.future);
      final subscription = container.listen(logViewerProvider, (_, _) {});
      addTearDown(subscription.close);

      final initial = container.read(logViewerProvider);
      expect(initial.canSyncWebDav, isTrue);
      expect(initial.hasEntries, isTrue);
      expect(
        initial.headerSummary,
        equals(
          'tiertask_2026-11-21_linux_work.log • v0.4.0+4 (linux) • work • DEBUG',
        ),
      );
      expect(initial.totalEntries, equals(5));
      expect(initial.warningCount, equals(1));
      expect(initial.errorCount, equals(2));
      expect(
        initial.filteredLines.map((line) => line.severity).toSet(),
        containsAll(<DiagnosticLogSeverity>[
          DiagnosticLogSeverity.normal,
          DiagnosticLogSeverity.warn,
          DiagnosticLogSeverity.error,
          DiagnosticLogSeverity.crash,
        ]),
      );

      AppLogger.info(LogTag.ui, 'RECOVERED UNCLEAN EXIT');
      await Future<void>.microtask(() {});
      final updated = container.read(logViewerProvider);
      expect(updated.totalEntries, equals(6));
      expect(
        updated.filteredLines.last.severity,
        equals(DiagnosticLogSeverity.crash),
      );
    });

    test('preserves filters across webDavConfigProvider updates and supports clear/fullText', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
      );
      AppLogger.debug(LogTag.ui, 'ui debug');
      AppLogger.warn(LogTag.sync, 'sync warn');
      AppLogger.error(LogTag.sync, 'sync error');

      final configurationNotifier = _TestWebDavConfigNotifier(
        initialConfig: const WebDavConfig(logStorageMode: StorageMode.local),
      );
      final container = ProviderContainer(
        overrides: [
          webDavConfigProvider.overrideWith(() => configurationNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container.read(webDavConfigProvider.future);
      final subscription = container.listen(logViewerProvider, (_, _) {});
      addTearDown(subscription.close);

      final notifier = container.read(logViewerProvider.notifier);
      notifier
        ..setMinimumLevel(LogLevel.warn)
        ..setMinimumLevel(LogLevel.warn)
        ..setSelectedTag(LogTag.sync)
        ..setSelectedTag(LogTag.sync);

      final filtered = container.read(logViewerProvider);
      expect(filtered.canSyncWebDav, isFalse);
      expect(filtered.minimumLevel, equals(LogLevel.warn));
      expect(filtered.selectedTag, equals(LogTag.sync));
      expect(filtered.filteredLines.length, equals(2));
      expect(notifier.readFullLogText(), contains('ui debug'));

      configurationNotifier.emitConfig(
        const WebDavConfig(logStorageMode: StorageMode.webdav),
      );
      expect(container.read(logViewerProvider).canSyncWebDav, isFalse);

      configurationNotifier.emitConfig(
        const WebDavConfig(
          serverUrl: 'https://cloud.example.com/dav/',
          username: 'user',
          password: 'secret',
          logStorageMode: StorageMode.webdav,
        ),
      );

      final afterConfigChange = container.read(logViewerProvider);
      expect(afterConfigChange.canSyncWebDav, isTrue);
      expect(afterConfigChange.minimumLevel, equals(LogLevel.warn));
      expect(afterConfigChange.selectedTag, equals(LogTag.sync));
      expect(afterConfigChange.filteredLines.length, equals(2));

      notifier
        ..setSelectedTag(null)
        ..setMinimumLevel(LogLevel.debug);
      expect(
        container.read(logViewerProvider).filteredLines.length,
        greaterThan(2),
      );

      notifier.clearLog();
      final afterClear = container.read(logViewerProvider);
      expect(afterClear.hasEntries, isFalse);
      expect(afterClear.totalEntries, equals(0));
      expect(afterClear.filteredLines, isEmpty);
    });

    test(
      'maps WebDAV log sync success and failure into LogSyncResult',
      () async {
        const config = WebDavConfig(
          serverUrl: 'https://cloud.example.com/dav/',
          username: 'user',
          password: 'secret',
          diagnosticsEnabled: true,
          logStorageMode: StorageMode.webdav,
        );
        final configurationNotifier = _TestWebDavConfigNotifier(
          initialConfig: config,
        );
        final spyRepository = _SpyWebDavRepository(config: config);
        final container = ProviderContainer(
          overrides: [
            webDavConfigProvider.overrideWith(() => configurationNotifier),
            webDavRepositoryProvider.overrideWithValue(spyRepository),
          ],
        );
        addTearDown(container.dispose);
        await container.read(webDavConfigProvider.future);

        final notifier = container.read(logViewerProvider.notifier);
        expect(await notifier.syncLogToWebDav(), isA<LogSyncSucceeded>());
        expect(spyRepository.syncCalls, equals(1));

        AppLogger.setSecretToRedact('super-secret-webdav-pw');
        spyRepository.syncError = StateError(
          'WebDAV offline with super-secret-webdav-pw',
        );
        final failure = await notifier.syncLogToWebDav();
        switch (failure) {
          case LogSyncFailed(:final message):
            expect(message, contains('WebDAV offline'));
            expect(
              message,
              isNot(contains('super-secret-webdav-pw')),
              reason: 'LogSyncFailed must redact registered secrets',
            );
          case LogSyncSucceeded():
            fail('Expected LogSyncFailed when WebDAV log sync throws');
        }
      },
    );

    test('activeLogFileNameProvider reacts to AppLogger.revision and cleans up on dispose', () async {
      AppLogger.setEnabled(
        true,
        persistToDisk: false,
        metadata: const LogMetadata(platform: 'linux', workspaceId: 'tasks'),
      );
      final container = ProviderContainer(
        overrides: [diagnosticsEnabledProvider.overrideWithValue(true)],
      );

      final subscription = container.listen(
        activeLogFileNameProvider,
        (_, _) {},
      );
      expect(
        container.read(activeLogFileNameProvider),
        equals('tiertask_2026-11-21_linux_tasks.log'),
      );

      AppLogger.setEnabled(
        true,
        persistToDisk: false,
        logFilePath: '/tmp/tiertask_2026-11-21_linux_work.log',
      );
      await Future<void>.microtask(() {});
      expect(
        container.read(activeLogFileNameProvider),
        equals('tiertask_2026-11-21_linux_work.log'),
      );

      subscription.close();
      container.dispose();
      // Subsequent logger writes must not throw after provider disposal.
      AppLogger.info(LogTag.ui, 'post-dispose write');
      await Future<void>.microtask(() {});
    });

    test('defers AppLogger.revision updates safely when another provider logs during build', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
        metadata: const LogMetadata(platform: 'linux', workspaceId: 'tasks'),
      );
      final loggingProvider = Provider<int>((ref) {
        AppLogger.setEnabled(
          true,
          persistToDisk: false,
          logFilePath: '/tmp/tiertask_2026-11-21_linux_reentrant.log',
        );
        AppLogger.info(LogTag.domain, 'logged inside provider build');
        return 1;
      });
      final container = ProviderContainer(
        overrides: [diagnosticsEnabledProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final nameSubscription = container.listen(
        activeLogFileNameProvider,
        (_, _) {},
      );
      final viewerSubscription = container.listen(logViewerProvider, (_, _) {});
      addTearDown(nameSubscription.close);
      addTearDown(viewerSubscription.close);

      // Must not throw Riverpod re-entrancy assertion during provider build.
      expect(container.read(loggingProvider), equals(1));
      await Future<void>.microtask(() {});
      expect(
        container.read(activeLogFileNameProvider),
        equals('tiertask_2026-11-21_linux_reentrant.log'),
      );
      expect(
        container
            .read(logViewerProvider)
            .filteredLines
            .any((line) => line.text.contains('logged inside provider build')),
        isTrue,
      );
    });
  });
}
