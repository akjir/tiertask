# TierTask

> [!IMPORTANT]
> `TierTask` is a private, personal project developed for individual use. It is provided without warranty, official support, or maintenance guarantees.

`TierTask` is a task manager for Linux, Android, and Windows that derives six operational tiers (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) from a single `.tdf` file in the TierTask Data Format ([`spec/TDF_SPEC_0.7.0.md`](spec/TDF_SPEC_0.7.0.md)).

## Overview

Tasks and metadata are stored as plain text in a `.tdf` document, while operational tiers are computed at runtime.

- **Deterministic Pull System:** Separates `Completed`, `Someday`, and `Blocked` tasks first, slices active `queue` tasks into `Focus` (limit `3`), `Ready` (limit `5`), and `Planned` with configurable deadline (`due`) lead-window auto-promotion (`24` hours by default), clears expired `suspended` locks and resolved one-shot `blocked` prerequisites on sync, and prunes completed tasks and tombstones after `30` days (UTC).
- **Scoped Queues & Conditions:** Supports global and label-scoped queues (`scoped`), label and task reference `link` entries, prerequisite dependencies, deferral (`suspended`) and deadline (`due`) notes, recurrence with preparation lead days (`repeat ... lead`), persistent task progress logs (`history`), and `day`, `time`, and geofence (`location`) conditions.
- **Three-Way Synchronization:** Reconciles in-memory state, watched local `.tdf` file edits, and a WebDAV server at entity and field granularity using 10-character Base62 IDs, UTC modification timestamps, and `deleted` tombstones.
- **Workspaces & Local Security:** Isolates independent task boards and storage credentials into switchable workspaces persisted via `flutter_secure_storage`.
- **Diagnostic Logging:** Writes opt-in, redacted runtime logs per workspace to local storage or WebDAV with an in-app filterable viewer.

## Requirements

| Component | Requirement |
| :--- | :--- |
| Flutter SDK | `>=3.50.0` (`stable`) |
| Dart SDK | `^3.14.0` |
| Platforms | Linux (`x64`, `arm64`), Android (`arm64-v8a`, `x86_64`), Windows (`x64`) |
| Localization | English (`en`, default), German (`de`) |
| Storage | Local `.tdf` file, HTTP/HTTPS WebDAV server, or both |

## Installation & Build

Clone the repository, generate localization bindings, and run a desktop debug build:

```bash
git clone https://github.com/ststark/tiertask.git
cd tiertask
flutter pub get
flutter gen-l10n
flutter run -d linux
```

Build and install the Linux desktop release into `$HOME/.local` (or remove with `./install.sh uninstall`), or build obfuscated release artifacts manually:

```bash
./install.sh
flutter build linux --release --obfuscate --split-debug-info=build/symbols
flutter build apk --release --obfuscate --split-debug-info=build/symbols
flutter build windows --release --obfuscate --split-debug-info=build/symbols
```

## Quick Start

1. Open **Settings** from the navigation drawer to configure language, theme, time zone, and deadline lead window.
2. Select a storage mode (`Local`, `WebDAV`, or `Both`) and set the local `.tdf` path (`tasks.tdf`) and/or WebDAV endpoint (`https://cloud.example.com`, username `example-user`, remote path `tasks.tdf`).
3. Add tasks via the bottom bar (`Priority`, `Someday`, `Labels`, or `Advanced` for subtasks, conditions, and recurrence).
4. Switch between the global board and `scoped` label queues in the navigation drawer, or inspect a label's notes, reference links, and conditions in its context hub; changes persist and synchronize automatically.

## Tier System & Documentation

| Tier | English (`en`) | German (`de`) | Soft Limit | Derivation Rule |
| :--- | :--- | :--- | :--- | :--- |
| `1` | `Focus` | `Fokus` | `3` | Active tasks at positions `1..3` of the evaluated queue |
| `2` | `Ready` | `Bereit` | `5` | Active tasks at positions `4..8` of the evaluated queue |
| `3` | `Planned` | `Geplant` | None | Active tasks from position `9` onward of the evaluated queue |
| `4` | `Blocked` | `Blockiert` | None | Open tasks with an active `suspended` lock, or queued tasks with unmet `blocked` dependencies or `condition` rules |
| `5` | `Someday` | `Irgendwann` | None | Open tasks outside the evaluated queue without an active `suspended` lock |
| `6` | `Completed` | `Erledigt` | None | Tasks with a `finished` timestamp (pruned after `30` days in UTC) |

Example `tasks.tdf`:

```text
tdf 0.7.0

queue {
    modified 2026-11-01 09:15:00
    task 8jKaCdOkD2
    task 3nR8vWOkD8
}

label 4x9p2mOkD2 {
    name     "Infrastructure"
    color    "#4CAF50"
    modified 2026-11-01 08:30:00
    link     "Runbook" "https://docs.example.com/backups"
}

task 8jKaCdOkD2 priority {
    name     "Verify server backup"
    created  2026-11-01 08:30:00
    modified 2026-11-01 08:30:00
    repeat   1 months lead 3 days
    labels   4x9p2mOkD2
    due      2026-11-15 00:00:00 "Before monthly maintenance window"
    history  2026-11-01 08:30:00 "Verified offsite snapshot checksums"
}

task 3nR8vWOkD8 {
    name     "Clean up study"
    created  2026-11-01 09:00:00
    modified 2026-11-01 09:15:00
    subtasks auto-finish {
        step true  "Wipe desk"
        step false "Organize cables"
    }
}
```

Repository documentation:
- [`spec/TDF_SPEC_0.7.0.md`](spec/TDF_SPEC_0.7.0.md) — TDF `0.7.0` grammar, tier derivation rules, and three-way merge specification.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — Layer architecture, directory layout, file responsibilities, and execution flow.
- [`AGENTS.md`](AGENTS.md) — Engineering standards, TDD rules, and verification workflow.
- [`CHANGELOG.md`](CHANGELOG.md) — Release history.

## Development

```bash
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

## Disclaimer & License

`TierTask` is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. Licensed under the GNU General Public License v3.0 ([`LICENSE`](LICENSE)).
