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
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/board_v2_view_models.dart';
import 'package:tiertask/presentation/entity_v2_controller.dart';
import 'package:tiertask/presentation/workspace_v2_controller.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/tdf_service.dart';
import 'package:tiertask/ui_v2/dialogs/app_modals.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../ui/test_helpers.dart';
import 'test_helpers.dart';

class _ControlledLocationRepository implements LocationRepository {
  _ControlledLocationRepository({
    this.initialFix,
    this.refreshedFix,
    this.refreshGate,
  });

  final LocationFix? initialFix;
  final LocationFix? refreshedFix;
  Completer<void>? refreshGate;
  int determineCalls = 0;
  bool lastForceRefresh = false;

  @override
  Future<LocationFix?> determineLocation({bool forceRefresh = false}) async {
    determineCalls++;
    lastForceRefresh = forceRefresh;
    if (forceRefresh) {
      if (refreshGate case final gate?) {
        await gate.future;
      }
      return refreshedFix ?? initialFix;
    }
    return initialFix;
  }

  @override
  Future<List<GeocodingCandidate>> searchLocations(String query) async =>
      const <GeocodingCandidate>[];
}

class _ListingLocalFileRepository extends FakeLocalFileRepository {
  _ListingLocalFileRepository({
    required super.config,
    required this.existingFileNames,
    super.initialTdf = 'tdf 0.8.0\n',
  });

  final List<String> existingFileNames;

  @override
  List<String> listTdfFileNamesInDirectory() => existingFileNames;
}

class _ModalHost extends StatelessWidget {
  const _ModalHost({required this.onTrigger});

  final Future<void> Function(BuildContext context) onTrigger;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: UiButton(
          key: const ValueKey<String>('open_modal_trigger'),
          label: 'Open Modal',
          onPressed: () async {
            await onTrigger(context);
          },
        ),
      ),
    );
  }
}

class _SpyTaskNotifier extends FakeTaskNotifier {
  _SpyTaskNotifier();

  final List<String> selectedPaths = <String>[];
  final List<({bool isRemote, bool createBackup, String path})> wipeCalls =
      <({bool isRemote, bool createBackup, String path})>[];

  @override
  Future<void> selectLocalFile(WebDavConfig newConfig) async {
    selectedPaths.add(newConfig.localFilePath);
  }

  @override
  Future<void> wipeLocalFile(
    WebDavConfig config, {
    bool createBackup = false,
  }) async {
    wipeCalls.add((
      isRemote: false,
      createBackup: createBackup,
      path: config.localFilePath,
    ));
  }

  @override
  Future<void> wipeRemoteFile(
    WebDavConfig config, {
    bool createBackup = false,
  }) async {
    wipeCalls.add((
      isRemote: true,
      createBackup: createBackup,
      path: config.filePath,
    ));
  }
}

