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
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_board_sync.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/services/sha256_service.dart';
import 'package:tiertask/services/tdf_service.dart';

const String _boundsDir = 'spec/conformance/v0.8.0/bounds';
const String _boundsManifestPath = '$_boundsDir/manifest.json';
const String _conformanceReadmePath = 'spec/conformance/v0.8.0/README.md';
const String _mergeVectorsPath = 'spec/conformance/v0.8.0/merge/vectors.json';
const String _parseInvalidDir = 'spec/conformance/v0.8.0/parse_invalid';
const String _parseInvalidManifestPath = '$_parseInvalidDir/manifest.json';
const String _parseValidDir = 'spec/conformance/v0.8.0/parse_valid';
const String _parseValidManifestPath = '$_parseValidDir/manifest.json';
const String _specPath = 'spec/TDF_SPEC_0.8.0.md';
const String _timezoneVectorsPath =
    'spec/conformance/v0.8.0/timezone/vectors.json';

final RegExp _appendixA3RuleRowPattern = RegExp(
  r'^\|\s*`(TDF-[A-Z]+-\d{3})`\s*\|',
  multiLine: true,
);
final RegExp _ruleIdFormatPattern = RegExp(r'^TDF-[A-Z]+-\d{3}$');

/// Executes the normative TDF 0.8.0 Part A, bounds, operational, and 93-rule traceability conformance suite.
void main() {
  const tdfService = TdfService();

  group('TDF 0.8.0 Conformance Fixture Suite & 93-Rule Traceability', () {
    test('verifies README.md documentation and bijective 93-rule Appendix A.3 coverage across all 5 conformance suites', () {
      final readmeFile = File(_conformanceReadmePath);
      expect(
        readmeFile.existsSync(),
        isTrue,
        reason: 'Conformance suite README.md must exist',
      );
      final readmeText = readmeFile.readAsStringSync();
      expect(
        readmeText.contains('\n---\n'),
        isFalse,
        reason: 'README.md must not contain Markdown horizontal rules',
      );
      for (final requiredSection in <String>[
        'parse_valid/',
        'parse_invalid/',
        'bounds/',
        'merge/',
        'timezone/',
        'sourceDigest',
      ]) {
        expect(
          readmeText,
          contains(requiredSection),
          reason: 'README.md must document $requiredSection',
        );
      }

      final specRules = _extractAppendixA3RuleIds();
      expect(
        specRules.length,
        equals(93),
        reason: 'Appendix A.3 of spec/TDF_SPEC_0.8.0.md must index 93 rules',
      );
      for (final ruleId in specRules) {
        expect(
          _ruleIdFormatPattern.hasMatch(ruleId),
          isTrue,
          reason: 'TDF-META-002 requires TDF-<AREA>-<NNN> format: $ruleId',
        );
      }

      final coveredRules = <String>{
        ..._collectSuiteRuleIds(_loadJsonMap(_parseValidManifestPath)),
        ..._collectSuiteRuleIds(_loadJsonMap(_parseInvalidManifestPath)),
        ..._collectSuiteRuleIds(_loadJsonMap(_boundsManifestPath)),
        ..._collectSuiteRuleIds(_loadJsonMap(_mergeVectorsPath)),
        ..._collectSuiteRuleIds(_loadJsonMap(_timezoneVectorsPath)),
        ..._executeOperationalAndMetaRuleAssertions(tdfService),
      };

      final missingFromSuites = specRules.difference(coveredRules);
      final unknownInSuites = coveredRules.difference(specRules);
      expect(
        missingFromSuites,
        isEmpty,
        reason:
            'Every Appendix A.3 Rule ID must be verified: missing $missingFromSuites',
      );
      expect(
        unknownInSuites,
        isEmpty,
        reason:
            'Conformance suites must not reference non-existent Rule IDs: $unknownInSuites',
      );
    });

    test('executes all parse_valid fixtures with normalized model, byte-exact canonical output, idempotence, and SHA-256 sourceDigest checks', () {
      final manifest = _loadJsonMap(_parseValidManifestPath);
      expect(manifest['version'], equals(tdfSupportedVersion));
      final fixtures = _requireMapList(manifest, 'fixtures');
      expect(
        fixtures.length,
        greaterThanOrEqualTo(10),
        reason: 'parse_valid must cover Vectors 1-4, Section 1.5, and normalization cases',
      );
      for (final fixture in fixtures) {
        _runParseValidFixture(tdfService, fixture);
      }
    });

    test('executes all parse_invalid fixtures across parse and parseBytes and verifies exhaustive 30-error coverage', () {
      final invalidManifest = _loadJsonMap(_parseInvalidManifestPath);
      expect(invalidManifest['version'], equals(tdfSupportedVersion));
      final invalidFixtures = _requireMapList(invalidManifest, 'fixtures');
      expect(invalidFixtures.length, greaterThanOrEqualTo(45));

      final observedErrors = <TdfErrorKind>{};
      for (final fixture in invalidFixtures) {
        final kind = _runParseInvalidFixture(tdfService, fixture);
        observedErrors.add(kind);
      }

      final boundsManifest = _loadJsonMap(_boundsManifestPath);
      if (_requireMapList(boundsManifest, 'fileCases').isNotEmpty ||
          _requireMapList(boundsManifest, 'templateCases').isNotEmpty) {
        observedErrors.add(TdfErrorKind.limitExceeded);
      }

      expect(
        observedErrors,
        equals(TdfErrorKind.values.toSet()),
        reason: 'parse_invalid + bounds must exercise all 30 TdfErrorKind variants (TDF-ERR-001)',
      );
    });

    test('executes all 22 normative MAX_* bounds at exact N (accept) and N + 1 (LimitExceeded) from bounds/manifest.json', () {
      final manifest = _loadJsonMap(_boundsManifestPath);
      expect(manifest['version'], equals(tdfSupportedVersion));
      final constants = _requireMap(manifest, 'boundConstants');
      _verifyDeclaredBoundConstants(constants);

      final coveredBounds = <String>{};
      for (final fileCase in _requireMapList(manifest, 'fileCases')) {
        coveredBounds.add(_requireString(fileCase, 'bound'));
        _runBoundsFileCase(tdfService, fileCase);
      }
      for (final templateCase in _requireMapList(manifest, 'templateCases')) {
        coveredBounds.add(_requireString(templateCase, 'bound'));
        _runBoundsTemplateCase(tdfService, templateCase);
      }

      expect(
        coveredBounds.length,
        equals(22),
        reason: 'bounds/manifest.json must test all 22 normative MAX_* constants in Section 6.2',
      );
    });

    test('accepts EOF-terminated standalone tdf 0.8.0 version header and serializes canonically with LF (TDF-LEX-002, TDF-GRAM-002)', () {
      for (final raw in const <String>[
        'tdf 0.8.0',
        '  tdf 0.8.0  # trailing comment at EOF',
        '# leading comment\ntdf 0.8.0',
      ]) {
        final parsed = tdfService.parse(raw);
        expect(
          parsed.allTasks,
          isEmpty,
          reason: 'EOF-terminated "$raw" must parse as empty board',
        );
        expect(
          tdfService.serialize(parsed),
          equals('tdf 0.8.0\n'),
          reason: 'Canonical output for "$raw" must end with LF',
        );
      }
    });
  });
}

