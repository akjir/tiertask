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

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/location_state.dart';
import '../models/tdf_error.dart';

/// Parsed full Open Location Code with an optional human-readable [localitySuffix].
@immutable
final class FullPlusCodeInput extends PlusCodeInput {
  /// Creates a [FullPlusCodeInput].
  const FullPlusCodeInput({required this.fullCode, this.localitySuffix});

  /// Canonical uppercase full Open Location Code (for example, `'9F2PXXH7+F4'`).
  final String fullCode;

  /// Optional normalized single-line locality suffix following or preceding [fullCode].
  final String? localitySuffix;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FullPlusCodeInput &&
        other.fullCode == fullCode &&
        other.localitySuffix == localitySuffix;
  }

  @override
  int get hashCode => Object.hash(fullCode, localitySuffix);

  @override
  String toString() =>
      'FullPlusCodeInput(fullCode: $fullCode, localitySuffix: $localitySuffix)';
}

/// Represents an input string that is not a valid Open Location Code.
@immutable
final class InvalidPlusCodeInput extends PlusCodeInput {
  /// Creates an [InvalidPlusCodeInput].
  const InvalidPlusCodeInput();

  @override
  bool operator ==(Object other) => other is InvalidPlusCodeInput;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'InvalidPlusCodeInput()';
}

/// Decoded WGS-84 bounding box and center coordinates for a full Open Location Code.
@immutable
class PlusCodeArea {
  /// Creates a [PlusCodeArea] bounding box.
  const PlusCodeArea({
    required this.latitudeHi,
    required this.latitudeLo,
    required this.longitudeHi,
    required this.longitudeLo,
  });

  /// Northern latitude bound in decimal degrees (`[-90.0, 90.0]`).
  final double latitudeHi;

  /// Southern latitude bound in decimal degrees (`[-90.0, 90.0]`).
  final double latitudeLo;

  /// Eastern longitude bound in decimal degrees (`[-180.0, 180.0]`).
  final double longitudeHi;

  /// Western longitude bound in decimal degrees (`[-180.0, 180.0]`).
  final double longitudeLo;

  /// Center latitude of the decoded cell clamped to `[-90.0, 90.0]`.
  double get latitudeCenter =>
      ((latitudeLo + latitudeHi) / 2.0).clamp(-90.0, 90.0);

  /// Center longitude of the decoded cell clamped to `[-180.0, 180.0]`.
  double get longitudeCenter =>
      ((longitudeLo + longitudeHi) / 2.0).clamp(-180.0, 180.0);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlusCodeArea &&
        other.latitudeLo == latitudeLo &&
        other.latitudeHi == latitudeHi &&
        other.longitudeLo == longitudeLo &&
        other.longitudeHi == longitudeHi;
  }

  @override
  int get hashCode =>
      Object.hash(latitudeLo, latitudeHi, longitudeLo, longitudeHi);

  @override
  String toString() =>
      'PlusCodeArea(lat: [$latitudeLo, $latitudeHi], lon: [$longitudeLo, $longitudeHi])';
}

/// Sealed result of parsing a user-entered Open Location Code input string.
@immutable
sealed class PlusCodeInput {
  /// Creates a [PlusCodeInput].
  const PlusCodeInput();
}

/// Stateless Open Location Code (Google Plus Code) parser, decoder, encoder, and nearest-locality recovery service.
final class PlusCodeService {
  /// Private constructor to prevent instantiation.
  const PlusCodeService._();

  /// Base-20 character alphabet defined by the Open Location Code specification.
  static const String alphabet = '23456789CFGHJMPQRVWX';

  /// Number of grid refinement digits allowed after the first 10 pair digits.
  static const int gridCodeLength = 5;

  /// Maximum number of base-20 digits in an Open Location Code (excluding `'+'`).
  static const int maxDigitCount = 15;

  /// Maximum character length accepted when parsing a Plus Code input string.
  static const int maxInputLength = 500;

  /// Number of base-20 digits in the 5-pair prefix/suffix section (`10`).
  static const int pairCodeLength = 10;

  /// Index of the `'+'` separator in a full Open Location Code (`8`).
  static const int separatorPosition = 8;

  /// Number of columns in the $5 \times 4$ grid refinement step.
  static const int _gridColumns = 4;

  /// Number of rows in the $5 \times 4$ grid refinement step.
  static const int _gridRows = 5;

