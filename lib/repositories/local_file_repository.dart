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
import 'local_file_operations.dart';

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

/// Repository-layer [AppLogSink] implementation backed by [LocalFileRepository] static log helpers.
class LocalFileLogSink implements AppLogSink {
  /// Creates a const [LocalFileLogSink].
  const LocalFileLogSink();

  @override
  String defaultLogFilePath({String? baseDirectoryPath}) =>
      LocalFileRepository.defaultLogFilePath(
        baseDirectoryPath: baseDirectoryPath,
      );

  @override
  void deleteLogFileSync(String path) =>
      LocalFileRepository.deleteLogFileSync(path);

  @override
  String readLogFileSync(String path, {required int maxBytes}) =>
      LocalFileRepository.readLogFileSync(path, maxBytes: maxBytes);

  @override
  void writeLogFileSync(String path, String content, {required bool append}) =>
      LocalFileRepository.writeLogFileSync(path, content, append: append);
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
  static const int maxBackupSuffix = LocalFileOperations.maxBackupSuffix;

  static const LocalFileOperations<LocalFileException> _operations =
      LocalFileOperations<LocalFileException>(LocalFileException.new);

  /// Optional base directory path where relative local file names are stored.
  final String? baseDirectoryPath;

  /// Active configuration containing the local file name or path and locale setting.
  final WebDavConfig config;

  /// Optional in-memory store used during hermetic widget tests.
  final Map<String, String>? inMemoryStore;

  /// Maximum allowed file size in bytes before rejecting a read or write.
  final int maxFileBytes;

  /// Resolves the active [AppLocalizations] instance for error messages.
  AppLocalizations get _messages => lookupAppLocalizations(
    config.language.resolveLocale(PlatformDispatcher.instance.locale),
  );

  /// Whether to use the isolated in-memory store during hermetic widget tests.
  bool get _useInMemoryFallback =>
      baseDirectoryPath == null &&
      !_operations.isAbsolutePath(config.localFilePath.trim()) &&
      inMemoryStore != null &&
      Platform.environment.containsKey('FLUTTER_TEST');

  /// Combines [directoryPath] and [fileName] into a normalized local `.tdf` file path.
  static String combineDirectoryAndFileName(
    String directoryPath,
    String fileName,
  ) => _operations.combineDirectoryAndFileName(directoryPath, fileName);

  /// Resolves the default filesystem path for `tiertask.log` inside [baseDirectoryPath] or the user data directory.
  static String defaultLogFilePath({String? baseDirectoryPath}) =>
      _operations.defaultLogFilePath(baseDirectoryPath: baseDirectoryPath);

  /// Synchronously deletes the diagnostic log file at [path] if it exists.
  static void deleteLogFileSync(String path) =>
      _operations.deleteLogFileSync(path);

  /// Deletes the configured local `.tdf` file if it exists, rejecting directories and symbolic links.
  Future<void> deleteTdf() async => _operations.deleteTdf(
    resolveFilePath(),
    _messages,
    inMemory: _useInMemoryFallback,
    inMemoryStore: inMemoryStore,
  );

  /// Appends `.tdf` to [rawName] when it does not already end with `.tdf` (case-insensitive).
  static String ensureTdfExtension(String rawName) =>
      _operations.ensureTdfExtension(rawName);

  /// Extracts the parent directory portion from [rawPath], or an empty string when [rawPath] is a bare file name.
  static String extractDirectoryFromPath(String rawPath) =>
      _operations.extractDirectoryFromPath(rawPath);

  /// Extracts the base file name without a trailing `.tdf` extension from [rawPath].
  static String extractFileBaseName(String rawPath) =>
      _operations.extractFileBaseName(rawPath);

  /// Extracts the trailing `.tdf` file name segment from [config.localFilePath].
  String extractFileName() => extractFileNameFromPath(config.localFilePath);

  /// Extracts the trailing file name segment from [rawPath], defaulting to [WebDavConfig.defaultFileName].
  static String extractFileNameFromPath(String rawPath) =>
      _operations.extractFileNameFromPath(rawPath);