void _appendNormalizedConditionGroup(
  TaskCondition condition,
  List<String> dayArgs,
  List<String> timeArgs,
  List<String> locationArgs,
) {
  switch (condition.group) {
    case ConditionGroup.day:
      dayArgs.add(condition.toTdfDirectiveArgs());
    case ConditionGroup.time:
      timeArgs.add(condition.toTdfDirectiveArgs());
    case ConditionGroup.location:
      locationArgs.add(condition.toTdfDirectiveArgs());
    case null:
      break;
  }
}

Map<String, Object?> _boardToNormalizedJson(TaskBoard board) {
  final sortedLabels = List<TdfLabel>.from(board.labels)
    ..sort((a, b) => a.id.compareTo(b.id));
  final sortedLocations = List<TdfLocation>.from(board.locations)
    ..sort((a, b) => a.id.compareTo(b.id));
  final sortedTasks = List<TaskItem>.from(board.allTasks)
    ..sort((a, b) => a.id.compareTo(b.id));
  final sortedDeletedTasks = List<TdfDeletedTaskRecord>.from(
    board.deletedBlock.tasks,
  )..sort((a, b) => a.taskId.compareTo(b.taskId));
  final sortedDeletedLabels = List<TdfDeletedLabelRecord>.from(
    board.deletedBlock.labels,
  )..sort((a, b) => a.labelId.compareTo(b.labelId));
  final sortedDeletedLocations = List<TdfDeletedLocationRecord>.from(
    board.deletedBlock.locations,
  )..sort((a, b) => a.locationId.compareTo(b.locationId));

  return <String, Object?>{
    'version': tdfSupportedVersion,
    'deleted': <String, Object?>{
      'generation': board.deletedBlock.generation,
      'tasks': <Map<String, Object?>>[
        for (final record in sortedDeletedTasks)
          <String, Object?>{
            'id': record.taskId,
            'deletedAt': _formatUtcSeconds(record.deletedAt),
            'checkpoint': record.completionsCheckpoint,
          },
      ],
      'labels': <Map<String, Object?>>[
        for (final record in sortedDeletedLabels)
          <String, Object?>{
            'id': record.labelId,
            'deletedAt': _formatUtcSeconds(record.deletedAt),
          },
      ],
      'locations': <Map<String, Object?>>[
        for (final record in sortedDeletedLocations)
          <String, Object?>{
            'id': record.locationId,
            'deletedAt': _formatUtcSeconds(record.deletedAt),
          },
      ],
    },
    'queue': <String, Object?>{
      'modified': _formatUtcSeconds(board.queueBlock.modifiedAt),
      'tasks': List<String>.from(board.queueBlock.taskIds),
    },
    'labels': <Map<String, Object?>>[
      for (final label in sortedLabels) _labelToNormalizedJson(label),
    ],
    'locations': <Map<String, Object?>>[
      for (final location in sortedLocations)
        _locationToNormalizedJson(location),
    ],
    'tasks': <Map<String, Object?>>[
      for (final task in sortedTasks) _taskToNormalizedJson(task),
    ],
  };
}

