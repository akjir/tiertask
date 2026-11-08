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

import 'tdf_location.dart';

/// Canonical Base62 character alphabet (`0-9`, `A-Z`, `a-z`) defined in `TDF_SPEC.md` Section 2.9.
const String tdfBase62Alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// Modulo divisor `62^4` (`14,776,336` seconds) for the 4-character Base62 timestamp suffix.
const int tdfBase62TimeModulo = 14776336;

/// Fixed total character length of a TDF `<task-id>` or `<label-id>`.
const int tdfEntityIdLength = 10;

/// Canonical condition rule groups defined in `TDF_SPEC.md` Section 4.3.
enum ConditionGroup {
  /// Weekday rule group (`day`).
  day,

  /// Daily time-window rule group (`time`).
  time,

  /// Geographic proximity rule group (`location`).
  location,
}

/// Represents a dynamic activation condition (`condition` directive) on a TDF `label` or `task` block.
@immutable
sealed class TaskCondition {
  /// Creates a [TaskCondition].
  const TaskCondition();

  /// Rule group to which this condition belongs, or `null` for [GlobalResetTaskCondition].
  ConditionGroup? get group;

  /// Evaluates whether this condition is satisfied at [evaluationTime] and optional GPS coordinates.
  bool isSatisfiedAt(
    DateTime evaluationTime, {
    double? currentLatitude,
    double? currentLongitude,
    Map<String, TdfLocation> locations = const <String, TdfLocation>{},
  });

  /// Formats the condition arguments as a canonical TDF directive suffix.
  String toTdfDirectiveArgs();
}

/// Weekday activation condition (`day <mon|tue|wed|thu|fri|sat|sun ...>`).
@immutable
class DayTaskCondition extends TaskCondition {
  /// Creates a [DayTaskCondition] for the given [weekdays] (`1..7`) and [dayTokens].
  DayTaskCondition({
    required List<int> weekdays,
    required List<String> dayTokens,
  }) : weekdays = List<int>.unmodifiable(weekdays),
       dayTokens = List<String>.unmodifiable(dayTokens);

  /// Canonical lowercase weekday tokens in Monday-to-Sunday order.
  static const List<String> canonicalTokens = <String>[
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun',
  ];

  /// Canonical lowercase weekday tokens (`mon` through `sun`) in declaration order.
  final List<String> dayTokens;

  /// ISO-8601 weekday integers (`1` for Monday through `7` for Sunday).
  final List<int> weekdays;

  @override
  ConditionGroup get group => ConditionGroup.day;

  /// Builds a canonicalized [DayTaskCondition] from ISO-8601 [weekdays] (`1..7`).
  static DayTaskCondition fromWeekdays(Iterable<int> weekdays) {
    final weekdaySet = <int>{...weekdays};
    final orderedWeekdays = <int>[];
    final orderedTokens = <String>[];
    for (var weekday = 1; weekday <= 7; weekday++) {
      if (weekdaySet.contains(weekday)) {
        orderedWeekdays.add(weekday);
        orderedTokens.add(canonicalTokens[weekday - 1]);
      }
    }
    return DayTaskCondition(
      weekdays: orderedWeekdays,
      dayTokens: orderedTokens,
    );
  }

  @override
  bool isSatisfiedAt(
    DateTime evaluationTime, {
    double? currentLatitude,
    double? currentLongitude,
    Map<String, TdfLocation> locations = const <String, TdfLocation>{},
  }) {
    return weekdays.contains(evaluationTime.weekday);
  }

  /// Resolves an ISO-8601 weekday integer (`1` to `7`) from a TDF day token.
  static int? parseWeekdayToken(String token) {
    return switch (token) {
      'mon' => DateTime.monday,
      'tue' => DateTime.tuesday,
      'wed' => DateTime.wednesday,
      'thu' => DateTime.thursday,
      'fri' => DateTime.friday,
      'sat' => DateTime.saturday,
      'sun' => DateTime.sunday,
      _ => null,
    };
  }

