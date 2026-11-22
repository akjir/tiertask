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
import '../../models/tdf_error.dart';
import '../../providers/board_providers.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/shell_providers.dart';
import '../layout/ui_page_header.dart';
import '../primitives/ui_banner.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';

/// Minimum body height for flex-expanded layout before falling back to outer vertical scrolling.
const double _minFlexBodyHeight = 440.0;

/// Full-height canonical TDF source preview view with byte/line telemetry,
/// clipboard copy action, and Section 6.2 limit-exceeded alert (`U-UX-007`).
class RawTdfView extends ConsumerWidget {
  /// Creates a [RawTdfView].
  const RawTdfView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final preview = ref.watch(rawTdfPreviewProvider);
    final viewport = UiBreakpoints.classify(MediaQuery.sizeOf(context).width);

    return Padding(
      padding: tokens.spacing.mainContentPadding(viewport),
      child: _RawTdfLayout(
        preview: preview,
        onBack: () =>
            ref.read(shellProvider.notifier).openView(ShellView.tasks),
        onCopy: preview.isLimitExceeded
            ? null
            : () {
                unawaited(
                  _copyRawTdf(
                    context,
                    ref,
                    content: preview.content,
                    copiedNotice: localizations.rawTdfCopiedNotice,
                  ),
                );
              },
      ),
    );
  }
}

/// Responsive body switching between single-scroll compact height and flex [Expanded] layout.
class _RawTdfAdaptiveBody extends StatelessWidget {
  /// Creates a [_RawTdfAdaptiveBody].
  const _RawTdfAdaptiveBody({required this.header, required this.content});

  /// Canonical serialized `.tdf` document text.
  final String content;

  /// Header and telemetry strip rendered above the code block.
  final Widget header;

  @override
  Widget build(BuildContext context) {
    final minConsoleHeight = UiThemeTokens.of(context).spacing.minConsoleHeight;
    final codeBlock = _RawTdfCodeBlock(
      key: const ValueKey<String>('raw_tdf_code_block'),
      content: content,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < _minFlexBodyHeight) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                header,
                SizedBox(height: minConsoleHeight, child: codeBlock),
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
                child: codeBlock,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Flat `1px`-bordered `panel` code block supporting both vertical and horizontal scrolling.
class _RawTdfCodeBlock extends StatefulWidget {
  /// Creates a [_RawTdfCodeBlock].
  const _RawTdfCodeBlock({super.key, required this.content});

  /// Canonical LF-terminated serialized `.tdf` document text.
  final String content;

  @override
  State<_RawTdfCodeBlock> createState() => _RawTdfCodeBlockState();
}

/// Manages line splitting, cached text metrics, scroll controllers, and selection for [_RawTdfCodeBlock].
class _RawTdfCodeBlockState extends State<_RawTdfCodeBlock> {
  final ScrollController _horizontalController = ScrollController();
  final _RawTdfSelectionDelegate _selectionDelegate =
      _RawTdfSelectionDelegate();
  final ScrollController _verticalController = ScrollController();

  double _cachedLineExtent = 20.0;
  double _cachedMeasuredWidth = 0.0;
  int _cachedMetricsVersion = -1;
  TextStyle? _cachedStyle;
  TextScaler? _cachedTextScaler;
  int _contentVersion = 0;
  List<String> _lines = const <String>[];
  String _longestLine = '';

  @override
  void initState() {
    super.initState();
    _syncParsedLines(widget.content);
  }

  @override
  void didUpdateWidget(covariant _RawTdfCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _syncParsedLines(widget.content);
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _selectionDelegate.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final codeStyle = tokens.typography.rawCode.copyWith(color: colors.ink);
    final metrics = _resolveMetrics(
      codeStyle,
      MediaQuery.textScalerOf(context),
    );

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
          child: _RawTdfScrollableCode(
            lines: _lines,
            codeStyle: codeStyle,
            measuredWidth: metrics.measuredWidth,
            lineExtent: metrics.lineExtent,
            horizontalController: _horizontalController,
            verticalController: _verticalController,
            selectionDelegate: _selectionDelegate,
          ),
        ),
      ),
    );
  }

  /// Resolves cached horizontal canvas width and fixed line extent for [style] and [textScaler].
  ({double measuredWidth, double lineExtent}) _resolveMetrics(
    TextStyle style,
    TextScaler textScaler,
  ) {
    if (_cachedMetricsVersion == _contentVersion &&
        _cachedStyle == style &&
        _cachedTextScaler == textScaler) {
      return (
        measuredWidth: _cachedMeasuredWidth,
        lineExtent: _cachedLineExtent,
      );
    }
    final sampleText = _longestLine.isEmpty ? 'M' : _longestLine;
    final painter = TextPainter(
      text: TextSpan(text: sampleText, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    _cachedMeasuredWidth = _longestLine.isEmpty ? 0.0 : painter.width + 44.0;
    _cachedLineExtent = painter.height.ceilToDouble();
    painter.dispose();
    _cachedMetricsVersion = _contentVersion;
    _cachedStyle = style;
    _cachedTextScaler = textScaler;
    return (measuredWidth: _cachedMeasuredWidth, lineExtent: _cachedLineExtent);
  }

  /// Splits [content] into lines and records the longest line in one single O(N) pass.
  void _syncParsedLines(String content) {
    final parsed = _parseLinesAndLongest(content);
    _lines = parsed.lines;
    _longestLine = parsed.longestLine;
    _contentVersion++;
  }
}

/// Page header with copy trigger and telemetry strip rendered above the raw TDF body.
class _RawTdfHeaderSection extends StatelessWidget {
  /// Creates a [_RawTdfHeaderSection].
  const _RawTdfHeaderSection({
    required this.statsLabel,
    required this.onBack,
    required this.onCopy,
  });

  /// Back navigation callback returning to Tasks.
  final VoidCallback onBack;

  /// Clipboard copy callback, or `null` when preview limits are exceeded.
  final VoidCallback? onCopy;

  /// Formatted telemetry summary string.
  final String statsLabel;

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
          title: localizations.rawTdfPreviewTitle,
          subtitle: localizations.rawTdfPreviewSubtitle,
          trailing: UiButton(
            key: const ValueKey<String>('raw_tdf_copy_button'),
            label: localizations.actionCopy,
            leadingIcon: Icons.copy_outlined,
            variant: UiButtonVariant.primary,
            density: UiButtonDensity.compact,
            onPressed: onCopy,
          ),
        ),
        SizedBox(height: tokens.spacing.space3),
        _RawTdfStatsStrip(statsLabel: statsLabel),
        SizedBox(height: tokens.spacing.space3),
      ],
    );
  }
}