String _buildTemplateDocument(String templateKind, int count) {
  switch (templateKind) {
    case 'file_bytes':
      const prefix = 'tdf 0.8.0\n#';
      final padCount = count - prefix.length - 1;
      return '$prefix${'a' * padCount}\n';
    case 'line_count':
      return 'tdf 0.8.0\n${'\n' * (count - 1)}';
    case 'blocks_per_doc':
      final blocks = List<String>.generate(
        count,
        (i) => 'label ${i.toString().padLeft(6, '0')}OkD2 {\n  name "L"\n}',
      ).join('\n');
      return 'tdf 0.8.0\n$blocks\n';
    case 'locations':
      final blocks = List<String>.generate(
        count,
        (i) =>
            'location ${i.toString().padLeft(6, '0')}OkD2 {\n  name "Loc"\n  coordinates 0 0\n  radius 10\n}',
      ).join('\n');
      return 'tdf 0.8.0\n$blocks\n';
    case 'stmts_per_block':
      final steps = List<String>.filled(count, '    step false "S"').join('\n');
      return 'tdf 0.8.0\ntask 000001OkD2 {\n  name "T"\n  created 2026-11-01\n  subtasks {\n$steps\n  }\n}\n';
    case 'condition_rules_multi_block':
      final firstHalf = count ~/ 2;
      final secondHalf = count - firstHalf;
      final blockA = List<String>.filled(firstHalf, '    day mon').join('\n');
      final blockB = List<String>.filled(
        secondHalf,
        '    time 09:00 17:00',
      ).join('\n');
      return 'tdf 0.8.0\nlabel 000001OkD2 {\n  name "L"\n  condition {\n$blockA\n  }\n  condition {\n$blockB\n  }\n}\n';
    case 'deleted_records':
      final records = List<String>.generate(
        count,
        (i) => '  task ${i.toString().padLeft(6, '0')}OkD2 2026-11-01',
      ).join('\n');
      return 'tdf 0.8.0\ndeleted {\n  generation 1\n$records\n}\n';
    case 'history_raw_duplicates':
      final entries = List<String>.filled(
        count,
        '  history 2026-11-01 09:00:00 "Duplicate raw journal line"',
      ).join('\n');
      return 'tdf 0.8.0\ntask 000001OkD2 {\n  name "T"\n  created 2026-11-01\n$entries\n}\n';
    case _:
      throw StateError('Unsupported bounds template kind: $templateKind');
  }
}

Set<String> _collectSuiteRuleIds(Map<String, Object?> root) {
  final collected = <String>{};
  _collectRuleIdsFromValue(root, collected);
  return collected;
}

void _collectRuleIdsFromValue(Object? node, Set<String> target) {
  if (node is Map<Object?, Object?>) {
    for (final entry in node.entries) {
      if (entry.value case final List<Object?> listValue
          when entry.key == 'ruleIds' || entry.key == 'rules') {
        _copyStringElements(listValue, target);
      } else {
        _collectRuleIdsFromValue(entry.value, target);
      }
    }
    return;
  }
  if (node is List<Object?>) {
    for (final element in node) {
      _collectRuleIdsFromValue(element, target);
    }
  }
}

void _copyStringElements(List<Object?> list, Set<String> target) {
  for (final item in list) {
    if (item is String) {
      target.add(item);
    }
  }
}

int _countLfLines(Uint8List bytes) {
  var lines = 0;
  for (final byte in bytes) {
    if (byte == 0x0A) {
      lines++;
    }
  }
  return lines;
}

