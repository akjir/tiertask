---
id: TEP-002
title: Structured Diagnostic Logging, Configurable Log Levels, and Local/WebDAV Log Persistence
status: completed
type: feature
created: 2026-11-08
updated: 2026-11-08
---

# TEP-002: Structured Diagnostic Logging, Configurable Log Levels, and Local/WebDAV Log Persistence

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal expands `AppLogger` (`lib/services/app_logger.dart`) into a structured, level-filtered diagnostic and development telemetry subsystem with configurable minimum severity levels (`DEBUG`, `INFO`, `WARN`, `ERROR`), standardized machine- and human-readable `event | key=value` log output, rich session and environment metadata headers (stored in the log file and displayed in `LogViewerDialog`), deeper instrumentation across all architectural layers (`LIFECYCLE`, `TDF`, `DOMAIN`, `SYNC`, `STORAGE`, `UI`), separate local and/or WebDAV log persistence using a deterministic filename convention with bounded daily retention, and a CLI log analyzer subcommand in `.agents/scripts/tiertask_dev.py` to support development and debugging.

### 1.2 Motivation
The current `AppLogger` implementation has five limitations that restrict both post-incident diagnostics and day-to-day development:
1. **Unstructured Output:** Log entries mix free-form prose with inconsistent field names (`2ms` vs `elapsed=12ms`), making automated filtering, timing analysis, and causal correlation across multi-step operations (`Mutation -> TDF Serialize -> Local Save -> WebDAV Sync`) difficult.
2. **Incomplete Instrumentation Depth:** Critical subsystems lack diagnostic trace statements: `TaskBoardReconciler` (per-entity three-way merge decisions and conflict detection), `TaskBoardEvaluator` (why a task evaluated to `Blocked` via dependency, deferral, or `day`/`time`/`location` conditions), `PlatformLocationRepository` and `LocationNotifier` (GPS, Wi-Fi BSSID, Nominatim reverse geocoding, and GeoIP fallback steps), `PlatformLinkLauncherRepository`, `SettingsRepository`, and most UI dialogs/screens have no log instrumentation.
3. **No Configurable Log Levels:** All calls are emitted unconditionally when `diagnosticsEnabled` is active, without a user- or developer-selectable minimum `LogLevel` in `SettingsScreen` or interactive level/tag filtering in `LogViewerDialog`.
4. **Ephemeral Single-File Local Storage Only:** Logs are written only to a local `tiertask.log` file that is truncated to `0` bytes on clean application exit (`AppLifecycleState.detached`). Users and developers cannot persist logs across normal restarts, cannot automatically store or upload logs to a configured WebDAV server, and risk filename collisions across multiple devices.
5. **Missing Diagnostic Metadata:** Session headers only record the UTC timestamp and platform name, omitting the SemVer + Git build string (`v0.1.0+<count>.<hash>`), workspace ID, storage mode, time zone configuration, and log storage target.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Standardize all log lines to `<UTC-ISO-Timestamp> [<LEVEL>] [<TAG>] <event> | <key=value ...>` for unambiguous human reading and automated CLI/test evaluation.
  2. Instrument all architectural layers with clear distinction between operational milestones (`INFO`), recoverable anomalies (`WARN`), handled failures (`ERROR`), unhandled crashes (`CRASH`), and deep development traces (`DEBUG`).
  3. Add a configurable minimum `LogLevel` (`debug`, `info`, `warn`, `error`) in `WebDavConfig` and `SettingsScreen`, plus live `LogLevel` and `LogTag` filter controls in `LogViewerDialog`.
  4. Support separate diagnostic log persistence locally (`local`), on WebDAV (`webdav`), or both (`both`) when WebDAV is configured, with a deterministic, collision-free filename format (`tiertask_<YYYY-MM-DD>_<platform>_<workspaceId>.log`) and bounded file retention (`maxRetainedLogDays = 7`, `maxRetainedLogFiles = 5`).
  5. Record a structured `@meta` header block at the top of each log file and render its metadata summary (version, build, platform, workspace, time zone, active log level, file name, and entry/warn/error counts) inside `LogViewerDialog`.
  6. Add `python3 .agents/scripts/tiertask_dev.py log` to parse, filter, and summarize log files during development and debugging.
* **Non-Goals:**
  1. Third-party telemetry, cloud analytics SDKs, or external crash reporting servers (`P-STDLIB-FIRST`, `P-SECRET-HYGIENE`).
  2. Modifying the `.tdf` file specification (`TDF_SPEC.md`); diagnostic logs remain strictly separate from `.tdf` task board files.
  3. Logging sensitive credentials, passwords, raw `Authorization` headers, raw GPS coordinates (`latitude`, `longitude`), reverse-geocoded street/place addresses, or raw Wi-Fi MAC addresses (`BSSID`) (`P-SECRET-HYGIENE`).

### 1.4 Description

