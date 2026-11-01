# TierTask Data Format (TDF) Specification

**Version:** 0.1.0-draft
**Status:** Draft Specification
**File Extension:** `.tdf`
**Character Encoding:** UTF-8

> [!NOTE]
> **Draft Status Notice:**
> This document is an initial specification draft. While the lexical grammar, structural block syntax, core `task` and `subtasks` schema, dynamic tier derivation pipeline, and state mutation rules are normatively specified, the domain semantics for **`location`**, **`category`**, and **`condition`** remain under active design and are marked as **Draft / Work in Progress**.

## 1. Overview, Architecture & Design Goals

The TierTask Data Format (`TDF`) is a deterministic, line-oriented, block-based plain-text data format for representing tasks, checklists, dependencies, contexts, and scheduling states. It combines human readability in standard text editors with structured `{ ... }` blocks and single-line directives.

### 1.1 Core Philosophy: Data vs. View Separation

A `.tdf` document stores exclusively objective facts: tasks (`task`), timestamps (`created`, `queued`, `finished`, `suspended`), dependencies (`blocked`), checklists (`subtasks`), locations (`location`), and categories (`category`).

1. **No Explicit Tier Storage:** Unlike positional list formats, a `.tdf` document does NOT store an explicit tier assignment (`[1]` through `[6]`) on any task.
2. **Dynamic Derivation ($O(N)$ Pipeline):** The six operational tiers (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, and `Completed`) are derived deterministically from the stored task attributes via a single-pass $O(N)$ filtering, sorting, and slicing pipeline (see Section 5).

### 1.2 Core Design Principles

1. **Strict Root Block Enforcement:** Every top-level statement at nesting depth `0` in a TDF document MUST be a block (`task`, `location`, or `category`). Standalone directives at the root level are forbidden.
2. **No Empty Directives:** Optional directives that have no value (such as an unset `finished` or `queued` timestamp) MUST be omitted entirely from the block rather than written with empty arguments.
3. **Single-Pass Linear Grammar:** TDF is designed to be tokenized and parsed in a single $O(N)$ linear pass without regular expressions or backtracking.
4. **Two-Layer Validation (Syntax vs. Domain Semantics):** At the lexical and structural layer, all identifiers and arguments are scanned as UTF-8 string tokens. Semantic validation (ISO-8601 timestamps, boolean literals, geographic coordinates, hexadecimal color codes, and cross-block identifier references) is enforced deterministically by the domain schema layer.

## 2. Lexical Elements

### 2.1 Character Encoding
- A TDF document MUST be a valid UTF-8 byte sequence.
- Invalid UTF-8 byte sequences and null bytes (`U+0000`) MUST be rejected before or during scanning.
- A conforming scanner MUST respect UTF-8 character boundaries at all times.

### 2.2 Whitespace
Horizontal whitespace separates tokens within a single line and is otherwise insignificant outside of quoted strings.
- **Allowed horizontal whitespace characters:**
  - ASCII Space (`U+0020`, `' '`)
  - ASCII Horizontal Tab (`U+0009`, `'\t'`)
- Other Unicode whitespace characters outside of quoted strings MUST be rejected as invalid characters.

### 2.3 Newlines (Line Terminators)
TDF is a line-oriented format. Directives and block headers are terminated by a newline.
- **Allowed newline sequences:**
  - Line Feed (`LF`, `U+000A`, `"\n"`)
  - Carriage Return + Line Feed (`CRLF`, `U+000D U+000A`, `"\r\n"`)
- A standalone Carriage Return (`CR`, `U+000D`) not followed by `LF` outside of a double-quoted escape sequence is invalid.
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
- A contiguous sequence of one or more valid UTF-8 characters excluding horizontal whitespace (`' '`, `'\t'`), newlines (`\r`, `\n`), and reserved punctuation (`{`, `}`, `#`, `"`, `'`).
- Bare words are used for single-word values without spaces, including entity IDs (`t001`, `taxes2026`, `home`, `c_it`), header flags (`priority`, `auto-finish`), boolean literals (`true`, `false`), numbers (`50.9787`, `150`), and ISO-8601 date/time tokens (`2026-11-01`, `08:30`).

