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

import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_timezone.dart';

/// Lexical category of a scanned token in a TDF document.
enum TdfTokenKind {
  /// Unquoted bare word (`[a-zA-Z0-9_-]`, numbers, dates, etc.).
  bareWord,

  /// Closing block brace `}`.
  closeBrace,

  /// Opening block brace `{`.
  openBrace,

  /// Double-quoted or single-quoted string literal.
  quotedString,
}

/// Represents the start, end, and next offset of a single logical TDF line.
@immutable
class TdfLineSpan {
  /// Creates a [TdfLineSpan].
  const TdfLineSpan({
    required this.lineStart,
    required this.lineEnd,
    required this.nextOffset,
  });

  final int lineEnd;
  final int lineStart;
  final int nextOffset;
}

/// Lexical token scanned from a single logical TDF line.
@immutable
class TdfScannedToken {
  /// Creates a [TdfScannedToken].
  const TdfScannedToken({required this.value, required this.kind});

  final TdfTokenKind kind;
  final String value;

  /// Whether this token is an unquoted [TdfTokenKind.bareWord].
  bool get isBare => kind == TdfTokenKind.bareWord;

  /// Whether this token is a [TdfTokenKind.quotedString].
  bool get isQuoted => kind == TdfTokenKind.quotedString;
}

/// Stateless lexical scanner and literal validator for `TDF_SPEC.md` Section 2.
@immutable
class TdfScanner {
  /// Private constructor to prevent instantiation.
  const TdfScanner._();

  /// Counts Unicode scalar values in [text] and throws [TdfErrorKind.unexpectedToken] on unpaired surrogates.
  static int countUnicodeScalars(String text, [int line = 1]) =>
      TdfCalendar.countUnicodeScalars(text) ??
      fail(TdfErrorKind.unexpectedToken, line, 'Unpaired surrogate.');

  /// Throws a [TdfException] with [kind], 1-based [line], and [message].
  static Never fail(TdfErrorKind kind, int line, String message) =>
      throw TdfException(kind: kind, line: line, message: message);

