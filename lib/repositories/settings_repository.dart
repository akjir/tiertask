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
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_build_profile.dart';
import '../models/app_workspace.dart';
import '../models/settings_codec.dart';
import '../models/tdf_file_path.dart';
import '../models/webdav_config.dart';
import '../models/workspace_sync_state.dart';
import '../services/app_logger.dart';
import '../services/base64_service.dart';
import 'host_file_lock.dart';
import 'local_file_repository.dart';

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

  /// Creates an [InMemorySettingsRepository] pre-seeded with a one-shot [recoveryNotice].
  InMemorySettingsRepository.withRecoveryNotice({
    WebDavConfig initialConfig = const WebDavConfig(),
    required SettingsRecoveryNotice recoveryNotice,
  }) : _activeWorkspaceId = AppWorkspace.defaultId,
       _lastRecoveryNotice = recoveryNotice,
       _workspaces = <AppWorkspace>[
         AppWorkspace(
           id: AppWorkspace.defaultId,
           name: AppWorkspace.defaultName,
           config: initialConfig,
         ),
       ];

  String _activeWorkspaceId;
  SettingsRecoveryNotice? _lastRecoveryNotice;
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
  Future<void> saveConfigForWorkspace(
    String workspaceId,
    WebDavConfig config,
  ) async {
    final target = _findWorkspace(_workspaces, workspaceId);
    _workspaces = _updateWorkspaceConfigEntry(_workspaces, target.id, config);
  }

  @override
  Future<void> saveWorkspaceSyncState(
    String workspaceId,
    WorkspaceSyncState state,
  ) async {
    _syncStates[workspaceId.trim()] = state;
  }

  @override
  SettingsRecoveryNotice? takeLastRecoveryNotice() {
    final notice = _lastRecoveryNotice;
    _lastRecoveryNotice = null;
    return notice;
  }
}

/// Split settings repository persisting non-secret workspace metadata in host-local
/// `settings.json` (with cross-process locking, atomic writes, `.bak` backup rotation,
/// and quarantine) and WebDAV passwords per workspace in [FlutterSecureStorage].
class SecureSettingsRepository implements SettingsRepository {
  /// Creates a [SecureSettingsRepository] with optional overrides for storage,
  /// build profile, settings directory, host lock directory, clock, and Android
  /// `Context.filesDir` resolution.
  SecureSettingsRepository({
    FlutterSecureStorage? storage,
    AppBuildProfile? buildProfile,
    String? settingsDirectoryPath,
    String? hostLockDirectoryOverride,
    DateTime Function()? clock,
    this._androidFilesDirectoryResolver,
    Duration lockAcquireTimeout = HostFileLockManager.defaultLockAcquireTimeout,
  }) : buildProfile = buildProfile ?? AppBuildProfile.current,
       _clock = clock ?? DateTime.now,
       _lockManager = HostFileLockManager<WorkspaceException>(
         createException: (message, {cause}) => WorkspaceException(
           WorkspaceErrorKind.settingsPersistenceFailed,
           message,
           cause: cause,
         ),
         hostLockDirectoryOverride: hostLockDirectoryOverride,
         lockAcquireTimeout: lockAcquireTimeout,
       ),
       _settingsDirectoryOverride = settingsDirectoryPath,
       _storage = storage ?? const FlutterSecureStorage();

  static const MethodChannel _androidStorageChannel = MethodChannel(
    'de.akjir.tiertask/app_storage',
  );
  static const Base64Service _base64Service = Base64Service(
    maxInputBytes: WorkspaceSyncState.maxSerializedBytes,
  );
  static const int _gzipMagicByte0 = 0x1F;
  static const int _gzipMagicByte1 = 0x8B;
  static const int _isolateOffloadThresholdBytes = 32768;
  static const int _maxQuarantineCollisionSlots = 100;
  static const Utf8Codec _utf8Codec = Utf8Codec();

  /// Active build storage profile determining directory and secure storage key namespaces.
  final AppBuildProfile buildProfile;

  final Future<String?> Function()? _androidFilesDirectoryResolver;
  final Map<String, String> _cachedPasswordsByWorkspaceId = <String, String>{};
  String? _cachedSettingsDirectoryPath;
  String? _cachedSettingsFilePath;
  ({
    String filePath,
    DateTime modified,
    DateTime changed,
    int size,
    PersistedSettingsDocument document,
    List<int> rawBytes,
  })?
  _cachedSettingsSnapshot;
  final Map<String, WorkspaceSyncState> _cachedSyncStatesByWorkspaceId =
      <String, WorkspaceSyncState>{};
  final DateTime Function() _clock;
  SettingsRecoveryNotice? _lastRecoveryNotice;
  final HostFileLockManager<WorkspaceException> _lockManager;
  final Set<String> _migratedOrAbsentLegacySyncIds = <String>{};
  int _settingsDiskReadCount = 0;
  final String? _settingsDirectoryOverride;
  final FlutterSecureStorage _storage;
  int _syncStateDiskReadCount = 0;
  final Set<String> _unreadableSecretWorkspaceIds = <String>{};

  /// Number of primary `settings.json` disk reads executed by this repository instance.
  @visibleForTesting
  int get settingsDiskReadCountForTesting => _settingsDiskReadCount;

  /// Number of `.tts` sync state disk reads executed by this repository instance.
  @visibleForTesting
  int get syncStateDiskReadCountForTesting => _syncStateDiskReadCount;

  @override
  Future<AppWorkspace> activateWorkspace(String workspaceId) async {
    final settingsFilePath = await _resolveSettingsFilePath();
    return _lockManager.withExclusiveLock(settingsFilePath, () async {
      final loaded = await _loadDocumentLocked(settingsFilePath);
      final target = _findWorkspace(loaded.document.workspaces, workspaceId);
      final updatedDocument = loaded.document.copyWith(
        activeWorkspaceId: target.id,
      );
      await _persistDocumentLocked(
        settingsFilePath,
        updatedDocument,
        secretUpdated: false,
        priorPrimaryBytes: loaded.primaryBytes,
      );
      return _hydrateWorkspacePassword(target, updatedDocument);
    });
  }

  @override
  Future<AppWorkspace> createWorkspace(
    String name, {
    WebDavConfig? config,
    String? id,
    bool activate = false,
  }) async {
    final settingsFilePath = await _resolveSettingsFilePath();
    return _lockManager.withExclusiveLock(settingsFilePath, () async {
      final loaded = await _loadDocumentLocked(settingsFilePath);
      final document = loaded.document;
      final created = _buildNewWorkspace(
        document.workspaces,
        name,
        config: config,
        id: id,
      );
      final nextPasswordIds = Set<String>.from(
        document.passwordStoredWorkspaceIds,
      );
      var secretUpdated = false;
      if (created.config.password.isNotEmpty) {
        await _writeWorkspacePassword(created.id, created.config.password);
        nextPasswordIds.add(created.id);
        secretUpdated = true;
      }
      final persistedEntry = _stripPassword(created);
      final updatedDocument = document.copyWith(
        activeWorkspaceId: activate ? created.id : document.activeWorkspaceId,
        workspaces: <AppWorkspace>[...document.workspaces, persistedEntry],
        passwordStoredWorkspaceIds: nextPasswordIds,
      );
      try {
        await _persistDocumentLocked(
          settingsFilePath,
          updatedDocument,
          secretUpdated: secretUpdated,
          priorPrimaryBytes: loaded.primaryBytes,
        );
      } on Object {
        if (secretUpdated) {
          await _rollbackWorkspacePasswordQuietly(
            created.id,
            const _PasswordRollbackSnapshot(
              hadStoredSecret: false,
              wasCached: false,
              wasUnreadable: false,
            ),
          );
        }
        rethrow;
      }
      return created;
    });
  }

