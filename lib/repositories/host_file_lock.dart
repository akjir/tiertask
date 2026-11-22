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
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/tdf_file_path.dart';
import '../services/app_logger.dart';
import '../services/sha256_service.dart';
import 'posix_file_lock_bindings.dart';
import 'win32_file_lock_bindings.dart';

/// Non-blocking cooperative host-local file lock and atomic temporary-file
/// publication manager implementing `TDF-PUB-002` and `TDF-PUB-003`.
@immutable
class HostFileLockManager<E extends Exception> {
  /// Creates a [HostFileLockManager] building domain errors with [createException].
  const HostFileLockManager({
    required this.createException,
    this.hostLockDirectoryOverride,
    this.lockAcquireTimeout = defaultLockAcquireTimeout,
  });

  /// Default bounded timeout when acquiring a contended OS file lock (`5` seconds).
  static const Duration defaultLockAcquireTimeout = Duration(seconds: 5);

  /// Initial polling delay when backing off on OS lock contention or Win32 sharing errors (`10ms`).
  static const Duration initialBackoff = Duration(milliseconds: 10);

  /// Maximum single sleep interval while polling a contended OS file lock (`100ms`).
  static const Duration maxAcquireBackoff = Duration(milliseconds: 100);

  /// Maximum total attempts for Windows `MoveFileExW` replacement on transient sharing errors (`5`).
  static const int maxWindowsRenameAttempts = 5;

  /// Maximum single sleep interval while retrying Windows `MoveFileExW` sharing errors (`80ms`).
  static const Duration maxWindowsRenameBackoff = Duration(milliseconds: 80);

  static final Object _heldLocksZoneKey = Object();
  static const String _hexDigits = '0123456789abcdef';
  static final Map<String, Completer<void>> _inProcessQueues =
      <String, Completer<void>>{};
  static const int _maxVerifiedPosixLockDirs = 64;
  static final math.Random _secureRandom = math.Random.secure();
  static final RegExp _separatorSequencePattern = RegExp(r'[\\/]+');
  static final Set<String> _verifiedPosixLockDirs = <String>{};
  static final RegExp _windowsDrivePattern = RegExp(r'^[a-zA-Z]:[\\/]');

  /// Factory function constructing a typed domain exception with an optional underlying cause.
  final E Function(String message, {Object? cause}) createException;

  /// Optional directory override for `<host_lock_dir>` used in hermetic filesystem tests.
  final String? hostLockDirectoryOverride;

  /// Maximum duration to wait for an exclusive lock before aborting with [createException].
  final Duration lockAcquireTimeout;

  /// Applies permissions and polls [tryLock] on an opened POSIX [descriptor],
  /// guaranteeing [closeDescriptor] runs if any step throws before ownership
  /// transfers to the returned releaser.
  @visibleForTesting
  Future<void Function()> acquirePosixDescriptorLock({
    required int descriptor,
    required void Function() applyPermissions,
    required bool Function() tryLock,
    required void Function(int descriptor) closeDescriptor,
    required void Function(int descriptor) releaseAndClose,
    required String lockFilePath,
    required String targetHash,
    required Stopwatch stopwatch,
  }) async {
    var acquired = false;
    try {
      applyPermissions();
      await _pollLockWithBackoff(
        tryAcquire: tryLock,
        targetHash: targetHash,
        lockFilePath: lockFilePath,
        stopwatch: stopwatch,
      );
      acquired = true;
      return () => releaseAndClose(descriptor);
    } finally {
      if (!acquired) {
        closeDescriptor(descriptor);
      }
    }
  }

  /// Applies POSIX `chmod` [mode] to [path] via native libc FFI on Linux and
  /// Android, retrying `EINTR` and ignoring non-POSIX or inaccessible path
  /// errors on a best-effort basis without spawning subprocesses.
  static void applyPosixChmodBestEffort(String path, int mode) =>
      PosixLockBindings.applyChmodBestEffort(path, mode);

  /// Applies descriptor-based `fchmod` via [performFchmod], tolerating
  /// non-POSIX filesystem errnos (`EPERM`, `EINVAL`, `ENOSYS`, `EOPNOTSUPP`)
  /// with a debug log event and throwing via [createException] on hard errors.
  @visibleForTesting
  void applyPosixFchmodBestEffort({
    required int Function() performFchmod,
    required int Function() readErrno,
    required String path,
    String Function(String details)? formatFailureMessage,
  }) {
    while (true) {
      if (performFchmod() == 0) {
        return;
      }
      final errorCode = readErrno();
      if (errorCode == PosixLockBindings.eintr) {
        continue;
      }
      if (isTolerablePosixFchmodErrno(errorCode)) {
        PosixLockBindings.logFchmodSkipped(errorCode);
        return;
      }
      throw _posixException(
        'fchmod',
        path,
        errorCode,
        formatFailureMessage: formatFailureMessage,
      );
    }
  }

  /// Resolves [targetPath] to its canonical `/`-separated UTF-8 form (`TDF-PUB-002`).
  static String canonicalizeTargetPath(String targetPath, {bool? isWindows}) {
    final effectiveWindows = isWindows ?? Platform.isWindows;
    final trimmed = TdfFilePath.trimTrailingSeparators(targetPath.trim());
    if (trimmed.isEmpty) {
      return '';
    }
    final canQueryHost =
        effectiveWindows == Platform.isWindows &&
        (Platform.isWindows || !_windowsDrivePattern.hasMatch(trimmed));
    final resolved = canQueryHost
        ? _resolveRealTargetPathOnHost(trimmed)
        : trimmed;
    return _normalizeCanonicalSeparators(resolved, isWindows: effectiveWindows);
  }

