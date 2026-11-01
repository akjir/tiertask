# TierTask

> [!IMPORTANT]
> **Disclaimer:** `TierTask` is strictly a private, personal project developed for individual use. It is provided without any warranty, official support, or maintenance guarantees.

`TierTask` is a Flutter task manager for Linux, Android, and Windows that organizes tasks across six numbered priority and status tiers (`[1]` to `[6]`) using a deterministic pull-system backed by a single local or WebDAV-synchronized Markdown file (`tiertask.md`).

## Overview

`TierTask` stores the entire task board in one plain-text Markdown file and enforces work-in-progress (WIP) limits automatically:

* **Supported Target Platforms:** Linux (`linux/`), Android (`android/`), and Windows (`windows/`). All other target platforms are unsupported.
* **English & German Localization:** Supports English (`en`, default fallback) and German (`de`) via external Flutter ARB language files (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`), selectable in Settings (`System`, `English`, or `Deutsch`).
* **Theme Modes & Card Options:** Supports `System` (default), `Light`, and `Dark` Material 3 color themes, and an `Open Task Count` toggle (`Off` by default, `On`) to show or hide total open task counts on category and location cards.
* **Six Numbered Tiers (`[1]`–`[6]`):** `# [1] Focus`, `# [2] Ready`, `# [3] Planned`, `# [4] Blocked`, `# [5] Someday`, and `# [6] Completed`. The parser matches strictly by tier number (`[1]`–`[6]`), ignores the label text, and creates any missing tiers automatically.
* **Deterministic Auto-Pull Cascade:** Automatically refills Tier `1` (soft limit `3`) from Tier `2` and Tier `2` (soft limit `5`) from Tier `3` without force-demoting manually overfilled tiers.
* **Anti-Ping-Pong Downgrade:** Pulls replacement tasks upward before appending a downgraded task to the lower tier.
* **30-Day Completed Task Pruning:** Stamps completed tasks with `- [x] YYYY-MM-DD` in Tier `6` and removes entries older than `30` days (UTC).
* **Configurable Storage Modes (`Local`, `WebDAV`, `Both`):** Supports local-only Markdown persistence (`LocalFileRepository` with configurable local file name `localFilePath`, defaulting to `tiertask.md`), remote-only WebDAV synchronization (`WebDavRepository`), or combined dual persistence (`Both`).
* **Encrypted Configuration Persistence:** Stores storage mode, local and remote file names, WebDAV credentials, language, and theme settings via `flutter_secure_storage`.

## Requirements

| Component | Requirement |
| :--- | :--- |
| Flutter SDK | `>=3.47.0` (channel `stable`) |
| Dart SDK | `^3.13.7` |
| Target Platforms | Linux (`x64`), Android (`arm64-v8a` / `x86_64`), Windows (`x64`) |
| Supported Languages | English (`en`, default) and German (`de`) via external `.arb` files |
| Storage Backend | Local filesystem `.md` file or any HTTP/HTTPS WebDAV server |

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

1. Launch `TierTask` and open the settings screen via the toolbar icon.
2. Select the display language (`System`, `English`, or `Deutsch`) and color theme (`System`, `Light`, or `Dark`).
3. Select the storage mode (`Local`, `WebDAV`, or `Both`) and configure the local Markdown file name (default `tiertask.md`) and/or WebDAV endpoint (`https://cloud.example.com`, username `example-user`, password/app-password, and remote file path `tiertask.md`).
4. Activate connection test and synchronization to load an existing Markdown file or initialize a new 6-tier `tiertask.md` file.
5. Add tasks via the task creation bar (`QuickAddBar`) using the input field, mutually exclusive `Priority` (`# [1] Focus`) and `Someday` (`# [5] Someday`) toggles, or the `Advanced` view to define subtasks; new tasks without `Priority` or `Someday` enter `# [3] Planned` by default and cascade into `# [2] Ready` or `# [1] Focus` when slots are open.

## Tier System & Markdown Format

`MarkdownService` identifies sections strictly by their tier number (`1` to `6`), ignores any trailing heading name (`# [1] Focus`, `# [1] Fokus`, or `# (1) Custom`), and automatically creates missing tiers on save:

| Tier | English Heading (`en`) | German Heading (`de`) | Soft Limit | Auto-Pull Behavior |
| :--- | :--- | :--- | :--- | :--- |
| `1` | `# [1] Focus` | `# [1] Fokus` | `3` | Pulls top tasks from Tier `2` while `< 3` |
| `2` | `# [2] Ready` | `# [2] Bereit` | `5` | Pulls top tasks from Tier `3` while `< 5` |
| `3` | `# [3] Planned` | `# [3] Geplant` | None | Active backlog feeding Tier `2` |
| `4` | `# [4] Blocked` | `# [4] Blockiert` | None | Static tier; excluded from automatic pull |
| `5` | `# [5] Someday` | `# [5] Irgendwann` | None | Static tier; excluded from automatic pull |
| `6` | `# [6] Completed` | `# [6] Erledigt` | None | Static archive; prunes tasks `> 30` days old |

Canonical `tiertask.md` format (English default):

```markdown
# [1] Focus
- [ ] Prepare release notes

# [2] Ready
- [ ] Verify WebDAV synchronization

# [3] Planned
- [ ] Update package dependencies

# [4] Blocked
- [ ] Await server certificate renewal

# [5] Someday
- [ ] Evaluate keyboard shortcuts

# [6] Completed
- [x] 2026-11-01 Initialize project structure
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the layer design and [CHANGELOG.md](CHANGELOG.md) for release history.

## Development

```bash
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

## Disclaimer & License

`TierTask` is a strictly private project. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. Licensed under the GNU General Public License v3.0; see [LICENSE](LICENSE) for full terms.
