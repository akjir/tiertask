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

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/log_viewer_providers.dart';
import '../../providers/shell_providers.dart';
import '../../services/app_logger.dart';
import '../layout/ui_page_header.dart';
import '../primitives/ui_banner.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';

/// Sentinel dropdown option value matching all diagnostic subsystems.
const String _allSubsystemsValue = '__all__';

/// Pixel distance from the end of the log console within which auto-follow stays engaged.
const double _endProximityThreshold = 4.0;

/// Minimum available body width required to place the log toolbar inline with the page heading.
const double _inlineToolbarBreakpoint = 960.0;

/// Minimum body height for flex-expanded layout before falling back to outer vertical scrolling.
const double _minFlexBodyHeight = 520.0;

/// Full-height diagnostic log view with metadata summary, level/subsystem filters,
/// selectable severity-tinted monospace console, auto-scroll to end, and WebDAV/clipboard/scroll/clear actions (`U-UX-007`).
class LogViewerView extends ConsumerStatefulWidget {
  /// Creates a [LogViewerView].
  const LogViewerView({super.key});

  @override
  ConsumerState<LogViewerView> createState() => _LogViewerViewState();
}

/// Wraps a fixed-width vertically scrolling child in pinned vertical/horizontal [Scrollbar]s and a multi-line [SelectionArea].
class _DualAxisScrollRegion extends StatelessWidget {
  /// Creates a [_DualAxisScrollRegion].
  const _DualAxisScrollRegion({
    required this.contentWidth,
    required this.horizontalController,
    required this.onVerticalMetricsChanged,
    required this.onVerticalScroll,
    required this.selectionDelegate,
    required this.verticalController,
    required this.child,
  });

  /// Vertically scrollable content sized to [contentWidth].
  final Widget child;

  /// Finite width allocated inside the horizontal scroll viewport.
  final double contentWidth;

  /// Horizontal scroll controller.
  final ScrollController horizontalController;

  /// Notification callback observing vertical scroll extent changes.
  final NotificationListenerCallback<ScrollMetricsNotification>
  onVerticalMetricsChanged;

  /// Notification callback observing vertical user scroll updates.
  final NotificationListenerCallback<ScrollNotification> onVerticalScroll;

  /// Delegate joining multi-line console text selections with newline separators.
  final SelectionContainerDelegate selectionDelegate;