#### B. Double-Quoted String (`"..."`)
- Begins and ends with `"` (`U+0022`).
- Used for text containing spaces or special characters, such as task titles (`name`), descriptions (`note`), and hexadecimal color codes (`"#4CAF50"`).
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
- **Entity ID (`<id>`):** A bare word matching `[a-zA-Z0-9_-]+`. Automated writers typically generate sequential IDs (`t001`, `t002`, `t003`, ...), while descriptive single-word IDs (e.g., `taxes2026`, `home`, `c_house`) are equally valid when authored manually.
- **Boolean (`<bool>`):** Exact case-sensitive bare word `true` or `false`.
- **Timestamp (`<timestamp>`):** ISO-8601 date with optional 24-hour minute-precision time, written as either:
  - One bare-word token: `<YYYY-MM-DD>` (e.g., `2026-11-01`).
  - Two whitespace-separated bare-word tokens: `<YYYY-MM-DD> <HH:MM>` (e.g., `2026-11-01 08:30`), where `MM` is `01..12`, `DD` is valid for the calendar month/year, `HH` is `00..23`, and `MM` (minute) is `00..59`.
  - When `<HH:MM>` is omitted on a date-only timestamp, chronological ordering and comparison treat the time component as `00:00`.
- **Floating-Point / Numeric (`<number>`):** Standard ASCII decimal number (`-?[0-9]+(\.[0-9]+)?`) used for geographic latitude, longitude, and radius values.

## 3. Structural Grammar

### 3.1 Document Structure (Mandatory Root Blocks)
A TDF document represents a sequence of root-level **Blocks**.
- At the root level (nesting depth `0`), ONLY **Blocks** (`task`, `location`, `category`), blank lines, and `#` comments are permitted.
- **Root-Level Directive Prohibition:** Any directive appearing at nesting depth `0` (outside of a `{ ... }` block) MUST be rejected as a syntax error (`UnexpectedRootDirective`).
- An empty file (or a file containing only whitespace and comments) is a valid empty TDF document with zero blocks.

### 3.2 Blocks
A **Block** groups related directives and optional nested sub-blocks under a named context.

```text
<identifier> [<argument> ...] {
    <statement> ...
}
```

- **Block Header:** Consists of an Identifier, followed by one or more whitespace-separated Arguments (or zero arguments for parameterless sub-blocks such as `subtasks {`), followed by the opening brace `{`.
- **Opening Brace Placement:** The opening brace `{` MUST appear on the same line as the block Identifier and its arguments, separated from the preceding token by at least one horizontal whitespace character (e.g., `task t001 {`, `task t001 priority {`, or `subtasks {`).
- **After Opening Brace:** Only optional horizontal whitespace and an optional `#` comment may follow `{` before the line terminator (`\n` or `\r\n`), except for an empty inline block `{}`.
- **Block Body:** Contains zero or more statements (Directives or nested Blocks), each on its own logical line.
- **Closing Brace Placement:** A non-empty block is closed by `}` on its own logical line (preceded only by optional horizontal whitespace and followed only by optional horizontal whitespace, an optional `#` comment, and a newline or `EOF`).
- **Empty Blocks:** A block may be empty (if it requires no mandatory directives), written either across multiple lines or inline as `<identifier> [<argument> ...] {}`.

### 3.3 Directives
A **Directive** is a single-line key-value or key-tuple instruction inside a block.

```text
<identifier> <argument> [<argument> ...]
```

- **Block-Only Scope:** A directive MUST reside inside a block (nesting depth $\ge 1$).
- **Minimum Arity (No Empty Directives):** A directive MUST have an Identifier followed by at least one Argument separated by horizontal whitespace. A standalone identifier on a line without arguments and without `{` is a syntax error (`MissingDirectiveArgument`). If an optional property has no value, the entire directive line MUST be omitted.
- **Termination:** A directive is terminated by a newline (`LF` or `CRLF`) or `EOF` (if preceding a closing brace). Semicolons (`;`) are NOT used as statement terminators; a trailing `;` on an unquoted token is treated as part of that bare word.
- **Ordering & Multiplicity:** The parser MUST preserve the exact top-to-bottom declaration order of blocks and directives. Directives designated as repeatable (such as `condition` inside `task` or `step` inside `subtasks`) are evaluated in declaration order; single-valued directives (`name`, `created`, `queued`, `finished`, `note`, `suspended`) MUST NOT appear more than once per block (`DuplicateDirective`).

### 3.4 Formal Grammar (EBNF)

