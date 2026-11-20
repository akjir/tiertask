---
id: TEP-014
title: Robust Versioned JSON Settings Persistence, Split Credential Storage, and Deprecated TTW v2 Migration Converter
status: planned
type: architecture
created: 2026-11-20
updated: 2026-11-20
---

# TEP-014: Robust Versioned JSON Settings Persistence, Split Credential Storage, and Deprecated TTW v2 Migration Converter

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal replaces TierTask's bit-packed `TTW\x02` binary workspace settings storage inside `FlutterSecureStorage` with a split persistence architecture: versioned UTF-8 JSON (`settings.json`) in the host-local application data directory (with `HostFileLockManager` cross-process locking, atomic temp-file replacement, `.bak` backup rotation, and corruption quarantine) paired with per-workspace WebDAV password storage in `FlutterSecureStorage`. All `TTW\x01` code is removed completely. Read-only `TTW\x02` decoding is isolated into a dedicated `@Deprecated` converter module (`lib/models/legacy_ttw_v2_converter.dart`) that automatically migrates existing installations on first launch and is scheduled for complete removal no later than `0.5.0`.

### 1.2 Motivation
The current settings persistence in `lib/models/app_workspace.dart` (`TTW\x02`) and `lib/repositories/settings_repository.dart` (`SecureSettingsRepository`) has structural extensibility and reliability defects:

1. **Exhausted positional bit-packing:** `AppWorkspace` packs 17 `WebDavConfig` fields per workspace into a positional byte layout with no field names or tags. `localWatchEnabled == false` is multiplexed into unused bit states of `storageMode`, `language`, and `themeMode` via base-3 arithmetic; `themePalette` occupies 1 bit; `logStorageMode == StorageMode.both` is squeezed into the 11-bit UTC offset field (quantizing manual UTC offsets to 5-minute steps); and `logLevel` collapses `error` and `crash` into 2 bits. Adding any new setting or enum variant requires a wire-format version bump and error-prone bit shifts.
2. **All-or-nothing silent data loss:** `SecureSettingsRepository._readPersistedState` catches `Object` on any decode or validation failure (single corrupt byte, unknown enum ID, or future schema version) and silently returns `[AppWorkspace.defaultWorkspace]`. The next settings write permanently overwrites all workspaces and credentials.
3. **Unnecessary coupling of preferences to the OS keyring:** Storing non-secret workspace metadata and UI preferences in `FlutterSecureStorage` forces OS keyring reads/writes even for local-only workspaces (causing friction on minimal Linux desktops without an unlocked `libsecret` keyring), lacks cross-process file locking and `.bak` recovery, and rewrites every workspace password on every UI preference toggle.
4. **No concurrent write serialization:** Overlapping async calls to `saveConfig`, `createWorkspace`, `renameWorkspace`, `deleteWorkspace`, or `activateWorkspace` perform unlocked read-modify-write cycles and can lose updates.
5. **Android persistent directory gap:** `LocalFileOperations.resolveDefaultDirectoryPath` currently falls back to `Directory.systemTemp.path` when `XDG_DATA_HOME` and `HOME` are unset, which maps to `/data/user/0/<pkg>/cache` on Android (subject to OS cache eviction). Persistent `settings.json` on Android requires `Context.filesDir`.
6. **Obsolete `TTW\x01` code:** `TTW\x01` decoding is no longer needed in production code and adds dead version-branching complexity.

### 1.3 Goals & Non-Goals
- **Goals:**
  - Persist workspace lists, `activeWorkspaceId`, and all 16 non-secret `WebDavConfig` fields in a human-inspectable, versioned UTF-8 JSON file (`settings.json`, `schemaVersion: 1`) using `dart:convert` with zero new external dependencies (`P-STDLIB-FIRST`).
  - Persist WebDAV passwords exclusively in `FlutterSecureStorage`, keyed per workspace (`t2_webdav_pw_<workspaceId>` for release, `t2_dev_webdav_pw_<workspaceId>` for dev), and never write passwords to `settings.json` or `settings.json.bak`.
  - Avoid touching `FlutterSecureStorage` during normal reads, workspace switches, renames, or UI preference saves for workspaces without a stored WebDAV password (`hasWebDavPassword == false`).
  - Use `HostFileLockManager` for in-process FIFO serialization, cross-process OS locking, `0600` atomic temp-file replacement, and `.bak` backup rotation before overwriting valid settings.
  - Eliminate silent settings wipes: recover automatically from `settings.json.bak` when primary is corrupt, quarantine corrupt files (`settings.json.corrupt.<YYYYMMDDTHHMMSSZ>`) instead of overwriting them, refuse to overwrite unsupported future `schemaVersion > 1` files, perform per-field resilient decoding with safe defaults, and preserve unknown JSON keys across downgrades.
  - Resolve persistent platform-native app data directories across Linux, Windows, and Android (via Android `Context.filesDir` over a zero-dependency `MethodChannel`).
  - Remove all `TTW\x01` decoding logic and tests completely.
  - Remove all `TTW\x02` encoding logic (`encodePersistedState`, `toBytes`) from production code and encapsulate read-only `TTW\x02` decoding inside a single `@Deprecated` module (`lib/models/legacy_ttw_v2_converter.dart`) for automatic one-time migration until removal in `0.5.0`.
- **Non-Goals:**
  - Migrating or redesigning `WorkspaceSyncState` (`TTS\x04`, `t2_sync_v1_<id>`). Sync baseline storage remains unchanged in this proposal.
  - Changing `spec/TDF_SPEC_0.8.0.md` or `.tdf` file syntax, tier derivation, or WebDAV sync protocol.
  - Synchronizing `settings.json` across devices via WebDAV.
  - Adding third-party serialization, database, or path-provider packages (`shared_preferences`, `path_provider`, `hive`, `sqlite3`, `protobuf`).

### 1.4 Description

#### Storage Split & Platform Locations
Settings are split into two stores scoped by `AppBuildProfile` (`release` vs. `dev`):

1. **Settings JSON file (`settings.json`) and backup (`settings.json.bak`):**
   - **Linux:** `$XDG_DATA_HOME/<dirName>/settings.json`, falling back to `$HOME/.local/share/<dirName>/settings.json` (and `<systemTemp>/<dirName>/settings.json` only when both variables are unset), where `<dirName>` is `tiertask` (`release`) or `tiertask-dev` (`dev`).
   - **Windows:** `%APPDATA%\<dirName>\settings.json`, falling back to `%LOCALAPPDATA%\<dirName>\settings.json`, then `%USERPROFILE%\<dirName>\settings.json`.
   - **Android:** `<Context.filesDir>/<dirName>/settings.json` resolved via `MethodChannel('de.akjir.tiertask/app_storage')` (`getFilesDirectory`), guaranteeing private persistent storage (`/data/user/0/de.akjir.tiertask/files/tiertask/settings.json` for release; `/data/user/0/de.akjir.tiertask.dev/files/tiertask-dev/settings.json` for debug) that is immune to OS cache cleanup and excluded from cloud backups (`android:allowBackup="false"`).
