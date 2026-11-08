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

import 'tdf_sync_metadata.dart';

/// Internal rule mode used by [TdfTimeZoneContext].
enum _TimeZoneRuleKind {
  /// Fixed UTC offset in seconds.
  fixedOffset,

  /// Central European Time / Central European Summer Time (`Europe/Berlin`).
  europeBerlin,

  /// Missing or unsupported time zone rules (`TimeZoneContextRequired`).
  unavailable,
}

/// Proleptic Gregorian calendar and Unicode scalar validation utilities per `TDF_SPEC.md` Sections 2.6, 2.8, and 3.3.
abstract final class TdfCalendar {
  /// Unix epoch (`1970-01-01 00:00:00` UTC).
  static final DateTime epochUtc = DateTime.utc(1970, 1, 1, 0, 0, 0);

  /// Maximum valid TDF timestamp (`9999-12-31 23:59:59` UTC).
  static final DateTime maxTimestampUtc = DateTime.utc(
    9999,
    12,
    31,
    23,
    59,
    59,
  );

  /// Maximum supported year in the proleptic Gregorian calendar.
  static const int maxYear = 9999;

  /// Minimum valid TDF timestamp (`0001-01-01 00:00:00` UTC).
  static final DateTime minTimestampUtc = DateTime.utc(1, 1, 1, 0, 0, 0);

  /// Minimum supported year in the proleptic Gregorian calendar.
  static const int minYear = 1;

  /// Counts Unicode scalar values in [value], returning `null` if [value] contains any unpaired UTF-16 surrogate (`U+D800..U+DFFF`).
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
        count += 1;
        index += 2;
        continue;
      }
      if (unit >= 0xDC00 && unit <= 0xDFFF) {
        return null;
      }
      count += 1;
      index += 1;
    }
    return count;
  }

  /// Returns the number of days in [month] (`1..12`) of [year] in the proleptic Gregorian calendar.
  static int daysInMonth(int year, int month) {
    return switch (month) {
      1 || 3 || 5 || 7 || 8 || 10 || 12 => 31,
      4 || 6 || 9 || 11 => 30,
      2 => isLeapYear(year) ? 29 : 28,
      _ => 0,
    };
  }

  /// Checks whether [year] is a leap year in the proleptic Gregorian calendar.
  static bool isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
  }

  /// Checks whether [year]-[month]-[day] is a valid proleptic Gregorian date within `0001-01-01..9999-12-31`.
  static bool isValidGregorianDate(int year, int month, int day) {
    if (year < minYear ||
        year > maxYear ||
        month < 1 ||
        month > 12 ||
        day < 1) {
      return false;
    }
    return day <= daysInMonth(year, month);
  }

  /// Checks whether [instant] is within the supported TDF timestamp range (`0001-01-01 00:00:00`..`9999-12-31 23:59:59` UTC).
  static bool isWithinTimestampBounds(DateTime instant) {
    final utc = instant.toUtc();
    return !utc.isBefore(minTimestampUtc) && !utc.isAfter(maxTimestampUtc);
  }
}

/// Immutable local wall-clock time (`HH:MM` or `HH:MM:SS`) for a `repeat` directive per `TDF_SPEC.md` Section 4.1 and 6.10.3.
@immutable
class TdfRepeatClock {
  /// Creates a [TdfRepeatClock] (`00:00:00` through `23:59:59`).
  const TdfRepeatClock({this.hour = 0, this.minute = 0, this.second = 0})
    : assert(hour >= 0 && hour <= 23, 'hour must be within 0..23'),
      assert(minute >= 0 && minute <= 59, 'minute must be within 0..59'),
      assert(second >= 0 && second <= 59, 'second must be within 0..59');

  /// Default local midnight recurrence clock (`00:00:00`).
  static const TdfRepeatClock midnight = TdfRepeatClock();

  /// Hour component (`0..23`).
  final int hour;

  /// Minute component (`0..59`).
  final int minute;

  /// Second component (`0..59`).
  final int second;

  /// Whether this clock represents local midnight (`00:00:00`).
  bool get isMidnight => hour == 0 && minute == 0 && second == 0;

