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

import '../primitives/ui_button.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_pill.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import 'ui_dialog_frame.dart';

/// Inline color swatch, `#RRGGBB` input, 8 canonical preset chips, and circular HSV wheel modal (`U-COMP-007`).
class UiColorWheel extends StatefulWidget {
  /// Creates a [UiColorWheel] with caller-supplied localized copy.
  const UiColorWheel({
    super.key,
    required this.value,
    required this.onChanged,
    required this.customButtonLabel,
    required this.modalTitle,
    required this.brightnessLabel,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.closeTooltip,
    required this.invalidHexError,
    this.inputLabel,
    this.enabled = true,
  });

  /// Canonical 8 TierTask label color presets (`U-COMP-007`).
  static const List<Color> canonicalPresets = <Color>[
    Color(0xFF2196F3),
    Color(0xFF4CAF50),
    Color(0xFFFF9100),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFEB06FF),
    Color(0xFF00E5FF),
  ];

  /// Localized label for the `0..100%` Value brightness slider inside the modal.
  final String brightnessLabel;

  /// Localized cancel button label in the custom color modal.
  final String cancelLabel;

  /// Accessible tooltip for the modal header close button.
  final String closeTooltip;

  /// Localized confirm button label in the custom color modal.
  final String confirmLabel;

  /// Localized label for the inline custom color modal trigger button.
  final String customButtonLabel;

  /// Whether inputs and triggers are enabled.
  final bool enabled;

  /// Optional localized field label displayed above the inline swatch/hex row.
  final String? inputLabel;

  /// Localized inline error displayed when a submitted hex value does not match `#RRGGBB`.
  final String invalidHexError;

  /// Localized heading title for the custom HSV wheel modal.
  final String modalTitle;

  /// Callback invoked with the committed opaque [Color].
  final ValueChanged<Color> onChanged;

  /// Active color value.
  final Color value;

  /// Formats [color] as uppercase `#RRGGBB`.
  static String formatHex(Color color) {
    final red = (color.r * 255.0).round().clamp(0, 255);
    final green = (color.g * 255.0).round().clamp(0, 255);
    final blue = (color.b * 255.0).round().clamp(0, 255);
    final hex = ((red << 16) | (green << 8) | blue)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    return '#$hex';
  }

  /// Converts a local pointer position on a circular HSV wheel of [size] to [HSVColor] at brightness [value].
  static HSVColor hsvFromWheelOffset(
    Offset localPosition,
    Size size,
    double value,
  ) {
    final radius = math.min(size.width, size.height) / 2.0;
    if (radius <= 0.0) {
      return HSVColor.fromAHSV(1.0, 0.0, 0.0, value.clamp(0.0, 1.0));
    }
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final saturation = (distance / radius).clamp(0.0, 1.0);
    final radians = math.atan2(dy, dx);
    var degrees = radians * 180.0 / math.pi;
    if (degrees < 0.0) {
      degrees += 360.0;
    }
    return HSVColor.fromAHSV(
      1.0,
      degrees % 360.0,
      saturation,
      value.clamp(0.0, 1.0),
    );
  }

  /// Validates and parses an exact 7-character `#RRGGBB` hex string (case-insensitive).
  static Color? tryParseHex(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length != 7 || trimmed.codeUnitAt(0) != 0x23) {
      return null;
    }
    final parsed = int.tryParse(trimmed.substring(1), radix: 16);
    if (parsed == null) {
      return null;
    }
    return Color(0xFF000000 | parsed);
  }

  @override
  State<UiColorWheel> createState() => _UiColorWheelState();
}

/// Manages synchronized `#RRGGBB` input text, validation state, and HSV wheel modal launching for [UiColorWheel].
class _UiColorWheelState extends State<UiColorWheel> {
  /// Text controller backing the `110px` mono `#RRGGBB` input.
  late final TextEditingController _hexController;

