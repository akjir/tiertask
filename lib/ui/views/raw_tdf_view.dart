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

/// Manages horizontal and vertical [ScrollController]s for [_RawTdfCodeBlock].
class _RawTdfCodeBlockState extends State<_RawTdfCodeBlock> {
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
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final codeStyle = tokens.typography.rawCode.copyWith(color: colors.ink);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(tokens.radii.card),
        border: Border.all(color: colors.line, width: tokens.radii.borderWidth),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radii.card),
        child: _RawTdfScrollableCode(
          content: widget.content,
          codeStyle: codeStyle,
          horizontalController: _horizontalController,
          verticalController: _verticalController,
        ),
      ),
    );
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

/// Dual-axis scrollable [SelectableText] canvas sized to [contentWidth].
class _RawTdfScrollCanvas extends StatelessWidget {
  /// Creates a [_RawTdfScrollCanvas].
  const _RawTdfScrollCanvas({
    required this.content,
    required this.codeStyle,
    required this.contentWidth,
    required this.horizontalController,
    required this.verticalController,
  });

  /// Monospace code text style (`tokens.typography.rawCode`).
  final TextStyle codeStyle;

  /// Canonical serialized `.tdf` document text.
  final String content;

  /// Measured finite horizontal canvas width for [SelectableText].
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
          controller: verticalController,
          child: SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 14.0,
                ),
                child: SelectableText(content, style: codeStyle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bidirectionally scrollable [SelectableText] canvas inside [_RawTdfCodeBlock].
class _RawTdfScrollableCode extends StatelessWidget {
  /// Creates a [_RawTdfScrollableCode].
  const _RawTdfScrollableCode({
    required this.content,
    required this.codeStyle,
    required this.horizontalController,
    required this.verticalController,
  });

  /// Monospace code text style (`tokens.typography.rawCode`).
  final TextStyle codeStyle;

  /// Canonical serialized `.tdf` document text.
  final String content;

  /// Horizontal scroll controller.
  final ScrollController horizontalController;

  /// Vertical scroll controller.
  final ScrollController verticalController;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = _computeRawTdfContentWidth(
          content: content,
          style: codeStyle,
          textScaler: textScaler,
          viewportWidth: constraints.maxWidth,
        );
        return _RawTdfScrollCanvas(
          content: content,
          codeStyle: codeStyle,
          contentWidth: contentWidth,
          horizontalController: horizontalController,
          verticalController: verticalController,
        );
      },
    );
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

/// Measures a finite horizontal canvas width for [SelectableText] from the longest line in [content].
double _computeRawTdfContentWidth({
  required String content,
  required TextStyle style,
  required TextScaler textScaler,
  required double viewportWidth,
}) {
  final longestLine = _findLongestLine(content);
  if (longestLine.isEmpty) {
    return viewportWidth;
  }
  final painter = TextPainter(
    text: TextSpan(text: longestLine, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final measuredWidth = painter.width + 44.0;
  painter.dispose();
  return math.max(viewportWidth, measuredWidth);
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

/// Returns the single longest `\n`-delimited line slice in [text] in one zero-split $O(N)$ pass.
String _findLongestLine(String text) {
  var start = 0;
  var bestStart = 0;
  var bestLength = 0;
  final length = text.length;
  while (start <= length) {
    final newlineIndex = text.indexOf('\n', start);
    final end = newlineIndex < 0 ? length : newlineIndex;
    final lineLength = end - start;
    if (lineLength > bestLength) {
      bestStart = start;
      bestLength = lineLength;
    }
    if (newlineIndex < 0) {
      break;
    }
    start = newlineIndex + 1;
  }
  if (bestLength == 0) {
    return '';
  }
  return text.substring(bestStart, bestStart + bestLength);
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