  /// Vertical scroll controller.
  final ScrollController verticalController;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: onVerticalMetricsChanged,
      child: NotificationListener<ScrollNotification>(
        onNotification: onVerticalScroll,
        child: Scrollbar(
          controller: verticalController,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.vertical,
          child: Scrollbar(
            controller: horizontalController,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SelectionArea(
              child: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentWidth,
                  child: SelectionContainer(
                    delegate: selectionDelegate,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
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

/// Bidirectionally scrollable selectable flat monospace console rendering filtered diagnostic log rows.
class _LogConsolePanel extends StatelessWidget {
  /// Creates a [_LogConsolePanel].
  const _LogConsolePanel({
    super.key,
    required this.emptyHint,
    required this.horizontalController,
    required this.lines,
    required this.onVerticalMetricsChanged,
    required this.onVerticalScroll,
    required this.verticalController,
  });

  /// Plain-text message rendered when [lines] is empty.
  final String emptyHint;

  /// Horizontal scroll controller shared by the console viewport and scrollbar.
  final ScrollController horizontalController;

  /// Filtered diagnostic log rows to display.
  final List<DiagnosticLogLine> lines;

  /// Notification callback observing vertical scroll extent changes.
  final NotificationListenerCallback<ScrollMetricsNotification>
  onVerticalMetricsChanged;

  /// Notification callback observing vertical user scroll updates.
  final NotificationListenerCallback<ScrollNotification> onVerticalScroll;

  /// Vertical scroll controller shared by the lazy list and `Scroll to Top` action.
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
                horizontalController: horizontalController,
                lines: lines,
                onVerticalMetricsChanged: onVerticalMetricsChanged,
                onVerticalScroll: onVerticalScroll,
                verticalController: verticalController,
              ),
      ),
    );
  }
}

/// Inner horizontal and vertical scrollable selectable list for [_LogConsolePanel].
class _LogConsoleScrollView extends StatefulWidget {
  /// Creates a [_LogConsoleScrollView].
  const _LogConsoleScrollView({
    required this.horizontalController,
    required this.lines,
    required this.onVerticalMetricsChanged,
    required this.onVerticalScroll,
    required this.verticalController,
  });

  /// Horizontal scroll controller for wide diagnostic lines.
  final ScrollController horizontalController;

  /// Non-empty filtered diagnostic log entries.
  final List<DiagnosticLogLine> lines;

  /// Notification callback observing vertical scroll extent changes.
  final NotificationListenerCallback<ScrollMetricsNotification>
  onVerticalMetricsChanged;

  /// Notification callback observing vertical user scroll updates.
  final NotificationListenerCallback<ScrollNotification> onVerticalScroll;

  /// Vertical scroll controller for the lazy `ListView.builder`.
  final ScrollController verticalController;

  @override
  State<_LogConsoleScrollView> createState() => _LogConsoleScrollViewState();
}

/// Owns the newline-preserving selection delegate for [_LogConsoleScrollView].
class _LogConsoleScrollViewState extends State<_LogConsoleScrollView> {
  final _LogLineSelectionDelegate _selectionDelegate =
      _LogLineSelectionDelegate();

  @override
  void dispose() {
    _selectionDelegate.dispose();
    super.dispose();
  }

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
          lines: widget.lines,
          style: baseStyle,
          textScaler: textScaler,
          viewportWidth: constraints.maxWidth,
        );
        return _DualAxisScrollRegion(
          contentWidth: contentWidth,
          horizontalController: widget.horizontalController,
          onVerticalMetricsChanged: widget.onVerticalMetricsChanged,
          onVerticalScroll: widget.onVerticalScroll,
          selectionDelegate: _selectionDelegate,
          verticalController: widget.verticalController,
          child: ListView.builder(
            controller: widget.verticalController,
            padding: const EdgeInsets.all(10.0),
            itemCount: widget.lines.length,
            itemBuilder: (context, index) => _LogLineRow(
              key: ValueKey<String>('log_line_$index'),
              line: widget.lines[index],
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

  /// Active minimum [LogLevel] filter.
  final LogLevel minimumLevel;

  /// Callback invoked when the user chooses a new minimum severity threshold.
  final ValueChanged<LogLevel> onLevelChanged;

  /// Callback invoked when the user chooses a subsystem tag or `null` for all.
  final ValueChanged<LogTag?> onTagChanged;

  /// Active subsystem [LogTag] filter, or `null` for all subsystems.
  final LogTag? selectedTag;

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

  /// Cached immutable select options for all [LogLevel] severity levels.
  static final List<UiSelectOption> _levelOptions =
      List<UiSelectOption>.unmodifiable(<UiSelectOption>[
        for (final level in LogLevel.values)
          UiSelectOption(value: level.name, label: level.label),
      ]);

  /// Currently selected minimum log level.
  final LogLevel minimumLevel;

  /// Callback invoked on level selection change.
  final ValueChanged<LogLevel> onLevelChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return UiField(
      key: const ValueKey<String>('log_viewer_level_filter'),
      kind: UiFieldKind.select,
      label: localizations.logLevelLabel,
      selectValue: minimumLevel.name,
      selectOptions: _levelOptions,
      onSelectChanged: (rawValue) {
        final parsed = _parseLogLevel(rawValue);
        if (parsed != null) {
          onLevelChanged(parsed);
        }
      },
    );
  }
}

/// Single severity-tinted monospace diagnostic log line inside [_LogConsoleScrollView].
class _LogLineRow extends StatefulWidget {
  /// Creates a [_LogLineRow].
  const _LogLineRow({super.key, required this.line});

  /// Formatted diagnostic log entry with pre-classified severity.
  final DiagnosticLogLine line;

  @override
  State<_LogLineRow> createState() => _LogLineRowState();
}

/// Row-level selection delegate appending a newline when selection reaches the end of a log line.
final class _LogLineRowSelectionDelegate
    extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    if (content == null || content.plainText.isEmpty) {
      return null;
    }
    final range = getSelection();
    if (range != null &&
        math.max(range.startOffset, range.endOffset) >= contentLength) {
      return SelectedContent(plainText: '${content.plainText}\n');
    }
    return content;
  }
}

/// Owns the per-row selection delegate and severity styling for [_LogLineRow].
class _LogLineRowState extends State<_LogLineRow> {
  final _LogLineRowSelectionDelegate _selectionDelegate =
      _LogLineRowSelectionDelegate();

  @override
  void dispose() {
    _selectionDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final styleSpec = _resolveStyle(tokens);

    return SelectionContainer(
      delegate: _selectionDelegate,
      child: Padding(
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
            widget.line.text,
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
      ),
    );
  }

