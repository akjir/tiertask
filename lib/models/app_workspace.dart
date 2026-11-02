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

import 'dart:convert' show Utf8Codec;
import 'dart:typed_data' show BytesBuilder;

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

  /// Reconstructs a single [AppWorkspace] from its compact binary representation.
  factory AppWorkspace.fromBytes(List<int> bytes) =>
      decodePersistedState(bytes).workspaces.first;

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

  /// Maximum allowed binary payload size in bytes (`64 KiB`).
  static const int maxBinaryBytes = 65536;

  /// Maximum allowed workspace display name length in characters.
  static const int maxNameLength = 128;

  /// Maximum allowed number of persisted workspaces.
  static const int maxWorkspaces = 32;

  static const int _binaryHeaderBytes = 6;
  static const int _binaryVersion = 1;
  static const Utf8Codec _utf8Codec = Utf8Codec(allowMalformed: false);

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
  AppWorkspace copyWith({String? id, String? name, WebDavConfig? config}) =>
      AppWorkspace(
        id: id ?? this.id,
        name: name ?? this.name,
        config: config ?? this.config,
      );

  /// Decodes a compact `TTW\x01` binary payload into all persisted [AppWorkspace]s and the active workspace ID.
  static ({List<AppWorkspace> workspaces, String activeId})
  decodePersistedState(List<int> bytes) {
    final (workspaceCount, activeIndex) = _validateBinaryHeader(bytes);
    final source = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final workspaces = <AppWorkspace>[];
    final summaries = <WorkspaceSummary>[];
    var offset = _binaryHeaderBytes;

    for (var i = 0; i < workspaceCount; i++) {
      final (workspace, nextOffset) = _decodeRecord(source, offset, summaries);
      workspaces.add(workspace);
      summaries.add(workspace.summary);
      offset = nextOffset;
    }

    if (offset != source.length) {
      _throwCorrupt('Binary workspace payload has trailing bytes.');
    }
    return (
      workspaces: List<AppWorkspace>.unmodifiable(workspaces),
      activeId: workspaces[activeIndex].id,
    );
  }

  /// Derives a unique workspace identifier from [workspaceName] against [existingSummaries].
  static String deriveWorkspaceId(
    String workspaceName,
    Iterable<WorkspaceSummary> existingSummaries,
  ) {
    final slug = _buildAsciiSlug(workspaceName.trim());
    final base = slug.isEmpty ? 'workspace' : slug;
    final ids = <String>{for (final item in existingSummaries) item.id};
    if (!ids.contains(base)) return base;
    var suffix = 2;
    while (ids.contains('${base}_$suffix')) {
      suffix++;
    }
    return '${base}_$suffix';
  }

  /// Encodes [workspaces] and [activeId] into a single compact `TTW\x01` binary [Uint8List] payload.
  static Uint8List encodePersistedState(
    List<AppWorkspace> workspaces, {
    required String activeId,
  }) {
    final list = workspaces.isEmpty ? const [defaultWorkspace] : workspaces;
    final count = list.length <= maxWorkspaces ? list.length : maxWorkspaces;

    var activeIndex = 0;
    final builder = BytesBuilder(copy: false)
      ..add(<int>[0x54, 0x54, 0x57, _binaryVersion, count, 0]);

    for (var i = 0; i < count; i++) {
      if (list[i].id == activeId) {
        activeIndex = i;
      }
      _appendWorkspaceRecord(builder, list[i]);
    }

    final output = builder.toBytes();
    output[5] = activeIndex;
    return output;
  }

  /// Normalizes a `.tdf` file path into a case-insensitive key for duplicate detection.
  static String normalizeFilePathKey(String rawPath) =>
      _validateSingleTdfPath(rawPath).join('/').toLowerCase();

  /// Normalizes a workspace display name into a case-insensitive key for duplicate detection.
  static String normalizeNameKey(String rawName) =>
      rawName.trim().toLowerCase();

  /// Suggests a lowercase `.tdf` file name derived from [workspaceName] (e.g. `'Arbeit'` -> `'arbeit.tdf'`).
  static String suggestFileName(String workspaceName) {
    final slug = _buildAsciiSlug(workspaceName.trim());
    return '${slug.isEmpty ? 'workspace' : slug}.tdf';
  }

  /// Serializes this single [AppWorkspace] into a compact `TTW\x01` binary [Uint8List].
  Uint8List toBytes() =>
      encodePersistedState(<AppWorkspace>[this], activeId: id);

  /// Validates that [config] uses valid, non-colliding `.tdf` file paths across [existingSummaries].
  static void validateConfigPaths(
    WebDavConfig config,
    Iterable<WorkspaceSummary> existingSummaries, {
    String? excludeWorkspaceId,
  }) {
    final localKey = normalizeFilePathKey(config.localFilePath);
    final remoteKey = normalizeFilePathKey(config.filePath);
    for (final existing in existingSummaries) {
      if (existing.id != excludeWorkspaceId &&
          (normalizeFilePathKey(existing.localFilePath) == localKey ||
              normalizeFilePathKey(existing.filePath) == remoteKey)) {
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
      if (existing.id != excludeWorkspaceId &&
          normalizeNameKey(existing.name) == normalizedTarget) {
        throw const WorkspaceException(
          WorkspaceErrorKind.duplicateName,
          'A workspace with this name already exists.',
        );
      }
    }
    return trimmed;
  }

  /// Appends a single [workspace] binary record to [builder], enforcing size bounds.
  static void _appendWorkspaceRecord(
    BytesBuilder builder,
    AppWorkspace workspace,
  ) {
    final config = workspace.config;
    builder.addByte(
      (config.storageMode.id & 0x03) |
          ((config.language.id & 0x03) << 2) |
          ((config.themeMode.id & 0x03) << 4) |
          ((config.themePalette.id & 0x01) << 6) |
          ((config.showOpenTaskCount ? 1 : 0) << 7),
    );
    for (final rawField in <String>[
      workspace.id.trim(),
      workspace.name.trim(),
      config.serverUrl.trim(),
      config.username.trim(),
      config.password,
      config.filePath.trim(),
      config.localFilePath.trim(),
    ]) {
      final encoded = _utf8Codec.encode(rawField);
      if (encoded.length > 0xFFFF ||
          builder.length + 2 + encoded.length > maxBinaryBytes) {
        _throwCorrupt('Binary workspace payload exceeds maximum size.');
      }
      builder
        ..addByte((encoded.length >> 8) & 0xFF)
        ..addByte(encoded.length & 0xFF)
        ..add(encoded);
    }
  }

  /// Converts [input] into a lowercase ASCII identifier slug with `_` separators.
  static String _buildAsciiSlug(String input) {
    final buffer = StringBuffer();
    var lastWasUnderscore = true;
    for (var i = 0; i < input.length; i++) {
      final token = _transliterateCodeUnit(input.codeUnitAt(i));
      if (token != '_' || !lastWasUnderscore) {
        buffer.write(token);
        lastWasUnderscore = token == '_';
      }
    }
    final rawSlug = buffer.toString();
    return rawSlug.endsWith('_')
        ? rawSlug.substring(0, rawSlug.length - 1)
        : rawSlug;
  }

  /// Decodes and validates a single [AppWorkspace] record from [source] at [offset].
  static (AppWorkspace, int) _decodeRecord(
    Uint8List source,
    int offset,
    List<WorkspaceSummary> existing,
  ) {
    if (offset >= source.length) {
      _throwCorrupt('Unexpected end of binary workspace record.');
    }
    final flags = source[offset];
    final fields = <String>[];
    var cursor = offset + 1;
    for (var i = 0; i < 7; i++) {
      final (decoded, nextCursor) = _readString(source, cursor);
      fields.add(decoded);
      cursor = nextCursor;
    }

    final filePath = fields[5].trim();
    final localPath = fields[6].trim();
    final workspace = AppWorkspace(
      id: fields[0].trim().isEmpty ? defaultId : fields[0].trim(),
      name: fields[1].trim().isEmpty ? defaultName : fields[1].trim(),
      config: WebDavConfig(
        serverUrl: fields[2].trim(),
        username: fields[3].trim(),
        password: fields[4],
        filePath: filePath.isEmpty ? defaultFileName : filePath,
        localFilePath: localPath.isEmpty ? defaultFileName : localPath,
        storageMode: StorageMode.fromId(flags & 0x03),
        language: AppLanguage.fromId((flags >> 2) & 0x03),
        themeMode: AppThemeMode.fromId((flags >> 4) & 0x03),
        themePalette: AppThemePalette.fromId((flags >> 6) & 0x01),
        showOpenTaskCount: ((flags >> 7) & 0x01) == 1,
      ),
    );
    if (workspace.id.isEmpty ||
        _hasControlCharacters(workspace.id) ||
        existing.any((summary) => summary.id == workspace.id)) {
      _throwCorrupt('Decoded workspace ID is invalid or duplicated.');
    }
    try {
      validateName(workspace.name, existing);
      validateConfigPaths(workspace.config, existing);
    } on WorkspaceException catch (error) {
      _throwCorrupt(error.message);
    }
    return (workspace, cursor);
  }

  /// Returns `true` when [value] contains C0/C1 control characters, line separators, or BiDi overrides.
  static bool _hasControlCharacters(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit < 0x20 || (unit >= 0x7F && unit <= 0x9F) || unit == 0x061C) {
        return true;
      }
      if (unit == 0x200E ||
          unit == 0x200F ||
          (unit >= 0x2028 && unit <= 0x202E) ||
          (unit >= 0x2066 && unit <= 0x2069)) {
        return true;
      }
    }
    return false;
  }

  /// Reads a 16-bit big-endian length-prefixed UTF-8 string from [source] at [offset].
  static (String, int) _readString(Uint8List source, int offset) {
    final end = offset + 2 > source.length
        ? source.length + 1
        : offset + 2 + ((source[offset] << 8) | source[offset + 1]);
    if (end > source.length) {
      _throwCorrupt('Truncated string in binary workspace record.');
    }
    try {
      final view = Uint8List.sublistView(source, offset + 2, end);
      return (_utf8Codec.decode(view), end);
    } on FormatException {
      _throwCorrupt('Invalid UTF-8 string in binary workspace record.');
    }
  }

  /// Throws a [WorkspaceException] with [WorkspaceErrorKind.corruptBinaryPayload] and [message].
  static Never _throwCorrupt(String message) => throw WorkspaceException(
    WorkspaceErrorKind.corruptBinaryPayload,
    message,
  );

  /// Transliterates a UTF-16 [codeUnit] into lowercase ASCII characters or `'_'`.
  static String _transliterateCodeUnit(int codeUnit) => switch (codeUnit) {
    0x00E4 || 0x00C4 => 'ae',
    0x00F6 || 0x00D6 => 'oe',
    0x00FC || 0x00DC => 'ue',
    0x00DF => 'ss',
    >= 0x0041 && <= 0x005A => String.fromCharCode(codeUnit + 32),
    (>= 0x0061 && <= 0x007A) ||
    (>= 0x0030 && <= 0x0039) => String.fromCharCode(codeUnit),
    _ => '_',
  };

  /// Validates the 6-byte `TTW\x01` binary header and returns `(workspaceCount, activeIndex)`.
  static (int, int) _validateBinaryHeader(List<int> bytes) {
    if (bytes.length < _binaryHeaderBytes || bytes.length > maxBinaryBytes) {
      _throwCorrupt('Binary workspace payload size is out of bounds.');
    }
    final count = bytes[4];
    final activeIndex = bytes[5];
    if (bytes[0] != 0x54 ||
        bytes[1] != 0x54 ||
        bytes[2] != 0x57 ||
        bytes[3] != _binaryVersion ||
        count < 1 ||
        count > maxWorkspaces ||
        activeIndex < 0 ||
        activeIndex >= count) {
      _throwCorrupt('Binary workspace header is invalid or out of range.');
    }
    return (count, activeIndex);
  }

  /// Validates that [rawPath] is a safe `.tdf` file path and returns its non-empty path segments.
  static List<String> _validateSingleTdfPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (_hasControlCharacters(trimmed) ||
        !trimmed.toLowerCase().endsWith('.tdf')) {
      throw const WorkspaceException(
        WorkspaceErrorKind.invalidFilePath,
        'Workspace TDF file path must be a valid .tdf file name or path.',
      );
    }

    final segments = <String>[];
    for (final segment in trimmed.split(_pathSeparatorPattern)) {
      if (segment.isEmpty) {
        continue;
      }
      if (segment != segment.trim() || segment == '.' || segment == '..') {
        throw const WorkspaceException(
          WorkspaceErrorKind.invalidFilePath,
          'Workspace TDF file path must not contain relative traversal segments.',
        );
      }
      segments.add(segment);
    }
    if (segments.isEmpty ||
        segments.last.length <= 4 ||
        segments.last.startsWith('.') ||
        !segments.last.toLowerCase().endsWith('.tdf')) {
      throw const WorkspaceException(
        WorkspaceErrorKind.invalidFilePath,
        'Workspace TDF file path must end with a .tdf file name.',
      );
    }
    return segments;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppWorkspace &&
          other.id == id &&
          other.name == name &&
          other.config == config);

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

  /// Persisted binary workspace payload is truncated, malformed, or uses an unsupported header/version.
  corruptBinaryPayload,
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
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceSummary &&
          other.id == id &&
          other.name == name &&
          other.localFilePath == localFilePath &&
          other.filePath == filePath);

  @override
  int get hashCode => Object.hash(id, name, localFilePath, filePath);
}
