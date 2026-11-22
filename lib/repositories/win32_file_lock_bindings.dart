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

import 'dart:ffi';

/// Encapsulates an open Win32 file handle and its zero-initialized `OVERLAPPED` structure for lock operations.
class Win32LockHandle {
  /// Creates a [Win32LockHandle] owning [handle] and [overlappedPointer].
  const Win32LockHandle({
    required this.handle,
    required this.overlappedPointer,
  });

  /// Win32 file `HANDLE`.
  final int handle;

  /// Zero-initialized `OVERLAPPED` structure pointer allocated via `LocalAlloc`.
  final Pointer<Void> overlappedPointer;

  /// Closes [handle] and frees [overlappedPointer] without calling `UnlockFileEx`.
  void closeWithoutUnlock() {
    final bindings = Win32LockBindings.instance;
    bindings.closeHandle(handle);
    bindings.localFree(overlappedPointer);
  }

  /// Attempts non-blocking `LockFileEx` over bytes `0..1`, returning `0` on success, `null` when contended, or Win32 error code on hard failure.
  int? tryLockExclusiveRaw() {
    final bindings = Win32LockBindings.instance;
    final result = bindings.lockFileEx(
      handle,
      Win32LockBindings.lockExclusiveImmediate,
      0,
      1,
      0,
      overlappedPointer,
    );
    if (result != 0) {
      return 0;
    }
    final errorCode = bindings.getLastError();
    if (errorCode == Win32LockBindings.errorLockViolation) {
      return null;
    }
    return errorCode;
  }

  /// Unlocks bytes `0..1`, closes [handle], and frees [overlappedPointer] without deleting the lock file.
  void unlockAndClose() {
    final bindings = Win32LockBindings.instance;
    bindings.unlockFileEx(handle, 0, 1, 0, overlappedPointer);
    bindings.closeHandle(handle);
    bindings.localFree(overlappedPointer);
  }
}