  /// Validation error message shown when the user enters invalid hex syntax.
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text: UiColorWheel.formatHex(widget.value),
    );
  }

  @override
  void didUpdateWidget(covariant UiColorWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final formatted = UiColorWheel.formatHex(widget.value);
    if (UiColorWheel.formatHex(oldWidget.value) != formatted &&
        _hexController.text.toUpperCase() != formatted) {
      _hexController.text = formatted;
      _errorText = null;
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final activeHex = UiColorWheel.formatHex(widget.value);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.inputLabel case final label?) ...<Widget>[
          Text(
            label,
            style: tokens.typography.meta.copyWith(
              color: colors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6.0),
        ],
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ExcludeSemantics(
              child: Container(
                width: tokens.spacing.chromeControlHeight,
                height: tokens.spacing.chromeControlHeight,
                decoration: BoxDecoration(
                  color: widget.value,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.line,
                    width: tokens.radii.borderWidth,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 110.0,
              child: UiField(
                controller: _hexController,
                enabled: widget.enabled,
                maxLength: 7,
                isMonospace: true,
                height: tokens.spacing.chromeControlHeight,
                onChanged: _handleHexChanged,
                onSubmitted: _commitHexInput,
              ),
            ),
            UiButton(
              label: widget.customButtonLabel,
              leadingIcon: Icons.palette_outlined,
              density: UiButtonDensity.compact,
              onPressed: widget.enabled ? _openWheelModal : null,
            ),
          ],
        ),
        if (_errorText case final error?) ...<Widget>[
          const SizedBox(height: 4.0),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: tokens.typography.meta.copyWith(
                color: colors.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10.0),
        Wrap(
          spacing: 6.0,
          runSpacing: 6.0,
          children: <Widget>[
            for (final preset in UiColorWheel.canonicalPresets)
              UiPill(
                label: UiColorWheel.formatHex(preset),
                variant: UiPillVariant.selectable,
                colorDot: preset,
                isMono: true,
                enabled: widget.enabled,
                isSelected: UiColorWheel.formatHex(preset) == activeHex,
                onPressed: widget.enabled ? () => _selectColor(preset) : null,
              ),
          ],
        ),
      ],
    );
  }

  /// Validates and commits [raw] `#RRGGBB` input, normalizing to uppercase on success.
  void _commitHexInput(String raw) {
    final parsed = UiColorWheel.tryParseHex(raw);
    if (parsed == null) {
      setState(() => _errorText = widget.invalidHexError);
      return;
    }
    _selectColor(parsed);
  }

  /// Clears error eagerly when the user types a valid `#RRGGBB` hex string.
  void _handleHexChanged(String raw) {
    final parsed = UiColorWheel.tryParseHex(raw);
    if (parsed != null) {
      if (_errorText != null) {
        setState(() => _errorText = null);
      }
      widget.onChanged(parsed);
    }
  }

  /// Opens the focused `small` HSV wheel modal and commits the returned color.
  Future<void> _openWheelModal() async {
    final picked = await UiDialogFrame.showModal<Color>(
      context: context,
      barrierLabel: widget.modalTitle,
      builder: (dialogContext) {
        return _UiColorWheelModal(
          initialColor: widget.value,
          title: widget.modalTitle,
          brightnessLabel: widget.brightnessLabel,
          cancelLabel: widget.cancelLabel,
          confirmLabel: widget.confirmLabel,
          closeTooltip: widget.closeTooltip,
        );
      },
    );
    if (mounted && picked != null) {
      _selectColor(picked);
    }
  }

  /// Updates the hex controller and emits [color] to caller.
  void _selectColor(Color color) {
    final normalized = UiColorWheel.formatHex(color);
    _hexController.text = normalized;
    _hexController.selection = TextSelection.collapsed(
      offset: normalized.length,
    );
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
    widget.onChanged(color);
  }
}

/// Modal dialog presenting the live preview bar, `210x210px` HSV wheel canvas, and Value slider (`U-COMP-007`).
class _UiColorWheelModal extends StatefulWidget {
  /// Creates a [_UiColorWheelModal].
  const _UiColorWheelModal({
    required this.initialColor,
    required this.title,
    required this.brightnessLabel,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.closeTooltip,
  });

  /// Brightness slider label.
  final String brightnessLabel;

  /// Cancel button copy.
  final String cancelLabel;

  /// Close button tooltip.
  final String closeTooltip;

  /// Confirm button copy.
  final String confirmLabel;

  /// Initial selected color.
  final Color initialColor;

  /// Modal title.
  final String title;

  @override
  State<_UiColorWheelModal> createState() => _UiColorWheelModalState();
}

/// Owns the local `ValueNotifier<HSVColor>` driving smooth canvas + preview updates without rebuilding parent trees.
class _UiColorWheelModalState extends State<_UiColorWheelModal> {
  /// Local HSV state notifier disposed cleanly in [dispose].
  late final ValueNotifier<HSVColor> _hsvNotifier;

  @override
  void initState() {
    super.initState();
    _hsvNotifier = ValueNotifier<HSVColor>(
      HSVColor.fromColor(widget.initialColor),
    );
  }