2. **WebDAV passwords (`FlutterSecureStorage`):**
   - Key format: `${buildProfile.webdavPasswordKeyPrefix}${workspace.id}` (`t2_webdav_pw_<id>` for release, `t2_dev_webdav_pw_<id>` for dev).
   - Non-secret boolean `"hasWebDavPassword"` in each `settings.json` workspace object tracks whether a password key exists in `FlutterSecureStorage`. Workspaces with `hasWebDavPassword: false` never invoke `FlutterSecureStorage.read` or `write`.

#### Startup Recovery, Quarantine & User Feedback
On startup and on every settings read/mutation under the exclusive lock for `settings.json`:
1. **Valid primary `settings.json`:** Decoded with per-field validation. Missing optional fields silently use defaults; invalid field values (wrong JSON type, unknown enum token, out-of-range UTC offset) fall back to that field's default and emit a structured `[WARN]` `AppLogger` event (`settings.decode_warning`). Unrecognized root and workspace keys are preserved losslessly across subsequent saves.
2. **Unsupported future schema (`schemaVersion > 1`):** Never quarantined and never overwritten (whether encountered in `settings.json` or in `settings.json.bak` during fallback). Throws `WorkspaceException(WorkspaceErrorKind.unsupportedSettingsSchemaVersion, ...)`, surfacing a localized error view on `HomeScreen` advising the user to update TierTask.
3. **Non-regular filesystem entry (`settings.json` or `settings.json.bak` is a symlink, directory, pipe, or socket):** Never read, renamed/quarantined, deleted, or overwritten. Immediately logs `[ERROR] settings.invalid_file_type` and throws `WorkspaceException(WorkspaceErrorKind.settingsPersistenceFailed, ...)`.
4. **Corrupt regular primary `settings.json` (invalid UTF-8, malformed JSON, oversized `> 256 KiB`, `> 32` workspaces, invalid `schemaVersion < 1`, or zero valid workspaces):**
   - Atomically quarantined via same-directory rename to `settings.json.corrupt.<YYYYMMDDTHHMMSSZ>` (with `.001`..`.099` collision suffix). If all 100 slots exist or rename fails, `SecureSettingsRepository` throws `WorkspaceException(WorkspaceErrorKind.settingsPersistenceFailed, ...)` without modifying or deleting `settings.json`.
   - If regular `settings.json.bak` exists and decodes cleanly, it is restored atomically to `settings.json`, logged as `[WARN] settings.recovered_from_backup`, and surfaced once as a localized non-blocking `SnackBar` on `HomeScreen` (`en` / `de`).
   - If regular `settings.json.bak` exists with `schemaVersion > 1`, do not quarantine it; throw `WorkspaceException(WorkspaceErrorKind.unsupportedSettingsSchemaVersion, ...)`.
   - If `settings.json.bak` is missing or is also a corrupt regular file (quarantined to `settings.json.bak.corrupt.<YYYYMMDDTHHMMSSZ>`), TierTask does **not** invoke legacy `TTW\x02` migration; it atomically writes `PersistedSettingsDocument.initial` (default `Tasks` workspace) to `settings.json` (preventing subsequent reads from re-entering Case 6), logs `[ERROR] settings.corrupt_quarantined`, and surfaces a localized recovery `SnackBar` (`en` / `de`) noting that corrupt settings were backed up.
5. **Missing primary with existing `settings.json.bak`:**
   - If regular `settings.json.bak` decodes cleanly, restores `settings.json` atomically from `settings.json.bak`, logs `[WARN] settings.recovered_from_backup`, and records `SettingsRecoveryKind.recoveredFromBackup`.
   - If regular `settings.json.bak` has `schemaVersion > 1`, throws `WorkspaceException(WorkspaceErrorKind.unsupportedSettingsSchemaVersion, ...)` without quarantining or overwriting it.
   - If regular `settings.json.bak` is corrupt, quarantines it to `settings.json.bak.corrupt.<YYYYMMDDTHHMMSSZ>`, atomically writes `PersistedSettingsDocument.initial` to `settings.json` (without invoking legacy `TTW\x02` migration), logs `[ERROR] settings.corrupt_quarantined`, and records `SettingsRecoveryKind.resetAfterQuarantine`.
6. **Fresh install or automatic one-time `TTW\x02` migration:** Runs **only** when neither `settings.json` nor `settings.json.bak` existed before the read. `SecureSettingsRepository` checks `buildProfile.legacySettingsStorageKey` (`t2_settings_v1` / `t2_dev_settings_v1`) via the `@Deprecated` migration hook:
   - If absent (or if the OS keyring is unavailable on a fresh local-only install), TierTask initializes with `[AppWorkspace.defaultWorkspace]` in memory without failing startup.
   - If present, `LegacyTtwV2Converter.decodeTtwV2Bytes` decodes `TTW\x02` (`TTW\x01` is rejected without deleting `t2_settings_v1`). On success, non-empty passwords are written idempotently to `t2_webdav_pw_<id>`, `settings.json` is written atomically and read back through `SettingsCodec.decodeJsonBytes` to verify persistence, and only after verified write-and-readback is `t2_settings_v1` deleted from `FlutterSecureStorage` (preventing stale plaintext-equivalent passwords from remaining in the old blob). If any step before verified read-back fails, `t2_settings_v1` is left untouched for idempotent retry on next launch. If only the final deletion of `t2_settings_v1` fails after verified read-back, TierTask logs `[WARN] settings.legacy_migration.cleanup_failed` (`legacy_key_removed: false`) and returns the migrated state.

#### Write Safety & Keyring Failure Protection
- Every write acquires `HostFileLockManager.withExclusiveLock(settingsFilePath, ...)`, re-reads the current `PersistedSettingsDocument` (preserving `unknownRootFields` and `unknownWorkspaceFieldsById`), updates password keys in `FlutterSecureStorage` only when changed against the repository's in-memory session password cache (`_cachedPasswordsByWorkspaceId`), rotates the existing valid `settings.json` atomically to `settings.json.bak`, and atomically replaces `settings.json`.
- If `FlutterSecureStorage.read` fails on startup for a workspace with `hasWebDavPassword: true` (for example, a locked desktop keyring), TierTask logs `[ERROR] settings.secret.read_failed`, boots with `password: ''` so local tasks remain accessible, and records the workspace ID in `_unreadableSecretWorkspaceIds` so subsequent unrelated preference saves (`saveConfig` with `password == ''`) preserve `hasWebDavPassword: true` and do not delete the unreadable keyring entry. Both a later successful keyring read and a later successful non-empty password write remove the workspace ID from `_unreadableSecretWorkspaceIds`.

