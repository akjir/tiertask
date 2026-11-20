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

import '../models/tdf_error.dart';

/// Lexical category of a scanned token in a TDF `0.8.0` document.
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

/// Start, end, and next code-unit offset of a single logical TDF line.
@immutable
class TdfLineSpan {
  /// Creates a [TdfLineSpan].
  const TdfLineSpan({
    required this.lineStart,
    required this.lineEnd,
    required this.nextOffset,
  });

  /// Exclusive end offset of the line content before `LF` or `CRLF`.
  final int lineEnd;

  /// Inclusive start offset of the line content in the source string.
  final int lineStart;

  /// Start offset of the next physical line (or `source.length` at `EOF`).
  final int nextOffset;
}

/// Lexical token scanned from a single logical TDF line.
@immutable
class TdfScannedToken {
  /// Creates a [TdfScannedToken].
  const TdfScannedToken({required this.value, required this.kind});

  /// Lexical category of this token.
  final TdfTokenKind kind;

  /// Decoded string content of this token.
  final String value;

  /// Whether this token is an unquoted [TdfTokenKind.bareWord].
  bool get isBare => kind == TdfTokenKind.bareWord;

  /// Whether this token is a [TdfTokenKind.quotedString].
  bool get isQuoted => kind == TdfTokenKind.quotedString;
}

/// Stateless single-pass lexical scanner for `spec/TDF_SPEC_0.8.0.md` Section 3.
@immutable
class TdfScanner {
  /// Prevents instantiation of this stateless helper class.
  const TdfScanner._();

  /// Throws a [TdfException] with [kind], 1-based [line], and [message].
  static Never fail(TdfErrorKind kind, int line, String message) =>
      throw TdfException(kind: kind, line: line, message: message);

  /// Finds the end of the line starting at [startOffset] and validates line terminators, control characters, and UTF-16 surrogates.
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
        _requireCrLfPair(source, index, line);
        return TdfLineSpan(
          lineStart: startOffset,
          lineEnd: index,
          nextOffset: index + 2,
        );
      }
      index = _advanceValidatedLineCodeUnit(source, index, unit, line);
    }
    return TdfLineSpan(
      lineStart: startOffset,
      lineEnd: source.length,
      nextOffset: source.length,
    );
  }

  /// Checks whether [codeUnit] is an ASCII decimal digit (`0-9`).
  static bool isAsciiDigit(int codeUnit) =>
      codeUnit >= 0x30 && codeUnit <= 0x39;

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
      _ensureTokenCapacityBeforeScan(source, cursor, line, tokens);
      cursor = _scanNextToken(source, cursor, lineEnd, line, tokens);
    }
    return tokens;
  }

  /// Validates a non-terminator UTF-16 code unit (or surrogate pair) at [index] and returns the next code-unit index.
  static int _advanceValidatedLineCodeUnit(
    String source,
    int index,
    int unit,
    int line,
  ) {
    if ((unit < 0x20 && unit != 0x09) || unit == 0x7F) {
      fail(TdfErrorKind.unexpectedToken, line, 'Invalid control character.');
    }
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      final low = index + 1 < source.length ? source.codeUnitAt(index + 1) : 0;
      if (low < 0xDC00 || low > 0xDFFF) {
        fail(TdfErrorKind.unexpectedToken, line, 'Unpaired high surrogate.');
      }
      return index + 2;
    }
    if (unit >= 0xDC00 && unit <= 0xDFFF) {
      fail(TdfErrorKind.unexpectedToken, line, 'Unpaired low surrogate.');
    }
    return index + 1;
  }

  /// Checks whether [tokens] already contains an opening `{` or closing `}` brace token.
  static bool _containsBraceToken(List<TdfScannedToken> tokens) {
    for (final token in tokens) {
      if (token.kind == TdfTokenKind.openBrace ||
          token.kind == TdfTokenKind.closeBrace) {
        return true;
      }
    }
    return false;
  }

  /// Enforces `MAX_ARGS_PER_STMT = 64` before scanning the next token at [cursor] (`TDF-VAL-001`, `TDF-VAL-002`).
  static void _ensureTokenCapacityBeforeScan(
    String source,
    int cursor,
    int line,
    List<TdfScannedToken> tokens,
  ) {
    if (tokens.length < maxTdfArgsPerStmt + 1) {
      return;
    }
    if (_containsBraceToken(tokens)) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Non-comment tokens after brace.',
      );
    }
    if (tokens.length == maxTdfArgsPerStmt + 1 &&
        source.codeUnitAt(cursor) == 0x7B) {
      return;
    }
    fail(TdfErrorKind.limitExceeded, line, 'Too many statement arguments.');
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

  /// Ensures a carriage return (`0x0D`) at [crIndex] is immediately followed by `LF` (`0x0A`).
  static void _requireCrLfPair(String source, int crIndex, int line) {
    if (crIndex + 1 >= source.length ||
        source.codeUnitAt(crIndex + 1) != 0x0A) {
      fail(TdfErrorKind.unexpectedToken, line, 'Standalone CR without LF.');
    }
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

  /// Appends one literal or escaped unit from [source] at [cursor] into [buffer] and returns the next cursor.
  static int _scanDoubleQuotedContentUnit(
    String source,
    int cursor,
    int lineEnd,
    int line,
    StringBuffer buffer,
  ) {
    final unit = source.codeUnitAt(cursor);
    if (unit != 0x5C) {
      buffer.writeCharCode(unit);
      return cursor + 1;
    }
    if (cursor + 1 >= lineEnd) {
      fail(TdfErrorKind.unterminatedString, line, 'Unterminated escape.');
    }
    buffer.writeCharCode(_unescapeChar(source.codeUnitAt(cursor + 1), line));
    return cursor + 2;
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
      if (source.codeUnitAt(cursor) == 0x22) {
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
      cursor = _scanDoubleQuotedContentUnit(
        source,
        cursor,
        lineEnd,
        line,
        buffer,
      );
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
