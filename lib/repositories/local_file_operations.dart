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
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import '../models/webdav_config.dart';
import '../services/app_logger.dart';

/// Stateless helper operations for local `.tdf` path validation, `.bak` backup
/// rotation, safe cross-device file moves, and synchronous diagnostic log I/O.
@immutable
class LocalFileOperations<E extends Exception> {
  /// Creates a const [LocalFileOperations] helper using [createException] to build domain errors.
  const LocalFileOperations(this.createException);

  /// Maximum numbered `.bak.NNN` suffix checked when creating a backup copy (`999`).
  static const int maxBackupSuffix = 999;

  static const String _hexDigits = '0123456789abcdef';
  static final RegExp _pathSeparatorPattern = RegExp(r'[\\/]+');
  static final math.Random _secureRandom = math.Random.secure();
  static final RegExp _windowsDrivePattern = RegExp(r'^[a-zA-Z]:[\\/]');

  /// Factory function that constructs a typed domain exception with an optional cause.
  final E Function(String message, {Object? cause}) createException;

  /// Combines [directoryPath] and [fileName] into a normalized local `.tdf` file path.
  String combineDirectoryAndFileName(String directoryPath, String fileName) =>
      _joinDirectoryAndChild(directoryPath, extractFileNameFromPath(fileName));

  /// Resolves the default filesystem path for [fileName] (or `tiertask.log`) inside [baseDirectoryPath] or the user data directory.
  String defaultLogFilePath({String? baseDirectoryPath, String? fileName}) {
    final trimmed = baseDirectoryPath?.trim() ?? '';
    final base = trimmed.isNotEmpty ? trimmed : resolveDefaultDirectoryPath();
    final targetName = (fileName != null && fileName.trim().isNotEmpty)
        ? extractFileNameFromPath(fileName.trim())
        : AppLogger.defaultLogFileName;
    return _joinDirectoryAndChild(base, targetName);
  }

  /// Synchronously deletes the diagnostic log file at [path] if it is a regular file.
  void deleteLogFileSync(String path) {
    try {
      if (FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.file) {
        File(path).deleteSync();
      }
    } on FileSystemException {
      // Ignore deletion failures on missing or locked diagnostic files.
    }
  }

