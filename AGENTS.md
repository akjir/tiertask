# TierTask AI Agent Rules

> [!IMPORTANT]
> Update this file, [`ARCHITECTURE.md`](ARCHITECTURE.md), and [`TDF_SPEC.md`](TDF_SPEC.md) when the architecture, directory structure, file names, or TierTask Data Format (`TDF`) schema change.

## 1. Core Principles, Language & TDD Workflow
- **Primary Priority — Test-Driven Development (`P-TDD-FIRST`):** Develop every feature, domain rule, parser routine, state notifier, repository method, UI widget, and bug fix using strict Red-Green-Refactor TDD:
  1. **Red:** Write failing unit tests (`test/`) or widget tests (`testWidgets`) FIRST and verify that they fail via `flutter test`.
  2. **Green:** Write the minimal production code in `lib/` required to make the tests pass.
  3. **Refactor:** Clean up and optimize the implementation while keeping `flutter test` and `flutter analyze --fatal-infos --fatal-warnings` green.
- **Primary Priority — Language & Tone (`P-LANG-RULES`):** Write all AI responses, code, identifiers, comments, documentation, tests, error messages, and commit messages in concise, factual English (ASD-STE100 80%). Never use emojis, filler text, marketing adjectives, greetings, or Markdown horizontal rules (`---`).
- **Goal & Supported Targets:** Manage tasks across six dynamically derived priority and status tiers (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`) in the `TierTask` Flutter application on **Linux, Android, and Windows** (`linux/`, `android/`, `windows/`) with **English (`en`, default) and German (`de`) localization** (configurable in settings or derived from the OS locale) using a deterministic pull-system and a single `.tdf` file in the block-based TierTask Data Format ([`TDF_SPEC.md`](TDF_SPEC.md)) stored either as a **local TDF (`.tdf`) file** or synchronized via **any standards-compliant WebDAV server**. All other target platforms (iOS, macOS, Web) and storage backends are unsupported.
- **Standard Library First (`P-STDLIB-FIRST`):** Prefer the Dart SDK (`dart:async`, `dart:collection`, `dart:convert`, `dart:core`, `dart:io`) and Flutter SDK (`package:flutter`, `package:flutter_localizations`) over third-party packages. Keep `pubspec.yaml` minimal, store all English and German UI strings in external ARB files (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`) compiled via `flutter gen-l10n`, and implement TDF scanning/parsing (`lib/services/tdf_service.dart`), local file I/O (`dart:io` `File`), and WebDAV HTTP operations (`dart:io` `HttpClient`) directly with the Dart standard library.
- **Strict Type & Null Safety (`P-STRICT-TYPES`, `P-NULL-SAFE`):** Target modern Dart 3+ and Flutter (Material 3) with sound null safety and strict static analysis (`strict-casts: true`, `strict-inference: true`, `strict-raw-types: true` in `analysis_options.yaml`). Forbid `dynamic`, unchecked `as` casts, and mutable global state in production code. Never use the null-assertion operator (`!`), uninitialized `late` variables without a guaranteed lifecycle initializer, or unchecked `.cast<T>()` in production code (allowed only for proven mathematical invariants); deconstruct nullable values via pattern matching (`if (value case final v?)`), `??`, or `?.`.
- **Version Control:** NEVER commit changes unless explicitly instructed by the user.
- **Simplicity, Vertical Clarity & File Size (`P-VERTICAL-CLARITY`, `P-FILE-SIZE`):** Prioritize readability, flat control flow, and small composable `Widget` classes over dense code or monolithic `build()` methods. Prefer extracting small, single-purpose helper functions or private `StatelessWidget` classes over deep nesting, dense expressions, or complex inline closures. Aim for around **500 lines** per production and test `.dart` file (`lib/` and `test/`) as a soft target (`P-FILE-SIZE`), not a mandatory limit: when a file grows too large, check whether it can be split into cohesive domain, service, or widget leaf files; if a clean split is not possible, keeping the larger file is acceptable.
- **Token Efficiency:** Avoid redundancy across code, docs, rules, and skills. Preserve all business logic, public signatures, error types, and test semantics during refactors.
- **Direct Use & Zero Dead Code (`P-NO-DEAD-CODE`):** Write ONLY directly called functions, methods, classes, fields, enum variants, providers, and imports. Never write speculative helpers, unused getters/setters, hypothetical fallbacks, or commented-out code; delete orphaned items immediately in the same edit. **Compilation Stub Exception:** Minimal active no-op stubs wired into the call graph for unimplemented downstream stages are permitted.