#### 1.4.1 Standardized Output Format (`LogRecord`)
Every diagnostic entry uses a deterministic single-line structure:
```text
2026-11-08T10:20:44.123Z [INFO ] [DOMAIN   ] task.complete | ws=tasks id=0123456789 recurring=false focus=2 ready=5 planned=1 blocked=0 someday=3 completed=4
2026-11-08T10:20:44.125Z [DEBUG] [DOMAIN   ] eval.summary | total=15 eligible=8 blockedDeferral=1 blockedDep=1 blockedCond=2 someday=3 completed=4 pruned=0 elapsedMs=1
2026-11-08T10:20:44.127Z [DEBUG] [TDF      ] tdf.serialize | v=0.5.1 tasks=15 labels=3 queue=8 deletedGen=0 bytes=1420 elapsedMs=1
2026-11-08T10:20:44.130Z [INFO ] [STORAGE  ] local.save | path=".../tasks.tdf" bytes=1420 elapsedMs=3
2026-11-08T10:20:44.290Z [INFO ] [STORAGE  ] webdav.put | uri="https://cloud.example.com/.../tasks.tdf" status=204 bytes=1420 elapsedMs=160
2026-11-08T10:20:44.292Z [INFO ] [SYNC     ] sync.complete | ws=tasks mode=both wroteLocal=true wroteRemote=true tasks=15 labels=3 gen=0 elapsedMs=167
```
* **Timestamp:** UTC ISO-8601 with millisecond precision (`YYYY-MM-DDTHH:MM:SS.mmmZ`).
* **Severity (`[LEVEL]`):** 5-character right-padded uppercase tag (`DEBUG`, `INFO `, `WARN `, `ERROR`, `CRASH`).
* **Subsystem (`[TAG]`):** 9-character right-padded uppercase tag (`LIFECYCLE`, `TDF      `, `DOMAIN   `, `SYNC     `, `STORAGE  `, `UI       `).
* **Event Identifier (`<domain>.<action>`):** Dot-separated machine token identifying what happened (e.g., `session.start`, `workspace.switch`, `tdf.parse`, `tdf.migrate`, `task.add`, `task.update`, `task.complete`, `eval.blocked`, `sync.stage.local`, `sync.stage.remote`, `sync.reconcile`, `webdav.get`, `webdav.put`, `location.lookup`, `ui.dialog.open`).
* **Structured Key-Value Payload:** Ordered `key=value` pairs after ` | `, quoting values containing spaces and sanitizing credentials and control characters.

#### 1.4.2 Recommended Instrumentation Locations & Depth (User & Development Support)