  /// Closes a Win32 write handle via [closeHandle], logging and throwing a formatted exception on failure.
  @visibleForTesting
  void closeWindowsWriteHandle({
    required bool Function() closeHandle,
    required int Function() readLastError,
    required String tempPath,
    String Function(String details)? formatFailureMessage,
  }) {
    if (closeHandle()) {
      return;
    }
    final code = readLastError();
    final details = 'CloseHandle failed (Win32 error $code)';
    AppLogger.event(
      LogLevel.error,
      LogTag.storage,
      'local.write.close_failed',
      fields: <String, Object?>{'win32_error': code},
    );
    throw createException(
      formatFailureMessage != null
          ? formatFailureMessage(details)
          : '$details: $tempPath',
      cause: FileSystemException(
        details,
        tempPath,
        OSError('Win32 error $code', code),
      ),
    );
  }

  /// Computes the 64-character lowercase hexadecimal SHA-256 `<targetPathHash>` for [targetPath].
  static String computeTargetPathHash(String targetPath, {bool? isWindows}) {
    final canonical = canonicalizeTargetPath(targetPath, isWindows: isWindows);
    return Sha256Service.hashHex(utf8.encode(canonical));
  }

  /// Returns the real numeric POSIX user ID (`getuid()`) on Linux/Android, or `0` on Windows.
  static int getPosixUid() {
    if (Platform.isLinux || Platform.isAndroid) {
      return PosixLockBindings.instance.getuid();
    }
    return 0;
  }

  /// Returns `true` when [lockDirectoryPath] is currently present in the verified POSIX lock directory cache.
  @visibleForTesting
  static bool isPosixLockDirectoryVerifiedForTesting(
    String lockDirectoryPath,
  ) => _verifiedPosixLockDirs.contains(lockDirectoryPath);

  /// Returns `true` when POSIX `fchmod` [errorCode] indicates a non-POSIX
  /// filesystem (`EPERM`, `EINVAL`, `ENOSYS`, `EOPNOTSUPP`) where permission
  /// adjustment is unsupported after `open(..., 0600)`.
  @visibleForTesting
  static bool isTolerablePosixFchmodErrno(int errorCode) =>
      PosixLockBindings.isTolerableFchmodErrno(errorCode);

  /// Retries [performMove] up to [maxWindowsRenameAttempts] times on transient Win32 sharing errors (`32`, `5`).
  @visibleForTesting
  Future<void> replaceTargetWithSharingRetry({
    required int? Function() performMove,
    required void Function() cleanupTemp,
    Future<void> Function(Duration)? delay,
    String? targetPath,
    String Function(String details)? formatFailureMessage,
  }) async {
    final waitDelay = delay ?? Future<void>.delayed;
    var backoffMs = initialBackoff.inMilliseconds;
    for (var attempt = 0; attempt < maxWindowsRenameAttempts; attempt++) {
      final int? errorCode;
      try {
        errorCode = performMove();
      } on Object catch (error) {
        cleanupTemp();
        if (error is E) rethrow;
        final details = error.toString();
        throw createException(
          formatFailureMessage != null
              ? formatFailureMessage(details)
              : details,
          cause: error,
        );
      }
      if (errorCode == null) {
        return;
      }
      final isTransientSharing =
          errorCode == Win32LockBindings.errorSharingViolation ||
          errorCode == Win32LockBindings.errorAccessDenied;
      final hasRemainingRetry = attempt + 1 < maxWindowsRenameAttempts;
      if (!isTransientSharing || !hasRemainingRetry) {
        cleanupTemp();
        _throwWindowsReplaceFailure(
          errorCode: errorCode,
          targetPath: targetPath,
          formatFailureMessage: formatFailureMessage,
        );
      }
      await waitDelay(Duration(milliseconds: backoffMs));
      final doubled = backoffMs * 2;
      final cap = maxWindowsRenameBackoff.inMilliseconds;
      backoffMs = doubled > cap ? cap : doubled;
    }
  }

  /// Resolves `<host_lock_dir>` across Linux, Android, and Windows per `TDF-PUB-002`.
  static String resolveHostLockDirectory({
    Map<String, String>? environment,
    bool? isAndroid,
    bool? isWindows,
    String? systemTempPath,
    int? uidOverride,
  }) {
    final activeEnvironment = environment ?? Platform.environment;
    final effectiveWindows = isWindows ?? Platform.isWindows;
    final effectiveAndroid = isAndroid ?? Platform.isAndroid;
    final fallbackTemp = TdfFilePath.trimTrailingSeparators(
      (systemTempPath ?? Directory.systemTemp.path).trim(),
    );

    if (effectiveWindows) {
      final localAppData = (activeEnvironment['LOCALAPPDATA'] ?? '').trim();
      if (localAppData.isNotEmpty) {
        final cleanLocal = TdfFilePath.trimTrailingSeparators(localAppData);
        return '$cleanLocal\\Temp\\tdf-locks';
      }
      return '$fallbackTemp\\tdf-locks';
    }

    final xdgRuntime = (activeEnvironment['XDG_RUNTIME_DIR'] ?? '').trim();
    if (!effectiveAndroid && xdgRuntime.startsWith('/')) {
      final cleanRuntime = TdfFilePath.trimTrailingSeparators(xdgRuntime);
      return '$cleanRuntime/tdf-locks';
    }

    final uid = uidOverride ?? getPosixUid();
    return '$fallbackTemp/tdf-locks-$uid';
  }

