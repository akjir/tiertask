# TierTask Architecture and File Structure

> [!IMPORTANT]
> Update this file, [`AGENTS.md`](AGENTS.md), and [`TDF_SPEC.md`](TDF_SPEC.md) whenever the architecture, supported target platforms, directory layout, file responsibilities, localization files, or TDF synchronization flow change.

## Architectural Layers

| Layer | Path | Responsibility |
| :--- | :--- | :--- |
| Localization | `lib/l10n/` | External English (`app_en.arb`) and German (`app_de.arb`) resource bundles, generated `AppLocalizations` classes, and `TaskTier` localization mappings. |
| Models | `lib/models/` | Immutable domain data structures (`AppWorkspace`, `WorkspaceSummary`, `WorkspaceException`, `WorkspaceErrorKind`, `LocationFix`, `LocationSource`, `LocationState`, `LocationStatus`, `TaskTier`, `TaskItem`, `SubtaskItem`, `RepeatUnit`, `TaskRepeatRule`, `ConditionGroup`, `TaskCondition`, `TdfLabel`, `TdfColor`, `TdfQueueBlock`, `TdfDeletionRecord`, `TdfDeletedBlock`, `TaskDependency`, `TdfRepeatClock`, `TdfTimeZoneContext`, `TdfCalendar`, `TdfPayloadComparison`, `TaskBoard`, `TaskBoardSync`, `WorkspaceSyncState`, `AppLanguage`, `AppThemeMode`, `AppThemePalette`, `AppTimeZoneMode`, `StorageMode`, `WebDavConfig`) and the dynamic $O(N)$ 6-tier derivation, mutation, and three-way synchronization pipeline. |
| Services | `lib/services/` | Opt-in diagnostic logging service (`AppLogger`, `LogLevel`, `LogTag`), stateless single-pass $O(N)$ RFC 4648 Base64 codec (`Base64Service`, `Base64Exception`, `Base64ErrorKind`), deterministic SHA-256 Base62 legacy ID migration (`TdfIdMigration`), TDF `0.5.1` lexical scanner, structural parser (with automatic `0.5.0 -> 0.5.1` load-time conversion), and canonical `LF` serializer (`TdfService`, `TdfException`, `TdfErrorKind`), and explicit `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1` version import and adjacent migration pipeline (`TdfImporter`, `TdfImportResult`). |
| Repositories | `lib/repositories/` | All external I/O: WebDAV HTTP `GET`/`PUT` (`dart:io` `HttpClient`), local `.tdf` file reads/writes (`dart:io` `File`), foreground location channel and bounded reverse-geocoding/GeoIP lookup (`MethodChannel` and `HttpClient`), and encrypted workspace and settings persistence (`flutter_secure_storage`). |
| Providers | `lib/providers/` | Riverpod state management (`Provider`, `Notifier`, `AsyncNotifier`) coordinating single-active-workspace unload/load transitions, foreground lifecycle-aware location determination, locale and theme resolution, domain mutations, and repository synchronization. |
| UI | `lib/ui/` | Localized Material 3 screens and modular leaf widgets for Linux, Android, and Windows. |

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
├── TDF_SPEC.md
├── analysis_options.yaml
├── l10n.yaml
├── pubspec.yaml
├── android/
├── assets/
│   └── logo/
│       ├── tiertask_logo.png
│       └── tiertask_logo.svg
├── linux/
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
│   │   ├── task_board_sync.dart
│   │   ├── task_item.dart
│   │   ├── task_tier.dart
│   │   ├── tdf_metadata.dart
│   │   ├── tdf_payload_comparison.dart
│   │   ├── tdf_sync_metadata.dart
│   │   ├── tdf_timezone.dart
│   │   └── webdav_config.dart
│   ├── providers/
│   │   ├── location_providers.dart
│   │   ├── task_providers.dart
│   │   └── workspace_providers.dart
│   ├── repositories/
│   │   ├── app_version_repository.dart
│   │   ├── link_launcher_repository.dart
│   │   ├── local_file_repository.dart
│   │   ├── location_repository.dart
│   │   ├── settings_repository.dart
│   │   └── webdav_repository.dart
│   ├── services/
│   │   ├── app_logger.dart
│   │   ├── base64_service.dart
│   │   ├── tdf_id_migration.dart
│   │   ├── tdf_importer.dart
│   │   └── tdf_service.dart
│   └── ui/
│       ├── app_theme.dart
│       ├── edit_labels_screen.dart
│       ├── edit_task_screen.dart
│       ├── home_screen.dart
│       ├── settings_screen.dart
│       └── widgets/
│           ├── app_logo.dart
│           ├── clearable_text_field.dart
│           ├── local_tdf_file_dialogs.dart
│           ├── location_status_dialog.dart
│           ├── log_viewer_dialog.dart
│           ├── quick_add_bar.dart
│           ├── task_editor_conditions_section.dart
│           ├── task_editor_links_section.dart
│           ├── task_editor_sections.dart
│           ├── tier_page_indicator.dart
│           ├── tier_task_pill.dart
│           ├── wipe_tdf_dialog.dart
│           └── workspace_dialog.dart
└── test/
    ├── models/
    │   ├── app_workspace_test.dart
    │   ├── location_state_test.dart
    │   ├── task_board_downgrade_test.dart
    │   ├── task_board_evaluation_test.dart
    │   ├── task_board_lifecycle_test.dart
    │   ├── task_board_mutation_test.dart
    │   ├── task_board_sync_test.dart
    │   ├── task_board_v050_rules_test.dart
    │   └── tdf_v050_primitives_test.dart
    ├── repositories/
    │   ├── app_version_repository_test.dart
    │   ├── link_launcher_repository_test.dart
    │   ├── local_directory_migration_test.dart
    │   ├── location_repository_test.dart
    │   ├── storage_and_providers_test.dart
    │   └── sync_merge_test.dart
    ├── services/
    │   ├── app_logger_test.dart
    │   ├── base64_service_test.dart
    │   ├── tdf_migration_test.dart
    │   ├── tdf_service_bounds_test.dart
    │   └── tdf_service_parser_test.dart
    └── ui/
        ├── app_theme_test.dart
        ├── edit_labels_screen_test.dart
        ├── edit_task_screen_test.dart
        ├── home_screen_test.dart
        ├── local_directory_picker_test.dart
        ├── location_ui_test.dart
        ├── settings_screen_test.dart
        ├── test_helpers.dart
        └── widgets/
            ├── app_logo_test.dart
            ├── clearable_text_field_test.dart
            ├── quick_add_bar_test.dart
            ├── task_editor_conditions_test.dart
            ├── tier_page_indicator_test.dart
            ├── tier_task_pill_test.dart
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
| `TDF_SPEC.md` | Normative specification for the TierTask Data Format (`.tdf`) lexical grammar, blocks, directives, 6-tier derivation pipeline, mutations, and error bounds. |
| `analysis_options.yaml` | Dart analyzer configuration excluding `build/**`, `android/**`, `linux/**`, `windows/**`, and generated `lib/l10n/app_localizations*.dart` files. |
| `l10n.yaml` | Flutter `gen-l10n` configuration pointing to `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb`. |
| `pubspec.yaml` | Package metadata and dependencies (`flutter`, `flutter_localizations`, `flutter_riverpod`, `flutter_secure_storage`, `intl`). |

