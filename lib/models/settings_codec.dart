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

import 'dart:convert' show JsonEncoder, Utf8Codec, jsonDecode;

import 'package:flutter/foundation.dart';

import '../services/app_logger.dart';
import 'app_workspace.dart';
import 'webdav_config.dart';

/// Categorizes a startup recovery action taken while loading `settings.json`.
enum SettingsRecoveryKind {
  /// Primary `settings.json` was corrupt or missing and restored from `settings.json.bak`.
  recoveredFromBackup,

  /// Corrupt settings file(s) were quarantined and reset to [PersistedSettingsDocument.initial].
  resetAfterQuarantine,
}

/// Immutable, versioned representation of the persisted `settings.json` document.
@immutable
class PersistedSettingsDocument {
  /// Creates an immutable [PersistedSettingsDocument] with unmodifiable collections.
  factory PersistedSettingsDocument({
    required int schemaVersion,
    required String activeWorkspaceId,
    required List<AppWorkspace> workspaces,
    Set<String> passwordStoredWorkspaceIds = const <String>{},
    Map<String, Object?> unknownRootFields = const <String, Object?>{},
    Map<String, Map<String, Object?>> unknownWorkspaceFieldsById =
        const <String, Map<String, Object?>>{},
  }) {
    final frozenWorkspaceUnknowns = <String, Map<String, Object?>>{
      for (final entry in unknownWorkspaceFieldsById.entries)
        entry.key: Map<String, Object?>.unmodifiable(entry.value),
    };
    return PersistedSettingsDocument._(
      schemaVersion: schemaVersion,
      activeWorkspaceId: activeWorkspaceId,
      workspaces: List<AppWorkspace>.unmodifiable(workspaces),
      passwordStoredWorkspaceIds: Set<String>.unmodifiable(
        passwordStoredWorkspaceIds,
      ),
      unknownRootFields: Map<String, Object?>.unmodifiable(unknownRootFields),
      unknownWorkspaceFieldsById:
          Map<String, Map<String, Object?>>.unmodifiable(
            frozenWorkspaceUnknowns,
          ),
    );
  }

  /// Internal const constructor backing [initial] and factory-validated instances.
  const PersistedSettingsDocument._({
    required this.schemaVersion,
    required this.activeWorkspaceId,
    required this.workspaces,
    this.passwordStoredWorkspaceIds = const <String>{},
    this.unknownRootFields = const <String, Object?>{},
    this.unknownWorkspaceFieldsById = const <String, Map<String, Object?>>{},
  });

  /// Canonical default settings document containing the single `Tasks` workspace.
  static const PersistedSettingsDocument initial = PersistedSettingsDocument._(
    schemaVersion: SettingsCodec.currentSchemaVersion,
    activeWorkspaceId: AppWorkspace.defaultId,
    workspaces: <AppWorkspace>[AppWorkspace.defaultWorkspace],
  );

  /// Identifier of the currently active workspace.
  final String activeWorkspaceId;

  /// Workspace identifiers that currently have a WebDAV password key stored in secure storage.
  final Set<String> passwordStoredWorkspaceIds;

  /// Positive integer schema version of this settings document.
  final int schemaVersion;

  /// Unrecognized top-level JSON keys preserved losslessly across saves.
  final Map<String, Object?> unknownRootFields;

  /// Unrecognized per-workspace JSON keys keyed by workspace identifier.
  final Map<String, Map<String, Object?>> unknownWorkspaceFieldsById;

  /// Ordered, unmodifiable list of persisted workspaces (`1..32`).
  final List<AppWorkspace> workspaces;

