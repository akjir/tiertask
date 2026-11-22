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

import 'package:flutter/foundation.dart' show listEquals, setEquals;
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
import '../primitives/ui_pill.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';

/// Minimum body width before compact phone wrapping requires outer vertical scrolling.
const double _compactScrollWidthThreshold = 560.0;

/// Pixel distance from the end of the log console within which auto-follow stays engaged.
const double _endProximityThreshold = 4.0;

/// Shared minimum height for filter section header rows so level and subsystem controls align horizontally.
const double _filterHeaderRowMinHeight = 30.0;

/// Minimum available body width required to place level and subsystem filters side by side.
const double _inlineFilterBreakpoint = 800.0;

/// Minimum available body width required to place log session metadata and stats on one row.
const double _inlineMetadataBreakpoint = 820.0;

/// Minimum available body width required to place the log toolbar inline with the page heading.
const double _inlineToolbarBreakpoint = 960.0;

/// Total width allocated to the left minimum severity column when filters render side by side.
const double _levelFilterColumnWidth = 244.0;

/// Minimum body height for flex-expanded layout at desktop widths (`>= _inlineToolbarBreakpoint`).
const double _minFlexBodyHeight = 520.0;

/// Maximum width allocated to the minimum severity select when filters stack vertically.
const double _stackedLevelFilterMaxWidth = 340.0;

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
class _LogConsolePanel extends ConsumerWidget {
  /// Creates a [_LogConsolePanel].
  const _LogConsolePanel({
    super.key,
    required this.horizontalController,
    required this.onVerticalMetricsChanged,
    required this.onVerticalScroll,
    required this.verticalController,
  });

  /// Horizontal scroll controller shared by the console viewport and scrollbar.
  final ScrollController horizontalController;

  /// Notification callback observing vertical scroll extent changes.
  final NotificationListenerCallback<ScrollMetricsNotification>
  onVerticalMetricsChanged;

  /// Notification callback observing vertical user scroll updates.
  final NotificationListenerCallback<ScrollNotification> onVerticalScroll;

  /// Vertical scroll controller shared by the lazy list and `Scroll to Top` action.
  final ScrollController verticalController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final consoleSlice = ref.watch(
      logViewerProvider.select(_selectLogConsoleSlice),
    );
    final emptyHint = consoleSlice.hasEntries
        ? localizations.emptyFilteredLogHint
        : localizations.emptyLogHint;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(tokens.radii.card),
          border: Border.all(
            color: colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radii.card),
          child: consoleSlice.filteredLines.isEmpty
              ? UiBanner(
                  variant: UiBannerVariant.emptyState,
                  message: emptyHint,
                )
              : _LogConsoleScrollView(
                  horizontalController: horizontalController,
                  lines: consoleSlice.filteredLines,
                  onVerticalMetricsChanged: onVerticalMetricsChanged,
                  onVerticalScroll: onVerticalScroll,
                  verticalController: verticalController,
                ),
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

/// Owns cached text metrics and the newline-preserving selection delegate for [_LogConsoleScrollView].
class _LogConsoleScrollViewState extends State<_LogConsoleScrollView> {
  final _LogLineSelectionDelegate _selectionDelegate =
      _LogLineSelectionDelegate();

