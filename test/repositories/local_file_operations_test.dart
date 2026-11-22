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
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations_en.dart';
import 'package:tiertask/repositories/host_file_lock.dart';
import 'package:tiertask/repositories/local_file_operations.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/services/app_logger.dart';

/// Fake [Directory] injected via [IOOverrides.runZoned] to control `watch()` streams and errors.
class _FakeWatchDirectory implements Directory {
  _FakeWatchDirectory(
    this.path, {
    required this.existsResult,
    this.watchFactory,
  });

  final bool existsResult;

  @override
  final String path;

  final Stream<FileSystemEvent> Function()? watchFactory;

  @override
  bool existsSync() => existsResult;

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) {
    final factory = watchFactory;
    if (factory == null) {
      return const Stream<FileSystemEvent>.empty();
    }
    return factory();
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected Directory member: ${invocation.memberName}',
  );
}

void main() {
  const operations = LocalFileOperations<LocalFileException>(
    LocalFileException.new,
  );
  final messages = AppLocalizationsEn();

  group('LocalFileOperations OS-Aware Exception Mapping', () {
    test('separates POSIX errno codes from Win32 GetLastError codes without cross-platform collisions', () {
      const path = '/tmp/board.tdf';
      final cases =
          <({int code, bool isWindows, String expected, String description})>[
            // Overlapping numeric codes with completely different OS meanings.
            (
              code: 39,
              isWindows: false,
              expected: messages.errorMoveTargetDirectoryExists(path),
              description: 'POSIX 39 is ENOTEMPTY (target directory exists)',
            ),
            (
              code: 39,
              isWindows: true,
              expected: messages.errorMoveDiskFull(path),
              description: 'Windows 39 is ERROR_HANDLE_DISK_FULL',
            ),
            (
              code: 17,
              isWindows: false,
              expected: messages.errorMoveTargetFileExists(path),
              description: 'POSIX 17 is EEXIST',
            ),
            (
              code: 17,
              isWindows: true,
              expected: messages.errorMoveLocalFileFailed('raw error ($path)'),
              description: 'Windows 17 is ERROR_NOT_SAME_DEVICE and must not map to EEXIST',
            ),
            (
              code: 21,
              isWindows: false,
              expected: messages.errorMoveTargetDirectoryExists(path),
              description: 'POSIX 21 is EISDIR',
            ),
            (
              code: 21,
              isWindows: true,
              expected: messages.errorMoveLocalFileFailed('raw error ($path)'),
              description:
                  'Windows 21 is ERROR_NOT_READY and must not map to EISDIR',
            ),
            // Platform-specific codes that must not leak across OS boundaries.
            (
              code: 28,
              isWindows: false,
              expected: messages.errorMoveDiskFull(path),
              description: 'POSIX 28 is ENOSPC',
            ),
            (
              code: 28,
              isWindows: true,
              expected: messages.errorMoveLocalFileFailed('raw error ($path)'),
              description: 'Windows 28 must not map to POSIX ENOSPC',
            ),
            (
              code: 112,
              isWindows: true,
              expected: messages.errorMoveDiskFull(path),
              description: 'Windows 112 is ERROR_DISK_FULL',
            ),
            (
              code: 112,
              isWindows: false,
              expected: messages.errorMoveLocalFileFailed('raw error ($path)'),
              description: 'POSIX 112 must not map to Windows ERROR_DISK_FULL',
            ),
            (
              code: 183,
              isWindows: true,
              expected: messages.errorMoveTargetFileExists(path),
              description: 'Windows 183 is ERROR_ALREADY_EXISTS',
            ),
            (
              code: 183,
              isWindows: false,
              expected: messages.errorMoveLocalFileFailed('raw error ($path)'),
              description:
                  'POSIX 183 must not map to Windows ERROR_ALREADY_EXISTS',
            ),
            (
              code: 5,
              isWindows: true,
              expected: messages.errorMovePermissionDenied(path),
              description: 'Windows 5 is ERROR_ACCESS_DENIED',
            ),
            (
              code: 5,
              isWindows: false,
              expected: messages.errorMoveLocalFileFailed('raw error ($path)'),
              description: 'POSIX 5 is EIO and must not map to Windows ERROR_ACCESS_DENIED',
            ),
            (
              code: 13,
              isWindows: false,
              expected: messages.errorMovePermissionDenied(path),
              description: 'POSIX 13 is EACCES',
            ),
            (
              code: 13,
              isWindows: true,
              expected: messages.errorMoveLocalFileFailed('raw error ($path)'),
              description: 'Windows 13 is ERROR_INVALID_DATA and must not map to POSIX EACCES',
            ),
            (
              code: 30,
              isWindows: false,
              expected: messages.errorMoveReadOnlyFileSystem(path),
              description: 'POSIX 30 is EROFS',
            ),
            (
              code: 30,
              isWindows: true,
              expected: messages.errorMoveLocalFileFailed('raw error ($path)'),
              description: 'Windows 30 is ERROR_READ_FAULT and must not map to POSIX EROFS',
            ),
            (
              code: 32,
              isWindows: true,
              expected: messages.errorMoveFileLocked(path),
              description: 'Windows 32 is ERROR_SHARING_VIOLATION',
            ),
            (
              code: 32,
              isWindows: false,
              expected: messages.errorMoveLocalFileFailed('raw error ($path)'),
              description: 'POSIX 32 is EPIPE and must not map to Windows ERROR_SHARING_VIOLATION',
            ),
            // Remaining mapped POSIX and Win32 error codes.
            (
              code: 1,
              isWindows: false,
              expected: messages.errorMovePermissionDenied(path),
              description: 'POSIX 1 is EPERM',
            ),
            (
              code: 2,
              isWindows: false,
              expected: messages.errorMoveTargetDirectoryNotFound(path),
              description: 'POSIX 2 is ENOENT',
            ),
            (
              code: 16,
              isWindows: false,
              expected: messages.errorMoveFileLocked(path),
              description: 'POSIX 16 is EBUSY',
            ),
            (
              code: 20,
              isWindows: false,
              expected: messages.errorMoveTargetNotADirectory(path),
              description: 'POSIX 20 is ENOTDIR',
            ),
            (
              code: 26,
              isWindows: false,
              expected: messages.errorMoveFileLocked(path),
              description: 'POSIX 26 is ETXTBSY',
            ),
            (
              code: 36,
              isWindows: false,
              expected: messages.errorMovePathTooLong(path),
              description: 'POSIX 36 is ENAMETOOLONG',
            ),
            (
              code: 122,
              isWindows: false,
              expected: messages.errorMoveDiskFull(path),
              description: 'POSIX 122 is EDQUOT',
            ),
            (
              code: 2,
              isWindows: true,
              expected: messages.errorMoveTargetDirectoryNotFound(path),
              description: 'Windows 2 is ERROR_FILE_NOT_FOUND',
            ),
            (
              code: 3,
              isWindows: true,
              expected: messages.errorMoveTargetDirectoryNotFound(path),
              description: 'Windows 3 is ERROR_PATH_NOT_FOUND',
            ),
            (
              code: 19,
              isWindows: true,
              expected: messages.errorMoveReadOnlyFileSystem(path),
              description: 'Windows 19 is ERROR_WRITE_PROTECT',
            ),
            (
              code: 33,
              isWindows: true,
              expected: messages.errorMoveFileLocked(path),
              description: 'Windows 33 is ERROR_LOCK_VIOLATION',
            ),
            (
              code: 80,
              isWindows: true,
              expected: messages.errorMoveTargetFileExists(path),
              description: 'Windows 80 is ERROR_FILE_EXISTS',
            ),
            (
              code: 206,
              isWindows: true,
              expected: messages.errorMovePathTooLong(path),
              description: 'Windows 206 is ERROR_FILENAME_EXCED_RANGE',
            ),
            (
              code: 267,
              isWindows: true,
              expected: messages.errorMoveTargetNotADirectory(path),
              description: 'Windows 267 is ERROR_DIRECTORY',
            ),
            (
              code: 1314,
              isWindows: true,
              expected: messages.errorMovePermissionDenied(path),
              description: 'Windows 1314 is ERROR_PRIVILEGE_NOT_HELD',
            ),
          ];

      for (final entry in cases) {
        final fsError = FileSystemException(
          'Move failed',
          path,
          OSError('raw error', entry.code),
        );
        final mapped = operations.mapMoveFileSystemException(
          fsError,
          '/fallback/tasks.tdf',
          messages,
          isWindows: entry.isWindows,
        );
        expect(
          mapped.message,
          equals(entry.expected),
          reason: entry.description,
        );
        expect(
          identical(mapped.cause, fsError),
          isTrue,
          reason:
              'Original FileSystemException cause must be preserved for ${entry.description}',
        );
      }
    });

    test('falls back to case-insensitive OS text matching and fallbackPath when errorCode is absent or unknown', () {
      const fallbackPath = '/fallback/tasks.tdf';
      final textCases = <({String osMessage, String expected, String label})>[
        (
          osMessage: 'Permission Denied by policy',
          expected: messages.errorMovePermissionDenied(fallbackPath),
          label: 'permission denied',
        ),
        (
          osMessage: 'Access is denied',
          expected: messages.errorMovePermissionDenied(fallbackPath),
          label: 'access is denied',
        ),
        (
          osMessage: 'Operation not permitted',
          expected: messages.errorMovePermissionDenied(fallbackPath),
          label: 'operation not permitted',
        ),
        (
          osMessage: 'Read-only file system',
          expected: messages.errorMoveReadOnlyFileSystem(fallbackPath),
          label: 'read-only',
        ),
        (
          osMessage: 'No space left on device',
          expected: messages.errorMoveDiskFull(fallbackPath),
          label: 'no space',
        ),
        (
          osMessage: 'Target Disk Full',
          expected: messages.errorMoveDiskFull(fallbackPath),
          label: 'disk full',
        ),
        (
          osMessage: 'Unexpected I/O anomaly',
          expected: messages.errorMoveLocalFileFailed(
            'Unexpected I/O anomaly ($fallbackPath)',
          ),
          label: 'generic OS message',
        ),
      ];

      for (final entry in textCases) {
        final fsError = FileSystemException(
          'Fallback error message',
          '   ',
          OSError(entry.osMessage, 99999),
        );
        final mapped = operations.mapMoveFileSystemException(
          fsError,
          fallbackPath,
          messages,
          isWindows: false,
        );
        expect(
          mapped.message,
          equals(entry.expected),
          reason: 'Text fallback failed for ${entry.label}',
        );
      }

      const noOsError = FileSystemException('Disk full during rename');
      final fromMessageOnly = operations.mapMoveFileSystemException(
        noOsError,
        fallbackPath,
        messages,
        isWindows: true,
      );
      expect(
        fromMessageOnly.message,
        equals(messages.errorMoveDiskFull(fallbackPath)),
        reason: 'Fallback text matcher must inspect error.message when osError is null',
      );
    });
  });

  group('LocalFileOperations Bounded Reads, Deletion & Log I/O', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'tiertask_local_file_ops_',
      );
      AppLogger.resetForTesting();
    });

    tearDown(() async {
      AppLogger.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('readBoundedRegularFileBytes handles sync (<32 KiB) and async (>=32 KiB) paths, enforces maxBytes, and rejects missing/directory/symlink entities', () async {
      // Sync fast path (< 32 KiB) including boundary threshold - 1.
      final smallPath = '${tempDir.path}/small.tdf';
      final smallBytes = Uint8List.fromList(
        List<int>.generate(
          LocalFileOperations.asyncReadThresholdBytes - 1,
          (i) => i & 0xFF,
        ),
      );
      File(smallPath).writeAsBytesSync(smallBytes, flush: true);

      final readSmall = await operations.readBoundedRegularFileBytes(
        smallPath,
        smallBytes.length,
        messages,
      );
      expect(
        readSmall,
        equals(smallBytes),
        reason: 'Sync fast path must return exact bytes at maxBytes boundary',
      );
      await expectLater(
        () => operations.readBoundedRegularFileBytes(
          smallPath,
          smallBytes.length - 1,
          messages,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorLocalFileTooLarge),
          ),
        ),
        reason: 'Sync fast path must reject files exceeding maxBytes',
      );

      // Async path (>= 32 KiB) at exact threshold and above threshold.
      final largePath = '${tempDir.path}/large.tdf';
      final largeBytes = Uint8List.fromList(
        List<int>.generate(
          LocalFileOperations.asyncReadThresholdBytes + 4096,
          (i) => (i * 3) & 0xFF,
        ),
      );
      File(largePath).writeAsBytesSync(largeBytes, flush: true);

      final readLarge = await operations.readBoundedRegularFileBytes(
        largePath,
        largeBytes.length,
        messages,
      );
      expect(
        readLarge,
        equals(largeBytes),
        reason: 'Async path must return exact bytes for files >= 32 KiB',
      );
      await expectLater(
        () => operations.readBoundedRegularFileBytes(
          largePath,
          largeBytes.length - 1,
          messages,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorLocalFileTooLarge),
          ),
        ),
        reason: 'Async path must reject files exceeding maxBytes',
      );

      // Negative maxBytes rejected before opening file.
      await expectLater(
        () => operations.readBoundedRegularFileBytes(smallPath, -1, messages),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorLocalFileTooLarge),
          ),
        ),
      );

      // Missing file throws FileSystemException.
      final missingPath = '${tempDir.path}/does_not_exist.tdf';
      await expectLater(
        () =>
            operations.readBoundedRegularFileBytes(missingPath, 1024, messages),
        throwsA(isA<FileSystemException>()),
        reason: 'Missing file must propagate FileSystemException to caller',
      );

      // Directory rejected cleanly.
      final subdir = Directory('${tempDir.path}/as_dir')..createSync();
      await expectLater(
        () =>
            operations.readBoundedRegularFileBytes(subdir.path, 1024, messages),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorMoveSourceIsDirectory(subdir.path)),
          ),
        ),
      );

      // Symlink rejected cleanly without following link.
      final linkPath = '${tempDir.path}/symlink.tdf';
      Link(linkPath).createSync(smallPath);
      await expectLater(
        () => operations.readBoundedRegularFileBytes(
          linkPath,
          smallBytes.length + 10,
          messages,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorMoveSourceIsSymlink(linkPath)),
          ),
        ),
      );
    });

    test('deleteTdf removes regular files, ignores missing paths, handles in-memory mode, and rejects directories and symlinks', () {
      final inMemoryStore = <String, String>{
        '/virtual/tasks.tdf': 'tdf 0.8.0\n',
      };
      operations.deleteTdf(
        '/virtual/tasks.tdf',
        messages,
        inMemory: true,
        inMemoryStore: inMemoryStore,
      );
      expect(inMemoryStore.containsKey('/virtual/tasks.tdf'), isFalse);

      // Missing file on disk is a no-op.
      expect(
        () => operations.deleteTdf(
          '${tempDir.path}/missing.tdf',
          messages,
          inMemory: false,
        ),
        returnsNormally,
      );

      // Regular file is deleted.
      final targetFile = File('${tempDir.path}/delete_me.tdf')
        ..writeAsStringSync('tdf 0.8.0\n', flush: true);
      operations.deleteTdf(targetFile.path, messages, inMemory: false);
      expect(targetFile.existsSync(), isFalse);

      // Directory is rejected.
      final directoryPath = '${tempDir.path}/protected_dir';
      Directory(directoryPath).createSync();
      expect(
        () => operations.deleteTdf(directoryPath, messages, inMemory: false),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorMoveSourceIsDirectory(directoryPath)),
          ),
        ),
      );
      expect(Directory(directoryPath).existsSync(), isTrue);

      // Symlink is rejected and target remains intact.
      final realTarget = File('${tempDir.path}/real_target.tdf')
        ..writeAsStringSync('tdf 0.8.0\n', flush: true);
      final symlinkPath = '${tempDir.path}/link_to_real.tdf';
      Link(symlinkPath).createSync(realTarget.path);
      expect(
        () => operations.deleteTdf(symlinkPath, messages, inMemory: false),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorMoveSourceIsSymlink(symlinkPath)),
          ),
        ),
      );
      expect(realTarget.existsSync(), isTrue);
      expect(
        FileSystemEntity.typeSync(symlinkPath, followLinks: false),
        equals(FileSystemEntityType.link),
      );
    });

    test('writeLogFileSync creates parent directories, appends/overwrites, enforces POSIX 0600 permissions via FFI, and protects symlinks', () {
      final logPath = '${tempDir.path}/nested/logs/session.log';
      operations.writeLogFileSync(
        logPath,
        'line-1\n',
        append: false,
        flush: true,
      );
      expect(File(logPath).existsSync(), isTrue);
      expect(File(logPath).readAsStringSync(), equals('line-1\n'));

      if (Platform.isLinux) {
        expect(
          File(logPath).statSync().mode & 0x1FF,
          equals(0x180),
          reason: 'Newly created diagnostic log must have POSIX 0600 (0x180) permissions',
        );
      }

      operations.writeLogFileSync(logPath, 'line-2\n', append: true);
      expect(File(logPath).readAsStringSync(), equals('line-1\nline-2\n'));

      // Re-hardens mode on full overwrite after loosening permissions via FFI chmod.
      if (Platform.isLinux) {
        HostFileLockManager.applyPosixChmodBestEffort(logPath, 0x1A4);
        expect(File(logPath).statSync().mode & 0x1FF, equals(0x1A4));
        operations.writeLogFileSync(
          logPath,
          'rewritten\n',
          append: false,
          flush: true,
        );
        expect(
          File(logPath).statSync().mode & 0x1FF,
          equals(0x180),
          reason: 'Overwrite must restore POSIX 0600 (0x180) permissions via FFI without spawning chmod',
        );
      }

      // readLogFileSync reads full and trailing bounded slices.
      expect(
        operations.readLogFileSync(logPath, maxBytes: 1024),
        equals(File(logPath).readAsStringSync()),
      );
      expect(
        operations.readLogFileSync(logPath, maxBytes: 4),
        equals(
          File(logPath)
              .readAsStringSync()
              .substring(File(logPath).readAsStringSync().length - 4),
        ),
      );
      expect(operations.readLogFileSync(logPath, maxBytes: 0), isEmpty);

      // Symlink log paths are ignored so targets are never overwritten.
      final protectedTarget = File('${tempDir.path}/protected.txt')
        ..writeAsStringSync('keep-me', flush: true);
      final symlinkLogPath = '${tempDir.path}/symlink.log';
      Link(symlinkLogPath).createSync(protectedTarget.path);
      operations.writeLogFileSync(
        symlinkLogPath,
        'malicious-overwrite',
        append: false,
      );
      expect(protectedTarget.readAsStringSync(), equals('keep-me'));
      expect(
        operations.readLogFileSync(symlinkLogPath, maxBytes: 1024),
        isEmpty,
      );

      // Directory log paths are ignored safely.
      final dirLogPath = '${tempDir.path}/dir_as_log';
      Directory(dirLogPath).createSync();
      expect(
        () => operations.writeLogFileSync(dirLogPath, 'ignored', append: true),
        returnsNormally,
      );
    });

    test('pruneExpiredLogFilesSync and deleteWorkspaceLogFilesSync isolate logs by workspace and retention limits', () {
      final logsDir = Directory('${tempDir.path}/retention')..createSync();
      final todayUtc = DateTime.utc(2026, 11, 22, 12);
      File('${logsDir.path}/${AppLogger.defaultLogFileName}')
          .writeAsStringSync('legacy', flush: true);
      File('${logsDir.path}/unrelated.txt')
          .writeAsStringSync('keep', flush: true);
      File('${logsDir.path}/tiertask_2026-11-22_linux_otherws.log')
          .writeAsStringSync('other workspace', flush: true);

      // Create 4 dated files for workspace `ws1`: 1 expired (>7 days) + 3 recent, retaining max 2.
      for (final date in <DateTime>[
        DateTime.utc(2026, 11, 10),
        DateTime.utc(2026, 11, 19),
        DateTime.utc(2026, 11, 20),
        DateTime.utc(2026, 11, 22),
      ]) {
        final name = AppLogger.formatLogFileName(
          utcNow: date,
          platform: 'linux',
          workspaceId: 'ws1',
        );
        File('${logsDir.path}/$name').writeAsStringSync('log', flush: true);
      }

      final pruned = operations.pruneExpiredLogFilesSync(
        directoryPath: logsDir.path,
        platform: 'linux',
        workspaceId: 'ws1',
        utcNow: todayUtc,
        maxRetainedFiles: 2,
      );
      expect(
        pruned,
        equals(3),
        reason: 'Should prune legacy tiertask.log, 1 expired file (>7 days), and 1 oldest overflow file',
      );
      expect(
        File('${logsDir.path}/tiertask_2026-11-20_linux_ws1.log').existsSync(),
        isTrue,
      );
      expect(
        File('${logsDir.path}/tiertask_2026-11-22_linux_ws1.log').existsSync(),
        isTrue,
      );
      expect(
        File('${logsDir.path}/tiertask_2026-11-19_linux_ws1.log').existsSync(),
        isFalse,
      );
      expect(
        File('${logsDir.path}/tiertask_2026-11-22_linux_otherws.log')
            .existsSync(),
        isTrue,
      );
      expect(File('${logsDir.path}/unrelated.txt').existsSync(), isTrue);

      final deleted = operations.deleteWorkspaceLogFilesSync(
        directoryPath: logsDir.path,
        platform: 'linux',
        workspaceId: 'ws1',
      );
      expect(deleted, equals(2));
      expect(
        File('${logsDir.path}/tiertask_2026-11-22_linux_otherws.log')
            .existsSync(),
        isTrue,
      );
    });
  });

  group('LocalFileOperations Move, Rename, Backup & Watch Helpers', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_ops_move_');
      AppLogger.resetForTesting();
    });

    tearDown(() async {
      AppLogger.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('moveTdfFile and renameTdf handle disk/in-memory moves, target collisions, non-regular sources, and _verifyDirectoryWritable', () async {
      // In-memory move & collision check.
      final store = <String, String>{'/mem/a.tdf': 'tdf 0.8.0\n'};
      await operations.moveTdfFile(
        '/mem/a.tdf',
        '/mem/b.tdf',
        '/mem',
        1024,
        messages,
        inMemory: true,
        inMemoryStore: store,
      );
      expect(store.containsKey('/mem/a.tdf'), isFalse);
      expect(store['/mem/b.tdf'], equals('tdf 0.8.0\n'));

      store['/mem/c.tdf'] = 'existing';
      await expectLater(
        () => operations.moveTdfFile(
          '/mem/b.tdf',
          '/mem/c.tdf',
          '/mem',
          1024,
          messages,
          inMemory: true,
          inMemoryStore: store,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorMoveTargetFileExists('/mem/c.tdf')),
          ),
        ),
      );

      // No-op when source equals target.
      final samePath = '${tempDir.path}/same.tdf';
      await expectLater(
        operations.moveTdfFile(
          samePath,
          samePath,
          tempDir.path,
          1024,
          messages,
          inMemory: false,
        ),
        completes,
      );

      // Missing source exercises _verifyDirectoryWritable on writable directory cleanly.
      final writableDir = Directory('${tempDir.path}/writable')..createSync();
      await operations.moveTdfFile(
        '${tempDir.path}/nonexistent.tdf',
        '${writableDir.path}/fresh.tdf',
        writableDir.path,
        1024,
        messages,
        inMemory: false,
      );
      expect(
        writableDir.listSync(),
        isEmpty,
        reason:
            '_verifyDirectoryWritable must delete its probe file immediately',
      );

      // Missing source against read-only target directory fails via _verifyDirectoryWritable.
      if (Platform.isLinux && Platform.environment['USER'] != 'root') {
        final readOnlyDir = Directory('${tempDir.path}/readonly')..createSync();
        HostFileLockManager.applyPosixChmodBestEffort(readOnlyDir.path, 0x140);
        addTearDown(
          () => HostFileLockManager.applyPosixChmodBestEffort(
            readOnlyDir.path,
            0x1C0,
          ),
        );
        await expectLater(
          () => operations.moveTdfFile(
            '${tempDir.path}/nonexistent.tdf',
            '${readOnlyDir.path}/blocked.tdf',
            readOnlyDir.path,
            1024,
            messages,
            inMemory: false,
          ),
          throwsA(
            isA<LocalFileException>().having(
              (error) => error.message,
              'message',
              allOf(contains('Permission denied'), contains(readOnlyDir.path)),
            ),
          ),
          reason: '_verifyDirectoryWritable must reject unwritable target directories',
        );
      }

      // Regular file move and renameTdf (including automatic .tdf extension and invalid name rejection).
      final sourceFile = File('${tempDir.path}/origin.tdf')
        ..writeAsStringSync('tdf 0.8.0\n', flush: true);
      final movedPath = '${writableDir.path}/moved.tdf';
      await operations.moveTdfFile(
        sourceFile.path,
        movedPath,
        writableDir.path,
        1024,
        messages,
        inMemory: false,
      );
      expect(sourceFile.existsSync(), isFalse);
      expect(File(movedPath).readAsStringSync(), equals('tdf 0.8.0\n'));

      final renamedPath = await operations.renameTdf(
        movedPath,
        writableDir.path,
        'renamed_board',
        1024,
        messages,
        inMemory: false,
      );
      expect(renamedPath, equals('${writableDir.path}/renamed_board.tdf'));
      expect(File(movedPath).existsSync(), isFalse);
      expect(File(renamedPath).readAsStringSync(), equals('tdf 0.8.0\n'));

      for (final invalidName in const <String>[
        '',
        '../escape.tdf',
        'sub/board.tdf',
        'bad\x00name.tdf',
      ]) {
        await expectLater(
          () => operations.renameTdf(
            renamedPath,
            writableDir.path,
            invalidName,
            1024,
            messages,
            inMemory: false,
          ),
          throwsA(
            isA<LocalFileException>().having(
              (error) => error.message,
              'message',
              equals(messages.localFileNameErrorInvalid),
            ),
          ),
          reason: 'renameTdf must reject invalid file name "$invalidName"',
        );
      }

      // Target validation failures: missing dir, non-dir parent, existing file/dir/symlink, source dir/symlink.
      await expectLater(
        () => operations.moveTdfFile(
          renamedPath,
          '${tempDir.path}/missing_dir/out.tdf',
          '${tempDir.path}/missing_dir',
          1024,
          messages,
          inMemory: false,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(
              messages.errorMoveTargetDirectoryNotFound(
                '${tempDir.path}/missing_dir',
              ),
            ),
          ),
        ),
      );

      await expectLater(
        () => operations.moveTdfFile(
          renamedPath,
          '$renamedPath/child.tdf',
          renamedPath,
          1024,
          messages,
          inMemory: false,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorMoveTargetNotADirectory(renamedPath)),
          ),
        ),
      );

      final existingTargetDir = Directory('${tempDir.path}/existing_dir')
        ..createSync();
      await expectLater(
        () => operations.moveTdfFile(
          renamedPath,
          existingTargetDir.path,
          tempDir.path,
          1024,
          messages,
          inMemory: false,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(
              messages.errorMoveTargetDirectoryExists(existingTargetDir.path),
            ),
          ),
        ),
      );

      final existingTargetLink = '${tempDir.path}/existing_link.tdf';
      Link(existingTargetLink).createSync(renamedPath);
      await expectLater(
        () => operations.moveTdfFile(
          renamedPath,
          existingTargetLink,
          tempDir.path,
          1024,
          messages,
          inMemory: false,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorMoveTargetSymlinkExists(existingTargetLink)),
          ),
        ),
      );

      await expectLater(
        () => operations.moveTdfFile(
          existingTargetDir.path,
          '${tempDir.path}/dest_from_dir.tdf',
          tempDir.path,
          1024,
          messages,
          inMemory: false,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorMoveSourceIsDirectory(existingTargetDir.path)),
          ),
        ),
      );

      await expectLater(
        () => operations.moveTdfFile(
          existingTargetLink,
          '${tempDir.path}/dest_from_link.tdf',
          tempDir.path,
          1024,
          messages,
          inMemory: false,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(messages.errorMoveSourceIsSymlink(existingTargetLink)),
          ),
        ),
      );
    });

    test('formatBackupPath and resolveNextLocalBackupPath format and rotate suffixes deterministically', () {
      const base = '/work/tasks.tdf';
      final formatCases = <({int attempt, String expected})>[
        (attempt: -1, expected: '/work/tasks.tdf.bak'),
        (attempt: 0, expected: '/work/tasks.tdf.bak'),
        (attempt: 1, expected: '/work/tasks.tdf.bak.001'),
        (attempt: 42, expected: '/work/tasks.tdf.bak.042'),
        (attempt: 999, expected: '/work/tasks.tdf.bak.999'),
      ];
      for (final entry in formatCases) {
        expect(
          operations.formatBackupPath(base, entry.attempt),
          equals(entry.expected),
          reason: 'Unexpected backup path for attemptIndex=${entry.attempt}',
        );
      }

      final diskBase = '${tempDir.path}/tasks.tdf';
      expect(
        operations.resolveNextLocalBackupPath(diskBase, messages),
        equals('$diskBase.bak'),
      );
      File('$diskBase.bak').writeAsStringSync('0', flush: true);
      expect(
        operations.resolveNextLocalBackupPath(diskBase, messages),
        equals('$diskBase.bak.001'),
      );
      File('$diskBase.bak.001').writeAsStringSync('1', flush: true);
      expect(
        operations.resolveNextLocalBackupPath(diskBase, messages),
        equals('$diskBase.bak.002'),
      );
    });

    test('matchesWatchedFileName and isRelevantWatchEvent enforce exact basename matching and filter delete events', () async {
      final matchCases =
          <
            ({
              String candidate,
              String target,
              bool caseInsensitive,
              bool expected,
              String reason,
            })
          >[
            (
              candidate: '/var/data/tasks.tdf',
              target: 'tasks.tdf',
              caseInsensitive: false,
              expected: true,
              reason: 'POSIX path ending with exact target must match',
            ),
            (
              candidate: r'C:\Users\Alice\Tasks.TDF',
              target: 'tasks.tdf',
              caseInsensitive: true,
              expected: true,
              reason: 'Windows path must match case-insensitively when enabled',
            ),
            (
              candidate: r'C:\Users\Alice\Tasks.TDF',
              target: 'tasks.tdf',
              caseInsensitive: false,
              expected: false,
              reason: 'Case mismatch must fail when caseInsensitive is false',
            ),
            (
              candidate: 'tasks.tdf',
              target: 'tasks.tdf',
              caseInsensitive: false,
              expected: true,
              reason: 'Bare filename equal to target must match',
            ),
            (
              candidate: '/var/data/tasks.tdf/',
              target: 'tasks.tdf',
              caseInsensitive: false,
              expected: false,
              reason: 'Trailing POSIX separator must not match a file',
            ),
            (
              candidate: r'C:\data\tasks.tdf\',
              target: 'tasks.tdf',
              caseInsensitive: true,
              expected: false,
              reason: 'Trailing Windows separator must not match a file',
            ),
            (
              candidate: '/var/data/tasks.tdf ',
              target: 'tasks.tdf',
              caseInsensitive: false,
              expected: false,
              reason: 'Basename comparison must not trim trailing whitespace',
            ),
            (
              candidate: '',
              target: 'tasks.tdf',
              caseInsensitive: false,
              expected: false,
              reason: 'Empty candidate path must not match',
            ),
            (
              candidate: '/var/data/tasks.tdf',
              target: '',
              caseInsensitive: false,
              expected: false,
              reason: 'Empty target name must not match',
            ),
          ];
      for (final entry in matchCases) {
        expect(
          operations.matchesWatchedFileName(
            entry.candidate,
            entry.target,
            caseInsensitive: entry.caseInsensitive,
          ),
          equals(entry.expected),
          reason: entry.reason,
        );
      }

      if (!FileSystemEntity.isWatchSupported) {
        return;
      }

      final watchDir = Directory('${tempDir.path}/watch_events')..createSync();
      final events = await _captureRealWatchEvents(watchDir);

      expect(
        operations.isRelevantWatchEvent(
          events.createTarget,
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isTrue,
        reason: 'Matching FileSystemCreateEvent must be relevant',
      );
      expect(
        operations.isRelevantWatchEvent(
          events.createTarget,
          'TASKS.TDF',
          caseInsensitive: true,
        ),
        isTrue,
        reason: 'Case-insensitive matching must accept uppercase target name',
      );
      expect(
        operations.isRelevantWatchEvent(
          events.modifyOther,
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isFalse,
        reason: 'Unrelated FileSystemModifyEvent must be ignored',
      );
      expect(
        operations.isRelevantWatchEvent(
          events.deleteTarget,
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isFalse,
        reason: 'FileSystemDeleteEvent must always be ignored',
      );
      expect(
        operations.isRelevantWatchEvent(
          events.moveIntoTarget,
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isTrue,
        reason: 'Atomic rename destination matching target must be relevant',
      );
      expect(
        operations.isRelevantWatchEvent(
          events.moveOutOfTarget,
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isTrue,
        reason: 'Move event originating from target must be relevant',
      );
      expect(
        operations.isRelevantWatchEvent(
          events.moveUnrelated,
          'tasks.tdf',
          caseInsensitive: false,
        ),
        isFalse,
        reason: 'Move event between unrelated files must be ignored',
      );
    });

    test('watchTdfFile handles inMemory/missing dir, filters watch events, logs watch errors in onError and sync throw, and closes cleanly', () async {
      AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 22, 12));
      AppLogger.setEnabled(
        true,
        persistToDisk: false,
        minimumLevel: LogLevel.debug,
      );

      // inMemory mode yields an immediate empty stream.
      final inMemoryEvents = await operations
          .watchTdfFile(
            directoryPath: tempDir.path,
            targetFileName: 'tasks.tdf',
            inMemory: true,
          )
          .toList();
      expect(inMemoryEvents, isEmpty);

      // Missing directory closes immediately without error.
      final missingDirEvents = await operations
          .watchTdfFile(
            directoryPath: '${tempDir.path}/absent_dir',
            targetFileName: 'tasks.tdf',
            inMemory: false,
          )
          .toList();
      expect(missingDirEvents, isEmpty);

      final sampleDir = Directory('${tempDir.path}/sample_watch')..createSync();
      final sampleEvents = FileSystemEntity.isWatchSupported
          ? await _captureRealWatchEvents(sampleDir)
          : null;

      // 1. Stream onError callback logs local.watch.error, cancels source subscription, and closes cleanly without forwarding error.
      var sourceCancelledOnError = false;
      final errorWatchController = StreamController<FileSystemEvent>(
        onCancel: () {
          sourceCancelledOnError = true;
        },
      );
      addTearDown(errorWatchController.close);

      await IOOverrides.runZoned<Future<void>>(
        () async {
          final receivedCount = <int>[];
          final receivedErrors = <Object>[];
          final doneCompleter = Completer<void>();
          final subscription = operations
              .watchTdfFile(
                directoryPath: '/virtual/watched',
                targetFileName: 'tasks.tdf',
                inMemory: false,
              )
              .listen(
                (_) => receivedCount.add(1),
                onError: receivedErrors.add,
                onDone: doneCompleter.complete,
              );
          addTearDown(subscription.cancel);

          if (sampleEvents != null) {
            errorWatchController.add(sampleEvents.deleteTarget);
            errorWatchController.add(sampleEvents.modifyOther);
            errorWatchController.add(sampleEvents.moveIntoTarget);
          }
          errorWatchController.addError(
            const FileSystemException(
              'Simulated inotify overflow',
              '/virtual/watched',
            ),
          );

          await doneCompleter.future.timeout(const Duration(seconds: 2));
          if (sampleEvents != null) {
            expect(
              receivedCount.length,
              equals(1),
              reason: 'Only the matching move-in event must emit before the watch stream errors',
            );
          }
          expect(
            receivedErrors,
            isEmpty,
            reason: 'watchTdfFile must isolate Directory.watch onError and close without propagating errors',
          );
          expect(
            sourceCancelledOnError,
            isTrue,
            reason: 'watchTdfFile onError must cancel the underlying Directory.watch subscription',
          );
        },
        createDirectory: (path) => _FakeWatchDirectory(
          path,
          existsResult: true,
          watchFactory: () => errorWatchController.stream,
        ),
      );

      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('[WARN ]') &&
              line.contains('local.watch.error') &&
              line.contains('Simulated inotify overflow'),
        ),
        isTrue,
        reason: 'watchTdfFile onError must log local.watch.error at WARN level',
      );

      // 2. Synchronous FileSystemException thrown by Directory.watch() logs local.watch.error and closes cleanly.
      await IOOverrides.runZoned<Future<void>>(
        () async {
          final events = await operations
              .watchTdfFile(
                directoryPath: '/virtual/sync_throw',
                targetFileName: 'tasks.tdf',
                inMemory: false,
              )
              .toList();
          expect(events, isEmpty);
        },
        createDirectory: (path) => _FakeWatchDirectory(
          path,
          existsResult: true,
          watchFactory: () => throw const FileSystemException(
            'inotify watch limit reached',
            '/virtual/sync_throw',
          ),
        ),
      );

      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('local.watch.error') &&
              line.contains('inotify watch limit reached'),
        ),
        isTrue,
        reason: 'Synchronous Directory.watch FileSystemException must log local.watch.error',
      );

      // 3. Underlying stream onDone and consumer cancel both log local.watch.stop at DEBUG level.
      final doneWatchController = StreamController<FileSystemEvent>();
      await IOOverrides.runZoned<Future<void>>(
        () async {
          final doneCompleter = Completer<void>();
          final subscription = operations
              .watchTdfFile(
                directoryPath: '/virtual/done_target',
                targetFileName: 'tasks.tdf',
                inMemory: false,
              )
              .listen((_) {}, onDone: doneCompleter.complete);
          addTearDown(subscription.cancel);
          await doneWatchController.close();
          await doneCompleter.future.timeout(const Duration(seconds: 2));
        },
        createDirectory: (path) => _FakeWatchDirectory(
          path,
          existsResult: true,
          watchFactory: () => doneWatchController.stream,
        ),
      );
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('[DEBUG]') &&
              line.contains('local.watch.stop') &&
              line.contains('/virtual/done_target'),
        ),
        isTrue,
        reason: 'Underlying stream completion must log local.watch.stop at DEBUG level',
      );

      var sourceCancelledOnUnsubscribe = false;
      final cancelWatchController = StreamController<FileSystemEvent>(
        onCancel: () {
          sourceCancelledOnUnsubscribe = true;
        },
      );
      addTearDown(cancelWatchController.close);

      await IOOverrides.runZoned<Future<void>>(
        () async {
          final subscription = operations
              .watchTdfFile(
                directoryPath: '/virtual/cancel_target',
                targetFileName: 'tasks.tdf',
                inMemory: false,
              )
              .listen((_) {});
          await subscription.cancel();
          expect(
            sourceCancelledOnUnsubscribe,
            isTrue,
            reason: 'Cancelling watchTdfFile stream must cancel the underlying Directory.watch subscription',
          );
        },
        createDirectory: (path) => _FakeWatchDirectory(
          path,
          existsResult: true,
          watchFactory: () => cancelWatchController.stream,
        ),
      );

      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('[DEBUG]') &&
              line.contains('local.watch.stop') &&
              line.contains('/virtual/cancel_target'),
        ),
        isTrue,
        reason:
            'Cancelling watchTdfFile must log local.watch.stop at DEBUG level',
      );
    });

    test('readBoundedRegularFileBytes decodes UTF-8 payloads intact across threshold boundary', () async {
      final path = '${tempDir.path}/utf8_check.tdf';
      const content = 'tdf 0.8.0\n\ntask utf8Test01 {\n    name "Übung"\n}\n';
      final expectedBytes = utf8.encode(content);
      File(path).writeAsBytesSync(expectedBytes, flush: true);

      final actualBytes = await operations.readBoundedRegularFileBytes(
        path,
        expectedBytes.length,
        messages,
      );
      expect(utf8.decode(actualBytes), equals(content));
    });
  });
}

