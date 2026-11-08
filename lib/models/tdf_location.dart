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

/// Base62 alphabet (`0-9`, `A-Z`, `a-z`) for TDF entity identifiers.
const String _base62Alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// Fixed length of a TDF `<location-id>` (`10`).
const int _entityIdLength = 10;

/// Modulo divisor `62^4` (`14,776,336` seconds) for the 4-character Base62 timestamp suffix.
const int _timeModulo = 14776336;

/// Immutable representation of a TDF `location <location-id> { ... }` root block (`spec/TDF_SPEC_0.6.0.md` Section 4.3).
@immutable
class TdfLocation {
  /// Creates a [TdfLocation] definition.
  const TdfLocation({
    required this.id,
    required this.name,
    this.note,
    this.source,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.modifiedAt,
    String? rawLatitudeText,
    String? rawLongitudeText,
    String? rawRadiusText,
  }) : _latitudeText = rawLatitudeText,
       _longitudeText = rawLongitudeText,
       _radiusText = rawRadiusText;

  /// Fallback UTC modification timestamp (`1970-01-01 00:00:00` UTC) when a `location` block omits `modified` (`spec/TDF_SPEC_0.6.0.md` Section 6.7.1).
  static final DateTime defaultModifiedAt = DateTime.utc(1970, 1, 1, 0, 0, 0);

  /// Unique 10-character Base62 location identifier (`<location-id>`).
  final String id;

  /// WGS-84 latitude in decimal degrees (`[-90.0, 90.0]`).
  final double latitude;

  /// WGS-84 longitude in decimal degrees (`[-180.0, 180.0]`).
  final double longitude;

  /// Optional UTC modification timestamp (`modified` directive).
  final DateTime? modifiedAt;

  /// Human-readable single-line place name (`name` directive).
  final String name;

  /// Optional extended description (`note` directive).
  final String? note;

  /// Geofencing radius in meters (`0 < radius <= 100000`).
  final double radius;

  /// Optional passive single-line address or location code (`source` directive).
  final String? source;

  final String? _latitudeText;
  final String? _longitudeText;
  final String? _radiusText;

  /// Effective UTC modification timestamp (`modifiedAt ?? defaultModifiedAt`).
  DateTime get effectiveModifiedAt => modifiedAt ?? defaultModifiedAt;

  /// Canonical normalized decimal representation of [latitude] per Section 6.7.3.
  String get latitudeText => _latitudeText ?? formatRoundedDouble(latitude, 6);

  /// Canonical normalized decimal representation of [longitude] per Section 6.7.3.
  String get longitudeText =>
      _longitudeText ?? formatRoundedDouble(longitude, 6);

  /// Canonical normalized decimal representation of [radius] per Section 6.7.3.
  String get radiusText => _radiusText ?? formatRoundedDouble(radius, 2);

  /// Returns a copy of this location with updated fields.
  TdfLocation copyWith({
    String? id,
    String? name,
    String? note,
    bool clearNote = false,
    String? source,
    bool clearSource = false,
    double? latitude,
    double? longitude,
    double? radius,
    DateTime? modifiedAt,
    bool clearModifiedAt = false,
    String? latitudeText,
    String? longitudeText,
    String? radiusText,
  }) {
    final nextLat = latitude ?? this.latitude;
    final nextLon = longitude ?? this.longitude;
    final nextRad = radius ?? this.radius;
    return TdfLocation(
      id: id ?? this.id,
      name: name ?? this.name,
      note: clearNote ? null : (note ?? this.note),
      source: clearSource ? null : (source ?? this.source),
      latitude: nextLat == 0.0 ? 0.0 : nextLat,
      longitude: nextLon == 0.0 ? 0.0 : nextLon,
      radius: nextRad,
      modifiedAt: clearModifiedAt ? null : (modifiedAt ?? this.modifiedAt),
      rawLatitudeText:
          latitudeText ?? (latitude != null ? null : _latitudeText),
      rawLongitudeText:
          longitudeText ?? (longitude != null ? null : _longitudeText),
      rawRadiusText: radiusText ?? (radius != null ? null : _radiusText),
    );
  }