/// Adaptive header, telemetry strip, and flex preview or limit-exceeded alert layout.
class _RawTdfLayout extends StatelessWidget {
  /// Creates a [_RawTdfLayout].
  const _RawTdfLayout({
    required this.preview,
    required this.onBack,
    required this.onCopy,
  });

  /// Back navigation callback returning to Tasks.
  final VoidCallback onBack;

  /// Clipboard copy callback, or `null` when preview limits are exceeded.
  final VoidCallback? onCopy;

  /// Live auto-disposed Raw TDF preview snapshot.
  final RawTdfPreview preview;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final header = _RawTdfHeaderSection(
      statsLabel: _formatRawTdfStatsLabel(preview, localizations),
      onBack: onBack,
      onCopy: onCopy,
    );
    if (preview.isLimitExceeded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header,
          UiBanner(
            key: const ValueKey<String>('raw_tdf_limit_banner'),
            variant: UiBannerVariant.status,
            tone: UiBannerTone.warning,
            title: localizations.rawTdfLimitExceededTitle,
            message: localizations.rawTdfLimitExceededDescription,
          ),
        ],
      );
    }

    return _RawTdfAdaptiveBody(header: header, content: preview.content);
  }
}

/// Single virtualized monospace source line participating in newline-preserving [SelectionArea] copy.
class _RawTdfLineRow extends StatefulWidget {
  /// Creates a [_RawTdfLineRow].
  const _RawTdfLineRow({
    super.key,
    required this.text,
    required this.codeStyle,
  });

  /// Monospace code text style (`tokens.typography.rawCode`).
  final TextStyle codeStyle;

  /// Single line of canonical TDF text without trailing newline.
  final String text;

  @override
  State<_RawTdfLineRow> createState() => _RawTdfLineRowState();
}

/// Row-level selection delegate appending a newline when selection reaches the end of a source line.
final class _RawTdfLineRowSelectionDelegate
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

/// Owns the per-row selection delegate for [_RawTdfLineRow].
class _RawTdfLineRowState extends State<_RawTdfLineRow> {
  final _RawTdfLineRowSelectionDelegate _selectionDelegate =
      _RawTdfLineRowSelectionDelegate();

  @override
  void dispose() {
    _selectionDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(
      delegate: _selectionDelegate,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          widget.text,
          softWrap: false,
          maxLines: 1,
          style: widget.codeStyle,
        ),
      ),
    );
  }
}

/// Dual-axis scrollable virtualized [ListView.builder] canvas inside [SelectionArea].
class _RawTdfScrollCanvas extends StatelessWidget {
  /// Creates a [_RawTdfScrollCanvas].
  const _RawTdfScrollCanvas({
    required this.lines,
    required this.codeStyle,
    required this.contentWidth,
    required this.lineExtent,
    required this.horizontalController,
    required this.verticalController,
    required this.selectionDelegate,
  });

  /// Monospace code text style (`tokens.typography.rawCode`).
  final TextStyle codeStyle;

  /// Measured finite horizontal canvas width.
  final double contentWidth;

  /// Horizontal scroll controller.
  final ScrollController horizontalController;

