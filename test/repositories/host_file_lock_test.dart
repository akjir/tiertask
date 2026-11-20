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

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/repositories/host_file_lock.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/sha256_service.dart';

void main() {
  group('HostFileLockManager Canonical Target Hash & Lock Directory Resolution', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'tiertask_host_lock_hash_',
      );
      AppLogger.resetForTesting();
    });

    tearDown(() async {
      AppLogger.resetForTesting();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('computes identical 64-char SHA-256 targetPathHash across file symlinks, parent directory symlinks, trailing slashes, and Windows case/separators', () async {
      final realDirectory = Directory(
        '${tempRoot.path}${Platform.pathSeparator}real_workspace',
      )..createSync(recursive: true);
      final symlinkDirectory = Link(
        '${tempRoot.path}${Platform.pathSeparator}linked_workspace',
      )..createSync(realDirectory.path);

      // 1. Non-existent <target> resolves parent directory symlinks + basename.
      final nonExistentRealTarget =
          '${realDirectory.path}${Platform.pathSeparator}tasks.tdf';
      final nonExistentLinkedTarget =
          '${symlinkDirectory.path}${Platform.pathSeparator}tasks.tdf';
      final hashBeforeCreateReal = HostFileLockManager.computeTargetPathHash(
        nonExistentRealTarget,
      );
      final hashBeforeCreateLinked = HostFileLockManager.computeTargetPathHash(
        nonExistentLinkedTarget,
      );
      expect(hashBeforeCreateReal.length, equals(64));
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(hashBeforeCreateReal),
        isTrue,
        reason: 'targetPathHash must be 64 lowercase hexadecimal characters',
      );
      expect(
        hashBeforeCreateLinked,
        equals(hashBeforeCreateReal),
        reason: 'Non-existent target under symlinked parent must match canonical parent path hash',
      );

      // 2. Existing <target> file symlink resolves directly via File.resolveSymbolicLinksSync (DECISION-09).
      File(nonExistentRealTarget).writeAsStringSync('tdf 0.8.0\n', flush: true);
      final aliasDirectory = Directory(
        '${tempRoot.path}${Platform.pathSeparator}alias_folder',
      )..createSync(recursive: true);
      final symlinkFilePath =
          '${aliasDirectory.path}${Platform.pathSeparator}shortcut_board.tdf';
      Link(symlinkFilePath).createSync(nonExistentRealTarget);

      final hashAfterCreateReal = HostFileLockManager.computeTargetPathHash(
        nonExistentRealTarget,
      );
      final hashViaFileSymlink = HostFileLockManager.computeTargetPathHash(
        symlinkFilePath,
      );
      final hashWithTrailingSlashes = HostFileLockManager.computeTargetPathHash(
        '$nonExistentRealTarget///',
      );

      expect(
        hashAfterCreateReal,
        equals(hashBeforeCreateReal),
        reason: 'targetPathHash must remain identical before and after file creation',
      );
      expect(
        hashViaFileSymlink,
        equals(hashAfterCreateReal),
        reason: 'Direct file symlink and real .tdf file must produce the identical targetPathHash',
      );
      expect(
        hashWithTrailingSlashes,
        equals(hashAfterCreateReal),
        reason: 'Trailing path separators must be stripped before hashing',
      );

      // 3. Windows separator normalization and NTFS lowercase canonicalization.
      final windowsCanonicalUpper = HostFileLockManager.canonicalizeTargetPath(
        r'C:\Dir\SubFolder\\Tasks.TDF\',
        isWindows: true,
      );
      final windowsCanonicalLower = HostFileLockManager.canonicalizeTargetPath(
        'c:/dir/subfolder/tasks.tdf',
        isWindows: true,
      );
      expect(windowsCanonicalUpper, equals('c:/dir/subfolder/tasks.tdf'));
      expect(windowsCanonicalLower, equals('c:/dir/subfolder/tasks.tdf'));

      final windowsHashUpper = HostFileLockManager.computeTargetPathHash(
        r'C:\Dir\Tasks.TDF',
        isWindows: true,
      );
      final windowsHashLower = HostFileLockManager.computeTargetPathHash(
        'c:/dir/tasks.tdf',
        isWindows: true,
      );
      expect(
        windowsHashUpper,
        equals(windowsHashLower),
        reason: 'Windows targetPathHash must normalize backslashes to / and lowercase paths',
      );
      expect(
        windowsHashLower,
        equals(Sha256Service.hashHex(utf8.encode('c:/dir/tasks.tdf'))),
      );
    });

    test('resolves host lock directories across Linux XDG_RUNTIME_DIR, Linux/Android fallback with real libc getuid(), and Windows LOCALAPPDATA', () async {
      final linuxXdgDir = HostFileLockManager.resolveHostLockDirectory(
        environment: const <String, String>{
          'XDG_RUNTIME_DIR': '/run/user/1000/',
        },
        isWindows: false,
        isAndroid: false,
        systemTempPath: '/tmp',
        uidOverride: 1000,
      );
      expect(linuxXdgDir, equals('/run/user/1000/tdf-locks'));

      final linuxFallbackDir = HostFileLockManager.resolveHostLockDirectory(
        environment: const <String, String>{'XDG_RUNTIME_DIR': '   '},
        isWindows: false,
        isAndroid: false,
        systemTempPath: '/tmp/',
        uidOverride: 1042,
      );
      expect(linuxFallbackDir, equals('/tmp/tdf-locks-1042'));

      final androidFallbackDir = HostFileLockManager.resolveHostLockDirectory(
        environment: const <String, String>{
          'XDG_RUNTIME_DIR': '/run/user/1000',
        },
        isWindows: false,
        isAndroid: true,
        systemTempPath: '/data/local/tmp',
        uidOverride: 10155,
      );
      expect(androidFallbackDir, equals('/data/local/tmp/tdf-locks-10155'));

      final windowsLockDir = HostFileLockManager.resolveHostLockDirectory(
        environment: const <String, String>{
          'LOCALAPPDATA': r'C:\Users\Stefan\AppData\Local\',
        },
        isWindows: true,
        isAndroid: false,
        systemTempPath: r'C:\Temp',
      );
      expect(
        windowsLockDir,
        equals(r'C:\Users\Stefan\AppData\Local\Temp\tdf-locks'),
      );

      if (Platform.isLinux) {
        final idResult = await Process.run('id', const <String>['-u']);
        final expectedUid = int.parse(idResult.stdout.toString().trim());
        expect(
          HostFileLockManager.getPosixUid(),
          equals(expectedUid),
          reason: 'getPosixUid() must match real OS uid from libc getuid()',
        );

        final resolvedFallbackRealUid =
            HostFileLockManager.resolveHostLockDirectory(
              environment: const <String, String>{'XDG_RUNTIME_DIR': ''},
              isWindows: false,
              isAndroid: false,
              systemTempPath: tempRoot.path,
            );
        expect(
          resolvedFallbackRealUid,
          equals('${tempRoot.path}/tdf-locks-$expectedUid'),
        );

        final resolvedXdgDir = HostFileLockManager.resolveHostLockDirectory(
          environment: <String, String>{
            'XDG_RUNTIME_DIR': '${tempRoot.path}/xdg_runtime',
          },
          isWindows: false,
          isAndroid: false,
          systemTempPath: tempRoot.path,
        );
        expect(
          resolvedXdgDir,
          equals('${tempRoot.path}/xdg_runtime/tdf-locks'),
        );

        // Verify both lock directories are created on disk with 0700 permissions.
        for (final lockDirPath in <String>[
          resolvedXdgDir,
          resolvedFallbackRealUid,
        ]) {
          final manager = HostFileLockManager<LocalFileException>(
            createException: LocalFileException.new,
            hostLockDirectoryOverride: lockDirPath,
          );
          final targetFile = '${tempRoot.path}/workspace/tasks.tdf';
          await manager.withExclusiveLock(targetFile, () async {});
          final dirMode = Directory(lockDirPath).statSync().mode & 0x1FF;
          expect(
            dirMode,
            equals(0x1C0),
            reason: 'Host lock directory "$lockDirPath" must have 0700 mode',
          );
        }
      }
    });
  });

  group('HostFileLockManager Locking, Re-Entrancy, Multi-Process Contention & Atomic Write', () {
    late Directory tempRoot;
    late Directory workspaceDir;
    late Directory lockDir;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'tiertask_host_lock_io_',
      );
      workspaceDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}workspace',
      )..createSync(recursive: true);
      lockDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}host_locks',
      );
      AppLogger.resetForTesting();
      AppLogger.setEnabled(true, persistToDisk: false);
    });

    tearDown(() async {
      AppLogger.resetForTesting();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('creates 0600 lock file in host lock directory, creates zero .tdf.lock files in workspace, and never unlinks lock file after release', () async {
      final manager = HostFileLockManager<LocalFileException>(
        createException: LocalFileException.new,
        hostLockDirectoryOverride: lockDir.path,
      );
      final targetPath =
          '${workspaceDir.path}${Platform.pathSeparator}tasks.tdf';
      final expectedHash = HostFileLockManager.computeTargetPathHash(
        targetPath,
      );
      final expectedLockPath =
          '${lockDir.path}${Platform.pathSeparator}tdf-$expectedHash.lock';

      expect(manager.resolveLockFilePath(targetPath), equals(expectedLockPath));

      await manager.withExclusiveLock(targetPath, () async {
        await manager.writeAtomically(targetPath, utf8.encode('tdf 0.8.0\n'));
      });

      expect(
        File(expectedLockPath).existsSync(),
        isTrue,
        reason: 'Host lock file must NEVER be unlinked after lock release',
      );
      if (Platform.isLinux) {
        final lockMode = File(expectedLockPath).statSync().mode & 0x1FF;
        expect(
          lockMode,
          equals(0x180),
          reason: 'Host lock file on POSIX must have 0600 permissions',
        );
        final targetMode = File(targetPath).statSync().mode & 0x1FF;
        expect(
          targetMode,
          equals(0x180),
          reason: 'Published .tdf file on POSIX must have 0600 permissions',
        );
      }

      final workspaceNames = workspaceDir
          .listSync(followLinks: false)
          .map((entity) => entity.path.split(Platform.pathSeparator).last)
          .toList();
      expect(
        workspaceNames,
        equals(<String>['tasks.tdf']),
        reason: 'Workspace directory must contain zero .tdf.lock or leftover .tmp files',
      );

      final logText = AppLogger.fullLogText;
      final shortHash = expectedHash.substring(0, 12);
      expect(logText, contains('local.lock.acquire'));
      expect(logText, contains('local.lock.release'));
      expect(logText, contains('hash=$shortHash'));
    });

    test('serializes concurrent in-process callers in strict FIFO order and supports re-entrant Zone nesting without self-deadlock', () async {
      final manager = HostFileLockManager<LocalFileException>(
        createException: LocalFileException.new,
        hostLockDirectoryOverride: lockDir.path,
      );
      final targetPath =
          '${workspaceDir.path}${Platform.pathSeparator}fifo_tasks.tdf';

      final executionOrder = <String>[];
      final firstEntered = Completer<void>();
      final releaseFirst = Completer<void>();

      final firstFuture = manager.withExclusiveLock(targetPath, () async {
        executionOrder.add('first:enter');
        firstEntered.complete();
        await releaseFirst.future;
        // Re-entrant nested lock + writeAtomically on the same targetPathHash must not deadlock.
        await manager.withExclusiveLock(targetPath, () async {
          executionOrder.add('first:nested');
          await manager.writeAtomically(
            targetPath,
            utf8.encode('tdf 0.8.0\n# first\n'),
          );
        });
        executionOrder.add('first:exit');
      });

      await firstEntered.future;

      final secondFuture = manager.withExclusiveLock(targetPath, () async {
        executionOrder.add('second:enter');
        await manager.writeAtomically(
          targetPath,
          utf8.encode('tdf 0.8.0\n# second\n'),
        );
        executionOrder.add('second:exit');
      });

      final thirdFuture = manager.withExclusiveLock(targetPath, () async {
        executionOrder.add('third:enter');
        await manager.writeAtomically(
          targetPath,
          utf8.encode('tdf 0.8.0\n# third\n'),
        );
        executionOrder.add('third:exit');
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        executionOrder,
        equals(<String>['first:enter']),
        reason: 'Queued callers must wait until first caller releases lock',
      );

      releaseFirst.complete();
      await Future.wait(<Future<void>>[firstFuture, secondFuture, thirdFuture]);

      expect(
        executionOrder,
        equals(<String>[
          'first:enter',
          'first:nested',
          'first:exit',
          'second:enter',
          'second:exit',
          'third:enter',
          'third:exit',
        ]),
        reason: 'In-process callers must run strictly in FIFO arrival order',
      );
      expect(
        File(targetPath).readAsStringSync(),
        equals('tdf 0.8.0\n# third\n'),
      );
    });

    test('multi-process OS kernel lock contention waits with exponential backoff when released in time and aborts cleanly on timeout without wedging subsequent writes', () async {
      final dartExecutable = _resolveStandaloneDartExecutable();
      final helperScript = File(
        '${tempRoot.path}${Platform.pathSeparator}child_lock_holder.dart',
      )..writeAsStringSync(_childLockHolderScriptSource, flush: true);

      final targetPath =
          '${workspaceDir.path}${Platform.pathSeparator}multiprocess.tdf';
      final contendingManager = HostFileLockManager<LocalFileException>(
        createException: LocalFileException.new,
        hostLockDirectoryOverride: lockDir.path,
        lockAcquireTimeout: const Duration(seconds: 5),
      );
      final lockFilePath = contendingManager.resolveLockFilePath(targetPath);

      // 1. Child process acquires OS exclusive lock, holds briefly, then releases before timeout.
      final firstChild = await _startChildLockHolder(
        dartExecutable: dartExecutable,
        scriptPath: helperScript.path,
        lockFilePath: lockFilePath,
      );

      var writerFinished = false;
      final writerFuture = contendingManager.withExclusiveLock(
        targetPath,
        () async {
          await contendingManager.writeAtomically(
            targetPath,
            utf8.encode('tdf 0.8.0\n# after-child-release\n'),
          );
          writerFinished = true;
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        writerFinished,
        isFalse,
        reason:
            'Parent writer must wait while child process holds OS kernel lock',
      );

      await _releaseChildLockHolder(firstChild);
      await writerFuture;
      expect(writerFinished, isTrue);
      expect(
        File(targetPath).readAsStringSync(),
        equals('tdf 0.8.0\n# after-child-release\n'),
      );

      // 2. Child holds OS lock beyond lockAcquireTimeout (180ms): withExclusiveLock aborts, logs local.lock.timeout, and keeps FIFO queue healthy.
      final secondChild = await _startChildLockHolder(
        dartExecutable: dartExecutable,
        scriptPath: helperScript.path,
        lockFilePath: lockFilePath,
      );

      final shortTimeoutManager = HostFileLockManager<LocalFileException>(
        createException: LocalFileException.new,
        hostLockDirectoryOverride: lockDir.path,
        lockAcquireTimeout: const Duration(milliseconds: 180),
      );

      await expectLater(
        () => shortTimeoutManager.withExclusiveLock(
          targetPath,
          () async => fail('Must not enter critical section while locked'),
        ),
        throwsA(isA<LocalFileException>()),
        reason:
            'Hung external lock holder must time out with LocalFileException',
      );
      expect(
        AppLogger.fullLogText,
        contains('local.lock.timeout'),
        reason: 'Lock acquisition timeout must emit local.lock.timeout event',
      );
      expect(
        File(lockFilePath).existsSync(),
        isTrue,
        reason: 'Timeout cleanup must close descriptor without unlinking .lock',
      );

      // Release external child and verify subsequent call on same manager succeeds immediately without deadlock.
      await _releaseChildLockHolder(secondChild);

      final recoveryValue = await shortTimeoutManager.withExclusiveLock(
        targetPath,
        () async {
          await shortTimeoutManager.writeAtomically(
            targetPath,
            utf8.encode('tdf 0.8.0\n# recovered\n'),
          );
          return 'recovered';
        },
      );
      expect(recoveryValue, equals('recovered'));
      expect(
        File(targetPath).readAsStringSync(),
        equals('tdf 0.8.0\n# recovered\n'),
      );
    });

    test('writeAtomically cleans up .tmp files on target failure and replaceTargetWithSharingRetry retries transient Win32 sharing errors (32, 5) up to 5 attempts', () async {
      final manager = HostFileLockManager<LocalFileException>(
        createException: LocalFileException.new,
        hostLockDirectoryOverride: lockDir.path,
      );

      // Verify directory target rejection leaves zero .tmp.* files.
      final dirTargetPath =
          '${workspaceDir.path}${Platform.pathSeparator}dir_collision.tdf';
      Directory(dirTargetPath).createSync();
      await expectLater(
        () =>
            manager.writeAtomically(dirTargetPath, utf8.encode('tdf 0.8.0\n')),
        throwsA(isA<LocalFileException>()),
      );
      final leftoverAfterDir = workspaceDir
          .listSync(followLinks: false)
          .where((entity) => entity.path.contains('.tmp.'))
          .toList();
      expect(leftoverAfterDir, isEmpty);

      // 1. Transient ERROR_SHARING_VIOLATION (32) + ERROR_ACCESS_DENIED (5) clearing on attempt 3 (0-indexed retry 2 -> 3rd call).
      final recordedDelays = <Duration>[];
      var transientAttempt = 0;
      var cleanedUpOnSuccess = false;
      await manager.replaceTargetWithSharingRetry(
        performMove: () {
          transientAttempt++;
          if (transientAttempt == 1) return 32;
          if (transientAttempt == 2) return 5;
          return null;
        },
        cleanupTemp: () {
          cleanedUpOnSuccess = true;
        },
        delay: (duration) async {
          recordedDelays.add(duration);
        },
      );
      expect(transientAttempt, equals(3));
      expect(cleanedUpOnSuccess, isFalse);
      expect(
        recordedDelays,
        equals(const <Duration>[
          Duration(milliseconds: 10),
          Duration(milliseconds: 20),
        ]),
        reason: 'Transient sharing errors must use 10ms, 20ms backoff',
      );

      // 2. Exhausting all 5 attempts on ERROR_SHARING_VIOLATION (32) unlinks temp file and throws LocalFileException.
      final stagedTempFile = File(
        '${workspaceDir.path}${Platform.pathSeparator}.tasks.tdf.tmp.0123456789abcdef0123456789abcdef',
      )..writeAsStringSync('tdf 0.8.0\n', flush: true);
      final exhaustedDelays = <Duration>[];
      var exhaustedAttempts = 0;

      await expectLater(
        () => manager.replaceTargetWithSharingRetry(
          performMove: () {
            exhaustedAttempts++;
            return 32;
          },
          cleanupTemp: () {
            if (stagedTempFile.existsSync()) {
              stagedTempFile.deleteSync();
            }
          },
          delay: (duration) async {
            exhaustedDelays.add(duration);
          },
        ),
        throwsA(isA<LocalFileException>()),
        reason: '5 exhausted sharing-violation attempts must throw',
      );
      expect(exhaustedAttempts, equals(5));
      expect(
        exhaustedDelays,
        equals(const <Duration>[
          Duration(milliseconds: 10),
          Duration(milliseconds: 20),
          Duration(milliseconds: 40),
          Duration(milliseconds: 80),
        ]),
        reason:
            '5 attempts must sleep 4 times with 10ms, 20ms, 40ms, 80ms backoff',
      );
      expect(
        stagedTempFile.existsSync(),
        isFalse,
        reason: 'Exhausted atomic replacement must unlink the temporary file',
      );

      // 3. Non-sharing OS error (e.g. ERROR_DISK_FULL = 112) aborts immediately on attempt 1 without retries.
      var nonTransientCalls = 0;
      var nonTransientCleanedUp = false;
      await expectLater(
        () => manager.replaceTargetWithSharingRetry(
          performMove: () {
            nonTransientCalls++;
            return 112;
          },
          cleanupTemp: () {
            nonTransientCleanedUp = true;
          },
          delay: (_) async {
            fail('Non-sharing errors must not sleep or retry');
          },
        ),
        throwsA(isA<LocalFileException>()),
      );
      expect(nonTransientCalls, equals(1));
      expect(nonTransientCleanedUp, isTrue);
    });

    test('replaceTargetWithSharingRetry formats terminal Win32 failure messages via formatFailureMessage and preserves fallback when omitted', () async {
      final manager = HostFileLockManager<LocalFileException>(
        createException: LocalFileException.new,
        hostLockDirectoryOverride: lockDir.path,
      );
      String formatLocalized(String details) =>
          'Fehler beim Schreiben der lokalen TDF-Datei ($details).';

      // 1. Immediate non-transient Win32 error uses formatFailureMessage.
      var cleanedUpImmediate = false;
      await expectLater(
        () => manager.replaceTargetWithSharingRetry(
          performMove: () => 112,
          cleanupTemp: () {
            cleanedUpImmediate = true;
          },
          targetPath: r'C:\vault\tasks.tdf',
          formatFailureMessage: formatLocalized,
        ),
        throwsA(
          isA<LocalFileException>()
              .having(
                (error) => error.message,
                'message',
                allOf(
                  startsWith('Fehler beim Schreiben der lokalen TDF-Datei ('),
                  contains('Win32 error 112'),
                ),
              )
              .having(
                (error) => error.cause,
                'cause',
                isA<FileSystemException>().having(
                  (cause) => cause.osError?.errorCode,
                  'osError.errorCode',
                  equals(112),
                ),
              ),
        ),
        reason: 'Terminal non-transient Win32 MoveFileExW errors must pass details to formatFailureMessage',
      );
      expect(cleanedUpImmediate, isTrue);

      // 2. Exhausted transient sharing retries also format through formatFailureMessage.
      var cleanedUpExhausted = false;
      await expectLater(
        () => manager.replaceTargetWithSharingRetry(
          performMove: () => 32,
          cleanupTemp: () {
            cleanedUpExhausted = true;
          },
          delay: (_) async {},
          targetPath: r'C:\vault\tasks.tdf',
          formatFailureMessage: formatLocalized,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            allOf(
              startsWith('Fehler beim Schreiben der lokalen TDF-Datei ('),
              contains('Win32 error 32'),
            ),
          ),
        ),
        reason: 'Exhausted Win32 sharing retries must pass details to formatFailureMessage',
      );
      expect(cleanedUpExhausted, isTrue);

      // 3. Unexpected thrown error from performMove also formats via formatFailureMessage.
      var cleanedUpThrown = false;
      await expectLater(
        () => manager.replaceTargetWithSharingRetry(
          performMove: () => throw StateError('unexpected move failure'),
          cleanupTemp: () {
            cleanedUpThrown = true;
          },
          targetPath: r'C:\vault\tasks.tdf',
          formatFailureMessage: formatLocalized,
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            allOf(
              startsWith('Fehler beim Schreiben der lokalen TDF-Datei ('),
              contains('unexpected move failure'),
            ),
          ),
        ),
      );
      expect(cleanedUpThrown, isTrue);

      // 4. Omitting formatFailureMessage preserves the default fallback message.
      await expectLater(
        () => manager.replaceTargetWithSharingRetry(
          performMove: () => 112,
          cleanupTemp: () {},
          targetPath: r'C:\vault\tasks.tdf',
        ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            equals(
              r'Atomic target replacement failed (Win32 error 112) for C:\vault\tasks.tdf',
            ),
          ),
        ),
      );
    });

    test('classifies non-POSIX fchmod errnos vs hard I/O errors and tolerates non-POSIX mounts with debug logging while forwarding formatFailureMessage on hard failures', () {
      final manager = HostFileLockManager<LocalFileException>(
        createException: LocalFileException.new,
        hostLockDirectoryOverride: lockDir.path,
      );
      AppLogger.setMinimumLevel(LogLevel.debug);

      const tolerableErrnos = <int>[1, 22, 38, 95];
      for (final code in tolerableErrnos) {
        expect(
          HostFileLockManager.isTolerablePosixFchmodErrno(code),
          isTrue,
          reason: 'Non-POSIX filesystem errno $code must be tolerated',
        );
      }

      const hardErrnos = <int>[-1, 0, 4, 5, 9, 13, 30];
      for (final code in hardErrnos) {
        expect(
          HostFileLockManager.isTolerablePosixFchmodErrno(code),
          isFalse,
          reason: 'Hard or non-tolerable errno $code must not be ignored',
        );
      }

      // 1. Retries EINTR (4) and succeeds when fchmod subsequently returns 0.
      var eintrCalls = 0;
      manager.applyPosixFchmodBestEffort(
        performFchmod: () {
          eintrCalls++;
          return eintrCalls == 1 ? -1 : 0;
        },
        readErrno: () => 4,
        path: '/mnt/storage/.tasks.tdf.tmp.abc',
      );
      expect(eintrCalls, equals(2));
      expect(AppLogger.fullLogText, isNot(contains('local.fchmod.skipped')));

      // 2. Non-POSIX mount errnos (EPERM, EINVAL, ENOSYS, EOPNOTSUPP) log debug event and succeed.
      for (final code in tolerableErrnos) {
        AppLogger.resetForTesting();
        AppLogger.setEnabled(true, persistToDisk: false);
        AppLogger.setMinimumLevel(LogLevel.debug);
        manager.applyPosixFchmodBestEffort(
          performFchmod: () => -1,
          readErrno: () => code,
          path: '/storage/emulated/0/Documents/.tasks.tdf.tmp.abc',
        );
        final logs = AppLogger.fullLogText;
        expect(
          logs,
          contains('local.fchmod.skipped'),
          reason: 'Tolerated fchmod errno $code must emit debug log event',
        );
        expect(
          logs,
          contains('errno=$code'),
          reason: 'Tolerated fchmod log must include errno=$code',
        );
        expect(
          logs,
          isNot(contains('/storage/emulated/0')),
          reason: 'Tolerated fchmod log must not expose raw file paths',
        );
      }

      // 3. Hard I/O errors (EIO=5, EBADF=9, EACCES=13, EROFS=30) throw and forward formatFailureMessage.
      for (final code in const <int>[5, 9, 13, 30]) {
        expect(
          () => manager.applyPosixFchmodBestEffort(
            performFchmod: () => -1,
            readErrno: () => code,
            path: '/mnt/usb/.tasks.tdf.tmp.abc',
            formatFailureMessage: (details) => 'Localized save error: $details',
          ),
          throwsA(
            isA<LocalFileException>()
                .having(
                  (error) => error.message,
                  'message',
                  equals('Localized save error: fchmod failed (errno $code)'),
                )
                .having(
                  (error) => error.cause,
                  'cause',
                  isA<FileSystemException>().having(
                    (cause) => cause.osError?.errorCode,
                    'osError.errorCode',
                    equals(code),
                  ),
                ),
          ),
          reason:
              'Hard fchmod errno $code must throw formatted LocalFileException',
        );
      }
    });

    test('acquirePosixDescriptorLock closes descriptor on fchmod or flock failure and transfers ownership only on acquisition', () async {
      final manager = HostFileLockManager<LocalFileException>(
        createException: LocalFileException.new,
        hostLockDirectoryOverride: lockDir.path,
      );
      AppLogger.setMinimumLevel(LogLevel.debug);

      // 1. Failure during applyPermissions (e.g. fchmod EIO) must close the opened descriptor.
      final closedOnPermFailure = <int>[];
      var releaseCalledOnPermFailure = false;
      var tryLockCalledOnPermFailure = false;
      await expectLater(
        () => manager.acquirePosixDescriptorLock(
          descriptor: 42,
          applyPermissions: () => manager.applyPosixFchmodBestEffort(
            performFchmod: () => -1,
            readErrno: () => 5,
            path: '/tmp/tdf-locks/tdf-test.lock',
          ),
          tryLock: () {
            tryLockCalledOnPermFailure = true;
            return true;
          },
          closeDescriptor: closedOnPermFailure.add,
          releaseAndClose: (_) {
            releaseCalledOnPermFailure = true;
          },
          lockFilePath: '/tmp/tdf-locks/tdf-test.lock',
          targetHash: 'abcdef0123456789',
          stopwatch: Stopwatch()..start(),
        ),
        throwsA(isA<LocalFileException>()),
        reason: 'Hard fchmod failure during lock acquisition must rethrow',
      );
      expect(
        closedOnPermFailure,
        equals(const <int>[42]),
        reason:
            'Descriptor must be closed when fchmod throws to prevent FD leak',
      );
      expect(tryLockCalledOnPermFailure, isFalse);
      expect(releaseCalledOnPermFailure, isFalse);

      // 2. Failure during tryLock must also close the opened descriptor.
      final closedOnFlockFailure = <int>[];
      await expectLater(
        () => manager.acquirePosixDescriptorLock(
          descriptor: 77,
          applyPermissions: () {},
          tryLock: () => throw const LocalFileException('flock failed'),
          closeDescriptor: closedOnFlockFailure.add,
          releaseAndClose: (_) {},
          lockFilePath: '/tmp/tdf-locks/tdf-test.lock',
          targetHash: 'abcdef0123456789',
          stopwatch: Stopwatch()..start(),
        ),
        throwsA(isA<LocalFileException>()),
      );
      expect(
        closedOnFlockFailure,
        equals(const <int>[77]),
        reason: 'Descriptor must be closed when flock throws',
      );

      // 3. Tolerated non-POSIX fchmod (EOPNOTSUPP=95) proceeds to lock and transfers FD to releaser.
      final closedOnSuccess = <int>[];
      final releasedOnSuccess = <int>[];
      final release = await manager.acquirePosixDescriptorLock(
        descriptor: 99,
        applyPermissions: () => manager.applyPosixFchmodBestEffort(
          performFchmod: () => -1,
          readErrno: () => 95,
          path: '/tmp/tdf-locks/tdf-test.lock',
        ),
        tryLock: () => true,
        closeDescriptor: closedOnSuccess.add,
        releaseAndClose: releasedOnSuccess.add,
        lockFilePath: '/tmp/tdf-locks/tdf-test.lock',
        targetHash: 'abcdef0123456789',
        stopwatch: Stopwatch()..start(),
      );
      expect(
        closedOnSuccess,
        isEmpty,
        reason: 'Acquired descriptor must not be closed prematurely',
      );
      expect(releasedOnSuccess, isEmpty);
      release();
      expect(releasedOnSuccess, equals(const <int>[99]));
    });

    test('real POSIX fchmod enforces 0600 permissions on lock and atomic target files without leaking file descriptors', () async {
      if (!Platform.isLinux) {
        return;
      }
      final manager = HostFileLockManager<LocalFileException>(
        createException: LocalFileException.new,
        hostLockDirectoryOverride: lockDir.path,
      );
      final targetPath =
          '${workspaceDir.path}${Platform.pathSeparator}fchmod_real.tdf';
      final lockFilePath = manager.resolveLockFilePath(targetPath);

      // Pre-create lock directory and lock file with overly permissive 0644 mode.
      lockDir.createSync(recursive: true);
      Process.runSync('chmod', <String>['0700', lockDir.path]);
      File(lockFilePath).writeAsStringSync('', flush: true);
      Process.runSync('chmod', <String>['0644', lockFilePath]);
      expect(File(lockFilePath).statSync().mode & 0x1FF, equals(0x1A4));

      final fdDir = Directory('/proc/self/fd');
      final fdCountBefore = fdDir.existsSync() ? fdDir.listSync().length : -1;

      for (var i = 0; i < 8; i++) {
        await manager.withExclusiveLock(targetPath, () async {
          await manager.writeAtomically(
            targetPath,
            utf8.encode('tdf 0.8.0\n# write $i\n'),
          );
        });
      }

      expect(
        File(lockFilePath).statSync().mode & 0x1FF,
        equals(0x180),
        reason: 'Descriptor-based fchmod must tighten existing 0644 lock file to 0600',
      );
      expect(
        File(targetPath).statSync().mode & 0x1FF,
        equals(0x180),
        reason: 'Descriptor-based fchmod must set atomic target file to 0600',
      );
      expect(
        File(targetPath).readAsStringSync(),
        equals('tdf 0.8.0\n# write 7\n'),
      );

      if (fdCountBefore >= 0) {
        final fdCountAfter = fdDir.listSync().length;
        expect(
          fdCountAfter,
          lessThanOrEqualTo(fdCountBefore),
          reason: 'Repeated lock and atomic write cycles must not leak open file descriptors',
        );
      }
    });
  });
}