| Tag | Event / Location | Level | Logged Information & Analytical Value |
| :--- | :--- | :--- | :--- |
| `LIFECYCLE` | `session.start`, `session.recover`, `session.exit` (`AppLogger`, `main.dart`) | `INFO` / `WARN` | App version + Git build, platform, locale, active workspace ID, storage mode, time zone mode + offset, configured `logLevel`, `logStorageMode`, pruned expired log file count, and unclean exit recovery detection. |
| `LIFECYCLE` | `workspace.create`, `workspace.switch`, `workspace.rename`, `workspace.delete`, `workspace.unload` (`ActiveWorkspaceNotifier`) | `INFO` / `DEBUG` | Source and target workspace IDs, pre-unload flush status, and elapsed ms. |
| `LIFECYCLE` | `config.update` (`WebDavConfigNotifier`, `SettingsRepository`) | `INFO` / `WARN` | Changed setting keys (`storageMode`, `language`, `themeMode`, `themePalette`, `timeZoneMode`, `locationEnabled`, `diagnosticsEnabled`, `logLevel`, `logStorageMode`) and binary settings decode fallbacks (`WARN`). |
| `TDF` | `tdf.scan`, `tdf.parse`, `tdf.serialize` (`TdfScanner`, `TdfParser`, `TdfService`) | `INFO` / `DEBUG` | `INFO`: version, task/label counts, byte size, `elapsedMs`. `DEBUG`: line count, `queue` length, `deleted` generation and tombstone counts, load-time `0.5.0 -> 0.5.1` synthesis. |
| `TDF` | `tdf.migrate`, `tdf.id_migrate` (`TdfImporter`, `TdfIdMigration`) | `INFO` / `DEBUG` | Source and target versions (`0.2.0 -> ... -> 0.5.1`), per-step duration, migrated task/label ID mappings, and SHA-256 Base62 collision probe count. |
| `TDF` | `tdf.error` (`TdfService`, `TdfParser`, `TdfScanner`) | `ERROR` | `TdfErrorKind`, 1-based line number, source version, and sanitized error description. |
| `DOMAIN` | `task.add`, `task.update`, `task.complete`, `task.restore`, `task.delete`, `task.downgrade`, `task.schedule`, `task.block`, `task.move_queue`, `task.toggle_subtask` (`TaskBoardMutator`, `TaskBoardQueueMutator`) | `INFO` | Entity `id`, `fromTier -> toTier`, changed field flags (`priority`, `suspended`, `repeat`, `labels`, `deps`, `conditions`, `subtasks`), recurrence `nextDueUtc`, and resulting 6-tier counts. |
| `DOMAIN` | `eval.summary`, `eval.blocked`, `eval.prune` (`TaskBoardEvaluator`) | `DEBUG` / `INFO` | Guarded behind `AppLogger.shouldLog(LogLevel.debug)` and emitted only on actual board state transitions or deduplicated evaluation passes (never on redundant UI selector reads). `DEBUG`: evaluation timestamps (`utcNow`, `localNow`), `activeLabelId`, `coordAvailable`, per-reason blocking counts (`deferral`, `dependency`, `condition.day`, `condition.time`, `condition.location`), and anonymized location condition metrics (`distanceMeters`, `radiusMeters`, `withinRadius`). `INFO`: 30-day completed task and tombstone pruning counts + `generation` bump. |
| `SYNC` | `sync.start`, `sync.stage.local`, `sync.stage.remote`, `sync.complete`, `sync.error` (`TaskSyncPipeline`) | `INFO` / `ERROR` | Workspace ID, storage mode, `isInitialLoad`, baseline presence (`hasBaseline`, `ackGen`), whether local/remote write-back was executed or skipped (`wrote=true/false`), converged counts, and per-stage `elapsedMs`. |
| `SYNC` | `sync.reconcile.task`, `sync.reconcile.label`, `sync.reconcile.queue`, `sync.conflict` (`TaskBoardSync`, `TaskBoardReconciler`) | `DEBUG` / `WARN` | Guarded behind `AppLogger.shouldLog(LogLevel.debug)`. `DEBUG`: per-entity LWW winner (`primary`, `secondary`, `tieBreak`) and reason (`modifiedAt`, `completions`, `payload`, `deleted`), stripped deleted label IDs, and concurrent queue additions. `WARN`: `deletionConflict`, `recoveryRequired` (ambiguous IDs), `syncGenerationRollback`, or corrupted baseline reset. |
| `STORAGE` | `local.load`, `local.save`, `local.move`, `local.rename`, `local.wipe`, `local.backup`, `log.prune` (`LocalFileRepository`, `LocalFileOperations`) | `INFO` / `ERROR` | Sanitized file path, byte size, backup path (`.bak.NNN`), `elapsedMs`, and filesystem exception details. |
| `STORAGE` | `webdav.get`, `webdav.put`, `webdav.wipe`, `webdav.log_put` (`WebDavRepository`) | `INFO` / `WARN` / `ERROR` | Sanitized endpoint URI, HTTP method, HTTP status code, payload bytes, `elapsedMs`, and socket/TLS/timeout error diagnostics. For `webdav.log_put`, record upload intent before serializing the log snapshot and never append a post-snapshot log line on HTTP `200`/`201`/`204` success (avoiding stale remote buffers and recursive self-logging loops); emit `webdav.log_put` after the HTTP call only on `WARN`/`ERROR` failure. |
| `STORAGE` | `location.lookup`, `location.geocode`, `location.geoip`, `link.open` (`PlatformLocationRepository`, `LocationNotifier`, `PlatformLinkLauncherRepository`) | `INFO` / `DEBUG` / `WARN` | Strict privacy sanitization (`P-SECRET-HYGIENE`): never log raw `latitude`/`longitude`, reverse-geocoded street/place names, or raw Wi-Fi `BSSID` MAC addresses. Log only anonymized metrics: `source` (`gps`, `system`, `internet`), `coordAvailable=true/false`, `bssidCount`, `distanceMeters`, 100m Haversine geocoding gate `displaced=true/false`, 30m GeoIP `cacheHit=true/false`, 5m resume `cooldownSkipped=true/false`, and `elapsedMs`. |
| `UI` | `ui.screen.open`, `ui.dialog.open`, `ui.filter.change`, `ui.action` (`HomeScreen`, `SettingsScreen`, `EditTaskScreen`, `EditLabelsScreen`, dialogs) | `INFO` / `DEBUG` | Screen/dialog name, active label filter or search state, and manual user triggers (sync, wipe, file select, log export/upload). |

#### 1.4.3 Log Levels & UI Configurability
`LogLevel` defines five ordered severities:
1. `LogLevel.debug` (`id: 0`, `DEBUG`): Full development trace including condition evaluation, per-entity sync decisions, and TDF block metrics.
2. `LogLevel.info` (`id: 1`, `INFO`, **default**): Standard operational milestones, mutations, sync stages, storage I/O, and UI navigation.
3. `LogLevel.warn` (`id: 2`, `WARN`): Recoverable fallbacks, sync conflicts, cache/baseline anomalies.
4. `LogLevel.error` (`id: 3`, `ERROR`): Handled domain, parser, filesystem, and network exceptions.
5. `LogLevel.crash` (`id: 4`, `CRASH`): Unhandled framework or isolate exceptions (always captured when logging is enabled).