  @override
  String toTdfDirectiveArgs() => 'day ${dayTokens.join(' ')}';

  /// Builds a canonicalized [DayTaskCondition] from [tokens], or returns `null` if empty or invalid.
  static DayTaskCondition? tryFromTokens(Iterable<String> tokens) {
    final tokenSet = <String>{};
    for (final rawToken in tokens) {
      final normalized = rawToken.trim();
      if (parseWeekdayToken(normalized) == null) {
        return null;
      }
      tokenSet.add(normalized);
    }
    if (tokenSet.isEmpty) {
      return null;
    }
    final orderedTokens = <String>[];
    final orderedWeekdays = <int>[];
    for (final canonical in canonicalTokens) {
      if (tokenSet.contains(canonical)) {
        if (parseWeekdayToken(canonical) case final weekday?) {
          orderedTokens.add(canonical);
          orderedWeekdays.add(weekday);
        }
      }
    }
    return DayTaskCondition(
      weekdays: orderedWeekdays,
      dayTokens: orderedTokens,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DayTaskCondition &&
        listEquals(other.weekdays, weekdays) &&
        listEquals(other.dayTokens, dayTokens);
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(weekdays), Object.hashAll(dayTokens));

  @override
  String toString() => 'condition ${toTdfDirectiveArgs()}';
}

/// Global condition reset (`condition any`) on a TDF `task` block that clears all inherited label conditions.
@immutable
class GlobalResetTaskCondition extends TaskCondition {
  /// Creates a const [GlobalResetTaskCondition].
  const GlobalResetTaskCondition();

  @override
  ConditionGroup? get group => null;

  @override
  bool isSatisfiedAt(
    DateTime evaluationTime, {
    double? currentLatitude,
    double? currentLongitude,
    Map<String, TdfLocation> locations = const <String, TdfLocation>{},
  }) {
    return true;
  }

  @override
  String toTdfDirectiveArgs() => 'any';

  @override
  bool operator ==(Object other) => other is GlobalResetTaskCondition;

  @override
  int get hashCode => 0x474C4F42;

  @override
  String toString() => 'condition any';
}

/// Group-specific condition reset (`day any`, `time any`, or `location any`) on a TDF `task` block.
@immutable
class GroupResetTaskCondition extends TaskCondition {
  /// Creates a [GroupResetTaskCondition] for [targetGroup].
  const GroupResetTaskCondition({required this.targetGroup});

  /// Condition group cleared by this reset directive.
  final ConditionGroup targetGroup;

  @override
  ConditionGroup get group => targetGroup;

  @override
  bool isSatisfiedAt(
    DateTime evaluationTime, {
    double? currentLatitude,
    double? currentLongitude,
    Map<String, TdfLocation> locations = const <String, TdfLocation>{},
  }) {
    return true;
  }

  @override
  String toTdfDirectiveArgs() => '${targetGroup.name} any';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupResetTaskCondition && other.targetGroup == targetGroup;
  }

  @override
  int get hashCode => targetGroup.hashCode;

  @override
  String toString() => 'condition ${toTdfDirectiveArgs()}';
}

/// Geographic proximity activation condition (`location <loc-1> [<loc-2> ...]` in TDF `0.6.0`, or legacy inline `location <lat> <lon> <radius>`).
@immutable
class LocationTaskCondition extends TaskCondition {
  /// Creates a [LocationTaskCondition] for [locationIds] (or legacy inline [latitude], [longitude], and [radiusMeters]).
  const LocationTaskCondition({
    this.locationIds = const <String>[],
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.radiusMeters = 0.0,
  }) : _latitudeText = null,
       _longitudeText = null,
       _radiusText = null;

  /// Creates a [LocationTaskCondition] preserving canonical raw decimal token texts.
  const LocationTaskCondition._(
    this.locationIds,
    this.latitude,
    this.longitude,
    this.radiusMeters,
    this._latitudeText,
    this._longitudeText,
    this._radiusText,
  );

