# TierTask Architecture and File Structure

> [!IMPORTANT]
> Update this file, [`AGENTS.md`](AGENTS.md), and [`TDF_SPEC.md`](TDF_SPEC.md) whenever the architecture, supported target platforms, directory layout, file responsibilities, localization files, or TDF synchronization flow change.

## Architectural Layers

| Layer | Path | Responsibility |
| :--- | :--- | :--- |
| Localization | `lib/l10n/` | External English (`app_en.arb`) and German (`app_de.arb`) resource bundles, generated `AppLocalizations` classes, and `TaskTier` localization mappings. |
| Models | `lib/models/` | Immutable domain data structures (`AppWorkspace`, `WorkspaceSummary`, `WorkspaceException`, `WorkspaceErrorKind`, `LocationFix`, `LocationSource`, `LocationState`, `LocationStatus`, `TaskTier`, `TaskItem`, `SubtaskItem`, `RepeatUnit`, `TaskRepeatRule`, `ConditionGroup`, `TaskCondition`, `TdfLabel`, `TdfColor`, `TaskBoard`, `TaskBoardSync`, `WorkspaceSyncState`, `AppLanguage`, `AppThemeMode`, `AppThemePalette`, `AppTimeZoneMode`, `StorageMode`, `WebDavConfig`) and the dynamic $O(N)$ 6-tier derivation, mutation, and entity-level synchronization pipeline. |
| Services | `lib/services/` | Stateless single-pass $O(N)$ RFC 4648 Base64 codec (`Base64Service`, `Base64Exception`, `Base64ErrorKind`) and TDF lexical scanner, structural parser, and canonical `LF` serializer (`TdfService`, `TdfException`, `TdfErrorKind`). |
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
│   │   └── webdav_config.dart
│   ├── providers/
│   │   ├── location_providers.dart
│   │   ├── task_providers.dart
│   │   └── workspace_providers.dart
│   ├── repositories/
│   │   ├── local_file_repository.dart
│   │   ├── location_repository.dart
│   │   ├── settings_repository.dart
│   │   └── webdav_repository.dart
│   ├── services/
│   │   ├── base64_service.dart
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
│           ├── location_status_dialog.dart
│           ├── quick_add_bar.dart
│           ├── task_editor_conditions_section.dart
│           ├── task_editor_sections.dart
│           ├── tier_page_indicator.dart
│           ├── tier_task_pill.dart
│           └── workspace_dialog.dart
└── test/
    ├── models/
    │   ├── app_workspace_test.dart
    │   ├── location_state_test.dart
    │   ├── task_board_downgrade_test.dart
    │   ├── task_board_evaluation_test.dart
    │   ├── task_board_lifecycle_test.dart
    │   ├── task_board_mutation_test.dart
    │   └── task_board_sync_test.dart
    ├── repositories/
    │   ├── local_directory_migration_test.dart
    │   ├── location_repository_test.dart
    │   ├── storage_and_providers_test.dart
    │   └── sync_merge_test.dart
    ├── services/
    │   ├── base64_service_test.dart
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
| `lib/models/app_workspace.dart` | Defines immutable `AppWorkspace`, `WorkspaceSummary`, `WorkspaceErrorKind`, and `WorkspaceException` for isolated workspace configurations and `.tdf` files, defaulting to `Tasks` (`tasks.tdf`), deriving suggested lowercase `.tdf` filenames (`AppWorkspace.suggestFileName`), enforcing unique workspace names and `.tdf` file paths, and serializing workspaces and the active workspace index into a compact `TTW\x01` binary `Uint8List` format (`encodePersistedState`, `decodePersistedState`, `toBytes`, `fromBytes`) with bit-packed enum flags, `locationEnabled` bit, and 16-bit length-prefixed UTF-8 strings. |
| `lib/models/location_state.dart` | Defines immutable `LocationFix`, `LocationSource` (`gps`, `system`, `internet`), `LocationState`, and `LocationStatus` (`disabled`, `searching`, `found`, `unavailable`) for foreground location determination, including 5-decimal WGS-84 coordinate formatting (`formattedCoordinates`), 100-meter Haversine displacement gating (`isWithinDisplacementThreshold`), and 5-minute resume refresh cooldown evaluation (`shouldRefreshOnResume`). |
| `lib/models/task_tier.dart` | Defines the `TaskTier` enum for the 6 derived tiers (`1` `focus`, `2` `ready`, `3` `planned`, `4` `blocked`, `5` `someday`, `6` `completed`) and WIP soft limits. |
| `lib/models/tdf_metadata.dart` | Immutable `ConditionGroup` (`day`, `time`, `location`), `TaskCondition` (`DayTaskCondition`, `GlobalResetTaskCondition`, `GroupResetTaskCondition`, `LocationTaskCondition`, `TimeWindowTaskCondition`), `TdfLabel` (including `modifiedAt` and `effectiveModifiedAt`), `TdfColor` hex color utilities, and 10-character Base62 entity identifier generation, validation, and non-conforming ID conversion helpers (`tdfBase62Alphabet`, `tdfBase62TimeModulo`, `encodeTdfBase62Time`, `isValidTaskId`, `isValidLabelId`, `generateTaskId`, `generateLabelId`, `convertLegacyEntityId`) from `TDF_SPEC.md` Sections 2.9 and 4. |
| `lib/models/task_item.dart` | Immutable `TaskItem`, `SubtaskItem`, `RepeatUnit`, and `TaskRepeatRule` value classes with 10-character Base62 TDF `<task-id>` (`<6xBase62Random><4xBase62Time>`), `priority` flag, UTC `created` / `queued` / `finished` / `modified` timestamps (`modifiedAt`, `effectiveModifiedAt`, `nextModifiedTimestamp`), wall-clock `suspended` timestamp, completion-relative `repeat <count> <days\|weeks\|months>` rule, `labels`, `blocked` dependencies, `conditions`, `subtasks auto-finish`, subtask completion synchronization (`toCompleted`), and strict ISO-8601 date/time helpers. |
| `lib/models/task_board.dart` | Immutable `TaskBoard` aggregate implementing the $O(N)$ dynamic 6-tier derivation pipeline (`TaskBoard.evaluate` with UTC `evaluationTime` and local wall-clock `localEvaluationTime`), context-filtered evaluation (`TaskBoard.evaluateForContext`), group-level condition inheritance and overrides, auto-pull cascade, 30-day UTC completed task pruning, recurring task rescheduling into `Blocked` with `priority` and subtask reset (`repeat`), `subtasks auto-finish` completion, closing all subtasks on task completion, locking subtasks while a task is completed (`toggleSubtask`), and reopening all subtasks on task restoration, 10-character Base62 task and label creation (`generateTaskId`, `generateLabelId` with collision checks), label renaming/deletion and precomputed $O(1)$ open task counting (`openTaskCountsByLabel`, `openTaskCountForLabel`), and Section 6 mutations with monotonic `modifiedAt` stamping. |
| `lib/models/task_board_sync.dart` | Stateless per-entity synchronization engine (`TaskBoardSync.merge`, `TaskBoardSync.stampAndNormalize`) and persisted sync baseline state (`WorkspaceSyncState` with `TTS\x01` binary serialization) implementing `TDF_SPEC.md` Sections 2.9 and 6.7 entity-level Last-Write-Wins comparison (`modified`) with immutable 10-character Base62 sync identities, baseline-aware external task deletion, handwritten label preservation, and label deletion timestamp reconciliation. |
| `lib/models/webdav_config.dart` | Defines `AppLanguage` (`system`, `english`, `german`), `AppThemeMode` (`system`, `light`, `dark`), `AppThemePalette` (`slate`, `navy`), `AppTimeZoneMode` (`automatic`, `manual`), `StorageMode` (`local`, `webdav`, `both`) with compact binary IDs (`id` / `fromId`), and the immutable `WebDavConfig` model defaulting to `tasks.tdf`, `AppThemePalette.slate`, `AppTimeZoneMode.automatic`, and UTC/local wall-clock conversion helpers (`toLocalWallClock`, `localWallClockToUtc`). |