* **Settings UI (`DiagnosticsSelectionCard` in `SettingsScreen`):**
  When diagnostic logging is enabled, display:
  1. **Log Level Selector (`SegmentedButton<LogLevel>`):** `Debug`, `Info` (default), `Warn`, `Error`.
  2. **Log Storage Selector (`SegmentedButton<StorageMode>`):** `Local`, `WebDAV` (enabled when WebDAV is configured), `Both` (enabled when WebDAV is configured).
  3. **Active Log Filename & Metadata Preview:** Shows the resolved log filename and a direct button to open `LogViewerDialog`.
* **Log Viewer UI (`LogViewerDialog`):**
  1. **Metadata Summary Banner:** Displays `AppVersion`, `Platform`, `Workspace`, `TimeZone`, `LogLevel`, `LogStorageMode`, `FileName`, and `Entries / Warnings / Errors` counters.
  2. **Interactive Filter Bar:** Filter visible lines in real time by minimum `LogLevel` (`Debug+`, `Info+`, `Warn+`, `Error+`) and by `LogTag` (`All`, `LIFECYCLE`, `TDF`, `DOMAIN`, `SYNC`, `STORAGE`, `UI`).
  3. **Actions:** `Copy All` (copies metadata header + filtered or full log), `Sync Log Now` (uploads/flushes to WebDAV when configured), `Scroll to Bottom`, and `Clear Log`.

#### 1.4.4 Filename Format, Retention Policy, Lifecycle Flushing & Local / WebDAV Storage
* **Deterministic Filename Format:**
  `tiertask_<YYYY-MM-DD>_<platform>_<workspaceId>.log`
  Example: `tiertask_2026-11-08_linux_tasks.log` or `tiertask_2026-11-08_android_work.log`.
  * **Why this format:**
    * Sorts chronologically by UTC date (`YYYY-MM-DD`).
    * Prevents multi-device overwrite collisions on WebDAV because `<platform>` (`linux`, `android`, `windows`) and `<workspaceId>` (`tasks`) are encoded in the filename.
    * Avoids creating dozens of tiny files on rapid restarts within the same day while keeping daily logs bounded (`maxFileBytes = 2 MiB`, `defaultMaxLines = 5000`).
    * Preserves logs across normal application restarts on the same day instead of wiping the log on clean `detached` exit.
* **Daily Log File Retention Bounds (`P-BOUND-ALLOC`):**
  * Enforce `AppLogger.maxRetainedLogDays = 7` and `AppLogger.maxRetainedLogFiles = 5` per `<platform>_<workspaceId>` stream so dated log files never accumulate unboundedly over weeks or months.
  * On session initialization (`AppLogger.setEnabled`), scan the local log directory and delete any log files matching `tiertask_*_<platform>_<workspaceId>.log` whose UTC date is older than `maxRetainedLogDays` (`7` days) or that exceed the `maxRetainedLogFiles` (`5` newest files) cap.
  * When diagnostic logging is disabled in `SettingsScreen` or the user triggers `Clear Log` in `LogViewerDialog`, delete all local log files for the workspace (`tiertask_*_<platform>_<workspaceId>.log` and legacy `tiertask.log`) and, when WebDAV log storage is active, delete or truncate the active remote WebDAV log file.
* **WebDAV Remote Path Resolution, Throttling & Self-Logging Prevention:**
  * Resolved relative to the configured WebDAV directory of `config.filePath` (e.g., if `filePath` is `tiertask/tasks.tdf`, the remote log URI resolves to `.../tiertask/tiertask_2026-11-08_linux_tasks.log`).
  * **Debounced Upload Strategy:** Do not upload the full log file (up to `2 MiB`) synchronously on every rapid task mutation in `TaskSyncPipeline`. Instead, schedule automatic WebDAV log uploads via a trailing debounce timer (`AppLogger.webDavFlushDebounce = Duration(seconds: 5)`) after sync/mutation activity settles, in addition to immediate flushes on manual `Sync Log Now` in `LogViewerDialog` and background lifecycle transitions.
  * **No Post-Snapshot Self-Logging on Success:** `WebDavRepository.saveLog(String logFileName, String content)` records any upload-start trace *before* taking the log text snapshot and emits zero log entries after HTTP `200`/`201`/`204` completion. Only HTTP/network failures emit a `WARN`/`ERROR` `webdav.log_put` entry (without re-triggering the debounce timer), preventing stale remote snapshots and infinite upload loops.
* **OS Lifecycle Reliability for Local vs. WebDAV Log Flushes:**
  * Asynchronous HTTP `PUT` requests (`WebDavRepository.saveLog`) cannot reliably complete during `AppLifecycleState.detached` because mobile (Android) and desktop (Linux/Windows) OS kernels terminate the process before asynchronous socket I/O finishes.
  * Therefore, asynchronous WebDAV log flushes are triggered on `AppLifecycleState.inactive` and `AppLifecycleState.paused` (when the application transitions to the background or loses focus), while `AppLifecycleState.detached` is reserved strictly for synchronous local disk flushing (`LocalFileRepository.writeLogFileSync`).
