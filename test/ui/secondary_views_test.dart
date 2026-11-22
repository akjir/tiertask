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
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/board_providers.dart';
import 'package:tiertask/providers/floating_notice_providers.dart';
import 'package:tiertask/providers/log_viewer_providers.dart';
import 'package:tiertask/providers/shell_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/ui/layout/ui_page_header.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';
import 'package:tiertask/ui/primitives/ui_field.dart';
import 'package:tiertask/ui/primitives/ui_pill.dart';
import 'package:tiertask/ui/tokens/ui_theme_tokens.dart';
import 'package:tiertask/ui/tokens/ui_typography_tokens.dart';
import 'package:tiertask/ui/views/log_viewer_view.dart';
import 'package:tiertask/ui/views/raw_tdf_view.dart';
import 'package:tiertask/ui/views/resolution_views.dart';

import 'test_helpers.dart';

class _MetaPreservingLogViewerNotifier extends LogViewerNotifier {
  _MetaPreservingLogViewerNotifier({required this.preservedMeta});

  final List<DiagnosticLogLine> preservedMeta;

  @override
  DiagnosticLogSnapshot build() {
    return DiagnosticLogSnapshot(
      canSyncWebDav: false,
      errorCount: 0,
      filteredLines: <DiagnosticLogLine>[
        ...preservedMeta,
        const DiagnosticLogLine(
          text: '2026-11-21T12:00:00Z [INFO ] [UI       ] transient entry',
          severity: DiagnosticLogSeverity.normal,
        ),
      ],
      hasEntries: true,
      headerSummary: 'tiertask_2026-11-21_linux_work.log • v0.4.0 (linux)',
      minimumLevel: LogLevel.debug,
      selectedTags: LogTag.values,
      totalEntries: 1,
      warningCount: 0,
    );
  }

  @override
  void clearLog() {
    state = DiagnosticLogSnapshot(
      canSyncWebDav: false,
      errorCount: 0,
      filteredLines: preservedMeta,
      hasEntries: preservedMeta.isNotEmpty,
      headerSummary: state.headerSummary,
      minimumLevel: state.minimumLevel,
      selectedTags: state.selectedTags,
      totalEntries: 0,
      warningCount: 0,
    );
  }
}

class _SpyResolutionTaskNotifier extends FakeTaskNotifier {
  _SpyResolutionTaskNotifier(
    super.initialBoard, {
    this.onResolveDeletionConflicts,
    this.onResolveRecovery,
  });

  final Future<TaskBoard> Function({
    required Map<String, TdfDeletionResolution> taskResolutions,
    required Map<String, TdfDeletionResolution> labelResolutions,
    required Map<String, TdfDeletionResolution> locationResolutions,
  })?
  onResolveDeletionConflicts;

  final Future<TaskBoard> Function({
    required Map<String, TdfRecoveryResolution> taskResolutions,
    required Map<String, TdfRecoveryResolution> labelResolutions,
    required Map<String, TdfRecoveryResolution> locationResolutions,
  })?
  onResolveRecovery;

  @override
  Future<TaskBoard> resolveDeletionConflicts({
    Map<String, TdfDeletionResolution> taskResolutions = const {},
    Map<String, TdfDeletionResolution> labelResolutions = const {},
    Map<String, TdfDeletionResolution> locationResolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundTaskDecisions = const {},
    Map<String, TdfBoundDeletionDecision> boundLabelDecisions = const {},
    Map<String, TdfBoundDeletionDecision> boundLocationDecisions = const {},
  }) async {
    final handler = onResolveDeletionConflicts;
    if (handler != null) {
      return handler(
        taskResolutions: taskResolutions,
        labelResolutions: labelResolutions,
        locationResolutions: locationResolutions,
      );
    }
    return initialBoard;
  }

  @override
  Future<TaskBoard> resolveRecovery({
    Map<String, TdfRecoveryResolution> taskResolutions = const {},
    Map<String, TdfRecoveryResolution> labelResolutions = const {},
    Map<String, TdfRecoveryResolution> locationResolutions = const {},
  }) async {
    final handler = onResolveRecovery;
    if (handler != null) {
      return handler(
        taskResolutions: taskResolutions,
        labelResolutions: labelResolutions,
        locationResolutions: locationResolutions,
      );
    }
    return initialBoard;
  }
}

class _SpyWebDavRepository extends WebDavRepository {
  _SpyWebDavRepository({required super.config, this.onSaveLog});

  final Future<void> Function(String logFileName)? onSaveLog;
  final List<String> uploadedFileNames = <String>[];

  @override
  Future<void> saveLog(String logFileName, [String? logContent]) async {
    uploadedFileNames.add(logFileName);
    final handler = onSaveLog;
    if (handler != null) {
      await handler(logFileName);
    }
  }
}