```ebnf
(* Document Root: Strictly Blocks, Comments, and Blank Lines *)
document        = { empty-line | root-block } ;

root-block      = block ;

(* Blocks *)
block           = ws* identifier { ws+ argument } ws+ "{" ws* [ comment ] newline
                  { block-item }
                  ws* "}" ( [ ws* [ comment ] newline ] | ws* [ comment ] eof )
                | ws* identifier { ws+ argument } ws+ "{" ws* "}"
                  ( [ ws* [ comment ] newline ] | ws* [ comment ] eof ) ;

block-item      = empty-line
                | block
                | directive ;

(* Directives: Must contain at least one argument *)
directive       = ws* identifier { ws+ argument }+ ws* [ comment ] ( newline | eof ) ;

(* Tokens *)
identifier      = id-start { id-continue } ;
id-start        = "a".."z" | "A".."Z" | "_" ;
id-continue     = id-start | "0".."9" | "-" ;

argument        = quoted-string
                | single-string
                | bare-word ;

bare-word       = bare-char { bare-char } ;
bare-char       = ? any UTF-8 char except ' ', '\t', '\r', '\n', '{', '}', '#', '"', '\'' ? ;

quoted-string   = '"' { quoted-char | escape-seq } '"' ;
quoted-char     = ? any UTF-8 char except '"', '\\', '\r', '\n' ? ;
escape-seq      = "\\" ( '"' | "\\" | "n" | "r" | "t" ) ;

single-string   = "'" { single-char } "'" ;
single-char     = ? any UTF-8 char except '\'', '\r', '\n' ? ;

(* Whitespace & Comments *)
empty-line      = ws* [ comment ] newline ;
comment         = "#" { ? any UTF-8 char except '\r', '\n' ? } ;
ws              = " " | "\t" ;
newline         = "\n" | "\r\n" ;
```

## 4. Domain Schema: Root Blocks, Sub-Blocks & Directives

At nesting depth `0`, TDF defines three root block types: `task`, `location`, and `category`. Any other root block identifier MUST be rejected with an `UnknownBlockType` error.

### 4.1 The `task` Block (Tasks)

Every task is represented as an independent `task` block at the root level (nesting depth `0`).

```text
task <id> [priority] {
    ...
}
```

#### 4.1.1 Header Parameters
1. `<id>` (**Required**, Bare Word): Unique identifier for the task across all `task` blocks in the document.
   - Sequential IDs (`t001`, `t002`, `t003`, ...) or descriptive single-word IDs (`taxes2026`, `backup_check`) are permitted.
2. `priority` (**Optional**, Bare Word Flag): Controls sorting precedence within the active pull cycle (see Section 5.4):
   - **When present:** Marks the task as prioritized so that it sorts ahead of all regular tasks in the active cycle (ordered chronologically by `queued` among prioritized tasks).
   - **When omitted:** The task is treated as a regular task and sorts strictly in ascending chronological order by its `queued` timestamp (FIFO) after any prioritized tasks.

#### 4.1.2 Directives in `task`

| Directive | Required | Multiplicity | Format / Arguments | Semantics When Present / Omitted |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Human-readable title of the task. Required in every `task` block. |
| `created` | Yes | `1` | `<YYYY-MM-DD> [<HH:MM>]` | Creation timestamp of the task. Required in every `task` block. |
| `queued` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM>]` | Timestamp governing ascending FIFO ordering in the active cycle. **When omitted** (and `finished` is omitted), the task is classified as `Someday` and excluded from the active cycle. |
| `finished` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM>]` | Completion timestamp. **When present**, the task is classified as `Completed` and subject to garbage collection once older than $30$ days. **When omitted**, the task is open. |
| `note` | No | `0..1` | `"<text>"` | Optional extended description or note. **When omitted**, the task has no extended note. |
| `locations` | No | `0..1` | `<id1> [<id2> ...]` | *(Draft)* One or more `location` IDs. **When omitted**, the task is location-independent and matches every location context. |
| `categories` | No | `0..1` | `<id1> [<id2> ...]` | *(Draft)* One or more `category` IDs associated with the task. **When omitted**, the task has no category assignment. |
| `blocked` | No | `0..1` | `<task_id1> [<task_id2> ...]` | IDs of prerequisite tasks. **When present**, the task is classified as `Blocked` if at least one referenced task exists in the document without a `finished` directive. **When omitted**, no task-dependency block applies. |
| `suspended` | No | `0..1` | `<YYYY-MM-DD> [<HH:MM>]` | Deferral / snooze timestamp. **When present**, the task is classified as `Blocked` while the timestamp lies strictly in the future. **When omitted**, no time-deferral block applies. |
| `condition` | No | `0..N` | `<type> <arg1> [<arg2> ...]` | *(Draft)* Dynamic activation condition. Multiple `condition` directives are combined with logical `AND`. **When omitted**, no dynamic condition restricts the task. |

