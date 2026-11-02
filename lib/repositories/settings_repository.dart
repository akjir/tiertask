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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_workspace.dart';
import '../models/webdav_config.dart';

/// In-memory [SettingsRepository] implementation for unit and widget tests.
class InMemorySettingsRepository implements SettingsRepository {
  /// Creates an [InMemorySettingsRepository] initialized with a default `Tasks` workspace using [initialConfig].
  InMemorySettingsRepository([
    WebDavConfig initialConfig = const WebDavConfig(),
  ]) : _activeWorkspaceId = AppWorkspace.defaultId,
       _workspaces = <AppWorkspace>[
         AppWorkspace(
           id: AppWorkspace.defaultId,
           name: AppWorkspace.defaultName,
           config: initialConfig,
         ),
       ];

  String _activeWorkspaceId;
  List<AppWorkspace> _workspaces;

  @override
  Future<AppWorkspace> activateWorkspace(String workspaceId) async {
    final target = _findWorkspace(_workspaces, workspaceId);
    _activeWorkspaceId = target.id;
    return target;
  }

  @override
  Future<AppWorkspace> createWorkspace(
    String name, {
    WebDavConfig? config,
    String? id,
    bool activate = false,
  }) async {
    final created = _buildNewWorkspace(
      _workspaces,
      name,
      config: config,
      id: id,
    );
    _workspaces = <AppWorkspace>[..._workspaces, created];
    if (activate) {
      _activeWorkspaceId = created.id;
    }
    return created;
  }

  @override
  Future<AppWorkspace> deleteWorkspace(String workspaceId) async {
    final updated = _removeWorkspace(
      _workspaces,
      _activeWorkspaceId,
      workspaceId,
    );
    _workspaces = updated.workspaces;
    _activeWorkspaceId = updated.activeId;
    return _resolveActiveWorkspace(_workspaces, _activeWorkspaceId);
  }

  @override
  Future<AppWorkspace> loadActiveWorkspace() async {
    return _resolveActiveWorkspace(_workspaces, _activeWorkspaceId);
  }

  @override
  Future<WebDavConfig> loadConfig() async {
    final active = await loadActiveWorkspace();
    return active.config;
  }

  @override
  Future<AppWorkspace> renameWorkspace(
    String workspaceId,
    String newName,
  ) async {
    final updated = _renameWorkspaceEntry(_workspaces, workspaceId, newName);
    _workspaces = updated.workspaces;
    return updated.renamed;
  }

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    _workspaces = _updateWorkspaceConfigEntry(
      _workspaces,
      _activeWorkspaceId,
      config,
    );
  }
}

/// Encrypted settings repository backed by [FlutterSecureStorage].
class SecureSettingsRepository implements SettingsRepository {
  /// Creates a [SecureSettingsRepository] with an optional [storage] instance.
  SecureSettingsRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _keyActiveWorkspaceId = 't2_active_workspace_id';
  static const String _keyFilePath = 't2_webdav_file_path';
  static const String _keyLanguage = 't2_app_language';
  static const String _keyLocalFilePath = 't2_local_file_path';
  static const String _keyPassword = 't2_webdav_password';
  static const String _keyServerUrl = 't2_webdav_server_url';
  static const String _keyShowOpenTaskCount = 't2_show_open_task_count';
  static const String _keyStorageMode = 't2_storage_mode';
  static const String _keyThemeMode = 't2_theme_mode';
  static const String _keyUsername = 't2_webdav_username';
  static const String _keyWorkspaces = 't2_workspaces_v1';

  final FlutterSecureStorage _storage;

  @override
  Future<AppWorkspace> activateWorkspace(String workspaceId) async {
    final persisted = await _readPersistedState();
    final target = _findWorkspace(persisted.workspaces, workspaceId);
    await _writePersistedState(persisted.workspaces, target.id);
    return target;
  }

