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
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/settings_codec.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/floating_notice_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/tdf_service.dart';

import '../ui/test_helpers.dart';

/// Controllable [ActiveWorkspaceNotifier] supporting synthetic transient `AsyncLoading` emissions.
class _ControllableWorkspaceNotifier extends ActiveWorkspaceNotifier {
  /// Emits a transient [AsyncLoading] state without changing the persisted workspace.
  void emitTransientLoading() {
    state = const AsyncLoading();
  }

  /// Emits a loaded [workspace] state.
  void emitWorkspace(AppWorkspace workspace) {
    state = AsyncData(workspace);
  }
}

/// [InMemorySettingsRepository] that counts [takeLastRecoveryNotice] calls for build-purity checks.
class _CountingRecoverySettingsRepository extends InMemorySettingsRepository {
  _CountingRecoverySettingsRepository({
    required super.initialConfig,
    required super.recoveryNotice,
  }) : super.withRecoveryNotice();

  /// Number of times [takeLastRecoveryNotice] has been invoked.
  int takeCallCount = 0;

  @override
  SettingsRecoveryNotice? takeLastRecoveryNotice() {
    takeCallCount++;
    return super.takeLastRecoveryNotice();
  }
}

/// Delayed [InMemorySettingsRepository] emitting a startup recovery notice only after [onLoad] completes.
class _DelayedRecoverySettingsRepository extends InMemorySettingsRepository {
  _DelayedRecoverySettingsRepository({
    WebDavConfig initialConfig = const WebDavConfig(
      language: AppLanguage.english,
    ),
    required this.onLoad,
    SettingsRecoveryNotice? recoveryNotice,
  }) : _pendingNotice = recoveryNotice,
       super(initialConfig);

  final Future<void> Function() onLoad;
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
  SettingsRecoveryNotice? takeLastRecoveryNotice() {
    final notice = _emittedNotice;
    _emittedNotice = null;
    return notice;
  }
}

/// [FakeLocalFileRepository] that can fail subsequent writes on demand to test undo rollback dismissal.
class _FailingWriteLocalFileRepository extends FakeLocalFileRepository {
  _FailingWriteLocalFileRepository({
    required super.config,
    required super.initialTdf,
  });

  /// Whether [saveTdf] should throw a [LocalFileException].
  bool failNextSave = false;

