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

/// Readability state of a single active `.tdf` storage file.
enum StorageFileReadState {
  /// File was read and parsed cleanly (or is absent/empty and ready for initialization).
  readable,

  /// File header specifies an unsupported TDF format version.
  unsupportedVersion,

  /// File could not be read or parsed due to an I/O, network, or format error.
  unreadable,
}

/// Identifies which `.tdf` storage target a [StorageFileReadStatus] describes.
enum StorageFileTarget {
  /// Local `.tdf` file on the device filesystem.
  local,

  /// Remote `.tdf` file on the WebDAV server.
  remote,
}

/// High-level classification of which active `.tdf` file(s) could not be read.
enum StorageReadFailureScope {
  /// Only local storage is active and the local file could not be read.
  localOnly,

  /// Only WebDAV storage is active and the remote file could not be read.
  remoteOnly,

  /// Both storage targets are active; only the local file failed while the remote file is intact.
  localFailedRemoteOk,

  /// Both storage targets are active; only the remote file failed while the local file is intact.
  remoteFailedLocalOk,

  /// Both storage targets are active and neither file could be read.
  bothFailed,
}

/// Immutable diagnostic report describing the readability of active local and/or remote `.tdf` files.
@immutable
class StorageFileReadReport {
  /// Creates a [StorageFileReadReport] with at least one active target status.
  const StorageFileReadReport({this.local, this.remote})
    : assert(
        local != null || remote != null,
        'At least one storage target status must be provided.',
      );

  /// Read status of the local `.tdf` file, or `null` when local storage is inactive.
  final StorageFileReadStatus? local;

  /// Read status of the remote WebDAV `.tdf` file, or `null` when WebDAV storage is inactive.
  final StorageFileReadStatus? remote;

  /// Active target statuses in deterministic display order (local first, then remote).
  List<StorageFileReadStatus> get activeEntries =>
      List<StorageFileReadStatus>.unmodifiable(<StorageFileReadStatus>[
        ?local,
        ?remote,
      ]);

  /// Whether both local and remote storage files were evaluated.
  bool get evaluatesBoth => local != null && remote != null;

  /// Classifies which active file(s) failed to read, or returns `null` when all active files are readable.
  StorageReadFailureScope? get failureScope {
    final localEntry = local;
    final remoteEntry = remote;
    if (localEntry != null && remoteEntry != null) {
      if (!localEntry.isReadable && !remoteEntry.isReadable) {
        return StorageReadFailureScope.bothFailed;
      }
      if (!localEntry.isReadable) {
        return StorageReadFailureScope.localFailedRemoteOk;
      }
      if (!remoteEntry.isReadable) {
        return StorageReadFailureScope.remoteFailedLocalOk;
      }
      return null;
    }
    if (localEntry != null && !localEntry.isReadable) {
      return StorageReadFailureScope.localOnly;
    }
    if (remoteEntry != null && !remoteEntry.isReadable) {
      return StorageReadFailureScope.remoteOnly;
    }
    return null;
  }

  /// Whether at least one active storage file could not be read.
  bool get hasFailure => failureScope != null;

  /// Whether at least one active storage file failed due to an unsupported TDF version.
  bool get hasUnsupportedVersion =>
      (local?.isUnsupportedVersion ?? false) ||
      (remote?.isUnsupportedVersion ?? false);

  /// Underlying cause exception from the first failed storage target (local preferred over remote).
  Object? get primaryCause {
    if (local case final entry? when !entry.isReadable && entry.cause != null) {
      return entry.cause;
    }
    if (remote case final entry?
        when !entry.isReadable && entry.cause != null) {
      return entry.cause;
    }
    return null;
  }

  /// Combined unsupported version label across affected target(s), or `null` when no target has an unsupported version.
  String? get unsupportedVersionLabel {
    final localVersion = local?.isUnsupportedVersion == true
        ? (local?.unsupportedVersion ?? '?')
        : null;
    final remoteVersion = remote?.isUnsupportedVersion == true
        ? (remote?.unsupportedVersion ?? '?')
        : null;
    if (localVersion != null && remoteVersion != null) {
      return localVersion == remoteVersion
          ? localVersion
          : '$localVersion / $remoteVersion';
    }
    return localVersion ?? remoteVersion;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StorageFileReadReport &&
          other.local == local &&
          other.remote == remote);

  @override
  int get hashCode => Object.hash(local, remote);

  @override
  String toString() =>
      'StorageFileReadReport(local: $local, remote: $remote, scope: ${failureScope?.name})';
}

/// Immutable readability status for a single active `.tdf` storage target.
@immutable
class StorageFileReadStatus {
  /// Creates a [StorageFileReadStatus] entry.
  const StorageFileReadStatus({
    required this.target,
    required this.state,
    this.detail,
    this.line,
    this.unsupportedVersion,
    this.cause,
  });

  /// Creates a readable/intact status entry for [target].
  const StorageFileReadStatus.readable(this.target)
    : state = StorageFileReadState.readable,
      detail = null,
      line = null,
      unsupportedVersion = null,
      cause = null;

  /// Creates an unreadable status entry for [target] with optional [detail], [line], and [cause].
  const StorageFileReadStatus.unreadable(
    this.target, {
    this.detail,
    this.line,
    this.cause,
  }) : state = StorageFileReadState.unreadable,
       unsupportedVersion = null;

  /// Creates an unsupported-version status entry for [target] with detected [version] and optional [cause].
  const StorageFileReadStatus.unsupportedVersion(
    this.target, {
    required String version,
    this.cause,
  }) : state = StorageFileReadState.unsupportedVersion,
       detail = null,
       line = null,
       unsupportedVersion = version;

  /// Optional underlying exception that caused the read failure.
  final Object? cause;

  /// Optional diagnostic detail text for [StorageFileReadState.unreadable].
  final String? detail;

  /// Optional 1-based line number when a `.tdf` document failed parsing or validation.
  final int? line;

  /// Readability outcome for [target].
  final StorageFileReadState state;

  /// Storage target represented by this entry.
  final StorageFileTarget target;

  /// Detected offending version token when [state] is [StorageFileReadState.unsupportedVersion].
  final String? unsupportedVersion;

  /// Whether [target] was read and parsed cleanly.
  bool get isReadable => state == StorageFileReadState.readable;

  /// Whether [target] failed specifically due to an unsupported TDF version header.
  bool get isUnsupportedVersion =>
      state == StorageFileReadState.unsupportedVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StorageFileReadStatus &&
          other.target == target &&
          other.state == state &&
          other.detail == detail &&
          other.line == line &&
          other.unsupportedVersion == unsupportedVersion);

  @override
  int get hashCode =>
      Object.hash(target, state, detail, line, unsupportedVersion);

  @override
  String toString() =>
      'StorageFileReadStatus(${target.name}, ${state.name}, '
      'version: $unsupportedVersion, line: $line, detail: $detail)';
}