  /// Formats this clock in canonical TDF 0.5.1 form: empty string for `00:00:00`, `HH:MM` when [second] is `0`, else `HH:MM:SS`.
  String formatCanonical() {
    if (isMidnight) {
      return '';
    }
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    if (second == 0) {
      return '$hh:$mm';
    }
    final ss = second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  /// Parses an unquoted `<repeat-time>` token (`HH:MM` or `HH:MM:SS` in `00:00:00..23:59:59`), or returns `null` if invalid.
  static TdfRepeatClock? tryParse(String raw) {
    if (raw.length != 5 && raw.length != 8) {
      return null;
    }
    if (raw.codeUnitAt(2) != 0x3A) {
      return null;
    }
    final hour = _parseTwoDigits(raw, 0);
    final minute = _parseTwoDigits(raw, 3);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    if (raw.length == 5) {
      return TdfRepeatClock(hour: hour, minute: minute);
    }
    if (raw.codeUnitAt(5) != 0x3A) {
      return null;
    }
    final second = _parseTwoDigits(raw, 6);
    if (second == null || second > 59) {
      return null;
    }
    return TdfRepeatClock(hour: hour, minute: minute, second: second);
  }

  /// Parses two ASCII decimal digits starting at [offset] in [source], or returns `null`.
  static int? _parseTwoDigits(String source, int offset) {
    final first = source.codeUnitAt(offset);
    final second = source.codeUnitAt(offset + 1);
    if (first < 0x30 || first > 0x39 || second < 0x30 || second > 0x39) {
      return null;
    }
    return (first - 0x30) * 10 + (second - 0x30);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfRepeatClock &&
        other.hour == hour &&
        other.minute == minute &&
        other.second == second;
  }

  @override
  int get hashCode => Object.hash(hour, minute, second);
}

/// Time zone transition and local-to-UTC resolution context per `TDF_SPEC.md` Section 6.10.
@immutable
class TdfTimeZoneContext {
  /// Creates a [TdfTimeZoneContext] with [zoneId], [_ruleKind], and [fixedOffsetSeconds].
  const TdfTimeZoneContext._(
    this.zoneId,
    this._ruleKind, [
    this.fixedOffsetSeconds = 0,
  ]);

  /// Creates a [TdfTimeZoneContext] with a fixed [offset] from UTC.
  factory TdfTimeZoneContext.fixedOffset(Duration offset) {
    return TdfTimeZoneContext._(
      'FIXED',
      _TimeZoneRuleKind.fixedOffset,
      offset.inSeconds,
    );
  }

  /// Creates an unavailable [TdfTimeZoneContext] that triggers `TimeZoneContextRequired` when evaluated.
  const factory TdfTimeZoneContext.missing([String zoneId]) =
      TdfTimeZoneContext._missing;

  /// Creates an unavailable [TdfTimeZoneContext] with [zoneId].
  const TdfTimeZoneContext._missing([this.zoneId = ''])
    : _ruleKind = _TimeZoneRuleKind.unavailable,
      fixedOffsetSeconds = 0;

  /// Resolves a [TdfTimeZoneContext] by IANA name or ISO UTC offset (`UTC`, `Europe/Berlin`, `+01:00`, etc.).
  factory TdfTimeZoneContext.named(String rawZoneId) {
    final trimmed = rawZoneId.trim();
    if (trimmed.isEmpty) {
      return const TdfTimeZoneContext.missing();
    }
    final upper = trimmed.toUpperCase();
    if (upper == 'UTC' ||
        upper == 'ETC/UTC' ||
        upper == 'Z' ||
        upper == 'GMT') {
      return utc;
    }
    if (trimmed == 'Europe/Berlin' || upper == 'EUROPE/BERLIN') {
      return europeBerlin;
    }
    if (upper == 'CET') {
      return TdfTimeZoneContext.fixedOffset(const Duration(hours: 1));
    }
    if (upper == 'CEST') {
      return TdfTimeZoneContext.fixedOffset(const Duration(hours: 2));
    }
    final parsedOffset = _tryParseOffsetSeconds(trimmed);
    if (parsedOffset != null) {
      return TdfTimeZoneContext._(
        trimmed,
        _TimeZoneRuleKind.fixedOffset,
        parsedOffset,
      );
    }
    return TdfTimeZoneContext.missing(trimmed);
  }