Set<String> _executeOperationalAndMetaRuleAssertions(TdfService tdfService) {
  final nowUtc = DateTime.utc(2026, 11, 16, 12, 0, 0);

  // TDF-ID-001 & TDF-MUT-003: Entity creation generates collision-free Base62 IDs, revisions, and queue entries.
  var board = TaskBoard.empty()
      .addLocation(
        'Office',
        latitude: 50.9787,
        longitude: 11.0328,
        radius: 150,
        currentDate: nowUtc,
      )
      .addLocation(
        'Datacenter',
        latitude: 51.0000,
        longitude: 11.0000,
        radius: 200,
        currentDate: nowUtc,
      )
      .addLabel('Ops', isScoped: true, color: '#2196F3', currentDate: nowUtc);
  final createdLoc = board.locations.first;
  final backupLoc = board.locations.last;
  final createdLabel = board.labels.single;
  expect(isValidLocationId(createdLoc.id), isTrue);
  expect(isValidLocationId(backupLoc.id), isTrue);
  expect(isValidLabelId(createdLabel.id), isTrue);

  board = board.updateLabel(
    createdLabel.id,
    conditions: <TaskCondition>[
      LocationTaskCondition(locationIds: <String>[backupLoc.id]),
    ],
    currentDate: nowUtc.add(const Duration(seconds: 1)),
  );
  board = board.addTask(
    'Scoped Ops Task',
    targetTier: TaskTier.planned,
    isPriority: true,
    labelIds: <String>[createdLabel.id],
    conditions: <TaskCondition>[
      LocationTaskCondition(locationIds: <String>[createdLoc.id]),
    ],
    currentDate: nowUtc.add(const Duration(seconds: 2)),
  );
  final createdTask = board.allTasks.single;
  expect(isValidTaskId(createdTask.id), isTrue);
  expect(board.queueTaskIds, contains(createdTask.id));

  // TDF-MUT-002: Monotonic revision advancement and 9999-12-31 23:59:59 overflow guard.
  expect(
    TaskItem.nextModifiedTimestamp(nowUtc, nowUtc),
    equals(nowUtc.add(const Duration(seconds: 1))),
  );
  expect(
    () => TaskItem.nextModifiedTimestamp(
      nowUtc,
      DateTime.utc(9999, 12, 31, 23, 59, 59),
    ),
    throwsA(
      isA<TdfException>().having(
        (error) => error.kind,
        'kind',
        TdfErrorKind.invalidTimestamp,
      ),
    ),
  );

  // TDF-MUT-009: Deleting a location referenced by both task and label inserts `location any` on the task;
  // deleting the sole `scoped` label evicts the open task from `queue` and strips `priority`.
  final afterLocDelete = board.deleteLocation(
    createdLoc.id,
    currentDate: nowUtc.add(const Duration(seconds: 3)),
  );
  expect(
    afterLocDelete.findTask(createdTask.id)?.conditions,
    equals(const <TaskCondition>[
      GroupResetTaskCondition(targetGroup: ConditionGroup.location),
    ]),
  );
  final afterScopedLabelDelete = afterLocDelete.deleteLabel(
    createdLabel.id,
    currentDate: nowUtc.add(const Duration(seconds: 4)),
  );
  expect(afterScopedLabelDelete.queueTaskIds, isNot(contains(createdTask.id)));
  expect(afterScopedLabelDelete.findTask(createdTask.id)?.isPriority, isFalse);

  // TDF-CLEAN-002 & TDF-PUB-001: Load preserves expired deferral; deferred sync preserves expired deferral;
  // finalStage sync strips expired deferral; candidate round-trips through TdfSerializer + TdfService.parse.
  const expiredDoc =
      'tdf 0.8.0\n\n'
      'task 8jKaCdOkD2 {\n'
      '    name      "Deferred cleanup check"\n'
      '    created   2026-11-01 08:00\n'
      '    modified  2026-11-01 08:00\n'
      '    suspended 2026-11-10 08:00:00 "Expired note"\n'
      '}\n';
  final loadedBoard = tdfService.parse(expiredDoc, evaluationTime: nowUtc);
  expect(loadedBoard.findTask('8jKaCdOkD2')?.suspendedAt, isNotNull);

  final deferredMerged = TaskBoardSync.merge(
    primary: loadedBoard,
    secondary: loadedBoard,
    baseline: loadedBoard,
    evaluationTime: nowUtc,
    cleanupMode: TdfCleanupMode.deferred,
  );
  expect(deferredMerged.findTask('8jKaCdOkD2')?.suspendedAt, isNotNull);

  final finalMerged = TaskBoardSync.merge(
    primary: loadedBoard,
    secondary: loadedBoard,
    baseline: loadedBoard,
    evaluationTime: nowUtc,
    cleanupMode: TdfCleanupMode.finalStage,
  );
  expect(finalMerged.findTask('8jKaCdOkD2')?.suspendedAt, isNull);
  final publishedCanonical = tdfService.serialize(finalMerged);
  expect(
    tdfService
        .parse(publishedCanonical, evaluationTime: nowUtc)
        .allTasks
        .length,
    equals(1),
  );

  // TDF-PUB-002: Host-local cooperative lock naming uses lowercase SHA-256 hex of canonical target path.
  const canonicalTargetPath = '/var/tmp/workspace/tasks.tdf';
  final targetPathHash = Sha256Service.hashHex(
    utf8.encode(canonicalTargetPath),
  );
  expect(targetPathHash.length, equals(64));
  expect('tdf-$targetPathHash.lock', startsWith('tdf-'));

  return const <String>{
    'TDF-META-001',
    'TDF-META-002',
    'TDF-CONF-001',
    'TDF-ID-001',
    'TDF-GRAM-002',
    'TDF-MUT-002',
    'TDF-CLEAN-002',
    'TDF-MUT-003',
    'TDF-MUT-009',
    'TDF-PUB-001',
    'TDF-PUB-002',
    'TDF-ERR-001',
    'TDF-VEC-001',
    'TDF-TRACE-001',
  };
}

Set<String> _extractAppendixA3RuleIds() {
  final specText = File(_specPath).readAsStringSync();
  final sectionStart = specText.indexOf('### A.3 Normative Rule ID Index');
  expect(sectionStart, greaterThan(0));
  final sectionEnd = specText.indexOf('## Appendix B:', sectionStart);
  final slice = sectionEnd > sectionStart
      ? specText.substring(sectionStart, sectionEnd)
      : specText.substring(sectionStart);
  final matches = _appendixA3RuleRowPattern.allMatches(slice);
  final ids = <String>{};
  for (final match in matches) {
    if (match.group(1) case final id?) {
      final added = ids.add(id);
      expect(added, isTrue, reason: 'Duplicate Rule ID "$id" in Appendix A.3');
    }
  }
  return ids;
}

String _formatUtcSeconds(DateTime instant) {
  final utc = instant.toUtc();
  final yyyy = utc.year.toString().padLeft(4, '0');
  final mm = utc.month.toString().padLeft(2, '0');
  final dd = utc.day.toString().padLeft(2, '0');
  final hh = utc.hour.toString().padLeft(2, '0');
  final min = utc.minute.toString().padLeft(2, '0');
  final ss = utc.second.toString().padLeft(2, '0');
  return '$yyyy-$mm-$dd $hh:$min:$ss';
}