  /// Classifies an optional TDF `location.source` string into a [LocationSourceType].
  static LocationSourceType classifySource(String? rawSource) {
    if (rawSource == null) {
      return LocationSourceType.gps;
    }
    if (rawSource.length > maxInputLength) {
      return LocationSourceType.address;
    }
    final trimmed = rawSource.trim();
    if (trimmed.isEmpty) {
      return LocationSourceType.gps;
    }
    final lower = trimmed.toLowerCase();
    if (lower == 'gps' || lower == 'manual') {
      return LocationSourceType.gps;
    }
    return switch (parseInput(trimmed)) {
      FullPlusCodeInput() ||
      ShortPlusCodeInput() => LocationSourceType.plusCode,
      InvalidPlusCodeInput() => LocationSourceType.address,
    };
  }

  /// Decodes a full Open Location Code into a [PlusCodeArea], or returns `null` if invalid.
  static PlusCodeArea? decode(String fullCode) {
    if (fullCode.length > maxInputLength) {
      return null;
    }
    final trimmed = fullCode.trim();
    if (!isFullCode(trimmed)) {
      return null;
    }
    final digits = _extractCleanDigits(trimmed);
    if (digits.isEmpty) {
      return null;
    }

    var latitudeLow = -90.0;
    var longitudeLow = -180.0;
    var latitudePlaceValue = 400.0;
    var longitudePlaceValue = 400.0;

    final pairLimit = math.min(digits.length, pairCodeLength);
    for (var i = 0; i < pairLimit; i += 2) {
      latitudePlaceValue /= 20.0;
      longitudePlaceValue /= 20.0;
      latitudeLow += digits[i] * latitudePlaceValue;
      longitudeLow += digits[i + 1] * longitudePlaceValue;
    }

    for (var i = pairCodeLength; i < digits.length; i++) {
      latitudePlaceValue /= _gridRows;
      longitudePlaceValue /= _gridColumns;
      final digit = digits[i];
      final row = digit ~/ _gridColumns;
      final column = digit % _gridColumns;
      latitudeLow += row * latitudePlaceValue;
      longitudeLow += column * longitudePlaceValue;
    }

    return PlusCodeArea(
      latitudeLo: latitudeLow,
      latitudeHi: (latitudeLow + latitudePlaceValue).clamp(-90.0, 90.0),
      longitudeLo: longitudeLow,
      longitudeHi: (longitudeLow + longitudePlaceValue).clamp(-180.0, 180.0),
    );
  }

  /// Encodes WGS-84 [latitude] and [longitude] into a full Open Location Code of length [codeLength].
  static String encode(
    double latitude,
    double longitude, {
    int codeLength = pairCodeLength,
  }) {
    var targetLength = codeLength.clamp(2, maxDigitCount);
    if (targetLength < pairCodeLength && targetLength.isOdd) {
      targetLength -= 1;
    }
    final clippedLatitude = _clipLatitude(latitude, targetLength);
    final normalizedLongitude = _normalizeLongitude(longitude);

    final latitudeDigits = List<int>.filled(maxDigitCount, 0);
    final longitudeDigits = List<int>.filled(maxDigitCount, 0);
    final gridDigits = List<int>.filled(gridCodeLength, 0);

    var latitudeValue = ((clippedLatitude + 90.0) * 8000.0 * 3125.0).floor();
    var longitudeValue = ((normalizedLongitude + 180.0) * 8000.0 * 1024.0)
        .floor();

    for (var i = gridCodeLength - 1; i >= 0; i--) {
      final row = latitudeValue % _gridRows;
      final column = longitudeValue % _gridColumns;
      gridDigits[i] = row * _gridColumns + column;
      latitudeValue ~/= _gridRows;
      longitudeValue ~/= _gridColumns;
    }

    for (var i = 4; i >= 0; i--) {
      latitudeDigits[i] = latitudeValue % 20;
      longitudeDigits[i] = longitudeValue % 20;
      latitudeValue ~/= 20;
      longitudeValue ~/= 20;
    }

    final buffer = StringBuffer();
    final pairCount = math.min(targetLength, pairCodeLength) ~/ 2;
    for (var i = 0; i < pairCount; i++) {
      buffer.write(alphabet[latitudeDigits[i]]);
      buffer.write(alphabet[longitudeDigits[i]]);
      if (buffer.length == separatorPosition) {
        buffer.write('+');
      }
    }

    if (targetLength < separatorPosition) {
      for (var i = targetLength; i < separatorPosition; i++) {
        buffer.write('0');
      }
      buffer.write('+');
      return buffer.toString();
    }

    for (var i = pairCodeLength; i < targetLength; i++) {
      buffer.write(alphabet[gridDigits[i - pairCodeLength]]);
    }
    return buffer.toString();
  }

