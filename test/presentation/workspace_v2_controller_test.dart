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
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/l10n/tier_localization_extension.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/floating_notice_controller.dart';
import 'package:tiertask/presentation/ui_v2_shell_models.dart';
import 'package:tiertask/presentation/workspace_v2_controller.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

class _ControlledSettingsRepository extends InMemorySettingsRepository {
  _ControlledSettingsRepository([super.initialConfig]);

  Completer<void>? activateGate;
  int activateCallCount = 0;
  Completer<void>? createGate;
  int createCallCount = 0;
  Completer<void>? deleteGate;
  int deleteCallCount = 0;
  Completer<void>? loadActiveGate;
  Completer<void>? loadSummariesGate;
  Object? nextError;
  Completer<void>? renameGate;
  int renameCallCount = 0;

  @override
  Future<AppWorkspace> activateWorkspace(String workspaceId) async {
    activateCallCount++;
    if (activateGate case final gate?) {
      await gate.future;
    }
    _throwIfConfigured();
    return super.activateWorkspace(workspaceId);
  }

  @override
  Future<AppWorkspace> createWorkspace(
    String name, {
    WebDavConfig? config,
    String? id,
    bool activate = false,
  }) async {
    createCallCount++;
    if (createGate case final gate?) {
      await gate.future;
    }
    _throwIfConfigured();
    return super.createWorkspace(
      name,
      config: config,
      id: id,
      activate: activate,
    );
  }

  @override
  Future<AppWorkspace> deleteWorkspace(String workspaceId) async {
    deleteCallCount++;
    if (deleteGate case final gate?) {
      await gate.future;
    }
    _throwIfConfigured();
    return super.deleteWorkspace(workspaceId);
  }

  @override
  Future<AppWorkspace> loadActiveWorkspace() async {
    if (loadActiveGate case final gate?) {
      await gate.future;
    }
    return super.loadActiveWorkspace();
  }

  @override
  Future<List<WorkspaceSummary>> loadWorkspaceSummaries() async {
    if (loadSummariesGate case final gate?) {
      await gate.future;
    }
    return super.loadWorkspaceSummaries();
  }

  @override
  Future<AppWorkspace> renameWorkspace(
    String workspaceId,
    String newName,
  ) async {
    renameCallCount++;
    if (renameGate case final gate?) {
      await gate.future;
    }
    _throwIfConfigured();
    return super.renameWorkspace(workspaceId, newName);
  }

  void _throwIfConfigured() {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }
}

