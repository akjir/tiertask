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
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/app_shell_controller.dart';
import '../../presentation/floating_notice_controller.dart';
import '../../presentation/log_viewer_controller.dart';
import '../../presentation/shell_models.dart';

const String _allSubsystemsValue = '__all__';

/// Minimum available body width required to place the log toolbar inline with the page heading.
const double _inlineToolbarBreakpoint = 760.0;

/// Minimum body height for flex-expanded layout before falling back to outer vertical scrolling.
const double _minFlexBodyHeight = 520.0;

/// Full-height diagnostic log view with metadata summary, level/subsystem filters,
/// severity-tinted monospace console, and WebDAV/clipboard/scroll/clear actions (`U-UX-007`).
class LogViewerView extends ConsumerStatefulWidget {
  /// Creates a [LogViewerView].
  const LogViewerView({super.key});

  @override
  ConsumerState<LogViewerView> createState() => _LogViewerViewState();
}

/// Wraps a fixed-width vertically scrolling child in pinned vertical and horizontal [Scrollbar]s.
class _DualAxisScrollRegion extends StatelessWidget {
  /// Creates a [_DualAxisScrollRegion].
  const _DualAxisScrollRegion({
    required this.horizontalController,
    required this.verticalController,
    required this.contentWidth,
    required this.child,
  });

  /// Vertically scrollable content sized to [contentWidth].
  final Widget child;

  /// Finite width allocated inside the horizontal scroll viewport.
  final double contentWidth;

  /// Horizontal scroll controller.
  final ScrollController horizontalController;

  /// Vertical scroll controller.
  final ScrollController verticalController;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: verticalController,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.vertical,
      child: Scrollbar(
        controller: horizontalController,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: horizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: contentWidth, child: child),
        ),
      ),
    );
  }
}

/// Danger-styled Clear button clearing buffered diagnostic log entries.
class _LogClearToolbarButton extends StatelessWidget {
  /// Creates a [_LogClearToolbarButton].
  const _LogClearToolbarButton({required this.onClearLog});

  /// Callback clearing buffered diagnostic entries.
  final VoidCallback onClearLog;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      key: const ValueKey<String>('log_viewer_clear_button'),
      label: localizations.logActionClear,
      leadingIcon: Icons.delete_outline_rounded,
      variant: UiButtonVariant.danger,
      density: UiButtonDensity.compact,
      onPressed: onClearLog,
    );
  }
}

/// Bidirectionally scrollable flat monospace console rendering filtered diagnostic log rows.
class _LogConsolePanel extends StatelessWidget {
  /// Creates a [_LogConsolePanel].
  const _LogConsolePanel({
    super.key,
    required this.lines,
    required this.emptyHint,
    required this.horizontalController,
    required this.verticalController,
  });

  /// Plain-text message rendered when [lines] is empty.
  final String emptyHint;

  /// Horizontal scroll controller shared by the console viewport and scrollbar.
  final ScrollController horizontalController;

  /// Filtered diagnostic log rows to display.
  final List<DiagnosticLogLineViewModel> lines;

  /// Vertical scroll controller shared by the lazy list and `Scroll to Bottom` action.
  final ScrollController verticalController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(tokens.radii.card),
        border: Border.all(color: colors.line, width: tokens.radii.borderWidth),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radii.card),
        child: lines.isEmpty
            ? UiBanner(variant: UiBannerVariant.emptyState, message: emptyHint)
            : _LogConsoleScrollView(
                lines: lines,
                horizontalController: horizontalController,
                verticalController: verticalController,
              ),
      ),
    );
  }
}

/// Inner horizontal and vertical scrollable list for [_LogConsolePanel].
class _LogConsoleScrollView extends StatelessWidget {
  /// Creates a [_LogConsoleScrollView].
  const _LogConsoleScrollView({
    required this.lines,
    required this.horizontalController,
    required this.verticalController,
  });

  /// Horizontal scroll controller for wide diagnostic lines.
  final ScrollController horizontalController;

  /// Non-empty filtered diagnostic log entries.
  final List<DiagnosticLogLineViewModel> lines;

  /// Vertical scroll controller for the lazy `ListView.builder`.
  final ScrollController verticalController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final baseStyle = UiTypographyTokens.mono(
      tokens.typography.meta.copyWith(height: 1.5),
    );
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = _computeLogContentWidth(
          lines: lines,
          style: baseStyle,
          textScaler: textScaler,
          viewportWidth: constraints.maxWidth,
        );
        return _DualAxisScrollRegion(
          horizontalController: horizontalController,
          verticalController: verticalController,
          contentWidth: contentWidth,
          child: ListView.builder(
            controller: verticalController,
            padding: const EdgeInsets.all(10.0),
            itemCount: lines.length,
            itemBuilder: (context, index) => _LogLineRow(
              key: ValueKey<String>('log_line_$index'),
              line: lines[index],
            ),
          ),
        );
      },
    );
  }
}