  /// Returns `true` when [code] is a syntactically valid full Open Location Code.
  static bool isFullCode(String code) {
    if (!_isValidCodeCharacters(code)) {
      return false;
    }
    final plusIndex = code.indexOf('+');
    if (plusIndex != separatorPosition) {
      return false;
    }
    final firstLatitudeDigit = _digitValue(code.codeUnitAt(0));
    final firstLongitudeDigit = _digitValue(code.codeUnitAt(1));
    if (firstLatitudeDigit == null || firstLongitudeDigit == null) {
      return false;
    }
    return firstLatitudeDigit * 20 < 180 && firstLongitudeDigit * 20 < 360;
  }

  /// Returns `true` when [code] is a syntactically valid short Open Location Code (`plusIndex < 8`, no `'0'` padding).
  static bool isShortCode(String code) {
    if (!_isValidCodeCharacters(code)) {
      return false;
    }
    final plusIndex = code.indexOf('+');
    return plusIndex >= 0 &&
        plusIndex < separatorPosition &&
        !code.contains('0');
  }

  /// Replaces `\r`, `\n`, and `\t` with ASCII spaces, strips C0/C1 control characters and lone surrogates, collapses consecutive spaces, trims, and truncates to at most [maxScalarValues] Unicode scalar values.
  static String normalizeSingleLineText(
    String rawText, {
    int maxScalarValues = maxTdfTextLength,
  }) {
    if (rawText.isEmpty || maxScalarValues <= 0) {
      return '';
    }
    final buffer = StringBuffer();
    var lastWasSpace = true;
    var scalarCount = 0;
    for (final rune in rawText.runes) {
      final isWhitespace =
          rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D;
      if (isWhitespace) {
        if (!lastWasSpace && scalarCount < maxScalarValues) {
          buffer.writeCharCode(0x20);
          scalarCount++;
          lastWasSpace = true;
        }
        continue;
      }
      if (rune < 0x20 ||
          (rune >= 0x7F && rune <= 0x9F) ||
          (rune >= 0xD800 && rune <= 0xDFFF)) {
        continue;
      }
      if (scalarCount >= maxScalarValues) {
        break;
      }
      buffer.writeCharCode(rune);
      scalarCount++;
      lastWasSpace = false;
    }
    final result = buffer.toString();
    if (result.endsWith(' ')) {
      return result.substring(0, result.length - 1);
    }
    return result;
  }

  /// Parses [rawInput] into a [FullPlusCodeInput], [ShortPlusCodeInput], or [InvalidPlusCodeInput].
  static PlusCodeInput parseInput(String rawInput) {
    if (rawInput.length > maxInputLength) {
      return const InvalidPlusCodeInput();
    }
    final normalized = normalizeSingleLineText(
      rawInput,
      maxScalarValues: maxInputLength,
    );
    if (normalized.isEmpty || !normalized.contains('+')) {
      return const InvalidPlusCodeInput();
    }

    final tokens = normalized.split(' ');
    var codeTokenIndex = -1;
    var cleanCodeCandidate = '';
    for (var i = 0; i < tokens.length; i++) {
      final candidate = _stripLeadingTrailingCommas(tokens[i]);
      if (candidate.contains('+')) {
        if (codeTokenIndex != -1) {
          return const InvalidPlusCodeInput();
        }
        codeTokenIndex = i;
        cleanCodeCandidate = candidate.toUpperCase();
      }
    }
    if (codeTokenIndex == -1 || cleanCodeCandidate.isEmpty) {
      return const InvalidPlusCodeInput();
    }

    final locality = _joinRemainingLocalityTokens(tokens, codeTokenIndex);
    final plusIndex = cleanCodeCandidate.indexOf('+');
    final suffixLength = cleanCodeCandidate.length - plusIndex - 1;
    if (isFullCode(cleanCodeCandidate) && suffixLength >= 2) {
      return FullPlusCodeInput(
        fullCode: cleanCodeCandidate,
        localitySuffix: locality.isEmpty ? null : locality,
      );
    }

    if (isShortCode(cleanCodeCandidate) &&
        (plusIndex == 4 || plusIndex == 6) &&
        suffixLength >= 2 &&
        locality.isNotEmpty) {
      return ShortPlusCodeInput(
        localityQuery: locality,
        shortCode: cleanCodeCandidate,
      );
    }
    return const InvalidPlusCodeInput();
  }