void main() {
  const englishLocale = Locale('en');
  const germanLocale = Locale('de');
  final englishLocalizations = lookupAppLocalizations(englishLocale);
  final germanLocalizations = lookupAppLocalizations(germanLocale);

  ProviderContainer createContainer({
    SettingsRepository? settingsRepository,
    WebDavConfig initialConfig = const WebDavConfig(
      language: AppLanguage.english,
    ),
  }) {
    final repository =
        settingsRepository ?? InMemorySettingsRepository(initialConfig);
    return ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
  }

  Future<void> primeWorkspaceProviders(ProviderContainer container) async {
    await container.read(activeWorkspaceProvider.future);
    await container.read(workspaceSummariesProvider.future);
  }

  group('WorkspaceV2Controller view models and immutable value semantics', () {
    test('projects loading state while summaries load and resolves single default workspace row', () async {
      final repository = _ControlledSettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      final summariesGate = Completer<void>();
      repository.loadSummariesGate = summariesGate;

      final container = createContainer(settingsRepository: repository);
      addTearDown(container.dispose);

      await container.read(activeWorkspaceProvider.future);
      final loadingModel = container.read(workspacesViewModelProvider);
      expect(
        loadingModel.isLoading,
        isTrue,
        reason: 'Initial summaries load must report isLoading true',
      );
      expect(loadingModel.activeWorkspaceId, equals(AppWorkspace.defaultId));
      expect(loadingModel.maxWorkspaces, equals(AppWorkspace.maxWorkspaces));
      expect(loadingModel.canCreateMore, isTrue);

      summariesGate.complete();
      await container.read(workspaceSummariesProvider.future);

      final loadedModel = container.read(workspacesViewModelProvider);
      expect(loadedModel.isLoading, isFalse);
      expect(loadedModel.activeWorkspaceId, equals(AppWorkspace.defaultId));
      expect(loadedModel.maxWorkspaces, equals(32));
      expect(loadedModel.canCreateMore, isTrue);
      expect(loadedModel.workspaces, hasLength(1));

      final row = loadedModel.workspaces.single;
      expect(row.id, equals(AppWorkspace.defaultId));
      expect(row.name, equals(AppWorkspace.defaultName));
      expect(row.localFileName, equals('tasks.tdf'));
      expect(row.isActive, isTrue);
      expect(
        row.canDelete,
        isFalse,
        reason: 'Single remaining workspace must disable deletion',
      );
      expect(
        () => loadedModel.workspaces.add(row),
        throwsUnsupportedError,
        reason: 'WorkspacesViewModel.workspaces must be unmodifiable',
      );
    });

    test('extracts trailing .tdf filename for POSIX and Windows paths and enables deletion for multiple workspaces', () async {
      final repository = InMemorySettingsRepository(
        const WebDavConfig(
          language: AppLanguage.english,
          localFilePath: '/home/user/tiertask/tasks.tdf',
        ),
      );
      await repository.createWorkspace(
        'Work',
        config: const WebDavConfig(
          localFilePath: r'C:\Users\Stefan\Documents\work_board.tdf',
          filePath: 'work_board.tdf',
        ),
      );

      final container = createContainer(settingsRepository: repository);
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final model = container.read(workspacesViewModelProvider);
      expect(model.workspaces, hasLength(2));
      expect(model.workspaces[0].localFileName, equals('tasks.tdf'));
      expect(model.workspaces[0].isActive, isTrue);
      expect(model.workspaces[0].canDelete, isTrue);
      expect(model.workspaces[1].localFileName, equals('work_board.tdf'));
      expect(model.workspaces[1].isActive, isFalse);
      expect(model.workspaces[1].canDelete, isTrue);
    });

    test('supports value equality, hashCode, and copyWith on state and view model types', () {
      const idleState = WorkspaceV2ControllerState();
      final busyState = idleState.copyWith(isBusy: true);
      expect(idleState.isBusy, isFalse);
      expect(busyState, equals(const WorkspaceV2ControllerState(isBusy: true)));
      expect(
        busyState.hashCode,
        equals(const WorkspaceV2ControllerState(isBusy: true).hashCode),
      );
      expect(busyState.copyWith(), equals(busyState));

      const rowA = WorkspaceRowViewModel(
        id: 'tasks',
        name: 'Tasks',
        localFileName: 'tasks.tdf',
        isActive: true,
        canDelete: false,
      );
      const rowB = WorkspaceRowViewModel(
        id: 'tasks',
        name: 'Tasks',
        localFileName: 'tasks.tdf',
        isActive: true,
        canDelete: false,
      );
      expect(rowA, equals(rowB));
      expect(rowA.hashCode, equals(rowB.hashCode));

      final viewModelA = WorkspacesViewModel(
        activeWorkspaceId: 'tasks',
        workspaces: const <WorkspaceRowViewModel>[rowA],
        canCreateMore: true,
        isLoading: false,
        maxWorkspaces: 32,
      );
      final viewModelB = WorkspacesViewModel(
        activeWorkspaceId: 'tasks',
        workspaces: const <WorkspaceRowViewModel>[rowB],
        canCreateMore: true,
        isLoading: false,
        maxWorkspaces: 32,
      );
      expect(viewModelA, equals(viewModelB));
      expect(viewModelA.hashCode, equals(viewModelB.hashCode));
    });
  });

  group('WorkspaceV2Controller suggestWorkspaceFileName', () {
    test('delegates .tdf filename suggestions to AppWorkspace.suggestFileName', () {
      final container = createContainer();
      addTearDown(container.dispose);
      final controller = container.read(workspaceV2ControllerProvider.notifier);

      final samples = <String, String>{
        'Arbeit': 'arbeit.tdf',
        'Müller & Co': 'mueller_co.tdf',
        '  Side Project 2026! ': 'side_project_2026.tdf',
        '': 'workspace.tdf',
        '   ': 'workspace.tdf',
        '!!!': 'workspace.tdf',
      };
      for (final entry in samples.entries) {
        expect(
          controller.suggestWorkspaceFileName(entry.key),
          equals(entry.value),
          reason:
              'Suggested filename for "${entry.key}" must match ${entry.value}',
        );
      }
    });
  });

  group('WorkspaceV2Controller create, switch, rename, and delete flows', () {
    test('creates and activates a workspace by default and emits a surviving workspaceSwitchedNotice toast', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final noticeHistory = <FloatingNoticeViewModel?>[];
      final subscription = container.listen<FloatingNoticeViewModel?>(
        floatingNoticeControllerProvider,
        (_, next) => noticeHistory.add(next),
        fireImmediately: false,
      );
      addTearDown(subscription.close);

      final controller = container.read(workspaceV2ControllerProvider.notifier);
      final result = await controller.createWorkspace('Work');
      await container.read(workspaceSummariesProvider.future);
      await Future<void>.delayed(Duration.zero);

      final expectedNotice = englishLocalizations.workspaceSwitchedNotice(
        'Work',
      );
      expect(
        result,
        equals(
          V2ActionSucceeded(entityId: 'work', noticeMessage: expectedNotice),
        ),
      );

      final viewModel = container.read(workspacesViewModelProvider);
      expect(viewModel.activeWorkspaceId, equals('work'));
      expect(viewModel.workspaces, hasLength(2));
      expect(
        viewModel.workspaces.firstWhere((row) => row.id == 'work').isActive,
        isTrue,
      );
      expect(
        viewModel.workspaces
            .firstWhere((row) => row.id == 'work')
            .localFileName,
        equals('work.tdf'),
      );

      final activeNotice = container.read(floatingNoticeControllerProvider);
      expect(
        activeNotice?.message,
        equals(expectedNotice),
        reason: 'Toast emitted after workspace activation must survive FloatingNoticeController workspace reset',
      );
      expect(activeNotice?.tone, equals(NoticeTone.neutral));
      expect(
        noticeHistory.last?.message,
        equals(expectedNotice),
        reason: 'Listener must observe the workspace switched toast last',
      );
    });

    test('creates a workspace with activate false without changing active workspace or emitting switch toast', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final controller = container.read(workspaceV2ControllerProvider.notifier);
      final result = await controller.createWorkspace(
        'Personal',
        activate: false,
      );
      await container.read(workspaceSummariesProvider.future);

      expect(result, equals(const V2ActionSucceeded(entityId: 'personal')));
      final viewModel = container.read(workspacesViewModelProvider);
      expect(viewModel.activeWorkspaceId, equals(AppWorkspace.defaultId));
      expect(viewModel.workspaces, hasLength(2));
      expect(
        container.read(floatingNoticeControllerProvider),
        isNull,
        reason: 'Non-activating creation must not emit workspaceSwitchedNotice',
      );
    });

    test('switches workspace, updates active row, emits localized toast, and skips duplicate toast on no-op switch', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final controller = container.read(workspaceV2ControllerProvider.notifier);
      await controller.createWorkspace('Arbeit', activate: false);
      await container.read(workspaceSummariesProvider.future);

      final subscription = container.listen<FloatingNoticeViewModel?>(
        floatingNoticeControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final switchResult = await controller.switchWorkspace(
        'arbeit',
        locale: germanLocale,
      );
      await container.read(workspaceSummariesProvider.future);
      await Future<void>.delayed(Duration.zero);

      final expectedGermanNotice = germanLocalizations.workspaceSwitchedNotice(
        'Arbeit',
      );
      expect(
        switchResult,
        equals(
          V2ActionSucceeded(
            entityId: 'arbeit',
            noticeMessage: expectedGermanNotice,
          ),
        ),
      );
      expect(
        container.read(workspacesViewModelProvider).activeWorkspaceId,
        equals('arbeit'),
      );
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        equals(expectedGermanNotice),
      );

      container.read(floatingNoticeControllerProvider.notifier).dismiss();
      final noopResult = await controller.switchWorkspace('arbeit');
      expect(noopResult, equals(const V2ActionSucceeded(entityId: 'arbeit')));
      expect(
        container.read(floatingNoticeControllerProvider),
        isNull,
        reason: 'Switching to already-active workspace must not emit toast',
      );
    });

    test('renames active and inactive workspaces cleanly', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final controller = container.read(workspaceV2ControllerProvider.notifier);
      await controller.createWorkspace('Work', activate: false);
      await container.read(workspaceSummariesProvider.future);

      final renameActive = await controller.renameWorkspace(
        AppWorkspace.defaultId,
        '  Daily Tasks  ',
      );
      await container.read(workspaceSummariesProvider.future);
      expect(
        renameActive,
        equals(const V2ActionSucceeded(entityId: AppWorkspace.defaultId)),
      );
      expect(
        container.read(activeWorkspaceProvider).value?.name,
        equals('Daily Tasks'),
      );

      final renameInactive = await controller.renameWorkspace(
        'work',
        'Client Work',
      );
      await container.read(workspaceSummariesProvider.future);
      expect(renameInactive, equals(const V2ActionSucceeded(entityId: 'work')));

      final rows = container.read(workspacesViewModelProvider).workspaces;
      expect(
        rows.firstWhere((row) => row.id == AppWorkspace.defaultId).name,
        equals('Daily Tasks'),
      );
      expect(
        rows.firstWhere((row) => row.id == 'work').name,
        equals('Client Work'),
      );
    });

    test('deletes inactive workspace and falls back cleanly when deleting active workspace', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final controller = container.read(workspaceV2ControllerProvider.notifier);
      await controller.createWorkspace('Work', activate: false);
      await controller.createWorkspace('Home', activate: true);
      await container.read(workspaceSummariesProvider.future);

      final deleteInactive = await controller.deleteWorkspace('work');
      await container.read(workspaceSummariesProvider.future);
      expect(deleteInactive, equals(const V2ActionSucceeded(entityId: 'home')));
      expect(
        container.read(workspacesViewModelProvider).workspaces,
        hasLength(2),
      );

      final deleteActive = await controller.deleteWorkspace('home');
      await container.read(workspaceSummariesProvider.future);
      expect(
        deleteActive,
        equals(const V2ActionSucceeded(entityId: AppWorkspace.defaultId)),
      );

      final finalModel = container.read(workspacesViewModelProvider);
      expect(finalModel.activeWorkspaceId, equals(AppWorkspace.defaultId));
      expect(finalModel.workspaces, hasLength(1));
      expect(finalModel.workspaces.single.canDelete, isFalse);
    });
  });

  group('WorkspaceV2Controller validation bounds and error localization', () {
    test('rejects empty, control-character, oversized, duplicate-name, and duplicate-path creations', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final controller = container.read(workspaceV2ControllerProvider.notifier);

      final invalidNames = <String>[
        '',
        '   ',
        'Bad\nName',
        'A' * (AppWorkspace.maxNameLength + 1),
      ];
      for (final invalidName in invalidNames) {
        final result = await controller.createWorkspace(
          invalidName,
          locale: englishLocale,
        );
        expect(
          result,
          equals(
            V2ActionValidationFailed(
              message: englishLocalizations.errorWorkspaceNameEmpty,
            ),
          ),
          reason:
              'Invalid name length=${invalidName.length} must fail validation',
        );
      }

      final germanEmpty = await controller.createWorkspace(
        '   ',
        locale: germanLocale,
      );
      expect(
        germanEmpty,
        equals(
          V2ActionValidationFailed(
            message: germanLocalizations.errorWorkspaceNameEmpty,
          ),
        ),
      );

      final duplicateName = await controller.createWorkspace(
        '  tAsKs  ',
        locale: englishLocale,
      );
      expect(
        duplicateName,
        equals(
          V2ActionValidationFailed(
            message: englishLocalizations.errorWorkspaceNameDuplicate,
          ),
        ),
      );

      final firstCustom = await controller.createWorkspace(
        'My Work',
        activate: false,
      );
      expect(firstCustom, isA<V2ActionSucceeded>());

      final duplicatePath = await controller.createWorkspace(
        'My-Work',
        locale: englishLocale,
      );
      expect(
        duplicatePath,
        equals(
          V2ActionValidationFailed(
            message: englishLocalizations.errorDuplicateWorkspaceFilePath,
          ),
        ),
        reason: 'Distinct display name deriving colliding .tdf filename must report duplicateFilePath',
      );
    });

    test('enforces AppWorkspace.maxWorkspaces = 32 boundary at N-1, N, and N+1', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final controller = container.read(workspaceV2ControllerProvider.notifier);
      for (var i = 2; i < AppWorkspace.maxWorkspaces; i++) {
        final created = await controller.createWorkspace(
          'Board $i',
          activate: false,
        );
        expect(
          created,
          isA<V2ActionSucceeded>(),
          reason: 'Creating workspace $i of 32 must succeed',
        );
      }
      await container.read(workspaceSummariesProvider.future);
      expect(
        container.read(workspacesViewModelProvider).workspaces,
        hasLength(AppWorkspace.maxWorkspaces - 1),
        reason: 'N-1 (31) workspaces must allow creating one more',
      );
      expect(container.read(workspacesViewModelProvider).canCreateMore, isTrue);

      final thirtySecond = await controller.createWorkspace(
        'Board 32',
        activate: false,
      );
      await container.read(workspaceSummariesProvider.future);
      expect(
        thirtySecond,
        isA<V2ActionSucceeded>(),
        reason: 'Creating the 32nd workspace (N) must succeed',
      );

      final atLimitModel = container.read(workspacesViewModelProvider);
      expect(atLimitModel.workspaces, hasLength(AppWorkspace.maxWorkspaces));
      expect(atLimitModel.canCreateMore, isFalse);

      final thirtyThird = await controller.createWorkspace(
        'Board 33',
        locale: englishLocale,
      );
      expect(
        thirtyThird,
        equals(
          V2ActionValidationFailed(
            message: englishLocalizations.errorWorkspaceMaxExceeded,
          ),
        ),
        reason:
            'Creating workspace 33 (N+1) must fail with maxWorkspacesExceeded',
      );
    });

    test('rejects deleting the last remaining workspace and validates rename and missing ID errors', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final controller = container.read(workspaceV2ControllerProvider.notifier);

      final deleteLastEnglish = await controller.deleteWorkspace(
        AppWorkspace.defaultId,
        locale: englishLocale,
      );
      expect(
        deleteLastEnglish,
        equals(
          V2ActionValidationFailed(
            message: englishLocalizations.errorWorkspaceCannotDeleteLast,
          ),
        ),
      );

      final deleteLastGerman = await controller.deleteWorkspace(
        AppWorkspace.defaultId,
        locale: germanLocale,
      );
      expect(
        deleteLastGerman,
        equals(
          V2ActionValidationFailed(
            message: germanLocalizations.errorWorkspaceCannotDeleteLast,
          ),
        ),
      );

      await controller.createWorkspace('Work', activate: false);

      final renameDuplicate = await controller.renameWorkspace(
        'work',
        'tasks',
        locale: englishLocale,
      );
      expect(
        renameDuplicate,
        equals(
          V2ActionValidationFailed(
            message: englishLocalizations.errorWorkspaceNameDuplicate,
          ),
        ),
      );

      final renameEmpty = await controller.renameWorkspace(
        'work',
        '   ',
        locale: englishLocale,
      );
      expect(
        renameEmpty,
        equals(
          V2ActionValidationFailed(
            message: englishLocalizations.errorWorkspaceNameEmpty,
          ),
        ),
      );

      final switchMissing = await controller.switchWorkspace('missing_id');
      expect(switchMissing, isA<V2ActionValidationFailed>());

      final renameMissing = await controller.renameWorkspace(
        'missing_id',
        'Valid Name',
      );
      expect(renameMissing, isA<V2ActionValidationFailed>());

      final deleteMissing = await controller.deleteWorkspace('missing_id');
      expect(deleteMissing, isA<V2ActionValidationFailed>());
    });

    test(
      'maps every WorkspaceErrorKind and unexpected exceptions exhaustively',
      () async {
        final repository = _ControlledSettingsRepository(
          const WebDavConfig(language: AppLanguage.english),
        );
        final container = createContainer(settingsRepository: repository);
        addTearDown(container.dispose);
        await primeWorkspaceProviders(container);

        final controller = container.read(
          workspaceV2ControllerProvider.notifier,
        );

        for (final kind in WorkspaceErrorKind.values) {
          final exception = WorkspaceException(kind, 'Synthetic $kind');
          repository.nextError = exception;
          final result = await controller.createWorkspace(
            'Probe ${kind.name}',
            locale: englishLocale,
          );
          final expectedMessage = englishLocalizations.localizeWorkspaceError(
            exception,
          );
          final isPersistenceError = switch (kind) {
            WorkspaceErrorKind.corruptSettingsPayload ||
            WorkspaceErrorKind.unsupportedSettingsSchemaVersion ||
            WorkspaceErrorKind.credentialStorageUnavailable ||
            WorkspaceErrorKind.settingsPersistenceFailed => true,
            WorkspaceErrorKind.emptyName ||
            WorkspaceErrorKind.duplicateName ||
            WorkspaceErrorKind.duplicateFilePath ||
            WorkspaceErrorKind.invalidFilePath ||
            WorkspaceErrorKind.workspaceNotFound ||
            WorkspaceErrorKind.cannotDeleteLastWorkspace ||
            WorkspaceErrorKind.maxWorkspacesExceeded => false,
          };
          if (isPersistenceError) {
            expect(
              result,
              equals(V2ActionPersistFailed(message: expectedMessage)),
              reason: '$kind must map to V2ActionPersistFailed',
            );
          } else {
            expect(
              result,
              equals(V2ActionValidationFailed(message: expectedMessage)),
              reason: '$kind must map to V2ActionValidationFailed',
            );
          }
          expect(
            container.read(workspaceV2ControllerProvider).isBusy,
            isFalse,
            reason: 'isBusy must reset after $kind error',
          );
        }

        repository.nextError = Exception(
          'raw internal path /secret/settings.json',
        );
        final unexpectedResult = await controller.createWorkspace(
          'Probe Unexpected',
          locale: englishLocale,
        );
        expect(
          unexpectedResult,
          equals(
            V2ActionPersistFailed(
              message: englishLocalizations.errorSettingsSaveFailed,
            ),
          ),
          reason: 'Unexpected exceptions must return sanitized localized error',
        );
        expect(container.read(workspaceV2ControllerProvider).isBusy, isFalse);
      },
    );
  });

  group('WorkspaceV2Controller mid-flight busy guard and disposal safety', () {
    test('blocks concurrent mutations while an async workspace operation is in flight and resets isBusy on completion', () async {
      final repository = _ControlledSettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      await repository.createWorkspace('Work', activate: false);

      final container = createContainer(settingsRepository: repository);
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final gate = Completer<void>();
      repository.activateGate = gate;
      repository.activateCallCount = 0;
      repository.createCallCount = 0;
      repository.renameCallCount = 0;
      repository.deleteCallCount = 0;

      final controller = container.read(workspaceV2ControllerProvider.notifier);
      final inFlightSwitch = controller.switchWorkspace('work');

      expect(
        container.read(workspaceV2ControllerProvider).isBusy,
        isTrue,
        reason:
            'Controller must enter isBusy while switchWorkspace is suspended',
      );

      final blockedSwitch = await controller.switchWorkspace('tasks');
      final blockedCreate = await controller.createWorkspace('Other');
      final blockedRename = await controller.renameWorkspace('work', 'Renamed');
      final blockedDelete = await controller.deleteWorkspace('work');

      expect(blockedSwitch, isA<V2ActionValidationFailed>());
      expect(blockedCreate, isA<V2ActionValidationFailed>());
      expect(blockedRename, isA<V2ActionValidationFailed>());
      expect(blockedDelete, isA<V2ActionValidationFailed>());
      expect(
        repository.activateCallCount,
        equals(1),
        reason: 'Concurrent switch must not reach repository while busy',
      );
      expect(repository.createCallCount, equals(0));
      expect(repository.renameCallCount, equals(0));
      expect(repository.deleteCallCount, equals(0));

      gate.complete();
      final completedResult = await inFlightSwitch;
      expect(completedResult, isA<V2ActionSucceeded>());
      expect(
        container.read(workspaceV2ControllerProvider).isBusy,
        isFalse,
        reason: 'isBusy must clear after in-flight mutation completes',
      );

      final followUp = await controller.renameWorkspace('work', 'Work 2');
      expect(followUp, equals(const V2ActionSucceeded(entityId: 'work')));
      expect(repository.renameCallCount, equals(1));
    });

    test('completes safely without throwing when ProviderContainer disposes mid-flight', () async {
      final repository = _ControlledSettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      final container = createContainer(settingsRepository: repository);
      await primeWorkspaceProviders(container);

      final gate = Completer<void>();
      repository.createGate = gate;

      final controller = container.read(workspaceV2ControllerProvider.notifier);
      final inFlightCreate = controller.createWorkspace(
        'Disposed Target',
        locale: englishLocale,
      );
      expect(container.read(workspaceV2ControllerProvider).isBusy, isTrue);

      container.dispose();
      gate.complete();

      final result = await inFlightCreate;
      expect(
        result,
        equals(
          V2ActionPersistFailed(
            message: englishLocalizations.errorSettingsSaveFailed,
          ),
        ),
        reason: 'Mid-flight container disposal must not throw UnmountedRefException',
      );
    });

    test(
      'clears isBusy when a suspended mutation fails with WorkspaceException',
      () async {
        final repository = _ControlledSettingsRepository(
          const WebDavConfig(language: AppLanguage.english),
        );
        final container = createContainer(settingsRepository: repository);
        addTearDown(container.dispose);
        await primeWorkspaceProviders(container);

        final gate = Completer<void>();
        repository.deleteGate = gate;

        final controller = container.read(
          workspaceV2ControllerProvider.notifier,
        );
        final inFlightDelete = controller.deleteWorkspace(
          AppWorkspace.defaultId,
          locale: englishLocale,
        );
        expect(container.read(workspaceV2ControllerProvider).isBusy, isTrue);

        gate.complete();
        final result = await inFlightDelete;
        expect(
          result,
          equals(
            V2ActionValidationFailed(
              message: englishLocalizations.errorWorkspaceCannotDeleteLast,
            ),
          ),
        );
        expect(
          container.read(workspaceV2ControllerProvider).isBusy,
          isFalse,
          reason: 'isBusy must clear after suspended mutation throws',
        );
      },
    );
  });
}
