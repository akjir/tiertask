# TierTask Architecture and File Structure

> [!IMPORTANT]
> Update this file, [`AGENTS.md`](AGENTS.md), [`spec/TDF_SPEC_0.8.0.md`](spec/TDF_SPEC_0.8.0.md), and [`spec/UI_DESIGN_SYSTEM.md`](spec/UI_DESIGN_SYSTEM.md) whenever the architecture, supported target platforms, directory layout, file responsibilities, localization files, UI design guidelines, or TDF synchronization flow change.

## Architectural Layers

| Layer | Path | Responsibility |
| :--- | :--- | :--- |
| Localization | `lib/l10n/` | External English (`app_en.arb`) and German (`app_de.arb`) resource bundles, generated `AppLocalizations` classes, `TaskTier` and `WorkspaceException` mappings, and per-file readability localization extensions. |
| Models | `lib/models/` | Immutable domain data structures (`AppWorkspace`, `WorkspaceSummary`, `WorkspaceException`, `WorkspaceErrorKind`, `PersistedSettingsDocument`, `SettingsCodec`, `SettingsDecodeResult`, `SettingsDecodeWarning`, `SettingsRecoveryKind`, `SettingsRecoveryNotice`, deprecated `LegacyTtwV2Converter`, `GeocodingCandidate`, `LocationFix`, `LocationSource`, `LocationSourceType`, `LocationState`, `LocationStatus`, `StorageFileTarget`, `StorageFileReadState`, `StorageReadFailureScope`, `StorageFileReadStatus`, `StorageFileReadReport`, `TaskTier`, `QuickAddMode`, `TaskItem`, `TaskOrigin`, `SubtaskItem`, `TaskHistoryEntry`, `TaskLink`, `RepeatUnit`, `TaskRepeatRule`, `ConditionGroup`, `TaskCondition`, `TdfFilePath`, `TdfLocation`, `TdfLabel`, `TdfColor`, `TdfQueueBlock`, `TdfDeletionRecord`, `TdfDeletedBlock`, `TdfTaskDependency`, `TdfCleanupMode`, `TdfBoundDeletionDecision`, `TdfRecoveryResolution`, `TdfSyncOutcomeException`, `TdfContextException`, `TdfErrorKind`, `TdfException`, `TdfLocalDateTime`, `TdfRepeatClock`, `TdfTimeZoneContext`, `TdfCalendar`, `TdfPayloadComparison`, `TaskBoard`, `TaskBoardEvaluator`, `TaskBoardMutator`, `TaskBoardQueueMutator`, `TaskBoardSync`, `TaskBoardReconciler`, `TaskBoardUndo`, `WorkspaceSyncState`, `AppLanguage`, `AppThemeMode`, `AppThemePalette`, `AppTimeZoneMode`, `DueLeadWindow`, `StorageMode`, `WebDavConfig`) and the dynamic $O(N)$ 6-tier derivation, mutation, undo, and three-way synchronization pipeline. |
| Services | `lib/services/` | Opt-in diagnostic logging service (`AppLogger`, `AppLogSink`, `LogLevel`, `LogTag`) at DAG rank `0`, stateless single-pass $O(N)$ RFC 4648 Base64 codec (`Base64Service`, `Base64Exception`, `Base64ErrorKind`), Open Location Code parser and decoder (`PlusCodeService`, `PlusCodeArea`, `PlusCodeInput`), pure-Dart FIPS 180-4 SHA-256 digest service (`Sha256Service`), and TDF `0.8.0` lexical scanner (`TdfScanner`), structural parser (`TdfParser`, `TdfDirectiveParser`), and byte-exact canonical `LF` serializer (`TdfSerializer`, `TdfService`). |
| Repositories | `lib/repositories/` | All external I/O: WebDAV HTTP `GET`/`PUT` (`dart:io` `HttpClient`), pure-Dart `dart:ffi` non-blocking host-local cooperative file locking and atomic temp-file publication (`HostFileLockManager`), local `.tdf` file and `tiertask.log` reads/writes (`LocalFileRepository`, `LocalFileOperations`, `LocalFileLogSink`), foreground location channel and bounded reverse/forward geocoding and GeoIP lookup (`MethodChannel` and `HttpClient`), and split host-local JSON settings (`settings.json` + `.bak` + quarantine) with per-workspace encrypted WebDAV passwords and `TTS\x04` sync baselines (`flutter_secure_storage`). |
| Providers | `lib/providers/` | Riverpod state management (`Provider`, `Notifier`, `AsyncNotifier`) across `workspace_providers.dart`, `config_providers.dart`, `local_file_watch_providers.dart`, `location_providers.dart`, `sync_providers.dart`, and `task_providers.dart` coordinating single-active-workspace unload/load transitions, parent-directory `.tdf` file watching, foreground lifecycle-aware location determination, locale and theme resolution, domain mutations, conflict/recovery resolution, and multi-stage repository synchronization (`TaskSyncPipeline`). |
| Presentation | `lib/presentation/` | Model-free shell, board, task, entity, settings, workspace, sync, floating-notice, log-viewer, link-action, and window-control controllers (`21` acyclic leaves), immutable domain-partitioned ViewModels (`view_model_primitives.dart`, `shell_chrome_view_models.dart`, `tasks_view_model.dart`, `entity_view_models.dart`), schedule and location helpers (`TaskScheduleHelper`, `LocationSourceResolver`), redacted UI telemetry (`UiTelemetry`), and wall-clock boundary scheduling (`BoardBoundaryTimer`). |
| UI Component Library | `packages/tiertask_ui/` | Compiler-isolated local Flutter package (`tiertask_ui`) with zero `tiertask`, `flutter_riverpod`, `dart:io`, or `dart:ffi` dependencies, exporting Layer 1 design tokens (`Calm` default and `Plum Umber`, Light and Dark, automated WCAG AA contrast checking), 8 core primitives, 4 adaptive layouts, and 5 composites through one curated barrel (`lib/tiertask_ui.dart`) alongside a runnable `example/` gallery app. |
| UI | `lib/ui/` | Production adaptive shell (`27` acyclic leaves across root shell/mapper, `dialogs/`, `widgets/`, and `views/`) acting as strict Rank `7` model-free adapters over `packages/tiertask_ui/`, `lib/presentation/`, and `AppLocalizations` with zero Riverpod provider or notifier declarations. |

> [!NOTE]
> Per Google's Flutter App Architecture guidelines (`P-UDF-ARCHITECTURE`, `P-ACYCLIC-DAG`, `P-IO-ISOLATION`, `P-WEBDAV-API`, `P-GLOBAL-ERROR-BOUNDARY`, `P-ATOMIC-STATE`, `P-SECRET-HYGIENE`, `P-TRANSPORT-SECURITY`), data flows unidirectionally from single-source-of-truth repositories (`lib/repositories/`) through state notifiers (`lib/providers/`) and presentation controllers (`lib/presentation/`) to stateless/consumer views (`lib/ui/`), enforcing strict bottom-up DAG rank order (`0: lib/services/app_logger.dart < 1: lib/models/* < 2: lib/l10n/* < 3: lib/services/* < 4: lib/repositories/* < 5: lib/providers/* < 6: lib/presentation/* < 7: lib/ui/* < 8: lib/main.dart`). `lib/ui/` enforces a global strict import whitelist (`package:tiertask_ui/tiertask_ui.dart`, `lib/presentation/*`, acyclic `lib/ui/*`, `lib/l10n/app_localizations.dart`, `package:flutter_riverpod/flutter_riverpod.dart`, Flutter/`material_ui`, and non-I/O Dart SDK utilities only) and forbids Riverpod provider/notifier declarations; all network (`HttpClient`), native OS locking (`dart:ffi`), local filesystem (`File`), and secure storage (`FlutterSecureStorage`) operations are strictly isolated in `lib/repositories/`; global error boundaries (`FlutterError.onError` and `PlatformDispatcher.instance.onError`) guard runtime stability; and credentials are redacted from logs and error messages.

## Directory Layout

