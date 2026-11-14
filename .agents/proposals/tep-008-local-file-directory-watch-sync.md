---
id: TEP-008
title: Automatic Local TDF Directory Watching, Digest-Gated Reconciliation, and Per-Workspace Settings Toggle
status: planned
type: feature
created: 2026-11-14
updated: 2026-11-14
---

# TEP-008: Automatic Local TDF Directory Watching, Digest-Gated Reconciliation, and Per-Workspace Settings Toggle

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal introduces automatic local `.tdf` parent-directory observation and three-way external edit reconciliation in `StorageMode.local` and `StorageMode.both`, controlled by a per-workspace `localWatchEnabled` setting (`default: true`) in `WebDavConfig` (`lib/models/webdav_config.dart`) and `SettingsScreen` (`lib/ui/settings_screen.dart`). `LocalFileRepository` (`lib/repositories/local_file_repository.dart`) observes the active `.tdf` file's parent directory via `dart:io` `Directory.watch(recursive: false)`, filtering out sibling files, temporary staging files, diagnostic logs, and deletion events. A dedicated Riverpod watcher subsystem (`lib/providers/local_file_watch_providers.dart`) applies a `350 ms` trailing-edge debounce, serializes behind active in-app synchronization operations, and compares the on-disk SHA-256 hex digest against `WorkspaceSyncState.localSourceDigest` before executing non-destructive three-way reconciliation through `TaskNotifier` (`lib/providers/task_providers.dart`) and `TaskSyncPipeline` (`lib/providers/sync_providers.dart`).

### 1.2 Motivation
In the current implementation, `TaskSyncPipeline` reads and merges the local `.tdf` file only on application startup, manual synchronization (`syncFromRemote`, `testConnectionAndSync`), workspace or file selection, and in-app domain mutations (`addTask`, `updateTask`, `completeTask`, `downgradeTask`, `deleteTask`, `toggleSubtask`, `addLabel`, `addLocation`, etc.):
1. **Unmerged External Edits While Idle:** When an external text editor, CLI script, or background file-synchronization daemon updates the active `.tdf` file while TierTask is open on Linux, Android, or Windows, the in-memory `TaskBoard` remains stale until the user manually triggers synchronization or edits a task inside TierTask.
2. **Atomic Replacement Blindness with Direct File Watchers:** External text editors, background file-synchronization daemons, and `LocalFileOperations.writeTdfAtomicallySync` save updates by writing a temporary file in the same directory and executing an atomic `rename()` onto the target `.tdf` path. Watching a `File` inode directly loses observation after the first `rename()` on Linux and Android (`inotify`) and throws `FileSystemException` on Windows (`ReadDirectoryChangesW` supports directories only).
3. **Self-Write & Log Feedback Risk Without Digest Gating:** Because dated diagnostic logs (`tiertask_<date>_<platform>_<workspace>.log`) and `.tmp.<32hex>` atomic staging files reside in the same default user data directory as `tasks.tdf`, an unfiltered directory watcher or an un-gated file watcher would either loop on `AppLogger` writes or re-run `TdfService.parse` and WebDAV HTTP requests after TierTask's own local writes.
4. **Configurable Per-Workspace Control:** While automatic external file reconciliation should be enabled by default (`localWatchEnabled: true`), users working on slow network mounts or editing large `.tdf` batches externally need an explicit per-workspace toggle in `SettingsScreen` (`LocalStorageSection`) to disable automatic directory watching without changing `StorageMode`.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Add `bool localWatchEnabled = true` to `WebDavConfig` (`lib/models/webdav_config.dart`) and persist it losslessly inside the existing 51-byte `TTW\x01` binary workspace record (`lib/models/app_workspace.dart`) with full backward compatibility so existing persisted workspaces decode with `localWatchEnabled: true`.
  2. Render a localized Material 3 toggle switch (`ValueKey('settings_local_watch_switch')`) inside `LocalStorageSection` (`lib/ui/widgets/settings_local_storage_section.dart`) whenever `storageMode.usesLocal` (`StorageMode.local` or `StorageMode.both`), wired to `WebDavConfigNotifier.updateLocalWatchEnabled` (`lib/providers/config_providers.dart`) with English (`en`) and German (`de`) localization strings.
  3. Observe the parent directory of the configured `.tdf` file via `Directory(directoryPath).watch(recursive: false)` inside `LocalFileOperations` and `LocalFileRepository` (`lib/repositories/`), emitting `Stream<void>` notifications strictly for `Create`, `Modify`, and `Move` (`event.path` or `event.destination`) events matching the active `.tdf` filename while ignoring `Delete` events, `.tmp` staging files, `.bak` backups, sibling `.tdf` files, and `.log` files.
  4. Coordinate subscription lifecycle, `350 ms` trailing-edge debouncing, and `AppLifecycleState.resumed` catch-up checks in `lib/providers/local_file_watch_providers.dart` without rebuilding on unrelated preference edits (`themeMode`, `themePalette`, `language`, `diagnosticsEnabled`, `logLevel`).
  5. Gate reconciliation in `TaskNotifier.reconcileExternalLocalChanges()` behind `_awaitInFlightSync()` and `WorkspaceSyncState.localSourceDigest` so TierTask's own local writes, `wipeLocalFile`, metadata-only `touch` events, `0`-byte truncated intermediate files, and byte-identical saves perform zero TDF parses and zero WebDAV HTTP requests.
  6. Execute confirmed external merges non-destructively via `TaskSyncPipeline.synchronize` (`In-Memory <-> Local File` in `StorageMode.local`; `In-Memory <-> Local File <-> WebDAV` in `StorageMode.both`) without flashing `AsyncLoading()` over `HomeScreen`, without clearing the in-memory undo stack (`TEP-007`), and without overwriting malformed external `.tdf` files (`P-ATOMIC-STATE`).