  int _cachedLineCount = -1;
  List<DiagnosticLogLine>? _cachedLines;
  double _cachedMeasuredWidth = 0.0;
  double _cachedRowExtent = 25.0;
  TextStyle? _cachedStyle;
  TextScaler? _cachedTextScaler;

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
    final metrics = _resolveMetrics(
      baseStyle,
      MediaQuery.textScalerOf(context),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(
          constraints.maxWidth,
          metrics.measuredWidth,
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
            itemExtent: metrics.rowExtent,
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

  /// Resolves cached horizontal width and fixed vertical row extent for [style] and [textScaler].
  ({double measuredWidth, double rowExtent}) _resolveMetrics(
    TextStyle style,
    TextScaler textScaler,
  ) {
    final lines = widget.lines;
    if (identical(_cachedLines, lines) &&
        _cachedLineCount == lines.length &&
        _cachedStyle == style &&
        _cachedTextScaler == textScaler) {
      return (measuredWidth: _cachedMeasuredWidth, rowExtent: _cachedRowExtent);
    }
    final measured = _measureLogLineMetrics(
      lines: lines,
      style: style,
      textScaler: textScaler,
    );
    _cachedLines = lines;
    _cachedLineCount = lines.length;
    _cachedStyle = style;
    _cachedTextScaler = textScaler;
    _cachedMeasuredWidth = measured.measuredWidth;
    _cachedRowExtent = measured.rowExtent;
    return measured;
  }
}

/// Immutable value-equality console slice watched by [_LogConsolePanel].
@immutable
class _LogConsoleSlice {
  /// Creates a [_LogConsoleSlice].
  const _LogConsoleSlice({
    required this.hasEntries,
    required this.filteredLines,
  });

  /// Filtered diagnostic log entries rendered in the console.
  final List<DiagnosticLogLine> filteredLines;

  /// Whether at least one entry exists in the unfiltered log buffer.
  final bool hasEntries;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _LogConsoleSlice &&
        other.hasEntries == hasEntries &&
        (identical(other.filteredLines, filteredLines) ||
            listEquals(other.filteredLines, filteredLines));
  }

  @override
  int get hashCode => Object.hash(hasEntries, Object.hashAll(filteredLines));
}

/// Unified flat `panel` control card combining session metadata and level/subsystem filters.
class _LogControlPanel extends StatelessWidget {
  /// Creates a [_LogControlPanel].
  const _LogControlPanel({
    required this.callbacks,
    required this.inlineFilters,
    required this.inlineMetadata,
  });

  /// Level and subsystem filter callbacks.
  final _LogFilterCallbacks callbacks;

  /// Whether level and subsystem controls render side by side.
  final bool inlineFilters;

  /// Whether metadata header and severity counters render on a single row.
  final bool inlineMetadata;

  @override
  Widget build(BuildContext context) {
    return UiCard.standard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _LogMetadataStrip(inlineMetadata: inlineMetadata),
          _LogFilterRow(callbacks: callbacks, inlineFilters: inlineFilters),
        ],
      ),
    );
  }
}

/// Immutable bundle of level and subsystem filter callbacks for [LogViewerView].
@immutable
class _LogFilterCallbacks {
  /// Creates a [_LogFilterCallbacks] bundle.
  const _LogFilterCallbacks({
    required this.onClearSelectedTags,
    required this.onLevelChanged,
    required this.onSelectAllTags,
    required this.onToggleTag,
  });

  /// Callback deselecting all subsystem tags.
  final VoidCallback onClearSelectedTags;

  /// Callback invoked when the user chooses a new minimum severity threshold.
  final ValueChanged<LogLevel> onLevelChanged;

  /// Callback selecting every subsystem tag.
  final VoidCallback onSelectAllTags;

  /// Callback toggling a single subsystem [LogTag].
  final ValueChanged<LogTag> onToggleTag;
}

/// Shared muted `meta` label text rendered above log filter controls.
class _LogFilterLabel extends StatelessWidget {
  /// Creates a [_LogFilterLabel].
  const _LogFilterLabel({required this.text});

