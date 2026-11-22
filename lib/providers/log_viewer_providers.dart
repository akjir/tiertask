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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_logger.dart';
import 'config_providers.dart';

/// User-configurable minimum diagnostic log thresholds in ascending severity order.
const List<LogLevel> configurableDiagnosticLogLevels = <LogLevel>[
  LogLevel.debug,
  LogLevel.info,
  LogLevel.warn,
  LogLevel.error,
];

/// Provides the live dated diagnostic log filename for settings views.
final activeLogFileNameProvider =
    NotifierProvider.autoDispose<ActiveLogFileNameNotifier, String>(
      ActiveLogFileNameNotifier.new,
    );

/// Provides reactive [DiagnosticLogSnapshot] state and actions for the diagnostic log viewer.
final logViewerProvider =
    NotifierProvider.autoDispose<LogViewerNotifier, DiagnosticLogSnapshot>(
      LogViewerNotifier.new,
    );

/// Visual highlight severity classification for a rendered diagnostic log line.
enum DiagnosticLogSeverity {
  /// Standard informational, debug, or metadata line.
  normal,

  /// Warning line containing `[WARN]` or `[WARN `.
  warn,

  /// Error line containing `[ERROR]`.
  error,

  /// Crash or unclean exit recovery line.
  crash,
}

/// Sealed outcome for manual WebDAV diagnostic log uploads.
sealed class LogSyncResult {
  /// Creates a [LogSyncResult].
  const LogSyncResult();
}

/// Outcome returned when uploading the active diagnostic log to WebDAV fails.
@immutable
final class LogSyncFailed extends LogSyncResult {
  /// Creates a [LogSyncFailed] outcome with a sanitized [message].
  const LogSyncFailed(this.message);

  /// Human-readable error message from the upload attempt.
  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LogSyncFailed && other.message == message;
  }

  @override
  int get hashCode => message.hashCode;
}

/// Outcome returned when uploading the active diagnostic log to WebDAV succeeds.
@immutable
final class LogSyncSucceeded extends LogSyncResult {
  /// Creates a [LogSyncSucceeded] outcome.
  const LogSyncSucceeded();
}

/// Reactive notifier mirroring [AppLogger.activeLogFileName] for settings widgets.
class ActiveLogFileNameNotifier extends Notifier<String> {
  bool _isDisposed = false;
  bool _refreshScheduled = false;

  @override
  String build() {
    ref.watch(diagnosticsEnabledProvider);
    _isDisposed = false;
    AppLogger.revision.removeListener(_handleRevisionChanged);
    AppLogger.revision.addListener(_handleRevisionChanged);
    ref.onDispose(() {
      _isDisposed = true;
      AppLogger.revision.removeListener(_handleRevisionChanged);
    });
    return AppLogger.activeLogFileName;
  }

  /// Coalesces [AppLogger.revision] updates onto a microtask so log writes inside other providers never mutate state re-entrantly.
  void _handleRevisionChanged() {
    if (_isDisposed || _refreshScheduled) {
      return;
    }
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (_isDisposed) {
        return;
      }
      final nextFileName = AppLogger.activeLogFileName;
      if (state != nextFileName) {
        state = nextFileName;
      }
    });
  }
}

/// Immutable entry for a single diagnostic log line and its [severity].
@immutable
class DiagnosticLogLine {
  /// Creates a [DiagnosticLogLine].
  const DiagnosticLogLine({required this.text, required this.severity});

  /// Semantic highlight severity classified for [text].
  final DiagnosticLogSeverity severity;

  /// Raw formatted single-line diagnostic text.
  final String text;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiagnosticLogLine &&
        other.text == text &&
        other.severity == severity;
  }

  @override
  int get hashCode => Object.hash(text, severity);
}

/// Immutable snapshot driving the diagnostic log viewer.
@immutable
class DiagnosticLogSnapshot {
  /// Creates a [DiagnosticLogSnapshot] with an unmodifiable [filteredLines] view.
  DiagnosticLogSnapshot({
    required this.canSyncWebDav,
    required this.errorCount,
    required Iterable<DiagnosticLogLine> filteredLines,
    required this.hasEntries,
    required this.headerSummary,
    required this.minimumLevel,
    required this.selectedTag,
    required this.totalEntries,
    required this.warningCount,
  }) : filteredLines = List<DiagnosticLogLine>.unmodifiable(filteredLines);

  /// Whether manual WebDAV log upload is currently enabled and configured.
  final bool canSyncWebDav;

  /// Total count of `[ERROR]` and `[CRASH]` entries across all buffered lines.
  final int errorCount;

  /// Unmodifiable filtered log lines matching [minimumLevel] and [selectedTag].
  final List<DiagnosticLogLine> filteredLines;

  /// Whether at least one line exists in the diagnostic log buffer.
  final bool hasEntries;

  /// Formatted metadata header string (`<file> • v<ver> (<platform>) • <ws> • <level>`).
  final String headerSummary;

  /// Currently selected minimum [LogLevel] filter.
  final LogLevel minimumLevel;

  /// Currently selected subsystem [LogTag] filter, or `null` for all subsystems.
  final LogTag? selectedTag;

  /// Total count of non-header entries across all buffered lines.
  final int totalEntries;

  /// Total count of `[WARN]` entries across all buffered lines.
  final int warningCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiagnosticLogSnapshot &&
        other.canSyncWebDav == canSyncWebDav &&
        other.errorCount == errorCount &&
        other.hasEntries == hasEntries &&
        other.headerSummary == headerSummary &&
        other.minimumLevel == minimumLevel &&
        other.selectedTag == selectedTag &&
        other.totalEntries == totalEntries &&
        other.warningCount == warningCount &&
        listEquals(other.filteredLines, filteredLines);
  }

  @override
  int get hashCode => Object.hash(
    canSyncWebDav,
    errorCount,
    hasEntries,
    headerSummary,
    minimumLevel,
    selectedTag,
    totalEntries,
    warningCount,
    Object.hashAll(filteredLines),
  );
}

