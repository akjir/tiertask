# TierTask Data Format (TDF) Specification

**Version:** 0.2.0
**Status:** Specification
**File Extension:** `.tdf`
**Character Encoding:** UTF-8

## 1. Overview, Architecture & Design Goals

The TierTask Data Format (`TDF`) is a deterministic, line-oriented, block-based plain-text data format for representing tasks, checklists, dependencies, label contexts, activation conditions, and scheduling states. It combines human readability in standard text editors with structured `{ ... }` blocks and single-line directives.

### 1.1 Core Philosophy: Data vs. View Separation

A `.tdf` document stores exclusively objective facts: tasks (`task`), labels (`label`), timestamps (`created`, `queued`, `finished`, `suspended`), dependencies (`blocked`), checklists (`subtasks`), and activation conditions (`condition` rules for `day`, `time`, and `location`).

1. **No Explicit Tier Storage:** Unlike positional list formats, a `.tdf` document does NOT store an explicit tier assignment (`[1]` through `[6]`) on any task.
2. **Dynamic Derivation ($O(N)$ Pipeline):** The six operational tiers (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, and `Completed`) are derived deterministically from the stored task and label attributes via a single-pass $O(N)$ filtering, sorting, and slicing pipeline (see Section 5).

### 1.2 Core Design Principles

1. **Mandatory Version Header & Strict Root Block Enforcement:** Every valid `.tdf` document MUST begin with the single-line version header `tdf 0.2.0` at nesting depth `0` before any root block, making it the only directive allowed at depth `0`. Following the version header, every top-level statement at nesting depth `0` MUST be a root block (`task` or `label`); all other standalone directives at the root level are forbidden.
2. **No Empty Directives:** Optional directives that have no value (such as an unset `finished` or `queued` timestamp) MUST be omitted entirely from the block rather than written with empty arguments.
3. **Single-Pass Linear Grammar:** TDF is designed to be tokenized and parsed in a single $O(N)$ linear pass without regular expressions or backtracking.
4. **Two-Layer Validation (Syntax vs. Domain Semantics):** At the lexical and structural layer, all identifiers and arguments are scanned as UTF-8 string tokens. Semantic validation (format version header, ISO-8601 timestamps, 24-hour time windows, weekday tokens, boolean literals, geographic coordinates and radii, hexadecimal color codes, and cross-block identifier references) is enforced deterministically by the domain schema layer.

## 2. Lexical Elements

### 2.1 Character Encoding
- A TDF document MUST be a valid UTF-8 byte sequence.
- Invalid UTF-8 byte sequences, null bytes (`U+0000`), and ASCII control characters (`U+0001`–`U+001F` and `U+007F`, except horizontal tab `U+0009`, line feed `U+000A`, and carriage return `U+000D` as specified below) MUST be rejected before or during scanning (`UnexpectedToken`).
- A conforming scanner MUST respect UTF-8 character boundaries at all times.

### 2.2 Whitespace
Horizontal whitespace separates tokens within a single line and is otherwise insignificant outside of quoted strings.
- **Allowed horizontal whitespace characters:**
  - ASCII Space (`U+0020`, `' '`)
  - ASCII Horizontal Tab (`U+0009`, `'\t'`)
- Other Unicode whitespace characters outside of quoted strings MUST be rejected (`UnexpectedToken`).

### 2.3 Newlines (Line Terminators)
TDF is a line-oriented format. Directives and block headers are terminated by a newline.
- **Allowed newline sequences:**
  - Line Feed (`LF`, `U+000A`, `"\n"`)
  - Carriage Return + Line Feed (`CRLF`, `U+000D U+000A`, `"\r\n"`)
- A standalone Carriage Return (`CR`, `U+000D`) not followed by `LF` outside of a double-quoted escape sequence MUST be rejected (`UnexpectedToken`).
- Canonical serialization MUST emit `LF` (`"\n"`) line terminators.
- Empty lines (lines containing only optional horizontal whitespace and an optional `#` comment) are ignored anywhere in the document.

### 2.4 Comments
- A comment starts with the hash character (`#`, `U+0023`) outside of a quoted string.
- All characters from `#` up to (but not including) the next newline (`LF`, `CRLF`) or End-Of-File (`EOF`) are ignored by the parser.
- A `#` character immediately following a bare word (e.g., `t001#comment`) is NOT part of the bare word; it immediately terminates the token (`t001`) and starts an inline comment (`#comment`). Hash characters inside quoted strings (e.g., `"#4CAF50"`) are literal characters.
- Multi-line block comments are not supported.

### 2.5 Delimiters & Reserved Punctuation
The following ASCII characters have special syntactic meaning outside of quoted strings:
- `{` (`U+007B`): Opens a block body.
- `}` (`U+007D`): Closes a block body.
- `#` (`U+0023`): Starts a line or inline comment.
- `"` (`U+0022`): Delimits a double-quoted string.
- `'` (`U+0027`): Delimits a single-quoted literal string.

### 2.6 Identifiers (Block & Directive Names)
An **Identifier** is the first token of a block header or directive.
- An Identifier MUST be an unquoted token (bare word). Quoted strings are not permitted as block or directive names.
- **Allowed characters:** ASCII alphanumeric characters (`a-z`, `A-Z`, `0-9`), underscore (`_`), and hyphen (`-`).
- **First character rule:** An Identifier MUST start with an ASCII alphabetic character (`a-z`, `A-Z`) or underscore (`_`). It MUST NOT start with a digit (`0-9`) or hyphen (`-`).

### 2.7 Arguments (Values)
An **Argument** represents a parameter passed to a block header or a directive. An argument can be written in one of three lexical forms:

#### A. Bare Word (Unquoted Token)
- A contiguous sequence of one or more valid UTF-8 characters excluding horizontal whitespace (`' '`, `'\t'`), newlines (`\r`, `\n`), ASCII control characters (`U+0000`–`U+001F`, `U+007F`), non-ASCII Unicode whitespace, and reserved punctuation (`{`, `}`, `#`, `"`, `'`).
- Bare words are used for single-word values without spaces, including entity IDs (`t001`, `taxes2026`, `home`, `it`), header flags (`priority`, `auto-finish`), condition rule keywords (`day`, `time`, `location`, `any`), weekday tokens (`mon`, `tue`, `wed`, `thu`, `fri`, `sat`, `sun`), boolean literals (`true`, `false`), numbers (`50.9787`, `11.0328`, `150`), and ISO-8601 date/time tokens (`2026-11-01`, `08:00`, `19:30:05`).

