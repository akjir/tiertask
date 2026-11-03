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
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('TDF Section 7 Resource Bounds & Section 8 Error Conditions', () {
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
          reason: 'Input must fail with $expectedKind',
        );
      }

      void expectTdfError(
        String bodyWithoutHeader,
        TdfErrorKind expectedKind, {
        int? expectedLine,
      }) {
        expectRawTdfError(
          'tdf 0.4.0\n$bodyWithoutHeader',
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
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n}',
        TdfErrorKind.missingVersionHeader,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf 0.1.0\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf "0.4.0"\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf 0.4.0 extra\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );

      expectTdfError(
        'tdf 0.4.0',
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
        '123task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 1,
      );
      expectTdfError(
        'task 000001OkD2 {\n  -bad "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2{\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 1,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  subtasks{\n  }\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 4,
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
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  subtasks {}\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
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
        '# comment with control char \x7F\n',
        TdfErrorKind.unexpectedToken,
        expectedLine: 1,
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
        "task 000001OkD2 {\n  name 'Unterminated\n  created 2026-11-01\n}",
        TdfErrorKind.unterminatedString,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name foo"bar"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "foo"bar\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
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
        'label 000001OkD2 {\n  name "L1"\n  subtasks {\n    step false "Bad"\n  }\n}',
        TdfErrorKind.unknownBlockType,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  unknown_dir 123\n}',
        TdfErrorKind.unknownDirective,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Missing created"\n}',
        TdfErrorKind.missingRequiredDirective,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Empty subtasks"\n  created 2026-11-01\n  subtasks {\n  }\n}',
        TdfErrorKind.missingRequiredDirective,
        expectedLine: 5,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Empty condition block"\n  condition {\n  }\n}',
        TdfErrorKind.missingRequiredDirective,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "First"\n  name "Second"\n  created 2026-11-01\n}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 3,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Dup condition blocks"\n  condition {\n    day mon\n  }\n  condition {\n    time 09:00 17:00\n  }\n}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 6,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "First"\n  created 2026-11-01\n}\ntask 000001OkD2 {\n  name "Dup"\n  created 2026-11-01\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 5,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "First"\n}\nlabel 000001OkD2 {\n  name "Dup"\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Unknown label"\n  created 2026-11-01\n  labels missinOkD2\n}',
        TdfErrorKind.unknownLabelReference,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Self blocked"\n  created 2026-11-01\n  blocked 000001OkD2\n}',
        TdfErrorKind.circularDependency,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Cycle A"\n  created 2026-11-01\n  blocked 000002OkD2\n}\n'
        'task 000002OkD2 {\n  name "Cycle B"\n  created 2026-11-01\n  blocked 000001OkD2\n}',
        TdfErrorKind.circularDependency,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad leap day"\n  created 2026-02-29\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad time"\n  created 2026-11-01 25:00\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad seconds"\n  created 2026-11-01 12:00:60\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad step bool"\n  created 2026-11-01\n  subtasks {\n    step yes "Sub"\n  }\n}',
        TdfErrorKind.invalidBoolean,
        expectedLine: 5,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Work"\n  condition location not_a_number 11.0 150\n}',
        TdfErrorKind.invalidNumber,
        expectedLine: 3,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Work"\n  color 4CAF50\n}',
        TdfErrorKind.invalidColor,
        expectedLine: 3,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Work"\n  color "#GGGGGG"\n}',
        TdfErrorKind.invalidColor,
        expectedLine: 3,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Work"\n  color "#12345"\n}',
        TdfErrorKind.invalidColor,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad day"\n  created 2026-11-01\n  condition day funday\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Equal time window"\n  created 2026-11-01\n  condition time 09:00 09:00\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 4,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Bad lat"\n  condition location 95.0 11.0 150\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Bad lon"\n  condition location 50.0 -185.0 150\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Bad radius"\n  condition location 50.0 11.0 0\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Label reset forbidden"\n  condition any\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Label group reset forbidden"\n  condition day any\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Global reset mixed"\n  created 2026-11-01\n  condition any\n  condition day mon\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 5,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Group reset mixed"\n  created 2026-11-01\n  condition day any\n  condition day mon\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 5,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Duplicate repeat"\n  created 2026-11-01\n  repeat 1 days\n  repeat 2 weeks\n}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 5,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Repeat missing unit"\n  created 2026-11-01\n  repeat 1\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Repeat extra arg"\n  created 2026-11-01\n  repeat 1 days extra\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Repeat unknown unit"\n  created 2026-11-01\n  repeat 1 years\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Repeat zero count"\n  created 2026-11-01\n  repeat 0 days\n}',
        TdfErrorKind.invalidNumber,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Repeat negative count"\n  created 2026-11-01\n  repeat -3 weeks\n}',
        TdfErrorKind.invalidNumber,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Repeat non-integer count"\n  created 2026-11-01\n  repeat abc months\n}',
        TdfErrorKind.invalidNumber,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Repeat exceeds maxRepeatCount"\n  created 2026-11-01\n  repeat 3651 days\n}',
        TdfErrorKind.limitExceeded,
        expectedLine: 4,
      );
    });

    test('enforces all Section 7 resource bounds before allocation', () {
      final overText = 'a' * (TdfService.maxTextLength + 1);
      expect(
        () => tdfService.parse(
          'tdf 0.4.0\ntask 000001OkD2 {\n  name "$overText"\n  created 2026-11-01\n}',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'name exceeding MAX_TEXT_LENGTH (500) must throw LimitExceeded',
      );

      final overNote = 'n' * (TdfService.maxNoteLength + 1);
      expect(
        () => tdfService.parse(
          'tdf 0.4.0\ntask 000001OkD2 {\n  name "Valid"\n  note "$overNote"\n  created 2026-11-01\n}',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason:
            'note exceeding MAX_NOTE_LENGTH (2000) must throw LimitExceeded',
      );

      final tooManyArgs = List.generate(
        TdfService.maxArgsPerStmt + 1,
        (index) => '${index.toString().padLeft(6, '0')}OkD2',
      ).join(' ');
      expect(
        () => tdfService.parse(
          'tdf 0.4.0\ntask 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  labels $tooManyArgs\n}',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Directive exceeding MAX_ARGS_PER_STMT (64) must throw LimitExceeded',
      );

      expect(
        () => tdfService.parse(
          'tdf 0.4.0\ntask 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  subtasks {\n    nested {\n    }\n  }\n}',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Block nesting exceeding MAX_NESTING_DEPTH (2) must throw LimitExceeded',
      );

      final tooManyStmtsBuffer = StringBuffer(
        'tdf 0.4.0\ntask 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  subtasks {\n',
      );
      for (var i = 0; i <= TdfService.maxStmtsPerBlock; i++) {
        tooManyStmtsBuffer.writeln('    step false "Step $i"');
      }
      tooManyStmtsBuffer.writeln('  }\n}');
      expect(
        () => tdfService.parse(tooManyStmtsBuffer.toString()),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Block exceeding MAX_STMTS_PER_BLOCK (512) must throw LimitExceeded',
      );

      final tooManyLines = List.filled(
        TdfService.maxLineCount + 1,
        '# comment',
      ).join('\n');
      expect(
        () => tdfService.parse(tooManyLines),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Document exceeding MAX_LINE_COUNT (16384) must throw LimitExceeded',
      );

      final tooManyBytes = '# ${'x' * TdfService.maxFileBytes}';
      expect(
        () => tdfService.parse(tooManyBytes),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Document exceeding MAX_FILE_BYTES (1 MiB) must throw LimitExceeded',
      );
    });
  });
}