/// Compact two-select filter bar for minimum severity level and diagnostic subsystem.
class _LogFilterRow extends StatelessWidget {
  /// Creates a [_LogFilterRow].
  const _LogFilterRow({
    required this.minimumLevel,
    required this.selectedTag,
    required this.onLevelChanged,
    required this.onTagChanged,
  });

  /// Active minimum [DiagnosticLogLevel] filter.
  final DiagnosticLogLevel minimumLevel;

  /// Callback invoked when the user chooses a new minimum severity threshold.
  final ValueChanged<DiagnosticLogLevel> onLevelChanged;

  /// Callback invoked when the user chooses a subsystem tag or `null` for all.
  final ValueChanged<DiagnosticLogTag?> onTagChanged;

  /// Active subsystem [DiagnosticLogTag] filter, or `null` for all subsystems.
  final DiagnosticLogTag? selectedTag;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _LogLevelFilterField(
                minimumLevel: minimumLevel,
                onLevelChanged: onLevelChanged,
              ),
            ),
            SizedBox(width: tokens.spacing.space3),
            Expanded(
              child: _LogSubsystemFilterField(
                selectedTag: selectedTag,
                onTagChanged: onTagChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimum severity dropdown control for [_LogFilterRow].
class _LogLevelFilterField extends StatelessWidget {
  /// Creates a [_LogLevelFilterField].
  const _LogLevelFilterField({
    required this.minimumLevel,
    required this.onLevelChanged,
  });

  /// Currently selected minimum log level.
  final DiagnosticLogLevel minimumLevel;

  /// Callback invoked on level selection change.
  final ValueChanged<DiagnosticLogLevel> onLevelChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiField(
      key: const ValueKey<String>('log_viewer_level_filter'),
      kind: UiFieldKind.select,
      label: localizations.logLevelLabel,
      selectValue: minimumLevel.name,
      selectOptions: <UiSelectOption>[
        for (final level in DiagnosticLogLevel.values)
          UiSelectOption(value: level.name, label: level.label),
      ],
      onSelectChanged: (rawValue) {
        final parsed = _parseDiagnosticLogLevel(rawValue);
        if (parsed != null) {
          onLevelChanged(parsed);
        }
      },
    );
  }
}

/// Single severity-tinted monospace diagnostic log line inside [_LogConsoleScrollView].
class _LogLineRow extends StatelessWidget {
  /// Creates a [_LogLineRow].
  const _LogLineRow({super.key, required this.line});

  /// Formatted diagnostic log entry with pre-classified severity.
  final DiagnosticLogLineViewModel line;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final styleSpec = _resolveStyle(tokens);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
        decoration: styleSpec.backgroundColor != null
            ? BoxDecoration(
                color: styleSpec.backgroundColor,
                borderRadius: BorderRadius.circular(tokens.radii.dotLg),
              )
            : null,
        child: Text(
          line.text,
          softWrap: false,
          style: UiTypographyTokens.mono(
            tokens.typography.meta.copyWith(
              height: 1.5,
              color: styleSpec.foregroundColor,
              fontWeight: styleSpec.fontWeight,
            ),
          ),
        ),
      ),
    );
  }

  /// Resolves foreground color, optional background tint, and weight for [line].
  ({Color? backgroundColor, Color foregroundColor, FontWeight fontWeight})
  _resolveStyle(UiThemeTokens tokens) {
    final colors = tokens.colors;
    final isMetaHeader =
        line.text.startsWith('@meta ') || line.text.startsWith('===');
    return switch (line.severity) {
      DiagnosticLogSeverity.crash => (
        backgroundColor: colors.dangerBg,
        foregroundColor: colors.danger,
        fontWeight: FontWeight.w700,
      ),
      DiagnosticLogSeverity.error => (
        backgroundColor: colors.dangerBg,
        foregroundColor: colors.danger,
        fontWeight: FontWeight.w600,
      ),
      DiagnosticLogSeverity.warn => (
        backgroundColor: colors.warningBg,
        foregroundColor: colors.warning,
        fontWeight: FontWeight.w600,
      ),
      DiagnosticLogSeverity.normal => (
        backgroundColor: null,
        foregroundColor: isMetaHeader ? colors.muted : colors.ink,
        fontWeight: FontWeight.w400,
      ),
    };
  }
}

