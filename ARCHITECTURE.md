# TierTask Architecture and File Structure

> [!IMPORTANT]
> Update this file, [`AGENTS.md`](AGENTS.md), and [`spec/TDF_SPEC_0.6.0.md`](spec/TDF_SPEC_0.6.0.md) whenever the architecture, supported target platforms, directory layout, file responsibilities, localization files, or TDF synchronization flow change.

## Architectural Layers

| Layer | Path | Responsibility |
| :--- | :--- | :--- |
| Localization | `lib/l10n/` | External English (`app_en.arb`) and German (`app_de.arb`) resource bundles, generated `AppLocalizations` classes, and `TaskTier` localization mappings. |
| Models | `lib/models/` | Immutable domain data structures (`AppWorkspace`, `WorkspaceSummary`, `WorkspaceException`, `WorkspaceErrorKind`, `GeocodingCandidate`, `LocationFix`, `LocationSource`, `LocationSourceType`, `LocationState`, `LocationStatus`, `TaskTier`, `QuickAddMode`, `TaskItem`, `TaskOrigin`, `SubtaskItem`, `RepeatUnit`, `TaskRepeatRule`, `ConditionGroup`, `TaskCondition`, `TdfLocation`, `TdfLabel`, `TdfColor`, `TdfQueueBlock`, `TdfDeletionRecord`, `TdfDeletedBlock`, `TaskDependency`, `TdfErrorKind`, `TdfException`, `TdfRepeatClock`, `TdfTimeZoneContext`, `TdfCalendar`, `TdfPayloadComparison`, `TaskBoard`, `TaskBoardEvaluator`, `TaskBoardMutator`, `TaskBoardQueueMutator`, `TaskBoardSync`, `TaskBoardReconciler`, `TaskBoardUndo`, `WorkspaceSyncState`, `AppLanguage`, `AppThemeMode`, `AppThemePalette`, `AppTimeZoneMode`, `StorageMode`, `WebDavConfig`) and the dynamic $O(N)$ 6-tier derivation, mutation, undo, and three-way synchronization pipeline. |
| Services | `lib/services/` | Opt-in diagnostic logging service (`AppLogger`, `AppLogSink`, `LogLevel`, `LogTag`) at DAG rank `0`, stateless single-pass $O(N)$ RFC 4648 Base64 codec (`Base64Service`, `Base64Exception`, `Base64ErrorKind`), Open Location Code parser and decoder (`PlusCodeService`, `PlusCodeArea`, `PlusCodeInput`), deterministic SHA-256 Base62 legacy ID migration (`TdfIdMigration`), TDF `0.6.0` lexical scanner (`TdfScanner`), structural parser (`TdfParser`, `TdfDirectiveParser`), and canonical `LF` serializer (`TdfSerializer`, `TdfService`), and explicit `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1 -> 0.6.0` version import and adjacent migration pipeline (`TdfImporter`, `TdfHistoricalParser`, `TdfHistoricalSerializer`, `TdfImportResult`). |
| Repositories | `lib/repositories/` | All external I/O: WebDAV HTTP `GET`/`PUT` (`dart:io` `HttpClient`), local `.tdf` file and `tiertask.log` reads/writes (`LocalFileRepository`, `LocalFileOperations`, `LocalFileLogSink`), foreground location channel and bounded reverse/forward geocoding and GeoIP lookup (`MethodChannel` and `HttpClient`), and encrypted workspace and settings persistence (`flutter_secure_storage`). |
| Providers | `lib/providers/` | Riverpod state management (`Provider`, `Notifier`, `AsyncNotifier`) across `workspace_providers.dart`, `config_providers.dart`, `local_file_watch_providers.dart`, `location_providers.dart`, `sync_providers.dart`, and `task_providers.dart` coordinating single-active-workspace unload/load transitions, parent-directory `.tdf` file watching, foreground lifecycle-aware location determination, locale and theme resolution, domain mutations, and two-stage repository synchronization (`TaskSyncPipeline`). |
| UI | `lib/ui/` | Localized Material 3 screens (`lib/ui/`) and modular leaf widgets (`lib/ui/widgets/`) for Linux, Android, and Windows. |