  /// Resolves `<host_lock_dir>/tdf-<targetPathHash>.lock` for [targetPath].
  String resolveLockFilePath(String targetPath) {
    final targetHash = computeTargetPathHash(targetPath);
    final lockDirectory = _effectiveLockDirectoryPath();
    final separator = Platform.pathSeparator;
    return '$lockDirectory${separator}tdf-$targetHash.lock';
  }

  /// Rejects symlinks, directories, pipes, and sockets at [lockFilePath] before opening the lock handle.
  @visibleForTesting
  void validateLockFileEntityType(
    FileSystemEntityType entityType,
    String lockFilePath,
  ) {
    if (entityType != FileSystemEntityType.notFound &&
        entityType != FileSystemEntityType.file) {
      throw createException('Invalid host lock file entity: $lockFilePath');
    }
  }

  /// Serializes [action] through an in-process FIFO queue and OS exclusive lock for [targetPath].
  Future<T> withExclusiveLock<T>(
    String targetPath,
    Future<T> Function() action, {
    bool inMemoryOnly = false,
  }) async {
    final targetHash = inMemoryOnly
        ? Sha256Service.hashHex(utf8.encode(targetPath))
        : computeTargetPathHash(targetPath);
    final lockKey = inMemoryOnly ? 'mem:$targetPath' : 'disk:$targetHash';
    final heldLocks = _currentHeldLocks();
    if (heldLocks.contains(lockKey)) {
      return await action();
    }

    final previousGate = _inProcessQueues[lockKey];
    final gate = Completer<void>();
    _inProcessQueues[lockKey] = gate;

    if (previousGate != null) {
      await previousGate.future;
    }
    final stopwatch = Stopwatch()..start();
    try {
      return await _acquireAndExecute<T>(
        targetPath: targetPath,
        targetHash: targetHash,
        lockKey: lockKey,
        inMemoryOnly: inMemoryOnly,
        heldLocks: heldLocks,
        stopwatch: stopwatch,
        action: action,
      );
    } finally {
      if (identical(_inProcessQueues[lockKey], gate)) {
        _inProcessQueues.remove(lockKey);
      }
      gate.complete();
    }
  }

  /// Loops POSIX `write` calls until [totalBytes] are written, retrying `EINTR` and aborting on zero-byte writes with `EIO`.
  @visibleForTesting
  void writeAllPosixLoop({
    required int totalBytes,
    required int Function(int offset, int remaining) performWrite,
    required int Function() readErrno,
    required String path,
    String Function(String details)? formatFailureMessage,
  }) {
    var writtenTotal = 0;
    while (writtenTotal < totalBytes) {
      final writtenNow = performWrite(writtenTotal, totalBytes - writtenTotal);
      if (writtenNow > 0) {
        writtenTotal += writtenNow;
        continue;
      }
      if (writtenNow == 0) {
        throw _posixException(
          'write',
          path,
          PosixLockBindings.eio,
          formatFailureMessage: formatFailureMessage,
        );
      }
      final errorCode = readErrno();
      if (errorCode != PosixLockBindings.eintr) {
        throw _posixException(
          'write',
          path,
          errorCode,
          formatFailureMessage: formatFailureMessage,
        );
      }
    }
  }

  /// Loops Win32 `WriteFile` calls until [totalBytes] are written, aborting cleanly if `WriteFile` fails or writes zero bytes.
  @visibleForTesting
  void writeAllWindowsLoop({
    required int totalBytes,
    required ({bool succeeded, int bytesWritten}) Function(
      int offset,
      int remaining,
    )
    performWrite,
    required int Function() readLastError,
    required String path,
    String Function(String details)? formatFailureMessage,
  }) {
    var writtenTotal = 0;
    while (writtenTotal < totalBytes) {
      final result = performWrite(writtenTotal, totalBytes - writtenTotal);
      if (!result.succeeded) {
        final code = readLastError();
        final details = 'WriteFile failed (Win32 error $code)';
        throw createException(
          formatFailureMessage != null
              ? formatFailureMessage(details)
              : '$details: $path',
          cause: FileSystemException(
            details,
            path,
            OSError('Win32 error $code', code),
          ),
        );
      }
      if (result.bytesWritten <= 0) {
        const details = 'WriteFile wrote zero bytes';
        throw createException(
          formatFailureMessage != null
              ? formatFailureMessage(details)
              : '$details: $path',
          cause: FileSystemException(details, path),
        );
      }
      writtenTotal += result.bytesWritten;
    }
  }

  /// Writes [bytes] to a `0600` CSPRNG temporary file, flushes it, and atomically replaces [targetPath].
  Future<void> writeAtomically(
    String targetPath,
    List<int> bytes, {
    String? targetIsDirectoryMessage,
    String? targetIsSymlinkMessage,
    String Function(String details)? formatFailureMessage,
  }) async {
    switch (FileSystemEntity.typeSync(targetPath, followLinks: false)) {
      case FileSystemEntityType.directory:
        throw createException(
          targetIsDirectoryMessage ?? 'Target path is a directory: $targetPath',
        );
      case FileSystemEntityType.link:
        throw createException(
          targetIsSymlinkMessage ??
              'Target path is a symbolic link: $targetPath',
        );
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        const details = 'Target path is not a regular file';
        throw createException(
          formatFailureMessage != null
              ? formatFailureMessage(details)
              : '$details: $targetPath',
        );
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.file:
        break;
    }
    if (Platform.isWindows) {
      await _writeAtomicallyWindows(
        targetPath,
        bytes,
        formatFailureMessage: formatFailureMessage,
      );
      return;
    }
    _writeAtomicallyPosix(
      targetPath,
      bytes,
      formatFailureMessage: formatFailureMessage,
    );
  }

