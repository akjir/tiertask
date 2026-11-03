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

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../repositories/local_file_repository.dart';

/// Severity levels for structured diagnostic log entries.
enum LogLevel {
  /// Verbose diagnostic trace for internal state transitions.
  debug(label: 'DEBUG'),

  /// Normal operational milestone.
  info(label: 'INFO'),

  /// Recoverable anomaly or fallback condition.
  warn(label: 'WARN'),

  /// Handled operational failure or exception.
  error(label: 'ERROR'),

  /// Unhandled framework or isolate exception recorded before termination.
  crash(label: 'CRASH');

  /// Creates a [LogLevel] with its uppercase bracket [label].
  const LogLevel({required this.label});

  /// Canonical uppercase identifier rendered in `<timestamp> [<LEVEL>] [<TAG>]`.
  final String label;
}

/// Architectural subsystem tags for structured diagnostic log entries.
enum LogTag {
  /// Application startup, platform metadata, lifecycle transitions, and crash recovery.
  lifecycle(label: 'LIFECYCLE'),

  /// TDF lexical scanning, structural parsing, and canonical serialization.
  tdf(label: 'TDF'),

  /// TaskBoard mutations, recurring task rescheduling, 30-day pruning, and 6-tier derivation.
  domain(label: 'DOMAIN'),

  /// Two-stage synchronization pipeline and per-entity LWW merge decisions.
  sync(label: 'SYNC'),

  /// Local `.tdf` filesystem I/O and WebDAV HTTP requests and responses.
  storage(label: 'STORAGE'),

  /// User interface navigation, dialog launches, and manual sync or migration triggers.
  ui(label: 'UI');

  /// Creates a [LogTag] with its uppercase bracket [label].
  const LogTag({required this.label});

  /// Canonical uppercase subsystem identifier rendered in `<timestamp> [<LEVEL>] [<TAG>]`.
  final String label;
}

/// Opt-in, zero-dependency diagnostic logger with synchronous crash preservation,
/// credential redaction, and rolling ring-buffer size protection.
class AppLogger {
  const AppLogger._();

  /// Default file name for the persistent diagnostic log.
  static const String defaultLogFileName = 'tiertask.log';

  /// Default maximum number of lines retained in memory and on disk before rolling 20% pruning.
  static const int defaultMaxLines = 5000;

  /// Maximum allowed diagnostic log file size in bytes (`2 MiB`).
  static const int maxFileBytes = 2097152;

  /// Injectable UTC clock used to format deterministic log entry timestamps.
  static DateTime Function() clock = () => DateTime.now().toUtc();

