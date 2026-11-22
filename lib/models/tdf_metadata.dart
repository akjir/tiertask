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

import 'tdf_error.dart';
import 'tdf_location.dart';

/// Canonical Base62 character alphabet (`0-9`, `A-Z`, `a-z`) defined in `TDF_SPEC.md` Section 2.9.
const String tdfBase62Alphabet = TdfEntityId.alphabet;

/// Modulo divisor `62^4` (`14,776,336` seconds) for the 4-character Base62 timestamp suffix.
const int tdfBase62TimeModulo = TdfEntityId.timeModulo;

/// Fixed total character length of a TDF `<task-id>` or `<label-id>`.
const int tdfEntityIdLength = TdfEntityId.idLength;

/// Sole normative TDF version supported by this implementation (`TDF-COMPAT-001`, `TDF-ENT-001`).
const String tdfSupportedVersion = '0.8.0';

/// Canonical condition rule groups defined in `spec/TDF_SPEC_0.8.0.md` Section 5.5.
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

/// Geographic proximity activation condition (`location <loc-1> [<loc-2> ...]`).
@immutable
class LocationTaskCondition extends TaskCondition {
  /// Creates a [LocationTaskCondition] referencing [locationIds].
  const LocationTaskCondition({this.locationIds = const <String>[]});

  /// Creates an ID-referenced [LocationTaskCondition] by deduplicating [rawLocationIds] in first-seen declaration order.
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

  /// Mean Earth radius in meters used for Haversine distance evaluation (`spec/TDF_SPEC_0.8.0.md` Section 4.4.2).
  static const double earthRadiusMeters = 6371000.0;

  /// Referenced 10-character Base62 `<location-id>` tokens (`1..63`, deduplicated in first-seen declaration order).
  final List<String> locationIds;

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
    Map<String, TdfLocation> locations = const <String, TdfLocation>{},
  }) {
    if (currentLatitude == null || currentLongitude == null) {
      return true;
    }
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

  @override
  String toTdfDirectiveArgs() => 'location ${locationIds.join(' ')}';

  /// Converts [degrees] to radians.
  static double _degreesToRadians(double degrees) =>
      degrees * (math.pi / 180.0);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationTaskCondition &&
        listEquals(other.locationIds, locationIds);
  }

  @override
  int get hashCode => Object.hashAll(locationIds);

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
    final startMinutes = TdfMetadata.tryParseTimeMinutes(startToken);
    final endMinutes = TdfMetadata.tryParseTimeMinutes(endToken);
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

/// Shared TDF primitive validation, time parsing, and location-condition coalescing utilities.
class TdfMetadata {
  /// Prevents instantiation of [TdfMetadata].
  const TdfMetadata._();

  /// Coalesces multiple [LocationTaskCondition] rules in [conditions] into one canonical rule in first-seen `<location-id>` order (`TDF-MODEL-006`).
  static List<TaskCondition> coalesceLocationConditions(
    List<TaskCondition> conditions,
  ) {
    final orderedLocationIds = collectDistinctLocationIds(conditions);
    if (orderedLocationIds.isEmpty) {
      return conditions;
    }
    final coalesced = <TaskCondition>[];
    var emittedLocation = false;
    for (final condition in conditions) {
      if (condition is LocationTaskCondition) {
        if (!emittedLocation) {
          coalesced.add(LocationTaskCondition(locationIds: orderedLocationIds));
          emittedLocation = true;
        }
      } else {
        coalesced.add(condition);
      }
    }
    return coalesced;
  }

  /// Coalesces [LocationTaskCondition] rules into a single canonical rule referencing deduplicated `<location-id>` tokens, or returns an empty list.
  static List<LocationTaskCondition> coalesceLocationRules(
    Iterable<LocationTaskCondition> rules,
  ) {
    final orderedLocationIds = collectDistinctLocationIds(rules);
    if (orderedLocationIds.isEmpty) {
      return const <LocationTaskCondition>[];
    }
    return <LocationTaskCondition>[
      LocationTaskCondition(locationIds: orderedLocationIds),
    ];
  }