## Localization

| File | Function |
| :--- | :--- |
| `lib/l10n/app_en.arb` | External English (`en`, default fallback) translation bundle for all UI labels, tier headings, and error messages. |
| `lib/l10n/app_de.arb` | External German (`de`) translation bundle for all UI labels, tier headings, and error messages. |
| `lib/l10n/tier_localization_extension.dart` | Extension on `AppLocalizations` mapping `TaskTier` (`1`–`6`) to localized tier names, uppercase section headings, and empty-state hints. |

## Domain Models

| File | Function |
| :--- | :--- |
| `lib/models/app_workspace.dart` | Defines immutable `AppWorkspace`, `WorkspaceSummary`, `WorkspaceErrorKind`, and `WorkspaceException` for isolated workspace configurations and `.tdf` files, defaulting to `Tasks` (`tasks.tdf`), deriving suggested lowercase `.tdf` filenames (`AppWorkspace.suggestFileName`), enforcing unique workspace names and `.tdf` file paths, and serializing workspaces and the active workspace index into a compact `TTW\x01` binary `Uint8List` format (`encodePersistedState`, `decodePersistedState`, `toBytes`, `fromBytes`) with bit-packed enum flags, `locationEnabled` and `diagnosticsEnabled` bits, and 16-bit length-prefixed UTF-8 strings. |
| `lib/models/location_state.dart` | Defines immutable `LocationFix`, `LocationSource` (`gps`, `system`, `internet`), `LocationState`, and `LocationStatus` (`disabled`, `searching`, `found`, `unavailable`) for foreground location determination, including 5-decimal WGS-84 coordinate formatting (`formattedCoordinates`), 100-meter Haversine displacement gating (`isWithinDisplacementThreshold`), and 5-minute resume refresh cooldown evaluation (`shouldRefreshOnResume`). |
| `lib/models/task_tier.dart` | Defines the `TaskTier` enum for the 6 derived tiers (`1` `focus`, `2` `ready`, `3` `planned`, `4` `blocked`, `5` `someday`, `6` `completed`) and WIP soft limits. |
| `lib/models/tdf_metadata.dart` | Immutable `ConditionGroup` (`day`, `time`, `location`), `TaskCondition` (`DayTaskCondition`, `GlobalResetTaskCondition`, `GroupResetTaskCondition`, `LocationTaskCondition`, `TimeWindowTaskCondition`), `TdfLabel` (including `modifiedAt` and `effectiveModifiedAt`), `TdfColor` hex color utilities, and 10-character Base62 entity identifier generation, validation, and non-conforming ID conversion helpers (`tdfBase62Alphabet`, `tdfBase62TimeModulo`, `encodeTdfBase62Time`, `isValidTaskId`, `isValidLabelId`, `generateTaskId`, `generateLabelId`, `convertLegacyEntityId`) from `TDF_SPEC.md` Sections 2.9, 4, and 10.2.3. |
| `lib/models/tdf_payload_comparison.dart` | Stateless non-revision payload equality and deterministic tie-break key extraction (`TdfPayloadComparison`) implementing `TDF_SPEC.md` Sections 6.7.2, 6.7.3, and 6.7.5 across `TaskItem` and `TdfLabel` (ignoring `modifiedAt` and comparing ordered vs order-insensitive payloads). |
| `lib/models/tdf_sync_metadata.dart` | Immutable `TdfQueueBlock` (`modifiedAt`, `taskIds`), `TdfDeletionRecordKind` (`task`, `label`), `TdfDeletionRecord`, `TdfDeletedBlock` (`generation`, `records`, `pruneExpired`, `recordDeletion`), `TaskDependency` (`<task-id>[:<required-completion>]`), and `TdfErrorKind` (`versionMismatch`, `circularDependency`, `invalidQueueMembership`, `invalidCompletionState`, `timeZoneContextRequired`, etc.) and `TdfException` from `TDF_SPEC.md` Sections 4.1.2, 4.4, 4.5, and 8. |
| `lib/models/tdf_timezone.dart` | Proleptic Gregorian calendar and Unicode scalar validation (`TdfCalendar`), recurring clock token (`TdfRepeatClock`), and local-to-UTC time zone transition resolution (`TdfTimeZoneContext` supporting `UTC`, fixed offsets, and `Europe/Berlin` DST spring-forward gap and fall-back fold rules) per `TDF_SPEC.md` Sections 2.6, 2.8, 3.3, 6.6.1, and 6.10. |
| `lib/models/task_item.dart` | Immutable `TaskItem`, `SubtaskItem`, `TaskLink`, `RepeatUnit`, and `TaskRepeatRule` value classes with 10-character Base62 TDF `<task-id>` (`<6xBase62Random><4xBase62Time>`), `priority` flag, UTC `created` / `finished` / `modified` timestamps (`modifiedAt`, `effectiveModifiedAt`, `nextModifiedTimestamp`), `suspended` (`isSuspendedForever` or UTC `suspendedUntil`), `completions` counter, completion-relative `repeat <count> <days\|weeks\|months> [<repeat-time>]` rule, `labels`, `dependencies` (`TaskDependency`), repeatable `link <title> <uri>` directives (`TaskLink.isValidUri`, `TaskLink.tryParse`, `maxLinksPerTask = 20`, `maxUriLength = 2048`), `conditions`, `subtasks auto-finish`, subtask completion synchronization (`toCompleted`), and strict ISO-8601 date/time helpers. |
| `lib/models/task_board.dart` | Immutable `TaskBoard` aggregate implementing the dynamic (N)$ 6-tier derivation pipeline (`evaluate`, `evaluateForContext`), shared `queue` ordering (`Focus`, `Ready`, `Planned`, `Blocked` vs. `Someday`), 30-day UTC completed task and `deleted` tombstone pruning, recurring task rescheduling (`repeat`), `subtasks auto-finish`, label condition inheritance, Base62 ID generation, and `TDF_SPEC.md` Section 6 mutations with monotonic `modifiedAt` stamping. |
| `lib/models/task_board_sync.dart` | Stateless three-way synchronization engine (`TaskBoardSync.merge`, `TaskBoardSync.stampAndNormalize`) and persisted sync baseline state (`WorkspaceSyncState` with `TTS\x01` binary serialization and `acknowledgedLocalGeneration` / `acknowledgedRemoteGeneration`) implementing `TDF_SPEC.md` Sections 6.7, 6.8, 6.9.5, and 6.11 baseline-aware payload comparison, monotonic revision selection, deterministic tie-breaking, deletion record and `generation` reconciliation, post-merge reference hygiene (`queue`, `labels`, `blocked`), and `queue` block reconciliation. |
| `lib/models/webdav_config.dart` | Defines `AppLanguage` (`system`, `english`, `german`), `AppThemeMode` (`system`, `light`, `dark`), `AppThemePalette` (`slate`, `navy`), `AppTimeZoneMode` (`automatic`, `manual`), `StorageMode` (`local`, `webdav`, `both`) with compact binary IDs (`id` / `fromId`), and the immutable `WebDavConfig` model defaulting to `tasks.tdf`, `AppThemePalette.slate`, `AppTimeZoneMode.automatic`, `diagnosticsEnabled: false` (`enableLogging`), and UTC/local wall-clock conversion helpers (`toLocalWallClock`, `localWallClockToUtc`). |

