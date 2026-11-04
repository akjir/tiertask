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
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/services/tdf_importer.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 4, 12, 0);

  group('TDF 0.5.0 Section 10 Explicit Version Import & Migration Chain', () {
    test('executes chained 0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 migration with Europe/Berlin DST conversions, intermediate local deferral preservation, and Section 10.4.4 ID vectors', () {
      const doc020 = '''
tdf 0.2.0

label home {
    name "Home"
    condition day sat sun
}

task t001 {
    name      "Summer DST Task"
    created   2026-07-01
    queued    2026-07-01 09:00
    suspended 2026-10-25 02:30
    labels    home
}

task home priority {
    name     "Winter Completed Task"
    created  2026-11-01 00:30
    queued   2026-11-01 08:00
    finished 2026-11-02 10:00
    blocked  t001 gone
    labels   home
}
''';

      expect(
        () => TdfImporter.importDocument(doc020, evaluationTime: fixedDate),
        throwsA(
          isA<TdfContextException>().having(
            (error) => error.kind,
            'kind',
            TdfContextOutcomeKind.importContextRequired,
          ),
        ),
        reason: 'Importing 0.2.0 without an explicit sourceTimeZone must fail with ImportContextRequired',
      );

      final step030 = TdfImporter.migrate020To030(
        doc020,
        sourceTimeZone: TdfTimeZoneContext.europeBerlin,
      );
      expect(step030, startsWith('tdf 0.3.0\n'));
      expect(
        step030,
        contains('    created 2026-06-30 22:00\n'),
        reason: '2026-07-01 00:00 CEST (UTC+2) must convert to preceding UTC day 2026-06-30 22:00',
      );
      expect(
        step030,
        contains('    suspended 2026-10-25 02:30\n'),
        reason: '0.2.0 -> 0.3.0 must preserve suspended as a local calendar value without converting it prematurely',
      );
      expect(
        step030,
        contains('label home {\n'),
        reason: '0.2.0 -> 0.3.0 must preserve source entity IDs',
      );

      final step040 = TdfImporter.migrate030To040(step030);
      expect(step040, startsWith('tdf 0.4.0\n'));
      expect(
        step040,
        contains('label e2Mz9WqsjC {\n'),
        reason: 'label/home must map to e2Mz9WqsjC per Section 10.4.4',
      );
      expect(
        step040,
        contains('task OaPtpMHEy3 {\n'),
        reason: 'task/t001 must map to OaPtpMHEy3 per Section 10.4.4',
      );
      expect(
        step040,
        contains('task vK4z80gnew priority {\n'),
        reason: 'task/home must map to vK4z80gnew (distinct from label/home) per Section 10.4.4',
      );
      expect(
        step040,
        contains('    blocked OaPtpMHEy3 5OhMnA4x2F\n'),
        reason: 'Missing prerequisite gone must map to 5OhMnA4x2F without creating a task block',
      );

      final result = TdfImporter.importDocument(
        doc020,
        sourceTimeZone: TdfTimeZoneContext.europeBerlin,
        evaluationTime: fixedDate,
      );
      expect(
        result.executedSteps,
        equals(['0.2.0', '0.3.0', '0.4.0', '0.5.0']),
        reason:
            'Chained 0.2.0 import must execute every intermediate version step',
      );
      final migratedTask = result.board.findTask('OaPtpMHEy3')!;
      expect(
        migratedTask.suspendedAt,
        equals(DateTime.utc(2026, 10, 25, 0, 30)),
        reason: 'Fall-back overlap 2026-10-25 02:30 in Europe/Berlin must convert to first occurrence 00:30 UTC in 0.4.0 -> 0.5.0',
      );
      expect(result.board.queueBlock.taskIds, equals(['OaPtpMHEy3']));

      final finishedTask = result.board.findTask('vK4z80gnew')!;
      expect(finishedTask.isCompleted, isTrue);
      expect(finishedTask.completions, equals(1));
      expect(
        finishedTask.blockedByTaskIds,
        equals(['5OhMnA4x2F', 'OaPtpMHEy3']),
      );
    });

    test('migrates 0.4.0 to 0.5.0 preserving canonical IDs, mapping 9999-12-31 23:59 sentinel to forever, extracting non-midnight repeat clock from finite deferral, and building shared queue in legacy order', () {
      const doc040 = '''
tdf 0.4.0

label 4x9p2mOkD2 {
    name "Ops"
}

task 111111OkD2 {
    name      "Regular Earlier Task"
    created   2026-11-01 08:00
    queued    2026-11-01 08:00
    modified  2026-11-01 10:00
    suspended 2026-03-29 02:30
    repeat    1 days
    labels    4x9p2mOkD2
}

task 222222OkD2 priority {
    name      "Priority Later Task"
    created   2026-11-01 09:00
    queued    2026-11-01 09:00
    modified  2026-11-01 12:00
    suspended 9999-12-31 23:59
    repeat    7 days
}

task 333333OkD2 {
    name     "Completed Task"
    created  2026-11-01 07:00
    queued   2026-11-01 07:30
    finished 2026-11-01 11:00
}
''';

      final result = tdfService.importDocument(
        doc040,
        sourceTimeZone: TdfTimeZoneContext.europeBerlin,
        evaluationTime: fixedDate,
      );

      final task1 = result.findTask('111111OkD2')!;
      expect(
        task1.repeatRule,
        equals(
          const TaskRepeatRule(
            count: 1,
            unit: RepeatUnit.days,
            clock: TdfRepeatClock(hour: 2, minute: 30),
          ),
        ),
        reason: 'Recurring task with finite non-midnight deferral in 0.4.0 must preserve 02:30 clock on repeat before converting suspended to UTC',
      );
      expect(
        task1.suspendedAt,
        equals(DateTime.utc(2026, 3, 29, 1, 30)),
        reason: 'Spring-forward gap 2026-03-29 02:30 in Europe/Berlin must convert using pre-gap CET (+01:00) to 01:30 UTC',
      );

      final task2 = result.findTask('222222OkD2')!;
      expect(
        task2.isSuspendedForever,
        isTrue,
        reason: 'Sentinel 9999-12-31 23:59 must map to suspended forever without timezone conversion',
      );
      expect(
        task2.repeatRule,
        equals(const TaskRepeatRule(count: 7, unit: RepeatUnit.days)),
        reason: 'Indefinite source deferral supplies no recurrence clock (defaults to midnight)',
      );

      final task3 = result.findTask('333333OkD2')!;
      expect(task3.completions, equals(1));

      expect(
        result.queueBlock.taskIds,
        equals(['222222OkD2', '111111OkD2']),
        reason: 'Shared queue must order priority tasks first, then regular tasks by ascending queuedAt',
      );
      expect(
        result.queueBlock.modifiedAt,
        equals(DateTime.utc(2026, 11, 1, 12, 0)),
        reason: 'Nonempty migrated queue revision must equal max effectiveModifiedAt of its member tasks',
      );
    });

    test('reserves canonical prerequisite IDs during 0.3.0 -> 0.4.0 migration even when occurring only as a missing prerequisite, and rejects target limit / timestamp violations', () {
      const docWithReservedPrerequisite = '''
tdf 0.3.0

task t001 {
    name    "Colliding With Missing Canonical Prerequisite"
    created 2026-11-01 08:00
    blocked OaPtpMHEy3
}
''';

      final migrated040 = TdfImporter.migrate030To040(
        docWithReservedPrerequisite,
      );
      expect(
        migrated040,
        contains('task ohlr11vwDl {\n'),
        reason: 'When OaPtpMHEy3 is reserved by a missing prerequisite reference, task/t001 must advance to counter 1 candidate ohlr11vwDl per Section 10.4.4',
      );
      expect(migrated040, contains('    blocked OaPtpMHEy3\n'));

      // 0.4.0 entity with 600 condition rules (100 inline + 500 in condition block) -> rejected under 0.5.0 MAX_CONDITION_RULES_PER_ENTITY (512):
      final inline100 = List.filled(100, '  condition day mon').join('\n');
      final block500 = List.filled(500, '    time 09:00 17:00').join('\n');
      final doc040With600Rules =
          'tdf 0.4.0\n'
          'label 4x9p2mOkD2 {\n'
          '  name "600 Rules in 0.4.0"\n'
          '$inline100\n'
          '  condition {\n$block500\n  }\n'
          '}\n';
      expect(
        () => TdfImporter.importDocument(doc040With600Rules),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Source 0.4.0 entity with 600 condition rules must be rejected with LimitExceeded under 0.5.0 without dropping rules',
      );

      // Out-of-range converted timestamp (0001-01-01 00:30 in UTC+02:00 -> year 0000 in UTC):
      const outOfRange040 = '''
tdf 0.4.0

task 8jKaCdOkD2 {
    name      "Underflow Deferral"
    created   2026-11-01 08:00
    suspended 0001-01-01 00:30
}
''';
      expect(
        () => TdfImporter.importDocument(
          outOfRange040,
          sourceTimeZone: TdfTimeZoneContext.fixedOffset(
            const Duration(hours: 2),
          ),
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.invalidTimestamp,
          ),
        ),
        reason: 'Converted UTC timestamp below 0001-01-01 00:00:00 must fail with InvalidTimestamp without clamping',
      );
    });
  });
}
