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
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_build_profile.dart';
import '../models/app_workspace.dart';
import '../models/legacy_ttw_v2_converter.dart';
import '../models/settings_codec.dart';
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
  static const int _gzipChunkBytes = 4096;
  static const int _gzipMagicByte0 = 0x1F;
  static const int _gzipMagicByte1 = 0x8B;
  static const Base64Service _legacyBase64Service = Base64Service(
    maxInputBytes: LegacyTtwV2Converter.maxBinaryBytes,
  );
  static const int _maxQuarantineCollisionSlots = 100;
  static const Utf8Codec _utf8Codec = Utf8Codec(allowMalformed: false);

  /// Active build storage profile determining directory and secure storage key namespaces.
  final AppBuildProfile buildProfile;

  final Future<String?> Function()? _androidFilesDirectoryResolver;
  final Map<String, String> _cachedPasswordsByWorkspaceId = <String, String>{};
  String? _cachedSettingsFilePath;
  final DateTime Function() _clock;
  SettingsRecoveryNotice? _lastRecoveryNotice;
  final HostFileLockManager<WorkspaceException> _lockManager;
  final String? _settingsDirectoryOverride;
  final FlutterSecureStorage _storage;
  final Set<String> _unreadableSecretWorkspaceIds = <String>{};

  @override
  Future<AppWorkspace> activateWorkspace(String workspaceId) async {
    final settingsFilePath = await _resolveSettingsFilePath();
    return _lockManager.withExclusiveLock(settingsFilePath, () async {
      final document = await _loadDocumentLocked(settingsFilePath);
      final target = _findWorkspace(document.workspaces, workspaceId);
      final updatedDocument = document.copyWith(activeWorkspaceId: target.id);
      await _persistDocumentLocked(
        settingsFilePath,
        updatedDocument,
        secretUpdated: false,
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
      final document = await _loadDocumentLocked(settingsFilePath);
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
      await _persistDocumentLocked(
        settingsFilePath,
        updatedDocument,
        secretUpdated: secretUpdated,
      );
      return created;
    });
  }

  @override
  Future<AppWorkspace> deleteWorkspace(String workspaceId) async {
    final settingsFilePath = await _resolveSettingsFilePath();
    return _lockManager.withExclusiveLock(settingsFilePath, () async {
      final document = await _loadDocumentLocked(settingsFilePath);
      final updated = _removeWorkspace(
        document.workspaces,
        document.activeWorkspaceId,
        workspaceId,
      );
      final targetId = workspaceId.trim();
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
      );
      _cachedPasswordsByWorkspaceId.remove(targetId);
      _unreadableSecretWorkspaceIds.remove(targetId);
      await _deleteKeyQuietly(
        '${buildProfile.webdavPasswordKeyPrefix}$targetId',
      );
      await _deleteKeyQuietly('${buildProfile.syncStorageKeyPrefix}$targetId');
      final active = _resolveActiveWorkspace(
        updatedDocument.workspaces,
        updatedDocument.activeWorkspaceId,
      );
      return _hydrateWorkspacePassword(active, updatedDocument);
    });
  }

  @override
  Future<AppWorkspace> loadActiveWorkspace() async {
    final settingsFilePath = await _resolveSettingsFilePath();
    return _lockManager.withExclusiveLock(settingsFilePath, () async {
      final document = await _loadDocumentLocked(settingsFilePath);
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
      final document = await _loadDocumentLocked(settingsFilePath);
      return List<WorkspaceSummary>.unmodifiable(<WorkspaceSummary>[
        for (final workspace in document.workspaces) workspace.summary,
      ]);
    });
  }

  @override
  Future<WorkspaceSyncState> loadWorkspaceSyncState(String workspaceId) async {
    try {
      final raw = await _storage.read(
        key: '${buildProfile.syncStorageKeyPrefix}${workspaceId.trim()}',
      );
      if (raw == null || raw.trim().isEmpty) {
        return WorkspaceSyncState.empty;
      }
      final bytes = _base64Service.decodeBytes(raw.trim());
      final wireBytes = _decodeSyncStateWireBytes(bytes);
      if (wireBytes == null) {
        return WorkspaceSyncState.empty;
      }
      return WorkspaceSyncState.fromBytes(wireBytes);
    } on Object {
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
      final document = await _loadDocumentLocked(settingsFilePath);
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
      );
      return _hydrateWorkspacePassword(updated.renamed, updatedDocument);
    });
  }

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    final settingsFilePath = await _resolveSettingsFilePath();
    await _lockManager.withExclusiveLock(settingsFilePath, () async {
      final document = await _loadDocumentLocked(settingsFilePath);
      final active = _resolveActiveWorkspace(
        document.workspaces,
        document.activeWorkspaceId,
      );
      final updatedWorkspaces = _updateWorkspaceConfigEntry(
        document.workspaces,
        active.id,
        config.copyWith(password: ''),
      );
      final secretSync = await _syncPasswordForSave(
        active.id,
        config.password,
        document.passwordStoredWorkspaceIds,
      );
      final updatedDocument = document.copyWith(
        workspaces: updatedWorkspaces,
        passwordStoredWorkspaceIds: secretSync.nextStoredIds,
      );
      await _persistDocumentLocked(
        settingsFilePath,
        updatedDocument,
        secretUpdated: secretSync.secretUpdated,
      );
    });
  }

  @override
  Future<void> saveWorkspaceSyncState(
    String workspaceId,
    WorkspaceSyncState state,
  ) async {
    final rawBytes = state.toBytes();
    final compressed = gzip.encode(rawBytes);
    final payload = compressed.length < rawBytes.length ? compressed : rawBytes;
    final encoded = _base64Service.encodeBytes(payload);
    await _storage.write(
      key: '${buildProfile.syncStorageKeyPrefix}${workspaceId.trim()}',
      value: encoded,
    );
  }

  @override
  SettingsRecoveryNotice? takeLastRecoveryNotice() {
    final notice = _lastRecoveryNotice;
    _lastRecoveryNotice = null;
    return notice;
  }

  /// Decompresses gzip-wrapped [bytes] with a strict upper output bound, or returns raw `TTS\x04` bytes directly.
  List<int>? _decodeSyncStateWireBytes(List<int> bytes) {
    final isGzip =
        bytes.length >= 2 &&
        bytes[0] == _gzipMagicByte0 &&
        bytes[1] == _gzipMagicByte1;
    if (!isGzip) {
      return bytes;
    }
    final sink = _BoundedBytesSink(WorkspaceSyncState.maxSerializedBytes);
    final inputSink = gzip.decoder.startChunkedConversion(sink);
    for (var offset = 0; offset < bytes.length; offset += _gzipChunkBytes) {
      final end = offset + _gzipChunkBytes < bytes.length
          ? offset + _gzipChunkBytes
          : bytes.length;
      inputSink.add(bytes.sublist(offset, end));
      if (sink.exceeded) {
        return null;
      }
    }
    inputSink.close();
    if (sink.exceeded) {
      return null;
    }
    return sink.takeBytes();
  }

  /// Best-effort deletes [key] from [_storage], ignoring unavailable keyring errors.
  Future<void> _deleteKeyQuietly(String key) async {
    try {
      await _storage.write(key: key, value: null);
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

  /// Loads `settings.json` under the exclusive lock, performing backup recovery, quarantine, or legacy migration.
  Future<PersistedSettingsDocument> _loadDocumentLocked(
    String settingsFilePath,
  ) async {
    final backupPath = '$settingsFilePath.bak';
    final primaryType = _inspectFileType(settingsFilePath, 'primary');
    final backupType = _inspectFileType(backupPath, 'backup');

    if (primaryType == FileSystemEntityType.file) {
      final decodedPrimary = _tryReadAndDecodeFile(settingsFilePath);
      if (decodedPrimary != null) {
        _logSettingsLoad(decodedPrimary.document);
        return decodedPrimary.document;
      }
      final quarantinedPrimary = _quarantineCorruptFile(settingsFilePath);
      return _recoverFromBackupOrResetLocked(
        settingsFilePath,
        backupPath,
        backupType: backupType,
        quarantinedPrimaryPath: quarantinedPrimary,
      );
    }

    if (backupType == FileSystemEntityType.file) {
      return _recoverFromBackupOrResetLocked(
        settingsFilePath,
        backupPath,
        backupType: backupType,
        quarantinedPrimaryPath: null,
      );
    }

    final migrated = await _migrateLegacyTtwV2IfPresent(settingsFilePath);
    if (migrated != null) {
      return migrated;
    }
    _logSettingsLoad(PersistedSettingsDocument.initial);
    return PersistedSettingsDocument.initial;
  }

  /// Migrates legacy `TTW\x02` settings from [AppBuildProfile.legacySettingsStorageKey] once on first launch.
  @Deprecated(
    'One-time TTW\\x02 migration hook for pre-0.4.0 settings. '
    'Scheduled for removal in 0.5.0.',
  )
  Future<PersistedSettingsDocument?> _migrateLegacyTtwV2IfPresent(
    String settingsFilePath,
  ) async {
    final legacyKey = buildProfile.legacySettingsStorageKey;
    final String? rawLegacy;
    try {
      rawLegacy = await _storage.read(key: legacyKey);
    } on Object catch (error) {
      _logKeyringFailure(
        'settings.legacy_migration.keyring_unavailable',
        error,
        level: LogLevel.warn,
      );
      return null;
    }
    if (rawLegacy == null || rawLegacy.trim().isEmpty) {
      return null;
    }

    final ({List<AppWorkspace> workspaces, String activeId}) legacyDecoded;
    try {
      final bytes = _legacyBase64Service.decodeBytes(rawLegacy.trim());
      legacyDecoded = LegacyTtwV2Converter.decodeTtwV2Bytes(bytes);
    } on Base64Exception catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'settings.legacy_migration.failed',
        fields: <String, Object?>{'error_kind': error.kind.name},
      );
      return null;
    } on WorkspaceException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'settings.legacy_migration.failed',
        fields: <String, Object?>{'error_kind': error.kind.name},
      );
      return null;
    }

    final passwordStoredIds = <String>{};
    var migratedPasswords = 0;
    for (final workspace in legacyDecoded.workspaces) {
      if (workspace.config.password.isNotEmpty) {
        await _writeWorkspacePassword(workspace.id, workspace.config.password);
        passwordStoredIds.add(workspace.id);
        migratedPasswords++;
      }
    }

    final strippedWorkspaces = <AppWorkspace>[
      for (final workspace in legacyDecoded.workspaces)
        _stripPassword(workspace),
    ];
    final migratedDocument = PersistedSettingsDocument(
      schemaVersion: SettingsCodec.currentSchemaVersion,
      activeWorkspaceId: legacyDecoded.activeId,
      workspaces: strippedWorkspaces,
      passwordStoredWorkspaceIds: passwordStoredIds,
    );
    await _persistDocumentLocked(
      settingsFilePath,
      migratedDocument,
      secretUpdated: migratedPasswords > 0,
    );
    final verifiedReadBack = _tryReadAndDecodeFile(settingsFilePath);
    if (verifiedReadBack == null) {
      throw const WorkspaceException(
        WorkspaceErrorKind.settingsPersistenceFailed,
        'Migrated settings.json failed post-write verification.',
      );
    }

    var legacyKeyRemoved = true;
    try {
      await _storage.write(key: legacyKey, value: null);
    } on Object catch (error) {
      legacyKeyRemoved = false;
      _logKeyringFailure(
        'settings.legacy_migration.cleanup_failed',
        error,
        level: LogLevel.warn,
      );
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.storage,
      'settings.legacy_migration.completed',
      fields: <String, Object?>{
        'workspace_count': verifiedReadBack.document.workspaces.length,
        'migrated_passwords': migratedPasswords,
        'legacy_key_removed': legacyKeyRemoved,
      },
    );
    return verifiedReadBack.document;
  }

  /// Atomically writes [document] to [settingsFilePath], rotating valid prior settings to `.bak`.
  Future<void> _persistDocumentLocked(
    String settingsFilePath,
    PersistedSettingsDocument document, {
    required bool secretUpdated,
  }) async {
    final backupPath = '$settingsFilePath.bak';
    final primaryType = _inspectFileType(settingsFilePath, 'primary');
    _inspectFileType(backupPath, 'backup');
    _ensureParentDirectory(settingsFilePath);

    var backupRotated = false;
    if (primaryType == FileSystemEntityType.file) {
      backupRotated = await _rotateBackupIfValidLocked(
        settingsFilePath,
        backupPath,
      );
    }

    final encodedJson = SettingsCodec.encodeJson(document);
    final encodedBytes = _utf8Codec.encode(encodedJson);
    await _lockManager.writeAtomically(settingsFilePath, encodedBytes);
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

  /// Restores [settingsFilePath] from [backupPath] or resets cleanly to [PersistedSettingsDocument.initial].
  Future<PersistedSettingsDocument> _recoverFromBackupOrResetLocked(
    String settingsFilePath,
    String backupPath, {
    required FileSystemEntityType backupType,
    required String? quarantinedPrimaryPath,
  }) async {
    var quarantinedPath = quarantinedPrimaryPath;
    if (backupType == FileSystemEntityType.file) {
      final decodedBackup = _tryReadAndDecodeFile(backupPath);
      if (decodedBackup != null) {
        _ensureParentDirectory(settingsFilePath);
        await _lockManager.writeAtomically(
          settingsFilePath,
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
        return decodedBackup.document;
      }
      final quarantinedBackup = _quarantineCorruptFile(backupPath);
      quarantinedPath ??= quarantinedBackup;
    }

    _ensureParentDirectory(settingsFilePath);
    final initialBytes = _utf8Codec.encode(
      SettingsCodec.encodeJson(PersistedSettingsDocument.initial),
    );
    await _lockManager.writeAtomically(settingsFilePath, initialBytes);
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
    return PersistedSettingsDocument.initial;
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
    return '${_trimTrailingSeparators(trimmed)}$separator'
        '${buildProfile.dataDirectoryName}';
  }

  /// Resolves and caches the platform-native absolute path of `settings.json`.
  Future<String> _resolveSettingsFilePath() async {
    if (_cachedSettingsFilePath case final cached?) {
      return cached;
    }
    final separator = Platform.pathSeparator;
    final override = _settingsDirectoryOverride?.trim() ?? '';
    final String directoryPath;
    if (override.isNotEmpty) {
      directoryPath = _trimTrailingSeparators(override);
    } else if (Platform.isAndroid || _androidFilesDirectoryResolver != null) {
      directoryPath = await _resolveAndroidSettingsDirectory(separator);
    } else {
      directoryPath = _trimTrailingSeparators(
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: buildProfile,
        ),
      );
    }
    final resolved =
        '$directoryPath$separator${SettingsCodec.settingsFileName}';
    _cachedSettingsFilePath = resolved;
    return resolved;
  }

  /// Copies valid existing [settingsFilePath] bytes atomically to [backupPath] before overwriting.
  Future<bool> _rotateBackupIfValidLocked(
    String settingsFilePath,
    String backupPath,
  ) async {
    try {
      final existing = _tryReadAndDecodeFile(settingsFilePath);
      if (existing == null) {
        return false;
      }
      await _lockManager.writeAtomically(backupPath, existing.rawBytes);
      return true;
    } on WorkspaceException catch (error) {
      if (error.kind == WorkspaceErrorKind.unsupportedSettingsSchemaVersion) {
        rethrow;
      }
      return false;
    }
  }

  /// Synchronizes [password] for [workspaceId] against [_cachedPasswordsByWorkspaceId] and [_storage].
  Future<({Set<String> nextStoredIds, bool secretUpdated})>
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
        return (nextStoredIds: currentStoredIds, secretUpdated: false);
      }
      await _writeWorkspacePassword(workspaceId, password);
      return (
        nextStoredIds: <String>{...currentStoredIds, workspaceId},
        secretUpdated: true,
      );
    }
    if (_unreadableSecretWorkspaceIds.contains(workspaceId) ||
        !currentStoredIds.contains(workspaceId)) {
      return (nextStoredIds: currentStoredIds, secretUpdated: false);
    }
    await _deleteWorkspacePassword(workspaceId);
    final updatedIds = Set<String>.from(currentStoredIds)..remove(workspaceId);
    return (nextStoredIds: updatedIds, secretUpdated: true);
  }

  /// Reads and decodes a regular settings JSON file at [path], returning `null` if corrupt.
  ({PersistedSettingsDocument document, List<int> rawBytes})?
  _tryReadAndDecodeFile(String path) {
    final List<int> rawBytes;
    try {
      final file = File(path);
      if (file.lengthSync() > SettingsCodec.maxJsonBytes) {
        return null;
      }
      rawBytes = file.readAsBytesSync();
    } on FileSystemException {
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

/// Logs an obfuscation-safe structured keyring error event.
void _logKeyringFailure(
  String eventName,
  Object error, {
  LogLevel level = LogLevel.error,
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
    level,
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

/// Removes trailing POSIX and Windows path separators from [path], preserving root paths.
String _trimTrailingSeparators(String path) {
  var result = path;
  while (result.length > 1 && (result.endsWith('/') || result.endsWith(r'\'))) {
    result = result.substring(0, result.length - 1);
  }
  return result;
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