## Services

| File | Function |
| :--- | :--- |
| `lib/services/app_logger.dart` | Opt-in diagnostic logging service (`AppLogger`, `LogLevel`, `LogTag`) formatting UTC millisecond entries, redacting credentials (`sanitize`, `registerSecret`), enforcing a rolling 5,000-line / 2 MiB `tiertask.log` ring buffer, preserving `[CRASH]` stack traces across unclean exits, and truncating the log on clean `detached` exit. |
| `lib/services/base64_service.dart` | Single-pass $O(N)$ RFC 4648 Base64 encoder and decoder (`Base64Service`, `Base64Exception`, `Base64ErrorKind`) with pre-allocated `Uint8List` buffers, strict input byte bounds (`maxInputBytes`), alphabet validation, padding verification, and non-zero padding-bit rejection (RFC 4648 Section 3.5). |
| `lib/services/tdf_id_migration.dart` | Pure Dart FIPS 180-4 SHA-256 implementation and deterministic `TDF_SPEC.md` Section 10.2.3 Base62 identifier migration (`TdfIdMigration.sha256Bytes`, `TdfIdMigration.deriveBase62Prefix`, `TdfIdMigration.migrateEntityId`) mapping legacy `<id>` values to 10-character `<6xBase62Prefix><4xBase62Time>` identifiers with deterministic collision probing. |
| `lib/services/tdf_importer.dart` | Stateless version import and adjacent migration service (`TdfImporter.importDocument`, `TdfImporter.migrate020To030`, `TdfImporter.migrate030To040`, `TdfImporter.migrate040To050`, `TdfImporter.migrate050To051`, and `TdfImportResult`) implementing `TDF_SPEC.md` Section 10 historical schema validation (`0.2.0`, `0.3.0`, `0.4.0`, `0.5.0`), local-to-UTC timestamp conversion, SHA-256 Base62 ID migration, reference rewriting, and `0.5.1` `queue` construction and `queued` removal. |
| `lib/services/tdf_service.dart` | Single-pass (N)$ lexical scanner, structural parser, and canonical `LF` `tdf 0.5.1` serializer (`TdfService`) validating `tdf 0.5.1` headers, converting `tdf 0.5.0` documents in memory on load, scanning `queue`, `deleted`, `label`, and `task` blocks, and enforcing all `TDF_SPEC.md` Section 7 resource bounds and Section 8 `TdfErrorKind` errors without regular expressions. |

