---
name: red
description: Acts as an adversarial Red Team Security, Stability, Performance, Readability, and Code Efficiency Auditor to break, exploit, audit, and harden the Flutter and Dart codebase. Triggered when the user types `/red`, `/red all`, `/red changed`, or `/red <file_or_dir...>`.
---

# Red Team Audit & Hardening Workflow

Execute this workflow on `/red`, `/red all`, `/red changed`, or `/red <path...>` (files or directories). Act as an adversarial security researcher and strict Flutter/Dart systems engineer. Enforce `AGENTS.md` strictly.

## 1. Scope Resolution & Context-Isolated Dispatch
Audit **every file in an isolated context window**:
1. **Single File (`/red <file>`):** Audit the target file directly (or via one `research` subagent) with exclusive focus on that file.
2. **Multiple Files, Directory, or Changed Files (`/red <file1> <file2> ...`, `/red <dir>`, `/red changed`):**
   - Expand any directory path to all `.dart` files inside it (recursively).
   - For `/red changed`, resolve non-deleted `.dart` files modified, staged, or untracked relative to `HEAD` (`git diff --name-only --diff-filter=d HEAD -- '*.dart'` and `git ls-files --others --exclude-standard -- '*.dart'`); stop immediately if none changed.
   - Spawn **one `research` subagent per file** (`invoke_subagent`, `TypeName: "research"`, `Model: "inherit"`) with Section 2 instructions. Each subagent must inspect **only its assigned file** (reading external definitions only to verify called functions, helpers, or type contracts).
3. **Full Project (`/red` or `/red all`):**
   - Enumerate all `.dart` files under `lib/`.
   - Audit `.dart` files via **one `research` subagent per file** in architectural waves, waiting for each wave to finish before starting the next:
     - **Wave 1 (Domain Models & Pure Services):** `lib/models/*`, `lib/services/*`, `lib/l10n/tier_localization_extension.dart`
     - **Wave 2 (I/O Repositories & Riverpod Providers):** `lib/repositories/*`, `lib/providers/*`
     - **Wave 3 (Application Entry & UI Layer):** `lib/main.dart`, `lib/ui/**`

## 2. Five-Pillar Reconnaissance (Red Team Phase — Per-File Instructions)
Assume the assigned `.dart` file is flawed and non-compliant. Audit exhaustively across all five pillars:

