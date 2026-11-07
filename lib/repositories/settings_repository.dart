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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_workspace.dart';
import '../models/webdav_config.dart';
import '../models/workspace_sync_state.dart';
import '../services/base64_service.dart';

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
  final Map<String, WorkspaceSyncState> _syncStates =
      <String, WorkspaceSyncState>{};
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
    _syncStates.remove(workspaceId.trim());
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
  Future<List<WorkspaceSummary>> loadWorkspaceSummaries() async {
    return List<WorkspaceSummary>.unmodifiable(<WorkspaceSummary>[
      for (final workspace in _workspaces) workspace.summary,
    ]);
  }

  @override
  Future<WorkspaceSyncState> loadWorkspaceSyncState(String workspaceId) async {
    return _syncStates[workspaceId.trim()] ?? WorkspaceSyncState.empty;
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

  @override
  Future<void> saveWorkspaceSyncState(
    String workspaceId,
    WorkspaceSyncState state,
  ) async {
    _syncStates[workspaceId.trim()] = state;
  }
}

/// Encrypted settings repository backed by [FlutterSecureStorage].
class SecureSettingsRepository implements SettingsRepository {
  /// Creates a [SecureSettingsRepository] with an optional [storage] instance.
  SecureSettingsRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const Base64Service _base64Service = Base64Service();
  static const String _keySettings = 't2_settings_v1';
  static const String _keySyncPrefix = 't2_sync_v1_';

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
    await _storage.write(
      key: '$_keySyncPrefix${workspaceId.trim()}',
      value: null,
    );
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
  Future<List<WorkspaceSummary>> loadWorkspaceSummaries() async {
    final persisted = await _readPersistedState();
    return List<WorkspaceSummary>.unmodifiable(<WorkspaceSummary>[
      for (final workspace in persisted.workspaces) workspace.summary,
    ]);
  }

  @override
  Future<WorkspaceSyncState> loadWorkspaceSyncState(String workspaceId) async {
    try {
      final raw = await _storage.read(
        key: '$_keySyncPrefix${workspaceId.trim()}',
      );
      if (raw == null || raw.trim().isEmpty) {
        return WorkspaceSyncState.empty;
      }
      final bytes = _base64Service.decodeBytes(raw.trim());
      return WorkspaceSyncState.fromBytes(bytes);
    } on Object {
      return WorkspaceSyncState.empty;
    }
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

  @override
  Future<void> saveWorkspaceSyncState(
    String workspaceId,
    WorkspaceSyncState state,
  ) async {
    final encoded = _base64Service.encodeBytes(state.toBytes());
    await _storage.write(
      key: '$_keySyncPrefix${workspaceId.trim()}',
      value: encoded,
    );
  }

  /// Reads all persisted workspaces and the active workspace identifier from [_storage].
  Future<({List<AppWorkspace> workspaces, String activeId})>
  _readPersistedState() async {
    try {
      final rawSettings = await _storage.read(key: _keySettings);
      if (rawSettings == null || rawSettings.trim().isEmpty) {
        return (
          workspaces: const <AppWorkspace>[AppWorkspace.defaultWorkspace],
          activeId: AppWorkspace.defaultId,
        );
      }
      final binaryPayload = _base64Service.decodeBytes(rawSettings.trim());
      return AppWorkspace.decodePersistedState(binaryPayload);
    } on Object {
      return (
        workspaces: const <AppWorkspace>[AppWorkspace.defaultWorkspace],
        activeId: AppWorkspace.defaultId,
      );
    }
  }

  /// Persists [workspaces] and [activeId] as a single Base64-encoded binary payload to [_storage].
  Future<void> _writePersistedState(
    List<AppWorkspace> workspaces,
    String activeId,
  ) async {
    final binaryPayload = AppWorkspace.encodePersistedState(
      workspaces,
      activeId: activeId,
    );
    final encodedPayload = _base64Service.encodeBytes(binaryPayload);
    await _storage.write(key: _keySettings, value: encodedPayload);
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

  /// Loads lightweight [WorkspaceSummary] entries for all persisted workspaces.
  Future<List<WorkspaceSummary>> loadWorkspaceSummaries();

  /// Loads the persisted [WorkspaceSyncState] for [workspaceId], or [WorkspaceSyncState.empty] if absent.
  Future<WorkspaceSyncState> loadWorkspaceSyncState(String workspaceId);

  /// Renames the workspace with [workspaceId] to [newName] after verifying name uniqueness.
  Future<AppWorkspace> renameWorkspace(String workspaceId, String newName);

  /// Saves [config] to the currently active workspace after verifying `.tdf` file path uniqueness.
  Future<void> saveConfig(WebDavConfig config);

  /// Persists the synchronization [state] for [workspaceId].
  Future<void> saveWorkspaceSyncState(
    String workspaceId,
    WorkspaceSyncState state,
  );
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
