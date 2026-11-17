# TDF 0.8.0 Normative Conformance Suite (`TDF-VEC-001`)

This directory contains the standalone machine-readable conformance fixtures and test vectors for TierTask Data Format (`TDF`) version `0.8.0` as specified in [`../../TDF_SPEC_0.8.0.md`](../../TDF_SPEC_0.8.0.md) Appendix A.1 through A.3.

## Suite Layout

| Suite Directory | Manifest / Vector File | Verified Normative Scope | Primary Rule IDs |
| :--- | :--- | :--- | :--- |
| `parse_valid/` | `parse_valid/manifest.json` | Valid `.tdf` inputs (canonical and non-canonical), decoded `.normalized.json` models, byte-exact `.canonical.tdf` outputs, idempotence, and lowercase SHA-256 `canonicalSourceDigest` values (Vectors `1`–`4`, Section 1.5, and normalization cases). | `TDF-COMPAT-001`, `TDF-MODEL-001`–`TDF-MODEL-006`, `TDF-SER-001`–`TDF-SER-005` |
| `parse_invalid/` | `parse_invalid/manifest.json` | Malformed lexical, structural, header, directive, and cross-reference `.tdf` inputs (including raw malformed UTF-8 byte streams) paired with `expectedError`, 1-based `expectedLine`, and optional `expectedSourceVersion`. | `TDF-LEX-001`–`TDF-GRAM-002`, `TDF-TYPE-001`–`TDF-TYPE-006`, `TDF-ENT-001`–`TDF-DIR-009`, `TDF-VAL-001`, `TDF-VAL-003`, `TDF-ERR-001` |
| `bounds/` | `bounds/manifest.json` | Exact `N` (accept) and `N + 1` (`LimitExceeded`) verification across all `22` `MAX_*` constants in Section 6.2 (plus `DEFAULT_DUE_LEAD_SECONDS = 86400`), covering input parsing, raw pre-deduplication counts, supplementary Unicode scalars (`> U+FFFF`), and canonical serializer output limits. | `TDF-TYPE-001`, `TDF-VAL-002`, `TDF-SER-001` |
| `merge/` | `merge/vectors.json` | Three-way and baseline-free reconciliation, `cleanupMode` (`final` vs. `deferred`) stage fairness, occurrence-independent `history` set union, pre-cascade `scoped` label reconstruction, `location` cascade normalization, `DeletionConflict` resolution, 30-day tombstone expiry, and `RecoveryRequired` resolution. | `TDF-SYNC-001`–`TDF-SYNC-002`, `TDF-MERGE-001`–`TDF-QSYNC-001`, `TDF-PUB-001`–`TDF-REC-002` |
| `timezone/` | `timezone/vectors.json` | `Europe/Berlin` and `America/New_York` DST gaps and folds, cross-zone UTC deferral expiry, Mode 2 `due ... anchor ...` monthly clamping and interval-edit preservation, `W_due` effective priority, `downgradeTask`, and `restoreTask`. | `TDF-CTX-001`–`TDF-EVAL-005`, `TDF-CAL-001`–`TDF-CAL-003`, `TDF-OCC-001`, `TDF-MUT-001`–`TDF-MUT-008` |

## Manifest Schemas

### 1. `parse_valid/manifest.json`

Each entry in `fixtures` binds a raw `.tdf` input file to its decoded model and byte-exact canonical serialization:

- `id`: Stable fixture identifier (`pv_01_...`).
- `description`: Factual summary of the exercised grammar and normalization rules.
- `inputFile`: Input `.tdf` file (UTF-8, permitting comments, `CRLF`, single quotes, and arbitrary declaration order).
- `canonicalFile`: Expected canonical `LF`-terminated `.canonical.tdf` output (`TDF-SER-001`–`TDF-SER-004`).
- `normalizedFile`: Expected `.normalized.json` snapshot of the decoded document (`deleted`, `queue`, `labels`, `locations`, `tasks`, preserving explicit-versus-omitted `modified` timestamps and `due.anchor` local components).
- `expectedCanonicalBytes`: Exact UTF-8 byte length of `canonicalFile`.
- `expectedCanonicalLines`: Exact `LF`-terminated line count of `canonicalFile`.
- `canonicalSourceDigest`: Lowercase 64-character hexadecimal SHA-256 `sourceDigest` computed over the raw UTF-8 bytes of `canonicalFile` (`TDF-SER-005`, `TDF-MERGE-001`).
- `ruleIds`: Normative `TDF-*` Rule IDs verified by this fixture.

### 2. `parse_invalid/manifest.json`

Each entry in `fixtures` specifies an invalid `.tdf` byte stream and its deterministic rejection outcome (`TDF-VAL-001`, `TDF-ERR-001`):

- `id`: Stable fixture identifier (`pi_01_...`).
- `file`: Relative `.tdf` filename in `parse_invalid/`.
- `expectedError`: Structured error variant matching Appendix A.1.1 (camelCase `TdfErrorKind` identifier, e.g., `missingVersionHeader`, `unsupportedVersion`, `invalidBlockHeader`, `unknownDirective`, `invalidCondition`, `invalidTimestamp`, `unexpectedToken`).
- `expectedLine`: 1-based physical line number of the offending construct.
- `expectedSourceVersion`: Expected offending `<version>` token string when `expectedError` is `unsupportedVersion`, else `null`.
- `rawBytesOnly`: `true` when `file` contains ill-formed UTF-8 bytes tested directly against byte-stream entrypoints (`parseBytes`); `false` when tested across both byte and string entrypoints.
- `ruleIds`: Normative `TDF-*` Rule IDs verified by this fixture.

### 3. `bounds/manifest.json`

- `boundConstants`: Exact integer table of all `22` `MAX_*` constants and `DEFAULT_DUE_LEAD_SECONDS` from Section 6.2.
- `fileCases`: Compact on-disk boundary pairs (`acceptFile` at exact `N`, `rejectFile` at `N + 1` failing with `limitExceeded`).
- `templateCases`: Deterministic structural generator descriptors for high-cardinality document bounds (`MAX_FILE_BYTES`, `MAX_LINE_COUNT`, `MAX_BLOCKS_PER_DOC`, `MAX_LOCATIONS`, `MAX_STMTS_PER_BLOCK`, `MAX_CONDITION_RULES_PER_ENTITY`, `MAX_QUEUE_ENTRIES`, `MAX_DELETED_RECORDS`, `MAX_HISTORY_PER_TASK`, full-capacity `534`-statement canonical task, and canonical serializer byte/line overflow checks).

## Traceability Verification (`TDF-TRACE-001`)

Together, `parse_valid/manifest.json`, `parse_invalid/manifest.json`, `bounds/manifest.json`, `merge/vectors.json`, `timezone/vectors.json`, and the executable conformance harnesses (`test/services/tdf_v080_conformance_test.dart` and `test/models/tdf_v080_merge_conformance_test.dart`) verify all `30` lexical/structural/semantic/bound error codes in Appendix A.1.1, all `4` synchronization/context outcome codes in Appendix A.1.2, and all `93` normative `TDF-*` Rule IDs in Appendix A.3.