  /// Localized filter section label.
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Text(
      text,
      style: tokens.typography.meta.copyWith(
        color: tokens.colors.muted,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Responsive filter grid combining minimum severity select and multi-select subsystem toggles.
class _LogFilterRow extends StatelessWidget {
  /// Creates a [_LogFilterRow].
  const _LogFilterRow({required this.callbacks, required this.inlineFilters});

  /// Level and subsystem filter callbacks.
  final _LogFilterCallbacks callbacks;

  /// Whether level and subsystem controls render side by side instead of stacked.
  final bool inlineFilters;

  @override
  Widget build(BuildContext context) {
    final levelField = _LogLevelFilterField(
      inlineFilters: inlineFilters,
      onLevelChanged: callbacks.onLevelChanged,
    );
    final subsystemField = _LogSubsystemFilterField(callbacks: callbacks);

    if (inlineFilters) {
      return _LogInlineFilterColumns(
        levelField: levelField,
        subsystemField: subsystemField,
      );
    }
    return _LogStackedFilterColumns(
      levelField: levelField,
      subsystemField: subsystemField,
    );
  }
}

/// Two-column desktop filter layout placing level and subsystem cells beside a `1px` vertical hairline.
class _LogInlineFilterColumns extends StatelessWidget {
  /// Creates a [_LogInlineFilterColumns].
  const _LogInlineFilterColumns({
    required this.levelField,
    required this.subsystemField,
  });

  /// Internal padding applied to each filter cell.
  static const EdgeInsets _cellPadding = EdgeInsets.fromLTRB(
    14.0,
    10.0,
    14.0,
    12.0,
  );

  /// Minimum severity filter column widget.
  final Widget levelField;

  /// Multi-select subsystem filter column widget.
  final Widget subsystemField;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final dividerSide = BorderSide(
      color: tokens.colors.line,
      width: tokens.radii.borderWidth,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: _levelFilterColumnWidth,
          child: Padding(padding: _cellPadding, child: levelField),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border(left: dividerSide)),
            child: Padding(padding: _cellPadding, child: subsystemField),
          ),
        ),
      ],
    );
  }
}

/// Minimum severity dropdown control with aligned section header for [_LogFilterRow].
class _LogLevelFilterField extends ConsumerWidget {
  /// Creates a [_LogLevelFilterField].
  const _LogLevelFilterField({
    required this.inlineFilters,
    required this.onLevelChanged,
  });

  /// Cached immutable select options for all [LogLevel] severity levels.
  static final List<UiSelectOption> _levelOptions =
      List<UiSelectOption>.unmodifiable(<UiSelectOption>[
        for (final level in LogLevel.values)
          UiSelectOption(value: level.name, label: level.label),
      ]);

  /// Whether this control renders beside [_LogSubsystemFilterField] and matches its header height.
  final bool inlineFilters;

  /// Callback invoked on level selection change.
  final ValueChanged<LogLevel> onLevelChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final minimumLevel = ref.watch(
      logViewerProvider.select((snapshot) => snapshot.minimumLevel),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: inlineFilters ? _filterHeaderRowMinHeight : 0.0,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _LogFilterLabel(text: localizations.logLevelLabel),
          ),
        ),
        const SizedBox(height: 6.0),
        UiField(
          key: const ValueKey<String>('log_viewer_level_filter'),
          kind: UiFieldKind.select,
          semanticLabel: localizations.logLevelLabel,
          height: tokens.spacing.fieldCompactHeight,
          selectValue: minimumLevel.name,
          selectOptions: _levelOptions,
          onSelectChanged: _handleSelectChanged,
        ),
      ],
    );
  }

  /// Parses [rawValue] into a [LogLevel] before forwarding to [onLevelChanged].
  void _handleSelectChanged(String rawValue) {
    final parsed = _parseLogLevel(rawValue);
    if (parsed != null) {
      onLevelChanged(parsed);
    }
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
            maxLines: 1,
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

/// Narrow-scoped session metadata summary text inside [_LogMetadataStripContent].
class _LogMetadataHeaderSummary extends ConsumerWidget {
  /// Creates a [_LogMetadataHeaderSummary].
  const _LogMetadataHeaderSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final headerSummary = ref.watch(
      logViewerProvider.select((snapshot) => snapshot.headerSummary),
    );
    return SelectableText(
      headerSummary,
      style: tokens.typography.monoSmall.copyWith(color: tokens.colors.ink),
    );
  }
}

/// Narrow-scoped severity counter badge text inside [_LogMetadataStripContent].
class _LogMetadataStatsCounter extends ConsumerWidget {
  /// Creates a [_LogMetadataStatsCounter].
  const _LogMetadataStatsCounter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final counts = ref.watch(
      logViewerProvider.select(
        (snapshot) => (
          totalEntries: snapshot.totalEntries,
          warningCount: snapshot.warningCount,
          errorCount: snapshot.errorCount,
        ),
      ),
    );
    return Text(
      localizations.logMetadataStats(
        counts.totalEntries.toString(),
        counts.warningCount.toString(),
        counts.errorCount.toString(),
      ),
      style: UiTypographyTokens.tabular(
        tokens.typography.meta.copyWith(color: tokens.colors.muted),
      ),
    );
  }
}

