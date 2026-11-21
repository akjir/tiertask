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

import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';

/// Vector application logo widget rendering the three stepped TierTask bars.
class AppLogo extends StatelessWidget {
  /// Creates an [AppLogo] widget with an optional square [size].
  const AppLogo({super.key = const ValueKey('app_logo'), this.size = 32.0});

  /// Width and height of the square logo in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppTheme.of(context).primaryAccent;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AppLogoPainter(accentColor: accentColor)),
    );
  }
}

/// Custom painter drawing the three stepped TierTask bars on a 22x22 grid.
class _AppLogoPainter extends CustomPainter {
  /// Creates a const [_AppLogoPainter] bound to [accentColor].
  const _AppLogoPainter({required this.accentColor});

  /// Rounded corner radius of each tier bar on the reference grid.
  static const double _barRadius = 2.0;

  /// Reference coordinate grid dimension matching the UI v2 three-bar mark.
  static const double _gridSize = 22.0;

  /// Accent color used to paint the three stepped tier bars.
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _gridSize;
    canvas.save();
    canvas.scale(scale, scale);
    _paintBar(canvas, const Rect.fromLTWH(0, 2, 22, 4), 1.0);
    _paintBar(canvas, const Rect.fromLTWH(0, 9, 16.5, 4), 0.72);
    _paintBar(canvas, const Rect.fromLTWH(0, 16, 11, 4), 0.42);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor;
  }

  /// Paints a single rounded tier bar at [rect] using [accentColor] at [opacity].
  void _paintBar(Canvas canvas, Rect rect, double opacity) {
    final paint = Paint()..color = accentColor.withValues(alpha: opacity);
    final roundedRect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_barRadius),
    );
    canvas.drawRRect(roundedRect, paint);
  }
}