  /// Reconstructs the nearest full Open Location Code from [shortCode] and reference coordinates.
  static String? recoverNearest(
    String shortCode,
    double referenceLatitude,
    double referenceLongitude,
  ) {
    if (shortCode.length > maxInputLength ||
        !referenceLatitude.isFinite ||
        !referenceLongitude.isFinite) {
      return null;
    }
    final clean = shortCode.trim().toUpperCase();
    if (isFullCode(clean)) {
      return clean;
    }
    if (!isShortCode(clean)) {
      return null;
    }

    referenceLatitude = referenceLatitude.clamp(-90.0, 90.0);
    referenceLongitude = _normalizeLongitude(referenceLongitude);
    final plusIndex = clean.indexOf('+');
    final paddingLength = separatorPosition - plusIndex;
    final resolution = _pow20(2 - (paddingLength ~/ 2));
    final halfResolution = resolution / 2.0;

    final prefix = encode(
      referenceLatitude,
      referenceLongitude,
    ).substring(0, paddingLength);
    final decoded = decode('$prefix$clean');
    if (decoded == null) {
      return null;
    }

    var latitude = decoded.latitudeCenter;
    if (referenceLatitude + halfResolution < latitude &&
        latitude - resolution >= -90.0) {
      latitude -= resolution;
    } else if (referenceLatitude - halfResolution > latitude &&
        latitude + resolution <= 90.0) {
      latitude += resolution;
    }

    var longitude = decoded.longitudeCenter;
    if (referenceLongitude + halfResolution < longitude) {
      longitude -= resolution;
    } else if (referenceLongitude - halfResolution > longitude) {
      longitude += resolution;
    }

    final adjustedPrefix = encode(
      latitude,
      longitude,
    ).substring(0, paddingLength);
    return '$adjustedPrefix$clean';
  }

  /// Normalizes and truncates [text] to a single-line string of at most [maxTdfTextLength] (`500`) Unicode scalar values.
  static String truncateToMaxTextLength(String text) =>
      normalizeSingleLineText(text, maxScalarValues: maxTdfTextLength);

  /// Strips commas adjacent to the Plus Code token at `tokenBeforeIndex + 1`.
  static String _cleanAdjacentLocalityToken(
    String token,
    int index,
    int tokenBeforeIndex,
  ) {
    if (index == tokenBeforeIndex) {
      return _stripTrailingCommas(token);
    }
    if (index == tokenBeforeIndex + 2) {
      return _stripLeadingCommas(token);
    }
    return token;
  }

  /// Clips [latitude] to `[-90.0, 90.0)` so `90.0` encodes inside the northernmost cell.
  static double _clipLatitude(double latitude, int codeLength) {
    if (!latitude.isFinite) {
      return 0.0;
    }
    final clamped = latitude.clamp(-90.0, 90.0);
    if (clamped < 90.0) {
      return clamped;
    }
    final double step;
    if (codeLength <= pairCodeLength) {
      step = _pow20((codeLength ~/ -2) + 2);
    } else {
      step = _pow20(-3) / math.pow(_gridRows, codeLength - pairCodeLength);
    }
    return 90.0 - (step / 2.0);
  }

  /// Maps an ASCII code unit to its base-20 digit index (`0..19`), or `null` if invalid.
  static int? _digitValue(int codeUnit) {
    final upper = codeUnit >= 0x61 && codeUnit <= 0x7A
        ? codeUnit - 0x20
        : codeUnit;
    return switch (upper) {
      0x32 => 0,
      0x33 => 1,
      0x34 => 2,
      0x35 => 3,
      0x36 => 4,
      0x37 => 5,
      0x38 => 6,
      0x39 => 7,
      0x43 => 8,
      0x46 => 9,
      0x47 => 10,
      0x48 => 11,
      0x4A => 12,
      0x4D => 13,
      0x50 => 14,
      0x51 => 15,
      0x52 => 16,
      0x56 => 17,
      0x57 => 18,
      0x58 => 19,
      _ => null,
    };
  }

  /// Extracts base-20 digit indices from [code], omitting `'+'` and `'0'` padding.
  static List<int> _extractCleanDigits(String code) {
    final digits = <int>[];
    for (var i = 0; i < code.length; i++) {
      final unit = code.codeUnitAt(i);
      if (unit == 0x2B || unit == 0x30) {
        continue;
      }
      final value = _digitValue(unit);
      if (value != null && digits.length < maxDigitCount) {
        digits.add(value);
      }
    }
    return digits;
  }