  @override
  Future<AppWorkspace> createWorkspace(
    String name, {
    WebDavConfig? config,
    String? id,
    bool activate = false,
  }) async {
    final persisted = await _readPersistedState();
    final created = _buildNewWorkspace(
      persisted.workspaces,
      name,
      config: config,
      id: id,
    );
    final updatedWorkspaces = <AppWorkspace>[...persisted.workspaces, created];
    final nextActiveId = activate ? created.id : persisted.activeId;
    await _writePersistedState(updatedWorkspaces, nextActiveId);
    return created;
  }

  @override
  Future<AppWorkspace> deleteWorkspace(String workspaceId) async {
    final persisted = await _readPersistedState();
    final updated = _removeWorkspace(
      persisted.workspaces,
      persisted.activeId,
      workspaceId,
    );
    await _writePersistedState(updated.workspaces, updated.activeId);
    return _resolveActiveWorkspace(updated.workspaces, updated.activeId);
  }

  @override
  Future<AppWorkspace> loadActiveWorkspace() async {
    final persisted = await _readPersistedState();
    return _resolveActiveWorkspace(persisted.workspaces, persisted.activeId);
  }

  @override
  Future<WebDavConfig> loadConfig() async {
    final active = await loadActiveWorkspace();
    return active.config;
  }

  @override
  Future<AppWorkspace> renameWorkspace(
    String workspaceId,
    String newName,
  ) async {
    final persisted = await _readPersistedState();
    final updated = _renameWorkspaceEntry(
      persisted.workspaces,
      workspaceId,
      newName,
    );
    await _writePersistedState(updated.workspaces, persisted.activeId);
    return updated.renamed;
  }

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    final persisted = await _readPersistedState();
    final updatedWorkspaces = _updateWorkspaceConfigEntry(
      persisted.workspaces,
      persisted.activeId,
      config,
    );
    await _writePersistedState(updatedWorkspaces, persisted.activeId);
  }

  /// Decodes a JSON list of persisted workspaces, falling back to an empty list when invalid.
  static List<AppWorkspace> _decodeWorkspacesJson(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return const <AppWorkspace>[];
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List<Object?>) {
        return const <AppWorkspace>[];
      }
      final result = <AppWorkspace>[];
      for (final item in decoded) {
        if (result.length >= AppWorkspace.maxWorkspaces) {
          break;
        }
        if (item is Map<String, Object?>) {
          result.add(AppWorkspace.fromJson(item));
        }
      }
      return result;
    } on Object {
      return const <AppWorkspace>[];
    }
  }

  /// Loads legacy single-profile settings from [FlutterSecureStorage] for migration into `Tasks`.
  Future<WebDavConfig> _loadLegacyConfig() async {
    try {
      final serverUrl = await _storage.read(key: _keyServerUrl) ?? '';
      final username = await _storage.read(key: _keyUsername) ?? '';
      final password = await _storage.read(key: _keyPassword) ?? '';
      final filePath =
          await _storage.read(key: _keyFilePath) ??
          WebDavConfig.defaultFileName;
      final localFilePath =
          await _storage.read(key: _keyLocalFilePath) ??
          WebDavConfig.defaultFileName;
      final rawStorageMode = await _storage.read(key: _keyStorageMode);
      final rawLanguage = await _storage.read(key: _keyLanguage);
      final rawThemeMode = await _storage.read(key: _keyThemeMode);
      final rawShowOpenTaskCount = await _storage.read(
        key: _keyShowOpenTaskCount,
      );

      return WebDavConfig(
        serverUrl: serverUrl,
        username: username,
        password: password,
        filePath: _normalizeLegacyTdfFilePath(filePath),
        localFilePath: _normalizeLegacyTdfFilePath(localFilePath),
        storageMode: rawStorageMode == null
            ? null
            : StorageMode.fromCode(rawStorageMode),
        language: AppLanguage.fromCode(rawLanguage),
        themeMode: AppThemeMode.fromCode(rawThemeMode),
        showOpenTaskCount: rawShowOpenTaskCount?.trim().toLowerCase() == 'true',
      );
    } on Object {
      return const WebDavConfig();
    }
  }

  /// Normalizes a legacy stored file path, defaulting empty or `.md` presets to `.tdf`.
  static String _normalizeLegacyTdfFilePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || trimmed == 'tiertask.md') {
      return WebDavConfig.defaultFileName;
    }
    if (trimmed == 't2.md') {
      return 't2.tdf';
    }
    return trimmed;
  }

  /// Reads all persisted workspaces and the active workspace identifier from [_storage].
  Future<({List<AppWorkspace> workspaces, String activeId})>
  _readPersistedState() async {
    try {
      final rawWorkspaces = await _storage.read(key: _keyWorkspaces);
      final decoded = _decodeWorkspacesJson(rawWorkspaces);
      if (decoded.isNotEmpty) {
        final rawActiveId = await _storage.read(key: _keyActiveWorkspaceId);
        final active = _resolveActiveWorkspace(
          decoded,
          rawActiveId ?? AppWorkspace.defaultId,
        );
        return (workspaces: decoded, activeId: active.id);
      }

      final legacyConfig = await _loadLegacyConfig();
      final defaultEntry = AppWorkspace(
        id: AppWorkspace.defaultId,
        name: AppWorkspace.defaultName,
        config: legacyConfig,
      );
      return (
        workspaces: <AppWorkspace>[defaultEntry],
        activeId: defaultEntry.id,
      );
    } on Object {
      return (
        workspaces: const <AppWorkspace>[AppWorkspace.defaultWorkspace],
        activeId: AppWorkspace.defaultId,
      );
    }
  }

  /// Persists [workspaces] and [activeId] to [_storage].
  Future<void> _writePersistedState(
    List<AppWorkspace> workspaces,
    String activeId,
  ) async {
    final encoded = jsonEncode(<Map<String, Object?>>[
      for (final workspace in workspaces) workspace.toJson(),
    ]);
    await _storage.write(key: _keyWorkspaces, value: encoded);
    await _storage.write(key: _keyActiveWorkspaceId, value: activeId);
  }
}

