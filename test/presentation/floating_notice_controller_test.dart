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
import 'package:tiertask/presentation/floating_notice_controller.dart';
import 'package:tiertask/presentation/shell_models.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/tdf_service.dart';

import '../ui/test_helpers.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixedNow = DateTime.utc(2026, 11, 10, 12, 0);

  group('FloatingNoticeController', () {
    test('consumes early-resolved startup recovery notice once as persistent warning toast', () async {
      final settingsRepo = InMemorySettingsRepository.withRecoveryNotice(
        initialConfig: const WebDavConfig(language: AppLanguage.english),
        recoveryNotice: const SettingsRecoveryNotice(
          kind: SettingsRecoveryKind.recoveredFromBackup,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          clockProvider.overrideWithValue(() => fixedNow),
          taskNotifierProvider.overrideWith(
            () => FakeTaskNotifier(TaskBoard.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activeWorkspaceProvider.future);
      final subscription = container.listen(
        floatingNoticeControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final notice = container.read(floatingNoticeControllerProvider);
      expect(
        notice,
        isNotNull,
        reason: 'Early-resolved workspace must surface pending recovery notice immediately',
      );
      expect(notice?.persistent, isTrue);
      expect(notice?.tone, equals(NoticeTone.warning));
      expect(
        notice?.message,
        equals('Settings were restored from backup after a file error.'),
      );
      expect(
        settingsRepo.takeLastRecoveryNotice(),
        isNull,
        reason: 'One-shot startup recovery notice must be consumed once',
      );

      // Calling showStartupRecoveryNoticeIfPending again must remain idempotent.
      container
          .read(floatingNoticeControllerProvider.notifier)
          .showStartupRecoveryNoticeIfPending();
      expect(container.read(floatingNoticeControllerProvider), equals(notice));
    });

    test('consumes async-resolved startup recovery notice when activeWorkspaceProvider completes later', () async {
      final loadGate = Completer<void>();
      final settingsRepo = _DelayedRecoverySettingsRepository(
        initialConfig: const WebDavConfig(language: AppLanguage.english),
        onLoad: () => loadGate.future,
        recoveryNotice: const SettingsRecoveryNotice(
          kind: SettingsRecoveryKind.resetAfterQuarantine,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          clockProvider.overrideWithValue(() => fixedNow),
          taskNotifierProvider.overrideWith(
            () => FakeTaskNotifier(TaskBoard.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notices = <FloatingNoticeViewModel?>[];
      final subscription = container.listen(
        floatingNoticeControllerProvider,
        (_, next) => notices.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      // Initial check while activeWorkspaceProvider is still AsyncLoading emits nothing.
      container
          .read(floatingNoticeControllerProvider.notifier)
          .showStartupRecoveryNoticeIfPending();
      expect(
        container.read(floatingNoticeControllerProvider),
        isNull,
        reason: 'No recovery notice should display before async workspace finishes loading',
      );

      loadGate.complete();
      await container.read(activeWorkspaceProvider.future);

      final notice = container.read(floatingNoticeControllerProvider);
      expect(
        notice,
        isNotNull,
        reason: 'Async workspace resolution must consume pending startup recovery notice automatically',
      );
      expect(notice?.persistent, isTrue);
      expect(notice?.tone, equals(NoticeTone.warning));
      expect(
        notice?.message,
        equals('Corrupt settings were backed up and reset to defaults.'),
      );
      expect(notices.last, equals(notice));
    });

    test('auto-hides standard notices, retains persistent notices, and clears active notices on workspace switch', () async {
      final settingsRepo = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          clockProvider.overrideWithValue(() => fixedNow),
          taskNotifierProvider.overrideWith(
            () => FakeTaskNotifier(TaskBoard.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);

      final subscription = container.listen(
        floatingNoticeControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final notifier = container.read(
        floatingNoticeControllerProvider.notifier,
      );
      notifier.showNotice(
        'Short toast',
        duration: const Duration(milliseconds: 20),
      );
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        equals('Short toast'),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(floatingNoticeControllerProvider),
        isNull,
        reason: 'Timed notice must auto-hide once duration elapses',
      );

      notifier.showNotice(
        'Persistent alert',
        tone: NoticeTone.warning,
        persistent: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        equals('Persistent alert'),
      );

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
        container.read(floatingNoticeControllerProvider),
        isNull,
        reason: 'Switching active workspace must dismiss active notice',
      );
    });

    test(
      'surfaces LIFO Undo notices and executes undoLatest with explicit locale',
      () async {
        final task = TaskItem(
          id: 'undo000001',
          title: 'Write tests',
          createdAt: fixedNow,
          modifiedAt: fixedNow,
        );
        final board = TaskBoard.evaluate(
          tasks: <TaskItem>[task],
          queueBlock: TdfQueueBlock(taskIds: const <String>['undo000001']),
          evaluationTime: fixedNow,
        );
        const config = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.local,
        );
        final localRepo = FakeLocalFileRepository(
          config: config,
          initialTdf: const TdfService().serialize(board),
        );
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(config),
            ),
            localFileRepositoryProvider.overrideWithValue(localRepo),
            clockProvider.overrideWithValue(() => fixedNow),
          ],
        );
        addTearDown(container.dispose);
        await container.read(taskNotifierProvider.future);

        final subscription = container.listen(
          floatingNoticeControllerProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);

        await container.read(taskNotifierProvider.notifier).deleteTask(task.id);
        final undoNotice = container.read(floatingNoticeControllerProvider);
        expect(undoNotice?.hasUndoAction, isTrue);
        expect(undoNotice?.tone, equals(NoticeTone.accent));

        final applied = await container
            .read(floatingNoticeControllerProvider.notifier)
            .undoLatest(locale: const Locale('de'));
        expect(applied, isTrue);
        expect(
          container.read(floatingNoticeControllerProvider)?.message,
          equals('Aktion rückgängig gemacht.'),
        );
      },
    );
  });
}
