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

import 'package:flutter/material.dart';

/// Interactive HSV hue-saturation color wheel widget for selecting a color.
class ColorWheelPicker extends StatelessWidget {
  /// Creates a [ColorWheelPicker] with [selectedColor] and [onColorChanged].
  const ColorWheelPicker({
    super.key,
    required this.selectedColor,
    required this.onColorChanged,
    this.diameter = 148,
  });

  /// Diameter of the circular color wheel in logical pixels.
  final double diameter;

  /// Callback invoked whenever the user taps or drags on the color wheel.
  final ValueChanged<Color> onColorChanged;

  /// Currently active color displayed by the thumb indicator on the wheel.
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _emitColorAt(details.localPosition),
        onPanUpdate: (details) => _emitColorAt(details.localPosition),
        child: CustomPaint(
          painter: _ColorWheelPainter(selectedColor: selectedColor),
        ),
      ),
    );
  }

  /// Resolves the HSV color at [localPosition] inside the wheel and invokes [onColorChanged].
  void _emitColorAt(Offset localPosition) {
    final radius = diameter / 2;
    if (radius <= 0) {
      return;
    }
    final deltaX = localPosition.dx - radius;
    final deltaY = localPosition.dy - radius;
    final distance = math.sqrt(deltaX * deltaX + deltaY * deltaY);
    final saturation = (distance / radius).clamp(0.0, 1.0);
    final angleRadians = math.atan2(deltaY, deltaX);
    final hueDegrees = (angleRadians * 180.0 / math.pi + 360.0) % 360.0;
    final resolved = HSVColor.fromAHSV(1.0, hueDegrees, saturation, 1.0);
    onColorChanged(resolved.toColor());
  }
}

/// Custom painter rendering the HSV hue-saturation wheel and selection thumb.
class _ColorWheelPainter extends CustomPainter {
  /// Creates a [_ColorWheelPainter] for [selectedColor].
  const _ColorWheelPainter({required this.selectedColor});

  static const List<Color> _hueSpectrum = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  /// Active color determining the thumb position and fill.
  final Color selectedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final wheelRect = Rect.fromCircle(center: center, radius: radius);

    final huePaint = Paint()
      ..shader = const SweepGradient(colors: _hueSpectrum)
          .createShader(wheelRect);
    canvas.drawCircle(center, radius, huePaint);

    final saturationPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withValues(alpha: 0.0)],
      ).createShader(wheelRect);
    canvas.drawCircle(center, radius, saturationPaint);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, borderPaint);

    _paintThumb(canvas, center, radius);
  }

  @override
  bool shouldRepaint(_ColorWheelPainter oldDelegate) {
    return oldDelegate.selectedColor != selectedColor;
  }

  /// Paints the circular selection thumb at the HSV `(hue, saturation)` offset of [selectedColor].
  void _paintThumb(Canvas canvas, Offset center, double radius) {
    final hsv = HSVColor.fromColor(selectedColor);
    final angleRadians = hsv.hue * math.pi / 180.0;
    final distance = hsv.saturation.clamp(0.0, 1.0) * radius;
    final thumbCenter = Offset(
      center.dx + distance * math.cos(angleRadians),
      center.dy + distance * math.sin(angleRadians),
    );

    final fillPaint = Paint()
      ..color = selectedColor
      ..style = PaintingStyle.fill;
    final outerStrokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final innerStrokePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(thumbCenter, 9, fillPaint);
    canvas.drawCircle(thumbCenter, 9, outerStrokePaint);
    canvas.drawCircle(thumbCenter, 10.5, innerStrokePaint);
  }
}