#### 4.1.3 Sub-Block `subtasks` (Checklists)

Inside a `task` block (at nesting depth `1`), an optional `subtasks` sub-block (at most one per `task`) defines an ordered checklist:

```text
subtasks [auto-finish] {
    step <true|false> "<text>"
}
```

- `auto-finish` (**Optional Header Flag**):
  - **When present:** As soon as all contained `step` directives have the value `true`, the enclosing `task` automatically transitions to completed (`finished` is set to the current timestamp).
  - **When omitted:** Completing all `step` directives does not automatically set `finished` on the enclosing `task`.
- `step <bool> "<text>"` (**Repeatable Directive**): Defines a single checklist step where `false` indicates open and `true` indicates completed. The top-to-bottom declaration order of `step` directives is preserved.

#### 4.1.4 Options for `condition` (Draft / Work in Progress)

> [!NOTE]
> The `condition` directive is currently a draft specification and is not yet finalized.

To keep the grammar flat, dynamic conditions are written as single-line key-tuple directives:
- `condition day <mon|tue|wed|thu|fri|sat|sun ...>`: The task is active only on the specified weekdays (e.g., `condition day sat sun`).
- `condition time <HH:MM> <HH:MM>`: The task is active only within the daily time window between the start and end times (e.g., `condition time 08:00 17:00`).

### 4.2 The `location` Block (Locations — Draft / Work in Progress)

> [!NOTE]
> The `location` block and its geofencing / filtering semantics are currently in draft status and not yet finalized.

Defines a named location at nesting depth `0` that tasks can reference via the `locations` directive.

```text
location <id> {
    name "<display_name>"
    note "<optional_description>"
    gps  <latitude> <longitude> [<radius_in_meters>]
}
```

| Directive | Required | Multiplicity | Format / Arguments | Description |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Human-readable display name of the location (e.g., `"Work"`). |
| `note` | No | `0..1` | `"<text>"` | Optional description of the location. |
| `gps` | No | `0..1` | `<lat> <lon> [<radius>]` | Optional decimal coordinates and optional radius in meters for geofencing or automatic location selection. |

### 4.3 The `category` Block (Categories — Draft / Work in Progress)

> [!NOTE]
> The `category` block and its context-filtering semantics are currently in draft status and not yet finalized.

Defines a named category (work context) at nesting depth `0` by which tasks can be filtered.

```text
category <id> {
    name  "<display_name>"
    color "<hex_color_code>"
    note  "<optional_description>"
}
```

| Directive | Required | Multiplicity | Format / Arguments | Description |
| :--- | :--- | :--- | :--- | :--- |
| `name` | Yes | `1` | `"<text>"` | Human-readable display name of the category (e.g., `"Household"`). |
| `color` | No | `0..1` | `"#RRGGBB"` | Optional hexadecimal color code associated with the category. |
| `note` | No | `0..1` | `"<text>"` | Optional description of the category. |

## 5. Dynamic Computation of the 6 Tiers (Evaluation Pipeline)

When evaluating a `.tdf` document against a reference timestamp and optional context filters (`category` and `location`), the six tiers are derived deterministically in a single $O(N)$ pipeline across all `task` blocks:

### 5.1 Tier 6 — `Completed`
- **Selection Rule:** All tasks that possess a `finished` directive.
- **Garbage Collection (30-Day Retention Pruning):** Tasks whose `finished` timestamp lies strictly more than $30$ days ($> 30$ days) in the past relative to the evaluation timestamp are removed when persisting the document.

### 5.2 Tier 5 — `Someday`
- **Selection Rule:** All open tasks (`finished` is absent) that do NOT possess a `queued` directive.
- **Behavior:** These tasks form the unscheduled backlog and do not participate in the active pull cycle.

### 5.3 Tier 4 — `Blocked`
- **Selection Rule:** All scheduled open tasks (`queued` is present and `finished` is absent) for which **at least one** of the following blocking conditions holds at the evaluation timestamp:
  1. **Unfinished Prerequisite (`blocked`):** At least one task ID referenced in the task's `blocked` directive exists in the document and does not have a `finished` directive.
  2. **Future Deferral (`suspended`):** The task's `suspended` timestamp lies strictly in the future.
  3. **Unmet Condition (`condition`, Draft):** At least one `condition` directive on the task is not satisfied at the evaluation timestamp.

