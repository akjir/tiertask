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

import 'webdav_config.dart';

/// Immutable representation of the single active workspace loaded in memory.
@immutable
class AppWorkspace {
  /// Creates an [AppWorkspace] with [id], display [name], and [config].
  const AppWorkspace({
    required this.id,
    required this.name,
    this.config = const WebDavConfig(),
  });

  /// Reconstructs an [AppWorkspace] from a persisted JSON map.
  factory AppWorkspace.fromJson(Map<String, Object?> json) {
    final rawId = (json['id'] as String?)?.trim() ?? '';
    final rawName = (json['name'] as String?)?.trim() ?? '';
    final id = rawId.isEmpty ? defaultId : rawId;
    final name = rawName.isEmpty ? defaultName : rawName;
    final filePath = (json['filePath'] as String?)?.trim() ?? defaultFileName;
    final localFilePath =
        (json['localFilePath'] as String?)?.trim() ?? defaultFileName;
    final rawStorageMode = json['storageMode'] as String?;

    return AppWorkspace(
      id: id,
      name: name,
      config: WebDavConfig(
        serverUrl: (json['serverUrl'] as String?)?.trim() ?? '',
        username: (json['username'] as String?)?.trim() ?? '',
        password: (json['password'] as String?) ?? '',
        filePath: filePath.isEmpty ? defaultFileName : filePath,
        localFilePath: localFilePath.isEmpty ? defaultFileName : localFilePath,
        storageMode: rawStorageMode == null
            ? null
            : StorageMode.fromCode(rawStorageMode),
        language: AppLanguage.fromCode(json['language'] as String?),
        themeMode: AppThemeMode.fromCode(json['themeMode'] as String?),
        showOpenTaskCount: json['showOpenTaskCount'] == true,
      ),
    );
  }

  /// Default `.tdf` file name for the primary `Tasks` workspace.
  static const String defaultFileName = WebDavConfig.defaultFileName;

  /// Identifier of the primary `Tasks` workspace.
  static const String defaultId = 'tasks';

  /// Display name of the primary `Tasks` workspace.
  static const String defaultName = 'Tasks';

  /// Default `Tasks` workspace instance using `tasks.tdf`.
  static const AppWorkspace defaultWorkspace = AppWorkspace(
    id: defaultId,
    name: defaultName,
  );

  /// Maximum allowed workspace display name length in characters.
  static const int maxNameLength = 128;

  /// Maximum allowed number of persisted workspaces.
  static const int maxWorkspaces = 32;

  static final RegExp _pathSeparatorPattern = RegExp(r'[\\/]+');

  /// Isolated storage, synchronization, locale, and theme settings for this workspace.
  final WebDavConfig config;

  /// Unique workspace identifier.
  final String id;

  /// User-facing workspace display name.
  final String name;

  /// Lightweight summary of this workspace for uniqueness checks and listing.
  WorkspaceSummary get summary => WorkspaceSummary(
    id: id,
    name: name,
    localFilePath: config.localFilePath,
    filePath: config.filePath,
  );

  /// Returns a copy of this [AppWorkspace] with updated fields.
  AppWorkspace copyWith({String? id, String? name, WebDavConfig? config}) {
    return AppWorkspace(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
    );
  }

  /// Derives a unique workspace identifier from [workspaceName] against [existingSummaries].
  static String deriveWorkspaceId(
    String workspaceName,
    Iterable<WorkspaceSummary> existingSummaries,
  ) {
    final baseSlug = _buildAsciiSlug(workspaceName.trim());
    final candidateBase = baseSlug.isEmpty ? 'workspace' : baseSlug;
    final existingIds = <String>{
      for (final summary in existingSummaries) summary.id,
    };
    if (!existingIds.contains(candidateBase)) {
      return candidateBase;
    }
    var suffix = 2;
    while (existingIds.contains('${candidateBase}_$suffix')) {
      suffix++;
    }
    return '${candidateBase}_$suffix';
  }