### 1.5 Alternatives
- **Versioned JSON inside `FlutterSecureStorage` (Option B):** Keeps all settings encrypted at rest in one key, but retains OS keyring coupling for local-only users, lacks cross-process locking and disk `.bak` recovery, and rewrites all workspace passwords on every UI preference change. Rejected in favor of Option A.
- **Custom TDF-style text DSL for settings:** Human-readable and stdlib-only, but requires maintaining a second custom parser/serializer for internal settings when `dart:convert` JSON is already built into the Dart SDK. Rejected.
- **Tagged binary (custom TLV, CBOR, or Protocol Buffers):** Eliminates bit-packing limits, but adds custom binary maintenance or external packages/codegen (`P-STDLIB-FIRST`) with no practical performance benefit for `<= 32` workspaces and no human inspectability for recovery. Rejected.
- **SQLite (`sqlite3` / `drift`) or `shared_preferences` / `hive`:** Introduces third-party or native dependencies (`P-STDLIB-FIRST`). SQLite is disproportionate for `<= 32` settings records; `shared_preferences` lacks cross-process locking and atomic multi-key writes. Rejected.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules
All imports strictly preserve `P-ACYCLIC-DAG` (`0: app_logger < 1: models < 2: l10n < 3: services < 4: repositories < 5: providers < 6: ui < 7: main`) and `P-IO-ISOLATION` (zero `dart:io` or `dart:ffi` outside `lib/repositories/`):

| Layer (Rank) | File | Change |
| :--- | :--- | :--- |
| Native Android | `android/app/src/main/kotlin/de/akjir/tiertask/MainActivity.kt` | Add `MethodChannel("de.akjir.tiertask/app_storage")` handling `getFilesDirectory` (`applicationContext.filesDir.absolutePath`). |
| Analyzer Config | `analysis_options.yaml` | Add temporary `analyzer.errors.deprecated_member_use_from_same_package: ignore` (keeping external `deprecated_member_use` fatal and preserving `P-NO-IGNORE` with zero `// ignore:` comments); remove in `0.5.0`. |
| Models (1) | `lib/models/app_build_profile.dart` | Replace `settingsStorageKey` with `@Deprecated` `legacySettingsStorageKey` (`t2_settings_v1` / `t2_dev_settings_v1`) and add `webdavPasswordKeyPrefix` (`t2_webdav_pw_` / `t2_dev_webdav_pw_`). |
| Models (1) | `lib/models/webdav_config.dart` | Add canonical lowercase `jsonValue` and `tryParseJson(String?)` on `AppLanguage`, `AppThemeMode`, `AppThemePalette`, `AppTimeZoneMode`, `DueLeadWindow`, and `StorageMode`. Remove obsolete `TTW\x02`-only numeric `id` and `fromId` members (moving `TTW\x02` ID lookup tables into `legacy_ttw_v2_converter.dart`). |
| Models (1) | `lib/models/app_workspace.dart` | Remove all `TTW\x01`/`TTW\x02` binary encoding and decoding methods (`encodePersistedState`, `decodePersistedState`, `toBytes`, `fromBytes`, bit-packing helpers). Replace `WorkspaceErrorKind.corruptBinaryPayload` with `corruptSettingsPayload`, `unsupportedSettingsSchemaVersion`, `credentialStorageUnavailable`, and `settingsPersistenceFailed`, and add optional `{this.cause}` to `WorkspaceException` (`P-ERR-PRESERVE`). |
| Models (1) | `lib/models/settings_codec.dart` *(new)* | Define `@immutable` `PersistedSettingsDocument`, `SettingsDecodeWarning`, `SettingsDecodeResult`, `SettingsRecoveryKind`, `SettingsRecoveryNotice`, and stateless `SettingsCodec` (`settingsFileName = 'settings.json'`, `encodeJson`, `decodeJsonBytes`, `currentSchemaVersion = 1`, `maxJsonBytes = 262144`, `maxJsonNestingDepth = 16`). |
| Models (1) | `lib/models/legacy_ttw_v2_converter.dart` *(new, `@Deprecated`)* | Encapsulated read-only `TTW\x02` binary decoder (`LegacyTtwV2Converter.decodeTtwV2Bytes`) containing private `TTW\x02` enum ID tables and strict version `0x02` validation (rejecting `TTW\x01` and all other versions). Scheduled for complete deletion in `0.5.0`. |
| Localization (2) | `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`, generated `lib/l10n/app_localizations*.dart`, `lib/l10n/tier_localization_extension.dart` | Add localized `en` and `de` strings for corrupt settings, unsupported future schema version, credential storage error, settings save failure, backup recovery notice, and quarantine reset notice; add a single exhaustive `localizeWorkspaceError(WorkspaceException)` helper on `AppLocalizations` in `tier_localization_extension.dart` (Rank 2) so both Rank 5 providers and Rank 6 UI share it without violating `P-ACYCLIC-DAG`. |
| Repositories (4) | `lib/repositories/settings_repository.dart` | Add `takeLastRecoveryNotice()` to `SettingsRepository` and `InMemorySettingsRepository`. Rewrite `SecureSettingsRepository` for split `settings.json` + per-workspace `FlutterSecureStorage` passwords with session password cache (`_cachedPasswordsByWorkspaceId`), `HostFileLockManager` locking + atomic writes + `.bak` rotation + quarantine, Android `MethodChannel` directory resolution, `@Deprecated` `_migrateLegacyTtwV2IfPresent()`, and `AppLogger` instrumentation. |
| Providers (5) | `lib/providers/workspace_providers.dart` | Add `settingsDirectoryPathProvider` (`Provider<String?>`, default `null`) and wire it into `settingsRepositoryProvider`. Keep `ActiveWorkspaceNotifier.build()` pure without synchronous cross-provider mutations. |
| Providers (5) | `lib/providers/config_providers.dart`, `lib/providers/task_providers.dart` | Delegate `WorkspaceException` localization to `localizations.localizeWorkspaceError(error)` so all `WorkspaceErrorKind` values map cleanly to localized messages. |
| UI (6) | `lib/ui/widgets/workspace_dialog.dart`, `lib/ui/settings_screen.dart`, `lib/ui/home_screen.dart` | Delegate workspace error localization to `localizations.localizeWorkspaceError(error)` across `workspace_dialog.dart`, `settings_screen.dart`, and `home_screen.dart`; catch `WorkspaceException` in `SettingsScreen._handlePreferenceChanged` (rolling back optimistic `_preferences` to `_lastSyncedConfig` and showing a localized error banner) and localize `WorkspaceException` in `_applyLocalFileUpdate` / `_executeStorageAction`; format `WorkspaceException` startup errors in `HomeScreen` `_LandingContentSwitcher` (invalidating `activeWorkspaceProvider` on retry when it is in `AsyncError`); consume `settingsRepositoryProvider.takeLastRecoveryNotice()` on `HomeScreen` via post-frame check in `initState` and `ref.listen(activeWorkspaceProvider, ...)` to display a one-shot Material 3 `SnackBar` without missing early loads. |
| Tests | `test/models/settings_codec_test.dart` *(new)*, `test/models/legacy_ttw_v2_converter_test.dart` *(new)*, `test/models/app_workspace_test.dart`, `test/models/app_build_profile_test.dart`, `test/models/location_state_test.dart`, `test/models/tdf_primitives_test.dart`, `test/services/base64_service_test.dart`, `test/repositories/settings_repository_test.dart`, `test/providers/config_providers_test.dart`, `test/providers/workspace_providers_test.dart`, `test/ui/settings_screen_test.dart`, `test/ui/home_screen_test.dart` | Add comprehensive Red-Green-Refactor test coverage for JSON codec, unknown-key preservation, per-field fallback, `TTW\x02` read-only converter and `TTW\x01` rejection, split credential storage, `.bak` recovery, quarantine, future-schema guard, concurrent write serialization, `SettingsScreen` persistence error rollback, and startup recovery UI notice. |

