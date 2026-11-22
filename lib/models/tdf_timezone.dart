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

  /// US Eastern Standard Time / Eastern Daylight Time (`America/New_York`).
  americaNewYork,

  /// Host operating system local time zone with historical and future DST probing.
  systemLocal,

  /// Injected UTC-epoch-second offset observer for deterministic transition testing.
  customObserver,

  /// Missing or unsupported time zone rules (`TimeZoneContextRequired`).
  unavailable,
}

/// Proleptic Gregorian calendar and Unicode scalar validation utilities per `spec/TDF_SPEC_0.8.0.md` Sections 4.1 and 4.4.
abstract final class TdfCalendar {
  /// Unix epoch (`1970-01-01 00:00:00` UTC).
  static final DateTime epochUtc = DateTime.utc(1970);

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
  static final DateTime minTimestampUtc = DateTime.utc(1);

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

/// Immutable proleptic Gregorian local calendar date-time (`0001-01-01 00:00:00..9999-12-31 23:59:59`) per `TDF-MODEL-005` and `TDF-DIR-004`.
@immutable
class TdfLocalDateTime implements Comparable<TdfLocalDateTime> {
  /// Creates and validates a [TdfLocalDateTime] (`0001-01-01 00:00:00..9999-12-31 23:59:59`).
  TdfLocalDateTime(
    this.year,
    this.month,
    this.day, [
    this.hour = 0,
    this.minute = 0,
    this.second = 0,
  ]) {
    if (!TdfCalendar.isValidGregorianDate(year, month, day) ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59) {
      throw const FormatException('InvalidTimestamp');
    }
  }

  /// Creates a [TdfLocalDateTime] from the calendar components of [wallClock].
  factory TdfLocalDateTime.fromWallClock(DateTime wallClock) {
    return TdfLocalDateTime(
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
      wallClock.second,
    );
  }

  /// Year component (`1..9999`).
  final int year;

  /// Month component (`1..12`).
  final int month;

  /// Day-of-month component (`1..31`).
  final int day;

  /// Hour component (`0..23`).
  final int hour;

  /// Minute component (`0..59`).
  final int minute;

  /// Second component (`0..59`).
  final int second;

  @override
  int compareTo(TdfLocalDateTime other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    if (day != other.day) return day.compareTo(other.day);
    if (hour != other.hour) return hour.compareTo(other.hour);
    if (minute != other.minute) return minute.compareTo(other.minute);
    return second.compareTo(other.second);
  }

  /// Formats as `YYYY-MM-DD HH:MM` when [second] is `0`, or `YYYY-MM-DD HH:MM:SS` when [second] is non-zero.
  String formatCompact() {
    final yyyy = year.toString().padLeft(4, '0');
    final mm = month.toString().padLeft(2, '0');
    final dd = day.toString().padLeft(2, '0');
    final hh = hour.toString().padLeft(2, '0');
    final min = minute.toString().padLeft(2, '0');
    if (second == 0) {
      return '$yyyy-$mm-$dd $hh:$min';
    }
    final ss = second.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hh:$min:$ss';
  }

  /// Formats with explicit zero-padded seconds (`YYYY-MM-DD HH:MM:SS`, `19` ASCII characters) per `TDF-SER-004`.
  String formatExplicitSeconds() {
    final yyyy = year.toString().padLeft(4, '0');
    final mm = month.toString().padLeft(2, '0');
    final dd = day.toString().padLeft(2, '0');
    final hh = hour.toString().padLeft(2, '0');
    final min = minute.toString().padLeft(2, '0');
    final ss = second.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hh:$min:$ss';
  }