const String _childLockHolderScriptSource = r'''
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

void main(List<String> args) async {
  final lockPath = args.first;
  File(lockPath).parent.createSync(recursive: true);
  if (Platform.isWindows) {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final localAlloc = kernel32.lookupFunction<
      Pointer<Void> Function(Uint32, Size),
      Pointer<Void> Function(int, int)
    >('LocalAlloc');
    final createFileW = kernel32.lookupFunction<
      IntPtr Function(
        Pointer<Uint16>,
        Uint32,
        Uint32,
        Pointer<Void>,
        Uint32,
        Uint32,
        IntPtr,
      ),
      int Function(Pointer<Uint16>, int, int, Pointer<Void>, int, int, int)
    >('CreateFileW');
    final lockFileEx = kernel32.lookupFunction<
      Int32 Function(IntPtr, Uint32, Uint32, Uint32, Uint32, Pointer<Void>),
      int Function(int, int, int, int, int, Pointer<Void>)
    >('LockFileEx');
    final unlockFileEx = kernel32.lookupFunction<
      Int32 Function(IntPtr, Uint32, Uint32, Uint32, Pointer<Void>),
      int Function(int, int, int, int, Pointer<Void>)
    >('UnlockFileEx');
    final closeHandle = kernel32.lookupFunction<
      Int32 Function(IntPtr),
      int Function(int)
    >('CloseHandle');

    final units = lockPath.codeUnits;
    final pathPtr = localAlloc(0x0040, (units.length + 1) * 2).cast<Uint16>();
    pathPtr.asTypedList(units.length + 1)
      ..setRange(0, units.length, units)
      ..[units.length] = 0;
    final overlapped = localAlloc(0x0040, 32);

    final handle = createFileW(
      pathPtr,
      0x80000000 | 0x40000000,
      0x03,
      nullptr,
      4,
      0x80,
      0,
    );
    if (handle == -1 || handle == 0) {
      stderr.writeln('CreateFileW failed');
      exit(2);
    }
    if (lockFileEx(handle, 0x03, 0, 1, 0, overlapped) == 0) {
      stderr.writeln('LockFileEx failed');
      exit(3);
    }
    stdout.writeln('LOCKED');
    await stdout.flush();
    await stdin.first;
    unlockFileEx(handle, 0, 1, 0, overlapped);
    closeHandle(handle);
    exit(0);
  } else {
    final libc = DynamicLibrary.process();
    final malloc = libc.lookupFunction<
      Pointer<Void> Function(Size),
      Pointer<Void> Function(int)
    >('malloc');
    final open = libc.lookupFunction<
      Int32 Function(Pointer<Uint8>, Int32, VarArgs<(Uint32,)>),
      int Function(Pointer<Uint8>, int, int)
    >('open');
    final flock = libc.lookupFunction<
      Int32 Function(Int32, Int32),
      int Function(int, int)
    >('flock');
    final close = libc.lookupFunction<
      Int32 Function(Int32),
      int Function(int)
    >('close');

    final bytes = utf8.encode(lockPath);
    final pathPtr = malloc(bytes.length + 1).cast<Uint8>();
    pathPtr.asTypedList(bytes.length + 1)
      ..setRange(0, bytes.length, bytes)
      ..[bytes.length] = 0;

    final fd = open(pathPtr, 0x02 | 0x40 | 0x80000, 0x180);
    if (fd < 0) {
      stderr.writeln('open failed');
      exit(2);
    }
    if (flock(fd, 2 | 4) != 0) {
      stderr.writeln('flock failed');
      exit(3);
    }
    stdout.writeln('LOCKED');
    await stdout.flush();
    await stdin.first;
    flock(fd, 8);
    close(fd);
    exit(0);
  }
}
''';

