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

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

/// Severity levels for structured diagnostic log entries.
enum LogLevel {
  /// Fine-grained diagnostic traces for development and deep troubleshooting.
  debug(0, 'DEBUG', 'DEBUG'),

  /// Normal operational milestones across lifecycle, TDF, domain, and sync.
  info(1, 'INFO', 'INFO '),

  /// Recoverable anomalies, fallbacks, or validation warnings.
  warn(2, 'WARN', 'WARN '),

  /// Operational failures, I/O errors, or rejected mutations.
  error(3, 'ERROR', 'ERROR'),

  /// Unhandled framework or isolate exceptions captured before termination.
  crash(4, 'CRASH', 'CRASH');

  /// Creates a [LogLevel] with its numeric [id], [label], and 5-char [paddedLabel].
  const LogLevel(this.id, this.label, this.paddedLabel);

  /// User-configurable minimum log thresholds in ascending severity order.
  static const List<LogLevel> configurableLevels = <LogLevel>[
    LogLevel.debug,
    LogLevel.info,
    LogLevel.warn,
    LogLevel.error,
  ];

  /// Numeric identifier used for compact configuration serialization.
  final int id;

  /// Canonical uppercase text token written to metadata and CLI filters.
  final String label;

  /// Fixed 5-character right-padded label written inside `[<LEVEL>]` brackets.
  final String paddedLabel;

  /// Resolves a configurable [LogLevel] from its persisted numeric [id].
  static LogLevel fromId(int id) {
    return switch (id) {
      0 => LogLevel.debug,
      1 => LogLevel.info,
      2 => LogLevel.warn,
      3 => LogLevel.error,
      _ => LogLevel.info,
    };
  }

  /// Parses a case-insensitive [LogLevel] token or returns `null` when unknown.
  static LogLevel? tryParse(String raw) {
    final normalized = raw.trim().toUpperCase();
    return switch (normalized) {
      'DEBUG' => LogLevel.debug,
      'INFO' => LogLevel.info,
      'WARN' || 'WARNING' => LogLevel.warn,
      'ERROR' => LogLevel.error,
      'CRASH' => LogLevel.crash,
      _ => null,
    };
  }
}

/// Architectural subsystem tags for structured diagnostic log entries.
enum LogTag {
  /// App startup, lifecycle state transitions, and global error boundaries.
  lifecycle('LIFECYCLE', 'LIFECYCLE'),

  /// TDF lexical scanning, parsing, serialization, and format migrations.
  tdf('TDF', 'TDF      '),

  /// Pure `TaskBoard` evaluations, task/label mutations, and queue changes.
  domain('DOMAIN', 'DOMAIN   '),

  /// Local/WebDAV synchronization pipeline stages and LWW board merges.
  sync('SYNC', 'SYNC     '),

  /// Local file I/O, WebDAV HTTP requests, and settings persistence.
  storage('STORAGE', 'STORAGE  '),

  /// User-initiated screen/dialog navigation and diagnostic actions.
  ui('UI', 'UI       ');

  /// Creates a [LogTag] with its canonical [label] and 9-char [paddedLabel].
  const LogTag(this.label, this.paddedLabel);

  /// Canonical uppercase subsystem token.
  final String label;

  /// Fixed 9-character right-padded label written inside `[<TAG>]` brackets.
  final String paddedLabel;

  /// Parses a case-insensitive [LogTag] token or returns `null` when unknown.
  static LogTag? tryParse(String raw) {
    final normalized = raw.trim().toUpperCase();
    return switch (normalized) {
      'LIFECYCLE' => LogTag.lifecycle,
      'TDF' => LogTag.tdf,
      'DOMAIN' => LogTag.domain,
      'SYNC' => LogTag.sync,
      'STORAGE' => LogTag.storage,
      'UI' => LogTag.ui,
      _ => null,
    };
  }
}

/// Immutable session and environment metadata written to the diagnostic log header.
@immutable
class LogMetadata {
  /// Creates a [LogMetadata] snapshot for the `@meta` header block.
  const LogMetadata({
    this.appVersion = 'unknown',
    this.platform = 'unknown',
    this.osVersion = 'unknown',
    this.locale = 'en',
    this.timeZone = 'system',
    this.workspaceId = 'default',
    this.workspaceName = 'Default',
    this.storageMode = 'local',
    this.logStorageMode = 'local',
  });

  /// Default metadata placeholder before provider initialization completes.
  static const LogMetadata empty = LogMetadata();

  /// Semantic application version and build identifier.
  final String appVersion;

  /// Active locale code (`en`, `de`).
  final String locale;

  /// Configured diagnostic log persistence target (`local`, `webdav`, `both`).
  final String logStorageMode;

  /// Operating system version description.
  final String osVersion;

  /// Target platform identifier (`linux`, `android`, `windows`).
  final String platform;

  /// Configured TDF task board storage mode (`local`, `webdav`, `both`).
  final String storageMode;

  /// Active time zone mode and UTC offset summary.
  final String timeZone;

  /// Stable identifier of the active workspace.
  final String workspaceId;

  /// Display name of the active workspace.
  final String workspaceName;

  /// Returns a copy of this metadata with the specified fields replaced.
  LogMetadata copyWith({
    String? appVersion,
    String? platform,
    String? osVersion,
    String? locale,
    String? timeZone,
    String? workspaceId,
    String? workspaceName,
    String? storageMode,
    String? logStorageMode,
  }) {
    return LogMetadata(
      appVersion: appVersion ?? this.appVersion,
      platform: platform ?? this.platform,
      osVersion: osVersion ?? this.osVersion,
      locale: locale ?? this.locale,
      timeZone: timeZone ?? this.timeZone,
      workspaceId: workspaceId ?? this.workspaceId,
      workspaceName: workspaceName ?? this.workspaceName,
      storageMode: storageMode ?? this.storageMode,
      logStorageMode: logStorageMode ?? this.logStorageMode,
    );
  }