  /// Normalizes a `.tdf` file path into a case-insensitive key for duplicate detection.
  static String normalizeFilePathKey(String rawPath) {
    final segments = _validateSingleTdfPath(rawPath);
    return segments.join('/').toLowerCase();
  }

  /// Normalizes a workspace display name into a case-insensitive key for duplicate detection.
  static String normalizeNameKey(String rawName) {
    return rawName.trim().toLowerCase();
  }

  /// Suggests a lowercase `.tdf` file name derived from [workspaceName] (e.g. `'Arbeit'` -> `'arbeit.tdf'`).
  static String suggestFileName(String workspaceName) {
    final slug = _buildAsciiSlug(workspaceName.trim());
    final effectiveStem = slug.isEmpty ? 'workspace' : slug;
    return '$effectiveStem.tdf';
  }

  /// Serializes this [AppWorkspace] into a JSON-compatible map for persistent storage.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'serverUrl': config.serverUrl.trim(),
      'username': config.username.trim(),
      'password': config.password,
      'filePath': config.filePath.trim(),
      'localFilePath': config.localFilePath.trim(),
      'storageMode': config.storageMode.code,
      'language': config.language.code,
      'themeMode': config.themeMode.code,
      'showOpenTaskCount': config.showOpenTaskCount,
    };
  }

  /// Validates that [config] uses valid, non-colliding `.tdf` file paths across [existingSummaries].
  static void validateConfigPaths(
    WebDavConfig config,
    Iterable<WorkspaceSummary> existingSummaries, {
    String? excludeWorkspaceId,
  }) {
    final localKey = normalizeFilePathKey(config.localFilePath);
    final remoteKey = normalizeFilePathKey(config.filePath);

    for (final existing in existingSummaries) {
      if (existing.id == excludeWorkspaceId) {
        continue;
      }
      final existingLocalKey = normalizeFilePathKey(existing.localFilePath);
      final existingRemoteKey = normalizeFilePathKey(existing.filePath);
      if (existingLocalKey == localKey || existingRemoteKey == remoteKey) {
        throw const WorkspaceException(
          WorkspaceErrorKind.duplicateFilePath,
          'Another workspace already uses the same TDF file path.',
        );
      }
    }
  }

  /// Validates and trims [rawName], ensuring it is non-empty, within bounds, and unique across [existingSummaries].
  static String validateName(
    String rawName,
    Iterable<WorkspaceSummary> existingSummaries, {
    String? excludeWorkspaceId,
  }) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty ||
        trimmed.length > maxNameLength ||
        _hasControlCharacters(trimmed)) {
      throw const WorkspaceException(
        WorkspaceErrorKind.emptyName,
        'Workspace name must be between 1 and 128 printable characters.',
      );
    }

    final normalizedTarget = normalizeNameKey(trimmed);
    for (final existing in existingSummaries) {
      if (existing.id == excludeWorkspaceId) {
        continue;
      }
      if (normalizeNameKey(existing.name) == normalizedTarget) {
        throw const WorkspaceException(
          WorkspaceErrorKind.duplicateName,
          'A workspace with this name already exists.',
        );
      }
    }
    return trimmed;
  }

  /// Converts [input] into a lowercase ASCII identifier slug with `_` separators.
  static String _buildAsciiSlug(String input) {
    final buffer = StringBuffer();
    var lastWasUnderscore = true;
    for (var i = 0; i < input.length; i++) {
      final token = _transliterateCodeUnit(input.codeUnitAt(i));
      if (token == '_') {
        if (!lastWasUnderscore) {
          buffer.write('_');
          lastWasUnderscore = true;
        }
        continue;
      }
      buffer.write(token);
      lastWasUnderscore = false;
    }
    final rawSlug = buffer.toString();
    if (rawSlug.endsWith('_')) {
      return rawSlug.substring(0, rawSlug.length - 1);
    }
    return rawSlug;
  }

  /// Returns `true` when [value] contains ASCII control characters or DEL (`0x7F`).
  static bool _hasControlCharacters(String value) {
    for (var i = 0; i < value.length; i++) {
      final codeUnit = value.codeUnitAt(i);
      if (codeUnit < 0x20 || codeUnit == 0x7F) {
        return true;
      }
    }
    return false;
  }

  /// Transliterates a UTF-16 [codeUnit] into lowercase ASCII characters or `'_'`.
  static String _transliterateCodeUnit(int codeUnit) {
    return switch (codeUnit) {
      0x00E4 || 0x00C4 => 'ae',
      0x00F6 || 0x00D6 => 'oe',
      0x00FC || 0x00DC => 'ue',
      0x00DF => 'ss',
      >= 0x0041 && <= 0x005A => String.fromCharCode(codeUnit + 32),
      (>= 0x0061 && <= 0x007A) ||
      (>= 0x0030 && <= 0x0039) => String.fromCharCode(codeUnit),
      _ => '_',
    };
  }

  /// Validates that [rawPath] is a safe `.tdf` file path and returns its non-empty path segments.
  static List<String> _validateSingleTdfPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.length <= 4 ||
        _hasControlCharacters(trimmed) ||
        !trimmed.toLowerCase().endsWith('.tdf')) {
      throw const WorkspaceException(
        WorkspaceErrorKind.invalidFilePath,
        'Workspace TDF file path must be a valid .tdf file name or path.',
      );
    }

    final rawSegments = trimmed.split(_pathSeparatorPattern);
    final segments = <String>[];
    for (final segment in rawSegments) {
      if (segment.isEmpty) {
        continue;
      }
      if (segment == '.' || segment == '..') {
        throw const WorkspaceException(
          WorkspaceErrorKind.invalidFilePath,
          'Workspace TDF file path must not contain relative traversal segments.',
        );
      }
      segments.add(segment);
    }
    if (segments.isEmpty || !segments.last.toLowerCase().endsWith('.tdf')) {
      throw const WorkspaceException(
        WorkspaceErrorKind.invalidFilePath,
        'Workspace TDF file path must end with a .tdf file name.',
      );
    }
    return segments;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppWorkspace &&
        other.id == id &&
        other.name == name &&
        other.config == config;
  }

  @override
  int get hashCode => Object.hash(id, name, config);
}

