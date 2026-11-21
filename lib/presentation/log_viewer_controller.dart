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

import '../providers/config_providers.dart';
import '../services/app_logger.dart';

/// Provides the live dated diagnostic log filename for settings presentation.
final activeLogFileNameProvider =
    NotifierProvider.autoDispose<ActiveLogFileNameNotifier, String>(
      ActiveLogFileNameNotifier.new,
    );

/// Provides reactive [DiagnosticLogViewModel] state and actions for the diagnostic log viewer.
final logViewerControllerProvider =
    NotifierProvider.autoDispose<LogViewerController, DiagnosticLogViewModel>(
      LogViewerController.new,
    );

/// Presentation-layer severity levels decoupling UI controls from [LogLevel].
enum DiagnosticLogLevel {
  /// Fine-grained diagnostic traces.
  debug('DEBUG'),

  /// Normal operational milestones.
  info('INFO'),

  /// Recoverable anomalies and validation warnings.
  warn('WARN'),

  /// Operational failures and rejected mutations.
  error('ERROR'),

  /// Unhandled framework or isolate crashes.
  crash('CRASH');

  /// Creates a [DiagnosticLogLevel] with its uppercase [label].
  const DiagnosticLogLevel(this.label);

  /// User-configurable minimum log thresholds in ascending severity order.
  static const List<DiagnosticLogLevel> configurableLevels =
      <DiagnosticLogLevel>[
        DiagnosticLogLevel.debug,
        DiagnosticLogLevel.info,
        DiagnosticLogLevel.warn,
        DiagnosticLogLevel.error,
      ];

  /// Canonical uppercase severity token.
  final String label;

  /// Maps a service-layer [LogLevel] to its [DiagnosticLogLevel] counterpart.
  static DiagnosticLogLevel fromLogLevel(LogLevel level) {
    return switch (level) {
      LogLevel.debug => DiagnosticLogLevel.debug,
      LogLevel.info => DiagnosticLogLevel.info,
      LogLevel.warn => DiagnosticLogLevel.warn,
      LogLevel.error => DiagnosticLogLevel.error,
      LogLevel.crash => DiagnosticLogLevel.crash,
    };
  }

  /// Maps this [DiagnosticLogLevel] back to its service-layer [LogLevel].
  LogLevel toLogLevel() {
    return switch (this) {
      DiagnosticLogLevel.debug => LogLevel.debug,
      DiagnosticLogLevel.info => LogLevel.info,
      DiagnosticLogLevel.warn => LogLevel.warn,
      DiagnosticLogLevel.error => LogLevel.error,
      DiagnosticLogLevel.crash => LogLevel.crash,
    };
  }
}

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

/// Presentation-layer subsystem tag filters decoupling UI controls from [LogTag].
enum DiagnosticLogTag {
  /// Application startup, lifecycle transitions, and global error boundaries.
  lifecycle('LIFECYCLE'),

  /// TDF scanning, parsing, serialization, and migrations.
  tdf('TDF'),

  /// Task board evaluation, mutations, and queue operations.
  domain('DOMAIN'),

  /// Synchronization pipeline stages and board merges.
  sync('SYNC'),

  /// Local file I/O, WebDAV requests, and settings persistence.
  storage('STORAGE'),

  /// User-initiated screen/dialog navigation and UI telemetry.
  ui('UI');

  /// Creates a [DiagnosticLogTag] with its canonical uppercase [label].
  const DiagnosticLogTag(this.label);

  /// Canonical uppercase subsystem token.
  final String label;

  /// Maps this [DiagnosticLogTag] back to its service-layer [LogTag].
  LogTag toLogTag() {
    return switch (this) {
      DiagnosticLogTag.lifecycle => LogTag.lifecycle,
      DiagnosticLogTag.tdf => LogTag.tdf,
      DiagnosticLogTag.domain => LogTag.domain,
      DiagnosticLogTag.sync => LogTag.sync,
      DiagnosticLogTag.storage => LogTag.storage,
      DiagnosticLogTag.ui => LogTag.ui,
    };
  }
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

/// Immutable presentation entry for a single diagnostic log line and its [severity].
@immutable
class DiagnosticLogLineViewModel {
  /// Creates a [DiagnosticLogLineViewModel].
  const DiagnosticLogLineViewModel({
    required this.text,
    required this.severity,
  });

  /// Semantic highlight severity classified for [text].
  final DiagnosticLogSeverity severity;

  /// Raw formatted single-line diagnostic text.
  final String text;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiagnosticLogLineViewModel &&
        other.text == text &&
        other.severity == severity;
  }

  @override
  int get hashCode => Object.hash(text, severity);
}

