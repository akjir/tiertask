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

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/webdav_config.dart';
import '../../providers/config_providers.dart';
import '../../services/app_logger.dart';

/// Type alias allowing the diagnostic log viewer to be referenced as [LogViewerScreen].
typedef LogViewerScreen = LogViewerDialog;

/// Material 3 dialog displaying the monospace diagnostic log with metadata summary,
/// level/subsystem filters, semantic severity highlighting, and toolbar actions.
class LogViewerDialog extends ConsumerStatefulWidget {
  /// Creates a [LogViewerDialog].
  const LogViewerDialog({super.key});

  @override
  ConsumerState<LogViewerDialog> createState() => _LogViewerDialogState();
}

/// Dialog body containing the metadata card, filter bar, and scrollable log lines.
class _LogDialogContent extends StatelessWidget {
  /// Creates a [_LogDialogContent].
  const _LogDialogContent({
    required this.allLines,
    required this.filteredLines,
    required this.horizontalController,
    required this.minimumLevel,
    required this.onLevelChanged,
    required this.onTagChanged,
    required this.selectedTag,
    required this.verticalController,
  });

  /// Unfiltered diagnostic log lines.
  final List<String> allLines;

  /// Log lines matching [minimumLevel] and [selectedTag].
  final List<String> filteredLines;

  /// Horizontal scroll controller for long lines.
  final ScrollController horizontalController;

  /// Currently selected minimum log level filter.
  final LogLevel minimumLevel;

  /// Callback invoked when the minimum log level filter changes.
  final ValueChanged<LogLevel> onLevelChanged;

  /// Callback invoked when the subsystem tag filter changes.
  final ValueChanged<LogTag?> onTagChanged;

  /// Currently selected subsystem tag filter (`null` for all subsystems).
  final LogTag? selectedTag;

  /// Vertical scroll controller for the log list.
  final ScrollController verticalController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SizedBox(
      width: double.maxFinite,
      height: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          _LogMetadataCard(
            key: const ValueKey('log_viewer_metadata_card'),
            lines: allLines,
          ),
          _LogFilterBar(
            minimumLevel: minimumLevel,
            selectedTag: selectedTag,
            onLevelChanged: onLevelChanged,
            onTagChanged: onTagChanged,
          ),
          Expanded(
            child: filteredLines.isEmpty
                ? Center(child: Text(localizations.emptyLogHint))
                : _LogLinesView(
                    lines: filteredLines,
                    verticalController: verticalController,
                    horizontalController: horizontalController,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Filter controls for minimum [LogLevel] and subsystem [LogTag] in [LogViewerDialog].
class _LogFilterBar extends StatelessWidget {
  /// Creates a [_LogFilterBar].
  const _LogFilterBar({
    required this.minimumLevel,
    required this.onLevelChanged,
    required this.onTagChanged,
    required this.selectedTag,
  });

  /// Selected minimum [LogLevel] filter.
  final LogLevel minimumLevel;

  /// Callback invoked when a new [LogLevel] is selected.
  final ValueChanged<LogLevel> onLevelChanged;

  /// Callback invoked when a new [LogTag] (or `null` for all) is selected.
  final ValueChanged<LogTag?> onTagChanged;

  /// Selected [LogTag] filter, or `null` for all subsystems.
  final LogTag? selectedTag;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<LogLevel>(
          key: const ValueKey('log_viewer_level_dropdown'),
          value: minimumLevel,
          isDense: true,
          items: [
            for (final level in LogLevel.configurableLevels)
              DropdownMenuItem<LogLevel>(
                value: level,
                child: Text('${localizations.logLevelLabel}: ${level.label}'),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              onLevelChanged(value);
            }
          },
        ),
        DropdownButton<LogTag?>(
          key: const ValueKey('log_viewer_tag_dropdown'),
          value: selectedTag,
          isDense: true,
          items: [
            DropdownMenuItem<LogTag?>(
              child: Text(localizations.logFilterAllTags),
            ),
            for (final tag in LogTag.values)
              DropdownMenuItem<LogTag?>(value: tag, child: Text(tag.label)),
          ],
          onChanged: onTagChanged,
        ),
      ],
    );
  }
}

/// Renders a single monospace log line with semantic color accents for `[WARN]`, `[ERROR]`, and `[CRASH]`.
class _LogLineRow extends StatelessWidget {
  /// Creates a [_LogLineRow].
  const _LogLineRow({super.key, required this.line});