### 2.1 Security (Sicherheit)
1. **Unidirectional Layer Isolation, WebDAV SSRF & TLS Hardening (`dart:io`, `P-UDF-ARCHITECTURE`, `P-IO-ISOLATION`, `P-WEBDAV-API`, `P-TRANSPORT-SECURITY`):** Does any module outside `lib/repositories/` perform network, secure storage, or local filesystem I/O (`P-IO-ISOLATION`), invoke `HttpClient` outside `lib/repositories/webdav_repository.dart` (`P-WEBDAV-API`), or invoke `File` outside `lib/repositories/`? Do UI widgets bypass Riverpod notifiers (`P-UDF-ARCHITECTURE`)? Is `badCertificateCallback` ever enabled to bypass TLS validation? Are Android platform defaults hardened (`android:usesCleartextTraffic="false"` and `android:allowBackup="false"`)? Can malformed server URLs inject non-HTTP(S) schemes (`file://`, `ftp://`), embedded userinfo (`user:pass@host`), query/fragment components (`?`, `#`), or silent cleartext `http://` downgrades on remote networks?
2. **Path Traversal & Endpoint Manipulation (`Uri`, `File`):** Can remote WebDAV or local filesystem `filePath` or `username` inputs containing `..`, `\0`, backslashes (`\`), encoded slashes (`%2F`), symbolic links, or unvalidated path segments escape the intended WebDAV base path or local file target and read or overwrite arbitrary files on Linux, Android, or Windows?
3. **Unbounded Network/File Streams & Denial of Service (`P-BOUND-ALLOC`):** Can a rogue or misconfigured WebDAV server or oversized local `.tdf` file return an unbounded payload (`response.transform(utf8.decoder).join()` or `file.readAsString()`) or stall connections without strict byte-count limits (`maxFileBytes`), stream timeouts, and guaranteed `client.close()` / file handle cleanup?
4. **TDF Delimiter Injection, Control Characters & BiDi Spoofing (`M-DELIM-INJECT-TESTS`):** Can untrusted task/label strings or externally edited `.tdf` documents containing `{`, `}`, quotes (`"`, `'`), backslashes (`\`), inline `#` comments, `\n`, `\r`, `\0`, C0/C1 control characters (`\u{0000}..=\u{001F}`, `\u{007F}..=\u{009F}`), or Unicode BiDi overrides forge TDF blocks/directives or corrupt the `.tdf` file on round-trip serialization?
5. **Credential Hygiene, Secret Leakage & Obfuscation Safety (`P-SECRET-HYGIENE`, `P-TRANSPORT-SECURITY`):** Are any secrets hardcoded in source code? Can passwords, Basic Auth headers, tokens, or raw system stack traces leak into exception strings, user-facing UI error banners, `toString()` outputs, `print()` / `debugPrint()` logs (`avoid_print`), or unencrypted storage outside `FlutterSecureStorage`? Does any code rely on `runtimeType.toString()` comparisons that break under `--obfuscate --split-debug-info` release builds?

### 2.2 Stability (Stabilität)
1. **Null-Safety, Pattern Matching & Sound Types (`P-NULL-SAFE`, `P-STRICT-TYPES`, `P-FLAT-CONTROL-FLOW`):** Does production code use the null-assertion operator (`!`), uninitialized `late` fields without lifecycle guarantees, `dynamic`, unchecked `as` casts, check-then-unwrap (`if (x != null) x!.foo`), or unchecked index/substring slicing (`list[i]`, `str.substring(a, b)`) instead of Dart 3 pattern matching (`if (x case final v?)`), `.firstOrNull`, or bounds checks?
2. **Async Lifecycle Safety, Global Error Boundaries & Resource Disposal (`P-GLOBAL-ERROR-BOUNDARY`, `P-DISPOSE-RESOURCES`):** Does `main.dart` register `FlutterError.onError` and `PlatformDispatcher.instance.onError` (`P-GLOBAL-ERROR-BOUNDARY`)? Are `BuildContext` or `State.setState` used across `await` gaps without `if (!mounted) return;` (`use_build_context_synchronously`)? Are all `TextEditingController`, `FocusNode`, `ScrollController`, `StreamSubscription`, and `HttpClient` instances disposed in `dispose()` or `finally` blocks? Are any `Future`s unawaited (`unawaited_futures`)?
3. **Pre-Scan Resource Bounds (`P-BOUND-ALLOC`):** Are `maxFileBytes`, `maxLineCount`, `maxNestingDepth`, `maxBlocksPerDoc`, `maxStmtsPerBlock`, `maxArgsPerStmt`, `maxTextLength`, `maxNoteLength`, and `maxDeletedRecords` enforced **before** scanning or allocating the $(N+1)$-th element?
4. **Deterministic Domain Invariants, Optimistic State Integrity & Error Preservation (`P-ERR-PRESERVE`, `P-ATOMIC-STATE`, `P-IMMUTABLE-MODELS`):** Are domain models strictly immutable (`List.unmodifiable`, value `==` and `hashCode`)? Are all point-in-time timestamps normalized to UTC (`DateTime.utc`) to prevent timezone/DST drift in 30-day pruning and sync comparisons? Can concurrent user mutations race, or can failed local/WebDAV saves leave inconsistent state or swallow exceptions (`catch (_) {}`) without preserving causes and signaling failure (`P-ATOMIC-STATE`)?
5. **Test Coverage, Reason Strings & Parallel Isolation (`P-TDD-FIRST`, `M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`, `M-URI-PATH-EDGE-TESTS`, `M-IO-TESTS`):** Is any `enum` / `sealed class` branch, WIP/retention/`max*` boundary, TDF delimiter injection vector, URI traversal edge case, or I/O failure untested? Do loop or table-driven `expect()` assertions omit `reason:` strings? Do tests rely on wall-clock `DateTime.now()` or shared mutable static state?

### 2.3 Speed & Performance (Geschwindigkeit)
1. **Const Widgets, Rebuild Scoping & Lazy Virtualization (`P-CONST-WIDGETS`, `P-SELECT-REBUILDS`, `P-LAZY-LISTS`):** Are `const` constructors (`prefer_const_constructors`) and `super.key` used everywhere possible? Do widgets watch full providers when `.select(...)` suffices, or trigger whole-form `setState(() {})` on every keystroke? Are dynamic task lists rendered lazily via `ListView.builder` with deterministic `ValueKey`s rather than materializing all items in `Column` or `ListView(children: [...])`?
2. **Zero-Waste Allocations (`P-ZERO-ALLOC`):** Are `RegExp` patterns instantiated inside methods or loops instead of `static final`? Are there avoidable `.toList()`, `List.from()`, or string concatenations inside loops or `build()` methods?
3. **Single-Pass O(N) Complexity (`P-NO-QUADRATIC`):** Are there $O(N^2)$ `List.removeAt(0)` shifts inside loops, redundant linear scans across all tasks for the same ID, or chained `.replaceAll()` / `.split()` passes?
4. **Unfragmented Buffer Serialization (`StringBuffer`):** Does `.tdf` serialization write directly to a single `StringBuffer` without intermediate string allocations?

### 2.4 Readability & Deterministic Layout (Lesbarkeit)
1. **Strict 7-Part File Layout & Class Member Order (`P-LICENSE-HEADER`, `P-DIRECTIVES-ORDER`, `AGENTS.md` Section 2):** Does the file follow the exact 7-part vertical order: (1) verbatim GPL-3.0 header + blank line, (2) `///` library doc, (3) 3-group alphabetized imports (`dart:`, `package:`, relative in `lib/`), (4) alphabetized constants/providers, (5) types with strictly ordered members (constructors, `static const`/`static final`, `final` fields, getters, lifecycle overrides, public methods, `_private` methods, `==`/`hashCode`/`toString`), (6) alphabetized top-level functions, (7) `dart format` compliance with trailing commas?
2. **Flat Control Flow, Combinators, Widget Modularity & File Size (`P-VERTICAL-CLARITY`, `P-FILE-SIZE`, `P-FLAT-CONTROL-FLOW`, `P-FLATTEN-BUILD`, `P-NO-NESTED-LOOPS`, `P-LOOP-MODULARITY`, `P-FUNCTIONAL-COMBINATORS`):** Are there nested loops, multi-arm `switch` or deep `if/else` blocks inside loops/closures, indentation $> 3$ levels, loop bodies $\ge 25$ lines, `build()` / dispatcher methods $\ge 40$ lines, helper methods returning `Widget` instead of dedicated `StatelessWidget` classes, complex `.where().map()` chains, or large production/test files exceeding the **~500-line** soft target (`P-FILE-SIZE`) that can be cleanly split into cohesive files (note: ~500 lines is a preference, not a hard requirement if a split is not practical)?
3. **Naming, Language & Documentation Integrity (`P-NO-ABBREV-VARS`, `P-FN-DOCS`, `P-LANG-RULES`):** Are variable names unabbreviated (`configuration` > `cfg`, `repository` > `repo`, `task` > `t`)? Are two-state enums or sealed classes used over ambiguous `bool` parameters? Does every production item have a concise English `///` comment (ASD-STE100 80%, zero emojis) while `test()` blocks omit redundant `///` comments? Are all strings, comments, and identifiers compliant with `P-LANG-RULES`?

### 2.5 Code Efficiency (Code-Effizienz)
1. **Zero Dead Code & Zero Ignore Directives (`P-NO-DEAD-CODE`, `P-NO-IGNORE`):** Does the file contain unused functions, methods, fields, enum values, providers, parameters, imports, or `// ignore:` / `// ignore_for_file:` directives?
2. **DRY & Shared Logic Reuse:** Does the file duplicate task lookup, tier filtering, UTC date normalization, or string sanitization logic?
3. **Exhaustive State Modeling (`P-EXHAUSTIVE-SWITCH`, `P-MASK-SAFE`):** Are exhaustive `switch` expressions/statements over `enum` / `sealed class` types used without redundant `default:` branches, and are mutually exclusive states modeled via `enum` / `sealed class` instead of chained boolean fields?

Each subagent must return either **"SECURE"** (if zero violations exist; never invent subjective issues outside `AGENTS.md`) or confirmed findings tagged by pillar (`[Security]`, `[Stability]`, `[Speed]`, `[Readability]`, `[Efficiency]`) with line numbers, triggering inputs/defects, and violated rule IDs.

## 3. Consolidated Audit Report & Remediation Plan (Decision Gate)
Aggregate all per-file results in the orchestrator context:
- **Guard Against Immutability Over-Optimization:** Classify bounded, structurally required allocations (`P-BOUND-ALLOC`, immutable `copyWith` models, `List.unmodifiable` views, `StringBuffer` outputs) as **"SECURE"**. Never sacrifice `P-VERTICAL-CLARITY` or `P-IMMUTABLE-MODELS`; report only unbounded (OOM/DoS) or trivially avoidable allocations (`P-ZERO-ALLOC`, `P-NO-QUADRATIC`).
- **If All Files Pass:** Declare the audited scope **"SECURE"** and stop immediately without modifying code.
- **If Findings Exist:** Present a unified **Audit Report & Remediation Plan** and **wait for explicit user approval** before editing code:
  1. List files verified as **SECURE**.
  2. Group findings by file in bottom-up dependency order (`lib/models/` -> `lib/services/` -> `lib/repositories/` -> `lib/providers/` -> `lib/ui/` -> `lib/main.dart`).
  3. State each finding's pillar tag, file, line numbers, defect/attack vector, violated rule IDs, and planned TDD fix + test.

## 4. Remediation (Blue Team Phase — Adaptive TDD Execution)
After user approval, remediate findings without breaking existing behavior:
- **Small Scope (1–2 files):** Remediate directly one by one.
- **Large Scope (3+ files):** Delegate to **one `self` subagent per file**, executed **sequentially** in dependency order (`lib/models/` and `lib/services/` first) to keep each subagent's context isolated while preventing concurrent edits and Flutter build-lock contention.
- **Per-File TDD Remediation Checklist (`P-TDD-FIRST`):**
  1. **Exploit & Regression Tests First (`Red`):** Add unit or widget tests in `test/` covering the identified attacks, bounds, or state branches (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`, `M-URI-PATH-EDGE-TESTS`, `M-IO-TESTS`) and verify failure via `flutter test`.
  2. **Harden & Optimize Source (`Green` & `Refactor`):** Resolve all approved findings while preserving business logic and public contracts.
  3. **Compliance Gate:** Re-verify the modified file against Sections 2.4 and 2.5 (`AGENTS.md` Sections 2–4, `P-LICENSE-HEADER`, `P-FN-DOCS`, `P-NO-DEAD-CODE`, `P-NO-IGNORE`, `P-LANG-RULES`).
  4. **Closed-Loop Verification:** Run `python3 .agents/scripts/tiertask_dev.py verify --fast --fix`, fixing any issues until all pass with zero warnings.

## 5. Finalization
Run workspace-wide `python3 .agents/scripts/tiertask_dev.py verify --full --fix`, then report the resolved findings and verification status concisely. Never run `git commit`.
