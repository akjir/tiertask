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
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/app_build_profile.dart';
import '../models/webdav_config.dart';
import '../services/app_logger.dart';
import '../services/sha256_service.dart';
import '../services/tdf_service.dart';
import 'host_file_lock.dart';
import 'local_file_operations.dart';

/// Custom domain exception thrown when local TDF file operations fail.
class LocalFileException implements Exception {
  /// Creates a [LocalFileException] with a localized [message] and optional [cause].
  const LocalFileException(this.message, {this.cause});

  /// Underlying exception cause when available.
  final Object? cause;

  /// Human-readable error message.
  final String message;

  /// Whether [cause] is an operating-system [FileSystemException] eligible for a transient watch read retry.
  bool get isTransientFileSystemError => cause is FileSystemException;

  @override
  String toString() => message;
}

/// Repository-layer [AppLogSink] implementation backed by [LocalFileRepository] static log helpers.
class LocalFileLogSink implements AppLogSink {
  /// Creates a const [LocalFileLogSink] with an optional [buildProfile].
  const LocalFileLogSink({this.buildProfile});

  /// Optional build storage profile overriding [AppBuildProfile.current].
  final AppBuildProfile? buildProfile;

  @override
  String defaultLogFilePath({String? baseDirectoryPath, String? fileName}) =>
      LocalFileRepository.defaultLogFilePath(
        baseDirectoryPath: baseDirectoryPath,
        fileName: fileName,
        buildProfile: buildProfile,
      );

  @override
  void deleteLogFileSync(String path) =>
      LocalFileRepository.deleteLogFileSync(path);

  @override
  int deleteWorkspaceLogFilesSync({
    required String directoryPath,
    required String platform,
    required String workspaceId,
  }) => LocalFileRepository.deleteWorkspaceLogFilesSync(
    directoryPath: directoryPath,
    platform: platform,
    workspaceId: workspaceId,
  );

  @override
  int pruneExpiredLogFilesSync({
    required String directoryPath,
    required String platform,
    required String workspaceId,
    required DateTime utcNow,
    int maxRetainedDays = AppLogger.maxRetainedLogDays,
    int maxRetainedFiles = AppLogger.maxRetainedLogFiles,
  }) => LocalFileRepository.pruneExpiredLogFilesSync(
    directoryPath: directoryPath,
    platform: platform,
    workspaceId: workspaceId,
    utcNow: utcNow,
    maxRetainedDays: maxRetainedDays,
    maxRetainedFiles: maxRetainedFiles,
  );

  @override
  String readLogFileSync(String path, {required int maxBytes}) =>
      LocalFileRepository.readLogFileSync(path, maxBytes: maxBytes);

  @override
  void writeLogFileSync(
    String path,
    String content, {
    required bool append,
    bool flush = false,
  }) => LocalFileRepository.writeLogFileSync(
    path,
    content,
    append: append,
    flush: flush,
  );
}

/// Repository for reading, writing, and locking the task board `.tdf` file on the local filesystem.
class LocalFileRepository {
  /// Creates a [LocalFileRepository] for [config].
  LocalFileRepository({
    required this.config,
    this.baseDirectoryPath,
    this.buildProfile,
    this.hostLockDirectoryOverride,
    this.inMemoryStore,
    this.lockAcquireTimeout = HostFileLockManager.defaultLockAcquireTimeout,
    this.maxFileBytes = defaultMaxFileBytes,
    this._androidFilesDirectoryResolver,
    this._languageResolver,
    @visibleForTesting this._legacyAndroidCacheDirectoryOverride,
  }) : _lockManager = HostFileLockManager<LocalFileException>(
         createException: LocalFileException.new,
         hostLockDirectoryOverride: hostLockDirectoryOverride,
         lockAcquireTimeout: lockAcquireTimeout,
       );

  /// Platform channel resolving persistent Android `Context.filesDir`.
  static const MethodChannel androidStorageChannel = MethodChannel(
    'de.akjir.tiertask/app_storage',
  );

  /// Default maximum allowed TDF file size in bytes (1 MiB).
  static const int defaultMaxFileBytes = 1048576;

  /// Platform channel for invoking the native Linux and Windows directory chooser dialog.
  static const MethodChannel directoryPickerChannel = MethodChannel(
    'de.akjir.tiertask/directory_picker',
  );