  /// Returns a copy of this document with updated fields.
  PersistedSettingsDocument copyWith({
    int? schemaVersion,
    String? activeWorkspaceId,
    List<AppWorkspace>? workspaces,
    Set<String>? passwordStoredWorkspaceIds,
    Map<String, Object?>? unknownRootFields,
    Map<String, Map<String, Object?>>? unknownWorkspaceFieldsById,
  }) {
    return PersistedSettingsDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
      workspaces: workspaces ?? this.workspaces,
      passwordStoredWorkspaceIds:
          passwordStoredWorkspaceIds ?? this.passwordStoredWorkspaceIds,
      unknownRootFields: unknownRootFields ?? this.unknownRootFields,
      unknownWorkspaceFieldsById:
          unknownWorkspaceFieldsById ?? this.unknownWorkspaceFieldsById,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PersistedSettingsDocument &&
        other.schemaVersion == schemaVersion &&
        other.activeWorkspaceId == activeWorkspaceId &&
        listEquals(other.workspaces, workspaces) &&
        setEquals(
          other.passwordStoredWorkspaceIds,
          passwordStoredWorkspaceIds,
        ) &&
        _jsonDeepEquals(other.unknownRootFields, unknownRootFields) &&
        _jsonDeepEquals(
          other.unknownWorkspaceFieldsById,
          unknownWorkspaceFieldsById,
        );
  }

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    activeWorkspaceId,
    Object.hashAll(workspaces),
    Object.hashAllUnordered(passwordStoredWorkspaceIds),
    _jsonDeepHash(unknownRootFields),
    _jsonDeepHash(unknownWorkspaceFieldsById),
  );
}

/// Stateless UTF-8 JSON encoder and resilient decoder for `settings.json`.
class SettingsCodec {
  const SettingsCodec._();

  /// Current supported `settings.json` schema version (`1`).
  static const int currentSchemaVersion = 1;

  /// Maximum allowed UTF-8 byte length for `settings.json` (`256 KiB`).
  static const int maxJsonBytes = 262144;

  /// Maximum allowed nesting depth for preserved unknown JSON values (`16`).
  static const int maxJsonNestingDepth = 16;

  /// Canonical file name for host-local application settings.
  static const String settingsFileName = 'settings.json';

  static const JsonEncoder _jsonEncoder = JsonEncoder.withIndent('  ');
  static const Set<String> _knownRootKeys = <String>{
    'schemaVersion',
    'activeWorkspaceId',
    'workspaces',
  };
  static const Set<String> _knownWorkspaceKeys = <String>{
    'id',
    'name',
    'storageMode',
    'localFilePath',
    'serverUrl',
    'username',
    'filePath',
    'hasWebDavPassword',
    'language',
    'themeMode',
    'themePalette',
    'locationEnabled',
    'timeZoneMode',
    'manualTimeZoneOffsetMinutes',
    'diagnosticsEnabled',
    'logLevel',
    'logStorageMode',
    'localWatchEnabled',
    'dueLeadWindow',
  };
  static const Utf8Codec _utf8Codec = Utf8Codec(allowMalformed: false);

  /// Decodes UTF-8 [bytes] into a [SettingsDecodeResult] with per-field fallbacks and warnings.
  static SettingsDecodeResult decodeJsonBytes(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxJsonBytes) {
      throw const WorkspaceException(
        WorkspaceErrorKind.corruptSettingsPayload,
        'Settings JSON payload size is out of bounds.',
      );
    }
    final rootObject = _decodeRootMap(bytes);
    final schemaVersion = _validateSchemaVersion(rootObject['schemaVersion']);
    final rawWorkspaces = _validateRawWorkspacesList(rootObject['workspaces']);

    final warnings = <SettingsDecodeWarning>[];
    final unknownRootFields = _extractUnknownFields(
      rootObject,
      knownKeys: _knownRootKeys,
      warnings: warnings,
      workspaceId: null,
    );
    final decodedEntries = _decodeWorkspaceEntries(rawWorkspaces, warnings);
    final activeWorkspaceId = _resolveActiveWorkspaceId(
      rootObject['activeWorkspaceId'],
      decodedEntries.workspaces,
      warnings,
    );