## 2. Deterministic File Layout (`.dart`)
Keep barrel files minimal (or omit them) and place core logic in dedicated `snake_case.dart` leaf files named after their primary class or domain. Organize every `.dart` file in this exact 7-part vertical order:
1. **License Header (`P-LICENSE-HEADER`):** Verbatim GPL-3.0 comment block at the top of the file, followed by one blank line:
   ```dart
   // TierTask
   // Copyright (C) 2026  Stefan Stark
   //
   // This program is free software: you can redistribute it and/or modify it under
   // the terms of the GNU General Public License as published by the Free Software
   // Foundation, either version 3 of the License, or (at your option)
   // any later version.
   //
   // This program is distributed in the hope that it will be useful, but WITHOUT
   // ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
   // FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
   //
   // You should have received a copy of the GNU General Public License along with
   // this program.  If not, see <https://www.gnu.org/licenses/>.
   ```
2. **Library & File Docs:** Optional `/// ...` file-level doc comment directly below the license header (`///` on production items; `//` only for non-obvious domain quirks; never use `/* ... */` block comments).
3. **Imports (`P-DIRECTIVES-ORDER`):** 3 alphabetized groups separated by one blank line (`directives_ordering`):
   - `dart:` SDK imports (`import 'dart:async';`, `import 'dart:convert';`, `import 'dart:io';`) in strict ASCII order.
   - `package:` imports (`import 'package:flutter/material.dart';`) in strict ASCII order.
   - Relative project imports (`import '../models/task_board.dart';`) in `lib/` (`prefer_relative_imports`), or `package:tiertask/...` imports in `test/`, in strict ASCII order.
   - **Namespace Hygiene:** Never import internal implementation files from another package's `src/` directory. Use `show` / `hide` or `as prefix` only when resolving identifier collisions.
4. **Constants & Providers:** File-local `const` items and top-level Riverpod `Provider` / `NotifierProvider` declarations, sorted alphabetically (`public` before `_private`).
5. **Types & Class Members (`enum`, `sealed class`, `class`, `extension`, `typedef`):** Sorted logically or alphabetically (`public` before `_private`). Inside every `class` or `enum`, order members strictly as follows:
   - **Constructors:** Primary `const` or unnamed constructor at top, followed by named and `factory` constructors.
   - **Static Constants & Static Fields:** `static const` and `static final` fields, sorted alphabetically.
   - **Instance Fields:** `final` fields (`public` before `_private`), sorted alphabetically or matching constructor parameter order.
   - **Getters & Setters:** Computed properties (`get`), sorted alphabetically.
   - **Lifecycle Overrides:** Framework lifecycle methods (`initState`, `didUpdateWidget`, `dispose`, `build`) in standard execution order.
   - **Instance Methods:** Public methods sorted alphabetically, followed by `_private` helper methods sorted alphabetically.
   - **`Object` Overrides:** `operator ==`, `hashCode`, and `toString` at the bottom of the class.
6. **Top-Level Functions:** Pure top-level helper functions sorted alphabetically (`public` before `_private`).
7. **Tests (`test/*_test.dart`, `P-FILE-SIZE`):** Place unit and widget tests in `test/` mirroring the `lib/` directory layout (`test/<layer>/<name>_test.dart`). Aim for around **500 lines** per test file as a soft target; when a test file grows too large, check whether it can be split by domain or widget responsibility, and keep it unified if a split is not practical.

## 3. Architecture, Types & Idioms
- **Formatting & Naming (`P-NO-ABBREV-VARS`):** Format with 2 spaces (`dart format`) and strip trailing whitespace. Use trailing commas (`require_trailing_commas`) in multi-line parameter, argument, and collection lists. Follow Effective Dart naming (`UpperCamelCase` for types/enums/extensions, `lowerCamelCase` for members/variables/parameters/constants, `snake_case` for files/directories). Never abbreviate variable names (`configuration` > `cfg`, `repository` > `repo`, `element` > `el`, `task` > `t`, `response` > `res`; loop indices `i`, `j` are allowed).
- **Mandatory Documentation (`P-FN-DOCS`):** Document every production `class`, `sealed class`, `enum`, `extension`, `typedef`, constructor, method, getter, top-level function, and provider (`public` and `_private`, including extracted helpers) with a concise `///` comment in factual English (ASD-STE100 80%, no emojis or filler). **Test Exception:** Omit `///` on `test()` and `testWidgets()` blocks in `test/` unless explaining a non-obvious edge case or attack vector.
- **Immutability, Constructors & Records (`P-IMMUTABLE-MODELS`, `P-CONST-WIDGETS`):**
  - Favor concrete, immutable domain models (`@immutable`, `final` fields, `List.unmodifiable` / `Map.unmodifiable`, `copyWith`, value `operator ==` and `hashCode`).
  - Use `const` constructors (`prefer_const_constructors`, `prefer_const_declarations`, `prefer_const_literals_to_create_immutables`) and `super.key` (`use_super_parameters`) across all `Widget` and immutable model classes.
  - Prefer named classes or named Dart 3 records over positional tuples, and two-state enums or `sealed class` hierarchies over ambiguous boolean parameters.