void main() {
  String? lastCopiedText;

  setUp(() {
    lastCopiedText = null;
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 12));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments;
            if (arguments is Map<Object?, Object?>) {
              final text = arguments['text'];
              if (text is String) {
                lastCopiedText = text;
              }
            }
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    AppLogger.resetForTesting();
  });

  group('LogViewerView', () {
    testWidgets(
      'renders metadata summary, severity-styled lines, level and subsystem filters, Copy All, and Clear',
      (tester) async {
        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LogViewerView()),
          config: const WebDavConfig(),
        );

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
        AppLogger.debug(LogTag.domain, 'domain debug trace');
        AppLogger.warn(LogTag.tdf, 'tdf warning line');
        AppLogger.warn(LogTag.sync, 'sync warning line');
        AppLogger.error(LogTag.storage, 'storage error line');
        AppLogger.crash(StateError('fatal crash line'), StackTrace.empty);
        await tester.pumpAndSettle();

        final tokens = UiThemePresets.calm.light;
        final colors = tokens.colors;

        expect(
          find.byKey(const ValueKey<String>('log_viewer_metadata_card')),
          findsOneWidget,
        );
        expect(
          find.textContaining('tiertask_2026-11-21_linux_work.log'),
          findsOneWidget,
        );
        expect(
          find.text('Entries: 6 | Warnings: 2 | Errors: 2'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('log_viewer_upload_button')),
          findsNothing,
          reason:
              'Upload Log must stay hidden when WebDAV log sync is unavailable',
        );

        final metaFinder = find.textContaining('@meta format=1');
        expect(metaFinder, findsOneWidget);
        final metaText = tester.widget<Text>(metaFinder);
        expect(metaText.style?.color, equals(colors.muted));

        final debugFinder = find.textContaining('domain debug trace');
        expect(debugFinder, findsOneWidget);
        final debugText = tester.widget<Text>(debugFinder);
        expect(debugText.style?.color, equals(colors.ink));

        final warnFinder = find.textContaining('sync warning line');
        expect(warnFinder, findsOneWidget);
        final warnText = tester.widget<Text>(warnFinder);
        expect(warnText.style?.color, equals(colors.warning));
        final warnContainer = tester.widget<Container>(
          find.ancestor(of: warnFinder, matching: find.byType(Container)).first,
        );
        final warnDecoration = warnContainer.decoration as BoxDecoration?;
        expect(warnDecoration?.color, equals(colors.warningBg));

        final errorFinder = find.textContaining('storage error line');
        expect(errorFinder, findsOneWidget);
        final errorText = tester.widget<Text>(errorFinder);
        expect(errorText.style?.color, equals(colors.danger));
        final errorContainer = tester.widget<Container>(
          find
              .ancestor(of: errorFinder, matching: find.byType(Container))
              .first,
        );
        final errorDecoration = errorContainer.decoration as BoxDecoration?;
        expect(errorDecoration?.color, equals(colors.dangerBg));

        final crashFinder = find.textContaining('fatal crash line');
        expect(crashFinder, findsOneWidget);
        final crashText = tester.widget<Text>(crashFinder);
        expect(crashText.style?.color, equals(colors.danger));

        // All six subsystem toggle pills start selected, count shows 6 / 6, All is disabled, None is enabled.
        expect(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_filter')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_count')),
          findsOneWidget,
        );
        expect(find.text('6 / 6'), findsOneWidget);
        for (final tag in LogTag.values) {
          final pillFinder = find.byKey(
            ValueKey<String>('log_viewer_subsystem_${tag.name}'),
          );
          expect(
            pillFinder,
            findsOneWidget,
            reason: 'Subsystem toggle pill for ${tag.name} must render',
          );
          expect(
            tester.widget<UiPill>(pillFinder).isSelected,
            isTrue,
            reason: 'Subsystem ${tag.name} must start selected by default',
          );
        }
        final allButtonWidget = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_all')),
        );
        final noneButtonWidget = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_none')),
        );
        expect(
          allButtonWidget.variant,
          equals(UiButtonVariant.secondary),
          reason: 'All bulk action must use flat bordered secondary styling',
        );
        expect(
          noneButtonWidget.variant,
          equals(UiButtonVariant.secondary),
          reason: 'None bulk action must use flat bordered secondary styling',
        );
        expect(
          allButtonWidget.onPressed,
          isNull,
          reason: 'All button must be disabled when all subsystems are already selected',
        );
        expect(
          noneButtonWidget.onPressed,
          isNotNull,
          reason: 'None button must be enabled when subsystems are selected',
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_copy_button')),
        );
        await tester.pumpAndSettle();
        expect(lastCopiedText, contains('domain debug trace'));
        expect(lastCopiedText, contains('storage error line'));
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Diagnostic log copied to clipboard.'),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_level_filter')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('WARN').last);
        await tester.pumpAndSettle();

        expect(find.textContaining('domain debug trace'), findsNothing);
        expect(find.textContaining('tdf warning line'), findsOneWidget);
        expect(find.textContaining('sync warning line'), findsOneWidget);
        expect(find.textContaining('storage error line'), findsOneWidget);

        // Deselecting SYNC hides only SYNC entries while keeping other subsystems active.
        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_sync')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<UiPill>(
                find.byKey(const ValueKey<String>('log_viewer_subsystem_sync')),
              )
              .isSelected,
          isFalse,
        );
        expect(find.text('5 / 6'), findsOneWidget);
        expect(find.textContaining('sync warning line'), findsNothing);
        expect(find.textContaining('tdf warning line'), findsOneWidget);
        expect(find.textContaining('storage error line'), findsOneWidget);

        // Clicking None deselects every subsystem and displays the empty-filter hint.
        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_none')),
        );
        await tester.pumpAndSettle();
        expect(find.text('0 / 6'), findsOneWidget);
        expect(
          find.text('No diagnostic log entries match the active filters.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<UiButton>(
                find.byKey(const ValueKey<String>('log_viewer_subsystem_none')),
              )
              .onPressed,
          isNull,
          reason:
              'None button must be disabled when zero subsystems are selected',
        );
        expect(
          tester
              .widget<UiButton>(
                find.byKey(
                  const ValueKey<String>('log_viewer_copy_filtered_button'),
                ),
              )
              .onPressed,
          isNull,
          reason: 'Copy Filtered must be disabled when active filters match zero lines',
        );
        expect(
          tester
              .widget<UiButton>(
                find.byKey(
                  const ValueKey<String>('log_viewer_scroll_top_button'),
                ),
              )
              .onPressed,
          isNull,
          reason: 'Scroll to Top must be disabled when active filters match zero lines',
        );
        expect(
          tester
              .widget<UiButton>(
                find.byKey(const ValueKey<String>('log_viewer_copy_button')),
              )
              .onPressed,
          isNotNull,
          reason: 'Copy All must remain enabled when unfiltered log entries still exist',
        );

        // Selecting both TDF and STORAGE shows and copies both subsystems together.
        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_tdf')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_storage')),
        );
        await tester.pumpAndSettle();

        expect(find.text('2 / 6'), findsOneWidget);
        expect(find.textContaining('tdf warning line'), findsOneWidget);
        expect(find.textContaining('storage error line'), findsOneWidget);
        expect(find.textContaining('sync warning line'), findsNothing);
        expect(find.textContaining('domain debug trace'), findsNothing);

        lastCopiedText = null;
        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_copy_filtered_button')),
        );
        await tester.pumpAndSettle();
        expect(lastCopiedText, contains('tdf warning line'));
        expect(lastCopiedText, contains('storage error line'));
        expect(lastCopiedText, isNot(contains('sync warning line')));
        expect(lastCopiedText, isNot(contains('domain debug trace')));
        expect(lastCopiedText, isNot(contains('@meta format=1')));
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Filtered diagnostic log copied to clipboard.'),
        );
        expect(
          container.read(floatingNoticeProvider)?.tone,
          equals(FloatingNoticeTone.success),
        );

        lastCopiedText = null;
        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_copy_button')),
        );
        await tester.pumpAndSettle();
        expect(lastCopiedText, contains('domain debug trace'));
        expect(lastCopiedText, contains('tdf warning line'));
        expect(lastCopiedText, contains('sync warning line'));
        expect(lastCopiedText, contains('storage error line'));
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Diagnostic log copied to clipboard.'),
        );

        // Clicking All restores all six subsystems.
        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_all')),
        );
        await tester.pumpAndSettle();
        expect(find.text('6 / 6'), findsOneWidget);
        expect(find.textContaining('sync warning line'), findsOneWidget);
        expect(find.textContaining('tdf warning line'), findsOneWidget);
        expect(find.textContaining('storage error line'), findsOneWidget);
        expect(
          tester
              .widget<UiButton>(
                find.byKey(const ValueKey<String>('log_viewer_subsystem_all')),
              )
              .onPressed,
          isNull,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_clear_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('No diagnostic log entries recorded yet.'),
          findsOneWidget,
        );
        expect(
          find.text('Entries: 0 | Warnings: 0 | Errors: 0'),
          findsOneWidget,
        );
        expect(
          find.textContaining('tiertask_2026-11-21_linux_work.log'),
          findsOneWidget,
          reason: 'Metadata header summary must remain preserved after Clear',
        );
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Diagnostic log cleared.'),
        );
      },
    );

    testWidgets(
      'preserves @meta lines when notifier retains header lines on Clear',
      (tester) async {
        final preservedMeta = <DiagnosticLogLine>[
          const DiagnosticLogLine(
            text: '@meta format=1 app_version=0.4.0 platform=linux',
            severity: DiagnosticLogSeverity.normal,
          ),
        ];
        final container = await pumpLeafWidget(
          tester,
          ProviderScope(
            overrides: [
              logViewerProvider.overrideWith(
                () => _MetaPreservingLogViewerNotifier(
                  preservedMeta: preservedMeta,
                ),
              ),
            ],
            child: const Scaffold(body: LogViewerView()),
          ),
        );

        expect(find.textContaining('transient entry'), findsOneWidget);
        expect(find.textContaining('@meta format=1'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_clear_button')),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('transient entry'), findsNothing);
        expect(
          find.textContaining('@meta format=1'),
          findsOneWidget,
          reason: '@meta lines retained on Clear must remain visible',
        );
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Diagnostic log cleared.'),
        );
      },
    );

    testWidgets(
      'shows Upload Log when WebDAV log sync is enabled, auto-scrolls to end, and scrolls to top on demand',
      (tester) async {
        var failUpload = false;
        Completer<void>? uploadGate;
        const webDavConfig = WebDavConfig(
          diagnosticsEnabled: true,
          logStorageMode: StorageMode.webdav,
          storageMode: StorageMode.webdav,
          serverUrl: 'https://cloud.example.com/dav/',
          username: 'alice',
          password: 'secret-password',
          logLevel: LogLevel.debug,
        );
        final spyWebDav = _SpyWebDavRepository(
          config: webDavConfig,
          onSaveLog: (_) async {
            if (uploadGate case final gate?) {
              await gate.future;
            }
            if (failUpload) {
              throw const WebDavException(
                'Upload rejected (503).',
                statusCode: 503,
              );
            }
          },
        );

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LogViewerView()),
          config: webDavConfig,
          webDavRepository: spyWebDav,
        );

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
        for (var i = 0; i < 60; i++) {
          AppLogger.info(
            LogTag.domain,
            'scrollable log entry #$i ${'x' * 140}',
          );
        }
        await tester.pumpAndSettle();

        final uploadFinder = find.byKey(
          const ValueKey<String>('log_viewer_upload_button'),
        );
        expect(uploadFinder, findsOneWidget);

        uploadGate = Completer<void>();
        await tester.tap(uploadFinder);
        await tester.pump();
        final loadingButton = tester.widget<UiButton>(uploadFinder);
        expect(loadingButton.isLoading, isTrue);
        expect(loadingButton.onPressed, isNull);

        uploadGate.complete();
        uploadGate = null;
        await tester.pumpAndSettle();
        expect(spyWebDav.uploadedFileNames.length, equals(1));
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Diagnostic log synced to WebDAV.'),
        );
        expect(
          container.read(floatingNoticeProvider)?.tone,
          equals(FloatingNoticeTone.success),
        );

        failUpload = true;
        await tester.tap(uploadFinder);
        await tester.pumpAndSettle();
        expect(
          container.read(floatingNoticeProvider)?.message,
          contains('Upload rejected (503).'),
        );
        expect(
          container.read(floatingNoticeProvider)?.tone,
          equals(FloatingNoticeTone.danger),
        );

        final listView = tester.widget<ListView>(find.byType(ListView));
        final verticalController = listView.controller;
        expect(verticalController, isNotNull);
        final initialMaxExtent =
            verticalController?.position.maxScrollExtent ?? 0.0;
        expect(
          initialMaxExtent,
          greaterThan(0.0),
          reason: '60 log entries must overflow vertically to test auto-scroll and Scroll to Top',
        );
        expect(
          verticalController?.offset,
          equals(initialMaxExtent),
          reason: 'Log console must automatically show the latest entries at the end',
        );
        expect(find.textContaining('scrollable log entry #59'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_scroll_top_button')),
        );
        await tester.pumpAndSettle();
        expect(
          verticalController?.offset,
          equals(0.0),
          reason: 'Scroll to Top must jump immediately to offset 0.0',
        );
        expect(find.textContaining('@meta format=1'), findsOneWidget);

        AppLogger.info(LogTag.domain, 'live entry #60 while scrolled to top');
        await tester.pumpAndSettle();
        expect(
          verticalController?.offset,
          equals(0.0),
          reason: 'New entries arriving while scrolled to top must not yank scroll position away',
        );

        verticalController?.jumpTo(verticalController.position.maxScrollExtent);
        await tester.pumpAndSettle();
        AppLogger.info(LogTag.domain, 'live entry #61 while following end');
        await tester.pumpAndSettle();
        expect(
          verticalController?.offset,
          equals(verticalController?.position.maxScrollExtent),
          reason: 'Scrolling back to the bottom must resume automatic following of new entries',
        );
        expect(
          find.textContaining('live entry #61 while following end'),
          findsOneWidget,
        );

        final horizontalScrollView = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        expect(
          horizontalScrollView.controller?.position.maxScrollExtent ?? 0.0,
          greaterThan(0.0),
          reason: 'Long monospace log lines must scroll horizontally',
        );
      },
    );

    testWidgets(
      'starts at the end on initial mount with pre-existing logs and re-anchors on filter change',
      (tester) async {
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
        for (var i = 0; i < 50; i++) {
          AppLogger.info(LogTag.tdf, 'tdf preloaded entry #$i');
          AppLogger.info(LogTag.sync, 'sync preloaded entry #$i');
        }

        await pumpLeafWidget(
          tester,
          const Scaffold(body: LogViewerView()),
          config: const WebDavConfig(diagnosticsEnabled: true),
        );
        await tester.pumpAndSettle();

        final listView = tester.widget<ListView>(find.byType(ListView));
        final verticalController = listView.controller;
        expect(verticalController, isNotNull);
        expect(verticalController?.position.maxScrollExtent, greaterThan(0.0));
        expect(
          verticalController?.offset,
          equals(verticalController?.position.maxScrollExtent),
          reason: 'Pre-existing logs must start scrolled to the end on open',
        );
        expect(find.textContaining('sync preloaded entry #49'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_scroll_top_button')),
        );
        await tester.pumpAndSettle();
        expect(verticalController?.offset, equals(0.0));

        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_sync')),
        );
        await tester.pumpAndSettle();

        expect(
          verticalController?.offset,
          equals(verticalController?.position.maxScrollExtent),
          reason: 'Toggling subsystem filter must anchor to the end of filtered entries',
        );
        expect(find.textContaining('tdf preloaded entry #49'), findsOneWidget);

        await tester.drag(find.byType(ListView), const Offset(0, 250));
        await tester.pumpAndSettle();
        final scrolledUpOffset = verticalController?.offset ?? 0.0;
        expect(
          scrolledUpOffset,
          lessThan(verticalController?.position.maxScrollExtent ?? 0.0),
          reason: 'Manual upward drag must scroll away from the end',
        );

        AppLogger.info(LogTag.tdf, 'tdf entry #50 during manual read');
        await tester.pumpAndSettle();
        expect(
          verticalController?.offset,
          equals(scrolledUpOffset),
          reason: 'Manual upward scroll must pause auto-follow while new entries arrive',
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('log_viewer_clear_button')),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 40; i++) {
          AppLogger.info(LogTag.tdf, 'post-clear tdf entry #$i');
        }
        await tester.pumpAndSettle();
        final postClearListView = tester.widget<ListView>(
          find.byType(ListView),
        );
        final postClearController = postClearListView.controller;
        expect(
          postClearController?.offset,
          equals(postClearController?.position.maxScrollExtent),
          reason: 'New entries added after Clear must resume auto-scrolling to the end',
        );
        expect(find.textContaining('post-clear tdf entry #39'), findsOneWidget);
      },
    );

    testWidgets(
      'supports selecting and copying multi-line text directly inside the log console',
      (tester) async {
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
        AppLogger.info(LogTag.tdf, 'selectable alpha line');
        AppLogger.info(LogTag.tdf, 'selectable beta line');

        await pumpLeafWidget(
          tester,
          const Scaffold(body: LogViewerView()),
          config: const WebDavConfig(diagnosticsEnabled: true),
        );
        await tester.pumpAndSettle();

        final consoleFinder = find.byKey(
          const ValueKey<String>('log_viewer_console'),
        );
        expect(
          find.descendant(
            of: consoleFinder,
            matching: find.byType(SelectionArea),
          ),
          findsOneWidget,
          reason: 'Log console must expose a SelectionArea for direct text selection',
        );

        final firstLineFinder = find.textContaining('selectable alpha line');
        final secondLineFinder = find.textContaining('selectable beta line');
        expect(firstLineFinder, findsOneWidget);
        expect(secondLineFinder, findsOneWidget);

        final firstRect = tester.getRect(firstLineFinder);
        final secondRect = tester.getRect(secondLineFinder);
        final gesture = await tester.startGesture(
          Offset(firstRect.left + 4.0, firstRect.center.dy),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(
          Offset(secondRect.right - 4.0, secondRect.center.dy),
        );
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        lastCopiedText = null;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(
          lastCopiedText,
          isNotNull,
          reason: 'Ctrl+C must copy the inline console selection to clipboard',
        );
        expect(lastCopiedText, contains('selectable alpha line'));
        expect(lastCopiedText, contains('selectable beta line'));
        expect(
          lastCopiedText,
          contains('\n'),
          reason:
              'Multi-line console selections must preserve newline separators',
        );
        expect(
          lastCopiedText?.endsWith('\n'),
          isFalse,
          reason: 'Completed console selections must not include a stray trailing newline',
        );

        final reverseGesture = await tester.startGesture(
          Offset(secondRect.right - 4.0, secondRect.center.dy),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await reverseGesture.moveTo(
          Offset(firstRect.left + 4.0, firstRect.center.dy),
        );
        await tester.pump();
        await reverseGesture.up();
        await tester.pumpAndSettle();

        lastCopiedText = null;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(
          lastCopiedText,
          contains('selectable alpha line\n'),
          reason: 'Bottom-to-top drag selection must preserve newline separation in visual order',
        );
        expect(lastCopiedText, contains('selectable beta line'));
        expect(lastCopiedText?.endsWith('\n'), isFalse);

        final singleLineGesture = await tester.startGesture(
          Offset(firstRect.left + 4.0, firstRect.center.dy),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await singleLineGesture.moveTo(
          Offset(firstRect.right - 4.0, firstRect.center.dy),
        );
        await tester.pump();
        await singleLineGesture.up();
        await tester.pumpAndSettle();

        lastCopiedText = null;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(lastCopiedText, contains('selectable alpha line'));
        expect(
          lastCopiedText,
          isNot(contains('\n')),
          reason: 'Single-line selection must not add a newline separator',
        );
      },
    );

    testWidgets(
      'renders without overflow across breakpoints in German locale with WebDAV upload and navigates Back to tasks',
      (tester) async {
        const webDavConfig = WebDavConfig(
          language: AppLanguage.german,
          diagnosticsEnabled: true,
          logStorageMode: StorageMode.webdav,
          storageMode: StorageMode.webdav,
          serverUrl: 'https://cloud.example.com/dav/',
          username: 'alice',
          password: 'secret-password',
        );
        const viewportSizes = <Size>[
          Size(390, 420),
          Size(390, 700),
          Size(720, 700),
          Size(721, 700),
          Size(760, 700),
          Size(820, 700),
          Size(821, 700),
          Size(960, 700),
          Size(1280, 800),
        ];
        const themeConfigs = <({String presetId, ThemeMode mode})>[
          (presetId: 'calm', mode: ThemeMode.light),
          (presetId: 'calm', mode: ThemeMode.dark),
          (presetId: 'plum_umber', mode: ThemeMode.light),
          (presetId: 'plum_umber', mode: ThemeMode.dark),
        ];

        for (var i = 0; i < viewportSizes.length; i++) {
          final size = viewportSizes[i];
          final theme = themeConfigs[i % themeConfigs.length];
          final container = await pumpLeafWidget(
            tester,
            const Scaffold(body: LogViewerView()),
            config: webDavConfig,
            locale: const Locale('de'),
            surfaceSize: size,
            presetId: theme.presetId,
            themeMode: theme.mode,
          );
          container.read(shellProvider.notifier).openView(ShellView.logs);
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason:
                'LogViewerView must not overflow at viewport $size (${theme.presetId}/${theme.mode.name})',
          );
          expect(find.text('Diagnoseprotokoll'), findsOneWidget);
          expect(find.text('Subsysteme'), findsOneWidget);
          expect(find.text('6 / 6'), findsOneWidget);
          expect(find.text('Alle'), findsOneWidget);
          expect(find.text('Keine'), findsOneWidget);
          expect(find.text('Alles kopieren'), findsOneWidget);
          expect(find.text('Gefiltert kopieren'), findsOneWidget);
          expect(find.text('Nach oben scrollen'), findsOneWidget);
          expect(find.text('Log hochladen'), findsOneWidget);
          expect(find.text('Leeren'), findsOneWidget);

          if (size == viewportSizes.first) {
            await tester.tap(find.text('Zurück zu den Aufgaben'));
            await tester.pumpAndSettle();
            expect(container.read(shellProvider).view, equals(ShellView.tasks));
          }
        }
      },
    );

    testWidgets(
      'supports keyboard toggling and semantic toggled state on subsystem pills',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          AppLogger.setEnabled(
            true,
            minimumLevel: LogLevel.debug,
            persistToDisk: false,
          );
          AppLogger.info(LogTag.tdf, 'tdf keyboard entry');
          AppLogger.info(LogTag.storage, 'storage keyboard entry');

          await pumpLeafWidget(
            tester,
            const Scaffold(body: LogViewerView()),
            config: const WebDavConfig(diagnosticsEnabled: true),
          );
          await tester.pumpAndSettle();

          final tdfPillFinder = find.byKey(
            const ValueKey<String>('log_viewer_subsystem_tdf'),
          );
          final initialSemantics = tester.getSemantics(tdfPillFinder);
          expect(initialSemantics.label, contains('TDF'));
          expect(initialSemantics.flagsCollection.isButton, isTrue);
          expect(
            initialSemantics.flagsCollection.isToggled,
            equals(Tristate.isTrue),
            reason:
                'Selected subsystem pill must expose toggled=true semantics',
          );

          final tdfFocusNode = Focus.of(
            tester.element(
              find.descendant(
                of: tdfPillFinder,
                matching: find.byType(GestureDetector),
              ),
            ),
          );
          tdfFocusNode.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();

          expect(find.textContaining('tdf keyboard entry'), findsNothing);
          expect(find.textContaining('storage keyboard entry'), findsOneWidget);
          expect(tester.widget<UiPill>(tdfPillFinder).isSelected, isFalse);
          expect(
            tester.getSemantics(tdfPillFinder).flagsCollection.isToggled,
            equals(Tristate.isFalse),
            reason: 'Space key must toggle subsystem pill to toggled=false',
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.textContaining('tdf keyboard entry'), findsOneWidget);
          expect(tester.widget<UiPill>(tdfPillFinder).isSelected, isTrue);
          expect(
            tester.getSemantics(tdfPillFinder).flagsCollection.isToggled,
            equals(Tristate.isTrue),
            reason: 'Enter key must toggle subsystem pill back to toggled=true',
          );
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'places All/None buttons in the subsystem header above aligned single-row pills on desktop and stacks cleanly on compact',
      (tester) async {
        AppLogger.setEnabled(
          true,
          minimumLevel: LogLevel.debug,
          persistToDisk: false,
        );
        AppLogger.info(LogTag.tdf, 'layout check entry');

        for (final desktopSize in const <Size>[
          Size(960, 700),
          Size(1280, 800),
        ]) {
          await pumpLeafWidget(
            tester,
            const Scaffold(body: LogViewerView()),
            config: const WebDavConfig(diagnosticsEnabled: true),
            surfaceSize: desktopSize,
          );
          await tester.pumpAndSettle();

          final allRect = tester.getRect(
            find.byKey(const ValueKey<String>('log_viewer_subsystem_all')),
          );
          final noneRect = tester.getRect(
            find.byKey(const ValueKey<String>('log_viewer_subsystem_none')),
          );
          final countRect = tester.getRect(
            find.byKey(const ValueKey<String>('log_viewer_subsystem_count')),
          );
          final levelRect = tester.getRect(
            find.byKey(const ValueKey<String>('log_viewer_level_filter')),
          );
          final firstPillRect = tester.getRect(
            find.byKey(
              const ValueKey<String>('log_viewer_subsystem_lifecycle'),
            ),
          );
          final lastPillRect = tester.getRect(
            find.byKey(const ValueKey<String>('log_viewer_subsystem_ui')),
          );

          expect(
            allRect.left,
            greaterThan(countRect.right),
            reason:
                'All button must sit to the right of the subsystem header count at $desktopSize',
          );
          expect(
            noneRect.left,
            greaterThan(allRect.right),
            reason: 'None button must sit to the right of All at $desktopSize',
          );
          expect(
            allRect.bottom,
            lessThanOrEqualTo(firstPillRect.top),
            reason:
                'All/None buttons must reside in the subsystem header row above the pills at $desktopSize',
          );
          expect(
            (firstPillRect.top - lastPillRect.top).abs(),
            lessThanOrEqualTo(1.0),
            reason:
                'All six subsystem pills must fit on a single row at $desktopSize',
          );
          expect(
            (levelRect.top - firstPillRect.top).abs(),
            lessThanOrEqualTo(2.0),
            reason:
                'Level select ($levelRect) and subsystem pills ($firstPillRect; all=$allRect, count=$countRect) must align vertically at $desktopSize',
          );
        }

        await pumpLeafWidget(
          tester,
          const Scaffold(body: LogViewerView()),
          config: const WebDavConfig(diagnosticsEnabled: true),
          surfaceSize: const Size(390, 700),
        );
        await tester.pumpAndSettle();

        final compactLevelRect = tester.getRect(
          find.byKey(const ValueKey<String>('log_viewer_level_filter')),
        );
        final compactSubsystemRect = tester.getRect(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_filter')),
        );
        final compactAllRect = tester.getRect(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_all')),
        );
        final compactFirstPillRect = tester.getRect(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_lifecycle')),
        );

        expect(
          compactLevelRect.bottom,
          lessThan(compactSubsystemRect.top),
          reason: 'Level filter must stack above subsystem filter on compact viewports',
        );
        expect(
          compactAllRect.bottom,
          lessThanOrEqualTo(compactFirstPillRect.top),
          reason: 'All/None buttons must remain in the subsystem header row above the pills on compact viewports',
        );
      },
    );

    testWidgets(
      'scopes log appends to console and metadata counts with fixed itemExtent and RepaintBoundary',
      (tester) async {
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
        AppLogger.info(LogTag.domain, 'initial scoped log entry');

        await pumpLeafWidget(
          tester,
          const Scaffold(body: LogViewerView()),
          config: const WebDavConfig(diagnosticsEnabled: true),
          surfaceSize: const Size(1280, 800),
        );
        await tester.pumpAndSettle();

        final consoleFinder = find.byKey(
          const ValueKey<String>('log_viewer_console'),
        );
        expect(
          find.descendant(
            of: consoleFinder,
            matching: find.byType(RepaintBoundary),
          ),
          findsWidgets,
          reason:
              'Log console panel must isolate repaints in a RepaintBoundary',
        );
        final listView = tester.widget<ListView>(
          find.descendant(of: consoleFinder, matching: find.byType(ListView)),
        );
        expect(
          listView.itemExtent,
          isNotNull,
          reason: 'Log console ListView must specify a fixed itemExtent for O(1) jumping',
        );

        final headerBefore = tester.widget<UiPageHeader>(
          find.byType(UiPageHeader),
        );
        final levelFieldBefore = tester.widget<UiField>(
          find.byKey(const ValueKey<String>('log_viewer_level_filter')),
        );
        final subsystemPillBefore = tester.widget<UiPill>(
          find.byKey(const ValueKey<String>('log_viewer_subsystem_tdf')),
        );
        final copyButtonBefore = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('log_viewer_copy_button')),
        );

        AppLogger.info(LogTag.domain, 'incremental scoped log entry');
        await tester.pumpAndSettle();

        expect(
          find.textContaining('incremental scoped log entry'),
          findsOneWidget,
        );
        expect(
          find.text('Entries: 3 | Warnings: 0 | Errors: 0'),
          findsOneWidget,
        );

        expect(
          identical(
            tester.widget<UiPageHeader>(find.byType(UiPageHeader)),
            headerBefore,
          ),
          isTrue,
          reason: 'Appending a log line must not rebuild UiPageHeader',
        );
        expect(
          identical(
            tester.widget<UiField>(
              find.byKey(const ValueKey<String>('log_viewer_level_filter')),
            ),
            levelFieldBefore,
          ),
          isTrue,
          reason: 'Appending a log line must not rebuild level filter select',
        );
        expect(
          identical(
            tester.widget<UiPill>(
              find.byKey(const ValueKey<String>('log_viewer_subsystem_tdf')),
            ),
            subsystemPillBefore,
          ),
          isTrue,
          reason:
              'Appending a log line must not rebuild subsystem toggle pills',
        );
        expect(
          identical(
            tester.widget<UiButton>(
              find.byKey(const ValueKey<String>('log_viewer_copy_button')),
            ),
            copyButtonBefore,
          ),
          isTrue,
          reason:
              'Appending a log line must not rebuild unchanged toolbar actions',
        );
      },
    );
  });

  group('RawTdfView', () {
    testWidgets(
      'renders canonical TDF text, telemetry stats, and copies content with toast notice',
      (tester) async {
        final board = TaskBoard(
          focus: <TaskItem>[
            TaskItem(
              id: 'alpha-1',
              title: 'Ship Wave 4 secondary views with long title ${'z' * 120}',
              note: 'Canonical note line',
            ),
          ],
        );

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: RawTdfView()),
          board: board,
        );

        expect(find.text('TDF Source'), findsOneWidget);
        expect(find.text('Raw TDF 0.8.0'), findsNothing);
        expect(
          find.text(
            'Canonical LF-terminated TDF serialization of the current workspace board.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('raw_tdf_stats_card')),
          findsOneWidget,
        );
        expect(find.textContaining('bytes / 1 MiB'), findsOneWidget);
        expect(find.textContaining('lines / 16,384 max'), findsOneWidget);

        final codeBlockFinder = find.byKey(
          const ValueKey<String>('raw_tdf_code_block'),
        );
        expect(codeBlockFinder, findsOneWidget);
        expect(
          find.descendant(
            of: codeBlockFinder,
            matching: find.byType(SelectionArea),
          ),
          findsOneWidget,
          reason: 'Raw TDF code block must expose a SelectionArea',
        );
        final headerLineFinder = find.descendant(
          of: codeBlockFinder,
          matching: find.textContaining('tdf 0.8.0'),
        );
        expect(headerLineFinder, findsOneWidget);
        expect(
          find.descendant(
            of: codeBlockFinder,
            matching: find.textContaining('task alpha-1 {'),
          ),
          findsOneWidget,
        );
        final headerLineText = tester.widget<Text>(headerLineFinder);
        expect(
          headerLineText.style?.fontSize,
          equals(UiTypographyTokens.standard.rawCode.fontSize),
        );
        expect(
          headerLineText.style?.fontFamily,
          equals(UiTypographyTokens.standard.rawCode.fontFamily),
        );

        final copyButtonFinder = find.byKey(
          const ValueKey<String>('raw_tdf_copy_button'),
        );
        final copyButton = tester.widget<UiButton>(copyButtonFinder);
        expect(copyButton.onPressed, isNotNull);

        await tester.tap(copyButtonFinder);
        await tester.pumpAndSettle();

        expect(
          lastCopiedText,
          equals(container.read(rawTdfPreviewProvider).content),
        );
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('TDF document copied to clipboard.'),
        );
        expect(
          container.read(floatingNoticeProvider)?.tone,
          equals(FloatingNoticeTone.success),
        );
      },
    );

    testWidgets(
      'virtualizes large TDF documents with fixed itemExtent and RepaintBoundary',
      (tester) async {
        final tasks = <TaskItem>[
          for (var i = 0; i < 200; i++)
            TaskItem(
              id: 't${i.toString().padLeft(4, '0')}',
              title: 'Virtualized TDF task #$i',
              note: 'Note payload line for task $i',
            ),
        ];
        final largeBoard = TaskBoard(planned: tasks);

        await pumpLeafWidget(
          tester,
          const Scaffold(body: RawTdfView()),
          board: largeBoard,
          surfaceSize: const Size(1280, 720),
        );

        final codeBlockFinder = find.byKey(
          const ValueKey<String>('raw_tdf_code_block'),
        );
        expect(codeBlockFinder, findsOneWidget);
        expect(
          find.descendant(
            of: codeBlockFinder,
            matching: find.byType(RepaintBoundary),
          ),
          findsWidgets,
          reason:
              'Raw TDF code block must isolate repaints in a RepaintBoundary',
        );
        final listView = tester.widget<ListView>(
          find.descendant(of: codeBlockFinder, matching: find.byType(ListView)),
        );
        expect(
          listView.itemExtent,
          isNotNull,
          reason:
              'Raw TDF ListView must set a fixed itemExtent for O(1) scrolling',
        );
        final mountedLines = tester
            .widgetList<Text>(
              find.descendant(
                of: find.descendant(
                  of: codeBlockFinder,
                  matching: find.byType(ListView),
                ),
                matching: find.byType(Text),
              ),
            )
            .length;
        expect(
          mountedLines,
          greaterThan(0),
          reason: 'Visible TDF lines must render inside ListView.builder',
        );
        expect(
          mountedLines,
          lessThan(100),
          reason: 'Virtualized RawTdfView must mount only visible + cached lines instead of all ~1000 lines',
        );
      },
    );

    testWidgets(
      'disables Copy and displays warning banner when TDF exceeds 1 MiB limit',
      (tester) async {
        final hugeNote = 'a' * 1900;
        final tasks = <TaskItem>[
          for (var i = 0; i < 600; i++)
            TaskItem(id: 'task-$i', title: 'Oversized Task $i', note: hugeNote),
        ];
        final oversizedBoard = TaskBoard(planned: tasks);

        await pumpLeafWidget(
          tester,
          const Scaffold(body: RawTdfView()),
          board: oversizedBoard,
        );

        final copyButton = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('raw_tdf_copy_button')),
        );
        expect(
          copyButton.onPressed,
          isNull,
          reason: 'Copy must be disabled when preview limit is exceeded',
        );
        expect(
          find.byKey(const ValueKey<String>('raw_tdf_code_block')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('raw_tdf_limit_banner')),
          findsOneWidget,
        );
        expect(find.text('Preview Limit Exceeded'), findsOneWidget);
        expect(
          find.textContaining('1 MiB or 16,384-line limit'),
          findsOneWidget,
        );
        expect(find.textContaining('1048577 bytes / 1 MiB'), findsOneWidget);
      },
    );

    testWidgets(
      'renders cleanly on compact viewport and supports Back to tasks',
      (tester) async {
        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: RawTdfView()),
          surfaceSize: const Size(390, 844),
        );
        container.read(shellProvider.notifier).openView(ShellView.rawTdf);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Back to tasks'));
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.tasks));
      },
    );
  });

  group('DeletionConflictView and ResolutionActionDock', () {
    testWidgets(
      'lists conflicted tasks, labels, and locations with Keep Edit defaults, toggles choices without ID collision, and applies via SyncActions',
      (tester) async {
        final board = TaskBoard(
          focus: <TaskItem>[
            TaskItem(id: 'shared-1', title: 'Conflicted Alpha Task'),
          ],
          labels: const <TdfLabel>[
            TdfLabel(id: 'shared-1', name: 'Conflicted Urgent Label'),
          ],
          locations: const <TdfLocation>[
            TdfLocation(
              id: 'loc-office',
              name: 'Headquarters Office',
              latitude: 48.1351,
              longitude: 11.5820,
              radius: 150.0,
            ),
          ],
        );

        Map<String, TdfDeletionResolution>? capturedTasks;
        Map<String, TdfDeletionResolution>? capturedLabels;
        Map<String, TdfDeletionResolution>? capturedLocations;
        final applyGate = Completer<TaskBoard>();

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: DeletionConflictView()),
                ResolutionActionDock(isRecovery: false),
              ],
            ),
          ),
          board: board,
          taskNotifierFactory: () => _SpyResolutionTaskNotifier(
            board,
            onResolveDeletionConflicts:
                ({
                  required taskResolutions,
                  required labelResolutions,
                  required locationResolutions,
                }) {
                  capturedTasks = taskResolutions;
                  capturedLabels = labelResolutions;
                  capturedLocations = locationResolutions;
                  return applyGate.future;
                },
          ),
        );

        container.read(shellProvider.notifier).openView(ShellView.conflict);
        container
            .read(syncStateProvider.notifier)
            .setConflict(
              'Conflict active',
              outcome: const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.deletionConflict,
                message: 'Deletion conflict detected',
                conflictedTaskIds: <String>['shared-1'],
                conflictedLabelIds: <String>['shared-1'],
                conflictedLocationIds: <String>['loc-office'],
              ),
            );
        await tester.pumpAndSettle();

        expect(
          find.text('Resolve Deletion Conflicts (TDF-DEL-003)'),
          findsOneWidget,
        );
        expect(find.text('3'), findsOneWidget);
        expect(find.text('TASK · shared-1'), findsOneWidget);
        expect(find.text('Conflicted Alpha Task'), findsOneWidget);
        expect(find.text('LABEL · shared-1'), findsOneWidget);
        expect(find.text('Conflicted Urgent Label'), findsOneWidget);
        expect(find.text('LOCATION · loc-office'), findsOneWidget);
        expect(find.text('Headquarters Office'), findsOneWidget);

        final initialDecisions = container.read(conflictDecisionsProvider);
        expect(
          initialDecisions[resolutionDecisionKey(
            EntityKind.task.name,
            'shared-1',
          )],
          equals(TdfDeletionResolution.undelete),
        );
        expect(
          initialDecisions[resolutionDecisionKey(
            EntityKind.label.name,
            'shared-1',
          )],
          equals(TdfDeletionResolution.undelete),
        );
        expect(
          initialDecisions[resolutionDecisionKey(
            EntityKind.location.name,
            'loc-office',
          )],
          equals(TdfDeletionResolution.undelete),
        );

        await tester.tap(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('conflict_card_task_shared-1'),
            ),
            matching: find.text('Confirm Deletion'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('conflict_card_location_loc-office'),
            ),
            matching: find.text('Confirm Deletion'),
          ),
        );
        await tester.pumpAndSettle();

        final updatedDecisions = container.read(conflictDecisionsProvider);
        expect(
          updatedDecisions[resolutionDecisionKey(
            EntityKind.task.name,
            'shared-1',
          )],
          equals(TdfDeletionResolution.delete),
        );
        expect(
          updatedDecisions[resolutionDecisionKey(
            EntityKind.label.name,
            'shared-1',
          )],
          equals(TdfDeletionResolution.undelete),
          reason: 'Label with identical raw ID must keep independent choice',
        );
        expect(
          updatedDecisions[resolutionDecisionKey(
            EntityKind.location.name,
            'loc-office',
          )],
          equals(TdfDeletionResolution.delete),
        );

        final applyFinder = find.byKey(
          const ValueKey<String>('resolution_apply_button'),
        );
        await tester.tap(applyFinder);
        await tester.pump();

        final busyApplyButton = tester.widget<UiButton>(applyFinder);
        expect(busyApplyButton.isLoading, isTrue);
        expect(busyApplyButton.onPressed, isNull);

        applyGate.complete(board);
        await tester.pumpAndSettle();

        expect(
          capturedTasks,
          equals(const <String, TdfDeletionResolution>{
            'shared-1': TdfDeletionResolution.delete,
          }),
        );
        expect(
          capturedLabels,
          equals(const <String, TdfDeletionResolution>{
            'shared-1': TdfDeletionResolution.undelete,
          }),
        );
        expect(
          capturedLocations,
          equals(const <String, TdfDeletionResolution>{
            'loc-office': TdfDeletionResolution.delete,
          }),
        );
        expect(container.read(shellProvider).view, equals(ShellView.tasks));
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Deletion conflicts resolved. Synchronization resumed.'),
        );
      },
    );

    testWidgets(
      'Cancel returns to Tasks and persist failure emits danger floating notice',
      (tester) async {
        final board = TaskBoard(
          focus: <TaskItem>[TaskItem(id: 'task-fail', title: 'Failing Task')],
        );
        var resolveCalls = 0;

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: DeletionConflictView()),
                ResolutionActionDock(isRecovery: false),
              ],
            ),
          ),
          board: board,
          taskNotifierFactory: () => _SpyResolutionTaskNotifier(
            board,
            onResolveDeletionConflicts:
                ({
                  required taskResolutions,
                  required labelResolutions,
                  required locationResolutions,
                }) {
                  resolveCalls++;
                  return Future<TaskBoard>.error(
                    const LocalFileException('Disk write failed.'),
                  );
                },
          ),
        );

        container.read(shellProvider.notifier).openView(ShellView.conflict);
        container
            .read(syncStateProvider.notifier)
            .setConflict(
              'Conflict active',
              outcome: const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.deletionConflict,
                message: 'Deletion conflict detected',
                conflictedTaskIds: <String>['task-fail'],
              ),
            );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('resolution_apply_button')),
        );
        await tester.pumpAndSettle();

        expect(resolveCalls, equals(1));
        expect(container.read(shellProvider).view, equals(ShellView.conflict));
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Disk write failed.'),
        );
        expect(
          container.read(floatingNoticeProvider)?.tone,
          equals(FloatingNoticeTone.danger),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('resolution_cancel_button')),
        );
        await tester.pumpAndSettle();

        expect(container.read(shellProvider).view, equals(ShellView.tasks));
      },
    );
  });

  group('GenerationRecoveryView and ResolutionActionDock', () {
    testWidgets(
      'lists ambiguous entities with Recover as New defaults, toggles to Discard Local Change, and applies recovery',
      (tester) async {
        final board = TaskBoard(
          focus: <TaskItem>[
            TaskItem(id: 'amb-task', title: 'Retired Local Task'),
          ],
          labels: const <TdfLabel>[
            TdfLabel(id: 'amb-label', name: 'Retired Local Label'),
          ],
          locations: const <TdfLocation>[
            TdfLocation(
              id: 'amb-loc',
              name: 'Retired Local Place',
              latitude: 52.5200,
              longitude: 13.4050,
              radius: 200.0,
            ),
          ],
        );

        Map<String, TdfRecoveryResolution>? capturedTasks;
        Map<String, TdfRecoveryResolution>? capturedLabels;
        Map<String, TdfRecoveryResolution>? capturedLocations;

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: GenerationRecoveryView()),
                ResolutionActionDock(isRecovery: true),
              ],
            ),
          ),
          board: board,
          taskNotifierFactory: () => _SpyResolutionTaskNotifier(
            board,
            onResolveRecovery:
                ({
                  required taskResolutions,
                  required labelResolutions,
                  required locationResolutions,
                }) async {
                  capturedTasks = taskResolutions;
                  capturedLabels = labelResolutions;
                  capturedLocations = locationResolutions;
                  return board;
                },
          ),
        );

        container.read(shellProvider.notifier).openView(ShellView.recovery);
        container
            .read(syncStateProvider.notifier)
            .setConflict(
              'Recovery required',
              outcome: const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.recoveryRequired,
                message: 'Generation advanced',
                ambiguousTaskIds: <String>['amb-task'],
                ambiguousLabelIds: <String>['amb-label'],
                ambiguousLocationIds: <String>['amb-loc'],
              ),
            );
        await tester.pumpAndSettle();

        expect(
          find.text('Recover After History Advancement (TDF-REC-002)'),
          findsOneWidget,
        );
        expect(find.text('3'), findsOneWidget);
        expect(find.text('TASK · amb-task'), findsOneWidget);
        expect(find.text('Retired Local Task'), findsOneWidget);
        expect(find.text('LABEL · amb-label'), findsOneWidget);
        expect(find.text('Retired Local Label'), findsOneWidget);
        expect(find.text('LOCATION · amb-loc'), findsOneWidget);
        expect(find.text('Retired Local Place'), findsOneWidget);

        final initialDecisions = container.read(recoveryDecisionsProvider);
        expect(
          initialDecisions[resolutionDecisionKey(
            EntityKind.task.name,
            'amb-task',
          )],
          equals(TdfRecoveryResolution.recoverAsNew),
        );
        expect(
          initialDecisions[resolutionDecisionKey(
            EntityKind.label.name,
            'amb-label',
          )],
          equals(TdfRecoveryResolution.recoverAsNew),
        );
        expect(
          initialDecisions[resolutionDecisionKey(
            EntityKind.location.name,
            'amb-loc',
          )],
          equals(TdfRecoveryResolution.recoverAsNew),
        );

        await tester.tap(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('recovery_card_label_amb-label'),
            ),
            matching: find.text('Discard Local Change'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('resolution_apply_button')),
        );
        await tester.pumpAndSettle();

        expect(
          capturedTasks,
          equals(const <String, TdfRecoveryResolution>{
            'amb-task': TdfRecoveryResolution.recoverAsNew,
          }),
        );
        expect(
          capturedLabels,
          equals(const <String, TdfRecoveryResolution>{
            'amb-label': TdfRecoveryResolution.discard,
          }),
        );
        expect(
          capturedLocations,
          equals(const <String, TdfRecoveryResolution>{
            'amb-loc': TdfRecoveryResolution.recoverAsNew,
          }),
        );
        expect(container.read(shellProvider).view, equals(ShellView.tasks));
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Recovery completed. Synchronization resumed.'),
        );
      },
    );

    testWidgets(
      'disables Apply when no recovery items are active and renders cleanly on compact viewport',
      (tester) async {
        await pumpLeafWidget(
          tester,
          const Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: GenerationRecoveryView()),
                ResolutionActionDock(isRecovery: true),
              ],
            ),
          ),
          surfaceSize: const Size(390, 844),
        );

        expect(tester.takeException(), isNull);
        final applyButton = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('resolution_apply_button')),
        );
        expect(applyButton.onPressed, isNull);
      },
    );
  });
}
