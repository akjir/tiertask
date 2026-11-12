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

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tdf_metadata.dart';
import '../../services/app_logger.dart';
import '../app_theme.dart';

/// Material 3 dialog presenting an interactive HSV color wheel and brightness slider for selecting a custom `#RRGGBB` label color.
class LabelColorPickerDialog extends StatefulWidget {
  /// Creates a [LabelColorPickerDialog].
  const LabelColorPickerDialog({super.key, this.initialHex});

  /// Default fallback color (`#2196F3`) when [initialHex] is omitted or invalid.
  static const int defaultColorArgb = 0xFF2196F3;

  /// Optional initial `#RRGGBB` hexadecimal color string.
  final String? initialHex;

  @override
  State<LabelColorPickerDialog> createState() => _LabelColorPickerDialogState();

  /// Resolves the initial [HSVColor] from [rawHex], falling back to [defaultColorArgb].
  static HSVColor resolveInitialHsv(String? rawHex) {
    final parsedArgb = TdfColor.tryParseArgb(rawHex) ?? defaultColorArgb;
    return HSVColor.fromColor(Color(parsedArgb));
  }
}

/// Brightness (`value`) slider row inside [LabelColorPickerDialog].
class _BrightnessSliderRow extends StatelessWidget {
  /// Creates a [_BrightnessSliderRow].
  const _BrightnessSliderRow({required this.hsvColor, required this.onChanged});

  /// Current HSV color selection.
  final HSVColor hsvColor;

  /// Callback invoked when the brightness value changes (`0.0..1.0`).
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    final fullBrightnessColor = hsvColor.withValue(1.0).toColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          localizations.labelColorBrightnessLabel,
          style: TextStyle(
            color: appTheme.mutedTextColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: fullBrightnessColor,
            thumbColor: hsvColor.toColor(),
          ),
          child: Slider(
            key: const ValueKey('label_color_picker_value_slider'),
            value: hsvColor.value,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Custom painter rendering the circular HSV hue-saturation color wheel and selection thumb.
class _ColorWheelPainter extends CustomPainter {
  /// Creates a [_ColorWheelPainter].
  const _ColorWheelPainter({required this.borderColor, required this.hsvColor});

  /// Primary and secondary hue stops around the 360-degree wheel.
  static const List<Color> _hueColors = <Color>[
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  /// Subtle border color around the outer wheel and thumb ring.
  final Color borderColor;

  /// Currently selected HSV color.
  final HSVColor hsvColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final huePaint = Paint()
      ..shader = const SweepGradient(colors: _hueColors).createShader(rect);
    canvas.drawCircle(center, radius, huePaint);

    final saturationPaint = Paint()
      ..shader = const RadialGradient(
        colors: <Color>[Colors.white, Color(0x00FFFFFF)],
      ).createShader(rect);
    canvas.drawCircle(center, radius, saturationPaint);

    final darknessAlpha = (1.0 - hsvColor.value).clamp(0.0, 1.0);
    if (darknessAlpha > 0) {
      final valuePaint = Paint()
        ..color = Colors.black.withValues(alpha: darknessAlpha);
      canvas.drawCircle(center, radius, valuePaint);
    }

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, borderPaint);

    _paintThumb(canvas, center, radius);
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return oldDelegate.hsvColor != hsvColor ||
        oldDelegate.borderColor != borderColor;
  }

  /// Paints the circular selection indicator at the polar coordinates of [hsvColor].
  void _paintThumb(Canvas canvas, Offset center, double radius) {
    final angleRadians = hsvColor.hue * math.pi / 180.0;
    final radialDistance = hsvColor.saturation * radius;
    final thumbCenter = Offset(
      center.dx + math.cos(angleRadians) * radialDistance,
      center.dy + math.sin(angleRadians) * radialDistance,
    );

    final fillPaint = Paint()
      ..color = hsvColor.toColor()
      ..style = PaintingStyle.fill;
    final outerStrokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final innerStrokePaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(thumbCenter, 10, fillPaint);
    canvas.drawCircle(thumbCenter, 10, outerStrokePaint);
    canvas.drawCircle(thumbCenter, 11, innerStrokePaint);
  }
}

/// Interactive 2D circular HSV hue-saturation color wheel widget.
class _ColorWheelPicker extends StatelessWidget {
  /// Creates a [_ColorWheelPicker].
  const _ColorWheelPicker({
    required this.diameter,
    required this.hsvColor,
    required this.onColorChanged,
  });

  /// Logical pixel diameter of the circular color wheel.
  final double diameter;

  /// Currently selected HSV color.
  final HSVColor hsvColor;

