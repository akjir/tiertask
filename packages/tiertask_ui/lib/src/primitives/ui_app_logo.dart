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

import '../tokens/ui_theme_tokens.dart';

/// Immutable bar geometry and opacity specification for [UiAppLogo].
@immutable
class UiLogoBarSpec {
  /// Creates a [UiLogoBarSpec] with [rect] on the `22x22` grid and [opacity].
  const UiLogoBarSpec({required this.rect, required this.opacity});

  /// Opacity multiplier applied to the active accent color (`0.0..1.0`).
  final double opacity;

  /// Bar bounds on the canonical `22x22` reference grid.
  final Rect rect;
}

/// Minimal three-bar stepped TierTask brand mark (`U-BRAND-001`).
class UiAppLogo extends StatelessWidget {
  /// Creates a [UiAppLogo] rendered at square [size] in [color] (defaults to `accent`).
  const UiAppLogo({super.key, this.size = 22.0, this.color});

  /// Canonical three stepped bars on the `22x22` grid (`100%/1.0`, `75%/0.72`, `50%/0.42`).
  static const List<UiLogoBarSpec> barSpecs = <UiLogoBarSpec>[
    UiLogoBarSpec(rect: Rect.fromLTWH(0.0, 2.0, 22.0, 4.0), opacity: 1.0),
    UiLogoBarSpec(rect: Rect.fromLTWH(0.0, 9.0, 16.5, 4.0), opacity: 0.72),
    UiLogoBarSpec(rect: Rect.fromLTWH(0.0, 16.0, 11.0, 4.0), opacity: 0.42),
  ];

  /// Optional explicit fill color overriding `tokens.colors.accent`.
  final Color? color;

  /// Width and height of the square brand mark in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final activeColor = color ?? tokens.colors.accent;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _UiAppLogoPainter(
            color: activeColor,
            barRadius: tokens.radii.logoBar,
          ),
        ),
      ),
    );
  }
}

/// Custom painter drawing the three stepped horizontal TierTask bars on a `22x22` grid.
class _UiAppLogoPainter extends CustomPainter {
  /// Creates a [_UiAppLogoPainter] bound to [color] and [barRadius].
  const _UiAppLogoPainter({required this.color, required this.barRadius});

  /// Reference coordinate grid dimension.
  static const double _gridSize = 22.0;

  /// Corner radius of each horizontal bar on the reference grid.
  final double barRadius;

  /// Active accent fill color.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _gridSize;
    canvas.save();
    canvas.scale(scale, scale);
    for (final spec in UiAppLogo.barSpecs) {
      final paint = Paint()..color = color.withValues(alpha: spec.opacity);
      final roundedRect = RRect.fromRectAndRadius(
        spec.rect,
        Radius.circular(barRadius),
      );
      canvas.drawRRect(roundedRect, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UiAppLogoPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.barRadius != barRadius;
  }
}
