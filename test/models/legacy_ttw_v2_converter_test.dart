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
import 'package:tiertask/models/legacy_ttw_v2_converter.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/services/app_logger.dart';

/// Test-only TTW v2 binary encoder mirroring pre-0.4.0 wire format for fixture generation.
Uint8List _encodeTestTtwV2(
  List<AppWorkspace> workspaces, {
  required String activeId,
}) {
  var activeIndex = 0;
  final builder = BytesBuilder(copy: false)
    ..add(<int>[0x54, 0x54, 0x57, 0x02, workspaces.length, 0]);
  for (var i = 0; i < workspaces.length; i++) {
    if (workspaces[i].id == activeId) {
      activeIndex = i;
    }
    _appendTestTtwV2Record(builder, workspaces[i]);
  }
  final output = builder.toBytes();
  output[5] = activeIndex;
  return output;
}

void _appendTestTtwV2Record(BytesBuilder builder, AppWorkspace workspace) {
  final config = workspace.config;
  final storageId = switch (config.storageMode) {
    StorageMode.local => 0,
    StorageMode.webdav => 1,
    StorageMode.both => 2,
  };
  final langId = switch (config.language) {
    AppLanguage.system => 0,
    AppLanguage.english => 1,
    AppLanguage.german => 2,
  };
  final themeId = switch (config.themeMode) {
    AppThemeMode.system => 0,
    AppThemeMode.light => 1,
    AppThemeMode.dark => 2,
  };
  final paletteId = switch (config.themePalette) {
    AppThemePalette.calm => 0,
    AppThemePalette.plumUmber => 1,
  };
  final tzId = switch (config.timeZoneMode) {
    AppTimeZoneMode.automatic => 0,
    AppTimeZoneMode.manual => 1,
  };
  final dueLeadId = switch (config.dueLeadWindow) {
    DueLeadWindow.off => 0,
    DueLeadWindow.atDue => 1,
    DueLeadWindow.hours12 => 2,
    DueLeadWindow.hours24 => 3,
    DueLeadWindow.hours48 => 4,
    DueLeadWindow.days7 => 5,
  };
  final logLevelBits = switch (config.logLevel) {
    LogLevel.debug => 1,
    LogLevel.info => 0,
    LogLevel.warn => 2,
    LogLevel.error || LogLevel.crash => 3,
  };

  final int lowFlags;
  if (config.localWatchEnabled) {
    lowFlags =
        (storageId & 0x03) | ((langId & 0x03) << 2) | ((themeId & 0x03) << 4);
  } else {
    final comboIndex = storageId + (langId * 3) + (themeId * 9);
    if (comboIndex < 16) {
      lowFlags = 0x03 | (comboIndex << 2);
    } else {
      final rem = comboIndex - 16;
      lowFlags = (rem % 3) | 0x0C | ((rem ~/ 3) << 4);
    }
  }
  final remoteLogFlag = config.logStorageMode == StorageMode.local ? 0 : 1;
  builder.addByte(lowFlags | ((paletteId & 0x01) << 6) | (remoteLogFlag << 7));

  for (final field in <String>[
    workspace.id.trim(),
    workspace.name.trim(),
    config.serverUrl.trim(),
    config.username.trim(),
    config.password,
    config.filePath.trim(),
    config.localFilePath.trim(),
  ]) {
    final encoded = utf8.encode(field);
    builder
      ..addByte((encoded.length >> 8) & 0xFF)
      ..addByte(encoded.length & 0xFF)
      ..add(encoded);
  }

  final shifted =
      config.manualTimeZoneOffsetMinutes - WebDavConfig.minUtcOffsetMinutes;
  final clamped = shifted < 0 ? 0 : (shifted > 1560 ? 1560 : shifted);
  final offsetField = config.logStorageMode == StorageMode.both
      ? 1561 + (clamped ~/ 5)
      : clamped;
  final tzWord =
      ((tzId & 0x01) << 15) |
      ((config.locationEnabled ? 1 : 0) << 14) |
      ((config.diagnosticsEnabled ? 1 : 0) << 13) |
      ((logLevelBits & 0x03) << 11) |
      (offsetField & 0x07FF);
  builder
    ..addByte((tzWord >> 8) & 0xFF)
    ..addByte(tzWord & 0xFF)
    ..addByte(dueLeadId & 0xFF);
}