Map<String, Object?> _labelToNormalizedJson(TdfLabel label) {
  return <String, Object?>{
    'id': label.id,
    'scoped': label.isScoped,
    'name': label.name,
    'color': label.color,
    'note': label.note,
    'modified': label.modifiedAt != null
        ? _formatUtcSeconds(label.modifiedAt ?? TdfLabel.defaultModifiedAt)
        : null,
    'links': <Map<String, Object?>>[
      for (final link in label.links)
        <String, Object?>{'title': link.title, 'uri': link.uri},
    ],
    'conditions': _normalizeConditionArgs(label.conditions),
  };
}

Map<String, Object?> _loadJsonMap(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'Missing JSON file: $path');
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  throw StateError('Expected top-level JSON object in $path');
}

Map<String, Object?> _locationToNormalizedJson(TdfLocation location) {
  return <String, Object?>{
    'id': location.id,
    'name': location.name,
    'note': location.note,
    'source': location.source,
    'latitude': location.latitudeText,
    'longitude': location.longitudeText,
    'radius': location.radiusText,
    'modified': location.modifiedAt != null
        ? _formatUtcSeconds(
            location.modifiedAt ?? TdfLocation.defaultModifiedAt,
          )
        : null,
  };
}

List<String> _normalizeConditionArgs(List<TaskCondition> conditions) {
  if (conditions.any((rule) => rule is GlobalResetTaskCondition)) {
    return const <String>['any'];
  }
  final dayArgs = <String>[];
  final timeArgs = <String>[];
  final locationArgs = <String>[];
  for (final condition in conditions) {
    _appendNormalizedConditionGroup(condition, dayArgs, timeArgs, locationArgs);
  }
  return <String>[...dayArgs, ...timeArgs, ...locationArgs];
}

TdfErrorKind _parseErrorKindByName(String rawName) {
  for (final kind in TdfErrorKind.values) {
    if (kind.name == rawName) {
      return kind;
    }
  }
  throw ArgumentError('Unknown TdfErrorKind name: $rawName');
}

bool _requireBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  throw StateError('Expected bool at "$key", got $value');
}

int _requireInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  throw StateError('Expected int at "$key", got $value');
}

Map<String, Object?> _requireMap(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  throw StateError('Expected Map at "$key", got $value');
}

List<Map<String, Object?>> _requireMapList(
  Map<String, Object?> map,
  String key,
) {
  final value = map[key];
  if (value is! List<Object?>) {
    throw StateError('Expected List at "$key", got $value');
  }
  final result = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is! Map<String, Object?>) {
      throw StateError('Expected Map element in "$key", got $item');
    }
    result.add(item);
  }
  return result;
}

String _requireString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String) {
    return value;
  }
  throw StateError('Expected String at "$key", got $value');
}

void _runBoundsFileCase(TdfService tdfService, Map<String, Object?> entry) {
  final caseId = _requireString(entry, 'id');
  final acceptPath = '$_boundsDir/${_requireString(entry, 'acceptFile')}';
  final rejectPath = '$_boundsDir/${_requireString(entry, 'rejectFile')}';
  final acceptBytes = File(acceptPath).readAsBytesSync();
  final rejectBytes = File(rejectPath).readAsBytesSync();

  final parsedBoard = tdfService.parseBytes(
    acceptBytes,
    timeZone: TdfTimeZoneContext.europeBerlin,
  );
  expect(
    tdfService.serialize(parsedBoard),
    isNotEmpty,
    reason: 'Bound accept fixture $caseId must parse and serialize cleanly',
  );
  expect(
    () => tdfService.parseBytes(
      rejectBytes,
      timeZone: TdfTimeZoneContext.europeBerlin,
    ),
    throwsA(
      isA<TdfException>().having(
        (error) => error.kind,
        'kind',
        TdfErrorKind.limitExceeded,
      ),
    ),
    reason: 'Bound reject fixture $caseId must fail with LimitExceeded',
  );
}

void _runBoundsTemplateCase(TdfService tdfService, Map<String, Object?> entry) {
  final caseId = _requireString(entry, 'id');
  final templateKind = _requireString(entry, 'templateKind');
  if (templateKind == 'queue_entries') {
    _runQueueEntriesBoundTemplate(tdfService, entry, caseId);
    return;
  }
  if (templateKind == 'full_capacity_canonical_task') {
    _runFullCapacityTaskTemplate(tdfService, caseId);
    return;
  }
  if (templateKind == 'serializer_output_line_overflow') {
    _runSerializerLineOverflowTemplate(tdfService, caseId);
    return;
  }
  if (templateKind == 'serializer_output_byte_overflow') {
    _runSerializerByteOverflowTemplate(tdfService, caseId);
    return;
  }
  final acceptN = _requireInt(entry, 'acceptCount');
  final rejectN = _requireInt(entry, 'rejectCount');
  final acceptDoc = _buildTemplateDocument(templateKind, acceptN);
  final rejectDoc = _buildTemplateDocument(templateKind, rejectN);

  expect(
    () => tdfService.parseBytes(utf8.encode(acceptDoc)),
    returnsNormally,
    reason: 'Template $caseId at exact N=$acceptN must succeed',
  );
  expect(
    () => tdfService.parseBytes(utf8.encode(rejectDoc)),
    throwsA(
      isA<TdfException>().having(
        (error) => error.kind,
        'kind',
        TdfErrorKind.limitExceeded,
      ),
    ),
    reason: 'Template $caseId at N+1=$rejectN must fail with LimitExceeded',
  );
}

