# TierTask

`TierTask` is a Flutter task manager for Linux, Android, and Windows that organizes tasks across six priority and status tiers using a deterministic pull-system backed by a single local or WebDAV-synchronized Markdown file (`tiertask.md`).

## Overview

`TierTask` stores the entire task board in one plain-text Markdown file and enforces work-in-progress (WIP) limits automatically:

* **Supported Target Platforms:** Linux (`linux/`), Android (`android/`), and Windows (`windows/`). All other target platforms are unsupported.
* **Six Priority and Status Tiers:** `# Fokus`, `# Bereit`, `# Irgendwann`, `# Blockiert`, `# Geplant`, and `# Erledigt`.
* **Deterministic Auto-Pull Cascade:** Automatically refills `# Fokus` (soft limit `3`) from `# Bereit` and `# Bereit` (soft limit `5`) from `# Geplant` without force-demoting manually overfilled tiers.
* **Anti-Ping-Pong Downgrade:** Pulls replacement tasks upward before appending a downgraded task to the lower tier.
* **30-Day Completed Task Pruning:** Stamps completed tasks with `- [x] YYYY-MM-DD` in `# Erledigt` and removes entries older than `30` days (UTC).
* **Dual Storage Backends:** Supports direct persistence to a local Markdown (`.md`) file via `dart:io` `File` and remote HTTP `GET`/`PUT` synchronization with any standards-compliant WebDAV server via `dart:io` `HttpClient`.
* **Encrypted Configuration Persistence:** Stores WebDAV credentials and file configuration via `flutter_secure_storage`.

## Requirements

| Component | Requirement |
| :--- | :--- |
| Flutter SDK | `>=3.47.0` (channel `stable`) |
| Dart SDK | `^3.13.7` |
| Target Platforms | Linux (`x64`), Android (`arm64-v8a` / `x86_64`), Windows (`x64`) |
| Storage Backend | Local filesystem `.md` file or any HTTP/HTTPS WebDAV server |

## Installation & Build

```bash
git clone https://github.com/ststark/tiertask.git
cd tiertask
flutter pub get

# Run on Linux or Windows desktop
flutter run -d linux
flutter run -d windows

# Build release artifacts for supported platforms
flutter build linux --release
flutter build apk --release
flutter build windows --release
```

## Quick Start

1. Launch `TierTask` and open the settings screen via the toolbar icon.
2. Select the storage mode and configure either a local Markdown file path (for example `/home/example-user/tiertask.md` or `C:\Users\example-user\tiertask.md`) or a WebDAV endpoint (`https://cloud.example.com`, username `example-user`, password/app-password, and file path `tiertask.md`).
3. Activate connection test and synchronization to load an existing Markdown file or initialize a new 6-tier `tiertask.md` file.
4. Add tasks via the bottom input bar (`QuickAddBar`); new tasks enter `# Geplant` by default and cascade into `# Bereit` or `# Fokus` when slots are open.

## Tier System & Markdown Format

| Tier | Markdown Heading | Soft Limit | Auto-Pull Behavior |
| :--- | :--- | :--- | :--- |
| Fokus | `# Fokus` | `3` | Pulls top tasks from `# Bereit` while `< 3` |
| Bereit | `# Bereit` | `5` | Pulls top tasks from `# Geplant` while `< 5` |
| Irgendwann | `# Irgendwann` | None | Static tier; excluded from automatic pull |
| Blockiert | `# Blockiert` | None | Static tier; excluded from automatic pull |
| Geplant | `# Geplant` | None | Active backlog feeding `# Bereit` |
| Erledigt | `# Erledigt` | None | Static archive; prunes tasks `> 30` days old |

Canonical `tiertask.md` format:

```markdown
# Fokus
- [ ] Prepare release notes

# Bereit
- [ ] Verify WebDAV synchronization

# Irgendwann
- [ ] Evaluate keyboard shortcuts

# Blockiert
- [ ] Await server certificate renewal

# Geplant
- [ ] Update package dependencies

# Erledigt
- [x] 2026-11-01 Initialize project structure
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the layer design and [CHANGELOG.md](CHANGELOG.md) for release history.

## Development

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

## Disclaimer & License

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. Licensed under the GNU General Public License v3.0; see [LICENSE](LICENSE) for full terms.