  /// Deletes all dated and legacy diagnostic log files for [workspaceId] in [directoryPath].
  int deleteWorkspaceLogFilesSync({
    required String directoryPath,
    required String platform,
    required String workspaceId,
  }) {
    final cleanDir = directoryPath.trim();
    if (cleanDir.isEmpty) return 0;
    try {
      final dir = Directory(cleanDir);
      if (!dir.existsSync()) return 0;
      final suffix = _workspaceLogSuffix(platform, workspaceId);
      var deleted = 0;
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = extractFileNameFromPath(entity.path);
        final isLegacy = name == AppLogger.defaultLogFileName;
        final isWorkspaceLog = _tryParseWorkspaceLogDate(name, suffix) != null;
        if (isLegacy || isWorkspaceLog) {
          deleteLogFileSync(entity.path);
          deleted++;
        }
      }
      return deleted;
    } on FileSystemException {
      return 0;
    }
  }

  /// Deletes the local `.tdf` file at [path] if it exists, rejecting directories, symbolic links, and special files.
  void deleteTdf(
    String path,
    AppLocalizations messages, {
    required bool inMemory,
    Map<String, String>? inMemoryStore,
  }) {
    if (inMemory) {
      inMemoryStore?.remove(path);
      return;
    }
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.directory:
        throw createException(messages.errorMoveSourceIsDirectory(path));
      case FileSystemEntityType.link:
        throw createException(messages.errorMoveSourceIsSymlink(path));
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw createException(messages.errorMovePermissionDenied(path));
      case FileSystemEntityType.file:
        break;
    }
    try {
      File(path).deleteSync();
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'local.wipe',
        fields: <String, Object?>{'path': path, 'deleted': true},
      );
    } on FileSystemException catch (error) {
      throw mapMoveFileSystemException(error, path, messages);
    }
  }

  /// Appends `.tdf` to [rawName] when it does not already end with `.tdf` (case-insensitive).
  String ensureTdfExtension(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return WebDavConfig.defaultFileName;
    if (trimmed.length > 4 &&
        trimmed.substring(trimmed.length - 4).toLowerCase() == '.tdf') {
      return trimmed;
    }
    return '$trimmed.tdf';
  }

  /// Extracts the parent directory portion from [rawPath], or an empty string when [rawPath] is a bare file name.
  String extractDirectoryFromPath(String rawPath) {
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
  String extractFileBaseName(String rawPath) {
    final fileName = extractFileNameFromPath(rawPath);
    if (fileName.length > 4 &&
        fileName.substring(fileName.length - 4).toLowerCase() == '.tdf') {
      return fileName.substring(0, fileName.length - 4);
    }
    return fileName;
  }

  /// Extracts the trailing file name segment from [rawPath], defaulting to [WebDavConfig.defaultFileName].
  String extractFileNameFromPath(String rawPath) {
    final parts = rawPath.trim().split(_pathSeparatorPattern);
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].isNotEmpty) return parts[i];
    }
    return WebDavConfig.defaultFileName;
  }

  /// Formats the candidate backup path or URI suffix for [basePath] at [attemptIndex].
  String formatBackupPath(String basePath, int attemptIndex) =>
      attemptIndex <= 0
      ? '$basePath.bak'
      : '$basePath.bak.${attemptIndex.toString().padLeft(3, '0')}';

  /// Returns `true` if [rawPath] starts with a POSIX root `/` or Windows drive prefix.
  bool isAbsolutePath(String rawPath) =>
      rawPath.startsWith('/') || _windowsDrivePattern.hasMatch(rawPath);

  /// Returns `true` when [rawName] is a valid single `.tdf` file name or base name without path separators or control characters.
  bool isValidSingleFileName(String rawName) {
    final trimmed = rawName.trim();
    return trimmed.isNotEmpty &&
        trimmed != '.' &&
        trimmed != '..' &&
        trimmed.toLowerCase() != '.tdf' &&
        !trimmed.contains('/') &&
        !trimmed.contains(r'\') &&
        !trimmed.contains(':') &&
        !_hasControlCharacters(trimmed);
  }

  /// Maps a [FileSystemException] during a `.tdf` file move into a specific localized exception.
  E mapMoveFileSystemException(
    FileSystemException error,
    String fallbackPath,
    AppLocalizations messages,
  ) {
    final rawErrorPath = error.path;
    final path = rawErrorPath != null && rawErrorPath.trim().isNotEmpty
        ? rawErrorPath
        : fallbackPath;
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
    return createException(text, cause: error);
  }

  /// Safely moves the `.tdf` file from [fromPath] to [toPath] inside [targetDirectoryPath] without overwriting existing entities.
  void moveTdfFile(
    String fromPath,
    String toPath,
    String targetDirectoryPath,
    int maxFileBytes,
    AppLocalizations messages, {
    required bool inMemory,
    Map<String, String>? inMemoryStore,
  }) {
    if (fromPath == toPath) return;
    if (inMemory) {
      _moveInMemoryEntry(inMemoryStore, fromPath, toPath, messages);
      return;
    }
    _validateTargetDirectory(targetDirectoryPath, messages);
    _ensureTargetDoesNotExist(toPath, messages);
    switch (FileSystemEntity.typeSync(fromPath, followLinks: false)) {
      case FileSystemEntityType.link:
        throw createException(messages.errorMoveSourceIsSymlink(fromPath));
      case FileSystemEntityType.directory:
        throw createException(messages.errorMoveSourceIsDirectory(fromPath));
      case FileSystemEntityType.notFound:
        _verifyDirectoryWritable(targetDirectoryPath, messages);
      case FileSystemEntityType.file:
        _performFileMove(fromPath, toPath, maxFileBytes, messages);
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw createException(messages.errorMovePermissionDenied(fromPath));
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.storage,
      'local.move',
      fields: <String, Object?>{'from': fromPath, 'to': toPath},
    );
  }

  /// Prunes expired (`> maxRetainedDays`) and excess (`> maxRetainedFiles`) log files for [workspaceId].
  int pruneExpiredLogFilesSync({
    required String directoryPath,
    required String platform,
    required String workspaceId,
    required DateTime utcNow,
    int maxRetainedDays = AppLogger.maxRetainedLogDays,
    int maxRetainedFiles = AppLogger.maxRetainedLogFiles,
  }) {
    final cleanDir = directoryPath.trim();
    if (cleanDir.isEmpty) return 0;
    try {
      final dir = Directory(cleanDir);
      if (!dir.existsSync()) return 0;
      final suffix = _workspaceLogSuffix(platform, workspaceId);
      final todayUtc = DateTime.utc(utcNow.year, utcNow.month, utcNow.day);
      final retainedCandidates = <(DateTime, String)>[];
      var pruned = 0;

      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = extractFileNameFromPath(entity.path);
        if (name == AppLogger.defaultLogFileName) {
          deleteLogFileSync(entity.path);
          pruned++;
          continue;
        }
        final logDate = _tryParseWorkspaceLogDate(name, suffix);
        if (logDate == null) continue;
        if (todayUtc.difference(logDate).inDays > maxRetainedDays) {
          deleteLogFileSync(entity.path);
          pruned++;
        } else {
          retainedCandidates.add((logDate, entity.path));
        }
      }

      retainedCandidates.sort((a, b) => a.$1.compareTo(b.$1));
      final overflowCount = retainedCandidates.length - maxRetainedFiles;
      for (var i = 0; i < overflowCount; i++) {
        deleteLogFileSync(retainedCandidates[i].$2);
        pruned++;
      }
      return pruned;
    } on FileSystemException {
      return 0;
    }
  }

  /// Synchronously reads up to [maxBytes] from the diagnostic log file at [path].
  String readLogFileSync(String path, {required int maxBytes}) {
    if (maxBytes <= 0) return '';
    try {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.file) {
        return '';
      }
      final randomAccessFile = File(path).openSync();
      try {
        final length = randomAccessFile.lengthSync();
        if (length <= 0) return '';
        if (length > maxBytes) {
          randomAccessFile.setPositionSync(length - maxBytes);
        }
        final bytes = randomAccessFile.readSync(
          length > maxBytes ? maxBytes : length,
        );
        return utf8.decode(bytes, allowMalformed: true);
      } finally {
        randomAccessFile.closeSync();
      }
    } on FileSystemException {
      return '';
    }
  }

  /// Renames the local `.tdf` file at [fromPath] inside [directoryPath] to [newFileName] and returns the new resolved path.
  String renameTdf(
    String fromPath,
    String directoryPath,
    String newFileName,
    int maxFileBytes,
    AppLocalizations messages, {
    required bool inMemory,
    Map<String, String>? inMemoryStore,
  }) {
    final normalizedName = validateFileName(newFileName, messages);
    final toPath = combineDirectoryAndFileName(directoryPath, normalizedName);
    moveTdfFile(
      fromPath,
      toPath,
      resolveDirectoryPath(toPath),
      maxFileBytes,
      messages,
      inMemory: inMemory,
      inMemoryStore: inMemoryStore,
    );
    return toPath;
  }

  /// Resolves the platform-appropriate user data directory for relative local file names.
  String resolveDefaultDirectoryPath() {
    final environment = Platform.environment;
    final separator = Platform.pathSeparator;
    final candidates = <String?>[
      if (Platform.isWindows) ...<String?>[
        environment['APPDATA'],
        environment['LOCALAPPDATA'],
        environment['USERPROFILE'],
      ],
      environment['XDG_DATA_HOME'],
    ];
    for (final candidate in candidates) {
      final trimmed = candidate?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return '${trimTrailingSeparators(trimmed)}${separator}tiertask';
      }
    }
    final home = (environment['HOME'] ?? '').trim();
    if (home.isNotEmpty) {
      return '${trimTrailingSeparators(home)}$separator.local${separator}share${separator}tiertask';
    }
    return Directory.systemTemp.path;
  }

  /// Resolves the parent directory path of [resolvedFilePath].
  String resolveDirectoryPath(String resolvedFilePath) {
    final separator = Platform.pathSeparator;
    final lastIndex = resolvedFilePath.lastIndexOf(separator);
    if (lastIndex <= 0) return separator;
    if (lastIndex == 2 && _windowsDrivePattern.hasMatch(resolvedFilePath)) {
      return resolvedFilePath.substring(0, 3);
    }
    return resolvedFilePath.substring(0, lastIndex);
  }

  /// Validates and resolves [rawPath] against [baseDirectoryPath], throwing via [createException] if invalid.
  String resolveFilePath(
    String rawPath,
    String? baseDirectoryPath,
    AppLocalizations messages,
  ) {
    final normalized = validateRelativeOrAbsolutePath(rawPath, messages);
    if (isAbsolutePath(rawPath.trim())) return normalized;
    final trimmedBase = baseDirectoryPath?.trim() ?? '';
    final base = trimmedBase.isNotEmpty
        ? _validateBaseDirectoryPath(trimmedBase, messages)
        : resolveDefaultDirectoryPath();
    return _joinDirectoryAndChild(base, normalized);
  }

  /// Resolves the first available `<filePath>.bak` or `<filePath>.bak.NNN` backup path on disk.
  String resolveNextLocalBackupPath(
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
    throw createException(
      messages.errorSaveLocalFileFailed('Maximum backup files reached'),
    );
  }

  /// Strips trailing `/` and `\` characters from [path], preserving POSIX and Windows drive roots.
  String trimTrailingSeparators(String path) {
    final minLength = _windowsDrivePattern.hasMatch(path) ? 3 : 1;
    var end = path.length;
    while (end > minLength &&
        (path.codeUnitAt(end - 1) == 0x2F ||
            path.codeUnitAt(end - 1) == 0x5C)) {
      end--;
    }
    return path.substring(0, end);
  }

  /// Validates that [rawName] is a single `.tdf` file name and returns it with a `.tdf` extension.
  String validateFileName(String rawName, AppLocalizations messages) {
    if (!isValidSingleFileName(rawName)) {
      throw createException(messages.localFileNameErrorInvalid);
    }
    return ensureTdfExtension(rawName);
  }

  /// Validates [rawPath] against traversal and control characters and returns the normalized path string.
  String validateRelativeOrAbsolutePath(
    String rawPath,
    AppLocalizations messages,
  ) {
    final trimmed = rawPath.trim();
    final segments = _validateAndSplitSegments(trimmed, messages);
    final separator = Platform.pathSeparator;
    final joined = segments.join(separator);
    if (trimmed.startsWith('/')) return '/$joined';
    if (_windowsDrivePattern.hasMatch(trimmed)) {
      final remaining = segments.skip(1).join(separator);
      if (remaining.isEmpty) {
        throw createException(messages.errorInvalidLocalFilePath);
      }
      return '${trimmed.substring(0, 2)}$separator$remaining';
    }
    return joined;
  }

  /// Synchronously writes or appends [content] to the diagnostic log file at [path] with `flush: true`.
  void writeLogFileSync(String path, String content, {required bool append}) {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        return;
      }
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        content,
        mode: append ? FileMode.append : FileMode.write,
        flush: true,
      );
      if (Platform.isLinux &&
          (type == FileSystemEntityType.notFound || !append)) {
        Process.runSync('chmod', <String>['0600', path]);
      }
    } on FileSystemException {
      // Never propagate diagnostic log I/O errors into user workflows.
    }
  }

  /// Atomically writes [bytes] to [filePath] via a dot-prefixed `.tmp.<32hex>` temporary file in the same directory.
  void writeTdfAtomicallySync(
    String filePath,
    List<int> bytes,
    AppLocalizations messages,
  ) {
    final targetType = FileSystemEntity.typeSync(filePath, followLinks: false);
    if (targetType == FileSystemEntityType.directory) {
      throw createException(messages.errorMoveSourceIsDirectory(filePath));
    }
    if (targetType == FileSystemEntityType.link) {
      throw createException(messages.errorMoveSourceIsSymlink(filePath));
    }
    final targetFile = File(filePath);
    targetFile.parent.createSync(recursive: true);
    final fileName = extractFileNameFromPath(filePath);
    final tempPath = _joinDirectoryAndChild(
      targetFile.parent.path,
      '.$fileName.tmp.${_generateTempHexSuffix()}',
    );
    if (FileSystemEntity.typeSync(tempPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw createException(
        messages.errorSaveLocalFileFailed('Temporary file collision'),
      );
    }
    final tempFile = File(tempPath);
    try {
      _writeAndFlushTempFileSync(tempFile, bytes, messages);
      tempFile.renameSync(filePath);
    } on Object {
      _cleanupTempFileSync(tempFile);
      rethrow;
    }
  }

  /// Deletes [tempFile] if it exists as a regular file after a failed atomic write or rename.
  void _cleanupTempFileSync(File tempFile) {
    if (FileSystemEntity.typeSync(tempFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    try {
      tempFile.deleteSync();
    } on FileSystemException {
      // Preserve original write or rename error as primary cause.
    }
  }

  /// Copies [sourcePath] to [targetPath] and deletes [sourcePath] when moving across mount points (`EXDEV`).
  void _copyAndDeleteCrossDevice(
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
        throw createException(messages.errorLocalFileTooLarge);
      }
      final bytes = sourceFile.readAsBytesSync();
      if (bytes.length > maxBytes) {
        throw createException(messages.errorLocalFileTooLarge);
      }
      targetFile.writeAsBytesSync(bytes, flush: true);
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
  void _ensureTargetDoesNotExist(String path, AppLocalizations messages) {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.link:
        throw createException(messages.errorMoveTargetSymlinkExists(path));
      case FileSystemEntityType.directory:
        throw createException(messages.errorMoveTargetDirectoryExists(path));
      case FileSystemEntityType.file:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw createException(messages.errorMoveTargetFileExists(path));
    }
  }

  /// Generates a 128-bit (`32` lowercase hex characters) CSPRNG suffix for atomic temporary files.
  String _generateTempHexSuffix() {
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(_hexDigits[_secureRandom.nextInt(16)]);
    }
    return buffer.toString();
  }

  /// Checks whether [value] contains ASCII control characters or null bytes.
  bool _hasControlCharacters(String value) {
    for (var i = 0; i < value.length; i++) {
      final codeUnit = value.codeUnitAt(i);
      if (codeUnit < 0x20 || codeUnit == 0x7F) return true;
    }
    return false;
  }

  /// Returns `true` when [error] indicates a cross-device link (`EXDEV` on Linux, `ERROR_NOT_SAME_DEVICE` on Windows).
  bool _isCrossDeviceError(FileSystemException error) {
    final code = error.osError?.errorCode;
    return code == 18 || code == 17 && Platform.isWindows;
  }

  /// Joins [directoryPath] and [childPath] with a single platform path separator without duplicating root slashes.
  String _joinDirectoryAndChild(String directoryPath, String childPath) {
    final cleanDirectory = trimTrailingSeparators(directoryPath.trim());
    if (cleanDirectory.isEmpty) return childPath;
    final lastCode = cleanDirectory.codeUnitAt(cleanDirectory.length - 1);
    if (lastCode == 0x2F || lastCode == 0x5C) {
      return '$cleanDirectory$childPath';
    }
    return '$cleanDirectory${Platform.pathSeparator}$childPath';
  }

  /// Fallback text matcher when `osError.errorCode` is not populated or uses a non-standard code.
  String _mapMoveErrorByText(
    FileSystemException error,
    String path,
    AppLocalizations messages,
  ) {
    final rawOsMessage = error.osError?.message.trim() ?? '';
    final details = rawOsMessage.isNotEmpty
        ? '$rawOsMessage ($path)'
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
  void _moveInMemoryEntry(
    Map<String, String>? store,
    String sourcePath,
    String targetPath,
    AppLocalizations messages,
  ) {
    if (store == null) return;
    if (store.containsKey(targetPath)) {
      throw createException(messages.errorMoveTargetFileExists(targetPath));
    }
    final existing = store.remove(sourcePath);
    if (existing != null) store[targetPath] = existing;
  }

  /// Moves [sourcePath] to [targetPath] via `File.renameSync` with cross-device copy-and-delete fallback.
  void _performFileMove(
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

  /// Parses the UTC date from [fileName] if it matches `tiertask_<YYYY-MM-DD>[suffix]`.
  DateTime? _tryParseWorkspaceLogDate(String fileName, String suffix) {
    if (!fileName.startsWith('tiertask_') ||
        !fileName.endsWith(suffix) ||
        fileName.length != 19 + suffix.length) {
      return null;
    }
    final datePart = fileName.substring(9, 19);
    if (datePart.codeUnitAt(4) != 0x2D || datePart.codeUnitAt(7) != 0x2D) {
      return null;
    }
    final year = int.tryParse(datePart.substring(0, 4));
    final month = int.tryParse(datePart.substring(5, 7));
    final day = int.tryParse(datePart.substring(8, 10));
    if (year == null ||
        month == null ||
        day == null ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    return DateTime.utc(year, month, day);
  }

  /// Validates [rawPath] against traversal, UNC prefixes, drive-relative colons, and control characters and returns normalized path segments.
  List<String> _validateAndSplitSegments(
    String rawPath,
    AppLocalizations messages,
  ) {
    if (rawPath.isEmpty ||
        rawPath.startsWith(r'\') ||
        _hasControlCharacters(rawPath)) {
      throw createException(messages.errorInvalidLocalFilePath);
    }
    final isWindowsDrive = _windowsDrivePattern.hasMatch(rawPath);
    final segments = <String>[];
    for (final segment in rawPath.split(_pathSeparatorPattern)) {
      if (segment.isEmpty) continue;
      final allowDriveColon = isWindowsDrive && segments.isEmpty;
      if (segment == '.' ||
          segment == '..' ||
          (!allowDriveColon && segment.contains(':'))) {
        throw createException(messages.errorInvalidLocalFilePath);
      }
      segments.add(segment);
    }
    if (segments.isEmpty) {
      throw createException(messages.errorInvalidLocalFilePath);
    }
    return segments;
  }

  /// Validates [rawBase] as a safe base directory path without traversal or control characters.
  String _validateBaseDirectoryPath(String rawBase, AppLocalizations messages) {
    final cleanBase = trimTrailingSeparators(rawBase.trim());
    if (cleanBase == '/') return '/';
    if (cleanBase.length == 3 && _windowsDrivePattern.hasMatch(cleanBase)) {
      return '${cleanBase.substring(0, 2)}${Platform.pathSeparator}';
    }
    return validateRelativeOrAbsolutePath(cleanBase, messages);
  }

  /// Verifies that [path] exists and resolves to a directory rather than a file or broken link.
  void _validateTargetDirectory(String path, AppLocalizations messages) {
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      throw createException(messages.errorMoveTargetDirectoryNotFound(path));
    }
    if (FileSystemEntity.typeSync(path, followLinks: true) !=
        FileSystemEntityType.directory) {
      throw createException(messages.errorMoveTargetNotADirectory(path));
    }
  }

  /// Verifies write access in [path] when no `.tdf` file exists on disk yet.
  void _verifyDirectoryWritable(String path, AppLocalizations messages) {
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

  /// Derives the canonical `_<platform>_<workspaceId>.log` suffix via [AppLogger.formatLogFileName].
  String _workspaceLogSuffix(String platform, String workspaceId) {
    final sample = AppLogger.formatLogFileName(
      utcNow: DateTime.utc(2000),
      platform: platform,
      workspaceId: workspaceId,
    );
    return sample.substring(19);
  }

  /// Opens [tempFile] with `FileMode.writeOnly`, applies owner-only `0600` permissions on Linux, writes [bytes], and flushes (`fsync`).
  void _writeAndFlushTempFileSync(
    File tempFile,
    List<int> bytes,
    AppLocalizations messages,
  ) {
    final handle = tempFile.openSync(mode: FileMode.writeOnly);
    try {
      if (Platform.isLinux &&
          Process.runSync('chmod', <String>['0600', tempFile.path]).exitCode !=
              0) {
        throw createException(
          messages.errorSaveLocalFileFailed('Failed to set 0600 permissions'),
        );
      }
      handle.writeFromSync(bytes);
      handle.flushSync();
    } finally {
      handle.closeSync();
    }
  }
}