```text
tiertask/
├── AGENTS.md
├── ARCHITECTURE.md
├── CHANGELOG.md
├── LICENSE
├── README.md
├── analysis_options.yaml
├── install.sh
├── l10n.yaml
├── pubspec.yaml
├── android/
├── assets/
│   └── logo/
│       ├── tiertask_logo.png
│       └── tiertask_logo.svg
├── linux/
├── spec/
│   ├── TDF_SPEC_0.8.0.md
│   ├── UI_DESIGN_SYSTEM.md
│   └── conformance/
├── windows/
├── lib/
│   ├── main.dart
│   ├── l10n/
│   │   ├── app_de.arb
│   │   ├── app_en.arb
│   │   ├── app_localizations.dart
│   │   ├── app_localizations_de.dart
│   │   ├── app_localizations_en.dart
│   │   ├── storage_file_read_localization_extension.dart
│   │   └── tier_localization_extension.dart
│   ├── models/
│   │   ├── app_build_profile.dart
│   │   ├── app_workspace.dart
│   │   ├── legacy_ttw_v2_converter.dart
│   │   ├── location_state.dart
│   │   ├── settings_codec.dart
│   │   ├── storage_file_read_status.dart
│   │   ├── task_board.dart
│   │   ├── task_board_evaluator.dart
│   │   ├── task_board_mutator.dart
│   │   ├── task_board_queue_mutator.dart
│   │   ├── task_board_reconciler.dart
│   │   ├── task_board_sync.dart
│   │   ├── task_board_undo.dart
│   │   ├── task_item.dart
│   │   ├── task_tier.dart
│   │   ├── tdf_error.dart
│   │   ├── tdf_file_path.dart
│   │   ├── tdf_location.dart
│   │   ├── tdf_metadata.dart
│   │   ├── tdf_payload_comparison.dart
│   │   ├── tdf_sync_metadata.dart
│   │   ├── tdf_timezone.dart
│   │   ├── webdav_config.dart
│   │   └── workspace_sync_state.dart
│   ├── presentation/
│   │   ├── app_shell_controller.dart
│   │   ├── board_boundary_timer.dart
│   │   ├── board_presentation_providers.dart
│   │   ├── entity_controller.dart
│   │   ├── entity_view_models.dart
│   │   ├── floating_notice_controller.dart
│   │   ├── link_action_controller.dart
│   │   ├── location_source_resolver.dart
│   │   ├── log_viewer_controller.dart
│   │   ├── settings_controller.dart
│   │   ├── settings_storage_controller.dart
│   │   ├── shell_chrome_view_models.dart
│   │   ├── shell_models.dart
│   │   ├── sync_controller.dart
│   │   ├── task_controller.dart
│   │   ├── task_schedule_helper.dart
│   │   ├── tasks_view_model.dart
│   │   ├── ui_telemetry.dart
│   │   ├── view_model_primitives.dart
│   │   ├── window_control_controller.dart
│   │   └── workspace_controller.dart
│   ├── providers/
│   │   ├── config_providers.dart
│   │   ├── local_file_watch_providers.dart
│   │   ├── location_providers.dart
│   │   ├── sync_providers.dart
│   │   ├── task_providers.dart
│   │   └── workspace_providers.dart
│   ├── repositories/
│   │   ├── app_version_repository.dart
│   │   ├── host_file_lock.dart
│   │   ├── link_launcher_repository.dart
│   │   ├── local_file_operations.dart
│   │   ├── local_file_repository.dart
│   │   ├── location_repository.dart
│   │   ├── settings_repository.dart
│   │   ├── webdav_repository.dart
│   │   └── window_control_repository.dart
│   ├── services/
│   │   ├── app_logger.dart
│   │   ├── base64_service.dart
│   │   ├── plus_code_service.dart
│   │   ├── sha256_service.dart
│   │   ├── tdf_directive_parser.dart
│   │   ├── tdf_parser.dart
│   │   ├── tdf_scanner.dart
│   │   ├── tdf_serializer.dart
│   │   └── tdf_service.dart
│   └── ui/
│       ├── tier_task_shell_screen.dart
│       ├── ui_icon_mapper.dart
│       ├── dialogs/
│       │   ├── compact_label_picker_sheet.dart
│       │   ├── geocoding_candidates_modal.dart
│       │   ├── local_file_modals.dart
│       │   ├── location_status_modal.dart
│       │   ├── wipe_tdf_modal.dart
│       │   └── workspaces_modal.dart
│       ├── views/
│       │   ├── label_card.dart
│       │   ├── labels_view.dart
│       │   ├── location_card.dart
│       │   ├── locations_view.dart
│       │   ├── log_viewer_view.dart
│       │   ├── raw_tdf_view.dart
│       │   ├── resolution_views.dart
│       │   ├── settings_view.dart
│       │   ├── task_card.dart
│       │   ├── task_detail_editors.dart
│       │   ├── task_draft_card.dart
│       │   ├── task_schedule_editors.dart
│       │   └── tasks_view.dart
│       └── widgets/
│           ├── entity_card_chrome.dart
│           ├── entity_conditions_section.dart
│           ├── entity_date_time_fields.dart
│           ├── entity_label_picker.dart
│           ├── entity_links_section.dart
│           └── entity_note_section.dart
├── packages/
│   └── tiertask_ui/
│       ├── analysis_options.yaml
│       ├── pubspec.yaml
│       ├── example/
│       │   ├── analysis_options.yaml
│       │   ├── pubspec.yaml
│       │   ├── lib/
│       │   │   ├── gallery_sections.dart
│       │   │   └── main.dart
│       │   ├── linux/
│       │   └── test/
│       │       └── gallery_smoke_test.dart
│       ├── lib/
│       │   ├── tiertask_ui.dart
│       │   └── src/
│       │       ├── components/
│       │       │   ├── ui_color_wheel.dart
│       │       │   ├── ui_dialog_frame.dart
│       │       │   ├── ui_ordered_item_list.dart
│       │       │   ├── ui_quick_composer.dart
│       │       │   └── ui_searchable_picker.dart
│       │       ├── layout/
│       │       │   ├── ui_adaptive_app_shell.dart
│       │       │   ├── ui_page_header.dart
│       │       │   ├── ui_responsive_grid.dart
│       │       │   └── ui_sidebar_section.dart
│       │       ├── primitives/
│       │       │   ├── ui_app_logo.dart
│       │       │   ├── ui_banner.dart
│       │       │   ├── ui_button.dart
│       │       │   ├── ui_card.dart
│       │       │   ├── ui_field.dart
│       │       │   ├── ui_pill.dart
│       │       │   ├── ui_segmented_control.dart
│       │       │   └── ui_toggle_row.dart
│       │       └── tokens/
│       │           ├── ui_breakpoints.dart
│       │           ├── ui_color_tokens.dart
│       │           ├── ui_focus_tokens.dart
│       │           ├── ui_radius_tokens.dart
│       │           ├── ui_spacing_tokens.dart
│       │           ├── ui_theme_tokens.dart
│       │           └── ui_typography_tokens.dart
│       └── test/
│           ├── test_helpers.dart
│           ├── components/
│           │   ├── ui_color_wheel_test.dart
│           │   ├── ui_dialog_frame_test.dart
│           │   ├── ui_ordered_item_list_test.dart
│           │   ├── ui_quick_composer_test.dart
│           │   └── ui_searchable_picker_test.dart
│           ├── layout/
│           │   ├── ui_adaptive_app_shell_test.dart
│           │   ├── ui_page_header_test.dart
│           │   ├── ui_responsive_grid_test.dart
│           │   └── ui_sidebar_section_test.dart
│           ├── primitives/
│           │   ├── ui_app_logo_test.dart
│           │   ├── ui_banner_test.dart
│           │   ├── ui_button_test.dart
│           │   ├── ui_card_test.dart
│           │   ├── ui_field_test.dart
│           │   ├── ui_pill_test.dart
│           │   ├── ui_segmented_control_test.dart
│           │   └── ui_toggle_row_test.dart
│           └── tokens/
│               ├── ui_breakpoints_test.dart
│               ├── ui_color_tokens_test.dart
│               └── ui_theme_tokens_test.dart
└── test/
    ├── l10n/
    │   ├── storage_file_read_localization_extension_test.dart
    │   └── tier_localization_extension_test.dart
    ├── models/
    │   ├── app_build_profile_test.dart
    │   ├── app_workspace_test.dart
    │   ├── legacy_ttw_v2_converter_test.dart
    │   ├── location_state_test.dart
    │   ├── settings_codec_test.dart
    │   ├── storage_file_read_status_test.dart
    │   ├── task_board_downgrade_test.dart
    │   ├── task_board_evaluation_test.dart
    │   ├── task_board_lifecycle_test.dart
    │   ├── task_board_mutation_test.dart
    │   ├── task_board_occurrence_rules_test.dart
    │   ├── task_board_sync_test.dart
    │   ├── task_board_undo_test.dart
    │   ├── tdf_file_path_test.dart
    │   ├── tdf_location_test.dart
    │   ├── tdf_primitives_test.dart
    │   └── tdf_v080_merge_conformance_test.dart
    ├── presentation/
    │   ├── app_shell_controller_test.dart
    │   ├── board_boundary_timer_test.dart
    │   ├── board_presentation_providers_test.dart
    │   ├── board_view_models_test.dart
    │   ├── entity_controller_test.dart
    │   ├── floating_notice_controller_test.dart
    │   ├── link_action_controller_test.dart
    │   ├── location_source_resolver_test.dart
    │   ├── log_viewer_controller_test.dart
    │   ├── settings_controller_test.dart
    │   ├── settings_storage_controller_test.dart
    │   ├── sync_controller_test.dart
    │   ├── task_controller_test.dart
    │   ├── task_schedule_helper_test.dart
    │   ├── ui_telemetry_test.dart
    │   ├── window_control_controller_test.dart
    │   └── workspace_controller_test.dart
    ├── providers/
    │   ├── config_providers_test.dart
    │   ├── local_file_watch_providers_test.dart
    │   ├── sync_providers_test.dart
    │   ├── task_providers_test.dart
    │   └── workspace_providers_test.dart
    ├── repositories/
    │   ├── app_version_repository_test.dart
    │   ├── host_file_lock_test.dart
    │   ├── link_launcher_repository_test.dart
    │   ├── local_file_repository_test.dart
    │   ├── location_repository_test.dart
    │   ├── settings_repository_test.dart
    │   ├── webdav_repository_test.dart
    │   └── window_control_repository_test.dart
    ├── services/
    │   ├── app_logger_test.dart
    │   ├── base64_service_test.dart
    │   ├── plus_code_service_test.dart
    │   ├── sha256_service_test.dart
    │   ├── tdf_service_bounds_test.dart
    │   ├── tdf_service_parser_test.dart
    │   └── tdf_v080_conformance_test.dart
    └── ui/
        ├── app_modals_test.dart
        ├── entity_section_widgets_test.dart
        ├── labels_view_test.dart
        ├── locations_view_test.dart
        ├── real_mechanics_test.dart
        ├── secondary_views_test.dart
        ├── settings_view_test.dart
        ├── tasks_view_test.dart
        ├── test_helpers.dart
        ├── tier_task_shell_screen_test.dart
        └── ui_icon_mapper_test.dart
```