  /// Formatted single-line diagnostic entry.
  final String line;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (textColor, backgroundColor, fontWeight) = _resolveLineStyle(
      line,
      colorScheme,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: backgroundColor != null
          ? BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Text(
        line,
        softWrap: false,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: textColor,
          fontWeight: fontWeight,
        ),
      ),
    );
  }

  /// Resolves foreground color, subtle background tint, and font weight for [line].
  (Color, Color?, FontWeight) _resolveLineStyle(
    String line,
    ColorScheme colorScheme,
  ) {
    if (line.contains('[CRASH]') || line.contains('RECOVERED UNCLEAN EXIT')) {
      return (
        colorScheme.onErrorContainer,
        colorScheme.errorContainer.withValues(alpha: 0.75),
        FontWeight.w700,
      );
    }
    if (line.contains('[ERROR]')) {
      return (
        colorScheme.error,
        colorScheme.errorContainer.withValues(alpha: 0.3),
        FontWeight.w600,
      );
    }
    if (line.contains('[WARN]') || line.contains('[WARN ')) {
      return (
        colorScheme.tertiary,
        colorScheme.tertiaryContainer.withValues(alpha: 0.35),
        FontWeight.w600,
      );
    }
    return (colorScheme.onSurface, null, FontWeight.normal);
  }
}

/// Bidirectionally scrollable monospace list of diagnostic log lines.
class _LogLinesView extends StatelessWidget {
  /// Creates a [_LogLinesView].
  const _LogLinesView({
    required this.lines,
    required this.verticalController,
    required this.horizontalController,
  });

  /// Horizontal scroll controller for long lines and stack traces.
  final ScrollController horizontalController;

  /// Snapshot of formatted log lines.
  final List<String> lines;

  /// Vertical scroll controller for jumping to the bottommost entry.
  final ScrollController verticalController;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: verticalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 960,
          child: ListView.builder(
            controller: verticalController,
            itemCount: lines.length,
            itemBuilder: (context, index) => _LogLineRow(
              key: ValueKey('log_line_$index'),
              line: lines[index],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact summary card displaying active session metadata and entry/warning/error counts.
class _LogMetadataCard extends StatelessWidget {
  /// Creates a [_LogMetadataCard].
  const _LogMetadataCard({super.key, required this.lines});

  /// Current log lines used to compute entry, warning, and error statistics.
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final metadata = AppLogger.metadata;
    final (entries, warnings, errors) = _computeStats(lines);
    final headerSummary =
        '${AppLogger.activeLogFileName} • v${metadata.appVersion} (${metadata.platform}) • '
        '${metadata.workspaceId} • ${AppLogger.minimumLevel.label}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(
            headerSummary,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontFamily: 'monospace'),
          ),
          Text(
            localizations.logMetadataStats(
              entries.toString(),
              warnings.toString(),
              errors.toString(),
            ),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// Counts structured entries, warnings, and errors/crashes across [logLines].
  (int, int, int) _computeStats(List<String> logLines) {
    var entries = 0;
    var warnings = 0;
    var errors = 0;
    for (final line in logLines) {
      if (line.startsWith('===') || line.startsWith('@meta ')) {
        continue;
      }
      entries++;
      if (line.contains('[WARN]') || line.contains('[WARN ')) {
        warnings++;
      } else if (line.contains('[ERROR]') || line.contains('[CRASH]')) {
        errors++;
      }
    }
    return (entries, warnings, errors);
  }
}

/// State for [LogViewerDialog] managing scroll controllers and level/tag filter state.
class _LogViewerDialogState extends ConsumerState<LogViewerDialog> {
  final ScrollController _horizontalController = ScrollController();
  LogLevel _minimumLevel = LogLevel.debug;
  LogTag? _selectedTag;
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config =
        ref.watch(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final canSyncWebDav =
        config.logStorageMode.usesWebDav && config.isWebDavConfigured;
    return ValueListenableBuilder<int>(
      valueListenable: AppLogger.revision,
      builder: (context, _, _) => _buildDialog(context, canSyncWebDav),
    );
  }

  /// Builds the [AlertDialog] for the current log buffer and filter state.
  Widget _buildDialog(BuildContext context, bool canSyncWebDav) {
    final localizations = AppLocalizations.of(context);
    final allLines = AppLogger.lines;
    final filteredLines = _filterLines(allLines);
    return AlertDialog(
      title: _LogViewerHeader(
        title: localizations.diagnosticLogTitle,
        hasEntries: allLines.isNotEmpty,
        canSyncWebDav: canSyncWebDav,
        onSyncWebDav: () => _syncLogToWebDav(context),
        onCopyAll: () => _copyAll(context),
        onScrollToBottom: _scrollToBottom,
        onClearLog: () => _clearLog(context),
      ),
      content: _LogDialogContent(
        allLines: allLines,
        filteredLines: filteredLines,
        horizontalController: _horizontalController,
        minimumLevel: _minimumLevel,
        onLevelChanged: (level) => setState(() => _minimumLevel = level),
        onTagChanged: (tag) => setState(() => _selectedTag = tag),
        selectedTag: _selectedTag,
        verticalController: _verticalController,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionClose),
        ),
      ],
    );
  }