### 2.2 TDF Schema, Localization & State Changes

#### TDF Specification Impact
None. `spec/TDF_SPEC_0.8.0.md` is unaffected.

#### `settings.json` Canonical Schema (`schemaVersion: 1`)
```json
{
  "schemaVersion": 1,
  "activeWorkspaceId": "tasks",
  "workspaces": [
    {
      "id": "tasks",
      "name": "Tasks",
      "storageMode": "local",
      "localFilePath": "tasks.tdf",
      "serverUrl": "",
      "username": "",
      "filePath": "tasks.tdf",
      "hasWebDavPassword": false,
      "language": "system",
      "themeMode": "system",
      "themePalette": "slate",
      "locationEnabled": false,
      "timeZoneMode": "automatic",
      "manualTimeZoneOffsetMinutes": 0,
      "diagnosticsEnabled": false,
      "logLevel": "info",
      "logStorageMode": "local",
      "localWatchEnabled": true,
      "dueLeadWindow": "hours24"
    }
  ]
}
```

#### Enum Canonical JSON Tokens
- `StorageMode`: `"local"`, `"webdav"`, `"both"` (default `"local"`).
- `AppLanguage`: `"system"`, `"english"`, `"german"` (default `"system"`).
- `AppThemeMode`: `"system"`, `"light"`, `"dark"` (default `"system"`).
- `AppThemePalette`: `"slate"`, `"navy"` (default `"slate"`).
- `AppTimeZoneMode`: `"automatic"`, `"manual"` (default `"automatic"`).
- `DueLeadWindow`: `"off"`, `"hours12"`, `"hours24"`, `"days2"`, `"days3"`, `"days7"` (default `"hours24"`).
- `LogLevel` (persisted configurable values only): `"debug"`, `"info"`, `"warn"`, `"error"` (default `"info"`; `"crash"` or unknown tokens fall back to `LogLevel.info` with a decode warning).

#### Legacy Binary Persistence Changes (`TTW\x01`, `TTW\x02`, `TTS\x04`)
- **`TTW\x01`:** Removed completely from `lib/` and `test/` (except explicit negative test verifying `LegacyTtwV2Converter.decodeTtwV2Bytes` rejects header version `0x01`).
- **`TTW\x02`:** Write/encode support removed from `lib/`. Read-only decode moved into `@Deprecated` `lib/models/legacy_ttw_v2_converter.dart` and invoked solely by `@Deprecated` `SecureSettingsRepository._migrateLegacyTtwV2IfPresent()` when neither `settings.json` nor `settings.json.bak` exists. Removal target: `0.5.0`.
- **`TTS\x04`:** Unchanged (`lib/models/workspace_sync_state.dart`).

#### ARB Localization Keys (`lib/l10n/app_en.arb` & `lib/l10n/app_de.arb`)
| Key | English (`en`) | German (`de`) |
| :--- | :--- | :--- |
| `errorSettingsCorrupt` | `"Application settings could not be read."` | `"Anwendungseinstellungen konnten nicht gelesen werden."` |
| `errorSettingsUnsupportedVersion` | `"Settings were created by a newer TierTask version. Update TierTask to avoid data loss."` | `"Die Einstellungen wurden von einer neueren TierTask-Version erstellt. Aktualisiere TierTask, um Datenverlust zu vermeiden."` |
| `errorSettingsCredentialStorageUnavailable` | `"Secure credential storage is unavailable. WebDAV password could not be saved."` | `"Sicherer Anmeldedatenspeicher ist nicht verfügbar. Das WebDAV-Passwort konnte nicht gespeichert werden."` |
| `errorSettingsSaveFailed` | `"Could not save application settings."` | `"Anwendungseinstellungen konnten nicht gespeichert werden."` |
| `settingsRecoveredFromBackupNotice` | `"Settings were restored from backup after a file error."` | `"Einstellungen wurden nach einem Dateifehler aus der Sicherung wiederhergestellt."` |
| `settingsResetAfterQuarantineNotice` | `"Corrupt settings were backed up and reset to defaults."` | `"Beschädigte Einstellungen wurden gesichert und auf Standardwerte zurückgesetzt."` |

### 2.3 Implementation Details

