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
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/settings_codec.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/services/app_logger.dart';

void main() {
  group('SettingsCodec Exhaustive Round-Trip & Secret Hygiene', () {
    test('round-trips every enum variant, 37 UTC offsets, 1-minute manual offset precision, and flags losslessly', () {
      expect(
        PersistedSettingsDocument.initial.schemaVersion,
        equals(SettingsCodec.currentSchemaVersion),
      );
      expect(
        PersistedSettingsDocument.initial.activeWorkspaceId,
        equals(AppWorkspace.defaultId),
      );
      expect(
        PersistedSettingsDocument.initial.workspaces,
        equals(const <AppWorkspace>[AppWorkspace.defaultWorkspace]),
      );

      final initialJson = SettingsCodec.encodeJson(
        PersistedSettingsDocument.initial,
      );
      expect(
        initialJson.endsWith('\n'),
        isTrue,
        reason: 'Encoded settings.json must end with a trailing newline',
      );
      final initialDecoded = SettingsCodec.decodeJsonBytes(
        utf8.encode(initialJson),
      );
      expect(
        initialDecoded.warnings,
        isEmpty,
        reason: 'Canonical initial document must decode with zero warnings',
      );
      expect(
        initialDecoded.document,
        equals(PersistedSettingsDocument.initial),
      );

      // Exhaustive enum coverage across all variants:
      for (final storageMode in StorageMode.values) {
        for (final language in AppLanguage.values) {
          for (final themeMode in AppThemeMode.values) {
            for (final palette in AppThemePalette.values) {
              for (final timeZoneMode in AppTimeZoneMode.values) {
                for (final dueLeadWindow in DueLeadWindow.values) {
                  for (final logLevel in LogLevel.configurableLevels) {
                    for (final logStorageMode in StorageMode.values) {
                      final workspace = AppWorkspace(
                        id: 'tasks',
                        name: 'Tasks',
                        config: WebDavConfig(
                          serverUrl: 'https://cloud.example.com',
                          username: 'alice',
                          filePath: 'tasks.tdf',
                          localFilePath: 'tasks.tdf',
                          storageMode: storageMode,
                          language: language,
                          themeMode: themeMode,
                          themePalette: palette,
                          locationEnabled:
                              timeZoneMode == AppTimeZoneMode.manual,
                          timeZoneMode: timeZoneMode,
                          manualTimeZoneOffsetMinutes: 63,
                          diagnosticsEnabled: logLevel == LogLevel.debug,
                          logLevel: logLevel,
                          logStorageMode: logStorageMode,
                          localWatchEnabled: palette == AppThemePalette.calm,
                          dueLeadWindow: dueLeadWindow,
                        ),
                      );
                      final document = PersistedSettingsDocument(
                        schemaVersion: SettingsCodec.currentSchemaVersion,
                        activeWorkspaceId: 'tasks',
                        workspaces: <AppWorkspace>[workspace],
                        passwordStoredWorkspaceIds: const <String>{'tasks'},
                      );
                      final encoded = SettingsCodec.encodeJson(document);
                      final result = SettingsCodec.decodeJsonBytes(
                        utf8.encode(encoded),
                      );
                      expect(
                        result.warnings,
                        isEmpty,
                        reason:
                            'Valid combination (${storageMode.name}/${language.name}/${dueLeadWindow.name}/${logLevel.label}/${logStorageMode.name}) must produce zero warnings',
                      );
                      expect(
                        result.document,
                        equals(document),
                        reason:
                            'Round-trip document must preserve exact config including +63 min offset with logStorageMode=${logStorageMode.name}',
                      );
                    }
                  }
                }
              }
            }
          }
        }
      }

      // All 37 standard UTC offsets plus 1-minute precision:
      for (final offset in <int>[
        ...WebDavConfig.supportedUtcOffsetMinutes,
        -719,
        -1,
        1,
        63,
        839,
      ]) {
        final workspace = AppWorkspace(
          id: 'tz',
          name: 'TimeZone',
          config: WebDavConfig(
            localFilePath: 'tz.tdf',
            filePath: 'tz.tdf',
            timeZoneMode: AppTimeZoneMode.manual,
            manualTimeZoneOffsetMinutes: offset,
            logStorageMode: StorageMode.both,
          ),
        );
        final doc = PersistedSettingsDocument(
          schemaVersion: SettingsCodec.currentSchemaVersion,
          activeWorkspaceId: 'tz',
          workspaces: <AppWorkspace>[workspace],
        );
        final decoded = SettingsCodec.decodeJsonBytes(
          utf8.encode(SettingsCodec.encodeJson(doc)),
        );
        expect(
          decoded.document.workspaces.first.config.manualTimeZoneOffsetMinutes,
          equals(offset),
          reason: 'UTC offset $offset minutes must survive JSON round-trip',
        );
      }
    });

    test('never serializes passwords even when WebDavConfig.password or unknownWorkspaceFieldsById contains password', () {
      const secret = 'SuperSecretPassword!@#\$%^&*()';
      const workspace = AppWorkspace(
        id: 'work',
        name: 'Work',
        config: WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: secret,
          localFilePath: 'work.tdf',
          filePath: 'work.tdf',
          storageMode: StorageMode.both,
        ),
      );
      final document = PersistedSettingsDocument(
        schemaVersion: SettingsCodec.currentSchemaVersion,
        activeWorkspaceId: 'work',
        workspaces: const <AppWorkspace>[workspace],
        passwordStoredWorkspaceIds: const <String>{'work'},
        unknownWorkspaceFieldsById: const <String, Map<String, Object?>>{
          'work': <String, Object?>{
            'password': 'leaked-unknown-password',
            'futureFeatureFlag': true,
          },
        },
      );

      final encoded = SettingsCodec.encodeJson(document);
      expect(
        encoded.contains(secret),
        isFalse,
        reason:
            'Encoded settings.json must never contain WebDavConfig.password',
      );
      expect(
        encoded.contains('leaked-unknown-password'),
        isFalse,
        reason: 'Encoded settings.json must strip accidental password key from unknownWorkspaceFieldsById',
      );
      expect(
        encoded.contains('"password"'),
        isFalse,
        reason:
            'Encoded settings.json must never emit a password JSON property',
      );
      expect(
        encoded.contains('"hasWebDavPassword": true'),
        isTrue,
        reason: 'Encoded settings.json must persist non-secret hasWebDavPassword flag',
      );
      expect(
        encoded.contains('"futureFeatureFlag": true'),
        isTrue,
        reason: 'Non-secret unknown workspace keys must still be preserved',
      );
    });

    test('preserves unknown root and workspace fields up to maxJsonNestingDepth and omits deeper or non-compliant values', () {
      Object buildNestedList(int depth) {
        Object current = 'leaf';
        for (var i = 0; i < depth; i++) {
          current = <Object?>[current];
        }
        return current;
      }

      final payload = <String, Object?>{
        'schemaVersion': 1,
        'activeWorkspaceId': 'tasks',
        'futureRootScalar': 'v2-feature',
        'futureRootNested': buildNestedList(14),
        'futureRootTooDeep': buildNestedList(20),
        'workspaces': <Object?>[
          <String, Object?>{
            'id': 'tasks',
            'name': 'Tasks',
            'storageMode': 'local',
            'localFilePath': 'tasks.tdf',
            'filePath': 'tasks.tdf',
            'futureWsObj': <String, Object?>{
              'enabled': true,
              'count': 42,
              'ratio': 0.5,
              'tags': <Object?>['a', 'b', null],
            },
            'futureWsTooDeep': buildNestedList(18),
            'password': 'should-never-be-kept-as-unknown',
          },
        ],
      };

      final decoded = SettingsCodec.decodeJsonBytes(
        utf8.encode(jsonEncode(payload)),
      );
      expect(
        decoded.document.unknownRootFields['futureRootScalar'],
        equals('v2-feature'),
      );
      expect(
        decoded.document.unknownRootFields.containsKey('futureRootNested'),
        isTrue,
        reason:
            'Unknown root field within maxJsonNestingDepth must be preserved',
      );
      expect(
        decoded.document.unknownRootFields.containsKey('futureRootTooDeep'),
        isFalse,
        reason:
            'Unknown root field exceeding maxJsonNestingDepth must be omitted',
      );
      expect(
        decoded.document.unknownWorkspaceFieldsById['tasks']?['futureWsObj'],
        isA<Map<String, Object?>>(),
      );
      expect(
        decoded.document.unknownWorkspaceFieldsById['tasks']?.containsKey(
          'futureWsTooDeep',
        ),
        isFalse,
        reason: 'Unknown workspace field exceeding maxJsonNestingDepth must be omitted',
      );
      expect(
        decoded.document.unknownWorkspaceFieldsById['tasks']?.containsKey(
          'password',
        ),
        isFalse,
        reason: 'Any legacy/stray password property must never be retained in unknownWorkspaceFieldsById',
      );
      expect(
        decoded.warnings.map((warning) => warning.field),
        containsAll(<String>['futureRootTooDeep', 'futureWsTooDeep']),
        reason:
            'Dropped over-deep unknown fields must emit SettingsDecodeWarning',
      );

      final reEncoded = SettingsCodec.encodeJson(decoded.document);
      final reDecoded = SettingsCodec.decodeJsonBytes(utf8.encode(reEncoded));
      expect(
        reDecoded.document.unknownRootFields,
        equals(decoded.document.unknownRootFields),
        reason: 'Unknown root fields must survive encode/decode round-trip',
      );
      expect(
        reDecoded.document.unknownWorkspaceFieldsById,
        equals(decoded.document.unknownWorkspaceFieldsById),
        reason:
            'Unknown workspace fields must survive encode/decode round-trip',
      );
      expect(
        reDecoded.warnings,
        isEmpty,
        reason: 'Re-encoded sanitized document must decode with zero warnings',
      );
    });
  });

  group('SettingsCodec Resilient Per-Field Decoding & Bounds', () {
    test('falls back per-field with warnings on invalid enums, crash logLevel, wrong types, out-of-range offsets, and invalid activeWorkspaceId', () {
      final rawJson = <String, Object?>{
        'schemaVersion': 1,
        'activeWorkspaceId': 'nonexistent',
        'workspaces': <Object?>[
          <String, Object?>{
            'id': 'tasks',
            'name': 'Tasks',
            'storageMode': 'ftp',
            'localFilePath': '',
            'filePath': 123,
            'serverUrl': 999,
            'username': false,
            'hasWebDavPassword': 'yes',
            'language': 'klingon',
            'themeMode': 'ultraviolet',
            'themePalette': 'rainbow',
            'locationEnabled': 'true',
            'timeZoneMode': 'mars',
            'manualTimeZoneOffsetMinutes': 9999,
            'diagnosticsEnabled': 1,
            'logLevel': 'crash',
            'logStorageMode': 's3',
            'localWatchEnabled': 'no',
            'dueLeadWindow': 'years10',
          },
        ],
      };

      final result = SettingsCodec.decodeJsonBytes(
        utf8.encode(jsonEncode(rawJson)),
      );
      expect(result.document.activeWorkspaceId, equals('tasks'));
      expect(result.document.workspaces, hasLength(1));
      final config = result.document.workspaces.first.config;
      expect(config.storageMode, equals(StorageMode.local));
      expect(config.localFilePath, equals(AppWorkspace.defaultFileName));
      expect(config.filePath, equals(AppWorkspace.defaultFileName));
      expect(config.serverUrl, isEmpty);
      expect(config.username, isEmpty);
      expect(result.document.passwordStoredWorkspaceIds, isEmpty);
      expect(config.language, equals(AppLanguage.system));
      expect(config.themeMode, equals(AppThemeMode.system));
      expect(config.themePalette, equals(AppThemePalette.calm));
      expect(config.locationEnabled, isFalse);
      expect(config.timeZoneMode, equals(AppTimeZoneMode.automatic));
      expect(config.manualTimeZoneOffsetMinutes, equals(0));
      expect(config.diagnosticsEnabled, isFalse);
      expect(config.logLevel, equals(LogLevel.info));
      expect(config.logStorageMode, equals(StorageMode.local));
      expect(config.localWatchEnabled, isTrue);
      expect(config.dueLeadWindow, equals(DueLeadWindow.hours24));

      final warnedFields = result.warnings.map((w) => w.field).toSet();
      expect(
        warnedFields,
        containsAll(<String>[
          'activeWorkspaceId',
          'storageMode',
          'localFilePath',
          'filePath',
          'serverUrl',
          'username',
          'hasWebDavPassword',
          'language',
          'themeMode',
          'themePalette',
          'locationEnabled',
          'timeZoneMode',
          'manualTimeZoneOffsetMinutes',
          'diagnosticsEnabled',
          'logLevel',
          'logStorageMode',
          'localWatchEnabled',
          'dueLeadWindow',
        ]),
        reason: 'Every invalid field must emit a SettingsDecodeWarning',
      );

      // Legacy "slate" and "navy" tokens migrate silently to calm with zero warnings:
      for (final legacyToken in const <String>['slate', 'navy']) {
        final legacyJson = <String, Object?>{
          'schemaVersion': 1,
          'activeWorkspaceId': 'tasks',
          'workspaces': <Object?>[
            <String, Object?>{
              'id': 'tasks',
              'name': 'Tasks',
              'localFilePath': 'tasks.tdf',
              'filePath': 'tasks.tdf',
              'themePalette': legacyToken,
            },
          ],
        };
        final migrated = SettingsCodec.decodeJsonBytes(
          utf8.encode(jsonEncode(legacyJson)),
        );
        expect(
          migrated.warnings,
          isEmpty,
          reason:
              'Legacy themePalette "$legacyToken" must migrate with zero warnings',
        );
        expect(
          migrated.document.workspaces.single.config.themePalette,
          equals(AppThemePalette.calm),
          reason: 'Legacy themePalette "$legacyToken" must decode to calm',
        );
      }
    });

    test('skips malformed or colliding workspace entries when at least one valid workspace remains, and throws when zero remain', () {
      final mixedJson = <String, Object?>{
        'schemaVersion': 1,
        'activeWorkspaceId': 'valid_one',
        'workspaces': <Object?>[
          'not-an-object',
          <String, Object?>{'id': '', 'name': 'Missing Id'},
          <String, Object?>{'id': 'bad\nid', 'name': 'Control Id'},
          <String, Object?>{
            'id': 'valid_one',
            'name': 'Valid One',
            'localFilePath': 'valid_one.tdf',
            'filePath': 'valid_one.tdf',
          },
          <String, Object?>{
            'id': 'valid_one',
            'name': 'Duplicate Id',
            'localFilePath': 'dup_id.tdf',
            'filePath': 'dup_id.tdf',
          },
          <String, Object?>{
            'id': 'dup_name',
            'name': 'valid one',
            'localFilePath': 'dup_name.tdf',
            'filePath': 'dup_name.tdf',
          },
          <String, Object?>{
            'id': 'dup_path',
            'name': 'Duplicate Path',
            'localFilePath': 'valid_one.tdf',
            'filePath': 'other.tdf',
          },
          <String, Object?>{
            'id': 'traversal_path',
            'name': 'Traversal',
            'localFilePath': '../escape.tdf',
            'filePath': 'escape.tdf',
          },
        ],
      };

      final decoded = SettingsCodec.decodeJsonBytes(
        utf8.encode(jsonEncode(mixedJson)),
      );
      expect(decoded.document.workspaces, hasLength(1));
      expect(decoded.document.workspaces.first.id, equals('valid_one'));
      expect(
        decoded.warnings.length,
        greaterThanOrEqualTo(7),
        reason: 'Each skipped malformed/colliding workspace entry must emit a warning',
      );

      final zeroValidJson = <String, Object?>{
        'schemaVersion': 1,
        'activeWorkspaceId': 'bad',
        'workspaces': <Object?>[
          <String, Object?>{
            'id': 'bad',
            'name': 'Bad',
            'localFilePath': '../escape.tdf',
            'filePath': 'escape.tdf',
          },
        ],
      };
      expect(
        () => SettingsCodec.decodeJsonBytes(
          utf8.encode(jsonEncode(zeroValidJson)),
        ),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.corruptSettingsPayload,
          ),
        ),
        reason:
            'Zero surviving valid workspaces must throw corruptSettingsPayload',
      );
    });

    test('enforces schemaVersion gating, workspace count limits, byte bounds, UTF-8 validity, and delimiter injection safety', () {
      // Unsupported future schemaVersion > 1:
      final futureSchemaBytes = utf8.encode(
        jsonEncode(<String, Object?>{
          'schemaVersion': 2,
          'activeWorkspaceId': 'tasks',
          'workspaces': <Object?>[],
        }),
      );
      expect(
        () => SettingsCodec.decodeJsonBytes(futureSchemaBytes),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.unsupportedSettingsSchemaVersion,
          ),
        ),
        reason: 'schemaVersion > 1 must throw unsupportedSettingsSchemaVersion',
      );

      // Corrupt schemaVersion values and malformed payloads:
      final corruptPayloads = <List<int>>[
        <int>[],
        <int>[0xFF, 0xFE, 0xFD],
        utf8.encode('{truncated'),
        utf8.encode('[]'),
        utf8.encode('"scalar"'),
        utf8.encode(jsonEncode(<String, Object?>{'workspaces': <Object?>[]})),
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': 0,
            'workspaces': <Object?>[],
          }),
        ),
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': -1,
            'workspaces': <Object?>[],
          }),
        ),
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': '1',
            'workspaces': <Object?>[],
          }),
        ),
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'workspaces': 'not-a-list',
          }),
        ),
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'workspaces': <Object?>[],
          }),
        ),
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'activeWorkspaceId': 'ws_0',
            'workspaces': <Object?>[
              for (var i = 0; i <= AppWorkspace.maxWorkspaces; i++)
                <String, Object?>{
                  'id': 'ws_$i',
                  'name': 'Workspace $i',
                  'localFilePath': 'ws_$i.tdf',
                  'filePath': 'ws_$i.tdf',
                },
            ],
          }),
        ),
        Uint8List(SettingsCodec.maxJsonBytes + 1),
      ];

      for (var i = 0; i < corruptPayloads.length; i++) {
        expect(
          () => SettingsCodec.decodeJsonBytes(corruptPayloads[i]),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.corruptSettingsPayload,
            ),
          ),
          reason: 'Corrupt payload case #$i must throw corruptSettingsPayload',
        );
      }

      // Exact maxWorkspaces (32) succeeds:
      final thirtyTwoDoc = PersistedSettingsDocument(
        schemaVersion: SettingsCodec.currentSchemaVersion,
        activeWorkspaceId: 'ws_31',
        workspaces: <AppWorkspace>[
          for (var i = 0; i < AppWorkspace.maxWorkspaces; i++)
            AppWorkspace(
              id: 'ws_$i',
              name: 'Workspace $i',
              config: WebDavConfig(
                localFilePath: 'ws_$i.tdf',
                filePath: 'ws_$i.tdf',
              ),
            ),
        ],
      );
      final decoded32 = SettingsCodec.decodeJsonBytes(
        utf8.encode(SettingsCodec.encodeJson(thirtyTwoDoc)),
      );
      expect(decoded32.document.workspaces, hasLength(32));
      expect(decoded32.document.activeWorkspaceId, equals('ws_31'));

      // Exact maxJsonBytes boundary (262144 passes, 262145 throws):
      final baseJson = SettingsCodec.encodeJson(
        PersistedSettingsDocument.initial,
      );
      final baseLength = utf8.encode(baseJson).length;
      final paddedExact = utf8.encode(
        '${' ' * (SettingsCodec.maxJsonBytes - baseLength)}$baseJson',
      );
      expect(paddedExact.length, equals(SettingsCodec.maxJsonBytes));
      expect(
        SettingsCodec.decodeJsonBytes(paddedExact).document,
        equals(PersistedSettingsDocument.initial),
        reason: 'Exact maxJsonBytes (262144) payload must decode cleanly',
      );
      final paddedOver = Uint8List.fromList(<int>[...paddedExact, 0x20]);
      expect(
        () => SettingsCodec.decodeJsonBytes(paddedOver),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.corruptSettingsPayload,
          ),
        ),
        reason: 'maxJsonBytes + 1 (262145) payload must throw corruptSettingsPayload',
      );

      // encodeJson enforces maxJsonBytes limit:
      final oversizedDoc = PersistedSettingsDocument(
        schemaVersion: SettingsCodec.currentSchemaVersion,
        activeWorkspaceId: AppWorkspace.defaultId,
        workspaces: const <AppWorkspace>[AppWorkspace.defaultWorkspace],
        unknownRootFields: <String, Object?>{
          'huge': 'X' * SettingsCodec.maxJsonBytes,
        },
      );
      expect(
        () => SettingsCodec.encodeJson(oversizedDoc),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.corruptSettingsPayload,
          ),
        ),
        reason: 'Encoding a document exceeding maxJsonBytes must throw corruptSettingsPayload',
      );

      // Delimiter & special character safety (quotes, backslashes, #, braces, Unicode):
      const specialWorkspace = AppWorkspace(
        id: 'special',
        name: r'Work "Quotes" \ {Braces} # Comment ÄÖÜß',
        config: WebDavConfig(
          serverUrl: 'https://cloud.example.com/dav/team',
          username: r'user\"name#1',
          localFilePath: 'special.tdf',
          filePath: 'special.tdf',
          storageMode: StorageMode.both,
        ),
      );
      final specialDoc = PersistedSettingsDocument(
        schemaVersion: SettingsCodec.currentSchemaVersion,
        activeWorkspaceId: 'special',
        workspaces: const <AppWorkspace>[specialWorkspace],
      );
      final specialDecoded = SettingsCodec.decodeJsonBytes(
        utf8.encode(SettingsCodec.encodeJson(specialDoc)),
      );
      expect(specialDecoded.warnings, isEmpty);
      expect(specialDecoded.document, equals(specialDoc));
    });

    test('passes explicit storageMode even when serverUrl/username are populated and storageMode is local', () {
      final rawJson = <String, Object?>{
        'schemaVersion': 1,
        'activeWorkspaceId': 'tasks',
        'workspaces': <Object?>[
          <String, Object?>{
            'id': 'tasks',
            'name': 'Tasks',
            'storageMode': 'local',
            'serverUrl': '  https://cloud.example.com  ',
            'username': '  alice  ',
            'localFilePath': 'tasks.tdf',
            'filePath': 'tasks.tdf',
          },
        ],
      };

      final decoded = SettingsCodec.decodeJsonBytes(
        utf8.encode(jsonEncode(rawJson)),
      );
      final config = decoded.document.workspaces.first.config;
      expect(config.storageMode, equals(StorageMode.local));
      expect(config.serverUrl, equals('https://cloud.example.com'));
      expect(config.username, equals('alice'));
    });
  });
}