  @override
  Future<AppWorkspace> deleteWorkspace(String workspaceId) async {
    final settingsFilePath = await _resolveSettingsFilePath();
    final targetId = workspaceId.trim();
    final activeWorkspace = await _lockManager.withExclusiveLock(
      settingsFilePath,
      () async {
        final loaded = await _loadDocumentLocked(settingsFilePath);
        final document = loaded.document;
        final updated = _removeWorkspace(
          document.workspaces,
          document.activeWorkspaceId,
          workspaceId,
        );
        final nextPasswordIds = Set<String>.from(
          document.passwordStoredWorkspaceIds,
        )..remove(targetId);
        final nextUnknownById = Map<String, Map<String, Object?>>.from(
          document.unknownWorkspaceFieldsById,
        )..remove(targetId);
        final updatedDocument = document.copyWith(
          activeWorkspaceId: updated.activeId,
          workspaces: updated.workspaces,
          passwordStoredWorkspaceIds: nextPasswordIds,
          unknownWorkspaceFieldsById: nextUnknownById,
        );
        await _persistDocumentLocked(
          settingsFilePath,
          updatedDocument,
          secretUpdated: false,
          priorPrimaryBytes: loaded.primaryBytes,
        );
        _cachedPasswordsByWorkspaceId.remove(targetId);
        _unreadableSecretWorkspaceIds.remove(targetId);
        _cachedSyncStatesByWorkspaceId.remove(targetId);
        _migratedOrAbsentLegacySyncIds.remove(targetId);
        await _deleteKeyQuietly(
          '${buildProfile.webdavPasswordKeyPrefix}$targetId',
        );
        await _deleteKeyQuietly(
          '${buildProfile.syncStorageKeyPrefix}$targetId',
        );
        final active = _resolveActiveWorkspace(
          updatedDocument.workspaces,
          updatedDocument.activeWorkspaceId,
        );
        return _hydrateWorkspacePassword(active, updatedDocument);
      },
    );
    await _deleteSyncStateFileQuietly(targetId);
    return activeWorkspace;
  }

  @override
  Future<AppWorkspace> loadActiveWorkspace() async {
    final settingsFilePath = await _resolveSettingsFilePath();
    return _lockManager.withExclusiveLock(settingsFilePath, () async {
      final loaded = await _loadDocumentLocked(settingsFilePath);
      final document = loaded.document;
      final active = _resolveActiveWorkspace(
        document.workspaces,
        document.activeWorkspaceId,
      );
      return _hydrateWorkspacePassword(active, document);
    });
  }

  @override
  Future<WebDavConfig> loadConfig() async {
    final active = await loadActiveWorkspace();
    return active.config;
  }

  @override
  Future<List<WorkspaceSummary>> loadWorkspaceSummaries() async {
    final settingsFilePath = await _resolveSettingsFilePath();
    return _lockManager.withExclusiveLock(settingsFilePath, () async {
      final loaded = await _loadDocumentLocked(settingsFilePath);
      return List<WorkspaceSummary>.unmodifiable(<WorkspaceSummary>[
        for (final workspace in loaded.document.workspaces) workspace.summary,
      ]);
    });
  }

