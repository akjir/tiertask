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

import 'package:flutter/foundation.dart';

/// Normative default deadline urgency lead-window duration (`DEFAULT_DUE_LEAD_SECONDS` = `86,400`, `24` hours).
const int defaultDueLeadSeconds = 86400;

/// Maximum arguments allowed on a single block header or directive (`MAX_ARGS_PER_STMT` = `64`).
const int maxTdfArgsPerStmt = 64;

/// Maximum total blocks per `.tdf` document (`MAX_BLOCKS_PER_DOC` = `4,096`).
const int maxTdfBlocksPerDoc = 4096;

/// Maximum `completions` counter, deletion checkpoint, or `blocked` threshold (`MAX_COMPLETIONS` = `9,007,199,254,740,991`).
const int maxTdfCompletions = 9007199254740991;

/// Maximum stored condition rules across all inline directives and condition blocks on one entity (`MAX_CONDITION_RULES_PER_ENTITY` = `512`).
const int maxTdfConditionRulesPerEntity = 512;

/// Maximum total deletion records inside `deleted` (`MAX_DELETED_RECORDS` = `4,096`).
const int maxTdfDeletedRecords = 4096;

/// Maximum input or serialized output size in UTF-8 bytes (`MAX_FILE_BYTES` = `1,048,576`, 1 MiB).
const int maxTdfFileBytes = 1048576;

/// Maximum `history` entries per `task` block (`MAX_HISTORY_PER_TASK` = `500`).
const int maxTdfHistoryPerTask = 500;

/// Maximum logical lines per `.tdf` document (`MAX_LINE_COUNT` = `16,384`).
const int maxTdfLineCount = 16384;

/// Maximum `link` entries per `label` block (`MAX_LINKS_PER_LABEL` = `20`).
const int maxTdfLinksPerLabel = 20;

/// Maximum `link` entries per `task` block (`MAX_LINKS_PER_TASK` = `20`).
const int maxTdfLinksPerTask = 20;

/// Maximum `radius` in meters (`100 km`) for a `location` block (`MAX_LOCATION_RADIUS` = `100,000`).
const int maxTdfLocationRadius = 100000;

/// Maximum `<location-id>` references across all `location` condition rules on one entity before deduplication (`MAX_LOCATION_REFS_PER_ENTITY` = `63`).
const int maxTdfLocationRefsPerEntity = 63;

/// Maximum root-level `location` blocks per `.tdf` document (`MAX_LOCATIONS` = `200`).
const int maxTdfLocations = 200;

/// Maximum `{ ... }` block nesting depth (`MAX_NESTING_DEPTH` = `2`).
const int maxTdfNestingDepth = 2;

/// Maximum decoded Unicode scalar values in a `note` text value (`MAX_NOTE_LENGTH` = `2,000`).
const int maxTdfNoteLength = 2000;

/// Maximum raw ASCII characters in a `<number>` token (`MAX_NUMBER_LENGTH` = `24`).
const int maxTdfNumberLength = 24;

/// Maximum `task` entries inside `queue` (`MAX_QUEUE_ENTRIES` = `4,096`).
const int maxTdfQueueEntries = 4096;

/// Maximum `<count>` or `<lead-count>` in `repeat` (`MAX_REPEAT_COUNT` = `3,650`).
const int maxTdfRepeatCount = 3650;

/// Maximum direct child statements per ordinary block (`MAX_STMTS_PER_BLOCK` = `1,024`).
const int maxTdfStmtsPerBlock = 1024;

/// Maximum `deleted.generation` value (`MAX_SYNC_GENERATION` = `9,007,199,254,740,991`).
const int maxTdfSyncGeneration = 9007199254740991;

/// Maximum decoded Unicode scalar values in a `name`, `step`, or link `<title>` (`MAX_TEXT_LENGTH` = `500`).
const int maxTdfTextLength = 500;

/// Maximum decoded Unicode scalar values in any `link` `<uri>` argument (`MAX_URI_LENGTH` = `2,048`).
const int maxTdfUriLength = 2048;