void _runFullCapacityTaskTemplate(TdfService tdfService, String caseId) {
  final fixedUtc = DateTime.utc(2026, 11, 16, 8, 0, 0);
  final fullTask = TaskItem(
    id: 'fullCap001',
    title: 'Full-capacity canonical task (534 statements <= 1024)',
    note: 'Standing note',
    isCompleted: true,
    isPriority: true,
    createdAt: fixedUtc,
    completedAt: fixedUtc.add(const Duration(hours: 1)),
    modifiedAt: fixedUtc.add(const Duration(hours: 1)),
    completions: 3,
    repeatRule: const TaskRepeatRule(
      count: 1,
      unit: RepeatUnit.months,
      clock: TdfRepeatClock(hour: 9, minute: 0),
      leadDays: 5,
    ),
    labelIds: const <String>['4x9p2mOkD2'],
    dependencies: const <TdfTaskDependency>[
      TdfTaskDependency(taskId: '3nQp7ROkB8', requiredCompletion: 2),
    ],
    suspendedAt: fixedUtc.add(const Duration(days: 2)),
    suspendedNote: 'Deferral note',
    dueAt: fixedUtc.add(const Duration(days: 5)),
    dueAnchor: TdfLocalDateTime(2026, 11, 21, 9, 0, 0),
    isDuePassive: true,
    dueNote: 'Deadline note',
    origin: const TaskOrigin(
      namespace: 'https://jira.example.com',
      externalKey: 'FULL-534',
    ),
    links: List<TaskLink>.generate(
      maxTdfLinksPerTask,
      (i) => TaskLink(title: 'Link $i', uri: 'https://example.com/$i'),
    ),
    history: List<TaskHistoryEntry>.generate(
      maxTdfHistoryPerTask,
      (i) => TaskHistoryEntry(
        timestampUtc: fixedUtc.add(Duration(seconds: i)),
        text: 'Entry $i',
      ),
    ),
    conditions: <TaskCondition>[
      DayTaskCondition.fromWeekdays(const <int>[1, 2, 3]),
    ],
    subtasksAutoFinish: true,
    subtasks: const <SubtaskItem>[SubtaskItem(title: 'Step 1')],
  );
  expect(
    fullTask.canonicalDirectChildStatementCount,
    equals(534),
    reason: '$caseId must comprise exactly 534 direct child statements',
  );
  final board = TaskBoard(
    labels: const <TdfLabel>[TdfLabel(id: '4x9p2mOkD2', name: 'Home')],
    completed: <TaskItem>[fullTask],
  );
  final serialized = tdfService.serialize(board);
  expect(tdfService.parse(serialized).completed.single.history.length, 500);
}

TdfErrorKind _runParseInvalidFixture(
  TdfService tdfService,
  Map<String, Object?> fixture,
) {
  final id = _requireString(fixture, 'id');
  final filePath = '$_parseInvalidDir/${_requireString(fixture, 'file')}';
  final expectedKind = _parseErrorKindByName(
    _requireString(fixture, 'expectedError'),
  );
  final expectedLine = _requireInt(fixture, 'expectedLine');
  final rawSourceVersion = fixture['expectedSourceVersion'];
  final expectedSourceVersion = rawSourceVersion is String
      ? rawSourceVersion
      : null;
  final rawBytesOnly = _requireBool(fixture, 'rawBytesOnly');
  final bytes = File(filePath).readAsBytesSync();

  expect(
    () => tdfService.parseBytes(bytes),
    throwsA(
      isA<TdfException>()
          .having((error) => error.kind, 'kind', expectedKind)
          .having((error) => error.line, 'line', expectedLine)
          .having(
            (error) =>
                expectedSourceVersion == null ? null : error.sourceVersion,
            'sourceVersion',
            expectedSourceVersion,
          ),
    ),
    reason:
        'Invalid fixture $id must fail via parseBytes at line $expectedLine',
  );

  if (!rawBytesOnly) {
    final decodedText = utf8.decode(bytes);
    expect(
      () => tdfService.parse(decodedText),
      throwsA(
        isA<TdfException>()
            .having((error) => error.kind, 'kind', expectedKind)
            .having((error) => error.line, 'line', expectedLine),
      ),
      reason: 'Invalid fixture $id must fail via parse at line $expectedLine',
    );
  }
  return expectedKind;
}