/// Captures real OS [FileSystemEvent] instances from [watchDir] for testing `isRelevantWatchEvent` and `watchTdfFile`.
Future<
  ({
    FileSystemCreateEvent createTarget,
    FileSystemModifyEvent modifyOther,
    FileSystemDeleteEvent deleteTarget,
    FileSystemMoveEvent moveIntoTarget,
    FileSystemMoveEvent moveOutOfTarget,
    FileSystemMoveEvent moveUnrelated,
  })
>
_captureRealWatchEvents(Directory watchDir) async {
  final createCompleter = Completer<FileSystemCreateEvent>();
  final modifyOtherCompleter = Completer<FileSystemModifyEvent>();
  final deleteTargetCompleter = Completer<FileSystemDeleteEvent>();
  final moveIntoCompleter = Completer<FileSystemMoveEvent>();
  final moveOutCompleter = Completer<FileSystemMoveEvent>();
  final moveUnrelatedCompleter = Completer<FileSystemMoveEvent>();

  final subscription = watchDir.watch().listen((event) {
    if (event is FileSystemCreateEvent &&
        event.path.endsWith('tasks.tdf') &&
        !createCompleter.isCompleted) {
      createCompleter.complete(event);
    } else if (event is FileSystemModifyEvent &&
        event.path.endsWith('other.tdf') &&
        !modifyOtherCompleter.isCompleted) {
      modifyOtherCompleter.complete(event);
    } else if (event is FileSystemDeleteEvent &&
        event.path.endsWith('tasks.tdf') &&
        !deleteTargetCompleter.isCompleted) {
      deleteTargetCompleter.complete(event);
    } else if (event is FileSystemMoveEvent) {
      final destination = event.destination;
      if (destination != null &&
          destination.endsWith('tasks.tdf') &&
          !moveIntoCompleter.isCompleted) {
        moveIntoCompleter.complete(event);
      } else if (event.path.endsWith('tasks.tdf') &&
          !moveOutCompleter.isCompleted) {
        moveOutCompleter.complete(event);
      } else if (event.path.endsWith('other.tmp') &&
          destination != null &&
          destination.endsWith('other.bak') &&
          !moveUnrelatedCompleter.isCompleted) {
        moveUnrelatedCompleter.complete(event);
      }
    }
  });

  try {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final targetFile = File('${watchDir.path}/tasks.tdf')..createSync();
    final otherFile = File('${watchDir.path}/other.tdf')..createSync();
    otherFile.writeAsStringSync('modified', flush: true);
    targetFile.deleteSync();

    final tmpFile = File('${watchDir.path}/tasks.tdf.tmp')
      ..writeAsStringSync('atomic', flush: true);
    tmpFile.renameSync('${watchDir.path}/tasks.tdf');
    File('${watchDir.path}/tasks.tdf')
        .renameSync('${watchDir.path}/tasks.tdf.bak');

    final unrelatedFile = File('${watchDir.path}/other.tmp')
      ..writeAsStringSync('unrelated', flush: true);
    unrelatedFile.renameSync('${watchDir.path}/other.bak');

    const timeout = Duration(seconds: 2);
    return (
      createTarget: await createCompleter.future.timeout(timeout),
      modifyOther: await modifyOtherCompleter.future.timeout(timeout),
      deleteTarget: await deleteTargetCompleter.future.timeout(timeout),
      moveIntoTarget: await moveIntoCompleter.future.timeout(timeout),
      moveOutOfTarget: await moveOutCompleter.future.timeout(timeout),
      moveUnrelated: await moveUnrelatedCompleter.future.timeout(timeout),
    );
  } finally {
    await subscription.cancel();
  }
}