  /// Returns `true` when the resolved local `.tdf` file exists on disk or in [inMemoryStore].
  bool fileExists() {
    final filePath = resolveFilePath();
    return _useInMemoryFallback
        ? (inMemoryStore?.containsKey(filePath) ?? false)
        : File(filePath).existsSync();
  }

  /// Formats the candidate backup path or URI suffix for [basePath] at [attemptIndex].
  static String formatBackupPath(String basePath, int attemptIndex) =>
      _operations.formatBackupPath(basePath, attemptIndex);

  /// Creates an empty `.tdf` document at [resolveFilePath] when the file does not exist yet, leaving existing files untouched.
  Future<void> initializeIfMissing() async {
    final messages = _messages;
    final filePath = resolveFilePath();
    const emptyContent = 'tdf ${TdfService.supportedVersion}\n';
    if (_useInMemoryFallback) {
      inMemoryStore?.putIfAbsent(filePath, () => emptyContent);
      return;
    }
    final entityType = FileSystemEntity.typeSync(filePath, followLinks: false);
    if (entityType == FileSystemEntityType.directory) {
      throw LocalFileException(messages.errorMoveSourceIsDirectory(filePath));
    }
    if (entityType == FileSystemEntityType.link) {
      throw LocalFileException(messages.errorMoveSourceIsSymlink(filePath));
    }
    if (entityType == FileSystemEntityType.notFound) {
      await saveTdf(emptyContent);
      AppLogger.info(LogTag.storage, 'initializeIfMissing created $filePath');
    }
  }

  /// Alias for [initializeIfMissing] that creates an empty `.tdf` document when the file does not exist yet.
  Future<void> initializeTdfIfNeeded() => initializeIfMissing();

  /// Returns `true` when [rawName] is a valid single `.tdf` file name or base name without path separators or control characters.
  static bool isValidSingleFileName(String rawName) =>
      _operations.isValidSingleFileName(rawName);

  /// Returns the sorted list of `.tdf` file names present in [resolveDirectoryPath].
  List<String> listTdfFileNamesInDirectory() {
    final dirPath = tryResolveDirectoryPath();
    if (dirPath == null) return const <String>[];
    if (_useInMemoryFallback) return _listInMemoryTdfFileNames(dirPath);
    try {
      final directory = Directory(dirPath);
      if (!directory.existsSync()) return const <String>[];
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
    final messages = _messages;
    final filePath = resolveFilePath();
    if (_useInMemoryFallback) {
      final content = inMemoryStore?[filePath] ?? '';
      AppLogger.info(
        LogTag.storage,
        'loadTdf (mem) $filePath bytes=${content.length} ${stopwatch.elapsedMilliseconds}ms',
      );
      return content;
    }
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        AppLogger.info(LogTag.storage, 'loadTdf missing $filePath');
        return '';
      }
      if (file.lengthSync() > maxFileBytes) {
        throw LocalFileException(messages.errorLocalFileTooLarge);
      }
      final bytes = file.readAsBytesSync();
      if (bytes.length > maxFileBytes) {
        throw LocalFileException(messages.errorLocalFileTooLarge);
      }
      final decoded = utf8.decode(bytes);
      AppLogger.info(
        LogTag.storage,
        'loadTdf $filePath bytes=${bytes.length} ${stopwatch.elapsedMilliseconds}ms',
      );
      return decoded;
    } on LocalFileException catch (error) {
      AppLogger.error(LogTag.storage, 'loadTdf failed $filePath: $error');
      rethrow;
    } on FileSystemException catch (error) {
      AppLogger.error(LogTag.storage, 'loadTdf fs error $filePath: $error');
      throw LocalFileException(
        messages.errorLoadLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.error(LogTag.storage, 'loadTdf error $filePath: $error');
      throw LocalFileException(
        messages.errorLoadLocalFileFailed(error.toString()),
        cause: error,
      );
    }
  }