  /// Maximum numbered `.bak.NNN` suffix checked when creating a backup copy (`999`).
  static const int maxBackupSuffix = LocalFileOperations.maxBackupSuffix;

  static String? _cachedAndroidFilesDirectory;
  static const LocalFileOperations<LocalFileException> _operations =
      LocalFileOperations<LocalFileException>(LocalFileException.new);

  /// Optional base directory path where relative local file names are stored.
  final String? baseDirectoryPath;

  /// Optional build storage profile overriding [AppBuildProfile.current].
  final AppBuildProfile? buildProfile;

  /// Active configuration containing the local file name or path and locale setting.
  final WebDavConfig config;

  /// Optional host lock directory override used for hermetic filesystem tests.
  final String? hostLockDirectoryOverride;

  /// Optional in-memory store used during hermetic widget tests.
  final Map<String, String>? inMemoryStore;

  /// Maximum duration to wait when acquiring the exclusive host file lock.
  final Duration lockAcquireTimeout;

  /// Maximum allowed file size in bytes before rejecting a read or write.
  final int maxFileBytes;

  final Future<String?> Function()? _androidFilesDirectoryResolver;
  bool _androidMigrationChecked = false;
  final AppLanguage Function()? _languageResolver;
  final String? _legacyAndroidCacheDirectoryOverride;
  final HostFileLockManager<LocalFileException> _lockManager;
  String? _resolvedAndroidFilesDirectory;

  /// Whether parent-directory observation is supported for this repository instance (`false` on Android and in-memory test stores).
  bool get canWatchDirectory =>
      !_useInMemoryFallback &&
      !_isAndroidHost &&
      FileSystemEntity.isWatchSupported;

  /// Host operating system version string reported by the Dart VM.
  static String get hostOsVersion => Platform.operatingSystemVersion;

  /// Host operating system identifier (`linux`, `android`, `windows`) reported by the Dart VM.
  static String get hostPlatform => Platform.operatingSystem;

  /// Exposes the memoized [HostFileLockManager] instance for unit test verification.
  @visibleForTesting
  HostFileLockManager<LocalFileException> get lockManagerForTesting =>
      _lockManager;

  /// Cached Android `Context.filesDir` path applicable to this repository instance, if resolved.
  String? get _effectiveAndroidFilesDirectory =>
      _resolvedAndroidFilesDirectory ?? _cachedAndroidFilesDirectory;

  /// Whether this repository targets the sandboxed Android host platform.
  bool get _isAndroidHost =>
      Platform.isAndroid || _androidFilesDirectoryResolver != null;

  /// Resolves the active [AppLocalizations] instance for error messages.
  AppLocalizations get _messages {
    final effectiveLanguage = _languageResolver?.call() ?? config.language;
    return lookupAppLocalizations(
      effectiveLanguage.resolveLocale(PlatformDispatcher.instance.locale),
    );
  }

  /// Whether to use the isolated in-memory store during hermetic widget tests.
  bool get _useInMemoryFallback =>
      baseDirectoryPath == null &&
      !_operations.isAbsolutePath(config.localFilePath.trim()) &&
      inMemoryStore != null &&
      Platform.environment.containsKey('FLUTTER_TEST');

  /// Whether relative path resolution must use persistent Android `Context.filesDir`.
  bool get _usesAndroidFilesDirectory =>
      !_useInMemoryFallback &&
      baseDirectoryPath == null &&
      !_operations.isAbsolutePath(config.localFilePath.trim()) &&
      _isAndroidHost;