  /// Parses an unquoted TDF `<YYYY-MM-DD>` date and optional `<HH:MM[:SS]>` clock into a [TdfLocalDateTime], or returns `null`.
  static TdfLocalDateTime? tryParse(String rawDate, [String? rawTime]) {
    if (rawDate.length != 10 ||
        rawDate.codeUnitAt(4) != 0x2D ||
        rawDate.codeUnitAt(7) != 0x2D) {
      return null;
    }
    final parsedYear = _parseDigits(rawDate, 0, 4);
    final parsedMonth = _parseDigits(rawDate, 5, 7);
    final parsedDay = _parseDigits(rawDate, 8, 10);
    if (parsedYear == null ||
        parsedMonth == null ||
        parsedDay == null ||
        !TdfCalendar.isValidGregorianDate(parsedYear, parsedMonth, parsedDay)) {
      return null;
    }
    if (rawTime == null) {
      return TdfLocalDateTime(parsedYear, parsedMonth, parsedDay);
    }
    final parsedClock = TdfRepeatClock.tryParse(rawTime);
    if (parsedClock == null) {
      return null;
    }
    return TdfLocalDateTime(
      parsedYear,
      parsedMonth,
      parsedDay,
      parsedClock.hour,
      parsedClock.minute,
      parsedClock.second,
    );
  }

  /// Parses a single-line `<YYYY-MM-DD> [<HH:MM[:SS]>]` string into a [TdfLocalDateTime], or returns `null`.
  static TdfLocalDateTime? tryParseInput(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    var separatorStart = -1;
    for (var i = 0; i < trimmed.length; i++) {
      final unit = trimmed.codeUnitAt(i);
      if (unit == 0x20 || unit == 0x09) {
        separatorStart = i;
        break;
      }
    }
    if (separatorStart == -1) {
      return tryParse(trimmed);
    }
    final datePart = trimmed.substring(0, separatorStart);
    final remainder = trimmed.substring(separatorStart).trimLeft();
    for (var i = 0; i < remainder.length; i++) {
      final unit = remainder.codeUnitAt(i);
      if (unit == 0x20 || unit == 0x09) {
        return null;
      }
    }
    return tryParse(datePart, remainder);
  }

  /// Parses ASCII decimal digits in `input[start..end]` without intermediate allocations.
  static int? _parseDigits(String input, int start, int end) {
    var value = 0;
    for (var i = start; i < end; i++) {
      final unit = input.codeUnitAt(i);
      if (unit < 0x30 || unit > 0x39) {
        return null;
      }
      value = value * 10 + (unit - 0x30);
    }
    return value;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfLocalDateTime &&
        other.year == year &&
        other.month == month &&
        other.day == day &&
        other.hour == hour &&
        other.minute == minute &&
        other.second == second;
  }

  @override
  int get hashCode => Object.hash(year, month, day, hour, minute, second);

  @override
  String toString() => formatExplicitSeconds();
}

/// Immutable local wall-clock time (`HH:MM` or `HH:MM:SS`) for a `repeat` directive per `spec/TDF_SPEC_0.8.0.md` Section 5.2.1.
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

  /// Formats this clock in canonical `0.8.0` form: empty string for `00:00:00`, `HH:MM` when [second] is `0`, else `HH:MM:SS`.
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

/// Time zone transition and local-to-UTC resolution context per `spec/TDF_SPEC_0.8.0.md` Sections 8.1 and 10.2 (`TDF-CTX-001`, `TDF-CAL-001`).
@immutable
class TdfTimeZoneContext {
  /// Creates a [TdfTimeZoneContext] with [zoneId], [_ruleKind], [fixedOffsetSeconds], and optional [_customOffsetObserver].
  const TdfTimeZoneContext._(
    this.zoneId,
    this._ruleKind, [
    this.fixedOffsetSeconds = 0,
    this._customOffsetObserver,
  ]);

  /// Creates a [TdfTimeZoneContext] backed by [offsetSecondsObserver] for deterministic DST transition verification.
  factory TdfTimeZoneContext.customObserver(
    String zoneId,
    int Function(int utcEpochSeconds) offsetSecondsObserver,
  ) {
    return TdfTimeZoneContext._(
      zoneId,
      _TimeZoneRuleKind.customObserver,
      0,
      offsetSecondsObserver,
    );
  }

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
      fixedOffsetSeconds = 0,
      _customOffsetObserver = null;

