---
name: red
description: Adversarial Red Team security, stability, performance, readability, and efficiency audit for Flutter/Dart code. Triggered by /red, /red all, /red changed, or /red <path...>.
---

# Red Team Audit & Hardening Workflow

Execute on `/red`, `/red all`, `/red changed`, or `/red <path...>`. Act as an adversarial security researcher and strict Flutter/Dart systems engineer enforcing `AGENTS.md`.

## 1. Scope Resolution & Context-Isolated Dispatch
Audit **every file in an isolated context window**:
1. **Single File (`/red <file>`):** Audit directly (or via one `research` subagent) with exclusive focus on that file.
2. **Multiple Files, Directory, or Changed (`/red <path...>`, `/red changed`):**
   - Recursively expand directories to `.dart` files (excluding generated `lib/l10n/app_localizations*.dart`).
   - For `/red changed`, resolve non-deleted `.dart` files relative to `HEAD` (`git diff --name-only --diff-filter=d HEAD -- '*.dart'` and `git ls-files --others --exclude-standard -- '*.dart'`), excluding generated `lib/l10n/app_localizations*.dart`; stop if empty.
   - Spawn **one `research` subagent per file** (`invoke_subagent`, `TypeName: "research"`, `Model: "inherit"`) with Section 2 instructions. Each subagent audits ONLY its assigned file (reading external symbols solely to verify contracts).
3. **Full Project (`/red` or `/red all`):** Enumerate all hand-written `.dart` files under `lib/` (excluding `lib/l10n/app_localizations*.dart`) and dispatch one `research` subagent per file in waves (wait for each wave to finish before starting the next):
   - **Wave 1 (Models, Services, L10n):** `lib/models/*`, `lib/services/*`, `lib/l10n/storage_file_read_localization_extension.dart`, `lib/l10n/tier_localization_extension.dart`
   - **Wave 2 (Repositories & Providers):** `lib/repositories/*`, `lib/providers/*`
   - **Wave 3 (Design System, Entry & UI):** `lib/ui/{tokens,primitives,layout,components}/*`, app `lib/ui/**`, `lib/main.dart`

## 2. Five-Pillar Audit (Per-File Subagent Instructions)
Assume the assigned `.dart` file is flawed. Check every pillar strictly against `AGENTS.md`:

### 2.1 Security
1. **Layer Isolation, DAG & Transport (`P-UDF-ARCHITECTURE`, `P-ACYCLIC-DAG`, `P-IO-ISOLATION`, `P-WEBDAV-API`, `P-TRANSPORT-SECURITY`):** Upward layer imports or circular SCCs (`0: app_logger < 1: models < 2: l10n < 3: services < 4: repositories < 5: providers < 6: ui < 7: main`); violations of internal Design System sub-rank order (`tokens (0) < primitives (1) < layout (2) < components (3)`) or imports from `lib/ui/{widgets,dialogs,views}/`, `tier_task_shell_screen.dart`, `ui_domain_mappers.dart`, `lib/models/`, `lib/l10n/`, `lib/services/`, `lib/repositories/`, `lib/providers/`, or `flutter_riverpod` inside `lib/ui/{tokens,primitives,layout,components}/`; direct `lib/repositories/` imports inside `lib/ui/`; `dart:io` or `dart:ffi` outside `lib/repositories/`; `HttpClient` outside `webdav_repository.dart`; `File` outside `lib/repositories/`; UI bypassing providers for I/O or mutations; `badCertificateCallback` TLS bypass; non-HTTP(S) schemes, URL userinfo (`user:pass@host`), query/fragment injection, or silent remote `http://` downgrades; Android `usesCleartextTraffic` / `allowBackup` regressions.
2. **Path Traversal (`Uri`, `File`):** Remote WebDAV or local paths containing `..`, `\0`, `\`, `%2F`, symlinks, or unvalidated segments escaping the intended base path on Linux, Android, or Windows.
3. **Unbounded I/O & DoS (`P-BOUND-ALLOC`):** Unbounded stream/file reads (`response.transform(utf8.decoder).join()`, `file.readAsString()`) without `maxTdfFileBytes`, `connectionTimeout`, or guaranteed `HttpClient.close()` / handle cleanup.
4. **TDF Injection & Control Characters (`M-DELIM-INJECT-TESTS`):** Untrusted strings with `{`, `}`, quotes, `\`, `#`, `\n`, `\r`, `\0`, C0/C1 controls (`\u{0000}..=\u{001F}`, `\u{007F}..=\u{009F}`), or Unicode BiDi overrides forging directives or corrupting round-trips.
5. **Secrets, Diagnostic PII & Obfuscation (`P-SECRET-HYGIENE`, `P-TRANSPORT-SECURITY`, `AGENTS.md` Section 6):** Hardcoded secrets; credentials, Basic Auth headers, raw stack traces, GPS coordinates, street addresses, BSSIDs, notes, link titles/URIs, or `history` text leaking into `toString()`, exceptions, UI banners, `print()`/`debugPrint()`, or `AppLogger`; `runtimeType.toString()` branching breaking `--obfuscate`.

