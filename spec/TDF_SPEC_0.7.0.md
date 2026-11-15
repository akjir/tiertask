# TierTask Data Format (TDF) Specification

**Version:** 0.7.0
**Status:** Working draft
**File Extension:** `.tdf`
**Character Encoding:** UTF-8

This working draft defines TDF 0.7.0. Sections remain provisional until reviewed.

Sections 1 through 9 define the current specification.
Section 10 contains import rules, load-time conversion from `0.6.0`, `0.5.1`, and `0.5.0`, and changes between adjacent versions.
Historical compatibility rules belong only in Section 10.

## 1. Overview, Architecture & Design Goals

The TierTask Data Format (`TDF`) is a deterministic, line-oriented, block-based plain-text data format for representing tasks, checklists, dependencies, label contexts, reusable geofence locations, activation conditions, deadlines, machine correlation keys, reference links, chronological task history, and scheduling states. It combines human readability in standard text editors with structured `{ ... }` blocks and single-line directives.

### 1.1 Core Philosophy: Data vs. View Separation

A `.tdf` document stores tasks, labels, reusable locations, timestamps, target deadlines, recurrence, prerequisites, machine correlation keys, links, chronological task history, checklists, activation conditions, and the shared task order.

1. **No Explicit Tier Storage:** A `.tdf` document stores no explicit tier assignment (`[1]` through `[6]`) on any task.
2. **Dynamic Derivation:** Derive all six tiers by filtering the stored order, applying effective priority (from explicit `priority` flags and approaching or overdue non-`passive` deadlines), and assigning bounded slots. Section 5 defines this process.

The document also stores recent deletion records and their deletion history generation. Queue membership and order are stored once in `queue`.

### 1.2 Core Design Principles

1. **Current Version and Root Blocks:** A current document MUST start with `tdf 0.7.0` (normal loading also accepts `tdf 0.6.0`, `tdf 0.5.1`, and `tdf 0.5.0`, converting them in memory via `0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0` under Sections 10.6 through 10.8 without writing to storage). Root blocks are `task`, `label`, `location`, `deleted`, or `queue`.
2. **No Empty Directives:** Omit optional directives that have no value, such as an unset `finished` timestamp, `suspended` deferral, `due` deadline, `origin` correlation key, `link` entry, or `history` entry. Never write a directive with empty arguments.
3. **Single-Pass Linear Grammar:** Tokenize and parse TDF in a single $O(N)$ linear pass without regular expressions or backtracking.
4. **Two-Layer Validation (Syntax vs. Domain Semantics):** The lexical and structural layers scan all identifiers and arguments as UTF-8 string tokens. The domain schema layer validates the version header, 10-character Base62 `<task-id>`, `<label-id>`, and `<location-id>` identifiers, header flags (`priority`, `scoped`, `auto-finish`), scheduling and recurrence modifiers (`forever`, `passive`, `lead`, `days`, `weeks`, `months`), ISO-8601 timestamps, 24-hour time windows, weekday tokens, booleans, finite 6-decimal geographic coordinates and 2-decimal radii, single-line `<text>` values, multi-line `<note>` values, hexadecimal colors, scheme-prefixed URIs (forbidding executable URI schemes), and cross-block references.

## 2. Lexical Elements

### 2.1 Character Encoding
- A TDF document MUST be a valid UTF-8 byte sequence.
- Reject invalid UTF-8 byte sequences, null bytes (`U+0000`), and ASCII control characters (`U+0001`–`U+001F` and `U+007F`, except `U+0009`, `U+000A`, and `U+000D` as specified below) before or during scanning (`UnexpectedToken`).
- A conforming scanner MUST respect UTF-8 character boundaries at all times.

### 2.2 Whitespace
Horizontal whitespace separates tokens within a single line and is otherwise insignificant outside of quoted strings.
- **Allowed horizontal whitespace characters:**
  - ASCII Space (`U+0020`, `' '`)
  - ASCII Horizontal Tab (`U+0009`, `'\t'`)
- Reject other Unicode whitespace outside quoted strings and comments (`UnexpectedToken`).
- Inside comments, Unicode whitespace is comment content and does not separate tokens.

### 2.3 Newlines (Line Terminators)
TDF is a line-oriented format. A newline terminates each directive and block header.
- **Allowed newline sequences:**
  - Line Feed (`LF`, `U+000A`, `"\n"`)
  - Carriage Return + Line Feed (`CRLF`, `U+000D U+000A`, `"\r\n"`)
- Reject a standalone Carriage Return (`CR`, `U+000D`) not followed by `LF` outside a double-quoted escape sequence (`UnexpectedToken`).
- Canonical serialization MUST emit `LF` (`"\n"`) line terminators.
- Ignore empty lines (containing only optional horizontal whitespace and an optional `#` comment) anywhere in the document.

### 2.4 Comments
- A comment starts with the hash character (`#`, `U+0023`) outside of a quoted string.
- The parser ignores all characters from `#` up to, but not including, the next newline (`LF`, `CRLF`) or End-Of-File (`EOF`).
- A `#` immediately after a bare word (such as `8jKaCdOkD2#comment`) terminates the token (`8jKaCdOkD2`) and starts an inline comment (`#comment`). Hash characters inside quoted strings (such as `"#4CAF50"`) are literal characters.
- Multi-line block comments are not supported.
- Comments remain subject to the UTF-8 and control-character restrictions in Section 2.1.

### 2.5 Delimiters & Reserved Punctuation
The following ASCII characters have special syntactic meaning outside of quoted strings:
- `{` (`U+007B`): Opens a block body.
- `}` (`U+007D`): Closes a block body.
- `#` (`U+0023`): Starts a line or inline comment.
- `"` (`U+0022`): Delimits a double-quoted string.
- `'` (`U+0027`): Delimits a single-quoted literal string.

### 2.6 Identifiers (Block & Directive Names)
An **Identifier** is the first token of a block header or directive.
- An Identifier MUST be an unquoted bare word. Quoted strings are forbidden as block or directive names.
- **Allowed characters:** ASCII alphanumeric characters (`a-z`, `A-Z`, `0-9`), underscore (`_`), and hyphen (`-`).
- **First character rule:** An Identifier MUST start with an ASCII alphabetic character (`a-z`, `A-Z`) or underscore (`_`). It MUST NOT start with a digit (`0-9`) or hyphen (`-`).

### 2.7 Arguments (Values)
An **Argument** represents a parameter passed to a block header or a directive. An argument can be written in one of three lexical forms:

#### A. Bare Word (Unquoted Token)
- A contiguous sequence of one or more valid UTF-8 characters excluding horizontal whitespace (`' '`, `'\t'`), newlines (`\r`, `\n`), ASCII control characters (`U+0000`–`U+001F`, `U+007F`), non-ASCII Unicode whitespace, and reserved punctuation (`{`, `}`, `#`, `"`, `'`).
- Bare words represent single-word values without spaces, including 10-character Base62 entity IDs (`8jKaCdOkD2`, `4x9p2mOkD2`, `7pQr9mOkD2`), header flags (`priority`, `scoped`, `auto-finish`), scheduling and recurrence keywords (`forever`, `passive`, `lead`, `days`, `weeks`, `months`), condition keywords (`day`, `time`, `location`, `any`), weekday tokens (`mon`..`sun`), booleans (`true`, `false`), numbers (`50.9787`, `11.0328`, `150`), and ISO-8601 date or time tokens (`2026-11-01`, `08:00`, `19:30:05`).

