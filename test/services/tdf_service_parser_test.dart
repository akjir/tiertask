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
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/sha256_service.dart';
import 'package:tiertask/services/tdf_parser.dart';
import 'package:tiertask/services/tdf_service.dart';

const String _section15ExampleTdf =
    'tdf 0.8.0\n'
    '\n'
    'queue {\n'
    '    modified 2026-11-16 09:00:00\n'
    '    task 8jKaCdOkD2\n'
    '}\n'
    '\n'
    'label 4x9p2mOkD2 {\n'
    '    name  "Home"\n'
    '    color "#4CAF50"\n'
    '}\n'
    '\n'
    'task 8jKaCdOkD2 priority {\n'
    '    name     "Inspect heating pressure"\n'
    '    created  2026-11-16 08:30\n'
    '    modified 2026-11-16 09:00\n'
    '    labels   4x9p2mOkD2\n'
    '    due      2026-11-20 17:00:00 anchor 2026-11-20 18:00:00\n'
    '    subtasks {\n'
    '        step false "Check boiler gauge"\n'
    '        step false "Bleed upstairs radiator"\n'
    '    }\n'
    '}\n';

const String _vector2MinimalTaskTdf =
    'tdf 0.8.0\n'
    '\n'
    'task AAAAAAAAAA {\n'
    '    name    "A"\n'
    '    created 2026-11-16 00:00\n'
    '}\n';

const String _vector3MultiSectionTdf =
    'tdf 0.8.0\n'
    '\n'
    'deleted {\n'
    '    generation 1\n'
    '    task 6uCk8N0aB1 2026-11-01 12:00:00 2\n'
    '}\n'
    '\n'
    'queue {\n'
    '    modified 2026-11-16 09:00:00\n'
    '    task 8jKaCdOkD2\n'
    '}\n'
    '\n'
    'label 4x9p2mOkD2 {\n'
    '    name      "Home"\n'
    '    color     "#4CAF50"\n'
    '    condition location 7pQr9mOkD2\n'
    '}\n'
    '\n'
    'location 7pQr9mOkD2 {\n'
    '    name        "Office"\n'
    '    coordinates 50.9787 11.0328\n'
    '    radius      150\n'
    '}\n'
    '\n'
    'task 8jKaCdOkD2 priority {\n'
    '    name     "Close monthly books"\n'
    '    note     "Line 1\\nLine 2 with \\"quotes\\""\n'
    '    created  2026-01-01 08:00\n'
    '    modified 2026-01-31 18:00:05\n'
    '    repeat   1 months 08:00 lead 2 days\n'
    '    labels   4x9p2mOkD2\n'
    '    due      2026-02-28 17:00:00 anchor 2026-01-31 18:00:00 "Month-end cutoff"\n'
    '    condition {\n'
    '        day  mon tue wed thu fri\n'
    '        time 08:00 18:00\n'
    '    }\n'
    '    subtasks auto-finish {\n'
    '        step false "Reconcile ledger"\n'
    '        step true  "Export statements"\n'
    '    }\n'
    '}\n';

