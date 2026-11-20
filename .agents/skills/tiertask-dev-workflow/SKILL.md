---
name: tiertask-dev-workflow
description: Builds, tests, and develops TierTask in Flutter/Dart using tiertask_dev.py and strict Red-Green-Refactor TDD.
---

# TierTask Development Workflow

Follow `AGENTS.md` strictly throughout every step below.

## 1. Fast-Path CLI (`python3 .agents/scripts/tiertask_dev.py`)
Use `tiertask_dev.py` instead of blind file reads or manual boilerplate:
- **`outline [files...]`:** Print repo overview or exact `StartLine-EndLine` ranges, class spans, and `_private` counts. Run before reading `> 400`-line files or `spec/TDF_SPEC_0.8.0.md`, then call `read_file` with targeted line ranges.
- **`find <q1> [<q2> ...] [--layer <layer>]`:** Multi-query lookup across Dart declarations, ARB keys, tests, `ARCHITECTURE.md`, and `spec/TDF_SPEC*.md`.
- **`deps <lib_path>`:** List direct imports, reverse `lib/` dependents, and mapped mirror/subsystem test suites before editing shared code.
- **`l10n`:** Manage `app_en.arb` and `app_de.arb` in one shot instead of manual edits:
  - `--query <pattern>` | `--set <key> "<en>" "<de>" [--desc "<desc>"]` | `--remove <key>` | `--audit` (`--set`/`--remove` auto-generate `@key` placeholder metadata and run `flutter gen-l10n`).
- **`scaffold <rel_path> --desc "<summary>"`:** Create a GPL-3.0 licensed `.dart` file and register it in `ARCHITECTURE.md`.
- **`arch --sync-tree [--set <rel_path> "<summary>"] [--audit]`:** Synchronize `ARCHITECTURE.md` layout tree and layer tables.
- **`log [path] [--level ...] [--tag ...] [--event ...] [--summary]`:** Filter and summarize TierTask diagnostic `.log` files.

## 2. TDD Edit-Verify Cycle (`P-TDD-FIRST`)
1. **Baseline:** Run `python3 .agents/scripts/tiertask_dev.py verify --fast`.
2. **Red (Tests First; `P-TDD-FIRST`, `P-TEST-MIRROR`):**
   - Add/update tests in mirrored `test/<layer>/<name>_test.dart` (or the mapped subsystem suite from `deps`). Do not split tests for line count.
   - Use `pumpLeafWidget` (`FakeTaskNotifier`) in `test/ui/test_helpers.dart` for isolated leaf widgets, `HttpOverrides.global = null;` in `setUp()` for loopback `HttpServer` tests, semantic matchers, `reason:` strings in loops/tables/multi-step cases, and all applicable `M-*` categories (`AGENTS.md` Section 5).
   - Confirm expected failure via `flutter test --no-pub --no-test-assets -r failures-only <target_tests>`.
3. **Green (Minimal Implementation):**
   - Implement in `lib/` following `AGENTS.md` Sections 1–4 (7-part layout, `P-FILE-SIZE`, `P-CLASS-COHESION`, `P-ACYCLIC-DAG`, `P-IO-ISOLATION`, `P-IMMUTABLE-MODELS`, `P-FN-DOCS`, `P-NO-DEAD-CODE`).
   - Add or update `AppLogger.event(...)` instrumentation per `AGENTS.md` Section 6.
4. **Refactor (Clarity & Performance Gate):**
   - Enforce `P-FLAT-CONTROL-FLOW` ($\le 3$ indent), `P-NO-NESTED-LOOPS`, `P-LOOP-MODULARITY` ($< 25$L), `P-FLATTEN-BUILD` ($< 40$L; extract `const` `StatelessWidget`/`ConsumerWidget` classes, never `Widget`-returning helpers), `P-ZERO-ALLOC`, `P-BOUND-ALLOC`, `P-LAZY-LISTS`, and `P-DISPOSE-RESOURCES`.
   - Never refactor, compress, or split existing files solely for line count (`P-FILE-SIZE`).
5. **Fast Iterative Verify & Parallel Waves:**
   - Run `python3 .agents/scripts/tiertask_dev.py verify --fast --fix` (auto-formats modified `.dart` files, checks `AGENTS.md`/`P-ACYCLIC-DAG`/`l10n`/`arch` invariants, runs `flutter analyze`, and executes impacted suites in `< 5s`).
   - For parallel write subagents, assign strictly disjoint `Write Set`s (`P-SUBAGENT-ISOLATION`) and run only assigned tests per subagent before `verify --full --fix` at the wave barrier.
6. **Sync Spec, Docs & Changelog:** Apply **`tdf-spec-workflow`**, **`update-documentation`**, and **`changelog-updater`** as applicable (skip `CHANGELOG.md` for internal changes or fixes to unreleased code).
7. **Final Full Verify & Stamp:** Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix` once at completion to run the full test suite and update `.dart_tool/tiertask_verify_stamp.json`.
