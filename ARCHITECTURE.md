# TierTask Architecture and File Structure

> [!IMPORTANT]
> Update this file, [`AGENTS.md`](AGENTS.md), and [`TDF_SPEC.md`](TDF_SPEC.md) whenever the architecture, supported target platforms, directory layout, file responsibilities, localization files, or TDF synchronization flow change.

## Architectural Layers

| Layer | Path | Responsibility |
| :--- | :--- | :--- |
| Localization | `lib/l10n/` | External English (`app_en.arb`) and German (`app_de.arb`) resource bundles, generated `AppLocalizations` classes, and `TaskTier` localization mappings. |
| Models | `lib/models/` | Immutable domain data structures (`TaskTier`, `TaskItem`, `SubtaskItem`, `TaskCondition`, `TdfCategory`, `TdfLocation`, `TaskBoard`, `AppLanguage`, `AppThemeMode`, `StorageMode`, `WebDavConfig`) and the dynamic $O(N)$ 6-tier derivation and mutation pipeline. |
| Services | `lib/services/` | Stateless single-pass $O(N)$ TDF lexical scanner, structural parser, and canonical `LF` serializer (`TdfService`, `TdfException`, `TdfErrorKind`). |
| Repositories | `lib/repositories/` | All external I/O: WebDAV HTTP `GET`/`PUT` (`dart:io` `HttpClient`), local `.tdf` file reads/writes (`dart:io` `File`), and encrypted settings persistence (`flutter_secure_storage`). |
| Providers | `lib/providers/` | Riverpod state management (`Provider`, `Notifier`, `AsyncNotifier`) coordinating locale and theme resolution, domain mutations, and repository synchronization. |
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
│   │   ├── task_board.dart
│   │   ├── task_item.dart
│   │   ├── task_tier.dart
│   │   ├── tdf_metadata.dart
│   │   └── webdav_config.dart
│   ├── providers/
│   │   └── task_providers.dart
│   ├── repositories/
│   │   ├── local_file_repository.dart
│   │   ├── settings_repository.dart
│   │   └── webdav_repository.dart
│   ├── services/
│   │   └── tdf_service.dart
│   └── ui/
│       ├── category_screen.dart
│       ├── home_screen.dart
│       ├── settings_screen.dart
│       └── widgets/
│           ├── color_wheel_picker.dart
│           ├── context_management_sheet.dart
│           ├── quick_add_bar.dart
│           ├── restore_task_sheet.dart
│           └── task_tile.dart
└── test/
    ├── tiertask_domain_test.dart
    └── widget_test.dart
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
| `lib/l10n/app_en.arb` | External English (`en`, default fallback) translation bundle for all UI labels, tier headings/descriptions, and error messages. |
| `lib/l10n/app_de.arb` | External German (`de`) translation bundle for all UI labels, tier headings/descriptions, and error messages. |
| `lib/l10n/tier_localization_extension.dart` | Extension on `AppLocalizations` mapping `TaskTier` (`1`–`6`) to localized tier names, descriptions, and empty-state hints. |

## Domain Models

| File | Function |
| :--- | :--- |
| `lib/models/task_tier.dart` | Defines the `TaskTier` enum for the 6 derived tiers (`1` `focus`, `2` `ready`, `3` `planned`, `4` `blocked`, `5` `someday`, `6` `completed`) and WIP soft limits. |
| `lib/models/tdf_metadata.dart` | Immutable `TaskCondition` (`DayTaskCondition`, `TimeWindowTaskCondition`), `TdfCategory`, `TdfLocation`, and `TdfColor` hex color utilities from `TDF_SPEC.md` Section 4. |
| `lib/models/task_item.dart` | Immutable `TaskItem` and `SubtaskItem` value classes with TDF `<id>`, `priority` flag, `created` / `queued` / `finished` / `suspended` timestamps, `locations`, `categories`, `blocked` dependencies, `conditions`, `subtasks auto-finish`, and strict ISO-8601 date/time helpers. |
| `lib/models/task_board.dart` | Immutable `TaskBoard` aggregate implementing the $O(N)$ dynamic 6-tier derivation pipeline (`TaskBoard.evaluate`), context-filtered evaluation (`TaskBoard.evaluateForContext`), auto-pull cascade, 30-day completed task pruning, `subtasks auto-finish` completion, category and location creation/deletion, and Section 6 mutations. |
| `lib/models/webdav_config.dart` | Defines `AppLanguage` (`system`, `english`, `german`), `AppThemeMode` (`system`, `light`, `dark`), `StorageMode` (`local`, `webdav`, `both`), and the immutable `WebDavConfig` model defaulting to `tiertask.tdf`. |

## Services

| File | Function |
| :--- | :--- |
| `lib/services/tdf_service.dart` | Single-pass $O(N)$ lexical scanner, structural parser, and canonical `LF` serializer (`TdfService`) enforcing all `TDF_SPEC.md` Section 7 resource bounds and Section 8 `TdfErrorKind` error conditions without regular expressions. |

## Repositories