#### 1. `lib/models/settings_codec.dart`
```dart
enum SettingsRecoveryKind { recoveredFromBackup, resetAfterQuarantine }

@immutable
class SettingsRecoveryNotice {
  const SettingsRecoveryNotice({
    required this.kind,
    this.quarantinedFilePath,
  });
  final SettingsRecoveryKind kind;
  final String? quarantinedFilePath;
}

@immutable
class SettingsDecodeWarning {
  const SettingsDecodeWarning({
    required this.field,
    required this.reason,
    this.workspaceId,
  });
  final String field;
  final String reason;
  final String? workspaceId;
}

@immutable
class PersistedSettingsDocument {
  /// Creates an immutable [PersistedSettingsDocument] wrapping all collections
  /// in unmodifiable views.
  factory PersistedSettingsDocument({
    required int schemaVersion,
    required String activeWorkspaceId,
    required List<AppWorkspace> workspaces,
    Set<String> passwordStoredWorkspaceIds = const <String>{},
    Map<String, Object?> unknownRootFields = const <String, Object?>{},
    Map<String, Map<String, Object?>> unknownWorkspaceFieldsById =
        const <String, Map<String, Object?>>{},
  });

  const PersistedSettingsDocument._({
    required this.schemaVersion,
    required this.activeWorkspaceId,
    required this.workspaces,
    this.passwordStoredWorkspaceIds = const <String>{},
    this.unknownRootFields = const <String, Object?>{},
    this.unknownWorkspaceFieldsById = const <String, Map<String, Object?>>{},
  });

  static const PersistedSettingsDocument initial = PersistedSettingsDocument._(
    schemaVersion: SettingsCodec.currentSchemaVersion,
    activeWorkspaceId: AppWorkspace.defaultId,
    workspaces: <AppWorkspace>[AppWorkspace.defaultWorkspace],
  );
  // Final unmodifiable fields; copyWith; == and hashCode.
}

@immutable
class SettingsDecodeResult {
  const SettingsDecodeResult({
    required this.document,
    this.warnings = const <SettingsDecodeWarning>[],
  });
  final PersistedSettingsDocument document;
  final List<SettingsDecodeWarning> warnings;
}

class SettingsCodec {
  const SettingsCodec._();

  static const int currentSchemaVersion = 1;
  static const int maxJsonBytes = 262144;
  static const int maxJsonNestingDepth = 16;
  static const String settingsFileName = 'settings.json';

  static SettingsDecodeResult decodeJsonBytes(List<int> bytes);
  static String encodeJson(PersistedSettingsDocument document);
}
```
Key codec invariants:
- `decodeJsonBytes` validates `bytes.isNotEmpty && bytes.length <= maxJsonBytes` BEFORE UTF-8 or JSON decoding (`P-BOUND-ALLOC`).
- Strict UTF-8 decoding (`const Utf8Codec(allowMalformed: false)`) rejects invalid byte sequences.
- Root must be a JSON object (`Map<String, Object?>`). `schemaVersion` must be an `int >= 1`; if `schemaVersion > currentSchemaVersion`, throws `WorkspaceException(WorkspaceErrorKind.unsupportedSettingsSchemaVersion, ...)`.
- Root `workspaces` must be a non-empty `List` with `1 <= workspaces.length <= AppWorkspace.maxWorkspaces` (`32`); missing, non-list, empty, or `> 32` entries throw `WorkspaceException(WorkspaceErrorKind.corruptSettingsPayload, ...)` so `.bak` recovery triggers without silently dropping workspaces.
- Each workspace entry must be a JSON object whose `id` is a non-empty trimmed string without control characters and unique among previously accepted entries, and whose `name` passes `AppWorkspace.validateName`. Missing, empty, or wrong-typed `localFilePath` or `filePath` values fall back to `AppWorkspace.defaultFileName` (`tasks.tdf`) with a `SettingsDecodeWarning` before running `AppWorkspace.validateConfigPaths`. Malformed or colliding individual workspace entries emit a `SettingsDecodeWarning` and are skipped; if zero valid workspaces remain, `decodeJsonBytes` throws `WorkspaceException(WorkspaceErrorKind.corruptSettingsPayload, ...)`.
- `decodeJsonBytes` trims `serverUrl` and `username` (falling back to `''` with a `SettingsDecodeWarning` on wrong type) and always passes an explicit non-null `storageMode` (defaulting to `StorageMode.local` if missing or invalid) so `WebDavConfig`'s implicit credential-based constructor fallback never overrides a stored `storageMode`. Passwords stored in `FlutterSecureStorage` are never trimmed.
- Every individual preference field (`storageMode`, `language`, `themeMode`, `themePalette`, `locationEnabled`, `timeZoneMode`, `manualTimeZoneOffsetMinutes`, `diagnosticsEnabled`, `logLevel`, `logStorageMode`, `localWatchEnabled`, `dueLeadWindow`, `serverUrl`, `username`, `hasWebDavPassword`) falls back independently to its `WebDavConfig` default (`hasWebDavPassword: false`) on wrong JSON type, unknown enum token, or out-of-range integer (`manualTimeZoneOffsetMinutes` outside `-720..840`), emitting a `SettingsDecodeWarning`.
- `encodeJson` never emits `"password"`, strips any accidental `"password"` key from `unknownWorkspaceFieldsById`, merges preserved `unknownRootFields` and `unknownWorkspaceFieldsById` deterministically without overriding known keys, formats with `const JsonEncoder.withIndent('  ')` + trailing `\n`, and enforces encoded UTF-8 byte length `<= maxJsonBytes` (throwing `WorkspaceException(WorkspaceErrorKind.corruptSettingsPayload, ...)` if exceeded).
- Preserved unknown JSON values are validated for strict JSON types (`null`, `bool`, `int`, finite `double`, `String`, `List`, `Map<String, Object?>`) and nesting depth `<= maxJsonNestingDepth` (omitting non-compliant unknown values with a `SettingsDecodeWarning`), and wrapped in unmodifiable containers (`List.unmodifiable`, `Map.unmodifiable`).

#### 2. `lib/models/legacy_ttw_v2_converter.dart` (`@Deprecated`, remove in `0.5.0`)
```dart
@Deprecated(
  'Read-only TTW\\x02 migration converter for pre-0.4.0 settings. '
  'Scheduled for removal in 0.5.0.',
)
class LegacyTtwV2Converter {
  const LegacyTtwV2Converter._();

  static const int maxBinaryBytes = 65536;

  @Deprecated(
    'Read-only TTW\\x02 migration decoder. Scheduled for removal in 0.5.0.',
  )
  static ({List<AppWorkspace> workspaces, String activeId}) decodeTtwV2Bytes(
    List<int> bytes,
  );
}
```
Key invariants:
- Strictly accepts 6-byte header `TTW\x02` (`bytes[0..3] == [0x54, 0x54, 0x57, 0x02]`). Explicitly rejects `TTW\x01` and all other versions with `WorkspaceException(WorkspaceErrorKind.corruptSettingsPayload, ...)`.
- Contains private `TTW\x02` integer-to-enum decoders (`_storageModeFromV2Id`, `_languageFromV2Id`, `_themeModeFromV2Id`, `_themePaletteFromV2Id`, `_timeZoneModeFromV2Id`, `_dueLeadWindowFromV2Id`, `_decodeLogLevelBits`, `_decodeLowFlagsBits`, `_decodeOffsetAndLogStorage`) so `webdav_config.dart` has zero binary ID coupling.
- Contains zero encode methods.