  static final RegExp _authHeaderPattern = RegExp(
    r'(Authorization\s*:\s*(?:Basic|Bearer)\s+)\S+',
    caseSensitive: false,
  );
  static final RegExp _basicBearerTokenPattern = RegExp(
    r'\b((?:Basic|Bearer)\s+)[A-Za-z0-9+/=._\-]{4,}',
    caseSensitive: false,
  );
  static final ValueNotifier<int> _changeNotifier = ValueNotifier<int>(0);
  static final RegExp _controlCharPattern = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
  );
  static bool _crashedInSession = false;
  static bool _enabled = false;
  static int _estimatedBytes = 0;
  static final RegExp _keyValueSecretPattern = RegExp(
    r'\b((?:password|appPassword|secret|token)\s*[=:]\s*)(?:"[^"]*"|\x27[^\x27]*\x27|\S+)',
    caseSensitive: false,
  );
  static final List<String> _lines = <String>[];
  static String? _logFilePath;
  static int _maxLines = defaultMaxLines;
  static final Set<String> _registeredSecrets = <String>{};
  static final RegExp _urlUserInfoPattern = RegExp(
    r'(https?://[^/\s:@]+:)([^@\s/]+)(@)',
    caseSensitive: false,
  );

  /// Listenable revision counter that increments whenever the log buffer changes.
  static ValueListenable<int> get changeListenable => _changeNotifier;

  /// Full newline-joined diagnostic log text currently held in memory.
  static String get fullLogText => _lines.join('\n');

  /// Whether an unhandled crash was recorded during the active session.
  static bool get hasCrashedInSession => _crashedInSession;

  /// Whether opt-in diagnostic logging is currently active.
  static bool get isEnabled => _enabled;

  /// Unmodifiable snapshot of all formatted log lines currently in the buffer.
  static List<String> get lines => List<String>.unmodifiable(_lines);

  /// Resolved filesystem path for `tiertask.log`, or `null` before initialization.
  static String? get logFilePath => _logFilePath;

  /// Manually clears the in-memory log buffer and truncates `tiertask.log` to 0 bytes.
  static void clear() {
    _lines.clear();
    _estimatedBytes = 0;
    _crashedInSession = false;
    if (_enabled) {
      if (_logFilePath case final path?) {
        LocalFileRepository.writeLogFileSync(path, '', append: false);
      }
    }
    _notifyChange();
  }

  /// Synchronously flushes an unhandled [error] and [stackTrace] with level `[CRASH]`
  /// and locks the session against clean-exit truncation.
  static void crash(Object error, StackTrace stackTrace) {
    if (!_enabled) {
      return;
    }
    _crashedInSession = true;
    final timestamp = formatUtcTimestamp(clock());
    final sanitizedError = _collapseNewlines(sanitize(error.toString()));
    final entries = <String>[
      '$timestamp [CRASH] [LIFECYCLE] Unhandled exception: $sanitizedError',
    ];
    final stackLines = sanitize(stackTrace.toString()).split('\n');
    for (final rawFrame in stackLines) {
      final cleanFrame = rawFrame.replaceAll('\r', '').trimRight();
      if (cleanFrame.isNotEmpty) {
        entries.add('$timestamp [CRASH] [LIFECYCLE]   $cleanFrame');
      }
    }
    _appendEntries(entries);
  }

  /// Records a [LogLevel.debug] entry under [tag] when diagnostic logging is enabled.
  static void debug(LogTag tag, String message) =>
      log(LogLevel.debug, tag, message);

  /// Records a [LogLevel.error] entry under [tag] when diagnostic logging is enabled.
  static void error(LogTag tag, String message) =>
      log(LogLevel.error, tag, message);

  /// Formats [timestamp] in UTC as `YYYY-MM-DD HH:MM:SS.mmm`.
  static String formatUtcTimestamp(DateTime timestamp) {
    final utc = timestamp.toUtc();
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final second = utc.second.toString().padLeft(2, '0');
    final millisecond = utc.millisecond.toString().padLeft(3, '0');
    return '$year-$month-$day $hour:$minute:$second.$millisecond';
  }

  /// Handles [AppLifecycleState] transitions, preserving the log across sleep/backgrounding
  /// and truncating `tiertask.log` on clean `detached` exit when no crash occurred.
  static void handleAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        info(LogTag.lifecycle, 'AppLifecycleState changed to ${state.name}');
      case AppLifecycleState.detached:
        _handleDetachedExit();
    }
  }

  /// Records a [LogLevel.info] entry under [tag] when diagnostic logging is enabled.
  static void info(LogTag tag, String message) =>
      log(LogLevel.info, tag, message);

  /// Formats, sanitizes, and synchronously appends a structured log entry when enabled.
  static void log(LogLevel level, LogTag tag, String message) {
    if (!_enabled) {
      return;
    }
    final timestamp = formatUtcTimestamp(clock());
    final cleanMessage = _collapseNewlines(sanitize(message));
    final entry = '$timestamp [${level.label}] [${tag.label}] $cleanMessage';
    _appendEntries(<String>[entry]);
  }

  /// Registers a sensitive credential string so any occurrence in log messages is replaced with `[REDACTED]`.
  static void registerSecret(String secret) {
    final trimmed = secret.trim();
    if (trimmed.isNotEmpty) {
      _registeredSecrets.add(trimmed);
    }
  }

  /// Resets all static logger state and restores the UTC clock for isolated testing.
  static void resetForTesting({DateTime Function()? clock}) {
    _enabled = false;
    _crashedInSession = false;
    _lines.clear();
    _estimatedBytes = 0;
    _logFilePath = null;
    _maxLines = defaultMaxLines;
    _registeredSecrets.clear();
    AppLogger.clock = clock ?? (() => DateTime.now().toUtc());
    _notifyChange();
  }

  /// Redacts credentials, `Authorization` headers, URL userinfo, and control characters from [input].
  static String sanitize(String input) {
    if (input.isEmpty) {
      return input;
    }
    var result = input;
    for (final secret in _registeredSecrets) {
      if (secret.isNotEmpty && result.contains(secret)) {
        result = result.replaceAll(secret, '[REDACTED]');
      }
    }
    result = result.replaceAllMapped(
      _authHeaderPattern,
      (match) => '${match.group(1)}[REDACTED]',
    );
    result = result.replaceAllMapped(
      _basicBearerTokenPattern,
      (match) => '${match.group(1)}[REDACTED]',
    );
    result = result.replaceAllMapped(
      _urlUserInfoPattern,
      (match) => '${match.group(1)}[REDACTED]${match.group(3)}',
    );
    result = result.replaceAllMapped(
      _keyValueSecretPattern,
      (match) => '${match.group(1)}[REDACTED]',
    );
    return result.replaceAll(_controlCharPattern, '');
  }

  /// Enables or disables diagnostic logging, performing startup crash recovery on enable
  /// or immediate buffer and file deletion on disable.
  static void setEnabled(
    bool enabled, {
    String? logFilePath,
    String? secretToRedact,
    int? maxLines,
  }) {
    if (secretToRedact != null) {
      registerSecret(secretToRedact);
    }
    if (maxLines != null && maxLines > 0) {
      _maxLines = maxLines;
    }
    final resolvedPath = _resolveTargetFilePath(logFilePath);
    if (!enabled) {
      _enabled = false;
      _crashedInSession = false;
      _lines.clear();
      _estimatedBytes = 0;
      _logFilePath = resolvedPath;
      LocalFileRepository.deleteLogFileSync(resolvedPath);
      _notifyChange();
      return;
    }
    if (_enabled && _logFilePath == resolvedPath) {
      return;
    }
    _enabled = true;
    _crashedInSession = false;
    _logFilePath = resolvedPath;
    _initializeSessionFile(resolvedPath);
    _notifyChange();
  }

  /// Records a [LogLevel.warn] entry under [tag] when diagnostic logging is enabled.
  static void warn(LogTag tag, String message) =>
      log(LogLevel.warn, tag, message);

  /// Appends [entries] to memory and disk, enforcing rolling line and byte bounds.
  static void _appendEntries(List<String> entries) {
    for (final entry in entries) {
      _lines.add(entry);
      _estimatedBytes += entry.length + 1;
    }
    final path = _logFilePath;
    if (_lines.length > _maxLines || _estimatedBytes > maxFileBytes) {
      _pruneOldestTwentyPercent();
      if (path != null) {
        LocalFileRepository.writeLogFileSync(
          path,
          '${_lines.join('\n')}\n',
          append: false,
        );
      }
    } else if (path != null) {
      LocalFileRepository.writeLogFileSync(
        path,
        '${entries.join('\n')}\n',
        append: true,
      );
    }
    _notifyChange();
  }

  /// Collapses CR and LF line breaks in [value] into single-line `' | '` separators.
  static String _collapseNewlines(String value) => value
      .replaceAll('\r\n', ' | ')
      .replaceAll('\n', ' | ')
      .replaceAll('\r', ' | ');

  /// Handles `AppLifecycleState.detached` by truncating `tiertask.log` unless a crash occurred.
  static void _handleDetachedExit() {
    if (_crashedInSession) {
      warn(
        LogTag.lifecycle,
        'AppLifecycleState.detached after crash; preserving tiertask.log',
      );
      return;
    }
    _lines.clear();
    _estimatedBytes = 0;
    if (_logFilePath case final path?) {
      LocalFileRepository.writeLogFileSync(path, '', append: false);
    }
    _notifyChange();
  }

  /// Inspects `tiertask.log` at [path] on session startup to detect clean exit vs. crash recovery.
  static void _initializeSessionFile(String path) {
    final existing = LocalFileRepository.readLogFileSync(
      path,
      maxBytes: maxFileBytes,
    );
    final timestamp = formatUtcTimestamp(clock());
    final platform = Platform.operatingSystem;
    if (existing.trim().isEmpty) {
      _lines.clear();
      final header = '=== SESSION START $timestamp [$platform] ===';
      _lines.add(header);
      _recomputeEstimatedBytes();
      LocalFileRepository.writeLogFileSync(path, '$header\n', append: false);
      return;
    }

    _loadExistingLines(existing);
    final banner =
        '=== RECOVERED UNCLEAN EXIT / CRASH LOG ABOVE | NEW SESSION START $timestamp [$platform] ===';
    _lines
      ..add('')
      ..add(banner);
    _recomputeEstimatedBytes();
    if (_lines.length > _maxLines || _estimatedBytes > maxFileBytes) {
      _pruneOldestTwentyPercent();
      LocalFileRepository.writeLogFileSync(
        path,
        '${_lines.join('\n')}\n',
        append: false,
      );
    } else {
      LocalFileRepository.writeLogFileSync(path, '\n$banner\n', append: true);
    }
  }

  /// Returns `true` when [line] is a session banner or `[CRASH]` entry that must survive rolling pruning.
  static bool _isProtectedLine(String line) =>
      line.startsWith('=== ') || line.contains('[CRASH]');

  /// Populates [_lines] from [rawContent] read from `tiertask.log` on startup.
  static void _loadExistingLines(String rawContent) {
    _lines.clear();
    final normalized = rawContent.replaceAll('\r\n', '\n');
    final split = normalized.split('\n');
    final count = (split.isNotEmpty && split.last.isEmpty)
        ? split.length - 1
        : split.length;
    for (var i = 0; i < count; i++) {
      _lines.add(split[i]);
    }
  }

  /// Increments [_changeNotifier] so open log viewer widgets rebuild.
  static void _notifyChange() {
    _changeNotifier.value = _changeNotifier.value + 1;
  }

  /// Trims the oldest 20% of non-protected log entries while preserving session headers and `[CRASH]` blocks.
  static void _pruneOldestTwentyPercent() {
    var regularCount = 0;
    for (final line in _lines) {
      if (!_isProtectedLine(line)) {
        regularCount++;
      }
    }
    final targetDrop = (regularCount * 0.20).ceil();
    var remainingToDrop = targetDrop > 0 ? targetDrop : 1;
    final retained = <String>[];
    for (final line in _lines) {
      if (_isProtectedLine(line) || remainingToDrop <= 0) {
        retained.add(line);
      } else {
        remainingToDrop--;
      }
    }
    _lines
      ..clear()
      ..addAll(retained);
    _recomputeEstimatedBytes();
  }

  /// Recomputes [_estimatedBytes] from the current [_lines] buffer.
  static void _recomputeEstimatedBytes() {
    var total = 0;
    for (final line in _lines) {
      total += line.length + 1;
    }
    _estimatedBytes = total;
  }

  /// Resolves the target filesystem path for `tiertask.log`.
  static String _resolveTargetFilePath(String? explicitPath) {
    if (explicitPath != null && explicitPath.trim().isNotEmpty) {
      return explicitPath.trim();
    }
    if (_logFilePath case final currentPath? when currentPath.isNotEmpty) {
      return currentPath;
    }
    return LocalFileRepository.defaultLogFilePath();
  }
}