  /// Creates a `0.6.0` ID-referenced [LocationTaskCondition] by deduplicating [rawLocationIds] in first-seen declaration order.
  factory LocationTaskCondition.fromIds(Iterable<String> rawLocationIds) {
    final deduplicated = <String>[];
    final seen = <String>{};
    for (final id in rawLocationIds) {
      if (seen.add(id)) {
        deduplicated.add(id);
      }
    }
    return LocationTaskCondition(
      locationIds: List<String>.unmodifiable(deduplicated),
    );
  }

  /// Mean Earth radius in meters used for Haversine distance evaluation (`spec/TDF_SPEC_0.6.0.md` Section 4.4.2).
  static const double earthRadiusMeters = 6371000.0;

  /// Legacy target WGS-84 latitude in decimal degrees (`-90.0..90.0`) for historical `0.2.0..0.5.1` rules.
  final double latitude;

  /// Referenced 10-character Base62 `<location-id>` tokens (`1..63`, deduplicated in first-seen declaration order).
  final List<String> locationIds;

  /// Legacy target WGS-84 longitude in decimal degrees (`-180.0..180.0`) for historical `0.2.0..0.5.1` rules.
  final double longitude;

  /// Legacy inclusive geofencing radius in meters (`> 0.0`) for historical `0.2.0..0.5.1` rules.
  final double radiusMeters;

  final String? _latitudeText;
  final String? _longitudeText;
  final String? _radiusText;

  @override
  ConditionGroup get group => ConditionGroup.location;

  /// Normalized decimal string representation of [latitude] per `TDF_SPEC.md` Section 6.7.3.
  String get latitudeText => _latitudeText ?? _formatDecimal(latitude);

  /// Normalized decimal string representation of [longitude] per `TDF_SPEC.md` Section 6.7.3.
  String get longitudeText => _longitudeText ?? _formatDecimal(longitude);

  /// Normalized decimal string representation of [radiusMeters] per `TDF_SPEC.md` Section 6.7.3.
  String get radiusText => _radiusText ?? _formatDecimal(radiusMeters);

  /// Computes the great-circle Haversine distance in meters between two WGS-84 coordinates.
  static double haversineDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = _degreesToRadians(lat1);
    final phi2 = _degreesToRadians(lat2);
    final deltaPhi = _degreesToRadians(lat2 - lat1);
    final deltaLambda = _degreesToRadians(lon2 - lon1);