## Root Files

| File | Function |
| :--- | :--- |
| `AGENTS.md` | Engineering rules, TDD workflow (`P-TDD-FIRST`), deterministic `.dart` file layout, and mandatory test categories. |
| `ARCHITECTURE.md` | Architectural layer definitions, directory structure, file inventory, and TDF synchronization flow. |
| `CHANGELOG.md` | User-facing change history following Keep a Changelog 1.1.0. |
| `README.md` | Project overview, supported platforms (Linux, Android, Windows), build instructions, and `.tdf` tier reference. |
| `analysis_options.yaml` | Dart analyzer configuration excluding `build/**`, `android/**`, `linux/**`, `windows/**`, `packages/**`, and generated `lib/l10n/app_localizations*.dart` files. |
| `install.sh` | POSIX user-space Linux build and installation script installing the release bundle, executable symlink, icons, and desktop entry into `$HOME/.local`. |
| `l10n.yaml` | Flutter `gen-l10n` configuration pointing to `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb`. |
| `pubspec.yaml` | Package metadata and dependencies (`flutter`, `flutter_localizations`, `flutter_riverpod`, `flutter_secure_storage`, `intl`, `material_ui`). |
| `spec/TDF_SPEC_0.8.0.md` | Normative standalone specification for the TierTask Data Format (`.tdf`) `0.8.0` lexical grammar, blocks, directives, schedule anchors, 6-tier derivation pipeline, mutations, multi-stage sync, host locking, and error bounds. |
| `spec/UI_DESIGN_SYSTEM.md` | Normative UI design system and interaction specification (`P-UI-DESIGN-SYSTEM`) codifying tokens, WCAG AA presets, surface hierarchy, breakpoints, 17-widget catalog contracts, expandable entity cards, workflows, keyboard shortcuts, and accessibility rules. |

## Localization

| File | Function |
| :--- | :--- |
| `lib/l10n/app_en.arb` | External English (`en`, default fallback) translation bundle for all UI labels, tier headings, and error messages. |
| `lib/l10n/app_de.arb` | External German (`de`) translation bundle for all UI labels, tier headings, and error messages. |
| `lib/l10n/storage_file_read_localization_extension.dart` | Extension on `AppLocalizations` mapping `StorageFileReadReport` and `StorageFileReadStatus` values to localized target labels, dual-storage summaries, and per-file readability diagnostics. |
| `lib/l10n/tier_localization_extension.dart` | Extension on `AppLocalizations` mapping `TaskTier` (`1`–`6`) to localized tier names and empty-state hints (`tierName`, `tierEmptyHint`), and exhaustively localizing `WorkspaceException` errors (`localizeWorkspaceError`). |

## Domain Models