void _runParseValidFixture(
  TdfService tdfService,
  Map<String, Object?> fixture,
) {
  final id = _requireString(fixture, 'id');
  final inputPath = '$_parseValidDir/${_requireString(fixture, 'inputFile')}';
  final canonicalPath =
      '$_parseValidDir/${_requireString(fixture, 'canonicalFile')}';
  final normalizedPath =
      '$_parseValidDir/${_requireString(fixture, 'normalizedFile')}';
  final expectedBytes = _requireInt(fixture, 'expectedCanonicalBytes');
  final expectedLines = _requireInt(fixture, 'expectedCanonicalLines');
  final expectedDigest = _requireString(fixture, 'canonicalSourceDigest');

  final inputBytes = File(inputPath).readAsBytesSync();
  final expectedCanonicalBytes = File(canonicalPath).readAsBytesSync();
  final expectedCanonicalText = utf8.decode(expectedCanonicalBytes);
  final expectedNormalized = _loadJsonMap(normalizedPath);

  final boardFromBytes = tdfService.parseBytes(
    inputBytes,
    timeZone: TdfTimeZoneContext.europeBerlin,
  );
  final boardFromString = tdfService.parse(
    utf8.decode(inputBytes),
    timeZone: TdfTimeZoneContext.europeBerlin,
  );
  expect(
    _boardToNormalizedJson(boardFromBytes),
    equals(expectedNormalized),
    reason: 'Normalized JSON mismatch on parseBytes for $id',
  );
  expect(
    _boardToNormalizedJson(boardFromString),
    equals(expectedNormalized),
    reason: 'Normalized JSON mismatch on parse for $id',
  );

  final serialized = tdfService.serialize(boardFromBytes);
  final serializedBytes = Uint8List.fromList(utf8.encode(serialized));
  expect(
    serialized,
    equals(expectedCanonicalText),
    reason: 'Canonical serialized text mismatch for $id',
  );
  expect(
    serializedBytes.length,
    equals(expectedBytes),
    reason: 'Canonical UTF-8 byte length mismatch for $id',
  );
  expect(
    _countLfLines(serializedBytes),
    equals(expectedLines),
    reason: 'Canonical LF line count mismatch for $id',
  );
  expect(
    Sha256Service.hashHex(serializedBytes),
    equals(expectedDigest),
    reason: 'Canonical SHA-256 sourceDigest mismatch for $id',
  );

  // Idempotence: serialize(parse(canonical)) == canonical
  final reparsed = tdfService.parseBytes(
    serializedBytes,
    timeZone: TdfTimeZoneContext.europeBerlin,
  );
  expect(
    tdfService.serialize(reparsed),
    equals(expectedCanonicalText),
    reason: 'Canonical output must be idempotent for $id',
  );
}

void _runQueueEntriesBoundTemplate(
  TdfService tdfService,
  Map<String, Object?> entry,
  String caseId,
) {
  final acceptCount = _requireInt(entry, 'acceptCount');
  final rejectCount = _requireInt(entry, 'rejectCount');
  final idsAccept = List<String>.generate(
    acceptCount,
    (i) => '${i.toString().padLeft(6, '0')}OkD2',
  );
  final idsReject = List<String>.generate(
    rejectCount,
    (i) => '${i.toString().padLeft(6, '0')}OkD2',
  );
  final fixedUtc = DateTime.utc(2026, 11, 16, 9, 0, 0);

  // Serializer enforces exact 4096 accept vs 4097 LimitExceeded:
  expect(
    tdfService.serialize(
      TaskBoard(
        queueBlock: TdfQueueBlock(modifiedAt: fixedUtc, taskIds: idsAccept),
      ),
    ),
    isNotEmpty,
    reason: '$caseId must serialize $acceptCount queue entries',
  );
  expect(
    () => tdfService.serialize(
      TaskBoard(
        queueBlock: TdfQueueBlock(modifiedAt: fixedUtc, taskIds: idsReject),
      ),
    ),
    throwsA(
      isA<TdfException>().having(
        (error) => error.kind,
        'kind',
        TdfErrorKind.limitExceeded,
      ),
    ),
    reason: '$caseId must reject $rejectCount queue entries on serialize',
  );

  // Parser enforces 4097 LimitExceeded at Step 2 while 4096 passes Step 2 into Step 4:
  final queueLines4096 = idsAccept.map((id) => '  task $id').join('\n');
  final queueLines4097 = idsReject.map((id) => '  task $id').join('\n');
  expect(
    () => tdfService.parse(
      'tdf 0.8.0\nqueue {\n  modified 2026-11-16 09:00:00\n$queueLines4096\n}\n',
    ),
    throwsA(
      isA<TdfException>().having(
        (error) => error.kind,
        'kind',
        TdfErrorKind.invalidQueueMembership,
      ),
    ),
  );
  expect(
    () => tdfService.parse(
      'tdf 0.8.0\nqueue {\n  modified 2026-11-16 09:00:00\n$queueLines4097\n}\n',
    ),
    throwsA(
      isA<TdfException>().having(
        (error) => error.kind,
        'kind',
        TdfErrorKind.limitExceeded,
      ),
    ),
  );
}

void _runSerializerByteOverflowTemplate(TdfService tdfService, String caseId) {
  final fixedUtc = DateTime.utc(2026, 11, 16, 9, 0, 0);
  final bigNote = 'n' * maxTdfNoteLength;
  final tasks = List<TaskItem>.generate(
    550,
    (i) => TaskItem(
      id: '${i.toString().padLeft(6, '0')}OkD2',
      title: 'Byte overflow task $i',
      note: bigNote,
      createdAt: fixedUtc,
    ),
  );
  expect(
    () => tdfService.serialize(TaskBoard(someday: tasks)),
    throwsA(
      isA<TdfException>().having(
        (error) => error.kind,
        'kind',
        TdfErrorKind.limitExceeded,
      ),
    ),
    reason: '$caseId must fail with LimitExceeded when output > 1 MiB',
  );
}

