# TierTask Architecture and File Structure

> [!IMPORTANT]
> Update this file, [`AGENTS.md`](AGENTS.md), [`spec/TDF_SPEC_0.8.0.md`](spec/TDF_SPEC_0.8.0.md), and [`spec/UI_DESIGN_SYSTEM.md`](spec/UI_DESIGN_SYSTEM.md) whenever the architecture, supported target platforms, directory layout, file responsibilities, localization files, UI design guidelines, or TDF synchronization flow change.

## Architectural Layers

| Layer | Path | Responsibility |
| :--- | :--- | :--- |
| Localization | `lib/l10n/` | External English (`app_en.arb`) and German (`app_de.arb`) resource bundles, generated `AppLocalizations` classes, `TaskTier` and `WorkspaceException` mappings, and per-file readability localization extensions. |
| Models | `lib/models/` | Immutable domain data structures (`AppWorkspace`, `WorkspaceSummary`, `WorkspaceException`, `WorkspaceErrorKind`, `PersistedSettingsDocument`, `SettingsCodec`, `SettingsDecodeResult`, `SettingsDecodeWarning`, `SettingsRecoveryKind`, `SettingsRecoveryNotice`, `GeocodingCandidate`, `LocationFix`, `LocationSource`, `LocationSourceType`, `LocationState`, `LocationStatus`, `StorageFileTarget`, `StorageFileReadState`, `StorageReadFailureScope`, `StorageFileReadStatus`, `StorageFileReadReport`, `TaskTier`, `QuickAddMode`, `TaskItem`, `TaskOrigin`, `SubtaskItem`, `TaskHistoryEntry`, `TaskLink`, `RepeatUnit`, `TaskRepeatRule`, `ConditionGroup`, `TaskCondition`, `TdfFilePath`, `TdfLocation`, `TdfLabel`, `TdfColor`, `TdfQueueBlock`, `TdfDeletionRecord`, `TdfDeletedBlock`, `TdfTaskDependency`, `TdfCleanupMode`, `TdfBoundDeletionDecision`, `TdfRecoveryResolution`, `TdfSyncOutcomeException`, `TdfContextException`, `TdfErrorKind`, `TdfException`, `TdfLocalDateTime`, `TdfRepeatClock`, `TdfTimeZoneContext`, `TdfCalendar`, `TdfPayloadComparison`, `TaskBoard`, `TaskBoardEvaluator`, `TaskBoardMutator`, `TaskBoardQueueMutator`, `TaskBoardSync`, `TaskBoardReconciler`, `TaskBoardUndo`, `WorkspaceSyncState`, `AppLanguage`, `AppThemeMode`, `AppThemePalette`, `AppTimeZoneMode`, `DueLeadWindow`, `StorageMode`, `WebDavConfig`) and the dynamic $O(N)$ 6-tier derivation, mutation, undo, and three-way synchronization pipeline. |
| Services | `lib/services/` | Opt-in diagnostic logging service (`AppLogger`, `AppLogSink`, `LogLevel`, `LogTag`) at DAG rank `0`, stateless single-pass $O(N)$ RFC 4648 Base64 codec (`Base64Service`, `Base64Exception`, `Base64ErrorKind`), Open Location Code parser and decoder (`PlusCodeService`, `PlusCodeArea`, `PlusCodeInput`), pure-Dart FIPS 180-4 SHA-256 digest service (`Sha256Service`), and TDF `0.8.0` lexical scanner (`TdfScanner`), structural parser (`TdfParser`, `TdfDirectiveParser`), and byte-exact canonical `LF` serializer (`TdfSerializer`, `TdfService`). |
| Repositories | `lib/repositories/` | All external I/O: pooled WebDAV HTTP `GET`/`PUT` (`dart:io` `HttpClient`), pure-Dart `dart:ffi` non-blocking host-local cooperative file locking and atomic temp-file publication (`HostFileLockManager`), local `.tdf` and dated log I/O with `Isolate.run` offloading `>= 32 KiB` (`LocalFileRepository`, `LocalFileOperations`, `LocalFileLogSink`), foreground location channel and pooled HTTPS geocoding/GeoIP lookup (`MethodChannel` and `HttpClient`), launch-time URI-validated external link launching, and host-local `settings.json` (`.bak` + quarantine) plus atomic `sync_state_<workspaceId>.tts` baselines (`TTS\x04`), reserving `flutter_secure_storage` exclusively for WebDAV passwords. |
| Providers | `lib/providers/` | Riverpod state management (`Provider`, `Notifier`, `AsyncNotifier`) across `18` acyclic leaves coordinating single-active-workspace switching (`workspace_providers.dart`), storage-scoped repository wiring and optimistic FIFO preferences (`config_providers.dart`), `.tdf` file watching (`local_file_watch_providers.dart`), foreground location (`location_providers.dart`), multi-stage sync and `.autoDispose` resolution decisions (`sync_providers.dart`, `sync_error_formatter.dart`), domain mutations and atomic undo (`task_providers.dart`), and domain-typed UI coordination (`board_providers.dart`, `shell_providers.dart`, `floating_notice_providers.dart`, `log_viewer_providers.dart`, `task_schedule_helper.dart`, `task_condition_draft_helper.dart`, `location_source_resolver.dart`, `settings_draft_providers.dart`, `board_actions_provider.dart`, `entity_actions_provider.dart`, `ui_telemetry.dart`). |
| Design System | `lib/ui/{tokens,primitives,layout,components}/` | Integrated four-sub-rank universal design system (`24` leaves across `tokens`, `primitives`, `layout`, and `components`) implementing `Calm` (default) and `Plum Umber` WCAG AA Light/Dark tokens, `8` core primitives, `4` adaptive layouts, and `5` domain-agnostic composites with zero imports from app UI, `lib/models/`, `lib/l10n/`, `lib/services/`, `lib/repositories/`, `lib/providers/`, `flutter_riverpod`, `dart:io`, or `dart:ffi`. |
| UI | `lib/ui/`, `lib/main.dart` | Production adaptive shell (`29` app UI leaves across root shell/mapper, `dialogs/`, `widgets/`, and `views/`, plus `lib/main.dart`) consuming domain models, `AppLocalizations`, integrated design-system widgets, and granular `.select(...)` / `.autoDispose` Riverpod providers directly while forbidding direct `lib/repositories/`, `dart:io`, `dart:ffi`, and `HttpClient` imports. |