* **Non-Goals:**
  1. **Changes to `spec/TDF_SPEC_0.6.0.md`:** Normative `sourceDigest` (Section 6.7.2), three-way entity/queue/deletion reconciliation (Sections 6.7–6.11), and guarded CAS publication (Sections 6.8.3–6.8.4) already cover all synchronization semantics.
  2. **Polling Loops or Third-Party Watcher Packages:** Observation uses only `dart:io` `Directory.watch` (`inotify` on Linux/Android, `ReadDirectoryChangesW` on Windows) plus an event-driven `AppLifecycleState.resumed` digest check (`P-STDLIB-FIRST`).
  3. **Recursive Subdirectory Watching:** Only the immediate parent directory of the configured `.tdf` file is watched (`recursive: false`).
  4. **WebDAV Push Notifications:** In `StorageMode.webdav`, local directory watching is inactive (`!storageMode.usesLocal`).

### 1.4 Description

#### 1.4.1 Per-Workspace Settings Option (`localWatchEnabled`, Default `true`)
1. **Visibility & Placement:** In `SettingsScreen`, `LocalStorageSection` renders when `storageMode.usesLocal` (`Local` or `Both`). Below the resolved local file path preview (`ResolvedPathPreview`) and four file management buttons (`Select`, `Move`, `Rename`, `Delete`), `LocalStorageSection` displays a toggle row containing `localWatchLabel`, `localWatchDescription`, and a Material 3 `Switch` (`ValueKey('settings_local_watch_switch')`) bound to `config.localWatchEnabled`.
2. **Default & Persistence:** New workspaces (`WebDavConfig()`) and previously saved `TTW\x01` workspace records default to `localWatchEnabled: true`. Toggling the switch persists the updated `WebDavConfig` immediately to `SettingsRepository` via `WebDavConfigNotifier.updateLocalWatchEnabled` and activates or cancels the active `Directory.watch` subscription without reloading `TaskBoard` (`AsyncLoading()`) or resetting the undo stack. When `localWatchEnabled` transitions from `false` to `true` within the same workspace, `LocalFileWatcherNotifier` also schedules a single debounced `reconcileExternalLocalChanges()` check (`localSourceDigest`-gated) so any external batch edits saved while watching was disabled merge immediately.