- **Error Handling, Global Boundaries & State Integrity (`P-ERR-PRESERVE`, `P-GLOBAL-ERROR-BOUNDARY`, `P-ATOMIC-STATE`):**
  - Register global framework and isolate error handlers (`FlutterError.onError` and `PlatformDispatcher.instance.onError`) in `main.dart` (`P-GLOBAL-ERROR-BOUNDARY`) so uncaught synchronous or asynchronous errors never terminate the event loop or expose raw internal stack traces in the UI (`docs.flutter.dev/testing/errors`).
  - Use typed domain exceptions or `sealed class` result hierarchies (e.g., `WebDavException`, `LocalFileException`); NEVER throw raw strings (`throw 'error'`), return untyped error maps, swallow exceptions silently (`catch (_) {}`), or display unsanitized system exception text to users. Preserve underlying error causes and stack traces (`Error.throwWithStackTrace`, `rethrow`, or a typed `cause` field).
  - Await all `Future`s explicitly (`unawaited_futures`), guard async state transitions (`AsyncValue.guard`), serialize or guard concurrent mutation commands, and preserve or roll back immutable `TaskBoard` state when persistence fails (`P-ATOMIC-STATE`, `docs.flutter.dev/app-architecture/design-patterns/optimistic-state`).
- **Unidirectional Architecture, I/O Isolation & Security Hardening (`P-UDF-ARCHITECTURE`, `P-IO-ISOLATION`, `P-WEBDAV-API`, `P-SECRET-HYGIENE`, `P-TRANSPORT-SECURITY`):**
  - Enforce Google's Flutter App Architecture separation of concerns and unidirectional data flow (`P-UDF-ARCHITECTURE`, `docs.flutter.dev/app-architecture`): UI widgets (`lib/ui/`) render immutable state snapshots and dispatch user intents to Riverpod notifiers (`lib/providers/`), which coordinate pure domain models (`lib/models/`), stateless services (`lib/services/`), and single-source-of-truth repositories (`lib/repositories/`).
  - Isolate all network (`dart:io` `HttpClient`), secure storage (`flutter_secure_storage`), and local filesystem (`dart:io` `File`) I/O inside `lib/repositories/` (`P-IO-ISOLATION`). Domain models (`lib/models/`), parsers/services (`lib/services/`), and UI widgets (`lib/ui/`) must remain pure and free of direct `dart:io` network or file calls.
  - Centralize all WebDAV HTTP request construction, authentication headers, timeouts, and status handling in `lib/repositories/webdav_repository.dart` (`P-WEBDAV-API`) and local `.tdf` file reads/writes in `lib/repositories/` (e.g., `lib/repositories/local_file_repository.dart`); no module outside `lib/repositories/` may invoke `HttpClient` or `File` directly.
  - Never hardcode credentials, tokens, or private endpoints in source code, never log sensitive data via `print()` or `debugPrint()` (`avoid_print`), and redact passwords and authorization headers from `toString()` and exception messages (`P-SECRET-HYGIENE`).
  - Enforce strict TLS certificate validation (`badCertificateCallback` must never bypass verification), reject non-HTTP(S) schemes and embedded URL userinfo, enforce Android manifest security (`android:usesCleartextTraffic="false"` and `android:allowBackup="false"`), avoid `runtimeType.toString()` branching, and build release artifacts with `--obfuscate --split-debug-info=<dir>` (`P-TRANSPORT-SECURITY`, `docs.flutter.dev/deployment/obfuscate`).