## Repositories

| File | Function |
| :--- | :--- |
| `lib/repositories/app_version_repository.dart` | Abstract `AppVersionRepository`, `PlatformAppVersionRepository`, and `FakeAppVersionRepository` isolating native `de.akjir.tiertask/app_version` `MethodChannel` queries (`getAppVersion` returning compile-time `TIERTASK_FULL_VERSION` / `R.string.tiertask_full_version`) and formatting SemVer 2.0.0 Git build metadata (`v0.1.0+<count>.<hash>[.dev]` via `formatFullVersion`, `isValidFullVersion`, and `defaultFullVersion`). |
| `lib/repositories/link_launcher_repository.dart` | Abstract `LinkLauncherRepository`, `PlatformLinkLauncherRepository`, `FakeLinkLauncherRepository`, and `LinkLaunchException` isolating native `de.akjir.tiertask/link_launcher` `MethodChannel` URI launching (`g_app_info_launch_default_for_uri` on Linux, `ShellExecuteW` on Windows, and `Intent(Intent.ACTION_VIEW)` on Android) with pre-launch URI scheme and control-character validation (`TaskLink.isValidUri`). |
| `lib/repositories/local_file_repository.dart` | Native `dart:io` `File` repository reading (`loadTdf`), writing (`saveTdf`), selecting (`pickTdfFile`, `pickDirectory`), moving (`moveTdfFile`), renaming (`renameTdfFile`), and deleting (`deleteTdfFile` with optional `.bak` / `.bak.001`+ backups) the local `.tdf` file with path validation, `maxFileBytes` bounds, conflict checks, and synchronous `tiertask.log` file I/O. |
| `lib/repositories/location_repository.dart` | Abstract `LocationRepository`, `PlatformLocationRepository`, and `FakeLocationRepository` isolating native `de.akjir.tiertask/location` `MethodChannel` queries (Android foreground `LocationManager` cache-first lookup with 5-minute freshness and `Geocoder`, Linux `GeoClue2` D-Bus client, and Windows WinRT `Windows.Devices.Geolocation.Geolocator`), 100-meter Haversine displacement-gated HTTPS reverse geocoding, and 30-minute cached HTTPS GeoIP desktop fallback. |
| `lib/repositories/settings_repository.dart` | Abstract `SettingsRepository`, `SecureSettingsRepository` (`flutter_secure_storage`), and `InMemorySettingsRepository` for persisting workspaces and the active workspace in a single atomic Base64-encoded `TTW\x01` binary key (`t2_settings_v1`), loading lightweight `WorkspaceSummary` items (`loadWorkspaceSummaries`), and persisting per-workspace sync baselines (`WorkspaceSyncState` in `t2_sync_v1_<id>`) via `Base64Service`. |
| `lib/repositories/webdav_repository.dart` | Native `dart:io` `HttpClient` WebDAV repository executing authenticated HTTP `GET` (`fetchTdf`), `PUT` (`saveTdf`), and remote file wipe/re-initialization (`wipeTdf` with optional `.bak` / `.bak.001`+ remote backup creation) operations with localized `WebDavException` error mapping. |