#### B. Double-Quoted String (`"..."`)
- Begins and ends with `"` (`U+0022`).
- Used for text containing spaces or special characters, such as task and label titles (`name`), descriptions (`note`), and hexadecimal color codes (`"#4CAF50"`).
- May contain horizontal whitespace, `#`, `{`, `}`, and `'`.
- **Single-line constraint:** Unescaped raw newlines (`\r` or `\n`) inside a double-quoted string are forbidden and MUST trigger an `UnterminatedString` error.
- **Escape sequences:** Backslash (`\`, `U+005C`) escapes the immediately following character:
  - `\"` -> Quotation mark (`U+0022`)
  - `\\` -> Reverse solidus / backslash (`U+005C`)
  - `\n` -> Line feed (`U+000A`)
  - `\r` -> Carriage return (`U+000D`)
  - `\t` -> Horizontal tab (`U+0009`)
- Any other backslash escape sequence MUST be rejected with an `InvalidEscapeSequence` error.

#### C. Single-Quoted String (`'...'`)
- Begins and ends with `'` (`U+0027`).
- Treated as a literal (raw) single-line string: backslashes (`\`) and double quotes (`"`) are treated as literal characters without escape processing.
- **Single-line constraint:** Raw newlines (`\r` or `\n`) inside a single-quoted string are forbidden and MUST trigger an `UnterminatedString` error.

### 2.8 Primitive Domain Value Types
At the semantic validation layer, directive and header arguments map to the following primitive types:
- **Version (`<version>`):** Semantic version bare word written as `<MAJOR>.<MINOR>.<PATCH>` where `<MAJOR>`, `<MINOR>`, and `<PATCH>` are non-negative ASCII decimal integers (`0.2.0` for this specification).
- **Entity ID (`<id>`):** A bare word matching `[a-zA-Z0-9_-]+`. Unlike block and directive identifiers (Section 2.6), an `<id>` argument may start with a digit (`0-9`) or hyphen (`-`). Automated writers typically generate sequential IDs (`t001`, `t002`, `t003`, ...), while descriptive single-word IDs (e.g., `taxes2026`, `home`, `it`) are equally valid when authored manually.
- **Boolean (`<bool>`):** Exact case-sensitive bare word `true` or `false`.
- **Weekday (`<weekday>`):** Exact case-sensitive lowercase bare word from the set `mon`, `tue`, `wed`, `thu`, `fri`, `sat`, `sun`.
- **Time of Day (`<time>`):** 24-hour minute-precision time written as `<HH:MM>` (e.g., `08:00`, `18:00`), where `HH` is `00..23` and `MM` is `00..59`.
- **Timestamp (`<timestamp>`):** ISO-8601 local date with optional 24-hour time (minute or second precision), written as either:
  - One bare-word token: `<YYYY-MM-DD>` (e.g., `2026-11-01`).
  - Two whitespace-separated bare-word tokens: `<YYYY-MM-DD> <HH:MM[:SS]>` (e.g., `2026-11-01 19:30` or `2026-11-01 19:30:05`), where `MM` (month) is `01..12`, `DD` is valid for the calendar month/year, `HH` is `00..23`, `MM` (minute) is `00..59`, and optional `SS` (second) is `00..59`.
  - All timestamps represent local time. When `<HH:MM[:SS]>` is omitted on a date-only timestamp, chronological ordering and comparison treat the local time component as `00:00:00`. When `:SS` is omitted on a minute-precision timestamp (`<HH:MM>`), the seconds component defaults to `00` (`<HH:MM:00>`).
  - Optional seconds precision (`:SS`) allows rapid successive mutations and step-down downgrades (Section 6) to sort deterministically by `queued` timestamp without reordering blocks in the file.
- **Floating-Point / Numeric (`<number>`):** Standard ASCII decimal number (`-?[0-9]+(\.[0-9]+)?`) used for geographic latitude (`-90.0` to `90.0`), longitude (`-180.0` to `180.0`), and radius values in meters (`> 0`).
- **Hexadecimal Color (`<color>`):** Quoted 7-character string `"#RRGGBB"` (or single-quoted `'#RRGGBB'`; canonical serialization emits double-quoted `"#RRGGBB"`) where each hexadecimal digit is in `0-9`, `a-f`, or `A-F`. Because `#` outside quotes starts a comment (Section 2.4), `<color>` values MUST be quoted.

## 3. Structural Grammar

### 3.1 Document Structure & Nesting Depth
A TDF document consists of a mandatory root-level **Version Header** (`tdf 0.2.0`) followed by a sequence of zero or more root-level **Blocks**.
- **Nesting Depth Definition:** Nesting depth equals the number of currently open `{ ... }` blocks:
  - Depth `0` (document root): Only the mandatory initial version header (`tdf 0.2.0`), root block headers (`task`, `label`), blank lines, and `#` comments are permitted.
  - Depth `1` (inside a `task` or `label` block body): Block directives and nested sub-block headers (`subtasks`, `condition`) are permitted.
  - Depth `2` (inside a `subtasks` or `condition` sub-block body): Only sub-block directives (`step`, `day`, `time`, `location`) are permitted; no further nested blocks are allowed (`MAX_NESTING_DEPTH = 2`).
- **Mandatory Version Header:** Every valid `.tdf` document MUST begin with `tdf 0.2.0` at nesting depth `0` before any root block (preceded only by optional blank lines and `#` comments). A file with no statements (empty or containing only whitespace and `#` comments) or whose first statement is not `tdf <version>` MUST be rejected with `MissingVersionHeader`. A file containing `tdf 0.2.0` and zero root blocks is a valid empty TDF document.
- **Root-Level Directive Prohibition:** Aside from the initial `tdf 0.2.0` version header, any directive appearing at nesting depth `0` (outside of a `{ ... }` block), including a duplicate `tdf` directive later in the file, MUST be rejected as a syntax error (`UnexpectedRootDirective`).

### 3.2 Blocks
A **Block** groups related directives and optional nested sub-blocks under a named context.

```text
<identifier> [<argument> ...] {
    <statement> ...
}
```

- **Block Header:** Consists of an Identifier, followed by one or more whitespace-separated Arguments (or zero arguments for parameterless sub-blocks such as `subtasks {` and `condition {`), followed by the opening brace `{`.
- **Opening Brace Placement:** The opening brace `{` MUST appear on the same line as the block Identifier and its arguments, separated from the preceding token by at least one horizontal whitespace character (e.g., `task t001 {`, `task t001 priority {`, `label home {`, `subtasks auto-finish {`, or `condition {`).
- **After Opening Brace:** Only optional horizontal whitespace and an optional `#` comment may follow `{` before the line terminator (`\n` or `\r\n`).
- **Block Body:** Contains zero or more statements (Directives or nested Blocks), each on its own logical line.
- **Closing Brace Placement:** Every block is closed by `}` on its own logical line (preceded only by optional horizontal whitespace and followed only by optional horizontal whitespace, an optional `#` comment, and a newline or `EOF`). Inline empty blocks (`{}`) on a single line are not permitted.
- **Empty Blocks:** Because `task` requires `name` and `created`, `label` requires `name`, and `condition` / `subtasks` sub-blocks require at least one rule or step when present, a block containing zero statements between its opening `{` line and closing `}` line is rejected during semantic validation (`MissingRequiredDirective`).

### 3.3 Directives
A **Directive** is a single-line key-value or key-tuple instruction.

```text
<identifier> <argument> [<argument> ...]
```

- **Scope:** Except for the mandatory initial `tdf 0.2.0` version header at nesting depth `0` (Section 4.0), every directive MUST reside inside a block (nesting depth `1` or `2`). Any other directive at nesting depth `0` is rejected with `UnexpectedRootDirective`.
- **Minimum Arity (No Empty Directives):** A directive MUST have an Identifier followed by at least one Argument separated by horizontal whitespace. A standalone identifier on a line inside a block without arguments and without `{` is a syntax error (`MissingDirectiveArgument`). If an optional property has no value, the entire directive line MUST be omitted.
- **Termination:** A directive is terminated by a newline (`LF` or `CRLF`). Because every enclosing block MUST be closed by `}` on a subsequent line, reaching `EOF` directly on a block directive line results in an `UnclosedBlock` error. Semicolons (`;`) are NOT used as statement terminators; a trailing `;` on an unquoted token is treated as part of that bare word.
- **Ordering & Multiplicity:** The parser MUST preserve the exact top-to-bottom declaration order of blocks and directives. Repeatable directives (`condition` inside `label` or `task`, `day`, `time`, and `location` inside `condition`, and `step` inside `subtasks`) are evaluated in declaration order; single-valued directives (`name`, `created`, `queued`, `finished`, `note`, `color`, `labels`, `blocked`, `suspended`) MUST NOT appear more than once per block (`DuplicateDirective`).

### 3.4 Formal Grammar (EBNF)

```ebnf
(* Document Root: Mandatory Version Header followed by Blocks, Comments, and Blank Lines *)
document        = { empty-line } version-header { empty-line | root-block } [ trailing-empty ] ;

version-header  = ws* "tdf" ws+ bare-word ws* [ comment ] newline ;

root-block      = block ;

(* Blocks *)
block           = ws* identifier { ws+ argument } ws+ "{" ws* [ comment ] newline
                  { block-item }
                  ws* "}" ws* [ comment ] ( newline | eof ) ;

block-item      = empty-line
                | block
                | directive ;

(* Directives: Must contain at least one argument and end with a newline *)
directive       = ws* identifier ws+ argument { ws+ argument } ws* [ comment ] newline ;

(* Tokens *)
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

At nesting depth `0`, every TDF document MUST start with the `tdf` version header (Section 4.0), followed by zero or more root blocks of type `task` (Section 4.1) or `label` (Section 4.2). Any other root-level directive MUST be rejected with `UnexpectedRootDirective`, and any other root block identifier MUST be rejected with an `UnknownBlockType` error.

### 4.0 The `tdf` Version Header

Every `.tdf` document MUST begin with a single-line `tdf` version header at nesting depth `0` before any root block:

```text
tdf 0.2.0
```

- **First Statement Requirement:** `tdf 0.2.0` MUST be the first statement of every `.tdf` document (preceded only by optional blank lines and `#` comments) and is the only directive permitted at nesting depth `0`.
- **Version Argument:** Takes a single bare-word `<version>` argument formatted as `<MAJOR>.<MINOR>.<PATCH>` and equal to `0.2.0`.
- **Validation Rules:**
  - If the file contains no statements or its first statement is not `tdf <version>`, the parser MUST fail with `MissingVersionHeader`.
  - If `<version>` is not `0.2.0`, is quoted, or is followed by extra arguments on the header line, the parser MUST fail with `UnsupportedVersion`.
  - If a duplicate `tdf` directive appears anywhere later in the file at nesting depth `0`, the parser MUST fail with `UnexpectedRootDirective`.
- **Serializer Output:** A conforming TDF serializer MUST always emit `tdf 0.2.0` as the first statement of every output document (including an empty board with zero `label` and `task` blocks).

### 4.1 The `task` Block (Tasks)

Every task is represented as an independent `task` block at the root level (header at nesting depth `0`, body at nesting depth `1`).

```text
task <id> [priority] {
    ...
}
```

#### 4.1.1 Header Parameters
1. `<id>` (**Required**, Bare Word `<id>`): Unique identifier for the task across all `task` blocks in the document.
   - Sequential IDs (`t001`, `t002`, `t003`, ...) or descriptive single-word IDs (`taxes2026`, `backup_check`) are permitted.
2. `priority` (**Optional**, Bare Word Flag): Controls sorting precedence within the active pull cycle (see Section 5.5):
   - **When present:** Marks the task as prioritized so that it sorts ahead of all regular tasks in the active cycle (ordered chronologically by `queued` among prioritized tasks).
   - **When omitted:** The task is treated as a regular task and sorts strictly in ascending chronological order by its `queued` timestamp (FIFO) after any prioritized tasks.
- Any missing `<id>`, extra header argument, or unknown header flag MUST be rejected with `InvalidBlockHeader`.

#### 4.1.2 Directives in `task`

| Directive | Required | Multiplicity | Format / Arguments | Semantics When Present / Omitted |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Human-readable title of the task (`1..MAX_TEXT_LENGTH` characters). Required in every `task` block. |
| `created` | Yes | `1` | `<YYYY-MM-DD> [<HH:MM[:SS]>]` | Creation timestamp of the task in local time. Required in every `task` block. |
| `queued` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM[:SS]>]` | Local timestamp governing ascending FIFO ordering in the active cycle. **When omitted** (and `finished` is omitted), the task is classified as `Someday` and excluded from the active cycle. |
| `finished` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM[:SS]>]` | Local completion timestamp. **When present**, the task is classified as `Completed` and subject to garbage collection once older than $30$ days in local time. **When omitted**, the task is open. |
| `note` | No | `0..1` | `"<text>"` | Optional extended description or note (`1..MAX_NOTE_LENGTH` characters). **When omitted**, the task has no extended note. |
| `labels` | No | `0..1` | `<id1> [<id2> ...]` | One or more space-separated `label` `<id>`s assigned to the task. Every referenced `<id>` MUST match a declared `label` block in the document (`UnknownLabelReference`). **When present**, associates the task with the referenced labels for context filtering and group-level condition inheritance. **When omitted**, the task has no label assignment. |
| `blocked` | No | `0..1` | `<task_id1> [<task_id2> ...]` | One or more space-separated `<id>`s of prerequisite tasks. **When present**, the task is classified as `Blocked` if at least one referenced task exists in the document without a `finished` directive (non-existent, pruned, or already completed task IDs do not block the task). Dependency references MUST NOT form a direct or indirect cycle (`CircularDependency`). **When omitted**, no task-dependency block applies. |
| `suspended` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM[:SS]>]` | Local deferral / snooze timestamp. **When present**, the task is classified as `Blocked` while the timestamp lies strictly in the future relative to the local evaluation timestamp. **When omitted**, no time-deferral block applies. |
| `condition` | No | `0..N` | `<type> <args...>`, `<type> any`, `any`, or `{ ... }` | Task-level activation condition(s) (`day`, `time`, `location`, group resets `day any`, `time any`, `location any`, or global reset `condition any`) written either as an inline directive or a `condition { ... }` sub-block (see Section 4.3). **When present**, `condition any` disables all inherited `label` conditions, whereas a group-specific rule (`day`, `time`, or `location`) or group reset (`<type> any`) overrides only that specific rule group from assigned labels while preserving all other inherited label condition groups and keeping the task's `labels` assignment intact. |

#### 4.1.3 Sub-Block `subtasks` (Checklists)

Inside a `task` block (header at nesting depth `1`, body at nesting depth `2`), an optional `subtasks` sub-block (at most one per `task`) defines an ordered checklist:

```text
subtasks [auto-finish] {
    step <true|false> "<text>"
}
```

- `auto-finish` (**Optional Header Flag**):
  - **When present:** As soon as all contained `step` directives have the value `true`, the enclosing `task` automatically transitions to completed (`finished` is set to the current timestamp).
  - **When omitted:** Completing all `step` directives does not automatically set `finished` on the enclosing `task`.
  - Any unknown or extra header argument on `subtasks` MUST be rejected with `InvalidBlockHeader`.
- `step <bool> "<text>"` (**Repeatable Directive**): Defines a single checklist step where `false` indicates open and `true` indicates completed (`"<text>"` up to `MAX_TEXT_LENGTH` characters). The top-to-bottom declaration order of `step` directives is preserved. A `subtasks` block MUST contain at least one `step` directive (`MissingRequiredDirective`).

### 4.2 The `label` Block (Labels & Context Profiles)

Defines a named label (work context and reusable condition profile) at the root level (header at nesting depth `0`, body at nesting depth `1`) that tasks can reference via the `labels` directive. A `label` block header requires exactly one `<id>` argument (`InvalidBlockHeader` if missing or if extra header arguments are present).

```text
label <id> {
    name  "<display_name>"
    color "<hex_color_code>"
    note  "<optional_description>"

    condition {
        day      <d1> [<d2> ...]
        time     <HH:MM> <HH:MM>
        location <lat> <lon> <radius>
    }
}
```

| Directive / Sub-Block | Required | Multiplicity | Format / Arguments | Description |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Human-readable display name of the label (`1..MAX_TEXT_LENGTH` characters, e.g., `"Home & Garden"`). |
| `color` | No | `0..1` | `"#RRGGBB"` | Optional hexadecimal color code associated with the label. |
| `note` | No | `0..1` | `"<text>"` | Optional description of the label (`1..MAX_NOTE_LENGTH` characters). |
| `condition` | No | `0..N` | `<type> <args...>` or `{ ... }` | Optional activation conditions (`day`, `time`, `location`) inherited by rule group for tasks carrying this label unless overridden for that group or cleared globally via `condition any` on the task (see Section 4.3). |

### 4.3 Activation Conditions (`condition`)

#### 4.3.1 Scope & Syntactic Forms (Block Form vs. Single-Line Shorthand)
Activation conditions can be defined inside both `label` blocks and `task` blocks (at nesting depth `1`). Two syntactic representations are supported and map to the exact same internal condition model:

1. **Block Form (`condition { ... }` — Multiple or Grouped Conditions):**
   A parameterless `condition { ... }` sub-block (body at nesting depth `2`) groups one or more condition rules (`day`, `time`, `location`, including task-level group resets `day any`, `time any`, `location any`) without repeating the `condition` keyword on each line:
   ```text
   condition {
       day      sat sun
       time     08:00 20:00
       location 50.9787 11.0328 150
   }
   ```
   A `condition { ... }` sub-block accepts zero header arguments (`InvalidBlockHeader` if any header argument is given before `{`), MUST contain at least one rule directive (`MissingRequiredDirective`), and MUST NOT contain nested sub-blocks (`UnknownBlockType` or `LimitExceeded`).
2. **Single-Line Shorthand (`condition <type> <args...>`, `condition <type> any`, or `condition any` — Inline Directive):**
   For a single condition rule (or repeatable inline declarations), the inline directive `condition <type> <args...>` (or `condition <type> any` / `condition any` on a `task` block) is equally valid:
   ```text
   condition time 09:00 18:00
   ```
3. **Canonical Serialization:**
   - When a `label` or `task` has `0` condition rules, no `condition` directive or sub-block is emitted.
   - When a `task` disables all inherited label conditions via `condition any`, a canonical serializer MUST emit `condition any`.
   - When a `label` or `task` has exactly `1` condition rule (including a single task-level group reset such as `condition day any`), a canonical serializer MUST emit the single-line shorthand `condition <type> <args...>`.
   - When a `label` or `task` has `2` or more condition rules, a canonical serializer MUST emit a single `condition { ... }` sub-block with rules ordered by evaluation group as `day`, `time`, `location` (preserving relative declaration order within the same group).

#### 4.3.2 Built-In Condition Rule Types & Resets

Inside a `condition { ... }` sub-block (or following the `condition` keyword in single-line shorthand), three rule groups (`day`, `time`, `location`), three task-level group resets (`day any`, `time any`, `location any`), and the task-level global reset (`condition any`) are defined:

| Rule / Form | Block Syntax | Inline Shorthand Syntax | Arguments & Domain Rules |
| :--- | :--- | :--- | :--- |
| `day` | `day <d1> [<d2> ...]` | `condition day <d1> [<d2> ...]` | One or more weekday tokens (`mon`, `tue`, `wed`, `thu`, `fri`, `sat`, `sun`). Allowed weekdays are combined with logical `OR`. |
| `time` | `time <start> <end>` | `condition time <start> <end>` | Two 24-hour `<HH:MM>` time tokens (`00:00` to `23:59`, `start != end`). Defines an inclusive daily active time window in local time. |
| `location` | `location <lat> <lon> <radius>` | `condition location <lat> <lon> <radius>` | Three decimal numbers (`<lat>` in `[-90.0, 90.0]`, `<lon>` in `[-180.0, 180.0]`, `<radius>` $> 0$ in meters). |
| `<type> any` | `day any` / `time any` / `location any` | `condition day any` / `condition time any` / `condition location any` | Valid on `task` blocks only (`InvalidCondition` on `label` or when combined with other rules of the same `<type>` group on the same `task`). Clears that single inherited condition group (`day`, `time`, or `location`) while preserving all other inherited `label` condition groups. |
| `any` | *(not allowed in block)* | `condition any` | Valid on `task` blocks only (`InvalidCondition` on `label` or when combined with any other `condition` rules on the same `task`). Disables all inherited `label` condition groups (`day`, `time`, and `location`) so the task is unrestricted. |

Detailed rule semantics:
1. **Weekday Rule (`day`):**
   - Evaluates to `true` if the current local calendar weekday at the evaluation timestamp matches at least one listed `<weekday>` token.
   - Multiple `day` rules within the active condition context are combined with logical `OR`.
2. **Time Window Rule (`time`):**
   - **Same-Day Window (`start < end`):** Evaluates to `true` when `start <= current_time <= end` in local time (inclusive boundaries, e.g., `time 08:00 20:00`).
   - **Overnight Window (`start > end`):** Spans midnight and evaluates to `true` when `current_time >= start || current_time <= end` in local time (e.g., `time 22:00 06:00`).
   - **Disjoint Windows on the Same Day:** Multiple `time` rules within the active condition context (e.g., `time 08:00 12:00` and `time 14:00 18:00`) are combined with logical `OR`, evaluating to `true` if the current local time falls within at least one window.
3. **GPS Location Rule (`location`):**
   - Specifies a circular geofence centered at `(<lat>, <lon>)` in WGS-84 decimal degrees with a radius of `<radius>` meters.
   - Evaluates to `true` when the great-circle Haversine distance (using mean Earth radius $R = 6\,371\,000\text{ m}$) between the device's current GPS coordinates and `(<lat>, <lon>)` is less than or equal to `<radius>` ($\text{distance} \le \text{radius}$).
   - Multiple `location` rules within the active condition context are combined with logical `OR`, evaluating to `true` if the device is within the radius of at least one specified location.
   - If the evaluation environment does not provide current GPS coordinates (e.g., desktop platform without GPS hardware or disabled location sensor), `location` rules evaluate to `true` (unrestricted).
4. **Global Reset (`condition any`) vs. Group Reset (`day any`, `time any`, `location any`):**
   - **Global Reset (`condition any`):** Disables all three inherited `label` condition groups (`day`, `time`, and `location`) at once so the task is unrestricted in every context. `condition any` is only valid as a standalone inline directive on a `task` block; using `any` on a `label` block, inside `condition { ... }` without a `<type>` prefix, or alongside any other `condition` rule on the same `task` MUST be rejected (`InvalidCondition`).
   - **Group Reset (`day any`, `time any`, `location any`):** Clears only the specified rule group (`day`, `time`, or `location`) inherited from assigned labels, treating that group as empty (`0` rules, unrestricted) while preserving all other inherited label condition groups. A group reset may be written inline (`condition <type> any`) or inside a task's `condition { ... }` sub-block (`<type> any`, e.g., `day any` paired with `time 09:00 18:00`). Using `<type> any` inside a `label` block, repeating `<type> any` for the same group, or combining `<type> any` with another rule of the same `<type>` group on the same `task` MUST be rejected (`InvalidCondition`).

#### 4.3.3 Group-Level Condition Inheritance, Selective Overrides & Per-Label Context Evaluation
Task-level condition rules operate at the granularity of individual rule groups (`day`, `time`, `location`) while leaving the task's `labels` membership intact for context filtering:

1. **Group-Level Resolution (`day`, `time`, `location`) for a Given Label Context:**
   When resolving a `task`'s effective condition groups against a specific `label` (or for an unlabeled task):
   - **Global Reset (`condition any`):** If the `task` specifies `condition any`, all three effective rule groups (`day`, `time`, `location`) are empty (`0` rules, unrestricted), ignoring all conditions on the `label`.
   - **Selective Per-Group Override or Inheritance:** Otherwise, each rule group $G \in \{\text{day}, \text{time}, \text{location}\}$ is resolved independently:
     - **Task Group Reset (`G any`):** If the `task` specifies `day any`, `time any`, or `location any` for group $G$, effective group $G$ is cleared to empty (`0` rules, unrestricted), ignoring the `label`'s rules for group $G$.
     - **Task Group Override (`G <args...>`):** If the `task` defines one or more rules for group $G$, the `task`'s rules for group $G$ replace only the `label`'s rules for group $G$.
     - **Label Group Inheritance (No Task Rule for $G$):** If the `task` defines no rule or reset for group $G$, effective group $G$ inherits the rules defined for group $G$ on the `label` (or is empty if the `label` defines no rules for $G$).
   - Consequently, a task assigned to `label home` (`day sat sun`, `time 08:00 20:00`, `location ...`) that specifies `condition time 09:00 18:00` overrides only the `time` group (`09:00..18:00`) while still inheriting `day sat sun` and `location` from `home`. To also allow execution on weekdays while still requiring `home`'s GPS location, the task can specify `day any` alongside `time 09:00 18:00`.
2. **Unlabeled Task (`labels` Omitted):**
   - If a `task` has no `labels` directive, it has a single effective condition context consisting exclusively of the task's own `day`, `time`, and `location` groups (any group omitted or set to `<type> any` is empty/unrestricted).
3. **Active `label` Context Filter Selected:**
   - When an active `label` context filter is selected, **only** that selected `label` context is evaluated. The task's effective condition context is constructed by applying the group-level resolution rules (Rule 1) to the selected `label`, and the task is satisfied if all three effective groups (`day`, `time`, `location`) of that context are satisfied (Section 4.3.4).
4. **No `label` Filter Selected (Global View — Cohesive Per-Label Contexts):**
   - **Cohesive Label Contexts:** When no `label` filter is active and a task is assigned to one or more labels ($L_1, \dots, L_k$), each assigned label $L_i$ represents a self-contained work context. Rather than pooling `day`, `time`, and `location` rules across different labels into a mixed group union, each assigned label $L_i$'s effective condition context $C_i$ (constructed by applying the task's group-level overrides and resets to $L_i$ per Rule 1) is evaluated **independently** in declaration order.
   - **Logical `OR` Across Labels:** A multi-label task is satisfied in the global view if **at least one** assigned label $L_i$ has all three of its effective groups (`day`, `time`, and `location`) satisfied (`OR` short-circuit across labels as soon as the first satisfied label context $C_i$ is found). If every assigned label context fails at least one of its effective groups, the task's condition is unmet and the task is classified as `Blocked` (`Tier 4`).

#### 4.3.4 Deterministic Group Evaluation Order (`day` -> `time` -> `location`) & Short-Circuiting
To minimize computational cost, each effective condition context $C$ is evaluated by group in strict order of increasing evaluation cost:

1. **Group 1 — `day` (Weekday check):** Fastest ($O(1)$ integer/bitmask check against the local evaluation date's weekday).
2. **Group 2 — `time` (Time-of-day window check):** Second fastest (integer minute-of-day boundary comparisons in local time).
3. **Group 3 — `location` (GPS Haversine check):** Most expensive (floating-point trigonometric great-circle distance calculation).

**Step-by-Step Context Evaluation Algorithm:**
- For a given effective condition context $C$, evaluation starts with `isContextSatisfied = true` and steps through the three groups (`day`, then `time`, then `location`):
  1. **Empty Group (`0` rules for the current group, or cleared via `<type> any` / `condition any`):** The group is trivially satisfied (`true`), and evaluation immediately advances to the next group.
  2. **Non-Empty Group ($\ge 1$ rules for the current group — Intra-Group Logical `OR`):** The rules in the group are tested one by one in declaration order. **As soon as a single rule in the group evaluates to `true`**, the entire group is satisfied (`OR` short-circuit) and evaluation immediately advances to the next group without testing the remaining rules in that group.
  3. **Group Failure (Inter-Group Logical `AND`):** If all rules in a non-empty group evaluate to `false`, evaluation of context $C$ terminates immediately with `false` (`AND` short-circuit) without checking any subsequent groups in $C$.
- Formally, for a single effective condition context $C$:
  $$\text{isContextSatisfied}(C) = (\bigvee C.\text{day}) \land (\bigvee C.\text{time}) \land (\bigvee C.\text{location})$$
- When evaluating a task with $k \ge 1$ assigned label contexts $\{C_1, \dots, C_k\}$ in the global view (no active label filter), label contexts are tested in declaration order with `OR` short-circuiting:
  $$\text{isSatisfied} = \bigvee_{i=1}^{k} \text{isContextSatisfied}(C_i)$$
  If $\text{isSatisfied}$ is `false`, the task is excluded from active selection (`Focus`, `Ready`, `Planned`) and classified as `Blocked` (`Tier 4`).

## 5. Dynamic Computation of the 6 Tiers (Evaluation Pipeline)

When evaluating a `.tdf` document against a local reference timestamp (`now`), optional device GPS coordinates, and an optional active `label` context filter, the six tiers are derived deterministically in a single $O(N)$ pipeline across all `task` blocks. All timestamp comparisons (`created`, `queued`, `finished`, `suspended`), weekday/time condition checks, and 30-day completed task retention pruning are evaluated in local time relative to `now`:

### 5.1 Pre-Filtering — Active `label` Context Filter
- **When an active `label` context filter is selected:** Only tasks whose `labels` directive contains the active `label` `<id>` enter the tier classification steps (Sections 5.2 through 5.5). All 6 tiers (`Completed`, `Someday`, `Blocked`, `Focus`, `Ready`, `Planned`) are scoped to that label context.
- **When no `label` context filter is selected (global view):** All `task` blocks in the document enter the tier classification steps.

### 5.2 Tier 6 — `Completed`
- **Selection Rule:** All retained tasks that possess a `finished` directive.
- **Garbage Collection (30-Day Retention Pruning):** Tasks whose `finished` timestamp lies strictly more than $30$ days in the past in local time relative to the evaluation timestamp (`now`) are removed when persisting the document.

### 5.3 Tier 5 — `Someday`
- **Selection Rule:** All retained open tasks (`finished` is absent) that do NOT possess a `queued` directive.
- **Behavior:** These tasks form the unscheduled backlog and do not participate in the active pull cycle.

### 5.4 Tier 4 — `Blocked`
- **Selection Rule:** All retained scheduled open tasks (`queued` is present and `finished` is absent) for which **at least one** of the following blocking conditions holds at the local evaluation timestamp (`now`):
  1. **Unfinished Prerequisite (`blocked`):** At least one task ID referenced in the task's `blocked` directive exists anywhere in the document (regardless of the active `label` filter) and does not have a `finished` directive.
  2. **Future Deferral (`suspended`):** The task's `suspended` timestamp lies strictly in the future in local time (`suspended > now`).
  3. **Unmet Condition (`condition` — `day` -> `time` -> `location` Short-Circuit):** Each candidate condition context (determined per Section 4.3.3: the task's own context if unlabeled, the active `label`'s effective context when filtered, or each assigned `label`'s independent effective context with `OR` across labels in global view) is evaluated by group in the order `day`, `time`, `location` (Section 4.3.4). If no candidate context has all three of its effective groups satisfied, the task is classified as `Blocked`.
- **Auto-Pull Cascade Behavior:** Any task derived as `Blocked` is skipped during the auto-pull cascade into `Focus` (limit `3`) and `Ready` (limit `5`), allowing the next unblocked task in queue order to advance automatically.

### 5.5 Active Pull Cycle (`Focus`, `Ready`, `Planned`)
All remaining retained scheduled, unblocked, open tasks (`queued` is present, `finished` is absent, and none of the Section 5.4 blocking criteria apply) enter the active cycle pipeline:

1. **Step 1 — Deterministic Sorting:**
   - **Primary Group (`priority` Flag Present):** Tasks carrying the `priority` header flag are placed ahead of regular tasks and sorted among themselves in ascending chronological order by their local `queued` timestamp (`<YYYY-MM-DD> [<HH:MM[:SS]>]`, with omitted time defaulting to `00:00:00` and omitted seconds defaulting to `00`).
   - **Secondary Group (`priority` Flag Omitted — Regular FIFO):** Regular tasks follow in ascending chronological order by their local `queued` timestamp (oldest timestamp first = FIFO).
   - **Tie-Breaking:** Tasks with identical `priority` status and identical `queued` timestamps preserve their relative document declaration order. Because `<timestamp>` supports optional seconds precision (`:SS`), rapid mutations and step-down downgrades (Section 6.3) sort deterministically by `queued` without reordering blocks in the file.
2. **Step 2 — Slot Slicing:**
   - **Tier 1 — `Focus` (Positions $1$ to $3$):** The first up to `3` tasks of the sorted list (indices `0..2`).
   - **Tier 2 — `Ready` (Positions $4$ to $8$):** The next up to `5` tasks of the sorted list (indices `3..7`).
   - **Tier 3 — `Planned` (Position $9$ onward):** All remaining tasks of the sorted list (indices $\ge 8$).

## 6. State Transitions & Document Mutations

State transitions mutate the task directives (`queued`, `finished`) and header flags (`priority`) in the `.tdf` document rather than moving task blocks between static tier sections. Tier membership is always derived deterministically from the resulting task attributes via Section 5:

### 6.1 Creating a New Task
- **For `Planned` (Default):** Sets both `created` and `queued` to the current local timestamp (`now`). If `Focus` or `Ready` has open capacity ($< 3$ or $< 5$ tasks) and all effective conditions are satisfied, the slicing pipeline (Section 5.5) places the task into the corresponding higher tier automatically.
- **For `Someday`:** Sets `created` to the current local timestamp (`now`) and omits `queued`.
- **With `priority` Flag (For `Focus`):** Sets `created` and `queued` to `now` and adds the `priority` flag to the `task` block header so that the task sorts ahead of regular tasks in the active pull cycle (Section 5.5).

### 6.2 Scheduling a Task from `Someday`
- Adds the `queued` directive set to the current local timestamp (`now`).

### 6.3 Downgrading an Active Task (`Focus` and `Ready` Only)
- **Allowed Source Tiers (`Focus` and `Ready` Only):** Only tasks currently derived in `Focus` (`Tier 1`) or `Ready` (`Tier 2`) can be downgraded. Tasks in `Planned` (`Tier 3`), `Blocked` (`Tier 4`), `Someday` (`Tier 5`), or `Completed` (`Tier 6`) CANNOT be downgraded (attempting to downgrade a task outside `Focus` and `Ready` is a no-op).
- **Downgrade from `Focus` to `Ready`:**
  - **Fewer than `8` active tasks (`< 8`):** Removes the `priority` header flag if present and sets `queued` to the current local timestamp (`now`).
  - **At least `8` active tasks (`>= 8`):** To place the downgraded task deterministically at active slot `8` (index `7`, the last slot of `Ready`) without reordering blocks in the file:
    1. **Priority Alignment with Slot `8`:** Removes the `priority` header flag if the task currently at active slot `8` is a regular task, or retains `priority` if the task at active slot `8` carries `priority` (ensuring the downgraded task is compared within the same sorting group as slot `8`).
    2. **Timestamp Offset (`+00:00:01`):** Sets the downgraded task's `queued` timestamp to `1` second (`+00:00:01`, using `<HH:MM:SS>` precision) after the `queued` timestamp of the task currently at active slot `8`.
    3. **Collision Shift in `Planned` (Slot `9` Onward):** If the task at active slot `9` (the first task in `Planned`) belongs to the same `priority` group and has a `queued` timestamp less than or equal to the downgraded task's new `queued` timestamp (`slot_9.queued <= new_queued`), shifts `slot_9` (and any subsequent colliding tasks in `Planned` within the same group) forward so each has a `queued` timestamp at least `1` second (`+00:00:01`) after its predecessor, guaranteeing `slot_8.queued < new_queued < slot_9.queued`.
- **Downgrade from `Ready` to `Planned`:** Removes the `priority` header flag if present and sets `queued` to the current local timestamp (`now`) so the task moves to the end of the regular FIFO queue (if fewer than `8` other active tasks exist, the Section 5.5 slicing pipeline places the task into the highest open slot in `Focus` or `Ready`).

### 6.4 Completing a Task (From Any Open Tier)
- Any open task—regardless of whether it is currently derived in `Focus`, `Ready`, `Planned`, `Blocked`, or `Someday`—can be completed directly by adding the `finished` directive set to the current local timestamp (`now`) (or automatically when all `step` directives in a `subtasks auto-finish` sub-block become `true`).
- The completed task transitions into `Completed` (`Tier 6`), unblocking any dependent tasks whose `blocked` directive waited exclusively on this task. If the completed task occupied a slot in `Focus` or `Ready` (or if a newly unblocked task enters the active pull cycle), re-running the Section 5 pipeline automatically refills `Focus` (up to `3`) and `Ready` (up to `5`) in queue order.

### 6.5 Restoring a Task from `Completed`
- Removes the `finished` directive and applies the chosen target state:
  - **Restore to `Someday`:** Removes the `priority` header flag if present and omits `queued`.
  - **Restore to `Planned`:** Removes the `priority` header flag if present and sets `queued` to the current local timestamp (`now`).
  - **Restore to `Focus`:** Adds the `priority` header flag to the `task` block and sets `queued` to the current local timestamp (`now`).

## 7. Conformance & Resource Bounds

To guarantee bounded memory usage and prevent denial-of-service on malformed inputs, a conforming TDF parser MUST enforce the following resource limits before scanning or allocating the $(N+1)$-th element:

| Bound Name | Default Limit | Purpose |
| :--- | :--- | :--- |
| `MAX_FILE_BYTES` | `1_048_576` (1 MiB) | Maximum input size in UTF-8 bytes before rejecting the document. |
| `MAX_LINE_COUNT` | `16_384` | Maximum logical lines per `.tdf` document. |
| `MAX_NESTING_DEPTH` | `2` | Maximum open `{ ... }` block depth (`1` inside root blocks `task` and `label`, `2` inside sub-blocks `subtasks` and `condition`). |
| `MAX_BLOCKS_PER_DOC` | `4_096` | Maximum total blocks (`task`, `label`, `subtasks`, `condition`) per document. |
| `MAX_STMTS_PER_BLOCK` | `512` | Maximum directives or sub-blocks inside a single block. |
| `MAX_ARGS_PER_STMT` | `64` | Maximum arguments allowed on a single block header or directive. |
| `MAX_TEXT_LENGTH` | `500` | Maximum character length (after unescaping) of a `name` or `step` text value. |
| `MAX_NOTE_LENGTH` | `2000` | Maximum character length (after unescaping) of a `note` text value. |

## 8. Mandatory Error Conditions

A conforming TDF parser MUST report a structured error (including the 1-based line number) and MUST fail deterministically on any of the following inputs:

- **Missing Version Header (`MissingVersionHeader`):** The file contains no statements (empty or only whitespace and `#` comments), or the first statement at nesting depth `0` is not `tdf <version>` (e.g., the file starts directly with `label home {` or `task t001 {`, or bare `tdf` without a version argument).
- **Unsupported Version (`UnsupportedVersion`):** The initial `tdf <version>` header specifies a `<version>` other than `0.2.0` (e.g., `tdf 0.1.0` or `tdf 1.0.0`), quotes the version token, or has extra arguments (e.g., `tdf 0.2.0 extra`).
- **Root Directive (`UnexpectedRootDirective`):** Any root-level directive other than the initial `tdf` version header appears at nesting depth `0` outside of any `{ ... }` block (e.g., `name "Mow the lawn"` at root level, or a duplicate `tdf` directive later in the file).
- **Missing Argument or Brace (`MissingDirectiveArgument`):** A single identifier appears on a line without arguments and without an opening `{` (e.g., `queued` with no timestamp value).
- **Quoted or Invalid Identifier (`InvalidIdentifier`):** A block or directive name is quoted (e.g., `"task" t001 {` or `"name" "Mow the lawn"`), a block/directive identifier starts with an invalid character (e.g., `123task {` or `-flag val`), or an `<id>` argument does not match `[a-zA-Z0-9_-]+`.
- **Malformed Block Header or Missing Whitespace Before Brace (`InvalidBlockHeader`):** The opening `{` is attached directly to the identifier or argument without whitespace (e.g., `task t001{` or `condition{`), a required header `<id>` is missing (e.g., `task {` or `label {`), or an unknown/extra header argument is provided (e.g., `task t001 urgent {`, `label home extra {`, `subtasks urgent {`, or `condition arg {`).
- **Unexpected Token, Control Character, or Trailing Tokens (`UnexpectedToken`):** Non-comment tokens appear on the same line after `{` or after `}`, a quote opens or closes in the middle of a token without separating whitespace (e.g., `foo"bar"` or `"foo"bar`), a directive has an invalid argument count, or the input contains invalid UTF-8 bytes, null bytes (`U+0000`), disallowed control characters, standalone `CR` without `LF`, or non-ASCII whitespace outside quotes.
- **Unclosed Block (`UnclosedBlock`):** `EOF` is reached while nesting depth $> 0$.
- **Unmatched Closing Brace (`UnexpectedClosingBrace`):** `}` is encountered at nesting depth `0`.
- **Unterminated Quote (`UnterminatedString`):** A `"` or `'` string reaches `\r`, `\n`, or `EOF` before its matching closing quote.
- **Invalid Escape (`InvalidEscapeSequence`):** A `"` string contains an unknown escape sequence (e.g., `\a`, `\x`, `\0`).
- **Schema Validation Errors:**
  - `UnknownBlockType`: Root block is not `task` or `label`; nested block inside `task` is not `subtasks` or `condition`; nested block inside `label` is not `condition`; or a block appears inside `subtasks` or `condition`.
  - `UnknownDirective`: A directive name is not valid for its enclosing block (`task`, `label`, `subtasks`, or `condition`), or a `condition` rule type is not `day`, `time`, or `location`.
  - `MissingRequiredDirective`: A required directive (`name` or `created` in `task`; `name` in `label`) is missing, or a `subtasks` or `condition` sub-block contains zero directives.
  - `DuplicateDirective`: A single-valued directive (`name`, `created`, `queued`, `finished`, `note`, `color`, `labels`, `blocked`, `suspended`) appears more than once in the same block, or more than one `subtasks` sub-block appears in a `task`.
  - `DuplicateIdentifier`: Two root blocks in the same namespace (`task` or `label`) share an identical `<id>`.
  - `UnknownLabelReference`: A `labels` directive in a `task` block references a label `<id>` that does not match any declared `label` block in the document (whereas `blocked` task `<id>`s referencing non-existent or pruned completed tasks remain valid and non-blocking).
  - `CircularDependency`: Task dependency references in `blocked` directives form a direct cycle (self-dependency) or an indirect cycle across two or more `task` blocks.
  - `InvalidTimestamp` / `InvalidBoolean` / `InvalidNumber` / `InvalidCondition` / `InvalidColor`: A directive argument fails semantic validation (invalid ISO-8601 `<YYYY-MM-DD> [<HH:MM[:SS]>]` date/time, invalid `<HH:MM>` time window or identical start and end times `start == end`, unknown weekday token, latitude outside `[-90.0, 90.0]`, longitude outside `[-180.0, 180.0]`, radius $\le 0$, `any` or `<type> any` used inside a `label` condition, `condition any` combined with other condition rules on a `task`, `<type> any` combined with other rules of the same `<type>` group on a `task`, or a `color` argument not matching `"#RRGGBB"`).
- **Limit Exceeded (`LimitExceeded`):** Any resource bound defined in Section 7 is exceeded.

## 9. Canonical Complete Example (`tiertask.tdf`)

```text
# ==========================================
# TierTask Data Format (TDF) Example Document
# ==========================================

tdf 0.2.0

label home {
    name "Home & Garden"

    condition {
        day      sat sun
        time     08:00 20:00
        location 50.9787 11.0328 150
    }
}

label it {
    name  "IT & Servers"
    color "#2196F3"

    condition {
        day  mon tue wed thu fri
        time 08:00 12:00
        time 14:00 18:00
    }
}

# Prioritized task in 'home' overriding only the 'time' condition group
# (narrowed to 09:00..18:00 while inheriting 'day sat sun' and 'location' from 'home'):
task t001 priority {
    name      "Mow the lawn"
    note      "Check fuel level before starting"
    created   2026-11-01 19:30
    queued    2026-11-01 19:30
    labels    home
    blocked   t002
    suspended 2026-11-05
    condition time 09:00 18:00

    subtasks auto-finish {
        step false "Get lawnmower from the shed"
        step true  "Empty grass catcher bag"
    }
}

# Prerequisite task in 'home' using 'condition any' to disable all inherited
# label conditions (can be ordered online on any day, at any time, from anywhere):
task t002 {
    name      "Order replacement lawnmower blades online"
    created   2026-11-01 18:00
    queued    2026-11-01 18:00
    labels    home
    condition any
}

# Task assigned to multiple labels without task-level overrides (in global view,
# evaluates each label context independently and is active if all condition groups
# of 'home' OR all condition groups of 'it' are satisfied; when filtered by 'home'
# or 'it', evaluates only the selected label's conditions):
task t003 {
    name    "Clean dust filters on home NAS server"
    created 2026-11-01 10:00
    queued  2026-11-01 10:00
    labels  home it
}

# Task in "Someday" (no 'queued' directive present)
task t004 {
    name    "Design 3D-printed enclosure for backup NAS"
    created 2026-11-01 12:00
    labels  it
}

# Completed task ('finished' is set -> deleted after 30 days)
task t005 {
    name     "Mount winter tires"
    created  2026-10-20 14:00
    queued   2026-10-21 08:00
    finished 2026-10-29 16:45
    labels   home
}
```