  /// `Europe/Berlin` time zone context implementing EU CET (`UTC+1`) / CEST (`UTC+2`) transitions.
  static const TdfTimeZoneContext europeBerlin = TdfTimeZoneContext._(
    'Europe/Berlin',
    _TimeZoneRuleKind.europeBerlin,
  );

  /// Standard `UTC` (`+00:00`) time zone context.
  static const TdfTimeZoneContext utc = TdfTimeZoneContext._(
    'UTC',
    _TimeZoneRuleKind.fixedOffset,
  );

  /// Fixed offset in seconds when [_ruleKind] is [_TimeZoneRuleKind.fixedOffset].
  final int fixedOffsetSeconds;

  /// Canonical or requested time zone identifier.
  final String zoneId;

  final _TimeZoneRuleKind _ruleKind;

  /// Whether transition rules are available for this time zone context.
  bool get isAvailable => _ruleKind != _TimeZoneRuleKind.unavailable;

  /// Resolves a local wall-clock date and time (`year-month-day hour:minute:second`) to a UTC [DateTime]
  /// per `TDF_SPEC.md` Section 6.10.2:
  /// 1. Unique local instant -> exact UTC instant.
  /// 2. Overlap -> first occurrence (earlier UTC instant).
  /// 3. Forward gap -> pre-gap offset (shifts local time forward by gap duration).
  ///
  /// Throws [TdfContextException] (`TimeZoneContextRequired`) if rules are unavailable, or [FormatException] (`InvalidTimestamp`) if out of range.
  DateTime resolveLocalToUtc(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) {
    if (!isAvailable) {
      throw const TdfContextException(
        kind: TdfContextOutcomeKind.timeZoneContextRequired,
        message: 'Time zone context is required for local calendar conversion.',
      );
    }
    if (!TdfCalendar.isValidGregorianDate(year, month, day) ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59) {
      throw const FormatException('InvalidTimestamp');
    }
    final offsetSeconds = _resolveOffsetSecondsForLocal(
      year,
      month,
      day,
      hour,
      minute,
      second,
    );
    final wallAsUtc = DateTime.utc(year, month, day, hour, minute, second);
    final resolvedUtc = wallAsUtc.subtract(Duration(seconds: offsetSeconds));
    if (!TdfCalendar.isWithinTimestampBounds(resolvedUtc)) {
      throw const FormatException('InvalidTimestamp');
    }
    return resolvedUtc;
  }

  /// Converts a UTC [instant] into local wall-clock components (returned as a `DateTime.utc(...)` carrier).
  DateTime toLocalWallClock(DateTime instant) {
    if (!isAvailable) {
      throw const TdfContextException(
        kind: TdfContextOutcomeKind.timeZoneContextRequired,
        message: 'Time zone context is required for local calendar conversion.',
      );
    }
    final utcInstant = instant.toUtc();
    final offsetSeconds = _resolveOffsetSecondsForUtc(utcInstant);
    final shifted = utcInstant.add(Duration(seconds: offsetSeconds));
    return DateTime.utc(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
    );
  }

  /// Computes the day of the month (`25..31`) of the last Sunday of [month] in [year].
  static int _lastSundayOfMonth(int year, int month) {
    final lastDay = DateTime.utc(year, month, 31);
    if (lastDay.weekday == DateTime.sunday) {
      return 31;
    }
    return 31 - lastDay.weekday;
  }

