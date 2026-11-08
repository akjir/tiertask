# TDF v0.6.0 Conformance Fixture Suite

Machine-readable conformance vectors for the TierTask Data Format (`TDF`) version `0.6.0` specification ([`spec/TDF_SPEC_0.6.0.md`](../../TDF_SPEC_0.6.0.md)).

## Directory Structure

- `parse_valid/`: Valid `tdf 0.6.0` input documents (`.tdf`), their exact canonical serialized output (`.canonical.tdf`), and normalized decoded payload representations (`.normalized.json`, including `sourceDigest`).
- `parse_invalid/`: Syntactically or semantically invalid `.tdf` documents paired with `manifest.json` specifying the mandatory `TdfErrorKind` and 1-based line number (`expectedLine`).
- `bounds/`: Boundary verification `.tdf` fixtures and `manifest.json` testing exact `N` (valid) and `N + 1` (`LimitExceeded`) resource and lexical bounds, including Unicode scalar values (`> U+FFFF` and decomposed combining marks), `MAX_LOCATIONS = 200`, `MAX_LOCATION_RADIUS = 100_000`, `MAX_NUMBER_LENGTH = 24`, and `MAX_LOCATION_REFS_PER_ENTITY = 63`.
- `merge/`: Deterministic three-way synchronization, deletion cascade, prerequisite expiry cleanup, and `DeletionConflict` test vectors (`vectors.json`).
- `timezone/`: Local calendar conversion (`Europe/Berlin` CET/CEST gaps and folds) and `repeat` + `due` + `suspended` lead-window recurrence vectors (`vectors.json`).
- `migration/`: Load-time conversion and chained migration fixtures (`0.5.1 -> 0.6.0` and `0.5.0 -> 0.5.1 -> 0.6.0`) and `manifest.json`.