  /// Finds the end of the line starting at [startOffset] and validates line terminators, control chars, and UTF-16 surrogates.
  static TdfLineSpan findLineSpan(String source, int startOffset, int line) {
    var index = startOffset;
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit == 0x0A) {
        return TdfLineSpan(
          lineStart: startOffset,
          lineEnd: index,
          nextOffset: index + 1,
        );
      }
      if (unit == 0x0D) {
        if (index + 1 >= source.length ||
            source.codeUnitAt(index + 1) != 0x0A) {
          fail(TdfErrorKind.unexpectedToken, line, 'Standalone CR without LF.');
        }
        return TdfLineSpan(
          lineStart: startOffset,
          lineEnd: index,
          nextOffset: index + 2,
        );
      }
      if ((unit < 0x20 && unit != 0x09) || unit == 0x7F) {
        fail(TdfErrorKind.unexpectedToken, line, 'Invalid control character.');
      }
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        final low = index + 1 < source.length
            ? source.codeUnitAt(index + 1)
            : 0;
        if (low < 0xDC00 || low > 0xDFFF) {
          fail(TdfErrorKind.unexpectedToken, line, 'Unpaired high surrogate.');
        }
        index += 2;
        continue;
      }
      if (unit >= 0xDC00 && unit <= 0xDFFF) {
        fail(TdfErrorKind.unexpectedToken, line, 'Unpaired low surrogate.');
      }
      index++;
    }
    return TdfLineSpan(
      lineStart: startOffset,
      lineEnd: source.length,
      nextOffset: source.length,
    );
  }

  /// Finds the first index of [kind] in [tokens], or `-1` if absent.
  static int findTokenKindIndex(
    List<TdfScannedToken> tokens,
    TdfTokenKind kind,
  ) {
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].kind == kind) {
        return i;
      }
    }
    return -1;
  }

  /// Checks whether [codeUnit] is an ASCII decimal digit (`0-9`).
  static bool isAsciiDigit(int codeUnit) =>
      codeUnit >= 0x30 && codeUnit <= 0x39;

  /// Checks whether [raw] matches `0` (when [allowZero] is `true`) or `[1-9][0-9]*`.
  static bool isValidCanonicalUnsignedInt(
    String raw, {
    required bool allowZero,
  }) {
    if (raw.isEmpty) {
      return false;
    }
    if (raw == '0') {
      return allowZero;
    }
    final first = raw.codeUnitAt(0);
    if (first < 0x31 || first > 0x39) {
      return false;
    }
    for (var i = 1; i < raw.length; i++) {
      if (!isAsciiDigit(raw.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  /// Checks whether [raw] matches `-?[0-9]+(\.[0-9]+)?` without using regular expressions.
  static bool isValidDecimalLiteral(String raw) {
    if (raw.isEmpty) {
      return false;
    }
    var index = 0;
    if (raw.codeUnitAt(0) == 0x2D) {
      if (raw.length == 1) {
        return false;
      }
      index = 1;
    }
    var hasLeadingDigits = false;
    while (index < raw.length && isAsciiDigit(raw.codeUnitAt(index))) {
      hasLeadingDigits = true;
      index++;
    }
    if (!hasLeadingDigits) {
      return false;
    }
    if (index == raw.length) {
      return true;
    }
    if (raw.codeUnitAt(index) != 0x2E || index == raw.length - 1) {
      return false;
    }
    for (var i = index + 1; i < raw.length; i++) {
      if (!isAsciiDigit(raw.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  /// Checks whether [value] is a strict `#RRGGBB` hexadecimal color string.
  static bool isValidHexColor(String value) => TdfColor.isStrictHexColor(value);

  /// Validates that [value] matches the TDF identifier rule (`[a-zA-Z_][a-zA-Z0-9_-]*`).
  static bool isValidIdentifier(String value) {
    if (value.isEmpty || !_isIdStartChar(value.codeUnitAt(0))) {
      return false;
    }
    for (var i = 1; i < value.length; i++) {
      if (!_isIdContinueChar(value.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  /// Checks whether [value] is a valid `<HH:MM[:SS]>` repeat clock literal.
  static bool isValidRepeatClock(String value) =>
      TdfRepeatClock.tryParse(value) != null;

  /// Checks whether [uri] begins with a valid URI scheme and contains no control characters.
  static bool isValidUriScheme(String uri) => TaskLink.isValidUri(uri);

  /// Validates and parses a canonical unsigned integer [raw] within `[allowZero ? 0 : 1, maxAllowed]`.
  static int parseCanonicalInt(
    String raw,
    int line,
    int maxAllowed, {
    bool allowZero = true,
  }) {
    final bigVal = isValidCanonicalUnsignedInt(raw, allowZero: allowZero)
        ? BigInt.tryParse(raw)
        : null;
    if (bigVal == null) {
      fail(TdfErrorKind.invalidNumber, line, 'Invalid integer "$raw".');
    }
    if (bigVal > BigInt.from(maxAllowed)) {
      fail(TdfErrorKind.limitExceeded, line, 'Integer > $maxAllowed.');
    }
    return bigVal.toInt();
  }

  /// Validates and parses `<YYYY-MM-DD> [<HH:MM[:SS]>]` into a canonical UTC [DateTime].
  static DateTime parseCanonicalUtcTimestamp(
    String dateToken,
    int line, [
    String? timeToken,
  ]) =>
      TaskItem.tryParseTdfTimestamp(dateToken, timeToken) ??
      fail(TdfErrorKind.invalidTimestamp, line, 'Invalid UTC timestamp.');

  /// Validates and parses `<HH:MM>` into minutes since midnight (`0..1439`).
  static int parseLocalClockMinutes(String token, int line) =>
      TaskItem.tryParseTimeMinutes(token) ??
      fail(TdfErrorKind.invalidTimestamp, line, 'Invalid <HH:MM> time.');

  /// Scans all lexical tokens on `[lineStart, lineEnd)` in a single $O(N)$ pass.
  static List<TdfScannedToken> scanLineTokens(
    String source,
    int lineStart,
    int lineEnd,
    int line,
  ) {
    final tokens = <TdfScannedToken>[];
    var cursor = lineStart;
    while (cursor < lineEnd) {
      cursor = _skipHorizontalWhitespace(source, cursor, lineEnd);
      if (cursor >= lineEnd || source.codeUnitAt(cursor) == 0x23) {
        break;
      }
      if (tokens.length >= maxTdfArgsPerStmt + 3) {
        fail(TdfErrorKind.limitExceeded, line, 'Too many statement arguments.');
      }
      cursor = _scanNextToken(source, cursor, lineEnd, line, tokens);
    }
    return tokens;
  }

  /// Validates that [text] contains no disallowed ASCII control characters.
  static void validateNoControlCharacters(
    String text, {
    required int lineNumber,
  }) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if ((unit < 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) ||
          unit == 0x7F) {
        fail(TdfErrorKind.unexpectedToken, lineNumber, 'Invalid control char.');
      }
    }
  }

  /// Checks whether [codeUnit] is an ASCII alphanumeric, underscore, or hyphen (`[a-zA-Z0-9_-]`).
  static bool _isIdContinueChar(int codeUnit) =>
      _isIdStartChar(codeUnit) || isAsciiDigit(codeUnit) || codeUnit == 0x2D;

  /// Checks whether [codeUnit] is an ASCII alphabetic character or underscore (`[a-zA-Z_]`).
  static bool _isIdStartChar(int codeUnit) =>
      (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
      codeUnit == 0x5F;

  /// Checks whether [codeUnit] is a disallowed control or non-ASCII whitespace character outside quotes and comments.
  static bool _isInvalidBareChar(int codeUnit) {
    if (codeUnit < 0x20 || codeUnit == 0x7F) {
      return true;
    }
    return codeUnit == 0x0085 ||
        codeUnit == 0x00A0 ||
        codeUnit == 0x1680 ||
        (codeUnit >= 0x2000 && codeUnit <= 0x200A) ||
        codeUnit == 0x2028 ||
        codeUnit == 0x2029 ||
        codeUnit == 0x202F ||
        codeUnit == 0x205F ||
        codeUnit == 0x3000 ||
        codeUnit == 0xFEFF;
  }

  /// Scans an unquoted bare word token starting at [start].
  static int _scanBareWordToken(
    String source,
    int start,
    int lineEnd,
    int line,
    List<TdfScannedToken> tokens,
  ) {
    var cursor = start;
    while (cursor < lineEnd) {
      final unit = source.codeUnitAt(cursor);
      if (unit == 0x20 || unit == 0x09 || unit == 0x23) {
        break;
      }
      if (unit == 0x7B) {
        fail(TdfErrorKind.invalidBlockHeader, line, 'Brace "{" needs space.');
      }
      if (unit == 0x7D ||
          unit == 0x22 ||
          unit == 0x27 ||
          _isInvalidBareChar(unit)) {
        fail(TdfErrorKind.unexpectedToken, line, 'Invalid bare word token.');
      }
      cursor++;
    }
    tokens.add(
      TdfScannedToken(
        value: source.substring(start, cursor),
        kind: TdfTokenKind.bareWord,
      ),
    );
    return cursor;
  }

  /// Scans a double-quoted string token (`"..."`) starting at [start].
  static int _scanDoubleQuotedToken(
    String source,
    int start,
    int lineEnd,
    int line,
    List<TdfScannedToken> tokens,
  ) {
    final buffer = StringBuffer();
    var cursor = start + 1;
    while (cursor < lineEnd) {
      final unit = source.codeUnitAt(cursor);
      if (unit == 0x22) {
        final nextCursor = cursor + 1;
        _validatePostQuoteDelimiter(source, nextCursor, lineEnd, line);
        tokens.add(
          TdfScannedToken(
            value: buffer.toString(),
            kind: TdfTokenKind.quotedString,
          ),
        );
        return nextCursor;
      }
      if (unit == 0x5C) {
        if (cursor + 1 >= lineEnd) {
          fail(TdfErrorKind.unterminatedString, line, 'Unterminated escape.');
        }
        buffer.writeCharCode(
          _unescapeChar(source.codeUnitAt(cursor + 1), line),
        );
        cursor += 2;
      } else {
        buffer.writeCharCode(unit);
        cursor++;
      }
    }
    fail(TdfErrorKind.unterminatedString, line, 'Unterminated string.');
  }

  /// Scans a single token starting at [cursor] and appends it to [tokens].
  static int _scanNextToken(
    String source,
    int cursor,
    int lineEnd,
    int line,
    List<TdfScannedToken> tokens,
  ) {
    final unit = source.codeUnitAt(cursor);
    if (unit == 0x7B) {
      tokens.add(
        const TdfScannedToken(value: '{', kind: TdfTokenKind.openBrace),
      );
      return cursor + 1;
    }
    if (unit == 0x7D) {
      tokens.add(
        const TdfScannedToken(value: '}', kind: TdfTokenKind.closeBrace),
      );
      return cursor + 1;
    }
    if (unit == 0x22) {
      return _scanDoubleQuotedToken(source, cursor, lineEnd, line, tokens);
    }
    if (unit == 0x27) {
      return _scanSingleQuotedToken(source, cursor, lineEnd, line, tokens);
    }
    return _scanBareWordToken(source, cursor, lineEnd, line, tokens);
  }

  /// Scans a single-quoted literal string token (`'...'`) starting at [start].
  static int _scanSingleQuotedToken(
    String source,
    int start,
    int lineEnd,
    int line,
    List<TdfScannedToken> tokens,
  ) {
    var cursor = start + 1;
    while (cursor < lineEnd) {
      if (source.codeUnitAt(cursor) == 0x27) {
        final nextCursor = cursor + 1;
        _validatePostQuoteDelimiter(source, nextCursor, lineEnd, line);
        tokens.add(
          TdfScannedToken(
            value: source.substring(start + 1, cursor),
            kind: TdfTokenKind.quotedString,
          ),
        );
        return nextCursor;
      }
      cursor++;
    }
    fail(TdfErrorKind.unterminatedString, line, 'Unterminated string.');
  }

  /// Advances [cursor] past horizontal whitespace (`' '` and `'\t'`).
  static int _skipHorizontalWhitespace(String source, int cursor, int lineEnd) {
    var index = cursor;
    while (index < lineEnd) {
      final unit = source.codeUnitAt(index);
      if (unit != 0x20 && unit != 0x09) {
        break;
      }
      index++;
    }
    return index;
  }

  /// Resolves a double-quoted escape character (`\"`, `\\`, `\n`, `\r`, `\t`).
  static int _unescapeChar(int escapedUnit, int line) => switch (escapedUnit) {
    0x22 => 0x22,
    0x5C => 0x5C,
    0x6E => 0x0A,
    0x72 => 0x0D,
    0x74 => 0x09,
    _ => fail(TdfErrorKind.invalidEscapeSequence, line, 'Invalid escape.'),
  };

  /// Validates the character immediately following a closing quote.
  static void _validatePostQuoteDelimiter(
    String source,
    int nextCursor,
    int lineEnd,
    int line,
  ) {
    if (nextCursor >= lineEnd) {
      return;
    }
    final nextUnit = source.codeUnitAt(nextCursor);
    if (nextUnit == 0x20 || nextUnit == 0x09 || nextUnit == 0x23) {
      return;
    }
    if (nextUnit == 0x7B) {
      fail(TdfErrorKind.invalidBlockHeader, line, 'Brace "{" needs space.');
    }
    fail(TdfErrorKind.unexpectedToken, line, 'Adjacent token after quote.');
  }
}