  /// Counts the significant fractional decimal digits of [rawDecimal] after stripping trailing zeros.
  static int countSignificantFractionalDigits(String rawDecimal) {
    final normalized = normalizeDecimalText(rawDecimal);
    final dotIndex = normalized.indexOf('.');
    if (dotIndex < 0) {
      return 0;
    }
    return normalized.length - dotIndex - 1;
  }

  /// Formats [value] rounded `half-away-from-zero` to at most [maxDecimals] fractional digits in Section 6.7.3 canonical form.
  static String formatRoundedDouble(double value, int maxDecimals) {
    if (value == 0.0 || value.isNaN || value.isInfinite) {
      return '0';
    }
    final fixed = value.toStringAsFixed(maxDecimals + 2);
    return roundDecimalHalfAwayFromZero(fixed, maxDecimals);
  }

  /// Checks whether [raw] is a valid finite ASCII decimal literal (`-?[0-9]+(\.[0-9]+)?`).
  static bool isValidNumberToken(String raw) {
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
    var hasIntegerDigits = false;
    while (index < raw.length) {
      final unit = raw.codeUnitAt(index);
      if (unit >= 0x30 && unit <= 0x39) {
        hasIntegerDigits = true;
        index++;
      } else {
        break;
      }
    }
    if (!hasIntegerDigits) {
      return false;
    }
    if (index < raw.length) {
      if (raw.codeUnitAt(index) != 0x2E || index == raw.length - 1) {
        return false;
      }
      index++;
      while (index < raw.length) {
        final unit = raw.codeUnitAt(index);
        if (unit < 0x30 || unit > 0x39) {
          return false;
        }
        index++;
      }
    }
    final parsed = double.tryParse(raw);
    return parsed != null && !parsed.isNaN && !parsed.isInfinite;
  }