  /// Validates the structural character, padding, and separator rules of an Open Location Code.
  static bool _isValidCodeCharacters(String code) {
    if (code.isEmpty || code.length > maxInputLength) {
      return false;
    }
    final plusIndex = code.indexOf('+');
    if (plusIndex < 0 ||
        code.indexOf('+', plusIndex + 1) != -1 ||
        plusIndex > separatorPosition ||
        plusIndex.isOdd) {
      return false;
    }
    final suffixLength = code.length - plusIndex - 1;
    if (suffixLength == 1 || plusIndex + suffixLength > maxDigitCount) {
      return false;
    }

    var seenPadding = false;
    var firstPaddingIndex = -1;
    for (var i = 0; i < plusIndex; i++) {
      final unit = code.codeUnitAt(i);
      if (unit == 0x30) {
        if (!seenPadding) {
          seenPadding = true;
          firstPaddingIndex = i;
        }
        continue;
      }
      if (seenPadding || _digitValue(unit) == null) {
        return false;
      }
    }

    if (seenPadding) {
      if (plusIndex != separatorPosition ||
          firstPaddingIndex < 2 ||
          firstPaddingIndex.isOdd ||
          suffixLength > 0) {
        return false;
      }
    } else if (plusIndex < separatorPosition && suffixLength < 2) {
      return false;
    }

    for (var i = plusIndex + 1; i < code.length; i++) {
      if (_digitValue(code.codeUnitAt(i)) == null) {
        return false;
      }
    }
    return true;
  }

  /// Joins all tokens except [excludedIndex] into a trimmed locality query string.
  static String _joinRemainingLocalityTokens(
    List<String> tokens,
    int excludedIndex,
  ) {
    final buffer = StringBuffer();
    final tokenBeforeIndex = excludedIndex - 1;
    for (var i = 0; i < tokens.length; i++) {
      if (i == excludedIndex) {
        continue;
      }
      final cleaned = _cleanAdjacentLocalityToken(
        tokens[i],
        i,
        tokenBeforeIndex,
      );
      if (cleaned.isEmpty) {
        continue;
      }
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(cleaned);
    }
    return _stripLeadingTrailingCommas(buffer.toString()).trim();
  }

  /// Normalizes [longitude] into the half-open interval `[-180.0, 180.0)`.
  static double _normalizeLongitude(double longitude) {
    if (!longitude.isFinite) {
      return 0.0;
    }
    final shifted = (longitude + 180.0) % 360.0;
    final wrapped = shifted < 0.0 ? shifted + 360.0 : shifted;
    return wrapped - 180.0;
  }

  /// Computes $20^{\text{exponent}}$ as a double.
  static double _pow20(int exponent) => math.pow(20.0, exponent).toDouble();

  /// Strips leading comma characters from [token].
  static String _stripLeadingCommas(String token) {
    var start = 0;
    while (start < token.length && token.codeUnitAt(start) == 0x2C) {
      start++;
    }
    return token.substring(start);
  }

  /// Strips leading and trailing comma characters from [token].
  static String _stripLeadingTrailingCommas(String token) =>
      _stripTrailingCommas(_stripLeadingCommas(token));

  /// Strips trailing comma characters from [token].
  static String _stripTrailingCommas(String token) {
    var end = token.length;
    while (end > 0 && token.codeUnitAt(end - 1) == 0x2C) {
      end--;
    }
    return token.substring(0, end);
  }
}

/// Parsed short Open Location Code paired with a mandatory [localityQuery] for reference lookup.
@immutable
final class ShortPlusCodeInput extends PlusCodeInput {
  /// Creates a [ShortPlusCodeInput].
  const ShortPlusCodeInput({
    required this.localityQuery,
    required this.shortCode,
  });

  /// Normalized locality or city query string used to resolve the reference coordinates.
  final String localityQuery;

  /// Canonical uppercase short Open Location Code (`4` or `6` prefix digits before `'+'`).
  final String shortCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShortPlusCodeInput &&
        other.localityQuery == localityQuery &&
        other.shortCode == shortCode;
  }

  @override
  int get hashCode => Object.hash(localityQuery, shortCode);

  @override
  String toString() =>
      'ShortPlusCodeInput(shortCode: $shortCode, localityQuery: $localityQuery)';
}