#### 3. `lib/repositories/settings_repository.dart`
`SecureSettingsRepository` constructor:
```dart
class SecureSettingsRepository implements SettingsRepository {
  SecureSettingsRepository({
    FlutterSecureStorage? storage,
    AppBuildProfile? buildProfile,
    String? settingsDirectoryPath,
    String? hostLockDirectoryOverride,
    DateTime Function()? clock,
    Future<String?> Function()? androidFilesDirectoryResolver,
    Duration lockAcquireTimeout = HostFileLockManager.defaultLockAcquireTimeout,
  });
}
```
Key repository invariants:
- **Locking & serialization:** Uses `HostFileLockManager<WorkspaceException>` with `createException: (message, {cause}) => WorkspaceException(WorkspaceErrorKind.settingsPersistenceFailed, message, cause: cause)`. Every public method (`loadActiveWorkspace`, `loadConfig`, `loadWorkspaceSummaries`, `activateWorkspace`, `createWorkspace`, `deleteWorkspace`, `renameWorkspace`, `saveConfig`) runs its file read/migration/recovery/write critical section inside `_lockManager.withExclusiveLock(settingsFilePath, () async { ... })`.
- **File path resolution:** Resolves and caches `<settingsDir>/settings.json` once. If `settingsDirectoryPath` is provided, uses it directly; else on Android invokes `androidFilesDirectoryResolver` (defaulting to `MethodChannel('de.akjir.tiertask/app_storage').invokeMethod<String>('getFilesDirectory')`) and joins `buildProfile.dataDirectoryName` (throwing `WorkspaceException(WorkspaceErrorKind.settingsPersistenceFailed, ...)` if the channel throws or returns null/empty, never silently falling back to Android `cacheDir`); else uses `LocalFileRepository.resolveDefaultDirectoryPath(buildProfile: buildProfile)`.
- **File type & bound checks:** Inspects `FileSystemEntity.typeSync(path, followLinks: false)` before reading `settings.json` or `settings.json.bak`. If `directory`, `link`, `pipe`, or `unixDomainSock`, logs `[ERROR] settings.invalid_file_type` and throws `WorkspaceException(WorkspaceErrorKind.settingsPersistenceFailed, ...)` without reading, renaming, deleting, or overwriting it. For regular files, enforces `File(path).lengthSync() <= SettingsCodec.maxJsonBytes` before `readAsBytesSync()` (oversized regular files trigger quarantine + recovery).
- **Quarantine before recovery:** Corrupt regular files are moved via `File(corruptPath).renameSync(quarantinePath)` where `quarantinePath` is `<filePath>.corrupt.<YYYYMMDDTHHMMSSZ>` (using UTC `clock()` with `.001`..`.099` collision suffixes). If all 100 slots exist or `renameSync` fails, throws `WorkspaceException(WorkspaceErrorKind.settingsPersistenceFailed, ...)` without modifying or deleting the source file. When quarantine recovery resets to defaults (no valid backup), `_lockManager.writeAtomically(settingsFilePath, ...)` immediately persists `PersistedSettingsDocument.initial` so subsequent reads load valid `settings.json` and never re-enter legacy `TTW\x02` migration.
- **Backup rotation:** Before replacing `settings.json`, if existing `settings.json` is a regular file whose bytes pass `SettingsCodec.decodeJsonBytes`, writes those bytes atomically to `settings.json.bak` via `_lockManager.writeAtomically(backupPath, existingBytes)`.
- **Secret split, session cache & ordering:**
  - Maintains an in-memory per-repository session map `_cachedPasswordsByWorkspaceId` (`Map<String, String>`) and `_unreadableSecretWorkspaceIds` (`Set<String>`), neither serialized nor logged.
  - `loadActiveWorkspace` / `activateWorkspace`: when `document.passwordStoredWorkspaceIds.contains(workspace.id)`, uses `_cachedPasswordsByWorkspaceId[workspace.id]` if populated (avoiding redundant keyring reads on immediate post-save reloads such as `ActiveWorkspaceNotifier.updateActiveConfig`); otherwise reads `${buildProfile.webdavPasswordKeyPrefix}${workspace.id}` from `FlutterSecureStorage`. On successful read, stores in `_cachedPasswordsByWorkspaceId` and removes `workspace.id` from `_unreadableSecretWorkspaceIds`. On missing/null value, logs `[WARN] settings.secret.missing` and caches `''`. On keyring read exception, logs `[ERROR] settings.secret.read_failed`, marks `workspace.id` in `_unreadableSecretWorkspaceIds`, and returns `password: ''` so local mode remains operable without risking password deletion on unrelated UI toggles.
  - `saveConfig`: compares `config.password` against `_cachedPasswordsByWorkspaceId[activeId]` and `document.passwordStoredWorkspaceIds.contains(activeId)`:
    - If `config.password.isNotEmpty`: writes to `${buildProfile.webdavPasswordKeyPrefix}$activeId` only when not equal to the cached value or not yet marked stored; on success updates `_cachedPasswordsByWorkspaceId[activeId] = config.password`, removes `activeId` from `_unreadableSecretWorkspaceIds`, and sets `hasWebDavPassword: true`. If `FlutterSecureStorage.write` throws, logs `[ERROR] settings.secret.write_failed` and throws `WorkspaceException(WorkspaceErrorKind.credentialStorageUnavailable, ...)` without modifying `settings.json`.
    - If `config.password.isEmpty`: if `_unreadableSecretWorkspaceIds.contains(activeId)`, preserves `hasWebDavPassword: true` and does not touch `FlutterSecureStorage`; else if `document.passwordStoredWorkspaceIds.contains(activeId)`, deletes `${buildProfile.webdavPasswordKeyPrefix}$activeId` before writing `settings.json`, removes `activeId` from `_cachedPasswordsByWorkspaceId`, and sets `hasWebDavPassword: false`.
  - `createWorkspace`: writes non-empty password to `${buildProfile.webdavPasswordKeyPrefix}${created.id}` and caches it before atomically writing `settings.json`.
  - `deleteWorkspace`: removes workspace from `settings.json` first (including `unknownWorkspaceFieldsById` and `passwordStoredWorkspaceIds`), removes `targetId` from `_cachedPasswordsByWorkspaceId` and `_unreadableSecretWorkspaceIds`, then best-effort deletes `${buildProfile.webdavPasswordKeyPrefix}${targetId}` and `${buildProfile.syncStorageKeyPrefix}${targetId}`.
  - `loadWorkspaceSummaries`: reads only `settings.json` with zero `FlutterSecureStorage` calls.
- **One-time `@Deprecated` `TTW\x02` migration:** Runs inside the exclusive lock **only** when neither `settings.json` nor `settings.json.bak` existed prior to the read. Decodes `buildProfile.legacySettingsStorageKey` via `Base64Service(maxInputBytes: LegacyTtwV2Converter.maxBinaryBytes)` and `LegacyTtwV2Converter.decodeTtwV2Bytes`, writes non-empty passwords idempotently under `${buildProfile.webdavPasswordKeyPrefix}${w.id}` (updating `_cachedPasswordsByWorkspaceId`), writes `settings.json` atomically, verifies read-back via `SettingsCodec.decodeJsonBytes`, and only then attempts deleting `buildProfile.legacySettingsStorageKey` (if that final cleanup delete throws, logs `[WARN] settings.legacy_migration.cleanup_failed` and still returns the verified migrated document).