/// Immutable snapshot driving the diagnostic log viewer dialog.
@immutable
class DiagnosticLogViewModel {
  /// Creates a [DiagnosticLogViewModel] with an unmodifiable [filteredLines] view.
  DiagnosticLogViewModel({
    required this.canSyncWebDav,
    required this.errorCount,
    required Iterable<DiagnosticLogLineViewModel> filteredLines,
    required this.hasEntries,
    required this.headerSummary,
    required this.minimumLevel,
    required this.selectedTag,
    required this.totalEntries,
    required this.warningCount,
  }) : filteredLines = List<DiagnosticLogLineViewModel>.unmodifiable(
         filteredLines,
       );

  /// Whether manual WebDAV log upload is currently enabled and configured.
  final bool canSyncWebDav;

  /// Total count of `[ERROR]` and `[CRASH]` entries across all buffered lines.
  final int errorCount;

  /// Unmodifiable filtered log lines matching [minimumLevel] and [selectedTag].
  final List<DiagnosticLogLineViewModel> filteredLines;

  /// Whether at least one line exists in the diagnostic log buffer.
  final bool hasEntries;

  /// Formatted metadata header string (`<file> • v<ver> (<platform>) • <ws> • <level>`).
  final String headerSummary;

  /// Currently selected minimum log level filter.
  final DiagnosticLogLevel minimumLevel;

  /// Currently selected subsystem tag filter, or `null` for all subsystems.
  final DiagnosticLogTag? selectedTag;

  /// Total count of non-header entries across all buffered lines.
  final int totalEntries;

  /// Total count of `[WARN]` entries across all buffered lines.
  final int warningCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiagnosticLogViewModel &&
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

/// Presentation controller managing diagnostic log filtering, statistics, clipboard text, and WebDAV uploads.
class LogViewerController extends Notifier<DiagnosticLogViewModel> {
  bool _canSyncWebDav = false;
  bool _isDisposed = false;
  DiagnosticLogLevel _minimumLevel = DiagnosticLogLevel.debug;
  bool _refreshScheduled = false;
  DiagnosticLogTag? _selectedTag;

  @override
  DiagnosticLogViewModel build() {
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
    return _buildViewModel();
  }

  /// Clears all in-memory diagnostic log lines and truncates the active log file.
  void clearLog() {
    AppLogger.clear();
    state = _buildViewModel();
  }

  /// Returns the concatenated full diagnostic log text for clipboard export.
  String readFullLogText() => AppLogger.fullLogText;

  /// Updates the active minimum [DiagnosticLogLevel] filter and recomputes state.
  void setMinimumLevel(DiagnosticLogLevel level) {
    if (_minimumLevel == level) {
      return;
    }
    _minimumLevel = level;
    state = _buildViewModel();
  }

  /// Updates the active [DiagnosticLogTag] filter (`null` for all) and recomputes state.
  void setSelectedTag(DiagnosticLogTag? tag) {
    if (_selectedTag == tag) {
      return;
    }
    _selectedTag = tag;
    state = _buildViewModel();
  }

  /// Uploads the active diagnostic log snapshot to WebDAV and returns a typed [LogSyncResult].
  Future<LogSyncResult> syncLogToWebDav() async {
    try {
      await ref.read(webDavConfigProvider.notifier).syncLogToWebDavNow();
      return const LogSyncSucceeded();
    } on Object catch (error) {
      return LogSyncFailed(AppLogger.sanitize(error.toString()));
    }
  }

  /// Computes [DiagnosticLogViewModel] in a single linear pass over [AppLogger.lines].
  DiagnosticLogViewModel _buildViewModel() {
    final allLines = AppLogger.lines;
    final metadata = AppLogger.metadata;
    final filterLevel = _minimumLevel.toLogLevel();
    final filterTag = _selectedTag?.toLogTag();
    final includeAll =
        _minimumLevel == DiagnosticLogLevel.debug && _selectedTag == null;

    var totalEntries = 0;
    var warningCount = 0;
    var errorCount = 0;
    final filtered = <DiagnosticLogLineViewModel>[];

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
            minimumLevel: filterLevel,
            tag: filterTag,
          )) {
        filtered.add(
          DiagnosticLogLineViewModel(
            text: line,
            severity: _classifySeverity(line),
          ),
        );
      }
    }

    final headerSummary =
        '${AppLogger.activeLogFileName} • v${metadata.appVersion} (${metadata.platform}) • '
        '${metadata.workspaceId} • ${AppLogger.minimumLevel.label}';

    return DiagnosticLogViewModel(
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
      state = _buildViewModel();
    });
  }
}