  /// Callback invoked when the user taps or drags to select a new hue and saturation.
  final ValueChanged<HSVColor> onColorChanged;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    return Center(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: GestureDetector(
          key: const ValueKey('label_color_picker_wheel'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _handleOffset(details.localPosition),
          onPanStart: (details) => _handleOffset(details.localPosition),
          onPanUpdate: (details) => _handleOffset(details.localPosition),
          child: CustomPaint(
            painter: _ColorWheelPainter(
              hsvColor: hsvColor,
              borderColor: appTheme.mutedTextColor.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }

  /// Converts a local pointer [position] inside the wheel box to HSV hue and saturation.
  void _handleOffset(Offset position) {
    final radius = diameter / 2;
    final deltaX = position.dx - radius;
    final deltaY = position.dy - radius;
    final distance = math.sqrt(deltaX * deltaX + deltaY * deltaY);
    final saturation = (distance / radius).clamp(0.0, 1.0);
    final angleRadians = math.atan2(deltaY, deltaX);
    final hueDegrees = (angleRadians * 180.0 / math.pi + 360.0) % 360.0;
    onColorChanged(hsvColor.withHue(hueDegrees).withSaturation(saturation));
  }
}

/// Body column of [LabelColorPickerDialog] containing the preview header, color wheel, and brightness slider.
class _DialogBody extends StatelessWidget {
  /// Creates a [_DialogBody].
  const _DialogBody({
    required this.formattedHex,
    required this.hsvColor,
    required this.onBrightnessChanged,
    required this.onWheelChanged,
  });

  /// Canonical uppercase `#RRGGBB` string of the current selection.
  final String formattedHex;

  /// Current HSV color selection.
  final HSVColor hsvColor;

  /// Callback invoked when the brightness slider changes.
  final ValueChanged<double> onBrightnessChanged;

  /// Callback invoked when the color wheel selection changes.
  final ValueChanged<HSVColor> onWheelChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PreviewHeaderRow(
              color: hsvColor.toColor(),
              formattedHex: formattedHex,
            ),
            const SizedBox(height: 16),
            _ColorWheelPicker(
              diameter: 210,
              hsvColor: hsvColor,
              onColorChanged: onWheelChanged,
            ),
            const SizedBox(height: 16),
            _BrightnessSliderRow(
              hsvColor: hsvColor,
              onChanged: onBrightnessChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// State for [LabelColorPickerDialog].
class _LabelColorPickerDialogState extends State<LabelColorPickerDialog> {
  late HSVColor _hsvColor;

  /// Canonical uppercase `#RRGGBB` hexadecimal representation of [_hsvColor].
  String get _formattedHex =>
      TdfColor.formatArgb(_hsvColor.toColor().toARGB32());

  @override
  void initState() {
    super.initState();
    _hsvColor = LabelColorPickerDialog.resolveInitialHsv(widget.initialHex);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('label_color_picker_dialog'),
      title: Text(localizations.labelColorPickerDialogTitle),
      content: _DialogBody(
        formattedHex: _formattedHex,
        hsvColor: _hsvColor,
        onBrightnessChanged: _handleBrightnessChanged,
        onWheelChanged: _handleWheelChanged,
      ),
      actions: [
        TextButton(
          key: const ValueKey('label_color_picker_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('label_color_picker_confirm_button'),
          onPressed: _handleConfirm,
          child: Text(localizations.actionSelectColor),
        ),
      ],
    );
  }

  /// Updates the brightness (`value`) component of [_hsvColor].
  void _handleBrightnessChanged(double nextValue) {
    setState(() {
      _hsvColor = _hsvColor.withValue(nextValue.clamp(0.0, 1.0));
    });
  }

  /// Logs and returns the selected `#RRGGBB` color string.
  void _handleConfirm() {
    final selectedHex = _formattedHex;
    AppLogger.info(LogTag.ui, 'Selected custom label color hex=$selectedHex');
    Navigator.of(context).pop(selectedHex);
  }

  /// Updates [_hsvColor] when the user taps or drags on the color wheel.
  void _handleWheelChanged(HSVColor nextColor) {
    setState(() {
      _hsvColor = nextColor;
    });
  }
}

/// Live color swatch and `#RRGGBB` hexadecimal text readout header inside [LabelColorPickerDialog].
class _PreviewHeaderRow extends StatelessWidget {
  /// Creates a [_PreviewHeaderRow].
  const _PreviewHeaderRow({required this.color, required this.formattedHex});

  /// Currently selected color.
  final Color color;

  /// Canonical uppercase `#RRGGBB` representation of [color].
  final String formattedHex;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: appTheme.canvasColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: appTheme.mutedTextColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            key: const ValueKey('label_color_picker_preview'),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: appTheme.mutedTextColor.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formattedHex,
            key: const ValueKey('label_color_picker_hex_text'),
            style: TextStyle(
              color: appTheme.primaryTextColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [LabelColorPickerDialog] and returns the selected uppercase `#RRGGBB` color string, or `null` if canceled.
Future<String?> showLabelColorPickerDialog(
  BuildContext context, {
  String? initialHex,
}) {
  AppLogger.info(
    LogTag.ui,
    'Opened LabelColorPickerDialog initialHex=${initialHex ?? ''}',
  );
  return showDialog<String>(
    context: context,
    builder: (_) => LabelColorPickerDialog(initialHex: initialHex),
  );
}
