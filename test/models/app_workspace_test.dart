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
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/app_logger.dart';

Uint8List _buildRawRecord({
  int flags = 0,
  String id = 'tasks',
  String name = 'Tasks',
  String serverUrl = '',
  String username = '',
  String password = '',
  String filePath = 'tasks.tdf',
  String localFilePath = 'tasks.tdf',
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
    ..addByte(0xD0);
  return builder.toBytes();
}

void main() {
  group('AppWorkspace & Suggested TDF File Names', () {
    test('defaults to Tasks workspace with tasks.tdf and derives lowercase .tdf filenames and collision IDs', () {
      const defaultWorkspace = AppWorkspace.defaultWorkspace;
      expect(
        defaultWorkspace.id,
        equals('tasks'),
        reason: 'Default workspace ID must be tasks',
      );
      expect(
        defaultWorkspace.name,
        equals('Tasks'),
        reason: 'Default workspace name must be Tasks',
      );
      expect(
        defaultWorkspace.config.localFilePath,
        equals('tasks.tdf'),
        reason: 'Default localFilePath must be tasks.tdf',
      );
      expect(
        defaultWorkspace.config.filePath,
        equals('tasks.tdf'),
        reason: 'Default remote filePath must be tasks.tdf',
      );

      for (final (rawName, expectedFile) in <(String, String)>[
        ('Tasks', 'tasks.tdf'),
        ('Arbeit', 'arbeit.tdf'),
        ('  Kunde Müller & Söhne! ', 'kunde_mueller_soehne.tdf'),
        ('Großprojekt ÄÖÜ', 'grossprojekt_aeoeue.tdf'),
        ('   ---   ', 'workspace.tdf'),
      ]) {
        expect(
          AppWorkspace.suggestFileName(rawName),
          equals(expectedFile),
          reason: 'suggestFileName("$rawName") must return "$expectedFile"',
        );
      }

      final summaries = <WorkspaceSummary>[
        defaultWorkspace.summary,
        const WorkspaceSummary(
          id: 'tasks_2',
          name: 'Tasks 2',
          localFilePath: 'tasks_2.tdf',
          filePath: 'tasks_2.tdf',
        ),
      ];
      expect(
        AppWorkspace.deriveWorkspaceId('Tasks', summaries),
        equals('tasks_3'),
        reason: 'deriveWorkspaceId must increment numeric suffix on collision',
      );
      expect(
        AppWorkspace.deriveWorkspaceId('!!!', summaries),
        equals('workspace'),
        reason: 'deriveWorkspaceId must fall back to workspace on empty slug',
      );

      final updated = defaultWorkspace.copyWith(
        name: 'Private Tasks',
        config: const WebDavConfig(
          localFilePath: 'private.tdf',
          filePath: 'private.tdf',
          storageMode: StorageMode.both,
          language: AppLanguage.german,
          themeMode: AppThemeMode.dark,
          themePalette: AppThemePalette.navy,
          timeZoneMode: AppTimeZoneMode.manual,
          manualTimeZoneOffsetMinutes: 120,
          diagnosticsEnabled: true,
        ),
      );
      final encodedBytes = updated.toBytes();
      expect(
        encodedBytes[6] & 0x80,
        equals(0),
        reason: 'Unused bit 7 in workspace flags byte must remain 0',
      );
      expect(
        encodedBytes.sublist(0, 4),
        equals(<int>[0x54, 0x54, 0x57, 0x01]),
        reason: 'Binary payload must start with TTW\\x01 magic header',
      );
      expect(
        defaultWorkspace.toBytes().length,
        equals(51),
        reason: 'Default workspace binary encoding must be 51 bytes',
      );
      expect(
        encodedBytes.length,
        equals(63),
        reason: 'Updated workspace binary encoding must be 63 bytes',
      );
      final roundTrip = AppWorkspace.fromBytes(encodedBytes);
      expect(
        roundTrip.config.diagnosticsEnabled,
        isTrue,
        reason: 'Binary round-trip must preserve diagnosticsEnabled',
      );
      expect(
        roundTrip.config.enableLogging,
        isTrue,
        reason: 'enableLogging getter must mirror diagnosticsEnabled',
      );
      expect(
        roundTrip,
        equals(updated),
        reason: 'Binary round-trip must preserve AppWorkspace equality',
      );
      expect(
        roundTrip.hashCode,
        equals(updated.hashCode),
        reason: 'Binary round-trip must preserve AppWorkspace hashCode',
      );
      expect(
        roundTrip.summary,
        equals(
          const WorkspaceSummary(
            id: 'tasks',
            name: 'Private Tasks',
            localFilePath: 'private.tdf',
            filePath: 'private.tdf',
          ),
        ),
        reason: 'summary getter must match id, name, and paths',
      );
      expect(
        roundTrip.summary.hashCode,
        equals(updated.summary.hashCode),
        reason: 'WorkspaceSummary hashCode must be deterministic',
      );
    });

    test('preserves logLevel and logStorageMode across all 37 UTC offsets without changing 51-byte default record size', () {
      const defaultWorkspace = AppWorkspace.defaultWorkspace;
      expect(
        defaultWorkspace.toBytes().length,
        equals(51),
        reason: 'Default workspace binary encoding must remain 51 bytes',
      );

      for (final level in LogLevel.configurableLevels) {
        for (final logMode in StorageMode.values) {
          for (final offset in WebDavConfig.supportedUtcOffsetMinutes) {
            final workspace = defaultWorkspace.copyWith(
              config: WebDavConfig(
                timeZoneMode: AppTimeZoneMode.manual,
                manualTimeZoneOffsetMinutes: offset,
                diagnosticsEnabled: true,
                logLevel: level,
                logStorageMode: logMode,
              ),
            );
            final bytes = workspace.toBytes();
            expect(
              bytes.length,
              equals(51),
              reason:
                  'Record size must remain 51 bytes for level=${level.label}, '
                  'logMode=${logMode.name}, offset=$offset',
            );
            final decoded = AppWorkspace.fromBytes(bytes);
            expect(
              decoded.config.logLevel,
              equals(level),
              reason: 'Decoded logLevel must match ${level.label}',
            );
            expect(
              decoded.config.logStorageMode,
              equals(logMode),
              reason: 'Decoded logStorageMode must match ${logMode.name}',
            );
            expect(
              decoded.config.manualTimeZoneOffsetMinutes,
              equals(offset),
              reason: 'Decoded manualTimeZoneOffsetMinutes must match $offset',
            );
          }
        }
      }
    });

    test('resolveLogEndpointUri resolves sibling WebDAV log URLs and rejects traversal or non-.log filenames', () {
      const nextcloudConfig = WebDavConfig(
        serverUrl: 'https://cloud.example.com/remote.php/dav/files/alice',
        username: 'alice',
        password: 'secret',
        filePath: 'tiertask/tasks.tdf',
      );
      expect(
        nextcloudConfig
            .resolveLogEndpointUri('tiertask_2026-11-03_linux_tasks.log')
            .toString(),
        equals(
          'https://cloud.example.com/remote.php/dav/files/alice/'
          'tiertask/tiertask_2026-11-03_linux_tasks.log',
        ),
      );

      const directUrlConfig = WebDavConfig(
        serverUrl: 'https://dav.example.com/sync/work.tdf',
        username: 'alice',
        password: 'secret',
      );
      expect(
        directUrlConfig
            .resolveLogEndpointUri('tiertask_2026-11-03_linux_work.log')
            .toString(),
        equals(
          'https://dav.example.com/sync/tiertask_2026-11-03_linux_work.log',
        ),
      );

      for (final invalidLogName in <String>[
        '',
        '../escape.log',
        'nested/file.log',
        r'nested\file.log',
        'not_a_log.tdf',
      ]) {
        expect(
          () => nextcloudConfig.resolveLogEndpointUri(invalidLogName),
          throwsA(isA<FormatException>()),
          reason: 'Invalid log filename "$invalidLogName" must be rejected',
        );
      }
    });
  });

  group('Workspace Uniqueness, Path Traversal, Control/BiDi Injection & Bounds', () {
    test('enforces name bounds, control/BiDi rejection, path traversal rejection, and all WorkspaceErrorKind variants', () async {
      final repository = InMemorySettingsRepository();

      final maxLenName = 'A' * AppWorkspace.maxNameLength;
      expect(
        AppWorkspace.validateName(maxLenName, const <WorkspaceSummary>[]),
        equals(maxLenName),
        reason: 'Exact 128-character workspace name must be accepted',
      );

      for (final invalidName in <String>[
        '',
        '   ',
        'Bad\nName',
        'Bad\rName',
        'Bad\x00Name',
        'Bad\x7FName',
        'Bad\u0085Name',
        'Bad\u009FName',
        'Bad\u2028Name',
        'Bad\u2029Name',
        'Bad\u202EName',
        'Bad\u2066Name',
        'Bad\u061CName',
        'Bad\u200EName',
        'Bad\u200FName',
        'A' * (AppWorkspace.maxNameLength + 1),
      ]) {
        await expectLater(
          () => repository.createWorkspace(invalidName),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.emptyName,
            ),
          ),
          reason: 'Invalid workspace name "$invalidName" must be rejected',
        );
      }

      for (final duplicateName in <String>['Tasks', 'tasks', '  TASKS  ']) {
        await expectLater(
          () => repository.createWorkspace(duplicateName),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.duplicateName,
            ),
          ),
          reason: 'Duplicate workspace name "$duplicateName" must be rejected',
        );
      }

      final arbeitWorkspace = await repository.createWorkspace('Arbeit');
      expect(
        arbeitWorkspace.id,
        equals('arbeit'),
        reason: 'Arbeit workspace ID must be arbeit',
      );

      await expectLater(
        () => repository.createWorkspace(
          'Zweiter Job',
          config: const WebDavConfig(
            localFilePath: 'ARBEIT.tdf',
            filePath: 'zweiter_job.tdf',
          ),
        ),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.duplicateFilePath,
          ),
        ),
        reason: 'Duplicate localFilePath must be rejected across workspaces',
      );

      await expectLater(
        () => repository.createWorkspace(
          'Dritter Job',
          config: const WebDavConfig(
            localFilePath: 'dritter_job.tdf',
            filePath: 'tasks.tdf',
          ),
        ),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.duplicateFilePath,
          ),
        ),
        reason: 'Duplicate remote filePath must be rejected across workspaces',
      );

      for (final invalidPath in <String>[
        '',
        '.tdf',
        '/.tdf',
        'sub/.tdf',
        'dir/..tdf',
        'dir/ .tdf',
        'dir/ .. /tasks.tdf',
        'dir/ . /tasks.tdf',
        'dir/ /tasks.tdf',
        'dir/ sub/tasks.tdf',
        'dir/sub /tasks.tdf',
        '../escape.tdf',
        'notes.txt',
        'bad\x00.tdf',
        'bad\u0085.tdf',
        'bad\u2028.tdf',
        'bad\u202E.tdf',
      ]) {
        await expectLater(
          () => repository.createWorkspace(
            'Invalid File Workspace',
            config: WebDavConfig(
              localFilePath: invalidPath,
              filePath: 'valid.tdf',
            ),
          ),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.invalidFilePath,
            ),
          ),
          reason: 'Invalid TDF path "$invalidPath" must be rejected',
        );
      }

      await expectLater(
        () => repository.renameWorkspace('arbeit', '  tasks '),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.duplicateName,
          ),
        ),
        reason: 'Renaming to an existing workspace name must be rejected',
      );

      final renamedArbeit = await repository.renameWorkspace(
        'arbeit',
        'Kunde Nord',
      );
      expect(
        renamedArbeit.name,
        equals('Kunde Nord'),
        reason: 'Renamed workspace must reflect new display name',
      );
      expect(
        renamedArbeit.config.localFilePath,
        equals('arbeit.tdf'),
        reason: 'Renaming a workspace must keep its configured .tdf file',
      );

      await expectLater(
        () => repository.saveConfig(
          const WebDavConfig(
            localFilePath: 'arbeit.tdf',
            filePath: 'tasks.tdf',
          ),
        ),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.duplicateFilePath,
          ),
        ),
        reason: 'Updating active config to another workspace file must fail',
      );

      await expectLater(
        () => repository.activateWorkspace('nonexistent'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.workspaceNotFound,
          ),
        ),
        reason: 'Activating unknown workspace ID must throw workspaceNotFound',
      );

      await repository.deleteWorkspace('arbeit');
      await expectLater(
        () => repository.deleteWorkspace('tasks'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.cannotDeleteLastWorkspace,
          ),
        ),
        reason: 'Deleting the sole remaining workspace must be rejected',
      );

      for (var i = 2; i <= AppWorkspace.maxWorkspaces; i++) {
        await repository.createWorkspace('Workspace $i');
      }
      await expectLater(
        () => repository.createWorkspace('Overflow Workspace'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.maxWorkspacesExceeded,
          ),
        ),
        reason: 'Exceeding AppWorkspace.maxWorkspaces must be rejected',
      );
    });

    test('rejects corrupt, negative-indexed, oversized, trailing-byte, invalid-UTF8, and duplicate binary payloads', () {
      final validSingle = AppWorkspace.defaultWorkspace.toBytes();
      final recordDefault = _buildRawRecord();
      final recordControlName = _buildRawRecord(name: 'Bad\nName');
      final recordBiDiPath = _buildRawRecord(localFilePath: 'bad\u202E.tdf');
      final recordTraversalPath = _buildRawRecord(
        localFilePath: '../escape.tdf',
      );
      final recordOverlongName = _buildRawRecord(
        name: 'A' * (AppWorkspace.maxNameLength + 1),
      );

      for (final corruptBytes in <List<int>>[
        <int>[],
        <int>[0x54, 0x54, 0x57],
        <int>[0x00, 0x00, 0x00, 0x01, 0x01, 0x00],
        <int>[0x154, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordDefault],
        <int>[0x54, 0x54, 0x57, 0x02, 0x01, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, 0x00, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, -1, 0x00, ...recordDefault],
        <int>[0x54, 0x54, 0x57, 0x01, 0x21, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x01],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, -256, ...recordDefault],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, 0x00, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, 0x00, 0x00, 0x05, 0x61],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0xFF, 0xFE],
        <int>[...validSingle, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordControlName],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordBiDiPath],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordTraversalPath],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordOverlongName],
        <int>[
          0x54,
          0x54,
          0x57,
          0x01,
          0x02,
          0x00,
          ...recordDefault,
          ...recordDefault,
        ],
        Uint8List(AppWorkspace.maxBinaryBytes + 1),
      ]) {
        expect(
          () => AppWorkspace.decodePersistedState(corruptBytes),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.corruptBinaryPayload,
            ),
          ),
          reason:
              'Corrupt binary payload (length ${corruptBytes.length}) must throw corruptBinaryPayload',
        );
      }

      final hugePasswordWorkspace = AppWorkspace(
        id: 'tasks',
        name: 'Tasks',
        config: WebDavConfig(password: 'P' * AppWorkspace.maxBinaryBytes),
      );
      expect(
        () => AppWorkspace.encodePersistedState(<AppWorkspace>[
          hugePasswordWorkspace,
        ], activeId: 'tasks'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.corruptBinaryPayload,
          ),
        ),
        reason: 'Encoding a workspace payload exceeding maxBinaryBytes must throw corruptBinaryPayload',
      );
    });
  });
}