#### 1.4.2 Parent-Directory Observation & Event Filtering
1. **Atomic Save Compatibility:** Watching `Directory(directoryPath).watch(recursive: false)` receives events regardless of whether an external tool edits `<file>.tdf` in place (`FileSystemModifyEvent`) or writes a temporary file in the same or another directory and renames it onto `<file>.tdf` (`FileSystemMoveEvent` with `destination` or `path`, or `FileSystemCreateEvent`).
2. **Filename Matching Rules:** `LocalFileOperations.matchesWatchedFileName` slices the trailing basename of `event.path` and (for `FileSystemMoveEvent`) `event.destination` directly via `lastIndexOf('/')` and `lastIndexOf(r'\')` without `.trim()`, `.split()`, or `defaultFileName` fallback (rejecting empty strings and trailing `/` or `\` separators immediately), and compares against the configured `.tdf` basename using exact case-sensitive matching on Linux and Android and case-insensitive matching (`toLowerCase()`) on Windows (`Platform.isWindows`).
3. **Noise & Race Suppression:**
   - `FileSystemDeleteEvent` is ignored so non-atomic tools that `unlink()` immediately before recreating `<file>.tdf` do not trigger a read while the file is transiently absent.
   - Sibling `.tdf` files (`work.tdf`), `.bak` / `.bak.NNN` backups, dot-prefixed `.tmp` files, and `tiertask_*.log` files do not match the target basename and never reset or arm the debounce timer.
   - Missing parent directories (`!directory.existsSync()`) and runtime `FileSystemException` stream errors are caught inside `LocalFileOperations`, logged at `LogLevel.warn` (`LogTag.storage`, `local.watch.error`), and closed cleanly without propagating uncaught asynchronous errors.

#### 1.4.3 Debouncing, Lifecycle Catch-Up & `localSourceDigest` Gate
1. **Trailing-Edge Debounce (`350 ms`):** Burst events from multi-syscall saves (`O_TRUNC` -> `write` -> `close` -> `attrib`) reset a single `350 ms` `Timer` in `LocalFileWatcherNotifier`, coalescing rapid writes into one reconciliation check after filesystem activity settles.
2. **Desktop Window Focus vs. Mobile Resume:**
   - On desktop (`Linux`, `Windows`), the `Directory.watch` subscription remains active when the TierTask window is unfocused (`AppLifecycleState.inactive` or `AppLifecycleState.hidden` across tiling workspaces) so side-by-side external editor saves update `HomeScreen` live.
   - On `AppLifecycleState.resumed`, `LocalFileWatcherNotifier` rebinds the directory stream if it had previously closed (and also rebinds automatically after initial board load or completed local saves via `syncStateProvider.lastSyncedAt` when the parent directory is created after startup) and schedules a single debounced `reconcileExternalLocalChanges()` check so edits made while an Android isolate was frozen in background are merged immediately upon returning to the app.
3. **Serialization & Digest Short-Circuit:**
   - `TaskNotifier.reconcileExternalLocalChanges()` awaits `_awaitInFlightSync()` first so any active in-app mutation or two-stage WebDAV sync finishes writing its converged `.tdf` file and persisting `WorkspaceSyncState.localSourceDigest` before the watcher reads disk.
   - `readTdfWithDigest()` reads the file once and computes `TdfIdMigration.sha256Hex(utf8.encode(content))`.
   - If `!disk.exists || disk.content.trim().isEmpty`, reconciliation aborts without modifying memory or disk (protecting external tools mid-truncation).
   - If `disk.digest == syncState.localSourceDigest`, reconciliation returns `false` immediately (`0` TDF parses, `0` merges, `0` HTTP requests, `0` UI state churn).
4. **Three-Way Merge & Error Isolation:**
   - When `disk.digest != syncState.localSourceDigest` (and `disk.digest != _lastFailedWatchDigest`), `TaskNotifier` runs `TaskSyncPipeline.synchronize` serialized via `_inFlightSync` with `candidateBoard: existingBoard` (`isInitialLoad: existingBoard == null`).
   - In `StorageMode.local`, Stage 1 merges `existingBoard` and the external `.tdf` against `lastSyncedLocalTdf`, writes canonical `tdf 0.6.0` via `_publishLocalWithCasLoop`, updates `localSourceDigest`, and updates `state = AsyncData(mergedBoard)` in place without setting `AsyncLoading()`.
   - In `StorageMode.both` (when `isWebDavConfigured` is `true`), Stage 2 additionally synchronizes the merged board with WebDAV (`304 Not Modified` fast-path or three-way merge + `If-Match` CAS `PUT`) and converges the local `.tdf` file and `WorkspaceSyncState`.
   - If the external `.tdf` file contains a syntax or validation error (`TdfException` or `UnsupportedTdfVersionException`), `existingBoard` remains mounted on `HomeScreen` (`P-ATOMIC-STATE`), the external file on disk is never overwritten, `_lastFailedWatchDigest` records `disk.digest` to suppress duplicate error spam on unchanged bytes, and `_SyncErrorBanner` displays the localized error until a subsequent valid save succeeds.
   - If `TaskNotifier` was in `AsyncError` from a failed startup load (`existingBoard == null`) and the user repairs and saves the `.tdf` file externally, `reconcileExternalLocalChanges()` loads the repaired file and transitions `HomeScreen` automatically from `_ErrorStateView` to `AsyncData(converged)`.

### 1.5 Alternatives
1. **Direct `File(filePath).watch()`:** Rejected because `File.watch()` is unsupported on Windows (`ReadDirectoryChangesW` requires a directory handle) and detaches from the active path after a single atomic `.tmp` -> `rename()` save on Linux and Android (`inotify`).
2. **Periodic Timer Polling (`File.lastModified()` / `stat`):** Rejected because filesystem `mtime` has coarse granularity on several filesystems (violating `spec/TDF_SPEC_0.6.0.md` Section 6.7.2: *"Do not rely on filesystem `mtime` or inode numbers alone to detect concurrent external modifications"*), wastes wakeups when idle, and adds latency compared to kernel directory events.
3. **Bumping Binary Workspace Format to `TTW\x02` with an Extra Byte:** Rejected because the existing 6-bit `(storageMode, language, themeMode)` field in `TTW\x01`'s `flags` byte uses only `27` of `64` bit patterns (`0..2` per 2-bit lane), leaving `37` unused bit patterns (`>= 27`) that encode `localWatchEnabled == false` losslessly while keeping `localWatchEnabled == true` 100% bit-for-bit identical to existing 51-byte `TTW\x01` records.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules
All changes preserve `0` circular import SCCs and strict bottom-up layer rank ordering (`models < l10n < services < repositories < providers < ui < main`, `P-ACYCLIC-DAG`) with all `dart:io` symbols isolated in `lib/repositories/` (`P-IO-ISOLATION`):
* **Localization (`lib/l10n/`):**
  - `lib/l10n/app_en.arb` & `lib/l10n/app_de.arb` (plus generated `app_localizations*.dart` via `tiertask_dev.py l10n`): add `localWatchLabel` and `localWatchDescription`.
* **Domain Models (`lib/models/`):**
  - `lib/models/webdav_config.dart`: add `final bool localWatchEnabled` (`default: true`) to `WebDavConfig`, `copyWith`, `operator ==`, and `hashCode`.
  - `lib/models/app_workspace.dart`: encode and decode `localWatchEnabled` losslessly inside the 6-bit `(storageMode, language, themeMode)` lanes of the `TTW\x01` `flags` byte while preserving exact 51-byte default record size and `localWatchEnabled: true` backward compatibility.
* **Repositories (`lib/repositories/`):**
  - `lib/repositories/local_file_operations.dart`: add `matchesWatchedFileName`, `isRelevantWatchEvent`, and `watchTdfFile` wrapping `Directory(directoryPath).watch(recursive: false)` with `FileSystemException` error isolation and `AppLogger` instrumentation.
  - `lib/repositories/local_file_repository.dart`: add `Stream<void> watchTdfChanges()` returning `const Stream<void>.empty()` when `_useInMemoryFallback` is active or paths are invalid, and delegating to `_operations.watchTdfFile(...)` otherwise.
* **Providers (`lib/providers/`):**
  - `lib/providers/config_providers.dart`: add `Future<void> updateLocalWatchEnabled(bool localWatchEnabled)` on `WebDavConfigNotifier`.
  - `lib/providers/task_providers.dart`: scope `TaskNotifier.build()`'s configuration subscription via `webDavConfigProvider.selectAsync((value) => value.copyWith(localWatchEnabled: true))` (`P-SELECT-REBUILDS`), and add `Future<bool> reconcileExternalLocalChanges()`, `_lastFailedWatchDigest` deduplication/reset lifecycle, and post-wipe `localSourceDigest` persistence in `_executeWipe` when wiping the local file.
  - `lib/providers/local_file_watch_providers.dart` (**new**): define `LocalFileWatchTarget`, `localFileWatchDebounceProvider`, `localFileWatchTargetProvider`, `localFileWatcherProvider`, and `LocalFileWatcherNotifier`.
* **UI & Root (`lib/ui/`, `lib/main.dart`):**
  - `lib/ui/widgets/settings_local_storage_section.dart`: add `localWatchEnabled` (`default: true`) and `onLocalWatchEnabledChanged` to `LocalStorageSection` and render `_LocalWatchToggleRow` with `Switch(key: const ValueKey('settings_local_watch_switch'), ...)`.
  - `lib/ui/settings_screen.dart`: pass `localWatchEnabled: _preferences.localWatchEnabled` and `onLocalWatchEnabledChanged` (disabled while `_isTesting` is `true`) to `LocalStorageSection` and route `localWatchEnabled` changes in `_handlePreferenceChanged` to `notifier.updateLocalWatchEnabled(...)` without triggering a board reload.
  - `lib/main.dart`: watch `ref.watch(localFileWatcherProvider);` in `_TierTaskAppState.build`.
* **Tests (`test/`):**
  - `test/models/app_workspace_test.dart` & `test/models/tdf_v050_primitives_test.dart`
  - `test/repositories/local_file_repository_test.dart`
  - `test/providers/config_providers_test.dart`, `test/providers/task_providers_test.dart`, & `test/providers/local_file_watch_providers_test.dart` (**new**)
  - `test/ui/test_helpers.dart`, `test/ui/local_directory_picker_test.dart`, & `test/ui/settings_screen_test.dart`

### 2.2 TDF Schema, Localization & State Changes
* **`spec/TDF_SPEC_0.6.0.md`:** Unchanged. Uses `sourceDigest` (`TdfIdMigration.sha256Hex`) per Section 6.7.2 and guarded CAS merge per Sections 6.8.3–6.8.4.
* **Lossless `TTW\x01` Binary Persistence (`lib/models/app_workspace.dart`):**
  - Each of `storageMode.id`, `language.id`, and `themeMode.id` occupies `{0, 1, 2}` (`3 * 3 * 3 = 27` valid combinations).
  - When `config.localWatchEnabled` is `true` (default): `low6 = (storageMode.id & 0x03) | ((language.id & 0x03) << 2) | ((themeMode.id & 0x03) << 4)`. All three 2-bit lanes are `< 3`, producing the exact byte representation of existing `TTW\x01` records (`51` bytes for `AppWorkspace.defaultWorkspace`, `flags & 0x80 == 0` when `logStorageMode == StorageMode.local`).
  - When `config.localWatchEnabled` is `false`: compute `comboIndex = storageMode.id + (language.id * 3) + (themeMode.id * 9)` (`0..26`):
    - For `comboIndex < 16`: `low6 = 0x03 | (comboIndex << 2)` (lane `0` is `3`, bits `2..5` store `comboIndex` `0..15`).
    - For `comboIndex >= 16`: `rem = comboIndex - 16` (`0..10`), `low6 = (rem % 3) | 0x0C | ((rem ~/ 3) << 4)` (lane `0` is `0..2 != 3`, lane `1` is `3`, and `(rem % 3) + 3 * (rem ~/ 3)` recovers `rem` `0..10`).
  - During `_decodeRecord`:
    - Let `lane0 = flags & 0x03`, `lane1 = (flags >> 2) & 0x03`, `lane2 = (flags >> 4) & 0x03`.
    - If `lane0 < 3 && lane1 < 3 && lane2 < 3`: `localWatchEnabled = true`, `storageMode = StorageMode.fromId(lane0)`, `language = AppLanguage.fromId(lane1)`, `themeMode = AppThemeMode.fromId(lane2)`.
    - Else if `lane0 == 3`: `localWatchEnabled = false`, `comboIndex = (flags >> 2) & 0x0F` (`0..15`).
    - Else if `lane1 == 3`: `rem = lane0 + (lane2 * 3)`; if `rem > 10` throw corrupt payload; `localWatchEnabled = false`, `comboIndex = 16 + rem` (`16..26`).
    - Else (`lane2 == 3` with `lane0 < 3 && lane1 < 3`, unused reserved code): throw `WorkspaceErrorKind.corruptBinaryPayload`.
* **ARB Localization Keys (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`):**
  - `localWatchLabel`:
    - `en`: `"Watch for external file changes"`
    - `de`: `"Externe Dateiänderungen überwachen"`
  - `localWatchDescription`:
    - `en`: `"Automatically merge edits saved by external editors, scripts, or file-sync tools."`
    - `de`: `"Änderungen durch externe Editoren, Skripte oder Datei-Synchronisation automatisch zusammenführen."`