Future<void> _releaseChildLockHolder(Process childProcess) async {
  childProcess.stdin.writeln('RELEASE');
  await childProcess.stdin.flush();
  await childProcess.stdin.close();
  final code = await childProcess.exitCode.timeout(const Duration(seconds: 5));
  expect(code, equals(0));
}

String _resolveStandaloneDartExecutable() {
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  final resolved = Platform.resolvedExecutable;
  if (resolved.endsWith('${Platform.pathSeparator}$executableName')) {
    return resolved;
  }
  var cursor = File(resolved).parent;
  for (var depth = 0; depth < 6; depth++) {
    final candidate = File(
      '${cursor.path}${Platform.pathSeparator}dart-sdk'
      '${Platform.pathSeparator}bin${Platform.pathSeparator}$executableName',
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }
    final parent = cursor.parent;
    if (parent.path == cursor.path) break;
    cursor = parent;
  }
  return executableName;
}

Future<Process> _startChildLockHolder({
  required String dartExecutable,
  required String scriptPath,
  required String lockFilePath,
}) async {
  final process = await Process.start(dartExecutable, <String>[
    scriptPath,
    lockFilePath,
  ]);
  final readyCompleter = Completer<void>();
  final stderrBuffer = StringBuffer();
  process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      if (line.trim() == 'LOCKED' && !readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
    },
  );
  unawaited(
    process.exitCode.then((code) {
      if (!readyCompleter.isCompleted) {
        readyCompleter.completeError(
          StateError('Child lock holder exited early ($code): $stderrBuffer'),
        );
      }
    }),
  );
  await readyCompleter.future.timeout(const Duration(seconds: 10));
  return process;
}