  @override
  Future<void> saveTdf(String tdfContent) async {
    if (failNextSave) {
      throw const LocalFileException('Simulated disk failure');
    }
    await super.saveTdf(tdfContent);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixedNow = DateTime.utc(2026, 11, 10, 12, 0);

  group('FloatingNotice', () {
    test('supports value equality, hashCode, and hasUndoAction semantics across all tones', () {
      const base = FloatingNotice(
        id: 1,
        message: 'Task deleted',
        tone: FloatingNoticeTone.accent,
        actionLabel: 'Undo',
        undoSequence: 3,
        shortcutHint: 'Ctrl+Z',
        autoHideDuration: FloatingNoticeNotifier.undoDuration,
      );
      const identicalCopy = FloatingNotice(
        id: 1,
        message: 'Task deleted',
        tone: FloatingNoticeTone.accent,
        actionLabel: 'Undo',
        undoSequence: 3,
        shortcutHint: 'Ctrl+Z',
        autoHideDuration: FloatingNoticeNotifier.undoDuration,
      );
      const withoutAction = FloatingNotice(
        id: 2,
        message: 'Saved',
        tone: FloatingNoticeTone.success,
      );

      expect(base, equals(identicalCopy));
      expect(base.hashCode, equals(identicalCopy.hashCode));
      expect(base.hasUndoAction, isTrue);
      expect(withoutAction.hasUndoAction, isFalse);
      expect(base, isNot(equals(withoutAction)));
      expect(
        FloatingNoticeTone.values,
        equals(const <FloatingNoticeTone>[
          FloatingNoticeTone.neutral,
          FloatingNoticeTone.accent,
          FloatingNoticeTone.warning,
          FloatingNoticeTone.danger,
          FloatingNoticeTone.success,
        ]),
      );
    });
  });

  group('FloatingNoticeNotifier', () {
    test('keeps build pure without consuming recovery notice synchronously and surfaces it via microtask', () async {
      final settingsRepository = _CountingRecoverySettingsRepository(
        initialConfig: const WebDavConfig(language: AppLanguage.english),
        recoveryNotice: const SettingsRecoveryNotice(
          kind: SettingsRecoveryKind.recoveredFromBackup,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          clockProvider.overrideWithValue(() => fixedNow),
          taskNotifierProvider.overrideWith(
            () => FakeTaskNotifier(TaskBoard.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activeWorkspaceProvider.future);
      final subscription = container.listen(floatingNoticeProvider, (_, _) {});
      addTearDown(subscription.close);

      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'build() must remain pure and return null synchronously',
      );
      expect(
        settingsRepository.takeCallCount,
        equals(0),
        reason:
            'build() must not synchronously consume takeLastRecoveryNotice()',
      );

      await Future<void>.microtask(() {});

      final notice = container.read(floatingNoticeProvider);
      expect(
        notice,
        isNotNull,
        reason: 'Scheduled microtask must surface pending recovery notice',
      );
      expect(settingsRepository.takeCallCount, equals(1));
      expect(notice?.persistent, isTrue);
      expect(notice?.tone, equals(FloatingNoticeTone.warning));
      expect(
        notice?.message,
        equals('Settings were restored from backup after a file error.'),
      );
      expect(
        settingsRepository.takeLastRecoveryNotice(),
        isNull,
        reason: 'One-shot startup recovery notice must be consumed once',
      );

      // Calling showStartupRecoveryNoticeIfPending again must remain idempotent.
      container
          .read(floatingNoticeProvider.notifier)
          .showStartupRecoveryNoticeIfPending();
      expect(container.read(floatingNoticeProvider), equals(notice));
    });

    test('consumes async-resolved startup recovery notice when activeWorkspaceProvider completes later', () async {
      final loadGate = Completer<void>();
      final settingsRepository = _DelayedRecoverySettingsRepository(
        initialConfig: const WebDavConfig(language: AppLanguage.english),
        onLoad: () => loadGate.future,
        recoveryNotice: const SettingsRecoveryNotice(
          kind: SettingsRecoveryKind.resetAfterQuarantine,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          clockProvider.overrideWithValue(() => fixedNow),
          taskNotifierProvider.overrideWith(
            () => FakeTaskNotifier(TaskBoard.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notices = <FloatingNotice?>[];
      final subscription = container.listen(
        floatingNoticeProvider,
        (_, next) => notices.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      // Initial check while activeWorkspaceProvider is still AsyncLoading emits nothing.
      container
          .read(floatingNoticeProvider.notifier)
          .showStartupRecoveryNoticeIfPending();
      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'No recovery notice should display before async workspace finishes loading',
      );

      loadGate.complete();
      await container.read(activeWorkspaceProvider.future);

      final notice = container.read(floatingNoticeProvider);
      expect(
        notice,
        isNotNull,
        reason: 'Async workspace resolution must consume pending startup recovery notice automatically',
      );
      expect(notice?.persistent, isTrue);
      expect(notice?.tone, equals(FloatingNoticeTone.warning));
      expect(
        notice?.message,
        equals('Corrupt settings were backed up and reset to defaults.'),
      );
      expect(notices.last, equals(notice));
    });

    test('auto-hides standard notices, retains persistent notices, ignores transient AsyncLoading, and dismisses on workspace switch', () async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      final workspaceNotifier = _ControllableWorkspaceNotifier();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          activeWorkspaceProvider.overrideWith(() => workspaceNotifier),
          clockProvider.overrideWithValue(() => fixedNow),
          taskNotifierProvider.overrideWith(
            () => FakeTaskNotifier(TaskBoard.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final initialWorkspace = await container.read(
        activeWorkspaceProvider.future,
      );

      final subscription = container.listen(floatingNoticeProvider, (_, _) {});
      addTearDown(subscription.close);

      final notifier = container.read(floatingNoticeProvider.notifier);
      notifier.showNotice(
        'Short toast',
        duration: const Duration(milliseconds: 20),
      );
      expect(
        container.read(floatingNoticeProvider)?.message,
        equals('Short toast'),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'Timed notice must auto-hide once duration elapses',
      );

      notifier.showNotice(
        'Persistent alert',
        tone: FloatingNoticeTone.warning,
        persistent: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        container.read(floatingNoticeProvider)?.message,
        equals('Persistent alert'),
      );

      // Transient AsyncLoading followed by resolving the SAME workspace must preserve active notice.
      workspaceNotifier.emitTransientLoading();
      expect(
        container.read(floatingNoticeProvider)?.message,
        equals('Persistent alert'),
        reason: 'Transient AsyncLoading must not dismiss active notice',
      );
      workspaceNotifier.emitWorkspace(initialWorkspace);
      expect(
        container.read(floatingNoticeProvider)?.message,
        equals('Persistent alert'),
        reason:
            'Re-resolving the same workspace must not dismiss active notice',
      );

      // Switching to a different workspace MUST dismiss the active notice.
      await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace(
            'Personal',
            config: const WebDavConfig(
              language: AppLanguage.english,
              localFilePath: 'personal.tdf',
              filePath: 'personal.tdf',
            ),
            activate: true,
          );
      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'Switching active workspace must dismiss active notice',
      );
    });

    test('surfaces LIFO Undo notices, transitions in a single emission without flashing null, and supports explicit locale', () async {
      final firstTask = TaskItem(
        id: 'undo000001',
        title: 'Write tests',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final secondTask = TaskItem(
        id: 'undo000002',
        title: 'Ship patch',
        isPriority: true,
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final thirdTask = TaskItem(
        id: 'undo000003',
        title: 'Verify release',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[firstTask, secondTask, thirdTask],
        queueBlock: TdfQueueBlock(
          taskIds: const <String>['undo000001', 'undo000002', 'undo000003'],
        ),
        evaluationTime: fixedNow,
      );
      const config = WebDavConfig(
        language: AppLanguage.english,
        storageMode: StorageMode.local,
      );
      final localRepository = FakeLocalFileRepository(
        config: config,
        initialTdf: const TdfService().serialize(board),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          localFileRepositoryProvider.overrideWithValue(localRepository),
          supportsDesktopWindowControlsProvider.overrideWithValue(true),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final transitions = <FloatingNotice?>[];
      final subscription = container.listen(
        floatingNoticeProvider,
        (_, next) => transitions.add(next),
      );
      addTearDown(subscription.close);

      // Empty stack undoLatest returns false.
      expect(
        await container.read(floatingNoticeProvider.notifier).undoLatest(),
        isFalse,
      );

      await container
          .read(taskNotifierProvider.notifier)
          .completeTask(firstTask.id);
      expect(
        container.read(floatingNoticeProvider)?.message,
        contains('Write tests'),
      );
      await container
          .read(taskNotifierProvider.notifier)
          .downgradeTask(secondTask.id);
      expect(
        container.read(floatingNoticeProvider)?.message,
        contains('Ship patch'),
      );
      await container
          .read(taskNotifierProvider.notifier)
          .deleteTask(secondTask.id);
      final undoNotice = container.read(floatingNoticeProvider);
      expect(undoNotice?.hasUndoAction, isTrue);
      expect(undoNotice?.tone, equals(FloatingNoticeTone.accent));
      expect(
        undoNotice?.shortcutHint,
        equals('Ctrl+Z'),
        reason: 'Desktop platforms must include Ctrl+Z shortcut hint',
      );

      // Undo via SnackBar action while remaining entries stay on stack: single transition, no null flash.
      transitions.clear();
      final firstApplied = await container
          .read(floatingNoticeProvider.notifier)
          .undoLatest(locale: const Locale('en'));
      expect(firstApplied, isTrue);
      expect(
        transitions,
        hasLength(1),
        reason:
            'Undo must transition directly without emitting intermediate null',
      );
      expect(transitions.single?.message, contains('2'));

      // Drain to the final undo entry and verify single transition to final notice.
      await container
          .read(floatingNoticeProvider.notifier)
          .undoLatest(fromShortcut: true);
      transitions.clear();
      final finalApplied = await container
          .read(floatingNoticeProvider.notifier)
          .undoLatest(fromShortcut: true, locale: const Locale('de'));
      expect(finalApplied, isTrue);
      expect(
        transitions,
        hasLength(1),
        reason: 'Final Undo must transition directly without flashing null',
      );
      expect(transitions.single?.message, equals('Aktion rückgängig gemacht.'));
    });

    test('gates shortcutHint by supportsDesktopWindowControlsProvider (null on Android)', () async {
      final task = TaskItem(
        id: 'andr000001',
        title: 'Mobile task',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[task],
        queueBlock: TdfQueueBlock(taskIds: const <String>['andr000001']),
        evaluationTime: fixedNow,
      );
      const config = WebDavConfig(
        language: AppLanguage.english,
        storageMode: StorageMode.local,
      );
      final localRepository = FakeLocalFileRepository(
        config: config,
        initialTdf: const TdfService().serialize(board),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          localFileRepositoryProvider.overrideWithValue(localRepository),
          supportsDesktopWindowControlsProvider.overrideWithValue(false),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final subscription = container.listen(floatingNoticeProvider, (_, _) {});
      addTearDown(subscription.close);

      await container.read(taskNotifierProvider.notifier).deleteTask(task.id);
      final undoNotice = container.read(floatingNoticeProvider);
      expect(undoNotice?.hasUndoAction, isTrue);
      expect(
        undoNotice?.shortcutHint,
        isNull,
        reason: 'Android must never show a desktop Ctrl+Z shortcut hint',
      );
    });

    test('dismisses Undo notice cleanly when undoLastAction fails and latestNotice is null', () async {
      final task = TaskItem(
        id: 'fail000001',
        title: 'Rollback task',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[task],
        queueBlock: TdfQueueBlock(taskIds: const <String>['fail000001']),
        evaluationTime: fixedNow,
      );
      const config = WebDavConfig(
        language: AppLanguage.english,
        storageMode: StorageMode.local,
      );
      final localRepository = _FailingWriteLocalFileRepository(
        config: config,
        initialTdf: const TdfService().serialize(board),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          localFileRepositoryProvider.overrideWithValue(localRepository),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final subscription = container.listen(floatingNoticeProvider, (_, _) {});
      addTearDown(subscription.close);

      await container.read(taskNotifierProvider.notifier).deleteTask(task.id);
      expect(container.read(floatingNoticeProvider)?.hasUndoAction, isTrue);

      localRepository.failNextSave = true;
      final applied = await container
          .read(floatingNoticeProvider.notifier)
          .undoLatest();
      expect(applied, isFalse);
      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'Failed Undo with no remaining latestNotice must dismiss the Undo toast cleanly',
      );
    });
  });
}