  /// Resolves a [TdfTimeZoneContext] by IANA name or ISO UTC offset (`UTC`, `Europe/Berlin`, `America/New_York`, `+01:00`, etc.).
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
    if (trimmed == 'America/New_York' || upper == 'AMERICA/NEW_YORK') {
      return americaNewYork;
    }
    if (upper == 'CET') {
      return TdfTimeZoneContext.fixedOffset(const Duration(hours: 1));
    }
    if (upper == 'CEST') {
      return TdfTimeZoneContext.fixedOffset(const Duration(hours: 2));
    }
    if (upper == 'EST') {
      return TdfTimeZoneContext.fixedOffset(const Duration(hours: -5));
    }
    if (upper == 'EDT') {
      return TdfTimeZoneContext.fixedOffset(const Duration(hours: -4));
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

  /// Creates a [TdfTimeZoneContext] delegating transition lookups to the host OS local zone (`AppTimeZoneMode.automatic`).
  const TdfTimeZoneContext.systemLocal()
    : zoneId = 'SYSTEM_LOCAL',
      _ruleKind = _TimeZoneRuleKind.systemLocal,
      fixedOffsetSeconds = 0,
      _customOffsetObserver = null;

  /// `America/New_York` time zone context implementing US EST (`UTC-5`) / EDT (`UTC-4`) transitions.
  static const TdfTimeZoneContext americaNewYork = TdfTimeZoneContext._(
    'America/New_York',
    _TimeZoneRuleKind.americaNewYork,
  );

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

  /// Upper OS `.toLocal()` clamp (`9999-12-31T23:59:59Z`) preventing 4-digit year overflow.
  static const int _maxClampedSystemEpochSeconds = 253402300799;

  /// Lower OS `.toLocal()` clamp (`1601-01-02T00:00:00Z`) preventing Win32 `FILETIME` pre-1601 failures.
  static const int _minClampedSystemEpochSeconds = -11644387200;

  /// Offset probe interval (`15` minutes = `900` seconds) for local-to-UTC sampling.
  static const int _sampleStepSeconds = 900;

  /// Half-width (`36` hours = `129,600` seconds) around civil wall time covering all IANA offsets and DST jumps.
  static const int _searchHalfWindowSeconds = 129600;

  /// Fixed offset in seconds when [_ruleKind] is [_TimeZoneRuleKind.fixedOffset].
  final int fixedOffsetSeconds;

  /// Canonical or requested time zone identifier.
  final String zoneId;

  final int Function(int utcEpochSeconds)? _customOffsetObserver;
  final _TimeZoneRuleKind _ruleKind;

  /// Whether transition rules are available for this time zone context.
  bool get isAvailable => _ruleKind != _TimeZoneRuleKind.unavailable;

  /// Whether this time zone context can cross Dart isolate boundaries without capturing custom closures.
  bool get isIsolateSendable => _customOffsetObserver == null;

  /// Resolves a local civil date and clock (`year-month-day hour:minute:second`) to a UTC [DateTime] per `TDF-CAL-001`:
  /// 1. Unique local instant -> exact UTC instant.
  /// 2. Overlap (fold) -> earliest matching UTC instant.
  /// 3. Forward gap -> pre-gap UTC offset (`u` `1s` prior to the transition).
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
    if (_ruleKind == _TimeZoneRuleKind.systemLocal ||
        _ruleKind == _TimeZoneRuleKind.customObserver) {
      return _resolveSampledLocalToUtc(year, month, day, hour, minute, second);
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

  /// Converts a UTC [instant] into a validated `0001..9999` [TdfLocalDateTime], throwing [FormatException] when outside range (`TDF-TYPE-004`).
  TdfLocalDateTime toLocalDateTime(DateTime instant) {
    return TdfLocalDateTime.fromWallClock(toLocalWallClock(instant));
  }

  /// Converts a UTC [instant] into local wall-clock components (returned as a `DateTime.utc(...)` carrier).
  DateTime toLocalWallClock(DateTime instant) {
    if (!isAvailable) {
      throw const TdfContextException(
        kind: TdfContextOutcomeKind.timeZoneContextRequired,
        message: 'Time zone context is required for local calendar conversion.',
      );
    }
    final rawUtc = instant.toUtc();
    final utcInstant = DateTime.utc(
      rawUtc.year,
      rawUtc.month,
      rawUtc.day,
      rawUtc.hour,
      rawUtc.minute,
      rawUtc.second,
    );
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

  /// Compares two 6-component local calendar tuples lexicographically.
  static int _compareLocalTuple(
    (int, int, int, int, int, int) left,
    (int, int, int, int, int, int) right,
  ) {
    if (left.$1 != right.$1) return left.$1.compareTo(right.$1);
    if (left.$2 != right.$2) return left.$2.compareTo(right.$2);
    if (left.$3 != right.$3) return left.$3.compareTo(right.$3);
    if (left.$4 != right.$4) return left.$4.compareTo(right.$4);
    if (left.$5 != right.$5) return left.$5.compareTo(right.$5);
    return left.$6.compareTo(right.$6);
  }

  /// Computes the day of the month (`1..7`) of the first Sunday of [month] in [year].
  static int _firstSundayOfMonth(int year, int month) {
    final firstDay = DateTime.utc(year, month);
    return firstDay.weekday == DateTime.sunday ? 1 : (8 - firstDay.weekday);
  }

  /// Computes the day of the month (`25..31`) of the last Sunday of [month] in [year].
  static int _lastSundayOfMonth(int year, int month) {
    final lastDay = DateTime.utc(year, month, 31);
    if (lastDay.weekday == DateTime.sunday) {
      return 31;
    }
    return 31 - lastDay.weekday;
  }

  /// Computes the local wall-clock 6-tuple at [utcEpochSeconds] without restricting probe endpoints to `0001..9999`.
  (int, int, int, int, int, int) _localTupleAtEpochSec(int utcEpochSeconds) {
    final offsetSeconds = _observeOffsetSecondsForEpoch(utcEpochSeconds);
    final shifted = DateTime.fromMillisecondsSinceEpoch(
      (utcEpochSeconds + offsetSeconds) * 1000,
      isUtc: true,
    );
    return (
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
    );
  }

  /// Observes the UTC offset in seconds at [utcEpochSeconds] across sampled zone modes.
  int _observeOffsetSecondsForEpoch(int utcEpochSeconds) {
    return switch (_ruleKind) {
      _TimeZoneRuleKind.fixedOffset => fixedOffsetSeconds,
      _TimeZoneRuleKind.europeBerlin => _resolveEuropeBerlinUtcOffsetSeconds(
        DateTime.fromMillisecondsSinceEpoch(
          utcEpochSeconds * 1000,
          isUtc: true,
        ),
      ),
      _TimeZoneRuleKind.americaNewYork =>
        _resolveAmericaNewYorkUtcOffsetSeconds(utcEpochSeconds),
      _TimeZoneRuleKind.systemLocal => _observeSystemLocalOffsetSeconds(
        utcEpochSeconds,
      ),
      _TimeZoneRuleKind.customObserver =>
        _customOffsetObserver?.call(utcEpochSeconds) ?? 0,
      _TimeZoneRuleKind.unavailable => 0,
    };
  }

  /// Observes the host OS UTC offset in seconds with `[1601-01-02, 9999-12-31]` Win32 clamping.
  static int _observeSystemLocalOffsetSeconds(int utcEpochSeconds) {
    final clampedSeconds = utcEpochSeconds < _minClampedSystemEpochSeconds
        ? _minClampedSystemEpochSeconds
        : (utcEpochSeconds > _maxClampedSystemEpochSeconds
              ? _maxClampedSystemEpochSeconds
              : utcEpochSeconds);
    return DateTime.fromMillisecondsSinceEpoch(
      clampedSeconds * 1000,
      isUtc: true,
    ).toLocal().timeZoneOffset.inSeconds;
  }

  /// Resolves the UTC offset in seconds for a local wall-clock timestamp in `America/New_York` per `TDF-CAL-001`.
  static int _resolveAmericaNewYorkLocalOffsetSeconds(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) {
    const estSeconds = -18000;
    const edtSeconds = -14400;
    if (month < 3 || month > 11) {
      return estSeconds;
    }
    if (month > 3 && month < 11) {
      return edtSeconds;
    }
    final daySeconds = hour * 3600 + minute * 60 + second;
    if (month == 3) {
      final springDay = _firstSundayOfMonth(year, 3) + 7;
      if (day < springDay) {
        return estSeconds;
      }
      if (day > springDay) {
        return edtSeconds;
      }
      return daySeconds < 3 * 3600 ? estSeconds : edtSeconds;
    }
    final autumnDay = _firstSundayOfMonth(year, 11);
    if (day < autumnDay) {
      return edtSeconds;
    }
    if (day > autumnDay) {
      return estSeconds;
    }
    return daySeconds < 2 * 3600 ? edtSeconds : estSeconds;
  }

  /// Resolves the UTC offset in seconds (`-18000` EST or `-14400` EDT) at [utcEpochSeconds] in `America/New_York`.
  static int _resolveAmericaNewYorkUtcOffsetSeconds(int utcEpochSeconds) {
    final utcInstant = DateTime.fromMillisecondsSinceEpoch(
      utcEpochSeconds * 1000,
      isUtc: true,
    );
    final year = utcInstant.year;
    if (year < 1 || year > 9999) {
      return -18000;
    }
    final secondSundayMarch = _firstSundayOfMonth(year, 3) + 7;
    final firstSundayNovember = _firstSundayOfMonth(year, 11);
    final dstStartSec =
        DateTime.utc(year, 3, secondSundayMarch, 7).millisecondsSinceEpoch ~/
        1000;
    final dstEndSec =
        DateTime.utc(year, 11, firstSundayNovember, 6).millisecondsSinceEpoch ~/
        1000;
    if (utcEpochSeconds >= dstStartSec && utcEpochSeconds < dstEndSec) {
      return -14400;
    }
    return -18000;
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
      return daySeconds < 3 * 3600 ? cetSeconds : cestSeconds;
    }
    final autumnDay = _lastSundayOfMonth(year, 10);
    if (day < autumnDay) {
      return cestSeconds;
    }
    if (day > autumnDay) {
      return cetSeconds;
    }
    return daySeconds < 3 * 3600 ? cestSeconds : cetSeconds;
  }

  /// Resolves the UTC offset in seconds for a UTC [utcInstant] in `Europe/Berlin`.
  static int _resolveEuropeBerlinUtcOffsetSeconds(DateTime utcInstant) {
    final year = utcInstant.year;
    if (year < 1 || year > 9999) {
      return 3600;
    }
    final springSunday = _lastSundayOfMonth(year, 3);
    final autumnSunday = _lastSundayOfMonth(year, 10);
    final dstStartUtc = DateTime.utc(year, 3, springSunday, 1);
    final dstEndUtc = DateTime.utc(year, 10, autumnSunday, 1);
    if (!utcInstant.isBefore(dstStartUtc) && utcInstant.isBefore(dstEndUtc)) {
      return 7200;
    }
    return 3600;
  }

  /// Resolves the UTC offset in seconds for a direct fixed or analytical local wall time.
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
      _TimeZoneRuleKind.americaNewYork =>
        _resolveAmericaNewYorkLocalOffsetSeconds(
          year,
          month,
          day,
          hour,
          minute,
          second,
        ),
      _TimeZoneRuleKind.systemLocal ||
      _TimeZoneRuleKind.customObserver ||
      _TimeZoneRuleKind.unavailable => 0,
    };
  }