#### B. Double-Quoted String (`"..."`)
- Begins and ends with `"` (`U+0022`).
- Used for text with spaces or special characters, such as task, label, and location titles (`name`), entity, deferral, and deadline notes (`note`, `suspended` `"<note>"`, `due` `"<note>"`), location addresses or codes (`source`), machine correlation keys (`origin`), task and label link titles and URIs (`link`), chronological task history entries (`history <timestamp> "<text>"`), and hexadecimal colors (`"#4CAF50"`).
- May contain horizontal whitespace, `#`, `{`, `}`, and `'`.
- **Single-line constraint:** Reject unescaped raw newlines (`\r` or `\n`) inside a double-quoted string with `UnterminatedString`.
- **Escape sequences:** Backslash (`\`, `U+005C`) escapes the immediately following character:
  - `\"` -> Quotation mark (`U+0022`)
  - `\\` -> Reverse solidus / backslash (`U+005C`)
  - `\n` -> Line feed (`U+000A`)
  - `\r` -> Carriage return (`U+000D`)
  - `\t` -> Horizontal tab (`U+0009`)
- Reject any other backslash escape sequence with `InvalidEscapeSequence`.

#### C. Single-Quoted String (`'...'`)
- Begins and ends with `'` (`U+0027`).
- Literal single-line string: treat backslashes (`\`) and double quotes (`"`) as literal characters without escape processing.
- **Single-line constraint:** Reject raw newlines (`\r` or `\n`) inside a single-quoted string with `UnterminatedString`.

### 2.8 Primitive Domain Value Types
Directive and header arguments use the primitive types below during semantic validation.

Measure text lengths in Unicode scalar values after escape decoding.
A scalar value is a Unicode code point outside the surrogate range `U+D800..U+DFFF`.
Count each combining mark separately.
A scalar value above `U+FFFF` counts as one character.
Do not count UTF-8 bytes, UTF-16 code units, or grapheme clusters for text limits.
Do not normalize Unicode before counting.

- **Version (`<version>`):** Semantic version bare word written as `<MAJOR>.<MINOR>.<PATCH>` where `<MAJOR>`, `<MINOR>`, and `<PATCH>` are non-negative ASCII decimal integers (`0.7.0` for this specification).
- **Base62 Alphabet (`<base62-char>`):** The 62 ASCII alphanumeric characters `0-9` (`U+0030`–`U+0039`), `A-Z` (`U+0041`–`U+005A`), and `a-z` (`U+0061`–`U+007A`) in canonical index order (`0`..`61`):
  `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`
- **Task Entity ID (`<task-id>`):** Canonical 10-character bare word identifying a `task` block or referenced in `blocked` or `queue`, matching `<6xBase62Random><4xBase62Time>` (`[0-9A-Za-z]{10}`, such as `8jKaCdOkD2`):
  - **Random Segment (`<6xBase62Random>`):** First `6` Base62 characters (`[0-9A-Za-z]{6}`).
  - **Time Segment (`<4xBase62Time>`):** Last `4` Base62 characters (`[0-9A-Za-z]{4}`).
- **Label Entity ID (`<label-id>`):** Canonical 10-character bare word identifying a `label` block or referenced in `labels`, matching `<6xBase62Random><4xBase62Time>` (`[0-9A-Za-z]{10}`, such as `4x9p2mOkD2`):
  - **Random Segment (`<6xBase62Random>`):** First `6` Base62 characters (`[0-9A-Za-z]{6}`).
  - **Time Segment (`<4xBase62Time>`):** Last `4` Base62 characters (`[0-9A-Za-z]{4}`).
- **Location Entity ID (`<location-id>`):** Canonical 10-character bare word identifying a `location` block or referenced in `condition` `location` rules, matching `<6xBase62Random><4xBase62Time>` (`[0-9A-Za-z]{10}`, such as `7pQr9mOkD2`):
  - **Random Segment (`<6xBase62Random>`):** First `6` Base62 characters (`[0-9A-Za-z]{6}`).
  - **Time Segment (`<4xBase62Time>`):** Last `4` Base62 characters (`[0-9A-Za-z]{4}`).
- **Entity ID Validation:** Entity ID components in headers, references, and deletion records MUST match `[0-9A-Za-z]{10}`. IDs and prerequisite reference tokens MUST be unquoted. A prerequisite token may append its requirement under Section 6.9. Quoted or malformed ID components produce `InvalidIdentifier`. Parsing MUST preserve valid IDs and requirements without generating replacements.
- **Single-Line Text (`<text>`) & Multi-Line Note (`<note>`):**
  - **Single-Line `<text>` (`task.name`, `label.name`, `location.name`, `location.source`, `subtasks` `step` `<text>`, `task.link` and `label.link` `<title>`, `origin` `"<namespace>"` and `"<external-key>"`, and `history <timestamp> "<text>"`):** Quoted string (`"..."` or `'...'` in input, emitted as double-quoted `"..."` canonically) containing `1..MAX_TEXT_LENGTH` (`500`) decoded Unicode scalar values after unescaping (`\"` and `\\` in `"..."`) without Unicode normalization. Unknown backslash escape sequences inside double-quoted strings fail at the lexical layer with `InvalidEscapeSequence` (Section 2.7.B). Check single-line and surrogate constraints **before** emptiness: after unescaping, a single-line `<text>` value MUST NOT contain a newline (`\n`, `0x0A`), carriage return (`\r`, `0x0D`), horizontal tab (`\t`, `0x09`), or an unpaired UTF-16 surrogate (`U+D800..U+DFFF`); if present (whether produced by `\n`, `\r`, `\t` escape sequences in a double-quoted string, a literal horizontal tab in a quoted string, or an unpaired surrogate), report `UnexpectedToken`. Next, if the decoded string is empty (`""`) or contains only ASCII spaces (`0x20`), report `EmptyText` (non-ASCII Unicode whitespace such as `U+00A0` is treated as graphic character content). If it exceeds `MAX_TEXT_LENGTH` (`500`) decoded Unicode scalar values, report `LimitExceeded`.
  - **Multi-Line `<note>` (`task.note`, `label.note`, `location.note`, `suspended` `"<note>"`, and `due` `"<note>"`):** Quoted string (`"..."` or `'...'` in input, emitted as double-quoted `"..."` canonically on a single physical `.tdf` line with `\"`, `\\`, `\n`, `\r`, and `\t` escapes) containing `1..MAX_NOTE_LENGTH` (`2000`) decoded Unicode scalar values after unescaping without Unicode normalization or `\r\n` / `\r` -> `\n` line-ending collapsing. Escaped `\n`, `\r`, and `\t` (and literal horizontal tabs) are permitted in `<note>`. Unpaired UTF-16 surrogates (`U+D800..U+DFFF`) report `UnexpectedToken` (checked before emptiness). If the decoded string is empty (`""`) or contains only ASCII whitespace characters (`0x20`, `\t` `0x09`, `\n` `0x0A`, or `\r` `0x0D`) after unescaping, report `EmptyText` (non-ASCII Unicode whitespace such as `U+00A0` is treated as graphic character content); if it exceeds `MAX_NOTE_LENGTH` (`2000`), report `LimitExceeded`.
- **Boolean (`<bool>`):** Exact case-sensitive bare word `true` or `false`.
- **Weekday (`<weekday>`):** Exact case-sensitive lowercase bare word from the set `mon`, `tue`, `wed`, `thu`, `fri`, `sat`, `sun`.
- **Time of Day (`<time>`):** 24-hour minute-precision local wall-clock time written as `<HH:MM>` (`00..23` hours, `00..59` minutes, such as `08:00` or `18:00`).
- **Timestamp (`<timestamp>`):** ISO-8601 date with optional 24-hour time (minute or second precision), written as either:
  - One bare-word token: `<YYYY-MM-DD>` (such as `2026-11-01`).
  - Two whitespace-separated bare-word tokens: `<YYYY-MM-DD> <HH:MM[:SS]>` (such as `2026-11-01 19:30` or `2026-11-01 19:30:05`), where month `MM` is `01..12`, `DD` is valid for the calendar month and year, `HH` is `00..23`, minute `MM` is `00..59`, and optional `SS` is `00..59`.
  - **Timestamp Semantics:** All stored timestamps (`created`, `finished`, `modified`, `due`, `history`, deletion revisions, and finite `suspended` values) represent UTC instants. Recurrence clocks and day/time conditions use the configured local calendar. Section 6.10 defines conversion, display, and daylight-saving rules.
  - Date-only timestamps default to `00:00:00` for chronological ordering and comparison. Minute-precision timestamps (`<HH:MM>`) default to `:00` seconds (`<HH:MM:00>`).
  - Explicit seconds support revision advancement under Sections 6.7 and 6.11.
  - **Calendar:** Use the proleptic Gregorian calendar for all dates and calendar calculations.
    Years use four ASCII digits in `0001..9999`.
    Reject year `0000` with `InvalidTimestamp`.
    A leap year is divisible by four, except century years not divisible by 400.
  - **Supported Range:** Accept UTC instants from `0001-01-01 00:00:00` through `9999-12-31 23:59:59`, inclusive.
    Local calendar values used during conversion or recurrence MUST remain within the same year range.
    Reject out-of-range input, conversion, or arithmetic results with `InvalidTimestamp`.
    Reject the complete affected mutation without partial changes.
- **Floating-Point / Numeric (`<number>`):** Unquoted finite ASCII decimal number (`-?[0-9]+(\.[0-9]+)?`) used in `location` blocks for `coordinates <lat> <lon>` (`<lat>` in `[-90.0, 90.0]`, `<lon>` in `[-180.0, 180.0]` in WGS-84 decimal degrees) and `radius <meters>` ($0 < \text{meters} \le \text{MAX\_LOCATION\_RADIUS} = 100\,000$).
  - A `<number>` token exceeding `MAX_NUMBER_LENGTH` (`24` ASCII characters) MUST fail with `LimitExceeded`.
  - Non-finite or non-decimal literals (`NaN`, `Infinity`, `-Infinity`, leading `+`, scientific notation such as `1e5` or `1E-3`, or any token not matching `-?[0-9]+(\.[0-9]+)?`) MUST fail with `InvalidNumber`.
  - **Precision & Range Bounds:** After stripping trailing fractional zeros under Section 6.7.3, `<lat>` and `<lon>` in native `tdf 0.7.0` (and `tdf 0.6.0`) documents MUST have at most **6 fractional decimal digits** ($\approx 11\text{ cm}$ resolution; inputs with $> 6$ non-zero fractional digits or outside `[-90.0, 90.0]` / `[-180.0, 180.0]` fail with `InvalidNumber`), and `<radius>` MUST have at most **2 fractional decimal digits** and satisfy $0 < \text{meters} \le \text{MAX\_LOCATION\_RADIUS}$ (`InvalidNumber` if $\le 0$ or $> 2$ non-zero fractional digits; `LimitExceeded` if $> \text{MAX\_LOCATION\_RADIUS}$). Canonical serialization emits `<lat>`, `<lon>`, and `<meters>` using the Section 6.7.3 normalized decimal representation (`-0.0` normalized to `0`, redundant leading integer zeros and trailing fractional zeros removed).
- **Hexadecimal Color (`<color>`):** Quoted 7-character string `"#RRGGBB"` or `'#RRGGBB'` where each digit is in `0-9`, `a-f`, or `A-F`. Because `#` outside quotes starts a comment (Section 2.4), `<color>` values MUST be quoted. Canonical serialization emits double-quoted `"#RRGGBB"`.
- **URI (`<uri>`):** Quoted string (`"..."` or `'...'` in input, emitted as double-quoted `"..."` canonically) containing a non-empty single-line URI (`1..MAX_URI_LENGTH` decoded Unicode scalar values after unescaping without Unicode normalization) with a scheme prefix matching `[a-zA-Z][a-zA-Z0-9+.-]*:` (such as `https://...`, `http://...`, `file://...`, or `mailto:...`):
  - **Precedence, Whitespace, Length & Control-Character Rules:** Unknown backslash escape sequences inside double-quoted strings fail at the lexical layer with `InvalidEscapeSequence` (Section 2.7.B), and unpaired UTF-16 surrogates (`U+D800..U+DFFF`) fail with `UnexpectedToken`. After unescaping, if the decoded `<uri>` string is empty (`""`) or contains only ASCII whitespace characters (`0x20`, `\t` `0x09`, `\n` `0x0A`, or `\r` `0x0D`), report `EmptyText` before length or scheme validation (non-ASCII Unicode whitespace such as `U+00A0` is treated as graphic character content). If the decoded `<uri>` exceeds `MAX_URI_LENGTH` (`2048`) decoded Unicode scalar values, report `LimitExceeded`. A decoded `<uri>` MUST NOT contain a newline (`\n`, `0x0A`), carriage return (`\r`, `0x0D`), horizontal tab (`\t`, `0x09`), or any other ASCII control character; if present, report `InvalidUri`.
  - **Executable URI Scheme Prohibition:** If a non-blank `<uri>` lacks a scheme prefix matching `[a-zA-Z][a-zA-Z0-9+.-]*:` or uses a forbidden executable or script/data-bearing scheme (`javascript:`, `vbscript:`, or `data:`, matched case-insensitively on the scheme prefix), fail deterministically with `InvalidUri`.
  - Double quotes treat `#` (URI fragments) and spaces in file paths as literal characters rather than comments or token delimiters.
  - Parsing performs no filesystem existence or network reachability check so platform-specific links (`file://...`) remain portable across operating systems. The consuming application resolves and opens URIs.
- **Recurrence Rule (`<repeat>`):** Two to six unquoted tokens: `<count> <unit> [<repeat-time>] [lead <lead-count> days]`. Both `<count>` and optional `<lead-count>` are canonical positive ASCII decimal integers without sign or leading zeros in `1..MAX_REPEAT_COUNT` (`3650`; `InvalidNumber` if quoted, non-integer, signed, leading-zero, or `0`; `LimitExceeded` if raw ASCII length exceeds `MAX_NUMBER_LENGTH` (`24`) or value exceeds `MAX_REPEAT_COUNT`). `<unit>` is `days`, `weeks`, or `months`. The optional local clock `<repeat-time>` defaults to midnight (`00:00:00`), and the optional `lead <lead-count> days` clause specifies a calendar-day preparation lead offset before `due` (defaulting to `0` days when omitted). Sections 4.1.2, 6.4, and 6.10.3 define token disambiguation, completion-relative and `due`-anchored calculation, and canonical serialization.

- **Deletion History Generation (`<generation>`):** An unquoted non-negative decimal integer in `0..MAX_SYNC_GENERATION`.
  Use ASCII digits without leading zeros, except for `0`.
  Quoted, signed, malformed, or negative values produce `InvalidNumber`.
  Values above the bound produce `LimitExceeded`.
- **Deletion Revision:** A UTC `<timestamp>` attached to a `task`, `label`, or `location` record in `deleted`.

- **Completion Count (`<completion-count>`):** An unquoted ASCII decimal integer in `0..MAX_COMPLETIONS`.
  Use no sign or leading zeros, except for the value `0`.
  Invalid literals produce `InvalidNumber` and values above the bound produce `LimitExceeded`.
- **Prerequisite Reference (`<dependency>`):** An unquoted `<task-id>` with an optional `:<required-completion>` suffix.
  The required completion is in `1..MAX_COMPLETIONS`.
  An omitted suffix means `1`.
  The ID component follows the normal entity ID rules.
  Section 6.9 defines arming, evaluation, and occurrence changes.

- **Repeat Clock (`<repeat-time>`):** An unquoted local clock written as `HH:MM` or `HH:MM:SS`.
  Hours are `00..23`, minutes and seconds are `00..59`, and omitted seconds mean zero.
  Invalid or quoted values produce `InvalidTime`.
- **Deferral (`<deferral>`):** A finite UTC `<timestamp>` or the exact unquoted token `forever`, followed by an optional trailing quoted `<note>` (`1..MAX_NOTE_LENGTH`).
  Omission means no deferral and no deferral note.
  Invalid finite timestamp values or a quoted leading token produce `InvalidTimestamp`; non-final quoted tokens or malformed/unquoted trailing arguments produce `UnexpectedToken` (Section 4.1.2).
- **Target Deadline (`due` arguments):** A UTC `<timestamp>`, followed by an optional occurrence-scoped unquoted `passive` modifier and an optional trailing quoted `<note>` (`1..MAX_NOTE_LENGTH`).
  Omission of `passive` enables Section 5.5 lead-window effective priority (`passive` = `false`); presence of `passive` opts the active deadline occurrence out of lead-window effective priority (`passive` = `true`).
  Invalid timestamp values or a quoted leading token produce `InvalidTimestamp`; non-final quoted tokens (such as `due <timestamp> "<note>" passive`), duplicate `passive`, or extra/unquoted trailing arguments produce `UnexpectedToken` (Section 4.1.2).

### 2.9 Mandatory Entity ID Generation & Identity Rules
Generate a new 10-character Base62 ID only when creating a new `task`, `label`, or `location` entity. Use the following algorithm.
1. **6-Character Cryptographic Random Segment (`<6xBase62Random>`):** Generate `6` independent random characters uniformly from the 62-character Base62 alphabet (`0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`) using a cryptographically secure random number generator ($62^6 = 56,800,235,584$ combinations).
2. **4-Character Rolling UTC Seconds Segment (`<4xBase62Time>`):**
   - Take the current UTC timestamp in whole Unix seconds (`unixUtcSeconds = floor(nowUtcMilliseconds / 1000)`).
   - Compute the rolling modulo value: `timeValue = unixUtcSeconds mod 14776336` ($62^4 = 14,776,336$, covering a rolling ~171-day cycle at 1-second resolution).
   - Encode `timeValue` into Base62 as `4` characters (most significant digit first, left-padded with `0`).
3. **Concatenation:** Concatenate `<6xBase62Random>` and `<4xBase62Time>` into `<6xBase62Random><4xBase62Time>`.
4. **In-Memory Uniqueness Check:** Reject generated IDs already present in entity blocks, references, or retained deletion records. Generate another candidate until it is unique.
5. **Read-Only Loading:** Loading MUST preserve entity IDs and references. It MUST NOT generate IDs, repair identifiers, serialize documents, or persist data.
6. **Immutable Identity:** An entity ID MUST remain unchanged throughout the entity's lifetime. Loading, editing, serialization, and synchronization MUST preserve it.

## 3. Structural Grammar

### 3.1 Document Structure & Nesting Depth
A TDF document consists of a mandatory root-level **Version Header** (`tdf 0.7.0`) followed by zero or more root-level **Blocks**.
- **Nesting Depth Definition:** Nesting depth equals the number of open `{ ... }` blocks:
  - Depth `0` (document root): Permit the initial version header, `task`, `label`, `location`, `deleted`, and `queue` blocks, blank lines, and comments.
  - Depth `1`: Permit root-block directives and schema-defined nested blocks. The `location`, `deleted`, and `queue` blocks permit directives only and forbid nested blocks (`UnknownBlockType`).
  - Depth `2` (inside `subtasks` or `condition`): Permit only `step`, `day`, `time`, and `location` directives. Forbid further nested blocks (`MAX_NESTING_DEPTH = 2`).
- **Mandatory Version Header:** Every valid `.tdf` document MUST begin with `tdf 0.7.0` at depth `0` before any root block, preceded only by optional blank lines and `#` comments. Normal loading also accepts `tdf 0.6.0`, `tdf 0.5.1`, and `tdf 0.5.0`, converting them in memory via `0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0` under Sections 10.6 through 10.8 without writing to storage during read-only loading. Reject a file with no statements or whose first statement is not `tdf <version>` with `MissingVersionHeader`. A file containing `tdf 0.7.0` and zero root blocks is a valid empty TDF document.
- **Root-Level Directive Prohibition:** Reject any directive at depth `0` other than the initial `tdf` version header, including a later duplicate `tdf` directive, with `UnexpectedRootDirective`.

### 3.2 Blocks
A **Block** groups related directives and optional nested sub-blocks under a named context.

```text
<identifier> [<argument> ...] {
    <statement> ...
}
```

- **Block Header:** An Identifier, followed by zero or more whitespace-separated Arguments, followed by the opening brace `{`. Parameterless sub-blocks (`subtasks {` and `condition {`) and root metadata blocks (`deleted {` and `queue {`) take zero arguments.
- **Opening Brace Placement:** Place `{` on the same line as the block Identifier and its arguments, separated from the preceding token by at least one horizontal whitespace character (such as `task 8jKaCdOkD2 {`, `task 8jKaCdOkD2 priority {`, `label 4x9p2mOkD2 {`, `label 4x9p2mOkD2 scoped {`, `location 7pQr9mOkD2 {`, `subtasks auto-finish {`, or `condition {`).
- **After Opening Brace:** Only optional horizontal whitespace and an optional `#` comment may follow `{` before the line terminator (`\n` or `\r\n`).
- **Block Body:** Contains zero or more statements (Directives or nested Blocks), each on its own logical line.
- **Closing Brace Placement:** Close every block with `}` on its own logical line, preceded only by optional horizontal whitespace and followed only by optional horizontal whitespace, an optional `#` comment, and a newline or `EOF`. Forbid inline empty blocks (`{}`) on a single line.
- **Empty Blocks:** A task requires `name` and `created`. A label requires `name`. A location requires `name`, `coordinates`, and `radius`. A deletion block requires `generation`. A queue requires `modified`. Condition and checklist blocks require a rule or step. Reject missing requirements with `MissingRequiredDirective`.

### 3.3 Directives
A **Directive** is a single-line key-value or key-tuple instruction.

```text
<identifier> <argument> [<argument> ...]
```

- **Scope:** Except for the initial `tdf 0.7.0` version header at depth `0` (Section 4.0), every directive MUST reside inside a block (depth `1` or `2`). Reject any other directive at depth `0` with `UnexpectedRootDirective`.
- **Minimum Arity (No Empty Directives):** A directive requires an Identifier followed by at least one Argument separated by horizontal whitespace. Reject a standalone identifier inside a block without arguments and without `{` with `MissingDirectiveArgument`. Omit optional directives that have no value.
- **Termination:** A newline (`LF` or `CRLF`) terminates each directive. Reaching `EOF` on a block directive line without a closing `}` on a subsequent line produces `UnclosedBlock`. Semicolons (`;`) do not terminate statements; a trailing `;` on an unquoted token is part of that bare word.
- **Ordering & Multiplicity:** Preserve declaration order while parsing (normalizing unordered/sorted directives during model construction and canonical serialization as specified in Sections 4 and 6.7.3). Repeatable directives exempt from `DuplicateDirective` are `link` (`0..MAX_LINKS_PER_TASK` on `task` and `0..MAX_LINKS_PER_LABEL` on `label`), `history` (`0..MAX_HISTORY_PER_TASK` on `task`), `condition` (`0..MAX_CONDITION_RULES_PER_ENTITY` on `task` and `label`), checklist `step` directives inside `subtasks`, deletion records (`task`, `label`, `location`) inside `deleted`, and `task` entries inside `queue`. Single-valued `task` directives (`name`, `note`, `created`, `finished`, `modified`, `completions`, `repeat`, `labels`, `blocked`, `suspended`, `due`, `origin`), single-valued `label` directives (`name`, `color`, `note`, `modified`), and single-valued `location` directives (`name`, `note`, `source`, `coordinates`, `radius`, `modified`) permit at most one occurrence per enclosing block. Permit one `subtasks` block per task, one `deleted` block per document, and one `queue` block per document. Report repeated singleton directives or blocks as `DuplicateDirective`.

### 3.4 Formal Grammar (EBNF)

```ebnf
(* Document Root: Mandatory Version Header followed by Blocks, Comments, and Blank Lines *)
document        = { empty-line } version-header { empty-line | root-block } [ trailing-empty ] ;

version-header  = ws* "tdf" ws+ "0.7.0" ws* [ comment ] newline ;

root-block      = task-block
                | label-block
                | location-block
                | deleted-block
                | queue-block ;

queue-block     = ws* "queue" ws+ "{" ws* [ comment ] newline
                  { empty-line | queue-modified-dir | queue-task-dir }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

queue-modified-dir = ws* "modified" ws+ timestamp ws* [ comment ] newline ;
queue-task-dir  = ws* "task" ws+ task-id ws* [ comment ] newline ;

deleted-block   = ws* "deleted" ws+ "{" ws* [ comment ] newline
                  { empty-line | generation-dir | deleted-task-dir | deleted-label-dir | deleted-location-dir }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

generation-dir  = ws* "generation" ws+ bare-word ws* [ comment ] newline ;
deleted-task-dir = ws* "task" ws+ task-id ws+ timestamp [ ws+ completion-count ] ws* [ comment ] newline ;
deleted-label-dir = ws* "label" ws+ label-id ws+ timestamp ws* [ comment ] newline ;
deleted-location-dir = ws* "location" ws+ location-id ws+ timestamp ws* [ comment ] newline ;
timestamp       = date [ ws+ clock ] ;
date            = digit digit digit digit "-" digit digit "-" digit digit ;
clock           = digit digit ":" digit digit [ ":" digit digit ] ;
digit           = "0".."9" ;

(* Root & Sub-Blocks: task-block permits task directives (including link and history) and condition/subtasks blocks;
   label-block permits label directives (including link) and condition blocks *)
task-block      = ws* "task" ws+ task-id [ ws+ "priority" ] ws+ "{" ws* [ comment ] newline
                  { block-item }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

label-block     = ws* "label" ws+ label-id [ ws+ "scoped" ] ws+ "{" ws* [ comment ] newline
                  { block-item }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

location-block  = ws* "location" ws+ location-id ws+ "{" ws* [ comment ] newline
                  { empty-line | directive }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

block           = ws* identifier { ws+ argument } ws+ "{" ws* [ comment ] newline
                  { block-item }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

block-item      = empty-line
                | block
                | directive ;

(* Directives: Must contain at least one argument and end with a newline *)
directive       = labels-dir
                | blocked-dir
                | suspended-dir
                | due-dir
                | origin-dir
                | repeat-dir
                | history-dir
                | ws* link-directive ws* [ comment ] newline
                | ws* identifier ws+ argument { ws+ argument } ws* [ comment ] newline ;

labels-dir      = ws* "labels" ws+ label-id { ws+ label-id } ws* [ comment ] newline ;
blocked-dir     = ws* "blocked" ws+ dependency { ws+ dependency } ws* [ comment ] newline ;
dependency      = task-id [ ":" positive-count ] ;
completion-count = "0" | positive-count ;
positive-count  = "1".."9" { "0".."9" } ;
link-directive  = "link" ws+ ( quoted-string | single-string ) ws+ ( quoted-string | single-string ) ;
suspended-dir   = ws* "suspended" ws+ ( "forever" | timestamp ) [ ws+ ( quoted-string | single-string ) ] ws* [ comment ] newline ;
due-dir         = ws* "due" ws+ timestamp [ ws+ "passive" ] [ ws+ ( quoted-string | single-string ) ] ws* [ comment ] newline ;
origin-dir      = ws* "origin" ws+ ( quoted-string | single-string ) ws+ ( quoted-string | single-string ) ws* [ comment ] newline ;
repeat-dir      = ws* "repeat" ws+ positive-count ws+ repeat-unit [ ws+ clock ] [ ws+ "lead" ws+ positive-count ws+ "days" ] ws* [ comment ] newline ;
repeat-unit     = "days" | "weeks" | "months" ;
history-dir     = ws* "history" ws+ timestamp ws+ ( quoted-string | single-string ) ws* [ comment ] newline ;

(* Entity Identifiers: Mandatory 10-Character Base62 Format *)
task-id         = base62-random base62-time ;
label-id        = base62-random base62-time ;
location-id     = base62-random base62-time ;
base62-random   = base62-char base62-char base62-char base62-char base62-char base62-char ;
base62-time     = base62-char base62-char base62-char base62-char ;
base62-char     = "0".."9" | "A".."Z" | "a".."z" ;

(* Lexical Tokens *)
identifier      = id-start { id-continue } ;
id-start        = "a".."z" | "A".."Z" | "_" ;
id-continue     = id-start | "0".."9" | "-" ;

argument        = quoted-string
                | single-string
                | bare-word ;

bare-word       = bare-char { bare-char } ;
bare-char       = ? any UTF-8 char except ASCII control chars (U+0000..U+001F, U+007F),
                    whitespace, '{', '}', '#', '"', '\'' ? ;

quoted-string   = '"' { quoted-char | escape-seq } '"' ;
quoted-char     = ? any UTF-8 char except '"', '\\', '\r', '\n', and ASCII control chars
                    (U+0000..U+001F except '\t', U+007F) ? ;
escape-seq      = "\\" ( '"' | "\\" | "n" | "r" | "t" ) ;

single-string   = "'" { single-char } "'" ;
single-char     = ? any UTF-8 char except '\'', '\r', '\n', and ASCII control chars
                    (U+0000..U+001F except '\t', U+007F) ? ;

(* Whitespace & Comments *)
empty-line      = ws* [ comment ] newline ;
trailing-empty  = ws* [ comment ] eof ;
comment         = "#" { ? any UTF-8 char except '\r', '\n', and ASCII control chars
                          (U+0000..U+001F except '\t', U+007F) ? } ;
ws              = " " | "\t" ;
newline         = "\n" | "\r\n" ;
```

## 4. Domain Schema: Version Header, Root Blocks, Sub-Blocks & Directives

At depth `0`, a document MUST start with the version header from Section 4.0. Permit root blocks from Sections 4.1, 4.2, 4.3, 4.5, and 4.6. Reject other root directives with `UnexpectedRootDirective` and other root blocks with `UnknownBlockType`.

### 4.0 The `tdf` Version Header

Every `.tdf` document MUST begin with a single-line `tdf` version header at depth `0` before any root block:

```text
tdf 0.7.0
```

- **First Statement Requirement:** `tdf 0.7.0` MUST be the first statement of every current `.tdf` document (preceded only by optional blank lines and `#` comments) and is the only directive permitted at depth `0`.
- **Version Argument & `0.6.0` / `0.5.1` / `0.5.0` Load-Time Conversion:** The header MUST contain one unquoted version token, `0.7.0` (or `0.6.0`, `0.5.1`, or `0.5.0` when loading a previous document). When a loader encounters `tdf 0.6.0`, it MUST validate the input against the `0.6.0` schema (`MAX_STMTS_PER_BLOCK = 512`) and convert it in memory to `0.7.0` under Section 10.8 without writing to storage during read-only loading (requiring an available `timeZone` parameter whenever an open task carries `repeat`, `due`, and a finite `suspended < due`, and returning `ImportContextRequired` when unavailable). When a loader encounters `tdf 0.5.1` or `tdf 0.5.0`, it MUST execute the chained in-memory conversion `0.5.1 -> 0.6.0 -> 0.7.0` or `0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0` under Sections 10.6 through 10.8 without writing to storage during read-only loading.
- **Validation Rules:**
  - Reject a file with no statements or whose first statement is not `tdf <version>` with `MissingVersionHeader`.
  - Reject any `<version>` other than `0.7.0` (and `0.6.0`, `0.5.1`, or `0.5.0` during load-time conversion), a quoted version token, or extra header arguments with `UnsupportedVersion`.
  - Reject a duplicate `tdf` directive later at depth `0` with `UnexpectedRootDirective`.
- **Serializer Output:** A canonical TDF serializer MUST emit `tdf 0.7.0` as the first statement of every output document, including an empty board.

### 4.1 The `task` Block (Tasks)

Represent each task as a root-level `task` block (header at depth `0`, body at depth `1`).

```text
task <task-id> [priority] {
    ...
}
```

#### 4.1.1 Header Parameters
1. `<task-id>` (**Required**, Bare Word `<task-id>`): Unique 10-character Base62 task identifier across all `task` blocks in the document, matching `<6xBase62Random><4xBase62Time>` (`[0-9A-Za-z]{10}`, such as `8jKaCdOkD2`; see Sections 2.8 and 2.9).
   - Reject a quoted or noncanonical `<task-id>` with `InvalidIdentifier`. Preserve each valid ID.
2. `priority` (**Optional**, Bare Word Flag): Grants explicit priority so eligible prioritized tasks enter the effective-priority partition ahead of regular tasks under Section 5.5.
   - **When present:** Places the task in the effective-priority partition of Section 5.5 Step 2 in its saved `queue` order.
   - **When omitted:** Places the task in the effective-priority partition only while an approaching or overdue non-`passive` `due` deadline grants derived effective priority under Section 5.5 Step 2; otherwise places the task in the regular partition in its saved `queue` order, after all eligible effective-priority tasks.
- A missing `<task-id>`, extra header argument, or unknown header flag MUST produce `InvalidBlockHeader`. A quoted or noncanonical `<task-id>` MUST produce `InvalidIdentifier`.

#### 4.1.2 Directives in `task`

| Directive | Required | Multiplicity | Format / Arguments | Semantics When Present / Omitted |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Human-readable single-line title of the task (`1..MAX_TEXT_LENGTH` characters). Required in every `task` block. |
| `note` | No | `0..1` | `"<note>"` | Optional standing description or instructions (`1..MAX_NOTE_LENGTH` characters). **When omitted**, the task has no extended note. |
| `created` | Yes | `1` | `<YYYY-MM-DD> [<HH:MM[:SS]>]` | Creation timestamp of the task in UTC. Required in every `task` block. |
| `finished` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM[:SS]>]` | UTC completion timestamp. Its presence places the task in `Completed`. Completed tasks MUST NOT appear in `queue`. Retention pruning after more than 30 days creates a deletion record under Section 6.8. |
| `modified` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM[:SS]>]` | UTC entity revision timestamp. Section 6.7.1 defines its effective value when omitted. Section 6.7 defines synchronization and revision updates. |
| `completions` | No | `0..1` | `<completion-count>` | Monotonic completion counter, defaulting to zero. A finished task requires a positive explicit value. Section 6.9 defines occurrence behavior. |
| `repeat` | No | `0..1` | `<count> <days\|weeks\|months> [<repeat-time>] [lead <lead-count> days]` | Local calendar recurrence with an optional local wake-up clock (defaulting to `00:00:00`) and an optional calendar-day preparation lead offset before `due` (`1..MAX_REPEAT_COUNT`, defaulting to `0` days when omitted). Completion keeps the task open, advances its counter, resets its checklist, clears any `suspended` note, preserves `origin` and `history`, and schedules its next occurrence (completion-relative when `due` is omitted, ignoring `lead`; or anchored to `due`'s fixed local schedule at `newDueLocalDate - leadDays` when `due` is present, preserving `due`'s note and resetting `passive` to omitted). Sections 6.4, 6.9, and 6.10.3 define the transition. |
| `labels` | No | `0..1` | `<label-id1> [<label-id2> ...]` | One or more label IDs assigned to the task. Each argument MUST be an unquoted 10-character Base62 ID (`InvalidIdentifier` otherwise). Each ID MUST match a declared label (`UnknownLabelReference` otherwise). Assigned labels provide context filtering (`scoped` vs. regular) and condition inheritance. Omission means no label assignment. |
| `blocked` | No | `0..1` | `<dependency> [<dependency> ...]` | Stored prerequisite completion requirements. Each token contains a canonical task ID and optional required completion number. Section 6.9 defines capture and evaluation. Unknown forward-reference targets (absent from both live `task` blocks and `deleted`) remain non-blocking and are preserved across parsing, loading, and mutations. Confirmed deleted targets (in `deleted`) and satisfied non-recurring-to-recurring targets on open tasks are stripped during committed mutations and refresh/synchronization (Sections 6.6, 6.7.5, and 6.8.1), while live recurring-to-recurring dependencies remain stored until the dependent recurring task completes its occurrence. Target IDs MUST NOT form dependency cycles. |
| `suspended` | No | `0..1` | `(<timestamp> \| forever) ["<note>"]` | A finite UTC deferral or indefinite suspension, with an optional trailing quoted deferral `<note>` (`1..MAX_NOTE_LENGTH` scalar values). Active strictly while `forever` or `suspended > now` in UTC, blocking an open task before other restrictions are evaluated. Expired finite `suspended <= now` deferrals (together with any attached `suspended` note) evaluate as non-blocking immediately and are stripped from open tasks during committed mutations and refresh/synchronization (Sections 6.6, 6.7.5, and 6.10.1). |
| `due` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM[:SS]>] [passive] ["<note>"]` | Non-blocking target deadline in UTC, converted from local calendar input under Section 6.10, with an optional occurrence-scoped `passive` modifier and an optional trailing quoted deadline `<note>` (`1..MAX_NOTE_LENGTH` scalar values). Imposes no ordering constraint against `suspended` and never places a task into `Blocked`. When `passive` is omitted, an eligible scheduled task in `queue` gains derived effective priority in Section 5.5 once `due <= now + W_due` (without mutating storage); when `passive` is present, `due` opts out of effective priority for the active deadline occurrence. Overdue deadlines (`due <= now`) and their notes remain intact on open tasks. Acts as the fixed local calendar anchor when combined with `repeat` (Sections 5.5, 6.3, 6.4, 6.6, and 6.10.3). |
| `origin` | No | `0..1` | `"<namespace>" "<external-key>"` | Optional passive machine correlation key (`1..MAX_TEXT_LENGTH` single-line `<text>` values per argument, non-unique across distinct `task` blocks). Preserved across completion, recurrence, and restoration, and merged as one atomic `(namespace, externalKey)` scalar pair (Sections 6.4, 6.5, 6.6, and 6.7). |
| `link` | No | `0..MAX_LINKS_PER_TASK` | `"<title>" "<uri>"` | Repeatable user-facing external or local URI link (`0..20` per `task`) in declaration order. `<title>` is a non-empty single-line `<text>` label (`1..MAX_TEXT_LENGTH`). `<uri>` is a non-empty single-line quoted URI (`1..MAX_URI_LENGTH`, forbidding decoded `\n`, `\r`, `\t`, or other ASCII control characters with `InvalidUri`) with a non-executable scheme prefix (`[a-zA-Z][a-zA-Z0-9+.-]*:`, forbidding `javascript:`, `vbscript:`, and `data:`). Omission means no links. |
| `history` | No | `0..MAX_HISTORY_PER_TASK` | `<YYYY-MM-DD> [<HH:MM[:SS]>] "<text>"` | Repeatable non-blocking chronological task journal entry (`0..500` raw directives per `task`, counted before deduplication). `<timestamp>` is a UTC instant (`0001-01-01 00:00:00..9999-12-31 23:59:59` UTC) and `"<text>"` is a single-line `<text>` value (`1..MAX_TEXT_LENGTH`). Deduplicated and sorted canonically by ascending UTC timestamp then unsigned UTF-8 byte order of decoded `<text>`. Preserved permanently across completion, recurrence, and restoration, and reconciled via occurrence-independent set merge (Sections 5, 6.4, 6.5, 6.6, and 6.7). Omission means `0` history entries. |
| `condition` | No | `0..N` | `<type> <args...>`, `<type> any`, `any`, or `{ ... }` | Task-level activation conditions (`day`, `time`, `location`), group resets (`day any`, `time any`, `location any`), or global reset (`condition any`), written inline or as a `condition { ... }` block (Section 4.4). `condition any` disables all inherited `label` conditions. Group rules and group resets override only that rule group from assigned labels while preserving other inherited groups and the task's `labels` assignment. |

- **No `queued` Directive in `0.7.0`:** Membership in the root `queue { ... }` block (Section 4.6) is the sole source of truth for whether an open task is scheduled into the active pull cycle. Encountering `queued` inside a `task` block in a `tdf 0.7.0`, `tdf 0.6.0`, or `tdf 0.5.1` document MUST trigger `UnknownDirective` (Section 8). When loading a `tdf 0.5.0` document, `queued` is validated under `0.5.0` rules and stripped during load-time conversion (Section 10.6).

**Canonical `task` Directive Serialization Order (16 Directives & Sub-Blocks):**
A canonical serializer MUST emit present directives and sub-blocks inside each `task` block in this exact 16-position order:
1. `name`
2. `note`
3. `created`
4. `finished`
5. `modified`
6. `completions` (omitted when `0`, emitted when `>= 1`)
7. `repeat` (emitted as `repeat <count> <days|weeks|months> [<HH:MM[:SS]>] [lead <lead-count> days]`, omitting midnight `00:00:00` and omitting `lead` when `0`)
8. `labels` (sorted ascending by ASCII ID, deduplicated)
9. `blocked` (sorted ascending by ASCII target ID, `:1` suffix omitted)
10. `suspended` (emitted as `suspended (<YYYY-MM-DD HH:MM:SS> | forever) ["<note>"]` in UTC)
11. `due` (emitted as `due <YYYY-MM-DD HH:MM:SS> [passive] ["<note>"]` in UTC)
12. `origin` (emitted as `origin "<namespace>" "<external-key>"`)
13. `link` (in declaration order)
14. `history` (emitted as `history YYYY-MM-DD HH:MM:SS "<text>"` in UTC, deduplicated and sorted by ascending UTC timestamp then unsigned UTF-8 byte order of decoded `<text>`)
15. `condition` (`condition any`, inline single rule, or `condition { ... }` sub-block sorted by `day`, `time`, `location`, with `location` rules coalesced into a single rule)
16. `subtasks` (in declaration order of `step` directives)

Additional `repeat`, `suspended`, `due`, `origin`, `link`, and `history` rules inside `task` blocks:
- **Recurrence & Preparation Lead Offset (`repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]`):**
  - **Token Disambiguation & Error Mapping:**
    - `0` arguments (and no `{` follows) -> `MissingDirectiveArgument` (`UnknownBlockType` if `{` follows).
    - `1` argument (`repeat 1`) -> `UnexpectedToken`.
    - `<count>` (1st argument): MUST be an unquoted canonical positive integer in `1..MAX_REPEAT_COUNT` (`3650`; `InvalidNumber` if quoted, non-integer, signed, leading-zero, or `0`; `LimitExceeded` if raw ASCII length exceeds `MAX_NUMBER_LENGTH` (`24`) or value exceeds `3650`).
    - `<unit>` (2nd argument): MUST be the unquoted bare word `days`, `weeks`, or `months` (`UnexpectedToken` if quoted or any other token).
    - Optional `<repeat-time>`: When a 3rd argument is present and is not the unquoted bare word `lead`, validate it as `<HH:MM[:SS]>` (`InvalidTime` if quoted or outside `00:00:00..23:59:59`).
    - Optional `lead <lead-count> days`: Any remaining arguments after `<unit>` (or `<repeat-time>`) MUST begin with the unquoted bare word `lead` (`UnexpectedToken` otherwise) and MUST be followed by exactly `2` tokens (`UnexpectedToken` if fewer than `2` tokens follow `lead` or if extra tokens follow `days`): `<lead-count>` (unquoted canonical positive integer in `1..MAX_REPEAT_COUNT` (`3650`); `InvalidNumber` if quoted, non-integer, signed, leading-zero, or `0`; `LimitExceeded` if raw ASCII length exceeds `MAX_NUMBER_LENGTH` (`24`) or value exceeds `3650`) and the unquoted bare word `days` (`UnexpectedToken` if quoted or any other unit).
  - **Independence from `due` Presence:** `lead <lead-count> days` is syntactically valid on any `repeat` directive regardless of whether `due` is currently present on the task, guaranteeing schema closure when `due` and `repeat` are reconciled independently in Section 6.7.5 Case 2 (when `due` is omitted, completion-relative Mode 1 ignores `lead`).
- **Deferrals & Deferral Notes (`suspended (<timestamp> | forever) ["<note>"]`):**
  - **Token Disambiguation & Error Mapping:**
    - `0` arguments (and no `{` follows) -> `MissingDirectiveArgument` (`UnknownBlockType` if `{` follows).
    - First argument quoted (such as `suspended "2026-11-11"` or `suspended "forever"`) -> `InvalidTimestamp`.
    - Any non-final argument (`1 <= i < args.length - 1`) quoted -> `UnexpectedToken`.
    - When `args[0]` is the unquoted bare word `forever`:
      - `1` argument: indefinite suspension with no deferral note.
      - `2` arguments: `args[1]` MUST be a quoted string token validated as `<note>` under Section 2.8 (`UnexpectedToken` if `args[1]` is an unquoted bare word, or if decoded content contains unpaired UTF-16 surrogates; `EmptyText` if empty or ASCII whitespace only; `LimitExceeded` if `> MAX_NOTE_LENGTH`).
      - `>= 3` arguments: `UnexpectedToken`.
    - When `args[0]` is any other unquoted bare word:
      - If `args.length >= 2` and `args.last` is a quoted string token, validate `args.sublist(0, args.length - 1)` as a UTC `<timestamp>` (`1..2` bare words; `InvalidTimestamp` if malformed or out of range, `UnexpectedToken` if `>= 3` bare words precede the note) and then validate `args.last` as `<note>` under Section 2.8.
      - Otherwise validate all `args` as a UTC `<timestamp>` (`InvalidTimestamp` if `1..2` tokens are malformed or out of range; `UnexpectedToken` if `>= 3` tokens).
  - **Strict Ownership & Diagnostic Redaction:** A deferral `<note>` cannot exist without its enclosing `suspended` directive and is removed automatically whenever `suspended` expires and is cleaned up, is cleared manually, moves to `Someday`, completes, or resets on recurrence or restoration (Section 6). Diagnostic logs MUST NOT emit raw `suspended` `<note>` text; record at most boolean presence flags or aggregate cleanup counts.
- **Target Deadlines, Occurrence-Scoped `passive` & Deadline Notes (`due <YYYY-MM-DD> [<HH:MM[:SS]>] [passive] ["<note>"]`):**
  - **Token Disambiguation & Error Mapping:**
    - `0` arguments (and no `{` follows) -> `MissingDirectiveArgument` (`UnknownBlockType` if `{` follows).
    - First argument quoted (such as `due "2026-11-11"`) -> `InvalidTimestamp`.
    - Any non-final argument (`1 <= i < args.length - 1`) quoted (such as misordered `due 2026-11-11 "note" passive`) -> `UnexpectedToken`.
    - Let `end = args.length`:
      1. If `end >= 2` and `args[end - 1]` is a quoted string token, record `rawNoteToken = args[end - 1]` and decrement `end -= 1`.
      2. If `end >= 2` and `args[end - 1]` is the unquoted bare word `passive`, record `passive = true` and decrement `end -= 1`.
      3. If `end == 2` and `args[1]` is the unquoted bare word `passive` (duplicate `due 2026-11-11 passive passive`), report `UnexpectedToken`.
      4. Validate `args.sublist(0, end)` as a UTC `<timestamp>` (`InvalidTimestamp` if `end` is `1` or `2` and malformed or out of range; `UnexpectedToken` if `end >= 3`).
      5. If `rawNoteToken` was recorded, validate it as `<note>` under Section 2.8 (`UnexpectedToken` on unpaired UTF-16 surrogates; `EmptyText` if empty or ASCII whitespace only; `LimitExceeded` if `> MAX_NOTE_LENGTH`).
  - **No `suspended <= due` Schema Constraint:** Do not enforce an ordering constraint between `suspended` and `due`. Manually deferring (`suspended`) an already-overdue task to tomorrow while preserving its original `due` date from last week is valid and MUST NOT fail parsing or validation.
  - **Non-Blocking Deadline, Occurrence-Scoped `passive`, and Ownership Coupling:** `due` never places a task into `Blocked` (`Tier 4`), never pulls an unscheduled `Someday` task without `queue` membership, and never mutates stored task state during read-only evaluation. When `passive` is omitted (`false`), `due` participates in Section 5.5 lead-window effective priority (`due <= now + W_due`); when `passive` is present (`true`), `due` suppresses lead-window effective priority for the active deadline occurrence (persisting across unrelated metadata edits and into `Completed` on non-recurring tasks, and resetting to omitted/`false` when a Mode 2 recurring task advances to `newDue`, when `due` changes to a different timestamp without explicitly specifying `passive`, when `priority` is explicitly set, or when a completed task is restored under Section 6). Overdue deadlines (`due <= now`) and their notes remain attached on open tasks; a deadline `<note>` cannot exist without `due`. Diagnostic logs MUST NOT emit raw `due` `<note>` text.
- **Machine Correlation Key (`origin "<namespace>" "<external-key>"`):**
  - **Purpose & Separation from `link`:** `origin` provides a dedicated machine correlation identifier so external CLI tools, scripts, and agents can deterministically identify and deduplicate imported tasks across open and `Completed` states even after a user edits `name`, `note`, or `link`.
  - **Argument Count & Quoting:** Requires exactly `2` quoted string arguments (`"<namespace>"` and `"<external-key>"`, accepting either double-quoted `"..."` or single-quoted `'...'` tokens in input per Section 2.7 and emitting double-quoted `"..."` canonically with a single ASCII space `0x20` between arguments):
    - If `0` arguments are provided (and no `{` follows), report `MissingDirectiveArgument`.
    - If `{` follows `origin`, report `UnknownBlockType`.
    - If `1` argument or $\ge 3$ arguments are provided, or if either argument is an unquoted bare word rather than a quoted string token, report `UnexpectedToken`.
  - **String Content & Character Bounds:** Both `<namespace>` and `<external-key>` are single-line `<text>` values under Section 2.8 (`1..MAX_TEXT_LENGTH` decoded Unicode scalar values without Unicode normalization; `InvalidEscapeSequence` on unknown backslash escapes in double-quoted strings; `UnexpectedToken` if the decoded string contains `\n`, `\r`, `\t`, or an unpaired UTF-16 surrogate, checked before `EmptyText` on `""` or ASCII spaces `0x20` only; `LimitExceeded` if $> \text{MAX\_TEXT\_LENGTH}$).
  - **Multiplicity & Cross-Task Non-Uniqueness:** At most one `origin` directive is permitted per `task` block (`DuplicateDirective` on repetition). Distinct `task` blocks in the same `.tdf` document MAY carry the same `(namespace, externalKey)` pair without triggering `DuplicateIdentifier` so concurrent offline imports with different random `<task-id>` values parse and merge cleanly before agent-level deduplication.
  - **Passive Security & Diagnostic Redaction:** `origin` arguments are strictly passive string identifiers and MUST NEVER be executed, opened as filesystem paths, or dereferenced as network URIs by a parser, evaluator, or reconciler. Diagnostic logs MUST NOT record raw `<external-key>` values; log at most `<task-id>` and `<namespace>` (or a boolean `hasOrigin` flag).
- **User-Facing Links (`link "<title>" "<uri>"`):**
  - **Arguments (`link <title> <uri>`):** Requires `2` quoted string tokens (`"..."` or `'...'` in input, emitted as double-quoted `"..."` canonically; `MissingDirectiveArgument` on `0` arguments without `{`, `UnknownBlockType` if `{` follows, `UnexpectedToken` on `1` or $\ge 3$ arguments or if either argument is unquoted). `<title>` is validated as a single-line `<text>` value under Section 2.8 (`1..MAX_TEXT_LENGTH`; `UnexpectedToken` if it contains a decoded `\n`, `\r`, `\t`, or unpaired UTF-16 surrogate, checked before `EmptyText` on `""` or ASCII spaces `0x20` only; `LimitExceeded` if $> \text{MAX\_TEXT\_LENGTH}$). `<uri>` is validated under Section 2.8 (`UnexpectedToken` on unpaired UTF-16 surrogates; `EmptyText` if empty `""` or ASCII whitespace `0x20`, `\t`, `\n`, `\r` only; `LimitExceeded` if $> \text{MAX\_URI\_LENGTH}` (`2048`); `InvalidUri` if it contains a decoded `\n`, `\r`, `\t`, or other ASCII control character, lacks a valid URI scheme `[a-zA-Z][a-zA-Z0-9+.-]*:`, or uses `javascript:`, `vbscript:`, or `data:` case-insensitively).
  - **Preserved Ordering:** Preserve the exact declaration order of `link` directives (`0..MAX_LINKS_PER_TASK` = `20`, `LimitExceeded` on the 21st `link`) in memory and during serialization.
  - **Canonical Serializer Position:** Emit `link` directives at canonical position 13 (after `origin` at position 12 and before `history` at position 14).
  - **Tier Derivation & Sync:** `link` directives are passive task metadata and do not affect tier derivation (Section 5). Adding, modifying, reordering, or removing a `link` updates the task's `modified` timestamp (Sections 6.6 and 6.7).
- **Persistent Timestamped Task History (`history <YYYY-MM-DD> [<HH:MM[:SS]>] "<text>"`):**
  - **Purpose & Separation from `note` and Scheduling Notes:** `note` (`0..1`) holds the standing description of a task, and `suspended` / `due` notes attach transient reasons to active deferrals and deadlines, whereas `history` records an occurrence-independent chronological trail of timestamped progress or status entries (`0..MAX_HISTORY_PER_TASK` = `500` per `task` block, counted **before** deduplication; `LimitExceeded` before allocating the 501st `history` directive in a `task` block).
  - **Scope, Argument Count & Token Disambiguation:** Valid only at depth `1` inside `task` blocks (`UnknownDirective` inside `label`, `location`, `deleted`, `queue`, `subtasks`, or `condition` blocks; `UnexpectedRootDirective` at depth `0`):
    - `0` arguments (and no `{` follows) -> `MissingDirectiveArgument`.
    - `{` follows `history` -> `UnknownBlockType` (after checking `InvalidBlockHeader` on attached `history{` and `LimitExceeded` on statement/argument bounds).
    - `1` argument (such as `history 2026-11-10` or `history "text"`), $\ge 4$ arguments (`4..MAX_ARGS_PER_STMT`), `3` arguments where the second argument is a quoted string token (`history 2026-11-10 "08:05:00" "text"`), or `2..3` arguments where the final argument is an unquoted bare word -> `UnexpectedToken`.
    - Validate `args.sublist(0, args.length - 1)` (`1` or `2` leading tokens) as a UTC `<timestamp>` under Section 2.8 (`0001-01-01 00:00:00..9999-12-31 23:59:59` UTC, defaulting omitted `<clock>` to `00:00:00` UTC and omitted `:SS` to `:00` UTC; `InvalidTimestamp` if the leading `<date>` token is quoted — such as `history "2026-11-10" "text"` or `history "2026-11-10" 08:05:00 "text"` — or if the date or clock is malformed or out of range).
    - Validate the final quoted argument as a single-line `<text>` value under Section 2.8 (`1..MAX_TEXT_LENGTH` = `500` decoded Unicode scalar values without Unicode normalization; `InvalidEscapeSequence` on unknown backslash escapes in `"..."`; `UnexpectedToken` if decoded `\n`, `\r`, `\t`, or an unpaired UTF-16 surrogate is present, checked before `EmptyText` on `""` or ASCII spaces `0x20` only; `LimitExceeded` if $> 500$ scalar values).
  - **Normalization & Canonical Position:** Collapse exact duplicate `(timestampUtc, text)` pairs within the same `task` block to a single entry and sort entries in ascending chronological order of `timestampUtc` (UTC epoch seconds), breaking identical-timestamp ties lexicographically by decoded `text` using unsigned UTF-8 byte order. Emit `history` directives at canonical position 14 (immediately after `link` at position 13 and before `condition` at position 15) as `history YYYY-MM-DD HH:MM:SS "<escaped-text>"`.
  - **Passive Security & Diagnostic Redaction:** `history` `<text>` values are strictly passive plain-text strings and MUST NEVER be dereferenced as network URIs, opened as filesystem paths, or executed by a parser, evaluator, or reconciler. Diagnostic logs MUST NOT emit raw `history` `<text>` contents; log at most `<task-id>` and the history entry count.

#### 4.1.3 Sub-Block `subtasks` (Checklists)

Inside a `task` block (header at depth `1`, body at depth `2`), an optional `subtasks` sub-block (at most one per `task`) defines an ordered checklist:

```text
subtasks [auto-finish] {
    step <true|false> "<text>"
}
```

- `auto-finish` (**Optional Header Flag**):
  - **When present:** When all `step` directives become `true`, complete the enclosing `task` automatically under Section 6.4 (setting `finished` to `now` in UTC for a standard task, or rescheduling a `repeat` task with all steps reset to `false`).
  - **When omitted:** Completing all `step` directives does not complete or reschedule the enclosing `task`.
  - Reject any unknown or extra header argument on `subtasks` with `InvalidBlockHeader`.
- `step <bool> "<text>"` (**Repeatable Directive**): Defines a checklist step in preserved declaration order (`false` = open, `true` = completed, single-line `"<text>"` up to `MAX_TEXT_LENGTH` characters). Require at least one `step` directive per `subtasks` block (`MissingRequiredDirective`).

### 4.2 The `label` Block (Labels & Context Profiles)

A `label` block defines a named project or context hub and reusable condition profile.
Tasks reference labels through the `labels` directive.
A label header MUST contain one required unquoted `<label-id>` followed by an optional `scoped` bare-word flag.
A missing ID, extra header argument, or unknown header flag MUST produce `InvalidBlockHeader`.
A quoted or noncanonical ID MUST produce `InvalidIdentifier`.

```text
label <label-id> [scoped] {
    name     "<display_name>"
    color    "<hex_color_code>"
    note     "<optional_description>"
    modified <YYYY-MM-DD> [<HH:MM[:SS]>]
    link     "<title>" "<uri>"

    condition {
        day      <d1> [<d2> ...]
        time     <HH:MM> <HH:MM>
        location <loc-1> [<loc-2> ...]
    }
}
```

- **`scoped` Header Flag (**Optional**, Bare Word Flag):**
  - **When present (`label <label-id> scoped {`):** Marks the label as a view-scoped context list. Tasks whose assigned labels are all `scoped` are excluded from the global view (Section 5.1), `scoped` labels are ignored when evaluating candidate condition contexts in the global view for mixed-label tasks (Section 4.4.3 Rule 4), and deleting a `scoped` label removes any previously global-view-restricted task that loses its last label from `queue` (stripping `priority` while preserving `suspended` with its note, `(due, passive, due-note)`, `origin`, and `history`) under Sections 6.7.8, 6.8.1, and 6.8.2.
  - **When omitted (`label <label-id> {`):** Regular label whose tasks enter both the global view and the filtered label view.

| Directive / Sub-Block | Required | Multiplicity | Format / Arguments | Description |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Human-readable single-line display name of the label (`1..MAX_TEXT_LENGTH` characters, such as `"Home & Garden"`). |
| `color` | No | `0..1` | `"#RRGGBB"` | Optional hexadecimal color code associated with the label. |
| `note` | No | `0..1` | `"<note>"` | Optional description of the label (`1..MAX_NOTE_LENGTH` characters). |
| `modified` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM[:SS]>]` | UTC entity revision timestamp. Section 6.7.1 defines its effective value (`1970-01-01 00:00:00` UTC) when omitted. Section 6.7 defines synchronization and revision updates. |
| `link` | No | `0..MAX_LINKS_PER_LABEL` | `"<title>" "<uri>"` | Repeatable shared context reference link (`0..20` per `label`, `LimitExceeded` on the 21st `link`) in preserved declaration order. Validated with the exact argument count, quoting, `<title>` single-line `<text>` (`1..MAX_TEXT_LENGTH`), and `<uri>` (`1..MAX_URI_LENGTH`, non-executable scheme `[a-zA-Z][a-zA-Z0-9+.-]*:`) rules defined for `task.link` in Sections 2.8 and 4.1.2. Passive context metadata with zero effect on 6-tier derivation or condition evaluation; adding, editing, reordering, or removing a `link` on a `label` advances `label.modified` under Section 6.7.1 while leaving task revisions and `queue.modified` untouched. Diagnostic logs MUST NOT emit raw `<title>` or `<uri>` values. |
| `condition` | No | `0..N` | `<type> <args...>` or `{ ... }` | Optional activation conditions (`day`, `time`, `location`) inherited by rule group for tasks carrying this label unless overridden for that group or cleared via `condition any` on the task (Section 4.4). |

**Canonical `label` Directive Serialization Order (6 Positions):**
Inside each `label` block, a canonical serializer MUST emit present directives and sub-blocks in this exact 6-position order: `1. name`, `2. color`, `3. note`, `4. modified`, `5. link` (in declaration order), `6. condition`.

### 4.3 The `location` Block (Reusable Geofence Locations)

A `location` block defines a reusable circular geofence place at depth `0` (body at depth `1`).
Tasks and labels reference locations by `<location-id>` in `condition` `location` rules (Section 4.4).
A document MAY contain at most `MAX_LOCATIONS` (`200`) `location` blocks (`LimitExceeded` on the 201st `location` block, while also counting toward `MAX_BLOCKS_PER_DOC = 4_096`).
A `location` block header MUST contain exactly one unquoted 10-character Base62 `<location-id>`.
A missing ID or extra header argument MUST produce `InvalidBlockHeader`.
A quoted or noncanonical ID MUST produce `InvalidIdentifier`.
A `location` block permits directives only at depth `1` and forbids nested blocks (`UnknownBlockType`).

```text
location <location-id> {
    name        "<display_name>"
    note        "<optional_description>"
    source      "<optional_address_or_code>"
    coordinates <lat> <lon>
    radius      <meters>
    modified    <YYYY-MM-DD> [<HH:MM[:SS]>]
}
```

- **Identity Namespace:** `location` uses a dedicated identity namespace separate from `task` and `label`. Within the `location` namespace, duplicate live `location` blocks, duplicate `deleted` `location` records, or a live `location` block sharing an ID with a `deleted` `location` record MUST report `DuplicateIdentifier`.

| Directive | Required | Multiplicity | Format / Arguments | Description |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Human-readable single-line display title of the place (`1..MAX_TEXT_LENGTH` decoded Unicode scalar values, not empty or ASCII-space-only `0x20` after unescaping; `EmptyText` if empty or ASCII spaces only; `InvalidEscapeSequence` on unknown backslash escapes; `UnexpectedToken` if the decoded string contains `\n`, `\r`, `\t`, or an unpaired UTF-16 surrogate). |
| `note` | No | `0..1` | `"<note>"` | Optional descriptive note (`1..MAX_NOTE_LENGTH` decoded Unicode scalar values, not empty or ASCII-whitespace-only `0x20`, `\t`, `\n`, `\r` after unescaping; `EmptyText` if empty or ASCII whitespace only; `\n`, `\r`, `\t` permitted via escape sequences). |
| `source` | No | `0..1` | `"<text>"` | Optional human- or tool-readable single-line address or location code, such as a street address (`"Bahnhofstraße 1, 99084 Erfurt"`), an Open Location Code / Google Plus Code (`"9F2PXXH7+F4"`), or a What3words code (`"///index.home.raft"`) (`1..MAX_TEXT_LENGTH` decoded Unicode scalar values, not empty or ASCII-space-only `0x20` after unescaping; `EmptyText` if empty or ASCII spaces only; `InvalidEscapeSequence` on unknown backslash escapes; `UnexpectedToken` if the decoded string contains `\n`, `\r`, `\t`, or an unpaired UTF-16 surrogate). |
| `coordinates` | Yes | `1` | `<lat> <lon>` | Two unquoted finite ASCII decimal `<number>` tokens (`-?[0-9]+(\.[0-9]+)?`, each `<= MAX_NUMBER_LENGTH = 24` ASCII characters; `LimitExceeded` if longer, `InvalidNumber` if `NaN`, `Infinity`, `-Infinity`, leading `+`, scientific notation, or malformed): `<lat>` in `[-90.0, 90.0]` and `<lon>` in `[-180.0, 180.0]` in WGS-84 decimal degrees (`InvalidNumber` if out of range; `MissingDirectiveArgument` if `0` arguments; `UnexpectedToken` if quoted or argument count is `1` or $\ge 3$). After stripping trailing fractional zeros under Section 6.7.3, `<lat>` and `<lon>` in native `tdf 0.7.0` (and `tdf 0.6.0`) documents MUST have at most **6 fractional decimal digits** (`InvalidNumber` if $> 6$ non-zero fractional digits). |
| `radius` | Yes | `1` | `<meters>` | One unquoted finite ASCII decimal `<number>` token (`<= MAX_NUMBER_LENGTH = 24` ASCII characters; `LimitExceeded` if longer) with at most **2 fractional decimal digits** after stripping trailing zeros, satisfying $0 < \text{meters} \le \text{MAX\_LOCATION\_RADIUS}$ (`MAX_LOCATION_RADIUS = 100_000` meters; `InvalidNumber` if $\le 0$, $> 2$ non-zero fractional digits, or malformed; `LimitExceeded` if $> \text{MAX\_LOCATION\_RADIUS}$; `MissingDirectiveArgument` if `0` arguments; `UnexpectedToken` if quoted or argument count $\ge 2$). |
| `modified` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM[:SS]>]` | UTC entity revision timestamp (`InvalidTimestamp` if invalid; effective value when omitted is `1970-01-01 00:00:00` UTC under Section 6.7.1, identical to `label.modified`). |

- **Required Directives & Multiplicity:** Omitting `name`, `coordinates`, or `radius` produces `MissingRequiredDirective`. All six directives are single-valued (`DuplicateDirective` on repetition; `UnknownDirective` on any other directive).
- **Canonical `location` Directive Serialization Order (6 Positions):** Inside each `location` block, a canonical serializer MUST emit present directives in this exact 6-position order: `1. name`, `2. note`, `3. source`, `4. coordinates`, `5. radius`, `6. modified`, formatting `<lat>`, `<lon>`, and `<meters>` using the Section 6.7.3 normalized decimal representation (`-0.0` normalized to `0`, redundant leading integer zeros and trailing fractional zeros removed).
- **Normative SSRF & Passive-Metadata Security Rule:** `location.source` is strictly passive textual metadata during parsing, migration, synchronization, and 6-tier evaluation (Section 5). A conforming parser, migrator, reconciler, or tier evaluator MUST NEVER automatically invoke external geocoding services, network APIs (such as Nominatim, Google Maps, or What3words), or filesystem/UNC paths (`\\server\share`) when processing `source`. If a consuming application offers an explicit user action to open `source` in an external map viewer, it MUST pass `source` as a URL-encoded query parameter to a safe map URI template (`https:` or `geo:`) rather than launching `source` as an unvalidated raw URI or OS command.
- **Diagnostic Redaction:** Diagnostic logs MUST record only the opaque 10-character Base62 `<location-id>` and MUST NEVER log `location.name`, `location.note`, `location.source`, or `location.coordinates`.

### 4.4 Activation Conditions (`condition`)

#### 4.4.1 Scope & Syntactic Forms (Block Form vs. Single-Line Shorthand)
Both `label` and `task` blocks accept activation conditions at depth `1`. Two syntactic forms map to the same condition model:

1. **Block Form (`condition { ... }` — Multiple or Grouped Conditions):**
   A parameterless `condition { ... }` sub-block (body at depth `2`) groups one or more condition rules (`day`, `time`, `location`, and task-level group resets `day any`, `time any`, `location any`):
   ```text
   condition {
       day      sat sun
       time     08:00 20:00
       location 7pQr9mOkD2
   }
   ```
   A `condition { ... }` sub-block accepts zero header arguments (`InvalidBlockHeader` otherwise), requires at least one rule directive (`MissingRequiredDirective`), and forbids nested sub-blocks (`UnknownBlockType` or `LimitExceeded`).
2. **Single-Line Shorthand (`condition <type> <args...>`, `condition <type> any`, or `condition any` — Inline Directive):**
   Write a single rule (or repeatable inline declarations) as `condition <type> <args...>`, or write `condition <type> any` or `condition any` on a `task` block:
   ```text
   condition time 09:00 18:00
   ```
3. **Canonical Coalescing of `location` Rules & Canonical Serialization:**
   - Because both intra-rule `<location-id>` tokens and multiple `location` rules within the same `condition` group combine with logical `OR`, canonical normalization (Section 6.7.3) and canonical serialization MUST coalesce all `location` rules on an entity into a **single canonical `location <loc-1> [<loc-2> ...]` rule** containing all referenced `<location-id>` tokens deduplicated in first-seen declaration order across the entity (`1..MAX_LOCATION_REFS_PER_ENTITY` tokens, where `MAX_LOCATION_REFS_PER_ENTITY = 63`).
   - With `0` condition rules, emit no `condition` directive or sub-block.
   - When a `task` disables all inherited label conditions via `condition any`, emit `condition any`.
   - With `1` canonical condition rule after coalescing `location` rules (including a single task-level group reset such as `condition day any` or a single coalesced `condition location <loc-1> [<loc-2> ...]`), emit the single-line shorthand `condition <type> <args...>`.
   - With `2` or more canonical condition rules after coalescing `location` rules, emit one `condition { ... }` sub-block with rules ordered by evaluation group as `day`, `time`, `location`, preserving declaration order within `day` and `time` and emitting the single coalesced `location <loc-1> [<loc-2> ...]` rule (or `location any`) for `location`.

Apply `MAX_CONDITION_RULES_PER_ENTITY` (`512`) and `MAX_LOCATION_REFS_PER_ENTITY` (`63`) across all condition forms in each task or label.
Count each input `day`, `time`, or `location` rule statement and each reset as one rule toward `MAX_CONDITION_RULES_PER_ENTITY`.
A `day` rule containing several weekdays or a `location` rule containing several `<location-id>` tokens still counts as one rule toward `MAX_CONDITION_RULES_PER_ENTITY`.
Count `condition any` as one rule.
In addition, count every `<location-id>` token across all `location` condition rules on a single `task` or `label` (before deduplication) toward `MAX_LOCATION_REFS_PER_ENTITY` (`63`), so coalescing all `location` rules on the entity into a single canonical rule never exceeds `MAX_ARGS_PER_STMT` (`64`) in either block form (`location <loc-1> ... <loc-63>`, 63 arguments) or inline shorthand form (`condition location <loc-1> ... <loc-63>`, 64 arguments).
Check both limits before accepting the next rule or `<location-id>` token, including rules in another condition block.
Report `LimitExceeded` at the first rule or `<location-id>` token that exceeds the limit.
Do not discard duplicate rules or duplicate `<location-id>` tokens to satisfy these limits.
Inherited rules belong to their declaring label and do not increase the task's stored rule or `<location-id>` reference count.

#### 4.4.2 Built-In Condition Rule Types & Resets

Three rule groups (`day`, `time`, `location`), three task-level group resets (`day any`, `time any`, `location any`), and the task-level global reset (`condition any`) are defined:

| Rule / Form | Block Syntax | Inline Shorthand Syntax | Arguments & Domain Rules |
| :--- | :--- | :--- | :--- |
| `day` | `day <d1> [<d2> ...]` | `condition day <d1> [<d2> ...]` | One or more weekday tokens (`mon`, `tue`, `wed`, `thu`, `fri`, `sat`, `sun`). Combine allowed weekdays with logical `OR`. |
| `time` | `time <start> <end>` | `condition time <start> <end>` | Two 24-hour `<HH:MM>` time tokens (`00:00` to `23:59`, `start != end`). Defines an inclusive daily active time window in local time. |
| `location` | `location <loc-1> [<loc-2> ...]` | `condition location <loc-1> [<loc-2> ...]` | One or more unquoted 10-character Base62 `<location-id>` tokens (`1..MAX_LOCATION_REFS_PER_ENTITY` across the entity; `InvalidIdentifier` if quoted or malformed; `UnknownLocationReference` if a `<location-id>` matches no declared `location` block). Combine referenced locations with logical `OR`. |
| `<type> any` | `day any` / `time any` / `location any` | `condition day any` / `condition time any` / `condition location any` | Valid on `task` blocks only (`InvalidCondition` on `label` or when combined with other rules of the same `<type>` group on the same `task`). Clears that single inherited condition group (`day`, `time`, or `location`) while preserving all other inherited `label` condition groups. |
| `any` | *(not allowed in block)* | `condition any` | Valid on `task` blocks only (`InvalidCondition` on `label` or when combined with any other `condition` rules on the same `task`). Disables all inherited `label` condition groups (`day`, `time`, and `location`) so the task is unrestricted. |

Detailed rule semantics:
1. **Weekday Rule (`day`):**
   - Evaluates to `true` when the local calendar weekday at `localNow` matches at least one listed `<weekday>` token.
   - Combine multiple `day` rules within the active condition context with logical `OR`.
2. **Time Window Rule (`time`):**
   - **Same-Day Window (`start < end`):** Evaluates to `true` when `start <= current_time <= end` in local time (inclusive boundaries, such as `time 08:00 20:00`).
   - **Overnight Window (`start > end`):** Spans midnight and evaluates to `true` when `current_time >= start || current_time <= end` in local time (such as `time 22:00 06:00`).
   - **Disjoint Windows on the Same Day:** Combine multiple `time` rules within the active condition context (such as `time 08:00 12:00` and `time 14:00 18:00`) with logical `OR`.
3. **Geofence Location Rule (`location`):**
   - References one or more declared `location <location-id> { ... }` blocks (Section 4.3).
   - Evaluates strictly offline to `true` when the great-circle Haversine distance (using mean Earth radius $R = 6\,371\,000\text{ m}$) between the device's current GPS coordinates and `loc_i.coordinates` satisfies $\text{distance} \le \text{loc}_i.\text{radius}$ for **at least one** referenced `<location-id>` (logical `OR`, short-circuiting at the first satisfied `<location-id>`).
   - If the evaluation environment provides no current GPS coordinates (such as a desktop without GPS hardware or a disabled location sensor), `location` rules evaluate to `true`.
4. **Global Reset (`condition any`) vs. Group Reset (`day any`, `time any`, `location any`):**
   - **Global Reset (`condition any`):** Disables all three inherited `label` condition groups (`day`, `time`, and `location`) so the task is unrestricted in every context. Permit `condition any` only as a standalone inline directive on a `task` block. Reject `any` on a `label` block, inside `condition { ... }` without a `<type>` prefix, or alongside any other `condition` rule on the same `task` (`InvalidCondition`).
   - **Group Reset (`day any`, `time any`, `location any`):** Clears only the specified rule group (`day`, `time`, or `location`) inherited from assigned labels, treating that group as empty (`0` rules, unrestricted) while preserving all other inherited label condition groups. Write a group reset inline (`condition <type> any`) or inside a task's `condition { ... }` sub-block (`<type> any`, such as `day any` paired with `time 09:00 18:00`). Reject `<type> any` inside a `label` block, repeated `<type> any` for the same group, or `<type> any` combined with another rule of the same `<type>` group on the same `task` (`InvalidCondition`).

#### 4.4.3 Group-Level Condition Inheritance, Selective Overrides & Per-Label Context Evaluation
Task-level condition rules operate on individual rule groups (`day`, `time`, `location`) while preserving the task's `labels` membership for context filtering:

1. **Group-Level Resolution (`day`, `time`, `location`) for a Given Label Context:**
   When resolving a `task`'s effective condition groups against a specific `label` (or for an unlabeled task):
   - **Global Reset (`condition any`):** If the `task` specifies `condition any`, all three effective rule groups (`day`, `time`, `location`) are empty (`0` rules, unrestricted), ignoring all conditions on the `label`.
   - **Selective Per-Group Override or Inheritance:** Otherwise, resolve each rule group $G \in \{\text{day}, \text{time}, \text{location}\}$ independently:
     - **Task Group Reset (`G any`):** If the `task` specifies `day any`, `time any`, or `location any` for group $G$, clear effective group $G$ to empty (`0` rules, unrestricted), ignoring the `label`'s rules for group $G$.
     - **Task Group Override (`G <args...>`):** If the `task` defines one or more rules for group $G$, replace only the `label`'s rules for group $G$ with the `task`'s rules.
     - **Label Group Inheritance (No Task Rule for $G$):** If the `task` defines no rule or reset for group $G$, inherit the rules defined for group $G$ on the `label` (or leave group $G$ empty when the `label` defines none).
   - For example, a task assigned to `label 4x9p2mOkD2` (`day sat sun`, `time 08:00 20:00`, `location 7pQr9mOkD2`) with `condition time 09:00 18:00` overrides only `time` while inheriting `day sat sun` and `location 7pQr9mOkD2`. Adding `day any` also removes the weekday restriction while preserving `location 7pQr9mOkD2`.
2. **Unlabeled Task (`labels` Omitted):**
   - A `task` without `labels` has one effective condition context containing only the task's own `day`, `time`, and `location` groups (any group omitted or set to `<type> any` is empty).
3. **Active `label` Context Filter Selected (`activeLabelId = l*`):**
   - Evaluate only the selected `label` context $l^*$ (whether $l^*$ is regular or `scoped`). Construct the effective condition context by applying Rule 1 to the selected `label` $l^*$. The task is satisfied when all three effective groups (`day`, `time`, `location`) of that context are satisfied (Section 4.4.4).
4. **No `label` Filter Selected (Global View — Non-Scoped Label Contexts Only):**
   - **Scoped Label Exclusion in Global View:** Let $L(T)$ be the set of declared labels referenced in task $T$'s `labels` directive, and let $\text{isScoped}(l)$ be `true` when label $l$ carries the `scoped` header flag. Tasks where $L(T) \neq \varnothing$ and all labels in $L(T)$ are `scoped` are excluded from the global view in Section 5.1. When a task $T$ has at least one non-`scoped` label ($\exists l \in L(T),\; \neg\text{isScoped}(l)$) alongside one or more `scoped` labels, $T$ is evaluated in the global view strictly against its non-`scoped` labels:
     $$L_{\text{global}}(T) = \{\, l \in L(T) \mid \neg\text{isScoped}(l) \,\}$$
     `scoped` labels are ignored when forming candidate condition contexts in the global view.
   - **Cohesive Label Contexts:** Each non-`scoped` label $L_i \in L_{\text{global}}(T)$ forms a self-contained context. Do not pool `day`, `time`, and `location` rules across different labels. Construct each label $L_i$'s effective condition context $C_i$ under Rule 1 and evaluate $C_i$ independently in ascending ASCII `<label-id>` / declaration order.
   - **Logical `OR` Across Non-Scoped Labels:** A task with $L_{\text{global}}(T) \neq \varnothing$ is satisfied in the global view when at least one non-`scoped` label $L_i \in L_{\text{global}}(T)$ has all three effective groups (`day`, `time`, `location`) satisfied (`OR` short-circuit at the first satisfied context $C_i$). If every candidate context in $L_{\text{global}}(T)$ fails at least one effective group, classify the task as `Blocked` (`Tier 4`).

#### 4.4.4 Deterministic Group Evaluation Order (`day` -> `time` -> `location`) & Short-Circuiting
Evaluate each effective condition context $C$ by group in order of increasing cost:

1. **Group 1 — `day` (Weekday check):** Fastest ($O(1)$ weekday check against `localNow`).
2. **Group 2 — `time` (Time-of-day window check):** Second fastest (integer minute-of-day comparisons in local time).
3. **Group 3 — `location` (GPS Haversine check):** Most expensive (floating-point great-circle distance calculation against referenced `location` blocks).

**Step-by-Step Context Evaluation Algorithm:**
- For an effective condition context $C$, start with `isContextSatisfied = true` and evaluate `day`, then `time`, then `location`:
  1. **Empty Group (`0` rules, or cleared via `<type> any` / `condition any`):** Treat the group as satisfied (`true`) and advance to the next group.
  2. **Non-Empty Group ($\ge 1$ rules — Intra-Group Logical `OR`):** Test rules (and referenced `<location-id>` entries within the coalesced `location` rule) in order. As soon as one rule or referenced `<location-id>` evaluates to `true`, the group is satisfied (`OR` short-circuit); advance to the next group without testing remaining items in that group.
  3. **Group Failure (Inter-Group Logical `AND`):** If all rules in a non-empty group evaluate to `false`, terminate evaluation of context $C$ immediately with `false` (`AND` short-circuit) without checking subsequent groups in $C$.
- Define satisfaction for each resolved rule group $G$:
  $$\text{isGroupSatisfied}(G) = (G = \varnothing) \lor \bigvee_{r \in G}\text{evaluate}(r)$$
- For a single effective condition context $C$:
  $$\text{isContextSatisfied}(C) = \text{isGroupSatisfied}(C.\text{day}) \land \text{isGroupSatisfied}(C.\text{time}) \land \text{isGroupSatisfied}(C.\text{location})$$
- For a task with $k \ge 1$ candidate label contexts $\{C_1, \dots, C_k\}$ (where $\{C_1, \dots, C_k\}$ corresponds to $L_{\text{global}}(T)$ in the global view), test label contexts in order with `OR` short-circuiting:
  $$\text{isSatisfied} = \bigvee_{i=1}^{k} \text{isContextSatisfied}(C_i)$$
  If $\text{isSatisfied}$ is `false`, exclude the task from `Focus`, `Ready`, and `Planned`, and classify it as `Blocked` (`Tier 4`).

### 4.5 The `deleted` Block

A document MAY contain one root-level `deleted` block.
It stores the deletion history generation and recent deletion records.

```text
deleted {
    generation 4
    task 6uCk8N0aB1 2026-11-01 12:00:00
    label 1rQv7S0cD2 2026-11-02 09:00:00
    location 9mTw3K0eF4 2026-11-03 15:30:00
}
```

The block header takes no arguments.
Nested blocks are forbidden.

| Directive | Required | Multiplicity | Arguments | Meaning |
| --- | --- | --- | --- | --- |
| `generation` | Yes | `1` | `<generation>` | Deletion history generation of the document. |
| `task` | No | `0..N` | `<task-id> <timestamp> [<completion-count>]` | Deleted task identity, UTC deletion revision, and optional completion checkpoint. |
| `label` | No | `0..N` | `<label-id> <timestamp>` | Deleted label identity and UTC deletion revision. |
| `location` | No | `0..N` | `<location-id> <timestamp>` | Deleted location identity and UTC deletion revision. |

Each record ID MUST be an unquoted 10-character Base62 value.
The timestamp uses Section 2.8 and represents the deletion revision in UTC.
A record stores no entity title, note, coordinates, or previous content.
A task record may retain its completion checkpoint under Section 6.9.5.
Read its date first, then an optional time token containing `:`, followed by an optional completion count.
A `label` or `location` record MUST NOT contain a completion count (`UnexpectedToken`).
Omit zero checkpoints during canonical serialization and emit positive checkpoints after the timestamp.

Allow at most one record for each namespace (`task`, `label`, `location`) and ID.
A live block and deletion record MUST NOT share that identity in the same namespace in one document.
Report violations as `DuplicateIdentifier`.
The `task`, `label`, and `location` namespaces remain separate.

If the block is absent, its generation is `0` and its record set is empty.
A present block MUST contain `generation`, including when it contains no records.
Preserve the block when its generation exceeds `0`.

A canonical serializer MUST place this block immediately after the version header.
Emit `generation` first.
Emit `task` records first, then `label` records, and then `location` records, sorting each group by ascending ASCII ID.
Emit record timestamps with explicit UTC seconds.
Omit the entire block only when its generation is `0` and it contains no records.

Section 6.8 defines deletion, retention, cleanup, and recovery behavior.

### 4.6 The `queue` Block

The document contains one shared order for all scheduled open tasks, stored in one root-level `queue` block. Membership in `queue` is the sole single source of truth for whether an open task (`finished` omitted) is scheduled into the active pull cycle or resides in `Someday` (`Tier 5`).

```text
queue {
    modified 2026-11-04 12:00:00
    task AAAAAAAAAA
    task BBBBBBBBBB
    task CCCCCCCCCC
}
```

These illustrative IDs require corresponding live open task blocks in a complete document.
The header takes no arguments.
Nested blocks are forbidden.

| Directive | Required | Multiplicity | Arguments | Meaning |
| --- | --- | --- | --- | --- |
| `modified` | Yes | `1` | `<timestamp>` | UTC revision for the complete ordered list. |
| `task` | No | `0..MAX_QUEUE_ENTRIES` | `<task-id>` | One scheduled open task in saved order. |

Each entry MUST reference a live open task (`finished` absent) in the document.
Include every scheduled open task at most once, including temporarily blocked tasks.
Open tasks (`finished` absent) whose task ID is omitted from `queue` are unscheduled (`Someday` under Section 5.3, or `Blocked` under Section 5.4 if an active `suspended` lock is present).
Resolve references after reading the complete document.
Reject duplicate queue IDs with `DuplicateIdentifier`.
Reject unknown, deleted, or completed (`finished` present) task IDs in `queue` with `InvalidQueueMembership`.
An entry references an existing identity and does not declare another entity.

A missing block means an empty list (no scheduled open tasks) with revision `1970-01-01 00:00:00` UTC.
A present block requires `modified`, even when its list is empty.
Canonical output MAY omit the block only when its list is empty and its revision equals that epoch.
Preserve other empty queue revisions.

Canonical output places `queue` after `deleted`, when present, and before live entity blocks (`label`, `location`, `task`).
Emit `modified` first, with explicit seconds.
Emit each `task` entry on its own line in saved order.
Task block declaration order does not change this order.

The saved order does not reserve Focus or Ready slots.
Section 5 filters eligible tasks before assigning slots.
Section 6.11 defines order mutations and synchronization.

## 5. Dynamic Computation of the 6 Tiers (Evaluation Pipeline)

Evaluate the document against one UTC reference instant `now` and an optional deadline lead-window duration $W_{\text{due}}$ (`DEFAULT_DUE_LEAD_SECONDS = 86_400` seconds / `24 hours` by normative default; `absent` when client lead-window promotion is disabled). Derive `localNow` through the configured time zone. Deferrals, deadlines, task history, revisions, and retention use UTC (converting stored UTC `history` timestamps to local time only for display). Day/time conditions use local calendar values. Section 6.10 defines calendar conversion. Label and GPS context remain inputs to tier derivation. `origin`, `label.link`, `task.link`, `history`, and scheduling notes (`suspended` `"<note>"` and `due` `"<note>"`) are strictly passive, non-blocking metadata with zero effect on 6-tier classification, condition evaluation, or `queue` ordering.

### 5.1 Pre-Filtering — Active `label` Context Filter & `scoped` Label Exclusion
Let $L(T)$ be the set of declared labels referenced in task $T$'s `labels` directive, and let $\text{isScoped}(l)$ be `true` when label $l$ carries the `scoped` header flag (Section 4.2):
- **When an active `label` context filter is selected (`activeLabelId = l*`):** Every task $T$ with $l^* \in L(T)$ enters Sections 5.2 through 5.5. Scope all six tiers (`Completed`, `Someday`, `Blocked`, `Focus`, `Ready`, `Planned`) to that label context.
- **When no `label` context filter is selected (global view):** Task $T$ is **restricted from the global view** (excluded in Section 5.1) if and only if $L(T)$ is non-empty and **every** assigned label in $L(T)$ is `scoped`:
  $$\text{isRestrictedFromGlobalView}(T) \iff L(T) \neq \varnothing \;\land\; \forall l \in L(T),\; \text{isScoped}(l)$$
  Tasks with $L(T) = \varnothing$ or with at least one regular (non-`scoped`) label ($\exists l \in L(T),\; \neg\text{isScoped}(l)$) enter Sections 5.2 through 5.5 in the global view. Tasks restricted to `scoped` labels remain excluded from the global view even when their `due` timestamp lies within $W_{\text{due}}$ or is overdue; they receive effective priority inside their filtered `activeLabelId` view.
- **Global Search & Prerequisite Resolution (`blocked`):** Full-board search always inspects all tasks in the document regardless of `scoped`. Prerequisite evaluation (`blocked` in Sections 5.4 and 6.9.2) always resolves across the complete document regardless of `scoped` or the active label filter.

### 5.2 Tier 6 — `Completed`
- **Selection Rule:** All retained tasks (after Section 5.1 pre-filtering) that possess a `finished` directive enter `Completed`. Completed tasks MUST NOT be members of `queue` (`InvalidQueueMembership`).
- **No Blocking Evaluation & Metadata Retention:** Retained tasks with `finished` remain in `Completed` when they match the label filter. Ignore deferrals, deadlines (`due`), prerequisite requirements, and activation conditions for their tier classification. All `history` entries (together with `origin`, `link`, and any preserved `due`, `passive`, and `due` note) remain intact on `Completed` tasks without clearing or rotation.
- **Garbage Collection:** Prune any task whose `finished` timestamp is strictly more than 30 days old during persistence, removing the entire `task` block (including its `history` entries) and replacing it with a deletion record under Section 6.8. Do not prune during loading or import.

### 5.3 Tier 5 — `Someday`
- **Selection Rule:** Retained open tasks (`finished` omitted) whose task ID is **not** listed in the `queue` block and that do not have an active `suspended` lock (`suspended > now` in UTC or `suspended forever`) under Section 6.10 enter `Someday`. When a finite `suspended` lock on an unqueued task expires (`suspended <= now` in UTC), the task is derived directly as `Someday` without mutating the document during read-only evaluation (Section 6.10.1).
- **Behavior:** These tasks form the unscheduled backlog and do not participate in the active pull cycle regardless of `due` (even when `due` lies within $W_{\text{due}}$ or is overdue).

### 5.4 Tier 4 — `Blocked`
- **Selection Rule:**
  - Any retained open task listed in `queue` that has at least one unsatisfied `blocked` dependency (`<id>:<count>`), an active `suspended` lock (`suspended > now` in UTC or `suspended forever`), or an unsatisfied effective `condition` rule group (`day`, `time`, `location`).
  - Any retained open task **not** listed in `queue` (such as in a hand-edited file, or after `scoped` label deletion flood protection under Section 6.8.1) that has an active `suspended` lock (`suspended > now` in UTC or `suspended forever`). When a finite `suspended` lock on an unqueued task expires (`suspended <= now` in UTC), the task is derived directly as `Someday` (`Tier 5`) under Section 5.3 without mutating the document during read-only evaluation (Section 6.10.1).
  - `due` (including overdue `due <= now`), `origin`, `label.link`, `task.link`, `history`, and scheduling notes NEVER classify a task as `Blocked`. Conversely, `due` NEVER overrides an active Section 5.4 restriction: an approaching or overdue task with an active `suspended` deferral, unmet `blocked` prerequisite, or unmet `condition` stays in `Blocked` until all Section 5.4 restrictions clear.
  - Evaluate restrictions in the following order:
    1. **Active Deferral (`suspended`):** The value is `forever`, or its UTC timestamp is later than `now`. Classify the task as `Blocked` without evaluating other restrictions. If a finite `suspended` timestamp expires (`suspended <= now` in UTC) on a task not listed in `queue`, the task enters `Someday` under Section 5.3.
    2. **Unmet Prerequisite (`blocked`):** At least one existing target has fewer completions than its stored requirement under Section 6.9. Missing or deleted targets do not block. Resolve targets across the complete document, regardless of `scoped` or the active label filter.
    3. **Unmet Condition (`condition` — `day` -> `time` -> `location` Short-Circuit):** Resolve candidate condition contexts under Section 4.4.3 (the task's own context if unlabeled, the active `label`'s effective context when filtered, or each non-`scoped` assigned `label` in $L_{\text{global}}(T)$ with `OR` across labels in global view). Evaluate each context against `localNow` by group in order `day`, `time`, `location` (Section 4.4.4). If no candidate context has all three effective groups satisfied, classify the task as `Blocked`.
- **Auto-Pull Cascade Behavior:** Scheduled tasks in `Blocked` consume no `Focus` or `Ready` slots and remain at their exact position inside `queue` so they resume their original queue slot automatically once all blocking conditions clear. Recompute eligible order before assigning slots whenever restrictions change.

### 5.5 Active Pull Cycle (`Focus`, `Ready`, `Planned`)

1. Filter the task IDs in `queue` to retain only open, currently executable tasks (not classified as `Blocked` under Section 5.4) that pass Section 5.1 pre-filtering for the active label filter context, preserving their relative `queue` order.
2. Derive effective priority for each retained executable task $T$ at UTC evaluation instant `now` and nullable lead-window duration $W_{\text{due}}$ (`DEFAULT_DUE_LEAD_SECONDS = 86_400` / `24 hours` by normative default; `absent` when client lead-window promotion is disabled):
   $$\text{isDueUrgent}(T, \text{now}, W_{\text{due}}) \iff W_{\text{due}} \neq \text{absent} \;\land\; T.\text{due} \neq \text{absent} \;\land\; \neg T.\text{passive} \;\land\; T.\text{due} \le \text{now} + W_{\text{due}}$$
   $$\text{hasEffectivePriority}(T, \text{now}, W_{\text{due}}) \iff T.\text{priority} \;\lor\; \text{isDueUrgent}(T, \text{now}, W_{\text{due}})$$
   At exact threshold equality ($T.\text{due} - \text{now} = W_{\text{due}}$), $\text{isDueUrgent}$ evaluates to `true`. Overdue tasks ($T.\text{due} \le \text{now}$) satisfy $T.\text{due} \le \text{now} + W_{\text{due}}$ for every $W_{\text{due}} \ge 0$ (including $W_{\text{due}} = 0$ seconds for at-deadline-only promotion). Partition the ordered sequence from Step 1 stably into two buckets:
   - First, all executable tasks with $\text{hasEffectivePriority}(T, \text{now}, W_{\text{due}}) = \text{true}$, in their saved relative `queue` order.
   - Second, all remaining executable tasks ($\text{hasEffectivePriority}(T, \text{now}, W_{\text{due}}) = \text{false}$), in their saved relative `queue` order.
   Neither `origin`, `link`, `history`, nor scheduling notes alter this ordering, and eligible tasks are never sorted by `due` timestamp within either bucket.
3. Slice positions `1..3` into `Focus` (`Tier 1`), positions `4..8` into `Ready` (`Tier 2`), and positions `9..N` into `Planned` (`Tier 3`). If more than `3` eligible tasks have effective priority, the first `3` in `queue` order occupy `Focus`, the next `5` occupy `Ready`, and any remainder wait at the top of `Planned`, pulling forward automatically as `Focus` tasks complete.

`Focus` MUST contain at most three tasks.
`Ready` MUST contain at most five tasks.
Apply these limits after filtering and effective-priority grouping.
Do not sort by task block declaration order.

Read-only evaluation MUST NEVER write `priority` or `passive` to the task or alter `task.modified` or `queue.modified`.
When a task becomes blocked, retain its saved position in `queue` and fill available slots with later eligible tasks.
When it becomes eligible again (or enters $W_{\text{due}}$), use that same `queue` position under its current effective priority and context.
This can displace existing `Focus` tasks into `Ready` and existing `Ready` tasks into `Planned`.
Recompute the complete assignment. Do not insert into already populated tiers.
Automatic blocking, release, lead-window entry, or context changes MUST NOT rewrite queue order or revisions.
Explicit queue moves can change relative positions while a task is blocked or within either effective-priority bucket.

For illustration, let `A` through `J` represent ten tasks in that order with equal effective priority.

| State | Focus | Ready | Planned | Blocked |
| --- | --- | --- | --- | --- |
| A is blocked | B, C, D | E, F, G, H, I | J | A |
| A becomes eligible | A, B, C | D, E, F, G, H | I, J | Empty |

With indexed task lookup, this ordering and slot assignment takes linear time in queue entries.
Condition evaluation adds the cost of the task, label, and prerequisite rules examined.

## 6. State Transitions & Document Mutations

State transitions update task, label, and location facts and the shared queue order. Apply related changes atomically, run open-task block-reason cleanup on committed mutations (Section 6.6), and validate the complete candidate before persistence. Derive tiers through Section 5. Section 6.11 defines queue revisions.

### 6.1 Creating a New Task, Label, or Location
- **Entity ID Generation:** Generate a unique, immutable 10-character Base62 `<task-id>`, `<label-id>`, or `<location-id>` (`<6xBase62Random><4xBase62Time>`) under Section 2.9.
- **New Completion History:** Initialize task `completions` to zero and omit its directive canonically.
- **Scheduled Task (`Planned` or `Focus` with `priority`):** Create the `task` block with `created` and `modified` set to `now` in UTC (adding the `priority` header flag when targeting `Focus`), append its task ID to the end of `queue`, and advance `queue.modified`. Section 5 fills available `Focus` and `Ready` slots automatically (placing effective-priority tasks ahead of regular tasks in `queue` order).
- **Unscheduled Task (`Someday`):** Create the `task` block with `created` and `modified` set to `now` in UTC without adding its ID to `queue`. `queue` and `queue.modified` remain unchanged.
- **New Label or Location:** Create the `label` (`[scoped]`) or `location` block with `modified` set to `now` in UTC after validating all directives under Section 4.2 or Section 4.3.

### 6.2 Scheduling from `Someday` & Moving to `Someday`
- **Scheduling from `Someday`:** Append the task's ID to the end of `queue` and advance `queue.modified`, preserving `due` (with its note), `origin`, and `history` unchanged. If explicitly promoting to `Focus` (`priority` set to `true`), also reset occurrence-scoped `passive` on `due` to omitted (`false`) and advance `task.modified`; if no task-level attributes are changed, `task.modified` MUST remain unchanged.
- **Moving to `Someday`:** Remove the task's ID from `queue` and advance `queue.modified`. If the task had a `priority` flag or `suspended` directive (together with any `suspended` note), strip them and advance `task.modified`; otherwise, leave `task.modified` unchanged. Preserve `(due, passive, due-note)`, `origin`, and `history` unchanged.

### 6.3 Downgrading an Active Task (`Focus`, `Ready`, and `Planned`)

Evaluate the board under Section 5 at the active evaluation parameters (`now`, `localNow`, `timeZone`, $W_{\text{due}}$, `activeLabelId`, and optional GPS coordinates — including in the unfiltered global view where `activeLabelId` is absent) before resolving the task's source tier, $E_{\text{ctx}}$, and $\text{isDueUrgent}(T, \text{now}, W_{\text{due}})$, and reevaluate the mutated board with the same $W_{\text{due}}$.
A downgrade outside `Focus`, `Ready`, or `Planned` is a pure no-op and leaves the document completely unchanged (without running board-wide block-reason cleanup).

- **Step-Down Downgrade from `Focus` to `Ready` (Active-Filter-Relative Anchor):**
   Let $E_{\text{ctx}}$ be the Section 5.5 Step 2 effective-priority-partitioned ordered sequence of other executable tasks (`[...focus, ...ready, ...planned]` excluding the downgraded task $T$ itself) that pass Sections 5.1 through 5.4 for the active filter context (`activeLabelId = absent` for the global view, where `scoped`-only tasks are excluded under Section 5.1; or `activeLabelId = l*` for a filtered label view):
   1. **When $|E_{\text{ctx}}| \ge 7$ and the 7th task in $E_{\text{ctx}}$ (the slot-8 anchor) has $\text{hasEffectivePriority} = \text{true}$:** Preserve `T.passive`, `T`'s `due` note, and `T.history` unchanged; keep `T.priority` unchanged if $\text{isDueUrgent}(T, \text{now}, W_{\text{due}})$ is already `true` (so an explicit `priority` flag is never stripped when `due` is also urgent, leaving `task.modified` unchanged) or set `T.priority = true` when $\text{isDueUrgent}(T, \text{now}, W_{\text{due}})$ is `false` (advancing `task.modified` only if `T.priority` changed from `false` to `true`); and move $T$ in `queue` immediately after the **7th task in $E_{\text{ctx}}$** (advancing `queue.modified` only if `queue` order changed) so $T$ occupies the 8th executable slot (`Ready`).
   2. **When $|E_{\text{ctx}}| < 7$ or the 7th task in $E_{\text{ctx}}$ has $\text{hasEffectivePriority} = \text{false}$:** Strip `T.priority` if present AND set occurrence-scoped `T.passive = true` (preserving `due` note and `history`) when $\text{isDueUrgent}(T, \text{now}, W_{\text{due}})$ is `true` (advancing `task.modified` when either attribute changes). Move $T$ in `queue` immediately after the 7th task in $E_{\text{ctx}}$ when $|E_{\text{ctx}}| \ge 7$, immediately after the **last task in $E_{\text{ctx}}$** when $1 \le |E_{\text{ctx}}| < 7$, or keep $T$'s position in `queue` unchanged when $|E_{\text{ctx}}| = 0$ (applying the strict no-op rule below when neither task attributes nor `queue` order change). Setting `passive` prevents an urgent-`due` task from bouncing back ahead of regular tasks into `Focus` upon reevaluation.
- **Downgrade to `Planned` (from `Ready`, or end of queue when `< 8` executable tasks exist):** Strip `T.priority` if present and set occurrence-scoped `T.passive = true` (preserving `due` note and `history`) when $\text{isDueUrgent}(T, \text{now}, W_{\text{due}})$ is `true` (advancing `task.modified` only when a task attribute changed), and move the task ID to the end of `queue` (advancing `queue.modified` only if its position in `queue` changed). `Planned` starts at the ninth executable slot, after three `Focus` and five `Ready` slots. The task enters `Planned` when at least eight other executable tasks precede it; with fewer than eight executable tasks in total, it takes the last available slot in `Focus` or `Ready`.
- **Downgrade from `Planned` to `Someday`:** Remove the task ID from `queue` and advance `queue.modified`. Strip `priority` and `suspended` (together with any `suspended` note) if present and advance `task.modified` only if a task attribute was removed (Section 6.2). Preserve `(due, passive, due-note)`, `origin`, and `history` unchanged. The task enters `Someday`.

Preserve the relative order of every other queue entry, including blocked tasks and tasks outside the active label filter.
Advance `queue.modified` only when `queue` changes.
Advance `task.modified` on the downgraded task only when its own attributes (`priority`, `passive`, or `suspended`) change.
If a `Focus` or `Ready` task has neither `priority` nor non-`passive` urgent `due` (`hasEffectivePriority == false`) and its target `queue` position equals its current `queue` position, neither task attributes nor `queue` order change; return as a pure no-op leaving `task.modified`, `queue.modified`, and bystander tasks unchanged.
Do not revise other tasks merely because their derived tier changes.

### 6.4 Completing a Task (From Any Open Tier)
- **Standard Task (`repeat` Omitted):** Complete any open task under Section 6.9.4. Set `finished` to `now` in UTC, increment `completions` by `1`, mark checklist steps `true`, **clear any `suspended` (together with any `suspended` note) and `blocked` directives on the completed task**, preserve `(due, passive, due-note)`, `origin`, and **all `history` entries unchanged**, advance `task.modified` once, remove the task ID from `queue` (advancing `queue.modified` if the ID was present in `queue`), and apply open-task block-reason cleanup (Section 6.6) so satisfied non-recurring-to-recurring `blocked` references on open dependents are stripped in the same atomic transaction. Reevaluate dependents and refill active slots.
- **Recurring Task (`repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]` Present):** Use the same guarded completion operation from Section 6.9.4. Omit `finished`, increment `completions` by `1`, clear any one-off `suspended` note, preserve `origin` and **all `history` entries unchanged across every recurrence cycle without clearing or ring-buffer rotation**, rearm retained prerequisites for the next occurrence under Section 6.9.3, and apply the reschedule below atomically:
  1. **Remain Open:** Keep `finished` omitted so the task stays open and exempt from 30-day garbage collection.
  2. **Reset Subtasks:** Reset every `step` directive in `subtasks` to `step false "<text>"`.
  3. **Ensure Priority on Wake-Up:** Enable the `priority` header flag on `task <task-id> priority {` if not already present.
  4. **Calculate Next Occurrence (`due` Omitted vs. `due` Present):**
     - **Without `due` (`due` Omitted — Completion-Relative Mode 1):** Compute `<next_due>` (`> now`) from the completion instant `localNow` + `<count> <unit>` combined with `<repeat-time>` (defaulting to `00:00:00` local time, ignoring `lead`) under Section 6.10.3, and store that UTC instant in `suspended` (with no `suspended` note).
     - **With `due` Present (`due` as Fixed Calendar Anchor + Explicit `lead` Preparation Offset — Mode 2):** Advance `due` along its fixed local calendar schedule by the smallest integer multiple $k \ge 1$ of `<count> <unit>` until `newDue > now`, preserve `due`'s `<note>` unchanged, reset occurrence-scoped `passive` to omitted (`false`) so the new deadline cycle participates normally in lead-window effective priority, compute `newSuspended` from `targetDueLocalDate - leadDays` (`0` when `lead` is omitted) combined with `<repeat-time>` (`00:00:00` when omitted) clamped to $\le \text{newDue}$ under Section 6.10.3, and set `suspended = newSuspended` (or omit `suspended` immediately when `newSuspended <= now`, always clearing any `suspended` note).
  5. **Store the Next Occurrence:** Advance `task.modified` once, keep the task ID at its existing position in `queue` (or append it to `queue` and advance `queue.modified` if it was completed while not in `queue`), and run open-task block-reason cleanup (Section 6.6). While `suspended > now`, the task is derived as `Blocked` (`Tier 4`) without reserving an active slot; when `suspended` is omitted (`newSuspended <= now`) or once `suspended <= now`, it is eligible in `Focus` (`Tier 1`) at its saved `queue` position.

### 6.5 Restoring a Task from `Completed`

Completed checklist steps remain locked while the task has `finished`, including during editing.
Permit adding and removing steps.
Mark each newly added step complete and lock it.

Restoration creates a new occurrence.
Remove `finished`, `suspended` (including an expired deferral, `forever`, and any `suspended` note), and `due` (including `passive` and any `due` note).
Preserve **`history`**, `origin`, the completion counter, and the `repeat` rule (including `<repeat-time>` and `lead <lead-count> days`) unchanged.
Reset all checklist steps to `false`.
Rearm prerequisites under Section 6.9.3.
Advance `task.modified` once, apply the selected scheduling target, and run open-task block-reason cleanup across open tasks (Section 6.6):

- **Target `Someday`:** Strip `priority` if present; do not add the task ID to `queue` (`queue.modified` unchanged).
- **Target `Planned`:** Strip `priority` if present, append the task ID to the end of `queue`, and advance `queue.modified`.
- **Target `Focus`:** Set `priority` to `true`, append the task ID to the end of `queue`, and advance `queue.modified`. Existing eligible effective-priority tasks remain ahead.

Persist all restoration changes atomically.
Derive the actual tier under Section 5.
Unmet prerequisites or conditions can block a scheduled restored task.
Capacity can place it in another active tier.
Setting a new deferral or deadline requires a separate explicit mutation under Section 6.6.

**Verification cases:**

| Case | Expected result |
| --- | --- |
| Restore a task with `suspended forever "note"` and `due ... passive "note"` to `Someday` | Remove `finished`, `suspended` (and note), `due` (with `passive` and note), and `priority`. Keep it outside `queue` (`queue.modified` unchanged) and classify it as `Someday`. |
| Restore a task with `origin`, `history`, and a deadline to `Planned` | Remove `finished`, `suspended`, `due` (with `passive` and note), and `priority`, preserve `origin` and all `history` entries unchanged, append its ID to `queue`, and advance `queue.modified`. |
| Restore to `Focus` with an unmet prerequisite | Remove `finished`, `suspended`, and `due`, set `priority`, append its ID to `queue`, and classify it as `Blocked`. |
| Restore a task with completion counter `7`, `origin`, `history`, and `repeat 1 months 09:00 lead 5 days` | Keep all four values unchanged. Reset the checklist and rearm remaining live recurring prerequisites. |
| Restoration persistence fails | Preserve the complete previous task and queue. |

### 6.6 Ordinary Directive Mutations (`suspended`, `due`, `repeat`, `blocked`, `origin`, `link`, `history`, `condition`, `location`) & Automatic Block-Reason Cleanup
- **Setting `suspended`:** Convert local input under Section 6.10 and validate any optional deferral `<note>` (`1..MAX_NOTE_LENGTH` scalar values). Set a future UTC instant or `forever` (with optional `<note>`). If the task ID is not in `queue`, append its ID to the end of `queue` and advance `queue.modified`; otherwise, preserve its `queue` position. Clearing `suspended` removes both `suspended` and any attached `suspended` `<note>` without changing `queue` order. Editing or clearing a `suspended` `<note>` while retaining `suspended` advances `task.modified` once. Advance `task.modified` and any changed `queue.modified`, and reevaluate remaining restrictions.
- **Setting `due`:** Convert local calendar input to UTC under Section 6.10, validate any optional deadline `<note>` (`1..MAX_NOTE_LENGTH` scalar values), advance `task.modified` once, and **preserve `queue` membership and order unchanged** (setting `due` on an unscheduled `Someday` task does not append the task to `queue`). Changing `due` to a different UTC timestamp (`nextDue != existingDue`) resets occurrence-scoped `passive` to omitted (`false`) unless `passive` is explicitly specified for the new timestamp; explicitly setting `priority` to `true` also resets `passive` to omitted (`false`). Clearing `due` removes `due`, `passive`, and any attached `due` `<note>`, advances `task.modified` once, and preserves `queue` membership and order. Editing or clearing `due`'s `<note>` or `passive` modifier while retaining `due` advances `task.modified` once.
- **Setting `repeat`:** Set or clear `<count> <unit> [<repeat-time>] [lead <lead-count> days]` (`1..MAX_REPEAT_COUNT` on both `<count>` and `<lead-count>`) under Sections 4.1.2 and 6.10, and advance `task.modified`. Preserve the current deferral, deadline, `history`, completion counter, and current prerequisite requirements (applying automatic open-task block-reason cleanup below if clearing `repeat` makes an already-satisfied prerequisite non-recurring-to-recurring).
- **Setting `blocked`:** Add, retain, or remove prerequisite targets under Section 6.9.3. Preserve requirements for unchanged targets and capture requirements for new targets. Unknown forward-reference `<task-id>` tokens (absent from both live `task` blocks and `deleted`) MUST NOT be pruned during parsing, loading, or mutations. Reject self-dependencies and cycles (`CircularDependency`), and enforce `<= MAX_ARGS_PER_STMT` (`64`, `LimitExceeded`). Advance `task.modified` without changing the completion counter.
- **Setting `origin`:** Validate both `<namespace>` and `<external-key>` under Sections 2.8 and 4.1.2, set or update `origin "<namespace>" "<external-key>"`, advance `task.modified` once under Section 6.7.1, and preserve `queue` membership and order unchanged. Clearing `origin` removes the directive, advances `task.modified` once, and preserves `queue` membership and order.
- **Setting `link` (`task` and `label`):** Add, modify, reorder, or remove `link "<title>" "<uri>"` directives in preserved declaration order (`0..MAX_LINKS_PER_TASK` = `20` on `task`, `0..MAX_LINKS_PER_LABEL` = `20` on `label`; `LimitExceeded` if exceeded; `InvalidUri` on missing or forbidden schemes) and advance `task.modified` or `label.modified` once under Section 6.7.1 (updating `label.link` leaves task revisions and `queue.modified` untouched).
- **Setting `history` (`task`):** Adding an entry `(timestampUtc, text)`, editing an entry `(oldTs, oldText) -> (newTs, newText)` via set replacement `(history \ {(oldTs, oldText)}) ∪ {(newTs, newText)}` when `(oldTs, oldText)` is present, or removing an entry `(timestampUtc, text)` validates UTC `<timestamp>` and single-line `<text>` under Sections 2.8 and 4.1.2, and enforces both `<= MAX_HISTORY_PER_TASK` (`500` normalized entries) and canonical `task` direct child statement count `<= MAX_STMTS_PER_BLOCK` (`1_024`, `LimitExceeded` if exceeded; guaranteed non-colliding for every valid canonical `task` block since `34 + 500 = 534 <= 1_024`). If the resulting normalized `(timestampUtc, text)` set differs from the prior normalized set, update `task.history` and advance `task.modified` once under Section 6.7.1 while preserving `queue` membership and `queue.modified` unchanged. **No-Op Revision Protection:** Adding an already-present `(timestampUtc, text)` pair, editing an entry without changing the normalized set, or removing a non-existent pair leaves the normalized `history` set unchanged and MUST return as a pure no-op without advancing `task.modified` or running board-wide cleanup.
- **Setting `condition`:** Set or update task- or label-level activation conditions (`day`, `time`, `location <loc-1> ...`), task-level group resets (`day any`, `time any`, `location any`), or the task-level global reset (`condition any`), coalescing multiple `location` rules per entity under Section 4.4.1, and advance `modified`.
- **Updating `location`:** Updating `name`, `note`, `source`, `coordinates`, or `radius` on a `location` block validates the directive arguments under Section 4.3 and advances `location.modified` once under Section 6.7.1.
- **Automatic Block-Reason Expiry & Resolution Cleanup (Committed Mutations & Refresh/Synchronization):**
  - **Parser & Read-Only Evaluator Purity:** Raw parsing and pure Section 5 view evaluation MUST preserve stored `suspended`, `suspended` notes, and `blocked` directives verbatim in memory without mutating storage or revisions, so `sourceDigest` (Section 6.7.2) and baseline `B` decoding remain exact.
  - **When Cleanup Runs:** During any guarded refresh/synchronization (Sections 6.7.5 through 6.7.8) or any **committed** domain mutation evaluated at UTC instant `now` (skipping board-wide cleanup on pure no-op calls where the requested operation itself makes zero task, label, location, or `queue` changes, or fails validation), inspect every live **open** task $D$ (`finished` omitted):
    1. **Expired Finite Deferrals:** If $D.\text{suspended}$ is a finite UTC timestamp with $D.\text{suspended} \le \text{now}$, strip both `suspended` and any attached `suspended` `<note>` from $D$ (queued open tasks retain their exact `queue` position with `queue.modified` unchanged; unqueued open tasks remain outside `queue` in `Someday`; `suspended forever` never expires by wall-clock time).
    2. **Confirmed Deleted Prerequisites:** Strip any `<target-id>[:<req>]` from $D.\text{blocked}$ whose `<target-id>` has a task record in `deleted` (omitting `blocked` when zero entries remain).
    3. **Satisfied Non-Recurring-to-Recurring Prerequisites:** Strip any `<target-id>[:<req>]` from $D.\text{blocked}$ whose `<target-id>` matches a live task $T_{\text{target}}$ with $T_{\text{target}}.\text{completions} \ge \text{req}$ AND where either $D.\text{repeat}$ is omitted or $T_{\text{target}}.\text{repeat}$ is omitted (omitting `blocked` when zero entries remain).
    4. **Preserved Restrictions & Deadlines:** Retain `<target-id>[:<req>]` on $D$ when both $D.\text{repeat}$ and $T_{\text{target}}.\text{repeat}$ are present (so Section 6.9.3 rearms `<target-id>:<completions + 1>` when $D$ completes its occurrence), retain unknown forward references (`<target-id>` absent from both live `task` blocks and `deleted`), retain overdue `due <= now` deadlines (with `passive` and `due` `<note>`), and retain standing cyclical/spatial `condition` rules (`day`, `time`, `location`).
    5. **Single Monotonic Revision:** Advance `D.modified = max(now, previousEffectiveModifiedAt + 1 second)` once on each open task whose stored directives changed (`InvalidTimestamp` if the result exceeds `9999-12-31 23:59:59`, aborting the mutation without partial changes).

### 6.7 Synchronization, Baseline Merging, and Entity Revisions

Synchronization uses decoded entity values and one revision timestamp per entity.
Field merging uses a proven common baseline.
Individual fields and checklist items do not receive timestamps.

#### 6.7.1 Entity Identity and Revision Timestamps

- Identify each entity by its namespace (`task`, `label`, or `location`) and immutable ID.
- Equal IDs in different namespaces identify different entities.
- A task's effective revision time is `modified`, when present.
- Without `modified`, use the maximum of its present `created` and `finished` timestamps.
- A label's or location's effective revision time is `modified`, when present.
- Without `modified`, a label's or location's effective revision time is `1970-01-01 00:00:00` UTC.
- Resolve these fallback values without changing the entity.

An ordinary entity mutation at UTC time `now` MUST set:

```text
modified = max(now, previousEffectiveModifiedAt + 1 second)
```

Use UTC second precision.
These values are monotonic entity revision timestamps.
Sections 6.7.4 and 6.7.6 define selection and merge revisions.

#### 6.7.2 Common Baseline & Normative Source Fingerprint (`sourceDigest`)

The baseline is a successfully acknowledged shared snapshot that precedes both variants.
Retain this snapshot durably in the client's synchronization state.
Store its acknowledged deletion history generation from Section 6.8 alongside it.
Bind every loaded working copy and acknowledged baseline `B` to the dataset, format version, entity identity, and the **exact byte length and SHA-256 digest (`sourceDigest`) of the raw `.tdf` byte stream** (paired with HTTP `ETag` when synchronizing via WebDAV).
Do not rely on filesystem `mtime` or inode numbers alone to detect concurrent external modifications.
A revision timestamp alone does not prove common ancestry.

Use field merging only when this common baseline contains the entity.
Without that baseline, select the complete winner for entities present on both sides under Section 6.7.4 (unioning task `history` entries under Section 6.7.5 Point 4).
Apply Sections 6.7.8 and 6.8 to one-sided entities and deletion records.
Baseline storage adds no fields to TDF entity blocks.
An import or dataset change MUST invalidate an incompatible baseline.

#### 6.7.3 Decoded Values and Deterministic Payload Order

Compare decoded values instead of raw lines, indentation, comments, or quote styles.
Represent an omitted optional value as absent.
Treat omitted `labels` as an empty set and omitted `blocked` as an empty prerequisite map.
Normalize each prerequisite to `(targetId, requiredCompletion)` and retain the greatest requirement for duplicate target IDs.
Treat omitted `link` directives (on `task` and `label`) as an empty ordered list and omitted `history` directives on `task` as an empty sorted list.

Use these normalized comparison values:

- Decode strings using Section 2.7. Preserve Unicode characters without applying Unicode normalization.
- Expand UTC timestamps (`created`, `finished`, `modified`, `due`, `history`, and finite `suspended`) into their six calendar components (and equivalent UTC epoch seconds), using the defaults from Section 2.8.
- Preserve UTC meaning for stored timestamps and local meaning for recurrence clocks and activation windows.
- Represent a time window endpoint as an integer minute of day.
- Represent a `repeat` rule as `(count, unit, localClock, leadDays)`.
- Normalize its local clock to `(hour, minute, second)`, using zero for omitted seconds or an omitted clock, and normalize omitted `lead <lead-count> days` to `leadDays = 0`.
- Represent finite deferrals (`suspended`) as `(false, utcComponents, optionalDecodedSuspendedNote)`, `forever` as `(true, emptyList, optionalDecodedSuspendedNote)`, and omission as absent (where `optionalDecodedSuspendedNote` is absent when the note argument is omitted).
- Represent deadlines (`due`) as absent when omitted, or as `(utcComponents, passive, optionalDecodedDueNote)` when present (where omitted `passive` is `false` and `optionalDecodedDueNote` is absent when the note argument is omitted).
- Represent `origin` as absent when omitted, or as the 2-tuple of decoded Unicode strings `(namespace, externalKey)` when present (compared lexicographically first by `namespace` and then by `externalKey` using unsigned UTF-8 byte order, with absent preceding present).
- Normalize `history` on a `task` into the deduplicated list of `(utcComponents, decodedText)` pairs sorted first by ascending UTC instant (epoch seconds) and then by ascending unsigned UTF-8 byte order of `decodedText`.
- Compare colors as uppercase hexadecimal strings.
- Remove duplicate label IDs and sort label sets in ascending ASCII order.
- Sort prerequisite map entries by target ID and compare their required numbers as integers.
- Resolve an omitted completion counter to zero.
- Preserve declaration order in `link` lists (on `task` and `label`) and checklist steps.
- Normalize decimal `<number>` values (`coordinates <lat> <lon>` and `radius <meters>` in `location` blocks) as normalized decimal text:
  - Remove redundant leading integer zeros, keeping one integer digit.
  - Remove trailing fractional zeros.
  - Preserve a nonzero decimal value's sign.
  - Remove an empty fractional part and represent every signed zero (`-0.0`) as `0`.
  - Compare `normalizedLat`, `normalizedLon`, and `normalizedRadius` as normalized decimal strings by unsigned UTF-8 bytes.

Normalize conditions into `(globalAny, dayGroup, timeGroup, locationGroup)`.
Each group is `(resetAny, orderedRules)`.
Preserve rule order within `dayGroup` and `timeGroup`.
Day rules contain ordered weekday tokens.
Time rules contain start and end minutes.
For `locationGroup`, coalesce all `location <loc-1> [<loc-2> ...]` rules on the entity into a single ordered list of `<location-id>` tokens deduplicated in first-seen declaration order across the entity (`1..MAX_LOCATION_REFS_PER_ENTITY`).
An absent condition model has false reset flags and empty rule/location lists.
Inline and block condition forms use the same normalized model.

Use these payload tuples (aligning non-state `task` components with canonical `task` directive order and keeping `history` outside `Task state`):

| Entity or value | Component order |
| --- | --- |
| Task payload | `name`, `note`, `created`, `labels`, `origin`, `link`, `history`, `condition`, task state |
| Label payload | `scoped`, `name`, `note`, `color`, `link`, `condition` |
| Location payload | `name`, `note`, `(coordinates, source)`, `radius` |
| Task state | `completions`, `priority`, `finished`, `suspended`, `due`, `repeat`, `blocked`, `subtasks` |
| Subtasks | `auto-finish`, ordered `(completed, text)` steps |
| Origin | Decoded `namespace`, decoded `externalKey` |
| Link | Decoded `title`, decoded `uri` |
| History entry | `utcComponents` (UTC epoch seconds), decoded `text` |
| Location geographic unit | `(normalizedLat, normalizedLon)`, optional decoded `source` |

An omitted `subtasks` block differs from a present checklist.
An omitted `priority`, `passive`, or `scoped` flag is `false`.
Exclude `modified` from the payload.

Compare tuples and lists lexicographically.
At the first differing component, apply its value comparison.
An absent value precedes a present value.
False precedes true.
Compare integers numerically.
Compare strings by unsigned UTF-8 bytes.
When one list (including a normalized `history` or `link` list) is an exact prefix, the shorter list precedes the longer list.
These computed tuples add no stored metadata.

#### 6.7.4 Complete Entity Winner

For two versions of the same entity, compare these criteria in order:

1. For task versions with different completion counters, the greater counter wins.
2. Otherwise, the later effective revision timestamp wins.
3. At equal timestamps, the greater payload tuple from Section 6.7.3 wins.
4. At equal payloads and timestamps, prefer an explicit `modified` directive over its absence.

If all criteria are equal, the versions are equivalent for merging.
Input direction MUST NOT select the winner.
Selecting an existing version MUST preserve its revision timestamp, including an omitted `modified` directive.

#### 6.7.5 Merge Units and Three-Way Rules

Let `B` be the common baseline, `L` the local version, and `R` the incoming version.
Determine the complete winner `W` of `L` and `R` (and opposing side `Loser`) from their raw un-normalized payloads under Sections 6.7.3 and 6.7.4 before merging units.

| Entity | Merge unit | Rule |
| --- | --- | --- |
| Task, label, and location | Each of `name` and `note` | Merge each scalar separately. |
| Label | `scoped` | Merge as an independent boolean scalar unit. |
| Label | `color` | Merge as an independent scalar unit. |
| Location | `(coordinates, source)` | Merge `coordinates` `(normalizedLat, normalizedLon)` and optional `source` together as one coupled geographic reference unit. |
| Location | `radius` | Merge as an independent scalar unit. |
| Task | `labels` | Merge the label reference set (`added` / `removed`), elevating any newly added reference targeting an opposing tombstoned label to `DeletionConflict` (Section 6.8.2). |
| Task and label | `condition` | Strip non-conflicting tombstoned `<location-id>` tokens from `B`, `L`, and `R` in strict `label`-before-`task` order (converting any task `locationGroup` emptied by removing tombstoned tokens directly into its cascade target state: `location any` when a post-merge live label defines a non-empty post-cascade `location` rule, or empty otherwise) before comparison; merge atomically when `globalAny == true` in any of `B`, `L`, `R`, otherwise merge `dayGroup`, `timeGroup`, and `locationGroup` per rule group. |
| Task | `origin` | Merge `(namespace, externalKey)` (or `absent`) as one atomic scalar pair unit. |
| Task and label | Complete ordered `link` list | Merge as one atomic value on each entity. |
| Task | `history` | Reconcile as an occurrence-independent `(timestampUtc, text)` set across both Case 1 and Case 2 (and via set union in baseline-free two-way merges when the task is present in both `L` and `R` without `B`). |
| Task | `Task state` (`completions`, `priority`, `finished`, `suspended`, `due`, `repeat`, `blocked`, `subtasks`) | Copy complete occurrence state from `W` when `completions` differs among `B`, `L`, `R` or `finished` is present in at least one of `B`, `L`, `R`; otherwise unbundle `priority`, `suspended` (pre-normalizing finite `suspended <= now` to `absent`), `due`, `repeat`, `blocked` (`V.repeat`-aware pre-normalization + per-`targetId` map merge), and `subtasks` (step-wise boolean merge on matching step texts). |

Apply these rules to each scalar or atomic value after normalization:

1. If `L` and `R` have equal values, keep that value.
2. Otherwise, if `L` equals `B`, keep `R`.
3. Otherwise, if `R` equals `B`, keep `L`.
4. Otherwise, keep this unit's value from `W`.

Clearing an optional value is a change to absence.
Use the same `W` for every true unit conflict.
Keep the task's `created` timestamp from `W`.
Preserve the entity namespace and ID.

**1. Label Reference Set Merge (`labels`):**
For a live task present in `B`, calculate:

```text
added = (L minus B) union (R minus B)
removed = (B minus L) union (B minus R)
result = (B minus removed) union added
```

Never silently strip a newly introduced label reference $l \in A_L(T) \cup A_R(T)$ merely because the opposing side contains a deletion record for `label` $l$ in `deleted`; classify `label` $l$ as a `DeletionConflict` under Section 6.8.2.
For non-conflicting deleted labels ($l \notin A_L(T) \cup A_R(T)$), remove tombstoned label IDs under Section 6.7.8.
Emit the merged label set in ascending ASCII order and omit an empty `labels` directive.

**2. Pre-Merge Tombstone Stripping and Commutative Group-Wise `condition` Merge:**
- Before stripping tombstoned locations or selecting a `condition` winner, evaluate newly introduced location references $A^{\text{loc}}_X(E)$ on the input entities $E_L, E_R$ across all live and `DeletionConflict`-retained tasks and labels under Section 6.8.2; if any $A^{\text{loc}}_X(E)$ references a `location` tombstoned on the opposing side, classify that `location` as a `DeletionConflict` and retain its live `location` block.
- Next, execute `condition` tombstone stripping and merging in strict **`label`-before-`task` order** (after resolving each task's post-merge live label set $L_{\text{after}}(T) = L_{\text{before}}(T) \setminus \text{DeletedLabels}$ under Point 1 and Section 6.7.8 Point 1). Before comparing or selecting a winner among `B.condition`, `L.condition`, and `R.condition` (including in two-way merges when `B` is absent), strip every `<location-id>` that is **non-conflictingly tombstoned** in the merged `deleted` block (i.e., not in `DeletionConflict`) from each present variant $V \in \{B, L, R\}$:
  - **On a `label` block:** If stripping non-conflicting tombstoned `<location-id>` tokens leaves $V.\text{locationGroup}$ with zero `<location-id>` tokens, set $V.\text{locationGroup}$ to the empty `locationGroup` (`resetAny = false, orderedRules = []`). Merge all live `label` blocks first so each live label's post-cascade `locationGroup` is known before processing tasks.
  - **On a `task` block:** If $V.\text{locationGroup}$ contained $\ge 1$ `<location-id>` tokens and stripping non-conflicting tombstoned `<location-id>` tokens leaves $V.\text{locationGroup}$ with zero `<location-id>` tokens, convert $V.\text{locationGroup}$ directly into its **post-cascade target state** (Section 6.7.8 Point 2):
    - Set $V.\text{locationGroup}$ to **`location any` (`resetAny = true, orderedRules = []`)** if at least one live `label` in the task's post-merge `labels` set $L_{\text{after}}(T)$ defines a non-empty post-cascade `location` rule group.
    - Set $V.\text{locationGroup}$ to the **empty `locationGroup` (`resetAny = false, orderedRules = []`)** otherwise (and if no live label in $L_{\text{after}}(T)$ defines a non-empty post-cascade `location` rule group while `B.locationGroup` had $\ge 1$ `<location-id>` tokens that were all tombstoned on side $X \in \{L, R\}$ and side $X$ has `location any`, normalize side $X$'s cascade-inserted `location any` to the empty `locationGroup` as well).
    Converting an all-tombstoned `<location-id>` list in `B`, `L`, and `R` directly into its post-cascade target state (`location any` or empty) ensures that a side $X$ whose local deletion cascade already inserted `location any` matches transformed `B` (`X.locationGroup == B.locationGroup`), while an explicit user removal of the task's `location` rule on the opposing side (`locationGroup` cleared to empty so the task inherits from its label) differs from transformed `B` (`location any`) and wins cleanly in the three-way merge.
- Using these cascade-normalized `B.condition`, `L.condition`, and `R.condition` variants:
  - **Global Reset Fallback (`globalAny == true`):** If any of cascade-normalized `B.condition`, `L.condition`, or `R.condition` sets `globalAny == true` (`condition any`), merge the complete `condition` model as one atomic scalar unit using cascade-normalized `B` and complete entity winner `W`.
  - **Group-Wise Merge (`globalAny == false` in all three):** Otherwise, merge `dayGroup`, `timeGroup`, and `locationGroup` as three independent rule-group units using cascade-normalized `B`, complete entity winner `W`, and opposing side `Loser`:
    1. **`dayGroup` and `timeGroup`:** Apply the standard three-way scalar rule using `W` on conflict.
    2. **`locationGroup` (Commutative `W`-Anchored Ordered-List Merge):**
       - If `L.locationGroup == R.locationGroup`, keep `L.locationGroup`.
       - Else if `L.locationGroup == B.locationGroup`, keep `R.locationGroup`.
       - Else if `R.locationGroup == B.locationGroup`, keep `L.locationGroup`.
       - Else if `resetAny == true` (`location any`) in any of `B.locationGroup`, `L.locationGroup`, or `R.locationGroup`, keep `W.locationGroup`.
       - Else (both `L` and `R` modified their `<location-id>` lists with `resetAny == false`), start from `W.locationGroup`'s ordered `<location-id>` list, remove any `<location-id>` in `B minus Loser`, and append any `<location-id>` in `Loser minus B` not already present in `Loser`'s declaration order.
- Validate the merged `condition` model under Section 6.7.7 against `MAX_ARGS_PER_STMT = 64` and `MAX_LOCATION_REFS_PER_ENTITY = 63` (`LimitExceeded` if exceeded).

**3. Coupled Geographic Reference Unit (`(coordinates, source)` on `location`):**
When merging a live `location` block across `B`, `L`, and `R`, merge `name`, `note`, `(coordinates, source)`, and `radius` as four independent merge units. Coupling `coordinates` `(normalizedLat, normalizedLon)` and optional `source` into one atomic unit guarantees that a concurrent address typo fix on old coordinates and a relocation to new coordinates + new address never produce a mismatched hybrid of old `source` and new `coordinates`.

**4. Occurrence-Independent Task History Set Merge (`history`):**
For every surviving live `task` block $T$, reconcile `history` as a set of `(timestampUtc, text)` pairs **outside `Task state` and independently of `completions` and `finished`** across both Case 1 and Case 2 (so completing a recurring cycle or finishing a task on one side and adding, editing, or deleting a `history` entry on the opposing side merge without data loss):
- **With Common Baseline ($T \in B$):**
  $$\text{added} = (T_L.\text{history} \setminus T_B.\text{history}) \cup (T_R.\text{history} \setminus T_B.\text{history})$$
  $$\text{removed} = (T_B.\text{history} \setminus T_L.\text{history}) \cup (T_B.\text{history} \setminus T_R.\text{history})$$
  $$T_M.\text{history} = \text{canonicalSort}((T_B.\text{history} \setminus \text{removed}) \cup \text{added})$$
- **Without Common Baseline ($T \notin B$ and $T$ Present in Both `L` and `R`):**
  $$T_M.\text{history} = \text{canonicalSort}(T_L.\text{history} \cup T_R.\text{history})$$
- **One-Sided Surviving Task ($T$ Present on Only One Side $X \in \{L, R\}$):**
  $$T_M.\text{history} = T_X.\text{history}$$
Validate $|T_M.\text{history}| \le \text{MAX\_HISTORY\_PER\_TASK}$ (`500`) under Section 6.7.7 (`LimitExceeded` on overflow; never silently truncate entries).

**5. Two-Level Task Occurrence Merge Rule (`Task state`):**
First resolve non-conflicting tombstones (`mergedDeletedTasks`) and every surviving live task's merged `(completions, finished, repeat)` (`mergedTasksById`, which do not depend on `blocked`). Raw payloads remain un-normalized when selecting complete entity winner `W` (`Section 6.7.4`) and Case 1 cross-occurrence winners (`Section 6.9.5`).
- **Case 1 — Cross-Occurrence or Completion-State Transition (`completions` differs among `B`, `L`, `R`, or `finished` is present in at least one of `B`, `L`, `R`):**
  Copy the complete occurrence state (`completions`, `priority`, `finished`, `suspended`, `due`, `repeat`, `blocked`, `subtasks`) atomically from the complete entity winner `W` (where the greater `completions` counter wins under Section 6.7.4). Do not combine individual occurrence fields or prerequisite thresholds from different occurrences. Post-merge open-task block cleanup (Section 6.7.8 Point 3) still applies if the winning occurrence is open (`finished` omitted).
- **Case 2 — Same-Occurrence Concurrent Edit (`B.completions == L.completions == R.completions` and `finished` is omitted in `B`, `L`, and `R`):**
  Merge each operational unit independently using the three-way baseline `B`, complete entity winner `W`, and UTC evaluation instant `now`:
  - `priority`: Independent boolean scalar unit.
  - `suspended` (**Expiry Pre-Normalization + Atomic `(isForever, utcComponents, optionalNote)` Unit**): Before comparing `(B.suspended, L.suspended, R.suspended)` at `now`, pre-normalize any variant $V \in \{B, L, R\}$ whose `V.suspended` is a finite UTC timestamp $\le \text{now}$ to `absent`, then apply the three-way scalar rule using `W` on conflict. Pre-normalizing finite `suspended <= now` to `absent` ensures that an offline refresh cleanup on one side matches normalized `B` (allowing a concurrent future deferral extension on the opposing side to win commutatively regardless of `modified` timestamps) while preventing an opposing side that edited unrelated fields from resurrecting an expired deferral.
  - `due`: Independent atomic `(utcComponents, passive, optionalNote)` unit.
  - `repeat`: Independent atomic `(count, unit, localClock, leadDays)` unit.
  - `blocked` (**`V.repeat`-Aware Pre-Normalization + Key-Value Map Merge by `targetId`**): On open task $D$, before per-target three-way scalar reconciliation of `(B.blocked, L.blocked, R.blocked)`, pre-normalize each variant $V \in \{B, L, R\}$'s dependency map $M_V$ to $M'_V$ using **$V.\text{repeat}$** against `(mergedTasksById, mergedDeletedTasks)`: map $M_V(\text{id}) = \text{req}$ to `absent` whenever $\text{id} \in \text{mergedDeletedTasks}$ OR ($\text{id} \in \text{mergedTasksById}$ with $T_{\text{target}} = \text{mergedTasksById}[\text{id}]$, $T_{\text{target}}.\text{completions} \ge \text{req}$, AND ($V.\text{repeat}$ is omitted OR $T_{\text{target}}.\text{repeat}$ is omitted)). Resolve each `targetId` in $\text{dom}(M'_B) \cup \text{dom}(M'_L) \cup \text{dom}(M'_R)$ independently:
    1. If $M'_L(\text{id}) = M'_R(\text{id})$, keep $M'_L(\text{id})$.
    2. Else if $M'_L(\text{id}) = M'_B(\text{id})$, keep $M'_R(\text{id})$ (preserving concurrent threshold raises such as `A:2` and newly added recurring pipelines where $V.\text{repeat}$ became present).
    3. Else if $M'_R(\text{id}) = M'_B(\text{id})$, keep $M'_L(\text{id})$.
    4. Else (both `L` and `R` changed `targetId` to different non-resolved states), keep $M'_W(\text{id})$.
    Then apply post-merge open-task block cleanup using merged **$D_M.\text{repeat}$** (Section 6.7.8 Point 3), and validate the resulting dependency graph across the complete merged document for `CircularDependency` and `MAX_ARGS_PER_STMT = 64` (Section 6.7.7).
  - `subtasks` (**Step-Wise Boolean Merge on Matching Step Texts**):
    - When `B.subtasks`, `L.subtasks`, and `R.subtasks` are all present and have the exact same ordered sequence of decoded step `<text>` strings $[s_1, \dots, s_m]$, merge the `auto-finish` header flag and each step $i$'s `<bool>` completion flag ($i \in 1..m$) independently via the three-way scalar rule using `W` on conflict.
    - Otherwise (if `subtasks` was added, removed, reordered, or had step `<text>` edited on either side), merge the complete `subtasks` block as one atomic unit via the three-way rule using `W` on conflict.
    - Synchronization MUST NOT independently trigger task completion or recurrence even if all merged steps become `true` on a `subtasks auto-finish` block.

Merge shared queue membership and order separately under Section 6.11.
Section 6.9.5 guards completion history against regression.

#### 6.7.6 Revision of the Result

Let $\mathcal{I} = \{B, L, R\}$ when common baseline `B` is present, or $\mathcal{I} = \{L, R\}$ when `B` is absent, and let $G$ be the greatest raw input version in $\mathcal{I}$ under Section 6.7.4 (or complete winner $W$ when `B` is absent).
For `label` and `location` entities, compare the final post-cascade payload against $G$'s raw payload: if equal, preserve $G$'s existing `modified` value (including omission); otherwise set $\text{modified} = \max_{X \in \mathcal{I}}(X.\text{effectiveModifiedAt}) + 1\text{ second}$.

For `task` entities, let $M_{\text{uncleaned}}$ be the merged task payload produced after Section 6.7.5 reconciliation (including baseline-free two-way `history` union when `B` is absent) and Section 6.7.8 Points 1–2 `label`/`location` deletion cascades **without** Case 2 `suspended <= now` or `blocked` pre-normalization and **without** Section 6.7.8 Point 3 post-merge open-task block cleanup, and let $M_{\text{clean}}$ be the final post-cleanup task payload after applying Case 2 pre-normalization and Section 6.7.8 Point 3 post-merge open-task block cleanup at UTC evaluation instant `now`:

1. **Idempotent Reuse of Greatest Existing Version:** If $G$'s raw (un-normalized) payload already equals $M_{\text{clean}}$ (or when `B` is absent and complete winner $W$'s raw payload equals $M_{\text{clean}}$), preserve that existing `modified` value unchanged (including an omitted `modified` directive).
2. **Deterministic Clock-Free Merge Revision ($M_{\text{clean}} == M_{\text{uncleaned}}$):** Otherwise, if $M_{\text{clean}}$ equals $M_{\text{uncleaned}}$ (neither Case 2 pre-normalization nor post-merge open-task block cleanup altered the payload, including when a baseline-free two-way `history` union adds entries not present on $W$), set:
   ```text
   modified = max_{X in I}(X.effectiveModifiedAt) + 1 second
   ```
   without reading the current wall clock.
3. **Block-Cleanup Revision ($M_{\text{clean}} \neq M_{\text{uncleaned}}$):** Otherwise (Case 2 `suspended <= now` or `blocked` pre-normalization or Section 6.7.8 Point 3 post-merge open-task block cleanup altered the payload relative to $M_{\text{uncleaned}}$), set:
   ```text
   modified = max(now, max_{X in I}(X.effectiveModifiedAt) + 1 second)
   ```

This rule covers external edits that retained an older revision timestamp and prevents the resulting payload from losing to an unchanged input revision.
Fail with `InvalidTimestamp` if any calculated revision exceeds `9999-12-31 23:59:59` UTC.

For fixed inputs, a fixed baseline, and a fixed `now`, reversing `L` and `R` MUST preserve the payload and revision.
Merging identical already-clean versions MUST NOT advance their revision, and when canonical serialized output already matches the stored snapshot on disk or remote storage, skip redundant write-back.

#### 6.7.7 Complete Result Validation, Guarded Local Publication & Bounded CAS-Merge Loop (`MAX_CAS_RETRIES = 3`)

Validate both input documents before merging.
After merging entities and applying post-merge deletion cascades and open-task block cleanup (Section 6.7.8), reconcile shared queue order under Section 6.11.
Then validate the complete candidate document, including exact queue membership.
Check required fields, value domains, `label` and `location` references (`UnknownLabelReference`, `UnknownLocationReference`), dependency cycles (`CircularDependency`), `MAX_ARGS_PER_STMT = 64` on merged `labels`, `blocked`, and `condition location` directives, `MAX_LOCATION_REFS_PER_ENTITY = 63`, `MAX_LOCATIONS = 200`, `MAX_LINKS_PER_TASK = 20`, `MAX_LINKS_PER_LABEL = 20`, `MAX_HISTORY_PER_TASK = 500`, `MAX_STMTS_PER_BLOCK = 1_024`, `MAX_LINE_COUNT = 16_384`, `MAX_FILE_BYTES = 1_048_576`, and all other Section 7 resource and canonical output bounds.
Individually valid inputs can produce an invalid combined dependency graph or exceed a resource bound (such as `|history| > 500` after set union) when combined.

If validation fails, report the existing validation error code (`LimitExceeded`, `CircularDependency`, etc.) and affected entity IDs.
Preserve both inputs, the active document, and the acknowledged baseline.
Do not publish a partial result or silently truncate `history`, `link`, or reference entries.

**Pre-Write Compare-and-Swap (CAS) Merge Loop (`MAX_CAS_RETRIES = 3`) & Hardened Temp-File Swap:**
Before persisting a mutated or merged candidate `L` to a local `.tdf` path `<target>`, initialize loop-local working state `loopDigest = sourceDigest`, `loopB = B` (`absent` if `<target>` did not exist when `L` was initialized), and `loopL = L`, and execute a bounded loop with `attempt = 0..MAX_CAS_RETRIES`:
1. **Read & Fingerprint Current Disk State:** Read the current byte stream `R_bytes` from `<target>` (resolving the path afresh on every attempt so atomic file replacements by cloud synchronizers such as OneDrive, Nextcloud, or Syncthing are always observed) and compute `diskDigest = SHA256(R_bytes)` (or `diskDigest = absent` if `<target>` does not exist).
2. **Digest Match — Hardened Atomic Temp-File Publication:** If `diskDigest == loopDigest` (including when both are `absent` on initial file creation), serialize `loopL` into `out_bytes` in canonical order (Section 7.1) and validate canonical output bounds. Create a dot-prefixed temporary file `.<target_basename>.tmp.<csprng_hex>` in the same directory using a $\ge 128$-bit (32-hex-character) cryptographically secure random suffix (CSPRNG), **exclusive creation flags** (`O_CREAT | O_EXCL | O_WRONLY` on POSIX, `CREATE_NEW` on Windows, never following existing symlinks), and restrictive owner-only file permissions (`0600` on POSIX). Write `out_bytes`, flush (`fsync`), atomically rename over `<target>`, and **only after the atomic rename succeeds** commit `sourceDigest = SHA256(out_bytes)`, set durable baseline `B = loopL`, and return success. If writing, flushing, or atomic rename fails (such as a transient file-sharing lock), unconditionally delete (`unlink`) `.<target_basename>.tmp.<csprng_hex>` before propagating the failure, leaving the caller's pre-loop `sourceDigest`, `B`, and `L` untouched.
3. **Digest Mismatch — Automatic Three-Way Reload & Merge Retry:** If `diskDigest != loopDigest` and `attempt < MAX_CAS_RETRIES`:
   - Parse `R_bytes` as incoming document `R` (if `<target>` was deleted externally while `loopDigest` was present, handle `<target>` absence under Section 6.8.4 recovery rules).
   - Execute the full reconciliation `M = merge(loopB, loopL, R)` under Sections 6.7 through 6.11 (if `loopB` is `absent` because `<target>` was created externally after initialization, reconcile without a common baseline under Sections 6.7.8 and 6.8.4) and validate `M`.
   - Update loop-local state `loopDigest = diskDigest`, `loopB = R`, and `loopL = M`, increment `attempt`, and repeat from Step 1 without mutating the caller's durable `sourceDigest` or `B`.
4. **Contention Exhaustion or Conflict Abort:** If contention persists after `MAX_CAS_RETRIES` attempts (`attempt == MAX_CAS_RETRIES` and `diskDigest != loopDigest`), or if parsing or reconciliation yields `DeletionConflict`, `RecoveryRequired`, `SyncGenerationRollback`, or a schema validation error, abort the write without modifying `<target>`, preserve the caller's pre-loop `sourceDigest`, `B`, and `L` unchanged, and report the outcome to the caller.

**Prohibition of Sync-Folder `.tdf.lock` Artifacts:**
Conforming implementations MUST NOT create persistent or advisory `.tdf.lock` files inside the synchronized workspace directory, because cloud sync daemons replicate lock files across devices and create stale ghost locks. Any optional local inter-process lock MUST use OS-native file-descriptor advisory locking or reside in the local OS runtime temporary directory outside the synchronized folder.

#### 6.7.8 Entity Presence, Deletion History, Post-Merge Cascades, and Open-Task Block Cleanup

Evaluate deletion records, deletion history generations, and `DeletionConflict` rules (including newly introduced `labels` and `condition location` references targeting deleted entities) under Section 6.8 before merging live entities.
Apply field merging when both variants contain a live entity and a common baseline is available (and apply baseline-free `history` set union on tasks present on both sides when `B` is absent under Section 6.7.5 Point 4).
Without that baseline, use the complete entity winner for all other units of entities present on both sides.

A known baseline may identify a locally unchanged cached entity (`task`, `label`, or `location`) that is now absent from the shared document.
Remove that cached copy instead of treating it as a new entity.

Preserve a local-only addition automatically only within a compatible, acknowledged deletion history generation.
Section 6.8.4 governs missing or outdated generation acknowledgments.
Keep ambiguous local entities for explicit recovery.
Do not interpret entity deletion as clearing every merge unit.

**Post-Merge Deletion Cascades and Open-Task Block Cleanup:**
Apply the following deterministic post-merge steps before final revision assignment (Section 6.7.6) and queue normalization (Section 6.11.2):
1. **Non-Conflicting `label` Deletion & Global-View Flood Protection (`scoped` Labels):**
   - For each live task $T$, let $L_{\text{before}}(T)$ be $T$'s merged label set computed prior to stripping labels tombstoned in the merged `deleted` block (so a label already stripped from $T$ on the deleting side as part of the label deletion is included in $L_{\text{before}}(T)$, with $\text{isScoped}(l)$ taken from the merged live `label` block for surviving labels and from the surviving side or `B` for tombstoned labels), and let $L_{\text{after}}(T) = L_{\text{before}}(T) \setminus \text{DeletedLabels}$ be $T$'s label set after removing tombstoned labels.
   - Replace $T$'s `labels` set with $L_{\text{after}}(T)$ (omitting `labels` if empty).
   - If $T$ was restricted from the global view prior to removing the deleted label(s) ($L_{\text{before}}(T) \neq \varnothing \land \forall l \in L_{\text{before}}(T),\; \text{isScoped}(l)$), and removing the tombstoned label(s) leaves $T$ with **zero labels** ($L_{\text{after}}(T) = \varnothing$), **strip `priority` from $T$ if present, preserve `suspended` (with its note), `(due, passive, due-note)`, `origin`, and `history` unchanged, and mark $T$ for removal from the merged `queue` during Section 6.11.2** so unscheduled tasks from a deleted `scoped` list do not flood the global `Focus` and `Ready` tiers as unlabeled tasks.
   - Compute `T.modified` and `queue.modified` via Sections 6.7.6 and 6.11.2.
2. **Non-Conflicting `location` Deletion in Strict `label`-Before-`task` Order & Task `location any` Inheritance-Trap Protection:**
   - **First on all live `label` blocks:** Strip every non-conflicting tombstoned `<location-id>` from `B.condition`, `L.condition`, and `R.condition` before merging each live `label`'s `condition` model (Section 6.7.5 Point 2); if zero `<location-id>` tokens remain in a variant's `locationGroup`, set that `locationGroup` to empty (and omit `condition` on the merged `label` if zero rules remain across all groups).
   - **Second on all live `task` blocks (Evaluated Against Post-Cascade Labels and $L_{\text{after}}(T)$):** When stripping non-conflicting tombstoned `<location-id>` tokens from `B.condition`, `L.condition`, and `R.condition` (or from `L.condition` and `R.condition` when `B` is absent) under Section 6.7.5 Point 2, retain the remaining live `<location-id>` tokens in any variant where $\ge 1$ live tokens remain. Whenever stripping non-conflicting tombstoned `<location-id>` tokens empties a variant $V \in \{B, L, R\}$'s `<location-id>` list ($V.\text{locationGroup}$ had $\ge 1$ `<location-id>` tokens that were all tombstoned in the merged `deleted` block), convert $V.\text{locationGroup}$ directly into its cascade target state before three-way (or two-way) comparison:
     - **If at least one live `label` in the task's post-merge `labels` set ($L_{\text{after}}(T)$) defines a non-empty post-cascade `location` rule group:** Convert the emptied `locationGroup` in $V$ to **`location any` (`condition location any`)** so a task whose location override was deleted does not silently snap into an inherited label location restriction, while an explicit user removal of the task's `location` rule on the opposing side (`locationGroup` cleared to empty) differs from `B`'s cascade target (`location any`) and wins cleanly in the three-way merge.
     - **Otherwise (no assigned live label in $L_{\text{after}}(T)$ defines a non-empty post-cascade `location` rule):** Convert the emptied `locationGroup` in $V$ to the **empty `locationGroup`** (normalizing any cascade-inserted `location any` on a side where all `B.locationGroup` tokens were tombstoned to empty as well, and omitting `condition` on the merged task if zero rules remain across all groups).
   - Compute `modified` on each affected `label` and `task` via Section 6.7.6.
3. **Post-Merge Open-Task Block-Reason Cleanup & Multi-Stage Synchronization Fairness:**
   - On every surviving open task $D_M$ (`finished` omitted), strip any remaining finite `suspended <= now` (together with its note) and strip any `blocked <target-id>[:<req>]` entry where `<target-id>` is non-conflictingly tombstoned in merged `deleted` tasks or where `<target-id>` is a surviving live task $T_{\text{target}}$ with $T_{\text{target}}.\text{completions} \ge \text{req}$ and ($D_M.\text{repeat}$ is omitted OR $T_{\text{target}}.\text{repeat}$ is omitted), assigning `D_M.modified` under Section 6.7.6.
   - **Multi-Stage Synchronization Fairness:** When a client synchronizes through an intermediate local cache/file stage before reconciling with a remote server stage, defer post-merge open-task block cleanup during the intermediate local stage until remote reconciliation completes — and when scoping a queued local mutation against its origin snapshot, preserve pre-cleanup revisions on untouched open bystander tasks whose cleanup-normalized payloads equal the origin snapshot — so automatic local block-reason cleanup never inflates `task.modified` ahead of concurrent remote edits before selecting complete winner `W`.

#### 6.7.9 Merge Verification Cases

These scalar cases use one task with a shared identity, creation timestamp, and zero completion counter.
The baseline has `name = N0`, `note = Q0`, and `modified = T10`.
Unspecified payload values equal the baseline.
`Tn` means `2026-11-04 12:00:00` UTC plus `n` seconds.

| Case | Local version | Incoming version | Result | Revision |
| --- | --- | --- | --- | --- |
| Independent edits | `name = N1`, `T11` | `note = Q1`, `T12` | `name = N1`, `note = Q1` | `T13` |
| Matching edits | `name = N1`, `T11` | `name = N1`, `T12` | `name = N1`, `note = Q0` | `T12` |
| Same field conflict | `name = N1`, `T11` | `name = N2`, `T12` | `name = N2`, `note = Q0` | `T12` |
| Equal timestamp conflict | `name = Alpha`, `T12` | `name = Zulu`, `T12` | `name = Zulu`, `note = Q0` | `T12` |
| Conflict and independent edit | `name = N1`, `note = Alpha`, `T11` | `note = Zulu`, `T12` | `name = N1`, `note = Zulu` | `T13` |
| Unstamped external edit | Unchanged payload, `T20` | `name = N1`, `T10` | `name = N1`, `note = Q0` | `T21` |

Repeat every case with the input directions reversed.
Without a known common baseline, the independent-edits case MUST retain the complete version at `T12` (while unioning `history` entries if both sides carry distinct `history` entries).

Verify these additional cases:

- Combine independent label additions and removals according to Section 6.7.5, and merge `label` `scoped`, `color`, and complete ordered `label.link` list independently.
- Merge `origin` (`(namespace, externalKey)` or `absent`) as one atomic scalar pair unit without mixing `namespace` from one side and `externalKey` from the other side.
- Merge `suspended` (`(isForever, utcComponents, optionalNote)` or `absent`), `due` (`(utcComponents, passive, optionalNote)` or `absent`), and `repeat` (`(count, unit, localClock, leadDays)` or `absent`) as atomic units without mixing an old note or `passive` flag with an opposing timestamp.
- Pre-normalize finite `suspended <= now` to `absent` in Case 2 so an offline refresh cleanup on one side (`modified = 12:00:01`) never overwrites a concurrent future deferral extension (`2026-11-12 09:00`, `modified = 11:30:00`) on the other side, and an unrelated `note` edit on the other side never resurrects an expired deferral.
- Pre-normalize `blocked` in Case 2 using each variant's `V.repeat` against `(mergedTasksById, mergedDeletedTasks)` before per-`targetId` reconciliation so completing one-shot `A` (`completions = 1`) on one side neither wipes out a concurrent threshold raise (`blocked A:2`) nor strips a newly configured recurring pipeline (`D.repeat` added while `A.repeat` is present) on the opposing side.
- Reconcile `history` as an occurrence-independent `(timestampUtc, text)` set across both Case 1 (such as completing a `repeat` occurrence or setting `finished` on `L` while adding, editing, or deleting a `history` entry on `R`) and Case 2, and union `history` sets in baseline-free two-way merges (`T` in both `L` and `R` without `B`, advancing `modified` to `max(L, R) + 1 second` when the union adds entries beyond `W`).
- Defer post-merge open-task block cleanup across intermediate local stages in multi-stage local-plus-remote synchronization so local cleanup never inflates `task.modified` ahead of remote edits when selecting `W`.
- Merge `location` `(coordinates, source)` as one coupled geographic reference unit while merging `name`, `note`, and `radius` independently.
- Strip non-conflicting tombstoned `<location-id>` tokens from `B.condition`, `L.condition`, and `R.condition` in strict `label`-before-`task` order (converting any task `locationGroup` emptied by removing tombstoned tokens directly into its cascade target state: `location any` when a post-merge live label defines a non-empty post-cascade `location` rule, or empty otherwise) before comparing conditions, and merge `dayGroup`, `timeGroup`, and `locationGroup` independently when `globalAny == false` in all three (using the commutative `W`-anchored ordered-list merge for `locationGroup`).
- Unbundle `priority`, `suspended`, `due`, `repeat`, `blocked` (per-`targetId` map merge), and `subtasks` (step-wise boolean merge when step text sequences match) when `B.completions == L.completions == R.completions` and `finished` is omitted in all three.
- Copy the complete winning task occurrence state atomically when `completions` differs among `B`, `L`, `R` or `finished` is present in at least one of `B`, `L`, `R` (while still merging occurrence-independent metadata including `history`).
- Preserve revisions when merging the same already-clean result again.
- Produce identical results for equivalent quoting, escaping, and condition syntax.
- Compare Unicode strings by UTF-8 byte order, including characters outside the Basic Multilingual Plane.
- Reject a merged dependency cycle even when both inputs are acyclic.
- Reject merged documents that exceed resource bounds (`MAX_ARGS_PER_STMT`, `MAX_LOCATION_REFS_PER_ENTITY`, `MAX_LOCATIONS`, `MAX_LINKS_PER_TASK`, `MAX_LINKS_PER_LABEL`, `MAX_HISTORY_PER_TASK`, `MAX_STMTS_PER_BLOCK`, `MAX_FILE_BYTES`, `MAX_LINE_COUNT`) with `LimitExceeded` without silent truncation.
- Preserve inputs and baseline after validation or publication failure.

### 6.8 Deletion Records, Retention, and Cleanup

Deletion records are synchronization metadata and do not enter any operational tier.
All retention calculations use one captured UTC reference time for the operation.
Thirty days means `2_592_000` seconds.

#### 6.8.1 Creating a Deletion Record

Deleting a live `task`, `label`, or `location` removes its block and creates the corresponding record in `deleted`.
Set its deletion revision using the ordinary mutation rule in Section 6.7.1.
For a task, copy its completion counter into the record when positive.
Remove a deleted task's queue entry in the same transaction and advance the queue revision when changed.
Create the `deleted` block with generation `0` if it does not exist.
Adding a deletion record MUST NOT increment the generation.

**Deleting a `label` & Global-View Flood Protection (`scoped` Labels):**
Deleting a `label` MUST remove its `<label-id>` from all live tasks in the same transaction:
- For each affected task $T$, let $L_{\text{before}}(T)$ be $T$'s assigned label set immediately prior to removing the deleted `<label-id>`, and let $L_{\text{after}}(T)$ be $T$'s label set after removing it.
- Omit `labels` on $T$ when $L_{\text{after}}(T) = \varnothing$.
- If $T$ was restricted from the global view prior to the deletion ($L_{\text{before}}(T) \neq \varnothing \land \forall l \in L_{\text{before}}(T),\; \text{isScoped}(l)$), and removing the deleted `scoped` label leaves $T$ with **zero labels** ($L_{\text{after}}(T) = \varnothing$), and $T$ is listed in `queue`, **remove $T$'s task ID from `queue` and strip `priority` if present in the same atomic transaction while preserving `suspended` (with its note), `(due, passive, due-note)`, `origin`, and `history`** (advancing `queue.modified` under Section 6.11.1).
- Advance each affected task's `modified` timestamp under Section 6.7.1.

**Deleting a `location` in Strict `label`-Before-`task` Order & Override-Preserving Cascade (`location any`):**
Deleting a `location` MUST remove its `<location-id>` from all live `label` and `task` `condition` models in the same transaction in **strict `label`-before-`task` order**:
1. **First on all `label` blocks:** Remove the deleted `<location-id>` from each live `label`'s `location` condition rule; if zero `<location-id>` tokens remain on a `label`, remove its `location` rule (and omit `condition` if zero rules remain across all groups), advancing `label.modified` under Section 6.7.1.
2. **Second on all `task` blocks (Evaluated Against Post-Cascade Labels):** Remove the deleted `<location-id>` from each live `task`'s `location` condition rule:
   - If other live `<location-id>` tokens remain on the task, retain the rule with the remaining tokens.
   - If removing the deleted `<location-id>` leaves the task's `location` group empty **and at least one live `label` in the task's `labels` set still defines a non-empty post-cascade `location` rule group**, replace the task's emptied `location` rule with **`location any` (`condition location any`)** in the same atomic transaction so the task does not silently inherit the label's location restriction.
   - Otherwise (if no assigned live label defines a non-empty post-cascade `location` rule), remove the emptied `location` rule from the task (omitting `condition` if zero rules remain across all groups).
   - Advance each affected task's `modified` timestamp under Section 6.7.1.

**Immediate Prerequisite Cleanup on Open Tasks When Deleting a `task`:**
Deleting a `task <id>` MUST immediately remove any `blocked <id>[:<req>]` prerequisite reference targeting `<id>` from all live **open** tasks (`finished` omitted) in the same atomic transaction (omitting `blocked` on any affected open task whose remaining prerequisite set becomes empty, and advancing each affected open task's `modified` timestamp once under Section 6.7.1 alongside open-task block-reason cleanup under Section 6.6). Any legacy `blocked <id>[:<req>]` reference remaining on a `Completed` task (`finished` present) is retired upon 30-day tombstone expiry under Section 6.8.3.

Task `history` entries are never individually tombstoned; `history` is removed as a whole only when its enclosing `task` block is explicitly deleted or pruned after its 30-day `Completed` retention period.

Pruning a completed task after its retention period MUST create a deletion record through this same operation.
Use the current deletion revision, not the task's old `finished` timestamp.
The deletion record then receives its own 30-day retention period.

Within a compatible generation, a proven baseline can identify an external `task`, `label`, or `location` deletion without an existing record.
Create its record during reconciliation, using the detection time and previous effective revision.
Apply the mutation rule from Section 6.7.1.
Parsing alone MUST NOT create or persist this record.
Do not recreate expired records after a generation change.

Repeated synchronization of an existing deletion MUST preserve its timestamp.
Do not restart retention because another client reports the same deletion.
Do not assign a deleted entity ID to a new entity.
Explicit Undelete preserves the existing identity under Section 6.8.2.

#### 6.8.2 Combining Deletion Records & `DeletionConflict` Resolution

Within the same deletion history generation, combine record sets by namespace (`task`, `label`, `location`) and ID.
For matching records, keep the later deletion revision.
For task records, independently keep the greatest completion checkpoint.
Equal deletion revisions refer to the same deletion.
Merging checkpoints MUST NOT restart retention.

Reconcile different or unknown generations under Section 6.8.4 before combining records.
Do not reintroduce records already contained in an older acknowledged baseline.
Preserve unacknowledged local deletion intents for reconciliation.

**Normative `DeletionConflict` Classification (Direct Entity Edits, Baseline-Cleanup Hygiene, and Newly Introduced References):**
For every live or `DeletionConflict`-retained task $T$ on side $X \in \{L, R\}$ during three-way merge, define the set of newly introduced label references on side $X$ as:
$$A_X(T) = \begin{cases} T_X.\text{labels} \setminus T_B.\text{labels} & \text{if } T \in B \\ T_X.\text{labels} & \text{if } T \notin B \text{ (newly created on side } X\text{)} \end{cases}$$
Analogously, for every live or `DeletionConflict`-retained entity $E \in \text{Tasks} \cup \text{Labels}$ on side $X \in \{L, R\}$, let $\text{locRefs}(E)$ be the set of `<location-id>` tokens referenced across $E$'s `condition` rules, and define the set of newly introduced location references on side $X$ (evaluated on the input entities $E_L, E_R$ before `condition` winner selection or deletion cascades) as:
$$A^{\text{loc}}_X(E) = \begin{cases} \text{locRefs}(E_X) \setminus \text{locRefs}(E_B) & \text{if } E \in B \\ \text{locRefs}(E_X) & \text{if } E \notin B \text{ (newly created on side } X\text{)} \end{cases}$$
A recorded deletion resolves an unchanged cached live copy without a conflict only when neither its own payload changed nor a new reference to it was introduced. Classify an entity (`task`, `label`, or `location`) as a **`DeletionConflict`** — retaining the live entity block alongside the opposing side's deletion record and requiring an explicit `Delete` or `Undelete` decision — whenever **either** of the following holds:
1. **Direct Entity Payload Edit vs. Deletion (With Open-Task Baseline-Cleanup Normalization):** The live `task`, `label`, or `location` block's own normalized payload (Section 6.7.3) changed relative to `B` on one side while the opposing side contains a deletion record in `deleted` (or no proven baseline `B` is available). When both $T_X$ and $T_B$ are open tasks (`finished` omitted), compare $T_X$ and $T_B$ **after normalizing both snapshots at UTC evaluation instant `now`** by stripping finite `suspended <= now` (with its note) and stripping `blocked` entries resolved by non-conflicting tombstones in the combined `deleted` task set or by surviving live prerequisites ($T_{\text{target}}.\text{completions} \ge \text{req}$ with $T.\text{repeat}$ or $T_{\text{target}}.\text{repeat}$ omitted), ignoring a `modified` advance caused solely by automatic block-reason cleanup (and apply the same cleanup normalization when testing retired entities against an origin snapshot for queued local mutations). Automatic block-reason cleanup alone therefore never causes a false `DeletionConflict`, whereas any user edit to `history` or any other non-cleaned task field triggers `DeletionConflict`.
2. **Newly Introduced Reference vs. Deletion:** Any live or `DeletionConflict`-retained task $T$ on side $X \in \{L, R\}$ introduces a label ID $l \in A_X(T)$ while `label` $l$ has a deletion record in `deleted` on the opposing side, or any live or `DeletionConflict`-retained `task` or `label` $E$ on side $X \in \{L, R\}$ introduces a location ID $\text{loc} \in A^{\text{loc}}_X(E)$ while `location` $\text{loc}$ has a deletion record in `deleted` on the opposing side (even when that `label` or `location`'s own payload was unchanged relative to `B`).

Revision timestamps and input direction MUST NOT choose between deletion and a conflicting edit or reference.
Preserve the live version, deletion record, referencing entities, and baseline until the decision is successfully published.
Present the deletion and live content together and provide these two outcomes:

| User decision | Result |
| --- | --- |
| Delete | Remove the live entity, retain its deletion record with `decisionRevision`, and execute the Section 6.8.1 deletion cascade. |
| Undelete | Restore the live entity with its original namespace and ID (`modified = decisionRevision`), remove its deletion record, advance `deleted.generation` once, and preserve all references. |

An explicit decision creates one new revision.
For tasks, preserve the greatest completion counter known from the live version, baseline, and deletion checkpoint.
Store that counter in the confirmed deletion record or undeleted task.
Preserve other selected task state (including `history`) during Undelete.
Observe the live, deletion, and available baseline revisions:

```text
decisionRevision = max(now, eachObservedRevision + 1 second)
```

- **For `Delete`:** Use `decisionRevision` in the deletion record and start its 30-day retention period from there. When confirming `Delete` on a `task`, remove its queue entry and strip `blocked <id>[:<req>]` references targeting it from all live open tasks in the same transaction under Section 6.8.1. When confirming `Delete` on a `label`, remove its `<label-id>` from all tasks and apply the `scoped` global-view flood-protection rule from Section 6.8.1 (removing affected global-view-restricted tasks that lose their last label from `queue` and stripping `priority` while preserving `suspended` with its note, `(due, passive, due-note)`, `origin`, and `history`). When confirming `Delete` on a `location`, remove its `<location-id>` from all `label` and `task` `condition` rules in strict `label`-before-`task` order under Section 6.8.1 (replacing an emptied task `location` override with `location any` when an assigned live label still defines a non-empty post-cascade `location` rule). Advance `modified` on all affected entities. Confirming `Delete` does not remove a deletion record and MUST NOT increment `deleted.generation`.
- **For `Undelete`:** Restore the live `task`, `label`, or `location` block with `modified = decisionRevision` (preserving the greatest known completion counter and `history` on tasks), remove its record from `deleted`, and increment `deleted.generation` once under Section 6.8.3 (preserving the nonzero generation even if this removes the last record). Include a restored open task (`finished` absent) in `queue` at its position from the surviving live variant's `queue` block (or reconciled under Section 6.11.2, advancing `queue.modified` under Section 6.11.1 if `queue` changes, unless evicted to `Someday` by a concurrent `scoped` label deletion under Section 6.8.1) if and only if its `<task-id>` was present in the surviving live variant's `queue` block; otherwise (when its `<task-id>` was absent from the surviving live variant's `queue` block, or when `finished` is present), the restored task remains outside `queue` (`Someday` or `Completed`). Preserve all `labels` and `condition location` references on tasks and labels.

Bind the decision to the exact live payload, live revision, and deletion revision presented.
If those versions change before publication, reevaluate the conflict and request a new decision.
Unrelated source changes require recalculation under guarded publication.
Revalidate the complete candidate before publication.
A failed publication MUST preserve the conflict and both versions.

#### 6.8.3 Thirty-Day Cleanup, Prerequisite Expiry Hygiene, and Publication

A deletion record (`task`, `label`, or `location`) expires only when `now - deletionRevision > 2_592_000 seconds`.
Keep a record at exactly 30 days.
Keep records whose timestamps lie in the future.

Calculate cleanup against the current shared source snapshot:
- Remove expired `task`, `label`, and `location` deletion records and increment `deleted.generation` once when at least one record is removed.
- **Prerequisite Reference Hygiene on 30-Day `task` Tombstone Expiry:** Open tasks already strip `blocked <id>[:<req>]` references targeting confirmed deleted tasks immediately during `deleteTask`, ordinary mutations, and refresh/synchronization (Sections 6.6, 6.7.8, and 6.8.1). In addition, whenever a `task <id> <ts> [<checkpoint>]` deletion record is retired after $> 30$ days (`now - ts > 2_592_000` seconds) during a guarded cleanup transaction, **remove any remaining `blocked` prerequisite reference `<id>[:<req>]` targeting that expiring `<id>` on any live task (including legacy `Completed` tasks) in the same guarded cleanup transaction** (omitting `blocked` if no dependencies remain on that live task and advancing each affected live task's `modified` timestamp under Section 6.7.1) regardless of `<checkpoint>`. Because any `<id>` present in `deleted` is a confirmed deleted task (never a forward reference) and can never be reused after 30-day expiry (Sections 6.8.1 and 6.8.4), retiring `<id>[:<req>]` upon 30-day tombstone expiry guarantees that zero dangling references survive tombstone retirement while keeping missing forward references (which have no record in `deleted`) untouched.
- Removing several records in one cleanup still increments `deleted.generation` only once.
- A cleanup-only operation without removals MUST preserve the generation.
- Explicit Undelete also retires a deletion record and MUST increment the generation.
- A transaction combining cleanup and Undelete increments the generation only once.
- Confirming Delete alone does not remove a record and MUST NOT increment the generation.

Publish record retirement, prerequisite reference cleanup, the resulting live entities, and the new generation atomically through guarded persistence (Section 6.7.7).
Use the shared source generation, not an independently incremented offline value.
If the source changed, reload it and recalculate the complete operation.
A failed publication MUST preserve the previous records, generation, active document, and acknowledged baseline.

Without a remote backend, a successful guarded update of the authoritative local file is publication.
Loading or importing a document MUST NOT perform this cleanup.
An offline cached copy MUST NOT independently discard records.

Preserve a nonzero generation even when no records remain.
Fail with `LimitExceeded` instead of wrapping a generation beyond `MAX_SYNC_GENERATION`.
Do not remove unexpired records to satisfy a resource bound.

#### 6.8.4 Generation Checks and Recovery

Store the last acknowledged generation alongside the durable baseline.
An initial publication to a new shared file establishes its first acknowledged generation.

Before publishing local changes, read the complete current shared document.
If its generation matches the acknowledged generation, use the normal merge rules.
If its generation increased, refresh the shared snapshot before reconciling local changes.

During that reconciliation:

1. Merge edits to entities (`task`, `label`, `location`) still present on both sides using the proven common baseline, when available.
2. Otherwise, select the complete winner for entities still present on both sides (unioning `history` on tasks under Section 6.7.5 Point 4).
3. Discard unchanged cached entities (`task`, `label`, `location`) that are absent from the shared snapshot (comparing open cached tasks against `B` after applying the Section 6.8.2 open-task baseline-cleanup normalization at `now` so automatic `suspended <= now` or resolved `blocked` cleanup never triggers a false `RecoveryRequired`).
4. Preserve changed local entities (`task`, `label`, `location`) that are absent remotely as recovery items (`ambiguousTaskIds`, `ambiguousLabelIds`, `ambiguousLocationIds`, including any open task whose `history` or other non-cleaned field changed relative to `B`).
5. Preserve local-only entities (`task`, `label`, `location`) absent from the baseline as recovery items.
6. Preserve unacknowledged deletion intents for reconciliation.
7. Start from the current shared generation and apply any retirement increment required by Section 6.8.3.

Whenever cached or local-only tasks absent remotely are discarded/retired rather than recovered (in Step 3, during explicit recovery discard, or when rebasing queued local mutations onto a newer generation), strip any `blocked` prerequisite entries targeting those discarded task IDs from all surviving live open tasks (advancing `modified` when changed) so retired tasks whose tombstones already expired are never retained as false forward references.

A newer generation may reflect expired records or an explicit Undelete.
Discard old acknowledged records before merging the refreshed shared state.
Preserve unacknowledged deletion intents for reconciliation.

Unknown generation acknowledgments require the same refresh and recovery procedure.
Absence alone does not distinguish an unpublished addition from a deletion whose record has expired.
Return `RecoveryRequired` for ambiguous `task`, `label`, or `location` entities.
Keep local changes and the previous baseline until reconciliation succeeds.
Do not publish ambiguous entities automatically or acknowledge an incomplete recovery.

Known conflicts with retained deletion records use Delete or Undelete under Section 6.8.2.
Explicitly recovering a missing `task`, `label`, or `location` entity as new after history expiry MUST generate a new 10-character Base62 ID under Section 2.9 and rewrite `labels`, `blocked`, and `condition location` references between recovered entities through their new identity mapping (preserving `history` on recovered tasks).
Validate the complete candidate before publication.

If the shared generation is lower than the acknowledged generation, return `SyncGenerationRollback`.
Preserve both documents for explicit recovery.
Do not silently lower the acknowledged generation or overwrite the shared document.

#### 6.8.5 Verification Cases

| Case | Expected result |
| --- | --- |
| Live task is deleted | Create its deletion record, remove its `queue` entry, and immediately strip `blocked <id>[:<req>]` targeting it from all live open tasks (advancing their `modified` timestamps). |
| Record age is exactly 30 days | Keep the record (and any remaining `blocked` references on `Completed` tasks) and the generation. |
| Record age exceeds 30 days | Remove the record during successful cleanup, remove any remaining `blocked <id>[:<req>]` references to an expiring `task <id>` on live tasks (advancing their `modified` timestamps), and increment the generation once. |
| Several expired records are removed | Increment the generation once for the complete cleanup. |
| Cleanup only, no records expire | Preserve the generation. |
| The last record expires | Keep a `deleted` block containing the new nonzero generation. |
| A cleanup write fails | Preserve records, generation, active document, and baseline. |
| A compatible baseline proves an external `task`, `label`, or `location` deletion | Create its record during reconciliation, preserving read-only parsing. |
| A newer generation explains an absent old record | Do not recreate that expired record. |
| The shared source changes before publication | Reload and recalculate via the Section 6.7.7 CAS-merge loop without publishing the stale candidate. |
| A client returns with an older generation | Refresh before reconciling or publishing its local changes. |
| An unchanged cached `task`, `label`, or `location` (or an open task with only automatic `suspended <= now` / resolved `blocked` cleanup) is absent remotely | Discard the stale cached copy without `RecoveryRequired`, and strip `blocked` references to any discarded task IDs from surviving open tasks. |
| An edited or unacknowledged `task` (including a `history` edit), `label`, or `location` is absent remotely | Preserve it for explicit recovery (`RecoveryRequired`). |
| A client has no acknowledged generation | Refresh and reconcile before publishing local-only entities. |
| The shared generation decreases | Return `SyncGenerationRollback` and preserve both versions. |
| Explicit recovery creates a new `task`, `label`, or `location` | Generate a new ID, preserve `history`, rewrite recovered `labels`, `blocked`, and `condition location` references, and strip `blocked` references to non-recovered discarded tasks on surviving open tasks. |
| Deletion conflicts with a changed non-cleanup live payload (including `history`) or a newly added `labels` / `condition location` reference | Return `DeletionConflict` and preserve the live entity block, deletion record, and referencing entities for the user; ignore differences caused solely by automatic open-task block cleanup. |
| The user chooses Delete on a `scoped` label or a `location` | Keep the deletion with `decisionRevision`, evict global-view-restricted tasks left with zero labels from `queue` (preserving `suspended` with its note, `(due, passive, due-note)`, `origin`, and `history`), or cascade `<location-id>` removal in `label`-before-`task` order (inserting `location any` on tasks whose assigned live labels still have a location rule). |
| The user chooses Undelete | Restore the original identity and live payload (`modified = decisionRevision`), remove the record, preserve `queue` membership and position from the surviving live variant when the restored task is open and listed there (or keep it outside `queue` otherwise), preserve `history` and all references, and advance the generation once. |
| Undelete removes the last record | Keep the block with its new nonzero generation. |
| Cleanup and Undelete share one transaction | Advance the generation once. |
| A client returns with an acknowledged record predating Undelete | Refresh and discard that old record. |
| The reviewed conflict changes before publication | Request a new decision for the changed conflict. |
| Publishing a conflict decision fails | Preserve both versions, the active document, and the baseline. |

Also verify strict IDs, UTC timestamps, duplicate records, live-record identity conflicts, and the limits from Section 7.

### 6.9 Completion Occurrences and Prerequisite Requirements

#### 6.9.1 Completion History

Each task has a non-negative `completions` counter.
An omitted counter means `0`.
The counter numbers completed occurrences within the task identity.
It MUST NOT decrease during ordinary mutation, restoration, or synchronization.

An open task's current occurrence follows its recorded completed occurrences.
Every successful completion advances the counter by exactly one.
Concurrent completions of the same occurrence represent one occurrence and MUST NOT be added together.
A task with `finished` MUST have an explicit counter of at least `1`.
Report a finished task with an effective zero counter as `InvalidCompletionState`.

A canonical serializer omits a zero counter and emits every positive counter.
Fail with `LimitExceeded` before a counter would exceed `MAX_COMPLETIONS`.

#### 6.9.2 Stored Prerequisite Requirements

Each `blocked` argument stores a task ID and the completion it requires:

```text
blocked 8jKaCdOkD2 5vWx9ZOk91:8
```

A bare ID requires completion `1`.
The suffix `:<required-completion>` specifies another positive completion number.
Both forms are single unquoted tokens.
The ID component MUST contain exactly 10 Base62 characters.
Validate the suffix as an integer in `1..MAX_COMPLETIONS`.

Canonical serialization omits the suffix for requirement `1`.
For repeated references to one target, retain the greatest required number in the decoded model.
Sort canonical references by ascending ASCII target ID.
An omitted `blocked` directive means no prerequisite requirements.

An existing prerequisite satisfies its requirement when:

```text
prerequisite.completions >= requiredCompletion
```

Missing or deleted prerequisites remain non-blocking.
Missing forward-reference prerequisite IDs (absent from both live `task` blocks and `deleted` task records) MUST NOT be pruned during parsing, loading, mutations, or synchronization.
On **open** tasks (`finished` omitted), `blocked <id>[:<req>]` entries targeting confirmed deleted tasks in `deleted` or satisfied live prerequisites where `prerequisite.completions >= requiredCompletion` and (`dependent.repeat` is omitted OR `prerequisite.repeat` is omitted) are stripped automatically during committed mutations and refresh/synchronization (Sections 6.6, 6.7.8, and 6.8.1).
Live recurring-to-recurring `blocked` pipelines (both `dependent.repeat` and `prerequisite.repeat` present) retain a satisfied `blocked <id>[:<req>]` entry until the recurring dependent completes its occurrence and rearms under Section 6.9.3, and any remaining `blocked` reference on a `Completed` task is retired upon 30-day tombstone expiry under Section 6.8.3.
Resolve existing prerequisites across the complete document, independently of `scoped` labels or active label filters.
Validate dependency cycles using target IDs, including already satisfied references.
Self-dependencies and indirect cycles remain forbidden.

Once a requirement is satisfied, later prerequisite cycles do not undo it.
Queue changes, priority changes, deferral, deadline changes, and condition evaluation MUST NOT rearm the requirement.
Parsing and serialization MUST preserve the stored required number.
A bare ID always means completion `1`, including when the prerequisite already has a larger counter.

#### 6.9.3 Arming and Rearming Requirements

When adding a prerequisite, capture its required number from one consistent document snapshot:

- For an existing open prerequisite, use its current counter plus one.
- For an existing finished prerequisite, use its current positive counter.
- For a missing prerequisite, use `1` unless retaining an existing stored requirement.

Retain requirements for unchanged target IDs when editing the dependency list.
Removing and later adding a target creates a new requirement.
Removing a dependency removes its stored requirement.

Completing a recurring dependent creates its next occurrence.
Rearm its retained prerequisites using the same capture rules in that completion transaction.
A prerequisite completed during the new occurrence's deferral can satisfy that occurrence.
Restoring a finished dependent also creates a new occurrence and rearms its prerequisites.
Changing the repeat interval alone MUST preserve current requirements and completion history.

A finished standard prerequisite remains sufficient without being reopened for every dependent occurrence (and is stripped from open dependents once satisfied under Section 6.6).
Retain a missing prerequisite's existing number during rearming.
If a required increment exceeds `MAX_COMPLETIONS`, reject the complete mutation without partial changes.

#### 6.9.4 Atomic Completion

A completion command MUST identify the expected current completion counter.
An unequal expected counter MUST leave the task unchanged.
If that counter already advanced, a retry MUST NOT complete another occurrence.
A finished task ignores another completion command until explicitly restored.

For a standard task, increment the counter, set `finished`, clear `suspended` (with its note) and `blocked`, preserve `(due, passive, due-note)`, `origin`, and `history`, and complete its checklist in one mutation.
For a recurring task, increment the counter, clear any `suspended` note, preserve `origin` and `history`, and apply the reschedule from Sections 6.4 and 6.10.3 in one mutation.
That recurring mutation also captures the next occurrence's prerequisite requirements.
Advance `modified` once for the completed task and strip any newly satisfied non-recurring-to-recurring `blocked` entries (and expired finite `suspended <= now` deferrals) on open tasks in the same transaction under Section 6.6.
Apply queue membership changes from Section 6.4 in the same transaction.
Reevaluate dependents against the new counter after successful persistence.

Explicit completion and checklist `auto-finish` use this same operation.
Applying checklist completion or reset MUST NOT recursively trigger another completion.
A separate deliberate command may complete the next open occurrence, including while it is deferred.

#### 6.9.5 Synchronization and Deletion Checkpoints

When `completions` differs among `B`, `L`, and `R` or `finished` is present in at least one of `B`, `L`, and `R` (Section 6.7.5 Case 1), copy the complete occurrence state (`completions`, `priority`, `finished`, `suspended`, `due`, `repeat`, `blocked`, `subtasks`) from the complete entity winner `W`, where a version with more completed occurrences takes precedence over a version of an older occurrence.
When `B.completions == L.completions == R.completions` and `finished` is omitted in all three (Section 6.7.5 Case 2), merge `priority`, `suspended` (pre-normalizing finite `suspended <= now` to `absent`), `due`, `repeat`, `blocked` (`V.repeat`-aware pre-normalization + per-`targetId` map merge), and `subtasks` independently.
Occurrence-independent metadata edits (`name`, `note`, `labels`, `origin`, `link`, `history`, and `condition`) always reconcile outside `Task state` across both Case 1 and Case 2 (`history` reconciling as a `(timestampUtc, text)` set under Section 6.7.5 Point 4 so recurrence progress on one device never discards `history` edits from another device).
If a purported descendant regresses below its proven baseline counter, return `RecoveryRequired`.
Preserve both versions until that inconsistent history is reconciled.

A task deletion record carries its last known completion counter as an optional final argument:

```text
task 8jKaCdOkD2 2026-11-04 12:00:00 7
```

An omitted deletion checkpoint means `0`.
`label` and `location` deletion records have no completion checkpoint.
Keep the greatest known checkpoint when combining task deletion records, independently of their deletion timestamps.
Checkpoint merging MUST NOT restart deletion retention.

Delete and Undelete decisions preserve the greatest counter known from the live version, baseline, and deletion record.
Undelete preserves other selected task state (including `history`) and MUST NOT reset completion history.
This prevents an earlier fulfilled requirement from becoming blocked after Undelete.
Expired history still uses the new-identity recovery rules from Section 6.8.4.

#### 6.9.6 Example

```text
tdf 0.7.0

queue {
    modified 2026-11-04 09:00:00
    task 8jKaCdOkD2
    task 3nQp7ROkB8
}

task 3nQp7ROkB8 {
    name     "Install update"
    created  2026-11-04 09:00
    modified 2026-11-04 09:00
    blocked  8jKaCdOkD2:8
}

task 8jKaCdOkD2 {
    name        "Create backup"
    created     2026-11-01 08:00
    modified    2026-11-04 08:00
    completions 7
    repeat      1 days 09:00
}
```

The update waits for backup completion `8`.
Completing backup occurrence `8` satisfies and strips non-recurring `3nQp7ROkB8`'s one-shot `blocked 8jKaCdOkD2:8` dependency (releasing the update while the backup schedules its next occurrence; if `3nQp7ROkB8` also had a `repeat` rule, `blocked 8jKaCdOkD2:8` would remain preserved and satisfied across backup completion `9` until `3nQp7ROkB8` completed its own occurrence and rearmed).

#### 6.9.7 Verification Cases

| Case | Expected result |
| --- | --- |
| Prerequisite counter is `7`, requirement is `8` | Block the dependent. |
| Prerequisite advances to `8` | Release that prerequisite restriction (stripping `blocked` immediately if either the open dependent or the prerequisite has no `repeat` rule, or retaining the satisfied entry if both have `repeat`). |
| Recurring prerequisite later advances to `9` while recurring dependent is still on its occurrence | Keep requirement `8` preserved and satisfied until the recurring dependent completes its occurrence. |
| A recurring dependent completes while its open recurring prerequisite is at `9` | Capture requirement `10` for the next dependent occurrence. |
| The prerequisite reaches `10` during deferral | Keep the new requirement satisfied when the dependent wakes. |
| A standard prerequisite is already finished at `1` | Already satisfied (stripped on open dependents during committed mutation / cleanup). |
| A completed prerequisite is restored with counter `1` | Keep earlier requirement `1` satisfied and arm new dependencies at `2`. |
| A dependency list gains another target | Preserve existing requirements and capture only the new target. |
| Two devices concurrently update `blocked` or `repeat` while a prerequisite completes in the same occurrence | Pre-normalize `blocked` per variant `V.repeat` against `(mergedTasksById, mergedDeletedTasks)` and merge per `targetId` under Section 6.7.5 Case 2 (preserving concurrent threshold raises such as `A:2` and newly added recurring pipelines). |
| A queue or priority change occurs | Preserve completion counters and required numbers. |
| The same completion command is retried | Advance the counter only once. |
| Two devices complete the same occurrence | Keep one counter increment. |
| An older occurrence has a later modification timestamp | Preserve the version with greater completion progress (while still merging `history` and occurrence-independent metadata). |
| Undelete selects an older edited version | Preserve the greatest known completion checkpoint. |
| Completion would overflow its bound | Preserve the complete previous state. |

### 6.10 UTC Deferrals, Deadlines (`due`), and Local Calendar Scheduling

#### 6.10.1 Stored Instants and Evaluation

All stored timestamps represent UTC instants, including `due`, `history`, and finite `suspended` values (converted to local time only for display and user input).
Recurring clock times and `condition day` or `condition time` rules represent local calendar values.

Capture one UTC reference instant for each evaluation or mutation.
Derive `localNow` from that instant using the configured time zone.
Use the zone's rules for the date being converted.
A fixed current UTC offset is insufficient for future or historical dates.

A finite deferral is active exactly when `suspended > now` in UTC.
The value `forever` is always an active deferral for an open task.
An omitted or expired deferral does not block the task.
At equality, the finite deferral has expired.
Tier derivation ignores an expired `suspended` timestamp (`suspended <= now` in UTC, along with its note) without mutating the document.
`due` is non-blocking target deadline metadata (with optional `passive` modifier and optional note) and never blocks a task regardless of whether `due <= now` or `due > now`.
Raw parsing, read-only loading, and pure Section 5 tier evaluation MUST NOT remove or update `suspended`, `due`, or `modified`.
During guarded refresh/synchronization or a committed domain mutation evaluated at UTC instant `now` (Sections 6.6 and 6.7.8), expired finite `suspended <= now` directives (and their notes) are stripped from open tasks (advancing `modified`), whereas overdue `due <= now` directives (with `passive` and `due` notes) remain intact until explicitly edited, cleared, restored from `Completed`, or advanced by Mode 2 recurrence.
Daylight-saving clock rollback MUST NOT reactivate an expired UTC deferral.
Other activation conditions remain subject to their own local evaluation.

A stored date-only timestamp means midnight UTC under Section 2.8.
A date-only local scheduling input means midnight in the configured zone before conversion.
Persist the converted instant with an explicit UTC time (`YYYY-MM-DD HH:MM:SS`).

Changing the configured zone MUST NOT reinterpret an already stored UTC `suspended`, `due`, or `history` timestamp.
The new zone applies to subsequent local calendar calculations.
Zone configuration (like the evaluation lead window $W_{\text{due}}$ in Section 5.5) is an operation parameter and adds no timezone or lead-window field to `task`, `label`, or `location` blocks.

#### 6.10.2 Resolving Local Times

For each local date and clock time:

1. If it identifies one instant, use that instant.
2. If it occurs twice during an overlap, use the first occurrence, which has the earlier UTC instant.
3. If it falls in a forward clock gap, apply the offset that existed immediately before that gap.

The gap rule shifts the resolved local time forward by the gap duration.
Preserve the intended recurrence clock independently of this adjustment.
These point-conversion choices follow [RFC 5545, Section 3.3.5](https://www.rfc-editor.org/rfc/rfc5545#section-3.3.5).

Require the configured zone's applicable transition rules.
If they are unavailable, return `TimeZoneContextRequired` without changing task data.
Reject a converted instant outside the timestamp range with `InvalidTimestamp`.

#### 6.10.3 Recurrence Clock, Explicit Preparation Lead Offset (`lead <N> days`), Schedule-Anchored Deadlines (`due`), and Next Occurrence Calculation

A recurrence rule may include its intended local clock time and an optional preparation lead offset in calendar days (`1..MAX_REPEAT_COUNT = 3650`):

```text
repeat 1 days 09:00
repeat 2 weeks 14:30:15
repeat 1 months 09:00 lead 5 days
repeat 2 weeks lead 3 days
```

An omitted clock means `00:00:00` local time, and an omitted `lead` clause means `leadDays = 0`.
Keep `<repeat-time>` and `leadDays` in the `repeat` rule across occurrences, including after a gap-adjusted occurrence or a temporary manual snooze via `suspended`.
A manual deferral (`suspended`) changes only the current occurrence's deferral and MUST NOT alter `<repeat-time>` or `leadDays`.

When completing a recurring task (`repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]`):

**Mode 1 — Without `due` (`due` Omitted — Completion-Relative Mode):**
1. Convert the completion's UTC instant (`now`) into `localNow` in the configured zone (`leadDays` is ignored when `due` is omitted).
2. Add the repeat interval (`<count> <unit>`) to `localNow`'s local calendar date:
   - Add `days` directly, or multiply `weeks` by `7` calendar days.
   - For `months`, clamp the source day to the target month's last valid day.
3. Combine the target local calendar date with the repeat rule's normalized local clock `<repeat-time>` (defaulting to `00:00:00` local time).
4. Resolve that local value to UTC under Section 6.10.2 to obtain `<next_due>`.
5. Require `<next_due> > now` in UTC (`InvalidTimestamp` if out of range).
6. Store `<next_due>` in `suspended`, clear any `suspended` `<note>`, and preserve `origin` and all `history` entries unchanged under Section 6.4.

**Mode 2 — With `due` Present (`due` as Fixed Calendar Anchor + Explicit `lead <lead-count> days` Preparation Window):**
1. **Advance `due` Along Fixed Local Schedule:** Convert `oldDue` (UTC) into local calendar components $(Y_d, M_d, D_d, h_d, m_d, s_d)$ in the configured IANA time zone, and find the smallest integer multiple $k \ge 1$ such that advancing $(Y_d, M_d, D_d)$ by $k \times \text{<count> <unit>}$ (adding `days` or $7 \times \text{weeks}$ directly, or applying month-end clamping against $D_d$ for `months`, preserving `oldDue`'s local wall-clock time $(h_d, m_d, s_d)$, and resolving local-to-UTC via Section 6.10.2) produces a UTC instant `newDue > now` with target local calendar date $(Y'_d, M'_d, D'_d)$.
2. **Compute Target Preparation Date:** Subtract `leadDays` (`0` when `lead` is omitted) calendar days from $(Y'_d, M'_d, D'_d)$ to obtain `targetSuspendedLocalDate` (`InvalidTimestamp` if outside `0001-01-01..9999-12-31`).
3. **Resolve Wake-Up Instant:** Combine `targetSuspendedLocalDate` with `repeat`'s normalized local clock `<repeat-time>` (`00:00:00` when omitted), resolve to UTC via Section 6.10.2 to obtain `candidateSuspended`, and set `newSuspended = min(candidateSuspended, newDue)`.
4. **Commit Next Occurrence State:** Set `due = newDue`, reset occurrence-scoped `passive` to omitted (`false`), preserve `due`'s `<note>` unchanged, clear any `suspended` `<note>`, preserve `origin` and all `history` entries unchanged, and either set `suspended = newSuspended` when `newSuspended > now` or **omit `suspended` immediately when `newSuspended <= now`** (when the previous occurrence is completed after the next occurrence's preparation window has already opened, making the next occurrence immediately eligible without writing an already-expired `suspended` timestamp).

Preserve the intended repeat clock and `leadDays` when a gap or overlap changes the resolved offset.
Persist the occurrence transition atomically under Section 6.9.4.

A canonical serializer omits a midnight recurrence clock (`00:00:00`) and omits `lead` when `leadDays == 0`.
For non-midnight recurrence clocks, emit `HH:MM` when seconds are zero, otherwise `HH:MM:SS`, followed by `lead <lead-count> days` when `leadDays >= 1`.
Emit finite deferrals (`suspended`) as `suspended YYYY-MM-DD HH:MM:SS ["<escaped-note>"]` in UTC, indefinite deferrals as `suspended forever ["<escaped-note>"]`, and deadlines (`due`) as `due YYYY-MM-DD HH:MM:SS [passive] ["<escaped-note>"]` in UTC.

#### 6.10.4 Verification Cases

These conversion vectors use `Europe/Berlin`:

| Intended local date and time | Stored UTC instant | Resolved local time |
| --- | --- | --- |
| `2026-03-28 09:00:00` | `2026-03-28 08:00:00` | `09:00:00` |
| `2026-03-29 09:00:00` | `2026-03-29 07:00:00` | `09:00:00` |
| `2026-03-29 02:30:00` | `2026-03-29 01:30:00` | `03:30:00`, after the gap |
| `2026-03-30 02:30:00` | `2026-03-30 00:30:00` | `02:30:00`, preserving the repeat clock |
| `2026-10-25 02:30:00` | `2026-10-25 00:30:00` | First `02:30:00`, before the overlap repeats |
| `2026-10-25 09:00:00` | `2026-10-25 08:00:00` | `09:00:00` |
| `2026-11-05 00:00:00` | `2026-11-04 23:00:00` | Local midnight |

Also verify:

- A deferral at `2026-10-25 00:30:00` UTC stays expired at `2026-10-25 01:10:00` UTC, and guarded refresh/synchronization or a committed mutation strips finite `suspended <= now` (and its note) from open tasks while keeping overdue `due <= now` (with `passive` and its note) intact.
- Two devices in different zones evaluate the same finite UTC deferral against the same instant.
- A configured zone change preserves already stored `suspended`, `due`, and `history` timestamps.
- Late completion does not shift a default-midnight recurrence clock.
- `2026-01-31` plus one calendar month becomes `2026-02-28`.
- Completing a monthly task (`repeat 1 months 08:00 lead 5 days`) with `due` on `2026-10-15 18:00` local (CEST, UTC+2) late on `2026-10-17` advances `newDue` by $k = 1$ month to `2026-11-15 18:00` local (CET, UTC+1) and sets `newSuspended` to `2026-11-10 08:00` local (CET, UTC+1), preserving the exact `5`-day lead window and `08:00` local wake-up clock across the October DST transition even after `suspended` on the October occurrence had already expired and been stripped.
- Completing a monthly task (`repeat 1 months 08:00 lead 2 days`) with `due` on `2026-01-31 18:00` local on `2026-01-31` clamps `newDue` to `2026-02-28 18:00` local and subtracts `2` calendar days to set `newSuspended = 2026-02-26 08:00` local.
- Completing a monthly task (`repeat 1 months`) with `due` on `2026-11-15 18:00` local and omitted `lead` (`leadDays = 0`) early on `2026-11-12` advances `newDue` to `2026-12-15 18:00` local and sets `newSuspended` to `2026-12-15 00:00:00` local; completing that occurrence late on `2026-12-15 10:00` local (`newSuspended <= now < newDue` when `due` was already on the target cycle) omits `suspended` immediately rather than persisting an already-expired timestamp.
- Mode 2 completion resets occurrence-scoped `passive` to omitted (`false`), clears any `suspended` note, and preserves `due` note, `origin`, and `history` unchanged.
- Temporarily snoozing a single occurrence via manual `suspended` (including `suspended > due`) does not alter `repeat`'s `<repeat-time>` or `leadDays` for subsequent occurrences.
- `suspended forever` remains indefinite in every zone.
- Parsing UTC values requires no source-zone conversion.
- Missing conversion context or timestamp overflow preserves the complete previous state.

### 6.11 Shared Queue Mutations and Synchronization

#### 6.11.1 Ordinary Mutations

The queue stores one ordered list and one `modified` timestamp.
It has no per-entry timestamps.
When an ordinary mutation changes the list, set its revision to:

```text
modified = max(now, previousQueueModified + 1 second)
```

An absent queue has the epoch revision from Section 4.6.
An unchanged list preserves its revision.
When a command changes neither task attributes nor `queue` order, leave both `task.modified` and `queue.modified` unchanged.
Fail with `InvalidTimestamp` if advancement exceeds the supported range.

Append newly scheduled tasks unless a transition specifies another position.
Remove entries when tasks become completed, moved to `Someday`, or deleted.
Retain entries during temporary restrictions and recurring deferrals.
A priority change preserves the saved list unless the command also requests a move.

An explicit move removes one entry and inserts it before or after a specified queue entry, or at the end.
The anchor MUST exist in the same current queue and differ from the moved task.
Reevaluate the command if its source snapshot changes before publication.
Task facts, queue changes, and deletion records MUST succeed or fail together.

#### 6.11.2 Queue Merge

Treat the complete ordered list in `queue` as the authoritative merge unit for `Someday` <-> scheduled transitions and queue order.
Bind its baseline to the same acknowledged document and history generation as the entity baseline.
Compare decoded IDs in list order. Block declaration order and whitespace are irrelevant.

Choose a complete queue winner by later `queue.modified`, then lexicographically greater ordered ID list.
Use unsigned ASCII ID order. A shorter equal-prefix list sorts first.
Without a proven common baseline, start from that winner's complete list.
With a baseline, apply the scalar three-way rules from Section 6.7.5 to the complete list:
- If `L.queue` and `R.queue` are equal, keep that list.
- If `L.queue` equals `B.queue`, keep `R.queue` (incorporating any `Someday` <-> scheduled transitions or reorders performed on `R`).
- If `R.queue` equals `B.queue`, keep `L.queue` (incorporating any `Someday` <-> scheduled transitions or reorders performed on `L`).
- Otherwise (both `L.queue` and `R.queue` diverged from `B.queue`, or no baseline `B` is available), start from the complete queue winner's list (`W.queue`), and append any concurrent additions from the non-winning queue (`Loser.queue` entries that were not in `B.queue`, or live open tasks present only on the losing side and listed in `Loser.queue` when no baseline is available) ordered by ascending UTC `created` timestamp, then ascending ASCII ID.

First resolve entity presence, deletion conflicts, history generation guards, and post-merge cascades (Section 6.7.8, including `scoped` label deletion flood protection that moves affected open tasks to `Someday` and removes their IDs from `queue`).
Let `O` contain the retained live open tasks (`finished` absent, not tombstoned in `deleted`, and not evicted to `Someday` by post-merge `scoped` label deletion under Section 6.7.8) in the merged document.
Perform post-merge queue normalization against `O`:

1. Keep entries in the merged queue whose IDs belong to `O`, preserving their relative order and removing any duplicate IDs.
2. Remove any task IDs from `queue` that are not in `O` (tasks that were completed with `finished` present, tombstoned in `deleted` on either side, or evicted to `Someday` when their last remaining `scoped` label was deleted during the merge).

This reconciliation preserves concurrent scheduled additions and `Someday` <-> scheduled transitions without losing task data.
It does not change stored task timestamps.
Filtering a stale entry does not itself delete a task.
Do not recover rejected or ambiguous local entities through queue membership.
Queue reconciliation runs during mutation or synchronization, never as parser repair.

Compare the available baseline and both input queues by the complete queue winner order.
If the greatest existing queue has the final post-cascade reconciled list, preserve its revision.
Otherwise, set `queue.modified` to the greatest observed queue revision among `B`, `L`, and `R` plus one second (`max(B.queue.modified, L.queue.modified, R.queue.modified) + 1 second`).
Do not use the current clock for this deterministic merge revision.
Equal inputs and repeated synchronization MUST NOT advance revisions.
Reversing the two inputs MUST preserve the resulting list and revision.

Validate the complete candidate under Section 6.7.7.
Do not publish a partial entity or queue result.
Advance their common baseline only after successful guarded publication or acknowledgment.

#### 6.11.3 Verification Cases

| Case | Required result |
| --- | --- |
| First task is blocked | Fill Focus and Ready from later eligible entries. |
| First task becomes eligible | Restore its saved position and displace later tasks within the fixed limits. |
| All queued tasks are blocked | Focus, Ready, and Planned remain empty. |
| A label filter or due lead window changes | Recompute tiers without changing saved order, stored `priority`/`passive` flags, or revisions. |
| Effective-priority groups interleave in the saved list | Preserve list order within the effective-priority group (`hasEffectivePriority == true`) and within the regular group (`hasEffectivePriority == false`). |
| Focus task is downgraded to Ready under active filter context | Place it immediately after the 7th task of $E_{\text{ctx}}$ (or after the last task of $E_{\text{ctx}}$ when $1 \le \|E_{\text{ctx}}\| < 7$), keeping explicit `priority` unchanged when the 7th task also has effective priority and `isDueUrgent` is `true` (or setting `priority` when `isDueUrgent` is `false`), or stripping `priority` and setting `passive` on urgent `due` when stepping below regular tasks. |
| Ready task moves to Planned | Strip `priority` if present, set `passive` if `isDueUrgent` is `true`, move its queue entry to the end of `queue`, and preserve every other entry's relative order. |
| Downgrade a Focus or Ready task without effective priority already at the end of `queue` | Leave task attributes, `queue` order, `task.modified`, and `queue.modified` unchanged (without running board-wide cleanup on a pure no-op). |
| Schedule a `Someday` task or move a scheduled task to `Someday` | Update `queue` membership and `queue.modified` (stripping `priority` and `suspended` + note while preserving `(due, passive, due-note)`, `origin`, and `history` on `Someday`); merge via `queue` and `queue.modified` rather than `task.modified` when task attributes are unchanged. |
| Recurrence creates a temporary deferral | Retain the existing queue position without occupying an active slot. |
| Standard completion or task deletion | Remove its entry atomically with the task mutation. |
| A task's last remaining label is a deleted `scoped` label | Keep the task open, strip the deleted label ID and `priority`, preserve `suspended` (with note), `(due, passive, due-note)`, `origin`, and `history`, and evict its ID from `queue` to `Someday` so it does not flood the global Focus/Ready queue. |
| Concurrent additions have different lists | Retain both task identities and append missing members deterministically by ascending `created`, then ascending ASCII ID. |
| A selected queue contains a now-completed (`finished`), tombstoned (`deleted`), or `scoped`-evicted task | Remove its queue entry during post-merge queue normalization. |
| Queue publication fails | Preserve the active document and acknowledged baseline. |
| Queue list contains an unknown, deleted, completed, or duplicated ID on load | Reject it without changing the source. |

## 7. Conformance & Resource Bounds

To guarantee bounded memory usage and prevent denial-of-service on malformed inputs, a conforming TDF parser MUST enforce the following resource limits before scanning or allocating the $(N+1)$-th element:

| Bound Name | Default Limit | Purpose |
| :--- | :--- | :--- |
| `MAX_FILE_BYTES` | `1_048_576` (1 MiB) | Maximum input or serialized output size in UTF-8 bytes. |
| `MAX_LINE_COUNT` | `16_384` | Maximum logical lines per `.tdf` document. |
| `MAX_NESTING_DEPTH` | `2` | Maximum open block depth. Root blocks are `task`, `label`, `location`, `deleted`, and `queue`. Only tasks and labels permit schema-defined nested blocks. |
| `MAX_BLOCKS_PER_DOC` | `4_096` | Maximum total blocks, including `task`, `label`, `location`, `deleted`, and `queue`. Their entries are directives. |
| `MAX_LOCATIONS` | `200` | Maximum root-level `location` blocks per `.tdf` document. |
| `MAX_STMTS_PER_BLOCK` | `1_024` | Maximum direct child statements per ordinary block in `tdf 0.7.0` (`512` when validating `< 0.7.0` source documents under Section 10.1.1). Count each nested block once. Count its contents within that nested block. A deletion block permits one generation plus `MAX_DELETED_RECORDS` records. A queue permits one revision plus `MAX_QUEUE_ENTRIES` entries. |
| `MAX_CONDITION_RULES_PER_ENTITY` | `512` | Maximum stored condition rules across all inline directives and condition blocks in one task or label. |
| `MAX_LOCATION_REFS_PER_ENTITY` | `63` | Maximum `<location-id>` references across all `location` condition rules in one task or label (counted before deduplication, matching `MAX_ARGS_PER_STMT - 1` when coalesced into a single canonical `location` rule). |
| `MAX_QUEUE_ENTRIES` | `4_096` | Maximum task entries in the shared queue, including blocked tasks. Other document bounds still apply. |
| `MAX_DELETED_RECORDS` | `4_096` | Maximum `task`, `label`, and `location` deletion records in the shared `deleted` block. |
| `MAX_SYNC_GENERATION` | `9_007_199_254_740_991` | Maximum deletion history generation. Overflow fails instead of wrapping. |
| `MAX_COMPLETIONS` | `9_007_199_254_740_991` | Maximum completion counter, deletion checkpoint, and required completion number. |
| `MAX_ARGS_PER_STMT` | `64` | Maximum arguments allowed on a single block header or directive. |
| `MAX_TEXT_LENGTH` | `500` | Maximum decoded Unicode scalar values in `name`, `step`, `task` or `label` link `<title>`, `location.source`, `origin` `"<namespace>"` and `"<external-key>"`, or `history` `"<text>"`. |
| `MAX_NOTE_LENGTH` | `2000` | Maximum decoded Unicode scalar values in `note` on a `task`, `label`, or `location`, or in the optional `"<note>"` argument on `suspended` or `due`. |
| `MAX_URI_LENGTH` | `2048` | Maximum decoded Unicode scalar values in a `task` or `label` link URI. |
| `MAX_LINKS_PER_TASK` | `20` | Maximum number of `link` directives permitted in a single `task` block. |
| `MAX_LINKS_PER_LABEL` | `20` | Maximum number of `link` directives permitted in a single `label` block. |
| `MAX_HISTORY_PER_TASK` | `500` | Maximum number of `history` directives permitted in a single `task` block (counted before deduplication). |
| `MAX_REPEAT_COUNT` | `3_650` | Maximum recurrence interval count `<count>` or preparation lead offset `<lead-count>` in `repeat <count> <unit> [<repeat-time>] [lead <lead-count> days]`. |
| `MAX_LOCATION_RADIUS` | `100_000` | Maximum `radius` in meters (`100 km`) for a `location` block (`0 < radius <= 100_000`). |
| `MAX_NUMBER_LENGTH` | `24` | Maximum raw ASCII characters in a `<number>` token. |

In addition to parser resource bounds, Section 5.5 defines the normative default deadline lead-window evaluation constant `DEFAULT_DUE_LEAD_SECONDS = 86_400` (`24` hours) for `hasEffectivePriority` when an evaluator does not override or disable lead-window auto-promotion.

### 7.1 Canonical Output Validation

A canonical serializer MUST emit root-level elements in this exact 6-section order (Sections 4.0, 4.5, and 4.6):
1. `tdf 0.7.0`
2. `deleted { ... }` (when present; `generation` first, followed by `task` records sorted by ascending ASCII `<task-id>`, `label` records sorted by ascending ASCII `<label-id>`, and `location` records sorted by ascending ASCII `<location-id>`)
3. `queue { ... }` (when present; `modified` first, followed by `task <task-id>` directives in saved queue order)
4. `label` blocks sorted by ascending ASCII `<label-id>` (emitting `label <id> scoped {` when `scoped = true`)
5. `location` blocks sorted by ascending ASCII `<location-id>`
6. `task` blocks sorted by ascending ASCII `<task-id>`

Inside every `label` block, a canonical serializer MUST emit present directives and sub-blocks in the exact 6-position order defined in Section 4.2:
1. `name`
2. `color`
3. `note`
4. `modified`
5. `link` (in declaration order)
6. `condition` (inline single rule or `condition { ... }` sub-block sorted by `day`, `time`, `location`, with all `location` references coalesced into a single `location <loc-1> [<loc-2> ...]` rule deduplicated in first-seen declaration order)

Inside every `location` block, a canonical serializer MUST emit present directives in the exact 6-position order defined in Section 4.3:
1. `name`
2. `note`
3. `source`
4. `coordinates` (formatted under Section 6.7.3 decimal normalization)
5. `radius` (formatted under Section 6.7.3 decimal normalization)
6. `modified`

Inside every `task` block, a canonical serializer MUST emit present directives and sub-blocks in the exact 16-position order defined in Section 4.1.2:
1. `name`
2. `note`
3. `created`
4. `finished`
5. `modified`
6. `completions` (omitted when `0`, emitted when `>= 1`)
7. `repeat` (`00:00:00` local clock omitted; `lead <lead-count> days` omitted when `leadDays == 0`)
8. `labels` (sorted ascending by ASCII ID, deduplicated)
9. `blocked` (sorted ascending by ASCII target ID, `:1` suffix omitted)
10. `suspended` (`YYYY-MM-DD HH:MM:SS` in UTC or `forever`, followed by `"<escaped-note>"` when present)
11. `due` (`YYYY-MM-DD HH:MM:SS` in UTC, followed by `passive` when true and `"<escaped-note>"` when present)
12. `origin`
13. `link` (in declaration order)
14. `history` (deduplicated `(timestampUtc, text)` pairs sorted by ascending UTC epoch seconds and then ascending unsigned UTF-8 byte order of `text`, emitted as `history YYYY-MM-DD HH:MM:SS "<escaped-text>"`)
15. `condition` (`condition any`, inline single rule, or `condition { ... }` sub-block sorted by `day`, `time`, `location`, with all `location` references coalesced into a single `location <loc-1> [<loc-2> ...]` rule deduplicated in first-seen declaration order)
16. `subtasks` (in declaration order of `step` directives)

Canonical condition grouping MUST preserve every accepted rule without exceeding `MAX_STMTS_PER_BLOCK` or `MAX_LOCATION_REFS_PER_ENTITY`.
Apply the entity-wide condition limits (`MAX_CONDITION_RULES_PER_ENTITY = 512` and `MAX_LOCATION_REFS_PER_ENTITY = 63` counted before deduplication) before grouping.
Splitting rules across several input blocks MUST NOT bypass those limits.
Canonical serialization emits `deleted` record timestamps, `queue.modified`, finite `suspended`, `due`, and `history` timestamps as `YYYY-MM-DD HH:MM:SS` in UTC with explicit seconds (Sections 4.1.2, 4.5, 4.6, and 6.10.3), and emits `created`, `finished`, and entity `modified` (`task.modified`, `label.modified`, `location.modified`) as `YYYY-MM-DD HH:MM` in UTC when seconds are zero and `YYYY-MM-DD HH:MM:SS` when seconds are non-zero.

Every successful serialization MUST produce a valid current-version (`tdf 0.7.0`) document whose canonical SHA-256 digest can be recorded as `sourceDigest` under Section 6.7.2.
Parsing that output MUST preserve the decoded values defined in Section 6.7.3 and the saved queue order.
Preserve entity identities, revisions, deletion records, and deletion history generation.
Validate the complete output against all schema and resource bounds before publication.
Canonical formatting can increase byte or line counts.
Return `LimitExceeded` if the output exceeds a resource bound.
Preserve the input, active document, and acknowledged baseline after failure.
Do not truncate `history`, `link`, or condition content or split the canonical condition block to force publication.
These output checks do not authorize serialization or persistence during loading.

### 7.2 Boundary Verification Cases

| Case | Expected result |
| --- | --- |
| An ordinary block has 1_024 direct child statements in `tdf 0.7.0` (or 512 in a `< 0.7.0` source document) | Accept when per-directive bounds hold. |
| An ordinary block has 1_025 direct child statements in `tdf 0.7.0` (or 513 in a `< 0.7.0` source document) | Reject the 1_025th (or 513th) direct child statement with `LimitExceeded`. |
| A canonical `task` block is at full capacity (`12` scalar directives + `20` `link` + `500` `history` + `1` `condition` + `1` `subtasks` = `534` direct child statements) | Accept (`534 <= MAX_STMTS_PER_BLOCK = 1_024`) and allow lifecycle mutations without statement-bound collision. |
| A `task` block declares 500 `history` directives (counted before deduplication) | Accept when other bounds hold; canonical serialization deduplicates exact `(timestampUtc, text)` duplicates and sorts chronologically with unsigned UTF-8 byte tie-breaks. |
| A `task` block declares 501 `history` directives (including duplicate lines counted before deduplication) | Reject directive 501 with `LimitExceeded` before allocating. |
| A `label` block declares 20 `link` directives | Accept when other bounds hold. |
| A `label` block declares 21 `link` directives | Reject directive 21 with `LimitExceeded`. |
| `repeat 1 months 09:00 lead 3650 days` | Accept (`<= MAX_REPEAT_COUNT`). |
| `repeat 1 months 09:00 lead 3651 days` | Return `LimitExceeded`. |
| `repeat 1 months lead 0 days` or `repeat 1 months lead -1 days` | Return `InvalidNumber`. |
| One entity has 511 or 512 condition rules across several blocks | Accept when other bounds hold. Canonical grouping stays within the statement limit. |
| One entity has 513 condition rules across several blocks | Reject rule 513 with `LimitExceeded`. |
| Two condition blocks contain 300 rules each | Reject at rule 513, before canonical serialization. |
| One entity references 63 `<location-id>`s across one or more `location` condition rules (counted before deduplication) | Accept and coalesce into one canonical `location` rule with up to 63 deduplicated arguments in first-seen declaration order. |
| One entity references 64 `<location-id>`s across one or more `location` condition rules (counted before deduplication) | Reject the 64th `<location-id>` reference with `LimitExceeded`. |
| Document declares 200 root `location` blocks | Accept when other bounds hold. |
| Document declares 201 root `location` blocks | Reject block 201 with `LimitExceeded`. |
| A `location` block has `radius 100000` or `radius 99999.99` | Accept (`<= MAX_LOCATION_RADIUS`). |
| A `location` block has `radius 100000.01` | Return `LimitExceeded`. |
| A `location` block has `radius 0` or `radius -5` or `radius 10.125` | Return `InvalidNumber`. |
| A `<number>` token has 24 ASCII characters (such as `-123.456789` within precision bounds) | Accept when semantic precision and range bounds hold. |
| A `<number>` token has 25 ASCII characters (such as `0000000000000000000000150`) | Return `LimitExceeded`. |
| Several valid layouts represent the same ordered condition groups | Serialize to one valid condition model. Preserve rule order within `day` and `time` and coalesce `location` IDs in first-seen declaration order. |
| Root blocks appear in arbitrary declaration order on load | Accept on load; canonical serialization emits `deleted`, `queue`, ASCII-sorted `label`s, ASCII-sorted `location`s, and ASCII-sorted `task`s. |
| Canonical output exceeds the file or line bound | Return `LimitExceeded` without publication or input changes. |
| All effective condition groups are empty | The context evaluates to `true`. |
| One group has only false rules and the other groups are empty | The context evaluates to `false`. |
| A reset clears an inherited group | Evaluate that empty group as `true`. Continue with the remaining groups. |
| Timestamp equals either supported endpoint | Accept. |
| Timestamp uses year `0000` or `10000` | Return `InvalidTimestamp`. |
| Date is `2000-02-29` | Accept. |
| Date is `1900-02-29` | Return `InvalidTimestamp`. |
| Revision advancement or `targetSuspendedLocalDate` exceeds `0001-01-01..9999-12-31` | Return `InvalidTimestamp` without partial changes. |
| A `name`, link `<title>`, `location.source`, `origin` component, or `history` `<text>` contains 500 scalar values above `U+FFFF` | Accept when other bounds hold. |
| A `name`, link `<title>`, `location.source`, `origin` component, or `history` `<text>` contains 501 scalar values above `U+FFFF` | Return `LimitExceeded`. |
| A `note` or `suspended` / `due` `<note>` contains 2000 decoded scalar values (including `\n`, `\r`, `\t`) | Accept when other bounds hold. |
| A `note` or `suspended` / `due` `<note>` contains 2001 decoded scalar values | Return `LimitExceeded`. |
| A `name` or `history` `<text>` contains 250 repetitions of `U+0065 U+0301` | Count 500 scalar values. Accept when other bounds hold. |
| A string contains the escaped sequence `\n` | Count the decoded line feed as one scalar value. Reject with `UnexpectedToken` in single-line `<text>` directives (`name`, `step`, `task` or `label` link `<title>`, `location.source`, `origin`, `history` `<text>`, even when no other characters are present), reject with `InvalidUri` in non-blank link `<uri>`, and accept in `<note>` (`note`, `suspended` `<note>`, `due` `<note>`). |
| A comment contains `U+00A0` | Accept the whitespace as comment content. |
| `U+00A0` separates a directive and its argument | Return `UnexpectedToken`. |
| A comment contains `U+0000` | Return `UnexpectedToken`. |
| A deleted task line is `task AAAAAAAAAA 2026-11-01 7` | Read midnight UTC and completion checkpoint `7`. |
| A deleted task line is `task AAAAAAAAAA 2026-11-01 12:30 7` | Read `12:30:00` UTC and completion checkpoint `7`. |

## 8. Mandatory Error Conditions

A conforming TDF parser MUST report a structured error with the 1-based line number and fail deterministically on any of the following inputs:

- **Missing Version Header (`MissingVersionHeader`):** The file contains no statements (empty or only whitespace and `#` comments), or the first statement at depth `0` is not `tdf <version>` (such as starting directly with a `label`, `location`, or `task` block, or bare `tdf` without a version argument).
- **Unsupported Version (`UnsupportedVersion`):** The initial `tdf <version>` header specifies any `<version>` other than `0.7.0` (or `0.6.0`, `0.5.1`, and `0.5.0` during load-time conversion under Sections 10.6 through 10.8), quotes the version token, or has extra arguments.
- **Root Directive (`UnexpectedRootDirective`):** Any root-level directive other than the initial `tdf` version header appears at depth `0` outside a `{ ... }` block, including a duplicate `tdf` directive or a root-level `history` directive later in the file.
- **Missing Argument or Brace (`MissingDirectiveArgument`):** A single identifier appears on a line without arguments and without an opening `{` (such as `created`, `repeat`, `suspended`, `due`, `origin`, `link`, or `history` with no arguments).
- **Quoted or Invalid Identifier (`InvalidIdentifier`):** A block or directive name violates Section 2.6. An entity ID component (`<task-id>`, `<label-id>`, or `<location-id>`, including IDs in `condition location`) is quoted or not canonical 10-character Base62. A prerequisite token is quoted or has an invalid ID component. Reject these inputs without generating replacements.
- **Malformed Block Header or Missing Whitespace Before Brace (`InvalidBlockHeader`):** The opening `{` attaches directly to an identifier or argument without whitespace (such as `task 8jKaCdOkD2{`, `location 7pQr9mOkD2{`, `history{`, or `condition{`). A required `<task-id>`, `<label-id>`, or `<location-id>` is missing (`task {`, `label {`, or `location {`), or an unknown or extra header argument is present (`task 8jKaCdOkD2 urgent {`, `label 4x9p2mOkD2 extra {`, `label 4x9p2mOkD2 "scoped" {`, `location 7pQr9mOkD2 priority {`, `subtasks urgent {`, or `condition arg {`).
- **Unexpected Token, Control Character, or Trailing Tokens (`UnexpectedToken`):** Non-comment tokens appear on the same line after `{` or `}`. A quote opens or closes inside a token without separating whitespace (such as `foo"bar"` or `"foo"bar`). A directive has an invalid argument count, token type, or modifier order — including `link` (on `task` or `label`) or `origin` with fewer or more than `2` arguments or unquoted string arguments; `history` with `1` or `>= 4` arguments, a quoted second argument in `3`-argument form, or an unquoted final `<text>` argument; `suspended` with an unquoted second argument after `forever`, `>= 3` arguments starting with `forever`, a non-final quoted argument after token `0`, or `>= 3` bare timestamp tokens; `due` with a non-final quoted argument after token `0` (such as wrong order `due <ts> "<note>" passive`), duplicate `passive passive`, or `>= 3` bare timestamp tokens; `repeat` with only `1` argument, an unknown `<unit>` other than `days`, `weeks`, or `months`, a post-unit/post-clock token other than `lead`, missing `<lead-count>` or `days` after `lead`, extra tokens after `days`, a quoted or non-`days` lead unit, or `>= 4` tokens in a `0.5.0`–`0.6.0` document; `coordinates` with fewer or more than `2` arguments; `radius` with fewer or more than `1` argument; or a completion count attached to a `label` or `location` deletion record in `deleted`. A single-line `<text>` directive (`name`, `step`, `task` or `label` link `<title>`, `location.source`, `origin` `"<namespace>"` and `"<external-key>"`, or `history` `"<text>"`) contains a decoded `\n` (`U+000A`), `\r` (`U+000D`), `\t` (`U+0009`), or unpaired UTF-16 surrogate after unescaping (checked before `EmptyText`), or a `<note>` or `<uri>` contains an unpaired UTF-16 surrogate. Also report `UnexpectedToken` for invalid UTF-8 bytes, null bytes (`U+0000`), disallowed control characters, standalone `CR` without `LF`, or non-ASCII whitespace outside quoted strings and comments.
- **Unclosed Block (`UnclosedBlock`):** `EOF` is reached while nesting depth $> 0$.
- **Unmatched Closing Brace (`UnexpectedClosingBrace`):** `}` occurs at depth `0`.
- **Unterminated Quote (`UnterminatedString`):** A `"` or `'` string reaches `\r`, `\n`, or `EOF` before its closing quote.
- **Invalid Escape (`InvalidEscapeSequence`):** A `"` string contains an unknown escape sequence (such as `\a`, `\x`, or `\0`).
- **Schema Validation Errors:**
  - `UnknownBlockType`: A root block is not `task`, `label`, `location`, `deleted`, or `queue`. Tasks permit `subtasks` and `condition`. Labels permit `condition`. Blocks inside `location`, `deleted`, `queue`, `subtasks`, or `condition` (or a `{` block header following non-block directives such as `origin`, `link`, `history`, `repeat`, `suspended`, or `due`) are forbidden.
  - `UnknownDirective`: A directive is invalid for its enclosing block or declared format version — including `queued` inside `task` in a `0.7.0`, `0.6.0`, or `0.5.1` document; `due` or `origin` inside `task` in a `0.5.0` or `0.5.1` document; `history` inside any non-`task` block or inside `task` in a `0.2.0`–`0.6.0` document; or `link` inside `label` in a `0.2.0`–`0.6.0` document. Location blocks permit `name`, `note`, `source`, `coordinates`, `radius`, and `modified`. Deletion blocks permit `generation`, `task`, `label`, and `location`. Queue blocks permit `modified` and `task`. Condition rule types are `day`, `time`, and `location`.
  - `MissingRequiredDirective`: A task lacks `name` or `created`, a label lacks `name`, a location lacks `name`, `coordinates`, or `radius`, a deletion block lacks `generation`, or a queue lacks `modified`. A checklist or condition block contains no step or rule.
  - `DuplicateDirective`: A single-valued scalar or reference directive (including `repeat`, `suspended`, `due`, or `origin` on a `task`, `name`, `color`, `note`, or `modified` on a `label`, or `name`, `note`, `source`, `coordinates`, `radius`, or `modified` on a `location`) occurs repeatedly. Repeatable directives (`link` on `task` and `label`, `history` on `task`, `condition`, checklist `step`, `deleted` records, and `queue` `task` entries) are exempt within their respective bounds. A task contains multiple `subtasks` blocks, or the document contains multiple `deleted` or `queue` blocks.
  - `DuplicateIdentifier`: An entity identity (`task`, `label`, or `location`) is declared repeatedly within its namespace, including duplicate deletion records or a live identity with a deletion record in the same namespace. A repeated queue entry also produces this error. One queue reference to a live open task is permitted, and multiple distinct `task` blocks MAY carry identical `origin` directives.
  - `InvalidQueueMembership`: A `queue` entry in a `0.7.0`, `0.6.0`, or `0.5.1` document references an unknown task ID, a deleted task ID, or a completed task (`finished` present) under Section 4.6. Report invalid entries at their queue lines.
  - `UnknownLabelReference`: A `labels` directive references a `<label-id>` that matches no declared `label` block in the document. Prerequisite `<task-id>` references to missing or pruned tasks remain valid and non-blocking.
  - `UnknownLocationReference`: A `location` condition rule in a `task` or `label` references a `<location-id>` that matches no declared root `location` block in the document (including a deleted or unknown `<location-id>`).
  - `CircularDependency`: Task references in `blocked` directives form a direct cycle (self-dependency) or an indirect cycle across two or more `task` blocks.
  - `EmptyText`: Any `<text>`, `<note>`, or `<uri>` value (`name`, `note`, `suspended` or `due` `"<note>"`, `step`, `task` or `label` link `<title>` and `<uri>`, `location.source`, `origin` `"<namespace>"` and `"<external-key>"`, or `history` `"<text>"`) is empty (`""`) or contains only ASCII whitespace characters (`0x20` for single-line `<text>` after checking `\n`/`\r`/`\t` as `UnexpectedToken`, or `0x20`, `\t` `0x09`, `\n` `0x0A`, and `\r` `0x0D` for `<note>` and `<uri>`) after unescaping (checked before `<uri>` scheme validation; non-ASCII Unicode whitespace such as `U+00A0` is treated as graphic character content).
  - `InvalidUri`: A non-blank `<uri>` in `link <title> <uri>` (on a `task` or `label`) contains a decoded `\n` (`U+000A`), `\r` (`U+000D`), or `\t` (`U+0009`) (or any other ASCII control character), lacks a valid URI scheme (`[a-zA-Z][a-zA-Z0-9+.-]*:`), or uses a forbidden executable or inline-payload scheme (`javascript:`, `vbscript:`, or `data:`, matched case-insensitively). (An empty or ASCII-whitespace-only `<uri>` fails earlier with `EmptyText`.)
  - `InvalidTimestamp` / `InvalidBoolean` / `InvalidNumber` / `InvalidCondition` / `InvalidColor`: A directive argument fails semantic validation. This includes a quoted leading first token or invalid ISO-8601 `<YYYY-MM-DD> [<HH:MM[:SS]>]` timestamp in `created`, `finished`, `modified`, `suspended`, `due`, `history`, or `deleted` records (and `2`-token modifier/note forms on `suspended` or `due` in `0.6.0` or `2`-token note forms on `suspended` in `0.5.0`–`0.5.1`), an out-of-range calendar calculation (`< 0001-01-01` or `> 9999-12-31`), an invalid `<HH:MM>` time window or `start == end`, an unknown weekday token, a non-finite or scientific-notation number (`NaN`, `Infinity`, `-Infinity`, `1e5`), `coordinates` latitude outside `[-90.0, 90.0]` or longitude outside `[-180.0, 180.0]` or having more than 6 fractional digits, `radius` $\le 0$ or having more than 2 fractional digits (note: `radius > MAX_LOCATION_RADIUS` produces `LimitExceeded`), or `repeat` `<count>` or `<lead-count>` quoted, non-integer, signed, leading-zero, or $< 1$. It also includes `any` or `<type> any` inside a `label` condition, `condition any` combined with other rules on a `task`, `<type> any` combined with rules of the same `<type>` group on a `task`, or `color` not matching `"#RRGGBB"`. Invalid deletion history generation literals, completion counts, and prerequisite numbers produce `InvalidNumber` under Section 2.8.
  - `InvalidCompletionState`: A task has `finished` but its effective `completions` counter is zero.
  - `InvalidTime`: A repeat clock (`<repeat-time>`) is quoted or does not match the valid `HH:MM[:SS]` range (`00:00:00..23:59:59`, including `repeat 1 months lead` at token 3 in `0.5.0`–`0.6.0` documents).
- **Limit Exceeded (`LimitExceeded`):** Any resource bound from Section 7 is exceeded (`MAX_FILE_BYTES`, `MAX_LINE_COUNT`, `MAX_NESTING_DEPTH`, `MAX_BLOCKS_PER_DOC`, `MAX_LOCATIONS`, `MAX_STMTS_PER_BLOCK`, `MAX_CONDITION_RULES_PER_ENTITY`, `MAX_LOCATION_REFS_PER_ENTITY`, `MAX_QUEUE_ENTRIES`, `MAX_DELETED_RECORDS`, `MAX_SYNC_GENERATION`, `MAX_COMPLETIONS`, `MAX_ARGS_PER_STMT`, `MAX_TEXT_LENGTH`, `MAX_NOTE_LENGTH`, `MAX_URI_LENGTH`, `MAX_LINKS_PER_TASK`, `MAX_LINKS_PER_LABEL`, `MAX_HISTORY_PER_TASK`, `MAX_REPEAT_COUNT`, `MAX_LOCATION_RADIUS`, or `MAX_NUMBER_LENGTH`).
  This includes `history` directives counted per `task` block before deduplication, condition rules and location references counted before deduplication across one entity, and canonical output bounds.
  Measure text lengths under Section 2.8.

### 8.1 Synchronization Outcomes

These outcomes describe synchronization state and do not make a syntactically valid document invalid:

- `RecoveryRequired`: Preserve ambiguous local data or completion history that regresses below a proven baseline for explicit reconciliation.
- `DeletionConflict`: Require the user to choose Delete or Undelete for a deletion-versus-edit conflict (including direct non-cleanup edits to a deleted entity or newly introduced references to a concurrently deleted `label` or `location` under Section 6.8.2).
- `SyncGenerationRollback`: The shared deletion history generation is lower than the client's acknowledged generation.

While unresolved, these outcomes prevent publication and advancement of the acknowledged baseline.

### 8.2 Scheduling and Import Context Outcomes

- `TimeZoneContextRequired`: A local calendar operation lacks a configured zone or its applicable transition rules.
- `ImportContextRequired`: A historical timestamp or `0.6.0 -> 0.7.0` open `repeat` + `due` + finite `suspended < due` preparation-window conversion requires a time zone (`timeZone` / `sourceTimeZone`) that is not known.

These outcomes preserve input data and prevent the affected conversion, evaluation, or mutation.

## 9. Canonical Complete Example (`tiertask.tdf`)

```text
# ==========================================
# TierTask Data Format (TDF) Example Document
# ==========================================

tdf 0.7.0

deleted {
    generation 4
    task 6uCk8N0aB1 2026-11-01 12:00:00
    label 1rQv7S0cD2 2026-11-02 09:00:00
    location 8tYp4M0eF3 2026-11-02 10:15:00
}

queue {
    modified 2026-11-01 19:30:00
    task 8jKaCdOkD2
    task 5vWx9ZOk91
    task 3nQp7ROkB8
}

label 4x9p2mOkD2 {
    name     "Home & Garden"
    modified 2026-11-01 08:00

    condition {
        day      sat sun
        time     08:00 20:00
        location 7pQr9mOkD2
    }
}

label 9kLm2P0aBc scoped {
    name     "IT & Servers"
    color    "#2196F3"
    note     "Infrastructure runbooks and maintenance"
    modified 2026-11-01 08:00
    link     "Grafana Dashboard" "https://grafana.example.com/d/nas"
    link     "Runbook Repo" "https://git.example.com/ops/runbooks"

    condition {
        day  mon tue wed thu fri
        time 08:00 12:00
        time 14:00 18:00
    }
}

location 7pQr9mOkD2 {
    name        "Home"
    note        "Main residence driveway and garden"
    source      "Erfurt, Germany"
    coordinates 50.9787 11.0328
    radius      150
    modified    2026-11-01 08:00
}

# Unscheduled task in "Someday" (open task not listed in the 'queue' block; assigned only to
# scoped label '9kLm2P0aBc', so hidden from the unfiltered global view)
task 2bDf6HOkA4 {
    name     "Design 3D-printed enclosure for backup NAS"
    created  2026-11-01 12:00
    modified 2026-11-01 12:00
    labels   9kLm2P0aBc
}

# Scheduled prerequisite task in '4x9p2mOkD2' (listed in 'queue') with occurrence-scoped 'passive'
# deadline, deadline note, chronological 'history' entries, and 'condition any' override:
task 3nQp7ROkB8 {
    name      "Order replacement lawnmower blades online"
    created   2026-11-01 18:00
    modified  2026-11-01 18:20
    labels    4x9p2mOkD2
    due       2026-11-03 17:00:00 passive "Order before seasonal supplier cutoff"
    origin    "https://jira.example.com" "HOME-42"
    link      "Portal Login" "https://example.com/portal#login"
    link      "Local Folder" "file:///home/user/documents/tax2026"
    history   2026-11-01 18:05:00 "Checked blade part number against mower manual"
    history   2026-11-01 18:20:00 "Confirmed OEM stock with dealer"
    condition any
}

# Scheduled recurring task assigned to non-scoped '4x9p2mOkD2' and scoped '9kLm2P0aBc' with an
# explicit 5-day preparation lead window and persistent 'history' retained across cycles:
task 5vWx9ZOk91 {
    name        "Clean dust filters on home NAS server"
    created     2026-10-01 09:00
    modified    2026-11-01 10:00
    completions 1
    repeat      1 months 09:00 lead 5 days
    labels      4x9p2mOkD2 9kLm2P0aBc
    due         2026-12-01 18:00:00 "Verify SMART health after cleaning"
    history     2026-10-01 09:30:00 "Replaced front intake filter pad"
}

# Completed task (omitted from 'queue'; 'history' remains intact until > 30-day pruning)
task 7mPr4T09xY {
    name        "Mount winter tires"
    created     2026-10-20 14:00
    finished    2026-10-29 16:45
    modified    2026-10-29 16:45
    completions 1
    labels      4x9p2mOkD2
    history     2026-10-29 16:40:00 "Torqued lug nuts to 120 Nm"
}

# Scheduled prioritized task in '4x9p2mOkD2' (listed in 'queue') overriding only the 'time'
# condition group (narrowed to 09:00..18:00 while inheriting 'day sat sun' and 'location 7pQr9mOkD2'):
task 8jKaCdOkD2 priority {
    name      "Mow the lawn"
    note      "Check fuel level before starting"
    created   2026-11-01 19:30
    modified  2026-11-01 19:30
    labels    4x9p2mOkD2
    blocked   3nQp7ROkB8
    suspended 2026-11-04 23:00:00 "Wait for blade delivery and dry forecast"
    due       2026-11-07 16:00:00 "Before first frost"
    condition time 09:00 18:00

    subtasks auto-finish {
        step false "Get lawnmower from the shed"
        step true  "Empty grass catcher bag"
    }
}
```

## 10. Version Import and Implementation Migrations

This section contains historical compatibility rules.
Each migration entry describes changes from one version to its immediate successor.
An entry MUST describe file conversion and changes required in an existing implementation.
Do not duplicate complete historical specifications here.

### 10.1 Import Boundary and Migration Chain

- Normal loading MUST accept the current version (`0.7.0`) and MUST also accept `0.6.0`, `0.5.1`, and `0.5.0`, converting `0.6.0` documents in memory to `0.7.0` under Section 10.8, `0.5.1` documents through `0.5.1 -> 0.6.0 -> 0.7.0` under Sections 10.7 and 10.8, and `0.5.0` documents through `0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0` under Sections 10.6 through 10.8 without writing to storage during read-only loading.
- Importing older legacy versions (`0.2.0`, `0.3.0`, `0.4.0`) MUST be an explicit operation.
- Import and load-time conversion MUST validate the input against its declared source schema before applying migration rules.
  Use the immutable source references in Section 10.1.1.
- Import MUST apply adjacent migration steps in version order.
- A chained import MUST execute every intermediate step. It MUST NOT skip a version.
- Intermediate documents MAY remain in memory.
- A migration step or load-time conversion MUST NOT write files or communicate with storage.
- The import or load-time conversion operation MUST validate the complete result against the current (`0.7.0`) specification before use or persistence.
- A failed import or load-time conversion MUST leave stored source data and the active document unchanged.
- Import and load-time conversion MUST NOT trigger task completion, recurrence, retention pruning, wall-clock deferral expiry, or other unrelated mutations.
- Preserve fields and declaration order unless a migration entry explicitly requires a change.
- Migration errors MUST identify the source version, target version, and relevant source line.

For example, importing version `0.3.0` executes `0.3.0 -> 0.4.0`, followed by `0.4.0 -> 0.5.0`, followed by `0.5.0 -> 0.5.1`, followed by `0.5.1 -> 0.6.0`, followed by `0.6.0 -> 0.7.0`.
Do not define a separate `0.3.0 -> 0.7.0` transformation.
Future versions MUST add one adjacent migration entry and retain earlier entries.

#### 10.1.1 Historical Schema References

These immutable snapshots identify the source schemas used by the adjacent migration chain and load-time conversion.
Historical snapshots (`0.2.0` through `0.5.1`) reside at `TDF_SPEC.md` in their specified Git commits; specifications from `0.6.0` onward reside at `spec/TDF_SPEC_<version>.md` (current: `spec/TDF_SPEC_0.7.0.md`).
The blob identifier identifies that file's exact contents.

| Version | Git commit | Specification blob |
| --- | --- | --- |
| `0.2.0` | `e6e6f804608fb00466d265533130c407f114b53e` | `e66b5917be314cebbea02d4163987f13018d1f5a` |
| `0.3.0` | `ad4634a090a136b840a232f1830ef3fac3e8b6d4` | `562df38feb93009c15df998491536d8d44104e9d` |
| `0.4.0` | `73bc56a9cd6fb09828df7bb97353b71eee81ddcd` | `0fdc2ce15a72ba6288fcd59ef4e23ab419d749fb` |
| `0.5.0` | `e64e6a554bdbc2f6d5d76eacb900ae36d8c9b25b` | `8b492e7dfedea819ddeb9a2f0663d28fa8b08dfc` |
| `0.5.1` | `f22a3d4b1b15e9d8f5dcbba86da4f7dbd6135b11` | `1504ddff1ad9bd40930e4f90de8302336524f4dc` |
| `0.6.0` | `439d3fea7797520e69f67936bed93bc5f5064577` | `b53140b959d2ee1b1dfdab8f0edbb4a046858b5d` |

Use these snapshots for historical syntax, value domains, resource bounds (including `MAX_STMTS_PER_BLOCK = 512` for `0.2.0` through `0.6.0`), and schema validation.
Across all historical schemas (`0.2.0` through `0.6.0`) and current `0.7.0`, character length limits (`MAX_TEXT_LENGTH`, `MAX_NOTE_LENGTH`, `MAX_URI_LENGTH`) are measured in decoded Unicode scalar values (`U+0000..U+10FFFF` excluding UTF-16 surrogates) after unescaping, without applying Unicode normalization (`NFC` or `NFD`).
Do not execute historical load-time normalization, persistence, or synchronization behavior during source validation.
Section 10 defines the conversion operations and their order.
Do not substitute the current schema or an unversioned working copy for a historical source schema.
Distribute the referenced schemas with an importer or provide equivalent validators tied to these snapshots.

### 10.2 Migration Entry Requirements

Each entry MUST specify:

- Source and target versions.
- An immutable reference for each historical source and intermediate target schema.
- Required source validation.
- File conversions and preserved values.
- Changes required in an implementation of the source version.
- Result validation and verification cases.

The supported adjacent chain is `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1 -> 0.6.0 -> 0.7.0`.
Execute every intermediate step for older inputs.

A draft entry MUST identify unresolved conversion rules.
An unresolved entry MUST NOT be treated as an executable import specification.
For each unresolved rule, state the affected input, required decision, and acceptance cases needed to close it.
Distinguish complete conversion rules from verified implementation support.
Complete rules do not establish that an application implements or passes them.

### 10.3 Migration from 0.2.0 to 0.3.0

**Status:** Historical changes verified. This entry defines the adjacent timestamp conversion.

**File conversion:**

1. Validate the source using the `0.2.0` schema.
2. Obtain an explicit source time zone when local event timestamps require conversion.
3. Convert `created`, `queued`, and `finished` from source-local calendar values into UTC.
4. Apply Section 6.10.2 to ambiguous or nonexistent source-local times.
5. Preserve `suspended` as a local calendar value for the intermediate `0.3.0` document.
6. Preserve IDs, label assignments, prerequisites, conditions, checklist values, and declaration order.
7. Change the header to `tdf 0.3.0` and validate the intermediate document against that schema.

Do not invent repeat rules or modification timestamps from missing history.
Return `ImportContextRequired` when a necessary source zone is unknown.
Do not assume that the importing device uses the source zone.

**Implementation changes:**

- Store event timestamps in UTC and convert them for local display and input.
- Keep day/time conditions and intermediate deferrals in local time.
- Add optional `modified` timestamps to tasks and labels.
- Add monotonic entity revisions, entity merging, and baseline-aware deletion detection.
- Add the historical sequential-ID collision handling, which the next migration replaces.
- Add completion-relative repeats in days, weeks, and months with a maximum count of `3650`.
- Keep recurring tasks open, reset checklists, and schedule their next occurrence on completion.

The historical label fallback is `2026-11-01 08:00:00` UTC when `modified` is absent.
The following migration replaces that fallback behavior.

**Verification cases:**

- Convert date-only events from source-local midnight, including UTC dates on the preceding day.
- Use the applicable source-date offset across daylight-saving transitions.
- Preserve intermediate local deferrals without converting them prematurely.
- Preserve absent directives and source entity identities.
- Fail without writes when conversion context is missing.

The next step remains `0.3.0 -> 0.4.0`.

### 10.4 Migration from 0.3.0 to 0.4.0

**Status:** ID conversion specified. Historical implementation changes verified.

**File conversion:**

1. Validate the source using the `0.3.0` schema.
2. Preserve IDs that already match the 10-character Base62 format.
3. Convert other task and label IDs into canonical IDs.
4. Maintain separate task and label mappings. An identical source token can name different entities in these namespaces.
5. Rewrite `labels` through the label mapping and `blocked` through the task mapping.
6. Preserve references to missing prerequisites without creating task blocks.
7. Preserve remaining field values and declaration order.
8. Change the header to `tdf 0.4.0` after successful conversion.

Use the deterministic conversion in Sections 10.4.1 through 10.4.4.

#### 10.4.1 Source IDs and Reserved IDs

- Validate source IDs against `[A-Za-z0-9_-]+` before conversion.
- Treat source IDs as case-sensitive ASCII strings.
- Form each mapping key from the entity namespace and source ID.
- Use the exact namespace token `task` or `label`.
- Include declared task IDs, declared label IDs, and missing prerequisite IDs.
- Reuse the label mapping for `labels` references and the task mapping for `blocked` references.
- Collect every canonical ID from entity headers and reference arguments into one reserved set.
- Preserve all canonical IDs, including references to missing prerequisites.
- Collect each noncanonical mapping key exactly once.

The complete source identity set and reserved set determine collision handling.
Identical sets MUST produce identical mappings, regardless of declaration order, device time, or random state.
This algorithm preserves identities within one legacy dataset.
Matching source IDs from independent datasets do not establish shared entity identity.

#### 10.4.2 Candidate Derivation

For a noncanonical mapping key and attempt counter, construct these exact bytes:

```text
message = UTF8("TDF-ID-MIGRATION-1" + LF + namespace + LF + sourceId + LF + decimal(counter))
```

- Use `LF` as the single byte `0x0A`.
- Encode the counter as an unsigned decimal integer without leading zeros, except for `0`.
- Do not add a byte-order mark or trailing newline.
- Calculate the 32-byte SHA-256 digest of `message`.
- Interpret the digest as an unsigned integer in big-endian byte order.
- Reduce that integer modulo `839299365868340224`, which equals `62^10`.
- Encode the result using the Base62 alphabet from Section 2.8.
- Emit the most significant digit first and pad with `0` to exactly 10 characters.

```text
candidate = base62_10(unsigned_big_endian(SHA256(message)) mod 839299365868340224)
```

Imported IDs need not contain a rolling creation-time segment.
The generation algorithm for newly created entities does not apply to this conversion.

#### 10.4.3 Collision Handling and Reference Rewriting

1. Sort noncanonical mapping keys by namespace, then source ID, using ascending ASCII order.
2. Start the attempt counter at `0` for each key.
3. Derive the candidate using Section 10.4.2.
4. If the candidate is reserved, increment the counter and derive another candidate.
5. Accept the first unreserved candidate and add it to the reserved set.
6. Store that candidate in the mapping for the current key.
7. Reuse the stored mapping for every occurrence of that key.
8. After building all mappings, rewrite entity headers and their typed reference arguments.

Allow counters `0..255`, for at most `256` attempts per key.
If all candidates are reserved, fail with `MigrationIdentifierCollision`.
Report the affected namespace, source ID, and line of its first occurrence.
Do not change stored data after this failure.

Rewrite only task IDs, label IDs, `labels` arguments, and `blocked` arguments.
Do not replace matching text inside names, notes, links, checklist text, or comments.
Do not create an entity for a missing prerequisite.
Preserve event and modification timestamps.

#### 10.4.4 Normative ID Conversion Vectors

These vectors define candidate derivation before checking the reserved set:

| Namespace | Source ID | Counter | Candidate |
| --- | --- | ---: | --- |
| `label` | `home` | `0` | `e2Mz9WqsjC` |
| `label` | `t001` | `0` | `Nb0QaFXPe7` |
| `task` | `home` | `0` | `vK4z80gnew` |
| `task` | `t001` | `0` | `OaPtpMHEy3` |
| `task` | `t001` | `1` | `ohlr11vwDl` |
| `task` | `T001` | `0` | `mXscM7kwvs` |
| `task` | `gone` | `0` | `5OhMnA4x2F` |

For the sole mapping key `task/t001`, reserve only `OaPtpMHEy3`.
The result MUST be `ohlr11vwDl`.
Apply this reservation even when `OaPtpMHEy3` occurs only as a missing prerequisite reference.

Reordering declarations or repeating reference arguments MUST NOT change the mapping.
A missing prerequisite `gone` maps to `5OhMnA4x2F` when that candidate is unreserved.
It MUST remain a missing prerequisite after conversion.

**Implementation changes:**

- Replace unrestricted entity IDs with 10-character Base62 IDs.
- Add the six-character random segment and four-character rolling UTC seconds segment for new entity IDs.
- Replace root-header and reference validation with the Base62 entity schema.
- Remove sequential ID collision repair based on task names and creation timestamps.
- Add repeatable `link` directives and preserve their declaration order.
- Add URI validation, `EmptyText`, `InvalidUri`, `MAX_URI_LENGTH`, and `MAX_LINKS_PER_TASK`.
- Mark all checklist steps complete when completing a standard task.
- Lock completed checklist steps and mark newly added steps complete on completed tasks.
- Reset all checklist steps when restoring a completed task.
- Replace the fixed fallback for labels without `modified` with the synchronization-time behavior.
- Apply Section 10.1 to historical ID repair. Do not perform that repair during normal current-version loading.

**Verification cases:**

- Preserve existing canonical IDs without modification.
- Preserve label assignments and prerequisite targets after ID conversion.
- Keep task and label references distinct when their source tokens are identical.
- Preserve missing prerequisite references as missing references.
- Reject duplicate IDs and invalid source references before conversion.
- Validate the converted result against the target schema.

### 10.5 Migration from 0.4.0 to 0.5.0

**Status:** Conversion rules are complete for this working draft.
No unresolved conversion rules remain in this adjacent step.
Implementation conformance remains unverified.

**File conversion:**

1. Validate the source using the `0.4.0` schema.
2. Preserve every canonical entity ID and reference.
3. Handle any noncanonical IDs through explicit import conversion, never through normal current-version loading.
4. Preserve all remaining field values and declaration order.
5. Change the header to `tdf 0.5.0` after successful conversion.
6. Validate the complete result against the `0.5.0` specification.

Initialize task completion counters to `1` when `finished` is present, otherwise to `0`.
Emit positive counters and omit zero counters canonically.
Retain each source `blocked` ID as requirement `1` after ID conversion.
Do not infer historical recurring completions from schedules or checklist values.

Initialize the deletion history generation to `0` with no deletion records.
Do not invent historical deletions.
The empty generation-zero block may remain omitted.

For noncanonical source IDs, use Sections 10.4.1 through 10.4.4 within this migration step.
Do not execute the complete `0.3.0 -> 0.4.0` step for a `0.4.0` source.
Preserve canonical IDs and existing UTC event and modification timestamps.
Convert finite source-local `suspended` values into UTC using an explicit source time zone.
Resolve gaps and overlaps under Section 6.10.2.
Map the normalized indefinite sentinel `9999-12-31 23:59:00` to `suspended forever` without time-zone conversion.
For a recurring task with a finite deferral, preserve its explicit non-midnight source clock before converting the deadline.
An indefinite source deferral supplies no recurrence clock.
Use the default midnight repeat clock when the source has no such clock.
Do not derive a repeat clock from `queued` or rewrite that existing UTC timestamp.
Return `ImportContextRequired` if a necessary source zone is unknown.
Do not guess it from the importing device or a current UTC offset.
Build the shared queue from all source tasks with `queued` present and `finished` absent, including blocked tasks.
Order prioritized tasks first, then regular tasks.
Within each group, use ascending source UTC `queued`, then source task declaration order for ties.
This preserves the source's effective queue order without changing timestamps.
Initialize a nonempty queue revision to the greatest effective revision of its member tasks under Section 6.7.1.
With no members, use the implicit empty epoch queue.
Do not infer desired order from later source timestamps or undo historical timestamp shifts.
Do not add per-field timestamps or baseline directives to the migrated document.
Invalidate client baselines bound to another format version.
Establish a new baseline after successfully acknowledging the target document.

Apply the target calendar, scalar-value text limits, and entity-wide condition limit during result validation.
A source-valid document can exceed a target bound or contain an unsupported target timestamp.
Return `LimitExceeded` or `InvalidTimestamp`, respectively.
Preserve the source and active document.
Do not truncate text, discard condition rules, or clamp timestamps to make the import succeed.
Validate canonical output under Section 7.1 before persistence.
Import retains each converted deferral and does not perform restoration under Section 6.5.

**Implementation changes:**

- Separate normal loading from explicit import.
- Restrict normal parsing to the current version.
- Reject noncanonical entity IDs with `InvalidIdentifier`.
- Remove ID generation, reference repair, and persistence from normal loading.
- Generate random IDs for newly created entities only.
- Convert noncanonical source IDs through the deterministic import mapping.
- Keep migration steps separate and execute them in version order.
- Store one durable common baseline for the dataset and format version.
- Merge scalar metadata, reference sets, conditions, links, and task state using the units in Section 6.7.5.
- Use the deterministic complete entity winner for true unit conflicts and missing baselines.
- Replace incoming-side tie-breaking with the payload comparison order in Section 6.7.3.
- Preserve revisions when reusing existing versions.
- Create one entity revision when the merge produces a new payload.
- Replace synchronization-time fallback values for unstamped labels with the fixed UTC epoch.
- Validate the complete merged document before publication.
- Advance the baseline only after a successful shared result.
- Add the shared deletion block, 30-day record retention, and guarded deletion history generation updates.
- Store the acknowledged deletion history generation alongside the baseline.
- Refresh and reconcile clients after deletion history expires.
- Preserve ambiguous local entities for explicit recovery with new IDs.
- Require a user decision for deletion-versus-edit conflicts.
- Apply Delete or Undelete as a new entity revision.
- Add completion counters and numbered prerequisite references under Section 6.9.
- Keep completion progress and prerequisite requirements in one occurrence state during synchronization.
- Prefer greater completion progress over stale occurrence state.
- Store finite deferrals in UTC and evaluate them against the UTC reference instant.
- Add the explicit `forever` deferral value and optional local repeat clock.
- Resolve local calendar targets with their target-date zone rules.
- Preserve intended repeat clocks across gaps, overlaps, and manual deferrals.
- Separate shared queue order from task activation timestamps under Sections 4.6 and 6.11.
- Filter blocked tasks before assigning bounded Focus and Ready slots.
- Restore a released task's saved position and recalculate displaced tasks.
- Replace timestamp shifts with explicit queue moves.
- Merge the complete queue list and reconcile membership after entity merging.
- Preserve completion checkpoints in task deletion records.
- Preserve the original identity during Undelete and advance the history generation when retiring its record.
- Enforce the combined condition limit across all forms within each task or label.
- Validate canonical output bounds before publication.
- Apply the explicit Gregorian timestamp range and Unicode scalar-value text limits.
- Accept Unicode whitespace inside comments while retaining encoding and control-character checks.
- Distinguish timestamp clocks from deletion checkpoints under the formal grammar.
- Treat empty condition groups as satisfied under Section 4.4.4.
- Clear old deferrals during restoration under Section 6.5 without resetting completion history or the repeat clock.

**Verification cases:**

- Loading a current document preserves every valid ID and reference.
- Loading a current document with ID `t001` fails with `InvalidIdentifier` and performs no writes.
- Loading an older version through the current parser fails with `UnsupportedVersion`.
- Explicit import executes every required adjacent step.
- Failed conversion or target validation leaves stored source data unchanged.
- Preserve independent metadata edits through a common baseline.
- Preserve complete task state during completion and recurrence conflicts.
- Resolve equal revision timestamps identically in both merge directions.
- Retain the complete winner when a common baseline is unavailable.
- Reject merged dependency cycles and preserve both inputs.
- Keep unchanged merge revisions stable.
- Parse and serialize one deletion block with canonical IDs and UTC record timestamps.
- Keep deletion records at exactly 30 days and expire them only after that boundary.
- Commit record removal and generation advancement atomically.
- Preserve a nonzero generation after the last record expires.
- Refresh older clients and preserve ambiguous pending changes for explicit recovery.
- Detect generation rollback and preserve both versions.
- Require explicit Delete or Undelete when deletion conflicts with an edit.
- Preserve the original identity and edited payload after Undelete.
- Propagate Undelete through a guarded generation change.
- Request a new decision when the reviewed conflict versions change.
- Preserve one fulfilled prerequisite occurrence across later cycles.
- Capture fresh prerequisites for each new recurring dependent occurrence.
- Prevent command retries and concurrent completion reports from counting one occurrence twice.
- Preserve task completion checkpoints through Delete and Undelete.
- Verify queue release, displacement, priority, context filtering, and concurrent additions under Section 6.11.3.
- Preserve the legacy effective queue order during adjacent migration.
- Verify the conversion vectors in Section 6.10.4.
- Preserve UTC deadlines across device-zone changes and daylight-saving rollback.
- Convert historical local deferrals with an explicit source zone.
- Import indefinite sentinels without date-range overflow.
- Validate each historical source and intermediate target against its pinned schema from Section 10.1.1.
- Reject a source entity with 600 condition rules under the target limit without dropping rules or writing data.
- Reject out-of-range converted timestamps without clamping.
- Verify target text bounds using Unicode scalar values, including supplementary characters and combining marks.
- Preserve converted deferrals during import. Clear them only during an explicit later restoration.
- Verify canonical output, lexical boundaries, and condition evaluation under Section 7.2.

Before claiming implementation conformance, execute all verification cases required by this step and its referenced sections.
Add any newly discovered conversion ambiguity here before treating affected inputs as supported.
Mark the affected rule unresolved until its conversion and acceptance cases are specified.

The next step in the adjacent migration chain is `0.5.0 -> 0.5.1` (Section 10.6).

### 10.6 Migration and Load-Time Conversion from 0.5.0 to 0.5.1

**Status:** Conversion rules are complete for this working draft.
No unresolved conversion rules remain in this adjacent step.
Implementation conformance remains unverified.

**Scope (Load-Time Conversion & Import Chain):**
- A `0.7.0`, `0.6.0`, or `0.5.1` reader MUST accept `tdf 0.5.0` documents directly during normal loading and convert them in memory to `0.5.1` (followed by `0.5.1 -> 0.6.0` under Section 10.7 and `0.6.0 -> 0.7.0` under Section 10.8 on a `0.7.0` reader) without writing to storage during read-only loading.
- An explicit import of `0.2.0`, `0.3.0`, or `0.4.0` executes `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0` followed by this `0.5.0 -> 0.5.1` step, `0.5.1 -> 0.6.0` (Section 10.7), and `0.6.0 -> 0.7.0` (Section 10.8).

**File and in-memory conversion:**

1. Validate the source using the `0.5.0` schema (Section 10.1.1).
   In a valid `0.5.0` document, the `queue` block already contains all live open tasks (`finished` absent) that have a `queued` directive, in their saved queue order.
2. If an intermediate migration step or hand-edited `0.5.0` input omitted an explicit `queue` block while containing open tasks with `queued` present, construct `queue` by ordering prioritized open `queued` tasks first, then regular open `queued` tasks, sorted within each group by ascending UTC `queued` timestamp and then source declaration order for ties, with `queue.modified` set to the greatest `0.5.0` effective revision (`max(created, queued, finished)` when `modified` is absent) among those queued tasks (or `1970-01-01 00:00:00` UTC when no scheduled open tasks exist).
3. For each `task` block in the `0.5.0` document:
   - If `modified` is omitted and `queued` is present with a UTC timestamp strictly greater than `created` (and `finished`, when present), set `task.modified` to that `0.5.0` effective revision (`max(created, queued, finished)`) so no historical revision ordering is lost when `queued` is removed.
   - Strip the `queued` directive from the `task` block.
   - Open tasks (`finished` absent) whose task ID is listed in `queue` remain scheduled in their exact `queue` order.
   - Open tasks (`finished` absent) whose task ID is not listed in `queue` remain unscheduled (`Someday` under Section 5.3, or `Blocked` under Section 5.4 if an active `suspended` lock is present).
   - Completed tasks (`finished` present) have their `queued` directive stripped and remain excluded from `queue`.
4. Preserve all entity IDs, `deleted` records and generation, `queue` order and `queue.modified`, `label` blocks, completion counters, prerequisites, deferrals, recurrence rules, links, conditions, and checklists.
5. Upgrade the document version header to `tdf 0.5.1` and validate the intermediate result against the `0.5.1` specification before executing `0.5.1 -> 0.6.0` (Section 10.7).

**Implementation changes:**

- Update canonical serialization to omit `queued`.
- Accept `tdf 0.5.0` during normal loading and convert `0.5.0` documents in memory without performing disk writes during read-only loading.
- Reject `queued` inside `task` blocks in `tdf 0.5.1`, `0.6.0`, and `0.7.0` documents with `UnknownDirective` (Section 8).
- Derive 6-tier scheduling status (`Focus`, `Ready`, `Planned`, `Blocked` vs. `Someday`) strictly from membership in `queue` and active `suspended` locks (Section 5).
- Update task creation, `Someday` scheduling/unscheduling, downgrading, completion, recurrence rescheduling, restoration, and `suspended` mutations to operate on `queue` and `queue.modified` without `queued` (Section 6).
- Update the omitted `task.modified` fallback formula to `max(created, finished)` (Section 6.7.1) and remove `queued` from the task occurrence state tuple (Sections 6.7.3 and 6.7.5).
- Merge `Someday` <-> scheduled transitions via `queue` membership and `queue.modified`, and normalize the merged `queue` by removing any completed (`finished`) or tombstoned (`deleted`) task IDs (Section 6.11.2).

**Verification cases:**

- Loading a valid `tdf 0.5.0` document succeeds, strips `queued` from all tasks in memory, preserves `queue` membership and order, and performs no storage writes during read-only loading.
- Loading a `tdf 0.5.1`, `0.6.0`, or `0.7.0` document containing a `queued` directive inside a `task` block fails with `UnknownDirective`.
- Chained import of `0.2.0`, `0.3.0`, and `0.4.0` documents executes through `0.5.0 -> 0.5.1`, populates `queue` from legacy `queued` open tasks, preserves fallback `task.modified` timestamps when `queued > created`, omits completed and unqueued tasks from `queue`, and strips all `queued` directives before executing `0.5.1 -> 0.6.0` and `0.6.0 -> 0.7.0`.

The next step in the adjacent migration chain is `0.5.1 -> 0.6.0` (Section 10.7).

### 10.7 Migration and Load-Time Conversion from 0.5.1 to 0.6.0

**Status:** Conversion rules are complete for this working draft.
No unresolved conversion rules remain in this adjacent step.
Implementation conformance remains unverified.

**Scope (Load-Time Conversion & Import Chain):**
- A `0.7.0` or `0.6.0` reader MUST accept `tdf 0.5.1` documents directly during normal loading (and `tdf 0.5.0` documents after in-memory `0.5.0 -> 0.5.1` conversion under Section 10.6) and convert them in memory to `0.6.0` (followed by `0.6.0 -> 0.7.0` under Section 10.8 on a `0.7.0` reader) without writing to storage during read-only loading.
- An explicit import of `0.2.0`, `0.3.0`, `0.4.0`, or `0.5.0` executes through this `0.5.1 -> 0.6.0` step before `0.6.0 -> 0.7.0` (Section 10.8).

**File and in-memory conversion:**

1. Validate the source using the `0.5.1` schema (Section 10.1.1).
   In `0.5.1`, `location` condition rules inside `task` and `label` blocks use the inline numeric form `location <latitude> <longitude> <radius>`.
2. Collect every canonical ID already present in the `0.5.1` document (`task` IDs, `label` IDs, `deleted` record IDs, and missing prerequisite `<task-id>` references) into the reserved ID set under Section 10.4.1.
3. Scan all `location <latitude> <longitude> <radius>` condition rules across all `label` and `task` blocks in the `0.5.1` document:
   - Count every inline `location` rule on each `task` or `label` before deduplication toward `MAX_LOCATION_REFS_PER_ENTITY` (`63`), failing with `LimitExceeded` if any single entity has more than `63` `location` rules.
   - Validate that each raw `<latitude>`, `<longitude>`, and `<radius>` token is a finite ASCII decimal literal (`-?[0-9]+(\.[0-9]+)?`) of at most `MAX_NUMBER_LENGTH` (`24`) ASCII characters, failing with `LimitExceeded` if any token exceeds `24` ASCII characters or `InvalidNumber` if non-finite or malformed before rounding.
   - Validate `<latitude>` in `[-90.0, 90.0]`, `<longitude>` in `[-180.0, 180.0]`, and `<radius>` in `(0.0, 100_000.0]`, failing with `InvalidNumber` or `LimitExceeded` (`radius > 100_000`) if out of bounds.
   - Exclusively during `0.5.1 -> 0.6.0` migration, round `<latitude>` and `<longitude>` to at most 6 fractional digits and `<radius>` to at most 2 fractional digits using `half-away-from-zero` rounding, then normalize each decimal value under Section 6.7.3 (`-0.0` normalized to `0`, trailing fractional zeros stripped, and a trailing decimal point stripped when all fractional digits are zero) to produce `<normalizedLat>`, `<normalizedLon>`, and `<normalizedRadius>`.
   - If `<normalizedRadius>` rounds to `0` (such as a `0.5.1` rule with `radius 0.004`), fail the migration with `InvalidNumber` without clamping.
   - Form the canonical deduplication key `sourceId = "<normalizedLat>:<normalizedLon>:<normalizedRadius>"`.
4. Enforce the document-wide `0.6.0` location bound on the collected keys before synthesizing blocks:
   - If the document contains more than `MAX_LOCATIONS` (`200`) distinct location keys across all entities, fail with `LimitExceeded`.
5. Sort all distinct location keys (`sourceId`) in ascending ASCII order and derive a deterministic 10-character Base62 `<location-id>` for each key using the candidate derivation and collision-handling algorithm from Sections 10.4.2 and 10.4.3 with `namespace = "location"` and `sourceId = "<normalizedLat>:<normalizedLon>:<normalizedRadius>"`:
   ```text
   message = UTF8("TDF-ID-MIGRATION-1" + LF + "location" + LF + "<normalizedLat>:<normalizedLon>:<normalizedRadius>" + LF + decimal(counter))
   ```
   Two devices migrating the same `0.5.1` document offline therefore derive identical `<location-id>`s and merge without duplicate `location` blocks.
6. For each distinct location key, synthesize a root-level `location <location-id>` block with:
   - `name "Location (<normalizedLat>, <normalizedLon>, <normalizedRadius>m)"`
   - `coordinates <normalizedLat> <normalizedLon>`
   - `radius <normalizedRadius>`
   - `note`, `source`, and `modified` omitted (falling back to the fixed UTC epoch `1970-01-01 00:00:00` under Section 6.7.1).
7. In every `label` and `task` block that contained one or more inline `location <latitude> <longitude> <radius>` condition rules, replace those inline rules with a single coalesced `location <loc-1> [<loc-2> ...]` condition rule whose `<location-id>` arguments are deduplicated in first-seen declaration order across the entity.
   Preserve `location any` rules on `task` blocks unchanged.
8. Preserve all `task` and `label` identities, revisions, attributes, `queue` membership and order, and `deleted` records and generation.
9. Upgrade the document version header to `tdf 0.6.0`, order root-level blocks and entity directives canonically under the `0.6.0` schema (Section 10.1.1), and validate the intermediate result against the `0.6.0` specification before executing `0.6.0 -> 0.7.0` (Section 10.8).

#### 10.7.1 Normative Location ID Conversion Vectors

These vectors define candidate `<location-id>` derivation under Section 10.4.2 (`namespace = "location"`) before checking the reserved set:

| Source coordinates (`lat`, `lon`, `radius`) | Normalized `sourceId` | Counter | Candidate `<location-id>` | Synthesized `location.name` |
| --- | --- | ---: | --- | --- |
| `50.978700`, `11.032800`, `150.00` | `50.9787:11.0328:150` | `0` | `5473OnNDhL` | `"Location (50.9787, 11.0328, 150m)"` |
| `50.978700`, `11.032800`, `150.00` | `50.9787:11.0328:150` | `1` | `5qLZ0E0s4Y` | `"Location (50.9787, 11.0328, 150m)"` |
| `52.520000`, `13.405000`, `250` | `52.52:13.405:250` | `0` | `9HSso0GjnR` | `"Location (52.52, 13.405, 250m)"` |
| `48.1371544`, `11.5761245`, `75.500` | `48.137154:11.576125:75.5` | `0` | `AU9Mg5SPW1` | `"Location (48.137154, 11.576125, 75.5m)"` |

**Implementation changes:**

- Update `0.6.0` serialization to emit `tdf 0.6.0`, the 6-section root-block order (`deleted`, `queue`, ASCII-sorted `label`s, ASCII-sorted `location`s, ASCII-sorted `task`s), the 6-position `location` directive order, and the 15-position `0.6.0` `task` directive order with `due` at position 11 and `origin` at position 12.
- Add root-level `location <id>` blocks, `deleted` `location` tombstones, ID-referenced `condition location <loc-1> [<loc-2> ...]`, `UnknownLocationReference`, `MAX_LOCATIONS = 200`, `MAX_LOCATION_RADIUS = 100_000`, `MAX_LOCATION_REFS_PER_ENTITY = 63`, and `MAX_NUMBER_LENGTH = 24`.
- Add the optional `scoped` header flag on `label` blocks, global-view visibility and condition evaluation exclusions for `scoped` labels (Sections 4.2, 4.4.3, and 5.1), and post-merge `scoped` label deletion queue eviction (Section 6.7.8).
- Add the optional non-blocking `due` timestamp and `origin "<namespace>" "<external-key>"` directive on `task` blocks (Sections 4.1.2 and 5).
- Update `Focus -> Ready` downgrade queue anchoring to position the downgraded task relative to the active filter's eligible sequence $E_{\text{ctx}}$ (Section 6.3).
- Update synchronization to bind `sourceDigest` and execute the bounded CAS-merge loop (`MAX_CAS_RETRIES = 3`), coupled `(coordinates, source)` location merging, atomic `origin` pair merging, pre-merge tombstone stripping and commutative `W`-anchored `locationGroup` merging, two-level occurrence unbundling, `blocked` map merging, step-wise `subtasks` merging, `label`-before-`task` `location` deletion cascades with `location any` inheritance-trap protection, 30-day `task` tombstone expiry `blocked` cleanup, and `DeletionConflict` detection on newly introduced references (Sections 6.7 and 6.8).

**Verification cases:**

- Loading a valid `tdf 0.5.1` document with inline `location 50.9787 11.0328 150` rules on both a `label` and a `task` synthesizes a single `location 5473OnNDhL` block with `name "Location (50.9787, 11.0328, 150m)"` and rewrites both rules to `location 5473OnNDhL` without writing to storage during read-only loading.
- Loading a `0.5.1` document whose inline coordinate has `7` fractional digits (`48.1371544 11.5761245 75.500`) rounds `half-away-from-zero` to `48.137154 11.576125 75.5` during migration and derives `<location-id>` `AU9Mg5SPW1`, whereas a native `0.6.0` or `0.7.0` document with `7` coordinate fractional digits fails with `InvalidNumber`.
- Loading a `0.5.1` document whose inline `location` coordinate or radius token exceeds `24` ASCII characters fails with `LimitExceeded` before rounding.
- Loading a `0.5.1` document whose inline `radius` rounds to `0` (`0.004`) fails with `InvalidNumber`.
- Loading a `0.5.1` document with more than `200` distinct inline locations across the document or more than `63` inline `location` rules on one entity (counted before deduplication) fails with `LimitExceeded`.
- Chained import of `0.2.0`, `0.3.0`, `0.4.0`, and `0.5.0` documents executes through `0.5.1 -> 0.6.0` before executing `0.6.0 -> 0.7.0` (Section 10.8).

The next step in the adjacent migration chain is `0.6.0 -> 0.7.0` (Section 10.8).

### 10.8 Migration and Load-Time Conversion from 0.6.0 to 0.7.0

**Status:** Conversion rules are complete for this working draft.
No unresolved conversion rules remain in this adjacent step.
Implementation conformance remains unverified.

**Scope (Load-Time Conversion & Import Chain):**
- A `0.7.0` reader MUST accept `tdf 0.6.0` documents directly during normal loading (as well as `tdf 0.5.1` and `tdf 0.5.0` documents after in-memory `0.5.0 -> 0.5.1 -> 0.6.0` conversion under Sections 10.6 and 10.7) and convert them in memory to `0.7.0` without writing to storage during read-only loading.
- An explicit import of `0.2.0`, `0.3.0`, `0.4.0`, `0.5.0`, `0.5.1`, or `0.6.0` executes the adjacent chain through this `0.6.0 -> 0.7.0` step.

**File and in-memory conversion:**

1. Validate the source using the `0.6.0` schema (Section 10.1.1):
   - Enforce `MAX_STMTS_PER_BLOCK = 512` on ordinary blocks in the `0.6.0` source (`LimitExceeded` if an ordinary block in a `0.6.0` document exceeds `512` direct child statements).
   - Reject `history` inside `task` blocks and `link` inside `label` blocks in `0.6.0` source documents with `UnknownDirective` (just as `0.5.0` and `0.5.1` additionally reject `due` and `origin` with `UnknownDirective`).
   - Reject `0.7.0` modifier and note extensions in `0.6.0` source documents (`repeat` with `lead` at token `3` fails with `InvalidTime`, and `>= 4` tokens fail with `UnexpectedToken`; `suspended` and `due` with `2`-token modifier or note forms fail with `InvalidTimestamp`, and `>= 3`-token forms fail with `UnexpectedToken`).
2. Initialize all newly introduced `0.7.0` optional fields losslessly on converted blocks:
   - On every `label` block, initialize `link` to the empty list `[]`.
   - On every `task` block, initialize `history` to the empty list `[]`, `suspended` `<note>` to absent, `due` `passive` to `false` (omitted), and `due` `<note>` to absent.
3. **Unified Wall-Clock-Free Preparation-Window & Wake-Up Clock Extraction (`open` `repeat` + `due` + Finite `suspended < due`):**
   To prevent silent loss of recurring preparation windows when an existing `0.6.0` workspace is loaded directly and subsequently cleaned and saved as `tdf 0.7.0` during synchronization, **both** read-only load-time conversion (`0.6.0 -> 0.7.0`) and explicit `0.6.0 -> 0.7.0` migration MUST execute the identical wall-clock-free `timeZone` / `sourceTimeZone` extraction:
   - If one or more open `task` blocks (`finished` omitted) in the `0.6.0` document carry `repeat`, `due`, and a finite UTC `suspended` timestamp with `suspended < due`, require an available IANA `timeZone` / `sourceTimeZone` (`ImportContextRequired` when omitted or unavailable; documents without any such open task convert without requiring a time zone, initializing `leadDays = 0` on all `repeat` rules).
   - For each open `task` block carrying `repeat`, `due`, and finite `suspended < due`, convert `suspended` and `due` from UTC into local calendar dates and wall-clock times in `timeZone` / `sourceTimeZone`:
     - Let $D = (\text{dueLocalDate} - \text{suspendedLocalDate})$ in calendar days.
     - If $D \ge 1$, set `leadDays = min(D, 3650)` (`lead <leadDays> days`); otherwise set `leadDays = 0`.
     - If $D \ge 0$ (including same-day $D = 0$ with `suspended < due`) and `repeat`'s `<repeat-time>` was `00:00:00` while `suspended` had a non-midnight local wall-clock time, copy `suspended`'s local wall-clock time into `<repeat-time>`.
   - Closed tasks (`finished` present) and open tasks without `repeat`, without `due`, with `suspended forever`, or with `suspended >= due` initialize `leadDays = 0` and preserve `<repeat-time>` unchanged.
4. **Read-Only Load-Time Preservation vs. Explicit Migration Cleanup:**
   - **During read-only load-time conversion:** Preserve every task's stored `suspended`, `blocked`, and `modified` directives verbatim in memory so `sourceDigest` (Section 6.7.2) and baseline decoding remain exact and completely independent of wall-clock time `now` (expired `suspended <= now` and resolved `blocked` entries are subsequently cleaned during guarded refresh/synchronization or committed mutations under Sections 6.6 and 6.7.8, with `repeat ... [<repeat-time>] [lead <leadDays> days]` already preserved).
   - **During explicit `0.6.0 -> 0.7.0` file migration:** Keep the conversion strictly wall-clock-free per Section 10.1 (never stripping finite `suspended` by wall-clock time), clear any legacy `suspended` or `blocked` directives on `Completed` tasks (`finished` present), and strip `blocked <target-id>[:<req>]` entries on open tasks that are already deterministically resolved in the source snapshot (`<target-id>` present in `deleted` tasks, or `<target-id>` present as a live task with `target.completions >= req` and either `dependent.repeat` or `target.repeat` omitted), omitting `blocked` when empty while preserving source timestamps.
5. Preserve all entity identities, `deleted` records and generation, `queue` membership, order, and `queue.modified`, `location` blocks, `label` attributes, completion counters, remaining prerequisites, deadlines, origins, links, conditions, and checklists.
6. Upgrade the document version header to `tdf 0.7.0`, order root-level blocks and entity directives canonically under Section 7.1, and validate the complete result against the `0.7.0` specification.

**Implementation changes:**

- Update canonical serialization to emit `tdf 0.7.0`, the 6-position `label` directive order (`link` at position `5`, `condition` at position `6`), and the 16-position `task` directive order (`history` at position `14` between `link` at `13` and `condition` at `15`, `subtasks` at `16`), and raise `MAX_STMTS_PER_BLOCK` from `512` to `1_024` for `0.7.0` documents while keeping `512` for `< 0.7.0` source validation (Sections 4.1.2, 4.2, 7, and 7.1).
- Add repeatable `link "<title>" "<uri>"` directives on `label` blocks (`0..MAX_LINKS_PER_LABEL = 20`) with identical lexical and URI scheme validation to `task.link`, and merge `label.link` as an atomic ordered list in `Label payload` (Sections 4.2, 6.6, 6.7.3, and 6.7.5).
- Derive effective priority `hasEffectivePriority(T, now, W_due)` (`DEFAULT_DUE_LEAD_SECONDS = 86_400`, optional `due ... passive` occurrence-scoped opt-out) during read-only Section 5.5 evaluation without mutating stored task flags, and update context-relative downgrades (`Section 6.3`), deadline edits (`Section 6.6`), restoration (`Section 6.5`), and Mode 2 recurrence (`Section 6.10.3`) to manage `passive` deterministically.
- Strip expired finite `suspended <= now` (with its note) and resolved `blocked` entries (`<target-id>` in `deleted` tasks, or live `target.completions >= req` with `dependent.repeat` or `target.repeat` omitted) from open tasks during committed mutations and guarded refresh/synchronization (while keeping raw parsing and read-only evaluation mutation-free), clear `suspended` and `blocked` on standard task completion (`Section 6.4`), and replace `0.6.0`'s `oldSuspended < oldDue` Mode 2 recurrence heuristic with explicit `repeat ... [lead <lead-count> days]` (`1..MAX_REPEAT_COUNT = 3_650`, omitting `suspended` immediately when `newSuspended <= now` under Section 6.10.3).
- Add optional trailing quoted `"<note>"` arguments (`1..MAX_NOTE_LENGTH = 2_000`) on `suspended` and `due` with strict parent-directive ownership, lifecycle clearing/preservation rules, diagnostic redaction, and atomic `(isForever, utcComponents, optionalNote)` / `(utcComponents, passive, optionalNote)` merge units (Sections 4.1.2, 6.2–6.6, 6.7.3, and 6.7.5).
- Add repeatable `history <timestamp> "<text>"` directives (`0..MAX_HISTORY_PER_TASK = 500` counted before deduplication, `1..MAX_TEXT_LENGTH = 500` single-line `<text>`) on `task` blocks with chronological + UTF-8 byte-order deduplicated canonical serialization, permanent retention across completion, recurrence, queue moves, and restoration, passive plain-text and diagnostic-redaction guarantees, and occurrence-independent `(timestampUtc, text)` set reconciliation outside `Task state` across both Case 1 and Case 2 (and baseline-free two-way union) without silent merge truncation (Sections 4.1.2, 5.2, 6.4–6.7.9, and 6.9.5).
- Update synchronization (`Sections 6.7.5, 6.7.6, 6.7.8, 6.8.2, and 6.8.4`) with Case 2 `suspended <= now` and `V.repeat`-aware `blocked` pre-normalization, stage-fair deferred cleanup in multi-stage sync, 3-step `M_clean` vs. `M_uncleaned` revision selection, open-task baseline-cleanup normalization for `DeletionConflict` and `RecoveryRequired`, and removal of `blocked` references to discarded non-recovered tasks during generation recovery.

**Verification cases:**

- Loading a valid `tdf 0.6.0`, `0.5.1`, or `0.5.0` document without open `repeat` + `due` + finite `suspended < due` tasks succeeds without requiring a `timeZone` parameter, initializes `label.link = []`, `task.history = []`, `passive = false`, `leadDays = 0`, and scheduling notes = absent, preserves `sourceDigest` and task fields verbatim in memory, and performs no storage writes during read-only loading.
- Loading or explicitly migrating a `0.6.0` document containing an open task with `repeat 1 months`, `due 2026-10-15 16:00:00` (`18:00` `Europe/Berlin`), and `suspended 2026-10-10 06:00:00` (`08:00` `Europe/Berlin`) fails with `ImportContextRequired` when `timeZone` / `sourceTimeZone` is omitted, and extracts `repeat 1 months 08:00 lead 5 days` when `Europe/Berlin` is provided (so subsequent sync cleanup of expired `suspended` preserves the 5-day preparation lead window and `08:00` wake-up clock).
- Loading a `0.6.0` document with `513` direct child statements in a `task` block fails with `LimitExceeded` under the `0.6.0` source bound (`512`), whereas a `0.7.0` document accepts up to `1_024` direct child statements per ordinary block.
- Loading a `0.2.0`–`0.6.0` document containing `history` inside `task` or `link` inside `label` fails with `UnknownDirective`, and loading a `0.5.0` or `0.5.1` document containing `due` or `origin` fails with `UnknownDirective`.
- Explicit `0.6.0 -> 0.7.0` migration strips deterministically resolved one-shot/deleted `blocked` entries on open tasks and `suspended`/`blocked` on `Completed` tasks without stripping finite `suspended` by wall-clock time, and chained import of `0.2.0` through `0.6.0` produces a valid canonical `tdf 0.7.0` document.

### 10.9 Migration from the Initial Draft

The repository also contains the unfinished, headerless `0.1.0-draft`.
Its adjacent migration to `0.2.0` remains under review.
Source-version identification and category/location mappings require explicit rules.
Do not guess a version for headerless files or skip that undocumented step.