  @override
  Future<WorkspaceSyncState> loadWorkspaceSyncState(String workspaceId) async {
    final targetId = _tryValidateSyncWorkspaceId(workspaceId);
    if (targetId == null) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.storage,
        'settings.sync_state.invalid_workspace_id',
      );
      return WorkspaceSyncState.empty;
    }
    if (_cachedSyncStatesByWorkspaceId[targetId] case final cached?) {
      return cached;
    }
    try {
      final syncFilePath = await _resolveSyncStateFilePath(targetId);
      return await _lockManager.withExclusiveLock(syncFilePath, () async {
        if (_cachedSyncStatesByWorkspaceId[targetId] case final cached?) {
          return cached;
        }
        final entityType = FileSystemEntity.typeSync(
          syncFilePath,
          followLinks: false,
        );
        if (entityType == FileSystemEntityType.file) {
          return _loadSyncStateFromFileLocked(targetId, syncFilePath);
        }
        if (entityType != FileSystemEntityType.notFound) {
          AppLogger.event(
            LogLevel.warn,
            LogTag.storage,
            'settings.sync_state.invalid_file_type',
            fields: <String, Object?>{
              'workspace_id': targetId,
              'entity_type': _entityTypeToken(entityType),
            },
          );
          return WorkspaceSyncState.empty;
        }
        if (_migratedOrAbsentLegacySyncIds.contains(targetId)) {
          return WorkspaceSyncState.empty;
        }
        return _migrateLegacySyncStateLocked(targetId, syncFilePath);
      });
    } on Object {
      _logSyncStateCorrupt(
        workspaceId: targetId,
        source: 'load',
        reason: 'unexpected_error',
      );
      return WorkspaceSyncState.empty;
    }
  }

  @override
  Future<AppWorkspace> renameWorkspace(
    String workspaceId,
    String newName,
  ) async {
    final settingsFilePath = await _resolveSettingsFilePath();
    return _lockManager.withExclusiveLock(settingsFilePath, () async {
      final loaded = await _loadDocumentLocked(settingsFilePath);
      final document = loaded.document;
      final updated = _renameWorkspaceEntry(
        document.workspaces,
        workspaceId,
        newName,
      );
      final updatedDocument = document.copyWith(workspaces: updated.workspaces);
      await _persistDocumentLocked(
        settingsFilePath,
        updatedDocument,
        secretUpdated: false,
        priorPrimaryBytes: loaded.primaryBytes,
      );
      return _hydrateWorkspacePassword(updated.renamed, updatedDocument);
    });
  }

  /// Exposes the resolved `settings.json` path for cross-platform path-handling unit tests.
  @visibleForTesting
  Future<String> resolveSettingsFilePathForTesting() =>
      _resolveSettingsFilePath();

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    final settingsFilePath = await _resolveSettingsFilePath();
    await _lockManager.withExclusiveLock(settingsFilePath, () async {
      final loaded = await _loadDocumentLocked(settingsFilePath);
      final document = loaded.document;
      final active = _resolveActiveWorkspace(
        document.workspaces,
        document.activeWorkspaceId,
      );
      await _saveWorkspaceConfigLocked(
        settingsFilePath,
        document,
        active.id,
        config,
        priorPrimaryBytes: loaded.primaryBytes,
      );
    });
  }

  @override
  Future<void> saveConfigForWorkspace(
    String workspaceId,
    WebDavConfig config,
  ) async {
    final settingsFilePath = await _resolveSettingsFilePath();
    await _lockManager.withExclusiveLock(settingsFilePath, () async {
      final loaded = await _loadDocumentLocked(settingsFilePath);
      final document = loaded.document;
      final target = _findWorkspace(document.workspaces, workspaceId);
      await _saveWorkspaceConfigLocked(
        settingsFilePath,
        document,
        target.id,
        config,
        priorPrimaryBytes: loaded.primaryBytes,
      );
    });
  }

  @override
  Future<void> saveWorkspaceSyncState(
    String workspaceId,
    WorkspaceSyncState state,
  ) async {
    final targetId = _tryValidateSyncWorkspaceId(workspaceId);
    if (targetId == null) {
      throw const WorkspaceException(
        WorkspaceErrorKind.settingsPersistenceFailed,
        'Invalid workspace identifier for sync state.',
      );
    }
    final syncFilePath = await _resolveSyncStateFilePath(targetId);
    await _lockManager.withExclusiveLock(syncFilePath, () async {
      final entityType = _inspectFileType(syncFilePath, 'sync_state');
      if (state == WorkspaceSyncState.empty) {
        if (entityType == FileSystemEntityType.file) {
          try {
            File(syncFilePath).deleteSync();
          } on FileSystemException catch (error) {
            throw WorkspaceException(
              WorkspaceErrorKind.settingsPersistenceFailed,
              'Could not delete workspace sync state file.',
              cause: error,
            );
          }
        }
        _cachedSyncStatesByWorkspaceId.remove(targetId);
        _migratedOrAbsentLegacySyncIds.add(targetId);
        await _deleteKeyQuietly(
          '${buildProfile.syncStorageKeyPrefix}$targetId',
        );
        return;
      }
      _ensureParentDirectory(syncFilePath);
      final payload = await _encodeSyncStatePayload(state);
      await _lockManager.writeAtomically(syncFilePath, payload);
      _cachedSyncStatesByWorkspaceId[targetId] = state;
      _migratedOrAbsentLegacySyncIds.add(targetId);
    });
  }

  @override
  SettingsRecoveryNotice? takeLastRecoveryNotice() {
    final notice = _lastRecoveryNotice;
    _lastRecoveryNotice = null;
    return notice;
  }

  /// Captures prior keyring and cache state for [workspaceId] before a password mutation so persistence failures roll back cleanly.
  Future<_PasswordRollbackSnapshot> _capturePasswordRollbackSnapshot(
    String workspaceId,
    Set<String> currentStoredIds,
  ) async {
    final hadStoredSecret = currentStoredIds.contains(workspaceId);
    final wasCached = _cachedPasswordsByWorkspaceId.containsKey(workspaceId);
    final wasUnreadable = _unreadableSecretWorkspaceIds.contains(workspaceId);
    var previousPassword = _cachedPasswordsByWorkspaceId[workspaceId];
    if (hadStoredSecret && !wasCached) {
      previousPassword = await _readKeyQuietly(
        '${buildProfile.webdavPasswordKeyPrefix}$workspaceId',
      );
    }
    return _PasswordRollbackSnapshot(
      hadStoredSecret: hadStoredSecret,
      previousPassword: previousPassword,
      wasCached: wasCached,
      wasUnreadable: wasUnreadable,
    );
  }

  /// Decompresses gzip-wrapped [bytes] with a strict upper output bound, offloading to a worker isolate when payload length meets [_isolateOffloadThresholdBytes].
  Future<List<int>?> _decodeSyncStateWireBytes(List<int> bytes) async {
    final isGzip =
        bytes.length >= 2 &&
        bytes[0] == _gzipMagicByte0 &&
        bytes[1] == _gzipMagicByte1;
    if (!isGzip) {
      return bytes;
    }
    if (bytes.length >= _isolateOffloadThresholdBytes) {
      return Isolate.run(() => _decodeGzipSyncStateBytesSync(bytes));
    }
    return _decodeGzipSyncStateBytesSync(bytes);
  }

  /// Best-effort deletes [key] from [_storage], ignoring unavailable keyring errors.
  Future<void> _deleteKeyQuietly(String key) async {
    try {
      await _storage.write(key: key, value: null);
    } on Object {
      // Best-effort cleanup after workspace removal.
    }
  }

  /// Best-effort deletes the host-local `.tts` sync state file and evicts in-memory sync caches for [workspaceId] under its exclusive lock.
  Future<void> _deleteSyncStateFileQuietly(String workspaceId) async {
    final targetId = _tryValidateSyncWorkspaceId(workspaceId);
    if (targetId == null) {
      return;
    }
    try {
      final syncFilePath = await _resolveSyncStateFilePath(targetId);
      await _lockManager.withExclusiveLock(syncFilePath, () async {
        try {
          if (FileSystemEntity.typeSync(syncFilePath, followLinks: false) ==
              FileSystemEntityType.file) {
            File(syncFilePath).deleteSync();
          }
        } finally {
          _cachedSyncStatesByWorkspaceId.remove(targetId);
          _migratedOrAbsentLegacySyncIds.remove(targetId);
        }
      });
    } on Object {
      // Best-effort cleanup after workspace removal.
    }
  }

  /// Deletes the stored WebDAV password key for [workspaceId], throwing [WorkspaceErrorKind.credentialStorageUnavailable] on failure.
  Future<void> _deleteWorkspacePassword(String workspaceId) async {
    final key = '${buildProfile.webdavPasswordKeyPrefix}$workspaceId';
    try {
      await _storage.write(key: key, value: null);
      _cachedPasswordsByWorkspaceId.remove(workspaceId);
    } on Object catch (error) {
      _logKeyringFailure(
        'settings.secret.write_failed',
        error,
        workspaceId: workspaceId,
        operation: 'delete',
      );
      throw WorkspaceException(
        WorkspaceErrorKind.credentialStorageUnavailable,
        'Could not remove WebDAV password from secure credential storage.',
        cause: error,
      );
    }
  }

  /// Serializes [state] as gzip-compressed `TTS\x04` bytes when compression reduces size, offloading to a worker isolate when raw payload length meets [_isolateOffloadThresholdBytes].
  Future<List<int>> _encodeSyncStatePayload(WorkspaceSyncState state) async {
    final rawBytes = state.toBytes();
    if (rawBytes.length >= _isolateOffloadThresholdBytes) {
      return Isolate.run(() => _compressSyncStateBytesSync(rawBytes));
    }
    return _compressSyncStateBytesSync(rawBytes);
  }

  /// Populates [workspace]'s WebDAV password from cache or [_storage] when stored.
  Future<AppWorkspace> _hydrateWorkspacePassword(
    AppWorkspace workspace,
    PersistedSettingsDocument document,
  ) async {
    if (!document.passwordStoredWorkspaceIds.contains(workspace.id)) {
      return workspace;
    }
    if (_cachedPasswordsByWorkspaceId.containsKey(workspace.id)) {
      final cached = _cachedPasswordsByWorkspaceId[workspace.id] ?? '';
      return workspace.copyWith(
        config: workspace.config.copyWith(password: cached),
      );
    }
    final key = '${buildProfile.webdavPasswordKeyPrefix}${workspace.id}';
    try {
      final stored = await _storage.read(key: key);
      _unreadableSecretWorkspaceIds.remove(workspace.id);
      if (stored == null) {
        AppLogger.event(
          LogLevel.warn,
          LogTag.storage,
          'settings.secret.missing',
          fields: <String, Object?>{'workspace_id': workspace.id},
        );
        _cachedPasswordsByWorkspaceId[workspace.id] = '';
        return workspace.copyWith(
          config: workspace.config.copyWith(password: ''),
        );
      }
      _cachedPasswordsByWorkspaceId[workspace.id] = stored;
      return workspace.copyWith(
        config: workspace.config.copyWith(password: stored),
      );
    } on Object catch (error) {
      _unreadableSecretWorkspaceIds.add(workspace.id);
      _logKeyringFailure(
        'settings.secret.read_failed',
        error,
        workspaceId: workspace.id,
      );
      return workspace.copyWith(
        config: workspace.config.copyWith(password: ''),
      );
    }
  }

  /// Checks the filesystem entity type at [path] without following symlinks, rejecting non-regular files.
  FileSystemEntityType _inspectFileType(String path, String targetLabel) {
    final entityType = FileSystemEntity.typeSync(path, followLinks: false);
    if (entityType == FileSystemEntityType.notFound ||
        entityType == FileSystemEntityType.file) {
      return entityType;
    }
    AppLogger.event(
      LogLevel.error,
      LogTag.storage,
      'settings.invalid_file_type',
      fields: <String, Object?>{
        'target': targetLabel,
        'entity_type': _entityTypeToken(entityType),
      },
    );
    throw WorkspaceException(
      WorkspaceErrorKind.settingsPersistenceFailed,
      'Settings $targetLabel path is not a regular file.',
    );
  }

  /// Invokes the Android `de.akjir.tiertask/app_storage` platform channel to resolve `Context.filesDir`.
  Future<String?> _invokeAndroidFilesDirectoryChannel() {
    return _androidStorageChannel.invokeMethod<String>('getFilesDirectory');
  }

  /// Loads `settings.json` under the exclusive lock, reusing the stat-validated cache when unchanged and performing backup recovery or quarantine when corrupt.
  Future<({PersistedSettingsDocument document, List<int>? primaryBytes})>
  _loadDocumentLocked(String settingsFilePath) async {
    final backupPath = '$settingsFilePath.bak';
    final primaryType = _inspectFileType(settingsFilePath, 'primary');
    final backupType = _inspectFileType(backupPath, 'backup');

    if (primaryType == FileSystemEntityType.file) {
      final stat = FileStat.statSync(settingsFilePath);
      if (_cachedSettingsSnapshot case final cached?
          when cached.filePath == settingsFilePath &&
              cached.modified == stat.modified &&
              cached.changed == stat.changed &&
              cached.size == stat.size) {
        _logSettingsLoad(cached.document);
        return (document: cached.document, primaryBytes: cached.rawBytes);
      }
      final decodedPrimary = _tryReadAndDecodeFile(settingsFilePath);
      if (decodedPrimary != null) {
        _updateSettingsCache(
          settingsFilePath,
          decodedPrimary.document,
          decodedPrimary.rawBytes,
          stat: stat,
        );
        _logSettingsLoad(decodedPrimary.document);
        return (
          document: decodedPrimary.document,
          primaryBytes: decodedPrimary.rawBytes,
        );
      }
      _cachedSettingsSnapshot = null;
      final quarantinedPrimary = _quarantineCorruptFile(settingsFilePath);
      return _recoverFromBackupOrResetLocked(
        settingsFilePath,
        backupPath,
        backupType: backupType,
        quarantinedPrimaryPath: quarantinedPrimary,
      );
    }

    _cachedSettingsSnapshot = null;
    if (backupType == FileSystemEntityType.file) {
      return _recoverFromBackupOrResetLocked(
        settingsFilePath,
        backupPath,
        backupType: backupType,
        quarantinedPrimaryPath: null,
      );
    }

    _logSettingsLoad(PersistedSettingsDocument.initial);
    return (document: PersistedSettingsDocument.initial, primaryBytes: null);
  }

  /// Reads, decompresses, and caches the host-local `.tts` sync state file for [targetId] under its exclusive lock.
  Future<WorkspaceSyncState> _loadSyncStateFromFileLocked(
    String targetId,
    String syncFilePath,
  ) async {
    _syncStateDiskReadCount++;
    final fileBytes = _readBoundedRegularBytes(
      syncFilePath,
      WorkspaceSyncState.maxSerializedBytes,
    );
    if (fileBytes == null) {
      _logSyncStateCorrupt(
        workspaceId: targetId,
        source: 'file',
        reason: 'read_or_size_exceeded',
      );
      return WorkspaceSyncState.empty;
    }
    final List<int>? wireBytes;
    try {
      wireBytes = await _decodeSyncStateWireBytes(fileBytes);
    } on Object {
      _logSyncStateCorrupt(
        workspaceId: targetId,
        source: 'file',
        reason: 'decompress_failed',
      );
      return WorkspaceSyncState.empty;
    }
    if (wireBytes == null) {
      _logSyncStateCorrupt(
        workspaceId: targetId,
        source: 'file',
        reason: 'decompress_bound_exceeded',
      );
      return WorkspaceSyncState.empty;
    }
    final decoded = WorkspaceSyncState.fromBytes(wireBytes);
    if (decoded == WorkspaceSyncState.empty) {
      _logSyncStateCorrupt(
        workspaceId: targetId,
        source: 'file',
        reason: 'invalid_payload',
      );
      return WorkspaceSyncState.empty;
    }
    _cachedSyncStatesByWorkspaceId[targetId] = decoded;
    _migratedOrAbsentLegacySyncIds.add(targetId);
    return decoded;
  }

  /// Migrates a legacy `0.4.0` sync state entry from [_storage] to [syncFilePath] and deletes the legacy keyring key.
  Future<WorkspaceSyncState> _migrateLegacySyncStateLocked(
    String targetId,
    String syncFilePath,
  ) async {
    final legacyKey = '${buildProfile.syncStorageKeyPrefix}$targetId';
    final String? raw;
    try {
      raw = await _storage.read(key: legacyKey);
    } on Object {
      _logSyncStateCorrupt(
        workspaceId: targetId,
        source: 'legacy_secure_storage',
        reason: 'keyring_read_failed',
      );
      return WorkspaceSyncState.empty;
    }
    if (raw == null || raw.trim().isEmpty) {
      _migratedOrAbsentLegacySyncIds.add(targetId);
      return WorkspaceSyncState.empty;
    }
    final List<int>? wireBytes;
    try {
      final bytes = _base64Service.decodeBytes(raw.trim());
      wireBytes = await _decodeSyncStateWireBytes(bytes);
    } on Object {
      _logSyncStateCorrupt(
        workspaceId: targetId,
        source: 'legacy_secure_storage',
        reason: 'decode_failed',
      );
      return WorkspaceSyncState.empty;
    }
    if (wireBytes == null) {
      _logSyncStateCorrupt(
        workspaceId: targetId,
        source: 'legacy_secure_storage',
        reason: 'decompress_bound_exceeded',
      );
      return WorkspaceSyncState.empty;
    }
    final decoded = WorkspaceSyncState.fromBytes(wireBytes);
    if (decoded == WorkspaceSyncState.empty) {
      _logSyncStateCorrupt(
        workspaceId: targetId,
        source: 'legacy_secure_storage',
        reason: 'invalid_payload',
      );
      return WorkspaceSyncState.empty;
    }
    _ensureParentDirectory(syncFilePath);
    final payload = await _encodeSyncStatePayload(decoded);
    await _lockManager.writeAtomically(syncFilePath, payload);
    await _deleteKeyQuietly(legacyKey);
    _cachedSyncStatesByWorkspaceId[targetId] = decoded;
    _migratedOrAbsentLegacySyncIds.add(targetId);
    AppLogger.event(
      LogLevel.info,
      LogTag.storage,
      'settings.sync_state.migrated',
      fields: <String, Object?>{'workspace_id': targetId},
    );
    return decoded;
  }

  /// Atomically writes [document] to [settingsFilePath], rotating validated [priorPrimaryBytes] to `.bak` without re-reading disk.
  Future<void> _persistDocumentLocked(
    String settingsFilePath,
    PersistedSettingsDocument document, {
    required bool secretUpdated,
    required List<int>? priorPrimaryBytes,
  }) async {
    final backupPath = '$settingsFilePath.bak';
    final primaryType = _inspectFileType(settingsFilePath, 'primary');
    _inspectFileType(backupPath, 'backup');
    _ensureParentDirectory(settingsFilePath);

    var backupRotated = false;
    if (primaryType == FileSystemEntityType.file && priorPrimaryBytes != null) {
      await _lockManager.writeAtomically(backupPath, priorPrimaryBytes);
      backupRotated = true;
    }

    final encodedJson = SettingsCodec.encodeJson(document);
    final encodedBytes = _utf8Codec.encode(encodedJson);
    _cachedSettingsSnapshot = null;
    await _lockManager.writeAtomically(settingsFilePath, encodedBytes);
    _updateSettingsCache(settingsFilePath, document, encodedBytes);
    AppLogger.event(
      LogLevel.debug,
      LogTag.storage,
      'settings.save',
      fields: <String, Object?>{
        'workspace_count': document.workspaces.length,
        'active_id': document.activeWorkspaceId,
        'backup_rotated': backupRotated,
        'secret_updated': secretUpdated,
      },
    );
  }

  /// Atomically renames corrupt regular [corruptPath] to `<corruptPath>.corrupt.<YYYYMMDDTHHMMSSZ>`.
  String _quarantineCorruptFile(String corruptPath) {
    final timestamp = _formatQuarantineTimestamp(_clock().toUtc());
    final baseCandidate = '$corruptPath.corrupt.$timestamp';
    String? quarantinePath;
    for (var slot = 0; slot < _maxQuarantineCollisionSlots; slot++) {
      final candidate = slot == 0
          ? baseCandidate
          : '$baseCandidate.${slot.toString().padLeft(3, '0')}';
      if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
          FileSystemEntityType.notFound) {
        quarantinePath = candidate;
        break;
      }
    }
    if (quarantinePath == null) {
      throw const WorkspaceException(
        WorkspaceErrorKind.settingsPersistenceFailed,
        'All quarantine filename slots are occupied for corrupt settings.',
      );
    }
    try {
      File(corruptPath).renameSync(quarantinePath);
      return quarantinePath;
    } on FileSystemException catch (error) {
      throw WorkspaceException(
        WorkspaceErrorKind.settingsPersistenceFailed,
        'Could not quarantine corrupt settings file.',
        cause: error,
      );
    }
  }

  /// Reads at most [maxBytes] from regular file [path], returning `null` if unreadable or oversized.
  Uint8List? _readBoundedRegularBytes(String path, int maxBytes) {
    try {
      final randomAccessFile = File(path).openSync();
      try {
        final bytes = randomAccessFile.readSync(maxBytes + 1);
        if (bytes.length > maxBytes) {
          return null;
        }
        return bytes;
      } finally {
        randomAccessFile.closeSync();
      }
    } on FileSystemException {
      return null;
    }
  }

  /// Best-effort reads [key] from [_storage], returning `null` when unavailable.
  Future<String?> _readKeyQuietly(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object {
      return null;
    }
  }

  /// Restores [settingsFilePath] from [backupPath] or resets cleanly to [PersistedSettingsDocument.initial].
  Future<({PersistedSettingsDocument document, List<int> primaryBytes})>
  _recoverFromBackupOrResetLocked(
    String settingsFilePath,
    String backupPath, {
    required FileSystemEntityType backupType,
    required String? quarantinedPrimaryPath,
  }) async {
    var quarantinedPath = quarantinedPrimaryPath;
    if (backupType == FileSystemEntityType.file) {
      final decodedBackup = _tryReadAndDecodeFile(
        backupPath,
        countAsPrimaryRead: false,
      );
      if (decodedBackup != null) {
        _ensureParentDirectory(settingsFilePath);
        await _lockManager.writeAtomically(
          settingsFilePath,
          decodedBackup.rawBytes,
        );
        _updateSettingsCache(
          settingsFilePath,
          decodedBackup.document,
          decodedBackup.rawBytes,
        );
        _lastRecoveryNotice = SettingsRecoveryNotice(
          kind: SettingsRecoveryKind.recoveredFromBackup,
          quarantinedFilePath: quarantinedPrimaryPath,
        );
        AppLogger.event(
          LogLevel.warn,
          LogTag.storage,
          'settings.recovered_from_backup',
          fields: <String, Object?>{
            'quarantined_path': quarantinedPrimaryPath ?? 'missing_primary',
            'workspace_count': decodedBackup.document.workspaces.length,
          },
        );
        return (
          document: decodedBackup.document,
          primaryBytes: decodedBackup.rawBytes,
        );
      }
      final quarantinedBackup = _quarantineCorruptFile(backupPath);
      quarantinedPath ??= quarantinedBackup;
    }

    _ensureParentDirectory(settingsFilePath);
    final initialBytes = _utf8Codec.encode(
      SettingsCodec.encodeJson(PersistedSettingsDocument.initial),
    );
    await _lockManager.writeAtomically(settingsFilePath, initialBytes);
    _updateSettingsCache(
      settingsFilePath,
      PersistedSettingsDocument.initial,
      initialBytes,
    );
    _lastRecoveryNotice = SettingsRecoveryNotice(
      kind: SettingsRecoveryKind.resetAfterQuarantine,
      quarantinedFilePath: quarantinedPath,
    );
    AppLogger.event(
      LogLevel.error,
      LogTag.storage,
      'settings.corrupt_quarantined',
      fields: <String, Object?>{
        'quarantined_path': quarantinedPath ?? 'unknown',
        'fallback': 'default_workspace',
      },
    );
    return (
      document: PersistedSettingsDocument.initial,
      primaryBytes: initialBytes,
    );
  }

  /// Resolves `<Context.filesDir>/<dataDirectoryName>` on Android without falling back to `cacheDir`.
  Future<String> _resolveAndroidSettingsDirectory(String separator) async {
    final resolver =
        _androidFilesDirectoryResolver ?? _invokeAndroidFilesDirectoryChannel;
    final String? filesDir;
    try {
      filesDir = await resolver();
    } on Object catch (error) {
      throw WorkspaceException(
        WorkspaceErrorKind.settingsPersistenceFailed,
        'Could not resolve Android persistent files directory.',
        cause: error,
      );
    }
    final trimmed = filesDir?.trim() ?? '';
    if (trimmed.isEmpty) {
      throw const WorkspaceException(
        WorkspaceErrorKind.settingsPersistenceFailed,
        'Android persistent files directory resolved to empty path.',
      );
    }
    if (Platform.isAndroid && _androidFilesDirectoryResolver == null) {
      LocalFileRepository.cacheAndroidFilesDirectory(trimmed);
    }
    return _joinDirectoryAndChild(
      trimmed,
      buildProfile.dataDirectoryName,
      separator,
    );
  }

  /// Resolves and caches the platform-native absolute settings directory path.
  Future<String> _resolveSettingsDirectoryPath() async {
    if (_cachedSettingsDirectoryPath case final cached?) {
      return cached;
    }
    final separator = Platform.pathSeparator;
    final override = _settingsDirectoryOverride?.trim() ?? '';
    final String directoryPath;
    if (override.isNotEmpty) {
      directoryPath = TdfFilePath.trimTrailingSeparators(override);
    } else if (Platform.isAndroid || _androidFilesDirectoryResolver != null) {
      directoryPath = await _resolveAndroidSettingsDirectory(separator);
    } else {
      directoryPath = TdfFilePath.trimTrailingSeparators(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: buildProfile,
        ),
      );
    }
    _cachedSettingsDirectoryPath = directoryPath;
    return directoryPath;
  }

  /// Resolves and caches the platform-native absolute path of `settings.json`.
  Future<String> _resolveSettingsFilePath() async {
    if (_cachedSettingsFilePath case final cached?) {
      return cached;
    }
    final directoryPath = await _resolveSettingsDirectoryPath();
    final resolved = _joinDirectoryAndChild(
      directoryPath,
      SettingsCodec.settingsFileName,
      Platform.pathSeparator,
    );
    _cachedSettingsFilePath = resolved;
    return resolved;
  }

  /// Resolves the host-local `sync_state_<workspaceId>.tts` file path inside the settings directory.
  Future<String> _resolveSyncStateFilePath(String validWorkspaceId) async {
    final directoryPath = await _resolveSettingsDirectoryPath();
    return _joinDirectoryAndChild(
      directoryPath,
      'sync_state_$validWorkspaceId.tts',
      Platform.pathSeparator,
    );
  }

  /// Best-effort restores [_storage], [_cachedPasswordsByWorkspaceId], and [_unreadableSecretWorkspaceIds] for [workspaceId] after a persistence failure.
  Future<void> _rollbackWorkspacePasswordQuietly(
    String workspaceId,
    _PasswordRollbackSnapshot snapshot,
  ) async {
    final key = '${buildProfile.webdavPasswordKeyPrefix}$workspaceId';
    if (!snapshot.hadStoredSecret) {
      await _deleteKeyQuietly(key);
      _cachedPasswordsByWorkspaceId.remove(workspaceId);
    } else if (snapshot.previousPassword case final previous?
        when previous.isNotEmpty) {
      await _writeKeyQuietly(key, previous);
      if (snapshot.wasCached) {
        _cachedPasswordsByWorkspaceId[workspaceId] = previous;
      } else {
        _cachedPasswordsByWorkspaceId.remove(workspaceId);
      }
    } else if (snapshot.wasCached && snapshot.previousPassword == '') {
      await _deleteKeyQuietly(key);
      _cachedPasswordsByWorkspaceId[workspaceId] = '';
    } else {
      _cachedPasswordsByWorkspaceId.remove(workspaceId);
    }
    if (snapshot.wasUnreadable) {
      _unreadableSecretWorkspaceIds.add(workspaceId);
    } else {
      _unreadableSecretWorkspaceIds.remove(workspaceId);
    }
  }

  /// Validates and persists [config] and its keyring password onto [targetWorkspaceId] under the exclusive lock.
  Future<void> _saveWorkspaceConfigLocked(
    String settingsFilePath,
    PersistedSettingsDocument document,
    String targetWorkspaceId,
    WebDavConfig config, {
    required List<int>? priorPrimaryBytes,
  }) async {
    final updatedWorkspaces = _updateWorkspaceConfigEntry(
      document.workspaces,
      targetWorkspaceId,
      config.copyWith(password: ''),
    );
    final secretSync = await _syncPasswordForSave(
      targetWorkspaceId,
      config.password,
      document.passwordStoredWorkspaceIds,
    );
    final updatedDocument = document.copyWith(
      workspaces: updatedWorkspaces,
      passwordStoredWorkspaceIds: secretSync.nextStoredIds,
    );
    try {
      await _persistDocumentLocked(
        settingsFilePath,
        updatedDocument,
        secretUpdated: secretSync.secretUpdated,
        priorPrimaryBytes: priorPrimaryBytes,
      );
    } on Object {
      if (secretSync.rollback case final snapshot?
          when secretSync.secretUpdated) {
        await _rollbackWorkspacePasswordQuietly(targetWorkspaceId, snapshot);
      }
      rethrow;
    }
  }

  /// Synchronizes [password] for [workspaceId] against [_cachedPasswordsByWorkspaceId] and [_storage].
  Future<
    ({
      Set<String> nextStoredIds,
      bool secretUpdated,
      _PasswordRollbackSnapshot? rollback,
    })
  >
  _syncPasswordForSave(
    String workspaceId,
    String password,
    Set<String> currentStoredIds,
  ) async {
    if (password.isNotEmpty) {
      final isUnchanged =
          currentStoredIds.contains(workspaceId) &&
          _cachedPasswordsByWorkspaceId[workspaceId] == password;
      if (isUnchanged) {
        return (
          nextStoredIds: currentStoredIds,
          secretUpdated: false,
          rollback: null,
        );
      }
      final rollback = await _capturePasswordRollbackSnapshot(
        workspaceId,
        currentStoredIds,
      );
      await _writeWorkspacePassword(workspaceId, password);
      return (
        nextStoredIds: <String>{...currentStoredIds, workspaceId},
        secretUpdated: true,
        rollback: rollback,
      );
    }
    if (_unreadableSecretWorkspaceIds.contains(workspaceId) ||
        !currentStoredIds.contains(workspaceId)) {
      return (
        nextStoredIds: currentStoredIds,
        secretUpdated: false,
        rollback: null,
      );
    }
    final rollback = await _capturePasswordRollbackSnapshot(
      workspaceId,
      currentStoredIds,
    );
    await _deleteWorkspacePassword(workspaceId);
    final updatedIds = Set<String>.from(currentStoredIds)..remove(workspaceId);
    return (nextStoredIds: updatedIds, secretUpdated: true, rollback: rollback);
  }

  /// Reads and decodes a regular settings JSON file at [path] via bounded I/O, returning `null` if unreadable, oversized, or corrupt.
  ({PersistedSettingsDocument document, List<int> rawBytes})?
  _tryReadAndDecodeFile(String path, {bool countAsPrimaryRead = true}) {
    if (countAsPrimaryRead) {
      _settingsDiskReadCount++;
    }
    final rawBytes = _readBoundedRegularBytes(path, SettingsCodec.maxJsonBytes);
    if (rawBytes == null) {
      return null;
    }

    try {
      final result = SettingsCodec.decodeJsonBytes(rawBytes);
      for (final warning in result.warnings) {
        AppLogger.event(
          LogLevel.warn,
          LogTag.storage,
          'settings.decode_warning',
          fields: <String, Object?>{
            'workspace_id': warning.workspaceId ?? 'root',
            'field': warning.field,
            'reason': warning.reason,
          },
        );
      }
      return (document: result.document, rawBytes: rawBytes);
    } on WorkspaceException catch (error) {
      if (error.kind == WorkspaceErrorKind.unsupportedSettingsSchemaVersion) {
        AppLogger.event(
          LogLevel.error,
          LogTag.storage,
          'settings.schema_unsupported',
          fields: <String, Object?>{
            if (error.cause case final int foundVersion)
              'found_version': foundVersion,
            'supported_version': SettingsCodec.currentSchemaVersion,
          },
        );
        rethrow;
      }
      return null;
    }
  }

  /// Refreshes [_cachedSettingsSnapshot] with [document], [rawBytes], and the current file metadata of [settingsFilePath].
  void _updateSettingsCache(
    String settingsFilePath,
    PersistedSettingsDocument document,
    List<int> rawBytes, {
    FileStat? stat,
  }) {
    final effectiveStat = stat ?? FileStat.statSync(settingsFilePath);
    if (effectiveStat.type != FileSystemEntityType.file) {
      _cachedSettingsSnapshot = null;
      return;
    }
    _cachedSettingsSnapshot = (
      filePath: settingsFilePath,
      modified: effectiveStat.modified,
      changed: effectiveStat.changed,
      size: effectiveStat.size,
      document: document,
      rawBytes: rawBytes,
    );
  }

  /// Best-effort writes [value] to [key] in [_storage], ignoring unavailable keyring errors during rollback.
  Future<void> _writeKeyQuietly(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on Object {
      // Best-effort rollback when settings persistence fails.
    }
  }

  /// Writes [password] for [workspaceId] to [_storage] and updates the session cache.
  Future<void> _writeWorkspacePassword(
    String workspaceId,
    String password,
  ) async {
    final key = '${buildProfile.webdavPasswordKeyPrefix}$workspaceId';
    try {
      await _storage.write(key: key, value: password);
      _cachedPasswordsByWorkspaceId[workspaceId] = password;
      _unreadableSecretWorkspaceIds.remove(workspaceId);
    } on Object catch (error) {
      _logKeyringFailure(
        'settings.secret.write_failed',
        error,
        workspaceId: workspaceId,
        operation: 'write',
      );
      throw WorkspaceException(
        WorkspaceErrorKind.credentialStorageUnavailable,
        'Could not save WebDAV password to secure credential storage.',
        cause: error,
      );
    }
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

  /// Saves [config] to the specific workspace matching [workspaceId], throwing [WorkspaceErrorKind.workspaceNotFound] if absent.
  Future<void> saveConfigForWorkspace(
    String workspaceId,
    WebDavConfig config,
  ) => saveConfig(config);

  /// Persists the synchronization [state] for [workspaceId].
  Future<void> saveWorkspaceSyncState(
    String workspaceId,
    WorkspaceSyncState state,
  );

  /// Returns and clears the most recent one-shot startup recovery notice, if any.
  SettingsRecoveryNotice? takeLastRecoveryNotice();
}