/// Top metadata band inside [_LogControlPanel] displaying session header and severity counters.
class _LogMetadataStrip extends StatelessWidget {
  /// Creates a [_LogMetadataStrip].
  const _LogMetadataStrip({required this.inlineMetadata});

  /// Whether session header and severity counters render side by side.
  final bool inlineMetadata;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return DecoratedBox(
      key: const ValueKey<String>('log_viewer_metadata_card'),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        child: _LogMetadataStripContent(inlineMetadata: inlineMetadata),
      ),
    );
  }
}

/// Responsive single-row or stacked layout for session summary text and severity counters.
class _LogMetadataStripContent extends StatelessWidget {
  /// Creates a [_LogMetadataStripContent].
  const _LogMetadataStripContent({required this.inlineMetadata});

  /// Whether summary and counters render horizontally.
  final bool inlineMetadata;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    const summaryText = _LogMetadataHeaderSummary();
    const statsText = _LogMetadataStatsCounter();

    if (inlineMetadata) {
      return Row(
        children: <Widget>[
          const Expanded(child: summaryText),
          SizedBox(width: tokens.spacing.space3),
          statsText,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        summaryText,
        SizedBox(height: tokens.spacing.space1),
        statsText,
      ],
    );
  }
}

/// Immutable value-equality subsystem tag selection slice watched by [_LogSubsystemFilterField].
@immutable
class _LogSelectedTagsSlice {
  /// Creates a [_LogSelectedTagsSlice].
  const _LogSelectedTagsSlice(this.tags);

  /// Currently selected subsystem tags.
  final Set<LogTag> tags;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _LogSelectedTagsSlice && setEquals(other.tags, tags);
  }

  @override
  int get hashCode => Object.hashAllUnordered(tags);
}

/// Stacked narrow/compact filter layout separating level and subsystem cells by a `1px` horizontal hairline.
class _LogStackedFilterColumns extends StatelessWidget {
  /// Creates a [_LogStackedFilterColumns].
  const _LogStackedFilterColumns({
    required this.levelField,
    required this.subsystemField,
  });

  /// Internal padding applied to each filter cell.
  static const EdgeInsets _cellPadding = EdgeInsets.fromLTRB(
    14.0,
    10.0,
    14.0,
    12.0,
  );

  /// Minimum severity filter column widget.
  final Widget levelField;

  /// Multi-select subsystem filter column widget.
  final Widget subsystemField;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final dividerSide = BorderSide(
      color: tokens.colors.line,
      width: tokens.radii.borderWidth,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: _cellPadding,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _stackedLevelFilterMaxWidth,
              ),
              child: levelField,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(border: Border(top: dividerSide)),
          child: Padding(padding: _cellPadding, child: subsystemField),
        ),
      ],
    );
  }
}

/// Compact bordered `All` and `None` bulk actions placed in [_LogSubsystemHeaderRow].
class _LogSubsystemBulkActions extends StatelessWidget {
  /// Creates a [_LogSubsystemBulkActions].
  const _LogSubsystemBulkActions({
    required this.areAllSelected,
    required this.isNoneSelected,
    required this.onClearSelectedTags,
    required this.onSelectAllTags,
  });

  /// Whether every subsystem tag is currently active.
  final bool areAllSelected;

  /// Whether zero subsystem tags are currently active.
  final bool isNoneSelected;

  /// Callback deselecting all subsystem tags.
  final VoidCallback onClearSelectedTags;

  /// Callback selecting all subsystem tags.
  final VoidCallback onSelectAllTags;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiButton(
          key: const ValueKey<String>('log_viewer_subsystem_all'),
          label: localizations.logFilterAllTags,
          density: UiButtonDensity.sidebarDesktop,
          onPressed: areAllSelected ? null : onSelectAllTags,
        ),
        const SizedBox(width: 6.0),
        UiButton(
          key: const ValueKey<String>('log_viewer_subsystem_none'),
          label: localizations.logFilterNoTags,
          density: UiButtonDensity.sidebarDesktop,
          onPressed: isNoneSelected ? null : onClearSelectedTags,
        ),
      ],
    );
  }
}