  /// Normalizes a valid ASCII decimal literal per `spec/TDF_SPEC_0.6.0.md` Section 6.7.3
  /// (strips redundant leading integer zeros, trailing fractional zeros, empty fractional part, and normalizes `-0` to `0`).
  static String normalizeDecimalText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '0';
    }
    final isNegative = trimmed.codeUnitAt(0) == 0x2D;
    final unsigned = isNegative ? trimmed.substring(1) : trimmed;
    final dotIndex = unsigned.indexOf('.');
    final rawInt = dotIndex < 0 ? unsigned : unsigned.substring(0, dotIndex);
    final rawFrac = dotIndex < 0 ? '' : unsigned.substring(dotIndex + 1);

    var intStart = 0;
    while (intStart < rawInt.length - 1 &&
        rawInt.codeUnitAt(intStart) == 0x30) {
      intStart++;
    }
    final normInt = rawInt.isEmpty ? '0' : rawInt.substring(intStart);

    var fracEnd = rawFrac.length;
    while (fracEnd > 0 && rawFrac.codeUnitAt(fracEnd - 1) == 0x30) {
      fracEnd--;
    }
    final normFrac = rawFrac.substring(0, fracEnd);

    if (normInt == '0' && normFrac.isEmpty) {
      return '0';
    }
    final sign = isNegative ? '-' : '';
    if (normFrac.isEmpty) {
      return '$sign$normInt';
    }
    return '$sign$normInt.$normFrac';
  }

  /// Rounds a valid ASCII decimal string [rawDecimal] to at most [maxDecimals] fractional digits
  /// using exact `half-away-from-zero` decimal arithmetic, then normalizes it under Section 6.7.3.
  static String roundDecimalHalfAwayFromZero(
    String rawDecimal,
    int maxDecimals,
  ) {
    final trimmed = rawDecimal.trim();
    if (!isValidNumberToken(trimmed)) {
      return normalizeDecimalText(trimmed);
    }
    final isNegative = trimmed.codeUnitAt(0) == 0x2D;
    final unsigned = isNegative ? trimmed.substring(1) : trimmed;
    final dotIndex = unsigned.indexOf('.');
    if (dotIndex < 0) {
      return normalizeDecimalText(trimmed);
    }
    final intPart = unsigned.substring(0, dotIndex);
    final fracPart = unsigned.substring(dotIndex + 1);
    if (fracPart.length <= maxDecimals) {
      return normalizeDecimalText(trimmed);
    }
    final keptFrac = maxDecimals == 0 ? '' : fracPart.substring(0, maxDecimals);
    final nextDigit = fracPart.codeUnitAt(maxDecimals) - 0x30;
    var scaled = BigInt.parse('$intPart$keptFrac');
    if (nextDigit >= 5) {
      scaled += BigInt.one;
    }
    if (scaled == BigInt.zero) {
      return '0';
    }
    final scaledDigits = scaled.toString().padLeft(maxDecimals + 1, '0');
    final splitOffset = scaledDigits.length - maxDecimals;
    final roundedInt = scaledDigits.substring(0, splitOffset);
    final roundedFrac = maxDecimals == 0
        ? ''
        : scaledDigits.substring(splitOffset);
    final sign = isNegative ? '-' : '';
    final candidate = maxDecimals == 0
        ? '$sign$roundedInt'
        : '$sign$roundedInt.$roundedFrac';
    return normalizeDecimalText(candidate);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfLocation &&
        other.id == id &&
        other.name == name &&
        other.note == note &&
        other.source == source &&
        other.latitudeText == latitudeText &&
        other.longitudeText == longitudeText &&
        other.radiusText == radiusText &&
        other.modifiedAt == modifiedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    note,
    source,
    latitudeText,
    longitudeText,
    radiusText,
    modifiedAt,
  );

  @override
  String toString() => 'location $id';
}

/// Generates a unique 10-character TDF 0.6.0 location identifier (`<6xBase62Random><4xBase62Time>`).
String generateLocationId({
  DateTime? timestamp,
  Set<String> existingIds = const <String>{},
}) {
  final resolvedTime = timestamp ?? DateTime.now().toUtc();
  final utcSeconds = resolvedTime.toUtc().millisecondsSinceEpoch ~/ 1000;
  final normalizedTime =
      ((utcSeconds % _timeModulo) + _timeModulo) % _timeModulo;
  final timePart = _encodeBase62Fixed(normalizedTime, 4);
  final random = math.Random.secure();
  while (true) {
    final units = List<int>.filled(6, 0x30);
    for (var i = 0; i < 6; i++) {
      units[i] = _base62Alphabet.codeUnitAt(random.nextInt(62));
    }
    final candidate = '${String.fromCharCodes(units)}$timePart';
    if (!existingIds.contains(candidate)) {
      return candidate;
    }
  }
}

/// Checks whether [value] is a canonical 10-character TDF 0.6.0 location identifier (`[0-9A-Za-z]{10}`).
bool isValidLocationId(String value) {
  if (value.length != _entityIdLength) {
    return false;
  }
  for (var i = 0; i < _entityIdLength; i++) {
    final unit = value.codeUnitAt(i);
    final isBase62 =
        (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A);
    if (!isBase62) {
      return false;
    }
  }
  return true;
}

/// Encodes non-negative integer [value] into a fixed-width Base62 string of [width] characters, left-padded with `'0'`.
String _encodeBase62Fixed(int value, int width) {
  final units = List<int>.filled(width, 0x30);
  var remaining = value < 0 ? 0 : value;
  for (var i = width - 1; i >= 0; i--) {
    final digit = remaining % 62;
    units[i] = _base62Alphabet.codeUnitAt(digit);
    remaining ~/= 62;
  }
  return String.fromCharCodes(units);
}