#### 4. Structured Diagnostic Logging (`AGENTS.md` Section 6)
All events use `LogTag.storage`, never log passwords, raw `Authorization` headers, or raw file payloads, and use static obfuscation-safe `reason` codes (never `runtimeType.toString()`):
- `settings.load` (`debug`): `workspace_count`, `active_id`, `schema_version`
- `settings.save` (`debug`): `workspace_count`, `active_id`, `backup_rotated`, `secret_updated`
- `settings.decode_warning` (`warn`): `workspace_id`, `field`, `reason`
- `settings.invalid_file_type` (`error`): `target` (`primary` | `backup`), `entity_type`
- `settings.recovered_from_backup` (`warn`): `quarantined_path`, `workspace_count`
- `settings.corrupt_quarantined` (`error`): `quarantined_path`, `fallback`
- `settings.schema_unsupported` (`error`): `found_version`, `supported_version`
- `settings.secret.read_failed` (`error`): `workspace_id`, `reason` (`platform_exception` | `missing_plugin` | `unexpected_error`), optional `code`
- `settings.secret.missing` (`warn`): `workspace_id`
- `settings.secret.write_failed` (`error`): `workspace_id`, `operation` (`write` | `delete`), `reason`, optional `code`
- `settings.legacy_migration.completed` (`info`): `workspace_count`, `migrated_passwords`, `legacy_key_removed`
- `settings.legacy_migration.cleanup_failed` (`warn`): `reason`, optional `code`
- `settings.legacy_migration.failed` (`error`): `error_kind`
- `settings.legacy_migration.keyring_unavailable` (`warn`): `reason`, optional `code`

#### 5. Scheduled `0.5.0` Removal Checklist (Encapsulated `TTW\x02` Cleanup)
When removing deprecated `TTW\x02` support (no later than `0.5.0`):
1. Delete `lib/models/legacy_ttw_v2_converter.dart` and `test/models/legacy_ttw_v2_converter_test.dart`.
2. Remove `AppBuildProfile.legacySettingsStorageKey` from `lib/models/app_build_profile.dart` and its assertions in `test/models/app_build_profile_test.dart`.
3. Remove `_migrateLegacyTtwV2IfPresent()` and its single call site in `lib/repositories/settings_repository.dart`, plus the legacy migration test group in `test/repositories/settings_repository_test.dart`.
4. Remove `deprecated_member_use_from_same_package: ignore` from `analysis_options.yaml`.
5. Remove `legacy_ttw_v2_converter.dart` from `ARCHITECTURE.md` and run `python3 .agents/scripts/tiertask_dev.py verify --full --fix`.

### 2.4 Testing Strategy
Follow strict Red-Green-Refactor TDD (`P-TDD-FIRST`) across all applicable mandatory categories:

1. **`test/models/settings_codec_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`):**
   - Exhaustive JSON round-trip of every variant of `StorageMode`, `AppLanguage`, `AppThemeMode`, `AppThemePalette`, `AppTimeZoneMode`, `DueLeadWindow`, configurable `LogLevel` (`debug`, `info`, `warn`, `error`), `logStorageMode`, `localWatchEnabled`, `locationEnabled`, `diagnosticsEnabled`, and all 37 standard UTC offsets plus 1-minute manual offset precision (`+63` min with `logStorageMode: StorageMode.both`).
   - Defense-in-depth secret hygiene: `encodeJson` never emits `"password"` even when `WebDavConfig.password` is non-empty or `"password"` is injected into `unknownWorkspaceFieldsById`.
   - Unknown field preservation: unrecognized root keys and per-workspace keys (scalars, nested lists/maps up to depth 16) survive encode/decode cycles; depth > 16 or non-finite numbers are safely rejected/sanitized.
   - Per-field resilient decoding: invalid enum strings, `"crash"` log level, wrong JSON types, out-of-range UTC offsets, and invalid `activeWorkspaceId` fall back per-field with `SettingsDecodeWarning` without dropping valid workspaces; invalid/duplicate workspace entries are skipped unless 0 valid workspaces remain (which throws `corruptSettingsPayload`).
   - Schema version gating: missing/`0`/non-int `schemaVersion` throws `corruptSettingsPayload`; `schemaVersion: 2` throws `unsupportedSettingsSchemaVersion`.
   - Bounds & malformed inputs: `0` bytes, invalid UTF-8, truncated JSON, `32` vs. `33` workspaces, `maxJsonBytes` exact boundary (`262144` passes, `262145` throws `corruptSettingsPayload`), quote/escape/newline/control-character strings.
2. **`test/models/legacy_ttw_v2_converter_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`):**
   - Test-only `TTW\x02` fixture builder and hardcoded golden `0.3.0` byte vectors verify lossless read-only decoding across all flag combinations (`localWatchEnabled: true/false`, all `StorageMode`/`AppLanguage`/`AppThemeMode`/`AppThemePalette`/`AppTimeZoneMode`/`DueLeadWindow`/`LogLevel`/`logStorageMode` combinations, multi-workspace, Unicode names and special-character passwords).
   - Explicitly verifies `TTW\x01` payloads (header byte `0x01`) are rejected with `WorkspaceErrorKind.corruptSettingsPayload`.
   - Verifies truncated headers, trailing bytes, invalid UTF-8, duplicate IDs/names/paths, invalid `DueLeadWindow` byte (`> 5`), and payloads exceeding `65536` bytes throw `corruptSettingsPayload`.
