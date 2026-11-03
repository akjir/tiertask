# TierTask

> [!IMPORTANT]
> **Disclaimer:** `TierTask` is strictly a private, personal project developed for individual use. It is provided without any warranty, official support, or maintenance guarantees.

`TierTask` is a Flutter task manager for Linux, Android, and Windows that dynamically derives six priority and status tiers (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) from a single local or WebDAV-synchronized `.tdf` file (`tiertask.tdf`) in the block-based TierTask Data Format ([`TDF_SPEC.md`](TDF_SPEC.md)).

## Overview

`TierTask` stores objective task facts (`tdf 0.4.0`, `label`, `task`, `modified`, `repeat`, `condition`, `subtasks`) in one `.tdf` document and derives operational tiers automatically:

* **Supported Target Platforms:** Linux (`linux/`), Android (`android/`), and Windows (`windows/`). All other target platforms are unsupported.
* **Dynamic $O(N)$ 6-Tier Derivation:** Derives `Completed` (`finished`), `Someday` (no `queued`), `Blocked` (`blocked`, future `suspended`, or unmet `condition` across `day`, `time`, and `location` rule groups with label inheritance), and slices active tasks by `priority` and ascending `queued` FIFO timestamp into `Focus` (limit `3`), `Ready` (limit `5`), and `Planned`.
* **Recurring Tasks (`repeat <count> <days|weeks|months>`):** Completing a recurring task (or completing all steps of its `subtasks auto-finish` checklist) reschedules it directly into `Blocked` (`suspended` set to `localNow + <count> <unit>` at `00:00` local time or preserving an explicit suspended time-of-day, `queued` set to the UTC equivalent, `priority` flag added, `modified` advanced, and all `subtasks` reset to `false`) without entering `Completed`, waking up directly into `Focus` on its next due date.
* **UTC Storage & Local Wall-Clock Conditions:** Stores and compares point-in-time directives (`created`, `queued`, `finished`, `modified`) and 30-day completed task pruning strictly in UTC while evaluating `condition day`, `condition time`, and `suspended` against the user's device or manually configured local time zone (`Automatic` / `Manual` UTC offset).
* **Foreground-Only Location Determination (`locationEnabled`):** Optional setting (default `Off`) that determines the current place name and GPS coordinates on Android (`LocationManager` + `Geocoder`), Linux (`GeoClue2` D-Bus), and Windows (`ILocation`) with 100-meter Haversine displacement reverse-geocoding gating, 30-minute cached GeoIP desktop fallback, and 5-minute app-resume cooldown only while the application is running in the foreground, displaying a 3-state status icon (`searching`, `found`, `unavailable`) and status popup in the top bar and dynamically evaluating `condition location` rules.
* **Two-Stage Entity-Level Synchronization (`In-Memory <-> Local File <-> WebDAV`):** Uses 10-character Base62 entity identifiers (`<6xBase62Random><4xBase62Time>`), compares individual `task` and `label` blocks via monotonic `modified` timestamps (`TaskBoardSync.merge`) on every save and manual sync, and immediately converts and syncs back legacy `tdf 0.2.0` / `0.3.0` identifiers when loading older files.
* **Anti-Ping-Pong Downgrade & Auto-Finish Checklists:** Updates `queued` timestamps and strips `priority` when downgrading tasks, and automatically completes a `task` when all steps in `subtasks auto-finish` become `true`.
* **30-Day Completed Task Pruning:** Removes `Completed` tasks whose `finished` timestamp is strictly older than `30` days (UTC) on save.
* **Configurable Storage Modes (`Local`, `WebDAV`, `Both`):** Supports local-only `.tdf` persistence (`LocalFileRepository` defaulting to `tiertask.tdf`), remote-only WebDAV synchronization (`WebDavRepository`), or combined dual persistence (`Both`).
* **Encrypted Configuration Persistence:** Stores storage mode, local and remote `.tdf` file names, WebDAV credentials, language, theme, and time zone settings via `flutter_secure_storage`.

## Requirements

| Component | Requirement |
| :--- | :--- |
| Flutter SDK | `>=3.47.0` (channel `stable`) |
| Dart SDK | `^3.13.7` |
| Target Platforms | Linux (`x64`), Android (`arm64-v8a` / `x86_64`), Windows (`x64`) |
| Supported Languages | English (`en`, default) and German (`de`) via external `.arb` files |
| Storage Backend | Local filesystem `.tdf` file or any HTTP/HTTPS WebDAV server |

## Installation & Build

```bash
git clone https://github.com/ststark/tiertask.git
cd tiertask
flutter pub get
flutter gen-l10n

# Run on Linux or Windows desktop
flutter run -d linux
flutter run -d windows

# Build obfuscated release artifacts for supported platforms
flutter build linux --release --obfuscate --split-debug-info=build/symbols
flutter build apk --release --obfuscate --split-debug-info=build/symbols
flutter build windows --release --obfuscate --split-debug-info=build/symbols
```

## Quick Start

1. Launch `TierTask` and open the settings screen via the menu drawer.
2. Select the display language (`System`, `English`, or `Deutsch`) and color theme (`System`, `Light`, or `Dark`).
3. Select the storage mode (`Local`, `WebDAV`, or `Both`) and configure the local TDF file name (default `tiertask.tdf`) and/or WebDAV endpoint (`https://cloud.example.com`, username `example-user`, password/app-password, and remote file path `tiertask.tdf`).
4. Add tasks via the floating action button (`QuickAddBar`) using the input field, mutually exclusive `Priority` and `Someday` toggles, or the multi-select `Labels` menu; changes persist immediately to the configured `.tdf` file.

## Tier System & TDF Format

See [`TDF_SPEC.md`](TDF_SPEC.md) for the complete grammar and evaluation pipeline:

| Tier | English (`en`) | German (`de`) | Soft Limit | Derivation Rule |
| :--- | :--- | :--- | :--- | :--- |
| `1` | `Focus` | `Fokus` | `3` | Active sorted tasks at positions `1..3` (`priority` first, then `queued` FIFO) |
| `2` | `Ready` | `Bereit` | `5` | Active sorted tasks at positions `4..8` |
| `3` | `Planned` | `Geplant` | None | Active sorted tasks from position `9` onward |
| `4` | `Blocked` | `Blockiert` | None | Open scheduled tasks with unfinished `blocked` IDs, future `suspended`, or unmet `condition` |
| `5` | `Someday` | `Irgendwann` | None | Open tasks without a `queued` directive |
| `6` | `Completed` | `Erledigt` | None | Tasks with a `finished` directive (pruned after `30` days) |

Canonical `tiertask.tdf` example:

```text
tdf 0.4.0

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

See [ARCHITECTURE.md](ARCHITECTURE.md) for the layer design, [TDF_SPEC.md](TDF_SPEC.md) for the format specification, and [CHANGELOG.md](CHANGELOG.md) for release history.

## Development

```bash
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

## Disclaimer & License

`TierTask` is a strictly private project. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. Licensed under the GNU General Public License v3.0; see [LICENSE](LICENSE) for full terms.
