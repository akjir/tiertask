# TierTask Architecture and File Structure

> [!IMPORTANT]
> Update this file, [`AGENTS.md`](AGENTS.md), and [`TDF_SPEC.md`](TDF_SPEC.md) whenever the architecture, supported target platforms, directory layout, file responsibilities, localization files, or TDF synchronization flow change.

## Architectural Layers

| Layer | Path | Responsibility |
| :--- | :--- | :--- |
| Localization | `lib/l10n/` | External English (`app_en.arb`) and German (`app_de.arb`) resource bundles, generated `AppLocalizations` classes, and `TaskTier` localization mappings. |
| Models | `lib/models/` | Immutable domain data structures (`AppWorkspace`, `WorkspaceSummary`, `WorkspaceException`, `WorkspaceErrorKind`, `TaskTier`, `TaskItem`, `SubtaskItem`, `ConditionGroup`, `TaskCondition`, `TdfLabel`, `TdfColor`, `TaskBoard`, `AppLanguage`, `AppThemeMode`, `AppThemePalette`, `StorageMode`, `WebDavConfig`) and the dynamic $O(N)$ 6-tier derivation and mutation pipeline. |
| Services | `lib/services/` | Stateless single-pass $O(N)$ TDF lexical scanner, structural parser, and canonical `LF` serializer (`TdfService`, `TdfException`, `TdfErrorKind`). |
| Repositories | `lib/repositories/` | All external I/O: WebDAV HTTP `GET`/`PUT` (`dart:io` `HttpClient`), local `.tdf` file reads/writes (`dart:io` `File`), and encrypted workspace and settings persistence (`flutter_secure_storage`). |
| Providers | `lib/providers/` | Riverpod state management (`Provider`, `Notifier`, `AsyncNotifier`) coordinating single-active-workspace unload/load transitions, locale and theme resolution, domain mutations, and repository synchronization. |
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
│   │   ├── task_board.dart
│   │   ├── task_item.dart
│   │   ├── task_tier.dart
│   │   ├── tdf_metadata.dart
│   │   └── webdav_config.dart
│   ├── providers/
│   │   ├── task_providers.dart
│   │   └── workspace_providers.dart
│   ├── repositories/
│   │   ├── local_file_repository.dart
│   │   ├── settings_repository.dart
│   │   └── webdav_repository.dart
│   ├── services/
│   │   └── tdf_service.dart
│   └── ui/
│       ├── app_theme.dart
│       ├── edit_labels_screen.dart
│       ├── edit_task_screen.dart
│       ├── home_screen.dart
│       ├── settings_screen.dart
│       └── widgets/
│           ├── app_logo.dart
│           ├── quick_add_bar.dart
│           ├── task_editor_conditions_section.dart
│           ├── task_editor_sections.dart
│           └── tier_page_indicator.dart
└── test/
    ├── models/
    │   ├── app_workspace_test.dart
    │   ├── task_board_downgrade_test.dart
    │   ├── task_board_evaluation_test.dart
    │   ├── task_board_lifecycle_test.dart
    │   └── task_board_mutation_test.dart
    ├── repositories/
    │   └── storage_and_providers_test.dart
    ├── services/
    │   ├── tdf_service_bounds_test.dart
    │   └── tdf_service_parser_test.dart
    └── ui/
        ├── app_theme_test.dart
        ├── edit_labels_screen_test.dart
        ├── edit_task_screen_test.dart
        ├── home_screen_test.dart
        ├── settings_screen_test.dart
        ├── test_helpers.dart
        └── widgets/
            ├── app_logo_test.dart
            ├── quick_add_bar_test.dart
            ├── task_editor_conditions_test.dart
            └── tier_page_indicator_test.dart
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
| `lib/models/app_workspace.dart` | Defines immutable `AppWorkspace`, `WorkspaceSummary`, `WorkspaceErrorKind`, and `WorkspaceException` for isolated workspace configurations and `.tdf` files, defaulting to `Tasks` (`tasks.tdf`), deriving suggested lowercase `.tdf` filenames (`AppWorkspace.suggestFileName`), and enforcing unique workspace names and `.tdf` file paths. |
| `lib/models/task_tier.dart` | Defines the `TaskTier` enum for the 6 derived tiers (`1` `focus`, `2` `ready`, `3` `planned`, `4` `blocked`, `5` `someday`, `6` `completed`) and WIP soft limits. |
| `lib/models/tdf_metadata.dart` | Immutable `ConditionGroup` (`day`, `time`, `location`), `TaskCondition` (`DayTaskCondition`, `GlobalResetTaskCondition`, `GroupResetTaskCondition`, `LocationTaskCondition`, `TimeWindowTaskCondition`), `TdfLabel`, and `TdfColor` hex color utilities from `TDF_SPEC.md` Section 4. |
| `lib/models/task_item.dart` | Immutable `TaskItem` and `SubtaskItem` value classes with TDF `<id>`, `priority` flag, `created` / `queued` / `finished` / `suspended` timestamps (with optional `:SS` precision), `labels`, `blocked` dependencies, `conditions`, `subtasks auto-finish`, and strict ISO-8601 date/time helpers. |
| `lib/models/task_board.dart` | Immutable `TaskBoard` aggregate implementing the $O(N)$ dynamic 6-tier derivation pipeline (`TaskBoard.evaluate`), context-filtered evaluation (`TaskBoard.evaluateForContext`), group-level condition inheritance and overrides, auto-pull cascade, 30-day completed task pruning, `subtasks auto-finish` completion, label creation/renaming/deletion and open task counting (`openTaskCountForLabel`), and Section 6 mutations. |
| `lib/models/webdav_config.dart` | Defines `AppLanguage` (`system`, `english`, `german`), `AppThemeMode` (`system`, `light`, `dark`), `AppThemePalette` (`slate`, `navy`), `StorageMode` (`local`, `webdav`, `both`), and the immutable `WebDavConfig` model defaulting to `tasks.tdf` and `AppThemePalette.slate`. |

