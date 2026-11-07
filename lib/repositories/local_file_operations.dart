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
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import '../models/webdav_config.dart';
import '../services/app_logger.dart';
import 'local_file_repository.dart';

/// Stateless helper operations for local `.tdf` path validation, `.bak` backup
/// rotation, safe cross-device file moves, and synchronous diagnostic log I/O.
@immutable
class LocalFileOperations {
  /// Private constructor for static filesystem helper methods.
  const LocalFileOperations._();

  /// Maximum numbered `.bak.NNN` suffix checked when creating a backup copy (`999`).
  static const int maxBackupSuffix = 999;

  static final RegExp _pathSeparatorPattern = RegExp(r'[\\/]+');
  static final RegExp _windowsDrivePattern = RegExp(r'^[a-zA-Z]:[\\/]');

  /// Combines [directoryPath] and [fileName] into a normalized local `.tdf` file path.
  static String combineDirectoryAndFileName(
    String directoryPath,
    String fileName,
  ) {
    final cleanDir = trimTrailingSeparators(directoryPath.trim());
    final cleanName = extractFileNameFromPath(fileName);
    if (cleanDir.isEmpty) return cleanName;
    final sep = Platform.pathSeparator;
    return cleanDir == sep ? '$sep$cleanName' : '$cleanDir$sep$cleanName';
  }

  /// Resolves the default filesystem path for `tiertask.log` inside [baseDirectoryPath] or the user data directory.
  static String defaultLogFilePath({String? baseDirectoryPath}) {
    final trimmed = baseDirectoryPath?.trim() ?? '';
    final base = trimmed.isNotEmpty ? trimmed : resolveDefaultDirectoryPath();
    return '${trimTrailingSeparators(base)}${Platform.pathSeparator}${AppLogger.defaultLogFileName}';
  }