> [!NOTE]
> Per Google's Flutter App Architecture guidelines (`P-UDF-ARCHITECTURE`, `P-IO-ISOLATION`, `P-WEBDAV-API`, `P-GLOBAL-ERROR-BOUNDARY`, `P-ATOMIC-STATE`, `P-SECRET-HYGIENE`, `P-TRANSPORT-SECURITY`), data flows unidirectionally from single-source-of-truth repositories (`lib/repositories/`) through state notifiers (`lib/providers/`) to stateless views (`lib/ui/`). All network (`HttpClient`), local filesystem (`File`), and secure storage (`FlutterSecureStorage`) operations are strictly isolated in `lib/repositories/`, global synchronous and asynchronous error boundaries (`FlutterError.onError` and `PlatformDispatcher.instance.onError`) guard runtime stability, and credentials are redacted from logs and error messages.

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
│   ├── TDF_SPEC_0.6.0.md
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
│   │   └── tier_localization_extension.dart
│   ├── models/
│   │   ├── app_workspace.dart
│   │   ├── location_state.dart
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
│   │   ├── tdf_location.dart
│   │   ├── tdf_metadata.dart
│   │   ├── tdf_payload_comparison.dart
│   │   ├── tdf_sync_metadata.dart
│   │   ├── tdf_timezone.dart
│   │   ├── webdav_config.dart
│   │   └── workspace_sync_state.dart
│   ├── providers/
│   │   ├── config_providers.dart
│   │   ├── local_file_watch_providers.dart
│   │   ├── location_providers.dart
│   │   ├── sync_providers.dart
│   │   ├── task_providers.dart
│   │   └── workspace_providers.dart
│   ├── repositories/
│   │   ├── app_version_repository.dart
│   │   ├── link_launcher_repository.dart
│   │   ├── local_file_operations.dart
│   │   ├── local_file_repository.dart
│   │   ├── location_repository.dart
│   │   ├── settings_repository.dart
│   │   └── webdav_repository.dart
│   ├── services/
│   │   ├── app_logger.dart
│   │   ├── base64_service.dart
│   │   ├── plus_code_service.dart
│   │   ├── tdf_directive_parser.dart
│   │   ├── tdf_historical_parser.dart
│   │   ├── tdf_historical_serializer.dart
│   │   ├── tdf_id_migration.dart
│   │   ├── tdf_importer.dart
│   │   ├── tdf_parser.dart
│   │   ├── tdf_scanner.dart
│   │   ├── tdf_serializer.dart
│   │   └── tdf_service.dart
│   └── ui/
│       ├── app_theme.dart
│       ├── edit_labels_screen.dart
│       ├── edit_locations_screen.dart
│       ├── edit_task_screen.dart
│       ├── home_screen.dart
│       ├── settings_screen.dart
│       └── widgets/
│           ├── app_logo.dart
│           ├── clearable_text_field.dart
│           ├── condition_editor_controller.dart
│           ├── home_drawer.dart
│           ├── home_tier_pane.dart
│           ├── home_top_bar.dart
│           ├── label_color_picker_dialog.dart
│           ├── local_tdf_file_dialogs.dart
│           ├── location_status_dialog.dart
│           ├── log_viewer_dialog.dart
│           ├── quick_add_bar.dart
│           ├── settings_local_storage_section.dart
│           ├── settings_preference_cards.dart
│           ├── settings_webdav_storage_section.dart
│           ├── task_editor_conditions_section.dart
│           ├── task_editor_links_section.dart
│           ├── task_editor_scheduling_card.dart
│           ├── task_editor_sections.dart
│           ├── task_editor_subtasks_and_blockers.dart
│           ├── task_info_dialog.dart
│           ├── tier_page_indicator.dart
│           ├── tier_task_pill.dart
│           ├── tier_task_subtasks_section.dart
│           ├── wipe_tdf_dialog.dart
│           ├── workspace_dialog.dart
│           └── workspace_row_card.dart
└── test/
    ├── models/
    │   ├── app_workspace_test.dart
    │   ├── location_state_test.dart
    │   ├── task_board_downgrade_test.dart
    │   ├── task_board_evaluation_test.dart
    │   ├── task_board_lifecycle_test.dart
    │   ├── task_board_mutation_test.dart
    │   ├── task_board_sync_test.dart
    │   ├── task_board_undo_test.dart
    │   ├── task_board_v050_rules_test.dart
    │   ├── tdf_location_test.dart
    │   ├── tdf_v050_primitives_test.dart
    │   └── tdf_v060_merge_conformance_test.dart
    ├── providers/
    │   ├── config_providers_test.dart
    │   ├── local_file_watch_providers_test.dart
    │   ├── sync_providers_test.dart
    │   ├── task_providers_test.dart
    │   └── workspace_providers_test.dart
    ├── repositories/
    │   ├── app_version_repository_test.dart
    │   ├── link_launcher_repository_test.dart
    │   ├── local_file_repository_test.dart
    │   ├── location_repository_test.dart
    │   ├── settings_repository_test.dart
    │   └── webdav_repository_test.dart
    ├── services/
    │   ├── app_logger_test.dart
    │   ├── base64_service_test.dart
    │   ├── plus_code_service_test.dart
    │   ├── tdf_migration_test.dart
    │   ├── tdf_service_bounds_test.dart
    │   ├── tdf_service_parser_test.dart
    │   └── tdf_v060_conformance_test.dart
    └── ui/
        ├── app_theme_test.dart
        ├── edit_labels_screen_test.dart
        ├── edit_locations_screen_test.dart
        ├── edit_task_screen_test.dart
        ├── home_drawer_test.dart
        ├── home_screen_test.dart
        ├── local_directory_picker_test.dart
        ├── location_ui_test.dart
        ├── settings_screen_test.dart
        ├── test_helpers.dart
        └── widgets/
            ├── app_logo_test.dart
            ├── clearable_text_field_test.dart
            ├── label_color_picker_dialog_test.dart
            ├── quick_add_bar_test.dart
            ├── task_editor_conditions_test.dart
            ├── task_info_dialog_test.dart
            ├── tier_page_indicator_test.dart
            ├── tier_task_pill_test.dart
            ├── tier_task_subtasks_test.dart
            ├── wipe_tdf_dialog_test.dart
            └── workspace_dialog_test.dart
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
| `spec/TDF_SPEC_0.6.0.md` | Normative specification for the TierTask Data Format (`.tdf`) lexical grammar, blocks, directives, 6-tier derivation pipeline, mutations, and error bounds. |

## Localization

| File | Function |
| :--- | :--- |
| `lib/l10n/app_en.arb` | External English (`en`, default fallback) translation bundle for all UI labels, tier headings, and error messages. |
| `lib/l10n/app_de.arb` | External German (`de`) translation bundle for all UI labels, tier headings, and error messages. |
| `lib/l10n/tier_localization_extension.dart` | Extension on `AppLocalizations` mapping `TaskTier` (`1`–`6`) to localized tier names, uppercase section headings, and empty-state hints. |

## Domain Models