const String _vector4TiertaskTdf =
    'tdf 0.8.0\n'
    '\n'
    'deleted {\n'
    '    generation 4\n'
    '    task 6uCk8N0aB1 2026-11-01 12:00:00\n'
    '    label 1rQv7S0cD2 2026-11-02 09:00:00\n'
    '    location 8tYp4M0eF3 2026-11-02 10:15:00\n'
    '}\n'
    '\n'
    'queue {\n'
    '    modified 2026-11-01 19:30:00\n'
    '    task 8jKaCdOkD2\n'
    '    task 5vWx9ZOk91\n'
    '    task 3nQp7ROkB8\n'
    '}\n'
    '\n'
    'label 4x9p2mOkD2 {\n'
    '    name     "Home & Garden"\n'
    '    modified 2026-11-01 08:00\n'
    '    condition {\n'
    '        day      sat sun\n'
    '        time     08:00 20:00\n'
    '        location 7pQr9mOkD2\n'
    '    }\n'
    '}\n'
    '\n'
    'label 9kLm2P0aBc scoped {\n'
    '    name     "IT & Servers"\n'
    '    color    "#2196F3"\n'
    '    note     "Infrastructure runbooks and maintenance"\n'
    '    modified 2026-11-01 08:00\n'
    '    link     "Grafana Dashboard" "https://grafana.example.com/d/nas"\n'
    '    link     "Runbook Repo" "https://git.example.com/ops/runbooks"\n'
    '    condition {\n'
    '        day  mon tue wed thu fri\n'
    '        time 08:00 12:00\n'
    '        time 14:00 18:00\n'
    '    }\n'
    '}\n'
    '\n'
    'location 7pQr9mOkD2 {\n'
    '    name        "Home"\n'
    '    note        "Main residence driveway and garden"\n'
    '    source      "Erfurt, Germany"\n'
    '    coordinates 50.9787 11.0328\n'
    '    radius      150\n'
    '    modified    2026-11-01 08:00\n'
    '}\n'
    '\n'
    'task 2bDf6HOkA4 {\n'
    '    name     "Design 3D-printed enclosure for backup NAS"\n'
    '    created  2026-11-01 12:00\n'
    '    modified 2026-11-01 12:00\n'
    '    labels   9kLm2P0aBc\n'
    '}\n'
    '\n'
    'task 3nQp7ROkB8 {\n'
    '    name      "Order replacement lawnmower blades online"\n'
    '    created   2026-11-01 18:00\n'
    '    modified  2026-11-01 18:20\n'
    '    labels    4x9p2mOkD2\n'
    '    due       2026-11-03 17:00:00 anchor 2026-11-03 18:00:00 passive "Order before seasonal supplier cutoff"\n'
    '    origin    "https://jira.example.com" "HOME-42"\n'
    '    link      "Portal Login" "https://example.com/portal#login"\n'
    '    link      "Local Folder" "file:///home/user/documents/tax2026"\n'
    '    history   2026-11-01 18:05:00 "Checked blade part number against mower manual"\n'
    '    history   2026-11-01 18:20:00 "Confirmed OEM stock with dealer"\n'
    '    condition any\n'
    '}\n'
    '\n'
    'task 5vWx9ZOk91 {\n'
    '    name        "Clean dust filters on home NAS server"\n'
    '    created     2026-10-01 09:00\n'
    '    modified    2026-11-01 10:00\n'
    '    completions 1\n'
    '    repeat      1 months 09:00 lead 5 days\n'
    '    labels      4x9p2mOkD2 9kLm2P0aBc\n'
    '    due         2026-02-28 17:00:00 anchor 2026-01-31 18:00:00 "Verify SMART health after cleaning"\n'
    '    history     2026-10-01 09:30:00 "Replaced front intake filter pad"\n'
    '}\n'
    '\n'
    'task 7mPr4T09xY {\n'
    '    name        "Mount winter tires"\n'
    '    created     2026-10-20 14:00\n'
    '    finished    2026-10-29 16:45\n'
    '    modified    2026-10-29 16:45\n'
    '    completions 1\n'
    '    labels      4x9p2mOkD2\n'
    '    history     2026-10-29 16:40:00 "Torqued lug nuts to 120 Nm"\n'
    '}\n'
    '\n'
    'task 8jKaCdOkD2 priority {\n'
    '    name      "Mow the lawn"\n'
    '    note      "Check fuel level before starting"\n'
    '    created   2026-11-01 19:30\n'
    '    modified  2026-11-01 19:30\n'
    '    labels    4x9p2mOkD2\n'
    '    blocked   3nQp7ROkB8\n'
    '    suspended 2026-11-04 23:00:00 "Wait for blade delivery and dry forecast"\n'
    '    due       2026-11-07 16:00:00 anchor 2026-11-07 17:00:00 "Before first frost"\n'
    '    condition time 09:00 18:00\n'
    '    subtasks auto-finish {\n'
    '        step false "Get lawnmower from the shed"\n'
    '        step true  "Empty grass catcher bag"\n'
    '    }\n'
    '}\n';