### 2.3 Implementation Details

#### 2.3.1 Repository Directory Stream (`lib/repositories/local_file_operations.dart`, `lib/repositories/local_file_repository.dart`)
* **`LocalFileOperations` methods:**
  - `bool matchesWatchedFileName(String candidatePath, String targetFileName, {required bool caseInsensitive})`: returns `false` immediately when `candidatePath.isEmpty || targetFileName.isEmpty` or when `candidatePath` ends with `/` (`0x2F`) or `\` (`0x5C`); slices the trailing basename segment in $O(N)$ via `lastIndexOf('/')` and `lastIndexOf(r'\')` without `.trim()`, `.split()`, or `defaultFileName` fallback (`P-ZERO-COPY`, `P-ZERO-ALLOC`); and compares via `caseInsensitive ? candidateName.toLowerCase() == targetFileName.toLowerCase() : candidateName == targetFileName`.
  - `bool isRelevantWatchEvent(FileSystemEvent event, String targetFileName, {required bool caseInsensitive})`: returns `false` if `event is FileSystemDeleteEvent`; returns `true` if `matchesWatchedFileName(event.path, targetFileName, caseInsensitive: caseInsensitive)`; if `event is FileSystemMoveEvent`, also checks `if (event.destination case final destination?)` with `matchesWatchedFileName(destination, targetFileName, caseInsensitive: caseInsensitive)`.
  - `Stream<void> watchTdfFile({required String directoryPath, required String targetFileName, required bool inMemory})`:
    - Returns `const Stream<void>.empty()` when `inMemory` or `!FileSystemEntity.isWatchSupported`.
    - Creates a single-subscription `StreamController<void>` whose `onListen` checks `Directory(directoryPath).existsSync()` inside `try / on FileSystemException`, subscribes to `directory.watch(recursive: false)` with `cancelOnError: false`, emits `null` when `isRelevantWatchEvent` returns `true` (passing `caseInsensitive: Platform.isWindows`), logs `local.watch.error` and closes the controller on stream error, and calls `unawaited(subscription?.cancel())` in `onCancel` so `FakeAsync` widget teardown never blocks on native I/O cancellation futures.
* **`LocalFileRepository.watchTdfChanges()` & Test Doubles (`test/ui/test_helpers.dart`):**
  - `LocalFileRepository.watchTdfChanges()` returns `const Stream<void>.empty()` when `_useInMemoryFallback` is `true` or `tryResolveFilePath()` / `tryResolveDirectoryPath()` returns `null`; otherwise delegates to `_operations.watchTdfFile(...)`.
  - `FakeLocalFileRepository` overrides `watchTdfChanges() => const Stream<void>.empty()` and `fileExists() => initialTdf.isNotEmpty`, and `FakeTaskNotifier` overrides `reconcileExternalLocalChanges() async => false`, preserving zero-I/O hermetic isolation across all widget test suites (`M-IO-TESTS`).

#### 2.3.2 Scoped Watcher Provider (`lib/providers/local_file_watch_providers.dart`)
* **`LocalFileWatchTarget`:**
  ```dart
  @immutable
  class LocalFileWatchTarget {
    const LocalFileWatchTarget({
      required this.workspaceId,
      required this.directoryPath,
      required this.fileName,
      required this.enabled,
    });

    final String? directoryPath;
    final bool enabled;
    final String? fileName;
    final String workspaceId;
    // value operator == and hashCode
  }
  ```
  `enabled` is `true` if and only if `config.localWatchEnabled && config.storageMode.usesLocal && config.isLocalConfigured && directoryPath != null && fileName != null`.
* **`localFileWatchDebounceProvider`:** `Provider<Duration>((ref) => LocalFileWatcherNotifier.defaultDebounce)` (`350 ms`).
* **`localFileWatchTargetProvider`:** Resolves the active `workspaceId` and `WebDavConfig` and extracts `(directoryPath, fileName)` via `localFileRepositoryProvider`. Because `LocalFileWatchTarget` implements value equality, changing `themeMode`, `themePalette`, `language`, `timeZoneMode`, `locationEnabled`, `diagnosticsEnabled`, `logLevel`, or `logStorageMode` does **not** rebuild `LocalFileWatcherNotifier` (`P-SELECT-REBUILDS`).
* **`LocalFileWatcherNotifier` (`Notifier<void>`):**
  - Holds `StreamSubscription<void>? _watchSubscription`, `Timer? _debounceTimer`, `AppLifecycleListener? _lifecycleListener`, `bool _streamClosed = false`, `int _watchGeneration = 0`, `String? _lastWorkspaceId`, and `bool? _lastEnabled`.
  - In `build()`: disposes prior resources, registers `ref.onDispose(_disposeResources)`, watches `target = ref.watch(localFileWatchTargetProvider)` and `debounce = ref.watch(localFileWatchDebounceProvider)`. Also listens to both `taskNotifierProvider.select((value) => value.hasValue)` and `syncStateProvider.select((sync) => sync.lastSyncedAt)` via `ref.listen` so if the parent directory did not exist at startup (`_streamClosed == true`) and is later created on initial load or on the first saved task (`writeTdfAtomicallySync`), `_bindWatchStream` re-subscribes immediately once `target.enabled && _streamClosed`.
  - Tracks `reEnabledInSameWorkspace = _lastWorkspaceId == target.workspaceId && _lastEnabled == false && target.enabled`, then updates `_lastWorkspaceId = target.workspaceId` and `_lastEnabled = target.enabled`.
  - When `!target.enabled`, increments `_watchGeneration` and returns without opening a `Directory.watch` handle or `AppLifecycleListener`.
  - When `target.enabled`, binds `_watchSubscription` to `ref.read(localFileRepositoryProvider).watchTdfChanges()` (`onData: (_) => _scheduleReconcile(generation, debounce)`, `onDone: () => _streamClosed = true`), registers `AppLifecycleListener(onStateChange: _handleLifecycleState)`, and when `reEnabledInSameWorkspace` is `true`, calls `_scheduleReconcile(generation, debounce)` so external batch edits saved while watching was disabled merge immediately.
  - On `AppLifecycleState.resumed`: if `_streamClosed`, re-invokes `_bindWatchStream`; schedules `_scheduleReconcile(generation, debounce)`.

#### 2.3.3 Digest-Gated Reconciliation & Settings Persistence (`lib/providers/config_providers.dart`, `lib/providers/task_providers.dart`)
* **`WebDavConfigNotifier.updateLocalWatchEnabled(bool localWatchEnabled)` & Scoped `TaskNotifier.build()` Watch:**
  - `WebDavConfigNotifier.updateLocalWatchEnabled` persists `current.copyWith(localWatchEnabled: localWatchEnabled)` via `updateConfig(...)`.
  - `TaskNotifier.build()` scopes its configuration dependency with `await ref.watch(webDavConfigProvider.selectAsync((value) => value.copyWith(localWatchEnabled: true)))` (`P-SELECT-REBUILDS`) so toggling `localWatchEnabled` never rebuilds `TaskNotifier`, never flashes `AsyncLoading()`, never clears `_pendingDeletedLabelTimestamps`, `_pendingDeletedLocationTimestamps`, or `_undoStack`, and performs zero redundant reloads.
* **`TaskNotifier.reconcileExternalLocalChanges()`:**
  - Guards `workspace != null`, `config.localWatchEnabled`, `config.storageMode.usesLocal`, `config.isLocalConfigured`, and `!(!state.hasValue && state.isLoading)`.
  - Awaits `_awaitInFlightSync()` and re-checks active `workspace.id` and `config.localWatchEnabled && config.storageMode.usesLocal && config.isLocalConfigured`.
  - Executes the pre-check I/O inside `try / on Object catch (error)` (so `LocalFileException` from `readTdfWithDigest()` on `> maxFileBytes`, invalid UTF-8, or permission-denied files logs `sync.watch.error`, sets `ref.read(syncStateProvider.notifier).setError(error.toString())`, preserves `existingBoard`, and returns `false` without throwing uncaught asynchronous errors):
    - Calls `disk = await ref.read(localFileRepositoryProvider).readTdfWithDigest()` and returns `false` if `!disk.exists || disk.content.trim().isEmpty`.
    - Loads `syncState = await ref.read(settingsRepositoryProvider).loadWorkspaceSyncState(workspace.id)`.
    - Returns `false` (clearing `_lastFailedWatchDigest = null`) if `disk.digest != null && disk.digest == syncState.localSourceDigest`.
    - Returns `false` if `disk.digest != null && disk.digest == _lastFailedWatchDigest`.
  - Runs `_executeExternalLocalReconcile` registered as `_inFlightSync`, preserving `existingBoard` and recording `_lastFailedWatchDigest = disk.digest` on error (`P-ATOMIC-STATE`), or clearing `_lastFailedWatchDigest = null` and updating `state = AsyncData(converged)` on success if `_mutationEpoch` and `workspace.id` remain current.
  - Also resets `_lastFailedWatchDigest = null` in `TaskNotifier.build()`, `selectLocalFile`, and `_executeWipe`.
* **`TaskNotifier._executeWipe`:**
  - When `!isRemote && config.storageMode.usesLocal`, reads `wipedDigest = (await ref.read(localFileRepositoryProvider).readTdfWithDigest()).digest` after `wipeTarget()` and persists `WorkspaceSyncState(localSourceDigest: wipedDigest)` so `wipeLocalFile` does not self-trigger an automatic watcher sync.

#### 2.3.4 Diagnostic Instrumentation (`AGENTS.md` Section 6)
All events use `AppLogger.event(...)` without logging task titles, notes, or credentials:
* `LogTag.storage`:
  - `local.watch.start` (`LogLevel.info`: `path`)
  - `local.watch.stop` (`LogLevel.debug`: `path`)
  - `local.watch.error` (`LogLevel.warn`: `path`, `error`)
* `LogTag.sync`:
  - `sync.watch.skip` (`LogLevel.debug`: `workspace`, `reason`: `'missing_or_empty'` | `'digest_unchanged'` | `'repeat_failed_digest'`)
  - `sync.watch.reconcile` (`LogLevel.info`: `workspace`, `mode`)
  - `sync.watch.error` (`LogLevel.warn`: `workspace`, `mode`, `error`)

### 2.4 Testing Strategy
Follow strict Red-Green-Refactor TDD (`P-TDD-FIRST`, `P-TEST-MIRROR`):
1. **`M-EXHAUSTIVE-STATE-TESTS` (`test/models/app_workspace_test.dart`, `test/models/tdf_v050_primitives_test.dart`, `test/providers/local_file_watch_providers_test.dart`, `test/providers/config_providers_test.dart`):**
   - Exhaustively round-trip `AppWorkspace` `TTW\x01` binary encoding across every combination of `localWatchEnabled` (`true`, `false`), `StorageMode` (`local`, `webdav`, `both`), `AppLanguage` (`system`, `english`, `german`), `AppThemeMode` (`system`, `light`, `dark`), `AppThemePalette` (`slate`, `navy`), `LogLevel`, and `logStorageMode`, verifying 51-byte default record size and corrupt reserved lane rejection (`lane2 == 3` or `rem > 10`).
   - Test every `StorageMode` (`local`, `webdav`, `both`) combined with `localWatchEnabled` (`true`, `false`), `false -> true` same-workspace catch-up reconciliation without `TaskBoard` `AsyncLoading()` reload or undo-stack reset, and every `AppLifecycleState` (`resumed`, `inactive`, `hidden`, `paused`, `detached`).
2. **`M-EXTREME-BOUND-TESTS` (`test/providers/local_file_watch_providers_test.dart`, `test/repositories/local_file_repository_test.dart`):**
   - Burst coalescing: `5` rapid external file writes within the debounce window execute `TaskSyncPipeline` exactly once with the final payload.
   - Empty/`0`-byte truncated file boundary and oversized (`maxFileBytes + 1`) external file boundary (`LocalFileException` caught during `readTdfWithDigest()` and surfaced in `SyncState.errorMessage` while preserving in-memory `TaskBoard`).
3. **`M-DELIM-INJECT-TESTS` (`test/providers/local_file_watch_providers_test.dart`):**
   - External `.tdf` save containing unclosed `{` braces, malformed directives, control characters, or unsupported TDF version (`tdf 9.9.9`): verify live in-memory `TaskBoard` and on-disk `.tdf` remain intact, `_SyncErrorBanner` receives the error, duplicate events with identical digest do not re-parse, and saving repaired `tdf 0.6.0` recovers, clears the error, and resets `_lastFailedWatchDigest`.
4. **`M-URI-PATH-EDGE-TESTS` (`test/repositories/local_file_repository_test.dart`):**
   - Verify basename matching across POSIX/Windows path separators, empty/root/trailing-separator paths (`''`, `'/'`, `'/dir/'` must not false-match `'tasks.tdf'`), trailing-space sibling filenames (`'tasks.tdf '`), case-sensitivity rules (`isRelevantWatchEvent` with `caseInsensitive: false` vs `true`), `..` traversal rejection returning `Stream.empty()`, dot-prefixed `.tmp` staging files, `.bak` backups, and dated `.log` files.
5. **`M-IO-TESTS` & UI Widget Tests (`test/repositories/local_file_repository_test.dart`, `test/providers/local_file_watch_providers_test.dart`, `test/ui/test_helpers.dart`, `test/ui/local_directory_picker_test.dart`, `test/ui/settings_screen_test.dart`):**
   - Real `Directory.systemTemp` tests covering direct `writeAsString`, same-directory atomic `.tmp` -> `rename`, cross-directory `rename`, missing parent directory creation after startup (including creation on first `addTask` save via `syncStateProvider.lastSyncedAt`), and runtime watched-directory deletion.
   - End-to-end `StorageMode.both` test with real `Directory.systemTemp` + loopback `HttpServer` (`HttpOverrides.global = null;` in `setUp()`) verifying external local edit -> automatic three-way merge with in-memory board -> WebDAV `PUT` upload -> zero self-trigger loop after Stage 2 local convergence, plus `wipeLocalFile` self-trigger suppression.
   - Widget tests in `test/ui/local_directory_picker_test.dart` and `test/ui/settings_screen_test.dart` verifying `ValueKey('settings_local_watch_switch')` defaults to `true`, appears in `Local` and `Both` modes, hides in `WebDAV` mode, disables during `_isTesting`, renders English and German labels, and persists `localWatchEnabled` when toggled without reloading `TaskBoard`.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [ ] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline.
- [ ] Add `localWatchLabel` and `localWatchDescription` via `python3 .agents/scripts/tiertask_dev.py l10n --set ...` (`app_en.arb`, `app_de.arb`, `flutter gen-l10n`).
- [ ] Write failing unit and widget tests first across `test/models/app_workspace_test.dart`, `test/models/tdf_v050_primitives_test.dart`, `test/repositories/local_file_repository_test.dart`, `test/providers/config_providers_test.dart`, `test/providers/local_file_watch_providers_test.dart`, `test/providers/task_providers_test.dart`, `test/ui/test_helpers.dart`, `test/ui/local_directory_picker_test.dart`, and `test/ui/settings_screen_test.dart` (TDD Red Phase — `P-TDD-FIRST`).
- [ ] Implement `WebDavConfig.localWatchEnabled`, `AppWorkspace` `TTW\x01` encoding, `LocalFileOperations` / `LocalFileRepository.watchTdfChanges`, `WebDavConfigNotifier.updateLocalWatchEnabled`, scoped `TaskNotifier.build()` config watch and `TaskNotifier.reconcileExternalLocalChanges`, `LocalFileWatcherNotifier`, `LocalStorageSection` toggle UI, and `TierTaskApp` watcher registration with `AppLogger` instrumentation (TDD Green & Refactor Phase).
- [ ] Update Parts 1 and 2 if implementation details evolve.
- [ ] Synchronize `ARCHITECTURE.md` (`python3 .agents/scripts/tiertask_dev.py arch --set lib/providers/local_file_watch_providers.dart --desc "..."` and `arch --sync-tree --audit`, plus `README.md` / `AGENTS.md` if applicable) per **`update-documentation`**.
- [ ] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix`.
- [ ] Add a user-facing `CHANGELOG.md` entry under `## [Unreleased]` per **`changelog-updater`**.
- [ ] Set `status: review`, update `BOARD.md`, and request user approval.
- [ ] After user approval, set `status: completed`, update `BOARD.md`, and record delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
* **2026-11-14:** Created `TEP-008` in `planned` status specifying `dart:io` `Directory.watch` parent-directory observation, `350 ms` trailing-edge debouncing, `WorkspaceSyncState.localSourceDigest` gating, non-destructive two-stage reconciliation in `Local` and `Both` storage modes, and a per-workspace `localWatchEnabled` toggle (`default: true`) in `LocalStorageSection` persisted losslessly in 51-byte `TTW\x01` workspace records.
* **2026-11-14:** Resolved 6 verification defects in `spec-verification-loop` Iteration 1: scoped `TaskNotifier.build()` via `webDavConfigProvider.selectAsync` to prevent board reloads on toggle, added `false -> true` catch-up reconciliation, rebound closed directory streams on `syncStateProvider.lastSyncedAt`, replaced `extractFileNameFromPath` with zero-alloc exact basename slicing in `matchesWatchedFileName`, guarded `readTdfWithDigest()` `LocalFileException` errors and `_lastFailedWatchDigest` resets in `reconcileExternalLocalChanges()`, and isolated `FakeLocalFileRepository` / `FakeTaskNotifier` in `test/ui/test_helpers.dart` while ordering `ARCHITECTURE.md` sync before `verify --full --fix`.

### 3.3 Delivered Artifacts
*(Complete upon approval)*
