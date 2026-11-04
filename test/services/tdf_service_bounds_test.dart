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
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('TDF 0.5.0 Section 7 Resource Bounds & Section 8 Error Conditions', () {
    test('rejects all mandatory syntax and schema error conditions in Section 8', () {
      void expectRawTdfError(
        String input,
        TdfErrorKind expectedKind, {
        int? expectedLine,
      }) {
        expect(
          () => tdfService.parse(input, evaluationTime: fixedDate),
          throwsA(
            isA<TdfException>()
                .having((error) => error.kind, 'kind', expectedKind)
                .having(
                  (error) => expectedLine == null ? null : error.line,
                  'line',
                  expectedLine,
                ),
          ),
          reason: 'Input must fail with $expectedKind: $input',
        );
      }

      void expectTdfError(
        String bodyWithoutHeader,
        TdfErrorKind expectedKind, {
        int? expectedLine,
      }) {
        expectRawTdfError(
          'tdf 0.5.0\n$bodyWithoutHeader',
          expectedKind,
          expectedLine: expectedLine == null ? null : expectedLine + 1,
        );
      }

      expectRawTdfError('', TdfErrorKind.missingVersionHeader, expectedLine: 1);
      expectRawTdfError(
        '# comment only\n',
        TdfErrorKind.missingVersionHeader,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf\n',
        TdfErrorKind.missingVersionHeader,
        expectedLine: 1,
      );
      expectRawTdfError(
        'label 000001OkD2 {\n  name "Home"\n}',
        TdfErrorKind.missingVersionHeader,
        expectedLine: 1,
      );
      expectRawTdfError(
        'category home {\n  name "Home"\n}',
        TdfErrorKind.missingVersionHeader,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf 0.4.0\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf "0.5.0"\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf 0.5.0 extra\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );

      expectTdfError(
        'tdf 0.5.0',
        TdfErrorKind.unexpectedRootDirective,
        expectedLine: 1,
      );
      expectTdfError(
        'name "Root Directive"',
        TdfErrorKind.unexpectedRootDirective,
        expectedLine: 1,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  queued\n}',
        TdfErrorKind.missingDirectiveArgument,
        expectedLine: 4,
      );
      expectTdfError(
        '"task" 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 1,
      );
      expectTdfError(
        'task 000001OkD2 {\n  "name" "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2{\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 1,
      );
      expectTdfError(
        'deleted extra {\n  generation 0\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 1,
      );
      expectTdfError(
        'queue extra {\n  modified 2026-11-01 00:00:00\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 1,
      );
      expectTdfError(
        'task 000001OkD2 { extra\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 1,
      );
      expectTdfError(
        'label 000001OkD2 {}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 1,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n} trailing',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Control\x07Char"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 2,
      );
      expectTdfError(
        '# comment with null byte \u0000\n',
        TdfErrorKind.unexpectedToken,
        expectedLine: 1,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name\u00A0"NBSP separator"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01',
        TdfErrorKind.unclosedBlock,
      );
      expectTdfError('}', TdfErrorKind.unexpectedClosingBrace, expectedLine: 1);
      expectTdfError(
        'task 000001OkD2 {\n  name "Unterminated\n  created 2026-11-01\n}',
        TdfErrorKind.unterminatedString,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad \\x escape"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidEscapeSequence,
        expectedLine: 2,
      );
      expectTdfError(
        'project 000001OkD2 {\n  name "Unknown"\n}',
        TdfErrorKind.unknownBlockType,
        expectedLine: 1,
      );
      expectTdfError(
        'deleted {\n  generation 0\n  condition {\n    day mon\n  }\n}',
        TdfErrorKind.unknownBlockType,
        expectedLine: 3,
      );
      expectTdfError(
        'queue {\n  modified 2026-11-01 00:00:00\n  condition {\n    day mon\n  }\n}',
        TdfErrorKind.unknownBlockType,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  unknown_dir 123\n}',
        TdfErrorKind.unknownDirective,
        expectedLine: 4,
      );
      expectTdfError(
        'deleted {\n  generation 0\n  unknown_dir 123\n}',
        TdfErrorKind.unknownDirective,
        expectedLine: 3,
      );
      expectTdfError(
        'queue {\n  modified 2026-11-01 00:00:00\n  unknown_dir 123\n}',
        TdfErrorKind.unknownDirective,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Missing created"\n}',
        TdfErrorKind.missingRequiredDirective,
      );
      expectTdfError(
        'deleted {\n  task 000001OkD2 2026-11-01 12:00:00\n}',
        TdfErrorKind.missingRequiredDirective,
        expectedLine: 3,
      );
      expectTdfError(
        'queue {\n  task 000001OkD2\n}',
        TdfErrorKind.missingRequiredDirective,
        expectedLine: 3,
      );
      expectTdfError(
        'deleted {\n  generation 0\n}\ndeleted {\n  generation 1\n}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 4,
      );
      expectTdfError(
        'queue {\n  modified 2026-11-01 00:00:00\n}\nqueue {\n  modified 2026-11-01 00:00:00\n}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 4,
      );
      expectTdfError(
        'deleted {\n  generation 0\n  task 000001OkD2 2026-11-01\n  task 000001OkD2 2026-11-02\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 4,
      );
      expectTdfError(
        'deleted {\n  generation 0\n  task 000001OkD2 2026-11-01\n}\ntask 000001OkD2 {\n  name "Live and Deleted"\n  created 2026-11-01\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 5,
      );
      expectTdfError(
        'queue {\n  modified 2026-11-01 00:00:00\n  task 000001OkD2\n  task 000001OkD2\n}\ntask 000001OkD2 {\n  name "Dup queue"\n  created 2026-11-01\n  queued 2026-11-01\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Scheduled but missing from queue"\n  created 2026-11-01\n  queued 2026-11-01\n}',
        TdfErrorKind.invalidQueueMembership,
        expectedLine: 1,
      );
      expectTdfError(
        'queue {\n  modified 2026-11-01 00:00:00\n  task 999999OkD2\n}',
        TdfErrorKind.invalidQueueMembership,
        expectedLine: 3,
      );
      expectTdfError(
        'queue {\n  modified 2026-11-01 00:00:00\n  task 000001OkD2\n}\ntask 000001OkD2 {\n  name "Someday in queue"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidQueueMembership,
        expectedLine: 3,
      );
      expectTdfError(
        'queue {\n  modified 2026-11-01 00:00:00\n  task 000001OkD2\n}\ntask 000001OkD2 {\n  name "Completed in queue"\n  created 2026-11-01\n  queued 2026-11-01\n  finished 2026-11-01 10:00\n  completions 1\n}',
        TdfErrorKind.invalidQueueMembership,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Finished without completions"\n  created 2026-11-01\n  finished 2026-11-01 10:00\n}',
        TdfErrorKind.invalidCompletionState,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Finished with zero completions"\n  created 2026-11-01\n  finished 2026-11-01 10:00\n  completions 0\n}',
        TdfErrorKind.invalidCompletionState,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Quoted repeat clock"\n  created 2026-11-01\n  repeat 1 days "09:00"\n}',
        TdfErrorKind.invalidTime,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Invalid repeat clock"\n  created 2026-11-01\n  repeat 1 days 24:00\n}',
        TdfErrorKind.invalidTime,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Quoted forever"\n  created 2026-11-01\n  suspended "forever"\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Year 0000"\n  created 0000-01-01\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Year 10000"\n  created 10000-01-01\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "1900 non-leap"\n  created 1900-02-29\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 3,
      );
      expectTdfError(
        'deleted {\n  generation 01\n}',
        TdfErrorKind.invalidNumber,
        expectedLine: 2,
      );
      expectTdfError(
        'deleted {\n  generation -1\n}',
        TdfErrorKind.invalidNumber,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad completions"\n  created 2026-11-01\n  completions 01\n}',
        TdfErrorKind.invalidNumber,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad blocked count"\n  created 2026-11-01\n  blocked 000002OkD2:0\n}',
        TdfErrorKind.invalidNumber,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Unknown label"\n  created 2026-11-01\n  labels missinOkD2\n}',
        TdfErrorKind.unknownLabelReference,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Self blocked"\n  created 2026-11-01\n  blocked 000001OkD2:2\n}',
        TdfErrorKind.circularDependency,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad step bool"\n  created 2026-11-01\n  subtasks {\n    step yes "Sub"\n  }\n}',
        TdfErrorKind.invalidBoolean,
        expectedLine: 5,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Work"\n  color 4CAF50\n}',
        TdfErrorKind.invalidColor,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad day"\n  created 2026-11-01\n  condition day funday\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "   "\n  created 2026-11-01\n}',
        TdfErrorKind.emptyText,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Link missing scheme"\n  created 2026-11-01\n  link "Docs" "www.example.com"\n}',
        TdfErrorKind.invalidUri,
        expectedLine: 4,
      );
    });

    test('enforces Section 7 and Section 7.2 bounds including 512 condition rules across blocks, Unicode scalar text limits, calendar endpoints, and canonical output bounds', () {
      // Calendar endpoints and 2000-02-29:
      const endpointDoc = '''
tdf 0.5.0

task 000001OkD2 {
    name     "Calendar Endpoints"
    created  0001-01-01 00:00:00
    modified 9999-12-31 23:59:59
    suspended 2000-02-29 12:00:00
}
''';
      final endpointBoard = tdfService.parse(
        endpointDoc,
        evaluationTime: fixedDate,
      );
      expect(
        endpointBoard.findTask('000001OkD2')!.createdAt,
        equals(DateTime.utc(1, 1, 1, 0, 0, 0)),
      );
      expect(
        endpointBoard.findTask('000001OkD2')!.modifiedAt,
        equals(DateTime.utc(9999, 12, 31, 23, 59, 59)),
      );

      // 512 condition rules across two condition blocks -> accepted:
      final block300 = List.filled(300, '    day mon').join('\n');
      final block212 = List.filled(212, '    time 09:00 17:00').join('\n');
      final valid512ConditionsDoc =
          'tdf 0.5.0\n'
          'label 000001OkD2 {\n'
          '  name "512 Conditions"\n'
          '  condition {\n$block300\n  }\n'
          '  condition {\n$block212\n  }\n'
          '}\n';
      final parsed512 = tdfService.parse(valid512ConditionsDoc);
      expect(parsed512.labels.single.conditions.length, equals(512));

      // Two condition blocks with 300 rules each -> rejected at rule 513 with LimitExceeded:
      final invalid600ConditionsDoc =
          'tdf 0.5.0\n'
          'label 000001OkD2 {\n'
          '  name "600 Conditions"\n'
          '  condition {\n$block300\n  }\n'
          '  condition {\n$block300\n  }\n'
          '}\n';
      expect(
        () => tdfService.parse(invalid600ConditionsDoc),
        throwsA(
          isA<TdfException>()
              .having((error) => error.kind, 'kind', TdfErrorKind.limitExceeded)
              .having((error) => error.line, 'line', 519),
        ),
        reason: 'Two condition blocks of 300 rules each must fail at rule 513 (line 519) with LimitExceeded',
      );

      // Unicode scalar value limits: 500 supplementary characters above U+FFFF accepted, 501 rejected:
      final rocket500 = '🚀' * 500;
      final rocket501 = '🚀' * 501;
      expect(
        tdfService
            .parse(
              'tdf 0.5.0\ntask 000001OkD2 {\n  name "$rocket500"\n  created 2026-11-01\n}\n',
            )
            .someday
            .single
            .title,
        equals(rocket500),
        reason: '500 supplementary Unicode scalar values (1000 UTF-16 code units) must be accepted',
      );
      expect(
        () => tdfService.parse(
          'tdf 0.5.0\ntask 000001OkD2 {\n  name "$rocket501"\n  created 2026-11-01\n}\n',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );

      // 250 repetitions of U+0065 U+0301 = 500 scalar values -> accepted:
      final combining500 = 'e\u0301' * 250;
      expect(
        tdfService
            .parse(
              'tdf 0.5.0\ntask 000001OkD2 {\n  name "$combining500"\n  created 2026-11-01\n}\n',
            )
            .someday
            .single
            .title,
        equals(combining500),
      );

      // MAX_SYNC_GENERATION and MAX_COMPLETIONS bounds:
      expect(
        tdfService
            .parse(
              'tdf 0.5.0\ndeleted {\n  generation 9007199254740991\n}\ntask 000001OkD2 {\n  name "Max"\n  created 2026-11-01\n  completions 9007199254740991\n  blocked 000002OkD2:9007199254740991\n}\n',
            )
            .deletedBlock
            .generation,
        equals(9007199254740991),
      );
      expect(
        () => tdfService.parse(
          'tdf 0.5.0\ndeleted {\n  generation 9007199254740992\n}\n',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );
      expect(
        () => tdfService.parse(
          'tdf 0.5.0\ntask 000001OkD2 {\n  name "Overflow"\n  created 2026-11-01\n  completions 9007199254740992\n}\n',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );

      // Canonical output exceeding MAX_LINE_COUNT -> LimitExceeded on serialize:
      final manyTasks = List.generate(
        3500,
        (index) => TaskItem(
          id: '${index.toString().padLeft(6, '0')}OkD2',
          title: 'Task $index',
          createdAt: fixedDate,
        ),
      );
      final hugeBoard = TaskBoard(someday: manyTasks);
      expect(
        () => tdfService.serialize(hugeBoard),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Canonical output exceeding MAX_LINE_COUNT (16384) must fail with LimitExceeded per Section 7.1',
      );
    });
  });
}