3. **`test/repositories/settings_repository_test.dart` (`M-IO-TESTS`, `M-URI-PATH-EDGE-TESTS`, `M-REAL-MECHANICS-TESTS`):**
   - Hermetic `Directory.systemTemp` tests verifying split persistence (`settings.json` on disk has zero passwords; `t2_webdav_pw_<id>` / `t2_dev_webdav_pw_<id>` in fake `FlutterSecureStorage` stores passwords including quotes, backslashes, and Unicode).
   - Zero-keyring-touch guarantee: local-only workspaces (`hasWebDavPassword: false`) never invoke `FlutterSecureStorage.read` or `write` across load, rename, switch, preference toggles, and summaries; UI preference toggles on WebDAV workspaces with unchanged password perform zero keyring writes.
   - Locked-keyring resilience: simulated `FlutterSecureStorage.read` throw on startup logs error, boots with `password: ''`, and subsequent unrelated `saveConfig` does NOT clear `hasWebDavPassword: true` or delete the keyring key; simulated `FlutterSecureStorage.write` throw on password save throws `credentialStorageUnavailable` without mutating `settings.json`.
   - Backup rotation & corruption recovery: second save rotates valid `settings.json` to `settings.json.bak`; corrupting `settings.json` quarantines it to `settings.json.corrupt.<timestamp>`, restores from `settings.json.bak`, and records `SettingsRecoveryKind.recoveredFromBackup`; corrupting both primary and backup (or missing primary with corrupt backup) quarantines the corrupt file(s), atomically persists `PersistedSettingsDocument.initial` to `settings.json` without triggering legacy `TTW\x02` migration, and records `SettingsRecoveryKind.resetAfterQuarantine`.
   - Unsupported future schema (`schemaVersion: 2`): throws `unsupportedSettingsSchemaVersion` whether present in `settings.json` or in `settings.json.bak` during fallback, leaves files byte-for-byte untouched, and creates no quarantine file.
   - Symlink & directory defense: replacing `settings.json` with a symlink or directory rejects safely without following or clobbering target.
   - Concurrent read-modify-write serialization (`M-REAL-MECHANICS-TESTS`): concurrent `Future.wait` calls (`createWorkspace` + `saveConfig` + `renameWorkspace`) serialize via `HostFileLockManager` with zero lost updates.
   - Automatic one-time `TTW\x02` migration: converts `t2_settings_v1` (`TTW\x02`) into `settings.json` + per-workspace `t2_webdav_pw_<id>`, verifies read-back, removes `t2_settings_v1`; verifies failed migration leaves `t2_settings_v1` intact; verifies `TTW\x01` is rejected without deleting `t2_settings_v1`; verifies dev/release profile isolation (`tiertask` vs. `tiertask-dev`, `t2_webdav_pw_` vs. `t2_dev_webdav_pw_`).
   - Android `filesDir` resolver callback verification: verifies Android path resolution joins resolved `filesDir` + `buildProfile.dataDirectoryName` + `settings.json`, and fails with `settingsPersistenceFailed` (never falling back to `cacheDir`) when the resolver returns null/empty or throws.
   - Legacy migration cleanup resilience: verifies that if deleting `t2_settings_v1` throws after `settings.json` is written and verified, migration succeeds with `settings.legacy_migration.cleanup_failed` warning and next load reads `settings.json` directly.
4. **`test/providers/workspace_providers_test.dart`, `test/providers/config_providers_test.dart`, `test/ui/settings_screen_test.dart`, `test/ui/home_screen_test.dart` (`M-REAL-MECHANICS-TESTS`):**
   - Verifies `HomeScreen` consumes `settingsRepositoryProvider.takeLastRecoveryNotice()` both when `activeWorkspaceProvider` resolves before `HomeScreen` mounts and when it resolves asynchronously after mount, rendering the localized `SnackBar` once.
   - Verifies `HomeScreen` displays the localized `errorSettingsUnsupportedVersion` error view when `activeWorkspaceProvider` fails with `unsupportedSettingsSchemaVersion`, invalidating `activeWorkspaceProvider` on retry without overwriting `settings.json`.
   - Verifies `SettingsScreen` catches `WorkspaceException` (`credentialStorageUnavailable`, `settingsPersistenceFailed`) in `_handlePreferenceChanged` (rolling back optimistic `_preferences` to `_lastSyncedConfig`) and displays localized error banners in `_applyLocalFileUpdate` / `_executeStorageAction`.
   - Verifies `test/services/base64_service_test.dart`, `test/models/app_workspace_test.dart`, `test/models/location_state_test.dart`, `test/models/tdf_primitives_test.dart`, `test/models/app_build_profile_test.dart`, and `test/providers/config_providers_test.dart` replace obsolete `TTW\x01`/`encodePersistedState`/numeric `fromId` assertions with `SettingsCodec` and `jsonValue`/`tryParseJson` assertions.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [ ] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline.
- [ ] Write failing unit and widget tests first in `test/models/settings_codec_test.dart`, `test/models/legacy_ttw_v2_converter_test.dart`, `test/repositories/settings_repository_test.dart`, `test/providers/workspace_providers_test.dart`, `test/ui/settings_screen_test.dart`, and `test/ui/home_screen_test.dart` (TDD Red Phase, `P-TDD-FIRST`).
- [ ] Implement model changes (`lib/models/webdav_config.dart`, `lib/models/app_build_profile.dart`, `lib/models/app_workspace.dart`, `lib/models/settings_codec.dart`, `@Deprecated` `lib/models/legacy_ttw_v2_converter.dart`) and remove all `TTW\x01` code and `TTW\x02` encoders (TDD Green Phase).
- [ ] Add Android `de.akjir.tiertask/app_storage` (`getFilesDirectory`) channel in `android/app/src/main/kotlin/de/akjir/tiertask/MainActivity.kt` and update `analysis_options.yaml` with temporary `deprecated_member_use_from_same_package: ignore`.
- [ ] Implement split `settings.json` + per-workspace `FlutterSecureStorage` persistence, `HostFileLockManager` locking, `.bak` rotation, quarantine, `@Deprecated` `TTW\x02` migration, and `AppLogger` instrumentation in `lib/repositories/settings_repository.dart`.
- [ ] Add `en`/`de` ARB keys in `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb`, run `python3 .agents/scripts/tiertask_dev.py l10n`, and wire recovery notices, `SettingsScreen` rollback/error localization, and `HomeScreen` startup error formatting in `lib/providers/` and `lib/ui/`.
- [ ] Update existing tests (`app_workspace_test.dart`, `app_build_profile_test.dart`, `location_state_test.dart`, `tdf_primitives_test.dart`, `base64_service_test.dart`, `config_providers_test.dart`) to remove `TTW\x01` / `encodePersistedState` references.
- [ ] Update Parts 1 and 2 if the implementation changes the design.
- [ ] Run `python3 .agents/scripts/tiertask_dev.py arch --sync-tree` and `python3 .agents/scripts/tiertask_dev.py verify --full --fix`.
- [ ] Follow **`update-documentation`** to synchronize `README.md`, `ARCHITECTURE.md`, and `AGENTS.md` as applicable.
- [ ] Follow **`changelog-updater`** to add a `CHANGELOG.md` entry under `## [Unreleased]`.
- [ ] Set `status: review`, update `BOARD.md`, and request user approval.
- [ ] After user approval, set `status: completed`, update `BOARD.md`, and list delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
- **2026-11-20:** Drafted `TEP-014` (`status: planned`) specifying Option A split persistence (`settings.json` + per-workspace `FlutterSecureStorage` passwords), full Section 3 robustness hardening, complete `TTW\x01` removal, Android `Context.filesDir` channel resolution, and encapsulated `@Deprecated` read-only `TTW\x02` migration converter scheduled for removal no later than `0.5.0`.

### 3.3 Delivered Artifacts
*(Complete upon approval)*