## State Providers

| File | Function |
| :--- | :--- |
| `lib/providers/location_providers.dart` | Defines `locationEnabledProvider`, `locationRepositoryProvider`, `locationStateProvider`, and `LocationNotifier` managing foreground-only location determination with startup/enable triggers, 5-minute app-resume cooldown (`minResumeRefreshInterval`), 15-minute passive foreground refresh (`passiveRefreshInterval`), immediate timer cancellation on app pause/hide/detach, and manual refresh (`refreshLocation`). |
| `lib/providers/task_providers.dart` | Riverpod providers and notifiers (`AppThemeNotifier`, `SyncStateNotifier`, `WebDavConfigNotifier`, `TaskNotifier`) orchestrating locale, theme, palette, location, and diagnostics preferences, local `.tdf` file selection/move/rename/delete and remote wipe actions, single-pass load-failure retry suppression, workspace unload flushing, board mutations, and two-stage local/WebDAV `.tdf` synchronization. |
| `lib/providers/workspace_providers.dart` | Defines `activeWorkspaceProvider`, `workspaceSummariesProvider`, `workspaceUnloadCoordinatorProvider` (`WorkspaceUnloadCoordinator`), and `ActiveWorkspaceNotifier`, holding only the single active `AppWorkspace` in memory and orchestrating lossless runtime workspace unload/load switching (`switchWorkspace`), creation (`createWorkspace`), renaming (`renameWorkspace`), deletion (`deleteWorkspace`), and active configuration updates (`updateActiveConfig`). |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/main.dart` | Application entry point registering global crash hooks (`FlutterError.onError` and `PlatformDispatcher.instance.onError` wired to `AppLogger.crash`) and `AppLifecycleListener` (`AppLogger.handleAppLifecycleState`), wrapping `TierTaskApp` in a `ProviderScope` with Material 3 light/dark/system themes from `appThemeProvider` (`lib/ui/app_theme.dart`) and `AppLocalizations` delegates (`en` and `de`). |
| `lib/ui/app_theme.dart` | Single unified application theme definition (`AppTheme` and `AppThemeSet`) implementing `ThemeExtension<AppTheme>` and `toThemeData()` for both the default Chromium-inspired Material 3 `Slate` palette (`AppTheme.slateDark` / `AppTheme.dark`, `AppTheme.slateLight` / `AppTheme.light`, `AppThemeSet.slate`) and the `Navy` palette (`AppTheme.navyDark`, `AppTheme.navyLight`, `AppThemeSet.navy`), providing all semantic surface, accent, tonal container (`primaryContainer`, `onPrimaryContainer`, `secondaryContainer`, `onSecondaryContainer`), text, indicator, and logo gradient tokens consumed across the UI and replaceable at runtime via `appThemeProvider`. |
| `lib/ui/edit_labels_screen.dart` | Dedicated label overview screen (`EditLabelsScreen`) and label editor panel (`EditLabelScreen` and `openEditLabelScreen`): `EditLabelsScreen` lists all labels in alphabetical order (`board.sortedLabels`) with new label creation, open task count badges (`Badge.count`), quick label deletion (`delete_label_button_<id>`), and a right-side edit button (`edit_label_button_<id>`) that opens `EditLabelScreen` to edit `name`, `color` (`LabelEditorColorCard`), `note`, and `condition` (`day`, `time`, `location`) reusing `TaskEditorDetailsCard`, `TaskEditorConditionsSection` (`allowResets: false`), and `TaskEditorActionsRow`. |
| `lib/ui/edit_task_screen.dart` | Full-screen task creation and editor panel (`EditTaskScreen`, `openEditTaskScreen`) grouped into Material 3 section cards for editing task name, note, scheduling mode (`Priority`, `Someday`, `Suspended`, `Repeat`), labels, subtasks (`auto-finish`), repeatable task links (`TaskEditorLinksSection`), prerequisite dependencies (`blocked` with cycle prevention), and activation conditions (`ConditionEditorController`). |
| `lib/ui/home_screen.dart` | Primary landing screen (`HomeScreen`) displaying the top navigation bar (menu drawer toggle, animated active label header, inline all-tasks search toggle, and `TopBarLocationButton`), 6 horizontal `PageView` tier panels (`Focus` through `Completed`) and all-tasks search results rendered with `TierTaskPill` cards, bottom `TierPageIndicator`, floating WebDAV sync and `QuickAddBar` triggers, and the navigation drawer (`DrawerWorkspaceCard`, alphabetical `Labels`, sync/preview/settings actions, and version footer). |
| `lib/ui/settings_screen.dart` | Configuration screen (`SettingsScreen`) for display language, theme mode, Material 3 palette (`Slate`, `Navy`), time zone (`Automatic`, `Manual`), foreground location determination, diagnostic logging, storage mode (`Local`, `WebDAV`, `Both`), local `.tdf` file actions (`Select`, `Move`, `Rename`, `Delete`), WebDAV endpoint parameters and remote wipe (`Wipe Remote TDF File`), and fixed bottom `Save` and `Test Connection / Sync Now` actions. |
| `lib/ui/widgets/app_logo.dart` | Vector application logo widget (`AppLogo` and `_AppLogoPainter`) rendering the stacked tier bars and completion checkmark badge in the navigation drawer header. |
| `lib/ui/widgets/clearable_text_field.dart` | Reusable text input widget (`ClearableTextField`) wrapping `TextField` or `TextFormField` that displays a right-side clear icon button (`Icons.close_rounded`) when focused, composes with any existing `InputDecoration.suffixIcon`, clears the `TextEditingController`, notifies `onChanged` and `onCleared`, and keeps focus on the input. |
| `lib/ui/widgets/local_tdf_file_dialogs.dart` | Material 3 dialogs (`SelectLocalTdfDialog`, `RenameLocalTdfDialog`, `showSelectLocalTdfDialog`, and `showRenameLocalTdfDialog`) for selecting an existing `.tdf` file or entering a new `.tdf` file name on platforms without a native desktop file chooser and for renaming the active local `.tdf` file inside its current directory with single-segment filename validation (`LocalFileRepository.isValidSingleFileName` and `LocalFileRepository.ensureTdfExtension`). |
| `lib/ui/widgets/location_status_dialog.dart` | Header location status icon button (`TopBarLocationButton` rendering `searching`, `found`, and `unavailable` states) and popup status dialog (`LocationStatusDialog` and `showLocationStatusDialog`) displaying the current location status, determined place name, GPS coordinates, location source (`GPS`, `System / Network`, `Internet (GeoIP)`), and a `Refresh` button. |
| `lib/ui/widgets/log_viewer_dialog.dart` | Material 3 diagnostic log viewer dialog (`LogViewerDialog` / `LogViewerScreen` and `showLogViewerDialog`) opened from the navigation drawer when `enableLogging` is `true`, displaying monospace `tiertask.log` lines with vertical and horizontal scrolling, semantic color accents for `[WARN]`, `[ERROR]`, and `[CRASH]` entries, and toolbar actions for `Copy All`, `Scroll to Bottom`, and `Clear Log`. |
| `lib/ui/widgets/quick_add_bar.dart` | Inline bottom task creation bar (`QuickAddBar`) featuring a borderless title input, mutually exclusive `Priority` and `Someday` toggles, an upward-anchored `OverlayPortal` multi-select `Labels` menu, an `Advanced` button opening `EditTaskScreen`, and automatic two-row stacking on narrow viewports. |
| `lib/ui/widgets/task_editor_conditions_section.dart` | Shared activation conditions controller (`ConditionEditorController`) and card (`TaskEditorConditionsSection`) used by `EditTaskScreen` and `EditLabelScreen`, rendering weekday (`day`), time window (`time` with 24-hour Material 3 time picker buttons), and GPS location (`location`) controls along with task-only reset chips (`condition any`, `day any`, `time any`, `location any` when `allowResets` is `true`). |
| `lib/ui/widgets/task_editor_links_section.dart` | Dedicated task links editor card (`TaskEditorLinksSection`) inside `EditTaskScreen` for viewing, opening, adding, validating, and removing repeatable `link "<title>" "<uri>"` directives. |
| `lib/ui/widgets/task_editor_sections.dart` | Reusable `SettingsScreen`-style section card (`TaskEditorSectionCard`), form cards (`LabelEditorColorCard`, `TaskEditorDetailsCard`, `TaskEditorSchedulingCard`, `TaskEditorContextSection`, `TaskEditorSubtasksSection`, `TaskEditorBlockedBySection`), date/time and recurrence fields (`TaskEditorSuspendedField`, `TaskEditorRepeatField`), prerequisite name search, and action widgets (`TaskEditorTitleField`, `TaskEditorNoteField`, `TaskEditorModeRow`, `TaskEditorActionsRow`, `TaskEditorChip`) shared across `EditTaskScreen` and `EditLabelScreen`. |
| `lib/ui/widgets/tier_page_indicator.dart` | Bottom 6-tier navigation indicator (`TierPageIndicator`) rendering dots for inactive tiers and an active tier icon with desktop hover previews, Left/Right arrow key navigation, and an interactive hold-and-drag wave effect. |
| `lib/ui/widgets/tier_task_pill.dart` | Task card widget (`TierTaskPill`) featuring a completion checkbox, passive status indicator icons (`priority`, `repeat`, `note`, `links`, `subtasks`) with localized tooltips, tier downgrade `>` and edit `⋮` buttons, an expandable drawer for notes, links, and interactive subtask steps, and directional completion/downgrade/restore/auto-pull transition animations. |
| `lib/ui/widgets/wipe_tdf_dialog.dart` | Confirmation dialog (`WipeTdfDialog`, `WipeTdfDialogResult`, `WipeTdfTarget`, and `showWipeTdfDialog`) requiring the user to type the exact file name without the `.tdf` extension before enabling the wipe confirmation button (`wipe_tdf_confirm_button`), keeping the cancel button (`wipe_tdf_cancel_button`) always enabled, and providing an optional checkbox (`wipe_tdf_backup_checkbox`) to create a `.bak` or `.bak.001`+ backup beforehand when the file exists. |
| `lib/ui/widgets/workspace_dialog.dart` | Active workspace navigation drawer card (`DrawerWorkspaceCard`) and Material 3 workspace management dialog (`WorkspaceDialog` and `showWorkspaceDialog`) supporting workspace switching, workspace creation with a live `.tdf` filename suggestion preview (`AppWorkspace.suggestFileName`), inline workspace renaming, and confirmed workspace deletion. |

## Execution & Synchronization Flow

1. **Startup, Workspace Loading & Locale Resolution:** `main.dart` initializes `ProviderScope`. `ActiveWorkspaceNotifier` loads only the single active `AppWorkspace` (`Tasks` / `tasks.tdf` by default) from `SettingsRepository`, `WebDavConfigNotifier` exposes its `WebDavConfig`, and `appLocaleProvider` / `appThemeModeProvider` resolve the active `Locale` and `AppThemeMode`. Switching workspaces at runtime via `ActiveWorkspaceNotifier.switchWorkspace` unloads the current `TaskBoard` and `SyncState` from memory and loads the selected `AppWorkspace` and its `.tdf` file without restarting the application.
2. **Two-Stage TDF Fetch & Three-Way Merge (`In-Memory <-> Local File <-> WebDAV`):** On startup, on every manual sync (`syncFromRemote`, `testConnectionAndSync`), and on every saved mutation (`addTask`, `updateTask`, `completeTask`, `restoreTask`, `downgradeTask`, `toggleSubtask`, `addLabel`, `updateLabel`, `deleteLabel`), `TaskNotifier` runs the two-stage merge pipeline (`_synchronizePipeline`): Stage 1 reads the local `.tdf` file (`LocalFileRepository.loadTdf`), merges external local `tdf 0.5.1` (or load-converted `tdf 0.5.0`) changes with the in-memory `TaskBoard` across `task`, `label`, `queue`, and `deleted` (`generation`) via `TaskBoardSync.merge`, and writes the converged `tdf 0.5.1` document back to the local file; Stage 2 fetches the remote `.tdf` file (`WebDavRepository.fetchTdf`), merges concurrent remote changes via `TaskBoardSync.merge`, writes the converged `tdf 0.5.1` document to WebDAV, and updates the local `.tdf` file and `WorkspaceSyncState` (`lastSyncedLocalTdf`, `lastSyncedRemoteTdf`, `acknowledgedLocalGeneration`, `acknowledgedRemoteGeneration`) so both storage backends converge to identical `tdf 0.5.1` documents. Explicit historical version migration (`0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1`) is performed via `TaskNotifier.importLegacyTdf` (`TdfImporter.importDocument`).
3. **Single-Pass Parse & Dynamic 6-Tier Derivation:** `TdfService.parse` validates the `tdf 0.5.1` header (and automatically converts `tdf 0.5.0` documents in memory per `TDF_SPEC.md` Section 10.6), scans and validates `queue`, `deleted`, `label`, and `task` blocks in a single $O(N)$ pass (interpreting `created`, `finished`, `modified`, and timed `suspended` in UTC while evaluating `condition day`, `condition time`, and `repeat` calendar progression in the user's configured local time zone), and invokes `TaskBoard.evaluate` to derive `Completed`, `Someday` (open tasks omitted from `queue` without an active `suspended` lock), `Blocked`, and the `queue`-ordered active tiers (`Focus`, `Ready`, `Planned`) per `TDF_SPEC.md` Section 5.
4. **Mutation & Persistence:** Every user action advances the mutated entity's (and `queue` block's when reordered) UTC `modified` timestamp monotonically (`TaskItem.nextModifiedTimestamp`), records explicit task and label deletions in `deleted` (`TdfDeletedBlock`), triggers the two-stage synchronization pipeline, serializes canonical `LF`-terminated `tdf 0.5.1` output via `TdfService.serialize`, and persists the converged `.tdf` document and sync baselines across the configured local and WebDAV targets.
5. **Opt-In Diagnostic Logging & Crash Preservation (`AppLogger`):** All layers (`LIFECYCLE`, `TDF`, `DOMAIN`, `SYNC`, `STORAGE`, `UI`) report state transitions, durations, tier distributions, and errors to `AppLogger`. When `diagnosticsEnabled` is `false`, logging calls are zero-allocation no-ops. When enabled, `AppLogger` inspects `tiertask.log` on startup (appending a crash recovery banner if the previous session did not exit cleanly), records `AppLifecycleState` sleep/background transitions (`inactive`, `hidden`, `paused`, `resumed`) without clearing the file, truncates `tiertask.log` to `0` bytes on clean `detached` exit, and synchronously flushes `[CRASH]` stack traces via `FlutterError.onError` and `PlatformDispatcher.instance.onError` while locking the session against truncation.