/// Bounded byte sink aborting decompression as soon as output exceeds [maxBytes].
class _BoundedBytesSink implements Sink<List<int>> {
  /// Creates a [_BoundedBytesSink] capped at [maxBytes].
  _BoundedBytesSink(this.maxBytes);

  /// Maximum allowed cumulative output byte length.
  final int maxBytes;

  final BytesBuilder _builder = BytesBuilder(copy: false);
  bool _exceeded = false;

  /// Whether accumulated output exceeded [maxBytes].
  bool get exceeded => _exceeded;

  @override
  void add(List<int> data) {
    if (_exceeded) {
      return;
    }
    if (_builder.length + data.length > maxBytes) {
      _exceeded = true;
      _builder.clear();
      return;
    }
    _builder.add(data);
  }

  @override
  void close() {}

  /// Returns all buffered bytes and clears the underlying builder.
  List<int> takeBytes() => _builder.takeBytes();
}

/// Snapshot of prior workspace password storage and cache state used for rollback on persistence failure.
@immutable
class _PasswordRollbackSnapshot {
  /// Creates a [_PasswordRollbackSnapshot].
  const _PasswordRollbackSnapshot({
    required this.hadStoredSecret,
    required this.wasCached,
    required this.wasUnreadable,
    this.previousPassword,
  });

