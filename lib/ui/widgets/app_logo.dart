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

import '../app_theme.dart';

/// Vector application logo widget rendering the stacked tier bars and completion checkmark.
class AppLogo extends StatelessWidget {
  /// Creates an [AppLogo] widget with an optional square [size].
  const AppLogo({super.key = const ValueKey('app_logo'), this.size = 32.0});

  /// Width and height of the square logo in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AppLogoPainter(appTheme: appTheme)),
    );
  }
}

/// Custom painter drawing the TierTask stacked tier bars and checkmark badge on a 512x512 grid.
class _AppLogoPainter extends CustomPainter {
  /// Creates a const [_AppLogoPainter] bound to [appTheme].
  const _AppLogoPainter({required this.appTheme});

  /// Reference coordinate grid dimension matching `assets/logo/tiertask_logo.svg`.
  static const double _gridSize = 512.0;

  /// Active application theme providing logo surface and bar gradient tokens.
  final AppTheme appTheme;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _gridSize;
    canvas.save();
    canvas.scale(scale, scale);
    _paintBackground(canvas);
    _paintTierBars(canvas);
    _paintCheckmarkBadge(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter oldDelegate) {
    return oldDelegate.appTheme != appTheme;
  }

  /// Paints a single rounded tier bar at [rect] with a horizontal gradient from [start] to [end].
  void _paintBar(Canvas canvas, Rect rect, Color start, Color end) {
    final paint = Paint()
      ..shader = LinearGradient(colors: [start, end]).createShader(rect);
    final roundedRect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(28),
    );
    canvas.drawRRect(roundedRect, paint);
  }

  /// Paints the squircle background and subtle accent inner border.
  void _paintBackground(Canvas canvas) {
    const rect = Rect.fromLTWH(0, 0, _gridSize, _gridSize);
    final backgroundRRect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(112),
    );
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [appTheme.logoBackgroundStart, appTheme.logoBackgroundEnd],
      ).createShader(rect);
    canvas.drawRRect(backgroundRRect, fillPaint);

    final borderPaint = Paint()
      ..color = appTheme.logoTier1Start.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawRRect(backgroundRRect.deflate(3), borderPaint);
  }

  /// Paints the circular completion badge with a cutout halo and checkmark.
  void _paintCheckmarkBadge(Canvas canvas) {
    const center = Offset(348, 332);
    final haloPaint = Paint()..color = appTheme.logoBackgroundEnd;
    canvas.drawCircle(center, 98, haloPaint);

    final badgeRect = Rect.fromCircle(center: center, radius: 82);
    final badgePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [appTheme.logoTier1Start, appTheme.logoTier2End],
      ).createShader(badgeRect);
    canvas.drawCircle(center, 82, badgePaint);

    final checkPath = Path()
      ..moveTo(308, 334)
      ..lineTo(336, 362)
      ..lineTo(392, 302);
    final checkPaint = Paint()
      ..color = appTheme.onPrimaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(checkPath, checkPaint);
  }

  /// Paints the three stacked horizontal tier bars representing Focus, Ready, and Planned.
  void _paintTierBars(Canvas canvas) {
    _paintBar(
      canvas,
      const Rect.fromLTWH(96, 116, 320, 56),
      appTheme.logoTier1Start,
      appTheme.logoTier1End,
    );
    _paintBar(
      canvas,
      const Rect.fromLTWH(96, 204, 248, 56),
      appTheme.logoTier2Start,
      appTheme.logoTier2End,
    );
    _paintBar(
      canvas,
      const Rect.fromLTWH(96, 292, 176, 56),
      appTheme.logoTier3Start,
      appTheme.logoTier3End,
    );
  }
}