/// Multi-select subsystem toggle group with header count pill and right-aligned `All`/`None` actions.
class _LogSubsystemFilterField extends ConsumerWidget {
  /// Creates a [_LogSubsystemFilterField].
  const _LogSubsystemFilterField({required this.callbacks});

  /// Subsystem filter mutation callbacks.
  final _LogFilterCallbacks callbacks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTags = ref
        .watch(logViewerProvider.select(_selectLogSelectedTagsSlice))
        .tags;

    return Column(
      key: const ValueKey<String>('log_viewer_subsystem_filter'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _LogSubsystemHeaderRow(
          callbacks: callbacks,
          selectedTags: selectedTags,
        ),
        const SizedBox(height: 6.0),
        _LogSubsystemToggleWrap(
          onToggleTag: callbacks.onToggleTag,
          selectedTags: selectedTags,
        ),
      ],
    );
  }
}

/// Header row pairing subsystem label and active count pill on the left with `All`/`None` actions on the right.
class _LogSubsystemHeaderRow extends StatelessWidget {
  /// Creates a [_LogSubsystemHeaderRow].
  const _LogSubsystemHeaderRow({
    required this.callbacks,
    required this.selectedTags,
  });

  /// Subsystem filter mutation callbacks.
  final _LogFilterCallbacks callbacks;

  /// Currently active subsystem tags.
  final Set<LogTag> selectedTags;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _filterHeaderRowMinHeight),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _LogFilterLabel(text: localizations.logFilterSubsystemLabel),
                UiPill(
                  key: const ValueKey<String>('log_viewer_subsystem_count'),
                  label: '${selectedTags.length} / ${LogTag.values.length}',
                  variant: UiPillVariant.count,
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.space2),
          _LogSubsystemBulkActions(
            areAllSelected: selectedTags.length == LogTag.values.length,
            isNoneSelected: selectedTags.isEmpty,
            onClearSelectedTags: callbacks.onClearSelectedTags,
            onSelectAllTags: callbacks.onSelectAllTags,
          ),
        ],
      ),
    );
  }
}

/// Wrapping row of selectable subsystem [UiPill] chips.
class _LogSubsystemToggleWrap extends StatelessWidget {
  /// Creates a [_LogSubsystemToggleWrap].
  const _LogSubsystemToggleWrap({
    required this.onToggleTag,
    required this.selectedTags,
  });

  /// Callback toggling one subsystem [LogTag].
  final ValueChanged<LogTag> onToggleTag;

  /// Currently active subsystem tags.
  final Set<LogTag> selectedTags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final tag in LogTag.values)
          UiPill(
            key: ValueKey<String>('log_viewer_subsystem_${tag.name}'),
            label: tag.label,
            variant: UiPillVariant.selectable,
            isSelected: selectedTags.contains(tag),
            onPressed: () => onToggleTag(tag),
          ),
      ],
    );
  }
}

/// Toolbar action cluster (`Upload Log`, `Copy All`, `Copy Filtered`, `Scroll to Top`, `Clear`).
class _LogToolbarActions extends ConsumerWidget {
  /// Creates a [_LogToolbarActions].
  const _LogToolbarActions({
    required this.onClearLog,
    required this.onCopyAll,
    required this.onCopyFiltered,
    required this.onScrollToTop,
  });

  /// Callback clearing buffered diagnostic entries.
  final VoidCallback onClearLog;

  /// Callback copying full diagnostic log text to clipboard.
  final VoidCallback onCopyAll;

  /// Callback copying only the currently filtered diagnostic log entries to clipboard.
  final VoidCallback onCopyFiltered;