/// Compact inset card displaying active log session metadata and severity counters.
class _LogMetadataSummaryCard extends StatelessWidget {
  /// Creates a [_LogMetadataSummaryCard].
  const _LogMetadataSummaryCard({required this.viewModel});

  /// Live diagnostic view model carrying [DiagnosticLogViewModel.headerSummary] and counts.
  final DiagnosticLogViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return UiCard.inset(
      key: const ValueKey<String>('log_viewer_metadata_card'),
      padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SelectableText(
            viewModel.headerSummary,
            style: tokens.typography.monoSmall.copyWith(color: colors.ink),
          ),
          SizedBox(height: tokens.spacing.space1),
          Text(
            localizations.logMetadataStats(
              viewModel.totalEntries.toString(),
              viewModel.warningCount.toString(),
              viewModel.errorCount.toString(),
            ),
            style: UiTypographyTokens.tabular(
              tokens.typography.meta.copyWith(color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Subsystem tag dropdown control for [_LogFilterRow].
class _LogSubsystemFilterField extends StatelessWidget {
  /// Creates a [_LogSubsystemFilterField].
  const _LogSubsystemFilterField({
    required this.selectedTag,
    required this.onTagChanged,
  });

  /// Callback invoked on subsystem tag change (`null` for all).
  final ValueChanged<DiagnosticLogTag?> onTagChanged;

  /// Currently selected subsystem tag, or `null` for all subsystems.
  final DiagnosticLogTag? selectedTag;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiField(
      key: const ValueKey<String>('log_viewer_subsystem_filter'),
      kind: UiFieldKind.select,
      label: localizations.logFilterSubsystemLabel,
      selectValue: selectedTag?.name ?? _allSubsystemsValue,
      selectOptions: <UiSelectOption>[
        UiSelectOption(
          value: _allSubsystemsValue,
          label: localizations.logFilterAllTags,
        ),
        for (final tag in DiagnosticLogTag.values)
          UiSelectOption(value: tag.name, label: tag.label),
      ],
      onSelectChanged: (rawValue) {
        if (rawValue == _allSubsystemsValue) {
          onTagChanged(null);
          return;
        }
        onTagChanged(_parseDiagnosticLogTag(rawValue));
      },
    );
  }
}

/// Toolbar action cluster (`Upload Log`, `Copy All`, `Scroll to Bottom`, `Clear`).
class _LogToolbarActions extends StatelessWidget {
  /// Creates a [_LogToolbarActions].
  const _LogToolbarActions({
    required this.canSyncWebDav,
    required this.hasEntries,
    required this.hasFilteredLines,
    required this.isUploading,
    required this.onUploadLog,
    required this.onCopyAll,
    required this.onScrollToBottom,
    required this.onClearLog,
  });

  /// Whether manual WebDAV diagnostic log upload is enabled and configured.
  final bool canSyncWebDav;

  /// Whether at least one line exists in the diagnostic log buffer.
  final bool hasEntries;

  /// Whether at least one filtered line is rendered in the console.
  final bool hasFilteredLines;

  /// Whether a manual WebDAV log upload is currently in flight.
  final bool isUploading;

  /// Callback clearing buffered diagnostic entries.
  final VoidCallback onClearLog;

  /// Callback copying full diagnostic log text to clipboard.
  final VoidCallback onCopyAll;

  /// Callback jumping vertical console scroll to the bottommost entry.
  final VoidCallback onScrollToBottom;

  /// Callback uploading the active diagnostic log to WebDAV.
  final VoidCallback onUploadLog;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: <Widget>[
        if (canSyncWebDav)
          _LogUploadToolbarButton(
            isUploading: isUploading,
            onUploadLog: onUploadLog,
          ),
        UiButton(
          key: const ValueKey<String>('log_viewer_copy_button'),
          label: localizations.tooltipCopyLog,
          leadingIcon: Icons.copy_outlined,
          density: UiButtonDensity.compact,
          onPressed: hasEntries ? onCopyAll : null,
        ),
        UiButton(
          key: const ValueKey<String>('log_viewer_scroll_bottom_button'),
          label: localizations.tooltipScrollToBottom,
          leadingIcon: Icons.vertical_align_bottom_rounded,
          density: UiButtonDensity.compact,
          onPressed: hasFilteredLines ? onScrollToBottom : null,
        ),
        _LogClearToolbarButton(onClearLog: onClearLog),
      ],
    );
  }
}

/// WebDAV upload trigger button rendered when remote diagnostic sync is enabled.
class _LogUploadToolbarButton extends StatelessWidget {
  /// Creates a [_LogUploadToolbarButton].
  const _LogUploadToolbarButton({
    required this.isUploading,
    required this.onUploadLog,
  });

  /// Whether a manual WebDAV log upload is currently in flight.
  final bool isUploading;

  /// Callback uploading the active diagnostic log to WebDAV.
  final VoidCallback onUploadLog;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      key: const ValueKey<String>('log_viewer_upload_button'),
      label: localizations.logActionUpload,
      leadingIcon: Icons.cloud_upload_outlined,
      density: UiButtonDensity.compact,
      isLoading: isUploading,
      onPressed: isUploading ? null : onUploadLog,
    );
  }
}