/// Repository contract for persisting workspaces and loading the single active [AppWorkspace] and [WebDavConfig].
abstract class SettingsRepository {
  /// Marks the workspace with [workspaceId] as active and returns only that [AppWorkspace].
  Future<AppWorkspace> activateWorkspace(String workspaceId);

  /// Creates and persists a new [AppWorkspace] with unique [name] and `.tdf` file paths.
  Future<AppWorkspace> createWorkspace(
    String name, {
    WebDavConfig? config,
    String? id,
    bool activate = false,
  });

  /// Deletes the workspace with [workspaceId] (unless it is the last remaining workspace) and returns the active [AppWorkspace].
  Future<AppWorkspace> deleteWorkspace(String workspaceId);

  /// Loads and returns only the single currently active [AppWorkspace].
  Future<AppWorkspace> loadActiveWorkspace();

  /// Loads the persisted [WebDavConfig] of the currently active workspace.
  Future<WebDavConfig> loadConfig();

  /// Renames the workspace with [workspaceId] to [newName] after verifying name uniqueness.
  Future<AppWorkspace> renameWorkspace(String workspaceId, String newName);

  /// Saves [config] to the currently active workspace after verifying `.tdf` file path uniqueness.
  Future<void> saveConfig(WebDavConfig config);
}

/// Validates and constructs a new [AppWorkspace] against [existingWorkspaces].
AppWorkspace _buildNewWorkspace(
  List<AppWorkspace> existingWorkspaces,
  String rawName, {
  WebDavConfig? config,
  String? id,
}) {
  if (existingWorkspaces.length >= AppWorkspace.maxWorkspaces) {
    throw const WorkspaceException(
      WorkspaceErrorKind.maxWorkspacesExceeded,
      'Maximum number of workspaces reached.',
    );
  }
  final summaries = <WorkspaceSummary>[
    for (final workspace in existingWorkspaces) workspace.summary,
  ];
  final validatedName = AppWorkspace.validateName(rawName, summaries);
  final suggestedFile = AppWorkspace.suggestFileName(validatedName);
  final effectiveConfig =
      config ??
      WebDavConfig(localFilePath: suggestedFile, filePath: suggestedFile);
  AppWorkspace.validateConfigPaths(effectiveConfig, summaries);

  final trimmedId = id?.trim() ?? '';
  final resolvedId = trimmedId.isNotEmpty
      ? trimmedId
      : AppWorkspace.deriveWorkspaceId(validatedName, summaries);

  return AppWorkspace(
    id: resolvedId,
    name: validatedName,
    config: effectiveConfig.copyWith(
      localFilePath: effectiveConfig.localFilePath.trim(),
      filePath: effectiveConfig.filePath.trim(),
    ),
  );
}