  /// Resolves the UTC offset in seconds for an exact second-precision UTC [utcInstant].
  int _resolveOffsetSecondsForUtc(DateTime utcInstant) {
    final epochSec = utcInstant.millisecondsSinceEpoch ~/ 1000;
    return switch (_ruleKind) {
      _TimeZoneRuleKind.fixedOffset => fixedOffsetSeconds,
      _TimeZoneRuleKind.europeBerlin => _resolveEuropeBerlinUtcOffsetSeconds(
        utcInstant,
      ),
      _TimeZoneRuleKind.americaNewYork =>
        _resolveAmericaNewYorkUtcOffsetSeconds(epochSec),
      _TimeZoneRuleKind.systemLocal => _observeSystemLocalOffsetSeconds(
        epochSec,
      ),
      _TimeZoneRuleKind.customObserver =>
        _customOffsetObserver?.call(epochSec) ?? 0,
      _TimeZoneRuleKind.unavailable => 0,
    };
  }

  /// Resolves local components to UTC via a 3-probe non-transition fast path with `15`-minute sweep fallback (`TDF-CAL-001`).
  DateTime _resolveSampledLocalToUtc(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) {
    final wallAsUtc = DateTime.utc(year, month, day, hour, minute, second);
    final centerSec = wallAsUtc.millisecondsSinceEpoch ~/ 1000;
    final startSec = centerSec - _searchHalfWindowSeconds;
    final endSec = centerSec + _searchHalfWindowSeconds;

    final offsetStart = _observeOffsetSecondsForEpoch(startSec);
    final offsetCenter = _observeOffsetSecondsForEpoch(centerSec);
    final offsetEnd = _observeOffsetSecondsForEpoch(endSec);
    if (offsetStart == offsetCenter && offsetCenter == offsetEnd) {
      final candidateUtcSec = centerSec - offsetCenter;
      if (offsetCenter == 0 ||
          _observeOffsetSecondsForEpoch(candidateUtcSec) == offsetCenter) {
        final resolvedUtc = DateTime.fromMillisecondsSinceEpoch(
          candidateUtcSec * 1000,
          isUtc: true,
        );
        if (!TdfCalendar.isWithinTimestampBounds(resolvedUtc)) {
          throw const FormatException('InvalidTimestamp');
        }
        return resolvedUtc;
      }
    }

    final targetTuple = (year, month, day, hour, minute, second);
    final seenOffsets = <int>{};
    int? earliestMatchSec;
    for (
      var probeSec = startSec;
      probeSec <= endSec;
      probeSec += _sampleStepSeconds
    ) {
      final candidateSec = _testCandidateOffsetAtProbe(
        probeSec,
        centerSec,
        targetTuple,
        seenOffsets,
      );
      if (candidateSec != null &&
          (earliestMatchSec == null || candidateSec < earliestMatchSec)) {
        earliestMatchSec = candidateSec;
      }
    }

    final DateTime resolvedUtc;
    if (earliestMatchSec != null) {
      resolvedUtc = DateTime.fromMillisecondsSinceEpoch(
        earliestMatchSec * 1000,
        isUtc: true,
      );
    } else {
      final preGapSec = _searchPreGapEpochSec(startSec, endSec, targetTuple);
      final preGapOffset = _observeOffsetSecondsForEpoch(preGapSec);
      resolvedUtc = wallAsUtc.subtract(Duration(seconds: preGapOffset));
    }
    if (!TdfCalendar.isWithinTimestampBounds(resolvedUtc)) {
      throw const FormatException('InvalidTimestamp');
    }
    return resolvedUtc;
  }