> [!NOTE]
> Per Google's Flutter App Architecture guidelines (`P-UDF-ARCHITECTURE`, `P-ACYCLIC-DAG`, `P-IO-ISOLATION`, `P-WEBDAV-API`, `P-GLOBAL-ERROR-BOUNDARY`, `P-ATOMIC-STATE`, `P-SECRET-HYGIENE`, `P-TRANSPORT-SECURITY`), data flows unidirectionally from single-source-of-truth repositories (`lib/repositories/`) through state providers (`lib/providers/`) to consumer views (`lib/ui/`), enforcing strict 8-rank bottom-up DAG order (`0: lib/services/app_logger.dart < 1: lib/models/* < 2: lib/l10n/* < 3: lib/services/* < 4: lib/repositories/* < 5: lib/providers/* < 6: lib/ui/* < 7: lib/main.dart`) with `0` circular import SCCs and an unconditional ban on `export`/`part`/`part of` directives. Inside `lib/ui/`, universal Design System leaves obey strict internal sub-rank order (`tokens (0) < primitives (1) < layout (2) < components (3)`) with zero app-UI, domain, or Riverpod imports; app `lib/ui/` freely imports `lib/models/`, `lib/l10n/`, pure `lib/services/`, `lib/providers/`, and `flutter_riverpod` while forbidding direct `lib/repositories/` imports; all network (`HttpClient`), native OS locking (`dart:ffi`), local filesystem (`File`), and secure storage (`FlutterSecureStorage`) operations are strictly isolated in `lib/repositories/`; global error boundaries (`FlutterError.onError` and `PlatformDispatcher.instance.onError`) guard runtime stability; and credentials are redacted from logs and error messages.

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
│   │   ├── location_state.dart
│   │   ├── settings_codec.dart
│   │   ├── storage_file_read_status.dart
│   │   ├── task_board.dart
│   │   ├── task_board_evaluator.dart
│   │   ├── task_board_mutator.dart
│   │   ├── task_board_queue_mutator.dart
│   │   ├── task_board_reconciler.dart
│   │   ├── task_board_recovery.dart
│   │   ├── task_board_sync.dart
│   │   ├── task_board_sync_scoping.dart
│   │   ├── task_board_undo.dart
│   │   ├── task_item.dart
│   │   ├── task_tier.dart
│   │   ├── tdf_entity_merger.dart
│   │   ├── tdf_error.dart
│   │   ├── tdf_file_path.dart
│   │   ├── tdf_location.dart
│   │   ├── tdf_metadata.dart
│   │   ├── tdf_payload_comparison.dart
│   │   ├── tdf_sync_metadata.dart
│   │   ├── tdf_timezone.dart
│   │   ├── webdav_config.dart
│   │   └── workspace_sync_state.dart
│   ├── providers/
│   │   ├── board_actions_provider.dart
│   │   ├── board_providers.dart
│   │   ├── config_providers.dart
│   │   ├── entity_actions_provider.dart
│   │   ├── floating_notice_providers.dart
│   │   ├── local_file_watch_providers.dart
│   │   ├── location_providers.dart
│   │   ├── location_source_resolver.dart
│   │   ├── log_viewer_providers.dart
│   │   ├── settings_draft_providers.dart
│   │   ├── shell_providers.dart
│   │   ├── sync_error_formatter.dart
│   │   ├── sync_providers.dart
│   │   ├── task_condition_draft_helper.dart
│   │   ├── task_providers.dart
│   │   ├── task_schedule_helper.dart
│   │   ├── ui_telemetry.dart
│   │   └── workspace_providers.dart
│   ├── repositories/
│   │   ├── app_version_repository.dart
│   │   ├── host_file_lock.dart
│   │   ├── link_launcher_repository.dart
│   │   ├── local_file_operations.dart
│   │   ├── local_file_repository.dart
│   │   ├── location_repository.dart
│   │   ├── posix_file_lock_bindings.dart
│   │   ├── settings_repository.dart
│   │   ├── webdav_repository.dart
│   │   ├── win32_file_lock_bindings.dart
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
│       ├── ui_domain_mappers.dart
│       ├── components/
│       │   ├── ui_color_wheel.dart
│       │   ├── ui_dialog_frame.dart
│       │   ├── ui_ordered_item_list.dart
│       │   ├── ui_quick_composer.dart
│       │   └── ui_searchable_picker.dart
│       ├── dialogs/
│       │   ├── compact_label_picker_sheet.dart
│       │   ├── geocoding_candidates_modal.dart
│       │   ├── local_file_modals.dart
│       │   ├── location_status_modal.dart
│       │   ├── wipe_tdf_modal.dart
│       │   └── workspaces_modal.dart
│       ├── layout/
│       │   ├── ui_adaptive_app_shell.dart
│       │   ├── ui_page_header.dart
│       │   ├── ui_responsive_grid.dart
│       │   └── ui_sidebar_section.dart
│       ├── primitives/
│       │   ├── ui_app_logo.dart
│       │   ├── ui_banner.dart
│       │   ├── ui_button.dart
│       │   ├── ui_card.dart
│       │   ├── ui_field.dart
│       │   ├── ui_pill.dart
│       │   ├── ui_segmented_control.dart
│       │   └── ui_toggle_row.dart
│       ├── tokens/
│       │   ├── ui_breakpoints.dart
│       │   ├── ui_color_tokens.dart
│       │   ├── ui_focus_tokens.dart
│       │   ├── ui_radius_tokens.dart
│       │   ├── ui_spacing_tokens.dart
│       │   ├── ui_theme_tokens.dart
│       │   └── ui_typography_tokens.dart
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
│           ├── entity_inline_name_editor.dart
│           ├── entity_label_picker.dart
│           ├── entity_links_section.dart
│           ├── entity_note_section.dart
│           └── entity_reveal_scroll_controller.dart
└── test/
    ├── main_test.dart
    ├── l10n/
    │   ├── storage_file_read_localization_extension_test.dart
    │   └── tier_localization_extension_test.dart
    ├── models/
    │   ├── app_build_profile_test.dart
    │   ├── app_workspace_test.dart
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
    ├── providers/
    │   ├── board_actions_provider_test.dart
    │   ├── board_providers_test.dart
    │   ├── config_providers_test.dart
    │   ├── entity_actions_provider_test.dart
    │   ├── floating_notice_providers_test.dart
    │   ├── local_file_watch_providers_test.dart
    │   ├── location_providers_test.dart
    │   ├── location_source_resolver_test.dart
    │   ├── log_viewer_providers_test.dart
    │   ├── settings_draft_providers_test.dart
    │   ├── shell_providers_test.dart
    │   ├── sync_providers_test.dart
    │   ├── task_providers_test.dart
    │   ├── task_schedule_helper_test.dart
    │   ├── ui_telemetry_test.dart
    │   └── workspace_providers_test.dart
    ├── repositories/
    │   ├── app_version_repository_test.dart
    │   ├── host_file_lock_test.dart
    │   ├── link_launcher_repository_test.dart
    │   ├── local_file_operations_test.dart
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
    │   ├── tdf_performance_benchmark_test.dart
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
        ├── ui_domain_mappers_test.dart
        ├── components/
        │   ├── ui_color_wheel_test.dart
        │   ├── ui_dialog_frame_test.dart
        │   ├── ui_ordered_item_list_test.dart
        │   ├── ui_quick_composer_test.dart
        │   └── ui_searchable_picker_test.dart
        ├── layout/
        │   ├── ui_adaptive_app_shell_test.dart
        │   ├── ui_page_header_test.dart
        │   ├── ui_responsive_grid_test.dart
        │   └── ui_sidebar_section_test.dart
        ├── primitives/
        │   ├── ui_app_logo_test.dart
        │   ├── ui_banner_test.dart
        │   ├── ui_button_test.dart
        │   ├── ui_card_test.dart
        │   ├── ui_field_test.dart
        │   ├── ui_pill_test.dart
        │   ├── ui_segmented_control_test.dart
        │   └── ui_toggle_row_test.dart
        └── tokens/
            ├── ui_breakpoints_test.dart
            ├── ui_color_tokens_test.dart
            └── ui_theme_tokens_test.dart