/// Finds the workspace with [workspaceId] in [workspaces] or throws [WorkspaceException].
AppWorkspace _findWorkspace(List<AppWorkspace> workspaces, String workspaceId) {
  final targetId = workspaceId.trim();
  for (final workspace in workspaces) {
    if (workspace.id == targetId) {
      return workspace;
    }
  }
  throw WorkspaceException(
    WorkspaceErrorKind.workspaceNotFound,
    'Workspace "$workspaceId" was not found.',
  );
}

/// Deletes [workspaceId] from [workspaces] while ensuring at least one workspace remains.
({List<AppWorkspace> workspaces, String activeId}) _removeWorkspace(
  List<AppWorkspace> workspaces,
  String currentActiveId,
  String workspaceId,
) {
  final target = _findWorkspace(workspaces, workspaceId);
  if (workspaces.length <= 1) {
    throw const WorkspaceException(
      WorkspaceErrorKind.cannotDeleteLastWorkspace,
      'Cannot delete the last remaining workspace.',
    );
  }
  final remaining = <AppWorkspace>[
    for (final workspace in workspaces)
      if (workspace.id != target.id) workspace,
  ];
  final nextActiveId = currentActiveId == target.id
      ? remaining.first.id
      : currentActiveId;
  return (workspaces: remaining, activeId: nextActiveId);
}

/// Renames [workspaceId] to [newName] after checking name uniqueness across [workspaces].
({List<AppWorkspace> workspaces, AppWorkspace renamed}) _renameWorkspaceEntry(
  List<AppWorkspace> workspaces,
  String workspaceId,
  String newName,
) {
  final target = _findWorkspace(workspaces, workspaceId);
  final summaries = <WorkspaceSummary>[
    for (final workspace in workspaces) workspace.summary,
  ];
  final validatedName = AppWorkspace.validateName(
    newName,
    summaries,
    excludeWorkspaceId: target.id,
  );
  final renamed = target.copyWith(name: validatedName);
  final updated = <AppWorkspace>[
    for (final workspace in workspaces)
      if (workspace.id == target.id) renamed else workspace,
  ];
  return (workspaces: updated, renamed: renamed);
}

/// Returns the workspace matching [activeId] in [workspaces], falling back to the first entry.
AppWorkspace _resolveActiveWorkspace(
  List<AppWorkspace> workspaces,
  String activeId,
) {
  for (final workspace in workspaces) {
    if (workspace.id == activeId) {
      return workspace;
    }
  }
  return workspaces.isNotEmpty
      ? workspaces.first
      : AppWorkspace.defaultWorkspace;
}

/// Validates and updates the [WebDavConfig] of [activeId] in [workspaces].
List<AppWorkspace> _updateWorkspaceConfigEntry(
  List<AppWorkspace> workspaces,
  String activeId,
  WebDavConfig newConfig,
) {
  final active = _resolveActiveWorkspace(workspaces, activeId);
  final summaries = <WorkspaceSummary>[
    for (final workspace in workspaces) workspace.summary,
  ];
  AppWorkspace.validateConfigPaths(
    newConfig,
    summaries,
    excludeWorkspaceId: active.id,
  );
  final normalizedConfig = newConfig.copyWith(
    serverUrl: newConfig.serverUrl.trim(),
    username: newConfig.username.trim(),
    filePath: newConfig.filePath.trim(),
    localFilePath: newConfig.localFilePath.trim(),
  );
  final updatedActive = active.copyWith(config: normalizedConfig);
  return <AppWorkspace>[
    for (final workspace in workspaces)
      if (workspace.id == active.id) updatedActive else workspace,
  ];
}