* **Structured File Metadata Header (`LogMetadata`):**
  Written at the top of the log file and updated on session start:
  ```text
  === TIERTASK DIAGNOSTIC LOG ===
  # format: tiertask-log/1.0
  # file: tiertask_2026-11-08_linux_tasks.log
  # version: v0.1.0+42.a1b2c3d
  # platform: linux (locale=de)
  # workspace: tasks ("Tasks")
  # timezone: automatic (UTC+01:00)
  # storage_mode: both (log_storage=both, min_level=DEBUG)
  # session_start: 2026-11-08T10:20:44.123Z
  ===============================
  ```

### 1.5 Alternatives
* **Alternative A — Single static `tiertask.log` on WebDAV:** Rejected because syncing a single `tiertask.log` from both a Linux desktop and an Android phone on the same WebDAV account would overwrite each device's diagnostic history.
* **Alternative B — JSON Lines (`.jsonl`) log files:** Rejected because raw JSON lines are harder for users to read directly in `LogViewerDialog` or a text editor; the `timestamp [LEVEL] [TAG] event | key=value` format is both human-readable in monospace UI and trivially parsed into JSON/dictionaries by `tiertask_dev.py log`.
* **Alternative C — Truncating logs on every clean exit:** Rejected because post-session analysis of synchronization, condition evaluation, or performance requires logs to survive normal application restarts while diagnostic logging is enabled.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules
* **Rank 0 (`lib/services/app_logger.dart`):**
  * Add `LogMetadata` immutable value class, `minimumLevel` filtering on `AppLogger`, `AppLogger.shouldLog(LogLevel level)`, structured `AppLogger.event(LogLevel, LogTag, String event, {Map<String, Object?> fields})` helper, deterministic filename builder `AppLogger.formatLogFileName({required DateTime utcNow, required String platform, required String workspaceId})`, retention constants (`maxRetainedLogDays = 7`, `maxRetainedLogFiles = 5`, `webDavFlushDebounce = Duration(seconds: 5)`), and `@meta` header parser/serializer.
  * Extend `AppLogSink` with `pruneExpiredLogFilesSync({String? baseDirectoryPath, required String platform, required String workspaceId, required DateTime utcNow, required int maxRetainedDays, required int maxRetainedFiles})` and `deleteWorkspaceLogFilesSync({String? baseDirectoryPath, required String platform, required String workspaceId})`.
* **Layer 1 (`lib/models/`):**
  * `lib/models/webdav_config.dart`: Add `logLevel` (`LogLevel`, default `LogLevel.info`) and `logStorageMode` (`StorageMode`, default `StorageMode.local`) to `WebDavConfig`, plus `resolveLogEndpointUri(String logFileName)` for WebDAV log upload.
  * `lib/models/app_workspace.dart`: Persist `logLevel` and `logStorageMode` deterministically inside the existing fixed-width `TTW\x01` binary record without adding trailing bytes:
    * `tzWord` bits `11..12` (`(tzWord >> 11) & 0x03`): `logLevel` (`0 = LogLevel.info` default for `00` backward compatibility, `1 = LogLevel.debug`, `2 = LogLevel.warn`, `3 = LogLevel.error`).
    * `flags` bit `7` (`(flags >> 7) & 0x01`) combined with `tzWord` bits `0..10` (`offsetField = tzWord & 0x07FF`):
      * `flags` bit `7 == 0` and `offsetField in 0..1560`: `logStorageMode = StorageMode.local`, `manualTimeZoneOffsetMinutes = offsetField - 720`.
      * `flags` bit `7 == 1` and `offsetField in 0..1560`: `logStorageMode = StorageMode.webdav`, `manualTimeZoneOffsetMinutes = offsetField - 720`.
      * `flags` bit `7 == 1` and `offsetField in 1561..1873`: `logStorageMode = StorageMode.both`, `manualTimeZoneOffsetMinutes = ((offsetField - 1561) * 5) - 720` (utilizing the unused upper range `1561..2047` of the 11-bit `offsetField` to encode all 37 `WebDavConfig.supportedUtcOffsetMinutes` and every 5-minute UTC offset in `-720..840`).
  * `lib/models/task_board_evaluator.dart`, `lib/models/task_board_mutator.dart`, `lib/models/task_board_queue_mutator.dart`, `lib/models/task_board_sync.dart`, `lib/models/task_board_reconciler.dart`: Add structured `INFO` and `DEBUG` instrumentation guarded by `AppLogger.shouldLog(LogLevel.debug)` and deduplicated so pure `TaskBoardEvaluator.evaluate` calls during UI reads do not flood the log buffer.
