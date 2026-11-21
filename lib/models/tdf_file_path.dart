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

import 'package:flutter/foundation.dart';

import 'app_workspace.dart';
import 'webdav_config.dart';

/// Stateless pure `.tdf` filename and path utilities with zero platform I/O dependencies.
class TdfFilePath {
  /// Prevents instantiation of [TdfFilePath].
  const TdfFilePath._();

  static final RegExp _pathSeparatorPattern = RegExp(r'[\\/]+');
  static final RegExp _windowsDrivePattern = RegExp(r'^[a-zA-Z]:[\\/]');

  /// Combines [directoryPath] and the trailing filename of [fileName] using [separator] or the target platform default.
  static String combineDirectoryAndFileName(
    String directoryPath,
    String fileName, {
    String? separator,
  }) {
    final cleanFileName = extractFileNameFromPath(fileName);
    final cleanDirectory = trimTrailingSeparators(directoryPath.trim());
    if (cleanDirectory.isEmpty) {
      return cleanFileName;
    }
    final lastCode = cleanDirectory.codeUnitAt(cleanDirectory.length - 1);
    if (lastCode == 0x2F || lastCode == 0x5C) {
      return '$cleanDirectory$cleanFileName';
    }
    final resolvedSeparator =
        separator ??
        (defaultTargetPlatform == TargetPlatform.windows ? r'\' : '/');
    return '$cleanDirectory$resolvedSeparator$cleanFileName';
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

  /// Extracts the parent directory portion from [rawPath], preserving POSIX and Windows drive roots.
  static String extractDirectoryFromPath(String rawPath) {
    final trimmed = trimTrailingSeparators(rawPath.trim());
    if (trimmed.isEmpty) {
      return '';
    }
    final lastSlash = trimmed.lastIndexOf('/');
    final lastBackslash = trimmed.lastIndexOf(r'\');
    final splitIndex = lastSlash > lastBackslash ? lastSlash : lastBackslash;
    if (splitIndex < 0) {
      return '';
    }
    if (splitIndex == 0) {
      return '/';
    }
    if (splitIndex == 2 && _windowsDrivePattern.hasMatch(trimmed)) {
      return trimmed.substring(0, 3);
    }
    return trimmed.substring(0, splitIndex);
  }

  /// Extracts the base filename without a trailing `.tdf` extension from [rawPath].
  static String extractFileBaseName(String rawPath) {
    final fileName = extractFileNameFromPath(rawPath);
    if (fileName.length > 4 &&
        fileName.substring(fileName.length - 4).toLowerCase() == '.tdf') {
      return fileName.substring(0, fileName.length - 4);
    }
    return fileName;
  }

  /// Extracts the trailing filename segment from [rawPath], defaulting to [WebDavConfig.defaultFileName].
  static String extractFileNameFromPath(String rawPath) {
    final parts = rawPath.trim().split(_pathSeparatorPattern);
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].isNotEmpty) {
        return parts[i];
      }
    }
    return WebDavConfig.defaultFileName;
  }

  /// Returns `true` when [rawPath] starts with a POSIX root `/` or Windows drive prefix.
  static bool isAbsolutePath(String rawPath) =>
      rawPath.startsWith('/') || _windowsDrivePattern.hasMatch(rawPath);

  /// Returns `true` when [rawName] is a valid single `.tdf` filename or base name without path separators or control characters.
  static bool isValidSingleFileName(String rawName) {
    final trimmed = rawName.trim();
    return trimmed.isNotEmpty &&
        trimmed != '.' &&
        trimmed != '..' &&
        trimmed.toLowerCase() != '.tdf' &&
        !trimmed.contains('/') &&
        !trimmed.contains(r'\') &&
        !trimmed.contains(':') &&
        !AppWorkspace.hasControlCharacters(trimmed);
  }

  /// Strips trailing `/` and `\` characters from [path], preserving POSIX and Windows drive roots.
  static String trimTrailingSeparators(String path) {
    final minLength = _windowsDrivePattern.hasMatch(path) ? 3 : 1;
    var end = path.length;
    while (end > minLength &&
        (path.codeUnitAt(end - 1) == 0x2F ||
            path.codeUnitAt(end - 1) == 0x5C)) {
      end--;
    }
    return path.substring(0, end);
  }
}
