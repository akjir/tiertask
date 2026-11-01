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

import '../../l10n/app_localizations.dart';
import '../../l10n/tier_localization_extension.dart';
import '../../models/task_board.dart';
import '../../models/task_tier.dart';

const Color _activeAccentColor = Color(0xFF2196F3);
const double _addButtonSlotWidth = 88;
const double _barHeight = 72;
const Color _barSurfaceColor = Color(0xFF071A52);
const Color _borderLineColor = Color(0xFF344FA1);
const Color _inactiveIconColor = Color(0xFF9BA8E5);
const Color _plusButtonColor = Color(0xFFEB06FF);

/// Bottom navigation bar with highlighted active icon buttons and a right-aligned task creation button.
class BottomNavBar extends StatelessWidget {
  /// Creates a [BottomNavBar].
  const BottomNavBar({
    super.key,
    required this.activeButtonIndex,
    required this.isTierMenuOpen,
    required this.selectedTier,
    required this.onSelectFocus,
    required this.onToggleTierMenu,
    required this.onQuickAdd,
  });

  /// Zero-based index of the currently active navigation button (`0` for Focus, `1` for secondary tiers).
  final int activeButtonIndex;

  /// Whether the upward secondary-tier selection menu is currently open.
  final bool isTierMenuOpen;

  /// Callback invoked when the circular `+` button is pressed.
  final VoidCallback onQuickAdd;

  /// Callback invoked when the first (`Focus` overview) button is pressed.
  final VoidCallback onSelectFocus;

  /// Callback invoked when the second (upward tier selection) button is pressed.
  final VoidCallback onToggleTierMenu;

  /// Currently displayed [TaskTier] on the home screen.
  final TaskTier selectedTier;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final items = <_BottomNavButtonData>[
      _BottomNavButtonData(
        buttonKey: const ValueKey('bottom_nav_focus_button'),
        icon: Icons.home_rounded,
        isSelected: activeButtonIndex == 0 && !isTierMenuOpen,
        tooltip: localizations.tierName(TaskTier.focus),
        onTap: onSelectFocus,
      ),
      _BottomNavButtonData(
        buttonKey: const ValueKey('bottom_nav_tiers_button'),
        icon: Icons.view_agenda_rounded,
        isSelected: activeButtonIndex == 1 || isTierMenuOpen,
        tooltip: localizations.tierName(
          selectedTier == TaskTier.focus ? TaskTier.ready : selectedTier,
        ),
        onTap: onToggleTierMenu,
      ),
    ];

    return Container(
      key: const ValueKey('bottom_nav_bar'),
      height: _barHeight,
      decoration: const BoxDecoration(
        color: _barSurfaceColor,
        border: Border(top: BorderSide(color: _borderLineColor, width: 1.5)),
      ),
      child: _BottomNavBarBody(items: items, onQuickAdd: onQuickAdd),
    );
  }
}

/// Upward floating selection menu for switching between secondary [TaskTier] views.
class UpwardTierSelectionMenu extends StatelessWidget {
  /// Creates an [UpwardTierSelectionMenu].
  const UpwardTierSelectionMenu({
    super.key,
    required this.board,
    required this.selectedTier,
    required this.onSelectTier,
  });

  /// Secondary tiers available in the upward selection popup.
  static const List<TaskTier> secondaryTiers = [
    TaskTier.ready,
    TaskTier.planned,
    TaskTier.blocked,
    TaskTier.someday,
    TaskTier.completed,
  ];

  /// Current [TaskBoard] snapshot used to display task counts per tier.
  final TaskBoard board;

  /// Callback invoked when a [TaskTier] option is selected.
  final ValueChanged<TaskTier> onSelectTier;

  /// Currently active [TaskTier].
  final TaskTier selectedTier;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('upward_tier_menu'),
      color: _barSurfaceColor,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: _borderLineColor, width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final tier in secondaryTiers)
                _UpwardTierOptionTile(
                  key: ValueKey('upward_tier_option_${tier.name}'),
                  count: board.tasksForTier(tier).length,
                  isSelected: selectedTier == tier,
                  tier: tier,
                  onTap: () => onSelectTier(tier),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row body inside [BottomNavBar] arranging the navigation buttons and right-aligned `+` button.
class _BottomNavBarBody extends StatelessWidget {
  /// Creates a [_BottomNavBarBody].
  const _BottomNavBarBody({required this.items, required this.onQuickAdd});

  /// Navigation button descriptors.
  final List<_BottomNavButtonData> items;

  /// Callback for the task creation button.
  final VoidCallback onQuickAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              for (final item in items)
                Expanded(child: _BottomNavIconButton(item: item)),
            ],
          ),
        ),
        SizedBox(
          width: _addButtonSlotWidth,
          child: Center(
            child: FloatingActionButton(
              backgroundColor: _plusButtonColor,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              onPressed: onQuickAdd,
              child: const Icon(Icons.add_rounded, size: 28),
            ),
          ),
        ),
      ],
    );
  }
}

/// Immutable configuration for a single navigation button inside [BottomNavBar].
@immutable
class _BottomNavButtonData {
  /// Creates a [_BottomNavButtonData].
  const _BottomNavButtonData({
    required this.buttonKey,
    required this.icon,
    required this.isSelected,
    required this.tooltip,
    required this.onTap,
  });

  /// Deterministic widget key for the button.
  final Key buttonKey;

  /// Icon displayed inside the button.
  final IconData icon;

  /// Whether this navigation item is currently active.
  final bool isSelected;

  /// Callback invoked when the button is tapped.
  final VoidCallback onTap;

  /// Accessibility tooltip label.
  final String tooltip;
}

/// Individual icon button rendered inside [BottomNavBar].
class _BottomNavIconButton extends StatelessWidget {
  /// Creates a [_BottomNavIconButton].
  const _BottomNavIconButton({required this.item});

  /// Button descriptor to render.
  final _BottomNavButtonData item;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.tooltip,
      child: InkWell(
        key: item.buttonKey,
        borderRadius: BorderRadius.circular(16),
        onTap: item.onTap,
        child: SizedBox(
          height: 52,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: item.isSelected
                    ? _activeAccentColor.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item.icon,
                size: 26,
                color: item.isSelected
                    ? _activeAccentColor
                    : _inactiveIconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Single option row inside [UpwardTierSelectionMenu].
class _UpwardTierOptionTile extends StatelessWidget {
  /// Creates an [_UpwardTierOptionTile].
  const _UpwardTierOptionTile({
    super.key,
    required this.count,
    required this.isSelected,
    required this.tier,
    required this.onTap,
  });

  /// Number of tasks currently in [tier].
  final int count;

  /// Whether [tier] is the currently active tier view.
  final bool isSelected;

  /// Callback invoked when this option is tapped.
  final VoidCallback onTap;

  /// Secondary [TaskTier] represented by this option.
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForTier(tier),
              size: 20,
              color: isSelected ? _activeAccentColor : _inactiveIconColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                localizations.tierName(tier),
                style: TextStyle(
                  color: isSelected ? Colors.white : _inactiveIconColor,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? _activeAccentColor.withValues(alpha: 0.25)
                    : _borderLineColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : _inactiveIconColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Resolves the leading icon for [tier].
  IconData _iconForTier(TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => Icons.bolt_rounded,
      TaskTier.ready => Icons.play_circle_outline_rounded,
      TaskTier.planned => Icons.schedule_rounded,
      TaskTier.blocked => Icons.block_rounded,
      TaskTier.someday => Icons.lightbulb_outline_rounded,
      TaskTier.completed => Icons.check_circle_outline_rounded,
    };
  }
}
