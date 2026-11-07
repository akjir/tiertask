# TierTask

> [!IMPORTANT]
> **Disclaimer:** `TierTask` is strictly a private, personal project developed for individual use. It is provided without any warranty, official support, or maintenance guarantees.

`TierTask` is a Flutter task manager for Linux, Android, and Windows that dynamically derives six priority and status tiers (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) from a single local or WebDAV-synchronized `.tdf` file (`tasks.tdf`) in the block-based TierTask Data Format ([`TDF_SPEC.md`](TDF_SPEC.md)).

## Overview

`TierTask` stores objective task facts (`tdf 0.5.0`, `queue`, `deleted`, `label`, `task`) in one `.tdf` document and derives operational tiers automatically in a deterministic pull system.

- **Cross-Platform Desktop & Mobile:** Supports Linux (`linux/`), Android (`android/`), and Windows (`windows/`) with English (`en`, default) and German (`de`) localization and Material 3 `Slate` and `Navy` color palettes.
- **Unified Block DSL (`TDF`):** Scans, parses, and serializes `.tdf` documents (`tdf 0.5.0`) in a single $O(N)$ pass with strict resource bounds and explicit `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0` version migration.
- **Deterministic 6-Tier Derivation:** Evaluates `Completed`, `Someday`, and `Blocked` automatically, slices active tasks in `queue` block order into `Focus` (limit `3`), `Ready` (limit `5`), and `Planned`, and prunes completed tasks and `deleted` tombstones older than `30` days (UTC).
- **Context-Aware Conditions & Recurrence:** Evaluates completion-count dependencies (`blocked <task-id>[:<required-completion>]`), `suspended`, and `day`, `time`, and foreground GPS `location` conditions with label inheritance, and reschedules completed `repeat` tasks into `Focus` via `Blocked`.
- **Two-Stage Three-Way Synchronization:** Reconciles in-memory state, local `.tdf` files, and WebDAV servers using 10-character Base62 entity identifiers, monotonic UTC `modified` timestamps, and `deleted.generation` counters across `Local`, `WebDAV`, and `Both` storage modes.
- **Multi-Workspace & Encrypted Settings:** Isolates independent `.tdf` task boards and storage settings into switchable workspaces persisted via `flutter_secure_storage`.
- **Opt-In Diagnostic Logging:** Records sanitized runtime events and crash stack traces into a 5,000-line rolling `tiertask.log` ring buffer with an in-app log viewer when enabled.

## Requirements

| Component | Requirement |
| :--- | :--- |
| Flutter SDK | `>=3.47.0` (channel `stable`) |
| Dart SDK | `^3.13.7` |
| Target Platforms | Linux (`x64`), Android (`arm64-v8a` / `x86_64`), Windows (`x64`) |
| Supported Languages | English (`en`, default) and German (`de`) via external `.arb` files |
| Storage Backend | Local filesystem `.tdf` file or any HTTP/HTTPS WebDAV server |

## Installation & Build

Clone the repository and generate localization bindings:

```bash
git clone https://github.com/ststark/tiertask.git
cd tiertask
flutter pub get
flutter gen-l10n
```

Run in debug mode on Linux or Windows desktop:

```bash
flutter run -d linux
flutter run -d windows
```

Build obfuscated release artifacts for supported platforms:

```bash
flutter build linux --release --obfuscate --split-debug-info=build/symbols
flutter build apk --release --obfuscate --split-debug-info=build/symbols
flutter build windows --release --obfuscate --split-debug-info=build/symbols
```

## Quick Start

1. Launch `TierTask` and open the settings screen via the navigation drawer.
2. Select the display language (`System`, `English`, or `Deutsch`), theme mode (`System`, `Light`, or `Dark`), color palette (`Slate` or `Navy`), and local time zone (`Automatic` or `Manual` UTC offset).
3. Select the storage mode (`Local`, `WebDAV`, or `Both`) and configure the local `.tdf` file name (default `tasks.tdf`) and/or WebDAV endpoint (`https://cloud.example.com`, username `example-user`, password, and remote path `tasks.tdf`).
4. Add tasks via the bottom quick-add bar (`Priority`, `Someday`, `Labels`, or `Advanced` for the full task editor); changes synchronize and persist automatically.

## Tier System & Documentation

| Tier | English (`en`) | German (`de`) | Soft Limit | Derivation Rule |
| :--- | :--- | :--- | :--- | :--- |
| `1` | `Focus` | `Fokus` | `3` | Active tasks at positions `1..3` in `queue` block order |
| `2` | `Ready` | `Bereit` | `5` | Active tasks at positions `4..8` in `queue` block order |
| `3` | `Planned` | `Geplant` | None | Active tasks from position `9` onward in `queue` block order |
| `4` | `Blocked` | `Blockiert` | None | Open scheduled tasks with unsatisfied `blocked` dependencies, `suspended`, or unmet `condition` rules |
| `5` | `Someday` | `Irgendwann` | None | Open tasks without a `queued` directive |
| `6` | `Completed` | `Erledigt` | None | Tasks with a `finished` directive (pruned after `30` days in UTC) |

Canonical `tasks.tdf` example:

```text
tdf 0.5.0

queue {
    modified 2026-11-01 09:15:00
    task 8jKaCdOkD2
    task 3nR8vWOkD8
}

label 4x9p2mOkD2 {
    name     "Home"
    color    "#4CAF50"
    modified 2026-11-01 08:30
}

task 8jKaCdOkD2 priority {
    name     "Verify server backup"
    created  2026-11-01 08:30
    queued   2026-11-01 08:30
    modified 2026-11-01 08:30
    labels   4x9p2mOkD2
}

task 3nR8vWOkD8 {
    name     "Clean up study"
    created  2026-11-01 09:00
    queued   2026-11-01 09:15
    modified 2026-11-01 09:15
    subtasks auto-finish {
        step true  "Wipe desk"
        step false "Organize cables"
    }
}
```

For complete documentation, refer to the dedicated specifications in this repository:
- **[TDF_SPEC.md](TDF_SPEC.md):** Normative lexical grammar, root-block schema, 6-tier evaluation pipeline, and synchronization rules for `.tdf` files.
- **[ARCHITECTURE.md](ARCHITECTURE.md):** Architectural layers, directory structure, file inventory, and synchronization flow.
- **[AGENTS.md](AGENTS.md):** Engineering rules, TDD workflow (`P-TDD-FIRST`), deterministic `.dart` file layout, and test requirements.
- **[CHANGELOG.md](CHANGELOG.md):** Version history and user-facing release notes.

## Development

```bash
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

## Disclaimer & License

`TierTask` is a strictly private project. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. Licensed under the **GNU General Public License v3.0 (GPL-3.0)**; see [LICENSE](LICENSE) for full terms.