  /// Binary-searches `[startSec, endSec]` to find `u` (`1s` before a forward clock gap) where `local(u) < target < local(u + 1)`.
  int _searchPreGapEpochSec(
    int startSec,
    int endSec,
    (int, int, int, int, int, int) targetTuple,
  ) {
    var low = startSec;
    var high = endSec;
    while (high - low > 1) {
      final mid = (low + high) >> 1;
      if (_compareLocalTuple(_localTupleAtEpochSec(mid), targetTuple) < 0) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Tests the offset observed at [probeSec] for an exact inverse match to [targetTuple], returning the matching UTC epoch second or `null`.
  int? _testCandidateOffsetAtProbe(
    int probeSec,
    int centerSec,
    (int, int, int, int, int, int) targetTuple,
    Set<int> seenOffsets,
  ) {
    final offsetSec = _observeOffsetSecondsForEpoch(probeSec);
    if (!seenOffsets.add(offsetSec)) {
      return null;
    }
    final candidateUtcSec = centerSec - offsetSec;
    if (_localTupleAtEpochSec(candidateUtcSec) == targetTuple) {
      return candidateUtcSec;
    }
    return null;
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
        other.fixedOffsetSeconds == fixedOffsetSeconds &&
        other._customOffsetObserver == _customOffsetObserver;
  }

  @override
  int get hashCode =>
      Object.hash(zoneId, _ruleKind, fixedOffsetSeconds, _customOffsetObserver);
}