  /// Clears the in-memory log buffer and truncates the active log file.
  void _clearLog(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    AppLogger.clear();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(localizations.logClearedSnackBar)));
  }

  /// Copies the full diagnostic log text to the system clipboard and displays a confirmation [SnackBar].
  Future<void> _copyAll(BuildContext context) async {
    final localizations = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: AppLogger.fullLogText));
    if (!mounted) {
      return;
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(localizations.logCopiedSnackBar)));
  }

  /// Filters [lines] according to [_minimumLevel] and [_selectedTag].
  List<String> _filterLines(List<String> lines) {
    if (_minimumLevel == LogLevel.debug && _selectedTag == null) {
      return lines;
    }
    final filtered = <String>[];
    for (final line in lines) {
      if (AppLogger.matchesFilter(
        line,
        minimumLevel: _minimumLevel,
        tag: _selectedTag,
      )) {
        filtered.add(line);
      }
    }
    return filtered;
  }

  /// Scrolls the vertical log view directly to the bottommost entry.
  void _scrollToBottom() {
    if (!_verticalController.hasClients) {
      return;
    }
    _verticalController.jumpTo(_verticalController.position.maxScrollExtent);
  }

  /// Uploads the active diagnostic log snapshot to WebDAV and shows a status [SnackBar].
  Future<void> _syncLogToWebDav(BuildContext context) async {
    final localizations = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(webDavConfigProvider.notifier).syncLogToWebDavNow();
      if (!mounted) {
        return;
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(localizations.logSyncedSnackBar)),
        );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

/// Dialog header bar containing the title and toolbar actions (`Sync Log Now`, `Copy All`, `Scroll to Bottom`, `Clear Log`).
class _LogViewerHeader extends StatelessWidget {
  /// Creates a [_LogViewerHeader].
  const _LogViewerHeader({
    required this.canSyncWebDav,
    required this.hasEntries,
    required this.onClearLog,
    required this.onCopyAll,
    required this.onScrollToBottom,
    required this.onSyncWebDav,
    required this.title,
  });

  /// Whether WebDAV log synchronization is enabled and configured.
  final bool canSyncWebDav;

  /// Whether at least one log line is present.
  final bool hasEntries;

  /// Callback to clear the log buffer and file.
  final VoidCallback onClearLog;

  /// Callback to copy the full log text to the clipboard.
  final VoidCallback onCopyAll;

  /// Callback to jump to the bottom of the log list.
  final VoidCallback onScrollToBottom;

  /// Callback to upload the diagnostic log to WebDAV immediately.
  final VoidCallback onSyncWebDav;

  /// Dialog title string.
  final String title;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(child: Text(title)),
        if (canSyncWebDav)
          IconButton(
            key: const ValueKey('log_viewer_sync_webdav_button'),
            tooltip: localizations.tooltipSyncLogWebDav,
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: hasEntries ? onSyncWebDav : null,
          ),
        IconButton(
          key: const ValueKey('log_viewer_copy_button'),
          tooltip: localizations.tooltipCopyLog,
          icon: const Icon(Icons.copy_rounded),
          onPressed: hasEntries ? onCopyAll : null,
        ),
        IconButton(
          key: const ValueKey('log_viewer_scroll_bottom_button'),
          tooltip: localizations.tooltipScrollToBottom,
          icon: const Icon(Icons.vertical_align_bottom_rounded),
          onPressed: hasEntries ? onScrollToBottom : null,
        ),
        IconButton(
          key: const ValueKey('log_viewer_clear_button'),
          tooltip: localizations.tooltipClearLog,
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: onClearLog,
        ),
      ],
    );
  }
}

/// Opens the [LogViewerDialog] modal and logs the navigation event under [LogTag.ui].
Future<void> showLogViewerDialog(BuildContext context) {
  AppLogger.event(
    LogLevel.info,
    LogTag.ui,
    'ui.dialog.open',
    fields: <String, Object?>{'dialog': 'log_viewer'},
  );
  return showDialog<void>(
    context: context,
    builder: (_) => const LogViewerDialog(),
  );
}