  @override
  void dispose() {
    _hsvNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return UiDialogFrame(
      title: widget.title,
      size: UiDialogSize.small,
      closeTooltip: widget.closeTooltip,
      onClose: () => Navigator.of(context).pop(),
      body: ValueListenableBuilder<HSVColor>(
        valueListenable: _hsvNotifier,
        builder: (context, hsv, _) {
          final currentColor = hsv.toColor();
          final currentHex = UiColorWheel.formatHex(currentColor);
          final brightnessPercent = (hsv.value * 100.0).round();

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(tokens.radii.row),
                  border: Border.all(
                    color: colors.line,
                    width: tokens.radii.borderWidth,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 10.0,
                  ),
                  child: Row(
                    children: <Widget>[
                      ExcludeSemantics(
                        child: Container(
                          width: 30.0,
                          height: 30.0,
                          decoration: BoxDecoration(
                            color: currentColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.line,
                              width: tokens.radii.borderWidth,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      Text(
                        currentHex,
                        style: UiTypographyTokens.mono(
                          tokens.typography.cardTitle.copyWith(
                            color: colors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              Center(
                child: _UiHsvWheelCanvas(
                  hsvColor: hsv,
                  borderColor: colors.line,
                  onChanged: (nextHsv) => _hsvNotifier.value = nextHsv,
                ),
              ),
              const SizedBox(height: 14.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    widget.brightnessLabel,
                    style: tokens.typography.meta.copyWith(
                      color: colors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '$brightnessPercent%',
                    style: UiTypographyTokens.tabular(
                      tokens.typography.meta.copyWith(color: colors.muted),
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: colors.accent,
                  inactiveTrackColor: colors.line,
                  thumbColor: colors.accent,
                  overlayColor: colors.soft,
                ),
                child: Slider(
                  value: hsv.value,
                  onChanged: (nextValue) {
                    _hsvNotifier.value = hsv.withValue(nextValue);
                  },
                ),
              ),
            ],
          );
        },
      ),
      footer: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiButton(
            label: widget.cancelLabel,
            density: UiButtonDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8.0),
          UiButton(
            label: widget.confirmLabel,
            variant: UiButtonVariant.primary,
            density: UiButtonDensity.compact,
            onPressed: () =>
                Navigator.of(context).pop(_hsvNotifier.value.toColor()),
          ),
        ],
      ),
    );
  }
}

/// Interactive `210x210px` circular HSV hue/saturation wheel surface (`U-COMP-007`).
class _UiHsvWheelCanvas extends StatelessWidget {
  /// Creates a [_UiHsvWheelCanvas].
  const _UiHsvWheelCanvas({
    required this.hsvColor,
    required this.borderColor,
    required this.onChanged,
  });

  /// Canonical circular wheel diameter (`210px`).
  static const double _wheelSize = 210.0;

  /// Outer hairline border color.
  final Color borderColor;

  /// Current HSV value.
  final HSVColor hsvColor;

  /// Callback invoked during tap or drag interaction.
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    const size = Size.square(_wheelSize);
    return GestureDetector(
      key: const ValueKey<String>('ui_color_wheel_canvas'),
      onTapDown: (details) {
        onChanged(
          UiColorWheel.hsvFromWheelOffset(
            details.localPosition,
            size,
            hsvColor.value,
          ),
        );
      },
      onPanStart: (details) {
        onChanged(
          UiColorWheel.hsvFromWheelOffset(
            details.localPosition,
            size,
            hsvColor.value,
          ),
        );
      },
      onPanUpdate: (details) {
        onChanged(
          UiColorWheel.hsvFromWheelOffset(
            details.localPosition,
            size,
            hsvColor.value,
          ),
        );
      },
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: _wheelSize,
          child: CustomPaint(
            painter: _UiHsvWheelPainter(
              hsvColor: hsvColor,
              borderColor: borderColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter rendering the circular HSV wheel, darkness overlay, and double-halo selection thumb.
class _UiHsvWheelPainter extends CustomPainter {
  /// Creates a [_UiHsvWheelPainter].
  const _UiHsvWheelPainter({required this.hsvColor, required this.borderColor});

  /// Primary and secondary hue stops around 360 degrees.
  static const List<Color> _hueStops = <Color>[
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  /// Outer wheel hairline border color.
  final Color borderColor;

  /// Current HSV color determining darkness overlay and thumb position.
  final HSVColor hsvColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2.0;
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final huePaint = Paint()
      ..shader = const SweepGradient(colors: _hueStops).createShader(rect);
    canvas.drawCircle(center, radius, huePaint);

    final saturationPaint = Paint()
      ..shader = const RadialGradient(
        colors: <Color>[Colors.white, Color(0x00FFFFFF)],
      ).createShader(rect);
    canvas.drawCircle(center, radius, saturationPaint);

    final darkness = (1.0 - hsvColor.value).clamp(0.0, 1.0);
    if (darkness > 0.0) {
      final valuePaint = Paint()
        ..color = Colors.black.withValues(alpha: darkness);
      canvas.drawCircle(center, radius, valuePaint);
    }

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius - 0.5, borderPaint);

    _paintThumb(canvas, center, radius);
  }

  @override
  bool shouldRepaint(covariant _UiHsvWheelPainter oldDelegate) {
    return oldDelegate.hsvColor != hsvColor ||
        oldDelegate.borderColor != borderColor;
  }

  /// Paints the `8px`-radius filled thumb with `2.5px` white + `1px` dark double halo.
  void _paintThumb(Canvas canvas, Offset center, double radius) {
    final angle = hsvColor.hue * math.pi / 180.0;
    final radial = hsvColor.saturation * radius;
    final thumbCenter = Offset(
      center.dx + math.cos(angle) * radial,
      center.dy + math.sin(angle) * radial,
    );

    canvas.drawCircle(thumbCenter, 8.0, Paint()..color = hsvColor.toColor());
    canvas.drawCircle(
      thumbCenter,
      8.0,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
      thumbCenter,
      9.25,
      Paint()
        ..color = const Color.fromRGBO(0, 0, 0, 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }
}