    final sinHalfPhi = math.sin(deltaPhi / 2.0);
    final sinHalfLambda = math.sin(deltaLambda / 2.0);
    final a =
        sinHalfPhi * sinHalfPhi +
        math.cos(phi1) * math.cos(phi2) * sinHalfLambda * sinHalfLambda;
    final clampedA = a < 0.0 ? 0.0 : (a > 1.0 ? 1.0 : a);
    final c = 2.0 * math.atan2(math.sqrt(clampedA), math.sqrt(1.0 - clampedA));
    return earthRadiusMeters * c;
  }

  @override
  bool isSatisfiedAt(
    DateTime evaluationTime, {
    double? currentLatitude,
    double? currentLongitude,
    Map<String, TdfLocation> locations = const <String, TdfLocation>{},
  }) {
    if (currentLatitude == null || currentLongitude == null) {
      return true;
    }
    if (locationIds.isNotEmpty) {
      for (final id in locationIds) {
        if (locations[id] case final location?) {
          final distance = haversineDistanceMeters(
            location.latitude,
            location.longitude,
            currentLatitude,
            currentLongitude,
          );
          if (distance <= location.radius) {
            return true;
          }
        }
      }
      return false;
    }
    final distance = haversineDistanceMeters(
      latitude,
      longitude,
      currentLatitude,
      currentLongitude,
    );
    return distance <= radiusMeters;
  }

  /// Normalizes a valid ASCII decimal literal per `TDF_SPEC.md` Section 6.7.3
  /// (strips redundant leading integer zeros, trailing fractional zeros, empty
  /// fractional part, and normalizes `-0` to `0`).
  static String normalizeDecimalText(String raw) =>
      TdfLocation.normalizeDecimalText(raw);

  @override
  String toTdfDirectiveArgs() {
    if (locationIds.isNotEmpty) {
      return 'location ${locationIds.join(' ')}';
    }
    return 'location $latitudeText $longitudeText $radiusText';
  }

  /// Parses and validates [rawLatitude], [rawLongitude], and [rawRadius] into a legacy inline [LocationTaskCondition].
  static LocationTaskCondition? tryParse(
    String rawLatitude,
    String rawLongitude,
    String rawRadius,
  ) {
    final trimmedLat = rawLatitude.trim();
    final trimmedLon = rawLongitude.trim();
    final trimmedRad = rawRadius.trim();
    final latitude = _tryParseDecimal(trimmedLat);
    final longitude = _tryParseDecimal(trimmedLon);
    final radius = _tryParseDecimal(trimmedRad);
    if (latitude == null || longitude == null || radius == null) {
      return null;
    }
    if (latitude < -90.0 ||
        latitude > 90.0 ||
        longitude < -180.0 ||
        longitude > 180.0 ||
        radius <= 0.0) {
      return null;
    }
    return LocationTaskCondition._(
      const <String>[],
      latitude == 0.0 ? 0.0 : latitude,
      longitude == 0.0 ? 0.0 : longitude,
      radius,
      normalizeDecimalText(trimmedLat),
      normalizeDecimalText(trimmedLon),
      normalizeDecimalText(trimmedRad),
    );
  }

  /// Converts [degrees] to radians.
  static double _degreesToRadians(double degrees) =>
      degrees * (math.pi / 180.0);

  /// Formats [value] without a trailing `.0` suffix when it represents an exact integer.
  static String _formatDecimal(double value) {
    if (value == 0.0) {
      return '0';
    }
    final truncated = value.truncateToDouble();
    if (value == truncated) {
      return value.toInt().toString();
    }
    return normalizeDecimalText(value.toString());
  }

  /// Parses a strict ASCII decimal literal (`-?[0-9]+(\.[0-9]+)?`) without regular expressions.
  static double? _tryParseDecimal(String raw) {
    if (!TdfLocation.isValidNumberToken(raw)) {
      return null;
    }
    return double.tryParse(raw);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LocationTaskCondition) return false;
    if (locationIds.isNotEmpty || other.locationIds.isNotEmpty) {
      return listEquals(other.locationIds, locationIds);
    }
    return other.latitudeText == latitudeText &&
        other.longitudeText == longitudeText &&
        other.radiusText == radiusText;
  }

  @override
  int get hashCode => locationIds.isNotEmpty
      ? Object.hashAll(locationIds)
      : Object.hash(latitudeText, longitudeText, radiusText);

  @override
  String toString() => 'condition ${toTdfDirectiveArgs()}';
}

/// Daily time-window activation condition (`time <HH:MM> <HH:MM>`).
@immutable
class TimeWindowTaskCondition extends TaskCondition {
  /// Creates a [TimeWindowTaskCondition] for `[startMinutes, endMinutes]`.
  const TimeWindowTaskCondition({
    required this.startMinutes,
    required this.endMinutes,
    required this.startToken,
    required this.endToken,
  });

  /// Inclusive end time in minutes from `00:00` (`0..1439`).
  final int endMinutes;

  /// Canonical `HH:MM` end token.
  final String endToken;

  /// Inclusive start time in minutes from `00:00` (`0..1439`).
  final int startMinutes;

  /// Canonical `HH:MM` start token.
  final String startToken;

  @override
  ConditionGroup get group => ConditionGroup.time;

