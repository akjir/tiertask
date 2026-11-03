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
import 'dart:ui';

import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/webdav_config.dart';

/// Custom domain exception thrown when local TDF file operations fail.
class LocalFileException implements Exception {
  /// Creates a [LocalFileException] with a localized [message] and optional [cause].
  const LocalFileException(this.message, {this.cause});

  /// Underlying exception cause when available.
  final Object? cause;

  /// Human-readable error message.
  final String message;

  @override
  String toString() => message;
}

/// Repository for reading, writing, and migrating the task board `.tdf` file on the local filesystem.
class LocalFileRepository {
  /// Creates a [LocalFileRepository] for [config].
  LocalFileRepository({
    required this.config,
    this.baseDirectoryPath,
    this.inMemoryStore,
    this.maxFileBytes = defaultMaxFileBytes,
  });

  /// Default maximum allowed TDF file size in bytes (1 MiB).
  static const int defaultMaxFileBytes = 1048576;

  /// Platform channel for invoking the native Linux and Windows directory chooser dialog.
  static const MethodChannel directoryPickerChannel = MethodChannel(
    'de.akjir.tiertask/directory_picker',
  );

  static final RegExp _pathSeparatorPattern = RegExp(r'[\\/]+');
  static final RegExp _windowsDrivePattern = RegExp(r'^[a-zA-Z]:[\\/]');

  /// Optional base directory path where relative local file names are stored.
  final String? baseDirectoryPath;

  /// Active configuration containing the local file name or path and locale setting.
  final WebDavConfig config;

  /// Optional in-memory store used during hermetic widget tests.
  final Map<String, String>? inMemoryStore;

  /// Maximum allowed file size in bytes before rejecting a read or write.
  final int maxFileBytes;

  /// Resolves the active [AppLocalizations] instance for error messages.
  AppLocalizations get _localizations {
    final locale = config.language.resolveLocale(
      PlatformDispatcher.instance.locale,
    );
    return lookupAppLocalizations(locale);
  }

  /// Whether to use the isolated in-memory store during hermetic widget tests.
  bool get _useInMemoryFallback =>
      baseDirectoryPath == null &&
      !_isAbsolutePath(config.localFilePath.trim()) &&
      inMemoryStore != null &&
      Platform.environment.containsKey('FLUTTER_TEST');

  /// Combines [directoryPath] and [fileName] into a normalized local `.tdf` file path.
  static String combineDirectoryAndFileName(
    String directoryPath,
    String fileName,
  ) {
    final cleanDir = _trimTrailingSeparators(directoryPath.trim());
    final cleanName = extractFileNameFromPath(fileName);
    if (cleanDir.isEmpty) {
      return cleanName;
    }
    final separator = Platform.pathSeparator;
    if (cleanDir == separator) {
      return '$separator$cleanName';
    }
    return '$cleanDir$separator$cleanName';
  }

  /// Extracts the trailing `.tdf` file name segment from [ config.localFilePath ].
  String extractFileName() => extractFileNameFromPath(config.localFilePath);