```

## Root Files

| File | Function |
| :--- | :--- |
| `AGENTS.md` | Engineering rules, TDD workflow (`P-TDD-FIRST`), deterministic `.dart` file layout, and mandatory test categories. |
| `ARCHITECTURE.md` | Architectural layer definitions, directory structure, file inventory, and TDF synchronization flow. |
| `CHANGELOG.md` | User-facing change history following Keep a Changelog 1.1.0. |
| `README.md` | Project overview, supported platforms (Linux, Android, Windows), build instructions, and `.tdf` tier reference. |
| `analysis_options.yaml` | Dart analyzer configuration excluding `build/**`, `android/**`, `linux/**`, `windows/**`, and generated `lib/l10n/app_localizations*.dart` files. |
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
| `lib/models/app_build_profile.dart` | Defines `AppBuildProfile` (`release` and `dev`) resolving compile-time `TIERTASK_ENV` and `kReleaseMode` into isolated user data directories (`tiertask` vs `tiertask-dev`), per-workspace WebDAV password and sync key prefixes (`t2_webdav_pw_` / `t2_sync_v1_` vs `t2_dev_webdav_pw_` / `t2_dev_sync_v1_`), and window titles. |
| `lib/models/app_workspace.dart` | Defines immutable `AppWorkspace`, `WorkspaceSummary`, `WorkspaceErrorKind`, and `WorkspaceException` (with optional `cause`) for isolated workspace configurations, suggested `.tdf` filenames (`AppWorkspace.suggestFileName`), control/BiDi validation (`hasControlCharacters`), and workspace name/path uniqueness checks. |
| `lib/models/location_state.dart` | Defines immutable `GeocodingCandidate`, `LocationFix`, `LocationSource` (`gps`, `system`, `internet`), `LocationSourceType` (`gps`, `address`, `plusCode`), `LocationState`, and `LocationStatus` (`disabled`, `searching`, `found`, `unavailable`) with WGS-84 coordinate formatting, 100-meter Haversine displacement gating, and 5-minute resume refresh cooldown evaluation. |
| `lib/models/settings_codec.dart` | Defines immutable PersistedSettingsDocument, SettingsDecodeWarning, SettingsDecodeResult, SettingsRecoveryKind, SettingsRecoveryNotice, and stateless SettingsCodec encoding and resiliently decoding versioned UTF-8 settings.json documents with unknown-key preservation and strict secret exclusion. |
| `lib/models/storage_file_read_status.dart` | Defines immutable `StorageFileTarget`, `StorageFileReadState`, `StorageReadFailureScope`, `StorageFileReadStatus`, and `StorageFileReadReport` models classifying per-file local and remote `.tdf` readability outcomes. |
| `lib/models/task_board.dart` | Defines the immutable `TaskBoard` aggregate storing `Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, and `Completed` tier slices, sorted `TdfLocation` and `TdfLabel` items, `TdfQueueBlock`, and `TdfDeletedBlock`, and delegating evaluation and mutations to `TaskBoardEvaluator`, `TaskBoardQueueMutator`, and `TaskBoardMutator`. |
| `lib/models/task_board_evaluator.dart` | Stateless dynamic $O(N)$ 6-tier derivation engine (`TaskBoardEvaluator`, `NormalizedTierSlices`, `TaskBoardSlicesX`) implementing `spec/TDF_SPEC_0.8.0.md` Section 9 tier partitioning, configurable `due` lead-window promotion (`24` hours by default), WIP soft limits (`3` `Focus`, `5` `Ready`), `scoped` label queues, block-reason cleanup, 30-day UTC pruning, `subtasks auto-finish`, and label condition inheritance. |
| `lib/models/task_board_mutator.dart` | Stateless task, location, and label CRUD, history, and recurrence mutation subsystem (`TaskBoardMutator`, `TaskBoardMutationSlicesX`) implementing `spec/TDF_SPEC_0.8.0.md` Section 10 task addition, editing (`dueLocalInput`/`suspendedLocalInput` `TDF-CAL-001` resolution, `due.anchor` preservation, and `priority` `passive` deadline resets), `(Y_cur, M_cur)` Mode 2 recurrence (`TDF-CAL-003`), completion, restoration, deletion, subtask toggling, `history` journal mutations, location and label management, block cleanup, and monotonic `modifiedAt` stamping. |
| `lib/models/task_board_queue_mutator.dart` | Stateless queue-ordered scheduling and dependency re-arming subsystem (`TaskBoardQueueMutator`, `TaskBoardQueueSlicesX`) implementing `spec/TDF_SPEC_0.8.0.md` Sections 10.3 and 10.4 tier downgrading (`Focus -> Ready -> Planned -> Someday` with `passive` deadline demotion and `scoped` label boundary jumps), restoration (`due`/`dueAnchor`/`suspended` clearing), explicit `priority` scheduling, priority reordering, dependency cycle detection, and completion requirement capture. |
| `lib/models/task_board_reconciler.dart` | Stateless synchronization helper subsystem (`TaskBoardReconciler`) implementing `spec/TDF_SPEC_0.8.0.md` Sections 11–13 baseline payload lookup, monotonic revision selection, deterministic tie-breaking, pre-cascade `scoped` label reconstruction (`TDF-MERGE-006`), `history` set reconciliation, two-level occurrence merging with atomic `(due, anchor, passive, note)` coupling, deletion conflict and bound decision verification (`TDF-DEL-003`), symmetric generation refresh (`TDF-REC-001`), new-identity recovery rewriting (`TDF-REC-002`), and `queue` block reconciliation. |
| `lib/models/task_board_recovery.dart` | Stateless TDF-REC-002 ambiguous-entity recovery rewriting subsystem (`TaskBoardRecovery`, `InlineRecoveryRewrite`, `PreparedRecoveryBoard`) extracted from `TaskBoardSync`. |
| `lib/models/task_board_sync.dart` | Stateless three-way synchronization facade (`TaskBoardSync.merge`, `TaskBoardSync.resolveRecovery`, `TaskBoardSync.stampAndNormalize`) coordinating baseline-aware task, location, label, `queue`, and `deleted` block reconciliation and stage-fair `TdfCleanupMode` (`finalStage` vs. `deferred`) cleanup across in-memory, local file, and WebDAV `.tdf` revisions. |
| `lib/models/task_board_sync_scoping.dart` | Pure `Ref`-free candidate-origin scoping, bystander pre-cleanup restoration, baseline filtering, and generation-rebasing subsystem (`TaskBoardSyncScoping`) shared by three-way sync. |
| `lib/models/task_board_undo.dart` | Stateless single-task undo subsystem (`TaskBoardUndo`, `TaskUndoActionKind`, `TaskUndoEntry`, `TaskUndoOutcome`) capturing pre-mutation task (including `dueAnchor`), queue, and prerequisite dependency snapshots and reversing task completion, active downgrade, and deletion while preserving monotonic `completions`, `decisionRevision`, `deleted` `generation`, live `history` across completion and downgrade undos, and `label`/`location` hygiene. |
| `lib/models/task_item.dart` | Defines immutable `TaskItem`, `TaskOrigin`, `SubtaskItem`, `TaskHistoryEntry`, `RepeatUnit`, and `TaskRepeatRule` value classes with 10-character Base62 `<task-id>` identifiers, UTC `created` / `finished` / `modified` / `suspended` / `due` timestamps and notes, optional local `dueAnchor` (`TdfLocalDateTime`), `passive` `due` flag, `completions` counter, recurrence `leadDays`, labels, dependencies, links, `history`, and conditions. |
| `lib/models/task_tier.dart` | Defines the `TaskTier` enum for the 6 derived tiers (`1` `focus` through `6` `completed`), WIP soft limits, and the `QuickAddMode` (`normal`, `priority`, `someday`) task creation scheduling enum. |
| `lib/models/tdf_entity_merger.dart` | Stateless three-way entity and unit merge engine (`TdfEntityMerger`) reconciling `TaskItem`, `TdfLabel`, `TdfLocation`, group-wise conditions, subtasks, history, dependencies, and due schedules. |
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
| `lib/repositories/link_launcher_repository.dart` | Abstract `LinkLauncherRepository`, `PlatformLinkLauncherRepository`, `FakeLinkLauncherRepository`, and `LinkLaunchException` isolating native `de.akjir.tiertask/link_launcher` `MethodChannel` URI launching with launch-time security validation (`LinkLauncherRepository.isLaunchableUri`) blocking backslashes, control/BiDi characters, and unsafe local/network-share schemes while preserving custom app schemes. |
| `lib/repositories/local_file_operations.dart` | Stateless local file subsystem (`LocalFileOperations`) providing desktop-only non-recursive parent-directory `.tdf` watching (`watchTdfFile`, `isRelevantWatchEvent`, `matchesWatchedFileName`), bounded regular-file reads (async `RandomAccessFile` `>= 32 KiB`), OS-aware error mapping, POSIX FFI `0600` log writes, `.bak` / `.bak.001`+ rotation, and atomic cross-device move/rename/delete. |
| `lib/repositories/local_file_repository.dart` | Native `dart:io` `File` repository (`LocalFileRepository`, `LocalFileException`, `LocalFileLogSink`) resolving persistent Android `Context.filesDir` storage, reading (`readTdfWithDigest` with `Isolate.run` UTF-8/SHA-256 offloading `>= 32 KiB`), atomically writing under `HostFileLockManager`, desktop-only watching, moving, renaming, and deleting `.tdf` files, and implementing `AppLogSink` with 7-day / 5-file log pruning. |
| `lib/repositories/location_repository.dart` | Abstract `LocationRepository`, `PlatformLocationRepository`, and `FakeLocationRepository` isolating native `de.akjir.tiertask/location` `MethodChannel` queries and a pooled `HttpClient` with disposable `close()` for 100-meter Haversine displacement-gated HTTPS reverse geocoding, bounded Nominatim forward geocoding (`searchLocations`), and 30-minute cached HTTPS GeoIP desktop fallback. |
| `lib/repositories/posix_file_lock_bindings.dart` | Pure-Dart `dart:ffi` POSIX `flock`, `open`, `fsync`, `rename`, `chmod`, and `fchmod` syscall bindings (`PosixLockBindings`) for Linux and Android host locking. |
| `lib/repositories/settings_repository.dart` | Abstract `SettingsRepository`, `SecureSettingsRepository` (split host-local `settings.json` with `HostFileLockManager` locking, atomic writes, `.bak` rotation, quarantine, Android `Context.filesDir` resolution, atomic file-backed `sync_state_<workspaceId>.tts` baselines with gzip `Isolate.run` offloading `>= 32 KiB`, and `FlutterSecureStorage` exclusively for per-workspace WebDAV passwords), and `InMemorySettingsRepository`. |
| `lib/repositories/webdav_repository.dart` | Native pooled `dart:io` `HttpClient` WebDAV repository (`WebDavRepository`, `WebDavException`) with disposable `close()`, authenticated conditional `GET` (`fetchTdf` with `If-None-Match`, `If-Modified-Since`, `304 Not Modified`), conditional `PUT` (`saveTdf` with strong `ETag` `If-Match`, `If-None-Match: *`, `412` cache invalidation; `saveLog`), `DELETE` (`deleteLog`), and remote `wipeTdf` with `.bak` rotation. |
| `lib/repositories/win32_file_lock_bindings.dart` | Pure-Dart `dart:ffi` Win32 `CreateFileW`, `LockFileEx`, `FlushFileBuffers`, and `MoveFileExW` syscall bindings (`Win32LockBindings`, `Win32LockHandle`) for Windows host locking. |
| `lib/repositories/window_control_repository.dart` | Abstract `WindowControlRepository`, `PlatformWindowControlRepository`, and `FakeWindowControlRepository` isolating native `de.akjir.tiertask/window_controls` `MethodChannel` commands for closing, dragging, and maximizing frameless desktop windows on Linux and Windows. |

## State Providers

| File | Function |
| :--- | :--- |
| `lib/providers/board_actions_provider.dart` | Domain-typed task action coordinator (`BoardActionsNotifier`, `BoardActionsState`, `TaskDraftInput`, `boardActionsProvider`) owning Quick-Add, Task Draft creation, live task controls, single-section inline editors, offline dual-storage commit checks, single-commit subtask auto-finish and label creation, and non-jumping notices. |
| `lib/providers/board_providers.dart` | Exposes `.autoDispose` evaluated board projections (`evaluatedBoardProvider`), prerequisite candidates (`taskPrerequisiteCandidatesProvider`, `PrerequisiteCandidate`), canonical `.tdf` preview (`rawTdfPreviewProvider`, `RawTdfPreview`), split SemVer display (`appVersionDisplayProvider`, `AppVersionDisplay`), and lifecycle-aware wall-clock boundary scheduling (`BoardBoundaryTimer`, `BoardBoundaryTimerNotifier`, `boardBoundaryTimerProvider`). |
| `lib/providers/config_providers.dart` | Defines storage-scoped `localFileRepositoryProvider` and `webDavRepositoryProvider`, FIFO optimistic `webDavConfigProvider` (`WebDavConfigNotifier`), `boundaryTickProvider`, `appLocaleProvider`, `appThemeModeProvider`, `appThemePaletteProvider`, `diagnosticsEnabledProvider`, `appVersionProvider`, `openExternalLinkProvider`, `desktopWindowActionsProvider` (`DesktopWindowActions`), `supportsDirectoryPickerProvider`, `supportsLocalFileWatchProvider`, `tdfServiceProvider`, `clockProvider`, and native picker/repository providers. |
| `lib/providers/entity_actions_provider.dart` | Domain-typed coordinators for Label and Location CRUD and geocoding (`EntityActionsNotifier`, `LabelDraftInput`, `LocationDraftInput`, `entityActionsProvider`), manual sync, location refresh, and conflict/recovery resolution (`SyncActionsNotifier`, `syncActionsProvider`), and workspace lifecycle operations (`WorkspaceActionsNotifier`, `workspaceActionsProvider`). |
| `lib/providers/floating_notice_providers.dart` | Manages floating bottom toasts, LIFO Undo recovery notifications (`8000ms`), standard auto-hide notices (`5000ms`), and persistent startup settings recovery alerts (`FloatingNotice`, `FloatingNoticeTone`, `FloatingNoticeNotifier`, `floatingNoticeProvider`). |
| `lib/providers/local_file_watch_providers.dart` | Defines `LocalFileWatchTarget`, `LocalFileWatcherNotifier`, `localFileWatchDebounceProvider`, `localFileWatchTargetProvider`, and `localFileWatcherProvider` for desktop-only (`supportsLocalFileWatchProvider`) parent-directory `.tdf` watching, `350 ms` trailing-edge debouncing, missing-directory rebinding, and `AppLifecycleState.resumed` catch-up reconciliation. |
| `lib/providers/location_providers.dart` | Defines `.select`-scoped `locationEnabledProvider`, `locationRepositoryProvider`, `locationStateProvider`, and `LocationNotifier` managing foreground-only location determination with startup/enable triggers, 5-minute app-resume cooldown, 15-minute passive foreground refresh, and manual refresh (`refreshLocation`). |
| `lib/providers/location_source_resolver.dart` | Domain-typed location source resolver (`LocationSourceResolver`, `LocationSourceResolutionResult`, `locationSourceResolverProvider`) coordinating live foreground GPS coordinates, bounded forward-geocoding `GeocodingCandidate` disambiguation, and offline Plus Code decoding and recovery. |
| `lib/providers/log_viewer_providers.dart` | Exposes `.autoDispose` diagnostic log viewer state and actions (`LogViewerNotifier`, `DiagnosticLogSnapshot`, `DiagnosticLogLine`, `DiagnosticLogSeverity`, `LogSyncResult`, `logViewerProvider`) plus live log filename tracking (`ActiveLogFileNameNotifier`, `activeLogFileNameProvider`) using real `LogLevel` and `LogTag` enums. |
| `lib/providers/settings_draft_providers.dart` | Exposes `.autoDispose` transient WebDAV draft state (`SettingsDraftNotifier`, `SettingsDraftState`, `SettingsStatusBanner`, `SettingsBusyOperation`, `settingsDraftProvider`) handling WebDAV dirty tracking, explicit validation, Save and Test+Sync flows, and capability-gated local file and `.tdf` wipe actions without shadowing persisted preferences. |
| `lib/providers/shell_providers.dart` | Coordinates adaptive shell routes, `ReturnContext`, single-expand cards, inline editing, drafts, and `Escape`/`PopScope` unwinding (`ShellState`, `ShellNotifier`, `shellProvider`, `ActionResult`) alongside decoupled high-frequency query providers (`searchQueryProvider`, `labelPickerQueryProvider`, `sidebarLabelsFilterQueryProvider`, `sidebarLocationsFilterQueryProvider`). |
| `lib/providers/sync_error_formatter.dart` | Unified localized sync, storage, settings, and TDF domain error and outcome formatter (`SyncErrorFormatter`, `StorageFileReadError`). |
| `lib/providers/sync_providers.dart` | Defines `SyncState`, `syncStateProvider`, `.autoDispose` `conflictDecisionsProvider` and `recoveryDecisionsProvider` (`ConflictDecisionsNotifier`, `RecoveryDecisionsNotifier`), `StorageFileReadException`, `UnsupportedTdfVersionException`, and stateless `TaskSyncPipeline` coordinating stage-fair merges, local/WebDAV CAS retries, 30-day pruning, readability diagnostics, and conflict/recovery resolution. |
| `lib/providers/task_condition_draft_helper.dart` | Stateless activation-condition draft extraction, compilation, and summary-chip formatting subsystem (`TaskConditionDraftHelper`). |
| `lib/providers/task_providers.dart` | Defines `taskNotifierProvider`, `taskUndoStateProvider`, `localFileWatchReadRetryDelayProvider`, `TaskUndoState`, and `TaskNotifier` orchestrating domain mutations, single-commit atomic `updateTaskAndComplete` and `createLabelAndAssignToTask`, in-memory `DueLeadWindow` re-evaluation, 10-entry LIFO undo, conflict/recovery resolution, external local reconciliation, workspace unload flushing, file actions, and sync. |
| `lib/providers/task_schedule_helper.dart` | Stateless scheduling, recurrence, condition, geofence radius, history validation, and remaining-duration formatting helpers (`TaskScheduleHelper`, `ResolvedDueDraft`, `ResolvedSuspendedDraft`, `ConditionDraft`, `TimeWindowDraft`, `ConditionDimensionMode`, `FileReadDiagnosticLine`) supporting local wall-clock drafts, `due.anchor` preservation, and `canonicalLabelPresetHexColors`. |
| `lib/providers/ui_telemetry.dart` | Stateless UI telemetry facade (`UiTelemetry`) emitting redacted structured `LogTag.ui` diagnostic events to `AppLogger` gated by `AppLogger.shouldLog`. |
| `lib/providers/workspace_providers.dart` | Defines `activeWorkspaceProvider`, `appBuildProfileProvider`, `settingsDirectoryPathProvider`, `settingsRepositoryProvider`, `workspaceSummariesProvider`, `workspaceUnloadCoordinatorProvider`, and `ActiveWorkspaceNotifier` orchestrating single-active-workspace switching (`switchWorkspace`), creation, renaming, deletion, and summary-gated list revision updates. |

## Design System

| File | Function |
| :--- | :--- |
| `lib/ui/components/ui_color_wheel.dart` | Renders inline swatch, `#RRGGBB` input, 8 canonical preset chips, and a `ValueNotifier`-driven circular HSV wheel modal (`UiColorWheel`). |
| `lib/ui/components/ui_dialog_frame.dart` | Renders three-part modal dialog frames (`UiDialogFrame`, `UiDialogSize`) and focus-trapped modal/compact bottom-sheet presenters (`showModal`, `showBottomSheet`) with `Tab` trapping, `Escape` dismissal, and focus restoration. |
| `lib/ui/components/ui_ordered_item_list.dart` | Renders repeatable ordered lists (`UiOrderedItemList`) with deterministic keys, optional progress track, inline editing highlight, boundary-disabled reorder controls, edit/delete actions, and add/footer slots. |
| `lib/ui/components/ui_quick_composer.dart` | Renders docked Task Quick-Add (with compact `+ New task` collapse and upward non-swallowing `TapRegion` desktop popover) and inline entity Quick-Create bars (`UiQuickComposer`). |
| `lib/ui/components/ui_searchable_picker.dart` | Renders searchable multi-select and single-select pickers (`UiSearchablePicker`, `UiPickerSelectionMode`, `UiPickerOption`, `UiPickerScopeFilter`) with conditional scope pills, inline creation, cycle-disabled rows, keyboard navigation, and non-autofocus compact sheets. |
| `lib/ui/layout/ui_adaptive_app_shell.dart` | Coordinates the `62px` top chrome bar, persistent `244px` sidebar vs below-chrome compact slide-over drawer, lazy-list viewport stack with floating notices, and decoupled pinned bottom dock (`UiAdaptiveAppShell`). |
| `lib/ui/layout/ui_page_header.dart` | Renders view headers (`UiPageHeader`) with optional back button, `28px` title, clickable inline active-label filter, tabular count capsule, trailing action cluster, and `58ch` subtitle. |
| `lib/ui/layout/ui_responsive_grid.dart` | Renders equal-width top-aligned adaptive grids (`UiResponsiveGrid`, `UiGridPreset`) collapsing cleanly at `820px` and `720px` with zero horizontal overflow. |
| `lib/ui/layout/ui_sidebar_section.dart` | Renders static and collapsible/filterable sidebar navigation groups (`UiSidebarSection`, `UiSidebarNavItem`) with collapsed summaries, 3 header icon actions, inline filtering, and split or single-button rows. |
| `lib/ui/primitives/ui_app_logo.dart` | Renders the minimal three-bar stepped TierTask accent brand mark (`UiAppLogo`, `UiLogoBarSpec`) via `CustomPaint` wrapped in `ExcludeSemantics`. |
| `lib/ui/primitives/ui_banner.dart` | Renders unified feedback surfaces (`UiBanner`, `UiBannerVariant`, `UiBannerTone`) for status banners, `620px` floating toasts, inline warnings, inline delete confirmations, plain-text empty states, loading spinners, and full-screen errors. |
| `lib/ui/primitives/ui_button.dart` | Renders flat interactive buttons (`UiButton`, `UiButtonVariant`, `UiButtonDensity`, `UiButtonTone`) with `1px` keyboard focus rings, active/loading states, danger hover, and `0.48` disabled opacity. |
| `lib/ui/primitives/ui_card.dart` | Renders flat bordered cards (`UiCard`, `UiCardVariant`: `standard`, `inset` with unconditional `UiSurfaceScope.insetWell`, `draft`, and unified single-expand `expandable` entity accordions). |
| `lib/ui/primitives/ui_field.dart` | Renders surface-aware flat `1px` inputs (`UiField`, `UiFieldKind`, `UiSelectOption`) for text, multiline, password reveal, unified custom flat dropdown popups (`select` via `UiSegmentedControl`), date/time display, focus-within search, and monospace read-only wells. |
| `lib/ui/primitives/ui_pill.dart` | Renders surface-aware pills (`UiPill`, `UiPillVariant`, `UiPillTone`) covering badges, tabular count capsules, color-dotted tags, split navigable/removable chips, dashed/direct add chips, and selectable toggles. |
| `lib/ui/primitives/ui_segmented_control.dart` | Renders horizontal equal-width segmented controls and unified custom flat vertical dropdown popups (`UiSegmentedControl`, `UiSegmentedControlMode`, `UiSegment`) with animated direction-aware positioning, keyboard navigation, and `TapRegion` dismissal. |
| `lib/ui/primitives/ui_toggle_row.dart` | Renders full-row checkbox controls (`UiToggleRow`) with optional muted descriptions and standard/dense target heights. |
| `lib/ui/tokens/ui_breakpoints.dart` | Defines `UiViewportClass` (`compact`, `medium`, `expanded`) and stateless `UiBreakpoints` width classification helpers (`<= 720`, `721..820`, `> 820`). |
| `lib/ui/tokens/ui_color_tokens.dart` | Defines immutable 19-role `UiColorTokens`, `UiContrastPair`, `UiContrastFailure`, and stateless `UiContrastChecker` validating WCAG 2.1 AA (`>= 4.5:1`) contrast across all 17 normative pairs. |
| `lib/ui/tokens/ui_focus_tokens.dart` | Defines immutable `UiFocusTokens` holding `1px` focus-ring geometry, transition durations, dimmed opacities, and the 5 allowlisted overlay shadows. |
| `lib/ui/tokens/ui_radius_tokens.dart` | Defines immutable `UiRadiusTokens` holding corner radii (`2px` to `999px`) and canonical stroke widths (`1.0`, `1.7`, `2.5`). |
| `lib/ui/tokens/ui_spacing_tokens.dart` | Defines immutable `UiSpacingTokens` holding the spacing ladder, touch-target densities (`26px` to `44px`), shell dimensions, canonical `EdgeInsets`, and icon sizes (`13/15/18/34px`). |
| `lib/ui/tokens/ui_theme_tokens.dart` | Defines `UiSurfaceLevel`, `UiSurfaceScope` for automatic `bg`/`panel` alternation, `UiThemeTokens` (`ThemeExtension` + flat Material 3 `toThemeData`), `UiThemePreset`, and `UiThemePresets` (`Calm` and `Plum Umber`, Light and Dark). |
| `lib/ui/tokens/ui_typography_tokens.dart` | Defines immutable `UiTypographyTokens` covering all 14 scale roles plus `mono` and `tabular` (`FontFeature.tabularFigures`) helpers. |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/main.dart` | Application entry point registering global crash hooks (`FlutterError.onError`, `PlatformDispatcher.instance.onError`) and `AppLifecycleListener`, caching `UiThemePresets` themes per palette and brightness, isolating background diagnostics and local file-watch listeners outside `MaterialApp` rebuilds, and mounting `TierTaskApp` with `AppLocalizations` and `TierTaskShellScreen`. |
| `lib/ui/dialogs/compact_label_picker_sheet.dart` | Live Riverpod-backed compact mobile label picker bottom sheet (`CompactLabelPickerSheet`, `showCompactLabelPickerSheet`) with scope filtering, multi-selection, and reactive inline label creation. |
| `lib/ui/dialogs/geocoding_candidates_modal.dart` | Forward-geocoding candidate disambiguation modal (`showGeocodingCandidatesModal`) allowing users to select from bounded address search matches. |
| `lib/ui/dialogs/local_file_modals.dart` | Local `.tdf` file selection and rename modals (`showSelectLocalFileModal`, `showRenameLocalFileModal`) with single-segment filename validation and capability-gated native pickers. |
| `lib/ui/dialogs/location_status_modal.dart` | Foreground location status modal (`showLocationStatusModal`) displaying fix status, resolved place name, WGS-84 coordinates, source, and manual refresh trigger. |
| `lib/ui/dialogs/wipe_tdf_modal.dart` | Typed-filename destructive Local and Remote `.tdf` wipe confirmation modal (`showWipeTdfModal`) with optional `.bak` backup toggle. |
| `lib/ui/dialogs/workspaces_modal.dart` | Workspace management modal (`showWorkspacesModal`) coordinating workspace switching, creation, inline renaming, and inline delete confirmation. |
| `lib/ui/tier_task_shell_screen.dart` | Adaptive root shell (`TierTaskShellScreen`) integrating `UiAdaptiveAppShell`, granular `.select(...)` top chrome, sidebar/drawer, view router, floating notice host, desktop keyboard shortcuts, and `PopScope` unwinding. |
| `lib/ui/ui_domain_mappers.dart` | Stateless domain-to-UI visual mapper (`UiDomainMappers`, `TaskCardBadge`) translating domain models and enums directly into `UiThemePreset`, `ThemeMode`, semantic tones, outline icons, localized chrome labels, and ordered collapsed task badges. |
| `lib/ui/views/label_card.dart` | Unified expandable label card and uncommitted draft card (`LabelCard`, `LabelDraftCard`) supporting inline name, HSV color wheel, board scope, note, links, and inherited conditions. |
| `lib/ui/views/labels_view.dart` | Labels manager view (`LabelsView`) combining header, inline quick-create bar, draft card slot, and virtualized label list. |
| `lib/ui/views/location_card.dart` | Unified expandable geofence card and uncommitted draft card (`LocationCard`, `LocationDraftCard`) supporting inline name, GPS/address/Plus Code resolution, radius, and notes. |
| `lib/ui/views/locations_view.dart` | Locations manager view (`LocationsView`) combining header, inline quick-create bar, draft card slot, and virtualized location list. |
| `lib/ui/views/log_viewer_view.dart` | Diagnostic log viewer view (`LogViewerView`) backed by `.autoDispose` `logViewerProvider`, rendering session metadata, level and tag filters, severity-highlighted monospace lines, and copy, upload, scroll, and clear actions. |
| `lib/ui/views/raw_tdf_view.dart` | Raw `tdf 0.8.0` preview view (`RawTdfView`) backed by `.autoDispose` `rawTdfPreviewProvider`, displaying canonical `LF` output, byte/line stats, copy action, and `1 MiB` limit-exceeded state. |
| `lib/ui/views/resolution_views.dart` | Domain-direct `TDF-DEL-003` deletion conflict and `TDF-REC-002` generation recovery views (`DeletionConflictView`, `GenerationRecoveryView`, `ResolutionActionDock`) backed by `.autoDispose` `conflictDecisionsProvider` and `recoveryDecisionsProvider` in `sync_providers.dart`. |
| `lib/ui/views/settings_view.dart` | Settings view (`SettingsView`, `SettingsActionDock`) separating `webDavConfigProvider.select` auto-saved preferences from `.autoDispose` `settingsDraftProvider` WebDAV credentials, local storage actions, Danger Zone, and docked footer controls. |
| `lib/ui/views/task_card.dart` | Unified single-expand task card (`TaskCard`) supporting collapsed badge overflow (`3` + `+N more`), live completion/downgrade/placement controls, inline section editors, and read-only completed mode. |
| `lib/ui/views/task_detail_editors.dart` | Inline task detail section editors (`TaskSubtasksSection`, `TaskHistorySection`, `TaskPrerequisitesSection`) and shared checklist widgets (`TaskSubtaskCheckBoxButton`, `EditableSubtaskRow`). |
| `lib/ui/views/task_draft_card.dart` | Uncommitted inline task creation draft card (`TaskDraftCard`) configuring details, scheduling, recurrence, labels, subtasks, prerequisites, links, and conditions before saving. |
| `lib/ui/views/task_schedule_editors.dart` | Inline task title and scheduling editors (`TaskInlineTitleEditor`, `TaskDueSection`, `TaskRepeatSection`, `TaskSuspendedSection`) with local wall-clock pickers, `due.anchor` details, and notes. |
| `lib/ui/views/tasks_view.dart` | Primary six-tier Tasks and Global Search view (`TasksView`, `TasksQuickAddDock`) rendering banners, full-screen errors, draft card, virtualized task cards, and pinned Quick-Add dock. |
| `lib/ui/widgets/entity_card_chrome.dart` | Shared expanded entity meta bar, danger header delete button, inline delete confirmation, error text, and editor/modal action footers (`EntityCardMetaBar`, `EntityHeaderDeleteButton`, `EntityInlineEditorFooter`, `EntityInlineErrorText`, `EntityModalActionFooter`). |
| `lib/ui/widgets/entity_conditions_section.dart` | Shared activation conditions section (`EntityConditionsSection`) managing weekday (`day`), time-window (`time`), geofence (`location`), and reset (`any`) rules. |
| `lib/ui/widgets/entity_date_time_fields.dart` | Shared hybrid typed and picker local date/time input widgets (`EntityHybridDateTimeField`, `EntityHybridTimeField`) and time-minute parsing helper (`parseEntityTimeMinutes`). |
| `lib/ui/widgets/entity_inline_name_editor.dart` | Shared adaptive inline title and name editor (`EntityInlineNameEditor`) used across task, label, and location cards with `Enter`/`Escape` shortcuts and deferred disposal. |
| `lib/ui/widgets/entity_label_picker.dart` | Shared searchable multi-select label picker (`EntitySearchableLabelPicker`) with board-scope filter tabs and inline label creation. |
| `lib/ui/widgets/entity_links_section.dart` | Shared ordered reference links section (`EntityLinksSection`) supporting URI launching, inline editing, reordering, and deletion within the `N / 20` cap. |
| `lib/ui/widgets/entity_note_section.dart` | Shared entity note viewer and inline multiline editor (`EntityNoteSection`) with clipboard copy and explicit save/cancel controls. |
| `lib/ui/widgets/entity_reveal_scroll_controller.dart` | Shared entity card key management, deferred fallback `ScrollController` ownership, and bounded offscreen pre-scroll reveal mixin (`EntityRevealScrollMixin`) across manager views. |

## Execution & Synchronization Flow

1. **Startup, Workspace Loading, Theme Caching & Reactive Shell:** `main.dart` registers global error handlers (`FlutterError.onError`, `PlatformDispatcher.instance.onError`) and `AppLifecycleListener`, initializes `ProviderScope`, caches `UiThemePresets` `ThemeData` per `(AppThemePalette, Brightness)`, and hosts `diagnosticsEnabledProvider` alongside desktop-only `localFileWatcherProvider` (gated by `supportsLocalFileWatchProvider`, disabled on Android) inside `_BackgroundServicesHost` so background services stay active without rebuilding `MaterialApp`. `ActiveWorkspaceNotifier` (`lib/providers/workspace_providers.dart`) loads only the single active `AppWorkspace` (`Tasks` / `tasks.tdf` by default) from `SettingsRepository`, `WebDavConfigNotifier` (`lib/providers/config_providers.dart`) exposes persisted `WebDavConfig` with immediate optimistic updates serialized in FIFO write order and rollback on `WorkspaceException`, and `TierTaskShellScreen` (`lib/ui/tier_task_shell_screen.dart`) plus feature views consume domain models directly via granular `.select(...)` subscriptions and `.autoDispose` view projections (`evaluatedBoardProvider`, `taskPrerequisiteCandidatesProvider`, `rawTdfPreviewProvider`, `settingsDraftProvider`, `logViewerProvider`, `conflictDecisionsProvider`, `recoveryDecisionsProvider`). Switching workspaces at runtime via `ActiveWorkspaceNotifier.switchWorkspace` flushes and unloads the current `TaskBoard` and `SyncState` from memory before loading the selected `AppWorkspace` and its `.tdf` file without restarting the application.
2. **Multi-Stage TDF Fetch, External Directory Watching & Three-Way Merge (`In-Memory <-> Local File <-> WebDAV`):** `localFileRepositoryProvider` and `webDavRepositoryProvider` scope subscriptions strictly to storage-relevant `WebDavConfig` fields so UI preference changes preserve the `WebDavRepository` pooled `HttpClient`, ETag, and existence cache (closing pooled clients on disposal). On startup, on every manual sync (`syncFromRemote`, `testConnectionAndSync`), on desktop external local `.tdf` edits detected via `LocalFileWatcherNotifier` (`350 ms` trailing-edge debounced `Directory.watch` events and `AppLifecycleState.resumed` catch-up checks gated by `supportsLocalFileWatchProvider`, `WebDavConfig.localWatchEnabled`, and `WorkspaceSyncState.localSourceDigest` inside `TaskNotifier.reconcileExternalLocalChanges`; disabled on Android), and on every saved mutation or conflict/recovery resolution (`resolveDeletionConflicts`, `resolveRecovery`), `TaskNotifier` (`lib/providers/task_providers.dart`) delegates to `TaskSyncPipeline` (`lib/providers/sync_providers.dart`): Stage 1 acquires the non-blocking host-local cooperative lock (`HostFileLockManager` via `LocalFileRepository.withExclusiveTargetLock`), reads the local `.tdf` file (`LocalFileRepository.readTdfWithDigest`, switching to async `RandomAccessFile` and `Isolate.run` UTF-8/SHA-256 offloading at `>= 32 KiB`), merges external local `tdf 0.8.0` changes with the in-memory `TaskBoard` across `task`, `location`, `label`, `queue`, and `deleted` (`generation`) via `TaskBoardSync.merge` using `TdfCleanupMode.deferred` when WebDAV Stage 2 follows (`TdfCleanupMode.finalStage` in `StorageMode.local`), and atomically replaces the local file via guarded CAS publication (`_publishLocalWithCasLoop`); Stage 2 seeds `WebDavRepository` with the persisted `remoteEtag`, `remoteLastModified`, and canonical `lastSyncedRemoteTdf` baseline, fetches the remote `.tdf` file (`WebDavRepository.fetchTdf` over its pooled `HttpClient` using `If-None-Match` and `If-Modified-Since` to short-circuit unchanged remote files on `HTTP 304 Not Modified`), merges concurrent remote changes in `TdfCleanupMode.finalStage` with authoritative 30-day retention pruning (`TDF-PUB-004`), writes changed `tdf 0.8.0` documents to WebDAV with `If-Match` / `If-None-Match: *` CAS retry (`_publishRemoteWithCasLoop` on `HTTP 412 Precondition Failed`), and in Stage 3 converges the local `.tdf` file (`TdfCleanupMode.finalStage` with symmetric generation refresh) and persists `WorkspaceSyncState` (`TTS\x04`, gzip-compressed with `Isolate.run` offloading at `>= 32 KiB`: canonical `lastSyncedLocalTdf` and `lastSyncedRemoteTdf`, `acknowledgedLocalGeneration`, `acknowledgedRemoteGeneration`, `localSourceDigest`, `remoteSourceDigest`, `remoteEtag`, `remoteLastModified`) atomically into host-local `sync_state_<workspaceId>.tts` files (keeping `FlutterSecureStorage` exclusively for WebDAV passwords) so both storage backends converge to byte-identical `tdf 0.8.0` documents.
3. **Single-Pass Parse & Dynamic 6-Tier Derivation:** `TdfService.parse` (`TdfScanner`, `TdfParser`, `TdfDirectiveParser`) validates the strict single-version `tdf 0.8.0` header (`TDF-COMPAT-001`), scans and validates `queue`, `deleted`, `location`, `label`, and `task` blocks in a single $O(N)$ pass (interpreting `created`, `finished`, `modified`, `due`, `history`, and timed `suspended` in UTC alongside optional local `due.anchor` calendar tuples while evaluating `condition day`, `condition time`, and `repeat` calendar progression in the workspace's `TDF-CTX-001` local time zone), and invokes `TaskBoard.evaluate` (`TaskBoardEvaluator`) through `.autoDispose` `evaluatedBoardProvider` (with `BoardBoundaryTimer` advancing `boundaryTickProvider` at exact wall-clock transitions) to derive `Completed`, `Someday` (open tasks omitted from `queue` without an active `suspended` lock), `Blocked`, and the `queue`-ordered active tiers (`Focus`, `Ready`, `Planned`, with configurable per-workspace non-`passive` `due` lead-window auto-promotion defaulting to `24` hours, and `scoped` label queue partitioning) per `spec/TDF_SPEC_0.8.0.md` Section 9.
4. **Mutation, Single-Commit Atomic Operations, Undo & Persistence:** Every user action advances the mutated entity's (and `queue` block's when reordered) UTC `modified` timestamp monotonically (`TaskItem.nextModifiedTimestamp`), cleans expired finite `suspended` locks and resolved one-shot `blocked` prerequisites on open tasks, records explicit task, location, and label deletions in `deleted` (`TdfDeletedBlock`) via `TaskBoardMutator` and `TaskBoardQueueMutator`, executes compound operations (`TaskNotifier.updateTaskAndComplete` for subtask auto-finish and `TaskNotifier.createLabelAndAssignToTask` for inline label creation and assignment) as single-commit atomic board mutations, captures bounded 10-entry in-memory LIFO undo snapshots (`TaskBoardUndo`) for task completion, downgrade, and deletion (clearing the undo stack immediately upon conflict or recovery resolution), triggers `TaskSyncPipeline`, serializes byte-exact canonical `LF`-terminated `tdf 0.8.0` output via `TdfService.serialize` (`TdfSerializer`), and persists the converged `.tdf` document across configured local/WebDAV targets alongside atomic host-local `sync_state_<workspaceId>.tts` baselines.
5. **Opt-In Diagnostic Logging & Local/WebDAV Persistence (`AppLogger`):** All layers (`LIFECYCLE`, `TDF`, `DOMAIN`, `SYNC`, `STORAGE`, `UI` via `UiTelemetry`) report structured `<UTC-ISO> [<LEVEL>] [<TAG>] <event> | <key=value ...>` events to `AppLogger` (at DAG rank `0`, decoupled from `dart:io` via `AppLogSink` and `LocalFileLogSink`). `diagnosticsEnabledProvider` scopes subscriptions to logger-affecting config fields so unrelated preference changes never rewrite log files. When `diagnosticsEnabled` is `false` or an entry is below `minimumLevel`, logging calls are zero-allocation no-ops. When enabled, `AppLogger` writes a 5-line `@meta` header block to `tiertask_<YYYY-MM-DD>_<platform>_<workspaceId>.log`, prunes expired local logs (`7` days / `5` files per workspace), preserves logs across clean `detached` exits (`session.exit | state=detached crashed=false`), appends a recovery banner on startup after an unclean exit, flushes `[CRASH]` stack traces via `FlutterError.onError` and `PlatformDispatcher.instance.onError`, and uploads log snapshots to WebDAV (`WebDavRepository.saveLog`) via a 5-second debounce and `inactive`/`paused` lifecycle hooks when `logStorageMode` includes WebDAV.