## Services

| File | Function |
| :--- | :--- |
| `lib/services/tdf_service.dart` | Single-pass $O(N)$ lexical scanner, structural parser, and canonical `LF` serializer (`TdfService`) enforcing all `TDF_SPEC.md` Section 7 resource bounds and Section 8 `TdfErrorKind` error conditions without regular expressions. |

## Repositories

| File | Function |
| :--- | :--- |
| `lib/repositories/local_file_repository.dart` | Native `dart:io` `File` repository reading (`loadTdf`) and writing (`saveTdf`) the local `.tdf` file (`localFilePath`) with path traversal validation and `maxFileBytes` bounds checking. |
| `lib/repositories/settings_repository.dart` | Abstract `SettingsRepository`, `SecureSettingsRepository` (`flutter_secure_storage`), and `InMemorySettingsRepository` for persisting workspaces (`Tasks` default and custom workspaces with unique names and `.tdf` file paths) and loading only the single active `AppWorkspace` and its `WebDavConfig` into memory. |
| `lib/repositories/webdav_repository.dart` | Native `dart:io` `HttpClient` WebDAV repository executing authenticated HTTP `GET` (`fetchTdf`) and `PUT` (`saveTdf`) operations with localized `WebDavException` error mapping. |

## State Providers

| File | Function |
| :--- | :--- |
| `lib/providers/task_providers.dart` | Riverpod providers and notifiers (`appLocaleProvider`, `appThemeModeProvider`, `appThemePaletteProvider`, `appThemeProvider`, `localFileRepositoryProvider`, `tdfServiceProvider`, `AppThemeNotifier`, `SyncStateNotifier`, `WebDavConfigNotifier`, `TaskNotifier`) orchestrating locale/theme/palette resolution, runtime theme replacement, board loading/unloading, mutations, and local/WebDAV `.tdf` persistence for the active workspace. |
| `lib/providers/workspace_providers.dart` | Defines `activeWorkspaceProvider` and `ActiveWorkspaceNotifier`, holding only the single active `AppWorkspace` in memory and orchestrating runtime workspace unload/load switching (`switchWorkspace`), creation (`createWorkspace`), renaming (`renameWorkspace`), deletion (`deleteWorkspace`), and active configuration updates (`updateActiveConfig`). |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/main.dart` | Application entry point wrapping `TierTaskApp` in a `ProviderScope` with Material 3 light/dark/system themes from `appThemeProvider` (`lib/ui/app_theme.dart`) and `AppLocalizations` delegates (`en` and `de`). |
| `lib/ui/app_theme.dart` | Single unified application theme definition (`AppTheme` and `AppThemeSet`) implementing `ThemeExtension<AppTheme>` and `toThemeData()` for both the default Chromium-inspired Material 3 `Slate` palette (`AppTheme.slateDark` / `AppTheme.dark`, `AppTheme.slateLight` / `AppTheme.light`, `AppThemeSet.slate`) and the `Navy` palette (`AppTheme.navyDark`, `AppTheme.navyLight`, `AppThemeSet.navy`), providing all semantic surface, accent, tonal container (`primaryContainer`, `onPrimaryContainer`, `secondaryContainer`, `onSecondaryContainer`), text, indicator, and logo gradient tokens consumed across the UI and replaceable at runtime via `appThemeProvider`. |
| `lib/ui/edit_labels_screen.dart` | Dedicated Google Keep style label management screen (`EditLabelsScreen`) opened from the navigation drawer's `Edit` button or `+ Create new label` entry, supporting new label creation, open task count badges (`Badge.count`) per label, inline label renaming, and label deletion. |
| `lib/ui/edit_task_screen.dart` | Dedicated panel screen (`EditTaskScreen` and `openEditTaskScreen`) grouped into `SettingsScreen`-style Material 3 section cards, used for both extended task creation (`QuickAddBar` `Advanced` button) and editing an existing task (`_TierTaskPill` edit button), enforcing non-empty and non-duplicate task names and editing notes, scheduling mode (`Priority`, `Someday`, and `Suspended` with optional timestamp and Material 3 date/time pickers), labels, subtasks (`auto-finish`), search-based multi-select prerequisite tasks (`blocked` with cycle prevention), and activation conditions (`condition any`, `day`, `time` with 24-hour time pickers, and `location` rules). |
| `lib/ui/home_screen.dart` | Primary landing page screen displaying a top navigation bar (`_LandingTopBar`) with the menu button on the left, the active label name centered in the middle when a label filter is selected (smoothly animating to the left next to the menu button with the inline search field expanding between the label name and the search/close button when search is opened), and the search toggle on the right; a unified layout across all 6 horizontal `PageView` tier panels (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) with the centered uppercase tier section heading, minimalist task pill cards (`_TierTaskPill` with a leading completion/restoration circle, a downward arrow downgrade button on `Focus`, `Ready`, and `Planned` tasks immediately to the left of a full-height 3px vertical gap matching the screen background, and a right-side edit button) or empty-state card (`_EmptyTierCard`); a bottom `TierPageIndicator`; floating action buttons (`_LandingFloatingButtons`) with a smaller conditional WebDAV sync button (`_FloatingSyncButton` in `WebDAV` / `Both` mode) right-aligned above the circular task-add button that both hide when the task-add button transforms into the inline bottom `QuickAddBar`; and a top-left navigation drawer (`_LandingDrawer`) featuring a Google Keep style `Labels` section (top `Edit` button, selectable label filter pills with open task count badges, and `+ Create new label` entry) alongside synchronization, TDF preview, and settings actions without tier navigation items. |
| `lib/ui/settings_screen.dart` | Configuration screen for display language (`System`, `English`, `Deutsch`), color theme (`System`, `Light`, `Dark`), Material 3 color palette (`Slate`, `Navy`), open task count visibility (`Off` by default, `On`), storage mode (`Local`, `WebDAV`, `Both`), local `.tdf` file name, WebDAV endpoint parameters, and synchronization testing. |
| `lib/ui/widgets/app_logo.dart` | Vector application logo widget (`AppLogo` and `_AppLogoPainter`) rendering the stacked tier bars and completion checkmark badge in the navigation drawer header. |
| `lib/ui/widgets/quick_add_bar.dart` | Inline bottom task creation bar (`QuickAddBar`) replacing the add button when opened, featuring a borderless title input field, mutually exclusive `Priority` and `Someday` icon buttons, a `Labels` icon button that expands a multi-select menu upward above the bar, an `Advanced` icon button opening `EditTaskScreen`, and a `Cancel` icon button, and automatically stacking the title input above the action buttons when the viewport width is at or below the Pixel 9 Pro width/aspect-ratio threshold. |
| `lib/ui/widgets/task_editor_conditions_section.dart` | Activation conditions card (`TaskEditorConditionsSection`) for `EditTaskScreen`, rendering global `condition any`, weekday (`day`), time window (`time` with 24-hour Material 3 time picker buttons), and GPS location (`location`) controls. |
| `lib/ui/widgets/task_editor_sections.dart` | Reusable `SettingsScreen`-style section card (`TaskEditorSectionCard`), form cards (`TaskEditorDetailsCard`, `TaskEditorSchedulingCard`, `TaskEditorContextSection`, `TaskEditorSubtasksSection`, `TaskEditorBlockedBySection`), date/time picker fields (`TaskEditorSuspendedField`), prerequisite name search, and action widgets (`TaskEditorTitleField`, `TaskEditorNoteField`, `TaskEditorModeRow`, `TaskEditorActionsRow`, `TaskEditorChip`) for `EditTaskScreen`. |
| `lib/ui/widgets/tier_page_indicator.dart` | Bottom tier indicator (`TierPageIndicator`) positioned above `QuickAddBar` when open, rendering dots for inactive tiers and an icon for the active tier (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) over a transparent background, a desktop mouse-over icon in an intermediate color and borderless label without wave animation, desktop Left/Right arrow key navigation, and an interactive wave effect on hold and drag that enlarges the two adjacent neighbor dots (`1.5x` in the intermediate color) and jumps directly to the selected tier pane upon release. |

## Execution & Synchronization Flow

1. **Startup, Workspace Loading & Locale Resolution:** `main.dart` initializes `ProviderScope`. `ActiveWorkspaceNotifier` loads only the single active `AppWorkspace` (`Tasks` / `tasks.tdf` by default) from `SettingsRepository`, `WebDavConfigNotifier` exposes its `WebDavConfig`, and `appLocaleProvider` / `appThemeModeProvider` resolve the active `Locale` and `AppThemeMode`. Switching workspaces at runtime via `ActiveWorkspaceNotifier.switchWorkspace` unloads the current `TaskBoard` and `SyncState` from memory and loads the selected `AppWorkspace` and its `.tdf` file without restarting the application.
2. **TDF Fetch (Local File or WebDAV):** `TaskNotifier` reads the raw `.tdf` document either from the configured local `.tdf` file (`LocalFileRepository.loadTdf`) or from the configured WebDAV endpoint via HTTP `GET` (`WebDavRepository.fetchTdf`). Missing files (`HTTP 404` or non-existent local file) initialize an empty board.
3. **Single-Pass Parse & Dynamic 6-Tier Derivation:** `TdfService.parse` validates the `tdf 0.2.0` header (while automatically migrating legacy `category` / `location` root blocks and `categories` / `locations` directives to unified `label` / `labels`), scans and validates all `label` and `task` blocks in a single $O(N)$ pass, and invokes `TaskBoard.evaluate` to derive `Completed`, `Someday`, `Blocked`, `Focus`, `Ready`, and `Planned` per `TDF_SPEC.md` Section 5.
4. **Mutation & Persistence:** Every user action (`addTask`, `updateTask`, `completeTask`, `restoreTask`, `downgradeTask`, `toggleSubtask`) produces a new immutable `TaskBoard`, updates UI state, serializes canonical `LF`-terminated `tdf 0.2.0` output via `TdfService.serialize`, and persists the `.tdf` document to the local filesystem and/or WebDAV server.