void _runSerializerLineOverflowTemplate(TdfService tdfService, String caseId) {
  final fixedUtc = DateTime.utc(2026, 11, 16, 9, 0, 0);
  final tasks = List<TaskItem>.generate(
    3500,
    (i) => TaskItem(
      id: '${i.toString().padLeft(6, '0')}OkD2',
      title: 'Line overflow task $i',
      createdAt: fixedUtc,
    ),
  );
  expect(
    () => tdfService.serialize(TaskBoard(someday: tasks)),
    throwsA(
      isA<TdfException>().having(
        (error) => error.kind,
        'kind',
        TdfErrorKind.limitExceeded,
      ),
    ),
    reason: '$caseId must fail with LimitExceeded when output > 16384 lines',
  );
}

Map<String, Object?> _taskToNormalizedJson(TaskItem task) {
  final blockedMap = <String, int>{
    for (final dep in task.dependencies) dep.taskId: dep.requiredCompletion,
  };
  Map<String, Object?>? suspendedJson;
  if (task.isSuspendedForever) {
    suspendedJson = <String, Object?>{
      'forever': true,
      'utc': null,
      'note': task.suspendedNote,
    };
  } else if (task.suspendedAt case final suspendedAt?) {
    suspendedJson = <String, Object?>{
      'forever': false,
      'utc': _formatUtcSeconds(suspendedAt),
      'note': task.suspendedNote,
    };
  }

  Map<String, Object?>? dueJson;
  if (task.dueAt case final dueAt?) {
    dueJson = <String, Object?>{
      'utc': _formatUtcSeconds(dueAt),
      'anchor': task.dueAnchor?.formatExplicitSeconds(),
      'passive': task.isDuePassive,
      'note': task.dueNote,
    };
  }

  Map<String, Object?>? originJson;
  if (task.origin case final origin?) {
    originJson = <String, Object?>{
      'namespace': origin.namespace,
      'externalKey': origin.externalKey,
    };
  }

  Map<String, Object?>? subtasksJson;
  if (task.subtasks.isNotEmpty) {
    subtasksJson = <String, Object?>{
      'autoFinish': task.subtasksAutoFinish,
      'steps': <Map<String, Object?>>[
        for (final step in task.subtasks)
          <String, Object?>{'completed': step.isCompleted, 'text': step.title},
      ],
    };
  }

  return <String, Object?>{
    'id': task.id,
    'priority': task.isPriority,
    'name': task.title,
    'note': task.note,
    'created': _formatUtcSeconds(task.createdAt),
    'finished': task.completedAt != null
        ? _formatUtcSeconds(task.completedAt ?? task.createdAt)
        : null,
    'modified': task.modifiedAt != null
        ? _formatUtcSeconds(task.modifiedAt ?? task.createdAt)
        : null,
    'completions': task.completions,
    'repeat': task.repeatRule?.toTdfDirectiveArgs(),
    'labels': List<String>.from(task.labelIds),
    'blocked': blockedMap,
    'suspended': suspendedJson,
    'due': dueJson,
    'origin': originJson,
    'links': <Map<String, Object?>>[
      for (final link in task.links)
        <String, Object?>{'title': link.title, 'uri': link.uri},
    ],
    'history': <Map<String, Object?>>[
      for (final entry in task.history)
        <String, Object?>{
          'timestamp': _formatUtcSeconds(entry.timestampUtc),
          'text': entry.text,
        },
    ],
    'conditions': _normalizeConditionArgs(task.conditions),
    'subtasks': subtasksJson,
  };
}

void _verifyDeclaredBoundConstants(Map<String, Object?> constants) {
  final expected = <String, int>{
    'MAX_FILE_BYTES': maxTdfFileBytes,
    'MAX_LINE_COUNT': maxTdfLineCount,
    'MAX_NESTING_DEPTH': maxTdfNestingDepth,
    'MAX_BLOCKS_PER_DOC': maxTdfBlocksPerDoc,
    'MAX_LOCATIONS': maxTdfLocations,
    'MAX_STMTS_PER_BLOCK': maxTdfStmtsPerBlock,
    'MAX_CONDITION_RULES_PER_ENTITY': maxTdfConditionRulesPerEntity,
    'MAX_LOCATION_REFS_PER_ENTITY': maxTdfLocationRefsPerEntity,
    'MAX_QUEUE_ENTRIES': maxTdfQueueEntries,
    'MAX_DELETED_RECORDS': maxTdfDeletedRecords,
    'MAX_SYNC_GENERATION': maxTdfSyncGeneration,
    'MAX_COMPLETIONS': maxTdfCompletions,
    'MAX_ARGS_PER_STMT': maxTdfArgsPerStmt,
    'MAX_TEXT_LENGTH': maxTdfTextLength,
    'MAX_NOTE_LENGTH': maxTdfNoteLength,
    'MAX_URI_LENGTH': maxTdfUriLength,
    'MAX_LINKS_PER_TASK': maxTdfLinksPerTask,
    'MAX_LINKS_PER_LABEL': maxTdfLinksPerLabel,
    'MAX_HISTORY_PER_TASK': maxTdfHistoryPerTask,
    'MAX_REPEAT_COUNT': maxTdfRepeatCount,
    'MAX_LOCATION_RADIUS': maxTdfLocationRadius,
    'MAX_NUMBER_LENGTH': maxTdfNumberLength,
    'DEFAULT_DUE_LEAD_SECONDS': defaultDueLeadSeconds,
  };
  expect(constants, equals(expected));
}
