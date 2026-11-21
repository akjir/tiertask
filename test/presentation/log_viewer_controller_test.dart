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
import 'package:tiertask/presentation/log_viewer_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/services/app_logger.dart';

class _TestWebDavConfigNotifier extends WebDavConfigNotifier {
  _TestWebDavConfigNotifier({required this.initialConfig});

  final WebDavConfig initialConfig;
  Object? syncError;
  int syncCalls = 0;

  @override
  Future<WebDavConfig> build() async => initialConfig;

  @override
  Future<void> syncLogToWebDavNow() async {
    syncCalls++;
    if (syncError case final error?) {
      throw error;
    }
  }

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

  group('DiagnosticLogLevel and DiagnosticLogTag mappings', () {
    test('round-trip every LogLevel and LogTag exhaustively', () {
      for (final level in LogLevel.values) {
        final mapped = DiagnosticLogLevel.fromLogLevel(level);
        expect(
          mapped.toLogLevel(),
          equals(level),
          reason: 'Round-trip failed for $level',
        );
        expect(mapped.label, equals(level.label));
      }
      expect(
        DiagnosticLogLevel.configurableLevels,
        equals(const <DiagnosticLogLevel>[
          DiagnosticLogLevel.debug,
          DiagnosticLogLevel.info,
          DiagnosticLogLevel.warn,
          DiagnosticLogLevel.error,
        ]),
      );

      for (final tag in LogTag.values) {
        final mapped = DiagnosticLogTag.fromLogTag(tag);
        expect(
          mapped.toLogTag(),
          equals(tag),
          reason: 'Round-trip failed for $tag',
        );
        expect(mapped.label, equals(tag.label));
      }
    });
  });

  group('LogViewerController', () {
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
      final sub = container.listen(logViewerControllerProvider, (_, _) {});
      addTearDown(sub.close);

      final initial = container.read(logViewerControllerProvider);
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
      final updated = container.read(logViewerControllerProvider);
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

      final configNotifier = _TestWebDavConfigNotifier(
        initialConfig: const WebDavConfig(logStorageMode: StorageMode.local),
      );
      final container = ProviderContainer(
        overrides: [webDavConfigProvider.overrideWith(() => configNotifier)],
      );
      addTearDown(container.dispose);

      await container.read(webDavConfigProvider.future);
      final sub = container.listen(logViewerControllerProvider, (_, _) {});
      addTearDown(sub.close);

      final controller = container.read(logViewerControllerProvider.notifier);
      controller
        ..setMinimumLevel(DiagnosticLogLevel.warn)
        ..setSelectedTag(DiagnosticLogTag.sync);

      final filtered = container.read(logViewerControllerProvider);
      expect(filtered.canSyncWebDav, isFalse);
      expect(filtered.minimumLevel, equals(DiagnosticLogLevel.warn));
      expect(filtered.selectedTag, equals(DiagnosticLogTag.sync));
      expect(filtered.filteredLines.length, equals(2));
      expect(controller.readFullLogText(), contains('ui debug'));

      configNotifier.emitConfig(
        const WebDavConfig(
          serverUrl: 'https://cloud.example.com/dav/',
          username: 'user',
          password: 'secret',
          logStorageMode: StorageMode.webdav,
        ),
      );

      final afterConfigChange = container.read(logViewerControllerProvider);
      expect(afterConfigChange.canSyncWebDav, isTrue);
      expect(afterConfigChange.minimumLevel, equals(DiagnosticLogLevel.warn));
      expect(afterConfigChange.selectedTag, equals(DiagnosticLogTag.sync));
      expect(afterConfigChange.filteredLines.length, equals(2));

      controller.clearLog();
      final afterClear = container.read(logViewerControllerProvider);
      expect(afterClear.hasEntries, isFalse);
      expect(afterClear.totalEntries, equals(0));
      expect(afterClear.filteredLines, isEmpty);
    });

    test(
      'maps WebDAV log sync success and failure into LogSyncResult',
      () async {
        final configNotifier = _TestWebDavConfigNotifier(
          initialConfig: const WebDavConfig(
            serverUrl: 'https://cloud.example.com/dav/',
            username: 'user',
            password: 'secret',
            logStorageMode: StorageMode.webdav,
          ),
        );
        final container = ProviderContainer(
          overrides: [webDavConfigProvider.overrideWith(() => configNotifier)],
        );
        addTearDown(container.dispose);
        await container.read(webDavConfigProvider.future);

        final controller = container.read(logViewerControllerProvider.notifier);
        expect(await controller.syncLogToWebDav(), isA<LogSyncSucceeded>());
        expect(configNotifier.syncCalls, equals(1));

        configNotifier.syncError = StateError('WebDAV offline');
        final failure = await controller.syncLogToWebDav();
        expect(failure, isA<LogSyncFailed>());
        expect((failure as LogSyncFailed).message, contains('WebDAV offline'));
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

      final sub = container.listen(activeLogFileNameProvider, (_, _) {});
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

      sub.close();
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

      final nameSub = container.listen(activeLogFileNameProvider, (_, _) {});
      final viewerSub = container.listen(
        logViewerControllerProvider,
        (_, _) {},
      );
      addTearDown(nameSub.close);
      addTearDown(viewerSub.close);

      // Must not throw Riverpod re-entrancy assertion during provider build.
      expect(container.read(loggingProvider), equals(1));
      await Future<void>.microtask(() {});
      expect(
        container.read(activeLogFileNameProvider),
        equals('tiertask_2026-11-21_linux_reentrant.log'),
      );
      expect(
        container
            .read(logViewerControllerProvider)
            .filteredLines
            .any((line) => line.text.contains('logged inside provider build')),
        isTrue,
      );
    });
  });
}