  /// Extracts the trailing file name segment from [rawPath], defaulting to [WebDavConfig.defaultFileName].
  static String extractFileNameFromPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return WebDavConfig.defaultFileName;
    }
    final parts = trimmed
        .split(_pathSeparatorPattern)
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? WebDavConfig.defaultFileName : parts.last;
  }

  /// Reads the local `.tdf` file and returns its contents, or an empty string if the file does not exist.
  Future<String> loadTdf() async {
    final localizations = _localizations;
    final filePath = resolveFilePath();

    if (_useInMemoryFallback) {
      return inMemoryStore?[filePath] ?? '';
    }

    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return '';
      }
      final fileLength = file.lengthSync();
      if (fileLength > maxFileBytes) {
        throw LocalFileException(localizations.errorLocalFileTooLarge);
      }
      final bytes = file.readAsBytesSync();
      if (bytes.length > maxFileBytes) {
        throw LocalFileException(localizations.errorLocalFileTooLarge);
      }
      return utf8.decode(bytes);
    } on LocalFileException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LocalFileException(
        localizations.errorLoadLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      throw LocalFileException(
        localizations.errorLoadLocalFileFailed(error.toString()),
        cause: error,
      );
    }
  }

  /// Maps a [FileSystemException] during a `.tdf` file move into a specific localized [LocalFileException].
  LocalFileException mapMoveFileSystemException(
    FileSystemException error, {
    required String fallbackPath,
  }) {
    final localizations = _localizations;
    final path = (error.path != null && error.path!.trim().isNotEmpty)
        ? error.path!
        : fallbackPath;
    final code = error.osError?.errorCode;
    final message = switch (code) {
      13 || 1 || 5 || 1314 => localizations.errorMovePermissionDenied(path),
      30 || 19 => localizations.errorMoveReadOnlyFileSystem(path),
      28 || 122 || 112 || 39 => localizations.errorMoveDiskFull(path),
      16 || 26 || 32 || 33 => localizations.errorMoveFileLocked(path),
      17 || 80 || 183 => localizations.errorMoveTargetFileExists(path),
      21 => localizations.errorMoveTargetDirectoryExists(path),
      20 || 267 => localizations.errorMoveTargetNotADirectory(path),
      2 || 3 => localizations.errorMoveTargetDirectoryNotFound(path),
      36 || 206 => localizations.errorMovePathTooLong(path),
      _ => _mapMoveErrorByText(error, path, localizations),
    };
    return LocalFileException(message, cause: error);
  }

  /// Safely moves the local `.tdf` file to [targetRepository]'s resolved path without overwriting existing entities.
  Future<void> moveTdfFile(LocalFileRepository targetRepository) async {
    final localizations = _localizations;
    final sourcePath = resolveFilePath();
    final targetPath = targetRepository.resolveFilePath();
    if (sourcePath == targetPath) {
      return;
    }

    if (_useInMemoryFallback && targetRepository._useInMemoryFallback) {
      _moveInMemoryEntry(sourcePath, targetPath, localizations);
      return;
    }

    final targetDirPath = targetRepository.resolveDirectoryPath();
    _validateTargetDirectory(targetDirPath, localizations);
    _ensureTargetDoesNotExist(targetPath, localizations);

    final sourceType = FileSystemEntity.typeSync(
      sourcePath,
      followLinks: false,
    );
    switch (sourceType) {
      case FileSystemEntityType.link:
        throw LocalFileException(
          localizations.errorMoveSourceIsSymlink(sourcePath),
        );
      case FileSystemEntityType.directory:
        throw LocalFileException(
          localizations.errorMoveSourceIsDirectory(sourcePath),
        );
      case FileSystemEntityType.notFound:
        _verifyDirectoryWritable(targetDirPath, localizations);
      case FileSystemEntityType.file:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        _performFileMove(sourcePath, targetPath);
    }
  }

  /// Opens the native desktop directory selection dialog and returns the chosen path, or `null` if cancelled.
  Future<String?> pickDirectory({String? initialDirectory}) async {
    try {
      final selected = await directoryPickerChannel.invokeMethod<String>(
        'pickDirectory',
        <String, Object?>{'initialDirectory': initialDirectory},
      );
      if (selected == null || selected.trim().isEmpty) {
        return null;
      }
      return _trimTrailingSeparators(selected.trim());
    } on PlatformException catch (error) {
      throw LocalFileException(
        _localizations.errorMoveLocalFileFailed(error.message ?? error.code),
        cause: error,
      );
    } on MissingPluginException {
      return null;
    }
  }

  /// Resolves the parent directory path of [resolveFilePath].
  String resolveDirectoryPath() {
    final fullPath = resolveFilePath();
    final separator = Platform.pathSeparator;
    final lastIndex = fullPath.lastIndexOf(separator);
    if (lastIndex <= 0) {
      return separator;
    }
    if (lastIndex == 2 && _windowsDrivePattern.hasMatch(fullPath)) {
      return fullPath.substring(0, 3);
    }
    return fullPath.substring(0, lastIndex);
  }

  /// Validates and resolves the target local file path, throwing [LocalFileException] if invalid.
  String resolveFilePath() {
    final localizations = _localizations;
    final rawPath = config.localFilePath.trim();
    final segments = _validateAndSplitSegments(rawPath, localizations);
    final separator = Platform.pathSeparator;
    final joinedSegments = segments.join(separator);

    if (rawPath.startsWith('/')) {
      return '/$joinedSegments';
    }
    if (_windowsDrivePattern.hasMatch(rawPath)) {
      final drivePrefix = rawPath.substring(0, 2);
      final remaining = segments.skip(1).join(separator);
      if (remaining.isEmpty) {
        throw LocalFileException(localizations.errorInvalidLocalFilePath);
      }
      return '$drivePrefix$separator$remaining';
    }

    if (baseDirectoryPath case final explicitBase?
        when explicitBase.trim().isNotEmpty) {
      final cleanedBase = _trimTrailingSeparators(explicitBase.trim());
      return '$cleanedBase$separator$joinedSegments';
    }

    final defaultBase = _trimTrailingSeparators(_defaultBaseDirectoryPath());
    return '$defaultBase$separator$joinedSegments';
  }

  /// Writes [tdfContent] to the configured local `.tdf` file.
  Future<void> saveTdf(String tdfContent) async {
    final localizations = _localizations;
    final filePath = resolveFilePath();
    final bytes = utf8.encode(tdfContent);
    if (bytes.length > maxFileBytes) {
      throw LocalFileException(localizations.errorLocalFileTooLarge);
    }

    if (_useInMemoryFallback) {
      inMemoryStore?[filePath] = tdfContent;
      return;
    }

    try {
      final file = File(filePath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes, flush: true);
    } on LocalFileException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LocalFileException(
        localizations.errorSaveLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      throw LocalFileException(
        localizations.errorSaveLocalFileFailed(error.toString()),
        cause: error,
      );
    }
  }

  /// Returns the resolved parent directory path, or `null` if [config.localFilePath] is invalid.
  String? tryResolveDirectoryPath() {
    try {
      return resolveDirectoryPath();
    } on LocalFileException {
      return null;
    }
  }

  /// Returns the resolved local file path, or `null` if [config.localFilePath] is invalid.
  String? tryResolveFilePath() {
    try {
      return resolveFilePath();
    } on LocalFileException {
      return null;
    }
  }

  /// Copies [sourcePath] to [targetPath] and deletes [sourcePath] when moving across mount points (`EXDEV`).
  void _copyAndDeleteCrossDevice(String sourcePath, String targetPath) {
    final localizations = _localizations;
    _ensureTargetDoesNotExist(targetPath, localizations);
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);

    try {
      final length = sourceFile.lengthSync();
      if (length > maxFileBytes) {
        throw LocalFileException(localizations.errorLocalFileTooLarge);
      }
      final bytes = sourceFile.readAsBytesSync();
      if (bytes.length > maxFileBytes) {
        throw LocalFileException(localizations.errorLocalFileTooLarge);
      }
      targetFile.writeAsBytesSync(bytes, flush: true);
    } on LocalFileException {
      rethrow;
    } on FileSystemException catch (error) {
      throw mapMoveFileSystemException(error, fallbackPath: targetPath);
    }

    try {
      sourceFile.deleteSync();
    } on FileSystemException catch (error) {
      try {
        if (targetFile.existsSync()) {
          targetFile.deleteSync();
        }
      } on Object {
        // Keep original source deletion error as primary cause.
      }
      throw mapMoveFileSystemException(error, fallbackPath: sourcePath);
    }
  }

  /// Resolves the platform-appropriate user data directory for relative local file names.
  static String _defaultBaseDirectoryPath() {
    final environment = Platform.environment;
    final separator = Platform.pathSeparator;

    if (Platform.isWindows) {
      final appData = environment['APPDATA'] ?? environment['LOCALAPPDATA'];
      if (appData != null && appData.trim().isNotEmpty) {
        return '${_trimTrailingSeparators(appData.trim())}${separator}tiertask';
      }
      final userProfile = environment['USERPROFILE'];
      if (userProfile != null && userProfile.trim().isNotEmpty) {
        return '${_trimTrailingSeparators(userProfile.trim())}${separator}tiertask';
      }
    }

    final xdgDataHome = environment['XDG_DATA_HOME'];
    if (xdgDataHome != null && xdgDataHome.trim().isNotEmpty) {
      return '${_trimTrailingSeparators(xdgDataHome.trim())}${separator}tiertask';
    }

    final home = environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return '${_trimTrailingSeparators(home.trim())}$separator.local${separator}share${separator}tiertask';
    }

    return Directory.systemTemp.path;
  }

  /// Verifies that no file, directory, or symbolic link exists at [targetPath].
  void _ensureTargetDoesNotExist(
    String targetPath,
    AppLocalizations localizations,
  ) {
    final targetType = FileSystemEntity.typeSync(
      targetPath,
      followLinks: false,
    );
    switch (targetType) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.link:
        throw LocalFileException(
          localizations.errorMoveTargetSymlinkExists(targetPath),
        );
      case FileSystemEntityType.directory:
        throw LocalFileException(
          localizations.errorMoveTargetDirectoryExists(targetPath),
        );
      case FileSystemEntityType.file:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw LocalFileException(
          localizations.errorMoveTargetFileExists(targetPath),
        );
    }
  }

  /// Checks whether [value] contains ASCII control characters or null bytes.
  static bool _hasControlCharacters(String value) {
    for (var i = 0; i < value.length; i++) {
      final codeUnit = value.codeUnitAt(i);
      if (codeUnit < 0x20 || codeUnit == 0x7F) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` if [rawPath] starts with a POSIX root `/` or Windows drive prefix.
  static bool _isAbsolutePath(String rawPath) =>
      rawPath.startsWith('/') || _windowsDrivePattern.hasMatch(rawPath);

  /// Returns `true` when [error] indicates a cross-device link (`EXDEV` on Linux, `ERROR_NOT_SAME_DEVICE` on Windows).
  static bool _isCrossDeviceError(FileSystemException error) {
    final code = error.osError?.errorCode;
    return code == 18 || code == 17 && Platform.isWindows;
  }

  /// Fallback text matcher when `osError.errorCode` is not populated or uses a non-standard code.
  String _mapMoveErrorByText(
    FileSystemException error,
    String path,
    AppLocalizations localizations,
  ) {
    final rawOsMessage = error.osError?.message.trim() ?? '';
    final details = rawOsMessage.isNotEmpty
        ? '$rawOsMessage ($path)'
        : '${error.message} ($path)';
    final lower = details.toLowerCase();
    if (lower.contains('permission denied') ||
        lower.contains('access is denied') ||
        lower.contains('operation not permitted')) {
      return localizations.errorMovePermissionDenied(path);
    }
    if (lower.contains('read-only')) {
      return localizations.errorMoveReadOnlyFileSystem(path);
    }
    if (lower.contains('no space') || lower.contains('disk full')) {
      return localizations.errorMoveDiskFull(path);
    }
    return localizations.errorMoveLocalFileFailed(details);
  }

  /// Moves a `.tdf` entry inside [inMemoryStore] during hermetic widget tests.
  void _moveInMemoryEntry(
    String sourcePath,
    String targetPath,
    AppLocalizations localizations,
  ) {
    final store = inMemoryStore;
    if (store == null) {
      return;
    }
    if (store.containsKey(targetPath)) {
      throw LocalFileException(
        localizations.errorMoveTargetFileExists(targetPath),
      );
    }
    final existing = store.remove(sourcePath);
    if (existing != null) {
      store[targetPath] = existing;
    }
  }

  /// Moves [sourcePath] to [targetPath] via `File.renameSync` with cross-device copy-and-delete fallback.
  void _performFileMove(String sourcePath, String targetPath) {
    try {
      File(sourcePath).renameSync(targetPath);
    } on FileSystemException catch (error) {
      if (_isCrossDeviceError(error)) {
        _copyAndDeleteCrossDevice(sourcePath, targetPath);
        return;
      }
      throw mapMoveFileSystemException(error, fallbackPath: targetPath);
    }
  }

  /// Strips trailing `/` and `\` characters from [path].
  static String _trimTrailingSeparators(String path) {
    var end = path.length;
    while (end > 1 &&
        (path.codeUnitAt(end - 1) == 0x2F ||
            path.codeUnitAt(end - 1) == 0x5C)) {
      end--;
    }
    return path.substring(0, end);
  }

  /// Validates [rawPath] against traversal and control characters and returns normalized path segments.
  List<String> _validateAndSplitSegments(
    String rawPath,
    AppLocalizations localizations,
  ) {
    if (rawPath.isEmpty || _hasControlCharacters(rawPath)) {
      throw LocalFileException(localizations.errorInvalidLocalFilePath);
    }

    final rawSegments = rawPath.split(_pathSeparatorPattern);
    final segments = <String>[];
    for (final segment in rawSegments) {
      if (segment.isEmpty) {
        continue;
      }
      if (segment == '.' || segment == '..') {
        throw LocalFileException(localizations.errorInvalidLocalFilePath);
      }
      segments.add(segment);
    }

    if (segments.isEmpty) {
      throw LocalFileException(localizations.errorInvalidLocalFilePath);
    }
    return segments;
  }

  /// Verifies that [targetDirPath] exists and resolves to a directory rather than a file or broken link.
  void _validateTargetDirectory(
    String targetDirPath,
    AppLocalizations localizations,
  ) {
    final rawType = FileSystemEntity.typeSync(
      targetDirPath,
      followLinks: false,
    );
    if (rawType == FileSystemEntityType.notFound) {
      throw LocalFileException(
        localizations.errorMoveTargetDirectoryNotFound(targetDirPath),
      );
    }
    final resolvedType = FileSystemEntity.typeSync(
      targetDirPath,
      followLinks: true,
    );
    if (resolvedType != FileSystemEntityType.directory) {
      throw LocalFileException(
        localizations.errorMoveTargetNotADirectory(targetDirPath),
      );
    }
  }

  /// Verifies write access in [targetDirPath] when no `.tdf` file exists on disk yet.
  void _verifyDirectoryWritable(
    String targetDirPath,
    AppLocalizations localizations,
  ) {
    final separator = Platform.pathSeparator;
    final probePath =
        '$targetDirPath$separator.tiertask_write_probe_${DateTime.now().microsecondsSinceEpoch}';
    final probeType = FileSystemEntity.typeSync(probePath, followLinks: false);
    if (probeType != FileSystemEntityType.notFound) {
      return;
    }
    final probeFile = File(probePath);
    try {
      probeFile.writeAsBytesSync(const <int>[], flush: true);
      probeFile.deleteSync();
    } on FileSystemException catch (error) {
      throw mapMoveFileSystemException(error, fallbackPath: targetDirPath);
    }
  }
}