int _countLfLines(String text) {
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      count++;
    }
  }
  return count;
}

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12);

  group('TdfService 0.8.0 Lexical Scanner, Parser & Canonical Serializer', () {
    test('reproduces byte-exact canonical output and SHA-256 digests for Section 1.5 and Vectors 1 through 4 (TDF-SER-005)', () {
      // Section 1.5 Introductory Example (453 UTF-8 bytes, 23 lines):
      final section15Bytes = utf8.encode(_section15ExampleTdf);
      expect(
        section15Bytes.length,
        equals(453),
        reason: 'Section 1.5 introductory example must be 453 UTF-8 bytes',
      );
      expect(
        _countLfLines(_section15ExampleTdf),
        equals(23),
        reason: 'Section 1.5 introductory example must have 23 LF lines',
      );
      final section15Board = tdfService.parseBytes(
        section15Bytes,
        evaluationTime: DateTime.utc(2026, 11, 16, 10),
        timeZone: TdfTimeZoneContext.europeBerlin,
      );
      expect(
        section15Board.findTask('8jKaCdOkD2')?.dueAnchor,
        equals(TdfLocalDateTime(2026, 11, 20, 18)),
      );
      expect(
        tdfService.serialize(section15Board),
        equals(_section15ExampleTdf),
        reason: 'Section 1.5 example must round-trip byte-identically',
      );

      // Vector 1: Empty Document (10 bytes, 1 line):
      final vector1Serialized = tdfService.serialize(TaskBoard.empty());
      final vector1Bytes = utf8.encode(vector1Serialized);
      expect(vector1Serialized, equals('tdf 0.8.0\n'));
      expect(vector1Bytes.length, equals(10));
      expect(_countLfLines(vector1Serialized), equals(1));
      expect(
        Sha256Service.hashHex(vector1Bytes),
        equals(
          '7904b7a8e8cd221287ac91710477af38bbb7beb14dea75e2c827dfa2bfd2097a',
        ),
        reason: 'Vector 1 must match normative SHA-256 sourceDigest',
      );

      // Vector 2: Minimal Single-Task Alignment (76 bytes, 6 lines):
      final vector2Board = tdfService.parse(
        _vector2MinimalTaskTdf,
        evaluationTime: fixedDate,
      );
      final vector2Serialized = tdfService.serialize(vector2Board);
      final vector2Bytes = utf8.encode(vector2Serialized);
      expect(vector2Serialized, equals(_vector2MinimalTaskTdf));
      expect(vector2Bytes.length, equals(76));
      expect(_countLfLines(vector2Serialized), equals(6));
      expect(
        Sha256Service.hashHex(vector2Bytes),
        equals(
          '3211d46b392b7b1efbf53cf07a0c0c6131f987a4b17dba9a733b9971108f7090',
        ),
        reason: 'Vector 2 must match normative SHA-256 sourceDigest',
      );

      // Vector 3: Multi-Section Alignment + Inline label condition W_dir = 9 (856 bytes, 41 lines):
      final vector3Board = tdfService.parse(
        _vector3MultiSectionTdf,
        evaluationTime: fixedDate,
        timeZone: TdfTimeZoneContext.europeBerlin,
      );
      final vector3Serialized = tdfService.serialize(vector3Board);
      final vector3Bytes = utf8.encode(vector3Serialized);
      expect(vector3Serialized, equals(_vector3MultiSectionTdf));
      expect(vector3Bytes.length, equals(856));
      expect(_countLfLines(vector3Serialized), equals(41));
      expect(
        Sha256Service.hashHex(vector3Bytes),
        equals(
          '8e5771dedbdde3bf9451c247bbab1a826298f90e0c2e20a57e98ed75f53cf7cd',
        ),
        reason: 'Vector 3 must match normative SHA-256 sourceDigest',
      );

      // Vector 4: Appendix B.1 tiertask.tdf (3,086 bytes, 106 lines):
      final vector4InputBytes = utf8.encode(_vector4TiertaskTdf);
      expect(vector4InputBytes.length, equals(3086));
      expect(_countLfLines(_vector4TiertaskTdf), equals(106));
      expect(
        Sha256Service.hashHex(vector4InputBytes),
        equals(
          'cf9d9f26158d9d58d9561802d9169bb704bac7df64f09d120a1d8a2b0bb17016',
        ),
      );
      final vector4Board = tdfService.parseBytes(
        vector4InputBytes,
        evaluationTime: fixedDate,
        timeZone: TdfTimeZoneContext.europeBerlin,
        currentLatitude: 50.9787,
        currentLongitude: 11.0328,
      );
      expect(vector4Board.deletedBlock.generation, equals(4));
      expect(
        vector4Board.deletedBlock.tasks.single.taskId,
        equals('6uCk8N0aB1'),
      );
      expect(
        vector4Board.deletedBlock.labels.single.labelId,
        equals('1rQv7S0cD2'),
      );
      expect(
        vector4Board.deletedBlock.locations.single.locationId,
        equals('8tYp4M0eF3'),
      );
      expect(
        vector4Board.queueBlock.taskIds,
        equals(<String>['8jKaCdOkD2', '5vWx9ZOk91', '3nQp7ROkB8']),
      );
      expect(
        vector4Board.focus.map((task) => task.id),
        equals(<String>['5vWx9ZOk91', '3nQp7ROkB8']),
        reason: 'On Sunday 12:00 UTC (13:00 CET) at Home GPS, 5vWx9ZOk91 (urgent non-passive Feb 28 <= Nov 1) and 3nQp7ROkB8 (condition any) enter Focus',
      );
      expect(
        vector4Board.blocked.map((task) => task.id),
        equals(<String>['8jKaCdOkD2']),
      );
      expect(
        vector4Board.someday,
        isEmpty,
        reason: '2bDf6HOkA4 carries only scoped label 9kLm2P0aBc, so global view excludes it while preserving it in allTasks',
      );
      expect(
        vector4Board.allTasks.any((task) => task.id == '2bDf6HOkA4'),
        isTrue,
      );
      expect(
        vector4Board.completed.map((task) => task.id),
        equals(<String>['7mPr4T09xY']),
      );

      final vector4Serialized = tdfService.serialize(vector4Board);
      final vector4OutputBytes = utf8.encode(vector4Serialized);
      expect(vector4Serialized, equals(_vector4TiertaskTdf));
      expect(vector4OutputBytes.length, equals(3086));
      expect(_countLfLines(vector4Serialized), equals(106));
      expect(
        Sha256Service.hashHex(vector4OutputBytes),
        equals(
          'cf9d9f26158d9d58d9561802d9169bb704bac7df64f09d120a1d8a2b0bb17016',
        ),
        reason: 'Vector 4 must round-trip with identical SHA-256 sourceDigest',
      );
    });

    test('enforces single-version tdf 0.8.0 contract and parseBytes UTF-8/size checks (TDF-COMPAT-001, TDF-ENT-001, TDF-LEX-001)', () {
      expect(TdfService.supportedVersion, equals('0.8.0'));
      expect(TdfBlockParser.supportedVersion, equals('0.8.0'));

      expect(
        tdfService
            .parse('   \t  \n# leading comment\r\ntdf 0.8.0  # version\n')
            .allTasks,
        isEmpty,
      );

      final unsupportedHeaders = <({String doc, String expectedSource})>[
        (doc: 'tdf 0.7.0\n', expectedSource: '0.7.0'),
        (doc: 'tdf 0.6.0\n', expectedSource: '0.6.0'),
        (doc: 'tdf 0.5.1\n', expectedSource: '0.5.1'),
        (doc: 'tdf 0.5.0\n', expectedSource: '0.5.0'),
        (doc: 'tdf 0.4.0\n', expectedSource: '0.4.0'),
        (doc: 'tdf 0.3.0\n', expectedSource: '0.3.0'),
        (doc: 'tdf 0.2.0\n', expectedSource: '0.2.0'),
        (doc: 'tdf 0.1.0\n', expectedSource: '0.1.0'),
        (doc: 'tdf 1.0.0\n', expectedSource: '1.0.0'),
        (doc: 'tdf 0.8\n', expectedSource: '0.8'),
        (doc: 'tdf v0.8.0\n', expectedSource: 'v0.8.0'),
        (doc: 'tdf "0.8.0"\n', expectedSource: '0.8.0'),
        (doc: "tdf '0.8.0'\n", expectedSource: '0.8.0'),
        (doc: 'tdf 0.8.0 extra\n', expectedSource: '0.8.0'),
      ];

      for (final testCase in unsupportedHeaders) {
        expect(
          () => tdfService.parse(testCase.doc),
          throwsA(
            isA<TdfException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  TdfErrorKind.unsupportedVersion,
                )
                .having((error) => error.line, 'line', 1)
                .having(
                  (error) => error.sourceVersion,
                  'sourceVersion',
                  testCase.expectedSource,
                ),
          ),
          reason:
              'Header "${testCase.doc.trim()}" must fail with UnsupportedVersion and sourceVersion=${testCase.expectedSource}',
        );
      }

      final missingHeaders = <String>[
        '',
        '   \t  \r\n# comment only\n',
        'tdf\n',
        'tdf {\n}\n',
        'tdf 0.8.0 {\n}\n',
        '"tdf" 0.8.0\n',
        "'tdf' 0.8.0\n",
        'task AAAAAAAAAA {\n  name "X"\n  created 2026-11-16\n}\n',
        'name "Missing header"\n',
        '{\n',
      ];

      for (final doc in missingHeaders) {
        expect(
          () => tdfService.parse(doc),
          throwsA(
            isA<TdfException>().having(
              (error) => error.kind,
              'kind',
              TdfErrorKind.missingVersionHeader,
            ),
          ),
          reason: 'Document must fail with MissingVersionHeader: $doc',
        );
      }

      // Oversized byte input checked BEFORE UTF-8 decoding:
      final overLimitBytes = Uint8List(maxTdfFileBytes + 1);
      overLimitBytes.fillRange(0, maxTdfFileBytes, 0x20);
      overLimitBytes[maxTdfFileBytes] = 0xFF;
      expect(
        () => tdfService.parseBytes(overLimitBytes),
        throwsA(
          isA<TdfException>()
              .having((error) => error.kind, 'kind', TdfErrorKind.limitExceeded)
              .having((error) => error.line, 'line', 1),
        ),
        reason: 'parseBytes must enforce MAX_FILE_BYTES before UTF-8 decoding',
      );

      // Malformed UTF-8 reports exact 1-based physical line number:
      final badUtf8Line1 = Uint8List.fromList(<int>[0xFF, 0x0A]);
      final badUtf8Line2 = Uint8List.fromList(<int>[
        ...utf8.encode('tdf 0.8.0\n'),
        0xC3,
        0x28,
        0x0A,
      ]);
      final badUtf8Line4 = Uint8List.fromList(<int>[
        ...utf8.encode('tdf 0.8.0\r\n# line 2\n# line 3\n# '),
        0xE2,
        0x28,
        0xA1,
      ]);

      for (final (bytes, expectedLine) in <(Uint8List, int)>[
        (badUtf8Line1, 1),
        (badUtf8Line2, 2),
        (badUtf8Line4, 4),
      ]) {
        expect(
          () => tdfService.parseBytes(bytes),
          throwsA(
            isA<TdfException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  TdfErrorKind.unexpectedToken,
                )
                .having((error) => error.line, 'line', expectedLine),
          ),
          reason:
              'Malformed UTF-8 on line $expectedLine must throw UnexpectedToken at line $expectedLine',
        );
      }
    });

    test('parses and serializes all due modifier combinations including local schedule anchors (TDF-DIR-004)', () {
      const dueVariantsDoc = '''
tdf 0.8.0

task 111111OkD2 {
    name    "Date-only due"
    created 2026-11-01 08:00
    due     2026-11-20
}

task 222222OkD2 {
    name    "Date-only due with date-only anchor and numeric-looking note"
    created 2026-11-01 08:00
    due     2026-11-20 anchor 2026-11-21 "18:00"
}

task 333333OkD2 {
    name      "Full due with anchor, passive, note, and suspended > due"
    created   2026-11-01 08:00
    suspended 2026-03-05 12:00:00 "Suspended past due is valid"
    due       2026-02-28 17:00 anchor 2026-01-31 18:00:05 passive "Month-end\\ncutoff"
}
''';

      final board = tdfService.parse(dueVariantsDoc, evaluationTime: fixedDate);

      final task1 = board.findTask('111111OkD2');
      expect(task1?.dueAt, equals(DateTime.utc(2026, 11, 20)));
      expect(task1?.dueAnchor, isNull);
      expect(task1?.isDuePassive, isFalse);
      expect(task1?.dueNote, isNull);

      final task2 = board.findTask('222222OkD2');
      expect(task2?.dueAt, equals(DateTime.utc(2026, 11, 20)));
      expect(task2?.dueAnchor, equals(TdfLocalDateTime(2026, 11, 21)));
      expect(task2?.isDuePassive, isFalse);
      expect(task2?.dueNote, equals('18:00'));

      final task3 = board.findTask('333333OkD2');
      expect(task3?.dueAt, equals(DateTime.utc(2026, 2, 28, 17)));
      expect(task3?.dueAnchor, equals(TdfLocalDateTime(2026, 1, 31, 18, 0, 5)));
      expect(task3?.isDuePassive, isTrue);
      expect(task3?.dueNote, equals('Month-end\ncutoff'));

      final serialized = tdfService.serialize(board);
      expect(serialized, contains('    due     2026-11-20 00:00:00\n'));
      expect(
        serialized,
        contains(
          '    due     2026-11-20 00:00:00 anchor 2026-11-21 00:00:00 "18:00"\n',
        ),
      );
      expect(
        serialized,
        contains(
          '    due       2026-02-28 17:00:00 anchor 2026-01-31 18:00:05 passive "Month-end\\ncutoff"\n',
        ),
      );

      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(reparsed.findTask('111111OkD2'), equals(task1));
      expect(reparsed.findTask('222222OkD2'), equals(task2));
      expect(reparsed.findTask('333333OkD2'), equals(task3));
    });

    test('preserves explicit epoch modified (1970-01-01 00:00) vs omitted modified, normalizes colors/decimals/conditions, and supports disjoint namespaces (TDF-MODEL-002, TDF-MODEL-006, TDF-SER-001)', () {
      const doc =
          'tdf 0.8.0 # version\u00A0comment\r\n'
          'deleted {\r\n'
          '  generation 3\r\n'
          '}\r\n'
          'queue {\r\n'
          '  modified 2026-11-01 08:00:05\r\n'
          '}\r\n'
          'label 8jKaCdOkD2 {\r\n'
          '  name \'Raw "quote" and \\\\backslash\'\r\n'
          '  color "#4caf50"\r\n'
          '  modified 1970-01-01 00:00\r\n'
          '  condition location 8jKaCdOkD2\r\n'
          '  condition {\r\n'
          '    location 8jKaCdOkD2\r\n'
          '  }\r\n'
          '}\r\n'
          'label omitMdOkD2 {\r\n'
          '  name "Omitted Modified Label"\r\n'
          '}\r\n'
          'location 8jKaCdOkD2 {\r\n'
          '  name "Shared ID Location"\r\n'
          '  coordinates -0.000 0011.032800\r\n'
          '  radius 0150.00\r\n'
          '  modified 1970-01-01 00:00\r\n'
          '}\r\n'
          'location omitLcOkD2 {\r\n'
          '  name "Omitted Modified Location"\r\n'
          '  coordinates 50.9787 11.0328\r\n'
          '  radius 25.50\r\n'
          '}\r\n'
          'task 8jKaCdOkD2 {\r\n'
          '  name "Shared ID Task"\r\n'
          '  created 2026-11-01 08:00\r\n'
          '  modified 1970-01-01 00:00\r\n'
          '  labels 8jKaCdOkD2\r\n'
          '  subtasks {\r\n'
          '    step true "All true uses W_bool = 4"\r\n'
          '  }\r\n'
          '}\r\n';

      final board = tdfService.parse(doc, evaluationTime: fixedDate);
      final epochLabel = board.findLabel('8jKaCdOkD2');
      final omittedLabel = board.findLabel('omitMdOkD2');
      final epochLocation = board.findLocation('8jKaCdOkD2');
      final omittedLocation = board.findLocation('omitLcOkD2');
      final epochTask = board.findTask('8jKaCdOkD2');

      expect(epochLabel?.color, equals('#4CAF50'));
      expect(epochLabel?.modifiedAt, equals(DateTime.utc(1970)));
      expect(omittedLabel?.modifiedAt, isNull);
      expect(omittedLabel?.effectiveModifiedAt, equals(DateTime.utc(1970)));

      expect(epochLocation?.latitudeText, equals('0'));
      expect(epochLocation?.longitudeText, equals('11.0328'));
      expect(epochLocation?.radiusText, equals('150'));
      expect(epochLocation?.modifiedAt, equals(DateTime.utc(1970)));
      expect(omittedLocation?.modifiedAt, isNull);
      expect(omittedLocation?.radiusText, equals('25.5'));

      expect(epochTask?.modifiedAt, equals(DateTime.utc(1970)));

      final serialized = tdfService.serialize(board);
      expect(
        serialized,
        contains(
          'deleted {\n'
          '    generation 3\n'
          '}\n\n'
          'queue {\n'
          '    modified 2026-11-01 08:00:05\n'
          '}\n',
        ),
        reason: 'Non-zero generation deleted block and non-epoch empty queue block must be preserved',
      );
      expect(
        serialized,
        contains(
          'label 8jKaCdOkD2 {\n'
          '    name      "Raw \\"quote\\" and \\\\\\\\backslash"\n'
          '    color     "#4CAF50"\n'
          '    modified  1970-01-01 00:00\n'
          '    condition location 8jKaCdOkD2\n'
          '}\n',
        ),
        reason: 'Explicit epoch modified and coalesced single location condition (W_dir = 9) must be emitted on label',
      );
      expect(
        serialized,
        contains(
          'label omitMdOkD2 {\n'
          '    name "Omitted Modified Label"\n'
          '}\n',
        ),
      );
      expect(
        serialized,
        contains(
          'location 8jKaCdOkD2 {\n'
          '    name        "Shared ID Location"\n'
          '    coordinates 0 11.0328\n'
          '    radius      150\n'
          '    modified    1970-01-01 00:00\n'
          '}\n',
        ),
      );
      expect(
        serialized,
        contains('        step true "All true uses W_bool = 4"\n'),
        reason: 'W_bool must be 4 when every step in subtasks is true',
      );

      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(reparsed.findLabel('8jKaCdOkD2')?.modifiedAt, isNotNull);
      expect(reparsed.findLabel('omitMdOkD2')?.modifiedAt, isNull);
      expect(reparsed.findLocation('8jKaCdOkD2')?.modifiedAt, isNotNull);
      expect(reparsed.findLocation('omitLcOkD2')?.modifiedAt, isNull);
      expect(reparsed.findTask('8jKaCdOkD2')?.modifiedAt, isNotNull);
    });

    test('redacts sensitive notes, links, history, origins, and locations from AppLogger during parse and serialize', () {
      AppLogger.clear();
      AppLogger.setEnabled(true, minimumLevel: LogLevel.debug);
      try {
        final board = tdfService.parse(
          _vector4TiertaskTdf,
          evaluationTime: fixedDate,
          timeZone: TdfTimeZoneContext.europeBerlin,
        );
        tdfService.serialize(board);
        final logs = AppLogger.fullLogText;
        expect(logs, contains('version=0.8.0'));
        for (final secret in <String>[
          'Erfurt, Germany',
          '50.9787',
          'HOME-42',
          'grafana.example.com',
          'Confirmed OEM stock',
          'Wait for blade delivery',
          'Before first frost',
        ]) {
          expect(
            logs,
            isNot(contains(secret)),
            reason: 'AppLogger must never emit sensitive TDF payload "$secret"',
          );
        }
      } finally {
        AppLogger.setEnabled(false);
        AppLogger.clear();
      }
    });

    test('scans double-quoted tokens identically across unescaped fast path and escaped slow path', () {
      final now = DateTime.utc(2026, 11, 20, 12);
      const tdf =
          'tdf 0.8.0\n'
          '\n'
          'task tskScan001 {\n'
          '    name    "Plain ASCII and \u00FCmlaut with \'single\' quotes"\n'
          '    note    "\\tStart\\nMiddle \\"quoted\\" \\\\ slash\\\\"\n'
          '    created 2026-11-20 12:00\n'
          '}\n';
      final board = tdfService.parse(tdf, evaluationTime: now);
      final task = board.allTasks.single;
      expect(
        task.title,
        equals("Plain ASCII and \u00FCmlaut with 'single' quotes"),
      );
      expect(task.note, equals('\tStart\nMiddle "quoted" \\ slash\\'));
    });

    test('logs UTF-8 byte count on serialize and runs parseAsync, parseBytesAsync, and serializeAsync across isolate threshold and non-sendable fallback', () async {
      expect(TdfService.isolateOffloadThresholdBytes, equals(32768));

      final now = DateTime.utc(2026, 11, 20, 12);
      const smallTdf =
          'tdf 0.8.0\n'
          '\n'
          'task tskUtf8001 {\n'
          '    name    "\u00E4\u00F6\u00FC\u00DF\u20AC\u{1F600}"\n'
          '    created 2026-11-20 12:00\n'
          '}\n';
      final smallBoard = tdfService.parse(smallTdf, evaluationTime: now);

      AppLogger.resetForTesting(clock: () => now);
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      try {
        final serializedSmall = tdfService.serialize(smallBoard);
        final expectedUtf8Bytes = utf8.encode(serializedSmall).length;
        expect(expectedUtf8Bytes, greaterThan(serializedSmall.length));
        final logLine = AppLogger.lines.lastWhere(
          (line) => line.contains('tdf.serialize |'),
        );
        expect(
          logLine,
          contains('bytes=$expectedUtf8Bytes'),
          reason: 'tdf.serialize log must report exact UTF-8 byte length rather than UTF-16 code units',
        );

        final asyncSmallParsed = await tdfService.parseAsync(
          serializedSmall,
          evaluationTime: now,
        );
        final asyncSmallBytesParsed = await tdfService.parseBytesAsync(
          utf8.encode(serializedSmall),
          evaluationTime: now,
        );
        final asyncSmallSerialized = await tdfService.serializeAsync(
          smallBoard,
        );
        expect(asyncSmallParsed, equals(smallBoard));
        expect(asyncSmallBytesParsed, equals(smallBoard));
        expect(asyncSmallSerialized, equals(serializedSmall));
      } finally {
        AppLogger.resetForTesting();
      }

      // Build a > 32 KiB document to exercise real Isolate.run offload paths.
      final largeBuffer = StringBuffer('tdf 0.8.0\n');
      for (var i = 0; i < 320; i++) {
        final taskId = 'ISO${i.toString().padLeft(7, '0')}';
        largeBuffer
          ..writeln()
          ..writeln('task $taskId {')
          ..writeln('    name    "Isolate benchmark payload task number $i"')
          ..writeln(
            '    note    "Structured multi-sentence note ensuring payload exceeds 32 KiB threshold for isolate offload."',
          )
          ..writeln('    created 2026-11-20 12:00')
          ..writeln('}');
      }
      final largeTdf = largeBuffer.toString();
      final largeBytes = utf8.encode(largeTdf);
      expect(
        largeBytes.length,
        greaterThanOrEqualTo(TdfService.isolateOffloadThresholdBytes),
      );

      final syncLargeBoard = tdfService.parse(
        largeTdf,
        evaluationTime: now,
        timeZone: TdfTimeZoneContext.americaNewYork,
      );
      final asyncLargeBoard = await tdfService.parseAsync(
        largeTdf,
        evaluationTime: now,
        timeZone: TdfTimeZoneContext.americaNewYork,
      );
      final asyncLargeBytesBoard = await tdfService.parseBytesAsync(
        largeBytes,
        evaluationTime: now,
        timeZone: TdfTimeZoneContext.americaNewYork,
      );
      expect(asyncLargeBoard, equals(syncLargeBoard));
      expect(asyncLargeBytesBoard, equals(syncLargeBoard));

      final syncLargeSerialized = tdfService.serialize(syncLargeBoard);
      final asyncLargeSerialized = await tdfService.serializeAsync(
        syncLargeBoard,
      );
      expect(asyncLargeSerialized, equals(syncLargeSerialized));

      // Non-sendable customObserver must fall back synchronously without throwing isolate errors.
      final customZone = TdfTimeZoneContext.customObserver(
        'Test/NonSendable',
        (int _) => 3600,
      );
      final fallbackBoard = await tdfService.parseAsync(
        largeTdf,
        evaluationTime: now,
        timeZone: customZone,
      );
      expect(fallbackBoard.allTasks.length, equals(320));

      // Malformed large document must propagate exact TdfException across isolate boundary.
      final invalidLargeTdf = '$largeTdf\ntask BAD {\n}\n';
      await expectLater(
        tdfService.parseAsync(invalidLargeTdf, evaluationTime: now),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.invalidIdentifier,
          ),
        ),
      );
    });
  });
}