/// Error categories for workspace creation, renaming, path validation, and lifecycle operations.
enum WorkspaceErrorKind {
  /// Workspace display name is empty, whitespace-only, contains control characters, or exceeds 128 characters.
  emptyName,

  /// Another workspace already uses the same display name (case-insensitive).
  duplicateName,

  /// Another workspace already uses the same local or remote `.tdf` file path.
  duplicateFilePath,

  /// Local or remote `.tdf` file path is empty, lacks the `.tdf` extension, or contains traversal segments.
  invalidFilePath,

  /// Target workspace identifier does not exist in storage.
  workspaceNotFound,

  /// Deleting the last remaining workspace is forbidden.
  cannotDeleteLastWorkspace,

  /// Creating a new workspace would exceed [AppWorkspace.maxWorkspaces].
  maxWorkspacesExceeded,
}

/// Domain exception thrown when workspace validation or lifecycle operations fail.
class WorkspaceException implements Exception {
  /// Creates a [WorkspaceException] with [kind] and a human-readable [message].
  const WorkspaceException(this.kind, this.message);

  /// Specific workspace error category.
  final WorkspaceErrorKind kind;

  /// Human-readable error description.
  final String message;

  @override
  String toString() => message;
}

/// Lightweight metadata summary for a persisted workspace without holding its full [WebDavConfig].
@immutable
class WorkspaceSummary {
  /// Creates a [WorkspaceSummary].
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.localFilePath,
    required this.filePath,
  });

  /// Configured remote `.tdf` file path on WebDAV.
  final String filePath;

  /// Unique workspace identifier.
  final String id;

  /// Configured local `.tdf` file path on disk.
  final String localFilePath;

  /// Display name of the workspace.
  final String name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkspaceSummary &&
        other.id == id &&
        other.name == name &&
        other.localFilePath == localFilePath &&
        other.filePath == filePath;
  }

  @override
  int get hashCode => Object.hash(id, name, localFilePath, filePath);
}