| File | Function |
| :--- | :--- |
| `lib/models/app_build_profile.dart` | Defines `AppBuildProfile` (`release` and `dev`) resolving compile-time `TIERTASK_ENV` and `kReleaseMode` into isolated user data directories (`tiertask` vs `tiertask-dev`), per-workspace WebDAV password and sync key prefixes (`t2_webdav_pw_` / `t2_sync_v1_` vs `t2_dev_webdav_pw_` / `t2_dev_sync_v1_`), deprecated `legacySettingsStorageKey`, and window titles. |
| `lib/models/app_workspace.dart` | Defines immutable `AppWorkspace`, `WorkspaceSummary`, `WorkspaceErrorKind`, and `WorkspaceException` (with optional `cause`) for isolated workspace configurations, suggested `.tdf` filenames (`AppWorkspace.suggestFileName`), control/BiDi validation (`hasControlCharacters`), and workspace name/path uniqueness checks. |
| `lib/models/legacy_ttw_v2_converter.dart` | Deprecated read-only LegacyTtwV2Converter decoding pre-0.4.0 TTW\x02 workspace payloads for automatic one-time migration while rejecting TTW\x01; scheduled for removal in 0.5.0. |
| `lib/models/location_state.dart` | Defines immutable `GeocodingCandidate`, `LocationFix`, `LocationSource` (`gps`, `system`, `internet`), `LocationSourceType` (`gps`, `address`, `plusCode`), `LocationState`, and `LocationStatus` (`disabled`, `searching`, `found`, `unavailable`) with WGS-84 coordinate formatting, 100-meter Haversine displacement gating, and 5-minute resume refresh cooldown evaluation. |
| `lib/models/settings_codec.dart` | Defines immutable PersistedSettingsDocument, SettingsDecodeWarning, SettingsDecodeResult, SettingsRecoveryKind, SettingsRecoveryNotice, and stateless SettingsCodec encoding and resiliently decoding versioned UTF-8 settings.json documents with unknown-key preservation and strict secret exclusion. |
| `lib/models/storage_file_read_status.dart` | Defines immutable `StorageFileTarget`, `StorageFileReadState`, `StorageReadFailureScope`, `StorageFileReadStatus`, and `StorageFileReadReport` models classifying per-file local and remote `.tdf` readability outcomes. |
| `lib/models/task_board.dart` | Defines the immutable `TaskBoard` aggregate storing `Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, and `Completed` tier slices, sorted `TdfLocation` and `TdfLabel` items, `TdfQueueBlock`, and `TdfDeletedBlock`, and delegating evaluation and mutations to `TaskBoardEvaluator`, `TaskBoardQueueMutator`, and `TaskBoardMutator`. |
| `lib/models/task_board_evaluator.dart` | Stateless dynamic $O(N)$ 6-tier derivation engine (`TaskBoardEvaluator`, `NormalizedTierSlices`, `TaskBoardSlicesX`) implementing `spec/TDF_SPEC_0.8.0.md` Section 9 tier partitioning, configurable `due` lead-window promotion (`24` hours by default), WIP soft limits (`3` `Focus`, `5` `Ready`), `scoped` label queues, block-reason cleanup, 30-day UTC pruning, `subtasks auto-finish`, and label condition inheritance. |
| `lib/models/task_board_mutator.dart` | Stateless task, location, and label CRUD, history, and recurrence mutation subsystem (`TaskBoardMutator`, `TaskBoardMutationSlicesX`) implementing `spec/TDF_SPEC_0.8.0.md` Section 10 task addition, editing (`dueLocalInput`/`suspendedLocalInput` `TDF-CAL-001` resolution, `due.anchor` preservation, and `priority` `passive` deadline resets), `(Y_cur, M_cur)` Mode 2 recurrence (`TDF-CAL-003`), completion, restoration, deletion, subtask toggling, `history` journal mutations, location and label management, block cleanup, and monotonic `modifiedAt` stamping. |
| `lib/models/task_board_queue_mutator.dart` | Stateless queue-ordered scheduling and dependency re-arming subsystem (`TaskBoardQueueMutator`, `TaskBoardQueueSlicesX`) implementing `spec/TDF_SPEC_0.8.0.md` Sections 10.3 and 10.4 tier downgrading (`Focus -> Ready -> Planned -> Someday` with `passive` deadline demotion and `scoped` label boundary jumps), restoration (`due`/`dueAnchor`/`suspended` clearing), explicit `priority` scheduling, priority reordering, dependency cycle detection, and completion requirement capture. |
| `lib/models/task_board_reconciler.dart` | Stateless synchronization helper subsystem (`TaskBoardReconciler`) implementing `spec/TDF_SPEC_0.8.0.md` Sections 11–13 baseline payload lookup, monotonic revision selection, deterministic tie-breaking, pre-cascade `scoped` label reconstruction (`TDF-MERGE-006`), `history` set reconciliation, two-level occurrence merging with atomic `(due, anchor, passive, note)` coupling, deletion conflict and bound decision verification (`TDF-DEL-003`), symmetric generation refresh (`TDF-REC-001`), new-identity recovery rewriting (`TDF-REC-002`), and `queue` block reconciliation. |
| `lib/models/task_board_sync.dart` | Stateless three-way synchronization facade (`TaskBoardSync.merge`, `TaskBoardSync.resolveRecovery`, `TaskBoardSync.stampAndNormalize`) coordinating baseline-aware task, location, label, `queue`, and `deleted` block reconciliation and stage-fair `TdfCleanupMode` (`finalStage` vs. `deferred`) cleanup across in-memory, local file, and WebDAV `.tdf` revisions. |
| `lib/models/task_board_undo.dart` | Stateless single-task undo subsystem (`TaskBoardUndo`, `TaskUndoActionKind`, `TaskUndoEntry`, `TaskUndoOutcome`) capturing pre-mutation task (including `dueAnchor`), queue, and prerequisite dependency snapshots and reversing task completion, active downgrade, and deletion while preserving monotonic `completions`, `decisionRevision`, `deleted` `generation`, live `history` across completion and downgrade undos, and `label`/`location` hygiene. |
| `lib/models/task_item.dart` | Defines immutable `TaskItem`, `TaskOrigin`, `SubtaskItem`, `TaskHistoryEntry`, `RepeatUnit`, and `TaskRepeatRule` value classes with 10-character Base62 `<task-id>` identifiers, UTC `created` / `finished` / `modified` / `suspended` / `due` timestamps and notes, optional local `dueAnchor` (`TdfLocalDateTime`), `passive` `due` flag, `completions` counter, recurrence `leadDays`, labels, dependencies, links, `history`, and conditions. |
| `lib/models/task_tier.dart` | Defines the `TaskTier` enum for the 6 derived tiers (`1` `focus` through `6` `completed`), WIP soft limits, and the `QuickAddMode` (`normal`, `priority`, `someday`) task creation scheduling enum. |
| `lib/models/tdf_error.dart` | Defines `TdfErrorKind`, `TdfException`, and normative `spec/TDF_SPEC_0.8.0.md` Section 6.2 resource bound constants (`maxTdfFileBytes`, `maxTdfLineCount`, `maxTdfNestingDepth`, `maxTdfBlocksPerDoc`, `maxTdfStmtsPerBlock`, `maxTdfArgsPerStmt`, `maxTdfTextLength`, `maxTdfNoteLength`, `maxTdfLinksPerTask`, `maxTdfLinksPerLabel`, `maxTdfHistoryPerTask`, `maxTdfQueueEntries`, `maxTdfDeletedRecords`, `maxTdfRepeatCount`, `maxTdfGeneration`, `maxTdfCompletions`, `defaultDueLeadSeconds`). |
| `lib/models/tdf_file_path.dart` | Pure cross-platform `.tdf` path manipulation, extension normalization, and single-segment filename validation (`TdfFilePath`) enforcing control-character, BiDi override, and separator rejection without `dart:io`. |
| `lib/models/tdf_location.dart` | Defines the immutable `TdfLocation` value class (`id`, `name`, `latitude`, `longitude`, `radius`, `source`, `note`, `modifiedAt`), 10-character Base62 `<location-id>` generation and validation helpers (`generateLocationId`, `isValidLocationId`), canonical 6-decimal coordinate/radius formatting, and Haversine distance calculation (`distanceMeters`). |
| `lib/models/tdf_metadata.dart` | Defines `tdfSupportedVersion` (`0.8.0`), `TaskLink`, `ConditionGroup` (`day`, `time`, `location`), `TaskCondition` (`DayTaskCondition`, `GlobalResetTaskCondition`, `GroupResetTaskCondition`, `LocationTaskCondition`, `TimeWindowTaskCondition`), `TdfLabel` (with `isScoped` and `links`), `TdfColor` hex utilities, and 10-character Base62 identifier helpers (`generateTaskId`, `generateLabelId`, `isValidTaskId`, `isValidLabelId`). |
| `lib/models/tdf_payload_comparison.dart` | Stateless non-revision payload equality, block-cleanup normalization, and deterministic tie-break key extraction (`TdfPayloadComparison`) implementing `spec/TDF_SPEC_0.8.0.md` Section 12.2 across `TaskItem` (including atomic 4-tuple `due` + `dueAnchor` comparison), `TdfLocation`, and `TdfLabel`. |
| `lib/models/tdf_sync_metadata.dart` | Defines immutable `TdfQueueBlock`, `TdfDeletionRecordKind`, `TdfDeletionRecord`, `TdfDeletedBlock`, `TdfTaskDependency`, `TdfCleanupMode` (`finalStage`, `deferred`), `TdfDeletionResolution`, `TdfBoundDeletionDecision`, `TdfRecoveryResolution` (`discard`, `recoverAsNew`), `TdfSyncOutcomeException`, and `TdfContextException` from `spec/TDF_SPEC_0.8.0.md` Sections 5, 11–13, and Appendix A.1. |
| `lib/models/tdf_timezone.dart` | Defines proleptic Gregorian calendar and Unicode scalar validation (`TdfCalendar`), local schedule-anchor timestamps (`TdfLocalDateTime`), recurring clock tokens (`TdfRepeatClock`), and `TDF-CAL-001` local-to-UTC time-zone transition resolution (`TdfTimeZoneContext` supporting `systemLocal()` binary-search DST gap and earliest-fold resolution, fixed offsets, `UTC`, `Europe/Berlin`, and `America/New_York`). |
| `lib/models/webdav_config.dart` | Defines `AppLanguage`, `AppThemeMode`, `AppThemePalette`, `AppTimeZoneMode`, `DueLeadWindow`, `StorageMode`, and the immutable `WebDavConfig` model with defaults (`tasks.tdf`, `localWatchEnabled: true`, `AppThemePalette.calm`, `AppTimeZoneMode.automatic`, `DueLeadWindow.hours24`, `diagnosticsEnabled: false`), `resolveTimeZoneContext()`, and UTC/local wall-clock conversion helpers (`toLocalWallClock`, `localWallClockToUtc`). |
| `lib/models/workspace_sync_state.dart` | Defines the immutable `WorkspaceSyncState` value class and compact `TTS\x04` binary serialization (`toBytes`, `fromBytes`) persisting canonical `tdf 0.8.0` `lastSyncedLocalTdf` and `lastSyncedRemoteTdf` snapshots, nullable `acknowledgedLocalGeneration` and `acknowledgedRemoteGeneration`, `localSourceDigest`, `remoteSourceDigest`, `remoteEtag`, and `remoteLastModified` with atomic per-target completeness validation. |

## Services

| File | Function |
| :--- | :--- |
| `lib/services/app_logger.dart` | Opt-in structured diagnostic logging service (`AppLogger`, `AppLogSink`, `LogLevel`, `LogTag`, `LogMetadata`) at DAG rank `0`, formatting `<UTC-ISO> [<LEVEL>] [<TAG>] <event> | <key=value ...>` entries, redacting credentials (`sanitize`, `registerSecret`), managing the 5,000-line / 2 MiB dated `tiertask_<date>_<platform>_<workspace>.log` buffer with `@meta` headers, and preserving logs across clean and unclean exits. |
| `lib/services/base64_service.dart` | Single-pass $O(N)$ RFC 4648 Base64 encoder and decoder (`Base64Service`, `Base64Exception`, `Base64ErrorKind`) with pre-allocated `Uint8List` buffers, strict input byte bounds (`maxInputBytes`), alphabet validation, and non-zero padding-bit rejection. |
| `lib/services/plus_code_service.dart` | Stateless Open Location Code (Google Plus Code) parser, decoder, encoder, and nearest-locality recovery service (`PlusCodeService`, `PlusCodeArea`, `PlusCodeInput`, `FullPlusCodeInput`, `ShortPlusCodeInput`, `InvalidPlusCodeInput`). |
| `lib/services/sha256_service.dart` | Stateless pure-Dart FIPS 180-4 SHA-256 cryptographic digest service (`Sha256Service.hashBytes`, `Sha256Service.hashHex`) computing source fingerprints (`TDF-MERGE-001`) and canonical host lock target hashes (`TDF-PUB-002`). |
| `lib/services/tdf_directive_parser.dart` | Stateless TDF `0.8.0` statement and directive validation subsystem (`TdfDirectiveParser`) parsing `queue`, `deleted`, `location`, `label`, `task` (including right-to-left `due ... anchor ... passive "<note>"` peeling), `condition` (4-way depth-`2` disambiguation), and `subtasks` block directives per `spec/TDF_SPEC_0.8.0.md` Sections 5–6. |
| `lib/services/tdf_parser.dart` | Stateless TDF `0.8.0` document assembly and validation subsystem (`TdfParser`) enforcing the exact single-version `tdf 0.8.0` header contract (`TDF-COMPAT-001`), preserving explicit-vs-omitted `modifiedAt` state, validating cross-entity references, and invoking `TaskBoard.evaluate`. |
| `lib/services/tdf_scanner.dart` | Single-pass $O(N)$ lexical scanner (`TdfScanner`, `TdfRawStatement`, `TdfRawBlock`) tokenizing `.tdf` byte and string streams into unescaped arguments, statements, and nested blocks while enforcing `spec/TDF_SPEC_0.8.0.md` Section 3 grammar, pre-depth attached-brace header validation, and Section 6.2 resource bounds. |
| `lib/services/tdf_serializer.dart` | Stateless byte-exact canonical `LF` `tdf 0.8.0` serializer (`TdfSerializer`) formatting `queue`, `deleted`, `location`, `label`, and `task` blocks in deterministic `spec/TDF_SPEC_0.8.0.md` Section 7 canonical order with uniform depth-`1` $W_{\text{dir}}$ alignment, explicit `modified` preservation, and `1 MiB` / `16,384`-line output bounds. |
| `lib/services/tdf_service.dart` | Stateless TDF `0.8.0` service facade (`TdfService.parse`, `TdfService.parseBytes`, `TdfService.serialize`) delegating lexical scanning, structural parsing, and canonical serialization to `TdfScanner`, `TdfParser`, and `TdfSerializer`. |

## Repositories

| File | Function |
| :--- | :--- |
| `lib/repositories/app_version_repository.dart` | Abstract `AppVersionRepository`, `PlatformAppVersionRepository`, and `FakeAppVersionRepository` isolating native `de.akjir.tiertask/app_version` `MethodChannel` queries and formatting SemVer 2.0.0 Git build metadata (`formatFullVersion`, `isValidFullVersion`, `defaultFullVersion`). |
| `lib/repositories/host_file_lock.dart` | Pure-Dart `dart:ffi` non-blocking cooperative host-local file locking (`flock(LOCK_EX | LOCK_NB)` on Linux/Android; `LockFileEx(LOCKFILE_FAIL_IMMEDIATELY)` without `FILE_SHARE_DELETE` on Windows) with bounded async backoff timeout, symlink-resolved `<targetPathHash>` lock files outside synchronized workspaces (`TDF-PUB-002`), and exclusive temp-file atomic replacement (`TDF-PUB-003`). |
| `lib/repositories/link_launcher_repository.dart` | Abstract `LinkLauncherRepository`, `PlatformLinkLauncherRepository`, `FakeLinkLauncherRepository`, and `LinkLaunchException` isolating native `de.akjir.tiertask/link_launcher` `MethodChannel` URI launching with pre-launch URI validation (`TaskLink.isValidUri`). |
| `lib/repositories/local_file_operations.dart` | Stateless native desktop file/folder picker (`zenity`, `kdialog`, PowerShell), non-recursive parent-directory `.tdf` file watcher (`watchTdfFile`, `isRelevantWatchEvent`, `matchesWatchedFileName`), `.bak` / `.bak.001`+ backup rotation, and atomic cross-device move/rename/delete subsystem (`LocalFileOperations`). |
| `lib/repositories/local_file_repository.dart` | Native `dart:io` `File` repository (`LocalFileRepository`, `LocalFileException`, `LocalFileLogSink`) reading (`readTdfWithDigest`), atomically writing under `HostFileLockManager` (`withExclusiveTargetLock`), watching (`watchTdfChanges`), selecting, moving, renaming, and deleting the local `.tdf` file, and implementing `AppLogSink` with 7-day / 5-file diagnostic log pruning. |
| `lib/repositories/location_repository.dart` | Abstract `LocationRepository`, `PlatformLocationRepository`, and `FakeLocationRepository` isolating native `de.akjir.tiertask/location` `MethodChannel` queries, 100-meter Haversine displacement-gated HTTPS reverse geocoding, bounded Nominatim forward geocoding (`searchLocations`), and 30-minute cached HTTPS GeoIP desktop fallback. |
| `lib/repositories/settings_repository.dart` | Abstract `SettingsRepository`, `SecureSettingsRepository` (split host-local `settings.json` with `HostFileLockManager` locking, atomic writes, `.bak` rotation, quarantine, Android `Context.filesDir` resolution, deprecated one-time `TTW\x02` migration, and per-workspace `FlutterSecureStorage` WebDAV passwords and `TTS\x04` sync baselines), and `InMemorySettingsRepository`. |
| `lib/repositories/webdav_repository.dart` | Native `dart:io` `HttpClient` WebDAV repository (`WebDavRepository`, `WebDavErrorKind`, `WebDavException`) executing authenticated conditional HTTP `GET` (`fetchTdf` with `If-None-Match`, `If-Modified-Since`, and `304 Not Modified` handling), conditional `PUT` (`saveTdf` with strong `ETag` `If-Match` and tri-state `_cachedExists` `If-None-Match: *` initial-creation preconditions plus `412 Precondition Failed` cache invalidation, and `saveLog`), `DELETE` (`deleteLog`), and remote file wipe/re-initialization (`wipeTdf` with optional `.bak` / `.bak.001`+ backups). |
| `lib/repositories/window_control_repository.dart` | Abstract `WindowControlRepository`, `PlatformWindowControlRepository`, and `FakeWindowControlRepository` isolating native `de.akjir.tiertask/window_controls` `MethodChannel` commands for closing, dragging, and maximizing frameless desktop windows on Linux and Windows. |

## State Providers

| File | Function |
| :--- | :--- |
| `lib/providers/config_providers.dart` | Defines `settingsRepositoryProvider`, `localFileRepositoryProvider`, `webDavRepositoryProvider`, `webDavConfigProvider` (`WebDavConfigNotifier`, including `updateDueLeadWindow`), `boundaryTickProvider` (`BoundaryTickNotifier`), `appLocaleProvider`, `appThemeModeProvider`, `appThemePaletteProvider`, `diagnosticsEnabledProvider`, `appVersionRepositoryProvider`, `appVersionProvider`, `linkLauncherRepositoryProvider`, `supportsDesktopWindowControlsProvider`, and `windowControlRepositoryProvider`. |
| `lib/providers/local_file_watch_providers.dart` | Defines `LocalFileWatchTarget`, `LocalFileWatcherNotifier`, `localFileWatchDebounceProvider`, `localFileWatchTargetProvider`, and `localFileWatcherProvider` for scoped parent-directory `.tdf` watching, `350 ms` trailing-edge debouncing, missing-directory rebinding, and `AppLifecycleState.resumed` catch-up reconciliation. |
| `lib/providers/location_providers.dart` | Defines `locationEnabledProvider`, `locationRepositoryProvider`, `locationStateProvider`, and `LocationNotifier` managing foreground-only location determination with startup/enable triggers, 5-minute app-resume cooldown, 15-minute passive foreground refresh, and manual refresh (`refreshLocation`). |
| `lib/providers/sync_providers.dart` | Defines `SyncState`, `syncStateProvider` (`SyncStateNotifier`), `StorageFileReadException`, `UnsupportedTdfVersionException`, and the stateless multi-stage `tdf 0.8.0` synchronization pipeline (`TaskSyncPipeline`) coordinating stage-fair merges, host-locked local and WebDAV `HTTP 412` CAS retries, 30-day pruning, per-file local/remote readability diagnostics, and conflict/recovery banners. |
| `lib/providers/task_providers.dart` | Defines `taskNotifierProvider`, `taskUndoStateProvider`, `localFileWatchReadRetryDelayProvider`, `TaskUndoNotice`, `TaskUndoState`, `TaskUndoStateNotifier`, and `TaskNotifier` orchestrating domain mutations, in-memory `DueLeadWindow` re-evaluation, bounded 10-entry LIFO undo recovery (`undoLastAction`), `resolveDeletionConflicts` and `resolveRecovery` (`TDF-DEL-003` / `TDF-REC-002` with immediate undo stack invalidation), digest-gated external local reconciliation (`reconcileExternalLocalChanges`), workspace unload flushing, local file selection, remote wipe, and multi-stage synchronization. |
| `lib/providers/workspace_providers.dart` | Defines `activeWorkspaceProvider`, `appBuildProfileProvider`, `settingsDirectoryPathProvider`, `settingsRepositoryProvider`, `workspaceSummariesProvider`, `workspaceUnloadCoordinatorProvider` (`WorkspaceUnloadCoordinator`), and `ActiveWorkspaceNotifier` orchestrating single-active-workspace switching (`switchWorkspace`), creation (`createWorkspace`), renaming (`renameWorkspace`), and deletion (`deleteWorkspace`). |

## Presentation

| File | Function |
| :--- | :--- |
| `lib/presentation/app_shell_controller.dart` | Coordinates adaptive shell routes, `ShellReturnContext`, single-expand entity cards, inline editing, uncommitted drafts, external board updates, and `Escape`/`PopScope` unwinding (`AppShellController`, `appShellControllerProvider`). |
| `lib/presentation/board_boundary_timer.dart` | Single-timer wall-clock boundary scheduler (`BoardBoundaryTimer`, `boardBoundaryTimerProvider`) monitoring foreground lifecycle state, workspace time zone, and due lead windows to advance `boundaryTickProvider` at exact suspension and deadline transitions. |
| `lib/presentation/board_presentation_providers.dart` | Shared lower-level presentation providers (`AppVersionViewModel`, `appVersionViewModelProvider`, `evaluatedBoardProvider`, `TdfPreviewController`, `TdfPreviewResult`, `TdfPreviewSuccess`, `TdfPreviewLimitExceeded`, `tdfPreviewControllerProvider`) exposing evaluated boards, formatted SemVer builds, and canonical `.tdf` previews. |
| `lib/presentation/entity_controller.dart` | Owns model-free label and location Quick-Create, draft cards, inline editors, live board scope toggles, and geocoding/Plus Code resolution (`EntityController`, `EntityControllerState`, `entityControllerProvider`, `LocationSourceUiResult`). |
| `lib/presentation/entity_view_models.dart` | Projects immutable label and location manager ViewModels (`LabelsManagerViewModel`, `LabelCardViewModel`, `LocationsManagerViewModel`, `LocationCardViewModel`, `labelsManagerViewModelProvider`, `locationsManagerViewModelProvider`). |
| `lib/presentation/floating_notice_controller.dart` | Manages floating toast notices, LIFO Undo recovery notifications, auto-hide timers, and early/async startup recovery alerts (`FloatingNoticeController`, `floatingNoticeControllerProvider`). |
| `lib/presentation/link_action_controller.dart` | Reference link launch controller (`LinkActionController`, `LinkOpenOutcome`, `linkActionControllerProvider`) validating and opening external URIs through `LinkLauncherRepository` with typed `opened` and `failed` outcomes. |
| `lib/presentation/location_source_resolver.dart` | Location source resolver (`LocationSourceResolver`, `LocationSourceResolutionResult`, `locationSourceResolverProvider`) coordinating live GPS coordinates, forward-geocoding address candidates, and offline Plus Code decoding and recovery. |
| `lib/presentation/log_viewer_controller.dart` | Diagnostic log presentation controller (`LogViewerController`, `DiagnosticLogViewModel`, `DiagnosticLogLineViewModel`, `DiagnosticLogLevel`, `DiagnosticLogTag`, `DiagnosticLogSeverity`, `LogSyncResult`, `activeLogFileNameProvider`, `logViewerControllerProvider`) exposing reactive log snapshots, filtering, clearing, and WebDAV syncing. |
| `lib/presentation/settings_controller.dart` | Owns model-free dual-persistence Settings state, auto-saved preferences, dirty WebDAV validation, and capability-gated local file and wipe actions (`SettingsController`, `SettingsViewModel`, `settingsControllerProvider`). |
| `lib/presentation/settings_storage_controller.dart` | Shared settings persistence and native file/directory picker facade (`SettingsStorageController`, `SettingsPreferenceSaveResult`, `settingsStorageControllerProvider`, `supportsNativeDirectoryPickerProvider`) managing preference saves, startup recovery consumption, and path preview resolution. |
| `lib/presentation/shell_chrome_view_models.dart` | Projects immutable theme, top chrome, sidebar navigation, and raw TDF preview ViewModels (`shellThemeStateProvider`, `boardChromeViewModelProvider`, `sidebarViewModelProvider`, `rawTdfViewModelProvider`). |
| `lib/presentation/shell_models.dart` | Defines immutable model-free presentation enums, shell navigation state, return context, floating notice, and action outcome types (`AppShellState`, `ShellView`, `ShellTier`, `FloatingNotice`, `ActionResult`). |
| `lib/presentation/sync_controller.dart` | Projects foreground location status and `TDF-DEL-003`/`TDF-REC-002` resolution views (`SyncController`, `syncControllerProvider`), owning sync/retry intents and conflict/recovery decision state (`ConflictDecisionsNotifier`, `RecoveryDecisionsNotifier`). |
| `lib/presentation/task_controller.dart` | Owns model-free task intents for non-jumping Quick-Add, draft creation, live controls, subtasks, history journal, and single-section inline editors (`TaskController`, `TaskControllerState`, `taskControllerProvider`). |
| `lib/presentation/task_schedule_helper.dart` | Pure scheduling, recurrence, history validation, and remaining-duration formatting subsystem (`TaskScheduleHelper`, `ResolvedDueDraft`, `ResolvedSuspendedDraft`, `taskScheduleHelperProvider`) supporting local wall-clock drafts and `due.anchor` preservation. |
| `lib/presentation/tasks_view_model.dart` | Projects immutable six-tier task lists, Global Search results, full-screen error states, and prerequisite candidates (`tasksViewModelProvider`, `taskPrerequisiteCandidatesProvider`, `TasksViewModel`, `TaskCardViewModel`). |
| `lib/presentation/ui_telemetry.dart` | Presentation-layer diagnostic telemetry facade (`UiTelemetry`) emitting redacted structured `LogTag.ui` events to `AppLogger` while keeping `lib/ui/` free of direct `lib/services/` imports. |
| `lib/presentation/view_model_primitives.dart` | Defines shared immutable cross-view value models (`CardBadgeViewModel`, `ConditionDraftViewModel`, `EntityLinkViewModel`, `FileReadReportViewModel`, `LabelPickerOptionViewModel`, `LocationOptionViewModel`, `ShellBannerViewModel`) and stateless `ViewModelFormatters`. |
| `lib/presentation/window_control_controller.dart` | Mediates desktop-only frameless chrome drag, maximize/restore, and close commands between `lib/ui/` and `WindowControlRepository` (`WindowControlController`, `windowControlControllerProvider`). |
| `lib/presentation/workspace_controller.dart` | Projects workspace summary rows and owns model-free workspace switching, creation, renaming, and deletion intents (`WorkspaceController`, `WorkspaceControllerState`, `workspaceControllerProvider`). |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/main.dart` | Application entry point registering global crash hooks (`FlutterError.onError`, `PlatformDispatcher.instance.onError`) and `AppLifecycleListener`, mounting `TierTaskApp` inside `ProviderScope` with `UiThemePresets` (`shellThemeStateProvider`), `AppLocalizations`, and `TierTaskShellScreen`. |
| `lib/ui/dialogs/compact_label_picker_sheet.dart` | Unified compact mobile label picker bottom sheet (`showCompactLabelPickerSheet`) with scope filtering, multi-selection, and inline label creation. |
| `lib/ui/dialogs/geocoding_candidates_modal.dart` | Forward-geocoding candidate disambiguation modal (`showGeocodingCandidatesModal`) allowing users to select from bounded address search matches. |
| `lib/ui/dialogs/local_file_modals.dart` | Local `.tdf` file selection and rename modals (`showSelectLocalFileModal`, `showRenameLocalFileModal`) with single-segment filename validation and capability-gated native pickers. |
| `lib/ui/dialogs/location_status_modal.dart` | Foreground location status modal (`showLocationStatusModal`) displaying fix status, resolved place name, WGS-84 coordinates, source, and manual refresh trigger. |
| `lib/ui/dialogs/wipe_tdf_modal.dart` | Typed-filename destructive Local and Remote `.tdf` wipe confirmation modal (`showWipeTdfModal`) with optional `.bak` backup toggle. |
| `lib/ui/dialogs/workspaces_modal.dart` | Workspace management modal (`showWorkspacesModal`) coordinating workspace switching, creation, inline renaming, and inline delete confirmation. |
| `lib/ui/tier_task_shell_screen.dart` | Adaptive root shell (`TierTaskShellScreen`) integrating `UiAdaptiveAppShell`, top chrome bar, sidebar/drawer, view router, floating notice host, desktop keyboard shortcuts, and `PopScope` unwinding. |
| `lib/ui/ui_icon_mapper.dart` | Stateless visual mapper (`UiIconMapper`) translating presentation enums into `tiertask_ui` theme presets, semantic tones, theme modes, and canonical outline icons. |
| `lib/ui/views/label_card.dart` | Unified expandable label card and uncommitted draft card (`LabelCard`, `LabelDraftCard`) supporting inline name, HSV color wheel, board scope, note, links, and inherited conditions. |
| `lib/ui/views/labels_view.dart` | Labels manager view (`LabelsView`) combining header, inline quick-create bar, draft card slot, and virtualized label list. |
| `lib/ui/views/location_card.dart` | Unified expandable geofence card and uncommitted draft card (`LocationCard`, `LocationDraftCard`) supporting inline name, GPS/address/Plus Code resolution, radius, and notes. |
| `lib/ui/views/locations_view.dart` | Locations manager view (`LocationsView`) combining header, inline quick-create bar, draft card slot, and virtualized location list. |
| `lib/ui/views/log_viewer_view.dart` | Diagnostic log viewer view (`LogViewerView`) rendering session metadata, level and tag filters, severity-highlighted monospace lines, and copy, upload, scroll, and clear actions. |
| `lib/ui/views/raw_tdf_view.dart` | Raw `tdf 0.8.0` preview view (`RawTdfView`) displaying canonical `LF` output, byte/line stats, copy action, and `1 MiB` limit-exceeded state. |
| `lib/ui/views/resolution_views.dart` | Pure `TDF-DEL-003` deletion conflict and `TDF-REC-002` generation recovery views (`DeletionConflictView`, `GenerationRecoveryView`, `ResolutionActionDock`) backed by `sync_controller.dart` decision providers. |
| `lib/ui/views/settings_view.dart` | Settings view (`SettingsView`, `SettingsActionDock`) separating auto-saved preferences from dirty-tracked WebDAV credentials, local storage actions, Danger Zone, and docked footer controls. |
| `lib/ui/views/task_card.dart` | Unified single-expand task card (`TaskCard`) supporting collapsed badge overflow (`3` + `+N more`), live completion/downgrade/placement controls, inline section editors, and read-only completed mode. |
| `lib/ui/views/task_detail_editors.dart` | Inline task detail section editors (`TaskSubtasksSection`, `TaskHistorySection`, `TaskPrerequisitesSection`) and shared checklist widgets (`TaskSubtaskCheckBoxButton`, `EditableSubtaskRow`). |
| `lib/ui/views/task_draft_card.dart` | Uncommitted inline task creation draft card (`TaskDraftCard`) configuring details, scheduling, recurrence, labels, subtasks, prerequisites, links, and conditions before saving. |
| `lib/ui/views/task_schedule_editors.dart` | Inline task title and scheduling editors (`TaskInlineTitleEditor`, `TaskDueSection`, `TaskRepeatSection`, `TaskSuspendedSection`) with local wall-clock pickers, `due.anchor` details, and notes. |
| `lib/ui/views/tasks_view.dart` | Primary six-tier Tasks and Global Search view (`TasksView`, `TasksQuickAddDock`) rendering banners, full-screen errors, draft card, virtualized task cards, and pinned Quick-Add dock. |
| `lib/ui/widgets/entity_card_chrome.dart` | Shared expanded entity header, inline delete confirmation, error text, and editor/modal action footers (`EntityCardMetaBar`, `EntityInlineEditorFooter`, `EntityInlineErrorText`, `EntityModalActionFooter`). |
| `lib/ui/widgets/entity_conditions_section.dart` | Shared activation conditions section (`EntityConditionsSection`) managing weekday (`day`), time-window (`time`), geofence (`location`), and reset (`any`) rules. |
| `lib/ui/widgets/entity_date_time_fields.dart` | Shared hybrid typed and picker local date/time input widgets (`EntityHybridDateTimeField`, `EntityHybridTimeField`) and time-minute parsing helper (`parseEntityTimeMinutes`). |
| `lib/ui/widgets/entity_label_picker.dart` | Shared searchable multi-select label picker (`EntitySearchableLabelPicker`) with board-scope filter tabs and inline label creation. |
| `lib/ui/widgets/entity_links_section.dart` | Shared ordered reference links section (`EntityLinksSection`) supporting URI launching, inline editing, reordering, and deletion within the `N / 20` cap. |
| `lib/ui/widgets/entity_note_section.dart` | Shared entity note viewer and inline multiline editor (`EntityNoteSection`) with clipboard copy and explicit save/cancel controls. |

