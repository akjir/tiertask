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
import 'dart:ffi';
import 'dart:io';

import '../services/app_logger.dart';

/// Lazy FFI bindings and low-level syscall helpers for POSIX `libc` symbols on Linux and Android.
class PosixLockBindings {
  /// Constructs [PosixLockBindings] with bound `libc` function pointers.
  const PosixLockBindings._({
    required this.close,
    required this.directoryFlag,
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
  factory PosixLockBindings._load() {
    final libc = DynamicLibrary.process();
    return PosixLockBindings._(
      close: libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'close',
        isLeaf: true,
      ),
      directoryFlag: _resolveDirectoryFlag(),
      errnoPointer: libc
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            Platform.isAndroid ? '__errno' : '__errno_location',
            isLeaf: true,
          ),
      fchmod: libc
          .lookupFunction<
            Int32 Function(Int32, Uint32),
            int Function(int, int)
          >('fchmod', isLeaf: true),
      flock: libc
          .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'flock',
            isLeaf: true,
          ),
      free: libc
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('free', isLeaf: true),
      fsync: libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'fsync',
      ),
      getuid: libc.lookupFunction<Uint32 Function(), int Function()>(
        'getuid',
        isLeaf: true,
      ),
      malloc: libc
          .lookupFunction<
            Pointer<Void> Function(Size),
            Pointer<Void> Function(int)
          >('malloc', isLeaf: true),
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
          >('unlink', isLeaf: true),
      write: libc
          .lookupFunction<
            IntPtr Function(Int32, Pointer<Uint8>, Size),
            int Function(int, Pointer<Uint8>, int)
          >('write'),
    );
  }

  /// Owner-only directory mode (`0700`).
  static const int dirMode0700 = 0x1C0;

  /// POSIX `EAGAIN` / `EWOULDBLOCK` error code (`11`).
  static const int eagain = 11;

  /// POSIX `EEXIST` error code (`17`).
  static const int eexist = 17;

  /// POSIX `EINTR` error code (`4`).
  static const int eintr = 4;

  /// POSIX `EINVAL` error code (`22`).
  static const int einval = 22;

  /// POSIX `EIO` error code (`5`).
  static const int eio = 5;

  /// POSIX `ENOENT` error code (`2`).
  static const int enoent = 2;

  /// POSIX `ENOSYS` error code (`38`).
  static const int enosys = 38;

  /// POSIX `EOPNOTSUPP` error code (`95`).
  static const int eopnotsupp = 95;

  /// POSIX `EPERM` error code (`1`).
  static const int eperm = 1;

  /// Owner-only regular file mode (`0600`).
  static const int fileMode0600 = 0x180;

  /// Singleton POSIX bindings instance.
  static final PosixLockBindings instance = PosixLockBindings._load();

  /// POSIX `LOCK_EX` exclusive lock bitmask (`2`).
  static const int lockEx = 2;

  /// POSIX `LOCK_NB` non-blocking lock bitmask (`4`).
  static const int lockNb = 4;

  /// POSIX `LOCK_UN` unlock bitmask (`8`).
  static const int lockUn = 8;

  /// POSIX `O_CLOEXEC` flag (`0x80000`).
  static const int oCloexec = 0x80000;

  /// POSIX `O_CREAT` flag (`0x0040`).
  static const int oCreat = 0x0040;

  /// POSIX `O_EXCL` flag (`0x0080`).
  static const int oExcl = 0x0080;

  /// POSIX `O_NONBLOCK` flag (`0x0800`).
  static const int oNonblock = 0x0800;

  /// POSIX `O_RDONLY` flag (`0x0000`).
  static const int oRdonly = 0x0000;

  /// POSIX `O_RDWR` flag (`0x0002`).
  static const int oRdwr = 0x0002;

  /// POSIX `O_WRONLY` flag (`0x0001`).
  static const int oWronly = 0x0001;

  /// POSIX `close(int)` function.
  final int Function(int) close;

  /// Architecture-specific `O_DIRECTORY` bitmask (`0x4000` on ARM/ARM64, `0x10000` on x86/x64/RISC-V).
  final int directoryFlag;

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

  /// Allocates a null-terminated UTF-8 C string in native heap memory, rejecting embedded NUL (`\u0000`).
  Pointer<Uint8> allocateUtf8(String value) {
    if (value.contains('\u0000')) {
      throw ArgumentError.value(
        '<redacted>',
        'value',
        'Native POSIX path must not contain embedded NUL characters.',
      );
    }
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

  /// Applies POSIX `fchmod` [mode] to [path] via a non-symlink-following descriptor on Linux and Android,
  /// retrying `EINTR` and ignoring non-POSIX, symlink, or inaccessible path errors.
  static void applyChmodBestEffort(String path, int mode) {
    if (!Platform.isLinux && !Platform.isAndroid) {
      return;
    }
    final bindings = instance;
    final openFlags = oRdonly | oNonblock | oCloexec | bindings.noFollowFlag;
    final outcome = bindings.openRaw(path, openFlags, 0);
    if (outcome.descriptor < 0) {
      return;
    }
    try {
      while (true) {
        if (bindings.fchmod(outcome.descriptor, mode) == 0) {
          return;
        }
        final errorCode = bindings.readErrno();
        if (errorCode == eintr) {
          continue;
        }
        if (isTolerableFchmodErrno(errorCode)) {
          logFchmodSkipped(errorCode);
        }
        return;
      }
    } finally {
      bindings.close(outcome.descriptor);
    }
  }

  /// Frees native heap [pointer] allocated by [allocateUtf8] or [allocateBytes].
  void freePointer(Pointer<Void> pointer) => free(pointer);

  /// Flushes [descriptor] to storage via `fsync`, retrying `EINTR` and returning `0` on success or captured `errno`.
  int fsyncDescriptor(int descriptor) {
    while (true) {
      if (fsync(descriptor) == 0) {
        return 0;
      }
      final errorCode = readErrno();
      if (errorCode != eintr) {
        return errorCode;
      }
    }
  }

  /// Flushes the directory metadata of [directoryPath] when supported by the underlying POSIX filesystem.
  void fsyncDirectoryBestEffort(String directoryPath) {
    final pathPointer = allocateUtf8(directoryPath);
    final int descriptor;
    try {
      descriptor = open(pathPointer, oRdonly | oCloexec, 0);
    } finally {
      freePointer(pathPointer.cast<Void>());
    }
    if (descriptor < 0) {
      return;
    }
    try {
      while (fsync(descriptor) != 0) {
        if (readErrno() != eintr) {
          break;
        }
      }
    } finally {
      close(descriptor);
    }
  }

  /// Returns `true` when POSIX `fchmod` [errorCode] indicates a non-POSIX filesystem (`EPERM`, `EINVAL`, `ENOSYS`, `EOPNOTSUPP`).
  static bool isTolerableFchmodErrno(int errorCode) =>
      errorCode == eperm ||
      errorCode == einval ||
      errorCode == enosys ||
      errorCode == eopnotsupp;

  /// Emits a debug diagnostic event when `fchmod` is unsupported by the filesystem.
  static void logFchmodSkipped(int errorCode) {
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

  /// Invokes POSIX `mkdir` on [path] with [mode], returning `(result, errorCode)`.
  ({int result, int errorCode}) mkdirRaw(String path, int mode) {
    final pointer = allocateUtf8(path);
    try {
      final result = mkdir(pointer, mode);
      final errorCode = result == 0 ? 0 : readErrno();
      return (result: result, errorCode: errorCode);
    } finally {
      freePointer(pointer.cast<Void>());
    }
  }

  /// Opens [path] with POSIX `open(flags, mode)`, retrying on `EINTR` and returning the descriptor or captured `errno`.
  ({int descriptor, int errorCode}) openRaw(String path, int flags, int mode) {
    final pointer = allocateUtf8(path);
    try {
      while (true) {
        final descriptor = open(pointer, flags, mode);
        if (descriptor >= 0) {
          return (descriptor: descriptor, errorCode: 0);
        }
        final errorCode = readErrno();
        if (errorCode != eintr) {
          return (descriptor: -1, errorCode: errorCode);
        }
      }
    } finally {
      freePointer(pointer.cast<Void>());
    }
  }

  /// Reads the thread-local POSIX `errno` value.
  int readErrno() => errnoPointer().value;

  /// Releases the POSIX `flock` on [descriptor] and closes it without unlinking the lock file.
  static void releaseAndClose(int descriptor) {
    final bindings = instance;
    bindings.flock(descriptor, lockUn);
    bindings.close(descriptor);
  }

  /// Invokes POSIX `rename(fromPath, toPath)` with OOM-safe dual-pointer allocation, returning `(result, errorCode)`.
  ({int result, int errorCode}) renameRaw(String fromPath, String toPath) {
    Pointer<Uint8>? fromPointer;
    Pointer<Uint8>? toPointer;
    try {
      fromPointer = allocateUtf8(fromPath);
      toPointer = allocateUtf8(toPath);
      final result = rename(fromPointer, toPointer);
      final errorCode = result == 0 ? 0 : readErrno();
      return (result: result, errorCode: errorCode);
    } finally {
      if (fromPointer != null) {
        freePointer(fromPointer.cast<Void>());
      }
      if (toPointer != null) {
        freePointer(toPointer.cast<Void>());
      }
    }
  }

  /// Attempts non-blocking `flock(LOCK_EX | LOCK_NB)` on [descriptor], returning `null` when contended (`EAGAIN`), `0` on success, or hard `errno`.
  int? tryFlockExclusiveRaw(int descriptor) {
    while (true) {
      if (flock(descriptor, lockEx | lockNb) == 0) {
        return 0;
      }
      final errorCode = readErrno();
      if (errorCode == eintr) {
        continue;
      }
      if (errorCode == eagain) {
        return null;
      }
      return errorCode;
    }
  }

  /// Removes [tempPath] via POSIX `unlink` while ignoring missing-file errors.
  static void unlinkQuietly(String tempPath) {
    final bindings = instance;
    final pointer = bindings.allocateUtf8(tempPath);
    try {
      bindings.unlink(pointer);
    } finally {
      bindings.freePointer(pointer.cast<Void>());
    }
  }

  /// Runs [writeLoop] over a native byte buffer copy of [bytes], freeing the buffer on completion or error.
  void withByteBuffer(
    List<int> bytes,
    void Function(int Function(int offset, int remaining) performWrite)
    writeLoop,
    int descriptor,
  ) {
    final bufferPointer = allocateBytes(bytes);
    try {
      writeLoop((offset, remaining) {
        final chunkPointer = Pointer<Uint8>.fromAddress(
          bufferPointer.address + offset,
        );
        return write(descriptor, chunkPointer, remaining);
      });
    } finally {
      freePointer(bufferPointer.cast<Void>());
    }
  }

  /// Resolves the Linux/Android ABI `O_DIRECTORY` constant (`0x4000` on ARM/ARM64, `0x10000` on x86/x64/RISC-V).
  static int _resolveDirectoryFlag() {
    return switch (Abi.current()) {
      Abi.linuxArm64 ||
      Abi.androidArm64 ||
      Abi.linuxArm ||
      Abi.androidArm => 0x4000,
      Abi.linuxX64 ||
      Abi.androidX64 ||
      Abi.linuxIA32 ||
      Abi.androidIA32 ||
      Abi.linuxRiscv64 ||
      Abi.androidRiscv64 => 0x10000,
      _ => 0,
    };
  }

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