## Services

| File | Function |
| :--- | :--- |
| `lib/services/base64_service.dart` | Single-pass $O(N)$ RFC 4648 Base64 encoder and decoder (`Base64Service`, `Base64Exception`, `Base64ErrorKind`) with pre-allocated `Uint8List` buffers, strict input byte bounds (`maxInputBytes`), alphabet validation, padding verification, and non-zero padding-bit rejection (RFC 4648 Section 3.5). |
| `lib/services/tdf_service.dart` | Single-pass $O(N)$ lexical scanner, structural parser, and canonical `LF` `tdf 0.4.0` serializer (`TdfService`) normalizing any non-conforming `<task-id>` and `<label-id>` entity identifiers across `tdf 0.4.0`, `0.3.0`, and `0.2.0` documents into 10-character Base62 IDs (`<6xBase62Random><4xBase62Time>`), rewriting all intra-document `labels` and `blocked` references on parse, and enforcing all `TDF_SPEC.md` Section 7 resource bounds and Section 8 `TdfErrorKind` error conditions without regular expressions. |

## Repositories

| File | Function |
| :--- | :--- |
| `lib/repositories/local_file_repository.dart` | Native `dart:io` `File` repository reading (`loadTdf`), writing (`saveTdf`), and safely migrating (`moveTdfFile`) the local `.tdf` file (`localFilePath`) with path traversal validation, `maxFileBytes` bounds checking, non-destructive target conflict inspection (rejecting existing files, directories, or symbolic links), Linux/Windows OS error mapping, and native desktop directory selection (`pickDirectory` via `de.akjir.tiertask/directory_picker`). |
| `lib/repositories/location_repository.dart` | Abstract `LocationRepository`, `PlatformLocationRepository`, and `FakeLocationRepository` isolating native `de.akjir.tiertask/location` `MethodChannel` queries (Android foreground `LocationManager` cache-first lookup with 5-minute freshness and `Geocoder`, Linux `GeoClue2` D-Bus client, and Windows `ILocation` `IID_ILatLongReport`), 100-meter Haversine displacement-gated HTTPS reverse geocoding, and 30-minute cached HTTPS GeoIP desktop fallback. |
| `lib/repositories/settings_repository.dart` | Abstract `SettingsRepository`, `SecureSettingsRepository` (`flutter_secure_storage`), and `InMemorySettingsRepository` for persisting workspaces and the active workspace in a single atomic Base64-encoded `TTW\x01` binary key (`t2_settings_v1`), loading lightweight `WorkspaceSummary` items (`loadWorkspaceSummaries`), and persisting per-workspace sync baselines (`WorkspaceSyncState` in `t2_sync_v1_<id>`) via `Base64Service`. |
| `lib/repositories/webdav_repository.dart` | Native `dart:io` `HttpClient` WebDAV repository executing authenticated HTTP `GET` (`fetchTdf`) and `PUT` (`saveTdf`) operations with localized `WebDavException` error mapping. |