  /// Resolves the UTC offset in seconds for a local wall-clock timestamp in `Europe/Berlin`.
  static int _resolveEuropeBerlinLocalOffsetSeconds(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) {
    const cetSeconds = 3600;
    const cestSeconds = 7200;
    if (month < 3 || month > 10) {
      return cetSeconds;
    }
    if (month > 3 && month < 10) {
      return cestSeconds;
    }
    final daySeconds = hour * 3600 + minute * 60 + second;
    if (month == 3) {
      final springDay = _lastSundayOfMonth(year, 3);
      if (day < springDay) {
        return cetSeconds;
      }
      if (day > springDay) {
        return cestSeconds;
      }
      // On spring-forward Sunday:
      // 00:00:00..01:59:59 is CET (UTC+1).
      // 02:00:00..02:59:59 is in the forward gap -> Section 6.10.2 Rule 3 applies pre-gap offset (CET, UTC+1).
      // >= 03:00:00 is CEST (UTC+2).
      return daySeconds < 3 * 3600 ? cetSeconds : cestSeconds;
    }
    final autumnDay = _lastSundayOfMonth(year, 10);
    if (day < autumnDay) {
      return cestSeconds;
    }
    if (day > autumnDay) {
      return cetSeconds;
    }
    // On fall-back Sunday:
    // 00:00:00..01:59:59 is CEST (UTC+2).
    // 02:00:00..02:59:59 occurs twice -> Section 6.10.2 Rule 2 selects the first occurrence (CEST, UTC+2).
    // >= 03:00:00 is CET (UTC+1).
    return daySeconds < 3 * 3600 ? cestSeconds : cetSeconds;
  }

  /// Resolves the UTC offset in seconds for a UTC [utcInstant] in `Europe/Berlin`.
  static int _resolveEuropeBerlinUtcOffsetSeconds(DateTime utcInstant) {
    final year = utcInstant.year;
    final springSunday = _lastSundayOfMonth(year, 3);
    final autumnSunday = _lastSundayOfMonth(year, 10);
    final dstStartUtc = DateTime.utc(year, 3, springSunday, 1, 0, 0);
    final dstEndUtc = DateTime.utc(year, 10, autumnSunday, 1, 0, 0);
    if (!utcInstant.isBefore(dstStartUtc) && utcInstant.isBefore(dstEndUtc)) {
      return 7200;
    }
    return 3600;
  }

  /// Resolves the UTC offset in seconds for a local wall-clock date and time.
  int _resolveOffsetSecondsForLocal(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) {
    return switch (_ruleKind) {
      _TimeZoneRuleKind.fixedOffset => fixedOffsetSeconds,
      _TimeZoneRuleKind.europeBerlin => _resolveEuropeBerlinLocalOffsetSeconds(
        year,
        month,
        day,
        hour,
        minute,
        second,
      ),
      _TimeZoneRuleKind.unavailable => 0,
    };
  }

  /// Resolves the UTC offset in seconds for an exact UTC [utcInstant].
  int _resolveOffsetSecondsForUtc(DateTime utcInstant) {
    return switch (_ruleKind) {
      _TimeZoneRuleKind.fixedOffset => fixedOffsetSeconds,
      _TimeZoneRuleKind.europeBerlin => _resolveEuropeBerlinUtcOffsetSeconds(
        utcInstant,
      ),
      _TimeZoneRuleKind.unavailable => 0,
    };
  }

  /// Parses an ISO UTC offset string such as `+01:00`, `-05:30`, `UTC+02:00`, or `+00:00` into seconds.
  static int? _tryParseOffsetSeconds(String raw) {
    var candidate = raw;
    if (candidate.toUpperCase().startsWith('UTC')) {
      candidate = candidate.substring(3);
    }
    if (candidate.length != 6) {
      return null;
    }
    final signChar = candidate.codeUnitAt(0);
    if (signChar != 0x2B && signChar != 0x2D) {
      return null;
    }
    if (candidate.codeUnitAt(3) != 0x3A) {
      return null;
    }
    final hours = TdfRepeatClock._parseTwoDigits(candidate, 1);
    final minutes = TdfRepeatClock._parseTwoDigits(candidate, 4);
    if (hours == null || minutes == null || hours > 14 || minutes > 59) {
      return null;
    }
    final totalSeconds = (hours * 60 + minutes) * 60;
    return signChar == 0x2D ? -totalSeconds : totalSeconds;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfTimeZoneContext &&
        other.zoneId == zoneId &&
        other._ruleKind == _ruleKind &&
        other.fixedOffsetSeconds == fixedOffsetSeconds;
  }

  @override
  int get hashCode => Object.hash(zoneId, _ruleKind, fixedOffsetSeconds);
}