  /// Records [directoryPath] as the process-wide cached Android `Context.filesDir`.
  static void cacheAndroidFilesDirectory(String? directoryPath) {
    final trimmed = directoryPath?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      _cachedAndroidFilesDirectory = trimmed;
    }
  }

  /// Combines [directoryPath] and [fileName] into a normalized local `.tdf` file path.
  static String combineDirectoryAndFileName(
    String directoryPath,
    String fileName,
  ) => _operations.combineDirectoryAndFileName(directoryPath, fileName);

  /// Resolves the default filesystem path for [fileName] (or `tiertask.log`) inside [baseDirectoryPath] or the user data directory.
  static String defaultLogFilePath({
    String? baseDirectoryPath,
    String? fileName,
    AppBuildProfile? buildProfile,
    String? androidFilesDirectoryPath,
  }) => _operations.defaultLogFilePath(
    baseDirectoryPath: baseDirectoryPath,
    fileName: fileName,
    buildProfile: buildProfile,
    androidFilesDirectoryPath:
        androidFilesDirectoryPath ?? _cachedAndroidFilesDirectory,
  );

  /// Synchronously deletes the diagnostic log file at [path] if it exists.
  static void deleteLogFileSync(String path) =>
      _operations.deleteLogFileSync(path);

  /// Deletes the configured local `.tdf` file under the exclusive host lock if it exists, rejecting directories and symbolic links.
  Future<void> deleteTdf() async {
    final messages = _messages;
    final filePath = await _resolveFilePathAsync(migrateLegacy: true);
    await _lockManager.withExclusiveLock(filePath, () async {
      _operations.deleteTdf(
        filePath,
        messages,
        inMemory: _useInMemoryFallback,
        inMemoryStore: inMemoryStore,
      );
    }, inMemoryOnly: _useInMemoryFallback);
  }

  /// Deletes all dated and legacy diagnostic log files for [workspaceId] in [directoryPath].
  static int deleteWorkspaceLogFilesSync({
    required String directoryPath,
    required String platform,
    required String workspaceId,
  }) => _operations.deleteWorkspaceLogFilesSync(
    directoryPath: directoryPath,
    platform: platform,
    workspaceId: workspaceId,
  );

  /// Returns `true` when the resolved parent directory exists on disk or in memory, or `false` if invalid or missing.
  bool directoryExists() {
    final directoryPath = tryResolveDirectoryPath();
    if (directoryPath == null) {
      return false;
    }
    return _operations.directoryExists(
      directoryPath,
      inMemory: _useInMemoryFallback,
    );
  }

  /// Resolves and caches the persistent Android `Context.filesDir` via platform channel or injected [resolver].
  static Future<String?> ensureAndroidFilesDirectoryInitialized({
    Future<String?> Function()? resolver,
  }) async {
    if (resolver == null) {
      if (_cachedAndroidFilesDirectory case final cached?) {
        return cached;
      }
      if (!Platform.isAndroid) {
        return null;
      }
    }
    final activeResolver = resolver ?? _invokeAndroidFilesDirectoryChannel;
    final resolved = await activeResolver();
    final trimmed = resolved?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    _cachedAndroidFilesDirectory = trimmed;
    return trimmed;
  }

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
    final filePath = await _resolveFilePathAsync(migrateLegacy: true);
    const emptyContent = 'tdf ${TdfService.supportedVersion}\n';
    await _lockManager.withExclusiveLock(filePath, () async {
      if (_useInMemoryFallback) {
        inMemoryStore?.putIfAbsent(filePath, () => emptyContent);
        return;
      }
      switch (FileSystemEntity.typeSync(filePath, followLinks: false)) {
        case FileSystemEntityType.directory:
          throw LocalFileException(
            messages.errorMoveSourceIsDirectory(filePath),
          );
        case FileSystemEntityType.link:
          throw LocalFileException(messages.errorMoveSourceIsSymlink(filePath));
        case FileSystemEntityType.pipe:
        case FileSystemEntityType.unixDomainSock:
          throw LocalFileException(
            messages.errorMovePermissionDenied(filePath),
          );
        case FileSystemEntityType.file:
          return;
        case FileSystemEntityType.notFound:
          await saveTdf(emptyContent);
          AppLogger.event(
            LogLevel.info,
            LogTag.storage,
            'local.save',
            fields: <String, Object?>{'path': filePath, 'initialized': true},
          );
      }
    }, inMemoryOnly: _useInMemoryFallback);
  }

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
    final snapshot = await _readTdfSnapshot(computeDigest: false);
    return snapshot.content;
  }

  /// Maps a [FileSystemException] during a `.tdf` file move into a specific localized [LocalFileException].
  LocalFileException mapMoveFileSystemException(
    FileSystemException error, {
    required String fallbackPath,
    bool? isWindows,
  }) => _operations.mapMoveFileSystemException(
    error,
    fallbackPath,
    _messages,
    isWindows: isWindows,
  );

  /// Safely moves the local `.tdf` file to [targetRepository]'s resolved path under ordered exclusive locks without overwriting existing entities.
  Future<void> moveTdfFile(LocalFileRepository targetRepository) async {
    final messages = _messages;
    final fromPath = await _resolveFilePathAsync(migrateLegacy: true);
    final toPath = await targetRepository._resolveFilePathAsync(
      migrateLegacy: false,
    );
    final targetDirectory = _operations.resolveDirectoryPath(toPath);
    final inMemory =
        _useInMemoryFallback && targetRepository._useInMemoryFallback;
    await _withOrderedDualLocks<void>(
      fromPath,
      _lockManager,
      toPath,
      targetRepository._lockManager,
      () async {
        await _operations.moveTdfFile(
          fromPath,
          toPath,
          targetDirectory,
          maxFileBytes,
          messages,
          inMemory: inMemory,
          inMemoryStore: inMemoryStore,
        );
      },
      inMemoryOnly: inMemory,
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

  /// Prunes expired (`> maxRetainedDays`) and excess (`> maxRetainedFiles`) log files for [workspaceId].
  static int pruneExpiredLogFilesSync({
    required String directoryPath,
    required String platform,
    required String workspaceId,
    required DateTime utcNow,
    int maxRetainedDays = AppLogger.maxRetainedLogDays,
    int maxRetainedFiles = AppLogger.maxRetainedLogFiles,
  }) => _operations.pruneExpiredLogFilesSync(
    directoryPath: directoryPath,
    platform: platform,
    workspaceId: workspaceId,
    utcNow: utcNow,
    maxRetainedDays: maxRetainedDays,
    maxRetainedFiles: maxRetainedFiles,
  );

  /// Synchronously reads up to [maxBytes] from the diagnostic log file at [path].
  static String readLogFileSync(String path, {required int maxBytes}) =>
      _operations.readLogFileSync(path, maxBytes: maxBytes);

  /// Reads the local `.tdf` file and returns its decoded content, SHA-256 hex digest, and existence flag.
  Future<({String content, String? digest, bool exists})> readTdfWithDigest() =>
      _readTdfSnapshot(computeDigest: true);

  /// Renames the local `.tdf` file to [newFileName] inside its current directory under ordered exclusive locks and returns the new resolved path.
  Future<String> renameTdf(String newFileName) async {
    final messages = _messages;
    final fromPath = await _resolveFilePathAsync(migrateLegacy: true);
    final directoryPath = _operations.resolveDirectoryPath(fromPath);
    final normalizedName = _operations.validateFileName(newFileName, messages);
    final toPath = combineDirectoryAndFileName(directoryPath, normalizedName);
    final renamed = await _withOrderedDualLocks<String>(
      fromPath,
      _lockManager,
      toPath,
      _lockManager,
      () => _operations.renameTdf(
        fromPath,
        directoryPath,
        newFileName,
        maxFileBytes,
        messages,
        inMemory: _useInMemoryFallback,
        inMemoryStore: inMemoryStore,
      ),
      inMemoryOnly: _useInMemoryFallback,
    );
    AppLogger.event(
      LogLevel.info,
      LogTag.storage,
      'local.rename',
      fields: <String, Object?>{'to': renamed},
    );
    return renamed;
  }

  /// Clears the cached Android `Context.filesDir` path for isolated unit tests.
  @visibleForTesting
  static void resetAndroidFilesDirectoryCacheForTesting() {
    _cachedAndroidFilesDirectory = null;
  }

  /// Resolves the platform-appropriate user data directory for relative local file names.
  static String resolveDefaultDirectoryPath({
    AppBuildProfile? buildProfile,
    Map<String, String>? environment,
    bool? isWindows,
    String? androidFilesDirectoryPath,
  }) => _operations.resolveDefaultDirectoryPath(
    buildProfile: buildProfile,
    environment: environment,
    isWindows: isWindows,
    androidFilesDirectoryPath:
        androidFilesDirectoryPath ??
        (environment == null ? _cachedAndroidFilesDirectory : null),
  );

  /// Resolves the parent directory path of [resolveFilePath].
  String resolveDirectoryPath() =>
      _operations.resolveDirectoryPath(resolveFilePath());

  /// Validates and resolves the target local file path, throwing [LocalFileException] if invalid.
  String resolveFilePath() => _operations.resolveFilePath(
    config.localFilePath,
    baseDirectoryPath,
    _messages,
    buildProfile: buildProfile,
    androidFilesDirectoryPath: _effectiveAndroidFilesDirectory,
  );

  /// Resolves the full dated diagnostic log file path for [workspaceId] and [utcNow].
  static String resolveLogFilePath({
    String? baseDirectoryPath,
    required DateTime utcNow,
    required String platform,
    required String workspaceId,
    AppBuildProfile? buildProfile,
    String? androidFilesDirectoryPath,
  }) {
    final fileName = AppLogger.formatLogFileName(
      utcNow: utcNow,
      platform: platform,
      workspaceId: workspaceId,
    );
    return defaultLogFilePath(
      baseDirectoryPath: baseDirectoryPath,
      fileName: fileName,
      buildProfile: buildProfile,
      androidFilesDirectoryPath: androidFilesDirectoryPath,
    );
  }

  /// Writes [tdfContent] to the configured local `.tdf` file under the exclusive host file lock.
  Future<void> saveTdf(String tdfContent) async {
    final stopwatch = Stopwatch()..start();
    final messages = _messages;
    final filePath = await _resolveFilePathAsync(migrateLegacy: true);
    final bytes = utf8.encode(tdfContent);
    if (bytes.length > maxFileBytes) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'local.save',
        fields: <String, Object?>{
          'path': filePath,
          'bytes': bytes.length,
          'reason': 'oversized',
        },
      );
      throw LocalFileException(messages.errorLocalFileTooLarge);
    }
    try {
      await _lockManager.withExclusiveLock(filePath, () async {
        if (_useInMemoryFallback) {
          inMemoryStore?[filePath] = tdfContent;
          return;
        }
        await _operations.writeTdfAtomically(
          filePath,
          bytes,
          messages,
          lockManager: _lockManager,
        );
      }, inMemoryOnly: _useInMemoryFallback);
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'local.save',
        fields: <String, Object?>{
          'path': filePath,
          'bytes': bytes.length,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
    } on LocalFileException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'local.save',
        fields: <String, Object?>{'path': filePath},
        error: error,
      );
      rethrow;
    } on FileSystemException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'local.save',
        fields: <String, Object?>{'path': filePath},
        error: error,
      );
      throw LocalFileException(
        messages.errorSaveLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'local.save',
        fields: <String, Object?>{'path': filePath},
        error: error,
      );
      throw LocalFileException(
        messages.errorSaveLocalFileFailed(_describeUnexpectedError(error)),
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

  /// Emits `null` whenever the configured `.tdf` file is created, modified, or moved into its parent directory.
  Stream<void> watchTdfChanges() {
    if (!canWatchDirectory) {
      return const Stream<void>.empty();
    }
    final filePath = tryResolveFilePath();
    final directoryPath = tryResolveDirectoryPath();
    if (filePath == null || directoryPath == null) {
      return const Stream<void>.empty();
    }
    return _operations.watchTdfFile(
      directoryPath: directoryPath,
      targetFileName: extractFileNameFromPath(filePath),
      inMemory: _useInMemoryFallback,
      isAndroid: _isAndroidHost,
    );
  }

  /// Empties and re-initializes the local `.tdf` file as a blank TDF document, optionally creating a `.bak` or `.bak.001`+ backup first if the file exists.
  Future<void> wipeTdf({bool createBackup = false}) async {
    final stopwatch = Stopwatch()..start();
    final messages = _messages;
    final filePath = await _resolveFilePathAsync(migrateLegacy: true);
    const emptyContent = 'tdf ${TdfService.supportedVersion}\n';
    try {
      await _lockManager.withExclusiveLock(filePath, () async {
        if (_useInMemoryFallback) {
          _wipeInMemoryEntry(
            filePath,
            emptyContent,
            createBackup: createBackup,
          );
          return;
        }
        await _performDiskWipe(
          filePath,
          emptyContent,
          messages,
          lockManager: _lockManager,
          createBackup: createBackup,
        );
      }, inMemoryOnly: _useInMemoryFallback);
      if (_useInMemoryFallback) {
        return;
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'local.wipe',
        fields: <String, Object?>{
          'path': filePath,
          'backup': createBackup,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
    } on LocalFileException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'local.wipe',
        fields: <String, Object?>{'path': filePath},
        error: error,
      );
      rethrow;
    } on FileSystemException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'local.wipe',
        fields: <String, Object?>{'path': filePath},
        error: error,
      );
      throw LocalFileException(
        messages.errorSaveLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'local.wipe',
        fields: <String, Object?>{'path': filePath},
        error: error,
      );
      throw LocalFileException(
        messages.errorSaveLocalFileFailed(_describeUnexpectedError(error)),
        cause: error,
      );
    }
  }

  /// Acquires the exclusive host-local cooperative lock (or hermetic in-process lock) for [resolveFilePath] and runs [action].
  Future<T> withExclusiveTargetLock<T>(Future<T> Function() action) async {
    final filePath = await _resolveFilePathAsync(migrateLegacy: true);
    return _lockManager.withExclusiveLock<T>(
      filePath,
      action,
      inMemoryOnly: _useInMemoryFallback,
    );
  }

  /// Synchronously writes or appends [content] to the diagnostic log file at [path], flushing to stable storage only when [flush] is `true`.
  static void writeLogFileSync(
    String path,
    String content, {
    required bool append,
    bool flush = false,
  }) =>
      _operations.writeLogFileSync(path, content, append: append, flush: flush);

  /// Computes the SHA-256 hex digest of [bytes], offloading to a worker isolate when length meets [LocalFileOperations.asyncReadThresholdBytes].
  static Future<String> _computeSha256Hex(List<int> bytes) async {
    if (bytes.length < LocalFileOperations.asyncReadThresholdBytes) {
      return Sha256Service.hashHex(bytes);
    }
    return Isolate.run(() => Sha256Service.hashHex(bytes));
  }

  /// Decodes UTF-8 [bytes] and optionally computes their SHA-256 hex digest, offloading to a worker isolate when length meets [LocalFileOperations.asyncReadThresholdBytes].
  static Future<({String decoded, String? digest})> _decodeAndHashBytes(
    List<int> bytes, {
    required bool computeDigest,
  }) async {
    if (bytes.length < LocalFileOperations.asyncReadThresholdBytes) {
      final decoded = utf8.decode(bytes);
      final digest = computeDigest ? Sha256Service.hashHex(bytes) : null;
      return (decoded: decoded, digest: digest);
    }
    return Isolate.run(() {
      final decoded = utf8.decode(bytes);
      final digest = computeDigest ? Sha256Service.hashHex(bytes) : null;
      return (decoded: decoded, digest: digest);
    });
  }

  /// Returns a static safe summary for unexpected storage errors without exposing raw runtime exception strings.
  static String _describeUnexpectedError(Object error) {
    return switch (error) {
      FormatException _ => 'Invalid UTF-8 encoding',
      IOException _ => 'Filesystem I/O error',
      ArgumentError _ => 'Invalid file operation argument',
      OutOfMemoryError _ => 'Insufficient memory',
      _ => 'Unexpected storage error',
    };
  }

  /// Resolves and caches the Android `Context.filesDir` path for this repository instance, throwing [LocalFileException] if unavailable.
  Future<String> _ensureAndroidFilesDirectory() async {
    if (_resolvedAndroidFilesDirectory case final resolved?) {
      return resolved;
    }
    final String? rawDirectory;
    try {
      rawDirectory = await ensureAndroidFilesDirectoryInitialized(
        resolver: _androidFilesDirectoryResolver,
      );
    } on Object catch (error) {
      throw LocalFileException(
        _messages.errorLoadLocalFileFailed(
          'Could not resolve Android persistent files directory.',
        ),
        cause: error,
      );
    }
    final trimmed = rawDirectory?.trim() ?? '';
    if (trimmed.isEmpty) {
      throw LocalFileException(
        _messages.errorLoadLocalFileFailed(
          'Android persistent files directory resolved to empty path.',
        ),
      );
    }
    _resolvedAndroidFilesDirectory = trimmed;
    return trimmed;
  }

  /// Invokes the Android `de.akjir.tiertask/app_storage` platform channel to resolve `Context.filesDir`.
  static Future<String?> _invokeAndroidFilesDirectoryChannel() {
    return androidStorageChannel.invokeMethod<String>('getFilesDirectory');
  }

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

  /// Performs a safe one-time migration of a legacy regular `.tdf` file from Android `cacheDir` (`Directory.systemTemp`) into persistent `filesDir` under exclusive lock.
  Future<void> _migrateLegacyAndroidCacheFileIfNeeded(
    String targetPath,
    AppLocalizations messages,
  ) async {
    final cacheRoot = _operations.trimTrailingSeparators(
      (_legacyAndroidCacheDirectoryOverride ?? Directory.systemTemp.path)
          .trim(),
    );
    if (cacheRoot.isEmpty) {
      _androidMigrationChecked = true;
      return;
    }
    final effectiveProfile = buildProfile ?? AppBuildProfile.current;
    final legacyBaseDir = effectiveProfile.isDev
        ? '$cacheRoot${Platform.pathSeparator}${effectiveProfile.dataDirectoryName}'
        : cacheRoot;
    final legacyPath = _operations.resolveFilePath(
      config.localFilePath,
      legacyBaseDir,
      messages,
      buildProfile: effectiveProfile,
    );
    if (legacyPath == targetPath) {
      _androidMigrationChecked = true;
      return;
    }
    if (FileSystemEntity.typeSync(targetPath, followLinks: false) !=
            FileSystemEntityType.notFound ||
        FileSystemEntity.typeSync(legacyPath, followLinks: false) !=
            FileSystemEntityType.file) {
      _androidMigrationChecked = true;
      return;
    }

    await _lockManager.withExclusiveLock(targetPath, () async {
      if (FileSystemEntity.typeSync(targetPath, followLinks: false) !=
              FileSystemEntityType.notFound ||
          FileSystemEntity.typeSync(legacyPath, followLinks: false) !=
              FileSystemEntityType.file) {
        return;
      }
      final bytes = await _operations.readBoundedRegularFileBytes(
        legacyPath,
        maxFileBytes,
        messages,
      );
      await _operations.writeTdfAtomically(
        targetPath,
        bytes,
        messages,
        lockManager: _lockManager,
      );
      try {
        if (FileSystemEntity.typeSync(legacyPath, followLinks: false) ==
            FileSystemEntityType.file) {
          File(legacyPath).deleteSync();
        }
      } on FileSystemException {
        // Target is durably written; ignore best-effort legacy cache cleanup errors.
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'storage.android_cache_migrated',
        fields: <String, Object?>{
          'from': legacyPath,
          'to': targetPath,
          'bytes': bytes.length,
        },
      );
    });
    _androidMigrationChecked = true;
  }

  /// Validates [filePath], creates an optional bounded atomic `.bak` copy, and atomically writes [emptyContent].
  Future<void> _performDiskWipe(
    String filePath,
    String emptyContent,
    AppLocalizations messages, {
    required HostFileLockManager<LocalFileException> lockManager,
    required bool createBackup,
  }) async {
    final sourceType = FileSystemEntity.typeSync(filePath, followLinks: false);
    switch (sourceType) {
      case FileSystemEntityType.directory:
        throw LocalFileException(messages.errorMoveSourceIsDirectory(filePath));
      case FileSystemEntityType.link:
        throw LocalFileException(messages.errorMoveSourceIsSymlink(filePath));
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw LocalFileException(messages.errorMovePermissionDenied(filePath));
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.file:
        break;
    }
    if (sourceType == FileSystemEntityType.file && createBackup) {
      final backupPath = _operations.resolveNextLocalBackupPath(
        filePath,
        messages,
      );
      final backupBytes = await _operations.readBoundedRegularFileBytes(
        filePath,
        maxFileBytes,
        messages,
      );
      await _operations.writeTdfAtomically(
        backupPath,
        backupBytes,
        messages,
        lockManager: lockManager,
      );
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'local.backup',
        fields: <String, Object?>{'path': backupPath},
      );
    }
    await _operations.writeTdfAtomically(
      filePath,
      utf8.encode(emptyContent),
      messages,
      lockManager: lockManager,
    );
  }

  /// Reads the resolved `.tdf` file once via bounded [RandomAccessFile] I/O and optionally computes its SHA-256 hex digest.
  Future<({String content, String? digest, bool exists})> _readTdfSnapshot({
    required bool computeDigest,
  }) async {
    final stopwatch = Stopwatch()..start();
    final messages = _messages;
    final filePath = await _resolveFilePathAsync(migrateLegacy: true);
    if (_useInMemoryFallback) {
      final store = inMemoryStore;
      final exists = store?.containsKey(filePath) ?? false;
      final content = exists ? (store?[filePath] ?? '') : '';
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'local.load',
        fields: <String, Object?>{
          'path': filePath,
          'bytes': content.length,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      final encodedBytes = computeDigest && exists
          ? utf8.encode(content)
          : null;
      final digest = encodedBytes == null
          ? null
          : await _computeSha256Hex(encodedBytes);
      return (content: content, digest: digest, exists: exists);
    }
    try {
      final entityType = FileSystemEntity.typeSync(
        filePath,
        followLinks: false,
      );
      switch (entityType) {
        case FileSystemEntityType.notFound:
          AppLogger.event(
            LogLevel.info,
            LogTag.storage,
            'local.load',
            fields: <String, Object?>{'path': filePath, 'missing': true},
          );
          return (content: '', digest: null, exists: false);
        case FileSystemEntityType.directory:
          throw LocalFileException(
            messages.errorMoveSourceIsDirectory(filePath),
          );
        case FileSystemEntityType.link:
          throw LocalFileException(messages.errorMoveSourceIsSymlink(filePath));
        case FileSystemEntityType.pipe:
        case FileSystemEntityType.unixDomainSock:
          throw LocalFileException(
            messages.errorMovePermissionDenied(filePath),
          );
        case FileSystemEntityType.file:
          break;
      }
      final bytes = await _operations.readBoundedRegularFileBytes(
        filePath,
        maxFileBytes,
        messages,
      );
      final (:decoded, :digest) = await _decodeAndHashBytes(
        bytes,
        computeDigest: computeDigest,
      );
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'local.load',
        fields: <String, Object?>{
          'path': filePath,
          'bytes': bytes.length,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return (content: decoded, digest: digest, exists: true);
    } on LocalFileException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'local.load',
        fields: <String, Object?>{'path': filePath},
        error: error,
      );
      rethrow;
    } on FileSystemException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'local.load',
        fields: <String, Object?>{'path': filePath},
        error: error,
      );
      throw LocalFileException(
        messages.errorLoadLocalFileFailed(error.message),
        cause: error,
      );
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'local.load',
        fields: <String, Object?>{'path': filePath},
        error: error,
      );
      throw LocalFileException(
        messages.errorLoadLocalFileFailed(_describeUnexpectedError(error)),
        cause: error,
      );
    }
  }

  /// Resolves the local file path asynchronously, initializing Android `Context.filesDir` and optional legacy `cacheDir` migration.
  Future<String> _resolveFilePathAsync({required bool migrateLegacy}) async {
    if (!_usesAndroidFilesDirectory) {
      if (baseDirectoryPath == null && !_useInMemoryFallback) {
        try {
          await ensureAndroidFilesDirectoryInitialized();
        } on Object {
          // Absolute-path and desktop operations do not depend on Android filesDir.
        }
      }
      return resolveFilePath();
    }
    final messages = _messages;
    // Validate relative path before touching platform channel or filesystem.
    _operations.validateRelativeOrAbsolutePath(config.localFilePath, messages);
    final androidDir = await _ensureAndroidFilesDirectory();
    final targetPath = _operations.resolveFilePath(
      config.localFilePath,
      baseDirectoryPath,
      messages,
      buildProfile: buildProfile,
      androidFilesDirectoryPath: androidDir,
    );
    if (migrateLegacy && !_androidMigrationChecked) {
      await _migrateLegacyAndroidCacheFileIfNeeded(targetPath, messages);
    }
    return targetPath;
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

  /// Acquires exclusive locks on [firstPath] and [secondPath] in deterministic canonical order to prevent AB-BA deadlocks.
  static Future<T> _withOrderedDualLocks<T>(
    String firstPath,
    HostFileLockManager<LocalFileException> firstManager,
    String secondPath,
    HostFileLockManager<LocalFileException> secondManager,
    Future<T> Function() action, {
    required bool inMemoryOnly,
  }) {
    if (firstPath == secondPath) {
      return firstManager.withExclusiveLock<T>(
        firstPath,
        action,
        inMemoryOnly: inMemoryOnly,
      );
    }
    final firstKey = inMemoryOnly
        ? firstPath
        : HostFileLockManager.computeTargetPathHash(firstPath);
    final secondKey = inMemoryOnly
        ? secondPath
        : HostFileLockManager.computeTargetPathHash(secondPath);
    if (firstKey.compareTo(secondKey) <= 0) {
      return firstManager.withExclusiveLock<T>(
        firstPath,
        () => secondManager.withExclusiveLock<T>(
          secondPath,
          action,
          inMemoryOnly: inMemoryOnly,
        ),
        inMemoryOnly: inMemoryOnly,
      );
    }
    return secondManager.withExclusiveLock<T>(
      secondPath,
      () => firstManager.withExclusiveLock<T>(
        firstPath,
        action,
        inMemoryOnly: inMemoryOnly,
      ),
      inMemoryOnly: inMemoryOnly,
    );
  }
}
