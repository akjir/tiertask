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
import '../services/app_logger.dart';
import '../services/tdf_service.dart';

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

  /// Maximum numbered `.bak.NNN` suffix checked when creating a backup copy (`999`).
  static const int maxBackupSuffix = 999;

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

  /// Resolves the default filesystem path for `tiertask.log` inside [baseDirectoryPath] or the user data directory.
  static String defaultLogFilePath({String? baseDirectoryPath}) {
    final separator = Platform.pathSeparator;
    if (baseDirectoryPath case final explicitBase?
        when explicitBase.trim().isNotEmpty) {
      final cleanBase = _trimTrailingSeparators(explicitBase.trim());
      return '$cleanBase$separator${AppLogger.defaultLogFileName}';
    }
    final defaultBase = _trimTrailingSeparators(_defaultBaseDirectoryPath());
    return '$defaultBase$separator${AppLogger.defaultLogFileName}';
  }

  /// Synchronously deletes the diagnostic log file at [path] if it exists.
  static void deleteLogFileSync(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on FileSystemException {
      // Ignore deletion failures on missing or locked diagnostic files.
    }
  }

  /// Appends `.tdf` to [rawName] when it does not already end with `.tdf` (case-insensitive).
  static String ensureTdfExtension(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return WebDavConfig.defaultFileName;
    }
    if (trimmed.length > 4 &&
        trimmed.substring(trimmed.length - 4).toLowerCase() == '.tdf') {
      return trimmed;
    }
    return '$trimmed.tdf';
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

  /// Formats the candidate backup path or URI suffix for [basePath] at [attemptIndex].
  ///
  /// Returns `<basePath>.bak` for `attemptIndex == 0` and `<basePath>.bak.NNN`
  /// (zero-padded to 3 digits) for `attemptIndex >= 1`.
  static String formatBackupPath(String basePath, int attemptIndex) {
    if (attemptIndex <= 0) {
      return '$basePath.bak';
    }
    final suffix = attemptIndex.toString().padLeft(3, '0');
    return '$basePath.bak.$suffix';
  }

  /// Creates an empty `.tdf` document at [resolveFilePath] when the file does not exist yet, leaving existing files untouched.
  Future<void> initializeIfMissing() async {
    final localizations = _localizations;
    final filePath = resolveFilePath();
    const emptyContent = 'tdf ${TdfService.supportedVersion}\n';

    if (_useInMemoryFallback) {
      final store = inMemoryStore;
      if (store != null && !store.containsKey(filePath)) {
        store[filePath] = emptyContent;
        AppLogger.info(
          LogTag.storage,
          'LocalFileRepository.initializeIfMissing (in-memory) created path=$filePath',
        );
      }
      return;
    }

    final entityType = FileSystemEntity.typeSync(filePath, followLinks: false);
    if (entityType == FileSystemEntityType.directory) {
      throw LocalFileException(
        localizations.errorMoveSourceIsDirectory(filePath),
      );
    }
    if (entityType == FileSystemEntityType.link) {
      throw LocalFileException(
        localizations.errorMoveSourceIsSymlink(filePath),
      );
    }
    if (entityType == FileSystemEntityType.notFound) {
      await saveTdf(emptyContent);
      AppLogger.info(
        LogTag.storage,
        'LocalFileRepository.initializeIfMissing created path=$filePath',
      );
    }
  }

  /// Returns `true` when [rawName] is a valid single `.tdf` file name or base name without path separators or control characters.
  static bool isValidSingleFileName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty ||
        trimmed == '.' ||
        trimmed == '..' ||
        trimmed.toLowerCase() == '.tdf' ||
        trimmed.contains('/') ||
        trimmed.contains(r'\') ||
        _hasControlCharacters(trimmed)) {
      return false;
    }
    return true;
  }

  /// Returns the sorted list of `.tdf` file names present in [resolveDirectoryPath].
  List<String> listTdfFileNamesInDirectory() {
    final dirPath = tryResolveDirectoryPath();
    if (dirPath == null) {
      return const <String>[];
    }
    if (_useInMemoryFallback) {
      return _listInMemoryTdfFileNames(dirPath);
    }
    try {
      final directory = Directory(dirPath);
      if (!directory.existsSync()) {
        return const <String>[];
      }
      final names = <String>[];
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is File) {
          final name = extractFileNameFromPath(entity.path);
          if (name.length > 4 &&
              name.substring(name.length - 4).toLowerCase() == '.tdf') {
            names.add(name);
          }
        }
      }
      names.sort();
      return List<String>.unmodifiable(names);
    } on FileSystemException {
      return const <String>[];
    }
  }

  /// Reads the local `.tdf` file and returns its contents, or an empty string if the file does not exist.
  Future<String> loadTdf() async {
    final stopwatch = Stopwatch()..start();
    final localizations = _localizations;
    final filePath = resolveFilePath();

    if (_useInMemoryFallback) {
      final content = inMemoryStore?[filePath] ?? '';
      AppLogger.info(
        LogTag.storage,
        'LocalFileRepository.loadTdf (in-memory) path=$filePath bytes=${content.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return content;
    }

    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        AppLogger.info(
          LogTag.storage,
          'LocalFileRepository.loadTdf file not found path=$filePath elapsed=${stopwatch.elapsedMilliseconds}ms',
        );
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
      final decoded = utf8.decode(bytes);
      AppLogger.info(
        LogTag.storage,
        'LocalFileRepository.loadTdf path=$filePath bytes=${bytes.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return decoded;
    } on LocalFileException catch (error) {
      AppLogger.error(
        LogTag.storage,
        'LocalFileRepository.loadTdf failed path=$filePath: $error',
      );
      rethrow;
    } on FileSystemException catch (error) {
      AppLogger.error(
        LogTag.storage,
        'LocalFileRepository.loadTdf filesystem error path=$filePath: ${error.message}',
      );
      throw LocalFileException(
        localizations.errorLoadLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.error(
        LogTag.storage,
        'LocalFileRepository.loadTdf unexpected error path=$filePath: $error',
      );
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
    AppLogger.info(
      LogTag.storage,
      'LocalFileRepository.moveTdfFile moved $sourcePath -> $targetPath',
    );
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

  /// Opens the native desktop file selection/creation dialog and returns the normalized `.tdf` path, or `null` if cancelled.
  Future<String?> pickTdfFile({
    String? initialDirectory,
    String? currentFileName,
  }) async {
    try {
      final selected = await directoryPickerChannel.invokeMethod<String>(
        'pickFile',
        <String, Object?>{
          'initialDirectory': initialDirectory,
          'currentFileName': currentFileName,
        },
      );
      if (selected == null || selected.trim().isEmpty) {
        return null;
      }
      return ensureTdfExtension(_trimTrailingSeparators(selected.trim()));
    } on PlatformException catch (error) {
      throw LocalFileException(
        _localizations.errorMoveLocalFileFailed(error.message ?? error.code),
        cause: error,
      );
    } on MissingPluginException {
      return null;
    }
  }

  /// Synchronously reads up to [maxBytes] from the diagnostic log file at [path].
  static String readLogFileSync(String path, {required int maxBytes}) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return '';
      }
      final bytes = file.readAsBytesSync();
      if (bytes.isEmpty) {
        return '';
      }
      final slice = bytes.length > maxBytes
          ? bytes.sublist(bytes.length - maxBytes)
          : bytes;
      return utf8.decode(slice, allowMalformed: true);
    } on FileSystemException {
      return '';
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
    final stopwatch = Stopwatch()..start();
    final localizations = _localizations;
    final filePath = resolveFilePath();
    final bytes = utf8.encode(tdfContent);
    if (bytes.length > maxFileBytes) {
      AppLogger.error(
        LogTag.storage,
        'LocalFileRepository.saveTdf failed (exceeds maxFileBytes) path=$filePath bytes=${bytes.length}',
      );
      throw LocalFileException(localizations.errorLocalFileTooLarge);
    }

    if (_useInMemoryFallback) {
      inMemoryStore?[filePath] = tdfContent;
      AppLogger.info(
        LogTag.storage,
        'LocalFileRepository.saveTdf (in-memory) path=$filePath bytes=${bytes.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return;
    }

    try {
      final file = File(filePath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes, flush: true);
      AppLogger.info(
        LogTag.storage,
        'LocalFileRepository.saveTdf path=$filePath bytes=${bytes.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
    } on LocalFileException catch (error) {
      AppLogger.error(
        LogTag.storage,
        'LocalFileRepository.saveTdf failed path=$filePath: $error',
      );
      rethrow;
    } on FileSystemException catch (error) {
      AppLogger.error(
        LogTag.storage,
        'LocalFileRepository.saveTdf filesystem error path=$filePath: ${error.message}',
      );
      throw LocalFileException(
        localizations.errorSaveLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.error(
        LogTag.storage,
        'LocalFileRepository.saveTdf unexpected error path=$filePath: $error',
      );
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

  /// Empties and re-initializes the local `.tdf` file as a blank TDF document, optionally creating a `.bak` or `.bak.001`+ backup first if the file exists.
  Future<void> wipeTdf({bool createBackup = false}) async {
    final stopwatch = Stopwatch()..start();
    final localizations = _localizations;
    final filePath = resolveFilePath();
    const emptyContent = 'tdf ${TdfService.supportedVersion}\n';

    if (_useInMemoryFallback) {
      _wipeInMemoryEntry(filePath, emptyContent, createBackup: createBackup);
      AppLogger.info(
        LogTag.storage,
        'LocalFileRepository.wipeTdf (in-memory) path=$filePath backup=$createBackup elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return;
    }

    try {
      final sourceType = FileSystemEntity.typeSync(
        filePath,
        followLinks: false,
      );
      if (sourceType == FileSystemEntityType.directory) {
        throw LocalFileException(
          localizations.errorMoveSourceIsDirectory(filePath),
        );
      }
      if (sourceType == FileSystemEntityType.link) {
        throw LocalFileException(
          localizations.errorMoveSourceIsSymlink(filePath),
        );
      }
      final file = File(filePath);
      if (sourceType != FileSystemEntityType.notFound && createBackup) {
        final backupPath = _resolveNextLocalBackupPath(filePath, localizations);
        file.copySync(backupPath);
        AppLogger.info(
          LogTag.storage,
          'LocalFileRepository.wipeTdf created backup $backupPath',
        );
      }
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(utf8.encode(emptyContent), flush: true);
      AppLogger.info(
        LogTag.storage,
        'LocalFileRepository.wipeTdf path=$filePath backup=$createBackup elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
    } on LocalFileException catch (error) {
      AppLogger.error(
        LogTag.storage,
        'LocalFileRepository.wipeTdf failed path=$filePath: $error',
      );
      rethrow;
    } on FileSystemException catch (error) {
      AppLogger.error(
        LogTag.storage,
        'LocalFileRepository.wipeTdf filesystem error path=$filePath: ${error.message}',
      );
      throw LocalFileException(
        localizations.errorSaveLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.error(
        LogTag.storage,
        'LocalFileRepository.wipeTdf unexpected error path=$filePath: $error',
      );
      throw LocalFileException(
        localizations.errorSaveLocalFileFailed(error.toString()),
        cause: error,
      );
    }
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

  /// Lists sorted `.tdf` file names stored under [dirPath] in [inMemoryStore].
  List<String> _listInMemoryTdfFileNames(String dirPath) {
    final store = inMemoryStore;
    if (store == null) {
      return const <String>[];
    }
    final prefix = '$dirPath${Platform.pathSeparator}';
    final names = <String>{};
    for (final key in store.keys) {
      if (key.startsWith(prefix)) {
        final rest = key.substring(prefix.length);
        if (!rest.contains(Platform.pathSeparator) &&
            rest.length > 4 &&
            rest.substring(rest.length - 4).toLowerCase() == '.tdf') {
          names.add(rest);
        }
      }
    }
    final sorted = names.toList()..sort();
    return List<String>.unmodifiable(sorted);
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

  /// Resolves the first available `<filePath>.bak` or `<filePath>.bak.NNN` backup path on disk.
  String _resolveNextLocalBackupPath(
    String filePath,
    AppLocalizations localizations,
  ) {
    for (var attempt = 0; attempt <= maxBackupSuffix; attempt++) {
      final candidate = formatBackupPath(filePath, attempt);
      if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return candidate;
      }
    }
    throw LocalFileException(
      localizations.errorSaveLocalFileFailed('Maximum backup files reached'),
    );
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

  /// Wipes [filePath] in [inMemoryStore] during hermetic widget tests, creating a `.bak` or `.bak.NNN` copy when [createBackup] is `true`.
  void _wipeInMemoryEntry(
    String filePath,
    String emptyContent, {
    required bool createBackup,
  }) {
    final store = inMemoryStore;
    if (store == null) {
      return;
    }
    if (createBackup && store.containsKey(filePath)) {
      final existing = store[filePath] ?? '';
      for (var attempt = 0; attempt <= maxBackupSuffix; attempt++) {
        final candidate = formatBackupPath(filePath, attempt);
        if (!store.containsKey(candidate)) {
          store[candidate] = existing;
          break;
        }
      }
    }
    store[filePath] = emptyContent;
  }
}