/// Lazy FFI bindings and low-level syscall helpers for Win32 `kernel32.dll` symbols on Windows.
class Win32LockBindings {
  /// Constructs [Win32LockBindings] with bound `kernel32.dll` function pointers.
  const Win32LockBindings._({
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
  factory Win32LockBindings._load() {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    return Win32LockBindings._(
      closeHandle: kernel32
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'CloseHandle',
            isLeaf: true,
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
        isLeaf: true,
      ),
      localAlloc: kernel32
          .lookupFunction<
            Pointer<Void> Function(Uint32, Size),
            Pointer<Void> Function(int, int)
          >('LocalAlloc', isLeaf: true),
      localFree: kernel32
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>)
          >('LocalFree', isLeaf: true),
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
          >('LockFileEx', isLeaf: true),
      moveFileExW: kernel32
          .lookupFunction<
            Int32 Function(Pointer<Uint16>, Pointer<Uint16>, Uint32),
            int Function(Pointer<Uint16>, Pointer<Uint16>, int)
          >('MoveFileExW'),
      unlockFileEx: kernel32
          .lookupFunction<
            Int32 Function(IntPtr, Uint32, Uint32, Uint32, Pointer<Void>),
            int Function(int, int, int, int, Pointer<Void>)
          >('UnlockFileEx', isLeaf: true),
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

  /// Win32 `CREATE_NEW` creation disposition (`1`).
  static const int createNew = 1;

  /// Win32 `ERROR_ACCESS_DENIED` error code (`5`).
  static const int errorAccessDenied = 5;

  /// Win32 `ERROR_LOCK_VIOLATION` error code (`33`).
  static const int errorLockViolation = 33;

  /// Win32 `ERROR_SHARING_VIOLATION` error code (`32`).
  static const int errorSharingViolation = 32;

  /// Win32 `FILE_ATTRIBUTE_NORMAL` flag (`0x80`).
  static const int fileAttributeNormal = 0x00000080;

  /// Win32 `FILE_FLAG_OPEN_REPARSE_POINT` flag (`0x00200000`).
  static const int fileFlagOpenReparsePoint = 0x00200000;

  /// Win32 `FILE_SHARE_READ | FILE_SHARE_WRITE` sharing mode (`0x03`).
  static const int fileShareReadWrite = 0x00000003;

  /// Win32 `GENERIC_READ | GENERIC_WRITE` access mask (`0xC0000000`).
  static const int genericReadWrite = 0xC0000000;

  /// Win32 `GENERIC_WRITE` access mask (`0x40000000`).
  static const int genericWrite = 0x40000000;

  /// Singleton Win32 bindings instance.
  static final Win32LockBindings instance = Win32LockBindings._load();

  /// Win32 `LMEM_ZEROINIT` allocation flag (`0x0040`).
  static const int lmemZeroInit = 0x0040;

  /// Win32 `LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY` flag (`0x03`).
  static const int lockExclusiveImmediate = 0x00000003;

  /// Win32 `MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH` flag (`0x09`).
  static const int moveReplaceWriteThrough = 0x00000009;

  /// Win32 `OPEN_ALWAYS` creation disposition (`4`).
  static const int openAlways = 4;

  /// Byte size allocated for a Win32 `OVERLAPPED` structure (`32`).
  static const int overlappedByteSize = 32;

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
      lmemZeroInit,
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

  /// Allocates a zero-initialized `OVERLAPPED` structure for [handle], closing [handle] if allocation fails.
  Win32LockHandle allocateLockHandle(int handle) {
    final overlappedPointer = localAlloc(lmemZeroInit, overlappedByteSize);
    if (overlappedPointer.address == 0) {
      closeHandle(handle);
      throw const OutOfMemoryError();
    }
    return Win32LockHandle(
      handle: handle,
      overlappedPointer: overlappedPointer,
    );
  }

  /// Allocates a null-terminated UTF-16LE wide string (`LPCWSTR`) in Win32 heap memory, rejecting embedded NUL (`\u0000`).
  Pointer<Uint16> allocateUtf16(String value) {
    final codeUnits = encodeUtf16NoNul(value);
    final pointer = localAlloc(
      lmemZeroInit,
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

  /// Opens or creates [path] via Win32 `CreateFileW`, returning `(handle, errorCode)`.
  ({int handle, int errorCode}) createFileRaw(
    String path, {
    required int desiredAccess,
    required int shareMode,
    required int creationDisposition,
    int flagsAndAttributes = fileAttributeNormal,
  }) {
    final pathPointer = allocateUtf16(path);
    try {
      final handle = createFileW(
        pathPointer,
        desiredAccess,
        shareMode,
        nullptr,
        creationDisposition,
        flagsAndAttributes,
        0,
      );
      final errorCode = (handle == -1 || handle == 0) ? getLastError() : 0;
      return (handle: handle, errorCode: errorCode);
    } finally {
      freePointer(pathPointer.cast<Void>());
    }
  }

  /// Returns the UTF-16 code units of [value], throwing [ArgumentError] if [value] contains an embedded NUL (`\u0000`).
  static List<int> encodeUtf16NoNul(String value) {
    if (value.contains('\u0000')) {
      throw ArgumentError.value(
        '<redacted>',
        'value',
        'Native Win32 path must not contain embedded NUL characters.',
      );
    }
    return value.codeUnits;
  }

  /// Frees Win32 heap [pointer] allocated via [localAlloc].
  void freePointer(Pointer<Void> pointer) {
    localFree(pointer);
  }

  /// Attempts Win32 `MoveFileExW` replacement, returning `null` on success or `GetLastError()` on failure.
  static int? tryMoveReplace(String fromPath, String toPath) {
    final bindings = instance;
    Pointer<Uint16>? fromPointer;
    Pointer<Uint16>? toPointer;
    try {
      fromPointer = bindings.allocateUtf16(fromPath);
      toPointer = bindings.allocateUtf16(toPath);
      final succeeded = bindings.moveFileExW(
        fromPointer,
        toPointer,
        moveReplaceWriteThrough,
      );
      if (succeeded != 0) {
        return null;
      }
      return bindings.getLastError();
    } finally {
      if (fromPointer != null) {
        bindings.freePointer(fromPointer.cast<Void>());
      }
      if (toPointer != null) {
        bindings.freePointer(toPointer.cast<Void>());
      }
    }
  }

  /// Deletes [tempPath] via Win32 `DeleteFileW`, ignoring errors on missing files.
  static void unlinkQuietly(String tempPath) {
    final bindings = instance;
    final pointer = bindings.allocateUtf16(tempPath);
    try {
      bindings.deleteFileW(pointer);
    } finally {
      bindings.freePointer(pointer.cast<Void>());
    }
  }

  /// Runs [writeLoop] over a native byte buffer copy of [bytes] and `DWORD` written-count output pointer for [handle].
  void withWriteBuffers(
    int handle,
    List<int> bytes,
    void Function(
      ({bool succeeded, int bytesWritten}) Function(int offset, int remaining)
      performWrite,
    )
    writeLoop,
  ) {
    Pointer<Uint8>? bufferPointer;
    Pointer<Uint32>? writtenPointer;
    try {
      bufferPointer = allocateBytes(bytes);
      final rawWritten = localAlloc(lmemZeroInit, 4);
      if (rawWritten.address == 0) {
        throw const OutOfMemoryError();
      }
      writtenPointer = rawWritten.cast<Uint32>();
      final activeBuffer = bufferPointer;
      final activeWritten = writtenPointer;
      writeLoop((offset, remaining) {
        final chunkPointer = Pointer<Uint8>.fromAddress(
          activeBuffer.address + offset,
        );
        final result = writeFile(
          handle,
          chunkPointer,
          remaining,
          activeWritten,
          nullptr,
        );
        return (succeeded: result != 0, bytesWritten: activeWritten.value);
      });
    } finally {
      if (writtenPointer != null) {
        freePointer(writtenPointer.cast<Void>());
      }
      if (bufferPointer != null) {
        freePointer(bufferPointer.cast<Void>());
      }
    }
  }
}
