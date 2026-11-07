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

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/repositories/local_file_operations.dart';
import 'package:tiertask/repositories/local_file_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalFileRepository Path Helpers & Native Picker Channel', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_dir_helpers_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolves directory path, extracts file name, and combines directory and file name for relative and absolute paths', () {
      final relativeRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'tasks.tdf'),
        baseDirectoryPath: tempDir.path,
      );
      expect(relativeRepo.extractFileName(), equals('tasks.tdf'));
      expect(relativeRepo.resolveDirectoryPath(), equals(tempDir.path));
      expect(relativeRepo.tryResolveDirectoryPath(), equals(tempDir.path));
      expect(
        relativeRepo.tryResolveFilePath(),
        equals('${tempDir.path}${Platform.pathSeparator}tasks.tdf'),
      );
      expect(
        LocalFileRepository.extractDirectoryFromPath('tasks.tdf'),
        isEmpty,
      );
      expect(
        LocalFileRepository.extractDirectoryFromPath('/tmp/sub/tasks.tdf'),
        equals('/tmp/sub'),
      );
      expect(LocalFileRepository.resolveDefaultDirectoryPath(), isNotEmpty);

      final customSubdir =
          '${tempDir.path}${Platform.pathSeparator}custom_folder';
      final combined = LocalFileRepository.combineDirectoryAndFileName(
        customSubdir,
        'work.tdf',
      );
      expect(
        combined,
        equals('$customSubdir${Platform.pathSeparator}work.tdf'),
      );

      final absoluteRepo = LocalFileRepository(
        config: WebDavConfig(localFilePath: combined),
        baseDirectoryPath: '${tempDir.path}${Platform.pathSeparator}ignored',
      );
      expect(absoluteRepo.resolveFilePath(), equals(combined));
      expect(absoluteRepo.resolveDirectoryPath(), equals(customSubdir));
      expect(absoluteRepo.extractFileName(), equals('work.tdf'));
    });

    test('pickDirectory and pickTdfFile invoke native directory_picker MethodChannel and handle cancel', () async {
      MethodCall? recordedCall;
      String? mockResponse = '/home/stefan/SelectedTasks';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            LocalFileRepository.directoryPickerChannel,
            (call) async {
              recordedCall = call;
              return mockResponse;
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              LocalFileRepository.directoryPickerChannel,
              null,
            );
      });

      final repo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'tasks.tdf'),
        baseDirectoryPath: tempDir.path,
      );
      final selectedDir = await repo.pickDirectory(
        initialDirectory: tempDir.path,
      );
      expect(selectedDir, equals('/home/stefan/SelectedTasks'));
      expect(recordedCall?.method, equals('pickDirectory'));

      mockResponse = '${tempDir.path}/custom_board';
      final pickedFile = await repo.pickTdfFile(
        initialDirectory: tempDir.path,
        currentFileName: 'tasks.tdf',
      );
      expect(pickedFile, equals('${tempDir.path}/custom_board.tdf'));
      expect(recordedCall?.method, equals('pickFile'));

      mockResponse = null;
      expect(await repo.pickDirectory(), isNull);
      expect(await repo.pickTdfFile(), isNull);
    });

    test('validates file names and paths, initializes missing .tdf files, and lists sorted .tdf files', () async {
      expect(
        LocalFileRepository.ensureTdfExtension('board'),
        equals('board.tdf'),
      );
      expect(
        LocalFileRepository.ensureTdfExtension('board.TDF'),
        equals('board.TDF'),
      );
      expect(
        LocalFileRepository.validateFileName('sprint'),
        equals('sprint.tdf'),
      );
      expect(
        LocalFileRepository.validateRelativeOrAbsolutePath('folder//tasks.tdf'),
        equals('folder${Platform.pathSeparator}tasks.tdf'),
      );
      expect(LocalFileRepository.isValidSingleFileName('tasks'), isTrue);
      expect(
        LocalFileRepository.isValidSingleFileName('my_tasks-2.tdf'),
        isTrue,
      );

      for (final invalid in <String>[
        '',
        '   ',
        '.',
        '..',
        '.tdf',
        'sub/tasks.tdf',
        r'sub\tasks.tdf',
        'bad\x00name.tdf',
      ]) {
        expect(LocalFileRepository.isValidSingleFileName(invalid), isFalse);
        expect(
          () => LocalFileRepository.validateFileName(invalid),
          throwsA(isA<LocalFileException>()),
        );
      }

      final newRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'newly_created.tdf'),
        baseDirectoryPath: tempDir.path,
      );
      expect(newRepo.fileExists(), isFalse);
      await newRepo.initializeTdfIfNeeded();
      expect(newRepo.fileExists(), isTrue);
      final createdPath =
          '${tempDir.path}${Platform.pathSeparator}newly_created.tdf';
      expect(File(createdPath).readAsStringSync(), startsWith('tdf '));

      File('${tempDir.path}${Platform.pathSeparator}alpha.tdf')
          .writeAsStringSync('tdf 0.5.1\n', flush: true);
      File('${tempDir.path}${Platform.pathSeparator}ignore.txt')
          .writeAsStringSync('not tdf', flush: true);
      expect(
        newRepo.listTdfFileNamesInDirectory(),
        equals(<String>['alpha.tdf', 'newly_created.tdf']),
      );
    });
  });

  group('LocalFileRepository Read, Write, Wipe, Rename, Delete & Bounds', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_local_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reads and writes local .tdf files and rejects traversal, null bytes, or oversized payloads', () async {
      final repository = LocalFileRepository(
        config: const WebDavConfig(
          localFilePath: 'custom_tasks.tdf',
          storageMode: StorageMode.local,
        ),
        baseDirectoryPath: tempDir.path,
        maxFileBytes: 256,
      );
      expect(await repository.loadTdf(), isEmpty);

      const sampleTdf =
          'tdf 0.2.0\ntask t001 {\n  name "Local Task"\n  created 2026-11-01 08:00\n  queued 2026-11-01 08:00\n}\n';
      await repository.saveTdf(sampleTdf);
      expect(await repository.loadTdf(), contains('name "Local Task"'));

      for (final invalidPath in <String>[
        '../escape.tdf',
        'sub/../../escape.tdf',
        './tasks.tdf',
        'bad\x00file.tdf',
        'bad\nfile.tdf',
        r'..\escape.tdf',
      ]) {
        final invalidRepo = LocalFileRepository(
          config: WebDavConfig(localFilePath: invalidPath),
          baseDirectoryPath: tempDir.path,
        );
        expect(invalidRepo.tryResolveFilePath(), isNull);
        expect(invalidRepo.tryResolveDirectoryPath(), isNull);
        await expectLater(
          invalidRepo.loadTdf,
          throwsA(isA<LocalFileException>()),
          reason: 'Invalid localFilePath "$invalidPath" must be rejected',
        );
      }

      await expectLater(
        repository.saveTdf('A' * 300),
        throwsA(isA<LocalFileException>()),
      );
      File(repository.resolveFilePath())
          .writeAsStringSync('B' * 300, flush: true);
      await expectLater(repository.loadTdf, throwsA(isA<LocalFileException>()));
    });

    test('wipes local TDF files, creates .bak and .bak.001+ backups, and supports renameTdf and deleteTdf', () async {
      expect(
        LocalFileRepository.extractFileBaseName('tasks.tdf'),
        equals('tasks'),
      );
      expect(
        LocalFileRepository.extractFileBaseName('/home/user/my.board.TDF'),
        equals('my.board'),
      );
      expect(
        LocalFileRepository.extractFileBaseName(r'C:\Users\user\work.tdf'),
        equals('work'),
      );
      expect(
        LocalFileRepository.formatBackupPath('/tmp/tasks.tdf', 0),
        equals('/tmp/tasks.tdf.bak'),
      );
      expect(
        LocalFileRepository.formatBackupPath('/tmp/tasks.tdf', 1),
        equals('/tmp/tasks.tdf.bak.001'),
      );
      expect(
        LocalFileRepository.formatBackupPath('/tmp/tasks.tdf', 12),
        equals('/tmp/tasks.tdf.bak.012'),
      );

      final repository = LocalFileRepository(
        config: const WebDavConfig(
          localFilePath: 'wipe_test.tdf',
          storageMode: StorageMode.local,
        ),
        baseDirectoryPath: tempDir.path,
      );
      final mainFile = File('${tempDir.path}/wipe_test.tdf');
      final bakFile = File('${tempDir.path}/wipe_test.tdf.bak');
      final bak001File = File('${tempDir.path}/wipe_test.tdf.bak.001');
      final bak002File = File('${tempDir.path}/wipe_test.tdf.bak.002');

      await repository.wipeTdf(createBackup: true);
      expect(await mainFile.readAsString(), equals('tdf 0.5.1\n'));
      expect(await bakFile.exists(), isFalse);

      await mainFile.writeAsString('corrupted tdf content 1', flush: true);
      await repository.wipeTdf(createBackup: false);
      expect(await mainFile.readAsString(), equals('tdf 0.5.1\n'));
      expect(await bakFile.exists(), isFalse);

      await mainFile.writeAsString('corrupted tdf content A', flush: true);
      await repository.wipeTdf(createBackup: true);
      expect(await bakFile.readAsString(), equals('corrupted tdf content A'));

      await mainFile.writeAsString('corrupted tdf content B', flush: true);
      await repository.wipeTdf(createBackup: true);
      expect(
        await bak001File.readAsString(),
        equals('corrupted tdf content B'),
      );
      expect(await bakFile.readAsString(), equals('corrupted tdf content A'));

      await mainFile.writeAsString('corrupted tdf content C', flush: true);
      await repository.wipeTdf(createBackup: true);
      expect(
        await bak002File.readAsString(),
        equals('corrupted tdf content C'),
      );

      final renamedPath = await repository.renameTdf('renamed_board');
      expect(
        renamedPath,
        equals('${tempDir.path}${Platform.pathSeparator}renamed_board.tdf'),
      );
      expect(await mainFile.exists(), isFalse);
      expect(await File(renamedPath).exists(), isTrue);

      final renamedRepo = LocalFileRepository(
        config: WebDavConfig(localFilePath: renamedPath),
      );
      await renamedRepo.deleteTdf();
      expect(await File(renamedPath).exists(), isFalse);
    });

    test('LocalFileLogSink reads, writes, appends, truncates to maxBytes, and deletes diagnostic log files', () {
      const sink = LocalFileLogSink();
      final defaultPath = sink.defaultLogFilePath(
        baseDirectoryPath: tempDir.path,
      );
      expect(
        defaultPath,
        equals('${tempDir.path}${Platform.pathSeparator}tiertask.log'),
      );
      expect(sink.readLogFileSync(defaultPath, maxBytes: 1024), isEmpty);

      sink.writeLogFileSync(defaultPath, 'Line 1\n', append: false);
      sink.writeLogFileSync(defaultPath, 'Line 2\n', append: true);
      expect(
        sink.readLogFileSync(defaultPath, maxBytes: 1024),
        equals('Line 1\nLine 2\n'),
      );
      expect(
        sink.readLogFileSync(defaultPath, maxBytes: 7),
        equals('Line 2\n'),
      );

      sink.deleteLogFileSync(defaultPath);
      expect(File(defaultPath).existsSync(), isFalse);
    });
  });

  group('LocalFileRepository Safe Non-Destructive File Move & Error Reasons', () {
    late Directory sourceDir;
    late Directory targetDir;

    setUp(() async {
      sourceDir = await Directory.systemTemp.createTemp('tiertask_move_src_');
      targetDir = await Directory.systemTemp.createTemp('tiertask_move_dst_');
    });

    tearDown(() async {
      if (await sourceDir.exists()) {
        await sourceDir.delete(recursive: true);
      }
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
    });

    test('moves existing .tdf file across directories and rejects existing target file, directory, symlink, or invalid source', () async {
      final sourcePath = '${sourceDir.path}${Platform.pathSeparator}tasks.tdf';
      final targetPath = '${targetDir.path}${Platform.pathSeparator}tasks.tdf';
      const content = 'tdf 0.3.0\ntask t001 {\n    name "Move Me"\n}\n';
      await File(sourcePath).writeAsString(content, flush: true);

      LocalFileRepository englishRepo(String path) => LocalFileRepository(
        config: WebDavConfig(
          localFilePath: path,
          language: AppLanguage.english,
        ),
      );
      final sourceRepo = englishRepo(sourcePath);
      final targetRepo = englishRepo(targetPath);

      await sourceRepo.moveTdfFile(targetRepo);
      expect(await File(sourcePath).exists(), isFalse);
      expect(await File(targetPath).readAsString(), equals(content));

      await File(sourcePath).writeAsString(content, flush: true);
      await expectLater(
        () => sourceRepo.moveTdfFile(targetRepo),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('A file already exists at the target path'),
          ),
        ),
      );

      final existingDirTarget =
          '${targetDir.path}${Platform.pathSeparator}existing_dir.tdf';
      await Directory(existingDirTarget).create();
      await expectLater(
        () => sourceRepo.moveTdfFile(englishRepo(existingDirTarget)),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains(
              'A directory with this name already exists at the target path',
            ),
          ),
        ),
      );

      final symlinkTarget =
          '${targetDir.path}${Platform.pathSeparator}symlink_tasks.tdf';
      await Link(symlinkTarget)
          .create('${targetDir.path}${Platform.pathSeparator}dangling_target');
      await expectLater(
        () => sourceRepo.moveTdfFile(englishRepo(symlinkTarget)),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('A symbolic link already exists at the target path'),
          ),
        ),
      );

      final symlinkSource =
          '${sourceDir.path}${Platform.pathSeparator}link_source.tdf';
      await Link(symlinkSource).create(sourcePath);
      final freshTargetRepo = englishRepo(
        '${targetDir.path}${Platform.pathSeparator}fresh.tdf',
      );
      await expectLater(
        () => englishRepo(symlinkSource).moveTdfFile(freshTargetRepo),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('The source path is a symbolic link'),
          ),
        ),
      );

      final missingDirTarget =
          '${targetDir.path}${Platform.pathSeparator}missing_folder${Platform.pathSeparator}tasks.tdf';
      await expectLater(
        () => sourceRepo.moveTdfFile(englishRepo(missingDirTarget)),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('The target directory does not exist'),
          ),
        ),
      );
    });

    test('maps OS error codes across Linux and Windows and probes target directory writability', () async {
      final repo = LocalFileRepository(
        config: const WebDavConfig(
          localFilePath: 'tasks.tdf',
          language: AppLanguage.english,
        ),
        baseDirectoryPath: sourceDir.path,
      );
      expect(
        LocalFileOperations.maxBackupSuffix,
        equals(LocalFileRepository.maxBackupSuffix),
      );

      for (final (code, message, expectedSubstring) in <(int, String, String)>[
        (13, 'Permission denied', 'Permission denied'),
        (1, 'Operation not permitted', 'Permission denied'),
        (5, 'Access is denied.', 'Permission denied'),
        (1314, 'Privilege not held', 'Permission denied'),
        (30, 'Read-only file system', 'read-only'),
        (19, 'The media is write protected.', 'read-only'),
        (28, 'No space left on device', 'Not enough free disk space'),
        (122, 'Disk quota exceeded', 'Not enough free disk space'),
        (112, 'Not enough space', 'Not enough free disk space'),
        (39, 'The disk is full.', 'Not enough free disk space'),
        (16, 'Device or resource busy', 'locked or in use'),
        (26, 'Text file busy', 'locked or in use'),
        (32, 'Sharing violation', 'locked or in use'),
        (33, 'Lock violation', 'locked or in use'),
        (17, 'File exists', 'A file already exists'),
        (80, 'The file exists.', 'A file already exists'),
        (183, 'Already exists.', 'A file already exists'),
        (21, 'Is a directory', 'A directory with this name'),
        (20, 'Not a directory', 'not a directory'),
        (267, 'Invalid directory.', 'not a directory'),
        (2, 'No such file or directory', 'does not exist'),
        (3, 'Path not found.', 'does not exist'),
        (36, 'File name too long', 'too long'),
        (206, 'Filename is too long.', 'too long'),
        (999, 'Custom hardware I/O fault', 'Custom hardware I/O fault'),
      ]) {
        final fsException = FileSystemException(
          'Move failed',
          '/target/tasks.tdf',
          OSError(message, code),
        );
        final mapped = repo.mapMoveFileSystemException(
          fsException,
          fallbackPath: '/target/tasks.tdf',
        );
        expect(
          mapped.message,
          contains(expectedSubstring),
          reason: 'OS error code $code must map to "$expectedSubstring"',
        );
      }

      if (!Platform.isLinux) return;
      final idResult = await Process.run('id', const <String>['-u']);
      if (idResult.stdout.toString().trim() == '0') return;

      final readOnlyDir =
          '${targetDir.path}${Platform.pathSeparator}readonly_dir';
      await Directory(readOnlyDir).create();
      await Process.run('chmod', <String>['0500', readOnlyDir]);
      addTearDown(() async {
        await Process.run('chmod', <String>['0700', readOnlyDir]);
      });

      final nonExistentSourceRepo = LocalFileRepository(
        config: WebDavConfig(
          localFilePath:
              '${sourceDir.path}${Platform.pathSeparator}not_created_yet.tdf',
          language: AppLanguage.english,
        ),
      );
      final readOnlyTargetRepo = LocalFileRepository(
        config: WebDavConfig(
          localFilePath:
              '$readOnlyDir${Platform.pathSeparator}not_created_yet.tdf',
          language: AppLanguage.english,
        ),
      );

      await expectLater(
        () => nonExistentSourceRepo.moveTdfFile(readOnlyTargetRepo),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('Permission denied'),
          ),
        ),
      );
    });
  });
}
