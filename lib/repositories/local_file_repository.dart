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

import '../l10n/app_localizations.dart';
import '../models/webdav_config.dart';

/// Custom domain exception thrown when local Markdown file operations fail.
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

/// Repository for reading and writing the task board Markdown file on the local filesystem.
class LocalFileRepository {
  /// Creates a [LocalFileRepository] for [config].
  LocalFileRepository({
    required this.config,
    this.baseDirectoryPath,
    this.inMemoryStore,
    this.maxFileBytes = defaultMaxFileBytes,
  });

  /// Default maximum allowed Markdown file size in bytes (1 MiB).
  static const int defaultMaxFileBytes = 1048576;

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
      inMemoryStore != null &&
      Platform.environment.containsKey('FLUTTER_TEST');

  /// Reads the local Markdown file and returns its contents, or an empty string if the file does not exist.
  Future<String> loadMarkdown() async {
    final localizations = _localizations;
    final filePath = resolveFilePath();

    if (_useInMemoryFallback) {
      return inMemoryStore?[filePath] ?? '';
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return '';
      }
      final fileLength = await file.length();
      if (fileLength > maxFileBytes) {
        throw LocalFileException(localizations.errorLocalFileTooLarge);
      }
      final bytes = await file.readAsBytes();
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

  /// Validates and resolves the target local file path, throwing [LocalFileException] if invalid.
  String resolveFilePath() {
    final localizations = _localizations;
    final rawPath = config.localFilePath.trim();
    final segments = _validateAndSplitSegments(rawPath, localizations);
    final separator = Platform.pathSeparator;
    final joinedSegments = segments.join(separator);

    if (baseDirectoryPath case final explicitBase?
        when explicitBase.trim().isNotEmpty) {
      final cleanedBase = _trimTrailingSeparators(explicitBase.trim());
      return '$cleanedBase$separator$joinedSegments';
    }

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

    final defaultBase = _trimTrailingSeparators(_defaultBaseDirectoryPath());
    return '$defaultBase$separator$joinedSegments';
  }

  /// Writes [markdownContent] to the configured local Markdown file.
  Future<void> saveMarkdown(String markdownContent) async {
    final localizations = _localizations;
    final filePath = resolveFilePath();
    final bytes = utf8.encode(markdownContent);
    if (bytes.length > maxFileBytes) {
      throw LocalFileException(localizations.errorLocalFileTooLarge);
    }

    if (_useInMemoryFallback) {
      inMemoryStore?[filePath] = markdownContent;
      return;
    }

    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
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

  /// Returns the resolved local file path, or `null` if [config.localFilePath] is invalid.
  String? tryResolveFilePath() {
    try {
      return resolveFilePath();
    } on LocalFileException {
      return null;
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
}