/// Header, optional wrapped toolbar, metadata card, and filter row above the log console.
class _LogViewerHeaderSection extends StatelessWidget {
  /// Creates a [_LogViewerHeaderSection].
  const _LogViewerHeaderSection({
    required this.inlineToolbar,
    required this.viewModel,
    required this.toolbar,
    required this.onBack,
    required this.onLevelChanged,
    required this.onTagChanged,
  });

  /// Whether [toolbar] renders inline inside [UiPageHeader.trailing].
  final bool inlineToolbar;

  /// Back navigation callback returning to Tasks.
  final VoidCallback onBack;

  /// Minimum log level change callback.
  final ValueChanged<DiagnosticLogLevel> onLevelChanged;

  /// Subsystem tag change callback.
  final ValueChanged<DiagnosticLogTag?> onTagChanged;

  /// Toolbar action cluster widget.
  final Widget toolbar;

  /// Live diagnostic log view model.
  final DiagnosticLogViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiPageHeader(
          backLabel: localizations.actionBackToTasks,
          onBack: onBack,
          title: localizations.diagnosticLogTitle,
          subtitle: localizations.logViewerSubtitle,
          trailing: inlineToolbar ? toolbar : null,
        ),
        if (!inlineToolbar) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          toolbar,
        ],
        SizedBox(height: tokens.spacing.space3),
        _LogMetadataSummaryCard(viewModel: viewModel),
        SizedBox(height: tokens.spacing.space3),
        _LogFilterRow(
          minimumLevel: viewModel.minimumLevel,
          selectedTag: viewModel.selectedTag,
          onLevelChanged: onLevelChanged,
          onTagChanged: onTagChanged,
        ),
        SizedBox(height: tokens.spacing.space3),
      ],
    );
  }
}

/// Adaptive header, metadata, filters, and flex console column for [LogViewerView].
class _LogViewerLayout extends StatelessWidget {
  /// Creates a [_LogViewerLayout].
  const _LogViewerLayout({
    required this.viewModel,
    required this.toolbar,
    required this.console,
    required this.onBack,
    required this.onLevelChanged,
    required this.onTagChanged,
  });

  /// Console panel widget.
  final Widget console;

  /// Back navigation callback returning to Tasks.
  final VoidCallback onBack;

  /// Minimum log level change callback.
  final ValueChanged<DiagnosticLogLevel> onLevelChanged;

  /// Subsystem tag change callback.
  final ValueChanged<DiagnosticLogTag?> onTagChanged;

  /// Toolbar action cluster widget.
  final Widget toolbar;

  /// Live diagnostic log view model.
  final DiagnosticLogViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final minConsoleHeight = UiThemeTokens.of(context).spacing.minConsoleHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final header = _LogViewerHeaderSection(
          inlineToolbar: constraints.maxWidth >= _inlineToolbarBreakpoint,
          viewModel: viewModel,
          toolbar: toolbar,
          onBack: onBack,
          onLevelChanged: onLevelChanged,
          onTagChanged: onTagChanged,
        );
        if (constraints.maxHeight < _minFlexBodyHeight) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                header,
                SizedBox(height: minConsoleHeight, child: console),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minConsoleHeight),
                child: console,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Manages horizontal/vertical console [ScrollController]s and upload busy state for [LogViewerView].
