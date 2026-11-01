# TierTask Architecture and File Structure

> [!IMPORTANT]
> Update this file and [`AGENTS.md`](AGENTS.md) whenever the architecture, supported target platforms, directory layout, file responsibilities, localization files, or Markdown synchronization flow change.

## Architectural Layers

| Layer | Path | Responsibility |
| :--- | :--- | :--- |
| Localization | `lib/l10n/` | External English (`app_en.arb`) and German (`app_de.arb`) resource bundles, generated `AppLocalizations` classes, and `TaskTier` localization mappings. |
| Models | `lib/models/` | Immutable domain data structures (`TaskTier`, `TaskItem`, `TaskBoard`, `AppLanguage`, `AppThemeMode`, `StorageMode`, `WebDavConfig`) and deterministic pull/pruning business rules. |
| Services | `lib/services/` | Stateless single-pass Markdown parsing and serialization (`MarkdownService`) matching numbered tiers `[1]`–`[6]`. |
| Repositories | `lib/repositories/` | All external I/O: WebDAV HTTP `GET`/`PUT` (`dart:io` `HttpClient`), local Markdown file reads/writes (`dart:io` `File`), and encrypted settings persistence (`flutter_secure_storage`). |
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
│   │   └── webdav_config.dart
│   ├── providers/
│   │   └── task_providers.dart
│   ├── repositories/
│   │   ├── local_file_repository.dart
│   │   ├── settings_repository.dart
│   │   └── webdav_repository.dart
│   ├── services/
│   │   └── markdown_service.dart
│   └── ui/
│       ├── home_screen.dart
│       ├── settings_screen.dart
│       └── widgets/
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
| `ARCHITECTURE.md` | Architectural layer definitions, directory structure, file inventory, and synchronization flow. |
| `CHANGELOG.md` | User-facing change history following Keep a Changelog 1.1.0. |
| `README.md` | Project overview, supported platforms (Linux, Android, Windows), build instructions, and numbered Markdown tier reference. |
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
| `lib/models/task_tier.dart` | Defines the `TaskTier` enum for the 6 numbered tiers (`1` `focus`, `2` `ready`, `3` `planned`, `4` `blocked`, `5` `someday`, `6` `completed`), soft limits, `# [n]` formatting, and label-independent tier-number parsing. |
| `lib/models/task_item.dart` | Immutable `TaskItem` and `SubtaskItem` value classes with priority flag, ordered subtasks, completion state, UTC `YYYY-MM-DD` date normalization, and Markdown line serialization. |
| `lib/models/task_board.dart` | Immutable `TaskBoard` aggregate enforcing the auto-pull cascade (`Tier 3 -> Tier 2 -> Tier 1`), 30-day completed task pruning in Tier `6`, and anti-ping-pong downgrades. |
| `lib/models/webdav_config.dart` | Defines `AppLanguage` (`system`, `english`, `german`), `AppThemeMode` (`system`, `light`, `dark`), `StorageMode` (`local`, `webdav`, `both`), and the immutable `WebDavConfig` model (including `showOpenTaskCount`, defaulting to `false`). |

## Services

| File | Function |
| :--- | :--- |
| `lib/services/markdown_service.dart` | Dependency-free parser and serializer converting between raw Markdown text and `TaskBoard` instances by matching tier numbers `[1]`–`[6]` and creating missing tiers automatically. |

## Repositories

| File | Function |
| :--- | :--- |
| `lib/repositories/local_file_repository.dart` | Native `dart:io` `File` repository reading and writing the local Markdown file (`localFilePath`) with path traversal validation and `maxFileBytes` bounds checking. |
| `lib/repositories/settings_repository.dart` | Abstract `SettingsRepository`, `SecureSettingsRepository` (`flutter_secure_storage`), and `InMemorySettingsRepository` for persisting `StorageMode`, local and remote file paths, WebDAV credentials, `AppLanguage`, and `AppThemeMode`. |
| `lib/repositories/webdav_repository.dart` | Native `dart:io` `HttpClient` WebDAV repository executing authenticated HTTP `GET` and `PUT` operations with localized `WebDavException` error mapping. |