| File | Function |
| :--- | :--- |
| `lib/models/app_workspace.dart` | Defines immutable `AppWorkspace`, `WorkspaceSummary`, `WorkspaceErrorKind`, and `WorkspaceException` for isolated workspace configurations, suggested `.tdf` filenames (`AppWorkspace.suggestFileName`), uniqueness checks, and compact `TTW\x01` binary serialization (`encodePersistedState`, `decodePersistedState`, `toBytes`, `fromBytes`). |
| `lib/models/location_state.dart` | Defines immutable `GeocodingCandidate`, `LocationFix`, `LocationSource` (`gps`, `system`, `internet`), `LocationSourceType` (`gps`, `address`, `plusCode`), `LocationState`, and `LocationStatus` (`disabled`, `searching`, `found`, `unavailable`) with WGS-84 coordinate formatting, 100-meter Haversine displacement gating, and 5-minute resume refresh cooldown evaluation. |
| `lib/models/task_board.dart` | Defines the immutable `TaskBoard` aggregate storing `Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, and `Completed` tier slices, sorted `TdfLocation` and `TdfLabel` items, `TdfQueueBlock`, and `TdfDeletedBlock`, and delegating evaluation and mutations to `TaskBoardEvaluator`, `TaskBoardQueueMutator`, and `TaskBoardMutator`. |
| `lib/models/task_board_evaluator.dart` | Stateless dynamic $O(N)$ 6-tier derivation engine (`TaskBoardEvaluator`, `NormalizedTierSlices`, `TaskBoardSlicesX`) implementing `spec/TDF_SPEC_0.6.0.md` Section 5 tier partitioning, WIP soft limits (`3` `Focus`, `5` `Ready`), `scoped` label queue partitioning, 30-day UTC completed task and tombstone pruning, `subtasks auto-finish`, and label condition inheritance. |
| `lib/models/task_board_mutator.dart` | Stateless task, location, and label CRUD and recurrence mutation subsystem (`TaskBoardMutator`, `TaskBoardMutationSlicesX`) implementing `spec/TDF_SPEC_0.6.0.md` Sections 6.2–6.6 task addition, editing, completion, restoration, deletion, subtask toggling, location and label management, and monotonic `modifiedAt` stamping. |
| `lib/models/task_board_queue_mutator.dart` | Stateless queue-ordered scheduling and dependency re-arming subsystem (`TaskBoardQueueMutator`, `TaskBoardQueueSlicesX`) implementing `spec/TDF_SPEC_0.6.0.md` Section 6.5 tier downgrading (`Focus -> Ready -> Planned -> Someday` with `scoped` label boundary jumps), priority reordering, dependency cycle detection, and completion requirement capture. |
| `lib/models/task_board_reconciler.dart` | Stateless synchronization helper subsystem (`TaskBoardReconciler`) implementing `spec/TDF_SPEC_0.6.0.md` Sections 6.7–6.11 baseline payload lookup, monotonic revision selection, deterministic tie-breaking, deletion record and `generation` reconciliation, location conflict recovery, post-merge reference hygiene, and `queue` block reconciliation. |
| `lib/models/task_board_sync.dart` | Stateless three-way synchronization facade (`TaskBoardSync.merge`, `TaskBoardSync.stampAndNormalize`) coordinating baseline-aware task, location, label, `queue`, and `deleted` block reconciliation across in-memory, local file, and WebDAV `.tdf` revisions. |
| `lib/models/task_board_undo.dart` | Stateless single-task undo subsystem (`TaskBoardUndo`, `TaskUndoActionKind`, `TaskUndoEntry`, `TaskUndoOutcome`) capturing pre-mutation task and queue snapshots and reversing task completion, active downgrade, and deletion while preserving monotonic `completions`, `decisionRevision`, `deleted` `generation`, and live `label`/`location` hygiene. |
| `lib/models/task_item.dart` | Defines immutable `TaskItem`, `TaskOrigin`, `SubtaskItem`, `TaskLink`, `RepeatUnit`, and `TaskRepeatRule` value classes with 10-character Base62 `<task-id>` identifiers, UTC `created` / `finished` / `modified` / `suspended` / `due` timestamps, `completions` counter, recurrence rules, labels, dependencies, links, conditions, and ISO-8601 date/time helpers. |
| `lib/models/task_tier.dart` | Defines the `TaskTier` enum for the 6 derived tiers (`1` `focus` through `6` `completed`), WIP soft limits, and the `QuickAddMode` (`normal`, `priority`, `someday`) task creation scheduling enum. |
| `lib/models/tdf_error.dart` | Defines `TdfErrorKind`, `TdfException`, and normative `spec/TDF_SPEC_0.6.0.md` Section 7 resource bound constants (`maxTdfFileBytes`, `maxTdfLineCount`, `maxTdfNestingDepth`, `maxTdfBlocksPerDoc`, `maxTdfStmtsPerBlock`, `maxTdfArgsPerStmt`, `maxTdfTextLength`, `maxTdfNoteLength`, `maxTdfDeletedRecords`, `maxTdfGeneration`, `maxTdfCompletions`). |
| `lib/models/tdf_location.dart` | Defines the immutable `TdfLocation` value class (`id`, `name`, `latitude`, `longitude`, `radius`, `source`, `note`, `modifiedAt`), 10-character Base62 `<location-id>` generation and validation helpers (`generateLocationId`, `isValidLocationId`), canonical 6-decimal coordinate/radius formatting, and Haversine distance calculation (`distanceMeters`). |
| `lib/models/tdf_metadata.dart` | Defines immutable `ConditionGroup` (`day`, `time`, `location`), `TaskCondition` (`DayTaskCondition`, `GlobalResetTaskCondition`, `GroupResetTaskCondition`, `LocationTaskCondition`, `TimeWindowTaskCondition`), `TdfLabel` (with `isScoped`), `TdfColor` hex utilities, and 10-character Base62 entity identifier generation and validation helpers (`generateTaskId`, `generateLabelId`, `isValidTaskId`, `isValidLabelId`). |
| `lib/models/tdf_payload_comparison.dart` | Stateless non-revision payload equality and deterministic tie-break key extraction (`TdfPayloadComparison`) implementing `spec/TDF_SPEC_0.6.0.md` Sections 6.7.2, 6.7.3, and 6.7.5 across `TaskItem`, `TdfLocation`, and `TdfLabel`. |
| `lib/models/tdf_sync_metadata.dart` | Defines immutable `TdfQueueBlock` (`modifiedAt`, `taskIds`), `TdfDeletionRecordKind` (`task`, `location`, `label`), `TdfDeletionRecord`, `TdfDeletedBlock` (`generation`, `records`, `pruneExpired`, `recordDeletion`), and `TaskDependency` (`<task-id>[:<required-completion>]`) from `spec/TDF_SPEC_0.6.0.md` Sections 4.1.2, 4.3, 4.4, and 4.5. |
| `lib/models/tdf_timezone.dart` | Defines proleptic Gregorian calendar and Unicode scalar validation (`TdfCalendar`), recurring clock token (`TdfRepeatClock`), and local-to-UTC time zone transition resolution (`TdfTimeZoneContext` supporting `UTC`, fixed offsets, and `Europe/Berlin` DST rules). |
| `lib/models/webdav_config.dart` | Defines `AppLanguage`, `AppThemeMode`, `AppThemePalette`, `AppTimeZoneMode`, `StorageMode`, and the immutable `WebDavConfig` model with defaults (`tasks.tdf`, `localWatchEnabled: true`, `AppThemePalette.slate`, `AppTimeZoneMode.automatic`, `diagnosticsEnabled: false`) and UTC/local wall-clock conversion helpers (`toLocalWallClock`, `localWallClockToUtc`). |
| `lib/models/workspace_sync_state.dart` | Defines the immutable `WorkspaceSyncState` value class and compact `TTS\x03` binary serialization (`toBytes`, `fromBytes`) persisting `lastSyncedLocalTdf`, `lastSyncedRemoteTdf`, `acknowledgedLocalGeneration`, `acknowledgedRemoteGeneration`, `localSourceDigest`, `remoteEtag`, `remoteLastModified`, and `deletedLocationTimestamps`. |

## Services

| File | Function |
| :--- | :--- |
| `lib/services/app_logger.dart` | Opt-in structured diagnostic logging service (`AppLogger`, `AppLogSink`, `LogLevel`, `LogTag`, `LogMetadata`) at DAG rank `0`, formatting `<UTC-ISO> [<LEVEL>] [<TAG>] <event> | <key=value ...>` entries, redacting credentials (`sanitize`, `registerSecret`), managing the 5,000-line / 2 MiB dated `tiertask_<date>_<platform>_<workspace>.log` buffer with `@meta` headers, and preserving logs across clean and unclean exits. |
| `lib/services/base64_service.dart` | Single-pass $O(N)$ RFC 4648 Base64 encoder and decoder (`Base64Service`, `Base64Exception`, `Base64ErrorKind`) with pre-allocated `Uint8List` buffers, strict input byte bounds (`maxInputBytes`), alphabet validation, and non-zero padding-bit rejection. |
| `lib/services/plus_code_service.dart` | Stateless Open Location Code (Google Plus Code) parser, decoder, encoder, and nearest-locality recovery service (`PlusCodeService`, `PlusCodeArea`, `PlusCodeInput`, `FullPlusCodeInput`, `ShortPlusCodeInput`, `InvalidPlusCodeInput`). |
| `lib/services/tdf_directive_parser.dart` | Stateless TDF `0.6.0` statement and directive validation subsystem (`TdfDirectiveParser`) parsing `queue`, `deleted`, `location`, `label`, `task`, `condition`, and `subtasks` block directives and enforcing `spec/TDF_SPEC_0.6.0.md` Section 4 and Section 8 semantic rules. |
| `lib/services/tdf_historical_parser.dart` | Stateless historical TDF parser (`TdfHistoricalParser`) validating legacy `tdf 0.2.0`, `tdf 0.3.0`, `tdf 0.4.0`, `tdf 0.5.0`, and `tdf 0.5.1` block structures, directives, and timestamps during explicit document migration. |
| `lib/services/tdf_historical_serializer.dart` | Stateless canonical `LF` serializer (`TdfHistoricalSerializer`) emitting intermediate `tdf 0.3.0`, `tdf 0.4.0`, `tdf 0.5.0`, and `tdf 0.5.1` documents during adjacent step-by-step version migration. |
| `lib/services/tdf_id_migration.dart` | Pure Dart FIPS 180-4 SHA-256 implementation and deterministic `spec/TDF_SPEC_0.6.0.md` Section 10.2.3 Base62 identifier migration (`TdfIdMigration.sha256Bytes`, `TdfIdMigration.deriveBase62Prefix`, `TdfIdMigration.migrateEntityId`, `TdfIdMigration.deriveLocationId`) with collision probing. |
| `lib/services/tdf_importer.dart` | Stateless version import and adjacent migration coordinator (`TdfImporter.importDocument`, `TdfImporter.migrate020To030`, `TdfImporter.migrate030To040`, `TdfImporter.migrate040To050`, `TdfImporter.migrate050To051`, `TdfImporter.migrate051To060`, `TdfImportResult`) implementing `spec/TDF_SPEC_0.6.0.md` Section 10 migrations. |
| `lib/services/tdf_parser.dart` | Stateless TDF `0.6.0` document assembly and validation subsystem (`TdfParser`) coordinating header verification, cross-entity reference validation, and `TaskBoard.evaluate` invocation. |
| `lib/services/tdf_scanner.dart` | Single-pass $O(N)$ lexical scanner (`TdfScanner`, `TdfRawStatement`, `TdfRawBlock`) tokenizing `.tdf` byte and string streams into unescaped arguments, statements, and nested blocks while enforcing `spec/TDF_SPEC_0.6.0.md` Section 2 grammar and Section 7 resource bounds. |
| `lib/services/tdf_serializer.dart` | Stateless canonical `LF` `tdf 0.6.0` serializer (`TdfSerializer`) formatting `queue`, `deleted`, `location`, `label`, and `task` blocks in deterministic `spec/TDF_SPEC_0.6.0.md` Section 9 canonical order. |
| `lib/services/tdf_service.dart` | Stateless TDF `0.6.0` service facade (`TdfService.parse`, `TdfService.parseBytes`, `TdfService.serialize`) delegating lexical scanning, structural parsing, and canonical serialization to `TdfScanner`, `TdfParser`, and `TdfSerializer`. |

## Repositories

| File | Function |
| :--- | :--- |
| `lib/repositories/app_version_repository.dart` | Abstract `AppVersionRepository`, `PlatformAppVersionRepository`, and `FakeAppVersionRepository` isolating native `de.akjir.tiertask/app_version` `MethodChannel` queries and formatting SemVer 2.0.0 Git build metadata (`formatFullVersion`, `isValidFullVersion`, `defaultFullVersion`). |
| `lib/repositories/link_launcher_repository.dart` | Abstract `LinkLauncherRepository`, `PlatformLinkLauncherRepository`, `FakeLinkLauncherRepository`, and `LinkLaunchException` isolating native `de.akjir.tiertask/link_launcher` `MethodChannel` URI launching with pre-launch URI validation (`TaskLink.isValidUri`). |
| `lib/repositories/local_file_operations.dart` | Stateless native desktop file/folder picker (`zenity`, `kdialog`, PowerShell), non-recursive parent-directory `.tdf` file watcher (`watchTdfFile`, `isRelevantWatchEvent`, `matchesWatchedFileName`), `.bak` / `.bak.001`+ backup rotation, and atomic cross-device move/rename/delete subsystem (`LocalFileOperations`). |
| `lib/repositories/local_file_repository.dart` | Native `dart:io` `File` repository (`LocalFileRepository`, `LocalFileException`, `LocalFileLogSink`) reading, writing, watching (`watchTdfChanges`), selecting, moving, renaming, and deleting the local `.tdf` file, and implementing `AppLogSink` with 7-day / 5-file diagnostic log pruning. |
| `lib/repositories/location_repository.dart` | Abstract `LocationRepository`, `PlatformLocationRepository`, and `FakeLocationRepository` isolating native `de.akjir.tiertask/location` `MethodChannel` queries, 100-meter Haversine displacement-gated HTTPS reverse geocoding, bounded Nominatim forward geocoding (`searchLocations`), and 30-minute cached HTTPS GeoIP desktop fallback. |
| `lib/repositories/settings_repository.dart` | Abstract `SettingsRepository`, `SecureSettingsRepository` (`flutter_secure_storage`), and `InMemorySettingsRepository` persisting workspaces (`t2_settings_v1`), lightweight `WorkspaceSummary` items (`loadWorkspaceSummaries`), and per-workspace sync baselines (`t2_sync_v1_<id>`) via `Base64Service`. |
| `lib/repositories/webdav_repository.dart` | Native `dart:io` `HttpClient` WebDAV repository (`WebDavRepository`, `WebDavErrorKind`, `WebDavException`) executing authenticated conditional HTTP `GET` (`fetchTdf` with `If-None-Match`, `If-Modified-Since`, and `304 Not Modified` handling), conditional `PUT` (`saveTdf` with strong `ETag` `If-Match` precondition checks and `412 Precondition Failed` cache invalidation, plus `saveLog`), `DELETE` (`deleteLog`), and remote file wipe/re-initialization (`wipeTdf` with optional `.bak` / `.bak.001`+ backups). |

## State Providers

| File | Function |
| :--- | :--- |
| `lib/providers/config_providers.dart` | Defines `settingsRepositoryProvider`, `localFileRepositoryProvider`, `webdavRepositoryProvider`, `webdavConfigProvider` (`WebDavConfigNotifier`), `appLocaleProvider`, `appThemeModeProvider`, `appThemePaletteProvider`, `diagnosticsEnabledProvider`, `appVersionRepositoryProvider`, `appFullVersionProvider`, and `linkLauncherRepositoryProvider`. |
| `lib/providers/local_file_watch_providers.dart` | Defines `LocalFileWatchTarget`, `LocalFileWatcherNotifier`, `localFileWatchDebounceProvider`, `localFileWatchTargetProvider`, and `localFileWatcherProvider` for scoped parent-directory `.tdf` watching, `350 ms` trailing-edge debouncing, missing-directory rebinding, and `AppLifecycleState.resumed` catch-up reconciliation. |
| `lib/providers/location_providers.dart` | Defines `locationEnabledProvider`, `locationRepositoryProvider`, `locationStateProvider`, and `LocationNotifier` managing foreground-only location determination with startup/enable triggers, 5-minute app-resume cooldown, 15-minute passive foreground refresh, and manual refresh (`refreshLocation`). |
| `lib/providers/sync_providers.dart` | Defines `SyncStatus`, `SyncState`, `syncStateProvider` (`SyncStateNotifier`), and the stateless two-stage synchronization and file management pipeline (`TaskSyncPipeline`) coordinating `In-Memory <-> Local File <-> WebDAV` merges, backups, and error recovery. |
| `lib/providers/task_providers.dart` | Defines `taskNotifierProvider`, `taskUndoStateProvider`, `localFileWatchReadRetryDelayProvider`, `TaskUndoNotice`, `TaskUndoState`, `TaskUndoStateNotifier`, and `TaskNotifier` orchestrating domain mutations, bounded 10-entry LIFO undo recovery (`undoLastAction`), digest-gated external local reconciliation (`reconcileExternalLocalChanges`), workspace unload flushing, local file selection, remote wipe, legacy import, and two-stage synchronization. |
| `lib/providers/workspace_providers.dart` | Defines `activeWorkspaceProvider`, `workspaceSummariesProvider`, `workspaceUnloadCoordinatorProvider` (`WorkspaceUnloadCoordinator`), and `ActiveWorkspaceNotifier` orchestrating single-active-workspace switching (`switchWorkspace`), creation (`createWorkspace`), renaming (`renameWorkspace`), and deletion (`deleteWorkspace`). |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/main.dart` | Application entry point registering global crash hooks (`FlutterError.onError` and `PlatformDispatcher.instance.onError`) and `AppLifecycleListener`, and mounting `TierTaskApp` inside `ProviderScope` with Material 3 themes, `AppLocalizations.delegate`, and `GlobalMaterialLocalizations.delegates`. |
| `lib/ui/app_theme.dart` | Unified Material 3 theme definition (`AppTheme`, `AppThemeSet`, `appThemeProvider`) implementing `ThemeExtension<AppTheme>` and `toThemeData()` for the `Slate` and `Navy` light and dark palettes. |
| `lib/ui/edit_labels_screen.dart` | Dedicated label overview screen (`EditLabelsScreen`) and label editor panel (`EditLabelScreen`, `openEditLabelScreen`) for creating, editing, and deleting `TdfLabel` definitions with `scoped` queue toggle, custom color wheel selection, color presets, notes, and inherited conditions. |
| `lib/ui/edit_locations_screen.dart` | Dedicated location overview screen (`EditLocationsScreen`) and location editor panel (`EditLocationScreen`, `openEditLocationScreen`) for creating, editing, and deleting reusable `TdfLocation` entities with selectable source resolution (`GPS Coordinates`, `Address`, `Google Plus Code`), forward-geocoding candidate disambiguation, radius in meters, and notes. |
| `lib/ui/edit_task_screen.dart` | Full-screen task creation and editor panel (`EditTaskScreen`, `openEditTaskScreen`) coordinating Material 3 section cards for editing task details, scheduling (`Priority`, `Someday`, `Suspended`, `Due`), recurrence, labels, subtasks, links, dependencies, activation conditions, and confirmation-guarded task deletion. |
| `lib/ui/home_screen.dart` | Primary landing screen (`HomeScreen`) coordinating `HomeTopBar`, 6 horizontal `PageView` tier panes (`TierScrollView`) and search view (`AllTasksSearchView`), bottom `TierPageIndicator`, floating Undo `SnackBar` and desktop `Ctrl+Z` shortcut recovery, floating WebDAV sync and `QuickAddBar` triggers, and `HomeDrawer`. |
| `lib/ui/settings_screen.dart` | Configuration screen (`SettingsScreen`) coordinating display, time zone, location, and diagnostics preference cards (`SettingsPreferenceCards`), local `.tdf` storage controls (`SettingsLocalStorageSection`), WebDAV endpoint controls (`SettingsWebDavStorageSection`), and fixed bottom `Save` and `Sync` actions. |
| `lib/ui/widgets/app_logo.dart` | Vector application logo widget (`AppLogo`) rendering the stacked tier bars and completion checkmark badge in the navigation drawer header. |
| `lib/ui/widgets/clearable_text_field.dart` | Reusable text input widget (`ClearableTextField`) wrapping `TextField` or `TextFormField` with a focus-aware clear button (`Icons.close_rounded`) that resets the controller and preserves input focus. |
| `lib/ui/widgets/condition_editor_controller.dart` | Mutable form state controller (`ConditionEditorController`) managing weekday (`day`), time window (`time`), GPS radius (`location`), and reset (`any`) condition edits for `EditTaskScreen` and `EditLabelScreen`. |
| `lib/ui/widgets/home_drawer.dart` | Navigation drawer (`HomeDrawer`) and raw `.tdf` preview dialog (`showRawTdfPreviewDialog`) displaying the `AppLogo` header, `DrawerWorkspaceCard`, alphabetical `Labels` filters with open task count badges, alphabetical `Locations` quick-access rows, sync/settings actions, and SemVer build footer. |
| `lib/ui/widgets/home_tier_pane.dart` | Virtualized single-tier task list (`HomeTierPane`) and all-tasks search result list (`HomeAllTasksSearchList`) rendering `TierTaskPill` items with tier-grouped headers and empty-state hints. |
| `lib/ui/widgets/home_top_bar.dart` | Top navigation bar (`HomeTopBar`) rendering the drawer menu button, animated active label title, expandable inline task search field, and `TopBarLocationButton`. |
| `lib/ui/widgets/label_color_picker_dialog.dart` | Material 3 custom color picker dialog (`LabelColorPickerDialog`, `showLabelColorPickerDialog`) rendering an interactive HSV hue-saturation color wheel, brightness slider, and live `#RRGGBB` preview for labels. |
| `lib/ui/widgets/local_tdf_file_dialogs.dart` | Material 3 dialogs (`SelectLocalTdfDialog`, `RenameLocalTdfDialog`, `showSelectLocalTdfDialog`, `showRenameLocalTdfDialog`) for selecting or renaming local `.tdf` files with single-segment filename validation. |
| `lib/ui/widgets/location_status_dialog.dart` | Top-bar location status button (`TopBarLocationButton`) and popup dialog (`LocationStatusDialog`, `showLocationStatusDialog`) displaying foreground location status, place name, WGS-84 coordinates, source, and manual refresh trigger. |
| `lib/ui/widgets/log_viewer_dialog.dart` | Material 3 diagnostic log viewer (`LogViewerDialog`, `LogViewerScreen`, `showLogViewerDialog`) displaying session `@meta` statistics, minimum `LogLevel` and `LogTag` filters, severity-highlighted monospace entries, and `Sync Log Now`, `Copy All`, `Scroll to Bottom`, and `Clear Log` actions. |
| `lib/ui/widgets/quick_add_bar.dart` | Inline bottom task creation bar (`QuickAddBar`) featuring a title input, `Priority` and `Someday` toggles, an upward-anchored `OverlayPortal` `Labels` menu, an `Advanced` editor trigger, and responsive two-row stacking. |
| `lib/ui/widgets/settings_local_storage_section.dart` | Settings section card (`LocalStorageSection`, `LocalStorageActionsRow`, `ResolvedPathPreview`, `WipeStorageButton`) displaying the resolved local `.tdf` file path, `Select`, `Move`, `Rename`, and `Delete` actions, and the per-workspace external file watcher toggle. |
| `lib/ui/widgets/settings_preference_cards.dart` | Settings section cards (`SettingsPreferenceCards`, `SettingsCardContainer`, `SettingsFieldLabel`, `SettingsInlineMessage`) for language, theme mode, color palette, time zone, foreground location, and diagnostic logging preferences. |
| `lib/ui/widgets/settings_webdav_storage_section.dart` | Settings section card (`SettingsWebDavStorageSection`) for WebDAV server URL, username, password, remote `.tdf` path, and `Wipe Remote TDF File` configuration. |
| `lib/ui/widgets/task_editor_conditions_section.dart` | Shared activation conditions editor card (`TaskEditorConditionsSection`) rendering weekday (`day`), 24-hour time window (`time`), reusable `TdfLocation` chip (`location`), and task-only reset (`any`) controls. |
| `lib/ui/widgets/task_editor_links_section.dart` | Dedicated task links editor card (`TaskEditorLinksSection`) inside `EditTaskScreen` for viewing, opening, adding, validating, and removing repeatable `link "<title>" "<uri>"` directives. |
| `lib/ui/widgets/task_editor_scheduling_card.dart` | Task scheduling and recurrence editor widgets (`TaskEditorSchedulingCard`, `TaskEditorModeRow`, `TaskEditorSuspendedField`, `TaskEditorDueField`, `TaskEditorRepeatField`) managing `Priority`, `Someday`, `Suspended`, `Due`, and `Repeat` directives. |
| `lib/ui/widgets/task_editor_sections.dart` | Shared editor layout cards and inputs (`TaskEditorSectionCard`, `LabelEditorColorCard`, `TaskEditorDetailsCard`, `TaskEditorContextSection`, `TaskEditorTitleField`, `TaskEditorNoteField`, `TaskEditorActionsRow`, `TaskEditorChip`) used across `EditTaskScreen` and `EditLabelScreen`. |
| `lib/ui/widgets/task_editor_subtasks_and_blockers.dart` | Subtask checklist editor (`TaskEditorSubtasksSection` with `auto-finish` toggle), searchable prerequisite blocker selector (`TaskEditorBlockedBySection`), and board lookup helper (`TaskEditorBoardHelper`) for `EditTaskScreen`. |
| `lib/ui/widgets/task_info_dialog.dart` | Material 3 task information dialog (`TaskInfoDialog`, `showTaskInfoDialog`) displaying remaining suspension and due durations, subtask and prerequisite progress, active conditions, recurrence, labels, notes, and links. |
| `lib/ui/widgets/tier_page_indicator.dart` | Bottom 6-tier navigation indicator (`TierPageIndicator`) rendering inactive tier dots and an active tier icon with desktop hover previews, Left/Right arrow key navigation, and hold-and-drag wave selection. |
| `lib/ui/widgets/tier_task_pill.dart` | Task card widget (`TierTaskPill`) featuring a completion checkbox, interactive status indicators (`priority`, `suspended`, `blocked_by`, `conditions`, `repeat`, `note`, `links`, `subtasks`, `due`, and a summary indicator when exceeding `maxVisibleTaskIndicators`) that open `TaskInfoDialog`, bottom label color blocks, tier downgrade `>` and edit buttons, expandable subtasks section (`AnimatedSubtasksSection`), and directional transition animations. |
| `lib/ui/widgets/tier_task_subtasks_section.dart` | Expandable task details drawer (`AnimatedSubtasksSection`), indicator and label resolution helpers (`maxVisibleTaskIndicators`, `resolveTaskIndicatorSpecs`, `resolveTaskLabels`), clipboard note copying (`copyTaskNoteToClipboard`), link launching (`openTaskResourceLink`), and interactive subtask checklist rows. |
| `lib/ui/widgets/wipe_tdf_dialog.dart` | Confirmation dialog (`WipeTdfDialog`, `WipeTdfDialogResult`, `WipeTdfTarget`, `showWipeTdfDialog`) requiring exact filename confirmation and offering optional `.bak` / `.bak.001`+ backup creation before wiping a local or remote `.tdf` file. |
| `lib/ui/widgets/workspace_dialog.dart` | Active workspace navigation drawer card (`DrawerWorkspaceCard`) and Material 3 workspace management dialog (`WorkspaceDialog`, `showWorkspaceDialog`) coordinating workspace switching, creation, renaming, and deletion. |
| `lib/ui/widgets/workspace_row_card.dart` | Individual workspace list row card (`WorkspaceRowCard`) inside `WorkspaceDialog` rendering workspace metadata, storage mode badge, inline rename input, and delete confirmation controls. |