    final document = PersistedSettingsDocument(
      schemaVersion: schemaVersion,
      activeWorkspaceId: activeWorkspaceId,
      workspaces: decodedEntries.workspaces,
      passwordStoredWorkspaceIds: decodedEntries.passwordStoredIds,
      unknownRootFields: unknownRootFields,
      unknownWorkspaceFieldsById: decodedEntries.unknownByWorkspaceId,
    );
    return SettingsDecodeResult(
      document: document,
      warnings: List<SettingsDecodeWarning>.unmodifiable(warnings),
    );
  }

  /// Encodes [document] into canonical indented UTF-8 JSON with a trailing newline, never emitting passwords.
  static String encodeJson(PersistedSettingsDocument document) {
    final workspaces = document.workspaces.isEmpty
        ? const <AppWorkspace>[AppWorkspace.defaultWorkspace]
        : document.workspaces;
    final encodedWorkspaces = <Map<String, Object?>>[
      for (final workspace in workspaces)
        _encodeWorkspaceObject(
          workspace,
          hasWebDavPassword: document.passwordStoredWorkspaceIds.contains(
            workspace.id,
          ),
          unknownFields: document.unknownWorkspaceFieldsById[workspace.id],
        ),
    ];

    final rootMap = <String, Object?>{};
    _copySanitizedUnknowns(
      document.unknownRootFields,
      target: rootMap,
      excludedKeys: _knownRootKeys,
    );
    rootMap['schemaVersion'] = document.schemaVersion;
    rootMap['activeWorkspaceId'] = document.activeWorkspaceId;
    rootMap['workspaces'] = encodedWorkspaces;

    final formatted = '${_jsonEncoder.convert(rootMap)}\n';
    final utf8Bytes = _utf8Codec.encode(formatted);
    if (utf8Bytes.length > maxJsonBytes) {
      throw const WorkspaceException(
        WorkspaceErrorKind.corruptSettingsPayload,
        'Encoded settings JSON payload exceeds maximum allowed size.',
      );
    }
    return formatted;
  }

  /// Copies sanitized unknown JSON entries from [source] into [target], skipping [excludedKeys] and `'password'`.
  static void _copySanitizedUnknowns(
    Map<String, Object?>? source, {
    required Map<String, Object?> target,
    required Set<String> excludedKeys,
  }) {
    if (source == null || source.isEmpty) {
      return;
    }
    final sortedKeys = source.keys.toList()..sort();
    for (final key in sortedKeys) {
      if (excludedKeys.contains(key) || key == 'password') {
        continue;
      }
      final sanitized = _sanitizeJsonValue(source[key], depth: 1);
      if (sanitized.valid) {
        target[key] = sanitized.value;
      }
    }
  }

  /// Decodes a boolean property from [source] at [key] or falls back to [fallback] with a warning.
  static bool _decodeBoolField(
    Map<String, Object?> source,
    String key, {
    required bool fallback,
    required String workspaceId,
    required List<SettingsDecodeWarning> warnings,
  }) {
    if (!source.containsKey(key)) {
      return fallback;
    }
    final rawValue = source[key];
    if (rawValue is bool) {
      return rawValue;
    }
    warnings.add(
      SettingsDecodeWarning(
        field: key,
        reason: 'invalid_type',
        workspaceId: workspaceId,
      ),
    );
    return fallback;
  }

  /// Decodes a configurable [LogLevel] token (`debug`, `info`, `warn`, `error`) or falls back to [LogLevel.info].
  static LogLevel _decodeConfigurableLogLevel(
    Map<String, Object?> source, {
    required String workspaceId,
    required List<SettingsDecodeWarning> warnings,
  }) {
    if (!source.containsKey('logLevel')) {
      return LogLevel.info;
    }
    final rawValue = source['logLevel'];
    if (rawValue is String) {
      final parsed = switch (rawValue.trim().toLowerCase()) {
        'debug' => LogLevel.debug,
        'info' => LogLevel.info,
        'warn' => LogLevel.warn,
        'error' => LogLevel.error,
        _ => null,
      };
      if (parsed != null) {
        return parsed;
      }
    }
    warnings.add(
      SettingsDecodeWarning(
        field: 'logLevel',
        reason: 'invalid_value',
        workspaceId: workspaceId,
      ),
    );
    return LogLevel.info;
  }

  /// Decodes a canonical enum property using [parser], falling back to [fallback] with a warning.
  static T _decodeEnumField<T>(
    Map<String, Object?> source,
    String key, {
    required T? Function(String?) parser,
    required T fallback,
    required String workspaceId,
    required List<SettingsDecodeWarning> warnings,
  }) {
    if (!source.containsKey(key)) {
      return fallback;
    }
    final rawValue = source[key];
    if (rawValue is String) {
      final parsed = parser(rawValue);
      if (parsed != null) {
        return parsed;
      }
    }
    warnings.add(
      SettingsDecodeWarning(
        field: key,
        reason: 'invalid_value',
        workspaceId: workspaceId,
      ),
    );
    return fallback;
  }

  /// Decodes `manualTimeZoneOffsetMinutes` within `-720..840`, falling back to `0` with a warning.
  static int _decodeManualUtcOffset(
    Map<String, Object?> source, {
    required String workspaceId,
    required List<SettingsDecodeWarning> warnings,
  }) {
    if (!source.containsKey('manualTimeZoneOffsetMinutes')) {
      return 0;
    }
    final rawValue = source['manualTimeZoneOffsetMinutes'];
    if (rawValue is int &&
        rawValue >= WebDavConfig.minUtcOffsetMinutes &&
        rawValue <= WebDavConfig.maxUtcOffsetMinutes) {
      return rawValue;
    }
    warnings.add(
      SettingsDecodeWarning(
        field: 'manualTimeZoneOffsetMinutes',
        reason: 'out_of_range',
        workspaceId: workspaceId,
      ),
    );
    return 0;
  }

  /// Decodes a required non-empty trimmed path field, defaulting to [AppWorkspace.defaultFileName] with a warning.
  static String _decodePathField(
    Map<String, Object?> source,
    String key, {
    required String workspaceId,
    required List<SettingsDecodeWarning> warnings,
  }) {
    final rawValue = source[key];
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return rawValue.trim();
    }
    warnings.add(
      SettingsDecodeWarning(
        field: key,
        reason: rawValue == null ? 'missing_defaulted' : 'invalid_value',
        workspaceId: workspaceId,
      ),
    );
    return AppWorkspace.defaultFileName;
  }

  /// Strictly decodes UTF-8 [bytes] and verifies the root JSON value is a JSON object map.
  static Map<String, Object?> _decodeRootMap(List<int> bytes) {
    final String jsonText;
    try {
      jsonText = _utf8Codec.decode(bytes);
    } on FormatException catch (error) {
      throw WorkspaceException(
        WorkspaceErrorKind.corruptSettingsPayload,
        'Settings file is not valid UTF-8.',
        cause: error,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      throw WorkspaceException(
        WorkspaceErrorKind.corruptSettingsPayload,
        'Settings file is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<Object?, Object?>) {
      throw const WorkspaceException(
        WorkspaceErrorKind.corruptSettingsPayload,
        'Settings JSON root must be an object.',
      );
    }
    return _castStringKeyMap(decoded);
  }

  /// Decodes a single workspace JSON entry or returns `null` after recording a warning when invalid.
  static ({
    AppWorkspace workspace,
    bool hasPassword,
    Map<String, Object?> unknownFields,
  })?
  _decodeSingleWorkspace(
    Object? rawEntry,
    int entryIndex,
    List<WorkspaceSummary> acceptedSummaries,
    Set<String> acceptedIds,
    List<SettingsDecodeWarning> warnings,
  ) {
    if (rawEntry is! Map<Object?, Object?>) {
      warnings.add(
        SettingsDecodeWarning(
          field: 'workspaces[$entryIndex]',
          reason: 'invalid_workspace_object',
        ),
      );
      return null;
    }
    final entryMap = _castStringKeyMap(rawEntry);
    final rawId = entryMap['id'];
    final id = rawId is String ? rawId.trim() : '';
    if (id.isEmpty ||
        AppWorkspace.hasControlCharacters(id) ||
        acceptedIds.contains(id)) {
      warnings.add(
        SettingsDecodeWarning(
          field: 'workspaces[$entryIndex].id',
          reason: 'invalid_or_duplicate_id',
        ),
      );
      return null;
    }

    final rawName = entryMap['name'];
    if (rawName is! String) {
      warnings.add(
        SettingsDecodeWarning(
          field: 'name',
          reason: 'invalid_type',
          workspaceId: id,
        ),
      );
      return null;
    }

    final String validatedName;
    try {
      validatedName = AppWorkspace.validateName(rawName, acceptedSummaries);
    } on WorkspaceException {
      warnings.add(
        SettingsDecodeWarning(
          field: 'name',
          reason: 'invalid_or_duplicate_name',
          workspaceId: id,
        ),
      );
      return null;
    }

    final entryWarnings = <SettingsDecodeWarning>[];
    final config = _decodeWorkspaceConfig(entryMap, id, entryWarnings);
    try {
      AppWorkspace.validateConfigPaths(config, acceptedSummaries);
    } on WorkspaceException {
      warnings.add(
        SettingsDecodeWarning(
          field: 'paths',
          reason: 'invalid_or_duplicate_path',
          workspaceId: id,
        ),
      );
      return null;
    }

    final hasPassword = _decodeBoolField(
      entryMap,
      'hasWebDavPassword',
      fallback: false,
      workspaceId: id,
      warnings: entryWarnings,
    );
    final unknownFields = _extractUnknownFields(
      entryMap,
      knownKeys: _knownWorkspaceKeys,
      warnings: entryWarnings,
      workspaceId: id,
    );
    warnings.addAll(entryWarnings);
    return (
      workspace: AppWorkspace(id: id, name: validatedName, config: config),
      hasPassword: hasPassword,
      unknownFields: unknownFields,
    );
  }

  /// Decodes an optional trimmed string property from [source] at [key], falling back to `''` with a warning.
  static String _decodeTrimmedStringField(
    Map<String, Object?> source,
    String key, {
    required String workspaceId,
    required List<SettingsDecodeWarning> warnings,
  }) {
    if (!source.containsKey(key)) {
      return '';
    }
    final rawValue = source[key];
    if (rawValue is String) {
      return rawValue.trim();
    }
    warnings.add(
      SettingsDecodeWarning(
        field: key,
        reason: 'invalid_type',
        workspaceId: workspaceId,
      ),
    );
    return '';
  }

  /// Decodes all non-secret [WebDavConfig] fields from [entryMap] with per-field warnings.
  static WebDavConfig _decodeWorkspaceConfig(
    Map<String, Object?> entryMap,
    String workspaceId,
    List<SettingsDecodeWarning> warnings,
  ) {
    final storageMode = _decodeEnumField<StorageMode>(
      entryMap,
      'storageMode',
      parser: StorageMode.tryParseJson,
      fallback: StorageMode.local,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final localFilePath = _decodePathField(
      entryMap,
      'localFilePath',
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final filePath = _decodePathField(
      entryMap,
      'filePath',
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final serverUrl = _decodeTrimmedStringField(
      entryMap,
      'serverUrl',
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final username = _decodeTrimmedStringField(
      entryMap,
      'username',
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final language = _decodeEnumField<AppLanguage>(
      entryMap,
      'language',
      parser: AppLanguage.tryParseJson,
      fallback: AppLanguage.system,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final themeMode = _decodeEnumField<AppThemeMode>(
      entryMap,
      'themeMode',
      parser: AppThemeMode.tryParseJson,
      fallback: AppThemeMode.system,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final themePalette = _decodeEnumField<AppThemePalette>(
      entryMap,
      'themePalette',
      parser: AppThemePalette.tryParseJson,
      fallback: AppThemePalette.calm,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final locationEnabled = _decodeBoolField(
      entryMap,
      'locationEnabled',
      fallback: false,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final timeZoneMode = _decodeEnumField<AppTimeZoneMode>(
      entryMap,
      'timeZoneMode',
      parser: AppTimeZoneMode.tryParseJson,
      fallback: AppTimeZoneMode.automatic,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final manualUtcOffset = _decodeManualUtcOffset(
      entryMap,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final diagnosticsEnabled = _decodeBoolField(
      entryMap,
      'diagnosticsEnabled',
      fallback: false,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final logLevel = _decodeConfigurableLogLevel(
      entryMap,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final logStorageMode = _decodeEnumField<StorageMode>(
      entryMap,
      'logStorageMode',
      parser: StorageMode.tryParseJson,
      fallback: StorageMode.local,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final localWatchEnabled = _decodeBoolField(
      entryMap,
      'localWatchEnabled',
      fallback: true,
      workspaceId: workspaceId,
      warnings: warnings,
    );
    final dueLeadWindow = _decodeEnumField<DueLeadWindow>(
      entryMap,
      'dueLeadWindow',
      parser: DueLeadWindow.tryParseJson,
      fallback: DueLeadWindow.hours24,
      workspaceId: workspaceId,
      warnings: warnings,
    );

    return WebDavConfig(
      serverUrl: serverUrl,
      username: username,
      filePath: filePath,
      localFilePath: localFilePath,
      storageMode: storageMode,
      language: language,
      themeMode: themeMode,
      themePalette: themePalette,
      locationEnabled: locationEnabled,
      timeZoneMode: timeZoneMode,
      manualTimeZoneOffsetMinutes: manualUtcOffset,
      diagnosticsEnabled: diagnosticsEnabled,
      logLevel: logLevel,
      logStorageMode: logStorageMode,
      localWatchEnabled: localWatchEnabled,
      dueLeadWindow: dueLeadWindow,
    );
  }

  /// Decodes all workspace entries in [rawWorkspaces], throwing when zero valid workspaces survive.
  static ({
    List<AppWorkspace> workspaces,
    Set<String> passwordStoredIds,
    Map<String, Map<String, Object?>> unknownByWorkspaceId,
  })
  _decodeWorkspaceEntries(
    List<Object?> rawWorkspaces,
    List<SettingsDecodeWarning> warnings,
  ) {
    final workspaces = <AppWorkspace>[];
    final summaries = <WorkspaceSummary>[];
    final acceptedIds = <String>{};
    final passwordStoredIds = <String>{};
    final unknownByWorkspaceId = <String, Map<String, Object?>>{};

    for (var i = 0; i < rawWorkspaces.length; i++) {
      final decoded = _decodeSingleWorkspace(
        rawWorkspaces[i],
        i,
        summaries,
        acceptedIds,
        warnings,
      );
      if (decoded == null) {
        continue;
      }
      final workspace = decoded.workspace;
      workspaces.add(workspace);
      summaries.add(workspace.summary);
      acceptedIds.add(workspace.id);
      if (decoded.hasPassword) {
        passwordStoredIds.add(workspace.id);
      }
      if (decoded.unknownFields.isNotEmpty) {
        unknownByWorkspaceId[workspace.id] = decoded.unknownFields;
      }
    }

    if (workspaces.isEmpty) {
      throw const WorkspaceException(
        WorkspaceErrorKind.corruptSettingsPayload,
        'Settings JSON contains zero valid workspaces.',
      );
    }
    return (
      workspaces: workspaces,
      passwordStoredIds: passwordStoredIds,
      unknownByWorkspaceId: unknownByWorkspaceId,
    );
  }

  /// Encodes a single [workspace] into a JSON object map without ever writing a password.
  static Map<String, Object?> _encodeWorkspaceObject(
    AppWorkspace workspace, {
    required bool hasWebDavPassword,
    Map<String, Object?>? unknownFields,
  }) {
    final config = workspace.config;
    final object = <String, Object?>{};
    _copySanitizedUnknowns(
      unknownFields,
      target: object,
      excludedKeys: _knownWorkspaceKeys,
    );
    object['id'] = workspace.id.trim();
    object['name'] = workspace.name.trim();
    object['storageMode'] = config.storageMode.jsonValue;
    object['localFilePath'] = config.localFilePath.trim();
    object['serverUrl'] = config.serverUrl.trim();
    object['username'] = config.username.trim();
    object['filePath'] = config.filePath.trim();
    object['hasWebDavPassword'] = hasWebDavPassword;
    object['language'] = config.language.jsonValue;
    object['themeMode'] = config.themeMode.jsonValue;
    object['themePalette'] = config.themePalette.jsonValue;
    object['locationEnabled'] = config.locationEnabled;
    object['timeZoneMode'] = config.timeZoneMode.jsonValue;
    object['manualTimeZoneOffsetMinutes'] = config.manualTimeZoneOffsetMinutes;
    object['diagnosticsEnabled'] = config.diagnosticsEnabled;
    object['logLevel'] = _encodeConfigurableLogLevel(config.logLevel);
    object['logStorageMode'] = config.logStorageMode.jsonValue;
    object['localWatchEnabled'] = config.localWatchEnabled;
    object['dueLeadWindow'] = config.dueLeadWindow.jsonValue;
    return object;
  }

  /// Encodes [level] to its canonical lowercase configurable JSON token.
  static String _encodeConfigurableLogLevel(LogLevel level) => switch (level) {
    LogLevel.debug => 'debug',
    LogLevel.info => 'info',
    LogLevel.warn => 'warn',
    LogLevel.error || LogLevel.crash => 'error',
  };

  /// Extracts and freezes unrecognized keys from [source], omitting `'password'` and values exceeding depth bounds.
  static Map<String, Object?> _extractUnknownFields(
    Map<String, Object?> source, {
    required Set<String> knownKeys,
    required List<SettingsDecodeWarning> warnings,
    required String? workspaceId,
  }) {
    final preserved = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key;
      if (knownKeys.contains(key) || key == 'password') {
        continue;
      }
      final sanitized = _sanitizeJsonValue(entry.value, depth: 1);
      if (!sanitized.valid) {
        warnings.add(
          SettingsDecodeWarning(
            field: key,
            reason: 'invalid_unknown_value',
            workspaceId: workspaceId,
          ),
        );
        continue;
      }
      preserved[key] = sanitized.value;
    }
    return Map<String, Object?>.unmodifiable(preserved);
  }

  /// Resolves `activeWorkspaceId` against decoded [workspaces], falling back to the first workspace with a warning.
  static String _resolveActiveWorkspaceId(
    Object? rawActiveId,
    List<AppWorkspace> workspaces,
    List<SettingsDecodeWarning> warnings,
  ) {
    if (rawActiveId is String) {
      final trimmed = rawActiveId.trim();
      for (final workspace in workspaces) {
        if (workspace.id == trimmed) {
          return workspace.id;
        }
      }
    }
    warnings.add(
      const SettingsDecodeWarning(
        field: 'activeWorkspaceId',
        reason: 'missing_or_unknown_active_id',
      ),
    );
    return workspaces.first.id;
  }

  /// Validates that [rawWorkspaces] is a non-empty list with at most [AppWorkspace.maxWorkspaces] entries.
  static List<Object?> _validateRawWorkspacesList(Object? rawWorkspaces) {
    if (rawWorkspaces is! List<Object?> ||
        rawWorkspaces.isEmpty ||
        rawWorkspaces.length > AppWorkspace.maxWorkspaces) {
      throw const WorkspaceException(
        WorkspaceErrorKind.corruptSettingsPayload,
        'Settings JSON must contain between 1 and 32 workspaces.',
      );
    }
    return rawWorkspaces;
  }

  /// Validates that [rawVersion] is an integer `>= 1` and `<= currentSchemaVersion`.
  static int _validateSchemaVersion(Object? rawVersion) {
    if (rawVersion is! int || rawVersion < 1) {
      throw const WorkspaceException(
        WorkspaceErrorKind.corruptSettingsPayload,
        'Settings JSON schemaVersion is missing or invalid.',
      );
    }
    if (rawVersion > currentSchemaVersion) {
      throw WorkspaceException(
        WorkspaceErrorKind.unsupportedSettingsSchemaVersion,
        'Settings schemaVersion $rawVersion is newer than supported version '
        '$currentSchemaVersion.',
        cause: rawVersion,
      );
    }
    return rawVersion;
  }

  /// Validates and freezes an arbitrary JSON value up to [maxJsonNestingDepth].
  static ({bool valid, Object? value}) _sanitizeJsonValue(
    Object? value, {
    required int depth,
  }) {
    if (value == null || value is bool || value is int || value is String) {
      return (valid: true, value: value);
    }
    if (value is double) {
      return value.isFinite
          ? (valid: true, value: value)
          : (valid: false, value: null);
    }
    if (depth > maxJsonNestingDepth) {
      return (valid: false, value: null);
    }
    if (value is List<Object?>) {
      return _sanitizeJsonList(value, depth: depth);
    }
    if (value is Map<Object?, Object?>) {
      return _sanitizeJsonMap(value, depth: depth);
    }
    return (valid: false, value: null);
  }

  /// Validates and freezes every element of [items] at [depth].
  static ({bool valid, Object? value}) _sanitizeJsonList(
    List<Object?> items, {
    required int depth,
  }) {
    final result = <Object?>[];
    for (final item in items) {
      final sanitized = _sanitizeJsonValue(item, depth: depth + 1);
      if (!sanitized.valid) {
        return (valid: false, value: null);
      }
      result.add(sanitized.value);
    }
    return (valid: true, value: List<Object?>.unmodifiable(result));
  }

  /// Validates and freezes every entry of [source] at [depth], requiring `String` keys.
  static ({bool valid, Object? value}) _sanitizeJsonMap(
    Map<Object?, Object?> source, {
    required int depth,
  }) {
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key;
      if (key is! String) {
        return (valid: false, value: null);
      }
      final sanitized = _sanitizeJsonValue(entry.value, depth: depth + 1);
      if (!sanitized.valid) {
        return (valid: false, value: null);
      }
      result[key] = sanitized.value;
    }
    return (valid: true, value: Map<String, Object?>.unmodifiable(result));
  }
}

/// Result of decoding a `settings.json` payload, combining the document and non-fatal warnings.
@immutable
class SettingsDecodeResult {
  /// Creates a [SettingsDecodeResult].
  const SettingsDecodeResult({
    required this.document,
    this.warnings = const <SettingsDecodeWarning>[],
  });

  /// Decoded settings document.
  final PersistedSettingsDocument document;

  /// Non-fatal per-field fallback warnings recorded during decoding.
  final List<SettingsDecodeWarning> warnings;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SettingsDecodeResult &&
        other.document == document &&
        listEquals(other.warnings, warnings);
  }

  @override
  int get hashCode => Object.hash(document, Object.hashAll(warnings));
}

/// Non-fatal field-level fallback recorded while decoding `settings.json`.
@immutable
class SettingsDecodeWarning {
  /// Creates a [SettingsDecodeWarning].
  const SettingsDecodeWarning({
    required this.field,
    required this.reason,
    this.workspaceId,
  });

  /// JSON property name or workspace entry slot that triggered the warning.
  final String field;

  /// Static machine-readable reason token (e.g. `invalid_value`, `out_of_range`).
  final String reason;

  /// Identifier of the workspace containing the field, or `null` for root-level fields.
  final String? workspaceId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SettingsDecodeWarning &&
        other.field == field &&
        other.reason == reason &&
        other.workspaceId == workspaceId;
  }

  @override
  int get hashCode => Object.hash(field, reason, workspaceId);

  @override
  String toString() =>
      'SettingsDecodeWarning(field: $field, reason: $reason, workspaceId: $workspaceId)';
}

/// One-shot recovery notification surfaced to the UI after startup backup restoration or quarantine reset.
@immutable
class SettingsRecoveryNotice {
  /// Creates a [SettingsRecoveryNotice].
  const SettingsRecoveryNotice({required this.kind, this.quarantinedFilePath});

  /// Specific recovery action performed.
  final SettingsRecoveryKind kind;

  /// Absolute path of the quarantined corrupt file, if one was created.
  final String? quarantinedFilePath;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SettingsRecoveryNotice &&
        other.kind == kind &&
        other.quarantinedFilePath == quarantinedFilePath;
  }

  @override
  int get hashCode => Object.hash(kind, quarantinedFilePath);

  @override
  String toString() =>
      'SettingsRecoveryNotice(kind: ${kind.name}, quarantinedFilePath: $quarantinedFilePath)';
}

/// Converts a decoded JSON map with `Object?` keys into a typed `Map<String, Object?>`.
Map<String, Object?> _castStringKeyMap(Map<Object?, Object?> raw) {
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is String) {
      result[key] = entry.value;
    }
  }
  return result;
}

/// Computes structural equality across JSON primitives, lists, and string-keyed maps.
bool _jsonDeepEquals(Object? first, Object? second) {
  if (identical(first, second)) {
    return true;
  }
  if (first is List<Object?> && second is List<Object?>) {
    if (first.length != second.length) {
      return false;
    }
    for (var i = 0; i < first.length; i++) {
      if (!_jsonDeepEquals(first[i], second[i])) {
        return false;
      }
    }
    return true;
  }
  if (first is Map<String, Object?> && second is Map<String, Object?>) {
    if (first.length != second.length) {
      return false;
    }
    for (final entry in first.entries) {
      if (!second.containsKey(entry.key) ||
          !_jsonDeepEquals(entry.value, second[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return first == second;
}

/// Computes a deterministic structural hash across JSON primitives, lists, and string-keyed maps.
int _jsonDeepHash(Object? value) {
  if (value is List<Object?>) {
    return Object.hashAll(value.map(_jsonDeepHash));
  }
  if (value is Map<String, Object?>) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) => Object.hash(entry.key, _jsonDeepHash(entry.value)),
      ),
    );
  }
  return value.hashCode;
}