class _LogViewerViewState extends ConsumerState<LogViewerView> {
  final ScrollController _horizontalController = ScrollController();
  bool _isUploading = false;
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
    final tokens = UiThemeTokens.of(context);
    final viewModel = ref.watch(logViewerControllerProvider);
    final controller = ref.read(logViewerControllerProvider.notifier);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);

    return Padding(
      padding: tokens.spacing.mainContentPadding(viewport),
      child: _LogViewerLayout(
        viewModel: viewModel,
        onBack: _navigateBackToTasks,
        onLevelChanged: controller.setMinimumLevel,
        onTagChanged: controller.setSelectedTag,
        toolbar: _LogToolbarActions(
          canSyncWebDav: viewModel.canSyncWebDav,
          hasEntries: viewModel.hasEntries,
          hasFilteredLines: viewModel.filteredLines.isNotEmpty,
          isUploading: _isUploading,
          onUploadLog: _handleUploadLog,
          onCopyAll: _handleCopyAll,
          onScrollToBottom: _scrollToBottom,
          onClearLog: _clearLog,
        ),
        console: _LogConsolePanel(
          key: const ValueKey<String>('log_viewer_console'),
          lines: viewModel.filteredLines,
          emptyHint: localizations.emptyLogHint,
          horizontalController: _horizontalController,
          verticalController: _verticalController,
        ),
      ),
    );
  }

  /// Clears buffered diagnostic entries and emits a confirmation floating notice.
  void _clearLog() {
    final localizations = AppLocalizations.of(context);
    ref.read(logViewerControllerProvider.notifier).clearLog();
    ref
        .read(floatingNoticeControllerProvider.notifier)
        .showNotice(localizations.logClearedSnackBar, tone: NoticeTone.neutral);
  }

  /// Copies the complete diagnostic log text to the system clipboard.
  Future<void> _copyAll() async {
    final localizations = AppLocalizations.of(context);
    final fullText = ref
        .read(logViewerControllerProvider.notifier)
        .readFullLogText();
    await Clipboard.setData(ClipboardData(text: fullText));
    if (!mounted) {
      return;
    }
    ref
        .read(floatingNoticeControllerProvider.notifier)
        .showNotice(localizations.logCopiedSnackBar, tone: NoticeTone.success);
  }

  /// Triggers [_copyAll] safely from synchronous button tap callbacks.
  void _handleCopyAll() {
    unawaited(_copyAll());
  }

  /// Triggers [_uploadLog] safely from synchronous button tap callbacks.
  void _handleUploadLog() {
    unawaited(_uploadLog());
  }

  /// Returns to the primary Tasks shell view.
  void _navigateBackToTasks() {
    ref.read(appShellControllerProvider.notifier).openView(ShellView.tasks);
  }

  /// Scrolls the vertical log list immediately to its bottommost entry.
  void _scrollToBottom() {
    if (!_verticalController.hasClients) {
      return;
    }
    _verticalController.jumpTo(_verticalController.position.maxScrollExtent);
  }

  /// Uploads the active diagnostic log snapshot to WebDAV and announces the outcome.
  Future<void> _uploadLog() async {
    if (_isUploading) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    setState(() => _isUploading = true);
    try {
      final result = await ref
          .read(logViewerControllerProvider.notifier)
          .syncLogToWebDav();
      if (!mounted) {
        return;
      }
      final noticeController = ref.read(
        floatingNoticeControllerProvider.notifier,
      );
      switch (result) {
        case LogSyncSucceeded():
          noticeController.showNotice(
            localizations.logSyncedSnackBar,
            tone: NoticeTone.success,
          );
        case LogSyncFailed(:final message):
          noticeController.showNotice(message, tone: NoticeTone.danger);
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }
}

/// Computes pixel width for horizontal scrolling from the longest line in [lines].
double _computeLogContentWidth({
  required List<DiagnosticLogLineViewModel> lines,
  required TextStyle style,
  required TextScaler textScaler,
  required double viewportWidth,
}) {
  var longestLine = '';
  for (final entry in lines) {
    if (entry.text.length > longestLine.length) {
      longestLine = entry.text;
    }
  }
  if (longestLine.isEmpty) {
    return viewportWidth;
  }
  final painter = TextPainter(
    text: TextSpan(
      text: longestLine,
      style: style.copyWith(fontWeight: FontWeight.w700),
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final measuredWidth = painter.width + 44.0;
  painter.dispose();
  return math.max(viewportWidth, measuredWidth);
}

/// Maps a serialized [DiagnosticLogLevel.name] string back to its enum value.
DiagnosticLogLevel? _parseDiagnosticLogLevel(String rawValue) {
  for (final level in DiagnosticLogLevel.values) {
    if (level.name == rawValue) {
      return level;
    }
  }
  return null;
}

/// Maps a serialized [DiagnosticLogTag.name] string back to its enum value.
DiagnosticLogTag? _parseDiagnosticLogTag(String rawValue) {
  for (final tag in DiagnosticLogTag.values) {
    if (tag.name == rawValue) {
      return tag;
    }
  }
  return null;
}