  /// Callback jumping vertical console scroll to the topmost entry.
  final VoidCallback onScrollToTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final availability = ref.watch(
      logViewerProvider.select(
        (snapshot) => (
          canSyncWebDav: snapshot.canSyncWebDav,
          hasEntries: snapshot.hasEntries,
          hasFilteredLines: snapshot.filteredLines.isNotEmpty,
        ),
      ),
    );

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: <Widget>[
        if (availability.canSyncWebDav) const _LogUploadToolbarButton(),
        UiButton(
          key: const ValueKey<String>('log_viewer_copy_button'),
          label: localizations.tooltipCopyLog,
          leadingIcon: Icons.copy_all_outlined,
          density: UiButtonDensity.compact,
          onPressed: availability.hasEntries ? onCopyAll : null,
        ),
        UiButton(
          key: const ValueKey<String>('log_viewer_copy_filtered_button'),
          label: localizations.tooltipCopyFilteredLog,
          leadingIcon: Icons.copy_outlined,
          density: UiButtonDensity.compact,
          onPressed: availability.hasFilteredLines ? onCopyFiltered : null,
        ),
        UiButton(
          key: const ValueKey<String>('log_viewer_scroll_top_button'),
          label: localizations.tooltipScrollToTop,
          leadingIcon: Icons.vertical_align_top_rounded,
          density: UiButtonDensity.compact,
          onPressed: availability.hasFilteredLines ? onScrollToTop : null,
        ),
        _LogClearToolbarButton(onClearLog: onClearLog),
      ],
    );
  }
}

/// WebDAV upload trigger button managing its own in-flight loading state when remote diagnostic sync is enabled.
class _LogUploadToolbarButton extends ConsumerStatefulWidget {
  /// Creates a [_LogUploadToolbarButton].
  const _LogUploadToolbarButton();

  @override
  ConsumerState<_LogUploadToolbarButton> createState() =>
      _LogUploadToolbarButtonState();
}