  /// Resolves foreground color, optional background tint, and weight for [widget.line].
  ({Color? backgroundColor, Color foregroundColor, FontWeight fontWeight})
  _resolveStyle(UiThemeTokens tokens) {
    final colors = tokens.colors;
    final isMetaHeader =
        widget.line.text.startsWith('@meta ') ||
        widget.line.text.startsWith('===');
    return switch (widget.line.severity) {
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

/// Console-level selection delegate trimming the trailing newline from completed log-line selections.
final class _LogLineSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    if (content == null || content.plainText.isEmpty) {
      return null;
    }
    final text = content.plainText;
    if (text.endsWith('\n')) {
      return SelectedContent(plainText: text.substring(0, text.length - 1));
    }
    return content;
  }
}

/// Compact inset card displaying active log session metadata and severity counters.
class _LogMetadataSummaryCard extends StatelessWidget {
  /// Creates a [_LogMetadataSummaryCard].
  const _LogMetadataSummaryCard({required this.snapshot});

  /// Live diagnostic snapshot carrying [DiagnosticLogSnapshot.headerSummary] and counts.
  final DiagnosticLogSnapshot snapshot;

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
            snapshot.headerSummary,
            style: tokens.typography.monoSmall.copyWith(color: colors.ink),
          ),
          SizedBox(height: tokens.spacing.space1),
          Text(
            localizations.logMetadataStats(
              snapshot.totalEntries.toString(),
              snapshot.warningCount.toString(),
              snapshot.errorCount.toString(),
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
  final ValueChanged<LogTag?> onTagChanged;

  /// Currently selected subsystem tag, or `null` for all subsystems.
  final LogTag? selectedTag;

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
        for (final tag in LogTag.values)
          UiSelectOption(value: tag.name, label: tag.label),
      ],
      onSelectChanged: (rawValue) {
        if (rawValue == _allSubsystemsValue) {
          onTagChanged(null);
          return;
        }
        onTagChanged(_parseLogTag(rawValue));
      },
    );
  }
}

/// Toolbar action cluster (`Upload Log`, `Copy All`, `Copy Filtered`, `Scroll to Top`, `Clear`).
class _LogToolbarActions extends StatelessWidget {
  /// Creates a [_LogToolbarActions].
  const _LogToolbarActions({
    required this.isUploading,
    required this.onClearLog,
    required this.onCopyAll,
    required this.onCopyFiltered,
    required this.onScrollToTop,
    required this.onUploadLog,
    required this.snapshot,
  });

  /// Whether a manual WebDAV log upload is currently in flight.
  final bool isUploading;

  /// Callback clearing buffered diagnostic entries.
  final VoidCallback onClearLog;

  /// Callback copying full diagnostic log text to clipboard.
  final VoidCallback onCopyAll;

  /// Callback copying only the currently filtered diagnostic log entries to clipboard.
  final VoidCallback onCopyFiltered;

  /// Callback jumping vertical console scroll to the topmost entry.
  final VoidCallback onScrollToTop;

  /// Callback uploading the active diagnostic log to WebDAV.
  final VoidCallback onUploadLog;