* **Layer 2 (`lib/l10n/`):**
  * `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`: Add localization strings for log levels (`Debug`, `Info`, `Warning`, `Error`), log storage targets, metadata labels in `LogViewerDialog`, and WebDAV log upload actions.
* **Layer 3 (`lib/services/`):**
  * `lib/services/tdf_service.dart`, `lib/services/tdf_parser.dart`, `lib/services/tdf_importer.dart`, `lib/services/tdf_id_migration.dart`: Add structured `tdf.*` events and `DEBUG` metrics.
* **Layer 4 (`lib/repositories/`):**
  * `lib/repositories/local_file_repository.dart` & `lib/repositories/local_file_operations.dart`: Implement dated log filename resolution, `pruneExpiredLogFilesSync`, and `deleteWorkspaceLogFilesSync`.
  * `lib/repositories/webdav_repository.dart`: Add `saveLog(String logFileName, String logContent)` (without post-snapshot success logging) and `deleteLog(String logFileName)` using `config.resolveLogEndpointUri(logFileName)`.
  * `lib/repositories/location_repository.dart`, `lib/repositories/link_launcher_repository.dart`, `lib/repositories/settings_repository.dart`: Add structured `AppLogger` instrumentation with strict coordinate/address/BSSID privacy sanitization.
* **Layer 5 (`lib/providers/`):**
  * `lib/providers/config_providers.dart`: Synchronize `LogMetadata`, `logLevel`, `logStorageMode`, and resolved dated filename in `diagnosticsEnabledProvider` and `WebDavConfigNotifier`.
  * `lib/providers/sync_providers.dart`: Schedule debounced (`5s`) WebDAV log uploads after sync/mutations and trigger immediate background flushes on `AppLifecycleState.inactive` / `paused` when `config.diagnosticsEnabled && config.logStorageMode.usesWebDav && config.isWebDavConfigured`.
  * `lib/providers/location_providers.dart`, `lib/providers/task_providers.dart`, `lib/providers/workspace_providers.dart`: Add structured lifecycle, location, and mutation correlation logs.
* **Layer 6 (`lib/ui/`):**
  * `lib/ui/widgets/settings_preference_cards.dart`: Expand `DiagnosticsSelectionCard` with `LogLevel` and `LogStorageMode` segmented buttons and metadata/viewer quick link when enabled.
  * `lib/ui/widgets/log_viewer_dialog.dart`: Add `_LogMetadataCard`, `_LogFilterBar` (`LogLevel` and `LogTag` filters), and `Sync Log Now` button.
* **Developer Tooling (`.agents/scripts/tiertask_dev.py`):**
  * Add `log` subcommand (`python3 .agents/scripts/tiertask_dev.py log [path] [--level ...] [--tag ...] [--event ...] [--summary]`) to inspect and evaluate local or downloaded `.log` files during development.

### 2.2 TDF Schema, Localization & State Changes
* **`TDF_SPEC.md`:** No `.tdf` format changes.
* **Binary Persistence (`TTW\x01` in `AppWorkspace`):**
  * Both `logLevel` and `logStorageMode` are encoded deterministically inside the existing fixed-width `TTW\x01` record (`flags` byte + 16-bit `tzWord`) without adding trailing bytes or changing the 51-byte default workspace record size:
    * `flags` byte (1 byte):
      * Bits `0..1`: `storageMode.id` (`0..2`)
      * Bits `2..3`: `language.id` (`0..2`)
      * Bits `4..5`: `themeMode.id` (`0..2`)
      * Bit `6`: `themePalette.id` (`0..1`)
      * Bit `7`: `logStorageMode != StorageMode.local ? 1 : 0` (`0` for default `StorageMode.local`, preserving `(flags & 0x80) == 0` for default workspaces).
    * `tzWord` (16-bit unsigned big-endian integer):
      * Bits `0..10` (11 bits, `offsetField = tzWord & 0x07FF`):
        * When `logStorageMode` is `StorageMode.local` (`flags` bit `7 == 0`): `offsetField = manualTimeZoneOffsetMinutes + 720` (`0..1560`).
        * When `logStorageMode` is `StorageMode.webdav` (`flags` bit `7 == 1`): `offsetField = manualTimeZoneOffsetMinutes + 720` (`0..1560`).
        * When `logStorageMode` is `StorageMode.both` (`flags` bit `7 == 1`): `offsetField = 1561 + ((manualTimeZoneOffsetMinutes + 720) ~/ 5)` (`1561..1873`, inside the unused upper range `1561..2047` of the 11-bit field; decodes back via `manualTimeZoneOffsetMinutes = ((offsetField - 1561) * 5) - 720`). Any `offsetField > 1873` or `< 1561` when decoding invalid combinations is clamped/validated per existing `TTW\x01` rules.
      * Bits `11..12` (2 bits, `levelCode = (tzWord >> 11) & 0x03`):
        * `0` -> `LogLevel.info` (default; existing `TTW\x01` payloads with bits `11..12 == 00` decode to `LogLevel.info`)
        * `1` -> `LogLevel.debug`
        * `2` -> `LogLevel.warn`
        * `3` -> `LogLevel.error`
      * Bit `13`: `diagnosticsEnabled` (`0` or `1`)
      * Bit `14`: `locationEnabled` (`0` or `1`)
      * Bit `15`: `timeZoneMode.id` (`0` or `1`)