/// Manages manual WebDAV diagnostic log upload progress and feedback toasts for [_LogUploadToolbarButton].
class _LogUploadToolbarButtonState
    extends ConsumerState<_LogUploadToolbarButton> {
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      key: const ValueKey<String>('log_viewer_upload_button'),
      label: localizations.logActionUpload,
      leadingIcon: Icons.cloud_upload_outlined,
      density: UiButtonDensity.compact,
      isLoading: _isUploading,
      onPressed: _isUploading ? null : _handleUploadTap,
    );
  }

  /// Dispatches [_uploadLog] from the synchronous button press handler.
  void _handleUploadTap() {
    unawaited(_uploadLog());
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

/// Header, optional wrapped toolbar, and unified metadata/filter panel above the log console.
class _LogViewerHeaderSection extends StatelessWidget {
  /// Creates a [_LogViewerHeaderSection].
  const _LogViewerHeaderSection({
    required this.filterCallbacks,
    required this.inlineFilters,
    required this.inlineMetadata,
    required this.inlineToolbar,
    required this.toolbar,
    required this.onBack,
  });

  /// Level and subsystem filter callbacks.
  final _LogFilterCallbacks filterCallbacks;

  /// Whether level and subsystem filter controls render side by side.
  final bool inlineFilters;

  /// Whether session metadata header and counters render on one row.
  final bool inlineMetadata;

  /// Whether [toolbar] renders inline inside [UiPageHeader.trailing].
  final bool inlineToolbar;

  /// Back navigation callback returning to Tasks.
  final VoidCallback onBack;

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
        _LogControlPanel(
          callbacks: filterCallbacks,
          inlineFilters: inlineFilters,
          inlineMetadata: inlineMetadata,
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
    required this.console,
    required this.filterCallbacks,
    required this.onBack,
    required this.toolbar,
  });

  /// Console panel widget.
  final Widget console;

  /// Level and subsystem filter callbacks.
  final _LogFilterCallbacks filterCallbacks;

  /// Back navigation callback returning to Tasks.
  final VoidCallback onBack;

  /// Toolbar action cluster widget.
  final Widget toolbar;

  @override
  Widget build(BuildContext context) {
    final minConsoleHeight = UiThemeTokens.of(context).spacing.minConsoleHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final header = _LogViewerHeaderSection(
          filterCallbacks: filterCallbacks,
          inlineFilters: constraints.maxWidth >= _inlineFilterBreakpoint,
          inlineMetadata: constraints.maxWidth >= _inlineMetadataBreakpoint,
          inlineToolbar: constraints.maxWidth >= _inlineToolbarBreakpoint,
          toolbar: toolbar,
          onBack: onBack,
        );
        if (constraints.maxHeight <
            _minFlexBodyHeightForWidth(constraints.maxWidth)) {
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

/// Manages console [ScrollController]s and auto-follow state for [LogViewerView] without watching log appends.
class _LogViewerViewState extends ConsumerState<LogViewerView> {
  late final _LogFilterCallbacks _filterCallbacks;
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  bool _followEnd = true;
  bool _isProgrammaticVerticalScroll = false;
  bool _scrollToEndScheduled = false;

  @override
  void initState() {
    super.initState();
    _filterCallbacks = _createFilterCallbacks();
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
    final tokens = UiThemeTokens.of(context);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);

    return Padding(
      padding: tokens.spacing.mainContentPadding(viewport),
      child: _LogViewerLayout(
        onBack: _navigateBackToTasks,
        filterCallbacks: _filterCallbacks,
        toolbar: _LogToolbarActions(
          onClearLog: _clearLog,
          onCopyAll: _handleCopyAll,
          onCopyFiltered: _handleCopyFiltered,
          onScrollToTop: _scrollToTop,
        ),
        console: _LogConsolePanel(
          key: const ValueKey<String>('log_viewer_console'),
          horizontalController: _horizontalController,
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
        .showNotice(localizations.logClearedSnackBar);
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

  /// Builds the immutable [_LogFilterCallbacks] bound to [logViewerProvider].
  _LogFilterCallbacks _createFilterCallbacks() {
    final notifier = ref.read(logViewerProvider.notifier);
    return _LogFilterCallbacks(
      onClearSelectedTags: notifier.clearSelectedTags,
      onLevelChanged: notifier.setMinimumLevel,
      onSelectAllTags: notifier.selectAllTags,
      onToggleTag: notifier.toggleTag,
    );
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
            !setEquals(previous.selectedTags, next.selectedTags));
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
}

/// Computes horizontal scroll width and fixed single-line row extent from [lines].
({double measuredWidth, double rowExtent}) _measureLogLineMetrics({
  required List<DiagnosticLogLine> lines,
  required TextStyle style,
  required TextScaler textScaler,
}) {
  var longestLine = '';
  for (final entry in lines) {
    if (entry.text.length > longestLine.length) {
      longestLine = entry.text;
    }
  }
  final sampleText = longestLine.isEmpty ? 'M' : longestLine;
  final painter = TextPainter(
    text: TextSpan(
      text: sampleText,
      style: style.copyWith(fontWeight: FontWeight.w700),
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final measuredWidth = longestLine.isEmpty ? 0.0 : painter.width + 44.0;
  final rowExtent = painter.height.ceilToDouble() + 7.0;
  painter.dispose();
  return (measuredWidth: measuredWidth, rowExtent: rowExtent);
}

/// Returns the minimum body height needed for a flex-expanded console at [availableWidth].
double _minFlexBodyHeightForWidth(double availableWidth) {
  if (availableWidth >= _inlineToolbarBreakpoint) {
    return _minFlexBodyHeight;
  }
  if (availableWidth >= _inlineFilterBreakpoint) {
    return 560.0;
  }
  if (availableWidth >= _compactScrollWidthThreshold) {
    return 640.0;
  }
  return 960.0;
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

/// Extracts value-compared console lines and buffer presence from [snapshot].
_LogConsoleSlice _selectLogConsoleSlice(DiagnosticLogSnapshot snapshot) {
  return _LogConsoleSlice(
    hasEntries: snapshot.hasEntries,
    filteredLines: snapshot.filteredLines,
  );
}

/// Extracts value-compared selected subsystem tags from [snapshot].
_LogSelectedTagsSlice _selectLogSelectedTagsSlice(
  DiagnosticLogSnapshot snapshot,
) {
  return _LogSelectedTagsSlice(snapshot.selectedTags);
}