- **State, Exhaustiveness & Rebuild Scoping (`P-EXHAUSTIVE-SWITCH`, `P-MASK-SAFE`, `P-SELECT-REBUILDS`):**
  - Use Dart 3 `enum` and `sealed class` hierarchies with compiler-enforced exhaustive `switch` expressions and statements (`P-EXHAUSTIVE-SWITCH`). Never add a redundant `default:` branch to an exhaustive `switch` over an `enum` or `sealed class`. Replace chained boolean flags (`isLoading`, `isError`, `isSuccess`) with a single `enum` or `sealed class` state (`P-MASK-SAFE`).
  - Scope Riverpod `ref.watch(...)` subscriptions with `.select(...)` when listening to a subset of state, and localize `StatefulWidget` state to leaf widgets to prevent full-screen rebuilds (`P-SELECT-REBUILDS`).
- **Flat Control Flow & Widget Modularity (`P-FLAT-CONTROL-FLOW`, `P-FLATTEN-BUILD`):**
  - Never exceed 3 indentation levels in business logic or methods. Deconstruct nullable values and sealed types via `switch`, `if (value case final v?)`, and early `return` / `continue` / `break` guard clauses (`P-FLAT-CONTROL-FLOW`).
  - Keep `build()` methods and action dispatchers under 40 lines (`P-FLATTEN-BUILD`). Extract UI subtrees into dedicated private `StatelessWidget` or `ConsumerWidget` classes rather than helper methods returning `Widget`.
- **Analyzer & Resource Discipline (`P-NO-IGNORE`, `P-DISPOSE-RESOURCES`):**
  - NEVER suppress analyzer warnings or lints with `// ignore:` or `// ignore_for_file:` (`P-NO-IGNORE`).
  - Always `.dispose()` every `TextEditingController`, `FocusNode`, `ScrollController`, `AnimationController`, `StreamSubscription`, and `HttpClient` (`P-DISPOSE-RESOURCES`), and check `if (!mounted) return;` before using `BuildContext` or `setState` across `await` gaps (`use_build_context_synchronously`).

## 4. Memory, Parsing & Performance
- **Zero-Waste Allocations (`P-ZERO-ALLOC`):** Accept `Iterable<T>` or unmodifiable views for read-only collection parameters. Avoid unnecessary `.toList()`, `.toSet()`, `List.from()`, or `.toString()` allocations inside loops or `build()` methods. Compile regular expressions once as `static final RegExp` constants; never instantiate `RegExp` inside functions, loops, or `build()` methods.
- **Bounded Inputs & Pre-Allocation (`P-BOUND-ALLOC`):** Enforce explicit `max*` resource bounds (`maxFileBytes`, `maxLineCount`, `maxNestingDepth`, `maxBlocksPerDoc`, `maxStmtsPerBlock`, `maxArgsPerStmt`, `maxTextLength`, `maxNoteLength`, `connectionTimeout`) BEFORE reading, scanning, or allocating the $(N+1)$-th element from network streams or `.tdf` documents to prevent OOM or UI frame drops (`P-BOUND-ALLOC`). Use `StringBuffer` for multi-line string serialization instead of `+` concatenation in loops.
- **Single-Pass Scanning & Zero-Copy Slicing (`P-ZERO-COPY`, `P-NO-QUADRATIC`):**
  - Scan, parse, and serialize `.tdf` files in a single $O(N)$ pass without regular expressions or quadratic $O(N^2)$ behavior (avoid `List.removeAt(0)` in loops, repeated full-board scans for the same task ID, or chained `.replaceAll()` passes) per [`TDF_SPEC.md`](TDF_SPEC.md) and **`tdf-spec-workflow`**.
  - Use `startsWith()`, `indexOf()`, code-unit checks, and substring views over intermediate `.split()` list allocations where practical (`P-ZERO-COPY`).
- **Pragmatic Allocation Boundary:** Do NOT sacrifice readability (`P-VERTICAL-CLARITY`) or domain immutability (`P-IMMUTABLE-MODELS`) for micro-optimizations; immutable `copyWith` updates and `List.unmodifiable` wrappers on bounded domain collections are idiomatic and required.
- **Flat Loops & Combinators (`P-NO-NESTED-LOOPS`, `P-LOOP-MODULARITY`, `P-FUNCTIONAL-COMBINATORS`):**
  - NEVER nest loops (`for`, `while`, `do`) or place multi-branch `switch` / deep `if/else` trees inside a loop body; extract a stateless helper function (`P-NO-NESTED-LOOPS`). Keep loop bodies single-level and $< 25$ lines (`P-LOOP-MODULARITY`). Order `switch` arms by enum/sealed declaration order.
  - Use collection `if` / `for` elements and shallow `.where()` / `.map()` chains only when readable (`P-FUNCTIONAL-COMBINATORS`); prefer a flat `for` loop calling a helper over deeply chained combinators or closures containing control flow (`P-VERTICAL-CLARITY`).