* **Localization (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`):**
  * `logLevelLabel`, `logLevelDebug`, `logLevelInfo`, `logLevelWarn`, `logLevelError`
  * `logStorageLabel`, `logStorageLocal`, `logStorageWebDav`, `logStorageBoth`
  * `logMetadataSectionTitle`, `logMetadataFile`, `logMetadataVersion`, `logMetadataPlatform`, `logMetadataWorkspace`, `logMetadataTimeZone`, `logMetadataStats`
  * `logFilterAllTags`, `tooltipSyncLogWebDav`, `logSyncedSnackBar`

### 2.3 Implementation Details
* **Zero-Allocation Guard & Pure Model Deduplication (`P-ZERO-ALLOC`):**
  * `AppLogger.shouldLog(LogLevel level)` checks `_enabled && (level == LogLevel.crash || level.index >= _minimumLevel.index)` before formatting timestamps, sanitizing strings, or allocating map entries.
  * Because `TaskBoardEvaluator.evaluate` is a pure function invoked during state checks and UI selector evaluations, Layer 1 diagnostic trace events (`eval.summary`, `eval.blocked`, `sync.reconcile.*`) must be strictly gated behind `AppLogger.shouldLog(LogLevel.debug)` and deduplicated (or gated via an explicit `emitDiagnosticTrace` parameter enabled only on state mutations and sync passes) so widget rebuilds never allocate or emit redundant log lines.
* **Location & Network Privacy Sanitization (`P-SECRET-HYGIENE`):**
  * `AppLogger.sanitize` continues to redact registered secrets, `Authorization` headers, Bearer/Basic tokens, and URL userinfo.
  * In addition, `PlatformLocationRepository`, `LocationNotifier`, and `TaskBoardEvaluator` must never pass raw GPS coordinates (`latitude`, `longitude`), reverse-geocoded street/city names, or Wi-Fi `BSSID` MAC addresses to `AppLogger`; only boolean availability flags, integer AP counts (`bssidCount`), source enum names (`gps`, `system`, `internet`), and rounded Haversine distances/radii (`distanceMeters`, `radiusMeters`, `withinRadius`) may be logged.
* **Repository I/O Isolation & Lifecycle Flushing (`P-IO-ISOLATION`, `P-ACYCLIC-DAG`):**
  * `AppLogger` remains at DAG rank `0` in `lib/services/app_logger.dart` with zero `dart:io` imports. Synchronous local file I/O and retention pruning use `AppLogSink` (`LocalFileLogSink`).
  * Asynchronous WebDAV log uploads (`WebDavRepository.saveLog`) are debounced (`5s`) after sync/mutations and flushed on `AppLifecycleState.inactive` / `paused` (backgrounding) and manual `Sync Log Now`, while `AppLifecycleState.detached` executes only synchronous local disk flushes.
* **Resource & File Retention Bounds (`P-BOUND-ALLOC`):**
  * Enforce `AppLogger.maxFileBytes = 2097152` (`2 MiB`) and `AppLogger.defaultMaxLines = 5000` per log file, preserving the `@meta` header block and `[CRASH]` entries during 20% rolling pruning.
  * Enforce `AppLogger.maxRetainedLogDays = 7` and `AppLogger.maxRetainedLogFiles = 5` per `<platform>_<workspaceId>` stream on startup, and delete all local/remote workspace log files when diagnostics are disabled or cleared.

### 2.4 Testing Strategy
* **`M-EXHAUSTIVE-STATE-TESTS`:** Test all `LogLevel` filtering thresholds (`debug`, `info`, `warn`, `error`, `crash`), all `LogTag` filters, and all `StorageMode` log persistence combinations (`local`, `webdav`, `both`) including `TTW\x01` binary round-trips across all 4 `LogLevel` values, all 3 `StorageMode` values, and all 37 `WebDavConfig.supportedUtcOffsetMinutes`.
* **`M-EXTREME-BOUND-TESTS`:** Verify rolling 20% pruning at `defaultMaxLines` and `maxFileBytes` preserves both the `@meta` session header block and `[CRASH]` stack traces, and verify daily file retention pruning at `maxRetainedLogDays = 7` and `maxRetainedLogFiles = 5`.
* **`M-DELIM-INJECT-TESTS`:** Verify `AppLogger.sanitize` and `key=value` formatting strip control characters, collapse CRLF/LF newlines, escape quotes, redact passwords/tokens/headers/userinfo, and never leak raw GPS coordinates, street addresses, or Wi-Fi BSSIDs.
* **`M-URI-PATH-EDGE-TESTS`:** Verify deterministic log filename generation (`tiertask_<YYYY-MM-DD>_<platform>_<workspaceId>.log`) sanitizes workspace IDs and resolves WebDAV log endpoint URIs safely across base URLs, Nextcloud paths, and explicit `.tdf` URLs.
* **`M-IO-TESTS`:** Test local dated log file creation, append, retention pruning, and full deletion in `local_file_repository_test.dart`, and test debounced WebDAV `PUT` log upload, `inactive`/`paused` background flush, and absence of post-snapshot self-logging loops against a loopback `HttpServer` (`HttpOverrides.global = null`) in `webdav_repository_test.dart`.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [x] Run `flutter analyze --fatal-infos --fatal-warnings` and `flutter test` to confirm a clean baseline.
- [x] Agree on log filename convention, retention across clean exits, log level defaults, and UI controls with the user (`concept -> planned`).
- [x] Write failing unit and widget tests first in `test/services/app_logger_test.dart`, `test/models/app_workspace_test.dart`, `test/repositories/webdav_repository_test.dart`, `test/providers/config_providers_test.dart`, and `test/ui/settings_screen_test.dart` (TDD Red Phase — `P-TDD-FIRST`).
- [x] Implement `AppLogger` structured formatting, `LogMetadata`, `LogLevel` filtering, `WebDavConfig` / `AppWorkspace` persistence, `WebDavRepository.saveLog`, layer-wide instrumentation, and UI updates in `SettingsScreen` and `LogViewerDialog` (TDD Green & Refactor Phase).
- [x] Add `log` analyzer subcommand to `.agents/scripts/tiertask_dev.py`.
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix`.
- [x] Synchronize `README.md`, `ARCHITECTURE.md`, `AGENTS.md`, and `CHANGELOG.md`.
- [x] Set `status: review`, update `BOARD.md`, and request user approval.
- [x] After user approval, set `status: completed`, update `BOARD.md`, and finalize delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
* **2026-11-08:** Drafted initial `TEP-002` specification covering structured log output, layer-wide instrumentation proposals, configurable log levels, metadata headers, and separate local/WebDAV log persistence.
* **2026-11-08:** Refined `TEP-002` with fixed-width `TTW\x01` bit-packing math, daily log file retention bounds (`7` days / `5` files), debounced WebDAV upload without post-snapshot self-logging, `inactive`/`paused` background WebDAV flushing, deduplicated Layer 1 `DEBUG` evaluation traces, and strict coordinate/address/BSSID privacy sanitization.
* **2026-11-08:** Completed TDD Red-Green-Refactor implementation across `AppLogger`, `WebDavConfig`, `AppWorkspace`, `TaskBoardEvaluator`, `TaskBoardSync`, `TaskBoardReconciler`, `TdfService`, `LocalFileRepository`, `WebDavRepository`, `LocationRepository`, `LinkLauncherRepository`, `WebDavConfigNotifier`, `TaskSyncPipeline`, `DiagnosticsSelectionCard`, `LogViewerDialog`, and `.agents/scripts/tiertask_dev.py`; verified all tests and static checks pass.
* **2026-11-08:** Approved by the user; set `status: completed` and moved `TEP-002` to `Completed Proposals` in `.agents/proposals/BOARD.md`.

### 3.3 Delivered Artifacts
* **Source Files (`lib/`):** `lib/services/app_logger.dart`, `lib/models/webdav_config.dart`, `lib/models/app_workspace.dart`, `lib/models/task_board_evaluator.dart`, `lib/models/task_board_sync.dart`, `lib/models/task_board_reconciler.dart`, `lib/services/tdf_service.dart`, `lib/repositories/local_file_operations.dart`, `lib/repositories/local_file_repository.dart`, `lib/repositories/webdav_repository.dart`, `lib/repositories/location_repository.dart`, `lib/repositories/link_launcher_repository.dart`, `lib/providers/config_providers.dart`, `lib/providers/sync_providers.dart`, `lib/providers/workspace_providers.dart`, `lib/main.dart`, `lib/ui/settings_screen.dart`, `lib/ui/widgets/settings_preference_cards.dart`, `lib/ui/widgets/log_viewer_dialog.dart`.
* **Localization (`lib/l10n/`):** `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`.
* **Test Files (`test/`):** `test/services/app_logger_test.dart`, `test/models/app_workspace_test.dart`, `test/repositories/local_file_repository_test.dart`, `test/repositories/webdav_repository_test.dart`, `test/providers/config_providers_test.dart`, `test/ui/settings_screen_test.dart`.
* **Developer Tooling & Documentation:** `.agents/scripts/tiertask_dev.py`, `AGENTS.md`, `ARCHITECTURE.md`, `README.md`, `CHANGELOG.md`.
