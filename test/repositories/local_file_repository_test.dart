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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations_de.dart';
import 'package:tiertask/l10n/app_localizations_en.dart';
import 'package:tiertask/models/app_build_profile.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/repositories/local_file_operations.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/sha256_service.dart';

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
        config: const WebDavConfig(),
        baseDirectoryPath: '/',
      );
      expect(rootRepository.resolveFilePath(), equals('/tasks.tdf'));

      final relativeRepository = LocalFileRepository(
        config: const WebDavConfig(),
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
        config: const WebDavConfig(),
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
      await newRepository.initializeIfMissing();
      expect(newRepository.fileExists(), isTrue);
      final createdPath =
          '${tempDirectory.path}${Platform.pathSeparator}newly_created.tdf';
      expect(File(createdPath).readAsStringSync(), startsWith('tdf '));

      File('${tempDirectory.path}${Platform.pathSeparator}alpha.tdf')
          .writeAsStringSync('tdf 0.8.0\n', flush: true);
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
          'tdf 0.8.0\ntask 000001OkD2 {\n    name "Local Task"\n    created 2026-11-01 08:00\n}\n';
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
          config: const WebDavConfig(),
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
      expect(await mainFile.readAsString(), equals('tdf 0.8.0\n'));
      expect(await backupFile.exists(), isFalse);

      await mainFile.writeAsString('corrupted tdf content 1', flush: true);
      await repository.wipeTdf();
      expect(await mainFile.readAsString(), equals('tdf 0.8.0\n'));
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
      if (Platform.isLinux) {
        final mode = FileStat.statSync(defaultPath).mode & 0x1FF;
        expect(
          mode,
          equals(0x180),
          reason: 'Diagnostic log files on Linux must use 0600 permissions',
        );
      }
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
      const content =
          'tdf 0.8.0\ntask 000001OkD2 {\n    name "Move Me"\n    created 2026-11-01 08:00\n}\n';
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
        config: const WebDavConfig(language: AppLanguage.english),
        baseDirectoryPath: sourceDirectory.path,
      );
      expect(
        LocalFileOperations.maxBackupSuffix,
        equals(LocalFileRepository.maxBackupSuffix),
      );

      for (final (code, message, expectedSubstring) in <(int, String, String)>[
        (13, 'Permission denied', 'Permission denied'),
        (1, 'Operation not permitted', 'Permission denied'),
        (30, 'Read-only file system', 'read-only'),
        (28, 'No space left on device', 'Not enough free disk space'),
        (122, 'Disk quota exceeded', 'Not enough free disk space'),
        (16, 'Device or resource busy', 'locked or in use'),
        (26, 'Text file busy', 'locked or in use'),
        (17, 'File exists', 'A file already exists'),
        (21, 'Is a directory', 'A directory with this name'),
        (39, 'Directory not empty', 'A directory with this name'),
        (20, 'Not a directory', 'not a directory'),
        (2, 'No such file or directory', 'does not exist'),
        (36, 'File name too long', 'too long'),
        (18, 'Invalid cross-device link', 'Invalid cross-device link'),
        (5, 'Input/output error', 'Input/output error'),
        (19, 'No such device', 'No such device'),
        (32, 'Broken pipe', 'Broken pipe'),
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
          isWindows: false,
        );
        expect(
          mapped.message,
          contains(expectedSubstring),
          reason: 'POSIX errno $code must map to "$expectedSubstring"',
        );
      }

      for (final (code, message, expectedSubstring) in <(int, String, String)>[
        (5, 'Access is denied.', 'Permission denied'),
        (1314, 'Privilege not held', 'Permission denied'),
        (19, 'The media is write protected.', 'read-only'),
        (112, 'Not enough space', 'Not enough free disk space'),
        (39, 'The disk is full.', 'Not enough free disk space'),
        (32, 'Sharing violation', 'locked or in use'),
        (33, 'Lock violation', 'locked or in use'),
        (80, 'The file exists.', 'A file already exists'),
        (183, 'Already exists.', 'A file already exists'),
        (267, 'Invalid directory.', 'not a directory'),
        (2, 'File not found.', 'does not exist'),
        (3, 'Path not found.', 'does not exist'),
        (206, 'Filename is too long.', 'too long'),
        (17, 'Not same device.', 'Not same device.'),
        (21, 'Device not ready.', 'Device not ready.'),
      ]) {
        final fileSystemException = FileSystemException(
          'Move failed',
          r'C:\target\tasks.tdf',
          OSError(message, code),
        );
        final mapped = repository.mapMoveFileSystemException(
          fileSystemException,
          fallbackPath: r'C:\target\tasks.tdf',
          isWindows: true,
        );
        expect(
          mapped.message,
          contains(expectedSubstring),
          reason: 'Win32 error $code must map to "$expectedSubstring"',
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

      const sampleContent = 'tdf 0.8.0\n';
      await repository.saveTdf(sampleContent);
      final populatedRead = await repository.readTdfWithDigest();
      expect(populatedRead.exists, isTrue);
      expect(populatedRead.content, equals(sampleContent));
      expect(populatedRead.digest, isNotNull);
      expect(populatedRead.digest?.length, equals(64));
      if (Platform.isLinux) {
        final mode = File(targetPath).statSync().mode & 0x1FF;
        expect(
          mode,
          equals(0x180),
          reason: 'Atomic temp-file swap on Linux must set owner-only 0600 permissions',
        );
      }

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

  group('LocalFileRepository Directory Watch & Event Filtering', () {
    late Directory watchTempRoot;

    setUp(() async {
      watchTempRoot = await Directory.systemTemp.createTemp(
        'tiertask_watch_repo_',
      );
    });

    tearDown(() async {
      if (await watchTempRoot.exists()) {
        await watchTempRoot.delete(recursive: true);
      }
    });

    test('matchesWatchedFileName and isRelevantWatchEvent enforce zero-trim basename matching, case rules, and Delete/tmp/bak/log suppression', () {
      const operations = LocalFileOperations<LocalFileException>(
        LocalFileException.new,
      );

      expect(
        operations.matchesWatchedFileName(
          '/home/user/tasks.tdf',
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isTrue,
      );
      expect(
        operations.matchesWatchedFileName(
          r'C:\Users\alice\TierTask\tasks.tdf',
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isTrue,
      );
      expect(
        operations.matchesWatchedFileName(
          'tasks.tdf',
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isTrue,
      );

      for (final rejectedPath in <String>[
        '',
        '/',
        r'\',
        '/home/user/',
        r'C:\Users\alice\',
        '/home/user/tasks.tdf ',
        '/home/user/ tasks.tdf',
        '/home/user/work.tdf',
        '/home/user/.tasks.tdf.tmp.0123456789abcdef0123456789abcdef',
        '/home/user/tasks.tdf.bak',
        '/home/user/tasks.tdf.bak.001',
        '/home/user/tiertask_2026-11-14_linux_tasks.log',
      ]) {
        expect(
          operations.matchesWatchedFileName(
            rejectedPath,
            'tasks.tdf',
            caseInsensitive: true,
          ),
          isFalse,
          reason: 'Path "$rejectedPath" must not match tasks.tdf',
        );
      }
      expect(
        operations.matchesWatchedFileName(
          '/home/user/tasks.tdf',
          '',
          caseInsensitive: true,
        ),
        isFalse,
      );

      expect(
        operations.matchesWatchedFileName(
          '/home/user/Tasks.TDF',
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isFalse,
      );
      expect(
        operations.matchesWatchedFileName(
          r'C:\Users\alice\Tasks.TDF',
          'tasks.tdf',
          caseInsensitive: true,
        ),
        isTrue,
      );

      expect(
        operations.isRelevantWatchEvent(
          FileSystemCreateEvent('/dir/tasks.tdf', false),
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isTrue,
      );
      expect(
        operations.isRelevantWatchEvent(
          FileSystemModifyEvent('/dir/tasks.tdf', false, true),
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isTrue,
      );
      expect(
        operations.isRelevantWatchEvent(
          FileSystemDeleteEvent('/dir/tasks.tdf', false),
          'tasks.tdf',
          caseInsensitive: true,
        ),
        isFalse,
        reason: 'FileSystemDeleteEvent must always be suppressed',
      );
      expect(
        operations.isRelevantWatchEvent(
          FileSystemMoveEvent(
            '/dir/.tasks.tdf.tmp.abcd',
            false,
            '/dir/tasks.tdf',
          ),
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isTrue,
        reason: 'Atomic temp-to-target rename must match via destination',
      );
      expect(
        operations.isRelevantWatchEvent(
          FileSystemMoveEvent('/dir/TASKS.TDF', false, '/dir/other.bak'),
          'tasks.tdf',
          caseInsensitive: true,
        ),
        isTrue,
      );
      expect(
        operations.isRelevantWatchEvent(
          FileSystemMoveEvent(
            '/dir/.work.tdf.tmp.abcd',
            false,
            '/dir/work.tdf',
          ),
          'tasks.tdf',
          caseInsensitive: true,
        ),
        isFalse,
      );
    });

    test('guards in-memory fallback, traversal paths, and missing directories, and emits events for direct write, same-dir atomic swap, and cross-dir rename', () async {
      final inMemoryRepo = LocalFileRepository(
        config: const WebDavConfig(),
        inMemoryStore: <String, String>{},
      );
      expect(inMemoryRepo.canWatchDirectory, isFalse);
      expect(inMemoryRepo.directoryExists(), isTrue);
      expect(await inMemoryRepo.watchTdfChanges().isEmpty, isTrue);

      final androidDir = Directory('${watchTempRoot.path}/android_files')
        ..createSync(recursive: true);
      final androidRepo = LocalFileRepository(
        config: const WebDavConfig(),
        baseDirectoryPath: androidDir.path,
        androidFilesDirectoryResolver: () async => androidDir.path,
      );
      expect(
        androidRepo.canWatchDirectory,
        isFalse,
        reason:
            'Android sandboxed local storage must disable directory watching',
      );
      expect(
        await androidRepo.watchTdfChanges().isEmpty,
        isTrue,
        reason: 'watchTdfChanges must return an empty stream on Android',
      );

      const operations = LocalFileOperations<LocalFileException>(
        LocalFileException.new,
      );
      expect(
        await operations
            .watchTdfFile(
              directoryPath: androidDir.path,
              targetFileName: 'tasks.tdf',
              inMemory: false,
              isAndroid: true,
            )
            .isEmpty,
        isTrue,
        reason: 'LocalFileOperations.watchTdfFile must return an empty stream when isAndroid is true',
      );

      final traversalRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: '../escape.tdf'),
        baseDirectoryPath: watchTempRoot.path,
      );
      expect(traversalRepo.directoryExists(), isFalse);
      expect(await traversalRepo.watchTdfChanges().isEmpty, isTrue);

      final missingDirPath = '${watchTempRoot.path}/not_created_yet';
      final missingDirRepo = LocalFileRepository(
        config: const WebDavConfig(),
        baseDirectoryPath: missingDirPath,
      );
      expect(missingDirRepo.directoryExists(), isFalse);
      expect(await missingDirRepo.watchTdfChanges().isEmpty, isTrue);

      if (!FileSystemEntity.isWatchSupported) {
        return;
      }

      final watchedDir = Directory('${watchTempRoot.path}/watched')
        ..createSync(recursive: true);
      final externalStagingDir = Directory('${watchTempRoot.path}/staging')
        ..createSync(recursive: true);
      final repo = LocalFileRepository(
        config: const WebDavConfig(),
        baseDirectoryPath: watchedDir.path,
      );
      expect(repo.canWatchDirectory, isTrue);
      expect(repo.directoryExists(), isTrue);

      var eventCount = 0;
      Completer<void>? nextEvent;
      final doneCompleter = Completer<void>();

      final subscription = repo.watchTdfChanges().listen(
        (_) {
          eventCount++;
          if (nextEvent case final pending? when !pending.isCompleted) {
            pending.complete();
          }
        },
        onDone: () {
          if (!doneCompleter.isCompleted) {
            doneCompleter.complete();
          }
        },
      );
      addTearDown(subscription.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Noise files and delete events must not emit notifications.
      File('${watchedDir.path}/work.tdf').writeAsStringSync('tdf 0.8.0\n');
      File('${watchedDir.path}/.tasks.tdf.tmp.0123456789abcdef0123456789abcdef')
          .writeAsStringSync('staging');
      File('${watchedDir.path}/tasks.tdf.bak').writeAsStringSync('backup');
      File('${watchedDir.path}/tiertask_2026-11-14_linux_tasks.log')
          .writeAsStringSync('log line\n');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        eventCount,
        equals(0),
        reason: 'Sibling .tdf, .tmp, .bak, and .log writes must be ignored',
      );

      // 1. Direct writeAsString on target file.
      nextEvent = Completer<void>();
      final targetFile = File(repo.resolveFilePath());
      await targetFile.writeAsString('tdf 0.8.0\n', flush: true);
      await nextEvent.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final countBeforeDelete = eventCount;
      targetFile.deleteSync();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        eventCount,
        equals(countBeforeDelete),
        reason: 'FileSystemDeleteEvent on tasks.tdf must be ignored',
      );

      // 2. Same-directory atomic .tmp -> rename save.
      nextEvent = Completer<void>();
      final countBeforeAtomic = eventCount;
      await repo.saveTdf(
        'tdf 0.8.0\n\nqueue {\n    modified 2026-11-01 08:00\n}\n',
      );
      await nextEvent.future.timeout(const Duration(seconds: 3));
      expect(eventCount, greaterThan(countBeforeAtomic));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // 3. Cross-directory rename onto target file.
      nextEvent = Completer<void>();
      final countBeforeCrossDir = eventCount;
      final stagedExternal = File('${externalStagingDir.path}/incoming.tmp')
        ..writeAsStringSync('tdf 0.8.0\n', flush: true);
      stagedExternal.renameSync(repo.resolveFilePath());
      await nextEvent.future.timeout(const Duration(seconds: 3));
      expect(eventCount, greaterThan(countBeforeCrossDir));

      // Runtime watched-directory deletion must not emit uncaught errors or duplicate local.watch.stop events.
      AppLogger.resetForTesting();
      addTearDown(AppLogger.resetForTesting);
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
      );
      watchedDir.deleteSync(recursive: true);
      await Future.any(<Future<void>>[
        doneCompleter.future,
        Future<void>.delayed(const Duration(milliseconds: 120)),
      ]);
      await subscription.cancel();
      final stopLines = AppLogger.lines
          .where((line) => line.contains('local.watch.stop'))
          .toList();
      expect(
        stopLines.length,
        equals(1),
        reason: 'Closing watch stream on directory deletion plus cancel() must emit local.watch.stop exactly once',
      );
    });
  });

  group('LocalFileRepository withExclusiveTargetLock On-Disk & In-Memory Serialization', () {
    late Directory lockTempRoot;

    setUp(() async {
      lockTempRoot = await Directory.systemTemp.createTemp(
        'tiertask_repo_lock_',
      );
    });

    tearDown(() async {
      if (await lockTempRoot.exists()) {
        await lockTempRoot.delete(recursive: true);
      }
    });

    test('serializes on-disk callers via HostFileLockManager and allows nested saveTdf/wipeTdf/initializeIfMissing without self-deadlock', () async {
      final workspaceDir = Directory('${lockTempRoot.path}/workspace')
        ..createSync(recursive: true);
      final customLockDir = Directory('${lockTempRoot.path}/host_locks');

      final repositoryA = LocalFileRepository(
        config: const WebDavConfig(),
        baseDirectoryPath: workspaceDir.path,
        hostLockDirectoryOverride: customLockDir.path,
        lockAcquireTimeout: const Duration(seconds: 2),
      );
      final repositoryB = LocalFileRepository(
        config: const WebDavConfig(),
        baseDirectoryPath: workspaceDir.path,
        hostLockDirectoryOverride: customLockDir.path,
        lockAcquireTimeout: const Duration(seconds: 2),
      );

      final events = <String>[];
      final aEntered = Completer<void>();
      final releaseA = Completer<void>();

      final futureA = repositoryA.withExclusiveTargetLock(() async {
        events.add('A:start');
        aEntered.complete();
        await releaseA.future;
        await repositoryA.initializeIfMissing();
        await repositoryA.saveTdf('tdf 0.8.0\n# nested-save\n');
        final snapshot = await repositoryA.readTdfWithDigest();
        expect(snapshot.content, equals('tdf 0.8.0\n# nested-save\n'));
        events.add('A:end');
        return snapshot.digest;
      });

      await aEntered.future;

      final futureB = repositoryB.withExclusiveTargetLock(() async {
        events.add('B:start');
        await repositoryB.wipeTdf(createBackup: true);
        events.add('B:end');
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        events,
        equals(<String>['A:start']),
        reason: 'Second repository instance must wait on shared target lock',
      );

      releaseA.complete();
      final digestA = await futureA;
      await futureB;

      expect(digestA, isNotNull);
      expect(events, equals(<String>['A:start', 'A:end', 'B:start', 'B:end']));
      expect(await repositoryB.loadTdf(), equals('tdf 0.8.0\n'));
      expect(
        File('${workspaceDir.path}/tasks.tdf.bak').readAsStringSync(),
        equals('tdf 0.8.0\n# nested-save\n'),
      );
      expect(
        customLockDir.existsSync(),
        isTrue,
        reason: 'On-disk repository lock must use hostLockDirectoryOverride',
      );
      expect(customLockDir.listSync().single.path, endsWith('.lock'));
    });

    test('serializes hermetic inMemoryStore callers via in-process mutex without touching host disk and supports nested saveTdf', () async {
      final nonExistentLockDir = Directory(
        '${lockTempRoot.path}/must_not_be_created',
      );
      final sharedStore = <String, String>{};
      final inMemoryRepoA = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'hermetic.tdf'),
        inMemoryStore: sharedStore,
        hostLockDirectoryOverride: nonExistentLockDir.path,
      );
      final inMemoryRepoB = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'hermetic.tdf'),
        inMemoryStore: sharedStore,
        hostLockDirectoryOverride: nonExistentLockDir.path,
      );

      final order = <String>[];
      final entered = Completer<void>();
      final proceed = Completer<void>();

      final first = inMemoryRepoA.withExclusiveTargetLock(() async {
        order.add('mem1:enter');
        entered.complete();
        await proceed.future;
        await inMemoryRepoA.saveTdf('tdf 0.8.0\n# mem1\n');
        order.add('mem1:exit');
      });

      await entered.future;

      final second = inMemoryRepoB.withExclusiveTargetLock(() async {
        order.add('mem2:enter');
        final previous = await inMemoryRepoB.loadTdf();
        expect(previous, equals('tdf 0.8.0\n# mem1\n'));
        await inMemoryRepoB.saveTdf('tdf 0.8.0\n# mem2\n');
        order.add('mem2:exit');
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(order, equals(<String>['mem1:enter']));

      proceed.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(
        order,
        equals(<String>['mem1:enter', 'mem1:exit', 'mem2:enter', 'mem2:exit']),
      );
      expect(await inMemoryRepoB.loadTdf(), equals('tdf 0.8.0\n# mem2\n'));
      expect(
        nonExistentLockDir.existsSync(),
        isFalse,
        reason: 'Hermetic inMemoryStore lock must not create host lock directory or files on disk',
      );
    });
  });

  group('LocalFileRepository Build Profile Isolation', () {
    test('separates release (tiertask) and dev (tiertask-dev) default directories across Linux, Windows, and temp fallback', () {
      expect(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: AppBuildProfile.release,
          environment: const <String, String>{
            'XDG_DATA_HOME': '/home/alice/.local/custom-share',
          },
          isWindows: false,
        ),
        equals('/home/alice/.local/custom-share/tiertask'),
        reason: 'Release profile must preserve XDG_DATA_HOME/tiertask',
      );
      expect(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: AppBuildProfile.dev,
          environment: const <String, String>{
            'XDG_DATA_HOME': '/home/alice/.local/custom-share',
          },
          isWindows: false,
        ),
        equals('/home/alice/.local/custom-share/tiertask-dev'),
        reason: 'Dev profile must isolate under XDG_DATA_HOME/tiertask-dev',
      );
      expect(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: AppBuildProfile.release,
          environment: const <String, String>{'HOME': '/home/alice'},
          isWindows: false,
        ),
        equals('/home/alice/.local/share/tiertask'),
      );
      expect(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: AppBuildProfile.dev,
          environment: const <String, String>{'HOME': '/home/alice'},
          isWindows: false,
        ),
        equals('/home/alice/.local/share/tiertask-dev'),
      );
      expect(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: AppBuildProfile.release,
          environment: const <String, String>{
            'APPDATA': r'C:\Users\Alice\AppData\Roaming',
          },
          isWindows: true,
        ),
        equals(r'C:\Users\Alice\AppData\Roaming\tiertask'),
      );
      expect(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: AppBuildProfile.dev,
          environment: const <String, String>{
            'APPDATA': r'C:\Users\Alice\AppData\Roaming',
          },
          isWindows: true,
        ),
        equals(r'C:\Users\Alice\AppData\Roaming\tiertask-dev'),
      );
      expect(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: AppBuildProfile.release,
          environment: const <String, String>{},
          isWindows: false,
        ),
        equals(Directory.systemTemp.path),
        reason: 'Release fallback without HOME/XDG must remain unchanged',
      );
      expect(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: AppBuildProfile.dev,
          environment: const <String, String>{},
          isWindows: false,
        ),
        endsWith('/tiertask-dev'),
        reason: 'Dev fallback without HOME/XDG must still isolate into tiertask-dev',
      );
    });

    test('isolates relative .tdf and log paths by buildProfile', () {
      final releaseRepo = LocalFileRepository(
        config: const WebDavConfig(),
        buildProfile: AppBuildProfile.release,
      );
      final devRepo = LocalFileRepository(
        config: const WebDavConfig(),
        buildProfile: AppBuildProfile.dev,
      );
      expect(
        releaseRepo.resolveFilePath(),
        isNot(equals(devRepo.resolveFilePath())),
        reason: 'Release and dev relative .tdf paths must never collide',
      );
      expect(
        devRepo.resolveDirectoryPath(),
        endsWith('tiertask-dev'),
        reason: 'Dev relative .tdf must resolve inside tiertask-dev',
      );
      final releaseLog = LocalFileRepository.defaultLogFilePath(
        buildProfile: AppBuildProfile.release,
      );
      final devLog = LocalFileRepository.defaultLogFilePath(
        buildProfile: AppBuildProfile.dev,
      );
      expect(
        releaseLog,
        isNot(equals(devLog)),
        reason: 'Release and dev default log paths must never collide',
      );
      expect(
        devLog,
        contains('tiertask-dev'),
        reason: 'Dev log file must resolve inside tiertask-dev',
      );
    });
  });

  group('LocalFileRepository Hardening, Locking & Android Context.filesDir', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'tiertask_hardening_test_',
      );
      AppLogger.resetForTesting();
      LocalFileRepository.resetAndroidFilesDirectoryCacheForTesting();
    });

    tearDown(() async {
      AppLogger.resetForTesting();
      LocalFileRepository.resetAndroidFilesDirectoryCacheForTesting();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('caches HostFileLockManager instance and rejects symlinks, directories, sockets, and oversized reads via bounded RandomAccessFile', () async {
      final workDir = Directory('${tempRoot.path}/read_checks')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks');

      final repo = LocalFileRepository(
        config: const WebDavConfig(),
        baseDirectoryPath: workDir.path,
        hostLockDirectoryOverride: lockDir.path,
        maxFileBytes: 32,
      );
      expect(
        identical(repo.lockManagerForTesting, repo.lockManagerForTesting),
        isTrue,
        reason: '_lockManager must be cached as a single final instance',
      );

      // Exact boundary (32 bytes) succeeds, 33 bytes fails cleanly.
      final targetPath = repo.resolveFilePath();
      File(targetPath).writeAsStringSync('A' * 32, flush: true);
      final exactSnapshot = await repo.readTdfWithDigest();
      expect(exactSnapshot.exists, isTrue);
      expect(exactSnapshot.content.length, equals(32));

      File(targetPath).writeAsStringSync('A' * 33, flush: true);
      await expectLater(
        repo.readTdfWithDigest,
        throwsA(isA<LocalFileException>()),
        reason: 'Payload of maxFileBytes + 1 must be rejected by bounded read',
      );

      // Symlink at targetPath must be rejected without reading target.
      File(targetPath).deleteSync();
      final secretFile = File('${tempRoot.path}/secret.txt')
        ..writeAsStringSync('top-secret', flush: true);
      Link(targetPath).createSync(secretFile.path);
      await expectLater(
        repo.loadTdf,
        throwsA(isA<LocalFileException>()),
        reason: 'loadTdf must reject symlinks without following them',
      );
      Link(targetPath).deleteSync();

      // Directory at targetPath must be rejected.
      Directory(targetPath).createSync();
      await expectLater(
        repo.readTdfWithDigest,
        throwsA(isA<LocalFileException>()),
        reason: 'readTdfWithDigest must reject directory targets',
      );
      Directory(targetPath).deleteSync();

      // Unix domain socket must be rejected on Linux.
      if (Platform.isLinux) {
        final serverSocket = await ServerSocket.bind(
          InternetAddress(targetPath, type: InternetAddressType.unix),
          0,
        );
        addTearDown(serverSocket.close);
        await expectLater(
          repo.loadTdf,
          throwsA(isA<LocalFileException>()),
          reason: 'loadTdf must reject Unix domain sockets',
        );
      }
    });

    test('serializes deleteTdf, renameTdf, and moveTdfFile under _lockManager.withExclusiveLock', () async {
      final workDir = Directory('${tempRoot.path}/lock_ops')
        ..createSync(recursive: true);
      final moveDir = Directory('${tempRoot.path}/move_ops')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/op_locks');

      final repo = LocalFileRepository(
        config: const WebDavConfig(),
        baseDirectoryPath: workDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      await repo.saveTdf('tdf 0.8.0\n# locked\n');

      // 1. renameTdf waits while target lock is held.
      final renameGate = Completer<void>();
      final renameHolderEntered = Completer<void>();
      var renameFinished = false;
      final holder1 = repo.withExclusiveTargetLock(() async {
        renameHolderEntered.complete();
        await renameGate.future;
      });
      await renameHolderEntered.future;
      final renameFuture = repo.renameTdf('renamed').then((value) {
        renameFinished = true;
        return value;
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        renameFinished,
        isFalse,
        reason: 'renameTdf must wait for exclusive lock on source file',
      );
      renameGate.complete();
      await holder1;
      final renamedPath = await renameFuture;
      expect(File(renamedPath).existsSync(), isTrue);

      // 2. moveTdfFile waits while source lock is held.
      final renamedRepo = LocalFileRepository(
        config: WebDavConfig(localFilePath: renamedPath),
        hostLockDirectoryOverride: lockDir.path,
      );
      final movedTargetRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'moved.tdf'),
        baseDirectoryPath: moveDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      final moveGate = Completer<void>();
      final moveHolderEntered = Completer<void>();
      var moveFinished = false;
      final holder2 = renamedRepo.withExclusiveTargetLock(() async {
        moveHolderEntered.complete();
        await moveGate.future;
      });
      await moveHolderEntered.future;
      final moveFuture = renamedRepo.moveTdfFile(movedTargetRepo).then((_) {
        moveFinished = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        moveFinished,
        isFalse,
        reason: 'moveTdfFile must wait for exclusive lock',
      );
      moveGate.complete();
      await holder2;
      await moveFuture;
      expect(File(movedTargetRepo.resolveFilePath()).existsSync(), isTrue);

      // 3. deleteTdf waits while target lock is held.
      final deleteGate = Completer<void>();
      final deleteHolderEntered = Completer<void>();
      var deleteFinished = false;
      final holder3 = movedTargetRepo.withExclusiveTargetLock(() async {
        deleteHolderEntered.complete();
        await deleteGate.future;
      });
      await deleteHolderEntered.future;
      final deleteFuture = movedTargetRepo.deleteTdf().then((_) {
        deleteFinished = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        deleteFinished,
        isFalse,
        reason: 'deleteTdf must wait for exclusive lock',
      );
      deleteGate.complete();
      await holder3;
      await deleteFuture;
      expect(File(movedTargetRepo.resolveFilePath()).existsSync(), isFalse);
    });

    test('resolves Android Context.filesDir for .tdf and diagnostic logs, migrates legacy cacheDir regular files safely once, and skips symlinks or existing files', () async {
      AppLogger.setEnabled(true, persistToDisk: false);

      final androidFilesDir = Directory('${tempRoot.path}/android_files')
        ..createSync(recursive: true);
      final legacyCacheDir = Directory('${tempRoot.path}/android_cache')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/android_locks');

      // 1. Static Android cache populates default directory & diagnostic log paths.
      final initialized =
          await LocalFileRepository.ensureAndroidFilesDirectoryInitialized(
            resolver: () async => androidFilesDir.path,
          );
      expect(initialized, equals(androidFilesDir.path));
      expect(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: AppBuildProfile.release,
        ),
        equals('${androidFilesDir.path}${Platform.pathSeparator}tiertask'),
        reason:
            'Android default directory must resolve inside persistent filesDir',
      );
      expect(
        LocalFileRepository.defaultLogFilePath(
          buildProfile: AppBuildProfile.release,
        ),
        equals(
          '${androidFilesDir.path}${Platform.pathSeparator}tiertask'
          '${Platform.pathSeparator}tiertask.log',
        ),
        reason:
            'Android diagnostic logs must resolve inside persistent filesDir',
      );

      // 2. Release legacy file in cacheDir migrates atomically into filesDir/tiertask and logs storage.android_cache_migrated.
      const legacyContent =
          'tdf 0.8.0\n\ntask 000001OkD2 {\n    name "Migrated Android Task"\n    created 2026-11-01 08:00\n}\n';
      final legacyReleaseFile = File(
        '${legacyCacheDir.path}${Platform.pathSeparator}tasks.tdf',
      )..writeAsStringSync(legacyContent, flush: true);

      final releaseRepo = LocalFileRepository(
        config: const WebDavConfig(),
        buildProfile: AppBuildProfile.release,
        hostLockDirectoryOverride: lockDir.path,
        androidFilesDirectoryResolver: () async => androidFilesDir.path,
        legacyAndroidCacheDirectoryOverride: legacyCacheDir.path,
      );
      final loaded = await releaseRepo.loadTdf();
      expect(loaded, equals(legacyContent));
      final migratedPath =
          '${androidFilesDir.path}${Platform.pathSeparator}tiertask'
          '${Platform.pathSeparator}tasks.tdf';
      expect(
        File(migratedPath).readAsStringSync(),
        equals(legacyContent),
        reason: 'Legacy Android cacheDir .tdf must be migrated into persistent filesDir',
      );
      expect(
        legacyReleaseFile.existsSync(),
        isFalse,
        reason:
            'Legacy cacheDir file must be cleaned up after durable migration',
      );
      expect(
        AppLogger.fullLogText,
        contains('storage.android_cache_migrated'),
        reason: 'Migration must emit storage.android_cache_migrated diagnostic event',
      );

      // 3. Existing target in filesDir must NEVER be overwritten by a stale legacy cacheDir file.
      final staleLegacyFile = File(
        '${legacyCacheDir.path}${Platform.pathSeparator}tasks.tdf',
      )..writeAsStringSync('tdf 0.8.0\n# stale\n', flush: true);
      final secondReleaseRepo = LocalFileRepository(
        config: const WebDavConfig(),
        buildProfile: AppBuildProfile.release,
        hostLockDirectoryOverride: lockDir.path,
        androidFilesDirectoryResolver: () async => androidFilesDir.path,
        legacyAndroidCacheDirectoryOverride: legacyCacheDir.path,
      );
      expect(await secondReleaseRepo.loadTdf(), equals(legacyContent));
      expect(staleLegacyFile.existsSync(), isTrue);

      // 4. Dev profile migrates from <cacheDir>/tiertask-dev/<file> to <filesDir>/tiertask-dev/<file>.
      final legacyDevDir = Directory(
        '${legacyCacheDir.path}${Platform.pathSeparator}tiertask-dev',
      )..createSync(recursive: true);
      final legacyDevFile = File(
        '${legacyDevDir.path}${Platform.pathSeparator}dev_board.tdf',
      )..writeAsStringSync('tdf 0.8.0\n# dev-migrated\n', flush: true);
      final devRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'dev_board.tdf'),
        buildProfile: AppBuildProfile.dev,
        hostLockDirectoryOverride: lockDir.path,
        androidFilesDirectoryResolver: () async => androidFilesDir.path,
        legacyAndroidCacheDirectoryOverride: legacyCacheDir.path,
      );
      expect(await devRepo.loadTdf(), equals('tdf 0.8.0\n# dev-migrated\n'));
      expect(legacyDevFile.existsSync(), isFalse);

      // 5. Symlink in legacy cacheDir must NEVER be followed or migrated.
      final secretOutside = File('${tempRoot.path}/outside_secret.txt')
        ..writeAsStringSync('do-not-migrate', flush: true);
      final legacySymlink = Link(
        '${legacyCacheDir.path}${Platform.pathSeparator}symlink_board.tdf',
      )..createSync(secretOutside.path);
      final symlinkRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'symlink_board.tdf'),
        buildProfile: AppBuildProfile.release,
        hostLockDirectoryOverride: lockDir.path,
        androidFilesDirectoryResolver: () async => androidFilesDir.path,
        legacyAndroidCacheDirectoryOverride: legacyCacheDir.path,
      );
      expect(await symlinkRepo.loadTdf(), isEmpty);
      expect(
        File(
          '${androidFilesDir.path}${Platform.pathSeparator}tiertask'
          '${Platform.pathSeparator}symlink_board.tdf',
        ).existsSync(),
        isFalse,
        reason: 'Symlink at legacy cacheDir path must never be migrated',
      );
      expect(legacySymlink.existsSync(), isTrue);

      // 6. Broken Android resolver fails with LocalFileException instead of silently falling back to cacheDir.
      final brokenRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'broken.tdf'),
        buildProfile: AppBuildProfile.release,
        hostLockDirectoryOverride: lockDir.path,
        androidFilesDirectoryResolver: () async => null,
      );
      await expectLater(
        brokenRepo.loadTdf,
        throwsA(isA<LocalFileException>()),
        reason: 'Missing Android filesDir must fail rather than falling back to volatile cacheDir',
      );
    });

    test('readBoundedRegularFileBytes reads asynchronously within maxBytes and rejects oversized files and symlinks', () async {
      const operations = LocalFileOperations<LocalFileException>(
        LocalFileException.new,
      );
      final messages = AppLocalizationsEn();
      final validFile = File('${tempRoot.path}/async_bounded.tdf')
        ..writeAsStringSync('tdf 0.8.0\n', flush: true);

      final Future<List<int>> readFuture = operations
          .readBoundedRegularFileBytes(validFile.path, 10, messages);
      final bytes = await readFuture;
      expect(bytes.length, equals(10));

      await expectLater(
        () =>
            operations.readBoundedRegularFileBytes(validFile.path, 9, messages),
        throwsA(isA<LocalFileException>()),
        reason: 'Async bounded reader must reject files larger than maxBytes',
      );

      final linkPath = '${tempRoot.path}/async_link.tdf';
      Link(linkPath).createSync(validFile.path);
      await expectLater(
        () => operations.readBoundedRegularFileBytes(linkPath, 64, messages),
        throwsA(isA<LocalFileException>()),
        reason:
            'Async bounded reader must keep followLinks:false symlink guard',
      );
    });

    test('readBoundedRegularFileBytes and readTdfWithDigest enforce bounds across the 32 KiB sync/async offload threshold', () async {
      const threshold = LocalFileOperations.asyncReadThresholdBytes;
      expect(threshold, equals(32768));

      const operations = LocalFileOperations<LocalFileException>(
        LocalFileException.new,
      );
      final messages = AppLocalizationsEn();

      final belowThresholdText = 'tdf 0.8.0\n# ${'a' * (threshold - 14)}\n';
      expect(utf8.encode(belowThresholdText).length, equals(threshold - 1));
      final belowFile = File('${tempRoot.path}/below_threshold.tdf')
        ..writeAsStringSync(belowThresholdText, flush: true);

      final belowBytes = await operations.readBoundedRegularFileBytes(
        belowFile.path,
        threshold - 1,
        messages,
      );
      expect(belowBytes.length, equals(threshold - 1));
      await expectLater(
        () => operations.readBoundedRegularFileBytes(
          belowFile.path,
          threshold - 2,
          messages,
        ),
        throwsA(isA<LocalFileException>()),
        reason: 'Small sync-read path must still enforce exact maxBytes bound',
      );

      final atThresholdText = 'tdf 0.8.0\n# ${'b' * (threshold - 13)}\n';
      expect(utf8.encode(atThresholdText).length, equals(threshold));
      final atThresholdFile = File('${tempRoot.path}/at_threshold.tdf')
        ..writeAsStringSync(atThresholdText, flush: true);

      final atThresholdBytes = await operations.readBoundedRegularFileBytes(
        atThresholdFile.path,
        threshold,
        messages,
      );
      expect(atThresholdBytes.length, equals(threshold));
      await expectLater(
        () => operations.readBoundedRegularFileBytes(
          atThresholdFile.path,
          threshold - 1,
          messages,
        ),
        throwsA(isA<LocalFileException>()),
        reason: 'Large async-read path must still enforce exact maxBytes bound',
      );

      final largeRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'at_threshold.tdf'),
        baseDirectoryPath: tempRoot.path,
      );
      final largeSnapshot = await largeRepo.readTdfWithDigest();
      expect(largeSnapshot.exists, isTrue);
      expect(largeSnapshot.content, equals(atThresholdText));
      expect(
        largeSnapshot.digest,
        equals(Sha256Service.hashHex(utf8.encode(atThresholdText))),
        reason: 'Large >= 32 KiB readTdfWithDigest must compute exact SHA-256 digest via Isolate.run',
      );
    });

    testWidgets(
      'readTdfWithDigest completes small disk-backed reads inside FakeAsync without stalling',
      (tester) async {
        final smallFile = File('${tempRoot.path}/fake_async_small.tdf')
          ..writeAsStringSync('tdf 0.8.0\n', flush: true);
        final repository = LocalFileRepository(
          config: WebDavConfig(localFilePath: smallFile.path),
        );

        ({String content, String? digest, bool exists})? snapshot;
        await repository.readTdfWithDigest().then((value) {
          snapshot = value;
        });
        await tester.pumpAndSettle();

        expect(snapshot?.exists, isTrue);
        expect(snapshot?.content, equals('tdf 0.8.0\n'));
        expect(
          snapshot?.digest,
          equals(Sha256Service.hashHex(utf8.encode('tdf 0.8.0\n'))),
        );
      },
    );

    test('languageResolver dynamically updates LocalFileRepository error localization without recreating the repository', () {
      var activeLanguage = AppLanguage.english;
      final repository = LocalFileRepository(
        config: const WebDavConfig(
          localFilePath: '../escape.tdf',
          language: AppLanguage.english,
        ),
        baseDirectoryPath: tempRoot.path,
        languageResolver: () => activeLanguage,
      );

      expect(
        repository.resolveFilePath,
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(AppLocalizationsEn().errorInvalidLocalFilePath),
          ),
        ),
      );

      activeLanguage = AppLanguage.german;
      expect(
        repository.resolveFilePath,
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(AppLocalizationsDe().errorInvalidLocalFilePath),
          ),
        ),
        reason: 'Dynamic languageResolver must localize errors in German without recreating LocalFileRepository',
      );
    });

    test('wipeTdf and initializeIfMissing reject Unix domain sockets and FIFO pipes, and wipeTdf backup enforces maxFileBytes with atomic 0600 write', () async {
      final workDir = Directory('${tempRoot.path}/wipe_init_hardening')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/wipe_init_locks');

      final repo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'target.tdf'),
        baseDirectoryPath: workDir.path,
        hostLockDirectoryOverride: lockDir.path,
        maxFileBytes: 64,
      );
      final targetPath = repo.resolveFilePath();

      if (Platform.isLinux) {
        // 1. Unix domain socket must be rejected by both initializeIfMissing and wipeTdf.
        final unixSocket = await ServerSocket.bind(
          InternetAddress(targetPath, type: InternetAddressType.unix),
          0,
        );
        try {
          await expectLater(
            repo.initializeIfMissing,
            throwsA(isA<LocalFileException>()),
            reason: 'initializeIfMissing must reject Unix domain sockets',
          );
          await expectLater(
            () => repo.wipeTdf(createBackup: true),
            throwsA(isA<LocalFileException>()),
            reason: 'wipeTdf must reject Unix domain sockets',
          );
        } finally {
          await unixSocket.close();
          if (FileSystemEntity.typeSync(targetPath, followLinks: false) !=
              FileSystemEntityType.notFound) {
            File(targetPath).deleteSync();
          }
        }

        // 2. FIFO named pipe must be rejected by both initializeIfMissing and wipeTdf.
        final mkfifoResult = Process.runSync('mkfifo', <String>[targetPath]);
        if (mkfifoResult.exitCode == 0) {
          try {
            await expectLater(
              repo.initializeIfMissing,
              throwsA(isA<LocalFileException>()),
              reason: 'initializeIfMissing must reject FIFO pipes',
            );
            await expectLater(
              () => repo.wipeTdf(createBackup: true),
              throwsA(isA<LocalFileException>()),
              reason: 'wipeTdf must reject FIFO pipes',
            );
          } finally {
            if (FileSystemEntity.typeSync(targetPath, followLinks: false) !=
                FileSystemEntityType.notFound) {
              File(targetPath).deleteSync();
            }
          }
        }
      }

      // 3. Oversized file (> maxFileBytes) must fail bounded wipe backup instead of unbounded copySync.
      File(targetPath).writeAsStringSync('X' * 65, flush: true);
      await expectLater(
        () => repo.wipeTdf(createBackup: true),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(AppLocalizationsEn().errorLocalFileTooLarge),
          ),
        ),
        reason: 'wipeTdf backup must enforce maxFileBytes via bounded read',
      );
      expect(
        File('$targetPath.bak').existsSync(),
        isFalse,
        reason: 'Rejected oversized backup must not create partial .bak file',
      );

      // 4. Valid file within maxFileBytes writes .bak atomically with 0600 mode on POSIX.
      File(targetPath)
          .writeAsStringSync('tdf 0.8.0\n# backup-me\n', flush: true);
      if (Platform.isLinux) {
        Process.runSync('chmod', <String>['0644', targetPath]);
      }
      await repo.wipeTdf(createBackup: true);
      final backupFile = File('$targetPath.bak');
      expect(backupFile.existsSync(), isTrue);
      expect(backupFile.readAsStringSync(), equals('tdf 0.8.0\n# backup-me\n'));
      if (Platform.isLinux) {
        expect(
          backupFile.statSync().mode & 0x1FF,
          equals(0x180),
          reason: 'Atomic wipe backup must enforce 0600 permissions on POSIX',
        );
      }
    });

    test('loadTdf, saveTdf, and wipeTdf use static safe summaries instead of raw error.toString() while preserving cause', () async {
      final workDir = Directory('${tempRoot.path}/safe_errors')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/safe_error_locks');

      final diskRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'invalid_utf8.tdf'),
        baseDirectoryPath: workDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      File(diskRepo.resolveFilePath())
          .writeAsBytesSync(const <int>[0xFF, 0xFE, 0xFD], flush: true);

      await expectLater(
        diskRepo.loadTdf,
        throwsA(
          isA<LocalFileException>()
              .having((error) => error.cause, 'cause', isA<FormatException>())
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('Invalid UTF-8 encoding'),
                  isNot(contains('FormatException')),
                  isNot(contains('Unexpected extension byte')),
                ),
              ),
        ),
        reason: 'loadTdf must not leak raw FormatException.toString() into user-facing message',
      );

      // Trigger non-FileSystemException runtime error in saveTdf and wipeTdf via unmodifiable inMemoryStore.
      final readOnlyMemoryRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'unmodifiable.tdf'),
        inMemoryStore: const <String, String>{},
      );
      await expectLater(
        () => readOnlyMemoryRepo.saveTdf('tdf 0.8.0\n'),
        throwsA(
          isA<LocalFileException>()
              .having((error) => error.cause, 'cause', isA<UnsupportedError>())
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('Unexpected storage error'),
                  isNot(contains('UnsupportedError')),
                  isNot(contains('unmodifiable')),
                ),
              ),
        ),
        reason: 'saveTdf must not leak raw runtime error.toString() into user-facing message',
      );
      await expectLater(
        () => readOnlyMemoryRepo.wipeTdf(),
        throwsA(
          isA<LocalFileException>()
              .having((error) => error.cause, 'cause', isA<UnsupportedError>())
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('Unexpected storage error'),
                  isNot(contains('UnsupportedError')),
                  isNot(contains('unmodifiable')),
                ),
              ),
        ),
        reason: 'wipeTdf must not leak raw runtime error.toString() into user-facing message',
      );
    });

    test('LocalFileRepository async entrypoints initialize process-wide Android Context.filesDir cache before resolving relative paths', () async {
      LocalFileRepository.resetAndroidFilesDirectoryCacheForTesting();
      final androidFilesDir = Directory('${tempRoot.path}/first_boot_android')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/first_boot_locks');

      final repo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'first_boot.tdf'),
        buildProfile: AppBuildProfile.release,
        hostLockDirectoryOverride: lockDir.path,
        androidFilesDirectoryResolver: () async => androidFilesDir.path,
      );

      await repo.initializeIfMissing();
      expect(
        File(
          '${androidFilesDir.path}${Platform.pathSeparator}tiertask'
          '${Platform.pathSeparator}first_boot.tdf',
        ).existsSync(),
        isTrue,
      );
      expect(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: AppBuildProfile.release,
        ),
        equals('${androidFilesDir.path}${Platform.pathSeparator}tiertask'),
        reason: 'LocalFileRepository async entrypoints must initialize the process-wide Android Context.filesDir cache even when run before SecureSettingsRepository',
      );
      expect(
        LocalFileRepository.defaultLogFilePath(
          buildProfile: AppBuildProfile.release,
        ),
        equals(
          '${androidFilesDir.path}${Platform.pathSeparator}tiertask'
          '${Platform.pathSeparator}tiertask.log',
        ),
      );
    });
  });
}
