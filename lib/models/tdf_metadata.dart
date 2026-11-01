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

/// Represents a dynamic activation condition (`condition` directive) on a TDF `task` block.
@immutable
sealed class TaskCondition {
  /// Creates a [TaskCondition].
  const TaskCondition();

  /// Evaluates whether this condition is satisfied at [evaluationTime].
  bool isSatisfiedAt(DateTime evaluationTime);

  /// Formats the condition arguments as a canonical TDF directive suffix.
  String toTdfDirectiveArgs();
}

/// Weekday activation condition (`condition day <mon|tue|wed|thu|fri|sat|sun ...>`).
@immutable
class DayTaskCondition extends TaskCondition {
  /// Creates a [DayTaskCondition] for the given [weekdays] (`1..7`) and [dayTokens].
  DayTaskCondition({
    required List<int> weekdays,
    required List<String> dayTokens,
  }) : weekdays = List<int>.unmodifiable(weekdays),
       dayTokens = List<String>.unmodifiable(dayTokens);

  /// Canonical lowercase weekday tokens (`mon` through `sun`) in declaration order.
  final List<String> dayTokens;

  /// ISO-8601 weekday integers (`1` for Monday through `7` for Sunday).
  final List<int> weekdays;

  @override
  bool isSatisfiedAt(DateTime evaluationTime) {
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

/// Daily time-window activation condition (`condition time <HH:MM> <HH:MM>`).
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
  bool isSatisfiedAt(DateTime evaluationTime) {
    final currentMinutes = evaluationTime.hour * 60 + evaluationTime.minute;
    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    }
    return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
  }

  @override
  String toTdfDirectiveArgs() => 'time $startToken $endToken';

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

/// Immutable representation of a TDF `category` root block.
@immutable
class TdfCategory {
  /// Creates a [TdfCategory] definition.
  const TdfCategory({
    required this.id,
    required this.name,
    this.color,
    this.note,
  });

  /// Optional hexadecimal color code (`"#RRGGBB"`).
  final String? color;

  /// Unique category identifier (`<id>`).
  final String id;

  /// Human-readable display name of the category.
  final String name;

  /// Optional extended description.
  final String? note;

  /// Returns a copy of this category with updated fields.
  TdfCategory copyWith({
    String? id,
    String? name,
    String? color,
    String? note,
  }) {
    return TdfCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfCategory &&
        other.id == id &&
        other.name == name &&
        other.color == color &&
        other.note == note;
  }

  @override
  int get hashCode => Object.hash(id, name, color, note);

  @override
  String toString() => 'category $id ($name)';
}

/// Immutable representation of a TDF `location` root block.
@immutable
class TdfLocation {
  /// Creates a [TdfLocation] definition.
  const TdfLocation({
    required this.id,
    required this.name,
    this.note,
    this.latitude,
    this.longitude,
    this.radiusMeters,
  });

  /// Unique location identifier (`<id>`).
  final String id;

  /// Optional decimal latitude coordinate.
  final double? latitude;

  /// Optional decimal longitude coordinate.
  final double? longitude;

  /// Human-readable display name of the location.
  final String name;

  /// Optional extended description.
  final String? note;

  /// Optional geofencing radius in meters.
  final double? radiusMeters;

  /// Returns a copy of this location with updated fields.
  TdfLocation copyWith({
    String? id,
    String? name,
    String? note,
    double? latitude,
    double? longitude,
    double? radiusMeters,
  }) {
    return TdfLocation(
      id: id ?? this.id,
      name: name ?? this.name,
      note: note ?? this.note,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfLocation &&
        other.id == id &&
        other.name == name &&
        other.note == note &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.radiusMeters == radiusMeters;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, note, latitude, longitude, radiusMeters);

  @override
  String toString() => 'location $id ($name)';
}
