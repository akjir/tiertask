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
import 'dart:typed_data' show Uint8List;

import '../services/app_logger.dart';
import 'app_workspace.dart';
import 'webdav_config.dart';

/// Read-only binary decoder migrating pre-0.4.0 `TTW\x02` settings payloads to `settings.json`.
///
/// Strictly rejects `TTW\x01` and all other versions. Scheduled for complete removal in `0.5.0`.
@Deprecated(
  'Read-only TTW\\x02 migration converter for pre-0.4.0 settings. '
  'Scheduled for removal in 0.5.0.',
)
class LegacyTtwV2Converter {
  const LegacyTtwV2Converter._();

  /// Maximum allowed `TTW\x02` binary payload size in bytes (`64 KiB`).
  static const int maxBinaryBytes = 65536;

  static const int _binaryHeaderBytes = 6;
  static const int _binaryVersionV2 = 2;
  static const Utf8Codec _utf8Codec = Utf8Codec(allowMalformed: false);

  /// Decodes a `TTW\x02` binary payload into workspaces and the active workspace identifier.
  ///
  /// Throws [WorkspaceException] with [WorkspaceErrorKind.corruptSettingsPayload] on `TTW\x01`,
  /// truncated data, invalid UTF-8, duplicate entries, or out-of-range fields.
  @Deprecated(
    'Read-only TTW\\x02 migration decoder. Scheduled for removal in 0.5.0.',
  )
  static ({List<AppWorkspace> workspaces, String activeId}) decodeTtwV2Bytes(
    List<int> bytes,
  ) {
    final header = _validateV2Header(bytes);
    final source = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final workspaces = <AppWorkspace>[];
    final summaries = <WorkspaceSummary>[];
    var offset = _binaryHeaderBytes;

    for (var i = 0; i < header.count; i++) {
      final (workspace, nextOffset) = _decodeRecord(source, offset, summaries);
      workspaces.add(workspace);
      summaries.add(workspace.summary);
      offset = nextOffset;
    }

    if (offset != source.length) {
      _throwCorrupt('Legacy TTW v2 payload has trailing bytes.');
    }
    return (
      workspaces: List<AppWorkspace>.unmodifiable(workspaces),
      activeId: workspaces[header.activeIndex].id,
    );
  }

  /// Decodes the 2-bit `tzWord` bits `11..12` into a [LogLevel] (`0 -> info`).
  static LogLevel _decodeLogLevelBits(int bits) => switch (bits & 0x03) {
    1 => LogLevel.debug,
    2 => LogLevel.warn,
    3 => LogLevel.error,
    _ => LogLevel.info,
  };

  /// Decodes `(storageMode, language, themeMode, localWatchEnabled)` from the low 6 bits of [flags].
  static (StorageMode, AppLanguage, AppThemeMode, bool) _decodeLowFlagsBits(
    int flags,
  ) {
    final lane0 = flags & 0x03;
    final lane1 = (flags >> 2) & 0x03;
    final lane2 = (flags >> 4) & 0x03;
    if (lane0 < 3 && lane1 < 3 && lane2 < 3) {
      return (
        _storageModeFromV2Id(lane0),
        _languageFromV2Id(lane1),
        _themeModeFromV2Id(lane2),
        true,
      );
    }
    final int comboIndex;
    if (lane0 == 3) {
      comboIndex = (flags >> 2) & 0x0F;
    } else if (lane1 == 3) {
      final remainder = lane0 + (lane2 * 3);
      if (remainder > 10) {
        _throwCorrupt('Invalid legacy TTW v2 flag combination.');
      }
      comboIndex = 16 + remainder;
    } else {
      _throwCorrupt('Reserved legacy TTW v2 flag bit pattern.');
    }
    return (
      _storageModeFromV2Id(comboIndex % 3),
      _languageFromV2Id((comboIndex ~/ 3) % 3),
      _themeModeFromV2Id(comboIndex ~/ 9),
      false,
    );
  }