  @override
  bool isSatisfiedAt(
    DateTime evaluationTime, {
    double? currentLatitude,
    double? currentLongitude,
    Map<String, TdfLocation> locations = const <String, TdfLocation>{},
  }) {
    final currentMinutes = evaluationTime.hour * 60 + evaluationTime.minute;
    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    }
    return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
  }

  @override
  String toTdfDirectiveArgs() => 'time $startToken $endToken';

  /// Parses and validates [rawStart] and [rawEnd] (`HH:MM` with `start != end`) into a [TimeWindowTaskCondition].
  static TimeWindowTaskCondition? tryParse(String rawStart, String rawEnd) {
    final startToken = rawStart.trim();
    final endToken = rawEnd.trim();
    final startMinutes = _tryParseTimeMinutes(startToken);
    final endMinutes = _tryParseTimeMinutes(endToken);
    if (startMinutes == null ||
        endMinutes == null ||
        startMinutes == endMinutes) {
      return null;
    }
    return TimeWindowTaskCondition(
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      startToken: startToken,
      endToken: endToken,
    );
  }

  /// Parses a two-digit ASCII number at `input[start..start+2]`, or `null` if non-digit.
  static int? _parseTwoDigits(String input, int start) {
    final tens = input.codeUnitAt(start) - 0x30;
    final ones = input.codeUnitAt(start + 1) - 0x30;
    if (tens < 0 || tens > 9 || ones < 0 || ones > 9) {
      return null;
    }
    return tens * 10 + ones;
  }

  /// Parses a strict 24-hour `HH:MM` string into minutes from `00:00`, or `null` if invalid.
  static int? _tryParseTimeMinutes(String rawTime) {
    if (rawTime.length != 5 || rawTime.codeUnitAt(2) != 0x3A) {
      return null;
    }
    final hour = _parseTwoDigits(rawTime, 0);
    final minute = _parseTwoDigits(rawTime, 3);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimeWindowTaskCondition &&
        other.startMinutes == startMinutes &&
        other.endMinutes == endMinutes &&
        other.startToken == startToken &&
        other.endToken == endToken;
  }

  @override
  int get hashCode =>
      Object.hash(startMinutes, endMinutes, startToken, endToken);

  @override
  String toString() => 'condition ${toTdfDirectiveArgs()}';
}

/// Pure hexadecimal color validation and formatting helper for TDF `label` blocks.
@immutable
class TdfColor {
  /// Prevents instantiation of this stateless helper class.
  const TdfColor._();

  /// Formats the lower 24 RGB bits of [argb] as a canonical uppercase `#RRGGBB` string.
  static String formatArgb(int argb) {
    final rgb = argb & 0xFFFFFF;
    return '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
  }