  /// Maps a [FileSystemException] during a `.tdf` file move into a specific localized [LocalFileException].
  LocalFileException mapMoveFileSystemException(
    FileSystemException error, {
    required String fallbackPath,
  }) => _operations.mapMoveFileSystemException(error, fallbackPath, _messages);

  /// Safely moves the local `.tdf` file to [targetRepository]'s resolved path without overwriting existing entities.
  Future<void> moveTdfFile(LocalFileRepository targetRepository) async {
    _operations.moveTdfFile(
      resolveFilePath(),
      targetRepository.resolveFilePath(),
      targetRepository.resolveDirectoryPath(),
      maxFileBytes,
      _messages,
      inMemory: _useInMemoryFallback && targetRepository._useInMemoryFallback,
      inMemoryStore: inMemoryStore,
    );
  }

  /// Opens the native desktop directory selection dialog and returns the chosen path, or `null` if cancelled.
  Future<String?> pickDirectory({String? initialDirectory}) async {
    try {
      final selected = await directoryPickerChannel.invokeMethod<String>(
        'pickDirectory',
        <String, Object?>{'initialDirectory': initialDirectory},
      );
      if (selected == null || selected.trim().isEmpty) return null;
      return _operations.trimTrailingSeparators(selected.trim());
    } on PlatformException catch (error) {
      throw LocalFileException(
        _messages.errorMoveLocalFileFailed(error.message ?? error.code),
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
      if (selected == null || selected.trim().isEmpty) return null;
      return ensureTdfExtension(
        _operations.trimTrailingSeparators(selected.trim()),
      );
    } on PlatformException catch (error) {
      throw LocalFileException(
        _messages.errorMoveLocalFileFailed(error.message ?? error.code),
        cause: error,
      );
    } on MissingPluginException {
      return null;
    }
  }

  /// Synchronously reads up to [maxBytes] from the diagnostic log file at [path].
  static String readLogFileSync(String path, {required int maxBytes}) =>
      _operations.readLogFileSync(path, maxBytes: maxBytes);

  /// Renames the local `.tdf` file to [newFileName] inside its current directory and returns the new resolved path.
  Future<String> renameTdf(String newFileName) async => _operations.renameTdf(
    resolveFilePath(),
    resolveDirectoryPath(),
    newFileName,
    maxFileBytes,
    _messages,
    inMemory: _useInMemoryFallback,
    inMemoryStore: inMemoryStore,
  );

  /// Resolves the platform-appropriate user data directory for relative local file names.
  static String resolveDefaultDirectoryPath() =>
      _operations.resolveDefaultDirectoryPath();

  /// Resolves the parent directory path of [resolveFilePath].
  String resolveDirectoryPath() =>
      _operations.resolveDirectoryPath(resolveFilePath());

  /// Validates and resolves the target local file path, throwing [LocalFileException] if invalid.
  String resolveFilePath() => _operations.resolveFilePath(
    config.localFilePath,
    baseDirectoryPath,
    _messages,
  );

  /// Writes [tdfContent] to the configured local `.tdf` file.
  Future<void> saveTdf(String tdfContent) async {
    final stopwatch = Stopwatch()..start();
    final messages = _messages;
    final filePath = resolveFilePath();
    final bytes = utf8.encode(tdfContent);
    if (bytes.length > maxFileBytes) {
      AppLogger.error(LogTag.storage, 'saveTdf oversized $filePath');
      throw LocalFileException(messages.errorLocalFileTooLarge);
    }
    if (_useInMemoryFallback) {
      inMemoryStore?[filePath] = tdfContent;
      AppLogger.info(
        LogTag.storage,
        'saveTdf (mem) $filePath bytes=${bytes.length} ${stopwatch.elapsedMilliseconds}ms',
      );
      return;
    }
    try {
      final file = File(filePath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes, flush: true);
      AppLogger.info(
        LogTag.storage,
        'saveTdf $filePath bytes=${bytes.length} ${stopwatch.elapsedMilliseconds}ms',
      );
    } on LocalFileException catch (error) {
      AppLogger.error(LogTag.storage, 'saveTdf failed $filePath: $error');
      rethrow;
    } on FileSystemException catch (error) {
      AppLogger.error(LogTag.storage, 'saveTdf fs error $filePath: $error');
      throw LocalFileException(
        messages.errorSaveLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.error(LogTag.storage, 'saveTdf error $filePath: $error');
      throw LocalFileException(
        messages.errorSaveLocalFileFailed(error.toString()),
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

  /// Validates that [rawName] is a single `.tdf` file name and returns it with a `.tdf` extension.
  static String validateFileName(
    String rawName, {
    AppLocalizations? localizations,
  }) => _operations.validateFileName(
    rawName,
    localizations ??
        lookupAppLocalizations(
          AppLanguage.english.resolveLocale(PlatformDispatcher.instance.locale),
        ),
  );

  /// Validates [rawPath] against traversal and control characters and returns the normalized path string.
  static String validateRelativeOrAbsolutePath(
    String rawPath, {
    AppLocalizations? localizations,
  }) => _operations.validateRelativeOrAbsolutePath(
    rawPath,
    localizations ??
        lookupAppLocalizations(
          AppLanguage.english.resolveLocale(PlatformDispatcher.instance.locale),
        ),
  );

  /// Empties and re-initializes the local `.tdf` file as a blank TDF document, optionally creating a `.bak` or `.bak.001`+ backup first if the file exists.
  Future<void> wipeTdf({bool createBackup = false}) async {
    final stopwatch = Stopwatch()..start();
    final messages = _messages;
    final filePath = resolveFilePath();
    const emptyContent = 'tdf ${TdfService.supportedVersion}\n';
    if (_useInMemoryFallback) {
      _wipeInMemoryEntry(filePath, emptyContent, createBackup: createBackup);
      return;
    }
    try {
      final sourceType = FileSystemEntity.typeSync(
        filePath,
        followLinks: false,
      );
      if (sourceType == FileSystemEntityType.directory) {
        throw LocalFileException(messages.errorMoveSourceIsDirectory(filePath));
      }
      if (sourceType == FileSystemEntityType.link) {
        throw LocalFileException(messages.errorMoveSourceIsSymlink(filePath));
      }
      final file = File(filePath);
      if (sourceType != FileSystemEntityType.notFound && createBackup) {
        final backupPath = _operations.resolveNextLocalBackupPath(
          filePath,
          messages,
        );
        file.copySync(backupPath);
        AppLogger.info(LogTag.storage, 'wipeTdf created backup $backupPath');
      }
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(utf8.encode(emptyContent), flush: true);
      AppLogger.info(
        LogTag.storage,
        'wipeTdf $filePath backup=$createBackup ${stopwatch.elapsedMilliseconds}ms',
      );
    } on LocalFileException catch (error) {
      AppLogger.error(LogTag.storage, 'wipeTdf failed $filePath: $error');
      rethrow;
    } on FileSystemException catch (error) {
      AppLogger.error(LogTag.storage, 'wipeTdf fs error $filePath: $error');
      throw LocalFileException(
        messages.errorSaveLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.error(LogTag.storage, 'wipeTdf error $filePath: $error');
      throw LocalFileException(
        messages.errorSaveLocalFileFailed(error.toString()),
        cause: error,
      );
    }
  }

  /// Synchronously writes or appends [content] to the diagnostic log file at [path] with `flush: true`.
  static void writeLogFileSync(
    String path,
    String content, {
    required bool append,
  }) => _operations.writeLogFileSync(path, content, append: append);

  /// Lists sorted `.tdf` file names stored under [dirPath] in [inMemoryStore].
  List<String> _listInMemoryTdfFileNames(String dirPath) {
    final store = inMemoryStore;
    if (store == null) return const <String>[];
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

  /// Wipes [filePath] in [inMemoryStore] during hermetic widget tests, creating a `.bak` or `.bak.NNN` copy when [createBackup] is `true`.
  void _wipeInMemoryEntry(
    String filePath,
    String emptyContent, {
    required bool createBackup,
  }) {
    final store = inMemoryStore;
    if (store == null) return;
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
