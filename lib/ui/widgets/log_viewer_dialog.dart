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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_logger.dart';

/// Type alias allowing the diagnostic log viewer to be referenced as [LogViewerScreen].
typedef LogViewerScreen = LogViewerDialog;

/// Material 3 dialog displaying the monospace diagnostic log (`tiertask.log`) with
/// semantic severity highlighting and toolbar actions for Copy All, Scroll to Bottom, and Clear Log.
class LogViewerDialog extends StatefulWidget {
  /// Creates a [LogViewerDialog].
  const LogViewerDialog({super.key});

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: AppLogger.changeListenable,
      builder: (context, _, _) {
        final lines = AppLogger.lines;
        return AlertDialog(
          title: _LogViewerHeader(
            title: localizations.diagnosticLogTitle,
            hasEntries: lines.isNotEmpty,
            onCopyAll: () => _copyAll(context),
            onScrollToBottom: _scrollToBottom,
            onClearLog: () => _clearLog(context),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 440,
            child: lines.isEmpty
                ? Center(child: Text(localizations.emptyLogHint))
                : _LogLinesView(
                    lines: lines,
                    verticalController: _verticalController,
                    horizontalController: _horizontalController,
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(localizations.actionClose),
            ),
          ],
        );
      },
    );
  }

  /// Clears the in-memory log buffer and truncates `tiertask.log`.
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

  /// Scrolls the vertical log view directly to the bottommost entry.
  void _scrollToBottom() {
    if (!_verticalController.hasClients) {
      return;
    }
    _verticalController.jumpTo(_verticalController.position.maxScrollExtent);
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
    if (line.contains('[WARN]')) {
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

/// Dialog header bar containing the title and toolbar actions (`Copy All`, `Scroll to Bottom`, `Clear Log`).
class _LogViewerHeader extends StatelessWidget {
  /// Creates a [_LogViewerHeader].
  const _LogViewerHeader({
    required this.title,
    required this.hasEntries,
    required this.onCopyAll,
    required this.onScrollToBottom,
    required this.onClearLog,
  });

  /// Whether at least one log line is present.
  final bool hasEntries;

  /// Callback to clear the log buffer and file.
  final VoidCallback onClearLog;

  /// Callback to copy the full log text to the clipboard.
  final VoidCallback onCopyAll;

  /// Callback to jump to the bottom of the log list.
  final VoidCallback onScrollToBottom;

  /// Dialog title string.
  final String title;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(child: Text(title)),
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
  AppLogger.info(LogTag.ui, 'Opened Diagnostic Log viewer');
  return showDialog<void>(
    context: context,
    builder: (_) => const LogViewerDialog(),
  );
}