### 5.4 Active Pull Cycle (`Focus`, `Ready`, `Planned`)
All remaining scheduled, unblocked, open tasks (`queued` is present, `finished` is absent, and none of the Section 5.3 blocking criteria apply) enter the active cycle pipeline:

1. **Step 1 — Context Filtering (Draft):**
   - From the remaining active tasks, select those matching the active `category` and `location` context filters.
   - Tasks without a `locations` directive are location-independent and match every location filter.
2. **Step 2 — Deterministic Sorting:**
   - **Primary Group (`priority` Flag Present):** Tasks carrying the `priority` header flag are placed ahead of regular tasks and sorted among themselves in ascending chronological order by their `queued` timestamp.
   - **Secondary Group (`priority` Flag Omitted — Regular FIFO):** Regular tasks follow in ascending chronological order by their `queued` timestamp (oldest timestamp first = FIFO).
   - **Tie-Breaking:** Tasks with identical `priority` status and identical `queued` timestamps preserve their relative document declaration order.
3. **Step 3 — Slot Slicing:**
   - **Tier 1 — `Focus` (Positions $1$ to $3$):** The first up to `3` tasks of the sorted list (indices `0..2`).
   - **Tier 2 — `Ready` (Positions $4$ to $8$):** The next up to `5` tasks of the sorted list (indices `3..7`).
   - **Tier 3 — `Planned` (Position $9$ onward):** All remaining tasks of the sorted list (indices $\ge 8$).

## 6. State Transitions & Document Mutations

State transitions mutate the task directives and header flags in the `.tdf` document rather than moving tasks between static tier sections:

### 6.1 Creating a New Task
- **For `Planned` (Default):** Sets both `created` and `queued` to the current timestamp (`now`). If `Focus` or `Ready` has open capacity (< 3 or < 5 tasks), the slicing pipeline (Section 5.4) places the task into the corresponding higher tier automatically.
- **For `Someday`:** Sets `created` to the current timestamp (`now`) and omits `queued`.
- **For Immediate `Focus` / High Priority:** Sets `created` and `queued` to `now` and adds the `priority` flag to the `task` block header.

### 6.2 Scheduling a Task from `Someday`
- Adds the `queued` directive set to the current timestamp (`now`).

### 6.3 Full Downgrade (`Ready` -> `Planned`)
- Removes any `priority` flag from the `task` header and updates `queued` to the current timestamp (`now`).
- Because `now` is newer than existing `queued` timestamps in the active cycle, the downgraded task sorts to the end of `Planned` (preventing the ping-pong effect) while the task at position $9$ (`Planned`) advances into position $8$ (`Ready`).

### 6.4 Minor Downgrade (`Focus` -> End of `Ready`)
- Removes any `priority` flag from the `task` header and sets the task's `queued` timestamp immediately after the `queued` timestamp of the task currently at position $8$ (the end of `Ready`).
- Consequently, the task at position $4$ (`Ready`) advances to position $3$ (`Focus`), and the downgraded task occupies position $8$ at the end of `Ready`.

### 6.5 Completing a Task
- Adds the `finished` directive set to the current timestamp (`now`).
- The task exits the active cycle into `Completed`, causing position $4$ (`Ready`) to advance to position $3$ (`Focus`) and position $9$ (`Planned`) to advance to position $8$ (`Ready`).

## 7. Conformance & Resource Bounds

To guarantee bounded memory usage and prevent denial-of-service on malformed inputs, a conforming TDF parser MUST enforce the following resource limits before scanning or allocating the $(N+1)$-th element:

| Bound Name | Default Limit | Purpose |
| :--- | :--- | :--- |
| `MAX_FILE_BYTES` | `1_048_576` (1 MiB) | Maximum input size in bytes before rejecting the document. |
| `MAX_LINE_COUNT` | `16_384` | Maximum logical lines per `.tdf` document. |
| `MAX_NESTING_DEPTH` | `2` | Maximum `{ ... }` block nesting depth (`1` for root blocks, `2` for `subtasks`). |
| `MAX_BLOCKS_PER_DOC` | `4_096` | Maximum total blocks (`task`, `location`, `category`, `subtasks`) per document. |
| `MAX_STMTS_PER_BLOCK` | `512` | Maximum directives or sub-blocks inside a single block. |
| `MAX_ARGS_PER_STMT` | `64` | Maximum arguments allowed on a single block header or directive. |
| `MAX_TEXT_LENGTH` | `500` | Maximum character length of a `name` or `step` text value. |

## 8. Mandatory Error Conditions