  /// Collects unique `<location-id>` tokens across all [LocationTaskCondition] entries in [conditions] in first-seen order.
  static List<String> collectDistinctLocationIds(
    Iterable<TaskCondition> conditions,
  ) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final condition in conditions) {
      if (condition case final LocationTaskCondition locationCondition) {
        _appendDistinctIds(locationCondition.locationIds, seen, ordered);
      }
    }
    return ordered;
  }

  /// Checks whether [value] contains any ASCII control character (`0x00..0x1F` or `0x7F`).
  static bool containsAsciiControlChar(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit <= 0x1F || unit == 0x7F) {
        return true;
      }
    }
    return false;
  }

  /// Counts total `<location-id>` references across all [LocationTaskCondition] rules in [conditions].
  static int countLocationRefs(List<TaskCondition> conditions) {
    var count = 0;
    for (final rule in conditions) {
      if (rule is LocationTaskCondition) {
        count += rule.locationIds.length;
      }
    }
    return count;
  }

  /// Counts decoded Unicode scalar values in [value], returning `null` if an unpaired UTF-16 surrogate (`U+D800..U+DFFF`) is present.
  static int? countUnicodeScalars(String value) {
    var count = 0;
    var index = 0;
    while (index < value.length) {
      final unit = value.codeUnitAt(index);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (index + 1 >= value.length) {
          return null;
        }
        final low = value.codeUnitAt(index + 1);
        if (low < 0xDC00 || low > 0xDFFF) {
          return null;
        }
        count++;
        index += 2;
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        return null;
      } else {
        count++;
        index++;
      }
    }
    return count;
  }

  /// Returns whether [conditions] contains a non-empty [LocationTaskCondition].
  static bool hasLocationConditionRule(List<TaskCondition> conditions) {
    for (final rule in conditions) {
      if (rule is LocationTaskCondition && rule.locationIds.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Parses a strict 24-hour `<HH:MM>` token into minutes from `00:00` (`0..1439`), or `null` if invalid.
  static int? tryParseTimeMinutes(String rawTime) {
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

  /// Appends non-empty unseen IDs from [source] into [ordered].
  static void _appendDistinctIds(
    List<String> source,
    Set<String> seen,
    List<String> ordered,
  ) {
    for (final id in source) {
      if (id.isNotEmpty && seen.add(id)) {
        ordered.add(id);
      }
    }
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
}

/// Immutable representation of a TDF `link "<title>" "<uri>"` directive belonging to a task or [TdfLabel].
@immutable
class TaskLink {
  /// Creates a [TaskLink] with [title] and [uri].
  const TaskLink({required this.title, required this.uri});

  /// Maximum number of `link` directives permitted on a single task (`20`).
  static const int maxLinksPerTask = maxTdfLinksPerTask;

  /// Maximum character length of a link `<uri>` (`2048`).
  static const int maxUriLength = maxTdfUriLength;

  /// Human-readable display title (`<title>`).
  final String title;

  /// Target resource URI (`<uri>`).
  final String uri;

  /// Returns a copy of this link with updated fields.
  TaskLink copyWith({String? title, String? uri}) {
    return TaskLink(title: title ?? this.title, uri: uri ?? this.uri);
  }

  /// Validates that [rawUri] is non-empty, within [maxUriLength], free of ASCII control characters,
  /// and begins with a valid URI scheme matching `[a-zA-Z][a-zA-Z0-9+.-]*:`.
  static bool isValidUri(String rawUri) {
    if (rawUri.isEmpty) {
      return false;
    }
    final scalarCount = TdfMetadata.countUnicodeScalars(rawUri);
    if (scalarCount == null || scalarCount > maxUriLength) {
      return false;
    }
    var colonIndex = -1;
    var hasNonWhitespace = false;
    for (var i = 0; i < rawUri.length; i++) {
      final unit = rawUri.codeUnitAt(i);
      if (unit <= 0x1F || unit == 0x7F) {
        return false;
      }
      if (unit != 0x20) {
        hasNonWhitespace = true;
      }
      if (colonIndex == -1 && unit == 0x3A) {
        colonIndex = i;
      }
    }
    if (!hasNonWhitespace || colonIndex <= 0) {
      return false;
    }
    if (!_isAlphaChar(rawUri.codeUnitAt(0))) {
      return false;
    }
    for (var i = 1; i < colonIndex; i++) {
      if (!_isSchemeContinueChar(rawUri.codeUnitAt(i))) {
        return false;
      }
    }
    final scheme = rawUri.substring(0, colonIndex).toLowerCase();
    if (scheme == 'javascript' || scheme == 'vbscript' || scheme == 'data') {
      return false;
    }
    return true;
  }

  /// Trims surrounding ASCII spaces and validates [rawTitle] and [rawUri] against single-line `<text>` and `<uri>` rules, returning a [TaskLink] or `null` if invalid.
  static TaskLink? tryParse({
    required String rawTitle,
    required String rawUri,
    int maxTextLength = maxTdfTextLength,
  }) {
    if (TdfMetadata.containsAsciiControlChar(rawTitle) ||
        TdfMetadata.containsAsciiControlChar(rawUri)) {
      return null;
    }
    final trimmedTitle = rawTitle.trim();
    final trimmedUri = rawUri.trim();
    final titleScalarCount = TdfMetadata.countUnicodeScalars(trimmedTitle);
    if (titleScalarCount == null ||
        titleScalarCount == 0 ||
        titleScalarCount > maxTextLength ||
        !_hasGraphicChar(trimmedTitle)) {
      return null;
    }
    if (!isValidUri(trimmedUri)) {
      return null;
    }
    return TaskLink(title: trimmedTitle, uri: trimmedUri);
  }

  /// Checks whether [value] contains at least one non-space graphic code unit (`!= 0x20`).
  static bool _hasGraphicChar(String value) {
    for (var i = 0; i < value.length; i++) {
      if (value.codeUnitAt(i) != 0x20) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether [unit] is an ASCII letter (`[a-zA-Z]`).
  static bool _isAlphaChar(int unit) {
    return (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
  }

  /// Checks whether [unit] is a valid URI scheme continuation character (`[a-zA-Z0-9+.-]`).
  static bool _isSchemeContinueChar(int unit) {
    return _isAlphaChar(unit) ||
        (unit >= 0x30 && unit <= 0x39) ||
        unit == 0x2B ||
        unit == 0x2D ||
        unit == 0x2E;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskLink && other.title == title && other.uri == uri;
  }

  @override
  int get hashCode => Object.hash(title, uri);

  @override
  String toString() => 'TaskLink(title: <redacted>, uri: <redacted>)';
}

/// Immutable representation of a TDF `label` root block (`TDF_SPEC.md` Section 4.2).
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
    this.links = const <TaskLink>[],
    this.conditions = const <TaskCondition>[],
  });

  /// Fallback UTC modification timestamp (`1970-01-01 00:00:00` UTC) when a `label` block omits `modified` (`TDF_SPEC.md` Section 6.7.2).
  static final DateTime defaultModifiedAt = DateTime.utc(1970);

  /// Maximum number of `link` directives permitted on a single label (`20`).
  static const int maxLinksPerLabel = maxTdfLinksPerLabel;

  /// Optional hexadecimal color code (`"#RRGGBB"`).
  final String? color;

  /// Default activation conditions inherited by tasks referencing this label.
  final List<TaskCondition> conditions;

  /// Unique label identifier (`<id>`).
  final String id;

  /// Whether the label carries the `scoped` header flag (`label <id> scoped {`).
  final bool isScoped;

  /// Reference links (`link "<title>" "<uri>"`, `0..20`) attached to this label.
  final List<TaskLink> links;

  /// Optional UTC modification timestamp (`modified` directive).
  final DateTime? modifiedAt;

  /// Human-readable display name of the label.
  final String name;

  /// Optional extended description (`1..2000` characters).
  final String? note;

  /// Number of direct child statements emitted inside this `label` block in canonical `0.8.0` form.
  int get canonicalDirectChildStatementCount {
    var count = 1;
    if (color != null) count++;
    if (note case final currentNote? when currentNote.isNotEmpty) {
      count++;
    }
    if (modifiedAt != null) count++;
    count += links.length;
    if (conditions.isNotEmpty) count++;
    return count;
  }

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
    Iterable<TaskLink>? links,
    Iterable<TaskCondition>? conditions,
  }) {
    return TdfLabel(
      id: id ?? this.id,
      name: name ?? this.name,
      isScoped: isScoped ?? this.isScoped,
      color: clearColor ? null : (color ?? this.color),
      note: clearNote ? null : (note ?? this.note),
      modifiedAt: clearModifiedAt ? null : (modifiedAt ?? this.modifiedAt),
      links: links != null
          ? (links.isEmpty
                ? const <TaskLink>[]
                : List<TaskLink>.unmodifiable(links))
          : this.links,
      conditions: conditions != null
          ? (conditions.isEmpty
                ? const <TaskCondition>[]
                : List<TaskCondition>.unmodifiable(conditions))
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
        listEquals(other.links, links) &&
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
    Object.hashAll(links),
    Object.hashAll(conditions),
  );

  @override
  String toString() => 'label $id ($name)';
}

/// Encodes the UTC seconds of [timestamp] modulo `62^4` (`14,776,336`) as a 4-character Base62 string.
String encodeTdfBase62Time(DateTime timestamp) =>
    TdfEntityId.encodeBase62Time(timestamp);

/// Generates a unique 10-character TDF label identifier (`<6xBase62Random><4xBase62Time>`).
String generateLabelId({
  DateTime? timestamp,
  Set<String> existingIds = const <String>{},
}) => TdfEntityId.generate(timestamp: timestamp, existingIds: existingIds);

/// Generates a unique 10-character TDF task identifier (`<6xBase62Random><4xBase62Time>`).
String generateTaskId({
  DateTime? timestamp,
  Set<String> existingIds = const <String>{},
}) => TdfEntityId.generate(timestamp: timestamp, existingIds: existingIds);

/// Checks whether [value] is a canonical 10-character TDF label identifier (`[0-9A-Za-z]{10}`).
bool isValidLabelId(String value) => TdfEntityId.isValid(value);

/// Checks whether [value] is a canonical 10-character TDF task identifier (`[0-9A-Za-z]{10}`).
bool isValidTaskId(String value) => TdfEntityId.isValid(value);