- **Lazy List Virtualization (`P-LAZY-LISTS`):** Use `ListView.builder` or `SliverList.builder` for dynamic task lists instead of instantiating all children eagerly inside `Column` or `ListView(children: [...])`, and attach deterministic `ValueKey`s to task item widgets.

## 5. Testing, Documentation & Verification
- **TDD & Test Coverage (`P-TDD-FIRST`, `flutter test`):** Write unit and widget tests FIRST for every feature, parser routine, state transition, repository method, or bug fix:
  - Use semantic matchers (`contains()`, `equals()`, `isA<T>()`, `throwsA(isA<DomainException>())`) over brittle exact-string checks, and include concise `reason:` strings in `expect(..., reason: '...')` when testing loops, table-driven cases, or multi-step state transitions.
  - Cover all mandatory edge-case categories:
    - `M-EXHAUSTIVE-STATE-TESTS`: Every `enum` variant, `sealed class` branch, and `TdfErrorKind` error condition in [`TDF_SPEC.md`](TDF_SPEC.md) Section 8.
    - `M-EXTREME-BOUND-TESTS`: WIP soft limits ($N-1$, $N$, $N+1$), retention pruning boundaries ($29$, $30$, $31$ days in UTC), `maxFileBytes` / `maxLineCount` / `maxNestingDepth` / `maxBlocksPerDoc` / `maxStmtsPerBlock` / `maxArgsPerStmt` / `maxTextLength` / `maxNoteLength` limits, and empty/whitespace inputs.
    - `M-DELIM-INJECT-TESTS`: TDF block brace, quote, escape, inline `#` comment, CRLF/LF newline, control character, and malformed directive/header injection.
    - `M-URI-PATH-EDGE-TESTS`: Generic WebDAV server URL and local/remote file path edge cases (`..` traversal, null bytes, leading/trailing slashes, POSIX/Windows path separators, query/fragment injection, special characters, missing scheme, empty host).
    - `M-IO-TESTS`: Isolated WebDAV HTTP (`GET`/`PUT` status codes, timeouts, socket/TLS errors, auth headers), local `.tdf` file I/O (read/write, missing file initialization, permission/filesystem errors, `maxFileBytes` limits), and secure storage tests using injected mock/in-memory repositories, temporary directories (`Directory.systemTemp`), or loopback `HttpServer` instances without external network access.
- **Documentation & Sync:** Keep `README.md`, `ARCHITECTURE.md`, `AGENTS.md`, `TDF_SPEC.md`, and `CHANGELOG.md` synchronized per **`update-documentation`**, **`tdf-spec-workflow`**, and **`changelog-updater`**. Follow **`tiertask-dev-workflow`** for the TDD edit-verify cycle.
- **Verification:** Run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --fatal-infos --fatal-warnings`, and `flutter test` after every code modification.

## 6. Diagnostic Logging & Autonomous Instrumentation Policy
1. **Mandatory Instrumentation of New & Modified Code:** Whenever an agent adds, modifies, or debugs any domain mutation (`TaskBoard`, `TaskNotifier`), parser/serializer rule (`TdfService`), merge logic (`TaskBoardSync`), storage backend (`LocalFileRepository`, `WebDavRepository`), or lifecycle/settings flow, the agent **MUST** autonomously add or update corresponding `AppLogger` (`lib/services/app_logger.dart`) statements using the appropriate `LogLevel` (`debug`, `info`, `warn`, `error`, `crash`) and `LogTag` (`lifecycle`, `tdf`, `domain`, `sync`, `storage`, `ui`).
2. **Proactive Debugging Expansion:** During bug investigations or test failures, the agent must proactively instrument decision branches, edge cases, and error catch blocks with `AppLogger.debug` / `AppLogger.warn` / `AppLogger.error` so runtime behavior is fully traceable in the in-app Log Viewer (`LogViewerDialog` in `lib/ui/widgets/log_viewer_dialog.dart`).
3. **Privacy & No-Op Invariant:** Never log credentials or raw `Authorization` headers (`AppLogger.sanitize` and `AppLogger.registerSecret`), and ensure all logging remains strictly gated behind the opt-in setting (`WebDavConfig.diagnosticsEnabled` / `enableLogging`) with zero disk writes when disabled and immediate deletion of `tiertask.log` when toggled off.