## UI Component Library

| File | Function |
| :--- | :--- |
| `packages/tiertask_ui/lib/tiertask_ui.dart` | Sole public barrel entrypoint for `package:tiertask_ui` exporting Layer 1 tokens, Layer 2 primitives, Layer 3 layouts, and Layer 4 composites. |
| `packages/tiertask_ui/lib/src/tokens/ui_breakpoints.dart` | Defines `UiViewportClass` (`compact`, `medium`, `expanded`) and stateless `UiBreakpoints` width classification helpers (`<= 720`, `721..820`, `> 820`). |
| `packages/tiertask_ui/lib/src/tokens/ui_color_tokens.dart` | Defines immutable 19-role `UiColorTokens`, `UiContrastPair`, `UiContrastFailure`, and stateless `UiContrastChecker` validating WCAG 2.1 AA (`>= 4.5:1`) contrast across all 17 normative pairs. |
| `packages/tiertask_ui/lib/src/tokens/ui_focus_tokens.dart` | Defines immutable `UiFocusTokens` holding `1px` focus-ring geometry, transition durations, dimmed opacities, and the 5 allowlisted overlay shadows. |
| `packages/tiertask_ui/lib/src/tokens/ui_radius_tokens.dart` | Defines immutable `UiRadiusTokens` holding corner radii (`2px` to `999px`) and canonical stroke widths (`1.0`, `1.7`, `2.5`). |
| `packages/tiertask_ui/lib/src/tokens/ui_spacing_tokens.dart` | Defines immutable `UiSpacingTokens` holding the spacing ladder, touch-target densities (`26px` to `44px`), shell dimensions, canonical `EdgeInsets`, and icon sizes (`13/15/18/34px`). |
| `packages/tiertask_ui/lib/src/tokens/ui_theme_tokens.dart` | Defines `UiSurfaceLevel`, `UiSurfaceScope` for automatic `bg`/`panel` alternation, `UiThemeTokens` (`ThemeExtension` + flat Material 3 `toThemeData`), `UiThemePreset`, and `UiThemePresets` (`Calm` and `Plum Umber`, Light and Dark). |
| `packages/tiertask_ui/lib/src/tokens/ui_typography_tokens.dart` | Defines immutable `UiTypographyTokens` covering all 14 scale roles plus `mono` and `tabular` (`FontFeature.tabularFigures`) helpers. |
| `packages/tiertask_ui/lib/src/primitives/ui_app_logo.dart` | Renders the minimal three-bar stepped TierTask accent brand mark (`UiAppLogo`, `UiLogoBarSpec`) via `CustomPaint` wrapped in `ExcludeSemantics`. |
| `packages/tiertask_ui/lib/src/primitives/ui_banner.dart` | Renders unified feedback surfaces (`UiBanner`, `UiBannerVariant`, `UiBannerTone`) for status banners, `620px` floating toasts, inline warnings, inline delete confirmations, plain-text empty states, loading spinners, and full-screen errors. |
| `packages/tiertask_ui/lib/src/primitives/ui_button.dart` | Renders flat interactive buttons (`UiButton`, `UiButtonVariant`, `UiButtonDensity`, `UiButtonTone`) with `1px` keyboard focus rings, active/loading states, danger hover, and `0.48` disabled opacity. |
| `packages/tiertask_ui/lib/src/primitives/ui_card.dart` | Renders flat bordered cards (`UiCard`, `UiCardVariant`: `standard`, `inset` with unconditional `UiSurfaceScope.insetWell`, `draft`, and unified single-expand `expandable` entity accordions). |
| `packages/tiertask_ui/lib/src/primitives/ui_field.dart` | Renders surface-aware flat `1px` inputs (`UiField`, `UiFieldKind`, `UiSelectOption`) for text, multiline, password reveal, flat select, date/time display, focus-within search, and monospace read-only wells. |
| `packages/tiertask_ui/lib/src/primitives/ui_pill.dart` | Renders surface-aware pills (`UiPill`, `UiPillVariant`, `UiPillTone`) covering badges, tabular count capsules, color-dotted tags, split navigable/removable chips, dashed/direct add chips, and selectable toggles. |
| `packages/tiertask_ui/lib/src/primitives/ui_segmented_control.dart` | Renders equal-width horizontal segmented controls (`UiSegmentedControl`, `UiSegment`) in a `bg` trough with `ArrowLeft`/`ArrowRight` keyboard stepping. |
| `packages/tiertask_ui/lib/src/primitives/ui_toggle_row.dart` | Renders full-row checkbox controls (`UiToggleRow`) with optional muted descriptions and standard/dense target heights. |
| `packages/tiertask_ui/lib/src/layout/ui_adaptive_app_shell.dart` | Coordinates the `62px` top chrome bar, persistent `244px` sidebar vs below-chrome compact slide-over drawer, lazy-list viewport stack with floating notices, and decoupled pinned bottom dock (`UiAdaptiveAppShell`). |
| `packages/tiertask_ui/lib/src/layout/ui_page_header.dart` | Renders view headers (`UiPageHeader`) with optional back button, `28px` title, clickable inline active-label filter, tabular count capsule, trailing action cluster, and `58ch` subtitle. |
| `packages/tiertask_ui/lib/src/layout/ui_responsive_grid.dart` | Renders equal-width top-aligned adaptive grids (`UiResponsiveGrid`, `UiGridPreset`) collapsing cleanly at `820px` and `720px` with zero horizontal overflow. |
| `packages/tiertask_ui/lib/src/layout/ui_sidebar_section.dart` | Renders static and collapsible/filterable sidebar navigation groups (`UiSidebarSection`, `UiSidebarNavItem`) with collapsed summaries, 3 header icon actions, inline filtering, and split or single-button rows. |
| `packages/tiertask_ui/lib/src/components/ui_color_wheel.dart` | Renders inline swatch, `#RRGGBB` input, 8 canonical preset chips, and a `ValueNotifier`-driven circular HSV wheel modal (`UiColorWheel`). |
| `packages/tiertask_ui/lib/src/components/ui_dialog_frame.dart` | Renders three-part modal dialog frames (`UiDialogFrame`, `UiDialogSize`) and focus-trapped modal/compact bottom-sheet presenters (`showModal`, `showBottomSheet`) with `Tab` trapping, `Escape` dismissal, and focus restoration. |
| `packages/tiertask_ui/lib/src/components/ui_ordered_item_list.dart` | Renders repeatable ordered lists (`UiOrderedItemList`) with deterministic keys, optional progress track, inline editing highlight, boundary-disabled reorder controls, edit/delete actions, and add/footer slots. |
| `packages/tiertask_ui/lib/src/components/ui_quick_composer.dart` | Renders docked Task Quick-Add (with compact `+ New task` collapse and upward non-swallowing `TapRegion` desktop popover) and inline entity Quick-Create bars (`UiQuickComposer`). |
| `packages/tiertask_ui/lib/src/components/ui_searchable_picker.dart` | Renders searchable multi-select and single-select pickers (`UiSearchablePicker`, `UiPickerSelectionMode`, `UiPickerOption`, `UiPickerScopeFilter`) with conditional scope pills, inline creation, cycle-disabled rows, keyboard navigation, and non-autofocus compact sheets. |