  /// Acquires the OS lock (when [inMemoryOnly] is `false`) and runs [action] in a re-entrant [Zone].
  Future<T> _acquireAndExecute<T>({
    required String targetPath,
    required String targetHash,
    required String lockKey,
    required bool inMemoryOnly,
    required Set<String> heldLocks,
    required Stopwatch stopwatch,
    required Future<T> Function() action,
  }) async {
    final nextHeld = Set<String>.unmodifiable(<String>{...heldLocks, lockKey});
    if (inMemoryOnly) {
      return runZoned(
        action,
        zoneValues: <Object?, Object?>{_heldLocksZoneKey: nextHeld},
      );
    }
    final lockDirectory = _effectiveLockDirectoryPath();
    final lockFilePath =
        '$lockDirectory${Platform.pathSeparator}tdf-$targetHash.lock';
    final releaseLock = await _acquireOsFileLock(
      lockDirectoryPath: lockDirectory,
      lockFilePath: lockFilePath,
      targetHash: targetHash,
      stopwatch: stopwatch,
    );
    _logLockEvent(
      LogLevel.info,
      'local.lock.acquire',
      targetHash: targetHash,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
    final holdStopwatch = Stopwatch()..start();
    try {
      return await runZoned(
        action,
        zoneValues: <Object?, Object?>{_heldLocksZoneKey: nextHeld},
      );
    } finally {
      releaseLock();
      _logLockEvent(
        LogLevel.info,
        'local.lock.release',
        targetHash: targetHash,
        elapsedMs: holdStopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Opens [lockFilePath] and polls non-blocking OS lock calls until acquired or [lockAcquireTimeout] expires.
  Future<void Function()> _acquireOsFileLock({
    required String lockDirectoryPath,
    required String lockFilePath,
    required String targetHash,
    required Stopwatch stopwatch,
  }) {
    if (Platform.isWindows) {
      return _acquireWindowsFileLock(
        lockDirectoryPath: lockDirectoryPath,
        lockFilePath: lockFilePath,
        targetHash: targetHash,
        stopwatch: stopwatch,
      );
    }
    return _acquirePosixFileLock(
      lockDirectoryPath: lockDirectoryPath,
      lockFilePath: lockFilePath,
      targetHash: targetHash,
      stopwatch: stopwatch,
    );
  }

  /// Opens [lockFilePath] (`0600`) and polls `flock(LOCK_EX | LOCK_NB)` with exponential backoff.
  Future<void Function()> _acquirePosixFileLock({
    required String lockDirectoryPath,
    required String lockFilePath,
    required String targetHash,
    required Stopwatch stopwatch,
  }) {
    final usedCache = _verifiedPosixLockDirs.contains(lockDirectoryPath);
    if (!usedCache) {
      _ensurePosixLockDirectory(lockDirectoryPath);
    }
    validateLockFileEntityType(
      FileSystemEntity.typeSync(lockFilePath, followLinks: false),
      lockFilePath,
    );

    final bindings = PosixLockBindings.instance;
    final openFlags =
        PosixLockBindings.oRdwr |
        PosixLockBindings.oCreat |
        PosixLockBindings.oCloexec |
        bindings.noFollowFlag;
    final openOutcome = bindings.openRaw(
      lockFilePath,
      openFlags,
      PosixLockBindings.fileMode0600,
    );
    final int descriptor;
    if (openOutcome.descriptor >= 0) {
      descriptor = openOutcome.descriptor;
    } else if (usedCache && openOutcome.errorCode == PosixLockBindings.enoent) {
      _verifiedPosixLockDirs.remove(lockDirectoryPath);
      _ensurePosixLockDirectory(lockDirectoryPath);
      validateLockFileEntityType(
        FileSystemEntity.typeSync(lockFilePath, followLinks: false),
        lockFilePath,
      );
      descriptor = _posixOpen(
        lockFilePath,
        openFlags,
        PosixLockBindings.fileMode0600,
      );
    } else {
      throw _posixException('open', lockFilePath, openOutcome.errorCode);
    }
    return acquirePosixDescriptorLock(
      descriptor: descriptor,
      applyPermissions: () => _posixFchmodBestEffort(
        descriptor,
        PosixLockBindings.fileMode0600,
        lockFilePath,
      ),
      tryLock: () => _posixTryFlockExclusive(descriptor, lockFilePath),
      closeDescriptor: bindings.close,
      releaseAndClose: PosixLockBindings.releaseAndClose,
      lockFilePath: lockFilePath,
      targetHash: targetHash,
      stopwatch: stopwatch,
    );
  }

  /// Opens [lockFilePath] (`FILE_SHARE_READ | FILE_SHARE_WRITE`) and polls `LockFileEx(LOCKFILE_FAIL_IMMEDIATELY)`.
  Future<void Function()> _acquireWindowsFileLock({
    required String lockDirectoryPath,
    required String lockFilePath,
    required String targetHash,
    required Stopwatch stopwatch,
  }) async {
    try {
      Directory(lockDirectoryPath).createSync(recursive: true);
    } on FileSystemException catch (error) {
      throw createException(
        'Failed to create Windows host lock directory: ${error.message}',
        cause: error,
      );
    }
    validateLockFileEntityType(
      FileSystemEntity.typeSync(lockFilePath, followLinks: false),
      lockFilePath,
    );
    final handle = _win32CreateFile(
      lockFilePath,
      desiredAccess: Win32LockBindings.genericReadWrite,
      shareMode: Win32LockBindings.fileShareReadWrite,
      creationDisposition: Win32LockBindings.openAlways,
      flagsAndAttributes:
          Win32LockBindings.fileAttributeNormal |
          Win32LockBindings.fileFlagOpenReparsePoint,
    );
    final lockHandle = Win32LockBindings.instance.allocateLockHandle(handle);

    var acquired = false;
    try {
      await _pollLockWithBackoff(
        tryAcquire: () => _win32TryLockExclusive(lockHandle, lockFilePath),
        targetHash: targetHash,
        lockFilePath: lockFilePath,
        stopwatch: stopwatch,
      );
      acquired = true;
      return lockHandle.unlockAndClose;
    } finally {
      if (!acquired) {
        lockHandle.closeWithoutUnlock();
      }
    }
  }

  /// Reads the active set of re-entrantly held lock keys from [Zone.current].
  static Set<String> _currentHeldLocks() {
    if (Zone.current[_heldLocksZoneKey] case final Set<String> active) {
      return active;
    }
    return const <String>{};
  }

  /// Resolves the trimmed [hostLockDirectoryOverride] or falls back to [resolveHostLockDirectory].
  String _effectiveLockDirectoryPath() {
    final rawOverride = hostLockDirectoryOverride?.trim() ?? '';
    if (rawOverride.isNotEmpty) {
      return TdfFilePath.trimTrailingSeparators(rawOverride);
    }
    return resolveHostLockDirectory();
  }

  /// Creates [lockDirectoryPath] on POSIX, opens it with `O_DIRECTORY | O_NOFOLLOW`, and enforces owner-only `0700` via `fchmod`.
  void _ensurePosixLockDirectory(String lockDirectoryPath) {
    final initialType = FileSystemEntity.typeSync(
      lockDirectoryPath,
      followLinks: false,
    );
    if (initialType != FileSystemEntityType.notFound &&
        initialType != FileSystemEntityType.directory) {
      throw createException(
        'Host lock directory path is not a directory: $lockDirectoryPath',
      );
    }
    try {
      Directory(lockDirectoryPath).parent.createSync(recursive: true);
    } on FileSystemException catch (error) {
      throw createException(
        'Failed to prepare parent of host lock directory: ${error.message}',
        cause: error,
      );
    }

    final bindings = PosixLockBindings.instance;
    final mkdirOutcome = bindings.mkdirRaw(
      lockDirectoryPath,
      PosixLockBindings.dirMode0700,
    );
    if (mkdirOutcome.result != 0 &&
        mkdirOutcome.errorCode != PosixLockBindings.eexist) {
      throw _posixException('mkdir', lockDirectoryPath, mkdirOutcome.errorCode);
    }
    final openFlags =
        PosixLockBindings.oRdonly |
        PosixLockBindings.oCloexec |
        bindings.directoryFlag |
        bindings.noFollowFlag;
    final directoryDescriptor = _posixOpen(lockDirectoryPath, openFlags, 0);
    try {
      _posixFchmodStrict(
        directoryDescriptor,
        PosixLockBindings.dirMode0700,
        lockDirectoryPath,
      );
    } finally {
      bindings.close(directoryDescriptor);
    }
    if (_verifiedPosixLockDirs.length >= _maxVerifiedPosixLockDirs) {
      _verifiedPosixLockDirs.clear();
    }
    _verifiedPosixLockDirs.add(lockDirectoryPath);
  }

  /// Ensures [parentDirectory] exists before staging a temporary file, mapping OS failures via [createException].
  void _ensureTargetParentDirectory(
    Directory parentDirectory, {
    String Function(String details)? formatFailureMessage,
  }) {
    try {
      parentDirectory.createSync(recursive: true);
    } on FileSystemException catch (error) {
      final details = error.message;
      throw createException(
        formatFailureMessage != null
            ? formatFailureMessage(details)
            : 'Failed to prepare target directory ($details): ${parentDirectory.path}',
        cause: error,
      );
    }
  }

  /// Generates a 128-bit (`32`-char lowercase hex) CSPRNG temporary file suffix.
  static String _generateTempHexSuffix() {
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(_hexDigits[_secureRandom.nextInt(16)]);
    }
    return buffer.toString();
  }

  /// Emits a sanitized structured `local.lock.*` event to [AppLogger] when enabled.
  static void _logLockEvent(
    LogLevel level,
    String eventName, {
    required String targetHash,
    required int elapsedMs,
  }) {
    if (!AppLogger.shouldLog(level)) {
      return;
    }
    final shortHash = targetHash.length > 12
        ? targetHash.substring(0, 12)
        : targetHash;
    AppLogger.event(
      level,
      LogTag.storage,
      eventName,
      fields: <String, Object?>{'hash': shortHash, 'elapsed_ms': elapsedMs},
    );
  }

  /// Normalizes path separators to `/` and lowercases Windows NTFS paths (`TDF-PUB-002`).
  static String _normalizeCanonicalSeparators(
    String rawPath, {
    required bool isWindows,
  }) {
    var cleaned = rawPath;
    if (cleaned.startsWith(r'\\?\') &&
        cleaned.length >= 7 &&
        _windowsDrivePattern.hasMatch(cleaned.substring(4))) {
      cleaned = cleaned.substring(4);
    }
    final leadingSlash = cleaned.startsWith('/');
    final segments = <String>[];
    for (final part in cleaned.split(_separatorSequencePattern)) {
      if (part.isNotEmpty) {
        segments.add(part);
      }
    }
    final joined = leadingSlash ? '/${segments.join('/')}' : segments.join('/');
    final normalized = joined.length == 2 && joined.codeUnitAt(1) == 0x3A
        ? '$joined/'
        : joined;
    return isWindows ? normalized.toLowerCase() : normalized;
  }

  /// Polls [tryAcquire] with `10ms..100ms` exponential backoff until acquired or [lockAcquireTimeout] elapses.
  Future<void> _pollLockWithBackoff({
    required bool Function() tryAcquire,
    required String targetHash,
    required String lockFilePath,
    required Stopwatch stopwatch,
  }) async {
    var backoffMs = initialBackoff.inMilliseconds;
    while (true) {
      if (tryAcquire()) {
        return;
      }
      final remaining = lockAcquireTimeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        final elapsedMs = stopwatch.elapsedMilliseconds;
        _logLockEvent(
          LogLevel.error,
          'local.lock.timeout',
          targetHash: targetHash,
          elapsedMs: elapsedMs,
        );
        throw createException(
          'Timed out after ${elapsedMs}ms waiting for host file lock',
          cause: FileSystemException(
            'Host file lock acquisition timed out',
            lockFilePath,
          ),
        );
      }
      final remainingMs = remaining.inMilliseconds;
      final sleepMs = remainingMs <= 0
          ? 1
          : (backoffMs < remainingMs ? backoffMs : remainingMs);
      await Future<void>.delayed(Duration(milliseconds: sleepMs));
      final doubled = backoffMs * 2;
      final cap = maxAcquireBackoff.inMilliseconds;
      backoffMs = doubled > cap ? cap : doubled;
    }
  }

  /// Wraps a POSIX `errno` failure on [operation] and [path] into [E].
  E _posixException(
    String operation,
    String path,
    int errorCode, {
    String Function(String details)? formatFailureMessage,
  }) {
    final details = '$operation failed (errno $errorCode)';
    final osException = FileSystemException(
      details,
      path,
      OSError('errno $errorCode', errorCode),
    );
    final message = formatFailureMessage != null
        ? formatFailureMessage(details)
        : '$details: $path';
    return createException(message, cause: osException);
  }

  /// Applies POSIX `fchmod` [mode] to open [descriptor], tolerating non-POSIX
  /// filesystem errnos and forwarding [formatFailureMessage] on hard errors.
  void _posixFchmodBestEffort(
    int descriptor,
    int mode,
    String path, {
    String Function(String details)? formatFailureMessage,
  }) {
    final bindings = PosixLockBindings.instance;
    applyPosixFchmodBestEffort(
      performFchmod: () => bindings.fchmod(descriptor, mode),
      readErrno: bindings.readErrno,
      path: path,
      formatFailureMessage: formatFailureMessage,
    );
  }

  /// Strictly enforces [mode] on open [descriptor] via POSIX `fchmod`, retrying `EINTR` and throwing on any failure.
  void _posixFchmodStrict(int descriptor, int mode, String path) {
    final bindings = PosixLockBindings.instance;
    while (true) {
      if (bindings.fchmod(descriptor, mode) == 0) {
        return;
      }
      final errorCode = bindings.readErrno();
      if (errorCode != PosixLockBindings.eintr) {
        throw _posixException('fchmod', path, errorCode);
      }
    }
  }

  /// Flushes [descriptor] to storage via `fsync`, retrying on `EINTR`.
  void _posixFsync(
    int descriptor,
    String path, {
    String Function(String details)? formatFailureMessage,
  }) {
    final errorCode = PosixLockBindings.instance.fsyncDescriptor(descriptor);
    if (errorCode != 0) {
      throw _posixException(
        'fsync',
        path,
        errorCode,
        formatFailureMessage: formatFailureMessage,
      );
    }
  }

  /// Opens [path] with POSIX `open(flags, mode)`, retrying on `EINTR` and throwing via [createException] on failure.
  int _posixOpen(
    String path,
    int flags,
    int mode, {
    String Function(String details)? formatFailureMessage,
  }) {
    final outcome = PosixLockBindings.instance.openRaw(path, flags, mode);
    if (outcome.descriptor >= 0) {
      return outcome.descriptor;
    }
    throw _posixException(
      'open',
      path,
      outcome.errorCode,
      formatFailureMessage: formatFailureMessage,
    );
  }

  /// Atomically renames [fromPath] over [toPath] via POSIX `rename`.
  void _posixRename(
    String fromPath,
    String toPath, {
    String Function(String details)? formatFailureMessage,
  }) {
    final outcome = PosixLockBindings.instance.renameRaw(fromPath, toPath);
    if (outcome.result != 0) {
      throw _posixException(
        'rename',
        toPath,
        outcome.errorCode,
        formatFailureMessage: formatFailureMessage,
      );
    }
  }

  /// Attempts a non-blocking `flock(LOCK_EX | LOCK_NB)` on [descriptor].
  bool _posixTryFlockExclusive(int descriptor, String lockFilePath) {
    final errorCode = PosixLockBindings.instance.tryFlockExclusiveRaw(
      descriptor,
    );
    if (errorCode == 0) {
      return true;
    }
    if (errorCode == null) {
      return false;
    }
    throw _posixException('flock', lockFilePath, errorCode);
  }

  /// Writes all [bytes] to [descriptor] via POSIX `write`, handling partial writes and `EINTR`.
  void _posixWriteAll(
    int descriptor,
    List<int> bytes,
    String path, {
    String Function(String details)? formatFailureMessage,
  }) {
    if (bytes.isEmpty) {
      return;
    }
    final bindings = PosixLockBindings.instance;
    bindings.withByteBuffer(
      bytes,
      (performWrite) => writeAllPosixLoop(
        totalBytes: bytes.length,
        performWrite: performWrite,
        readErrno: bindings.readErrno,
        path: path,
        formatFailureMessage: formatFailureMessage,
      ),
      descriptor,
    );
  }

  /// Resolves the deepest existing ancestor directory of [targetPath] and appends remaining segments.
  static String _resolveExistingAncestorAndSuffix(String targetPath) {
    final trailingSegments = <String>[];
    var cursor = File(targetPath).absolute.path;
    while (true) {
      final parentPath = File(cursor).parent.path;
      if (parentPath == cursor) {
        break;
      }
      trailingSegments.add(TdfFilePath.extractFileNameFromPath(cursor));
      cursor = parentPath;
      final resolvedDir = _safeResolveDirectoryLinks(cursor);
      if (resolvedDir != null) {
        final cleanAncestor = TdfFilePath.trimTrailingSeparators(resolvedDir);
        final orderedTail = trailingSegments.reversed.join('/');
        return cleanAncestor == '/'
            ? '/$orderedTail'
            : '$cleanAncestor/$orderedTail';
      }
    }
    return File(targetPath).absolute.path;
  }

  /// Resolves symlinks on [trimmedPath] directly when it exists, or via its ancestor directory when absent.
  static String _resolveRealTargetPathOnHost(String trimmedPath) {
    final entityType = _safeEntityType(trimmedPath, followLinks: true);
    if (entityType == FileSystemEntityType.file) {
      return _safeResolveFileLinks(trimmedPath) ??
          File(trimmedPath).absolute.path;
    }
    if (entityType == FileSystemEntityType.directory) {
      return _safeResolveDirectoryLinks(trimmedPath) ??
          Directory(trimmedPath).absolute.path;
    }
    return _resolveExistingAncestorAndSuffix(trimmedPath);
  }

  /// Queries [FileSystemEntity.typeSync] and returns `notFound` on OS errors.
  static FileSystemEntityType _safeEntityType(
    String path, {
    required bool followLinks,
  }) {
    try {
      return FileSystemEntity.typeSync(path, followLinks: followLinks);
    } on FileSystemException {
      return FileSystemEntityType.notFound;
    }
  }

  /// Resolves symbolic links for an existing directory at [directoryPath], or returns `null` if missing.
  static String? _safeResolveDirectoryLinks(String directoryPath) {
    try {
      if (!Directory(directoryPath).existsSync()) {
        return null;
      }
      return Directory(directoryPath).resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Resolves symbolic links for an existing regular file at [filePath], or returns `null` if failed.
  static String? _safeResolveFileLinks(String filePath) {
    try {
      return File(filePath).resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Throws the domain exception for a terminal Win32 `MoveFileExW` failure.
  Never _throwWindowsReplaceFailure({
    required int errorCode,
    required String? targetPath,
    required String Function(String details)? formatFailureMessage,
  }) {
    final label = targetPath ?? 'target';
    final details = 'MoveFileExW failed (Win32 error $errorCode)';
    final message = formatFailureMessage != null
        ? formatFailureMessage(details)
        : 'Atomic target replacement failed (Win32 error $errorCode) for $label';
    throw createException(
      message,
      cause: FileSystemException(
        'MoveFileExW failed',
        targetPath,
        OSError('Win32 error $errorCode', errorCode),
      ),
    );
  }

  /// Opens or creates [path] via Win32 `CreateFileW` and throws via [createException] on invalid handle.
  int _win32CreateFile(
    String path, {
    required int desiredAccess,
    required int shareMode,
    required int creationDisposition,
    int flagsAndAttributes = Win32LockBindings.fileAttributeNormal,
    String Function(String details)? formatFailureMessage,
  }) {
    final outcome = Win32LockBindings.instance.createFileRaw(
      path,
      desiredAccess: desiredAccess,
      shareMode: shareMode,
      creationDisposition: creationDisposition,
      flagsAndAttributes: flagsAndAttributes,
    );
    if (outcome.handle == -1 || outcome.handle == 0) {
      final details = 'CreateFileW failed (Win32 error ${outcome.errorCode})';
      final cause = FileSystemException(
        details,
        path,
        OSError('Win32 error ${outcome.errorCode}', outcome.errorCode),
      );
      final message = formatFailureMessage != null
          ? formatFailureMessage(details)
          : '$details: $path';
      throw createException(message, cause: cause);
    }
    return outcome.handle;
  }

  /// Attempts a non-blocking `LockFileEx` over bytes `0..1` on [lockHandle].
  bool _win32TryLockExclusive(Win32LockHandle lockHandle, String lockFilePath) {
    final errorCode = lockHandle.tryLockExclusiveRaw();
    if (errorCode == 0) {
      return true;
    }
    if (errorCode == null) {
      return false;
    }
    throw createException(
      'LockFileEx failed (Win32 error $errorCode): $lockFilePath',
      cause: FileSystemException(
        'LockFileEx failed',
        lockFilePath,
        OSError('Win32 error $errorCode', errorCode),
      ),
    );
  }

  /// Writes all [bytes] and calls `FlushFileBuffers` on Win32 [handle].
  void _win32WriteAndFlush(
    int handle,
    List<int> bytes,
    String tempPath, {
    String Function(String details)? formatFailureMessage,
  }) {
    final bindings = Win32LockBindings.instance;
    if (bytes.isNotEmpty) {
      bindings.withWriteBuffers(
        handle,
        bytes,
        (performWrite) => writeAllWindowsLoop(
          totalBytes: bytes.length,
          performWrite: performWrite,
          readLastError: bindings.getLastError,
          path: tempPath,
          formatFailureMessage: formatFailureMessage,
        ),
      );
    }
    if (bindings.flushFileBuffers(handle) == 0) {
      final code = bindings.getLastError();
      final details = 'FlushFileBuffers failed (Win32 error $code)';
      throw createException(
        formatFailureMessage != null
            ? formatFailureMessage(details)
            : '$details: $tempPath',
        cause: FileSystemException(
          details,
          tempPath,
          OSError('Win32 error $code', code),
        ),
      );
    }
  }

  /// Writes [bytes] to an exclusive `0600` `.tmp.<32hex>` file, flushes it, and renames over [targetPath] on POSIX.
  void _writeAtomicallyPosix(
    String targetPath,
    List<int> bytes, {
    String Function(String details)? formatFailureMessage,
  }) {
    final parentDirectory = File(targetPath).parent;
    _ensureTargetParentDirectory(
      parentDirectory,
      formatFailureMessage: formatFailureMessage,
    );
    final cleanParent = TdfFilePath.trimTrailingSeparators(
      parentDirectory.path,
    );
    final baseName = TdfFilePath.extractFileNameFromPath(targetPath);
    final prefix = cleanParent == '/' ? '' : cleanParent;
    final tempPath = '$prefix/.$baseName.tmp.${_generateTempHexSuffix()}';

    final bindings = PosixLockBindings.instance;
    final openFlags =
        PosixLockBindings.oWronly |
        PosixLockBindings.oCreat |
        PosixLockBindings.oExcl |
        PosixLockBindings.oCloexec |
        bindings.noFollowFlag;
    final descriptor = _posixOpen(
      tempPath,
      openFlags,
      PosixLockBindings.fileMode0600,
      formatFailureMessage: formatFailureMessage,
    );
    var descriptorClosed = false;
    try {
      _posixFchmodBestEffort(
        descriptor,
        PosixLockBindings.fileMode0600,
        tempPath,
        formatFailureMessage: formatFailureMessage,
      );
      _posixWriteAll(
        descriptor,
        bytes,
        tempPath,
        formatFailureMessage: formatFailureMessage,
      );
      _posixFsync(
        descriptor,
        tempPath,
        formatFailureMessage: formatFailureMessage,
      );
      descriptorClosed = true;
      if (bindings.close(descriptor) != 0) {
        final code = bindings.readErrno();
        throw _posixException(
          'close',
          tempPath,
          code,
          formatFailureMessage: formatFailureMessage,
        );
      }
      _posixRename(
        tempPath,
        targetPath,
        formatFailureMessage: formatFailureMessage,
      );
      bindings.fsyncDirectoryBestEffort(parentDirectory.path);
    } on Object {
      if (!descriptorClosed) {
        bindings.close(descriptor);
      }
      PosixLockBindings.unlinkQuietly(tempPath);
      rethrow;
    }
  }

  /// Writes [bytes] to a `CREATE_NEW` `.tmp.<32hex>` file, flushes it, and replaces [targetPath] via `MoveFileExW`.
  Future<void> _writeAtomicallyWindows(
    String targetPath,
    List<int> bytes, {
    String Function(String details)? formatFailureMessage,
  }) async {
    final parentDirectory = File(targetPath).parent;
    _ensureTargetParentDirectory(
      parentDirectory,
      formatFailureMessage: formatFailureMessage,
    );
    final cleanParent = TdfFilePath.trimTrailingSeparators(
      parentDirectory.path,
    );
    final baseName = TdfFilePath.extractFileNameFromPath(targetPath);
    final separator = cleanParent.endsWith(r'\') ? '' : r'\';
    final tempPath =
        '$cleanParent$separator.$baseName.tmp.${_generateTempHexSuffix()}';

    final handle = _win32CreateFile(
      tempPath,
      desiredAccess: Win32LockBindings.genericWrite,
      shareMode: 0,
      creationDisposition: Win32LockBindings.createNew,
      flagsAndAttributes:
          Win32LockBindings.fileAttributeNormal |
          Win32LockBindings.fileFlagOpenReparsePoint,
      formatFailureMessage: formatFailureMessage,
    );
    var handleClosed = false;
    final bindings = Win32LockBindings.instance;
    try {
      _win32WriteAndFlush(
        handle,
        bytes,
        tempPath,
        formatFailureMessage: formatFailureMessage,
      );
      handleClosed = true;
      closeWindowsWriteHandle(
        closeHandle: () => bindings.closeHandle(handle) != 0,
        readLastError: bindings.getLastError,
        tempPath: tempPath,
        formatFailureMessage: formatFailureMessage,
      );
    } on Object {
      if (!handleClosed) {
        bindings.closeHandle(handle);
      }
      Win32LockBindings.unlinkQuietly(tempPath);
      rethrow;
    }

    await replaceTargetWithSharingRetry(
      performMove: () => Win32LockBindings.tryMoveReplace(tempPath, targetPath),
      cleanupTemp: () => Win32LockBindings.unlinkQuietly(tempPath),
      targetPath: targetPath,
      formatFailureMessage: formatFailureMessage,
    );
  }
}