void main() {
  final localizations = lookupAppLocalizations(const Locale('en'));

  group('showWorkspacesModal', () {
    testWidgets(
      'creates workspace with live suggested .tdf filename and disables delete for single workspace',
      (tester) async {
        final settingsRepository = InMemorySettingsRepository(
          const WebDavConfig(language: AppLanguage.english),
        );
        final container = await pumpV2Widget(
          tester,
          const _ModalHost(onTrigger: showWorkspacesModal),
          settingsRepository: settingsRepository,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('workspaces_modal')),
          findsOneWidget,
        );
        expect(find.text(localizations.workspacesDialogTitle), findsOneWidget);
        expect(find.text(localizations.workspaceActiveBadge), findsOneWidget);
        expect(find.text(WebDavConfig.defaultFileName), findsOneWidget);

        final singleDeleteButton = tester.widget<UiButton>(
          find.byKey(
            const ValueKey<String>(
              'workspace_delete_button_${AppWorkspace.defaultId}',
            ),
          ),
        );
        expect(singleDeleteButton.onPressed, isNull);

        await tester.enterText(
          find.byKey(const ValueKey<String>('workspace_create_field')),
          'Work Projects',
        );
        await tester.pump();

        expect(
          find.text(
            localizations.workspaceSuggestedFileLabel('work_projects.tdf'),
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('workspace_create_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('workspaces_modal')),
          findsNothing,
        );
        final viewModel = container.read(workspacesViewModelProvider);
        expect(viewModel.workspaces.length, 2);
        expect(
          viewModel.workspaces.any(
            (row) => row.name == 'Work Projects' && row.isActive,
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'switches, renames inline, shows duplicate error, and confirms inline delete with multiple workspaces',
      (tester) async {
        final settingsRepository = InMemorySettingsRepository(
          const WebDavConfig(language: AppLanguage.english),
        );
        final created = await settingsRepository.createWorkspace(
          'Work',
          activate: false,
        );

        final container = await pumpV2Widget(
          tester,
          const _ModalHost(onTrigger: showWorkspacesModal),
          settingsRepository: settingsRepository,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        // Duplicate creation shows inline error banner and keeps modal open.
        await tester.enterText(
          find.byKey(const ValueKey<String>('workspace_create_field')),
          'Work',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey<String>('workspace_create_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('workspaces_modal')),
          findsOneWidget,
        );
        expect(
          find.text(localizations.errorWorkspaceNameDuplicate),
          findsOneWidget,
        );

        // Inline rename updates workspace name on Enter.
        await tester.tap(
          find.byKey(ValueKey<String>('workspace_rename_button_${created.id}')),
        );
        await tester.pumpAndSettle();

        final renameField = find.byKey(
          ValueKey<String>('workspace_rename_field_${created.id}'),
        );
        expect(renameField, findsOneWidget);
        await tester.enterText(renameField, 'Client Work');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.text('Client Work'), findsOneWidget);

        // Tapping inactive workspace row switches active workspace and closes modal.
        await tester.tap(
          find.byKey(ValueKey<String>('workspace_select_${created.id}')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('workspaces_modal')),
          findsNothing,
        );
        expect(
          container.read(workspacesViewModelProvider).activeWorkspaceId,
          created.id,
        );

        // Reopen modal and delete the workspace via inline confirmation banner.
        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(ValueKey<String>('workspace_delete_button_${created.id}')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(localizations.deleteWorkspaceConfirmMessage('Client Work')),
          findsOneWidget,
        );

        await tester.tap(
          find.widgetWithText(UiButton, localizations.actionDelete),
        );
        await tester.pumpAndSettle();

        expect(find.text('Client Work'), findsNothing);
        expect(
          container.read(workspacesViewModelProvider).workspaces.length,
          1,
        );
      },
    );

    testWidgets(
      'disables workspace create controls when maxWorkspaces limit is reached',
      (tester) async {
        final settingsRepository = InMemorySettingsRepository(
          const WebDavConfig(language: AppLanguage.english),
        );
        for (var i = 1; i < AppWorkspace.maxWorkspaces; i++) {
          await settingsRepository.createWorkspace('Workspace $i');
        }

        await pumpV2Widget(
          tester,
          const _ModalHost(onTrigger: showWorkspacesModal),
          settingsRepository: settingsRepository,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        final createField = tester.widget<UiField>(
          find.byKey(const ValueKey<String>('workspace_create_field')),
        );
        final createButton = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('workspace_create_button')),
        );
        expect(createField.enabled, isFalse);
        expect(createButton.onPressed, isNull);
        expect(
          find.text(localizations.errorWorkspaceMaxExceeded),
          findsOneWidget,
        );
      },
    );
  });

  group('showLocationStatusModal', () {
    testWidgets(
      'renders place, 6dp GPS coordinates, source, mid-flight refresh state, and updated fix',
      (tester) async {
        final refreshGate = Completer<void>();
        final locationRepository = _ControlledLocationRepository(
          initialFix: const LocationFix(
            placeName: 'Erfurt',
            latitude: 50.9787,
            longitude: 11.03283,
            source: LocationSource.gps,
          ),
          refreshedFix: const LocationFix(
            placeName: 'Berlin',
            latitude: 52.52,
            longitude: 13.405,
            source: LocationSource.system,
          ),
          refreshGate: refreshGate,
        );

        await pumpV2Widget(
          tester,
          const _ModalHost(onTrigger: showLocationStatusModal),
          config: const WebDavConfig(
            language: AppLanguage.english,
            locationEnabled: true,
          ),
          locationRepository: locationRepository,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('location_status_modal')),
          findsOneWidget,
        );
        expect(find.text(localizations.locationDialogTitle), findsOneWidget);
        expect(find.text(localizations.locationStatusFound), findsOneWidget);
        expect(find.text('Erfurt'), findsOneWidget);
        expect(find.text('50.978700, 11.032830'), findsOneWidget);
        expect(find.text(localizations.locationSourceGps), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('location_status_refresh_button')),
        );
        await tester.pump();

        // Mid-flight frame reflects loading refresh state.
        final refreshingButton = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('location_status_refresh_button')),
        );
        expect(refreshingButton.isLoading, isTrue);
        expect(refreshingButton.onPressed, isNull);
        expect(
          find.text(localizations.locationStatusSearching),
          findsOneWidget,
        );

        refreshGate.complete();
        await tester.pumpAndSettle();

        expect(locationRepository.lastForceRefresh, isTrue);
        expect(find.text('Berlin'), findsOneWidget);
        expect(find.text('52.520000, 13.405000'), findsOneWidget);
        expect(find.text(localizations.locationSourceSystem), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('location_status_close_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('location_status_modal')),
          findsNothing,
        );
      },
    );

    testWidgets('renders unavailable pill and hides detail wells without fix', (
      tester,
    ) async {
      await pumpV2Widget(
        tester,
        const _ModalHost(onTrigger: showLocationStatusModal),
        config: const WebDavConfig(
          language: AppLanguage.english,
          locationEnabled: true,
        ),
        locationRepository: _ControlledLocationRepository(),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('open_modal_trigger')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(localizations.locationStatusUnavailable),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('location_status_place')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('location_status_coordinates')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('location_status_source')),
        findsNothing,
      );
    });
  });

  group('showSelectLocalFileModal & showRenameLocalFileModal', () {
    testWidgets(
      'selects existing file, submits new filename, validates invalid input, and closes on two-step Escape',
      (tester) async {
        final spyNotifier = _SpyTaskNotifier();
        const config = WebDavConfig(
          language: AppLanguage.english,
          localFilePath: 'tasks.tdf',
        );
        final listingRepository = _ListingLocalFileRepository(
          config: config,
          existingFileNames: const <String>[
            'alpha.tdf',
            'tasks.tdf',
            'work.tdf',
          ],
        );

        await pumpV2Widget(
          tester,
          const _ModalHost(onTrigger: showSelectLocalFileModal),
          config: config,
          localFileRepository: listingRepository,
          taskNotifierFactory: () => spyNotifier,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('select_local_file_modal')),
          findsOneWidget,
        );
        expect(find.text('alpha.tdf'), findsOneWidget);
        expect(find.text('work.tdf'), findsOneWidget);

        // Invalid path traversal displays inline error and prevents dismissal.
        await tester.enterText(
          find.byKey(const ValueKey<String>('select_local_file_input')),
          '../escape.tdf',
        );
        await tester.pump();
        expect(
          find.text(localizations.localFileNameErrorInvalid),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(
            const ValueKey<String>('select_local_file_confirm_button'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('select_local_file_modal')),
          findsOneWidget,
        );
        expect(spyNotifier.selectedPaths, isEmpty);

        // Tapping an existing picker option populates the input and commits cleanly.
        await tester.tap(
          find.byKey(const ValueKey<String>('picker_opt_work.tdf')),
        );
        await tester.pump();

        await tester.tap(
          find.byKey(
            const ValueKey<String>('select_local_file_confirm_button'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('select_local_file_modal')),
          findsNothing,
        );
        expect(spyNotifier.selectedPaths, contains('work.tdf'));

        // Reopen and enter a brand-new filename submitted via Enter.
        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('select_local_file_input')),
          'personal_notes',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('select_local_file_modal')),
          findsNothing,
        );
        expect(spyNotifier.selectedPaths, contains('personal_notes.tdf'));

        // Reopen and verify two-step Escape from picker search field dismisses via onRequestClose.
        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        final searchField = find.descendant(
          of: find.byKey(const ValueKey<String>('select_local_file_picker')),
          matching: find.byType(TextField),
        );
        await tester.tap(searchField);
        await tester.pump();
        await tester.enterText(searchField, 'work');
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('select_local_file_modal')),
          findsOneWidget,
        );
        expect(find.text('alpha.tdf'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('select_local_file_modal')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'renames local .tdf file, validates bad input, and dismisses on Escape',
      (tester) async {
        final tempDirectory = Directory.systemTemp.createTempSync(
          'tiertask_rename_',
        );
        addTearDown(() {
          if (tempDirectory.existsSync()) {
            tempDirectory.deleteSync(recursive: true);
          }
        });
        final sourcePath = '${tempDirectory.path}/tasks.tdf';
        File(sourcePath)
            .writeAsStringSync('tdf ${TdfService.supportedVersion}\n');

        final config = WebDavConfig(
          language: AppLanguage.english,
          localFilePath: sourcePath,
        );

        await pumpV2Widget(
          tester,
          _ModalHost(
            onTrigger: (context) =>
                showRenameLocalFileModal(context, currentFileName: 'tasks.tdf'),
          ),
          config: config,
          localFileRepository: LocalFileRepository(config: config),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('rename_local_file_modal')),
          findsOneWidget,
        );
        expect(
          find.text(localizations.renameLocalDialogDescription('tasks.tdf')),
          findsOneWidget,
        );

        final inputField = find.byKey(
          const ValueKey<String>('rename_local_file_input'),
        );
        await tester.enterText(inputField, 'bad/name');
        await tester.pump();
        expect(
          find.text(localizations.localFileNameErrorInvalid),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('rename_local_file_modal')),
          findsNothing,
        );
        expect(File(sourcePath).existsSync(), isTrue);

        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        await tester.enterText(inputField, 'renamed_board');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('rename_local_file_modal')),
          findsNothing,
        );
        expect(
          File('${tempDirectory.path}/renamed_board.tdf').existsSync(),
          isTrue,
        );
      },
    );
  });

  group('showWipeTdfModal', () {
    testWidgets(
      'enforces U-UX-005 typed-filename guard and default-checked backup toggle for local wipe',
      (tester) async {
        final spyNotifier = _SpyTaskNotifier();
        const config = WebDavConfig(
          language: AppLanguage.english,
          localFilePath: 'tasks.tdf',
        );

        await pumpV2Widget(
          tester,
          _ModalHost(
            onTrigger: (context) => showWipeTdfModal(
              context,
              isRemote: false,
              fileName: 'tasks.tdf',
              baseName: 'tasks',
            ),
          ),
          config: config,
          taskNotifierFactory: () => spyNotifier,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Switch), findsNothing);
        expect(find.text(localizations.wipeLocalDialogTitle), findsOneWidget);

        final backupToggle = tester.widget<UiToggleRow>(
          find.byKey(const ValueKey<String>('wipe_tdf_backup_toggle')),
        );
        expect(backupToggle.value, isTrue);

        UiButton confirmButton() => tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('wipe_tdf_confirm_button')),
        );
        expect(confirmButton().onPressed, isNull);

        for (final invalidText in const <String>[
          'task',
          'tasks.tdf',
          'TASKS',
        ]) {
          await tester.enterText(
            find.byKey(const ValueKey<String>('wipe_tdf_confirm_input')),
            invalidText,
          );
          await tester.pump();
          expect(
            confirmButton().onPressed,
            isNull,
            reason: 'Expected Wipe File to remain disabled for "$invalidText"',
          );
        }

        await tester.enterText(
          find.byKey(const ValueKey<String>('wipe_tdf_confirm_input')),
          '  tasks  ',
        );
        await tester.pump();
        expect(confirmButton().onPressed, isNotNull);

        await tester.tap(
          find.byKey(const ValueKey<String>('wipe_tdf_confirm_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('wipe_local_tdf_modal')),
          findsNothing,
        );
        expect(spyNotifier.wipeCalls, hasLength(1));
        expect(spyNotifier.wipeCalls.single.isRemote, isFalse);
        expect(spyNotifier.wipeCalls.single.createBackup, isTrue);
      },
    );

    testWidgets('supports remote wipe with backup toggled off', (tester) async {
      final spyNotifier = _SpyTaskNotifier();
      const config = WebDavConfig(
        language: AppLanguage.english,
        storageMode: StorageMode.webdav,
        serverUrl: 'https://cloud.example.com/remote.php/dav/files/alice',
        username: 'alice',
        password: 'secret',
        filePath: 'remote_tasks.tdf',
      );

      await pumpV2Widget(
        tester,
        _ModalHost(
          onTrigger: (context) => showWipeTdfModal(
            context,
            isRemote: true,
            fileName: 'remote_tasks.tdf',
            baseName: 'remote_tasks',
          ),
        ),
        config: config,
        taskNotifierFactory: () => spyNotifier,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('open_modal_trigger')),
      );
      await tester.pumpAndSettle();

      expect(find.text(localizations.wipeRemoteDialogTitle), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('wipe_tdf_backup_toggle')),
      );
      await tester.pump();

      final backupToggle = tester.widget<UiToggleRow>(
        find.byKey(const ValueKey<String>('wipe_tdf_backup_toggle')),
      );
      expect(backupToggle.value, isFalse);

      await tester.enterText(
        find.byKey(const ValueKey<String>('wipe_tdf_confirm_input')),
        'remote_tasks',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('wipe_remote_tdf_modal')),
        findsNothing,
      );
      expect(spyNotifier.wipeCalls, hasLength(1));
      expect(spyNotifier.wipeCalls.single.isRemote, isTrue);
      expect(spyNotifier.wipeCalls.single.createBackup, isFalse);
    });

    testWidgets(
      'keeps modal open and shows error when remote wipe is unconfigured',
      (tester) async {
        await pumpV2Widget(
          tester,
          _ModalHost(
            onTrigger: (context) => showWipeTdfModal(
              context,
              isRemote: true,
              fileName: 'tasks.tdf',
              baseName: 'tasks',
            ),
          ),
          config: const WebDavConfig(
            language: AppLanguage.english,
            storageMode: StorageMode.local,
          ),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('wipe_tdf_confirm_input')),
          'tasks',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey<String>('wipe_tdf_confirm_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('wipe_remote_tdf_modal')),
          findsOneWidget,
        );
        expect(
          find.text(localizations.errorWebDavNotConfigured),
          findsOneWidget,
        );
      },
    );
  });

  group('showGeocodingCandidatesModal', () {
    testWidgets('returns selected candidate index on tap and null on cancel', (
      tester,
    ) async {
      int? chosenIndex = -1;
      const candidates = <GeocodingCandidateViewModel>[
        GeocodingCandidateViewModel(
          index: 0,
          displayName: 'Erfurt, Thuringia, Germany',
          latitude: 50.9787,
          longitude: 11.03283,
          coordinatesSummary: '50.978700, 11.032830',
        ),
        GeocodingCandidateViewModel(
          index: 1,
          displayName: 'Erfurt-Nord, Thuringia, Germany',
          latitude: 51.01,
          longitude: 11.02,
          coordinatesSummary: '51.010000, 11.020000',
        ),
      ];

      await pumpV2Widget(
        tester,
        _ModalHost(
          onTrigger: (context) async {
            chosenIndex = await showGeocodingCandidatesModal(
              context,
              candidates: candidates,
            );
          },
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('open_modal_trigger')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Erfurt, Thuringia, Germany'), findsOneWidget);
      expect(find.text('51.010000, 11.020000'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('picker_opt_1')));
      await tester.pumpAndSettle();

      expect(chosenIndex, 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('open_modal_trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('geocoding_candidates_cancel_button'),
        ),
      );
      await tester.pumpAndSettle();

      expect(chosenIndex, isNull);
    });
  });

  group('showCompactLabelPickerSheet', () {
    testWidgets(
      'does not auto-focus search on compact viewport, updates chips live on toggle/create, filters scopes, and pops on Escape',
      (tester) async {
        final toggled = <String>[];
        final created = <String>[];
        final openedInfo = <String>[];
        const labels = <LabelPickerOptionViewModel>[
          LabelPickerOptionViewModel(
            id: 'lbl_errands',
            name: 'Errands',
            colorValue: 0xFF2196F3,
            isScoped: false,
            openCount: 3,
          ),
          LabelPickerOptionViewModel(
            id: 'lbl_work',
            name: 'Work',
            colorValue: 0xFF4CAF50,
            isScoped: true,
            openCount: 5,
          ),
        ];

        await pumpV2Widget(
          tester,
          _ModalHost(
            onTrigger: (context) => showCompactLabelPickerSheet(
              context,
              title: localizations.taskLabelsSectionTitle,
              allLabels: labels,
              hasBothScopedAndGlobal: true,
              selectedIds: const <String>{'lbl_errands'},
              onToggleLabel: toggled.add,
              onCreateAndAssign: created.add,
              onOpenLabelInfo: openedInfo.add,
            ),
          ),
          surfaceSize: const Size(390, 844),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('ui_bottom_sheet')),
          findsOneWidget,
        );

        // U-A11Y-003: Search field MUST NOT auto-focus inside compact bottom sheets.
        final searchField = tester.widget<TextField>(find.byType(TextField));
        expect(searchField.autofocus, isFalse);
        expect(searchField.focusNode?.hasFocus, isFalse);

        // Conditional scope filters appear when both scoped and global labels exist.
        expect(
          find.byKey(const ValueKey<String>('picker_scope_all')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('picker_scope_scoped')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('picker_scope_global')),
          findsOneWidget,
        );

        // Initial selected chip is present; toggling Work adds its chip live.
        expect(
          find.byKey(const ValueKey<String>('picker_chip_lbl_errands')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('picker_chip_lbl_work')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('picker_opt_lbl_work')),
        );
        await tester.pumpAndSettle();

        expect(toggled, <String>['lbl_work']);
        expect(
          find.byKey(const ValueKey<String>('picker_chip_lbl_work')),
          findsOneWidget,
        );

        // Scope filter narrows visible rows to scoped labels only.
        await tester.tap(
          find.byKey(const ValueKey<String>('picker_scope_scoped')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('picker_opt_lbl_work')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('picker_opt_lbl_errands')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('picker_scope_all')),
        );
        await tester.pumpAndSettle();

        // Inline create adds chip live and invokes callback.
        await tester.enterText(find.byType(TextField), 'Urgent');
        await tester.pumpAndSettle();
        final createRow = find.text(
          localizations.labelPickerCreateAndAssign('Urgent'),
        );
        expect(createRow, findsOneWidget);
        await tester.tap(createRow);
        await tester.pumpAndSettle();

        expect(created, <String>['Urgent']);
        expect(
          find.byKey(const ValueKey<String>('picker_chip__created_0')),
          findsOneWidget,
        );

        // Two-step Escape from search clears text first, then dismisses sheet on second Escape.
        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Work');
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('ui_bottom_sheet')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('picker_opt_lbl_errands')),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('ui_bottom_sheet')),
          findsNothing,
        );

        // Reopen and verify row info button triggers callback and closes sheet.
        await tester.tap(
          find.byKey(const ValueKey<String>('open_modal_trigger')),
        );
        await tester.pumpAndSettle();

        final infoButton = find.descendant(
          of: find.byKey(const ValueKey<String>('picker_opt_lbl_work')),
          matching: find.byIcon(Icons.info_outline_rounded),
        );
        await tester.tap(infoButton);
        await tester.pumpAndSettle();

        expect(openedInfo, <String>['lbl_work']);
        expect(
          find.byKey(const ValueKey<String>('ui_bottom_sheet')),
          findsNothing,
        );
      },
    );

    testWidgets('omits scope filters when hasBothScopedAndGlobal is false', (
      tester,
    ) async {
      const labels = <LabelPickerOptionViewModel>[
        LabelPickerOptionViewModel(
          id: 'lbl_home',
          name: 'Home',
          colorValue: 0xFF2196F3,
          isScoped: false,
          openCount: 1,
        ),
      ];

      await pumpV2Widget(
        tester,
        _ModalHost(
          onTrigger: (context) => showCompactLabelPickerSheet(
            context,
            title: localizations.taskLabelsSectionTitle,
            allLabels: labels,
            hasBothScopedAndGlobal: false,
            selectedIds: const <String>{},
            onToggleLabel: (_) {},
            onCreateAndAssign: (_) {},
            onOpenLabelInfo: (_) {},
          ),
        ),
        surfaceSize: const Size(390, 844),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('open_modal_trigger')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('picker_scope_all')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('picker_scope_scoped')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('picker_scope_global')),
        findsNothing,
      );
    });
  });
}