### 2.2 Stability
1. **Null & Type Safety (`P-NULL-SAFE`, `P-STRICT-TYPES`, `P-FLAT-CONTROL-FLOW`):** `!` null-assertions, uninitialized `late`, `dynamic`, unchecked `as`, check-then-unwrap, or unchecked indexing/substring slicing (`list[i]`, `str.substring(a, b)`).
2. **Async, Error Boundaries & Disposal (`P-GLOBAL-ERROR-BOUNDARY`, `P-DISPOSE-RESOURCES`):** Missing `FlutterError.onError` / `PlatformDispatcher.instance.onError` in `main.dart`; `BuildContext`/`setState` across `await` without `if (!mounted) return;`; undisposed controllers, streams, or `HttpClient`s; unawaited `Future`s.
3. **Pre-Scan Resource Bounds (`P-BOUND-ALLOC`):** Missing pre-allocation checks for any `spec/TDF_SPEC_0.8.0.md` Section 6.2 `maxTdf*` constant (`lib/models/tdf_error.dart`) before reading or allocating the $(N+1)$-th element.
4. **Domain Invariants, UTC & Atomic State (`P-IMMUTABLE-MODELS`, `P-ERR-PRESERVE`, `P-ATOMIC-STATE`):** Mutable collections or broken value `==`/`hashCode`; non-UTC point-in-time timestamps risking DST/30-day pruning drift; concurrent mutation races; failed saves leaving inconsistent state; swallowed exceptions (`catch (_) {}`) or lost causes.
5. **Test Rigor (`P-TDD-FIRST`, `P-TEST-MIRROR`, all `M-*`):** Missing branch/bound/injection/URI/I/O tests; synthetic shortcuts violating `M-REAL-MECHANICS-TESTS`; non-mirrored tests, missing `pumpLeafWidget` or `HttpOverrides.global = null;`; missing `reason:` strings in loops/tables; wall-clock `DateTime.now()` or shared mutable static state in tests.

### 2.3 Performance
1. **Widgets & Virtualization (`P-CONST-WIDGETS`, `P-SELECT-REBUILDS`, `P-LAZY-LISTS`):** Missing `const`/`super.key`; broad `ref.watch` where `.select(...)` applies; full-form `setState` per keystroke; eager `Column`/`ListView(children: [...])` instead of `ListView.builder` with deterministic `ValueKey`s.
2. **Allocations & Complexity (`P-ZERO-ALLOC`, `P-NO-QUADRATIC`, `P-ZERO-COPY`):** Non-`static final` `RegExp`; avoidable `.toList()`/`List.from()`/`+` concatenation in loops or `build()`; $O(N^2)$ `List.removeAt(0)`, redundant board scans, or chained `.replaceAll()`/`.split()`; non-`StringBuffer` `.tdf` serialization.