  /// Whether `settings.json` previously recorded a stored password for this workspace.
  final bool hadStoredSecret;

  /// Previously cached or stored password value, if known.
  final String? previousPassword;

  /// Whether `_cachedPasswordsByWorkspaceId` previously held an entry for this workspace.
  final bool wasCached;

  /// Whether `_unreadableSecretWorkspaceIds` previously marked this workspace as unreadable.
  final bool wasUnreadable;
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

  final resolvedId = id != null
      ? _validateCustomWorkspaceId(id, existingWorkspaces)
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

/// Compresses [rawBytes] with gzip and returns the shorter of compressed or raw bytes.
List<int> _compressSyncStateBytesSync(List<int> rawBytes) {
  final compressed = gzip.encode(rawBytes);
  return compressed.length < rawBytes.length ? compressed : rawBytes;
}

/// Decompresses gzip-wrapped [bytes] in chunks while enforcing [WorkspaceSyncState.maxSerializedBytes].
List<int>? _decodeGzipSyncStateBytesSync(List<int> bytes) {
  const gzipChunkBytes = 4096;
  final typedBytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final sink = _BoundedBytesSink(WorkspaceSyncState.maxSerializedBytes);
  final inputSink = gzip.decoder.startChunkedConversion(sink);
  var abortedEarly = false;
  try {
    for (var offset = 0; offset < typedBytes.length; offset += gzipChunkBytes) {
      final end = offset + gzipChunkBytes < typedBytes.length
          ? offset + gzipChunkBytes
          : typedBytes.length;
      inputSink.add(Uint8List.sublistView(typedBytes, offset, end));
      if (sink.exceeded) {
        abortedEarly = true;
        return null;
      }
    }
  } finally {
    if (abortedEarly) {
      try {
        inputSink.close();
      } on Object {
        // Ignore truncated-stream trailer errors while releasing zlib sink resources.
      }
    } else {
      inputSink.close();
    }
  }
  if (sink.exceeded) {
    return null;
  }
  return sink.takeBytes();
}

/// Ensures the parent directory of [filePath] exists, wrapping I/O failures into [WorkspaceException].
void _ensureParentDirectory(String filePath) {
  try {
    Directory(filePath).parent.createSync(recursive: true);
  } on FileSystemException catch (error) {
    throw WorkspaceException(
      WorkspaceErrorKind.settingsPersistenceFailed,
      'Could not prepare settings directory.',
      cause: error,
    );
  }
}

/// Maps [entityType] to an obfuscation-safe static token for diagnostic logging.
String _entityTypeToken(FileSystemEntityType entityType) =>
    switch (entityType) {
      FileSystemEntityType.directory => 'directory',
      FileSystemEntityType.link => 'link',
      FileSystemEntityType.pipe => 'pipe',
      FileSystemEntityType.unixDomainSock => 'unix_domain_sock',
      FileSystemEntityType.file => 'file',
      FileSystemEntityType.notFound => 'not_found',
      _ => 'other',
    };

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

/// Formats [utcNow] as a compact `YYYYMMDDTHHMMSSZ` quarantine suffix.
String _formatQuarantineTimestamp(DateTime utcNow) {
  final year = utcNow.year.toString().padLeft(4, '0');
  final month = utcNow.month.toString().padLeft(2, '0');
  final day = utcNow.day.toString().padLeft(2, '0');
  final hour = utcNow.hour.toString().padLeft(2, '0');
  final minute = utcNow.minute.toString().padLeft(2, '0');
  final second = utcNow.second.toString().padLeft(2, '0');
  return '$year$month${day}T$hour$minute${second}Z';
}

/// Joins [directoryPath] and [childName] using [separator] while preserving POSIX and Windows drive roots.
String _joinDirectoryAndChild(
  String directoryPath,
  String childName,
  String separator,
) {
  final cleanDirectory = TdfFilePath.trimTrailingSeparators(directoryPath);
  if (cleanDirectory.isEmpty) {
    return childName;
  }
  final lastCode = cleanDirectory.codeUnitAt(cleanDirectory.length - 1);
  if (lastCode == 0x2F || lastCode == 0x5C) {
    return '$cleanDirectory$childName';
  }
  return '$cleanDirectory$separator$childName';
}

/// Logs an obfuscation-safe structured keyring error event.
void _logKeyringFailure(
  String eventName,
  Object error, {
  String? workspaceId,
  String? operation,
}) {
  final (reason, code) = switch (error) {
    final MissingPluginException _ => ('missing_plugin', null),
    final PlatformException platformError => (
      'platform_exception',
      platformError.code,
    ),
    _ => ('unexpected_error', null),
  };
  AppLogger.event(
    LogLevel.error,
    LogTag.storage,
    eventName,
    fields: <String, Object?>{
      'workspace_id': ?workspaceId,
      'operation': ?operation,
      'reason': reason,
      if (code != null && code.isNotEmpty) 'code': code,
    },
  );
}

/// Emits a debug `settings.load` diagnostic event for [document].
void _logSettingsLoad(PersistedSettingsDocument document) {
  AppLogger.event(
    LogLevel.debug,
    LogTag.storage,
    'settings.load',
    fields: <String, Object?>{
      'workspace_count': document.workspaces.length,
      'active_id': document.activeWorkspaceId,
      'schema_version': document.schemaVersion,
    },
  );
}

/// Emits a warning diagnostic event when persisted sync state falls back to [WorkspaceSyncState.empty].
void _logSyncStateCorrupt({
  required String workspaceId,
  required String source,
  required String reason,
}) {
  AppLogger.event(
    LogLevel.warn,
    LogTag.storage,
    'settings.sync_state.corrupt',
    fields: <String, Object?>{
      'workspace_id': workspaceId,
      'source': source,
      'reason': reason,
    },
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

/// Returns a copy of [workspace] with its WebDAV password stripped before JSON serialization.
AppWorkspace _stripPassword(AppWorkspace workspace) =>
    workspace.copyWith(config: workspace.config.copyWith(password: ''));

/// Validates [workspaceId] as a single filename-safe segment without path separators, traversal, colons, or control characters.
String? _tryValidateSyncWorkspaceId(String workspaceId) {
  final trimmed = workspaceId.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 128 ||
      trimmed == '.' ||
      trimmed == '..' ||
      trimmed.contains('..') ||
      trimmed.contains('/') ||
      trimmed.contains(r'\') ||
      trimmed.contains(':') ||
      AppWorkspace.hasControlCharacters(trimmed)) {
    return null;
  }
  return trimmed;
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

/// Validates a caller-supplied workspace [rawId] for control-character/filename safety and uniqueness across [existingWorkspaces].
String _validateCustomWorkspaceId(
  String rawId,
  List<AppWorkspace> existingWorkspaces,
) {
  if (AppWorkspace.hasControlCharacters(rawId)) {
    throw const WorkspaceException(
      WorkspaceErrorKind.settingsPersistenceFailed,
      'Workspace identifier contains invalid characters.',
    );
  }
  final validatedId = _tryValidateSyncWorkspaceId(rawId);
  if (validatedId == null) {
    throw const WorkspaceException(
      WorkspaceErrorKind.settingsPersistenceFailed,
      'Workspace identifier is invalid.',
    );
  }
  final normalizedTarget = validatedId.toLowerCase();
  for (final existing in existingWorkspaces) {
    if (existing.id.toLowerCase() == normalizedTarget) {
      throw WorkspaceException(
        WorkspaceErrorKind.settingsPersistenceFailed,
        'A workspace with identifier "$validatedId" already exists.',
      );
    }
  }
  return validatedId;
}