  /// Checks whether [rawHex] is a strict 7-character `#RRGGBB` hexadecimal color string (`#[0-9a-fA-F]{6}`).
  static bool isStrictHexColor(String rawHex) {
    if (rawHex.length != 7 || rawHex.codeUnitAt(0) != 0x23) {
      return false;
    }
    for (var i = 1; i < 7; i++) {
      if (!_isHexCodeUnit(rawHex.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  /// Validates and normalizes [rawHex] (`#RRGGBB` or `RRGGBB`) to `#RRGGBB`, or `null` if invalid.
  static String? normalizeHex(String? rawHex) {
    if (rawHex == null) {
      return null;
    }
    final trimmed = rawHex.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final hex = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    if (hex.length != 6) {
      return null;
    }
    for (var i = 0; i < 6; i++) {
      if (!_isHexCodeUnit(hex.codeUnitAt(i))) {
        return null;
      }
    }
    return '#${hex.toUpperCase()}';
  }

  /// Parses [rawHex] into an opaque 32-bit `0xFFRRGGBB` integer, or `null` if invalid.
  static int? tryParseArgb(String? rawHex) {
    final normalized = normalizeHex(rawHex);
    if (normalized == null) {
      return null;
    }
    final parsed = int.tryParse(normalized.substring(1), radix: 16);
    if (parsed == null) {
      return null;
    }
    return 0xFF000000 | parsed;
  }

  /// Checks whether [unit] is an ASCII hexadecimal character (`0-9`, `A-F`, `a-f`).
  static bool _isHexCodeUnit(int unit) {
    return (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x46) ||
        (unit >= 0x61 && unit <= 0x66);
  }
}

/// Immutable representation of a TDF `label` root block (`spec/TDF_SPEC_0.6.0.md` Section 4.2).
@immutable
class TdfLabel {
  /// Creates a [TdfLabel] definition.
  const TdfLabel({
    required this.id,
    required this.name,
    this.isScoped = false,
    this.color,
    this.note,
    this.modifiedAt,
    this.conditions = const [],
  });

  /// Fallback UTC modification timestamp (`1970-01-01 00:00:00` UTC) when a `label` block omits `modified` (`TDF_SPEC.md` Section 6.7.2).
  static final DateTime defaultModifiedAt = DateTime.utc(1970, 1, 1, 0, 0, 0);

  /// Optional hexadecimal color code (`"#RRGGBB"`).
  final String? color;

  /// Default activation conditions inherited by tasks referencing this label.
  final List<TaskCondition> conditions;

  /// Unique label identifier (`<id>`).
  final String id;

  /// Whether the label carries the `scoped` header flag (`label <id> scoped {`).
  final bool isScoped;

  /// Optional UTC modification timestamp (`modified` directive).
  final DateTime? modifiedAt;

  /// Human-readable display name of the label.
  final String name;

  /// Optional extended description (`1..2000` characters).
  final String? note;

  /// Effective UTC modification timestamp (`modifiedAt ?? defaultModifiedAt`).
  DateTime get effectiveModifiedAt => modifiedAt ?? defaultModifiedAt;

  /// Returns a copy of this label with updated fields.
  TdfLabel copyWith({
    String? id,
    String? name,
    bool? isScoped,
    String? color,
    bool clearColor = false,
    String? note,
    bool clearNote = false,
    DateTime? modifiedAt,
    bool clearModifiedAt = false,
    List<TaskCondition>? conditions,
  }) {
    return TdfLabel(
      id: id ?? this.id,
      name: name ?? this.name,
      isScoped: isScoped ?? this.isScoped,
      color: clearColor ? null : (color ?? this.color),
      note: clearNote ? null : (note ?? this.note),
      modifiedAt: clearModifiedAt ? null : (modifiedAt ?? this.modifiedAt),
      conditions: conditions != null
          ? List<TaskCondition>.unmodifiable(conditions)
          : this.conditions,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfLabel &&
        other.id == id &&
        other.name == name &&
        other.isScoped == isScoped &&
        other.color == color &&
        other.note == note &&
        other.modifiedAt == modifiedAt &&
        listEquals(other.conditions, conditions);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    isScoped,
    color,
    note,
    modifiedAt,
    Object.hashAll(conditions),
  );

  @override
  String toString() => 'label $id ($name)';
}

/// Deterministically converts a legacy `<task-id>` or `<label-id>` into a 10-character Base62 ID (`TDF_SPEC.md` Section 2.9).
String convertLegacyEntityId({
  required String prefix,
  required String legacyId,
  DateTime? timestamp,
  Set<String> existingIds = const <String>{},
}) {
  final timePart = timestamp != null
      ? encodeTdfBase62Time(timestamp)
      : _encodeBase62Fixed(
          _fnv1a32('$prefix:time:$legacyId') % tdfBase62TimeModulo,
          4,
        );
  for (var attempt = 0; attempt < 1024; attempt++) {
    final seed = attempt == 0
        ? '$prefix:id:$legacyId'
        : '$prefix:id:$legacyId:$attempt';
    final randomPart = _deterministicBase62Segment(seed);
    final candidate = '$randomPart$timePart';
    if (!existingIds.contains(candidate)) {
      return candidate;
    }
  }
  return _generateEntityId(timestamp: timestamp, existingIds: existingIds);
}

/// Encodes the UTC seconds of [timestamp] modulo `62^4` (`14,776,336`) as a 4-character Base62 string.
String encodeTdfBase62Time(DateTime timestamp) {
  final utcSeconds = timestamp.toUtc().millisecondsSinceEpoch ~/ 1000;
  final normalized =
      ((utcSeconds % tdfBase62TimeModulo) + tdfBase62TimeModulo) %
      tdfBase62TimeModulo;
  return _encodeBase62Fixed(normalized, 4);
}

/// Generates a unique 10-character TDF 0.4.0 label identifier (`<6xBase62Random><4xBase62Time>`).
String generateLabelId({
  DateTime? timestamp,
  Set<String> existingIds = const <String>{},
}) {
  return _generateEntityId(timestamp: timestamp, existingIds: existingIds);
}

/// Generates a unique 10-character TDF 0.4.0 task identifier (`<6xBase62Random><4xBase62Time>`).
String generateTaskId({
  DateTime? timestamp,
  Set<String> existingIds = const <String>{},
}) {
  return _generateEntityId(timestamp: timestamp, existingIds: existingIds);
}

/// Checks whether [value] is a canonical 10-character TDF 0.4.0 label identifier (`[0-9A-Za-z]{10}`).
bool isValidLabelId(String value) => _isValidEntityId(value);

/// Checks whether [value] is a canonical 10-character TDF 0.4.0 task identifier (`[0-9A-Za-z]{10}`).
bool isValidTaskId(String value) => _isValidEntityId(value);

/// Derives a deterministic 6-character Base62 string from [seed].
String _deterministicBase62Segment(String seed) {
  final high = _fnv1a32('hi:$seed');
  final low = _fnv1a32('lo:$seed');
  final combined = ((high & 0x1FFFFF) << 32) | low;
  return _encodeBase62Fixed(combined, 6);
}

/// Encodes non-negative integer [value] into a fixed-width Base62 string of [width] characters, left-padded with `'0'`.
String _encodeBase62Fixed(int value, int width) {
  final units = List<int>.filled(width, 0x30);
  var remaining = value < 0 ? 0 : value;
  for (var i = width - 1; i >= 0; i--) {
    final digit = remaining % 62;
    units[i] = tdfBase62Alphabet.codeUnitAt(digit);
    remaining ~/= 62;
  }
  return String.fromCharCodes(units);
}

/// Computes a deterministic 32-bit FNV-1a hash of [input].
int _fnv1a32(String input) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < input.length; i++) {
    hash ^= input.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Generates a unique 10-character `<6xBase62Random><4xBase62Time>` identifier not present in [existingIds].
String _generateEntityId({
  DateTime? timestamp,
  Set<String> existingIds = const <String>{},
}) {
  final resolvedTime = timestamp ?? DateTime.now().toUtc();
  final timePart = encodeTdfBase62Time(resolvedTime);
  while (true) {
    final randomPart = _randomBase62Segment();
    final candidate = '$randomPart$timePart';
    if (!existingIds.contains(candidate)) {
      return candidate;
    }
  }
}

/// Checks whether [unit] is an ASCII Base62 character (`0-9`, `A-Z`, `a-z`).
bool _isBase62CodeUnit(int unit) {
  return (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A);
}

/// Validates a 10-character `<6xBase62Random><4xBase62Time>` identifier without regular expressions.
bool _isValidEntityId(String value) {
  if (value.length != tdfEntityIdLength) {
    return false;
  }
  for (var i = 0; i < tdfEntityIdLength; i++) {
    if (!_isBase62CodeUnit(value.codeUnitAt(i))) {
      return false;
    }
  }
  return true;
}

/// Generates 6 cryptographically random Base62 characters (`62^6` possibilities).
String _randomBase62Segment() {
  final random = math.Random.secure();
  final units = List<int>.filled(6, 0x30);
  for (var i = 0; i < 6; i++) {
    units[i] = tdfBase62Alphabet.codeUnitAt(random.nextInt(62));
  }
  return String.fromCharCodes(units);
}
