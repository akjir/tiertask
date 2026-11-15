# TDF v0.7.0 Conformance Fixture Suite

Machine-readable conformance vectors for the TierTask Data Format (`TDF`) version `0.7.0` specification ([`spec/TDF_SPEC_0.7.0.md`](../../TDF_SPEC_0.7.0.md)).

## Directory Structure

- `parse_valid/`: Valid `tdf 0.7.0` input documents (`.tdf`), their exact canonical serialized output (`.canonical.tdf`), and normalized decoded payload representations (`.normalized.json`, including `canonicalSourceDigest`).
- `parse_invalid/`: Syntactically or semantically invalid `.tdf` documents paired with `manifest.json` specifying the mandatory `TdfErrorKind` (`expectedError`) and 1-based line number (`expectedLine`).
- `bounds/`: Boundary verification `.tdf` fixtures and `manifest.json` testing exact `N` (valid) and `N + 1` (`LimitExceeded`) resource and lexical bounds, including `MAX_HISTORY_PER_TASK = 500` (counted before deduplication), full-capacity `534`-statement canonical `task` blocks, `MAX_STMTS_PER_BLOCK = 1024` (`512` in `< 0.7.0`), `MAX_LINKS_PER_LABEL = 20`, `MAX_REPEAT_COUNT = 3650` on `lead`, `MAX_NOTE_LENGTH = 2000` on `suspended` and `due` notes, and supplementary Unicode scalar values (`> U+FFFF`).
- `merge/`: Deterministic three-way synchronization, occurrence-independent `history` set reconciliation, baseline-free two-way `history` union, `label.link` atomic list merge, `Case 2` `suspended <= now` and `V.repeat`-aware `blocked` pre-normalization, and `DeletionConflict` hygiene test vectors (`vectors.json`).
- `timezone/`: Local calendar recurrence (`Europe/Berlin` CET/CEST gaps, folds, and month-end clamping) for Mode 2 `repeat <count> <unit> [<clock>] [lead <N> days]`, `due` lead-window effective-priority evaluation, and `downgradeTask` test vectors (`vectors.json`).
- `migration/`: Adjacent (`0.6.0 -> 0.7.0`) and chained (`0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0`) explicit migration and load-time conversion fixtures, including `sourceTimeZone` extraction of `repeat ... lead` and `<repeat-time>` (`ImportContextRequired` when omitted) and `manifest.json`.