  /// Live diagnostic snapshot providing buffer availability and WebDAV sync status.
  final DiagnosticLogSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final hasFilteredLines = snapshot.filteredLines.isNotEmpty;

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: <Widget>[
        if (snapshot.canSyncWebDav)
          _LogUploadToolbarButton(
            isUploading: isUploading,
            onUploadLog: onUploadLog,
          ),
        UiButton(
          key: const ValueKey<String>('log_viewer_copy_button'),
          label: localizations.tooltipCopyLog,
          leadingIcon: Icons.copy_all_outlined,
          density: UiButtonDensity.compact,
          onPressed: snapshot.hasEntries ? onCopyAll : null,
        ),
        UiButton(
          key: const ValueKey<String>('log_viewer_copy_filtered_button'),
          label: localizations.tooltipCopyFilteredLog,
          leadingIcon: Icons.copy_outlined,
          density: UiButtonDensity.compact,
          onPressed: hasFilteredLines ? onCopyFiltered : null,
        ),
        UiButton(
          key: const ValueKey<String>('log_viewer_scroll_top_button'),
          label: localizations.tooltipScrollToTop,
          leadingIcon: Icons.vertical_align_top_rounded,
          density: UiButtonDensity.compact,
          onPressed: hasFilteredLines ? onScrollToTop : null,
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
    required this.snapshot,
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
  final ValueChanged<LogLevel> onLevelChanged;

  /// Subsystem tag change callback.
  final ValueChanged<LogTag?> onTagChanged;

  /// Live diagnostic log snapshot.
  final DiagnosticLogSnapshot snapshot;

  /// Toolbar action cluster widget.
  final Widget toolbar;

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
        _LogMetadataSummaryCard(snapshot: snapshot),
        SizedBox(height: tokens.spacing.space3),
        _LogFilterRow(
          minimumLevel: snapshot.minimumLevel,
          selectedTag: snapshot.selectedTag,
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
    required this.snapshot,
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
  final ValueChanged<LogLevel> onLevelChanged;

  /// Subsystem tag change callback.
  final ValueChanged<LogTag?> onTagChanged;

  /// Live diagnostic log snapshot.
  final DiagnosticLogSnapshot snapshot;

  /// Toolbar action cluster widget.
  final Widget toolbar;

  @override
  Widget build(BuildContext context) {
    final minConsoleHeight = UiThemeTokens.of(context).spacing.minConsoleHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final header = _LogViewerHeaderSection(
          inlineToolbar: constraints.maxWidth >= _inlineToolbarBreakpoint,
          snapshot: snapshot,
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

/// Manages console [ScrollController]s, auto-follow state, and upload busy state for [LogViewerView].
class _LogViewerViewState extends ConsumerState<LogViewerView> {
  bool _followEnd = true;
  final ScrollController _horizontalController = ScrollController();
  bool _isProgrammaticVerticalScroll = false;
  bool _isUploading = false;
  bool _scrollToEndScheduled = false;
  final ScrollController _verticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleScrollToEnd();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DiagnosticLogSnapshot>(
      logViewerProvider,
      _handleSnapshotChanged,
    );
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final snapshot = ref.watch(logViewerProvider);
    final notifier = ref.read(logViewerProvider.notifier);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);

    return Padding(
      padding: tokens.spacing.mainContentPadding(viewport),
      child: _LogViewerLayout(
        snapshot: snapshot,
        onBack: _navigateBackToTasks,
        onLevelChanged: notifier.setMinimumLevel,
        onTagChanged: notifier.setSelectedTag,
        toolbar: _LogToolbarActions(
          isUploading: _isUploading,
          onClearLog: _clearLog,
          onCopyAll: _handleCopyAll,
          onCopyFiltered: _handleCopyFiltered,
          onScrollToTop: _scrollToTop,
          onUploadLog: _handleUploadLog,
          snapshot: snapshot,
        ),
        console: _LogConsolePanel(
          key: const ValueKey<String>('log_viewer_console'),
          emptyHint: localizations.emptyLogHint,
          horizontalController: _horizontalController,
          lines: snapshot.filteredLines,
          onVerticalMetricsChanged: _handleVerticalMetricsNotification,
          onVerticalScroll: _handleVerticalScrollNotification,
          verticalController: _verticalController,
        ),
      ),
    );
  }

  /// Clears buffered diagnostic entries and emits a confirmation floating notice.
  void _clearLog() {
    final localizations = AppLocalizations.of(context);
    ref.read(logViewerProvider.notifier).clearLog();
    ref
        .read(floatingNoticeProvider.notifier)
        .showNotice(
          localizations.logClearedSnackBar,
          tone: FloatingNoticeTone.neutral,
        );
  }

  /// Copies the complete diagnostic log text to the system clipboard.
  Future<void> _copyAll() {
    final localizations = AppLocalizations.of(context);
    final fullText = ref.read(logViewerProvider.notifier).readFullLogText();
    return _copyTextToClipboard(
      fullText,
      notice: localizations.logCopiedSnackBar,
    );
  }

  /// Copies the currently filtered diagnostic log entries to the system clipboard.
  Future<void> _copyFiltered() {
    final localizations = AppLocalizations.of(context);
    final filteredText = ref
        .read(logViewerProvider.notifier)
        .readFilteredLogText();
    return _copyTextToClipboard(
      filteredText,
      notice: localizations.logFilteredCopiedSnackBar,
    );
  }

  /// Writes [text] to the system clipboard and announces [notice] if still mounted.
  Future<void> _copyTextToClipboard(
    String text, {
    required String notice,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ref
        .read(floatingNoticeProvider.notifier)
        .showNotice(notice, tone: FloatingNoticeTone.success);
  }

  /// Triggers [_copyAll] safely from synchronous button tap callbacks.
  void _handleCopyAll() {
    unawaited(_copyAll());
  }

  /// Triggers [_copyFiltered] safely from synchronous button tap callbacks.
  void _handleCopyFiltered() {
    unawaited(_copyFiltered());
  }

  /// Keeps the console anchored to the latest entries when logs load, filters change, or new lines arrive.
  void _handleSnapshotChanged(
    DiagnosticLogSnapshot? previous,
    DiagnosticLogSnapshot next,
  ) {
    if (next.filteredLines.isEmpty) {
      _followEnd = true;
      return;
    }
    final filtersChanged =
        previous != null &&
        (previous.minimumLevel != next.minimumLevel ||
            previous.selectedTag != next.selectedTag);
    final becameNonEmpty = previous == null || previous.filteredLines.isEmpty;
    if (filtersChanged || becameNonEmpty) {
      _followEnd = true;
      _scheduleScrollToEnd();
      return;
    }
    if (_followEnd && previous.filteredLines != next.filteredLines) {
      _scheduleScrollToEnd();
    }
  }

  /// Triggers [_uploadLog] safely from synchronous button tap callbacks.
  void _handleUploadLog() {
    unawaited(_uploadLog());
  }

  /// Re-anchors the vertical viewport when content or viewport extent changes while following the end.
  bool _handleVerticalMetricsNotification(
    ScrollMetricsNotification notification,
  ) {
    if (notification.metrics.axis != Axis.vertical || !_followEnd) {
      return false;
    }
    if (notification.metrics.maxScrollExtent - notification.metrics.pixels >
        0.5) {
      _scheduleScrollToEnd();
    }
    return false;
  }

  /// Tracks whether the user remains anchored near the end of the vertical log list.
  bool _handleVerticalScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical ||
        _isProgrammaticVerticalScroll) {
      return false;
    }
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      final distanceFromEnd =
          notification.metrics.maxScrollExtent - notification.metrics.pixels;
      _followEnd = distanceFromEnd <= _endProximityThreshold;
    }
    return false;
  }

  /// Jumps the vertical console immediately to its bottommost extent when auto-follow is active.
  void _jumpToEnd() {
    if (!mounted || !_followEnd || _verticalController.positions.length != 1) {
      return;
    }
    final position = _verticalController.position;
    final target = position.maxScrollExtent;
    if ((target - position.pixels).abs() > 0.5) {
      _jumpVertical(target);
    }
  }

  /// Jumps [_verticalController] to [offset] without altering [_followEnd] via user-scroll listeners.
  void _jumpVertical(double offset) {
    if (_verticalController.positions.length != 1) {
      return;
    }
    _isProgrammaticVerticalScroll = true;
    try {
      _verticalController.jumpTo(offset);
    } finally {
      _isProgrammaticVerticalScroll = false;
    }
  }

  /// Returns to the primary Tasks shell view.
  void _navigateBackToTasks() {
    ref.read(shellProvider.notifier).openView(ShellView.tasks);
  }

  /// Schedules a single post-frame vertical jump to the latest log entry.
  void _scheduleScrollToEnd() {
    if (_scrollToEndScheduled) {
      return;
    }
    _scrollToEndScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToEndScheduled = false;
      _jumpToEnd();
    });
  }

