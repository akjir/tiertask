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
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'tiertask_dir_helpers_',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('resolves directory path, extracts file name, and combines directory and file name for relative, absolute, and root paths', () {
      const operations = LocalFileOperations<LocalFileException>(
        LocalFileException.new,
      );
      expect(operations.trimTrailingSeparators('/'), equals('/'));
      expect(operations.trimTrailingSeparators('///'), equals('/'));
      expect(operations.trimTrailingSeparators(r'C:\'), equals(r'C:\'));
      expect(operations.trimTrailingSeparators(r'C:\\\'), equals(r'C:\'));
      expect(
        LocalFileRepository.defaultLogFilePath(baseDirectoryPath: '/'),
        equals('/tiertask.log'),
      );

      final rootRepository = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'tasks.tdf'),
        baseDirectoryPath: '/',
      );
      expect(rootRepository.resolveFilePath(), equals('/tasks.tdf'));

      final relativeRepository = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'tasks.tdf'),
        baseDirectoryPath: tempDirectory.path,
      );
      expect(relativeRepository.extractFileName(), equals('tasks.tdf'));
      expect(
        relativeRepository.resolveDirectoryPath(),
        equals(tempDirectory.path),
      );
      expect(
        relativeRepository.tryResolveDirectoryPath(),
        equals(tempDirectory.path),
      );
      expect(
        relativeRepository.tryResolveFilePath(),
        equals('${tempDirectory.path}${Platform.pathSeparator}tasks.tdf'),
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

      final customSubdirectory =
          '${tempDirectory.path}${Platform.pathSeparator}custom_folder';
      final combined = LocalFileRepository.combineDirectoryAndFileName(
        customSubdirectory,
        'work.tdf',
      );
      expect(
        combined,
        equals('$customSubdirectory${Platform.pathSeparator}work.tdf'),
      );

      final absoluteRepository = LocalFileRepository(
        config: WebDavConfig(localFilePath: combined),
        baseDirectoryPath:
            '${tempDirectory.path}${Platform.pathSeparator}ignored',
      );
      expect(absoluteRepository.resolveFilePath(), equals(combined));
      expect(
        absoluteRepository.resolveDirectoryPath(),
        equals(customSubdirectory),
      );
      expect(absoluteRepository.extractFileName(), equals('work.tdf'));
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

      final repository = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'tasks.tdf'),
        baseDirectoryPath: tempDirectory.path,
      );
      final selectedDirectory = await repository.pickDirectory(
        initialDirectory: tempDirectory.path,
      );
      expect(selectedDirectory, equals('/home/stefan/SelectedTasks'));
      expect(recordedCall?.method, equals('pickDirectory'));

      mockResponse = '${tempDirectory.path}/custom_board';
      final pickedFile = await repository.pickTdfFile(
        initialDirectory: tempDirectory.path,
        currentFileName: 'tasks.tdf',
      );
      expect(pickedFile, equals('${tempDirectory.path}/custom_board.tdf'));
      expect(recordedCall?.method, equals('pickFile'));

      mockResponse = null;
      expect(await repository.pickDirectory(), isNull);
      expect(await repository.pickTdfFile(), isNull);
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
        'C:tasks.tdf',
        'tasks.tdf:\$DATA',
      ]) {
        expect(
          LocalFileRepository.isValidSingleFileName(invalid),
          isFalse,
          reason: 'Single file name "$invalid" must be rejected',
        );
        expect(
          () => LocalFileRepository.validateFileName(invalid),
          throwsA(isA<LocalFileException>()),
          reason: 'validateFileName("$invalid") must throw LocalFileException',
        );
      }

      final newRepository = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'newly_created.tdf'),
        baseDirectoryPath: tempDirectory.path,
      );
      expect(newRepository.fileExists(), isFalse);
      await newRepository.initializeTdfIfNeeded();
      expect(newRepository.fileExists(), isTrue);
      final createdPath =
          '${tempDirectory.path}${Platform.pathSeparator}newly_created.tdf';
      expect(File(createdPath).readAsStringSync(), startsWith('tdf '));

      File('${tempDirectory.path}${Platform.pathSeparator}alpha.tdf')
          .writeAsStringSync('tdf 0.5.1\n', flush: true);
      File('${tempDirectory.path}${Platform.pathSeparator}ignore.txt')
          .writeAsStringSync('not tdf', flush: true);
      expect(
        newRepository.listTdfFileNamesInDirectory(),
        equals(<String>['alpha.tdf', 'newly_created.tdf']),
      );
    });
  });

  group('LocalFileRepository Read, Write, Wipe, Rename, Delete & Bounds', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'tiertask_local_test_',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('reads and writes local .tdf files and rejects traversal, null bytes, or oversized payloads', () async {
      final repository = LocalFileRepository(
        config: const WebDavConfig(
          localFilePath: 'custom_tasks.tdf',
          storageMode: StorageMode.local,
        ),
        baseDirectoryPath: tempDirectory.path,
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
        r'\tasks.tdf',
        r'\\server\share\tasks.tdf',
        'C:tasks.tdf',
        'tasks.tdf:\$DATA',
      ]) {
        final invalidRepository = LocalFileRepository(
          config: WebDavConfig(localFilePath: invalidPath),
          baseDirectoryPath: tempDirectory.path,
        );
        expect(
          invalidRepository.tryResolveFilePath(),
          isNull,
          reason: 'tryResolveFilePath for "$invalidPath" must return null',
        );
        expect(
          invalidRepository.tryResolveDirectoryPath(),
          isNull,
          reason: 'tryResolveDirectoryPath for "$invalidPath" must return null',
        );
        await expectLater(
          invalidRepository.loadTdf,
          throwsA(isA<LocalFileException>()),
          reason: 'Invalid localFilePath "$invalidPath" must be rejected',
        );
      }

      for (final invalidBase in <String>[
        '${tempDirectory.path}/../escape',
        '../escape',
        '${tempDirectory.path}/bad\x00dir',
      ]) {
        final invalidBaseRepository = LocalFileRepository(
          config: const WebDavConfig(localFilePath: 'tasks.tdf'),
          baseDirectoryPath: invalidBase,
        );
        expect(
          invalidBaseRepository.tryResolveFilePath(),
          isNull,
          reason: 'Invalid baseDirectoryPath "$invalidBase" must be rejected',
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
        baseDirectoryPath: tempDirectory.path,
      );
      final mainFile = File('${tempDirectory.path}/wipe_test.tdf');
      final backupFile = File('${tempDirectory.path}/wipe_test.tdf.bak');
      final backup001File = File('${tempDirectory.path}/wipe_test.tdf.bak.001');
      final backup002File = File('${tempDirectory.path}/wipe_test.tdf.bak.002');

      await repository.wipeTdf(createBackup: true);
      expect(await mainFile.readAsString(), equals('tdf 0.6.0\n'));
      expect(await backupFile.exists(), isFalse);

      await mainFile.writeAsString('corrupted tdf content 1', flush: true);
      await repository.wipeTdf(createBackup: false);
      expect(await mainFile.readAsString(), equals('tdf 0.6.0\n'));
      expect(await backupFile.exists(), isFalse);

      await mainFile.writeAsString('corrupted tdf content A', flush: true);
      await repository.wipeTdf(createBackup: true);
      expect(
        await backupFile.readAsString(),
        equals('corrupted tdf content A'),
      );

      await mainFile.writeAsString('corrupted tdf content B', flush: true);
      await repository.wipeTdf(createBackup: true);
      expect(
        await backup001File.readAsString(),
        equals('corrupted tdf content B'),
      );
      expect(
        await backupFile.readAsString(),
        equals('corrupted tdf content A'),
      );

      await mainFile.writeAsString('corrupted tdf content C', flush: true);
      await repository.wipeTdf(createBackup: true);
      expect(
        await backup002File.readAsString(),
        equals('corrupted tdf content C'),
      );

      final renamedPath = await repository.renameTdf('renamed_board');
      expect(
        renamedPath,
        equals(
          '${tempDirectory.path}${Platform.pathSeparator}renamed_board.tdf',
        ),
      );
      expect(await mainFile.exists(), isFalse);
      expect(await File(renamedPath).exists(), isTrue);

      final renamedRepository = LocalFileRepository(
        config: WebDavConfig(localFilePath: renamedPath),
      );
      await renamedRepository.deleteTdf();
      expect(await File(renamedPath).exists(), isFalse);
    });

    test('LocalFileLogSink reads, writes, appends, truncates to maxBytes, guards against non-positive maxBytes and symlinks, and deletes diagnostic log files', () {
      const sink = LocalFileLogSink();
      final defaultPath = sink.defaultLogFilePath(
        baseDirectoryPath: tempDirectory.path,
      );
      expect(
        defaultPath,
        equals('${tempDirectory.path}${Platform.pathSeparator}tiertask.log'),
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
      expect(sink.readLogFileSync(defaultPath, maxBytes: 0), isEmpty);
      expect(sink.readLogFileSync(defaultPath, maxBytes: -5), isEmpty);

      final targetFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}protected_target.txt',
      )..writeAsStringSync('sensitive content', flush: true);
      final symlinkLogPath =
          '${tempDirectory.path}${Platform.pathSeparator}symlink.log';
      Link(symlinkLogPath).createSync(targetFile.path);

      expect(sink.readLogFileSync(symlinkLogPath, maxBytes: 1024), isEmpty);
      sink.writeLogFileSync(symlinkLogPath, 'injected log', append: false);
      expect(targetFile.readAsStringSync(), equals('sensitive content'));
      sink.deleteLogFileSync(symlinkLogPath);
      expect(
        FileSystemEntity.typeSync(symlinkLogPath, followLinks: false),
        equals(FileSystemEntityType.link),
      );
      expect(targetFile.existsSync(), isTrue);

      sink.deleteLogFileSync(defaultPath);
      expect(File(defaultPath).existsSync(), isFalse);

      final nowUtc = DateTime.utc(2026, 11, 10, 12);
      final resolvedDatedPath = LocalFileRepository.resolveLogFilePath(
        baseDirectoryPath: tempDirectory.path,
        utcNow: nowUtc,
        platform: 'linux',
        workspaceId: 'work',
      );
      expect(
        resolvedDatedPath,
        equals(
          '${tempDirectory.path}${Platform.pathSeparator}'
          'tiertask_2026-11-10_linux_work.log',
        ),
      );

      final legacyLog = File(
        '${tempDirectory.path}${Platform.pathSeparator}tiertask.log',
      )..writeAsStringSync('legacy', flush: true);
      final expiredLog = File(
        '${tempDirectory.path}${Platform.pathSeparator}'
        'tiertask_2026-11-01_linux_work.log',
      )..writeAsStringSync('expired (>7d)', flush: true);
      final otherWorkspaceLog = File(
        '${tempDirectory.path}${Platform.pathSeparator}'
        'tiertask_2026-11-01_linux_other.log',
      )..writeAsStringSync('other workspace', flush: true);

      final recentDates = <String>[
        '2026-11-04',
        '2026-11-05',
        '2026-11-06',
        '2026-11-07',
        '2026-11-08',
        '2026-11-09',
        '2026-11-10',
      ];
      for (final dateStr in recentDates) {
        File(
          '${tempDirectory.path}${Platform.pathSeparator}'
          'tiertask_${dateStr}_linux_work.log',
        ).writeAsStringSync('recent $dateStr', flush: true);
      }

      final prunedCount = sink.pruneExpiredLogFilesSync(
        directoryPath: tempDirectory.path,
        platform: 'linux',
        workspaceId: 'work',
        utcNow: nowUtc,
        maxRetainedDays: 7,
        maxRetainedFiles: 5,
      );
      expect(
        prunedCount,
        equals(4),
        reason: 'Legacy tiertask.log, 1 expired file (2026-11-01), and 2 overflow files (2026-11-04, 2026-11-05) must be pruned',
      );
      expect(legacyLog.existsSync(), isFalse);
      expect(expiredLog.existsSync(), isFalse);
      expect(
        File(
          '${tempDirectory.path}${Platform.pathSeparator}'
          'tiertask_2026-11-05_linux_work.log',
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          '${tempDirectory.path}${Platform.pathSeparator}'
          'tiertask_2026-11-06_linux_work.log',
        ).existsSync(),
        isTrue,
      );
      expect(
        otherWorkspaceLog.existsSync(),
        isTrue,
        reason: 'Logs from other workspaces must not be pruned',
      );

      final deletedCount = sink.deleteWorkspaceLogFilesSync(
        directoryPath: tempDirectory.path,
        platform: 'linux',
        workspaceId: 'work',
      );
      expect(deletedCount, equals(5));
      expect(otherWorkspaceLog.existsSync(), isTrue);
    });
  });

  group('LocalFileRepository Safe Non-Destructive File Move & Error Reasons', () {
    late Directory sourceDirectory;
    late Directory targetDirectory;

    setUp(() async {
      sourceDirectory = await Directory.systemTemp.createTemp(
        'tiertask_move_src_',
      );
      targetDirectory = await Directory.systemTemp.createTemp(
        'tiertask_move_dst_',
      );
    });

    tearDown(() async {
      if (await sourceDirectory.exists()) {
        await sourceDirectory.delete(recursive: true);
      }
      if (await targetDirectory.exists()) {
        await targetDirectory.delete(recursive: true);
      }
    });

    test('moves existing .tdf file across directories and rejects existing target file, directory, symlink, or invalid source', () async {
      final sourcePath =
          '${sourceDirectory.path}${Platform.pathSeparator}tasks.tdf';
      final targetPath =
          '${targetDirectory.path}${Platform.pathSeparator}tasks.tdf';
      const content = 'tdf 0.3.0\ntask t001 {\n    name "Move Me"\n}\n';
      await File(sourcePath).writeAsString(content, flush: true);

      LocalFileRepository englishRepository(String path) => LocalFileRepository(
        config: WebDavConfig(
          localFilePath: path,
          language: AppLanguage.english,
        ),
      );
      final sourceRepository = englishRepository(sourcePath);
      final targetRepository = englishRepository(targetPath);

      await sourceRepository.moveTdfFile(targetRepository);
      expect(await File(sourcePath).exists(), isFalse);
      expect(await File(targetPath).readAsString(), equals(content));

      await File(sourcePath).writeAsString(content, flush: true);
      await expectLater(
        () => sourceRepository.moveTdfFile(targetRepository),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('A file already exists at the target path'),
          ),
        ),
      );

      final existingDirectoryTarget =
          '${targetDirectory.path}${Platform.pathSeparator}existing_dir.tdf';
      await Directory(existingDirectoryTarget).create();
      await expectLater(
        () => sourceRepository.moveTdfFile(
          englishRepository(existingDirectoryTarget),
        ),
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
          '${targetDirectory.path}${Platform.pathSeparator}symlink_tasks.tdf';
      await Link(symlinkTarget).create(
        '${targetDirectory.path}${Platform.pathSeparator}dangling_target',
      );
      await expectLater(
        () => sourceRepository.moveTdfFile(englishRepository(symlinkTarget)),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('A symbolic link already exists at the target path'),
          ),
        ),
      );

      final symlinkSource =
          '${sourceDirectory.path}${Platform.pathSeparator}link_source.tdf';
      await Link(symlinkSource).create(sourcePath);
      final freshTargetRepository = englishRepository(
        '${targetDirectory.path}${Platform.pathSeparator}fresh.tdf',
      );
      await expectLater(
        () =>
            englishRepository(symlinkSource).moveTdfFile(freshTargetRepository),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('The source path is a symbolic link'),
          ),
        ),
      );

      if (Platform.isLinux) {
        final socketSource =
            '${sourceDirectory.path}${Platform.pathSeparator}sock.tdf';
        final serverSocket = await ServerSocket.bind(
          InternetAddress(socketSource, type: InternetAddressType.unix),
          0,
        );
        addTearDown(() async {
          await serverSocket.close();
        });
        await expectLater(
          () =>
              englishRepository(socketSource)
                  .moveTdfFile(freshTargetRepository),
          throwsA(isA<LocalFileException>()),
        );
        await expectLater(
          englishRepository(socketSource).deleteTdf,
          throwsA(isA<LocalFileException>()),
        );
      }

      final missingDirectoryTarget =
          '${targetDirectory.path}${Platform.pathSeparator}missing_folder${Platform.pathSeparator}tasks.tdf';
      await expectLater(
        () => sourceRepository.moveTdfFile(
          englishRepository(missingDirectoryTarget),
        ),
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
      final repository = LocalFileRepository(
        config: const WebDavConfig(
          localFilePath: 'tasks.tdf',
          language: AppLanguage.english,
        ),
        baseDirectoryPath: sourceDirectory.path,
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
        final fileSystemException = FileSystemException(
          'Move failed',
          '/target/tasks.tdf',
          OSError(message, code),
        );
        final mapped = repository.mapMoveFileSystemException(
          fileSystemException,
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

      final readOnlyDirectory =
          '${targetDirectory.path}${Platform.pathSeparator}readonly_dir';
      await Directory(readOnlyDirectory).create();
      await Process.run('chmod', <String>['0500', readOnlyDirectory]);
      addTearDown(() async {
        await Process.run('chmod', <String>['0700', readOnlyDirectory]);
      });

      final nonExistentSourceRepository = LocalFileRepository(
        config: WebDavConfig(
          localFilePath:
              '${sourceDirectory.path}${Platform.pathSeparator}not_created_yet.tdf',
          language: AppLanguage.english,
        ),
      );
      final readOnlyTargetRepository = LocalFileRepository(
        config: WebDavConfig(
          localFilePath:
              '$readOnlyDirectory${Platform.pathSeparator}not_created_yet.tdf',
          language: AppLanguage.english,
        ),
      );

      await expectLater(
        () => nonExistentSourceRepository.moveTdfFile(readOnlyTargetRepository),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('Permission denied'),
          ),
        ),
      );
    });

    test('readTdfWithDigest computes SHA-256 hex digest and saveTdf uses atomic dot-prefixed .tmp.<32hex> replacement without .tdf.lock files', () async {
      final repository = LocalFileRepository(
        config: const WebDavConfig(
          localFilePath: 'atomic_tasks.tdf',
          storageMode: StorageMode.local,
        ),
        baseDirectoryPath: sourceDirectory.path,
      );

      final missingRead = await repository.readTdfWithDigest();
      expect(missingRead.exists, isFalse);
      expect(missingRead.content, isEmpty);
      expect(missingRead.digest, isNull);

      final targetPath = repository.resolveFilePath();
      File(targetPath).writeAsStringSync('', flush: true);
      final emptyRead = await repository.readTdfWithDigest();
      expect(emptyRead.exists, isTrue);
      expect(emptyRead.content, isEmpty);
      expect(
        emptyRead.digest,
        equals(
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        ),
      );

      const sampleContent = 'tdf 0.6.0\n';
      await repository.saveTdf(sampleContent);
      final populatedRead = await repository.readTdfWithDigest();
      expect(populatedRead.exists, isTrue);
      expect(populatedRead.content, equals(sampleContent));
      expect(populatedRead.digest, isNotNull);
      expect(populatedRead.digest?.length, equals(64));

      final entries = sourceDirectory
          .listSync(followLinks: false)
          .map((entity) => entity.path.split(Platform.pathSeparator).last)
          .toList();
      expect(entries, equals(<String>['atomic_tasks.tdf']));
      expect(
        entries.where(
          (name) => name.contains('.tmp.') || name.endsWith('.lock'),
        ),
        isEmpty,
        reason:
            'Must leave zero .tmp.<hex> or .tdf.lock files after atomic save',
      );

      File(targetPath).deleteSync();
      Directory(targetPath).createSync();
      await expectLater(
        () => repository.saveTdf(sampleContent),
        throwsA(isA<LocalFileException>()),
      );
      final remainingTempFiles = sourceDirectory
          .listSync(followLinks: false)
          .map((entity) => entity.path.split(Platform.pathSeparator).last)
          .where((name) => name.contains('.tmp.'))
          .toList();
      expect(
        remainingTempFiles,
        isEmpty,
        reason: 'Failed atomic save must unlink its temporary file before rethrowing',
      );
    });
  });
}