  /// Formats the 5-line `@meta` header block placed at the top of a log file.
  List<String> toHeaderLines({
    required LogLevel minimumLevel,
    required DateTime sessionStartUtc,
  }) {
    final startIso = AppLogger.formatIsoUtcTimestamp(sessionStartUtc);
    final safeVersion = AppLogger.formatFieldValue(appVersion);
    final safePlatform = AppLogger.formatFieldValue(platform);
    final safeOs = AppLogger.formatFieldValue(osVersion, alwaysQuote: true);
    final safeLocale = AppLogger.formatFieldValue(locale);
    final safeTz = AppLogger.formatFieldValue(timeZone, alwaysQuote: true);
    final safeWsId = AppLogger.formatFieldValue(workspaceId);
    final safeWsName = AppLogger.formatFieldValue(
      workspaceName,
      alwaysQuote: true,
    );
    final safeStorage = AppLogger.formatFieldValue(storageMode);
    final safeLogStorage = AppLogger.formatFieldValue(logStorageMode);
    final workspaceMeta =
        '@meta workspace_id=$safeWsId workspace_name=$safeWsName '
        'storage_mode=$safeStorage log_storage=$safeLogStorage '
        'min_level=${minimumLevel.label}';
    return <String>[
      AppLogger.headerStartBanner,
      '@meta format=1 app_version=$safeVersion platform=$safePlatform os=$safeOs',
      '@meta locale=$safeLocale timezone=$safeTz session_start=$startIso',
      workspaceMeta,
      AppLogger.headerEndBanner,
    ];
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LogMetadata &&
        other.appVersion == appVersion &&
        other.platform == platform &&
        other.osVersion == osVersion &&
        other.locale == locale &&
        other.timeZone == timeZone &&
        other.workspaceId == workspaceId &&
        other.workspaceName == workspaceName &&
        other.storageMode == storageMode &&
        other.logStorageMode == logStorageMode;
  }

  @override
  int get hashCode => Object.hash(
    appVersion,
    platform,
    osVersion,
    locale,
    timeZone,
    workspaceId,
    workspaceName,
    storageMode,
    logStorageMode,
  );

  @override
  String toString() =>
      'LogMetadata(version: $appVersion, platform: $platform, '
      'workspace: $workspaceId, logStorage: $logStorageMode)';
}

/// Abstract synchronous file persistence sink for [AppLogger].
///
/// Implemented in `lib/repositories/local_file_repository.dart` so that
/// `lib/services/app_logger.dart` remains pure and free of `dart:io` imports
/// (`P-IO-ISOLATION`, `P-ACYCLIC-DAG`).
abstract interface class AppLogSink {
  /// Creates a const [AppLogSink].
  const AppLogSink();

  /// Resolves the default diagnostic log file path inside [baseDirectoryPath].
  String defaultLogFilePath({String? baseDirectoryPath, String? fileName});

  /// Deletes the diagnostic log file at [path] if it exists.
  void deleteLogFileSync(String path);

  /// Deletes all dated and legacy log files for [workspaceId] in [directoryPath].
  int deleteWorkspaceLogFilesSync({
    required String directoryPath,
    required String platform,
    required String workspaceId,
  });

  /// Prunes expired (`> maxRetainedDays`) and excess (`> maxRetainedFiles`) log files.
  int pruneExpiredLogFilesSync({
    required String directoryPath,
    required String platform,
    required String workspaceId,
    required DateTime utcNow,
    int maxRetainedDays = AppLogger.maxRetainedLogDays,
    int maxRetainedFiles = AppLogger.maxRetainedLogFiles,
  });

  /// Reads up to the trailing [maxBytes] of the log file at [path], or returns `''`.
  String readLogFileSync(String path, {required int maxBytes});

  /// Writes or appends [content] synchronously to the log file at [path], flushing to stable storage only when [flush] is `true`.
  void writeLogFileSync(
    String path,
    String content, {
    required bool append,
    bool flush = false,
  });
}

/// Opt-in structured diagnostic logger with credential sanitization and crash recovery.
///
/// When [isEnabled] is `false` (the default), all logging methods return
/// immediately without formatting strings, allocating memory, or touching disk.
final class AppLogger {
  const AppLogger._();

  /// Default legacy filename for the persistent diagnostic log.
  static const String defaultLogFileName = 'tiertask.log';

  /// Default maximum number of lines retained in memory and on disk.
  static const int defaultMaxLines = 5000;

  /// Closing delimiter line of the `@meta` diagnostic header block.
  static const String headerEndBanner = '===============================';

  /// Opening delimiter line of the `@meta` diagnostic header block.
  static const String headerStartBanner = '=== TIERTASK DIAGNOSTIC LOG ===';

  /// Maximum byte size (2 MiB) allowed for the persistent diagnostic log file.
  static const int maxFileBytes = 2097152;

  /// Maximum number of distinct dynamic secrets retained simultaneously for redaction.
  static const int maxRegisteredSecrets = 64;

  /// Maximum age in days for retained local workspace log files.
  static const int maxRetainedLogDays = 7;

  /// Maximum number of dated local log files retained per workspace.
  static const int maxRetainedLogFiles = 5;

  /// Trailing debounce duration before uploading updated logs to WebDAV.
  static const Duration webDavFlushDebounce = Duration(seconds: 5);