## Execution & Synchronization Flow

1. **Startup, Workspace Loading & Locale Resolution:** `main.dart` registers `LocalFileLogSink` on `AppLogger` and initializes `ProviderScope`. `ActiveWorkspaceNotifier` (`lib/providers/workspace_providers.dart`) loads only the single active `AppWorkspace` (`Tasks` / `tasks.tdf` by default) from `SettingsRepository`, `WebDavConfigNotifier` (`lib/providers/config_providers.dart`) exposes its `WebDavConfig`, and `appLocaleProvider` / `appThemeModeProvider` resolve the active `Locale` and `AppThemeMode` (`appThemeProvider` in `lib/ui/app_theme.dart`). Switching workspaces at runtime via `ActiveWorkspaceNotifier.switchWorkspace` unloads the current `TaskBoard` and `SyncState` from memory and loads the selected `AppWorkspace` and its `.tdf` file without restarting the application.
2. **Two-Stage TDF Fetch, External Directory Watching & Three-Way Merge (`In-Memory <-> Local File <-> WebDAV`):** On startup, on every manual sync (`syncFromRemote`, `testConnectionAndSync`), on external local `.tdf` edits detected via `LocalFileWatcherNotifier` (`350 ms` trailing-edge debounced `Directory.watch` events and `AppLifecycleState.resumed` catch-up checks gated by `WebDavConfig.localWatchEnabled` and `WorkspaceSyncState.localSourceDigest` inside `TaskNotifier.reconcileExternalLocalChanges`), and on every saved mutation (`addTask`, `updateTask`, `deleteTask`, `completeTask`, `restoreTask`, `downgradeTask`, `toggleSubtask`, `addLocation`, `updateLocation`, `deleteLocation`, `addLabel`, `updateLabel`, `deleteLabel`), `TaskNotifier` (`lib/providers/task_providers.dart`) delegates to `TaskSyncPipeline` (`lib/providers/sync_providers.dart`): Stage 1 reads the local `.tdf` file (`LocalFileRepository.readTdfWithDigest`), merges external local `tdf 0.6.0` changes with the in-memory `TaskBoard` across `task`, `location`, `label`, `queue`, and `deleted` (`generation`) via `TaskBoardSync.merge`, and writes the converged `tdf 0.6.0` document back to the local file via guarded CAS publication (`_publishLocalWithCasLoop`); Stage 2 seeds `WebDavRepository` with the persisted `remoteEtag`, `remoteLastModified`, and `lastSyncedRemoteTdf` baseline, fetches the remote `.tdf` file (`WebDavRepository.fetchTdf` using `If-None-Match` and `If-Modified-Since` to short-circuit unchanged remote files on `HTTP 304 Not Modified` without body transfer or redundant TDF parsing/merging), merges concurrent remote changes via `TaskBoardSync.merge`, writes changed `tdf 0.6.0` documents to WebDAV with strong `ETag` `If-Match` CAS retry (`_publishRemoteWithCasLoop` on `HTTP 412 Precondition Failed`), and updates the local `.tdf` file and `WorkspaceSyncState` (`lastSyncedLocalTdf`, `lastSyncedRemoteTdf`, `acknowledgedLocalGeneration`, `acknowledgedRemoteGeneration`, `localSourceDigest`, `remoteEtag`, `remoteLastModified`, `deletedLocationTimestamps`) so both storage backends converge to identical `tdf 0.6.0` documents. Explicit historical version migration (`0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1 -> 0.6.0`) is performed via `TaskNotifier.importLegacyTdf` (`TdfImporter.importDocument`).
3. **Single-Pass Parse & Dynamic 6-Tier Derivation:** `TdfService.parse` (`TdfScanner`, `TdfParser`, `TdfDirectiveParser`) validates the `tdf 0.6.0` header, scans and validates `queue`, `deleted`, `location`, `label`, and `task` blocks in a single $O(N)$ pass (interpreting `created`, `finished`, `modified`, `due`, and timed `suspended` in UTC while evaluating `condition day`, `condition time`, and `repeat` calendar progression in the user's configured local time zone), and invokes `TaskBoard.evaluate` (`TaskBoardEvaluator`) to derive `Completed`, `Someday` (open tasks omitted from `queue` without an active `suspended` lock), `Blocked`, and the `queue`-ordered active tiers (`Focus`, `Ready`, `Planned`, partitioned across global and `scoped` label queues) per `spec/TDF_SPEC_0.6.0.md` Section 5.
4. **Mutation, Undo & Persistence:** Every user action advances the mutated entity's (and `queue` block's when reordered) UTC `modified` timestamp monotonically (`TaskItem.nextModifiedTimestamp`), records explicit task, location, and label deletions in `deleted` (`TdfDeletedBlock`) via `TaskBoardMutator` and `TaskBoardQueueMutator`, captures bounded 10-entry in-memory LIFO undo snapshots (`TaskBoardUndo`) for task completion, downgrade, and deletion (with `TdfDeletionResolution.undelete` and `deleted` `generation` advancement on undo), triggers `TaskSyncPipeline`, serializes canonical `LF`-terminated `tdf 0.6.0` output via `TdfService.serialize` (`TdfSerializer`), and persists the converged `.tdf` document and sync baselines across the configured local and WebDAV targets.
5. **Opt-In Diagnostic Logging & Local/WebDAV Persistence (`AppLogger`):** All layers (`LIFECYCLE`, `TDF`, `DOMAIN`, `SYNC`, `STORAGE`, `UI`) report structured `<UTC-ISO> [<LEVEL>] [<TAG>] <event> | <key=value ...>` events to `AppLogger` (at DAG rank `0`, decoupled from `dart:io` via `AppLogSink` and `LocalFileLogSink`). When `diagnosticsEnabled` is `false` or an entry is below `minimumLevel`, logging calls are zero-allocation no-ops. When enabled, `AppLogger` writes a 5-line `@meta` header block to `tiertask_<YYYY-MM-DD>_<platform>_<workspaceId>.log`, prunes expired local logs (`7` days / `5` files per workspace), preserves logs across clean `detached` exits (`session.exit | state=detached crashed=false`), appends a recovery banner on startup after an unclean exit, flushes `[CRASH]` stack traces via `FlutterError.onError` and `PlatformDispatcher.instance.onError`, and uploads log snapshots to WebDAV (`WebDavRepository.saveLog`) via a 5-second debounce and `inactive`/`paused` lifecycle hooks when `logStorageMode` includes WebDAV.