## Execution & Synchronization Flow

1. **Startup, Workspace Loading & Locale Resolution:** `main.dart` registers global error handlers and initializes `ProviderScope`. `ActiveWorkspaceNotifier` (`lib/providers/workspace_providers.dart`) loads only the single active `AppWorkspace` (`Tasks` / `tasks.tdf` by default) from `SettingsRepository`, `WebDavConfigNotifier` (`lib/providers/config_providers.dart`) exposes its `WebDavConfig`, and `shellThemeStateProvider` (`lib/presentation/shell_chrome_view_models.dart`) resolves the active `Locale`, `UiThemePresets` preset (`Calm` or `Plum Umber`), and theme mode for `TierTaskShellScreen` (`lib/ui/tier_task_shell_screen.dart`). Switching workspaces at runtime via `ActiveWorkspaceNotifier.switchWorkspace` unloads the current `TaskBoard` and `SyncState` from memory and loads the selected `AppWorkspace` and its `.tdf` file without restarting the application.
2. **Multi-Stage TDF Fetch, External Directory Watching & Three-Way Merge (`In-Memory <-> Local File <-> WebDAV`):** On startup, on every manual sync (`syncFromRemote`, `testConnectionAndSync`), on external local `.tdf` edits detected via `LocalFileWatcherNotifier` (`350 ms` trailing-edge debounced `Directory.watch` events and `AppLifecycleState.resumed` catch-up checks gated by `WebDavConfig.localWatchEnabled` and `WorkspaceSyncState.localSourceDigest` inside `TaskNotifier.reconcileExternalLocalChanges`), and on every saved mutation or conflict/recovery resolution (`resolveDeletionConflicts`, `resolveRecovery`), `TaskNotifier` (`lib/providers/task_providers.dart`) delegates to `TaskSyncPipeline` (`lib/providers/sync_providers.dart`): Stage 1 acquires the non-blocking host-local cooperative lock (`HostFileLockManager` via `LocalFileRepository.withExclusiveTargetLock`), reads the local `.tdf` file (`LocalFileRepository.readTdfWithDigest`), merges external local `tdf 0.8.0` changes with the in-memory `TaskBoard` across `task`, `location`, `label`, `queue`, and `deleted` (`generation`) via `TaskBoardSync.merge` using `TdfCleanupMode.deferred` when WebDAV Stage 2 follows (`TdfCleanupMode.finalStage` in `StorageMode.local`), and atomically replaces the local file via guarded CAS publication (`_publishLocalWithCasLoop`); Stage 2 seeds `WebDavRepository` with the persisted `remoteEtag`, `remoteLastModified`, and canonical `lastSyncedRemoteTdf` baseline, fetches the remote `.tdf` file (`WebDavRepository.fetchTdf` using `If-None-Match` and `If-Modified-Since` to short-circuit unchanged remote files on `HTTP 304 Not Modified`), merges concurrent remote changes in `TdfCleanupMode.finalStage` with authoritative 30-day retention pruning (`TDF-PUB-004`), writes changed `tdf 0.8.0` documents to WebDAV with `If-Match` / `If-None-Match: *` CAS retry (`_publishRemoteWithCasLoop` on `HTTP 412 Precondition Failed`), and in Stage 3 converges the local `.tdf` file (`TdfCleanupMode.finalStage` with symmetric generation refresh) and `WorkspaceSyncState` (`TTS\x04`: canonical `lastSyncedLocalTdf` and `lastSyncedRemoteTdf`, `acknowledgedLocalGeneration`, `acknowledgedRemoteGeneration`, `localSourceDigest`, `remoteSourceDigest`, `remoteEtag`, `remoteLastModified`) so both storage backends converge to byte-identical `tdf 0.8.0` documents.
3. **Single-Pass Parse & Dynamic 6-Tier Derivation:** `TdfService.parse` (`TdfScanner`, `TdfParser`, `TdfDirectiveParser`) validates the strict single-version `tdf 0.8.0` header (`TDF-COMPAT-001`), scans and validates `queue`, `deleted`, `location`, `label`, and `task` blocks in a single $O(N)$ pass (interpreting `created`, `finished`, `modified`, `due`, `history`, and timed `suspended` in UTC alongside optional local `due.anchor` calendar tuples while evaluating `condition day`, `condition time`, and `repeat` calendar progression in the workspace's `TDF-CTX-001` local time zone), and invokes `TaskBoard.evaluate` (`TaskBoardEvaluator`) to derive `Completed`, `Someday` (open tasks omitted from `queue` without an active `suspended` lock), `Blocked`, and the `queue`-ordered active tiers (`Focus`, `Ready`, `Planned`, with configurable per-workspace non-`passive` `due` lead-window auto-promotion defaulting to `24` hours, and `scoped` label queue partitioning) per `spec/TDF_SPEC_0.8.0.md` Section 9.
4. **Mutation, Undo & Persistence:** Every user action advances the mutated entity's (and `queue` block's when reordered) UTC `modified` timestamp monotonically (`TaskItem.nextModifiedTimestamp`), cleans expired finite `suspended` locks and resolved one-shot `blocked` prerequisites on open tasks, records explicit task, location, and label deletions in `deleted` (`TdfDeletedBlock`) via `TaskBoardMutator` and `TaskBoardQueueMutator`, captures bounded 10-entry in-memory LIFO undo snapshots (`TaskBoardUndo`) for task completion, downgrade, and deletion (clearing the undo stack immediately upon conflict or recovery resolution), triggers `TaskSyncPipeline`, serializes byte-exact canonical `LF`-terminated `tdf 0.8.0` output via `TdfService.serialize` (`TdfSerializer`), and persists the converged `.tdf` document and `TTS\x04` sync baselines across the configured local and WebDAV targets.
5. **Opt-In Diagnostic Logging & Local/WebDAV Persistence (`AppLogger`):** All layers (`LIFECYCLE`, `TDF`, `DOMAIN`, `SYNC`, `STORAGE`, `UI`) report structured `<UTC-ISO> [<LEVEL>] [<TAG>] <event> | <key=value ...>` events to `AppLogger` (at DAG rank `0`, decoupled from `dart:io` via `AppLogSink` and `LocalFileLogSink`). When `diagnosticsEnabled` is `false` or an entry is below `minimumLevel`, logging calls are zero-allocation no-ops. When enabled, `AppLogger` writes a 5-line `@meta` header block to `tiertask_<YYYY-MM-DD>_<platform>_<workspaceId>.log`, prunes expired local logs (`7` days / `5` files per workspace), preserves logs across clean `detached` exits (`session.exit | state=detached crashed=false`), appends a recovery banner on startup after an unclean exit, flushes `[CRASH]` stack traces via `FlutterError.onError` and `PlatformDispatcher.instance.onError`, and uploads log snapshots to WebDAV (`WebDavRepository.saveLog`) via a 5-second debounce and `inactive`/`paused` lifecycle hooks when `logStorageMode` includes WebDAV.
