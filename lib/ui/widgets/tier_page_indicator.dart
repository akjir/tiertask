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

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/tier_localization_extension.dart';
import '../../models/task_tier.dart';
import '../app_theme.dart';

const double _baseDotDiameter = 8.0;
const double _indicatorHeight = 48.0;
const double _slotWidth = 48.0;
const double _trackWidth = _slotWidth * 6;

/// Bottom tier page indicator displaying dots for inactive tiers, an icon for the
/// active tier, a desktop hover icon and label without wave animation, desktop
/// Left/Right arrow key navigation, and an interactive wave effect on hold and drag.
class TierPageIndicator extends StatefulWidget {
  /// Creates a [TierPageIndicator].
  const TierPageIndicator({
    super.key,
    required this.activeTier,
    required this.onTierSelected,
  });

  /// Currently visible [TaskTier] pane.
  final TaskTier activeTier;

  /// Callback invoked when the user selects or releases on a target [TaskTier].
  final ValueChanged<TaskTier> onTierSelected;

  @override
  State<TierPageIndicator> createState() => _TierPageIndicatorState();

  /// Returns the Material icon representing [tier].
  static IconData iconForTier(TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => Icons.bolt_rounded,
      TaskTier.ready => Icons.playlist_play_rounded,
      TaskTier.planned => Icons.list_alt_rounded,
      TaskTier.blocked => Icons.block_rounded,
      TaskTier.someday => Icons.lightbulb_outline_rounded,
      TaskTier.completed => Icons.check_circle_outline_rounded,
    };
  }
}

/// Icon rendered for the active or desktop-hovered [TaskTier] without background or border.
class _TierIndicatorActiveIcon extends StatelessWidget {
  /// Creates a [_TierIndicatorActiveIcon].
  const _TierIndicatorActiveIcon({
    required this.color,
    required this.isScrubbing,
    required this.tier,
  });

  /// Icon foreground color.
  final Color color;

  /// Whether the indicator is currently being scrubbed in wave mode.
  final bool isScrubbing;

  /// [TaskTier] to display as an icon.
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    return Icon(
      TierPageIndicator.iconForTier(tier),
      key: ValueKey('tier_indicator_icon_${tier.name}'),
      size: isScrubbing ? 24 : 20,
      color: color,
    );
  }
}

/// Circular dot rendered for every unhovered inactive [TaskTier] in [TierPageIndicator].
class _TierIndicatorDot extends StatelessWidget {
  /// Creates a [_TierIndicatorDot].
  const _TierIndicatorDot({required this.isAdjacentInWave, required this.tier});

  /// Whether this dot immediately flanks the active tier during wave scrubbing (`1.5x` size).
  final bool isAdjacentInWave;

