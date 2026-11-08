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

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';

void main() {
  group('TDF 0.6.0 Error Kinds and Resource Bounds', () {
    test(
      'defines 0.6.0 location and number bounds and unknownLocationReference',
      () {
        expect(maxTdfLocations, equals(200));
        expect(maxTdfLocationRadius, equals(100000));
        expect(maxTdfLocationRefsPerEntity, equals(63));
        expect(maxTdfNumberLength, equals(24));
        expect(
          TdfErrorKind.values,
          contains(TdfErrorKind.unknownLocationReference),
        );
      },
    );
  });

  group('TdfLocation Entity, Base62 IDs, Decimal Validation & Rounding', () {
    test('generates and validates 10-character Base62 location IDs', () {
      final id = generateLocationId(timestamp: DateTime.utc(2026, 11, 1, 8, 0));
      expect(id.length, equals(10));
      expect(isValidLocationId(id), isTrue);
      expect(isValidLocationId('7pQr9mOkD2'), isTrue);
      expect(isValidLocationId('short'), isFalse);
      expect(isValidLocationId('7pQr9mOkD!'), isFalse);
    });

    test('constructs immutable TdfLocation with canonical decimal texts, epoch default modifiedAt, and redacted toString', () {
      const location = TdfLocation(
        id: '7pQr9mOkD2',
        name: 'Home',
        note: 'Driveway and garden',
        source: 'Erfurt, Germany',
        latitude: 50.9787,
        longitude: 11.0328,
        radius: 150.0,
      );
      expect(
        location.effectiveModifiedAt,
        equals(TdfLocation.defaultModifiedAt),
      );
      expect(location.latitudeText, equals('50.9787'));
      expect(location.longitudeText, equals('11.0328'));
      expect(location.radiusText, equals('150'));
      expect(
        location.toString(),
        equals('location 7pQr9mOkD2'),
        reason: 'toString must redact name, note, source, and coordinates',
      );

      final updated = location.copyWith(
        name: 'Home HQ',
        clearNote: true,
        clearSource: true,
        radius: 250.5,
        modifiedAt: DateTime.utc(2026, 11, 2, 10, 0),
      );
      expect(updated.name, equals('Home HQ'));
      expect(updated.note, isNull);
      expect(updated.source, isNull);
      expect(updated.radiusText, equals('250.5'));
      expect(
        updated.effectiveModifiedAt,
        equals(DateTime.utc(2026, 11, 2, 10, 0)),
      );
      expect(updated, isNot(equals(location)));
      expect(updated.copyWith(), equals(updated));
      expect(updated.copyWith().hashCode, equals(updated.hashCode));
    });

    test('validates 0.6.0 coordinates and radius decimal tokens and precision bounds', () {
      expect(TdfLocation.isValidNumberToken('50.978700'), isTrue);
      expect(TdfLocation.isValidNumberToken('-0.000000'), isTrue);
      expect(TdfLocation.isValidNumberToken('+50.0'), isFalse);
      expect(TdfLocation.isValidNumberToken('1e2'), isFalse);
      expect(TdfLocation.isValidNumberToken('NaN'), isFalse);
      expect(TdfLocation.isValidNumberToken('Infinity'), isFalse);
      expect(TdfLocation.isValidNumberToken('50.'), isFalse);
      expect(TdfLocation.isValidNumberToken('.5'), isFalse);

      expect(
        TdfLocation.countSignificantFractionalDigits('50.978700'),
        equals(4),
      );
      expect(
        TdfLocation.countSignificantFractionalDigits('48.1371544'),
        equals(7),
      );
      expect(TdfLocation.countSignificantFractionalDigits('150.00'), equals(0));
      expect(TdfLocation.countSignificantFractionalDigits('75.525'), equals(3));
    });

    test('rounds decimal literals half-away-from-zero for 0.5.1 -> 0.6.0 migration and GPS coordinates', () {
      expect(
        TdfLocation.roundDecimalHalfAwayFromZero('48.1371544', 6),
        equals('48.137154'),
      );
      expect(
        TdfLocation.roundDecimalHalfAwayFromZero('11.5761245', 6),
        equals('11.576125'),
        reason:
            '5 in the 7th decimal place must round away from zero to .137125',
      );
      expect(
        TdfLocation.roundDecimalHalfAwayFromZero('-11.5761245', 6),
        equals('-11.576125'),
      );
      expect(
        TdfLocation.roundDecimalHalfAwayFromZero('75.500', 2),
        equals('75.5'),
      );
      expect(TdfLocation.roundDecimalHalfAwayFromZero('0.004', 2), equals('0'));
      expect(
        TdfLocation.roundDecimalHalfAwayFromZero('0.005', 2),
        equals('0.01'),
      );
      expect(
        TdfLocation.roundDecimalHalfAwayFromZero('-0.0000001', 6),
        equals('0'),
      );
      expect(
        TdfLocation.formatRoundedDouble(50.97870000001, 6),
        equals('50.9787'),
      );
    });
  });

  group('TdfLabel isScoped and ID-Referenced LocationTaskCondition', () {
    test('supports TdfLabel.isScoped and LocationTaskCondition.fromIds with Haversine evaluation', () {
      const regularLabel = TdfLabel(id: '4x9p2mOkD2', name: 'General');
      expect(regularLabel.isScoped, isFalse);
      final scopedLabel = regularLabel.copyWith(isScoped: true);
      expect(scopedLabel.isScoped, isTrue);
      expect(scopedLabel, isNot(equals(regularLabel)));

      final condition = LocationTaskCondition.fromIds(const <String>[
        '7pQr9mOkD2',
        '5473OnNDhL',
        '7pQr9mOkD2',
      ]);
      expect(
        condition.locationIds,
        equals(const <String>['7pQr9mOkD2', '5473OnNDhL']),
        reason: 'LocationTaskCondition.fromIds must deduplicate in first-seen declaration order',
      );
      expect(
        condition.toTdfDirectiveArgs(),
        equals('location 7pQr9mOkD2 5473OnNDhL'),
      );

      const locations = <String, TdfLocation>{
        '7pQr9mOkD2': TdfLocation(
          id: '7pQr9mOkD2',
          name: 'Home',
          latitude: 50.9787,
          longitude: 11.0328,
          radius: 150,
        ),
        '5473OnNDhL': TdfLocation(
          id: '5473OnNDhL',
          name: 'Office',
          latitude: 52.52,
          longitude: 13.405,
          radius: 200,
        ),
      };

      final evalTime = DateTime.utc(2026, 11, 1, 12, 0);
      expect(
        condition.isSatisfiedAt(evalTime, locations: locations),
        isTrue,
        reason:
            'Without GPS coordinates, location condition must evaluate to true',
      );
      expect(
        condition.isSatisfiedAt(
          evalTime,
          currentLatitude: 52.52,
          currentLongitude: 13.405,
          locations: locations,
        ),
        isTrue,
        reason: 'Matching second referenced location (OR semantics) must evaluate to true',
      );
      expect(
        condition.isSatisfiedAt(
          evalTime,
          currentLatitude: 48.137,
          currentLongitude: 11.576,
          locations: locations,
        ),
        isFalse,
        reason: 'Coordinates outside all referenced location radii must evaluate to false',
      );
    });
  });

  group('TaskOrigin, TaskItem dueAt/origin, TaskLink URI Hardening & Deleted Locations', () {
    test('stores TaskOrigin and TaskItem dueAt/origin and redacts externalKey in TaskOrigin.toString', () {
      const origin = TaskOrigin(
        namespace: 'https://jira.example.com',
        externalKey: 'SECRET-KEY-99',
      );
      expect(origin.toString().contains('SECRET-KEY-99'), isFalse);

      final due = DateTime.utc(2026, 11, 7, 16, 0);
      final task = TaskItem(
        id: '8jKaCdOkD2',
        title: 'Task with due and origin',
        dueAt: due,
        origin: origin,
      );
      expect(task.dueAt, equals(due));
      expect(task.origin, equals(origin));

      final cleared = task.copyWith(clearDueAt: true, clearOrigin: true);
      expect(cleared.dueAt, isNull);
      expect(cleared.origin, isNull);
    });

    test('rejects javascript:, vbscript:, and data: schemes in TaskLink.isValidUri', () {
      expect(TaskLink.isValidUri('https://example.com/portal#login'), isTrue);
      expect(TaskLink.isValidUri('file:///home/user/docs'), isTrue);
      expect(TaskLink.isValidUri('javascript:alert(1)'), isFalse);
      expect(TaskLink.isValidUri('JaVaScRiPt:alert(1)'), isFalse);
      expect(TaskLink.isValidUri('vbscript:msgbox("hi")'), isFalse);
      expect(TaskLink.isValidUri('data:text/html,<script>'), isFalse);
      expect(TaskLink.isValidUri('DATA:text/plain;base64,SGVsbG8='), isFalse);
      expect(TaskLink.isValidUri('https://example.com/a\nb'), isFalse);
      expect(TaskLink.isValidUri('https://example.com/a\tb'), isFalse);
    });

    test('supports TdfDeletedLocationRecord and location IDs in TdfDeletedBlock and TdfSyncOutcomeException', () {
      final deletedLoc = TdfDeletedLocationRecord(
        locationId: '8tYp4M0eF3',
        deletedAt: DateTime.utc(2026, 11, 2, 10, 15),
      );
      final block = TdfDeletedBlock(
        generation: 0,
        locations: <TdfDeletedLocationRecord>[deletedLoc],
      );
      expect(block.isDefaultEmpty, isFalse);
      expect(block.totalRecords, equals(1));
      expect(block.findLocationRecord('8tYp4M0eF3'), equals(deletedLoc));
      expect(block.findLocationRecord('missing123'), isNull);

      const syncError = TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.deletionConflict,
        message: 'Location conflict',
        conflictedLocationIds: <String>['8tYp4M0eF3'],
        ambiguousLocationIds: <String>['7pQr9mOkD2'],
      );
      expect(
        syncError.conflictedLocationIds,
        equals(const <String>['8tYp4M0eF3']),
      );
      expect(
        syncError.ambiguousLocationIds,
        equals(const <String>['7pQr9mOkD2']),
      );
    });
  });
}
