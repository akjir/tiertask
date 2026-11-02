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

/// Geographic proximity activation condition (`location <lat> <lon> <radius>`).
@immutable
class LocationTaskCondition extends TaskCondition {
  /// Creates a [LocationTaskCondition] for [latitude], [longitude], and [radiusMeters].
  const LocationTaskCondition({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  /// Mean Earth radius in meters used for Haversine distance evaluation (`TDF_SPEC.md` Section 4.3.1).
  static const double earthRadiusMeters = 6371000.0;

  /// Target WGS-84 latitude in decimal degrees (`-90.0..90.0`).
  final double latitude;

  /// Target WGS-84 longitude in decimal degrees (`-180.0..180.0`).
  final double longitude;

  /// Inclusive geofencing radius in meters (`> 0.0`).
  final double radiusMeters;

  @override
  ConditionGroup get group => ConditionGroup.location;

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
  }) {
    if (currentLatitude == null || currentLongitude == null) {
      return true;
    }
    final distance = haversineDistanceMeters(
      latitude,
      longitude,
      currentLatitude,
      currentLongitude,
    );
    return distance <= radiusMeters;
  }

  @override
  String toTdfDirectiveArgs() {
    final latStr = _formatDecimal(latitude);
    final lonStr = _formatDecimal(longitude);
    final radiusStr = _formatDecimal(radiusMeters);
    return 'location $latStr $lonStr $radiusStr';
  }

  /// Parses and validates [rawLatitude], [rawLongitude], and [rawRadius] into a [LocationTaskCondition].
  static LocationTaskCondition? tryParse(
    String rawLatitude,
    String rawLongitude,
    String rawRadius,
  ) {
    final latitude = _tryParseDecimal(rawLatitude.trim());
    final longitude = _tryParseDecimal(rawLongitude.trim());
    final radius = _tryParseDecimal(rawRadius.trim());
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
    return LocationTaskCondition(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radius,
    );
  }

  /// Converts [degrees] to radians.
  static double _degreesToRadians(double degrees) =>
      degrees * (math.pi / 180.0);

  /// Formats [value] without a trailing `.0` suffix when it represents an exact integer.
  static String _formatDecimal(double value) {
    final truncated = value.truncateToDouble();
    if (value == truncated) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  /// Parses a strict ASCII decimal literal (`-?[0-9]+(\.[0-9]+)?`) without regular expressions.
  static double? _tryParseDecimal(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    var index = 0;
    if (raw.codeUnitAt(0) == 0x2D) {
      if (raw.length == 1) {
        return null;
      }
      index = 1;
    }
    var hasLeadingDigits = false;
    while (index < raw.length) {
      final unit = raw.codeUnitAt(index);
      if (unit >= 0x30 && unit <= 0x39) {
        hasLeadingDigits = true;
        index++;
      } else {
        break;
      }
    }
    if (!hasLeadingDigits) {
      return null;
    }
    if (index < raw.length) {
      if (raw.codeUnitAt(index) != 0x2E || index == raw.length - 1) {
        return null;
      }
      index++;
      while (index < raw.length) {
        final unit = raw.codeUnitAt(index);
        if (unit < 0x30 || unit > 0x39) {
          return null;
        }
        index++;
      }
    }
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return null;
    }
    return parsed;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationTaskCondition &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.radiusMeters == radiusMeters;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude, radiusMeters);

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

/// Immutable representation of a TDF `label` root block (`TDF_SPEC.md` Section 4.1).
@immutable
class TdfLabel {
  /// Creates a [TdfLabel] definition.
  const TdfLabel({
    required this.id,
    required this.name,
    this.color,
    this.note,
    this.modifiedAt,
    this.conditions = const [],
  });

  /// Fallback UTC modification timestamp when a `label` block omits `modified`.
  static final DateTime defaultModifiedAt = DateTime.utc(2026, 11, 1, 8, 0);

  /// Optional hexadecimal color code (`"#RRGGBB"`).
  final String? color;

  /// Default activation conditions inherited by tasks referencing this label.
  final List<TaskCondition> conditions;

  /// Unique label identifier (`<id>`).
  final String id;

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
    String? color,
    String? note,
    DateTime? modifiedAt,
    bool clearModifiedAt = false,
    List<TaskCondition>? conditions,
  }) {
    return TdfLabel(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      note: note ?? this.note,
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
        other.color == color &&
        other.note == note &&
        other.modifiedAt == modifiedAt &&
        listEquals(other.conditions, conditions);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    color,
    note,
    modifiedAt,
    Object.hashAll(conditions),
  );

  @override
  String toString() => 'label $id ($name)';
}