/// Reactive notifier managing diagnostic log filtering, statistics, clipboard text, and WebDAV uploads.
class LogViewerNotifier extends Notifier<DiagnosticLogSnapshot> {
  bool _canSyncWebDav = false;
  bool _isDisposed = false;
  LogLevel _minimumLevel = LogLevel.debug;
  bool _refreshScheduled = false;
  LogTag? _selectedTag;

  @override
  DiagnosticLogSnapshot build() {
    _canSyncWebDav = ref.watch(
      webDavConfigProvider.select(
        (asyncConfig) =>
            (asyncConfig.asData?.value.logStorageMode.usesWebDav ?? false) &&
            (asyncConfig.asData?.value.isWebDavConfigured ?? false),
      ),
    );
    _isDisposed = false;
    AppLogger.revision.removeListener(_handleRevisionChanged);
    AppLogger.revision.addListener(_handleRevisionChanged);
    ref.onDispose(() {
      _isDisposed = true;
      AppLogger.revision.removeListener(_handleRevisionChanged);
    });
    return _buildSnapshot();
  }

  /// Clears all in-memory diagnostic log lines and truncates the active log file.
  void clearLog() {
    AppLogger.clear();
    state = _buildSnapshot();
  }

  /// Returns the concatenated filtered diagnostic log text matching active viewer filters.
  String readFilteredLogText() {
    final lines = state.filteredLines;
    if (lines.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) {
        buffer.write('\n');
      }
      buffer.write(lines[i].text);
    }
    return buffer.toString();
  }

  /// Returns the concatenated full diagnostic log text for clipboard export.
  String readFullLogText() => AppLogger.fullLogText;

  /// Updates the active minimum [LogLevel] filter and recomputes state.
  void setMinimumLevel(LogLevel level) {
    if (_minimumLevel == level) {
      return;
    }
    _minimumLevel = level;
    state = _buildSnapshot();
  }

  /// Updates the active [LogTag] filter (`null` for all) and recomputes state.
  void setSelectedTag(LogTag? tag) {
    if (_selectedTag == tag) {
      return;
    }
    _selectedTag = tag;
    state = _buildSnapshot();
  }

  /// Uploads the active diagnostic log snapshot to WebDAV and returns a typed [LogSyncResult].
  Future<LogSyncResult> syncLogToWebDav() async {
    try {
      final current = readCurrentConfig(ref);
      if (current.diagnosticsEnabled && current.isWebDavConfigured) {
        await ref
            .read(webDavRepositoryProvider)
            .saveLog(AppLogger.activeLogFileName);
      }
      return const LogSyncSucceeded();
    } on Object catch (error) {
      return LogSyncFailed(AppLogger.sanitize(error.toString()));
    }
  }

  /// Computes [DiagnosticLogSnapshot] in a single linear pass over [AppLogger.lines].
  DiagnosticLogSnapshot _buildSnapshot() {
    final allLines = AppLogger.lines;
    final metadata = AppLogger.metadata;
    final includeAll = _minimumLevel == LogLevel.debug && _selectedTag == null;

    var totalEntries = 0;
    var warningCount = 0;
    var errorCount = 0;
    final filtered = <DiagnosticLogLine>[];

    for (final line in allLines) {
      final isHeader = line.startsWith('===') || line.startsWith('@meta ');
      if (!isHeader) {
        totalEntries++;
        if (line.contains('[WARN]') || line.contains('[WARN ')) {
          warningCount++;
        } else if (line.contains('[ERROR]') || line.contains('[CRASH]')) {
          errorCount++;
        }
      }
      if (includeAll ||
          AppLogger.matchesFilter(
            line,
            minimumLevel: _minimumLevel,
            tag: _selectedTag,
          )) {
        filtered.add(
          DiagnosticLogLine(text: line, severity: _classifySeverity(line)),
        );
      }
    }

    final headerSummary =
        '${AppLogger.activeLogFileName} • v${metadata.appVersion} (${metadata.platform}) • '
        '${metadata.workspaceId} • ${AppLogger.minimumLevel.label}';

    return DiagnosticLogSnapshot(
      canSyncWebDav: _canSyncWebDav,
      errorCount: errorCount,
      filteredLines: filtered,
      hasEntries: allLines.isNotEmpty,
      headerSummary: headerSummary,
      minimumLevel: _minimumLevel,
      selectedTag: _selectedTag,
      totalEntries: totalEntries,
      warningCount: warningCount,
    );
  }

  /// Classifies [line] into its semantic [DiagnosticLogSeverity].
  DiagnosticLogSeverity _classifySeverity(String line) {
    if (line.contains('[CRASH]') || line.contains('RECOVERED UNCLEAN EXIT')) {
      return DiagnosticLogSeverity.crash;
    }
    if (line.contains('[ERROR]')) {
      return DiagnosticLogSeverity.error;
    }
    if (line.contains('[WARN]') || line.contains('[WARN ')) {
      return DiagnosticLogSeverity.warn;
    }
    return DiagnosticLogSeverity.normal;
  }

  /// Coalesces [AppLogger.revision] updates onto a microtask so logging inside other providers never mutates state re-entrantly.
  void _handleRevisionChanged() {
    if (_isDisposed || _refreshScheduled) {
      return;
    }
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (_isDisposed) {
        return;
      }
      state = _buildSnapshot();
    });
  }
}