| File | Function |
| :--- | :--- |
| `lib/repositories/local_file_repository.dart` | Native `dart:io` `File` repository reading (`loadTdf`) and writing (`saveTdf`) the local `.tdf` file (`localFilePath`) with path traversal validation and `maxFileBytes` bounds checking. |
| `lib/repositories/settings_repository.dart` | Abstract `SettingsRepository`, `SecureSettingsRepository` (`flutter_secure_storage`), and `InMemorySettingsRepository` for persisting `StorageMode`, local and remote `.tdf` file paths, WebDAV credentials, `AppLanguage`, and `AppThemeMode`. |
| `lib/repositories/webdav_repository.dart` | Native `dart:io` `HttpClient` WebDAV repository executing authenticated HTTP `GET` (`fetchTdf`) and `PUT` (`saveTdf`) operations with localized `WebDavException` error mapping. |

## State Providers

| File | Function |
| :--- | :--- |
| `lib/providers/task_providers.dart` | Riverpod providers and notifiers (`appLocaleProvider`, `appThemeModeProvider`, `localFileRepositoryProvider`, `tdfServiceProvider`, `SyncStateNotifier`, `WebDavConfigNotifier`, `TaskNotifier`) orchestrating locale/theme resolution, board loading, mutations, and local/WebDAV `.tdf` persistence. |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/main.dart` | Application entry point wrapping `TierTaskApp` in a `ProviderScope` with Material 3 light/dark/system themes and `AppLocalizations` delegates (`en` and `de`). |
| `lib/ui/category_screen.dart` | Category task view (`CategoryScreen`) opened by tapping a category card on `HomeScreen`, displaying the 3 derived `Focus` tasks filtered to that category while preserving all active blocking, condition, scheduling, and search filters, with a circular task-add button that transforms into `QuickAddBar` when pressed. |
| `lib/ui/home_screen.dart` | Primary landing page screen displaying the greeting, minimalist `Focus` task pills, dynamic `Categories` and `Locations` summary carousels (hidden when no categories or locations exist in the `.tdf` board) with solid colored accent bars, optional open task counts, and category navigation to `CategoryScreen`, top-right search and conditional WebDAV sync (`WebDAV` / `Both` mode), a circular task-add button that hides and transforms into the inline bottom `QuickAddBar` when pressed, and a top-left navigation drawer for secondary tiers, `Categories` and `Locations` management panels, synchronization, TDF preview, and settings. |
| `lib/ui/settings_screen.dart` | Configuration screen for display language (`System`, `English`, `Deutsch`), color theme (`System`, `Light`, `Dark`), open task count visibility (`Off` by default, `On`), storage mode (`Local`, `WebDAV`, `Both`), local `.tdf` file name, WebDAV endpoint parameters, and synchronization testing. |
| `lib/ui/widgets/color_wheel_picker.dart` | Interactive HSV color wheel widget (`ColorWheelPicker`) rendered via a dependency-free `CustomPainter` for selecting category and location accent colors. |
| `lib/ui/widgets/context_management_sheet.dart` | Modal panel (`ContextManagementSheet`) opened from the navigation drawer to create, view, and delete `Categories` or `Locations` with color selection via `ColorWheelPicker` or direct `#RRGGBB` hex input. |
| `lib/ui/widgets/quick_add_bar.dart` | Inline bottom task creation bar (`QuickAddBar`) replacing the add button when opened, featuring a borderless title input field, mutually exclusive `Priority` and `Someday` icon buttons, `Categories` and `Locations` icon buttons that expand multi-select menus upward above the bar, a placeholder `Advanced` icon button, and a `Cancel` icon button. |
| `lib/ui/widgets/restore_task_sheet.dart` | Modal bottom sheet for selecting the destination active tier (`1` through `5`) when restoring or moving a task. |
| `lib/ui/widgets/task_tile.dart` | Individual task card providing completion, downgrade, quick-block, title editing, move, and delete actions. |

## Execution & Synchronization Flow

1. **Startup, Configuration & Locale Resolution:** `main.dart` initializes `ProviderScope`. `WebDavConfigNotifier` loads persisted `StorageMode`, `.tdf` paths, WebDAV credentials, and `AppLanguage` settings via `SettingsRepository`. `appLocaleProvider` resolves the active `Locale`.
2. **TDF Fetch (Local File or WebDAV):** `TaskNotifier` reads the raw `.tdf` document either from the configured local `.tdf` file (`LocalFileRepository.loadTdf`) or from the configured WebDAV endpoint via HTTP `GET` (`WebDavRepository.fetchTdf`). Missing files (`HTTP 404` or non-existent local file) initialize an empty board.
3. **Single-Pass Parse & Dynamic 6-Tier Derivation:** `TdfService.parse` scans and validates all `location`, `category`, and `task` blocks in a single $O(N)$ pass and invokes `TaskBoard.evaluate` to derive `Completed`, `Someday`, `Blocked`, `Focus`, `Ready`, and `Planned` per `TDF_SPEC.md` Section 5.
4. **Mutation & Persistence:** Every user action (`addTask`, `completeTask`, `toggleSubtask`, `restoreTask`, `downgradeTask`, `blockTask`, `moveTask`, `editTaskTitle`, `deleteTask`) produces a new immutable `TaskBoard`, updates UI state, serializes canonical `LF`-terminated `.tdf` output via `TdfService.serialize`, and persists the `.tdf` document to the local filesystem and/or WebDAV server.