### 2.4 Readability & Layout
1. **7-Part Layout & Member Order (`P-LICENSE-HEADER`, `P-DIRECTIVES-ORDER`, `P-CLASS-COHESION`, `AGENTS.md` Section 2):** GPL-3.0 header + blank line, `///` doc, 3-group alphabetized imports, alphabetized constants/providers, cohesive types with strict member order, alphabetized top-level functions, `dart format` + trailing commas.
2. **Flatness & Modularity (`P-VERTICAL-CLARITY`, `P-FILE-SIZE`, `P-FLAT-CONTROL-FLOW`, `P-FLATTEN-BUILD`, `P-NO-NESTED-LOOPS`, `P-LOOP-MODULARITY`, `P-FUNCTIONAL-COMBINATORS`):** Nested loops; multi-arm `switch`/deep `if/else` in loops; indentation $> 3$; loop bodies $\ge 25$L; `build()`/dispatchers $\ge 40$L; helper methods returning `Widget` instead of `StatelessWidget` classes; dense combinator chains; unconditional ban on `part`/`part of`/`export` across hand-written `lib/` and `test/`. Never flag file line counts or `_private` method counts.
3. **Naming, Docs & UI Design System (`P-NO-ABBREV-VARS`, `P-FN-DOCS`, `P-LANG-RULES`, `P-UI-DESIGN-SYSTEM`):** Abbreviated variables; ambiguous `bool` params instead of enums/sealed types; missing `///` on production items or redundant `///` on `test()` blocks; non-English/emoji/filler prose; in `lib/ui/` (including `lib/ui/{tokens,primitives,layout,components}/`), violations of `spec/UI_DESIGN_SYSTEM.md` (hardcoded colors bypassing `UiThemeTokens`, unapproved drop shadows, missing `1px` focus-visible rings or accessible labels, broken `720`/`820` breakpoints, floating notices overlapping bottom docks, sliding switches, or bespoke one-off widgets bypassing the shared 17-widget catalog).

### 2.5 Code Efficiency
1. **Dead Code & Ignores (`P-NO-DEAD-CODE`, `P-NO-IGNORE`):** Unused symbols/params/imports or `// ignore:` / `// ignore_for_file:`.
2. **DRY:** Duplicated task lookup, tier filtering, UTC normalization, or sanitization logic.
3. **Exhaustive State (`P-EXHAUSTIVE-SWITCH`, `P-MASK-SAFE`):** Redundant `default:` on exhaustive switches; chained boolean flags instead of one `enum`/`sealed class`.

**Subagent Output Contract:** Return ONLY `"SECURE"` (never invent subjective issues outside `AGENTS.md`) OR a list of confirmed findings formatted as:
`[Security|Stability|Performance|Readability|Efficiency] <file>:<lines> | <Rule IDs> | <Trigger/Defect>`

## 3. Consolidated Report & Decision Gate
Aggregate all per-file results in the orchestrator:
- **Immutability Guard:** Treat bounded, required allocations (`copyWith`, `List.unmodifiable`, `StringBuffer`, `P-BOUND-ALLOC`) as `"SECURE"`. Flag only unbounded (OOM/DoS) or trivially avoidable waste.
- **All Clean:** Report **"SECURE"** and stop without editing files.
- **Findings Exist:** Present one **Audit Report & Remediation Plan** and **wait for explicit user approval** before editing:
  1. List files verified as **SECURE**.
  2. Group findings by file in bottom-up layer order (`app_logger` -> `models` -> `l10n` -> `services` -> `repositories` -> `providers` -> `ui` -> `main`).
  3. Include pillar tag, file/lines, attack vector/defect, violated rule IDs, and planned TDD fix + regression test.

## 4. Remediation (After User Approval, Adaptive TDD)
- **1–2 Files:** Remediate directly one by one.
- **3+ Files (`P-SUBAGENT-ISOLATION`):** Dispatch `self` subagents with strictly disjoint file `Write Set`s in bottom-up dependency waves.
- **Per-File TDD Checklist (`P-TDD-FIRST`):**
  1. **Red:** Add exploit/regression tests in `test/` covering all applicable `M-*` categories (including `M-REAL-MECHANICS-TESTS`) and confirm failure via `flutter test`.
  2. **Green & Refactor:** Fix all approved findings while preserving public contracts and `AGENTS.md` compliance (including Section 6 `AppLogger` instrumentation).
  3. **Fast Verify:** Run `python3 .agents/scripts/tiertask_dev.py verify --fast --fix` until clean.

## 5. Finalization
Run workspace-wide `python3 .agents/scripts/tiertask_dev.py verify --full --fix` and report resolved findings concisely. Never run `git commit`.