Uint8List _buildRawRecord({
  int flags = 0,
  String id = 'tasks',
  String name = 'Tasks',
  String serverUrl = '',
  String username = '',
  String password = '',
  String filePath = 'tasks.tdf',
  String localFilePath = 'tasks.tdf',
  int dueLeadByte = 3,
}) {
  final builder = BytesBuilder(copy: false)..addByte(flags);
  for (final field in <String>[
    id,
    name,
    serverUrl,
    username,
    password,
    filePath,
    localFilePath,
  ]) {
    final encoded = utf8.encode(field);
    builder
      ..addByte((encoded.length >> 8) & 0xFF)
      ..addByte(encoded.length & 0xFF)
      ..add(encoded);
  }
  builder
    ..addByte(0x02)
    ..addByte(0xD0)
    ..addByte(dueLeadByte);
  return builder.toBytes();
}

void main() {
  group('LegacyTtwV2Converter Read-Only Decoding', () {
    test('decodes hardcoded golden 0.3.0 TTW\\x02 default workspace vector losslessly', () {
      // Canonical 52-byte 0.3.0 TTW\x02 payload for AppWorkspace.defaultWorkspace:
      final goldenDefaultV2 = <int>[
        0x54, 0x54, 0x57, 0x02, 0x01, 0x00, // TTW\x02, count=1, activeIndex=0
        0x00, // flags: local, system, system, slate, localWatch=true, localLog
        0x00, 0x05, 0x74, 0x61, 0x73, 0x6B, 0x73, // "tasks"
        0x00, 0x05, 0x54, 0x61, 0x73, 0x6B, 0x73, // "Tasks"
        0x00, 0x00, // serverUrl ""
        0x00, 0x00, // username ""
        0x00, 0x00, // password ""
        0x00,
        0x09,
        0x74,
        0x61,
        0x73,
        0x6B,
        0x73,
        0x2E,
        0x74,
        0x64,
        0x66, // "tasks.tdf"
        0x00,
        0x09,
        0x74,
        0x61,
        0x73,
        0x6B,
        0x73,
        0x2E,
        0x74,
        0x64,
        0x66, // "tasks.tdf"
        0x02, 0xD0, // tzWord: auto, loc=false, diag=false, info, offset=0 (720)
        0x03, // dueLeadWindow: hours24 (3)
      ];
      expect(goldenDefaultV2.length, equals(52));

      final decoded = LegacyTtwV2Converter.decodeTtwV2Bytes(goldenDefaultV2);
      expect(decoded.activeId, equals(AppWorkspace.defaultId));
      expect(
        decoded.workspaces,
        equals(const <AppWorkspace>[AppWorkspace.defaultWorkspace]),
      );
    });

    test('decodes every TTW\\x02 flag, enum, UTC offset, logStorageMode, Unicode name, special-character password, and 32-workspace vector', () {
      final configs = <WebDavConfig>[
        for (final watchEnabled in <bool>[true, false])
          for (final storageMode in StorageMode.values)
            for (final language in AppLanguage.values)
              for (final themeMode in AppThemeMode.values)
                for (final palette in AppThemePalette.values)
                  for (final logMode in StorageMode.values)
                    for (final logLevel in LogLevel.configurableLevels)
                      WebDavConfig(
                        storageMode: storageMode,
                        language: language,
                        themeMode: themeMode,
                        themePalette: palette,
                        localWatchEnabled: watchEnabled,
                        logStorageMode: logMode,
                        logLevel: logLevel,
                        diagnosticsEnabled: !watchEnabled,
                        locationEnabled: palette == AppThemePalette.plumUmber,
                        dueLeadWindow:
                            DueLeadWindow.values[(storageMode.index +
                                    language.index +
                                    themeMode.index) %
                                DueLeadWindow.values.length],
                      ),
      ];

      for (final config in configs) {
        final workspace = AppWorkspace.defaultWorkspace.copyWith(
          config: config,
        );
        final bytes = _encodeTestTtwV2(<AppWorkspace>[
          workspace,
        ], activeId: 'tasks');
        final decoded = LegacyTtwV2Converter.decodeTtwV2Bytes(bytes);
        expect(
          decoded.workspaces.single.config,
          equals(config.copyWith(themePalette: AppThemePalette.calm)),
          reason:
              'TTW v2 decode mismatch (legacy palette IDs 0 and 1 must map to calm) for watch=${config.localWatchEnabled}, '
              'storage=${config.storageMode.name}, lang=${config.language.name}, '
              'theme=${config.themeMode.name}, palette=${config.themePalette.name}, '
              'logMode=${config.logStorageMode.name}, dueLead=${config.dueLeadWindow.name}',
        );
      }

      // All 37 standard UTC offsets across all logStorageMode variants:
      for (final logMode in StorageMode.values) {
        for (final offset in WebDavConfig.supportedUtcOffsetMinutes) {
          final workspace = AppWorkspace(
            id: 'tz',
            name: 'Zeit ÄÖÜß',
            config: WebDavConfig(
              serverUrl: 'https://cloud.example.com',
              username: 'stefan',
              password: r'p"a\\s$w0rd!äöü',
              localFilePath: 'tz.tdf',
              filePath: 'tz.tdf',
              timeZoneMode: AppTimeZoneMode.manual,
              manualTimeZoneOffsetMinutes: offset,
              logStorageMode: logMode,
              diagnosticsEnabled: true,
              logLevel: LogLevel.warn,
            ),
          );
          final bytes = _encodeTestTtwV2(<AppWorkspace>[
            workspace,
          ], activeId: 'tz');
          final decoded = LegacyTtwV2Converter.decodeTtwV2Bytes(bytes);
          expect(
            decoded.workspaces.single,
            equals(workspace),
            reason:
                'TTW v2 decode must preserve offset=$offset, logMode=${logMode.name}, Unicode name, and special password',
          );
        }
      }

      // 32-workspace multi-record payload:
      final maxWorkspacesList = <AppWorkspace>[
        for (var i = 0; i < AppWorkspace.maxWorkspaces; i++)
          AppWorkspace(
            id: 'ws_$i',
            name: 'Workspace $i',
            config: WebDavConfig(
              localFilePath: 'ws_$i.tdf',
              filePath: 'ws_$i.tdf',
              dueLeadWindow:
                  DueLeadWindow.values[i % DueLeadWindow.values.length],
            ),
          ),
      ];
      final multiBytes = _encodeTestTtwV2(maxWorkspacesList, activeId: 'ws_17');
      final multiDecoded = LegacyTtwV2Converter.decodeTtwV2Bytes(multiBytes);
      expect(multiDecoded.activeId, equals('ws_17'));
      expect(multiDecoded.workspaces, equals(maxWorkspacesList));
    });

    test('explicitly rejects TTW\\x01 and corrupt, truncated, trailing, invalid-UTF8, duplicate, invalid-dueLead, and oversized payloads', () {
      final recordV2 = _buildRawRecord();
      // 51-byte TTW v1 payload (no dueLead byte):
      final recordV1 = recordV2.sublist(0, recordV2.length - 1);
      final validSingle = _encodeTestTtwV2(const <AppWorkspace>[
        AppWorkspace.defaultWorkspace,
      ], activeId: 'tasks');

      final rejectedPayloads = <({String label, List<int> bytes})>[
        (
          label: 'TTW\\x01 payload (version 0x01)',
          bytes: <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordV1],
        ),
        (
          label: 'TTW\\x01 header with 52-byte v2 record',
          bytes: <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordV2],
        ),
        (label: 'empty', bytes: <int>[]),
        (label: 'short header', bytes: <int>[0x54, 0x54, 0x57]),
        (
          label: 'wrong magic',
          bytes: <int>[0x00, 0x00, 0x00, 0x02, 0x01, 0x00, ...recordV2],
        ),
        (
          label: 'version 0x00',
          bytes: <int>[0x54, 0x54, 0x57, 0x00, 0x01, 0x00, ...recordV2],
        ),
        (
          label: 'version 0x03',
          bytes: <int>[0x54, 0x54, 0x57, 0x03, 0x01, 0x00, ...recordV2],
        ),
        (label: 'count 0', bytes: <int>[0x54, 0x54, 0x57, 0x02, 0x00, 0x00]),
        (label: 'count 33', bytes: <int>[0x54, 0x54, 0x57, 0x02, 0x21, 0x00]),
        (
          label: 'activeIndex out of range',
          bytes: <int>[0x54, 0x54, 0x57, 0x02, 0x01, 0x01, ...recordV2],
        ),
        (
          label: 'negative activeIndex',
          bytes: <int>[0x54, 0x54, 0x57, 0x02, 0x01, -1, ...recordV2],
        ),
        (
          label: 'missing record body',
          bytes: <int>[0x54, 0x54, 0x57, 0x02, 0x01, 0x00],
        ),
        (
          label: 'truncated missing dueLead byte',
          bytes: <int>[0x54, 0x54, 0x57, 0x02, 0x01, 0x00, ...recordV1],
        ),
        (
          label: 'invalid dueLead byte 6',
          bytes: <int>[
            0x54,
            0x54,
            0x57,
            0x02,
            0x01,
            0x00,
            ..._buildRawRecord(dueLeadByte: 6),
          ],
        ),
        (
          label: 'invalid dueLead byte 0xFF',
          bytes: <int>[
            0x54,
            0x54,
            0x57,
            0x02,
            0x01,
            0x00,
            ..._buildRawRecord(dueLeadByte: 0xFF),
          ],
        ),
        (
          label: 'truncated string length',
          bytes: <int>[
            0x54,
            0x54,
            0x57,
            0x02,
            0x01,
            0x00,
            0x00,
            0x00,
            0x05,
            0x61,
          ],
        ),
        (
          label: 'invalid UTF-8 string',
          bytes: <int>[
            0x54,
            0x54,
            0x57,
            0x02,
            0x01,
            0x00,
            0x00,
            0x00,
            0x02,
            0xFF,
            0xFE,
          ],
        ),
        (label: 'trailing byte', bytes: <int>[...validSingle, 0x00]),
        (
          label: 'reserved flags lane2',
          bytes: <int>[
            0x54,
            0x54,
            0x57,
            0x02,
            0x01,
            0x00,
            ..._buildRawRecord(flags: 0x30),
          ],
        ),
        (
          label: 'overflow rem 11',
          bytes: <int>[
            0x54,
            0x54,
            0x57,
            0x02,
            0x01,
            0x00,
            ..._buildRawRecord(flags: 0x3E),
          ],
        ),
        (
          label: 'control char in name',
          bytes: <int>[
            0x54,
            0x54,
            0x57,
            0x02,
            0x01,
            0x00,
            ..._buildRawRecord(name: 'Bad\nName'),
          ],
        ),
        (
          label: 'traversal path',
          bytes: <int>[
            0x54,
            0x54,
            0x57,
            0x02,
            0x01,
            0x00,
            ..._buildRawRecord(localFilePath: '../escape.tdf'),
          ],
        ),
        (
          label: 'duplicate workspace records',
          bytes: <int>[
            0x54,
            0x54,
            0x57,
            0x02,
            0x02,
            0x00,
            ...recordV2,
            ...recordV2,
          ],
        ),
        (
          label: 'oversized 65537 bytes',
          bytes: Uint8List(LegacyTtwV2Converter.maxBinaryBytes + 1),
        ),
      ];

      for (final testCase in rejectedPayloads) {
        expect(
          () => LegacyTtwV2Converter.decodeTtwV2Bytes(testCase.bytes),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.corruptSettingsPayload,
            ),
          ),
          reason:
              'LegacyTtwV2Converter must reject ${testCase.label} with corruptSettingsPayload',
        );
      }
    });
  });
}