/// Mandatory lexical, structural, and semantic error categories defined in `TDF_SPEC.md` Section 8.
enum TdfErrorKind {
  /// A task's `blocked` dependency chain forms a cycle or self-dependency.
  circularDependency,

  /// A single-valued directive or sub-block appears more than once in the same block.
  duplicateDirective,

  /// Two blocks, deletion records, or queue entries in the same namespace share an identical `<id>`.
  duplicateIdentifier,

  /// A required text argument (`name`, `step` `<text>`, or `link` `<title>` / `<uri>`) is empty or whitespace-only after unescaping.
  emptyText,

  /// A block header is malformed or missing whitespace before `{`.
  invalidBlockHeader,

  /// A boolean literal is neither `true` nor `false`.
  invalidBoolean,

  /// A `color` argument is unquoted or fails `#RRGGBB` hexadecimal validation.
  invalidColor,

  /// A task has `finished` present while its effective `completions` counter is `0`.
  invalidCompletionState,

  /// A condition rule has an invalid weekday, equal time window, out-of-range GPS coordinate/radius, or invalid reset.
  invalidCondition,

  /// A double-quoted string contains an unsupported backslash escape sequence.
  invalidEscapeSequence,

  /// A block/directive identifier or entity ID is quoted or fails canonical format validation.
  invalidIdentifier,

  /// A numeric argument, generation counter, completion count, or prerequisite count fails decimal validation.
  invalidNumber,

  /// Queue entries do not match the exact set of live scheduled open tasks.
  invalidQueueMembership,

  /// A repeat clock (`<repeat-time>`) is quoted or outside `00:00:00..23:59:59`.
  invalidTime,

  /// A timestamp or time-window argument fails ISO-8601 calendar or 24-hour clock validation.
  invalidTimestamp,

  /// A `link` `<uri>` argument does not start with a valid scheme (`[a-zA-Z][a-zA-Z0-9+.-]*:`) or contains control characters.
  invalidUri,

  /// A resource bound defined in `TDF_SPEC.md` Section 7 was exceeded.
  limitExceeded,

  /// A standalone directive identifier appears without arguments and without `{`.
  missingDirectiveArgument,

  /// A required directive (`name`, `created`, `generation`, `modified`, `step`, or condition rule) is missing from a block.
  missingRequiredDirective,

  /// The document contains no statements or does not begin with `tdf <version>`.
  missingVersionHeader,

  /// End-of-file was reached while one or more `{ ... }` blocks remained open.
  unclosedBlock,

  /// A closing brace `}` was encountered at nesting depth `0`.
  unexpectedClosingBrace,

  /// A directive appears at nesting depth `0` outside of any `{ ... }` block.
  unexpectedRootDirective,

  /// An unexpected token, control character, trailing token after a brace, or adjacent quote was encountered.
  unexpectedToken,

  /// A root or nested block identifier is not part of the TDF schema.
  unknownBlockType,

  /// A directive identifier is not valid for its enclosing block.
  unknownDirective,

  /// A task's `labels` directive references an `<id>` that does not match any `label` block in the document.
  unknownLabelReference,

  /// A `condition` `location` rule references a `<location-id>` that does not match any live `location` block in the document.
  unknownLocationReference,

  /// The initial `tdf <version>` header specifies an unsupported or malformed version.
  unsupportedVersion,

  /// A double-quoted or single-quoted string reached end-of-line or EOF before its closing quote.
  unterminatedString,
}

/// Structured exception thrown when scanning, parsing, validating, or serializing a `.tdf` document fails.
@immutable
class TdfException implements Exception {
  /// Creates a [TdfException] for [kind] at 1-based [line] with [message].
  const TdfException({
    required this.kind,
    required this.line,
    required this.message,
    this.sourceVersion,
  });

  /// Normative error category from `spec/TDF_SPEC_0.8.0.md` Appendix A.1.1.
  final TdfErrorKind kind;

  /// 1-based line number where the error occurred.
  final int line;

  /// Human-readable diagnostic description.
  final String message;

  /// Optional offending `<version>` token when [kind] is [TdfErrorKind.unsupportedVersion].
  final String? sourceVersion;

  @override
  String toString() => 'TdfException(${kind.name}, line $line): $message';
}