## State Providers

| File | Function |
| :--- | :--- |
| `lib/providers/location_providers.dart` | Defines `locationEnabledProvider`, `locationRepositoryProvider`, `locationStateProvider`, and `LocationNotifier` managing foreground-only location determination with startup/enable triggers, 5-minute app-resume cooldown (`minResumeRefreshInterval`), 15-minute passive foreground refresh (`passiveRefreshInterval`), immediate timer cancellation on app pause/hide/detach, and manual refresh (`refreshLocation`). |
| `lib/providers/task_providers.dart` | Riverpod providers and notifiers (`appLocaleProvider`, `appThemeModeProvider`, `appThemePaletteProvider`, `appThemeProvider`, `directoryPickerProvider`, `localFileRepositoryProvider`, `supportsDirectoryPickerProvider`, `tdfServiceProvider`, `AppThemeNotifier`, `SyncStateNotifier`, `WebDavConfigNotifier`, `TaskNotifier`) orchestrating locale/theme/palette/location preference updates, runtime theme replacement, atomic local `.tdf` directory migration (`changeLocalFileLocation`), lossless pre-unload flushing (`prepareForWorkspaceUnload`), board loading/unloading, mutations, and local/WebDAV `.tdf` persistence for the active workspace. |
| `lib/providers/workspace_providers.dart` | Defines `activeWorkspaceProvider`, `workspaceSummariesProvider`, `workspaceUnloadCoordinatorProvider` (`WorkspaceUnloadCoordinator`), and `ActiveWorkspaceNotifier`, holding only the single active `AppWorkspace` in memory and orchestrating lossless runtime workspace unload/load switching (`switchWorkspace`), creation (`createWorkspace`), renaming (`renameWorkspace`), deletion (`deleteWorkspace`), and active configuration updates (`updateActiveConfig`). |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/main.dart` | Application entry point wrapping `TierTaskApp` in a `ProviderScope` with Material 3 light/dark/system themes from `appThemeProvider` (`lib/ui/app_theme.dart`) and `AppLocalizations` delegates (`en` and `de`). |
| `lib/ui/app_theme.dart` | Single unified application theme definition (`AppTheme` and `AppThemeSet`) implementing `ThemeExtension<AppTheme>` and `toThemeData()` for both the default Chromium-inspired Material 3 `Slate` palette (`AppTheme.slateDark` / `AppTheme.dark`, `AppTheme.slateLight` / `AppTheme.light`, `AppThemeSet.slate`) and the `Navy` palette (`AppTheme.navyDark`, `AppTheme.navyLight`, `AppThemeSet.navy`), providing all semantic surface, accent, tonal container (`primaryContainer`, `onPrimaryContainer`, `secondaryContainer`, `onSecondaryContainer`), text, indicator, and logo gradient tokens consumed across the UI and replaceable at runtime via `appThemeProvider`. |
| `lib/ui/edit_labels_screen.dart` | Dedicated Google Keep style label management screen (`EditLabelsScreen`) opened from the navigation drawer's `Edit` button or `+ Create new label` entry, supporting new label creation, open task count badges (`Badge.count`) per label, inline label renaming, and label deletion. |
| `lib/ui/edit_task_screen.dart` | Dedicated panel screen (`EditTaskScreen` and `openEditTaskScreen`) grouped into `SettingsScreen`-style Material 3 section cards, used for both extended task creation (`QuickAddBar` `Advanced` button) and editing an existing task (`TierTaskPill` edit button), enforcing non-empty and non-duplicate task names and editing notes, scheduling mode (`Priority`, `Someday`, `Suspended` with optional timestamp and Material 3 date/time pickers, and `Repeat` with interval count and `days`/`weeks`/`months` unit selection), labels, subtasks (`auto-finish`, locking completed subtasks against toggling when editing a completed task while allowing subtask deletion and immediately locking newly added subtasks as completed), search-based multi-select prerequisite tasks (`blocked` with cycle prevention), and activation conditions (`condition any`, `day`, `time` with 24-hour time pickers, and `location` rules). |
| `lib/ui/home_screen.dart` | Primary landing page screen displaying a top navigation bar (`_LandingTopBar`) with the menu button on the left, the active label name centered in the middle when a label filter is selected (smoothly animating to the left next to the menu button with the inline search field expanding between the label name and the search/close button when search is opened), the search toggle on the right, and the conditional location status icon (`TopBarLocationButton`) immediately to the right of the search icon when `locationEnabled` is `true`; a unified layout across all 6 horizontal `PageView` tier panels (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) dynamically evaluated with live foreground GPS coordinates (`board.evaluateForContext`), with the centered uppercase tier section heading, an all-tasks search view (`_AllTasksSearchView` displaying `ALL TASKS` / `ALLE AUFGABEN` and listing all tasks across `Focus` through `Completed` in tier order filtered by the active label and search query before returning to the previous tier pane when search closes), minimalist task pill cards (`TierTaskPill`) or empty-state card (`_EmptyTierCard`); a bottom `TierPageIndicator`; floating action buttons (`_LandingFloatingButtons`) with a smaller conditional WebDAV sync button (`_FloatingSyncButton` in `WebDAV` / `Both` mode) right-aligned above the circular task-add button that both hide when the task-add button transforms into the inline bottom `QuickAddBar`; and a top-left navigation drawer (`_LandingDrawer`) featuring the active workspace switcher card (`DrawerWorkspaceCard` between `Divider`s beneath `_DrawerHeader`), a Google Keep style `Labels` section (top `Edit` button, selectable label filter pills with open task count badges, and `+ Create new label` entry) alongside synchronization, TDF preview, and settings actions without tier navigation items. |
| `lib/ui/settings_screen.dart` | Configuration screen for display language (`System`, `English`, `Deutsch`), color theme (`System`, `Light`, `Dark`), Material 3 color palette (`Slate`, `Navy`), local time zone (`Automatic` or `Manual` UTC offset), foreground location determination (`Off` / `On`, default `Off`), storage mode (`Local`, `WebDAV`, `Both`), local `.tdf` file name and desktop directory selection (`Change Directory` on Linux and Windows), and WebDAV endpoint parameters, with a fixed bottom action footer (`Save` and `Test Connection / Sync Now` matching `EditTaskScreen`) and a floating status/error banner (`_SettingsStatusBanner`) positioned directly above the footer. |
| `lib/ui/widgets/app_logo.dart` | Vector application logo widget (`AppLogo` and `_AppLogoPainter`) rendering the stacked tier bars and completion checkmark badge in the navigation drawer header. |
| `lib/ui/widgets/clearable_text_field.dart` | Reusable text input widget (`ClearableTextField`) wrapping `TextField` or `TextFormField` that displays a right-side clear icon button (`Icons.close_rounded`) when focused, composes with any existing `InputDecoration.suffixIcon`, clears the `TextEditingController`, notifies `onChanged` and `onCleared`, and keeps focus on the input. |
| `lib/ui/widgets/location_status_dialog.dart` | Header location status icon button (`TopBarLocationButton` rendering `searching`, `found`, and `unavailable` states) and popup status dialog (`LocationStatusDialog` and `showLocationStatusDialog`) displaying the current location status, determined place name, GPS coordinates, location source (`GPS`, `System / Network`, `Internet (GeoIP)`), and a `Refresh` button. |
| `lib/ui/widgets/quick_add_bar.dart` | Inline bottom task creation bar (`QuickAddBar`) replacing the add button when opened, featuring a borderless title input field, mutually exclusive `Priority` and `Someday` icon buttons, a `Labels` icon button that expands a multi-select floating overlay menu (`OverlayPortal` and `CompositedTransformFollower`) upward above the bar without shifting `TierPageIndicator`, an `Advanced` icon button opening `EditTaskScreen`, and a `Cancel` icon button, and automatically stacking the title input above the action buttons when the viewport width is at or below the Pixel 9 Pro width/aspect-ratio threshold. |
| `lib/ui/widgets/task_editor_conditions_section.dart` | Activation conditions card (`TaskEditorConditionsSection`) for `EditTaskScreen`, rendering global `condition any`, weekday (`day`), time window (`time` with 24-hour Material 3 time picker buttons), and GPS location (`location`) controls. |
| `lib/ui/widgets/task_editor_sections.dart` | Reusable `SettingsScreen`-style section card (`TaskEditorSectionCard`), form cards (`TaskEditorDetailsCard`, `TaskEditorSchedulingCard`, `TaskEditorContextSection`, `TaskEditorSubtasksSection`, `TaskEditorBlockedBySection`), date/time and recurrence fields (`TaskEditorSuspendedField`, `TaskEditorRepeatField`), prerequisite name search, and action widgets (`TaskEditorTitleField`, `TaskEditorNoteField`, `TaskEditorModeRow`, `TaskEditorActionsRow`, `TaskEditorChip`) for `EditTaskScreen`. |
| `lib/ui/widgets/tier_page_indicator.dart` | Bottom tier indicator (`TierPageIndicator`) positioned above `QuickAddBar` when open, rendering dots for inactive tiers and an icon for the active tier (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) over a transparent background, a desktop mouse-over icon in an intermediate color and borderless label without wave animation, desktop Left/Right arrow key navigation, and an interactive wave effect on hold and drag that enlarges the two adjacent neighbor dots (`1.5x` in the intermediate color) and jumps directly to the selected tier pane upon release. |
| `lib/ui/widgets/tier_task_pill.dart` | Task pill card widget (`TierTaskPill`) rendered across all 6 tier panes and the all-tasks search view, featuring a leading Material 3 `primaryContainer` completion square, passive right-side status indicator icons (`_TierTaskIndicators` and `_TierTaskIndicatorIcon` for `priority`, `repeat`, and `subtasks` with localized hover tooltips, rendered smaller and darker than the interactive action buttons and distinguishing standard subtasks via `Icons.checklist_rounded` from `subtasks auto-finish` via `Icons.fact_check_outlined`), right-chevron `>` downgrade and three-dots `⋮` edit buttons, an animated downward-gliding subtask drawer (`_AnimatedSubtasksSection` and `_TierSubtaskStepRow`) toggled by clicking the task body to check or uncheck individual subtasks on open tasks while keeping completed subtasks locked on completed tasks, and two-stage closing, rightward downgrade, leftward restore, and auto-pull upgrade entry animations (`_AnimatedTaskTransitionWrapper`) that collapse any open subtask subgroup first before animating the task pill out and smoothly sliding lower tasks upward. |
| `lib/ui/widgets/workspace_dialog.dart` | Active workspace navigation drawer card (`DrawerWorkspaceCard`) and Material 3 workspace management dialog (`WorkspaceDialog` and `showWorkspaceDialog`) supporting workspace switching, workspace creation with a live `.tdf` filename suggestion preview (`AppWorkspace.suggestFileName`), inline workspace renaming, and confirmed workspace deletion. |

## Execution & Synchronization Flow

1. **Startup, Workspace Loading & Locale Resolution:** `main.dart` initializes `ProviderScope`. `ActiveWorkspaceNotifier` loads only the single active `AppWorkspace` (`Tasks` / `tasks.tdf` by default) from `SettingsRepository`, `WebDavConfigNotifier` exposes its `WebDavConfig`, and `appLocaleProvider` / `appThemeModeProvider` resolve the active `Locale` and `AppThemeMode`. Switching workspaces at runtime via `ActiveWorkspaceNotifier.switchWorkspace` unloads the current `TaskBoard` and `SyncState` from memory and loads the selected `AppWorkspace` and its `.tdf` file without restarting the application.
2. **Two-Stage TDF Fetch & Entity-Level Merge (`In-Memory <-> Local File <-> WebDAV`):** On startup, on every manual sync (`syncFromRemote`, `testConnectionAndSync`), and on every saved mutation (`addTask`, `updateTask`, `completeTask`, `restoreTask`, `downgradeTask`, `toggleSubtask`, `addLabel`, `renameLabel`, `deleteLabel`), `TaskNotifier` runs the two-stage merge pipeline (`_synchronizePipeline`): Stage 1 reads the local `.tdf` file (`LocalFileRepository.loadTdf`), immediately converts any legacy `tdf 0.2.0` or `0.3.0` identifiers to 13-character Base62 IDs, merges external local file changes with the in-memory `TaskBoard` per `task` and `label` entity via `TaskBoardSync.merge`, and writes the converged `tdf 0.4.0` document back to the local file; Stage 2 fetches the remote `.tdf` file (`WebDavRepository.fetchTdf`), merges concurrent remote changes per entity via `TaskBoardSync.merge`, writes the converged `tdf 0.4.0` document to WebDAV, and updates the local `.tdf` file and `WorkspaceSyncState` baselines so both storage backends converge to identical `tdf 0.4.0` documents.
3. **Single-Pass Parse & Dynamic 6-Tier Derivation:** `TdfService.parse` validates the `tdf 0.4.0` (or legacy `0.3.0` / `0.2.0`) header, scans and validates all `label` and `task` blocks in a single $O(N)$ pass (enforcing 13-character Base62 IDs on `0.4.0` documents or converting legacy IDs and rewriting `labels` and `blocked` references on older documents, and interpreting `created`, `queued`, `finished`, and `modified` in UTC while evaluating `condition day`, `condition time`, and `suspended` against the user's configured local wall-clock time), and invokes `TaskBoard.evaluate` to derive `Completed`, `Someday`, `Blocked`, `Focus`, `Ready`, and `Planned` per `TDF_SPEC.md` Section 5.
4. **Mutation & Persistence:** Every user action advances the mutated entity's UTC `modified` timestamp monotonically (`TaskItem.nextModifiedTimestamp`), triggers the two-stage synchronization pipeline, serializes canonical `LF`-terminated `tdf 0.4.0` output via `TdfService.serialize`, and persists the converged `.tdf` document and sync baselines across the configured local and WebDAV targets.
