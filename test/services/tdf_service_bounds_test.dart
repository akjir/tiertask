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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/services/tdf_parser.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

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
      'tdf 0.8.0\n$bodyWithoutHeader',
      expectedKind,
      expectedLine: expectedLine == null ? null : expectedLine + 1,
    );
  }

  group('TDF 0.8.0 Error Precedence & All 22 Resource Bounds', () {
    test('rejects all 30 mandatory lexical, structural, and semantic TdfErrorKind categories with deterministic line numbers (TDF-VAL-001, TDF-ERR-001)', () {
      // Initial root statement & version header framing:
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
        '}',
        TdfErrorKind.unexpectedClosingBrace,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf{\n',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf { extra\n',
        TdfErrorKind.unexpectedToken,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf 0.7.0\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf "0.8.0"\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf 0.8.0 extra\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );

      // Root directives & braces:
      expectTdfError(
        'tdf 0.8.0',
        TdfErrorKind.unexpectedRootDirective,
        expectedLine: 1,
      );
      expectTdfError(
        'tdf',
        TdfErrorKind.unexpectedRootDirective,
        expectedLine: 1,
      );
      expectTdfError(
        'history 2026-11-01 "Root history"',
        TdfErrorKind.unexpectedRootDirective,
        expectedLine: 1,
      );
      expectTdfError('}', TdfErrorKind.unexpectedClosingBrace, expectedLine: 1);
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01',
        TdfErrorKind.unclosedBlock,
        expectedLine: 3,
      );

      // Identifier syntax (quoted and invalid start/continue chars):
      expectTdfError(
        '"task" 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 1,
      );
      expectTdfError(
        '123task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 1,
      );
      expectTdfError(
        'task 000001OkD2 {\n  "name" "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  -bad "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  bad.dir "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 2,
      );
      expectTdfError(
        'task short {\n  name "Bad ID"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 1,
      );
      expectTdfError(
        'label "4x9p2mOkD2" {\n  name "Quoted ID"\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 1,
      );
      expectTdfError(
        'location bad_id_123 {\n  name "Bad Loc ID"\n  coordinates 0 0\n  radius 10\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 1,
      );

      // Block headers & lexical tokens:
      expectTdfError('{\n}', TdfErrorKind.invalidBlockHeader, expectedLine: 1);
      expectTdfError(
        'task 000001OkD2{\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 1,
      );
      expectTdfError(
        'label "4x9p2mOkD2"{\n  name "Test"\n}',
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
        'task 000001OkD2 urgent {\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 1,
      );
      expectTdfError(
        'label 000001OkD2 "scoped" {\n  name "Test"\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 1,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  subtasks urgent {\n    step false "S"\n  }\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  condition extra {\n    day mon\n  }\n}',
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
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n} trailing',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "foo"bar\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name foo"bar"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Line1\\nLine2"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "\\n"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 2,
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
        'task 000001OkD2 {\r  name "Standalone CR"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 1,
      );
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
        'task 000001OkD2 {\n  name "Bad \\x escape"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidEscapeSequence,
        expectedLine: 2,
      );

      // Unknown blocks & directives at depth 0 and depth 1:
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
        'location 000001OkD2 {\n  name "Loc"\n  coordinates 0 0\n  radius 10\n  condition {\n    day mon\n  }\n}',
        TdfErrorKind.unknownBlockType,
        expectedLine: 5,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  due {\n  }\n}',
        TdfErrorKind.unknownBlockType,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  queued 2026-11-01 08:00\n}',
        TdfErrorKind.unknownDirective,
        expectedLine: 4,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "Lbl"\n  history 2026-11-01 "Forbidden in label"\n}',
        TdfErrorKind.unknownDirective,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Test"\n  created 2026-11-01\n  modified\n}',
        TdfErrorKind.missingDirectiveArgument,
        expectedLine: 4,
      );

      // Required directives, duplicates, references, completion state, cycles:
      expectTdfError(
        'task 000001OkD2 {\n  name "Missing created"\n}',
        TdfErrorKind.missingRequiredDirective,
      );
      expectTdfError(
        'location 000001OkD2 {\n  name "Missing coords and radius"\n}',
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
        'task 000001OkD2 {\n  name "Empty subtasks"\n  created 2026-11-01\n  subtasks {\n  }\n}',
        TdfErrorKind.missingRequiredDirective,
        expectedLine: 5,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Empty condition"\n  created 2026-11-01\n  condition {\n  }\n}',
        TdfErrorKind.missingRequiredDirective,
        expectedLine: 5,
      );
      expectTdfError(
        'deleted {\n  generation 0\n}\ndeleted {\n  generation 1\n}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Dup subtasks"\n  created 2026-11-01\n  subtasks {\n    step false "One"\n  }\n  subtasks {\n    step false "Two"\n  }\n}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 7,
      );
      expectTdfError(
        'deleted {\n  generation 0\n  task 000001OkD2 2026-11-01\n}\ntask 000001OkD2 {\n  name "Live and Deleted"\n  created 2026-11-01\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 5,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Live First"\n  created 2026-11-01\n}\ndeleted {\n  generation 0\n  task 000001OkD2 2026-11-01\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 7,
      );
      expectTdfError(
        'queue {\n  modified 2026-11-01 00:00:00\n  task 000001OkD2\n  task 000001OkD2\n}\ntask 000001OkD2 {\n  name "Dup queue"\n  created 2026-11-01\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 4,
      );
      expectTdfError(
        'queue {\n  modified 2026-11-01 00:00:00\n  task 999999OkD2\n}',
        TdfErrorKind.invalidQueueMembership,
        expectedLine: 3,
      );
      expectTdfError(
        'queue {\n  modified 2026-11-01 00:00:00\n  task 000001OkD2\n}\ntask 000001OkD2 {\n  name "Completed in queue"\n  created 2026-11-01\n  finished 2026-11-01 10:00\n  completions 1\n}',
        TdfErrorKind.invalidQueueMembership,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Finished without completions"\n  created 2026-11-01\n  finished 2026-11-01 10:00\n}',
        TdfErrorKind.invalidCompletionState,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Unknown label"\n  created 2026-11-01\n  labels missinOkD2\n}',
        TdfErrorKind.unknownLabelReference,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Unknown loc"\n  created 2026-11-01\n  condition location missinOkD2\n}',
        TdfErrorKind.unknownLocationReference,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "T1"\n  created 2026-11-01\n  blocked 000002OkD2\n}\n'
        'task 000002OkD2 {\n  name "T2"\n  created 2026-11-01\n  blocked 000003OkD2\n}\n'
        'task 000003OkD2 {\n  name "T3"\n  created 2026-11-01\n  blocked 000001OkD2\n}',
        TdfErrorKind.circularDependency,
        expectedLine: 4,
      );

      // Primitive errors:
      expectTdfError(
        'task 000001OkD2 {\n  name "   "\n  created 2026-11-01\n}',
        TdfErrorKind.emptyText,
        expectedLine: 2,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad URI"\n  created 2026-11-01\n  link "XSS" "javascript:alert(1)"\n}',
        TdfErrorKind.invalidUri,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Bad URI"\n  created 2026-11-01\n  link "Tab" "https://example.com/\\tpath"\n}',
        TdfErrorKind.invalidUri,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "1900 non-leap"\n  created 1900-02-29\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 3,
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
        'task 000001OkD2 {\n  name "Quoted repeat clock"\n  created 2026-11-01\n  repeat 1 days "09:00"\n}',
        TdfErrorKind.invalidTime,
        expectedLine: 4,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "Repeat lead weeks"\n  created 2026-11-01\n  repeat 1 months lead 2 weeks\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
      );
      expectTdfError(
        'deleted {\n  generation 0\n  label 000001OkD2 2026-11-01 3\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 3,
      );
      expectTdfError(
        'deleted {\n  generation 0\n  location 000001OkD2 2026-11-01 3\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 3,
      );
    });

    test('enforces exact depth-2 condition { ... } 4-way disambiguation and inline condition rules (TDF-DIR-009, TDF-VAL-001)', () {
      // 1. Attached '{' at depth 2 -> InvalidBlockHeader BEFORE MAX_NESTING_DEPTH LimitExceeded:
      expectTdfError(
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  condition {\n    day{\n  }\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 5,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  subtasks {\n    condition{\n  }\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 5,
      );

      // 2. Malformed/quoted directive identifier at depth 2 -> InvalidIdentifier;
      // nested block header with invalid identifier at depth 2 -> LimitExceeded (MAX_NESTING_DEPTH checked before InvalidIdentifier):
      expectTdfError(
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  condition {\n    "day" mon\n  }\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 5,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  condition {\n    123bad {\n    }\n  }\n}',
        TdfErrorKind.limitExceeded,
        expectedLine: 5,
      );

      // 3. Separated nested '{' at depth 2 -> LimitExceeded (MAX_NESTING_DEPTH = 2):
      for (final innerBlock in <String>['day', 'condition', 'step', 'foo']) {
        expectTdfError(
          'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  condition {\n    $innerBlock {\n    }\n  }\n}',
          TdfErrorKind.limitExceeded,
          expectedLine: 5,
        );
        expectTdfError(
          'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  subtasks {\n    $innerBlock {\n    }\n  }\n}',
          TdfErrorKind.limitExceeded,
          expectedLine: 5,
        );
      }

      // 4. Zero-arg identifier without '{' at depth 2 -> MissingDirectiveArgument:
      for (final bareId in <String>[
        'any',
        'day',
        'time',
        'location',
        'condition',
        'foo',
      ]) {
        expectTdfError(
          'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  condition {\n    $bareId\n  }\n}',
          TdfErrorKind.missingDirectiveArgument,
          expectedLine: 5,
        );
        expectTdfError(
          'label 000001OkD2 {\n  name "L"\n  condition {\n    $bareId\n  }\n}',
          TdfErrorKind.missingDirectiveArgument,
          expectedLine: 4,
        );
      }

      // 5. Identifier outside {day, time, location, any} at depth 2 -> UnknownDirective on BOTH task and label:
      for (final badStmt in <String>[
        'condition any',
        'condition day mon',
        'foo bar',
        'step false "S"',
      ]) {
        expectTdfError(
          'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  condition {\n    $badStmt\n  }\n}',
          TdfErrorKind.unknownDirective,
          expectedLine: 5,
        );
        expectTdfError(
          'label 000001OkD2 {\n  name "L"\n  condition {\n    $badStmt\n  }\n}',
          TdfErrorKind.unknownDirective,
          expectedLine: 4,
        );
      }

      // UnknownDirective at depth 2 still wins even after 512 rules or after condition any:
      final rules512 = List<String>.filled(512, '    day mon').join('\n');
      expectTdfError(
        'label 000001OkD2 {\n  name "L"\n  condition {\n$rules512\n    condition any\n  }\n}',
        TdfErrorKind.unknownDirective,
        expectedLine: 516,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  condition any\n  condition {\n    condition day mon\n  }\n}',
        TdfErrorKind.unknownDirective,
        expectedLine: 6,
      );

      // 6. 'any <args...>' at depth 2 -> InvalidCondition:
      for (final anyWithArgs in <String>['any mon', 'any any']) {
        expectTdfError(
          'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  condition {\n    $anyWithArgs\n  }\n}',
          TdfErrorKind.invalidCondition,
          expectedLine: 5,
        );
        expectTdfError(
          'label 000001OkD2 {\n  name "L"\n  condition {\n    $anyWithArgs\n  }\n}',
          TdfErrorKind.invalidCondition,
          expectedLine: 4,
        );
      }

      // 7. Inline condition semantic validation -> InvalidCondition:
      for (final badInline in <String>[
        'condition bogus',
        'condition "day" mon',
        'condition day',
        'condition time',
        'condition time 08:00',
        'condition time "08:00" 18:00',
        'condition time 25:00 18:00',
        'condition time 09:00 09:00',
        'condition location',
        'condition any extra',
      ]) {
        expectTdfError(
          'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  $badInline\n}',
          TdfErrorKind.invalidCondition,
          expectedLine: 4,
        );
      }
      expectTdfError(
        'label 000001OkD2 {\n  name "L"\n  condition any\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'label 000001OkD2 {\n  name "L"\n  condition day any\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  condition day any\n  condition day any\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 5,
      );
    });

    test('enforces exact due right-to-left modifier peeling error precedence (TDF-DIR-004)', () {
      final loneHighSurrogate = String.fromCharCode(0xD800);
      final invalidDueLines = <({String lineText, TdfErrorKind kind})>[
        (lineText: 'due', kind: TdfErrorKind.missingDirectiveArgument),
        (lineText: 'due "2026-11-11"', kind: TdfErrorKind.invalidTimestamp),
        (
          lineText: 'due 2026-11-11 "note" passive',
          kind: TdfErrorKind.unexpectedToken,
        ),
        (
          lineText: 'due 2026-11-11 anchor "2026-11-11" passive',
          kind: TdfErrorKind.unexpectedToken,
        ),
        (
          lineText: 'due 2026-11-11 anchor "2026-11-11"',
          kind: TdfErrorKind.invalidTimestamp,
        ),
        (
          lineText: 'due 2026-11-11 17:00 anchor "2026-11-11"',
          kind: TdfErrorKind.invalidTimestamp,
        ),
        (
          lineText: 'due 2026-11-11 passive passive',
          kind: TdfErrorKind.unexpectedToken,
        ),
        (
          lineText: 'due 2026-11-11 passive anchor 2026-11-11',
          kind: TdfErrorKind.unexpectedToken,
        ),
        (
          lineText: 'due 2026-11-11 anchor 2026-11-11 anchor 2026-11-12',
          kind: TdfErrorKind.unexpectedToken,
        ),
        (lineText: 'due 2026-11-11 anchor', kind: TdfErrorKind.unexpectedToken),
        (
          lineText: 'due 2026-11-11 17:00 extra anchor 2026-11-11',
          kind: TdfErrorKind.unexpectedToken,
        ),
        (
          lineText: 'due 2026-11-11 anchor 2026-11-11 18:00 extra',
          kind: TdfErrorKind.unexpectedToken,
        ),
        (
          lineText: 'due 2026-11-11 17:00 extra',
          kind: TdfErrorKind.unexpectedToken,
        ),
        (
          lineText: 'due 2026-02-29 anchor 2026-03-01',
          kind: TdfErrorKind.invalidTimestamp,
        ),
        (
          lineText: 'due 2026-02-28 anchor 1900-02-29',
          kind: TdfErrorKind.invalidTimestamp,
        ),
        (
          lineText: 'due 2026-02-28 anchor 0000-01-01',
          kind: TdfErrorKind.invalidTimestamp,
        ),
        (
          lineText: 'due 2026-02-28 anchor 10000-01-01',
          kind: TdfErrorKind.invalidTimestamp,
        ),
        (
          lineText: 'due 2026-11-11 "$loneHighSurrogate"',
          kind: TdfErrorKind.unexpectedToken,
        ),
        (
          lineText: 'due 2026-11-11 "   \\t\\n  "',
          kind: TdfErrorKind.emptyText,
        ),
        (
          lineText: 'due 2026-11-11 "${'a' * 2001}"',
          kind: TdfErrorKind.limitExceeded,
        ),
      ];

      for (final item in invalidDueLines) {
        expectTdfError(
          'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  ${item.lineText}\n}',
          item.kind,
          expectedLine: 4,
        );
      }
    });

    test('enforces all 22 normative MAX_* bounds at exact N (accept) and N + 1 (LimitExceeded) across parse and serialize (TDF-VAL-002)', () {
      // Standalone TdfSubtasksBuilder closure guard:
      final state = TdfParserState();
      final subtasksBuilder = TdfSubtasksBuilder(true)
        ..steps.add(const SubtaskItem(title: 'Step 1', isCompleted: false));
      state.blockStack.add(subtasksBuilder);
      expect(() => TdfBlockParser.closeCurrentBlock(state, 1), returnsNormally);
      expect(state.blockStack, isEmpty);

      // 1. MAX_FILE_BYTES (1_048_576):
      const headerPrefix = 'tdf 0.8.0\n#';
      final exactMaxBytesDoc =
          '$headerPrefix${'a' * (maxTdfFileBytes - headerPrefix.length)}';
      expect(utf8.encode(exactMaxBytesDoc).length, equals(maxTdfFileBytes));
      expect(tdfService.parse(exactMaxBytesDoc).allTasks, isEmpty);
      expectRawTdfError('${exactMaxBytesDoc}a', TdfErrorKind.limitExceeded);

      // Multi-byte UTF-8 boundary where string.length < maxTdfFileBytes < utf8.length:
      const multiByteUnit = '\u{00E9}';
      const multiByteCount = (maxTdfFileBytes ~/ 2) + 10;
      final multiByteOverDoc = '$headerPrefix${multiByteUnit * multiByteCount}';
      expect(multiByteOverDoc.length, lessThan(maxTdfFileBytes));
      expect(
        utf8.encode(multiByteOverDoc).length,
        greaterThan(maxTdfFileBytes),
      );
      expectRawTdfError(multiByteOverDoc, TdfErrorKind.limitExceeded);

      // 2. MAX_LINE_COUNT (16_384):
      final exact16384Lines = 'tdf 0.8.0\n${'\n' * 16383}';
      expect(tdfService.parse(exact16384Lines).allTasks, isEmpty);
      expectRawTdfError(
        'tdf 0.8.0\n${'\n' * 16384}',
        TdfErrorKind.limitExceeded,
        expectedLine: 16385,
      );

      // 3. MAX_NESTING_DEPTH (2): tested in condition/subtasks above (2 accepted, 3 rejected).

      // 4. MAX_BLOCKS_PER_DOC (4_096):
      final blocks4096 = List<String>.generate(
        4096,
        (i) => 'label ${i.toString().padLeft(6, '0')}OkD2 {\n  name "L"\n}',
      ).join('\n');
      expect(
        tdfService.parse('tdf 0.8.0\n$blocks4096\n').labels.length,
        equals(4096),
      );
      expectRawTdfError(
        'tdf 0.8.0\n$blocks4096\nlabel extra0OkD2 {\n  name "Extra"\n}\n',
        TdfErrorKind.limitExceeded,
      );

      // Serializer MAX_BLOCKS_PER_DOC (4_096 vs 4_097):
      final labels2048WithCondBlock = List<TdfLabel>.generate(
        2048,
        (i) => TdfLabel(
          id: '${i.toString().padLeft(6, '0')}OkD2',
          name: 'L',
          conditions: <TaskCondition>[
            DayTaskCondition.fromWeekdays(const <int>[1]),
            const TimeWindowTaskCondition(
              startMinutes: 480,
              endMinutes: 720,
              startToken: '08:00',
              endToken: '12:00',
            ),
          ],
        ),
      );
      expect(
        () => tdfService.serialize(
          TaskBoard(
            labels: labels2048WithCondBlock,
            deletedBlock: TdfDeletedBlock(generation: 1),
          ),
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: '2048 labels * 2 blocks + 1 deleted block = 4097 blocks must fail on serialize with LimitExceeded',
      );

      // 5. MAX_LOCATIONS (200):
      final locations200 = List<String>.generate(
        200,
        (i) =>
            'location ${i.toString().padLeft(6, '0')}OkD2 {\n  name "Loc"\n  coordinates 0 0\n  radius 10\n}',
      ).join('\n');
      final board200Locs = tdfService.parse('tdf 0.8.0\n$locations200\n');
      expect(board200Locs.locations.length, equals(200));
      expect(tdfService.serialize(board200Locs), isNotEmpty);
      expectRawTdfError(
        'tdf 0.8.0\n$locations200\nlocation extra0OkD2 {\n  name "Loc"\n  coordinates 0 0\n  radius 10\n}\n',
        TdfErrorKind.limitExceeded,
      );

      // 6. MAX_STMTS_PER_BLOCK (1_024) & Full-Capacity Canonical Task (534 <= 1_024):
      final steps1024 = List<String>.filled(
        1024,
        '    step false "Step"',
      ).join('\n');
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\ntask 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  subtasks {\n$steps1024\n  }\n}\n',
            )
            .someday
            .single
            .subtasks
            .length,
        equals(1024),
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  subtasks {\n$steps1024\n    step false "1025"\n  }\n}\n',
        TdfErrorKind.limitExceeded,
      );

      // 7. MAX_CONDITION_RULES_PER_ENTITY (512):
      final block300 = List<String>.filled(300, '    day mon').join('\n');
      final block212 = List<String>.filled(
        212,
        '    time 09:00 17:00',
      ).join('\n');
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\nlabel 000001OkD2 {\n  name "512"\n  condition {\n$block300\n  }\n  condition {\n$block212\n  }\n}\n',
            )
            .labels
            .single
            .conditions
            .length,
        equals(512),
      );
      expectRawTdfError(
        'tdf 0.8.0\nlabel 000001OkD2 {\n  name "600"\n  condition {\n$block300\n  }\n  condition {\n$block300\n  }\n}\n',
        TdfErrorKind.limitExceeded,
        expectedLine: 519,
      );

      // 8. MAX_LOCATION_REFS_PER_ENTITY (63 counted before deduplication):
      final locRefs63 = List<String>.filled(63, '7pQr9mOkD2').join(' ');
      final locRefs64 = List<String>.filled(64, '7pQr9mOkD2').join(' ');
      const locDef =
          'location 7pQr9mOkD2 {\n  name "Home"\n  coordinates 0 0\n  radius 10\n}\n';
      final parsed63LocRefs = tdfService.parse(
        'tdf 0.8.0\n$locDef\nlabel 000001OkD2 {\n  name "L"\n  condition location $locRefs63\n}\n',
      );
      expect(
        (parsed63LocRefs.labels.single.conditions.single
                as LocationTaskCondition)
            .locationIds,
        equals(<String>['7pQr9mOkD2']),
      );
      expectRawTdfError(
        'tdf 0.8.0\n$locDef\nlabel 000001OkD2 {\n  name "L"\n  condition {\n    location $locRefs64\n  }\n}\n',
        TdfErrorKind.limitExceeded,
      );

      // 9. MAX_QUEUE_ENTRIES (4_096) & 10. MAX_DELETED_RECORDS (4_096):
      final queueTasks3200 = List<String>.generate(
        3200,
        (i) => '  task ${i.toString().padLeft(6, '0')}OkD2',
      ).join('\n');
      final taskBlocks3200 = List<String>.generate(
        3200,
        (i) =>
            'task ${i.toString().padLeft(6, '0')}OkD2 {\n  name "T"\n  created 2026-11-01\n}',
      ).join('\n');
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\nqueue {\n  modified 2026-11-01 00:00:00\n$queueTasks3200\n}\n$taskBlocks3200\n',
            )
            .queueTaskIds
            .length,
        equals(3200),
        reason: 'Queue block permits > 1024 entries without hitting MAX_STMTS_PER_BLOCK',
      );
      final queueTasks4096 = List<String>.generate(
        4096,
        (i) => '  task ${i.toString().padLeft(6, '0')}OkD2',
      ).join('\n');
      expectRawTdfError(
        'tdf 0.8.0\nqueue {\n  modified 2026-11-01 00:00:00\n$queueTasks4096\n}\n',
        TdfErrorKind.invalidQueueMembership,
        expectedLine: 4,
      );
      final queueTasks4097 = List<String>.generate(
        4097,
        (i) => '  task ${i.toString().padLeft(6, '0')}OkD2',
      ).join('\n');
      expectRawTdfError(
        'tdf 0.8.0\nqueue {\n  modified 2026-11-01 00:00:00\n$queueTasks4097\n}\n',
        TdfErrorKind.limitExceeded,
        expectedLine: 4100,
      );

      final deleted4096 = List<String>.generate(
        4096,
        (i) => '  task ${i.toString().padLeft(6, '0')}OkD2 2026-11-01',
      ).join('\n');
      final parsedDeleted4096 = tdfService.parse(
        'tdf 0.8.0\ndeleted {\n  generation 1\n$deleted4096\n}\n',
      );
      expect(parsedDeleted4096.deletedBlock.tasks.length, equals(4096));
      expectRawTdfError(
        'tdf 0.8.0\ndeleted {\n  generation 1\n$deleted4096\n  label extra0OkD2 2026-11-01\n}\n',
        TdfErrorKind.limitExceeded,
      );

      // 11. MAX_SYNC_GENERATION & 12. MAX_COMPLETIONS (9_007_199_254_740_991):
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\ndeleted {\n  generation 9007199254740991\n  task 999999OkD2 2026-11-01 9007199254740991\n}\n'
              'task 000001OkD2 {\n  name "Max"\n  created 2026-11-01\n  completions 9007199254740991\n  blocked 000002OkD2:9007199254740991\n}\n',
            )
            .deletedBlock
            .generation,
        equals(9007199254740991),
      );
      expectRawTdfError(
        'tdf 0.8.0\ndeleted {\n  generation 9007199254740992\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "Overflow"\n  created 2026-11-01\n  completions 9007199254740992\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "Overflow"\n  created 2026-11-01\n  blocked 000002OkD2:9007199254740992\n}\n',
        TdfErrorKind.limitExceeded,
      );

      // 13. MAX_ARGS_PER_STMT (64):
      final days64 = List<String>.filled(64, 'mon').join(' ');
      final days65 = List<String>.filled(65, 'mon').join(' ');
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\nlabel 000001OkD2 {\n  name "L"\n  condition {\n    day $days64\n  }\n}\n',
            )
            .labels
            .length,
        equals(1),
      );
      expectRawTdfError(
        'tdf 0.8.0\nlabel 000001OkD2 {\n  name "L"\n  condition {\n    day $days65\n  }\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expectRawTdfError(
        'tdf 0.8.0\nlabel $days65 {\n  name "L"\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expect(
        () => tdfService.serialize(
          TaskBoard(
            someday: <TaskItem>[
              TaskItem(
                id: '000001OkD2',
                title: '65 Labels',
                createdAt: fixedDate,
                labelIds: List<String>.generate(
                  65,
                  (i) => '${i.toString().padLeft(6, '0')}OkD2',
                ),
              ),
            ],
          ),
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );

      // 14. MAX_TEXT_LENGTH (500), 15. MAX_NOTE_LENGTH (2_000), 16. MAX_URI_LENGTH (2_048):
      final supplementary500 = '\u{1F680}' * 500;
      final supplementary501 = '\u{1F680}' * 501;
      final combining500 = 'e\u0301' * 250;
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\ntask 000001OkD2 {\n  name "$supplementary500"\n  created 2026-11-01\n}\n',
            )
            .someday
            .single
            .title,
        equals(supplementary500),
      );
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\ntask 000001OkD2 {\n  name "$combining500"\n  created 2026-11-01\n}\n',
            )
            .someday
            .single
            .title,
        equals(combining500),
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "$supplementary501"\n  created 2026-11-01\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\ntask 000001OkD2 {\n  name "N"\n  note "${'n' * 2000}"\n  created 2026-11-01\n}\n',
            )
            .someday
            .single
            .note
            ?.length,
        equals(2000),
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "N"\n  note "${'n' * 2001}"\n  created 2026-11-01\n}\n',
        TdfErrorKind.limitExceeded,
      );

      final uri2048 = 'https://${'a' * 2040}';
      expect(uri2048.length, equals(2048));
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\ntask 000001OkD2 {\n  name "U"\n  created 2026-11-01\n  link "T" "$uri2048"\n}\n',
            )
            .someday
            .single
            .links
            .single
            .uri,
        equals(uri2048),
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "U"\n  created 2026-11-01\n  link "T" "https://\t${'a' * 2048}"\n}\n',
        TdfErrorKind.limitExceeded,
      );

      // 17. MAX_LINKS_PER_TASK (20), 18. MAX_LINKS_PER_LABEL (20), 19. MAX_HISTORY_PER_TASK (500):
      final links20 = List<String>.generate(
        20,
        (i) => '  link "L$i" "https://example.com/$i"',
      ).join('\n');
      final history500Duplicates = List<String>.filled(
        500,
        '  history 2026-11-01 09:00:00 "Same entry"',
      ).join('\n');
      final fullTaskBoard = tdfService.parse(
        'tdf 0.8.0\n'
        'label 000001OkD2 {\n  name "L"\n$links20\n}\n'
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n$links20\n$history500Duplicates\n}\n',
      );
      expect(fullTaskBoard.labels.single.links.length, equals(20));
      expect(fullTaskBoard.someday.single.links.length, equals(20));
      expect(fullTaskBoard.someday.single.history.length, equals(1));

      expectRawTdfError(
        'tdf 0.8.0\nlabel 000001OkD2 {\n  name "L"\n$links20\n  link "21" "https://example.com/21"\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "T"\n  created 2026-11-01\n$links20\n  link "21" "https://example.com/21"\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "T"\n  created 2026-11-01\n$history500Duplicates\n  history 2026-11-01 09:00:00 "Same entry"\n}\n',
        TdfErrorKind.limitExceeded,
      );

      // 20. MAX_REPEAT_COUNT (3_650):
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\ntask 000001OkD2 {\n  name "R"\n  created 2026-11-01\n  repeat 3650 days 09:00 lead 3650 days\n}\n',
            )
            .someday
            .single
            .repeatRule
            ?.leadDays,
        equals(3650),
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "R"\n  created 2026-11-01\n  repeat 3651 days\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "R"\n  created 2026-11-01\n  repeat 1 months lead 3651 days\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expectRawTdfError(
        'tdf 0.8.0\ntask 000001OkD2 {\n  name "R"\n  created 2026-11-01\n  repeat 1 months lead 0 days\n}\n',
        TdfErrorKind.invalidNumber,
      );

      // 21. MAX_LOCATION_RADIUS (100_000) & 22. MAX_NUMBER_LENGTH (24):
      final num24Chars = '${'0' * 21}150';
      final num25Chars = '${'0' * 22}150';
      expect(num24Chars.length, equals(24));
      expect(num25Chars.length, equals(25));
      expect(
        tdfService
            .parse(
              'tdf 0.8.0\nlocation 000001OkD2 {\n  name "Loc"\n  coordinates 0 0\n  radius $num24Chars\n}\n'
              'location 000002OkD2 {\n  name "Max"\n  coordinates 90 -180\n  radius 100000\n}\n',
            )
            .locations
            .length,
        equals(2),
      );
      expectRawTdfError(
        'tdf 0.8.0\nlocation 000001OkD2 {\n  name "Loc"\n  coordinates 0 0\n  radius $num25Chars\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expectRawTdfError(
        'tdf 0.8.0\nlocation 000001OkD2 {\n  name "Loc"\n  coordinates 0 0\n  radius 100000.01\n}\n',
        TdfErrorKind.limitExceeded,
      );
      expectRawTdfError(
        'tdf 0.8.0\nlocation 000001OkD2 {\n  name "Loc"\n  coordinates 0 0\n  radius 10.125\n}\n',
        TdfErrorKind.invalidNumber,
      );
      expectRawTdfError(
        'tdf 0.8.0\nlocation 000001OkD2 {\n  name "Loc"\n  coordinates 50.1234567 0\n  radius 10\n}\n',
        TdfErrorKind.invalidNumber,
      );

      // Canonical output exceeding MAX_LINE_COUNT -> LimitExceeded:
      final hugeBoard = TaskBoard(
        someday: List<TaskItem>.generate(
          3500,
          (i) => TaskItem(
            id: '${i.toString().padLeft(6, '0')}OkD2',
            title: 'Task $i',
            createdAt: fixedDate,
          ),
        ),
      );
      expect(
        () => tdfService.serialize(hugeBoard),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );
    });

    test('enforces Step-4 validation precedence: UnknownLabelReference > UnknownLocationReference > InvalidQueueMembership > CircularDependency (TDF-VAL-001)', () {
      // Invalid queue membership (unknown task) beats circular dependency:
      expectTdfError(
        'queue {\n'
        '  modified 2026-11-01 00:00:00\n'
        '  task 999999OkD2\n'
        '}\n'
        'task 000001OkD2 {\n'
        '  name "T1"\n'
        '  created 2026-11-01\n'
        '  blocked 000002OkD2\n'
        '}\n'
        'task 000002OkD2 {\n'
        '  name "T2"\n'
        '  created 2026-11-01\n'
        '  blocked 000001OkD2\n'
        '}\n',
        TdfErrorKind.invalidQueueMembership,
        expectedLine: 3,
      );

      // Invalid queue membership (completed task) beats self-loop circular dependency:
      expectTdfError(
        'queue {\n'
        '  modified 2026-11-01 00:00:00\n'
        '  task 000001OkD2\n'
        '}\n'
        'task 000001OkD2 {\n'
        '  name "Done & Self-Blocked"\n'
        '  created 2026-11-01\n'
        '  finished 2026-11-01 10:00\n'
        '  completions 1\n'
        '  blocked 000001OkD2\n'
        '}\n',
        TdfErrorKind.invalidQueueMembership,
        expectedLine: 3,
      );

      // UnknownLocationReference beats InvalidQueueMembership and CircularDependency:
      expectTdfError(
        'queue {\n'
        '  modified 2026-11-01 00:00:00\n'
        '  task 999999OkD2\n'
        '}\n'
        'task 000001OkD2 {\n'
        '  name "Bad Loc"\n'
        '  created 2026-11-01\n'
        '  blocked 000001OkD2\n'
        '  condition location missinOkD2\n'
        '}\n',
        TdfErrorKind.unknownLocationReference,
        expectedLine: 9,
      );

      // UnknownLabelReference beats UnknownLocationReference, InvalidQueueMembership, and CircularDependency:
      expectTdfError(
        'queue {\n'
        '  modified 2026-11-01 00:00:00\n'
        '  task 999999OkD2\n'
        '}\n'
        'task 000001OkD2 {\n'
        '  name "Bad Label"\n'
        '  created 2026-11-01\n'
        '  labels missinOkD2\n'
        '  blocked 000001OkD2\n'
        '  condition location missinOkD2\n'
        '}\n',
        TdfErrorKind.unknownLabelReference,
        expectedLine: 8,
      );
    });

    test('enforces MAX_ARGS_PER_STMT before scanning the 65th argument while preserving 64-arg statements and brace precedence (TDF-VAL-001, TDF-VAL-002)', () {
      final args63 = List<String>.generate(
        63,
        (i) => '${i.toString().padLeft(6, '0')}OkD2',
      ).join(' ');
      final args64 = List<String>.generate(
        64,
        (i) => '${i.toString().padLeft(6, '0')}OkD2',
      ).join(' ');
      final args65 = List<String>.generate(
        65,
        (i) => '${i.toString().padLeft(6, '0')}OkD2',
      ).join(' ');

      // 64-arg directives scan cleanly (labels and blocked):
      final labelDefs64 = List<String>.generate(
        64,
        (i) => 'label ${i.toString().padLeft(6, '0')}OkD2 {\n  name "L$i"\n}',
      ).join('\n');
      final board64Labels = tdfService.parse(
        'tdf 0.8.0\n$labelDefs64\ntask 999999OkD2 {\n  name "T"\n  created 2026-11-01\n  labels $args64\n  blocked $args64\n}\n',
      );
      expect(board64Labels.someday.single.labelIds.length, equals(64));
      expect(board64Labels.someday.single.dependencies.length, equals(64));

      // 64-arg block header scans cleanly (fails later at unknownBlockType, not limitExceeded):
      expectTdfError(
        'foo $args64 {\n}',
        TdfErrorKind.unknownBlockType,
        expectedLine: 1,
      );

      // 64th arg with attached '{' fails with InvalidBlockHeader:
      expectTdfError(
        'foo $args63 000063OkD2{\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 1,
      );

      // 64-arg block header with trailing token after '{' fails with UnexpectedToken:
      expectTdfError(
        'task $args64 { extra\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 1,
      );

      // 65th arg with attached '{' MUST fail with LimitExceeded BEFORE scanning arg #65:
      expectTdfError(
        'task 999999OkD2 {\n  name "T"\n  created 2026-11-01\n  labels $args64 000064OkD2{\n}',
        TdfErrorKind.limitExceeded,
        expectedLine: 4,
      );

      // 65-arg block header with trailing token after '{' MUST fail with LimitExceeded BEFORE scanning arg #65:
      expectTdfError(
        'task $args65 { extra\n}',
        TdfErrorKind.limitExceeded,
        expectedLine: 1,
      );

      // 65th arg as an unterminated quoted string MUST fail with LimitExceeded BEFORE scanning the string:
      expectTdfError(
        'task 999999OkD2 {\n  name "T"\n  created 2026-11-01\n  labels $args64 "unterminated\n}',
        TdfErrorKind.limitExceeded,
        expectedLine: 4,
      );
    });

    test('enforces MAX_STMTS_PER_BLOCK, MAX_NESTING_DEPTH, and MAX_BLOCKS_PER_DOC before InvalidIdentifier (TDF-VAL-001, TDF-VAL-002)', () {
      // Depth-2 nested block header with invalid identifier -> LimitExceeded (not InvalidIdentifier):
      expectTdfError(
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  subtasks {\n    123 {\n    }\n  }\n}',
        TdfErrorKind.limitExceeded,
        expectedLine: 5,
      );

      // 1025th statement with invalid identifier inside ordinary block -> LimitExceeded (not InvalidIdentifier):
      final steps1024 = List<String>.filled(
        1024,
        '    step false "Step"',
      ).join('\n');
      expectTdfError(
        'task 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  subtasks {\n$steps1024\n    123 "x"\n  }\n}',
        TdfErrorKind.limitExceeded,
        expectedLine: 1029,
      );

      // 4097th block with invalid identifier -> LimitExceeded (not InvalidIdentifier):
      final blocks4096 = List<String>.generate(
        4096,
        (i) => 'label ${i.toString().padLeft(6, '0')}OkD2 {\n  name "L"\n}',
      ).join('\n');
      expectRawTdfError(
        'tdf 0.8.0\n$blocks4096\n123 {\n}\n',
        TdfErrorKind.limitExceeded,
        expectedLine: 12290,
      );
    });

    test('validates subtasks header arguments before DuplicateDirective on repeated subtasks blocks (TDF-VAL-001)', () {
      for (final badHeader in <String>[
        'subtasks urgent {',
        'subtasks "auto-finish" {',
        'subtasks auto-finish extra {',
      ]) {
        expectTdfError(
          'task 000001OkD2 {\n'
          '  name "T"\n'
          '  created 2026-11-01\n'
          '  subtasks {\n'
          '    step false "First"\n'
          '  }\n'
          '  $badHeader\n'
          '    step false "Second"\n'
          '  }\n'
          '}',
          TdfErrorKind.invalidBlockHeader,
          expectedLine: 7,
        );
      }

      // Valid second subtasks header still fails with DuplicateDirective:
      expectTdfError(
        'task 000001OkD2 {\n'
        '  name "T"\n'
        '  created 2026-11-01\n'
        '  subtasks {\n'
        '    step false "First"\n'
        '  }\n'
        '  subtasks auto-finish {\n'
        '    step false "Second"\n'
        '  }\n'
        '}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 7,
      );
    });

    test('validates deleted record arity and primitives (Step 3) before DuplicateIdentifier (Step 4) (TDF-VAL-001)', () {
      // Duplicate deleted label ID with invalid timestamp -> InvalidTimestamp (not DuplicateIdentifier):
      expectTdfError(
        'deleted {\n'
        '  generation 1\n'
        '  label 000001OkD2 2026-11-01 12:00:00\n'
        '  label 000001OkD2 not-a-date\n'
        '}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 4,
      );

      // Duplicate deleted location ID with invalid timestamp -> InvalidTimestamp (not DuplicateIdentifier):
      expectTdfError(
        'deleted {\n'
        '  generation 1\n'
        '  location 000001OkD2 2026-11-01 12:00:00\n'
        '  location 000001OkD2 1900-02-29\n'
        '}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 4,
      );

      // Duplicate deleted task ID with extra trailing args -> UnexpectedToken:
      expectTdfError(
        'deleted {\n'
        '  generation 1\n'
        '  task 000001OkD2 2026-11-01 12:00:00\n'
        '  task 000001OkD2 2026-11-01 5 extra\n'
        '}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
      );

      // Duplicate deleted task ID with invalid timestamp -> InvalidTimestamp:
      expectTdfError(
        'deleted {\n'
        '  generation 1\n'
        '  task 000001OkD2 2026-11-01 12:00:00\n'
        '  task 000001OkD2 1900-02-29\n'
        '}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 4,
      );

      // Duplicate deleted task ID with invalid completion checkpoint -> InvalidNumber:
      expectTdfError(
        'deleted {\n'
        '  generation 1\n'
        '  task 000001OkD2 2026-11-01 12:00:00\n'
        '  task 000001OkD2 2026-11-01 abc\n'
        '}',
        TdfErrorKind.invalidNumber,
        expectedLine: 4,
      );

      // Duplicate deleted task ID with overflow completion checkpoint -> LimitExceeded:
      expectTdfError(
        'deleted {\n'
        '  generation 1\n'
        '  task 000001OkD2 2026-11-01 12:00:00\n'
        '  task 000001OkD2 2026-11-01 9007199254740992\n'
        '}',
        TdfErrorKind.limitExceeded,
        expectedLine: 4,
      );

      // Valid duplicate deleted records still fail with DuplicateIdentifier:
      expectTdfError(
        'deleted {\n'
        '  generation 1\n'
        '  task 000001OkD2 2026-11-01 12:00:00\n'
        '  task 000001OkD2 2026-11-02 12:00:00\n'
        '}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 4,
      );
      expectTdfError(
        'deleted {\n'
        '  generation 1\n'
        '  label 000001OkD2 2026-11-01 12:00:00\n'
        '  label 000001OkD2 2026-11-02 12:00:00\n'
        '}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 4,
      );
      expectTdfError(
        'deleted {\n'
        '  generation 1\n'
        '  location 000001OkD2 2026-11-01 12:00:00\n'
        '  location 000001OkD2 2026-11-02 12:00:00\n'
        '}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 4,
      );
    });

    test('enforces MAX_TEXT_LENGTH, MAX_NOTE_LENGTH, MAX_URI_LENGTH, MAX_NUMBER_LENGTH, and DayTaskCondition MAX_ARGS_PER_STMT during TdfSerializer.serialize (TDF-SER-001, TDF-VAL-002)', () {
      void expectSerializeLimitExceeded(TaskBoard board, String reason) {
        expect(
          () => tdfService.serialize(board),
          throwsA(
            isA<TdfException>().having(
              (error) => error.kind,
              'kind',
              TdfErrorKind.limitExceeded,
            ),
          ),
          reason: reason,
        );
      }

      final text500 = '\u{1F680}' * 500;
      final text501 = '\u{1F680}' * 501;
      final note2000 = '\u{1F680}' * 2000;
      final note2001 = '\u{1F680}' * 2001;
      final uri2048 = 'https://example.com/${'\u{1F680}' * 2028}';
      final uri2049 = 'https://example.com/${'\u{1F680}' * 2029}';
      final num24 = '${'0' * 21}150';
      final num25 = '${'0' * 22}150';

      // Exact N acceptance using supplementary plane scalars (2 UTF-16 code units per scalar):
      final exactBoundaryBoard = TaskBoard(
        labels: <TdfLabel>[
          TdfLabel(
            id: '000001OkD2',
            name: text500,
            note: note2000,
            links: <TaskLink>[TaskLink(title: text500, uri: uri2048)],
            conditions: <TaskCondition>[
              DayTaskCondition(
                weekdays: const <int>[1],
                dayTokens: List<String>.filled(63, 'mon'),
              ),
            ],
          ),
        ],
        locations: <TdfLocation>[
          TdfLocation(
            id: '000002OkD2',
            name: text500,
            note: note2000,
            source: text500,
            latitude: 1.5,
            longitude: 2.5,
            radius: 150,
            rawLatitudeText: num24,
            rawLongitudeText: num24,
            rawRadiusText: num24,
          ),
        ],
        someday: <TaskItem>[
          TaskItem(
            id: '000003OkD2',
            title: text500,
            note: note2000,
            createdAt: fixedDate,
            dueAt: fixedDate,
            dueNote: note2000,
            suspendedAt: fixedDate,
            suspendedNote: note2000,
            origin: TaskOrigin(namespace: text500, externalKey: text500),
            links: <TaskLink>[TaskLink(title: text500, uri: uri2048)],
            history: <TaskHistoryEntry>[
              TaskHistoryEntry(timestampUtc: fixedDate, text: text500),
            ],
            subtasks: <SubtaskItem>[
              SubtaskItem(title: text500, isCompleted: false),
            ],
            conditions: <TaskCondition>[
              DayTaskCondition(
                weekdays: const <int>[1],
                dayTokens: List<String>.filled(64, 'mon'),
              ),
              const TimeWindowTaskCondition(
                startMinutes: 480,
                endMinutes: 720,
                startToken: '08:00',
                endToken: '12:00',
              ),
            ],
          ),
        ],
      );
      expect(tdfService.serialize(exactBoundaryBoard), isNotEmpty);

      // MAX_TEXT_LENGTH (501 scalars) rejections across all <text> fields:
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(id: '000001OkD2', title: text501, createdAt: fixedDate),
          ],
        ),
        'Task title > 500 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          labels: <TdfLabel>[TdfLabel(id: '000001OkD2', name: text501)],
        ),
        'Label name > 500 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          locations: <TdfLocation>[
            TdfLocation(
              id: '000001OkD2',
              name: text501,
              latitude: 0,
              longitude: 0,
              radius: 10,
            ),
          ],
        ),
        'Location name > 500 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          locations: <TdfLocation>[
            TdfLocation(
              id: '000001OkD2',
              name: 'Loc',
              source: text501,
              latitude: 0,
              longitude: 0,
              radius: 10,
            ),
          ],
        ),
        'Location source > 500 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              createdAt: fixedDate,
              origin: TaskOrigin(namespace: text501, externalKey: 'k'),
            ),
          ],
        ),
        'Task origin namespace > 500 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              createdAt: fixedDate,
              origin: TaskOrigin(namespace: 'ns', externalKey: text501),
            ),
          ],
        ),
        'Task origin externalKey > 500 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              createdAt: fixedDate,
              links: <TaskLink>[
                TaskLink(title: text501, uri: 'https://example.com'),
              ],
            ),
          ],
        ),
        'Task link title > 500 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          labels: <TdfLabel>[
            TdfLabel(
              id: '000001OkD2',
              name: 'L',
              links: <TaskLink>[
                TaskLink(title: text501, uri: 'https://example.com'),
              ],
            ),
          ],
        ),
        'Label link title > 500 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              createdAt: fixedDate,
              history: <TaskHistoryEntry>[
                TaskHistoryEntry(timestampUtc: fixedDate, text: text501),
              ],
            ),
          ],
        ),
        'Task history text > 500 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              createdAt: fixedDate,
              subtasks: <SubtaskItem>[
                SubtaskItem(title: text501, isCompleted: false),
              ],
            ),
          ],
        ),
        'Subtask title > 500 scalars must fail on serialize',
      );

      // MAX_NOTE_LENGTH (2001 scalars) rejections across all <note> fields:
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              note: note2001,
              createdAt: fixedDate,
            ),
          ],
        ),
        'Task note > 2000 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          labels: <TdfLabel>[
            TdfLabel(id: '000001OkD2', name: 'L', note: note2001),
          ],
        ),
        'Label note > 2000 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          locations: <TdfLocation>[
            TdfLocation(
              id: '000001OkD2',
              name: 'Loc',
              note: note2001,
              latitude: 0,
              longitude: 0,
              radius: 10,
            ),
          ],
        ),
        'Location note > 2000 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              createdAt: fixedDate,
              dueAt: fixedDate,
              dueNote: note2001,
            ),
          ],
        ),
        'Task dueNote > 2000 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              createdAt: fixedDate,
              suspendedAt: fixedDate,
              suspendedNote: note2001,
            ),
          ],
        ),
        'Task suspendedNote > 2000 scalars must fail on serialize',
      );

      // MAX_URI_LENGTH (2049 scalars) rejections:
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              createdAt: fixedDate,
              links: <TaskLink>[TaskLink(title: 'Link', uri: uri2049)],
            ),
          ],
        ),
        'Task link URI > 2048 scalars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          labels: <TdfLabel>[
            TdfLabel(
              id: '000001OkD2',
              name: 'L',
              links: <TaskLink>[TaskLink(title: 'Link', uri: uri2049)],
            ),
          ],
        ),
        'Label link URI > 2048 scalars must fail on serialize',
      );

      // MAX_NUMBER_LENGTH (25 chars) rejections on location coordinates & radius:
      expectSerializeLimitExceeded(
        TaskBoard(
          locations: <TdfLocation>[
            TdfLocation(
              id: '000001OkD2',
              name: 'Loc',
              latitude: 0,
              longitude: 0,
              radius: 10,
              rawLatitudeText: num25,
            ),
          ],
        ),
        'Location latitude > 24 chars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          locations: <TdfLocation>[
            TdfLocation(
              id: '000001OkD2',
              name: 'Loc',
              latitude: 0,
              longitude: 0,
              radius: 10,
              rawLongitudeText: num25,
            ),
          ],
        ),
        'Location longitude > 24 chars must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          locations: <TdfLocation>[
            TdfLocation(
              id: '000001OkD2',
              name: 'Loc',
              latitude: 0,
              longitude: 0,
              radius: 10,
              rawRadiusText: num25,
            ),
          ],
        ),
        'Location radius > 24 chars must fail on serialize',
      );

      // DayTaskCondition MAX_ARGS_PER_STMT rejections (inline 64 tokens = 65 args; block 65 tokens = 65 args):
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              createdAt: fixedDate,
              conditions: <TaskCondition>[
                DayTaskCondition(
                  weekdays: const <int>[1],
                  dayTokens: List<String>.filled(64, 'mon'),
                ),
              ],
            ),
          ],
        ),
        'Inline task condition day with 64 tokens (65 args) must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          labels: <TdfLabel>[
            TdfLabel(
              id: '000001OkD2',
              name: 'L',
              conditions: <TaskCondition>[
                DayTaskCondition(
                  weekdays: const <int>[1],
                  dayTokens: List<String>.filled(64, 'mon'),
                ),
              ],
            ),
          ],
        ),
        'Inline label condition day with 64 tokens (65 args) must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          someday: <TaskItem>[
            TaskItem(
              id: '000001OkD2',
              title: 'T',
              createdAt: fixedDate,
              conditions: <TaskCondition>[
                DayTaskCondition(
                  weekdays: const <int>[1],
                  dayTokens: List<String>.filled(65, 'mon'),
                ),
                const TimeWindowTaskCondition(
                  startMinutes: 480,
                  endMinutes: 720,
                  startToken: '08:00',
                  endToken: '12:00',
                ),
              ],
            ),
          ],
        ),
        'Block task condition day with 65 tokens must fail on serialize',
      );
      expectSerializeLimitExceeded(
        TaskBoard(
          labels: <TdfLabel>[
            TdfLabel(
              id: '000001OkD2',
              name: 'L',
              conditions: <TaskCondition>[
                DayTaskCondition(
                  weekdays: const <int>[1],
                  dayTokens: List<String>.filled(65, 'mon'),
                ),
                const TimeWindowTaskCondition(
                  startMinutes: 480,
                  endMinutes: 720,
                  startToken: '08:00',
                  endToken: '12:00',
                ),
              ],
            ),
          ],
        ),
        'Block label condition day with 65 tokens must fail on serialize',
      );
    });
  });
}
