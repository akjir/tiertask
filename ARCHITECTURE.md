# TierTask Architecture and File Structure

> [!IMPORTANT]
> Update this file and [`AGENTS.md`](AGENTS.md) whenever the architecture, supported target platforms, directory layout, file responsibilities, or Markdown synchronization flow change.

## Architectural Layers

| Layer | Path | Responsibility |
| :--- | :--- | :--- |
| Models | `lib/models/` | Immutable domain data structures (`TaskTier`, `TaskItem`, `TaskBoard`, storage/WebDAV configuration) and deterministic pull/pruning business rules. |
| Services | `lib/services/` | Stateless single-pass Markdown parsing and serialization (`MarkdownService`). |
| Repositories | `lib/repositories/` | All external I/O: WebDAV HTTP `GET`/`PUT` (`dart:io` `HttpClient`), local Markdown file reads/writes (`dart:io` `File`), and encrypted settings persistence (`flutter_secure_storage`). |
| Providers | `lib/providers/` | Riverpod state management (`Notifier`, `AsyncNotifier`) coordinating domain mutations and repository synchronization. |
| UI | `lib/ui/` | Material 3 screens and modular leaf widgets for Linux, Android, and Windows. |

> [!NOTE]
> Per `P-IO-ISOLATION` and `P-WEBDAV-API`, all network (`HttpClient`), local filesystem (`File`), and secure storage (`FlutterSecureStorage`) operations are strictly isolated in `lib/repositories/`. Domain models, services, and UI widgets remain free of direct `dart:io` calls.

## Directory Layout

```text
tiertask/
├── AGENTS.md
├── ARCHITECTURE.md
├── CHANGELOG.md
├── LICENSE
├── README.md
├── analysis_options.yaml
├── pubspec.yaml
├── android/
├── linux/
├── windows/
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── task_board.dart
│   │   ├── task_item.dart
│   │   ├── task_tier.dart
│   │   └── webdav_config.dart
│   ├── providers/
│   │   └── task_providers.dart
│   ├── repositories/
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
| `README.md` | Project overview, supported platforms (Linux, Android, Windows), build instructions, and Markdown format reference. |
| `analysis_options.yaml` | Dart analyzer configuration and lint rules excluding `build/**`, `android/**`, `linux/**`, and `windows/**`. |
| `pubspec.yaml` | Package metadata and dependencies (`flutter`, `flutter_riverpod`, `flutter_secure_storage`). |

## Domain Models

| File | Function |
| :--- | :--- |
| `lib/models/task_tier.dart` | Defines the `TaskTier` enum for the 6 German H1 sections (`Fokus`, `Bereit`, `Irgendwann`, `Blockiert`, `Geplant`, `Erledigt`), soft limits, and heading lookup. |
| `lib/models/task_item.dart` | Immutable `TaskItem` value class with completion state, UTC `YYYY-MM-DD` date normalization, and Markdown line serialization. |
| `lib/models/task_board.dart` | Immutable `TaskBoard` aggregate enforcing the auto-pull cascade (`#Geplant -> #Bereit -> #Fokus`), 30-day completed task pruning, and anti-ping-pong downgrades. |
| `lib/models/webdav_config.dart` | Immutable configuration model for resolving WebDAV endpoints and Markdown file paths. |

## Services

| File | Function |
| :--- | :--- |
| `lib/services/markdown_service.dart` | Dependency-free parser and serializer converting between raw Markdown text and `TaskBoard` instances. |

## Repositories

| File | Function |
| :--- | :--- |
| `lib/repositories/settings_repository.dart` | Abstract `SettingsRepository`, `SecureSettingsRepository` (`flutter_secure_storage`), and `InMemorySettingsRepository` for persisting storage and WebDAV settings. |
| `lib/repositories/webdav_repository.dart` | Native `dart:io` `HttpClient` WebDAV repository executing authenticated HTTP `GET` and `PUT` operations with `WebDavException` error mapping; local `.md` file persistence is also isolated in `lib/repositories/`. |

## State Providers

| File | Function |
| :--- | :--- |
| `lib/providers/task_providers.dart` | Riverpod providers and notifiers (`SyncStateNotifier`, `WebDavConfigNotifier`, `TaskNotifier`) orchestrating board loading, mutations, and persistence. |

## User Interface

| File | Function |
| :--- | :--- |
| `lib/main.dart` | Application entry point wrapping `TierTaskApp` in a `ProviderScope` with Material 3 light/dark themes. |
| `lib/ui/home_screen.dart` | Primary board screen displaying `# Fokus`, `# Bereit`, and tabbed secondary tiers (`# Geplant`, `# Blockiert`, `# Irgendwann`, `# Erledigt`). |
| `lib/ui/settings_screen.dart` | Configuration screen for storage settings, WebDAV endpoint parameters, local file path, and connection testing. |
| `lib/ui/widgets/quick_add_bar.dart` | Bottom input bar for creating tasks with optional target tier selection. |
| `lib/ui/widgets/restore_task_sheet.dart` | Modal bottom sheet for selecting the destination tier when restoring a completed task from `# Erledigt`. |
| `lib/ui/widgets/task_tile.dart` | Individual task card providing completion, downgrade, quick-block, title editing, move, and delete actions. |

## Execution & Synchronization Flow

1. **Startup & Configuration Load:** `main.dart` initializes `ProviderScope`. `WebDavConfigNotifier` loads persisted storage and WebDAV configuration via `SettingsRepository`.
2. **Markdown Fetch (Local File or WebDAV):** If configured, `TaskNotifier` reads the raw Markdown document either from the configured local `.md` file (`dart:io` `File`) or from the configured WebDAV endpoint via HTTP `GET` (`WebDavRepository.fetchMarkdown`). Missing files (`HTTP 404` or non-existent local file) initialize an empty board.
3. **Parse & Normalize:** `MarkdownService.parse` converts the raw text into an immutable `TaskBoard`. `TaskBoard.pruneCompletedTasks` removes `# Erledigt` items older than 30 days (UTC), and `TaskBoard.applyAutoPull` refills `# Fokus` (up to `3`) and `# Bereit` (up to `5`).
4. **Mutation & Persistence:** Every user action (`addTask`, `completeTask`, `restoreTask`, `downgradeTask`, `blockTask`, `moveTask`, `editTaskTitle`, `deleteTask`) produces a new immutable `TaskBoard`, updates UI state, serializes the board via `MarkdownService.serialize`, and persists the resulting Markdown back to the local `.md` file or WebDAV server (`HTTP PUT`).