A conforming TDF parser MUST report a structured error (including the 1-based line number) and MUST fail deterministically on any of the following inputs:

- **Root Directive (`UnexpectedRootDirective`):** A directive (e.g., `name "Test"`) appears at nesting depth `0` outside of any `{ ... }` block.
- **Missing Argument or Brace (`MissingDirectiveArgument`):** A single identifier appears on a line without arguments and without an opening `{` (e.g., `queued` with no timestamp value).
- **Quoted or Invalid Identifier (`InvalidIdentifier`):** A block or directive name is quoted (e.g., `"task" t001 {` or `"name" "Test"`) or starts with an invalid character (e.g., `123task {` or `-flag val`).
- **Missing Whitespace Before Brace (`InvalidBlockHeader`):** The opening `{` is attached directly to the identifier or argument without whitespace (e.g., `task t001{` or `subtasks{`).
- **Trailing Tokens After Brace (`UnexpectedToken`):** Non-comment tokens appear on the same line after `{` (except `}`) or after `}`.
- **Unclosed Block (`UnclosedBlock`):** `EOF` is reached while nesting depth $> 0$.
- **Unmatched Closing Brace (`UnexpectedClosingBrace`):** `}` is encountered at nesting depth `0`.
- **Unterminated Quote (`UnterminatedString`):** A `"` or `'` string reaches `\r`, `\n`, or `EOF` before its matching closing quote.
- **Adjacent Quoted Token (`UnexpectedToken`):** A quote opens or closes in the middle of a token without separating whitespace (e.g., `foo"bar"` or `"foo"bar`).
- **Invalid Escape (`InvalidEscapeSequence`):** A `"` string contains an unknown escape sequence (e.g., `\a`, `\x`, `\0`).
- **Schema Validation Errors:**
  - `UnknownBlockType`: Root block is not `task`, `location`, or `category`, or nested block inside `task` is not `subtasks`.
  - `UnknownDirective`: A directive name is not valid for its enclosing block.
  - `MissingRequiredDirective`: A required directive (`name` or `created` in `task`, `name` in `location` or `category`) is missing.
  - `DuplicateDirective`: A single-valued directive appears more than once in the same block.
  - `DuplicateIdentifier`: Two blocks in the same namespace share an identical `<id>`.
  - `InvalidTimestamp` / `InvalidBoolean` / `InvalidNumber`: A directive argument fails semantic format validation.
- **Limit Exceeded (`LimitExceeded`):** Any resource bound defined in Section 7 is exceeded.

## 9. Canonical Complete Example (`tiertask.tdf`)

```text
# ==========================================
# TierTask Data Format (TDF) Example Document
# ==========================================

# === Locations (Draft) ===
location home {
    name "Home"
}

location work {
    name "Work"
    gps  50.9787 11.0328 150
}

# === Categories (Draft) ===
category c_house {
    name  "Household"
    color "#4CAF50"
}

category c_it {
    name  "IT & Servers"
    color "#2196F3"
}

# === Tasks ===

# Prioritized task -> Lands at the top of Focus (in c_it)
task t001 priority {
    name       "Verify server backup"
    note       "Inspect logs under /var/log/backup"
    created    2026-11-01 08:30
    queued     2026-11-01 08:30
    categories c_it
}

# Regular active task with subtasks -> Focus / Ready
task t002 {
    name       "Clean up study"
    created    2026-11-01 09:00
    queued     2026-11-01 09:15
    locations  home
    categories c_house

    subtasks auto-finish {
        step true  "Wipe desk"
        step false "Organize cables"
        step false "Empty trash bin"
    }
}

# Task in multiple categories with condition (weekends only)
task t003 {
    name       "Clean dust from NAS drives"
    created    2026-11-01 10:00
    queued     2026-11-01 10:00
    locations  home
    categories c_house c_it
    condition  day sat sun
}

# Blocked task (waits for t001 and is suspended until Nov 5)
task t004 {
    name       "Apply firewall update"
    created    2026-11-01 11:00
    queued     2026-11-01 11:00
    locations  work
    categories c_it
    blocked    t001
    suspended  2026-11-05 08:00
}

# Task in "Someday" (no 'queued' directive present)
task t005 {
    name       "3D-print custom NAS enclosure"
    created    2026-11-01 12:00
    categories c_it
}

# Completed task ('finished' is set -> deleted after 30 days)
task t006 {
    name       "Mount winter tires"
    created    2026-10-20 14:00
    queued     2026-10-21 08:00
    finished   2026-10-29 16:45
    locations  home
}
```