  /// Decodes `(manualTimeZoneOffsetMinutes, logStorageMode)` from [flags] bit 7 and [tzWord].
  static (int, StorageMode) _decodeOffsetAndLogStorage(int flags, int tzWord) {
    final rawOffsetField = tzWord & 0x07FF;
    final hasRemoteLogBit = ((flags >> 7) & 0x01) == 1;
    if (!hasRemoteLogBit) {
      return (
        rawOffsetField + WebDavConfig.minUtcOffsetMinutes,
        StorageMode.local,
      );
    }
    if (rawOffsetField <= 1560) {
      return (
        rawOffsetField + WebDavConfig.minUtcOffsetMinutes,
        StorageMode.webdav,
      );
    }
    final decodedOffset =
        ((rawOffsetField - 1561) * 5) + WebDavConfig.minUtcOffsetMinutes;
    return (decodedOffset, StorageMode.both);
  }

  /// Decodes and validates a single `TTW\x02` [AppWorkspace] record from [source] at [offset].
  static (AppWorkspace, int) _decodeRecord(
    Uint8List source,
    int offset,
    List<WorkspaceSummary> existing,
  ) {
    if (offset >= source.length) {
      _throwCorrupt('Unexpected end of legacy TTW v2 workspace record.');
    }
    final flags = source[offset];
    final fields = <String>[];
    var cursor = offset + 1;
    for (var i = 0; i < 7; i++) {
      final (decoded, nextCursor) = _readString(source, cursor);
      fields.add(decoded);
      cursor = nextCursor;
    }
    if (cursor + 3 > source.length) {
      _throwCorrupt('Truncated trailing bytes in legacy TTW v2 record.');
    }
    final tzWord = (source[cursor] << 8) | source[cursor + 1];
    final rawDueLead = source[cursor + 2];
    cursor += 3;
    if (rawDueLead > 5) {
      _throwCorrupt('Legacy TTW v2 record contains invalid due lead window.');
    }

    final (storageMode, language, themeMode, localWatchEnabled) =
        _decodeLowFlagsBits(flags);
    final (manualOffsetMinutes, logStorageMode) = _decodeOffsetAndLogStorage(
      flags,
      tzWord,
    );
    final filePath = fields[5].trim();
    final localPath = fields[6].trim();
    final workspace = AppWorkspace(
      id: fields[0].trim().isEmpty ? AppWorkspace.defaultId : fields[0].trim(),
      name: fields[1].trim().isEmpty
          ? AppWorkspace.defaultName
          : fields[1].trim(),
      config: WebDavConfig(
        serverUrl: fields[2].trim(),
        username: fields[3].trim(),
        password: fields[4],
        filePath: filePath.isEmpty ? AppWorkspace.defaultFileName : filePath,
        localFilePath: localPath.isEmpty
            ? AppWorkspace.defaultFileName
            : localPath,
        storageMode: storageMode,
        language: language,
        themeMode: themeMode,
        themePalette: _themePaletteFromV2Id((flags >> 6) & 0x01),
        locationEnabled: ((tzWord >> 14) & 0x01) == 1,
        timeZoneMode: _timeZoneModeFromV2Id((tzWord >> 15) & 0x01),
        manualTimeZoneOffsetMinutes: manualOffsetMinutes,
        diagnosticsEnabled: ((tzWord >> 13) & 0x01) == 1,
        logLevel: _decodeLogLevelBits((tzWord >> 11) & 0x03),
        logStorageMode: logStorageMode,
        localWatchEnabled: localWatchEnabled,
        dueLeadWindow: _dueLeadWindowFromV2Id(rawDueLead),
      ),
    );
    _validateDecodedWorkspace(workspace, existing);
    return (workspace, cursor);
  }

  /// Resolves a `TTW\x02` due-lead byte (`0..5`) into a [DueLeadWindow].
  static DueLeadWindow _dueLeadWindowFromV2Id(int rawId) => switch (rawId) {
    0 => DueLeadWindow.off,
    1 => DueLeadWindow.atDue,
    2 => DueLeadWindow.hours12,
    3 => DueLeadWindow.hours24,
    4 => DueLeadWindow.hours48,
    5 => DueLeadWindow.days7,
    _ => DueLeadWindow.hours24,
  };

  /// Resolves a `TTW\x02` language ID (`0..2`) into an [AppLanguage].
  static AppLanguage _languageFromV2Id(int rawId) => switch (rawId) {
    1 => AppLanguage.english,
    2 => AppLanguage.german,
    _ => AppLanguage.system,
  };