  /// Synchronously deletes the diagnostic log file at [path] if it exists.
  static void deleteLogFileSync(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Ignore deletion failures on missing or locked diagnostic files.
    }
  }

  /// Deletes the local `.tdf` file for [repository] if it exists, rejecting directories and symbolic links.
  static void deleteTdf(
    LocalFileRepository repository,
    AppLocalizations messages, {
    required bool inMemory,
  }) {
    final path = repository.resolveFilePath();
    if (inMemory) {
      repository.inMemoryStore?.remove(path);
      return;
    }
    final sourceType = FileSystemEntity.typeSync(path, followLinks: false);
    if (sourceType == FileSystemEntityType.notFound) return;
    if (sourceType == FileSystemEntityType.directory) {
      throw LocalFileException(messages.errorMoveSourceIsDirectory(path));
    }
    if (sourceType == FileSystemEntityType.link) {
      throw LocalFileException(messages.errorMoveSourceIsSymlink(path));
    }
    try {
      File(path).deleteSync();
      AppLogger.info(LogTag.storage, 'deleteTdf deleted $path');
    } on FileSystemException catch (error) {
      throw mapMoveFileSystemException(error, path, messages);
    }
  }

  /// Appends `.tdf` to [rawName] when it does not already end with `.tdf` (case-insensitive).
  static String ensureTdfExtension(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return WebDavConfig.defaultFileName;
    if (trimmed.length > 4 &&
        trimmed.substring(trimmed.length - 4).toLowerCase() == '.tdf') {
      return trimmed;
    }
    return '$trimmed.tdf';
  }

  /// Extracts the parent directory portion from [rawPath], or an empty string when [rawPath] is a bare file name.
  static String extractDirectoryFromPath(String rawPath) {
    final trimmed = trimTrailingSeparators(rawPath.trim());
    if (trimmed.isEmpty) return '';
    final lastSlash = trimmed.lastIndexOf('/');
    final lastBackslash = trimmed.lastIndexOf(r'\');
    final splitIndex = lastSlash > lastBackslash ? lastSlash : lastBackslash;
    if (splitIndex < 0) return '';
    if (splitIndex == 0) return '/';
    if (splitIndex == 2 && _windowsDrivePattern.hasMatch(trimmed)) {
      return trimmed.substring(0, 3);
    }
    return trimmed.substring(0, splitIndex);
  }

  /// Extracts the base file name without a trailing `.tdf` extension from [rawPath].
  static String extractFileBaseName(String rawPath) {
    final fileName = extractFileNameFromPath(rawPath);
    if (fileName.length > 4 &&
        fileName.substring(fileName.length - 4).toLowerCase() == '.tdf') {
      return fileName.substring(0, fileName.length - 4);
    }
    return fileName;
  }

  /// Extracts the trailing file name segment from [rawPath], defaulting to [WebDavConfig.defaultFileName].
  static String extractFileNameFromPath(String rawPath) {
    final parts = rawPath.trim().split(_pathSeparatorPattern);
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].isNotEmpty) return parts[i];
    }
    return WebDavConfig.defaultFileName;
  }

  /// Formats the candidate backup path or URI suffix for [basePath] at [attemptIndex].
  static String formatBackupPath(String basePath, int attemptIndex) =>
      attemptIndex <= 0
      ? '$basePath.bak'
      : '$basePath.bak.${attemptIndex.toString().padLeft(3, '0')}';

  /// Returns `true` if [rawPath] starts with a POSIX root `/` or Windows drive prefix.
  static bool isAbsolutePath(String rawPath) =>
      rawPath.startsWith('/') || _windowsDrivePattern.hasMatch(rawPath);

  /// Returns `true` when [rawName] is a valid single `.tdf` file name or base name without path separators or control characters.
  static bool isValidSingleFileName(String rawName) {
    final trimmed = rawName.trim();
    return trimmed.isNotEmpty &&
        trimmed != '.' &&
        trimmed != '..' &&
        trimmed.toLowerCase() != '.tdf' &&
        !trimmed.contains('/') &&
        !trimmed.contains(r'\') &&
        !_hasControlCharacters(trimmed);
  }

  /// Maps a [FileSystemException] during a `.tdf` file move into a specific localized [LocalFileException].
  static LocalFileException mapMoveFileSystemException(
    FileSystemException error,
    String fallbackPath,
    AppLocalizations messages,
  ) {
    final errorPath = error.path?.trim() ?? '';
    final path = errorPath.isNotEmpty ? error.path! : fallbackPath;
    final text = switch (error.osError?.errorCode) {
      13 || 1 || 5 || 1314 => messages.errorMovePermissionDenied(path),
      30 || 19 => messages.errorMoveReadOnlyFileSystem(path),
      28 || 122 || 112 || 39 => messages.errorMoveDiskFull(path),
      16 || 26 || 32 || 33 => messages.errorMoveFileLocked(path),
      17 || 80 || 183 => messages.errorMoveTargetFileExists(path),
      21 => messages.errorMoveTargetDirectoryExists(path),
      20 || 267 => messages.errorMoveTargetNotADirectory(path),
      2 || 3 => messages.errorMoveTargetDirectoryNotFound(path),
      36 || 206 => messages.errorMovePathTooLong(path),
      _ => _mapMoveErrorByText(error, path, messages),
    };
    return LocalFileException(text, cause: error);
  }

  /// Safely moves the `.tdf` file from [source] to [target] without overwriting existing entities.
  static void moveTdfFile(
    LocalFileRepository source,
    LocalFileRepository target,
    AppLocalizations messages, {
    required bool inMemory,
  }) {
    final fromPath = source.resolveFilePath();
    final toPath = target.resolveFilePath();
    if (fromPath == toPath) return;
    if (inMemory) {
      _moveInMemoryEntry(source.inMemoryStore, fromPath, toPath, messages);
      return;
    }
    final targetDirPath = target.resolveDirectoryPath();
    _validateTargetDirectory(targetDirPath, messages);
    _ensureTargetDoesNotExist(toPath, messages);
    switch (FileSystemEntity.typeSync(fromPath, followLinks: false)) {
      case FileSystemEntityType.link:
        throw LocalFileException(messages.errorMoveSourceIsSymlink(fromPath));
      case FileSystemEntityType.directory:
        throw LocalFileException(messages.errorMoveSourceIsDirectory(fromPath));
      case FileSystemEntityType.notFound:
        _verifyDirectoryWritable(targetDirPath, messages);
      case FileSystemEntityType.file:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        _performFileMove(fromPath, toPath, source.maxFileBytes, messages);
    }
    AppLogger.info(LogTag.storage, 'moveTdfFile $fromPath -> $toPath');
  }

  /// Synchronously reads up to [maxBytes] from the diagnostic log file at [path].
  static String readLogFileSync(String path, {required int maxBytes}) {
    try {
      final file = File(path);
      if (!file.existsSync()) return '';
      final bytes = file.readAsBytesSync();
      if (bytes.isEmpty) return '';
      final slice = bytes.length > maxBytes
          ? bytes.sublist(bytes.length - maxBytes)
          : bytes;
      return utf8.decode(slice, allowMalformed: true);
    } on FileSystemException {
      return '';
    }
  }

  /// Renames the local `.tdf` file of [repository] to [newFileName] inside the same directory and returns the new resolved path.
  static Future<String> renameTdf(
    LocalFileRepository repository,
    String newFileName,
    AppLocalizations messages,
  ) async {
    final normalizedName = validateFileName(newFileName, messages);
    final targetPath = combineDirectoryAndFileName(
      repository.resolveDirectoryPath(),
      normalizedName,
    );
    final targetRepository = LocalFileRepository(
      config: repository.config.copyWith(localFilePath: targetPath),
      baseDirectoryPath: repository.baseDirectoryPath,
      inMemoryStore: repository.inMemoryStore,
      maxFileBytes: repository.maxFileBytes,
    );
    await repository.moveTdfFile(targetRepository);
    return targetRepository.resolveFilePath();
  }

  /// Resolves the platform-appropriate user data directory for relative local file names.
  static String resolveDefaultDirectoryPath() {
    final env = Platform.environment;
    final sep = Platform.pathSeparator;
    final candidates = <String?>[
      if (Platform.isWindows) ...<String?>[
        env['APPDATA'],
        env['LOCALAPPDATA'],
        env['USERPROFILE'],
      ],
      env['XDG_DATA_HOME'],
    ];
    for (final candidate in candidates) {
      final trimmed = candidate?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return '${trimTrailingSeparators(trimmed)}${sep}tiertask';
      }
    }
    final home = (env['HOME'] ?? '').trim();
    if (home.isNotEmpty) {
      return '${trimTrailingSeparators(home)}$sep.local${sep}share${sep}tiertask';
    }
    return Directory.systemTemp.path;
  }

  /// Resolves the parent directory path of [resolvedFilePath].
  static String resolveDirectoryPath(String resolvedFilePath) {
    final sep = Platform.pathSeparator;
    final lastIndex = resolvedFilePath.lastIndexOf(sep);
    if (lastIndex <= 0) return sep;
    if (lastIndex == 2 && _windowsDrivePattern.hasMatch(resolvedFilePath)) {
      return resolvedFilePath.substring(0, 3);
    }
    return resolvedFilePath.substring(0, lastIndex);
  }

  /// Validates and resolves [rawPath] against [baseDirectoryPath], throwing [LocalFileException] if invalid.
  static String resolveFilePath(
    String rawPath,
    String? baseDirectoryPath,
    AppLocalizations messages,
  ) {
    final normalized = validateRelativeOrAbsolutePath(rawPath, messages);
    if (isAbsolutePath(rawPath.trim())) return normalized;
    final trimmedBase = baseDirectoryPath?.trim() ?? '';
    final base = trimmedBase.isNotEmpty
        ? trimmedBase
        : resolveDefaultDirectoryPath();
    return '${trimTrailingSeparators(base)}${Platform.pathSeparator}$normalized';
  }

  /// Resolves the first available `<filePath>.bak` or `<filePath>.bak.NNN` backup path on disk.
  static String resolveNextLocalBackupPath(
    String filePath,
    AppLocalizations messages,
  ) {
    for (var attempt = 0; attempt <= maxBackupSuffix; attempt++) {
      final candidate = formatBackupPath(filePath, attempt);
      if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return candidate;
      }
    }
    throw LocalFileException(
      messages.errorSaveLocalFileFailed('Maximum backup files reached'),
    );
  }

  /// Strips trailing `/` and `\` characters from [path].
  static String trimTrailingSeparators(String path) {
    var end = path.length;
    while (end > 1 &&
        (path.codeUnitAt(end - 1) == 0x2F ||
            path.codeUnitAt(end - 1) == 0x5C)) {
      end--;
    }
    return path.substring(0, end);
  }

  /// Validates that [rawName] is a single `.tdf` file name and returns it with a `.tdf` extension.
  static String validateFileName(String rawName, AppLocalizations messages) {
    if (!isValidSingleFileName(rawName)) {
      throw LocalFileException(messages.localFileNameErrorInvalid);
    }
    return ensureTdfExtension(rawName);
  }

  /// Validates [rawPath] against traversal and control characters and returns the normalized path string.
  static String validateRelativeOrAbsolutePath(
    String rawPath,
    AppLocalizations messages,
  ) {
    final trimmed = rawPath.trim();
    final segments = _validateAndSplitSegments(trimmed, messages);
    final sep = Platform.pathSeparator;
    final joined = segments.join(sep);
    if (trimmed.startsWith('/')) return '/$joined';
    if (_windowsDrivePattern.hasMatch(trimmed)) {
      final remaining = segments.skip(1).join(sep);
      if (remaining.isEmpty) {
        throw LocalFileException(messages.errorInvalidLocalFilePath);
      }
      return '${trimmed.substring(0, 2)}$sep$remaining';
    }
    return joined;
  }

  /// Synchronously writes or appends [content] to the diagnostic log file at [path] with `flush: true`.
  static void writeLogFileSync(
    String path,
    String content, {
    required bool append,
  }) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        content,
        mode: append ? FileMode.append : FileMode.write,
        flush: true,
      );
    } on FileSystemException {
      // Never propagate diagnostic log I/O errors into user workflows.
    }
  }

  /// Copies [sourcePath] to [targetPath] and deletes [sourcePath] when moving across mount points (`EXDEV`).
  static void _copyAndDeleteCrossDevice(
    String sourcePath,
    String targetPath,
    int maxBytes,
    AppLocalizations messages,
  ) {
    _ensureTargetDoesNotExist(targetPath, messages);
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);
    try {
      if (sourceFile.lengthSync() > maxBytes) {
        throw LocalFileException(messages.errorLocalFileTooLarge);
      }
      final bytes = sourceFile.readAsBytesSync();
      if (bytes.length > maxBytes) {
        throw LocalFileException(messages.errorLocalFileTooLarge);
      }
      targetFile.writeAsBytesSync(bytes, flush: true);
    } on LocalFileException {
      rethrow;
    } on FileSystemException catch (error) {
      throw mapMoveFileSystemException(error, targetPath, messages);
    }
    try {
      sourceFile.deleteSync();
    } on FileSystemException catch (error) {
      try {
        if (targetFile.existsSync()) targetFile.deleteSync();
      } on Object {
        // Keep original source deletion error as primary cause.
      }
      throw mapMoveFileSystemException(error, sourcePath, messages);
    }
  }

  /// Verifies that no file, directory, or symbolic link exists at [path].
  static void _ensureTargetDoesNotExist(
    String path,
    AppLocalizations messages,
  ) {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.link:
        throw LocalFileException(messages.errorMoveTargetSymlinkExists(path));
      case FileSystemEntityType.directory:
        throw LocalFileException(messages.errorMoveTargetDirectoryExists(path));
      case FileSystemEntityType.file:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw LocalFileException(messages.errorMoveTargetFileExists(path));
    }
  }

  /// Checks whether [value] contains ASCII control characters or null bytes.
  static bool _hasControlCharacters(String value) {
    for (var i = 0; i < value.length; i++) {
      final codeUnit = value.codeUnitAt(i);
      if (codeUnit < 0x20 || codeUnit == 0x7F) return true;
    }
    return false;
  }

  /// Returns `true` when [error] indicates a cross-device link (`EXDEV` on Linux, `ERROR_NOT_SAME_DEVICE` on Windows).
  static bool _isCrossDeviceError(FileSystemException error) {
    final code = error.osError?.errorCode;
    return code == 18 || code == 17 && Platform.isWindows;
  }

  /// Fallback text matcher when `osError.errorCode` is not populated or uses a non-standard code.
  static String _mapMoveErrorByText(
    FileSystemException error,
    String path,
    AppLocalizations messages,
  ) {
    final rawOs = error.osError?.message.trim() ?? '';
    final details = rawOs.isNotEmpty
        ? '$rawOs ($path)'
        : '${error.message} ($path)';
    final lower = details.toLowerCase();
    if (lower.contains('permission denied') ||
        lower.contains('access is denied') ||
        lower.contains('operation not permitted')) {
      return messages.errorMovePermissionDenied(path);
    }
    if (lower.contains('read-only')) {
      return messages.errorMoveReadOnlyFileSystem(path);
    }
    if (lower.contains('no space') || lower.contains('disk full')) {
      return messages.errorMoveDiskFull(path);
    }
    return messages.errorMoveLocalFileFailed(details);
  }

  /// Moves a `.tdf` entry inside [store] during hermetic widget tests.
  static void _moveInMemoryEntry(
    Map<String, String>? store,
    String sourcePath,
    String targetPath,
    AppLocalizations messages,
  ) {
    if (store == null) return;
    if (store.containsKey(targetPath)) {
      throw LocalFileException(messages.errorMoveTargetFileExists(targetPath));
    }
    final existing = store.remove(sourcePath);
    if (existing != null) store[targetPath] = existing;
  }

  /// Moves [sourcePath] to [targetPath] via `File.renameSync` with cross-device copy-and-delete fallback.
  static void _performFileMove(
    String sourcePath,
    String targetPath,
    int maxBytes,
    AppLocalizations messages,
  ) {
    try {
      File(sourcePath).renameSync(targetPath);
    } on FileSystemException catch (error) {
      if (_isCrossDeviceError(error)) {
        _copyAndDeleteCrossDevice(sourcePath, targetPath, maxBytes, messages);
        return;
      }
      throw mapMoveFileSystemException(error, targetPath, messages);
    }
  }

  /// Validates [rawPath] against traversal and control characters and returns normalized path segments.
  static List<String> _validateAndSplitSegments(
    String rawPath,
    AppLocalizations messages,
  ) {
    if (rawPath.isEmpty || _hasControlCharacters(rawPath)) {
      throw LocalFileException(messages.errorInvalidLocalFilePath);
    }
    final segments = <String>[];
    for (final segment in rawPath.split(_pathSeparatorPattern)) {
      if (segment.isEmpty) continue;
      if (segment == '.' || segment == '..') {
        throw LocalFileException(messages.errorInvalidLocalFilePath);
      }
      segments.add(segment);
    }
    if (segments.isEmpty) {
      throw LocalFileException(messages.errorInvalidLocalFilePath);
    }
    return segments;
  }

  /// Verifies that [path] exists and resolves to a directory rather than a file or broken link.
  static void _validateTargetDirectory(String path, AppLocalizations messages) {
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      throw LocalFileException(messages.errorMoveTargetDirectoryNotFound(path));
    }
    if (FileSystemEntity.typeSync(path, followLinks: true) !=
        FileSystemEntityType.directory) {
      throw LocalFileException(messages.errorMoveTargetNotADirectory(path));
    }
  }

  /// Verifies write access in [path] when no `.tdf` file exists on disk yet.
  static void _verifyDirectoryWritable(String path, AppLocalizations messages) {
    final probe =
        '$path${Platform.pathSeparator}.tiertask_write_probe_${DateTime.now().microsecondsSinceEpoch}';
    if (FileSystemEntity.typeSync(probe, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return;
    }
    try {
      File(probe)
        ..writeAsBytesSync(const <int>[], flush: true)
        ..deleteSync();
    } on FileSystemException catch (error) {
      throw mapMoveFileSystemException(error, path, messages);
    }
  }
}