  /// Fixed vertical extent per line enabling O(1) virtualized scrolling.
  final double lineExtent;

  /// Pre-split canonical `.tdf` source lines.
  final List<String> lines;

  /// Container delegate trimming stray trailing newlines from completed selections.
  final SelectionContainerDelegate selectionDelegate;

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
        child: SelectionArea(
          child: SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              child: SelectionContainer(
                delegate: selectionDelegate,
                child: ListView.builder(
                  controller: verticalController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 14.0,
                  ),
                  itemExtent: lineExtent,
                  itemCount: lines.length,
                  itemBuilder: (context, index) => _RawTdfLineRow(
                    key: ValueKey<String>('raw_tdf_line_$index'),
                    text: lines[index],
                    codeStyle: codeStyle,
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

/// Bidirectionally scrollable virtualized code viewport inside [_RawTdfCodeBlock].
class _RawTdfScrollableCode extends StatelessWidget {
  /// Creates a [_RawTdfScrollableCode].
  const _RawTdfScrollableCode({
    required this.lines,
    required this.codeStyle,
    required this.measuredWidth,
    required this.lineExtent,
    required this.horizontalController,
    required this.verticalController,
    required this.selectionDelegate,
  });

  /// Monospace code text style (`tokens.typography.rawCode`).
  final TextStyle codeStyle;

  /// Horizontal scroll controller.
  final ScrollController horizontalController;

  /// Fixed vertical extent per source line.
  final double lineExtent;

  /// Pre-split canonical `.tdf` source lines.
  final List<String> lines;

  /// Pre-measured minimum horizontal width required by the longest source line.
  final double measuredWidth;

  /// Container delegate joining multi-line selections cleanly.
  final SelectionContainerDelegate selectionDelegate;

  /// Vertical scroll controller.
  final ScrollController verticalController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(constraints.maxWidth, measuredWidth);
        return _RawTdfScrollCanvas(
          lines: lines,
          codeStyle: codeStyle,
          contentWidth: contentWidth,
          lineExtent: lineExtent,
          horizontalController: horizontalController,
          verticalController: verticalController,
          selectionDelegate: selectionDelegate,
        );
      },
    );
  }
}

/// Document-level selection delegate trimming a stray trailing newline from completed source selections.
final class _RawTdfSelectionDelegate extends StaticSelectionContainerDelegate {
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

/// Compact monospace telemetry strip displaying byte and line counts against TDF Section 6.2 bounds.
class _RawTdfStatsStrip extends StatelessWidget {
  /// Creates a [_RawTdfStatsStrip].
  const _RawTdfStatsStrip({required this.statsLabel});

  /// Formatted telemetry summary string.
  final String statsLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      key: const ValueKey<String>('raw_tdf_stats_card'),
      padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 10.0),
      child: Text(
        statsLabel,
        style: UiTypographyTokens.tabular(
          tokens.typography.monoSmall.copyWith(color: tokens.colors.ink),
        ),
      ),
    );
  }
}

/// Copies serialized TDF [content] to the clipboard and emits [copiedNotice].
Future<void> _copyRawTdf(
  BuildContext context,
  WidgetRef ref, {
  required String content,
  required String copiedNotice,
}) async {
  await Clipboard.setData(ClipboardData(text: content));
  if (!context.mounted) {
    return;
  }
  ref
      .read(floatingNoticeProvider.notifier)
      .showNotice(copiedNotice, tone: FloatingNoticeTone.success);
}

/// Formats localized byte and line telemetry for [preview], showing overflow sentinel bounds on early `TdfException` aborts.
String _formatRawTdfStatsLabel(
  RawTdfPreview preview,
  AppLocalizations localizations,
) {
  final hasMeasuredCounts =
      !preview.isLimitExceeded ||
      preview.byteCount > 0 ||
      preview.lineCount > 0;
  final byteCount = hasMeasuredCounts ? preview.byteCount : maxTdfFileBytes + 1;
  final lineCount = hasMeasuredCounts ? preview.lineCount : maxTdfLineCount + 1;
  return localizations.rawTdfStatsSummary('$byteCount', '$lineCount');
}

/// Splits LF-delimited [text] into lines and locates its longest line in one single O(N) pass.
({List<String> lines, String longestLine}) _parseLinesAndLongest(String text) {
  if (text.isEmpty) {
    return (lines: const <String>[], longestLine: '');
  }
  final lines = <String>[];
  var longestLine = '';
  var start = 0;
  final length = text.length;
  while (start < length) {
    final newlineIndex = text.indexOf('\n', start);
    final end = newlineIndex < 0 ? length : newlineIndex;
    final line = text.substring(start, end);
    lines.add(line);
    if (line.length > longestLine.length) {
      longestLine = line;
    }
    if (newlineIndex < 0) {
      break;
    }
    start = newlineIndex + 1;
  }
  return (lines: List<String>.unmodifiable(lines), longestLine: longestLine);
}