  /// Inactive [TaskTier] represented by this dot.
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    final diameter = isAdjacentInWave
        ? _baseDotDiameter * 1.5
        : _baseDotDiameter;
    return Container(
      key: ValueKey('tier_indicator_dot_${tier.name}'),
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: isAdjacentInWave
            ? appTheme.indicatorIntermediateColor
            : appTheme.indicatorInactiveDotColor,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Borderless floating pill label displaying the name of the scrubbed or hovered [TaskTier].
class _TierIndicatorNameLabel extends StatelessWidget {
  /// Creates a [_TierIndicatorNameLabel].
  const _TierIndicatorNameLabel({required this.label});

  /// Localized tier name to display.
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('tier_indicator_wave_label'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Visual representation of a single tier slot inside [TierPageIndicator].
class _TierIndicatorSlot extends StatelessWidget {
  /// Creates a [_TierIndicatorSlot].
  const _TierIndicatorSlot({
    required this.isActive,
    required this.isAdjacentInWave,
    required this.isHovered,
    required this.isScrubbing,
    required this.tier,
    required this.verticalOffset,
    required this.onHoverChanged,
  });

  /// Whether this slot represents the currently active or scrub-targeted tier.
  final bool isActive;

  /// Whether this slot immediately flanks the active tier during wave scrubbing (`1.5x` dot size).
  final bool isAdjacentInWave;

  /// Whether a desktop mouse pointer is currently hovering over this slot.
  final bool isHovered;

  /// Whether the wave scrub mode is active.
  final bool isScrubbing;

  /// Callback invoked when a desktop mouse enters or exits this slot.
  final ValueChanged<bool> onHoverChanged;

  /// Tier represented by this slot.
  final TaskTier tier;

  /// Vertical wave displacement in logical pixels (`0.0` when not scrubbing).
  final double verticalOffset;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    final showIcon = isActive || isHovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: Transform.translate(
        offset: Offset(0, verticalOffset),
        child: SizedBox(
          key: ValueKey('tier_indicator_item_${tier.name}'),
          height: _indicatorHeight,
          child: Center(
            child: showIcon
                ? _TierIndicatorActiveIcon(
                    color: isActive
                        ? appTheme.indicatorActiveIconColor
                        : appTheme.indicatorIntermediateColor,
                    isScrubbing: isScrubbing && isActive,
                    tier: tier,
                  )
                : _TierIndicatorDot(
                    isAdjacentInWave: isAdjacentInWave,
                    tier: tier,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Stack combining the floating tier name label and the 6 tier slots over a transparent background.
class _TierIndicatorTrack extends StatelessWidget {
  /// Creates a [_TierIndicatorTrack].
  const _TierIndicatorTrack({
    required this.activeTier,
    required this.hoveredTier,
    required this.isScrubbing,
    required this.labeledTier,
    required this.scrubPosition,
    required this.onHoverChanged,
  });

  /// Currently active or scrub-targeted [TaskTier].
  final TaskTier activeTier;

  /// Desktop mouse-hovered [TaskTier], if any.
  final TaskTier? hoveredTier;

  /// Whether wave scrubbing is currently active.
  final bool isScrubbing;

  /// Tier whose localized name should be rendered above the track, if any.
  final TaskTier? labeledTier;

  /// Callback invoked when a desktop mouse enters or exits a tier slot.
  final void Function(TaskTier tier, bool isHovered) onHoverChanged;

  /// Continuous fractional scrub position in `[0.0, 5.0]`.
  final double scrubPosition;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final currentLabelTier = labeledTier;

    return SizedBox(
      width: _trackWidth,
      height: _indicatorHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (currentLabelTier != null)
            Positioned(
              top: isScrubbing ? -52 : -32,
              child: _TierIndicatorNameLabel(
                label: localizations.tierName(currentLabelTier),
              ),
            ),
          Row(
            children: [
              for (var i = 0; i < TaskTier.values.length; i++)
                Expanded(
                  child: _TierIndicatorSlot(
                    tier: TaskTier.values[i],
                    isActive: TaskTier.values[i] == activeTier,
                    isAdjacentInWave:
                        isScrubbing && (i - activeTier.index).abs() == 1,
                    isHovered:
                        !isScrubbing && hoveredTier == TaskTier.values[i],
                    isScrubbing: isScrubbing,
                    verticalOffset: _computeWaveOffset(i),
                    onHoverChanged: (hovered) =>
                        onHoverChanged(TaskTier.values[i], hovered),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Computes the vertical wave displacement for slot [index].
  double _computeWaveOffset(int index) {
    if (!isScrubbing) {
      return 0.0;
    }
    final delta = index - scrubPosition;
    final wheelCurve = math.sin((index / 5.0) * math.pi) * 4.0;
    final waveCrest = math.exp(-(delta * delta) * 0.85) * 18.0;
    return -(wheelCurve + waveCrest);
  }
}

/// State for [TierPageIndicator].
class _TierPageIndicatorState extends State<TierPageIndicator> {
  TaskTier? _hoveredTier;
  bool _isScrubbing = false;
  double _scrubPosition = 0.0;

  /// Returns the tier currently highlighted by scrubbing or active page state.
  TaskTier get _effectiveTier {
    if (_isScrubbing) {
      return _tierFromPosition(_scrubPosition);
    }
    return widget.activeTier;
  }

  /// Returns the tier whose localized name should be displayed above the indicator, if any.
  TaskTier? get _labeledTier {
    if (_isScrubbing) {
      return _tierFromPosition(_scrubPosition);
    }
    return _hoveredTier;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('tier_page_indicator'),
      height: _indicatorHeight,
      width: double.infinity,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handleTapUp(details.localPosition.dx),
          onLongPressStart: (details) => _startScrub(details.localPosition.dx),
          onLongPressMoveUpdate: (details) =>
              _updateScrub(details.localPosition.dx),
          onLongPressEnd: (details) => _endScrub(details.localPosition.dx),
          onLongPressCancel: _cancelScrub,
          onHorizontalDragStart: (details) =>
              _startScrub(details.localPosition.dx),
          onHorizontalDragUpdate: (details) =>
              _updateScrub(details.localPosition.dx),
          onHorizontalDragEnd: (_) => _commitCurrentScrub(),
          onHorizontalDragCancel: _cancelScrub,
          child: _TierIndicatorTrack(
            activeTier: _effectiveTier,
            hoveredTier: _hoveredTier,
            isScrubbing: _isScrubbing,
            labeledTier: _labeledTier,
            scrubPosition: _scrubPosition,
            onHoverChanged: _handleHoverChanged,
          ),
        ),
      ),
    );
  }

  /// Cancels an active scrub gesture without changing the selected pane.
  void _cancelScrub() {
    if (!_isScrubbing) {
      return;
    }
    setState(() {
      _isScrubbing = false;
    });
  }

  /// Commits the current [_scrubPosition] and notifies [TierPageIndicator.onTierSelected].
  void _commitCurrentScrub() {
    if (!_isScrubbing) {
      return;
    }
    final selectedTier = _tierFromPosition(_scrubPosition);
    setState(() {
      _isScrubbing = false;
    });
    widget.onTierSelected(selectedTier);
  }

  /// Ends a long-press scrub at [localDx] and jumps to the corresponding tier pane.
  void _endScrub(double localDx) {
    final position = _positionFromDx(localDx);
    final selectedTier = _tierFromPosition(position);
    setState(() {
      _scrubPosition = position;
      _isScrubbing = false;
    });
    widget.onTierSelected(selectedTier);
  }

  /// Updates the hovered tier state on desktop mouse enter or exit without wave animation.
  void _handleHoverChanged(TaskTier tier, bool isHovered) {
    if (isHovered && _hoveredTier != tier) {
      setState(() {
        _hoveredTier = tier;
      });
      return;
    }
    if (!isHovered && _hoveredTier == tier) {
      setState(() {
        _hoveredTier = null;
      });
    }
  }

  /// Navigates between adjacent tier panes on desktop Left and Right arrow key presses.
  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return false;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true) ||
        _isEditableTextFocused()) {
      return false;
    }
    final currentIndex = widget.activeTier.index;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && currentIndex > 0) {
      widget.onTierSelected(TaskTier.values[currentIndex - 1]);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        currentIndex < TaskTier.values.length - 1) {
      widget.onTierSelected(TaskTier.values[currentIndex + 1]);
      return true;
    }
    return false;
  }

  /// Selects the tapped tier slot directly when clicked or tapped.
  void _handleTapUp(double localDx) {
    final tappedTier = _tierFromPosition(_positionFromDx(localDx));
    widget.onTierSelected(tappedTier);
  }

  /// Returns whether a text input field currently holds primary keyboard focus.
  bool _isEditableTextFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) {
      return false;
    }
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Converts a horizontal coordinate [localDx] inside the track into a `[0.0, 5.0]` index.
  double _positionFromDx(double localDx) {
    return ((localDx / _slotWidth) - 0.5).clamp(0.0, 5.0);
  }

  /// Starts wave scrubbing at [localDx].
  void _startScrub(double localDx) {
    setState(() {
      _isScrubbing = true;
      _scrubPosition = _positionFromDx(localDx);
    });
  }

  /// Resolves the discrete [TaskTier] nearest to fractional [position].
  TaskTier _tierFromPosition(double position) {
    final index = position.round().clamp(0, TaskTier.values.length - 1);
    return TaskTier.values[index];
  }

  /// Updates the wave peak position while the user drags across the indicator.
  void _updateScrub(double localDx) {
    setState(() {
      _isScrubbing = true;
      _scrubPosition = _positionFromDx(localDx);
    });
  }
}