  /// Reads a 16-bit big-endian length-prefixed UTF-8 string from [source] at [offset].
  static (String, int) _readString(Uint8List source, int offset) {
    final end = offset + 2 > source.length
        ? source.length + 1
        : offset + 2 + ((source[offset] << 8) | source[offset + 1]);
    if (end > source.length) {
      _throwCorrupt('Truncated string in legacy TTW v2 workspace record.');
    }
    try {
      final view = Uint8List.sublistView(source, offset + 2, end);
      return (_utf8Codec.decode(view), end);
    } on FormatException catch (error) {
      throw WorkspaceException(
        WorkspaceErrorKind.corruptSettingsPayload,
        'Invalid UTF-8 string in legacy TTW v2 workspace record.',
        cause: error,
      );
    }
  }

  /// Resolves a `TTW\x02` storage mode ID (`0..2`) into a [StorageMode].
  static StorageMode _storageModeFromV2Id(int rawId) => switch (rawId) {
    1 => StorageMode.webdav,
    2 => StorageMode.both,
    _ => StorageMode.local,
  };

  /// Resolves a `TTW\x02` theme mode ID (`0..2`) into an [AppThemeMode].
  static AppThemeMode _themeModeFromV2Id(int rawId) => switch (rawId) {
    1 => AppThemeMode.light,
    2 => AppThemeMode.dark,
    _ => AppThemeMode.system,
  };

  /// Resolves a legacy `TTW\x02` palette ID (`0..1`) silently to [AppThemePalette.calm].
  static AppThemePalette _themePaletteFromV2Id(int rawId) => switch (rawId) {
    0 || 1 => AppThemePalette.calm,
    _ => AppThemePalette.calm,
  };

  /// Throws a [WorkspaceException] with [WorkspaceErrorKind.corruptSettingsPayload].
  static Never _throwCorrupt(String message) => throw WorkspaceException(
    WorkspaceErrorKind.corruptSettingsPayload,
    message,
  );

  /// Resolves a `TTW\x02` time zone mode ID (`0..1`) into an [AppTimeZoneMode].
  static AppTimeZoneMode _timeZoneModeFromV2Id(int rawId) => switch (rawId) {
    1 => AppTimeZoneMode.manual,
    _ => AppTimeZoneMode.automatic,
  };

  /// Validates that [workspace] has a unique non-control ID, valid name, and unique paths.
  static void _validateDecodedWorkspace(
    AppWorkspace workspace,
    List<WorkspaceSummary> existing,
  ) {
    if (workspace.id.isEmpty ||
        AppWorkspace.hasControlCharacters(workspace.id) ||
        existing.any((summary) => summary.id == workspace.id)) {
      _throwCorrupt('Decoded legacy workspace ID is invalid or duplicated.');
    }
    try {
      AppWorkspace.validateName(workspace.name, existing);
      AppWorkspace.validateConfigPaths(workspace.config, existing);
    } on WorkspaceException catch (error) {
      throw WorkspaceException(
        WorkspaceErrorKind.corruptSettingsPayload,
        error.message,
        cause: error,
      );
    }
  }

  /// Validates the 6-byte `TTW\x02` header strictly (rejecting `TTW\x01` and all other versions).
  static ({int count, int activeIndex}) _validateV2Header(List<int> bytes) {
    if (bytes.length < _binaryHeaderBytes || bytes.length > maxBinaryBytes) {
      _throwCorrupt('Legacy TTW v2 payload size is out of bounds.');
    }
    final version = bytes[3];
    final count = bytes[4];
    final activeIndex = bytes[5];
    if (bytes[0] != 0x54 ||
        bytes[1] != 0x54 ||
        bytes[2] != 0x57 ||
        version != _binaryVersionV2 ||
        count < 1 ||
        count > AppWorkspace.maxWorkspaces ||
        activeIndex < 0 ||
        activeIndex >= count) {
      _throwCorrupt('Legacy TTW v2 header is invalid or unsupported.');
    }
    return (count: count, activeIndex: activeIndex);
  }
}