  /// Scrolls the vertical log list immediately to its topmost entry.
  void _scrollToTop() {
    if (_verticalController.positions.length != 1) {
      return;
    }
    if (_verticalController.position.maxScrollExtent > 0.0) {
      _followEnd = false;
    }
    _jumpVertical(0.0);
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
          .read(logViewerProvider.notifier)
          .syncLogToWebDav();
      if (!mounted) {
        return;
      }
      final noticeNotifier = ref.read(floatingNoticeProvider.notifier);
      switch (result) {
        case LogSyncSucceeded():
          noticeNotifier.showNotice(
            localizations.logSyncedSnackBar,
            tone: FloatingNoticeTone.success,
          );
        case LogSyncFailed(:final message):
          noticeNotifier.showNotice(message, tone: FloatingNoticeTone.danger);
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
  required List<DiagnosticLogLine> lines,
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

/// Maps a serialized [LogLevel.name] string back to its enum value.
LogLevel? _parseLogLevel(String rawValue) {
  for (final level in LogLevel.values) {
    if (level.name == rawValue) {
      return level;
    }
  }
  return null;
}

/// Maps a serialized [LogTag.name] string back to its enum value.
LogTag? _parseLogTag(String rawValue) {
  for (final tag in LogTag.values) {
    if (tag.name == rawValue) {
      return tag;
    }
  }
  return null;
}