## State Providers

| File | Function |
| :--- | :--- |
| `lib/providers/task_providers.dart` | Riverpod providers and notifiers (`appLocaleProvider`, `appThemeModeProvider`, `localFileRepositoryProvider`, `SyncStateNotifier`, `WebDavConfigNotifier`, `TaskNotifier`) orchestrating locale/theme resolution, board loading, mutations, and local/WebDAV Markdown persistence. |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/main.dart` | Application entry point wrapping `TierTaskApp` in a `ProviderScope` with Material 3 light/dark/system themes and `AppLocalizations` delegates (`en` and `de`). |
| `lib/ui/home_screen.dart` | Primary landing page screen displaying the greeting, minimalist `Focus` task pills, horizontal `Categories` and `Locations` summary cards with solid colored accent bars and optional open task counts, top-right search and conditional WebDAV sync (`WebDAV` / `Both` mode), and a top-left navigation drawer for secondary tiers (`Ready`, `Planned`, `Blocked`, `Someday`, `Completed`), synchronization, Markdown preview, and settings. |
| `lib/ui/settings_screen.dart` | Configuration screen for display language (`System`, `English`, `Deutsch`), color theme (`System`, `Light`, `Dark`), open task count visibility (`Off` by default, `On`), storage mode (`Local`, `WebDAV`, `Both`), local file name, WebDAV endpoint parameters, and synchronization testing. |
| `lib/ui/widgets/quick_add_bar.dart` | Task creation bar (`QuickAddBar`) with a title input field, mutually exclusive `Priority` and `Someday` toggle buttons, an `Advanced` button opening the extended subtask editor view, and an `Add` button enabled only when input text is present. |
| `lib/ui/widgets/restore_task_sheet.dart` | Modal bottom sheet for selecting the destination active tier (`1` through `5`) when restoring or moving a task. |
| `lib/ui/widgets/task_tile.dart` | Individual task card providing completion, downgrade, quick-block, title editing, move, and delete actions. |

## Execution & Synchronization Flow

1. **Startup, Configuration & Locale Resolution:** `main.dart` initializes `ProviderScope`. `WebDavConfigNotifier` loads persisted WebDAV and `AppLanguage` settings via `SettingsRepository`. `appLocaleProvider` resolves the active `Locale` (`de` when `AppLanguage.german` is selected or when `AppLanguage.system` runs on a German OS locale; `en` default otherwise).
2. **Markdown Fetch (Local File or WebDAV):** If configured, `TaskNotifier` reads the raw Markdown document either from the configured local `.md` file (`dart:io` `File`) or from the configured WebDAV endpoint via HTTP `GET` (`WebDavRepository.fetchMarkdown`). Missing files (`HTTP 404` or non-existent local file) initialize an empty board.
3. **Parse & Normalize:** `MarkdownService.parse` matches headings strictly by their bracketed tier number (`[1]` to `[6]`), ignores any trailing heading text, and initializes missing tiers as empty lists. `TaskBoard.pruneCompletedTasks` removes Tier `6` items older than 30 days (UTC), and `TaskBoard.applyAutoPull` refills Tier `1` (up to `3`) from Tier `2` and Tier `2` (up to `5`) from Tier `3`.
4. **Mutation & Persistence:** Every user action (`addTask`, `completeTask`, `restoreTask`, `downgradeTask`, `blockTask`, `moveTask`, `editTaskTitle`, `deleteTask`) produces a new immutable `TaskBoard`, updates UI state, serializes all 6 tiers (`# [1]` through `# [6]`) via `MarkdownService.serialize` using the active language's tier names, and persists the resulting Markdown back to the local `.md` file or WebDAV server (`HTTP PUT`).