  static int _activeByteLength = 0;
  static String _activeUtcDateKey = '';
  static final RegExp _authHeaderPattern = RegExp(
    r'(authorization\s*[:=]\s*(?:basic|bearer)\s+)[^\s,;"]+',
    caseSensitive: false,
  );
  static String _baseDirectoryPath = '';
  static final RegExp _basicTokenPattern = RegExp(
    r'\b(basic\s+)[A-Za-z0-9+/=._~-]{6,}',
    caseSensitive: false,
  );
  static DateTime Function() _clock = DateTime.now;
  static bool _crashedInCurrentSession = false;
  static bool _enabled = false;
  static final RegExp _keyValueSecretPattern = RegExp(
    r'((?:password|passwd|secret|token|credentials?)\s*[:=]\s*)[^\s,&;"]+',
    caseSensitive: false,
  );
  static String _lastEvalSummarySignature = '';
  static final List<int> _lineByteLengths = <int>[];
  static final List<String> _lines = <String>[];
  static String _logFilePath = '';
  static int _maxLines = defaultMaxLines;
  static LogMetadata _metadata = LogMetadata.empty;
  static LogLevel _minimumLevel = LogLevel.info;
  static List<String> _orderedSecrets = const <String>[];
  static bool _persistToDisk = true;
  static final LinkedHashSet<String> _registeredSecrets =
      LinkedHashSet<String>();
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  static const Set<String> _secretFieldNames = <String>{
    'authorization',
    'credential',
    'credentials',
    'passwd',
    'password',
    'secret',
    'token',
  };
  static DateTime _sessionStartUtc = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );
  static AppLogSink? _sink;
  static final RegExp _urlUserInfoPattern = RegExp(
    r'(https?://[^/\s:@]+:)([^@\s/]+)(@)',
    caseSensitive: false,
  );

  /// Active dated log filename for the current workspace and UTC date.
  static String get activeLogFileName {
    if (_logFilePath.isNotEmpty) {
      final slashIndex = _logFilePath.lastIndexOf('/');
      final backslashIndex = _logFilePath.lastIndexOf(r'\');
      final splitIndex = slashIndex > backslashIndex
          ? slashIndex
          : backslashIndex;
      if (splitIndex >= 0 && splitIndex + 1 < _logFilePath.length) {
        return _logFilePath.substring(splitIndex + 1);
      }
      return _logFilePath;
    }
    return formatLogFileName(
      utcNow: _clock().toUtc(),
      platform: _metadata.platform,
      workspaceId: _metadata.workspaceId,
    );
  }

  /// Concatenated multi-line diagnostic log text for clipboard export or WebDAV upload.
  static String get fullLogText => _lines.join('\n');

  /// Whether an unhandled crash was recorded during the current process session.
  static bool get hasCrashedInSession => _crashedInCurrentSession;

  /// Whether diagnostic logging is currently enabled by the user.
  static bool get isEnabled => _enabled;

  /// Unmodifiable snapshot of all currently buffered diagnostic log lines.
  static List<String> get lines => UnmodifiableListView<String>(_lines);

  /// Active file system path used for `tiertask_<date>_<platform>_<workspace>.log`.
  static String get logFilePath => _logFilePath;

  /// Current session and workspace metadata written to the `@meta` header block.
  static LogMetadata get metadata => _metadata;

  /// Active minimum severity threshold for non-crash log entries.
  static LogLevel get minimumLevel => _minimumLevel;

  /// Notifier incremented whenever buffered log lines are added, pruned, or cleared.
  static ValueListenable<int> get revision => _revision;

  /// Overrides the clock function used for log entry timestamps and dated filenames.
  static set clock(DateTime Function() value) {
    _clock = value;
  }

  /// Clears all in-memory log lines and truncates or removes local workspace logs.
  static void clear() {
    _clearBuffer();
    _crashedInCurrentSession = false;
    _lastEvalSummarySignature = '';
    final sink = _sink;
    if (_enabled && sink != null) {
      if (_baseDirectoryPath.isNotEmpty) {
        sink.deleteWorkspaceLogFilesSync(
          directoryPath: _baseDirectoryPath,
          platform: _metadata.platform,
          workspaceId: _metadata.workspaceId,
        );
      }
      if (_persistToDisk && _logFilePath.isNotEmpty) {
        sink.writeLogFileSync(_logFilePath, '', append: false);
      }
    }
    _revision.value++;
  }

  /// Clears all dynamically registered secret strings retained for log redaction.
  static void clearSecrets() {
    _registeredSecrets.clear();
    _orderedSecrets = const <String>[];
  }

  /// Records an unhandled framework or isolate crash and flushes it synchronously.
  static void crash(Object error, StackTrace stackTrace) {
    if (!_enabled) return;
    _crashedInCurrentSession = true;
    final nowUtc = _clock().toUtc();
    final timestamp = formatIsoUtcTimestamp(nowUtc);
    final sanitizedError = formatFieldValue(
      error.toString(),
      alwaysQuote: true,
    );
    final sanitizedTrace = sanitize(stackTrace.toString()).trimRight();
    final crashLine =
        '$timestamp [${LogLevel.crash.paddedLabel}] '
        '[${LogTag.lifecycle.paddedLabel}] '
        'crash.unhandled | error=$sanitizedError';
    final batch = <String>[crashLine];
    if (sanitizedTrace.isNotEmpty) {
      var frameIndex = 0;
      for (final rawLine in sanitizedTrace.split('\n')) {
        final trimmed = rawLine.trimRight();
        if (trimmed.isNotEmpty) {
          final quotedFrame = _quoteSanitizedValue(
            _collapseControlChars(trimmed),
            alwaysQuote: true,
          );
          batch.add(
            '$timestamp [${LogLevel.crash.paddedLabel}] '
            '[${LogTag.lifecycle.paddedLabel}] '
            'crash.stack | frame=$frameIndex line=$quotedFrame',
          );
          frameIndex++;
        }
      }
    }
    _appendLines(batch, nowUtc: nowUtc, forceFullWrite: true, flush: true);
  }

  /// Logs a `DEBUG` message under [tag] when [shouldLog] permits `LogLevel.debug`.
  static void debug(LogTag tag, String message) {
    _log(LogLevel.debug, tag, message);
  }

  /// Deduplicated `DEBUG` logger for `eval.summary` to avoid flooding on UI rebuilds.
  static bool deduplicateEvalSummary(String signature) {
    if (_lastEvalSummarySignature == signature) {
      return false;
    }
    _lastEvalSummarySignature = signature;
    return true;
  }

  /// Logs an `ERROR` message and optional [error] / [stackTrace] under [tag].
  static void error(
    LogTag tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!shouldLog(LogLevel.error)) return;
    final buffer = StringBuffer(_collapseControlChars(sanitize(message)));
    if (error != null) {
      buffer
        ..write(' | error=')
        ..write(formatFieldValue(error.toString(), alwaysQuote: true));
    }
    if (stackTrace != null) {
      final firstFrame = _firstStackFrame(stackTrace);
      if (firstFrame.isNotEmpty) {
        buffer
          ..write(' trace=')
          ..write(formatFieldValue(firstFrame, alwaysQuote: true));
      }
    }
    _appendFormattedLine(LogLevel.error, tag, buffer.toString());
  }

  /// Logs a structured `<event> | <key=value ...>` entry at [level] and [tag].
  static void event(
    LogLevel level,
    LogTag tag,
    String event, {
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!shouldLog(level)) return;
    _appendFormattedLine(
      level,
      tag,
      _formatEventPayload(
        event,
        fields: fields,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  /// Logs multiple structured `<event> | <key=value ...>` [entries] at [level] and [tag] in a single buffered write.
  static void eventBatch(
    LogLevel level,
    LogTag tag,
    Iterable<({String event, Map<String, Object?> fields})> entries,
  ) {
    if (!shouldLog(level)) return;
    final nowUtc = _clock().toUtc();
    final timestamp = formatIsoUtcTimestamp(nowUtc);
    final prefix = '$timestamp [${level.paddedLabel}] [${tag.paddedLabel}] ';
    final batch = <String>[];
    for (final entry in entries) {
      final payload = _formatEventPayload(entry.event, fields: entry.fields);
      batch.add('$prefix$payload');
    }
    _appendLines(batch, nowUtc: nowUtc);
  }

  /// Formats a structured field [value] with secret sanitization and quoting.
  static String formatFieldValue(Object? value, {bool alwaysQuote = false}) {
    if (value == null) return '""';
    if (value is bool || value is num) return value.toString();
    final sanitized = _collapseControlChars(sanitize(value.toString()));
    return _quoteSanitizedValue(sanitized, alwaysQuote: alwaysQuote);
  }

  /// Formats [timestamp] as canonical UTC ISO-8601 (`YYYY-MM-DDTHH:MM:SS.mmmZ`).
  static String formatIsoUtcTimestamp(DateTime timestamp) {
    final utc = timestamp.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final h = utc.hour.toString().padLeft(2, '0');
    final min = utc.minute.toString().padLeft(2, '0');
    final s = utc.second.toString().padLeft(2, '0');
    final ms = utc.millisecond.toString().padLeft(3, '0');
    return '$y-$m-${d}T$h:$min:$s.${ms}Z';
  }

  /// Builds the canonical dated log filename `tiertask_<YYYY-MM-DD>_<platform>_<workspaceId>.log`.
  static String formatLogFileName({
    required DateTime utcNow,
    required String platform,
    required String workspaceId,
  }) {
    final utc = utcNow.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final safePlatform = _sanitizeSlugToken(platform, fallback: 'unknown');
    final safeWorkspace = _sanitizeSlugToken(workspaceId, fallback: 'default');
    return 'tiertask_$y-$m-${d}_${safePlatform}_$safeWorkspace.log';
  }

  /// Handles Flutter [AppLifecycleState] transitions while preserving session logs.
  static void handleAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        event(
          LogLevel.info,
          LogTag.lifecycle,
          'lifecycle.state',
          fields: <String, Object?>{'state': state.name},
        );
      case AppLifecycleState.detached:
        event(
          LogLevel.info,
          LogTag.lifecycle,
          'session.exit',
          fields: <String, Object?>{
            'state': 'detached',
            'crashed': _crashedInCurrentSession,
          },
        );
        _writeFullFile(flush: true);
    }
  }

  /// Logs an `INFO` message under [tag] when [shouldLog] permits `LogLevel.info`.
  static void info(LogTag tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  /// Returns `true` when [line] satisfies the viewer [minimumLevel] and optional [tags] filter.
  ///
  /// When [tags] is `null` or contains every [LogTag], all subsystems and
  /// header lines (at [LogLevel.debug]) match. An empty [tags] set matches no lines.
  static bool matchesFilter(
    String line, {
    required LogLevel minimumLevel,
    Set<LogTag>? tags,
  }) {
    final matchesAllTags = tags == null || tags.length == LogTag.values.length;
    if (line.startsWith('===') || line.startsWith('@meta ')) {
      return matchesAllTags && minimumLevel == LogLevel.debug;
    }
    final parsedLevel = _extractLineLevel(line);
    if (parsedLevel != null &&
        parsedLevel != LogLevel.crash &&
        parsedLevel.index < minimumLevel.index) {
      return false;
    }
    if (tags == null || tags.length == LogTag.values.length) {
      return true;
    }
    if (tags.isEmpty) {
      return false;
    }
    final parsedTag = _extractLineTag(line);
    return parsedTag != null && tags.contains(parsedTag);
  }

  /// Registers a dynamic secret [secret] to redact from all future log lines, retaining up to [maxRegisteredSecrets] entries.
  static void registerSecret(String? secret) {
    if (secret == null || secret.isEmpty) return;
    if (_registeredSecrets.remove(secret)) {
      _registeredSecrets.add(secret);
      return;
    }
    while (_registeredSecrets.length >= maxRegisteredSecrets) {
      _registeredSecrets.remove(_registeredSecrets.first);
    }
    _registeredSecrets.add(secret);
    _orderedSecrets = List<String>.unmodifiable(
      _registeredSecrets.toList()..sort((a, b) => b.length.compareTo(a.length)),
    );
  }

  /// Resets all static logger state for isolated unit and widget tests.
  @visibleForTesting
  static void resetForTesting({DateTime Function()? clock, AppLogSink? sink}) {
    _enabled = false;
    _crashedInCurrentSession = false;
    _lastEvalSummarySignature = '';
    _clearBuffer();
    _activeUtcDateKey = '';
    _logFilePath = '';
    _baseDirectoryPath = '';
    clearSecrets();
    _minimumLevel = LogLevel.info;
    _metadata = LogMetadata.empty;
    _persistToDisk = true;
    _maxLines = defaultMaxLines;
    _clock = clock ?? DateTime.now;
    _sink = sink;
    _revision.value = 0;
  }

  /// Redacts passwords, Bearer/Basic tokens, and embedded URL userinfo from [input] using a zero-allocation fast path when clean.
  static String sanitize(String input) {
    if (input.isEmpty) return input;
    var sanitized = input;
    if (_orderedSecrets.isNotEmpty) {
      for (final secret in _orderedSecrets) {
        if (sanitized.contains(secret)) {
          sanitized = sanitized.replaceAll(secret, '[REDACTED]');
        }
      }
    }
    final markers = _scanSanitizeMarkers(sanitized);
    if (!markers.hasColonOrEquals && !markers.hasWhitespace) {
      return sanitized;
    }
    if (markers.hasColonOrEquals &&
        markers.hasWhitespace &&
        sanitized.length >= 21) {
      sanitized = sanitized.replaceAllMapped(
        _authHeaderPattern,
        (match) => '${match.group(1)}[REDACTED]',
      );
    }
    if (markers.hasWhitespace && sanitized.length >= 12) {
      sanitized = sanitized.replaceAllMapped(
        _basicTokenPattern,
        (match) => '${match.group(1)}[REDACTED]',
      );
    }
    if (markers.hasAt && markers.hasColonOrEquals && sanitized.length >= 11) {
      sanitized = sanitized.replaceAllMapped(
        _urlUserInfoPattern,
        (match) => '${match.group(1)}[REDACTED]${match.group(3)}',
      );
    }
    if (markers.hasColonOrEquals && sanitized.length >= 7) {
      sanitized = sanitized.replaceAllMapped(
        _keyValueSecretPattern,
        (match) => '${match.group(1)}[REDACTED]',
      );
    }
    return sanitized;
  }

  /// Enables or disables diagnostic logging and synchronizes on-disk log state.
  static void setEnabled(
    bool enabled, {
    AppLogSink? sink,
    String? logFilePath,
    String? baseDirectoryPath,
    String? secretToRedact,
    LogLevel? minimumLevel,
    LogMetadata? metadata,
    bool? persistToDisk,
    int maxLines = defaultMaxLines,
  }) {
    final previousMinimumLevel = _minimumLevel;
    final previousMetadata = _metadata;
    final previousPersistToDisk = _persistToDisk;
    final previousBaseDirectoryPath = _baseDirectoryPath;
    if (sink != null) {
      _sink = sink;
    }
    registerSecret(secretToRedact);
    if (minimumLevel != null) {
      _minimumLevel = minimumLevel;
    }
    if (metadata != null) {
      _metadata = metadata;
    }
    if (persistToDisk != null) {
      _persistToDisk = persistToDisk;
    }
    if (baseDirectoryPath != null) {
      _baseDirectoryPath = baseDirectoryPath;
    }
    _maxLines = maxLines > 10 ? maxLines : 10;

    final resolvedPath = _resolvePath(logFilePath);
    if (!enabled) {
      _disableAndDeleteLogs(resolvedPath);
      return;
    }

    final wasEnabled = _enabled;
    final pathChanged = resolvedPath.isNotEmpty && resolvedPath != _logFilePath;
    _logFilePath = resolvedPath;
    if (_baseDirectoryPath.isEmpty && _logFilePath.isNotEmpty) {
      _baseDirectoryPath = _extractParentDirectory(_logFilePath);
    }
    _enabled = true;

    if (!wasEnabled || pathChanged) {
      _crashedInCurrentSession = false;
      _lastEvalSummarySignature = '';
      _sessionStartUtc = _clock().toUtc();
      _applyLocalStoragePolicy();
      _initializeSessionFile();
    } else if (previousMinimumLevel != _minimumLevel ||
        previousMetadata != _metadata ||
        previousPersistToDisk != _persistToDisk ||
        previousBaseDirectoryPath != _baseDirectoryPath) {
      if (previousPersistToDisk != _persistToDisk) {
        _applyLocalStoragePolicy();
      }
      _refreshHeaderLinesInPlace();
    }
  }

  /// Updates the active minimum severity [level] and refreshes the `@meta` header.
  static void setMinimumLevel(LogLevel level) {
    if (_minimumLevel == level) return;
    _minimumLevel = level;
    if (_enabled) {
      _refreshHeaderLinesInPlace();
    }
  }

  /// Registers [secret] for redaction across all future log lines via [registerSecret].
  static void setSecretToRedact(String? secret) {
    registerSecret(secret);
  }

  /// Returns `true` when [ isEnabled ] is `true` and [level] meets [minimumLevel].
  static bool shouldLog(LogLevel level) {
    if (!_enabled) return false;
    if (level == LogLevel.crash) return true;
    return level.index >= _minimumLevel.index;
  }

  /// Updates session [metadata], [minimumLevel], and [persistToDisk] state in place.
  static void updateMetadata(
    LogMetadata metadata, {
    LogLevel? minimumLevel,
    bool? persistToDisk,
    String? logFilePath,
    String? baseDirectoryPath,
  }) {
    _metadata = metadata;
    if (minimumLevel != null) {
      _minimumLevel = minimumLevel;
    }
    final previousPersist = _persistToDisk;
    if (persistToDisk != null) {
      _persistToDisk = persistToDisk;
    }
    if (baseDirectoryPath != null) {
      _baseDirectoryPath = baseDirectoryPath;
    }
    if (!_enabled) return;

    final nextPath = logFilePath != null
        ? _resolvePath(logFilePath)
        : _logFilePath;
    if (nextPath.isNotEmpty && nextPath != _logFilePath) {
      _logFilePath = nextPath;
      _applyLocalStoragePolicy();
      _initializeSessionFile();
      return;
    }
    if (previousPersist != _persistToDisk) {
      _applyLocalStoragePolicy();
    }
    _refreshHeaderLinesInPlace();
  }

  /// Logs a `WARN` message under [tag] when [shouldLog] permits `LogLevel.warn`.
  static void warn(LogTag tag, String message) {
    _log(LogLevel.warn, tag, message);
  }

  /// Formats a pre-sanitized [sanitizedPayload] with timestamp, [level], and [tag] and appends it to the active log buffer.
  static void _appendFormattedLine(
    LogLevel level,
    LogTag tag,
    String sanitizedPayload,
  ) {
    final nowUtc = _clock().toUtc();
    final timestamp = formatIsoUtcTimestamp(nowUtc);
    final formatted =
        '$timestamp [${level.paddedLabel}] [${tag.paddedLabel}] '
        '$sanitizedPayload';
    _appendLines(<String>[formatted], nowUtc: nowUtc);
  }

  /// Appends [newLines] to the in-memory ring buffer, rolling across UTC midnight and enforcing line and byte limits.
  static void _appendLines(
    List<String> newLines, {
    required DateTime nowUtc,
    bool forceFullWrite = false,
    bool flush = false,
  }) {
    if (newLines.isEmpty) return;
    var needsFullWrite = forceFullWrite;
    if (_rollOverUtcDayIfNeeded(nowUtc)) {
      needsFullWrite = true;
    }
    for (final line in newLines) {
      _pushLine(line);
    }
    final trimmed = _trimToLimitsIfNeeded();
    final sink = _sink;
    final path = _logFilePath;
    if (_persistToDisk && sink != null && path.isNotEmpty) {
      if (trimmed || needsFullWrite) {
        _writeFullFile(flush: flush);
      } else {
        final chunk = '${newLines.join('\n')}\n';
        sink.writeLogFileSync(path, chunk, append: true, flush: flush);
      }
    }
    _revision.value++;
  }

  /// Applies local retention pruning or local file removal based on [_persistToDisk].
  static void _applyLocalStoragePolicy() {
    final sink = _sink;
    if (sink == null || _baseDirectoryPath.isEmpty) return;
    if (!_persistToDisk) {
      sink.deleteWorkspaceLogFilesSync(
        directoryPath: _baseDirectoryPath,
        platform: _metadata.platform,
        workspaceId: _metadata.workspaceId,
      );
      if (_logFilePath.isNotEmpty) {
        sink.deleteLogFileSync(_logFilePath);
      }
      return;
    }
    sink.pruneExpiredLogFilesSync(
      directoryPath: _baseDirectoryPath,
      platform: _metadata.platform,
      workspaceId: _metadata.workspaceId,
      utcNow: _clock().toUtc(),
    );
  }

  /// Empties the in-memory log buffer and resets its tracked UTF-8 byte length.
  static void _clearBuffer() {
    _lines.clear();
    _lineByteLengths.clear();
    _activeByteLength = 0;
  }

  /// Replaces CR, LF, and ASCII control characters with single spaces, returning [input] unchanged when clean.
  static String _collapseControlChars(String input) {
    for (var i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code < 0x20 || code == 0x7F) {
        return _collapseControlCharsSlow(input, i);
      }
    }
    return input;
  }

  /// Copies [input] from [firstControlIndex] replacing ASCII control characters with single spaces.
  static String _collapseControlCharsSlow(String input, int firstControlIndex) {
    final buffer = StringBuffer(input.substring(0, firstControlIndex));
    for (var i = firstControlIndex; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code < 0x20 || code == 0x7F) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// Disables logging and removes both the active and historical workspace log files.
  static void _disableAndDeleteLogs(String resolvedPath) {
    _enabled = false;
    _crashedInCurrentSession = false;
    _lastEvalSummarySignature = '';
    _activeUtcDateKey = '';
    _clearBuffer();
    final sink = _sink;
    if (sink != null) {
      if (resolvedPath.isNotEmpty) {
        sink.deleteLogFileSync(resolvedPath);
      }
      if (_baseDirectoryPath.isNotEmpty) {
        sink.deleteWorkspaceLogFilesSync(
          directoryPath: _baseDirectoryPath,
          platform: _metadata.platform,
          workspaceId: _metadata.workspaceId,
        );
      }
    }
    _logFilePath = resolvedPath;
    _revision.value++;
  }

  /// Drops oldest non-header lines when protected entries alone still exceed [maxFileBytes].
  static int _dropOverflowNonHeaderBytes(
    List<String> lines,
    List<int> lengths,
    int initialBytes,
  ) {
    final retainedLines = <String>[];
    final retainedLengths = <int>[];
    var remainingBytes = initialBytes;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final byteLength = lengths[i];
      if (remainingBytes > maxFileBytes && !_isHeaderLine(line)) {
        remainingBytes -= byteLength;
      } else {
        retainedLines.add(line);
        retainedLengths.add(byteLength);
      }
    }
    lines
      ..clear()
      ..addAll(retainedLines);
    lengths
      ..clear()
      ..addAll(retainedLengths);
    return remainingBytes;
  }

  /// Extracts the [LogLevel] from a formatted log [line], or returns `null`.
  static LogLevel? _extractLineLevel(String line) {
    if (line.length < 32 || line.codeUnitAt(25) != 0x5B) {
      return null;
    }
    final rawLevel = line.substring(26, 31).trimRight();
    return LogLevel.tryParse(rawLevel);
  }

  /// Extracts the [LogTag] from a formatted log [line], or returns `null`.
  static LogTag? _extractLineTag(String line) {
    if (line.length < 44 || line.codeUnitAt(33) != 0x5B) {
      return null;
    }
    final rawTag = line.substring(34, 43).trimRight();
    return LogTag.tryParse(rawTag);
  }

  /// Extracts the parent directory path from [filePath], or returns `''`.
  static String _extractParentDirectory(String filePath) {
    final slashIndex = filePath.lastIndexOf('/');
    final backslashIndex = filePath.lastIndexOf(r'\');
    final splitIndex = slashIndex > backslashIndex
        ? slashIndex
        : backslashIndex;
    if (splitIndex <= 0) return '';
    return filePath.substring(0, splitIndex);
  }

  /// Extracts the first non-empty stack frame from [stackTrace].
  static String _firstStackFrame(StackTrace stackTrace) {
    for (final line in stackTrace.toString().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  /// Formats a structured `<event> | <key=value ...>` message body with single-pass secret sanitization.
  static String _formatEventPayload(
    String event, {
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final sanitizedEvent = _collapseControlChars(sanitize(event));
    final buffer = StringBuffer(sanitizedEvent)..write(' |');
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value != null) {
        final safeKey = _collapseControlChars(sanitize(entry.key));
        final safeValue = _isSecretFieldName(safeKey)
            ? '[REDACTED]'
            : formatFieldValue(value);
        buffer
          ..write(' ')
          ..write(safeKey)
          ..write('=')
          ..write(safeValue);
      }
    }
    if (error != null) {
      buffer
        ..write(' error=')
        ..write(formatFieldValue(error.toString(), alwaysQuote: true));
    }
    if (stackTrace != null) {
      final firstFrame = _firstStackFrame(stackTrace);
      if (firstFrame.isNotEmpty) {
        buffer
          ..write(' trace=')
          ..write(formatFieldValue(firstFrame, alwaysQuote: true));
      }
    }
    return buffer.toString();
  }

  /// Formats the UTC calendar date of [utc] as `YYYY-MM-DD`.
  static String _formatUtcDateKey(DateTime utc) {
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Returns `true` if [previousBodyLines] ended without a clean `crashed=false` exit.
  static bool _hadUncleanPreviousExit(List<String> previousBodyLines) {
    for (var i = previousBodyLines.length - 1; i >= 0; i--) {
      final line = previousBodyLines[i].trim();
      if (line.isNotEmpty) {
        return !line.contains('session.exit | state=detached crashed=false');
      }
    }
    return false;
  }

  /// Initializes the session log buffer, preserving prior entries and detecting crashes.
  static void _initializeSessionFile() {
    _clearBuffer();
    final path = _logFilePath;
    final nowUtc = _sessionStartUtc;
    _activeUtcDateKey = _formatUtcDateKey(nowUtc);
    final nowIso = formatIsoUtcTimestamp(nowUtc);

    final headerLines = _metadata.toHeaderLines(
      minimumLevel: _minimumLevel,
      sessionStartUtc: nowUtc,
    );
    final previousBodyLines = _readExistingBodyLines(path);

    for (final line in headerLines) {
      _pushLine(line);
    }
    for (final line in previousBodyLines) {
      _pushLine(line);
    }

    if (_hadUncleanPreviousExit(previousBodyLines)) {
      _pushLine(
        '=== RECOVERED UNCLEAN EXIT / CRASH LOG ABOVE | '
        'NEW SESSION START $nowIso ===',
      );
      _pushLine(
        '$nowIso [${LogLevel.warn.paddedLabel}] '
        '[${LogTag.lifecycle.paddedLabel}] '
        'session.recover | reason=unclean_exit_or_crash',
      );
    }

    _pushLine(
      '$nowIso [${LogLevel.info.paddedLabel}] '
      '[${LogTag.lifecycle.paddedLabel}] '
      'session.start | '
      'version=${formatFieldValue(_metadata.appVersion)} '
      'platform=${formatFieldValue(_metadata.platform)} '
      'workspace=${formatFieldValue(_metadata.workspaceId)} '
      'level=${_minimumLevel.label} '
      'storage=${formatFieldValue(_metadata.logStorageMode)}',
    );
    _trimToLimitsIfNeeded();
    _writeFullFile();
    _revision.value++;
  }

  /// Returns `true` when [codeUnit] is an ASCII decimal digit (`0-9`).
  static bool _isAsciiDigit(int codeUnit) =>
      codeUnit >= 0x30 && codeUnit <= 0x39;

  /// Returns `true` when [line] is part of the 5-line `@meta` header block.
  static bool _isHeaderLine(String line) {
    return line == headerStartBanner ||
        line == headerEndBanner ||
        line.startsWith('@meta ');
  }

  /// Returns `true` when [line] must be preserved across 20% rolling line pruning.
  static bool _isProtectedLine(String line) {
    return _isHeaderLine(line) ||
        line.contains('[CRASH]') ||
        line.contains('RECOVERED UNCLEAN EXIT / CRASH LOG ABOVE');
  }

  /// Returns `true` when structured field [key] names a secret credential field.
  static bool _isSecretFieldName(String key) =>
      _secretFieldNames.contains(key.toLowerCase());

  /// Formats and records a single log line when [shouldLog] permits [level].
  static void _log(LogLevel level, LogTag tag, String message) {
    if (!shouldLog(level)) return;
    final sanitizedMessage = _collapseControlChars(sanitize(message));
    _appendFormattedLine(level, tag, sanitizedMessage);
  }

  /// Returns `true` when [value] contains spaces, quotes, or `=` requiring quotes.
  static bool _needsQuotes(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit <= 0x20 || unit == 0x22 || unit == 0x3D || unit == 0x7C) {
        return true;
      }
    }
    return false;
  }

  /// Appends a single [line] to [_lines] and updates tracked UTF-8 byte length.
  static void _pushLine(String line) {
    final byteLength = _utf8LineByteLength(line);
    _lines.add(line);
    _lineByteLengths.add(byteLength);
    _activeByteLength += byteLength;
  }

  /// Escapes and quotes an already-sanitized [sanitized] string when required.
  static String _quoteSanitizedValue(
    String sanitized, {
    required bool alwaysQuote,
  }) {
    if (!alwaysQuote && sanitized.isNotEmpty && !_needsQuotes(sanitized)) {
      return sanitized;
    }
    final escaped = sanitized.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }

  /// Reads existing non-header lines from the persisted log file at [path], or returns an empty list.
  static List<String> _readExistingBodyLines(String path) {
    final sink = _sink;
    if (!_persistToDisk || sink == null || path.isEmpty) {
      return const <String>[];
    }
    final existing = sink.readLogFileSync(path, maxBytes: maxFileBytes);
    if (existing.trim().isEmpty) {
      return const <String>[];
    }
    return <String>[
      for (final line in existing.split('\n'))
        if (line.isNotEmpty && !_isHeaderLine(line)) line,
    ];
  }

  /// Replaces the 5-line `@meta` header at the top of [_lines] and rewrites the file.
  static void _refreshHeaderLinesInPlace() {
    if (_lines.isEmpty) return;
    final updatedHeader = _metadata.toHeaderLines(
      minimumLevel: _minimumLevel,
      sessionStartUtc: _sessionStartUtc,
    );
    var bodyStartIndex = 0;
    while (bodyStartIndex < _lines.length &&
        _isHeaderLine(_lines[bodyStartIndex])) {
      bodyStartIndex++;
    }
    final body = _lines.sublist(bodyStartIndex);
    _replaceBuffer(<String>[...updatedHeader, ...body]);
    _trimToLimitsIfNeeded();
    _writeFullFile();
    _revision.value++;
  }

  /// Replaces [_lines], [_lineByteLengths], and [_activeByteLength] with [nextLines].
  static void _replaceBuffer(List<String> nextLines) {
    _clearBuffer();
    for (final line in nextLines) {
      _pushLine(line);
    }
  }

  /// Resolves the target log file path from [explicitPath] or the configured sink.
  static String _resolvePath(String? explicitPath) {
    if (explicitPath != null && explicitPath.isNotEmpty) {
      return explicitPath;
    }
    if (_logFilePath.isNotEmpty) {
      return _logFilePath;
    }
    final sink = _sink;
    if (sink == null) {
      return '';
    }
    final fileName = formatLogFileName(
      utcNow: _clock().toUtc(),
      platform: _metadata.platform,
      workspaceId: _metadata.workspaceId,
    );
    return sink.defaultLogFilePath(
      baseDirectoryPath: _baseDirectoryPath.isEmpty ? null : _baseDirectoryPath,
      fileName: fileName,
    );
  }

  /// Replaces the `YYYY-MM-DD` date segment inside a dated `tiertask_<YYYY-MM-DD>_*.log` [currentPath], or returns `null` for non-dated paths.
  static String? _rollDatedLogPath(String currentPath, String nextDateKey) {
    final slashIndex = currentPath.lastIndexOf('/');
    final backslashIndex = currentPath.lastIndexOf(r'\');
    final splitIndex = slashIndex > backslashIndex
        ? slashIndex
        : backslashIndex;
    final prefix = splitIndex >= 0
        ? currentPath.substring(0, splitIndex + 1)
        : '';
    final fileName = splitIndex >= 0
        ? currentPath.substring(splitIndex + 1)
        : currentPath;
    if (!fileName.startsWith('tiertask_') ||
        !fileName.endsWith('.log') ||
        fileName.length < 24) {
      return null;
    }
    if (fileName.codeUnitAt(13) != 0x2D ||
        fileName.codeUnitAt(16) != 0x2D ||
        fileName.codeUnitAt(19) != 0x5F) {
      return null;
    }
    const digitPositions = <int>[9, 10, 11, 12, 14, 15, 17, 18];
    for (final index in digitPositions) {
      if (!_isAsciiDigit(fileName.codeUnitAt(index))) {
        return null;
      }
    }
    return '${prefix}tiertask_$nextDateKey${fileName.substring(19)}';
  }

  /// Rolls dated log file paths and buffers cleanly when [nowUtc] crosses a UTC calendar day boundary.
  static bool _rollOverUtcDayIfNeeded(DateTime nowUtc) {
    final nextDateKey = _formatUtcDateKey(nowUtc);
    if (_activeUtcDateKey.isEmpty) {
      _activeUtcDateKey = nextDateKey;
      return false;
    }
    if (_activeUtcDateKey == nextDateKey) {
      return false;
    }
    _activeUtcDateKey = nextDateKey;
    if (_logFilePath.isEmpty) {
      return false;
    }
    final rolledPath = _rollDatedLogPath(_logFilePath, nextDateKey);
    if (rolledPath == null || rolledPath == _logFilePath) {
      return false;
    }
    _logFilePath = rolledPath;
    _sessionStartUtc = nowUtc;
    _applyLocalStoragePolicy();

    final headerLines = _metadata.toHeaderLines(
      minimumLevel: _minimumLevel,
      sessionStartUtc: nowUtc,
    );
    final existingBodyLines = _readExistingBodyLines(rolledPath);
    _replaceBuffer(<String>[...headerLines, ...existingBodyLines]);
    return true;
  }

  /// Sanitizes a platform or workspace identifier into a safe filename slug token.
  static String _sanitizeSlugToken(String raw, {required String fallback}) {
    final lower = raw.trim().toLowerCase();
    if (lower.isEmpty) return fallback;
    final buffer = StringBuffer();
    var lastWasUnderscore = false;
    for (var i = 0; i < lower.length; i++) {
      final code = lower.codeUnitAt(i);
      final isAlphaNum =
          (code >= 0x61 && code <= 0x7A) ||
          (code >= 0x30 && code <= 0x39) ||
          code == 0x2D;
      if (isAlphaNum) {
        buffer.writeCharCode(code);
        lastWasUnderscore = false;
      } else if (!lastWasUnderscore && buffer.isNotEmpty) {
        buffer.write('_');
        lastWasUnderscore = true;
      }
    }
    var result = buffer.toString();
    while (result.endsWith('_')) {
      result = result.substring(0, result.length - 1);
    }
    return result.isEmpty ? fallback : result;
  }

  /// Scans [input] in a single pass for character markers required by secret-redaction patterns.
  static ({bool hasAt, bool hasColonOrEquals, bool hasWhitespace})
  _scanSanitizeMarkers(String input) {
    var hasAt = false;
    var hasColonOrEquals = false;
    var hasWhitespace = false;
    for (var i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code == 0x3A || code == 0x3D) {
        hasColonOrEquals = true;
      } else if (code == 0x40) {
        hasAt = true;
      } else if (code <= 0x20 ||
          code == 0x85 ||
          code == 0xA0 ||
          code > 0x1000) {
        hasWhitespace = true;
      }
      if (hasAt && hasColonOrEquals && hasWhitespace) {
        break;
      }
    }
    return (
      hasAt: hasAt,
      hasColonOrEquals: hasColonOrEquals,
      hasWhitespace: hasWhitespace,
    );
  }

  /// Trims the oldest non-protected lines until [_activeByteLength] fits within [maxFileBytes].
  static void _trimLinesByBytes() {
    final overflowBytes = _activeByteLength - maxFileBytes;
    final twentyPercentBytes = (maxFileBytes * 0.2).ceil();
    final targetDropBytes = overflowBytes + twentyPercentBytes;

    final retainedLines = <String>[];
    final retainedLengths = <int>[];
    var droppedBytes = 0;
    var totalBytes = 0;

    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final byteLength = _lineByteLengths[i];
      if (droppedBytes < targetDropBytes && !_isProtectedLine(line)) {
        droppedBytes += byteLength;
      } else {
        retainedLines.add(line);
        retainedLengths.add(byteLength);
        totalBytes += byteLength;
      }
    }

    if (totalBytes > maxFileBytes) {
      totalBytes = _dropOverflowNonHeaderBytes(
        retainedLines,
        retainedLengths,
        totalBytes,
      );
    }

    _lines
      ..clear()
      ..addAll(retainedLines);
    _lineByteLengths
      ..clear()
      ..addAll(retainedLengths);
    _activeByteLength = totalBytes;
  }

  /// Trims the oldest 20% of non-protected entries when [_lines] exceeds [_maxLines].
  static void _trimLinesByCount() {
    final overflow = _lines.length - _maxLines;
    final twentyPercent = (_maxLines * 0.2).ceil();
    final targetDrop = overflow + (twentyPercent > 1 ? twentyPercent : 1);

    final retainedLines = <String>[];
    final retainedLengths = <int>[];
    var dropped = 0;
    var totalBytes = 0;
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final byteLength = _lineByteLengths[i];
      if (dropped < targetDrop && !_isProtectedLine(line)) {
        dropped++;
      } else {
        retainedLines.add(line);
        retainedLengths.add(byteLength);
        totalBytes += byteLength;
      }
    }
    if (retainedLines.length > _maxLines) {
      final start = retainedLines.length - _maxLines;
      final tailLines = retainedLines.sublist(start);
      final tailLengths = retainedLengths.sublist(start);
      retainedLines
        ..clear()
        ..addAll(tailLines);
      retainedLengths
        ..clear()
        ..addAll(tailLengths);
      totalBytes = 0;
      for (final byteLength in retainedLengths) {
        totalBytes += byteLength;
      }
    }
    _lines
      ..clear()
      ..addAll(retainedLines);
    _lineByteLengths
      ..clear()
      ..addAll(retainedLengths);
    _activeByteLength = totalBytes;
  }

  /// Enforces both [_maxLines] and [maxFileBytes] bounds on the active log buffer.
  static bool _trimToLimitsIfNeeded() {
    if (_lines.length <= _maxLines && _activeByteLength <= maxFileBytes) {
      return false;
    }
    if (_lines.length > _maxLines) {
      _trimLinesByCount();
    }
    if (_activeByteLength > maxFileBytes) {
      _trimLinesByBytes();
    }
    return true;
  }

  /// Computes the UTF-8 byte length of [line] plus its trailing newline without allocating a byte buffer.
  static int _utf8LineByteLength(String line) {
    var byteLength = 1;
    for (var i = 0; i < line.length; i++) {
      final unit = line.codeUnitAt(i);
      if (unit <= 0x7F) {
        byteLength += 1;
      } else if (unit <= 0x7FF) {
        byteLength += 2;
      } else if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < line.length) {
        final next = line.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          byteLength += 4;
          i++;
        } else {
          byteLength += 3;
        }
      } else {
        byteLength += 3;
      }
    }
    return byteLength;
  }

  /// Overwrites the persistent log file with the current contents of [_lines].
  static void _writeFullFile({bool flush = false}) {
    if (!_persistToDisk) return;
    final sink = _sink;
    final path = _logFilePath;
    if (sink == null || path.isEmpty) return;
    final payload = _lines.isEmpty ? '' : '${_lines.join('\n')}\n';
    sink.writeLogFileSync(path, payload, append: false, flush: flush);
  }
}
