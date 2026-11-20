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
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/app_logger.dart';
import '../services/sha256_service.dart';

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
  static const int _posixDirMode0700 = 0x1C0;
  static const int _posixEagain = 11;
  static const int _posixEexist = 17;
  static const int _posixEintr = 4;
  static const int _posixEinval = 22;
  static const int _posixEnosys = 38;
  static const int _posixEopnotsupp = 95;
  static const int _posixEperm = 1;
  static const int _posixFileMode0600 = 0x180;
  static const int _posixLockEx = 2;
  static const int _posixLockNb = 4;
  static const int _posixLockUn = 8;
  static const int _posixOCloexec = 0x80000;
  static const int _posixOCreat = 0x0040;
  static const int _posixOExcl = 0x0080;
  static const int _posixORdonly = 0x0000;
  static const int _posixORdwr = 0x0002;
  static const int _posixOWronly = 0x0001;
  static final math.Random _secureRandom = math.Random.secure();
  static final RegExp _separatorSequencePattern = RegExp(r'[\\/]+');
  static const int _win32CreateNew = 1;
  static const int _win32ErrorAccessDenied = 5;
  static const int _win32ErrorLockViolation = 33;
  static const int _win32ErrorSharingViolation = 32;
  static const int _win32FileAttributeNormal = 0x00000080;
  static const int _win32FileShareReadWrite = 0x00000003;
  static const int _win32GenericReadWrite = 0xC0000000;
  static const int _win32GenericWrite = 0x40000000;
  static const int _win32LmemZeroInit = 0x0040;
  static const int _win32LockExclusiveImmediate = 0x00000003;
  static const int _win32MoveReplaceWriteThrough = 0x00000009;
  static const int _win32OpenAlways = 4;
  static const int _win32OverlappedByteSize = 32;
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
      if (errorCode == _posixEintr) {
        continue;
      }
      if (isTolerablePosixFchmodErrno(errorCode)) {
        _logFchmodSkipped(errorCode);
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
    final trimmed = _trimTrailingSeparators(targetPath.trim());
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

  /// Computes the 64-character lowercase hexadecimal SHA-256 `<targetPathHash>` for [targetPath].
  static String computeTargetPathHash(String targetPath, {bool? isWindows}) {
    final canonical = canonicalizeTargetPath(targetPath, isWindows: isWindows);
    return Sha256Service.hashHex(utf8.encode(canonical));
  }

  /// Returns the real numeric POSIX user ID (`getuid()`) on Linux/Android, or `0` on Windows.
  static int getPosixUid() {
    if (Platform.isLinux || Platform.isAndroid) {
      return _PosixLockBindings.instance.getuid();
    }
    return 0;
  }

  /// Returns `true` when POSIX `fchmod` [errorCode] indicates a non-POSIX
  /// filesystem (`EPERM`, `EINVAL`, `ENOSYS`, `EOPNOTSUPP`) where permission
  /// adjustment is unsupported after `open(..., 0600)`.
  @visibleForTesting
  static bool isTolerablePosixFchmodErrno(int errorCode) =>
      errorCode == _posixEperm ||
      errorCode == _posixEinval ||
      errorCode == _posixEnosys ||
      errorCode == _posixEopnotsupp;

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
          errorCode == _win32ErrorSharingViolation ||
          errorCode == _win32ErrorAccessDenied;
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
    final fallbackTemp = _trimTrailingSeparators(
      (systemTempPath ?? Directory.systemTemp.path).trim(),
    );

    if (effectiveWindows) {
      final localAppData = (activeEnvironment['LOCALAPPDATA'] ?? '').trim();
      if (localAppData.isNotEmpty) {
        final cleanLocal = _trimTrailingSeparators(localAppData);
        return '$cleanLocal\\Temp\\tdf-locks';
      }
      return '$fallbackTemp\\tdf-locks';
    }

    final xdgRuntime = (activeEnvironment['XDG_RUNTIME_DIR'] ?? '').trim();
    if (!effectiveAndroid && xdgRuntime.startsWith('/')) {
      final cleanRuntime = _trimTrailingSeparators(xdgRuntime);
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

    final stopwatch = Stopwatch()..start();
    final previousGate = _inProcessQueues[lockKey];
    final gate = Completer<void>();
    _inProcessQueues[lockKey] = gate;

    if (previousGate != null) {
      await previousGate.future;
    }
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

  /// Writes [bytes] to a `0600` CSPRNG temporary file, flushes it, and atomically replaces [targetPath].
  Future<void> writeAtomically(
    String targetPath,
    List<int> bytes, {
    String? targetIsDirectoryMessage,
    String? targetIsSymlinkMessage,
    String Function(String details)? formatFailureMessage,
  }) async {
    final targetType = FileSystemEntity.typeSync(
      targetPath,
      followLinks: false,
    );
    if (targetType == FileSystemEntityType.directory) {
      throw createException(
        targetIsDirectoryMessage ?? 'Target path is a directory: $targetPath',
      );
    }
    if (targetType == FileSystemEntityType.link) {
      throw createException(
        targetIsSymlinkMessage ?? 'Target path is a symbolic link: $targetPath',
      );
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
  }) async {
    _ensurePosixLockDirectory(lockDirectoryPath);
    final existingType = FileSystemEntity.typeSync(
      lockFilePath,
      followLinks: false,
    );
    if (existingType != FileSystemEntityType.notFound &&
        existingType != FileSystemEntityType.file) {
      throw createException('Invalid host lock file entity: $lockFilePath');
    }

    final bindings = _PosixLockBindings.instance;
    final openFlags =
        _posixORdwr | _posixOCreat | _posixOCloexec | bindings.noFollowFlag;
    final descriptor = _posixOpen(lockFilePath, openFlags, _posixFileMode0600);
    return acquirePosixDescriptorLock(
      descriptor: descriptor,
      applyPermissions: () =>
          _posixFchmodBestEffort(descriptor, _posixFileMode0600, lockFilePath),
      tryLock: () => _posixTryFlockExclusive(descriptor, lockFilePath),
      closeDescriptor: bindings.close,
      releaseAndClose: _posixReleaseAndClose,
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
    final bindings = _Win32LockBindings.instance;
    final handle = _win32CreateFile(
      lockFilePath,
      desiredAccess: _win32GenericReadWrite,
      shareMode: _win32FileShareReadWrite,
      creationDisposition: _win32OpenAlways,
    );
    final overlappedPointer = bindings.localAlloc(
      _win32LmemZeroInit,
      _win32OverlappedByteSize,
    );
    if (overlappedPointer.address == 0) {
      bindings.closeHandle(handle);
      throw const OutOfMemoryError();
    }

    var acquired = false;
    try {
      await _pollLockWithBackoff(
        tryAcquire: () =>
            _win32TryLockExclusive(handle, overlappedPointer, lockFilePath),
        targetHash: targetHash,
        lockFilePath: lockFilePath,
        stopwatch: stopwatch,
      );
      acquired = true;
      return () => _win32UnlockAndClose(handle, overlappedPointer);
    } finally {
      if (!acquired) {
        bindings.closeHandle(handle);
        bindings.localFree(overlappedPointer);
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
      return _trimTrailingSeparators(rawOverride);
    }
    return resolveHostLockDirectory();
  }

  /// Creates [lockDirectoryPath] on POSIX and enforces owner-only `0700` permissions.
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

    final bindings = _PosixLockBindings.instance;
    final pathPointer = bindings.allocateUtf8(lockDirectoryPath);
    final int mkdirResult;
    final int mkdirErrno;
    try {
      mkdirResult = bindings.mkdir(pathPointer, _posixDirMode0700);
      mkdirErrno = mkdirResult == 0 ? 0 : bindings.readErrno();
    } finally {
      bindings.freePointer(pathPointer.cast<Void>());
    }
    if (mkdirResult != 0 && mkdirErrno != _posixEexist) {
      throw _posixException('mkdir', lockDirectoryPath, mkdirErrno);
    }
    if (FileSystemEntity.typeSync(lockDirectoryPath, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw createException(
        'Host lock directory was replaced by a non-directory: $lockDirectoryPath',
      );
    }
    _posixChmod(lockDirectoryPath, _posixDirMode0700);
  }

  /// Extracts the trailing file name segment from [filePath].
  static String _extractBaseName(String filePath) {
    final parts = filePath.split(_separatorSequencePattern);
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].isNotEmpty) {
        return parts[i];
      }
    }
    return 'tasks.tdf';
  }

  /// Generates a 128-bit (`32`-char lowercase hex) CSPRNG temporary file suffix.
  static String _generateTempHexSuffix() {
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(_hexDigits[_secureRandom.nextInt(16)]);
    }
    return buffer.toString();
  }

  /// Emits a debug diagnostic event when `fchmod` is unsupported by the filesystem.
  static void _logFchmodSkipped(int errorCode) {
    if (!AppLogger.shouldLog(LogLevel.debug)) {
      return;
    }
    AppLogger.event(
      LogLevel.debug,
      LogTag.storage,
      'local.fchmod.skipped',
      fields: <String, Object?>{'errno': errorCode},
    );
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

  /// Applies POSIX `chmod` [mode] to [path], throwing via [createException] on failure.
  void _posixChmod(String path, int mode) {
    final bindings = _PosixLockBindings.instance;
    final pointer = bindings.allocateUtf8(path);
    final int result;
    final int errorCode;
    try {
      result = bindings.chmod(pointer, mode);
      errorCode = result == 0 ? 0 : bindings.readErrno();
    } finally {
      bindings.freePointer(pointer.cast<Void>());
    }
    if (result != 0) {
      throw _posixException('chmod', path, errorCode);
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
    final bindings = _PosixLockBindings.instance;
    applyPosixFchmodBestEffort(
      performFchmod: () => bindings.fchmod(descriptor, mode),
      readErrno: bindings.readErrno,
      path: path,
      formatFailureMessage: formatFailureMessage,
    );
  }

  /// Flushes [descriptor] to storage via `fsync`, retrying on `EINTR`.
  void _posixFsync(
    int descriptor,
    String path, {
    String Function(String details)? formatFailureMessage,
  }) {
    final bindings = _PosixLockBindings.instance;
    while (true) {
      if (bindings.fsync(descriptor) == 0) {
        return;
      }
      final errorCode = bindings.readErrno();
      if (errorCode != _posixEintr) {
        throw _posixException(
          'fsync',
          path,
          errorCode,
          formatFailureMessage: formatFailureMessage,
        );
      }
    }
  }

  /// Flushes the directory metadata of [directoryPath] when supported by the underlying POSIX filesystem.
  void _posixFsyncDirectoryBestEffort(String directoryPath) {
    final bindings = _PosixLockBindings.instance;
    final pathPointer = bindings.allocateUtf8(directoryPath);
    final int descriptor;
    try {
      descriptor = bindings.open(
        pathPointer,
        _posixORdonly | _posixOCloexec,
        0,
      );
    } finally {
      bindings.freePointer(pathPointer.cast<Void>());
    }
    if (descriptor < 0) {
      return;
    }
    try {
      while (bindings.fsync(descriptor) != 0) {
        if (bindings.readErrno() != _posixEintr) {
          break;
        }
      }
    } finally {
      bindings.close(descriptor);
    }
  }

  /// Opens [path] with POSIX `open(flags, mode)`, retrying on `EINTR`.
  int _posixOpen(
    String path,
    int flags,
    int mode, {
    String Function(String details)? formatFailureMessage,
  }) {
    final bindings = _PosixLockBindings.instance;
    final pointer = bindings.allocateUtf8(path);
    try {
      while (true) {
        final descriptor = bindings.open(pointer, flags, mode);
        if (descriptor >= 0) {
          return descriptor;
        }
        final errorCode = bindings.readErrno();
        if (errorCode != _posixEintr) {
          throw _posixException(
            'open',
            path,
            errorCode,
            formatFailureMessage: formatFailureMessage,
          );
        }
      }
    } finally {
      bindings.freePointer(pointer.cast<Void>());
    }
  }

  /// Releases the POSIX `flock` on [descriptor] and closes it without unlinking the lock file.
  static void _posixReleaseAndClose(int descriptor) {
    final bindings = _PosixLockBindings.instance;
    bindings.flock(descriptor, _posixLockUn);
    bindings.close(descriptor);
  }

  /// Atomically renames [fromPath] over [toPath] via POSIX `rename`.
  void _posixRename(
    String fromPath,
    String toPath, {
    String Function(String details)? formatFailureMessage,
  }) {
    final bindings = _PosixLockBindings.instance;
    final fromPointer = bindings.allocateUtf8(fromPath);
    final toPointer = bindings.allocateUtf8(toPath);
    final int result;
    final int errorCode;
    try {
      result = bindings.rename(fromPointer, toPointer);
      errorCode = result == 0 ? 0 : bindings.readErrno();
    } finally {
      bindings.freePointer(fromPointer.cast<Void>());
      bindings.freePointer(toPointer.cast<Void>());
    }
    if (result != 0) {
      throw _posixException(
        'rename',
        toPath,
        errorCode,
        formatFailureMessage: formatFailureMessage,
      );
    }
  }

  /// Attempts a non-blocking `flock(LOCK_EX | LOCK_NB)` on [descriptor].
  bool _posixTryFlockExclusive(int descriptor, String lockFilePath) {
    final bindings = _PosixLockBindings.instance;
    while (true) {
      if (bindings.flock(descriptor, _posixLockEx | _posixLockNb) == 0) {
        return true;
      }
      final errorCode = bindings.readErrno();
      if (errorCode == _posixEintr) {
        continue;
      }
      if (errorCode == _posixEagain) {
        return false;
      }
      throw _posixException('flock', lockFilePath, errorCode);
    }
  }

  /// Removes [tempPath] via POSIX `unlink` while ignoring missing-file errors.
  static void _posixUnlinkQuietly(String tempPath) {
    final bindings = _PosixLockBindings.instance;
    final pointer = bindings.allocateUtf8(tempPath);
    try {
      bindings.unlink(pointer);
    } finally {
      bindings.freePointer(pointer.cast<Void>());
    }
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
    final bindings = _PosixLockBindings.instance;
    final bufferPointer = bindings.allocateBytes(bytes);
    try {
      var writtenTotal = 0;
      while (writtenTotal < bytes.length) {
        final chunkAddress = bufferPointer.address + writtenTotal;
        final chunkPointer = Pointer<Uint8>.fromAddress(chunkAddress);
        final writtenNow = bindings.write(
          descriptor,
          chunkPointer,
          bytes.length - writtenTotal,
        );
        if (writtenNow > 0) {
          writtenTotal += writtenNow;
          continue;
        }
        final errorCode = bindings.readErrno();
        if (errorCode != _posixEintr) {
          throw _posixException(
            'write',
            path,
            errorCode,
            formatFailureMessage: formatFailureMessage,
          );
        }
      }
    } finally {
      bindings.freePointer(bufferPointer.cast<Void>());
    }
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
      trailingSegments.add(_extractBaseName(cursor));
      cursor = parentPath;
      final resolvedDir = _safeResolveDirectoryLinks(cursor);
      if (resolvedDir != null) {
        final cleanAncestor = _trimTrailingSeparators(resolvedDir);
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

  /// Strips trailing `/` and `\` characters while preserving POSIX `/` and Windows drive roots.
  static String _trimTrailingSeparators(String path) {
    final minLength = _windowsDrivePattern.hasMatch(path) ? 3 : 1;
    var end = path.length;
    while (end > minLength &&
        (path.codeUnitAt(end - 1) == 0x2F ||
            path.codeUnitAt(end - 1) == 0x5C)) {
      end--;
    }
    return path.substring(0, end);
  }

  /// Opens or creates [path] via Win32 `CreateFileW` and throws via [createException] on invalid handle.
  int _win32CreateFile(
    String path, {
    required int desiredAccess,
    required int shareMode,
    required int creationDisposition,
    String Function(String details)? formatFailureMessage,
  }) {
    final bindings = _Win32LockBindings.instance;
    final pathPointer = bindings.allocateUtf16(path);
    final int handle;
    final int errorCode;
    try {
      handle = bindings.createFileW(
        pathPointer,
        desiredAccess,
        shareMode,
        nullptr,
        creationDisposition,
        _win32FileAttributeNormal,
        0,
      );
      errorCode = (handle == -1 || handle == 0) ? bindings.getLastError() : 0;
    } finally {
      bindings.freePointer(pathPointer.cast<Void>());
    }
    if (handle == -1 || handle == 0) {
      final details = 'CreateFileW failed (Win32 error $errorCode)';
      final cause = FileSystemException(
        details,
        path,
        OSError('Win32 error $errorCode', errorCode),
      );
      final message = formatFailureMessage != null
          ? formatFailureMessage(details)
          : '$details: $path';
      throw createException(message, cause: cause);
    }
    return handle;
  }

  /// Attempts a non-blocking `LockFileEx` over bytes `0..1` on [handle].
  bool _win32TryLockExclusive(
    int handle,
    Pointer<Void> overlappedPointer,
    String lockFilePath,
  ) {
    final bindings = _Win32LockBindings.instance;
    final result = bindings.lockFileEx(
      handle,
      _win32LockExclusiveImmediate,
      0,
      1,
      0,
      overlappedPointer,
    );
    if (result != 0) {
      return true;
    }
    final errorCode = bindings.getLastError();
    if (errorCode == _win32ErrorLockViolation) {
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

  /// Attempts Win32 `MoveFileExW` replacement, returning `null` on success or `GetLastError()` on failure.
  static int? _win32TryMoveReplace(String fromPath, String toPath) {
    final bindings = _Win32LockBindings.instance;
    final fromPointer = bindings.allocateUtf16(fromPath);
    final toPointer = bindings.allocateUtf16(toPath);
    try {
      final succeeded = bindings.moveFileExW(
        fromPointer,
        toPointer,
        _win32MoveReplaceWriteThrough,
      );
      if (succeeded != 0) {
        return null;
      }
      return bindings.getLastError();
    } finally {
      bindings.freePointer(fromPointer.cast<Void>());
      bindings.freePointer(toPointer.cast<Void>());
    }
  }

  /// Deletes [tempPath] via Win32 `DeleteFileW`, ignoring errors on missing files.
  static void _win32UnlinkQuietly(String tempPath) {
    final bindings = _Win32LockBindings.instance;
    final pointer = bindings.allocateUtf16(tempPath);
    try {
      bindings.deleteFileW(pointer);
    } finally {
      bindings.freePointer(pointer.cast<Void>());
    }
  }

  /// Unlocks bytes `0..1`, closes [handle], and frees [overlappedPointer] without deleting the lock file.
  static void _win32UnlockAndClose(
    int handle,
    Pointer<Void> overlappedPointer,
  ) {
    final bindings = _Win32LockBindings.instance;
    bindings.unlockFileEx(handle, 0, 1, 0, overlappedPointer);
    bindings.closeHandle(handle);
    bindings.localFree(overlappedPointer);
  }

  /// Writes all [bytes] and calls `FlushFileBuffers` on Win32 [handle].
  void _win32WriteAndFlush(
    int handle,
    List<int> bytes,
    String tempPath, {
    String Function(String details)? formatFailureMessage,
  }) {
    if (bytes.isNotEmpty) {
      _win32WriteBuffer(
        handle,
        bytes,
        tempPath,
        formatFailureMessage: formatFailureMessage,
      );
    }
    final bindings = _Win32LockBindings.instance;
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

  /// Writes non-empty [bytes] to Win32 [handle] in a loop until complete.
  void _win32WriteBuffer(
    int handle,
    List<int> bytes,
    String tempPath, {
    String Function(String details)? formatFailureMessage,
  }) {
    final bindings = _Win32LockBindings.instance;
    final bufferPointer = bindings.allocateBytes(bytes);
    final writtenPointer = bindings
        .localAlloc(_win32LmemZeroInit, 4)
        .cast<Uint32>();
    if (writtenPointer.address == 0) {
      bindings.freePointer(bufferPointer.cast<Void>());
      throw const OutOfMemoryError();
    }
    try {
      var writtenTotal = 0;
      while (writtenTotal < bytes.length) {
        final chunkPointer = Pointer<Uint8>.fromAddress(
          bufferPointer.address + writtenTotal,
        );
        final result = bindings.writeFile(
          handle,
          chunkPointer,
          bytes.length - writtenTotal,
          writtenPointer,
          nullptr,
        );
        if (result == 0) {
          final code = bindings.getLastError();
          final details = 'WriteFile failed (Win32 error $code)';
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
        writtenTotal += writtenPointer.value;
      }
    } finally {
      bindings.freePointer(writtenPointer.cast<Void>());
      bindings.freePointer(bufferPointer.cast<Void>());
    }
  }

  /// Writes [bytes] to an exclusive `0600` `.tmp.<32hex>` file, flushes it, and renames over [targetPath] on POSIX.
  void _writeAtomicallyPosix(
    String targetPath,
    List<int> bytes, {
    String Function(String details)? formatFailureMessage,
  }) {
    final parentDirectory = File(targetPath).parent;
    parentDirectory.createSync(recursive: true);
    final cleanParent = _trimTrailingSeparators(parentDirectory.path);
    final baseName = _extractBaseName(targetPath);
    final prefix = cleanParent == '/' ? '' : cleanParent;
    final tempPath = '$prefix/.$baseName.tmp.${_generateTempHexSuffix()}';

    final bindings = _PosixLockBindings.instance;
    final openFlags =
        _posixOWronly |
        _posixOCreat |
        _posixOExcl |
        _posixOCloexec |
        bindings.noFollowFlag;
    final descriptor = _posixOpen(
      tempPath,
      openFlags,
      _posixFileMode0600,
      formatFailureMessage: formatFailureMessage,
    );
    var descriptorClosed = false;
    try {
      _posixFchmodBestEffort(
        descriptor,
        _posixFileMode0600,
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
      _posixFsyncDirectoryBestEffort(parentDirectory.path);
    } on Object {
      if (!descriptorClosed) {
        bindings.close(descriptor);
      }
      _posixUnlinkQuietly(tempPath);
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
    parentDirectory.createSync(recursive: true);
    final cleanParent = _trimTrailingSeparators(parentDirectory.path);
    final baseName = _extractBaseName(targetPath);
    final separator = cleanParent.endsWith(r'\') ? '' : r'\';
    final tempPath =
        '$cleanParent$separator.$baseName.tmp.${_generateTempHexSuffix()}';

    final handle = _win32CreateFile(
      tempPath,
      desiredAccess: _win32GenericWrite,
      shareMode: 0,
      creationDisposition: _win32CreateNew,
      formatFailureMessage: formatFailureMessage,
    );
    var handleClosed = false;
    try {
      _win32WriteAndFlush(
        handle,
        bytes,
        tempPath,
        formatFailureMessage: formatFailureMessage,
      );
      handleClosed = true;
      _Win32LockBindings.instance.closeHandle(handle);
    } on Object {
      if (!handleClosed) {
        _Win32LockBindings.instance.closeHandle(handle);
      }
      _win32UnlinkQuietly(tempPath);
      rethrow;
    }

    await replaceTargetWithSharingRetry(
      performMove: () => _win32TryMoveReplace(tempPath, targetPath),
      cleanupTemp: () => _win32UnlinkQuietly(tempPath),
      targetPath: targetPath,
      formatFailureMessage: formatFailureMessage,
    );
  }
}

/// Lazy FFI bindings to POSIX `libc` symbols on Linux and Android (`DynamicLibrary.process()`).
class _PosixLockBindings {
  /// Constructs [_PosixLockBindings] with bound `libc` function pointers.
  const _PosixLockBindings._({
    required this.chmod,
    required this.close,
    required this.errnoPointer,
    required this.fchmod,
    required this.flock,
    required this.free,
    required this.fsync,
    required this.getuid,
    required this.malloc,
    required this.mkdir,
    required this.noFollowFlag,
    required this.open,
    required this.rename,
    required this.unlink,
    required this.write,
  });

  /// Resolves `libc` process symbols on first POSIX lock or atomic file operation.
  factory _PosixLockBindings._load() {
    final libc = DynamicLibrary.process();
    return _PosixLockBindings._(
      chmod: libc
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Uint32),
            int Function(Pointer<Uint8>, int)
          >('chmod'),
      close: libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'close',
      ),
      errnoPointer: libc
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            Platform.isAndroid ? '__errno' : '__errno_location',
          ),
      fchmod: libc
          .lookupFunction<
            Int32 Function(Int32, Uint32),
            int Function(int, int)
          >('fchmod'),
      flock: libc
          .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'flock',
          ),
      free: libc
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('free'),
      fsync: libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'fsync',
      ),
      getuid: libc.lookupFunction<Uint32 Function(), int Function()>('getuid'),
      malloc: libc
          .lookupFunction<
            Pointer<Void> Function(Size),
            Pointer<Void> Function(int)
          >('malloc'),
      mkdir: libc
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Uint32),
            int Function(Pointer<Uint8>, int)
          >('mkdir'),
      noFollowFlag: _resolveNoFollowFlag(),
      open: libc
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Int32, VarArgs<(Uint32,)>),
            int Function(Pointer<Uint8>, int, int)
          >('open'),
      rename: libc
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Pointer<Uint8>),
            int Function(Pointer<Uint8>, Pointer<Uint8>)
          >('rename'),
      unlink: libc
          .lookupFunction<
            Int32 Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)
          >('unlink'),
      write: libc
          .lookupFunction<
            IntPtr Function(Int32, Pointer<Uint8>, Size),
            int Function(int, Pointer<Uint8>, int)
          >('write'),
    );
  }

  /// Singleton POSIX bindings instance.
  static final _PosixLockBindings instance = _PosixLockBindings._load();

  /// POSIX `chmod(const char *, mode_t)` function.
  final int Function(Pointer<Uint8>, int) chmod;

  /// POSIX `close(int)` function.
  final int Function(int) close;

  /// Thread-local POSIX `errno` address accessor.
  final Pointer<Int32> Function() errnoPointer;

  /// POSIX `fchmod(int, mode_t)` function.
  final int Function(int, int) fchmod;

  /// POSIX `flock(int, int)` function.
  final int Function(int, int) flock;

  /// Native `free(void *)` function.
  final void Function(Pointer<Void>) free;

  /// POSIX `fsync(int)` function.
  final int Function(int) fsync;

  /// POSIX `getuid(void)` function.
  final int Function() getuid;

  /// Native `malloc(size_t)` function.
  final Pointer<Void> Function(int) malloc;

  /// POSIX `mkdir(const char *, mode_t)` function.
  final int Function(Pointer<Uint8>, int) mkdir;

  /// Architecture-specific `O_NOFOLLOW` bitmask (`0x8000` on ARM/ARM64, `0x20000` on x86/x64).
  final int noFollowFlag;

  /// Variadic POSIX `open(const char *, int, mode_t)` function.
  final int Function(Pointer<Uint8>, int, int) open;

  /// POSIX `rename(const char *, const char *)` function.
  final int Function(Pointer<Uint8>, Pointer<Uint8>) rename;

  /// POSIX `unlink(const char *)` function.
  final int Function(Pointer<Uint8>) unlink;

  /// POSIX `write(int, const void *, size_t)` function.
  final int Function(int, Pointer<Uint8>, int) write;

  /// Allocates a native byte buffer initialized with [bytes].
  Pointer<Uint8> allocateBytes(List<int> bytes) {
    final pointer = malloc(bytes.isEmpty ? 1 : bytes.length).cast<Uint8>();
    if (pointer.address == 0) {
      throw const OutOfMemoryError();
    }
    if (bytes.isNotEmpty) {
      pointer.asTypedList(bytes.length).setRange(0, bytes.length, bytes);
    }
    return pointer;
  }

  /// Allocates a null-terminated UTF-8 C string in native heap memory.
  Pointer<Uint8> allocateUtf8(String value) {
    final encoded = utf8.encode(value);
    final pointer = malloc(encoded.length + 1).cast<Uint8>();
    if (pointer.address == 0) {
      throw const OutOfMemoryError();
    }
    pointer.asTypedList(encoded.length + 1)
      ..setRange(0, encoded.length, encoded)
      ..[encoded.length] = 0;
    return pointer;
  }

  /// Frees native heap [pointer] allocated by [allocateUtf8] or [allocateBytes].
  void freePointer(Pointer<Void> pointer) => free(pointer);

  /// Reads the thread-local POSIX `errno` value.
  int readErrno() => errnoPointer().value;

  /// Resolves the Linux/Android ABI `O_NOFOLLOW` constant.
  static int _resolveNoFollowFlag() {
    return switch (Abi.current()) {
      Abi.linuxArm64 ||
      Abi.androidArm64 ||
      Abi.linuxArm ||
      Abi.androidArm => 0x8000,
      Abi.linuxX64 ||
      Abi.androidX64 ||
      Abi.linuxIA32 ||
      Abi.androidIA32 ||
      Abi.linuxRiscv64 ||
      Abi.androidRiscv64 => 0x20000,
      _ => 0,
    };
  }
}

/// Lazy FFI bindings to Win32 `kernel32.dll` symbols on Windows.
class _Win32LockBindings {
  /// Constructs [_Win32LockBindings] with bound `kernel32.dll` function pointers.
  const _Win32LockBindings._({
    required this.closeHandle,
    required this.createFileW,
    required this.deleteFileW,
    required this.flushFileBuffers,
    required this.getLastError,
    required this.localAlloc,
    required this.localFree,
    required this.lockFileEx,
    required this.moveFileExW,
    required this.unlockFileEx,
    required this.writeFile,
  });

  /// Opens `kernel32.dll` and binds Win32 file/lock symbols on Windows.
  factory _Win32LockBindings._load() {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    return _Win32LockBindings._(
      closeHandle: kernel32
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'CloseHandle',
          ),
      createFileW: kernel32
          .lookupFunction<
            IntPtr Function(
              Pointer<Uint16>,
              Uint32,
              Uint32,
              Pointer<Void>,
              Uint32,
              Uint32,
              IntPtr,
            ),
            int Function(
              Pointer<Uint16>,
              int,
              int,
              Pointer<Void>,
              int,
              int,
              int,
            )
          >('CreateFileW'),
      deleteFileW: kernel32
          .lookupFunction<
            Int32 Function(Pointer<Uint16>),
            int Function(Pointer<Uint16>)
          >('DeleteFileW'),
      flushFileBuffers: kernel32
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'FlushFileBuffers',
          ),
      getLastError: kernel32.lookupFunction<Uint32 Function(), int Function()>(
        'GetLastError',
      ),
      localAlloc: kernel32
          .lookupFunction<
            Pointer<Void> Function(Uint32, Size),
            Pointer<Void> Function(int, int)
          >('LocalAlloc'),
      localFree: kernel32
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>)
          >('LocalFree'),
      lockFileEx: kernel32
          .lookupFunction<
            Int32 Function(
              IntPtr,
              Uint32,
              Uint32,
              Uint32,
              Uint32,
              Pointer<Void>,
            ),
            int Function(int, int, int, int, int, Pointer<Void>)
          >('LockFileEx'),
      moveFileExW: kernel32
          .lookupFunction<
            Int32 Function(Pointer<Uint16>, Pointer<Uint16>, Uint32),
            int Function(Pointer<Uint16>, Pointer<Uint16>, int)
          >('MoveFileExW'),
      unlockFileEx: kernel32
          .lookupFunction<
            Int32 Function(IntPtr, Uint32, Uint32, Uint32, Pointer<Void>),
            int Function(int, int, int, int, Pointer<Void>)
          >('UnlockFileEx'),
      writeFile: kernel32
          .lookupFunction<
            Int32 Function(
              IntPtr,
              Pointer<Uint8>,
              Uint32,
              Pointer<Uint32>,
              Pointer<Void>,
            ),
            int Function(
              int,
              Pointer<Uint8>,
              int,
              Pointer<Uint32>,
              Pointer<Void>,
            )
          >('WriteFile'),
    );
  }

  /// Singleton Win32 bindings instance.
  static final _Win32LockBindings instance = _Win32LockBindings._load();

  /// Win32 `CloseHandle(HANDLE)` function.
  final int Function(int) closeHandle;

  /// Win32 `CreateFileW` function.
  final int Function(Pointer<Uint16>, int, int, Pointer<Void>, int, int, int)
  createFileW;

  /// Win32 `DeleteFileW(LPCWSTR)` function.
  final int Function(Pointer<Uint16>) deleteFileW;

  /// Win32 `FlushFileBuffers(HANDLE)` function.
  final int Function(int) flushFileBuffers;

  /// Win32 `GetLastError(void)` function.
  final int Function() getLastError;

  /// Win32 `LocalAlloc(UINT, SIZE_T)` function.
  final Pointer<Void> Function(int, int) localAlloc;

  /// Win32 `LocalFree(HLOCAL)` function.
  final Pointer<Void> Function(Pointer<Void>) localFree;

  /// Win32 `LockFileEx` function.
  final int Function(int, int, int, int, int, Pointer<Void>) lockFileEx;

  /// Win32 `MoveFileExW` function.
  final int Function(Pointer<Uint16>, Pointer<Uint16>, int) moveFileExW;

  /// Win32 `UnlockFileEx` function.
  final int Function(int, int, int, int, Pointer<Void>) unlockFileEx;

  /// Win32 `WriteFile` function.
  final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
  writeFile;

  /// Allocates a native byte buffer initialized with [bytes].
  Pointer<Uint8> allocateBytes(List<int> bytes) {
    final pointer = localAlloc(
      0x0040,
      bytes.isEmpty ? 1 : bytes.length,
    ).cast<Uint8>();
    if (pointer.address == 0) {
      throw const OutOfMemoryError();
    }
    if (bytes.isNotEmpty) {
      pointer.asTypedList(bytes.length).setRange(0, bytes.length, bytes);
    }
    return pointer;
  }

  /// Allocates a null-terminated UTF-16LE wide string (`LPCWSTR`) in Win32 heap memory.
  Pointer<Uint16> allocateUtf16(String value) {
    final codeUnits = value.codeUnits;
    final pointer = localAlloc(
      0x0040,
      (codeUnits.length + 1) * 2,
    ).cast<Uint16>();
    if (pointer.address == 0) {
      throw const OutOfMemoryError();
    }
    pointer.asTypedList(codeUnits.length + 1)
      ..setRange(0, codeUnits.length, codeUnits)
      ..[codeUnits.length] = 0;
    return pointer;
  }

  /// Frees Win32 heap [pointer] allocated via [localAlloc].
  void freePointer(Pointer<Void> pointer) {
    localFree(pointer);
  }
}
