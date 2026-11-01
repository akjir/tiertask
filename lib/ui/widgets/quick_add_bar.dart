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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/tier_localization_extension.dart';
import '../../models/task_tier.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/task_providers.dart';

const Color _accentBlue = Color(0xFF2196F3);
const Color _accentCyan = Color(0xFF00E5FF);
const Color _accentMagenta = Color(0xFFEB06FF);
const Color _canvasColor = Color(0xFF344FA1);
const Color _cardColor = Color(0xFF071A52);
const Color _mutedLabelColor = Color(0xFF9BA8E5);
const String _popupTapRegionGroupId = 'quick_add_popup_region';

/// Inline bottom task creation bar with title input, Priority, Someday, upward Categories and Locations selectors, no-op Advanced, and Cancel actions.
class QuickAddBar extends ConsumerStatefulWidget {
  /// Creates a [QuickAddBar] widget.
  const QuickAddBar({super.key, this.onCancel, this.onSubmitted});

  /// Optional callback invoked when the cancel button is pressed.
  final VoidCallback? onCancel;

  /// Optional callback invoked after a non-empty task is submitted.
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

/// Mutually exclusive scheduling mode for creating a task in [QuickAddBar].
enum QuickAddMode {
  /// Default mode: adds the task to `# [3] Planned` (cascading up if slots are open).
  standard,

  /// Priority mode: marks the task as priority and places it into `# [1] Focus`.
  priority,

  /// Someday mode: places the task into `# [5] Someday` without automatic pull.
  someday;

  /// Target [TaskTier] corresponding to this mode.
  TaskTier get targetTier {
    return switch (this) {
      QuickAddMode.standard => TaskTier.planned,
      QuickAddMode.priority => TaskTier.focus,
      QuickAddMode.someday => TaskTier.someday,
    };
  }
}

/// Compact icon button rendered on the right side of [_QuickAddBarRow].
class _QuickAddActionIconButton extends StatelessWidget {
  /// Creates a [_QuickAddActionIconButton].
  const _QuickAddActionIconButton({
    required this.activeColor,
    required this.buttonKey,
    required this.icon,
    required this.isActive,
    required this.tooltip,
    required this.onTap,
  });

  /// Accent color applied when [isActive] is true.
  final Color activeColor;

  /// Deterministic widget key for the button.
  final Key buttonKey;

  /// Icon displayed inside the button.
  final IconData icon;

  /// Whether this button is currently toggled or expanded.
  final bool isActive;

  /// Callback invoked when the button is tapped.
  final VoidCallback onTap;

  /// Accessibility tooltip label.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                icon,
                size: 20,
                color: isActive ? activeColor : _mutedLabelColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Single-row layout inside [QuickAddBar] combining the text field and action icon buttons.
class _QuickAddBarRow extends StatelessWidget {
  /// Creates a [_QuickAddBarRow].
  const _QuickAddBarRow({
    required this.activePopup,
    required this.controller,
    required this.effectiveTier,
    required this.hasSelectedCategories,
    required this.hasSelectedLocations,
    required this.hasTaskText,
    required this.mode,
    required this.onAdvanced,
    required this.onCancel,
    required this.onSubmit,
    required this.onToggleCategoriesPopup,
    required this.onToggleLocationsPopup,
    required this.onTogglePriority,
    required this.onToggleSomeday,
  });

  /// Currently expanded upward popup menu.
  final _QuickAddPopup activePopup;

  /// Text controller for the task title input.
  final TextEditingController controller;

  /// Target tier corresponding to [mode].
  final TaskTier effectiveTier;

  /// Whether at least one category is selected.
  final bool hasSelectedCategories;

  /// Whether at least one location is selected.
  final bool hasSelectedLocations;

  /// Whether the task title input contains non-whitespace text.
  final bool hasTaskText;

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// No-op callback for the Advanced button.
  final VoidCallback onAdvanced;

  /// Callback invoked when the Cancel button is pressed.
  final VoidCallback onCancel;

  /// Callback invoked when the task is submitted.
  final VoidCallback onSubmit;

  /// Callback to toggle the upward Categories popup menu.
  final VoidCallback onToggleCategoriesPopup;

  /// Callback to toggle the upward Locations popup menu.
  final VoidCallback onToggleLocationsPopup;

  /// Callback to toggle Priority mode.
  final VoidCallback onTogglePriority;

  /// Callback to toggle Someday mode.
  final VoidCallback onToggleSomeday;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: _QuickAddTextField(
            controller: controller,
            effectiveTier: effectiveTier,
            hasText: hasTaskText,
            onSubmit: onSubmit,
          ),
        ),
        _QuickAddActionIconButton(
          buttonKey: const ValueKey('quick_add_priority_button'),
          icon: Icons.bolt_rounded,
          isActive: mode == QuickAddMode.priority,
          activeColor: _accentMagenta,
          tooltip: localizations.quickAddPriority,
          onTap: onTogglePriority,
        ),
        _QuickAddActionIconButton(
          buttonKey: const ValueKey('quick_add_someday_button'),
          icon: Icons.lightbulb_outline_rounded,
          isActive: mode == QuickAddMode.someday,
          activeColor: _accentBlue,
          tooltip: localizations.tierName(TaskTier.someday),
          onTap: onToggleSomeday,
        ),
        TapRegion(
          groupId: _popupTapRegionGroupId,
          child: _QuickAddActionIconButton(
            buttonKey: const ValueKey('quick_add_categories_button'),
            icon: Icons.label_outline_rounded,
            isActive:
                activePopup == _QuickAddPopup.categories ||
                hasSelectedCategories,
            activeColor: _accentMagenta,
            tooltip: localizations.drawerCategories,
            onTap: onToggleCategoriesPopup,
          ),
        ),
        TapRegion(
          groupId: _popupTapRegionGroupId,
          child: _QuickAddActionIconButton(
            buttonKey: const ValueKey('quick_add_locations_button'),
            icon: Icons.location_on_outlined,
            isActive:
                activePopup == _QuickAddPopup.locations || hasSelectedLocations,
            activeColor: _accentCyan,
            tooltip: localizations.drawerLocations,
            onTap: onToggleLocationsPopup,
          ),
        ),
        _QuickAddActionIconButton(
          buttonKey: const ValueKey('quick_add_advanced_button'),
          icon: Icons.tune_rounded,
          isActive: false,
          activeColor: _accentCyan,
          tooltip: localizations.quickAddAdvanced,
          onTap: onAdvanced,
        ),
        _QuickAddActionIconButton(
          buttonKey: const ValueKey('quick_add_cancel_button'),
          icon: Icons.close_rounded,
          isActive: false,
          activeColor: _mutedLabelColor,
          tooltip: localizations.actionCancel,
          onTap: onCancel,
        ),
      ],
    );
  }
}

/// State for [QuickAddBar].
class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  _QuickAddPopup _activePopup = _QuickAddPopup.none;
  final TextEditingController _controller = TextEditingController();
  QuickAddMode _mode = QuickAddMode.standard;
  final Set<String> _selectedCategoryIds = <String>{};
  final Set<String> _selectedLocationIds = <String>{};

  bool get _hasTaskText => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(
      taskNotifierProvider.select(
        (boardAsync) =>
            boardAsync.asData?.value.categories ?? const <TdfCategory>[],
      ),
    );
    final locations = ref.watch(
      taskNotifierProvider.select(
        (boardAsync) =>
            boardAsync.asData?.value.locations ?? const <TdfLocation>[],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_activePopup == _QuickAddPopup.categories)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.bottomRight,
              child: TapRegion(
                groupId: _popupTapRegionGroupId,
                onTapOutside: (_) => _dismissPopup(),
                child: _UpwardCategoriesMenu(
                  categories: categories,
                  selectedCategoryIds: _selectedCategoryIds,
                  onToggleCategory: _toggleCategory,
                ),
              ),
            ),
          ),
        if (_activePopup == _QuickAddPopup.locations)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.bottomRight,
              child: TapRegion(
                groupId: _popupTapRegionGroupId,
                onTapOutside: (_) => _dismissPopup(),
                child: _UpwardLocationsMenu(
                  locations: locations,
                  selectedLocationIds: _selectedLocationIds,
                  onToggleLocation: _toggleLocation,
                ),
              ),
            ),
          ),
        Material(
          key: const ValueKey('quick_add_bar'),
          elevation: 8,
          color: _cardColor,
          child: SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: _canvasColor, width: 1.5),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: _QuickAddBarRow(
                activePopup: _activePopup,
                controller: _controller,
                effectiveTier: _mode.targetTier,
                hasSelectedCategories: _selectedCategoryIds.isNotEmpty,
                hasSelectedLocations: _selectedLocationIds.isNotEmpty,
                hasTaskText: _hasTaskText,
                mode: _mode,
                onAdvanced: _handleAdvancedNoOp,
                onCancel: _cancel,
                onSubmit: _submit,
                onToggleCategoriesPopup: _toggleCategoriesPopup,
                onToggleLocationsPopup: _toggleLocationsPopup,
                onTogglePriority: _togglePriority,
                onToggleSomeday: _toggleSomeday,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Clears pending state and invokes [QuickAddBar.onCancel].
  void _cancel() {
    _controller.clear();
    setState(() {
      _activePopup = _QuickAddPopup.none;
      _selectedCategoryIds.clear();
      _selectedLocationIds.clear();
      _mode = QuickAddMode.standard;
    });
    widget.onCancel?.call();
  }

  /// Closes any open upward category or location popup menu.
  void _dismissPopup() {
    if (_activePopup == _QuickAddPopup.none) {
      return;
    }
    setState(() {
      _activePopup = _QuickAddPopup.none;
    });
  }

  /// Placeholder callback for the Advanced button.
  void _handleAdvancedNoOp() {}

  /// Rebuilds the widget when the task title text changes.
  void _handleControllerChanged() {
    setState(() {});
  }

  /// Submits the entered task title, priority/someday selection, locations, and categories.
  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    final selectedMode = _mode;
    final board = ref.read(taskNotifierProvider).asData?.value;
    final submittedCategoryIds = <String>[
      if (board != null)
        for (final category in board.categories)
          if (_selectedCategoryIds.contains(category.id)) category.id,
    ];
    final submittedLocationIds = <String>[
      if (board != null)
        for (final location in board.locations)
          if (_selectedLocationIds.contains(location.id)) location.id,
    ];

    _controller.clear();
    setState(() {
      _activePopup = _QuickAddPopup.none;
      _selectedCategoryIds.clear();
      _selectedLocationIds.clear();
      _mode = QuickAddMode.standard;
    });

    await ref
        .read(taskNotifierProvider.notifier)
        .addTask(
          text,
          targetTier: selectedMode.targetTier,
          isPriority: selectedMode == QuickAddMode.priority,
          categoryIds: submittedCategoryIds,
          locationIds: submittedLocationIds,
        );
    widget.onSubmitted?.call();
  }

  /// Toggles the upward Categories selection menu.
  void _toggleCategoriesPopup() {
    setState(() {
      _activePopup = _activePopup == _QuickAddPopup.categories
          ? _QuickAddPopup.none
          : _QuickAddPopup.categories;
    });
  }

  /// Toggles selection of [categoryId] for the task being created.
  void _toggleCategory(String categoryId) {
    setState(() {
      if (!_selectedCategoryIds.remove(categoryId)) {
        _selectedCategoryIds.add(categoryId);
      }
    });
  }

  /// Toggles selection of [locationId] for the task being created.
  void _toggleLocation(String locationId) {
    setState(() {
      if (!_selectedLocationIds.remove(locationId)) {
        _selectedLocationIds.add(locationId);
      }
    });
  }

  /// Toggles the upward Locations selection menu.
  void _toggleLocationsPopup() {
    setState(() {
      _activePopup = _activePopup == _QuickAddPopup.locations
          ? _QuickAddPopup.none
          : _QuickAddPopup.locations;
    });
  }

  /// Toggles Priority on or off, automatically turning Someday off when enabled.
  void _togglePriority() {
    setState(() {
      _mode = _mode == QuickAddMode.priority
          ? QuickAddMode.standard
          : QuickAddMode.priority;
    });
  }

  /// Toggles Someday on or off, automatically turning Priority off when enabled.
  void _toggleSomeday() {
    setState(() {
      _mode = _mode == QuickAddMode.someday
          ? QuickAddMode.standard
          : QuickAddMode.someday;
    });
  }
}

/// Active upward popup menu state inside [QuickAddBar].
enum _QuickAddPopup { none, categories, locations }

/// Single option row inside [_UpwardCategoriesMenu] or [_UpwardLocationsMenu].
class _QuickAddPopupOptionTile extends StatelessWidget {
  /// Creates a [_QuickAddPopupOptionTile].
  const _QuickAddPopupOptionTile({
    super.key,
    required this.accentColor,
    required this.icon,
    required this.isSelected,
    required this.label,
    required this.onTap,
  });

  /// Resolved accent color for the leading icon and selection indicator.
  final Color accentColor;

  /// Leading icon displayed for the option.
  final IconData icon;

  /// Whether this option is currently selected.
  final bool isSelected;

  /// Display name of the category or location.
  final String label;

  /// Callback invoked when this row is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : _mutedLabelColor,
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: isSelected
                    ? accentColor
                    : _mutedLabelColor.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Borderless inline task title [TextField] inside [_QuickAddBarRow].
class _QuickAddTextField extends StatelessWidget {
  /// Creates a [_QuickAddTextField].
  const _QuickAddTextField({
    required this.controller,
    required this.effectiveTier,
    required this.hasText,
    required this.onSubmit,
  });

  /// Text controller for the task title input.
  final TextEditingController controller;

  /// Target tier used to format the localized placeholder hint.
  final TaskTier effectiveTier;

  /// Whether the input field currently contains non-whitespace text.
  final bool hasText;

  /// Callback invoked when the user submits the task.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final heading = localizations.tierName(effectiveTier);

    return TextField(
      key: const ValueKey('quick_add_input'),
      controller: controller,
      autofocus: true,
      cursorColor: _accentMagenta,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        hintText: localizations.quickAddHint(heading),
        hintStyle: const TextStyle(color: _mutedLabelColor, fontSize: 15),
        isDense: true,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        suffixIcon: hasText
            ? IconButton(
                key: const ValueKey('quick_add_submit_button'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                tooltip: localizations.actionAdd,
                icon: const Icon(
                  Icons.check_rounded,
                  color: _accentMagenta,
                  size: 20,
                ),
                onPressed: onSubmit,
              )
            : null,
      ),
    );
  }
}

/// Upward floating selection menu for choosing task categories.
class _UpwardCategoriesMenu extends StatelessWidget {
  /// Creates an [_UpwardCategoriesMenu].
  const _UpwardCategoriesMenu({
    required this.categories,
    required this.selectedCategoryIds,
    required this.onToggleCategory,
  });

  /// Available categories on the board.
  final List<TdfCategory> categories;

  /// Callback invoked when a category option is tapped.
  final ValueChanged<String> onToggleCategory;

  /// Currently selected category IDs.
  final Set<String> selectedCategoryIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Material(
      key: const ValueKey('quick_add_categories_menu'),
      color: _cardColor,
      elevation: 12,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: _canvasColor, width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: categories.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    localizations.emptyCategoriesHint,
                    style: const TextStyle(
                      color: _mutedLabelColor,
                      fontSize: 14,
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final category in categories)
                      _QuickAddPopupOptionTile(
                        key: ValueKey('quick_add_category_${category.id}'),
                        icon: Icons.label_outline_rounded,
                        label: category.name,
                        isSelected: selectedCategoryIds.contains(category.id),
                        accentColor: _resolveColor(
                          category.color,
                          _accentMagenta,
                        ),
                        onTap: () => onToggleCategory(category.id),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Resolves a `#RRGGBB` color string or falls back to [fallback].
  Color _resolveColor(String? rawHex, Color fallback) {
    final parsed = TdfColor.tryParseArgb(rawHex);
    return parsed != null ? Color(parsed) : fallback;
  }
}

/// Upward floating selection menu for choosing task locations.
class _UpwardLocationsMenu extends StatelessWidget {
  /// Creates an [_UpwardLocationsMenu].
  const _UpwardLocationsMenu({
    required this.locations,
    required this.selectedLocationIds,
    required this.onToggleLocation,
  });

  /// Available locations on the board.
  final List<TdfLocation> locations;

  /// Callback invoked when a location option is tapped.
  final ValueChanged<String> onToggleLocation;

  /// Currently selected location IDs.
  final Set<String> selectedLocationIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Material(
      key: const ValueKey('quick_add_locations_menu'),
      color: _cardColor,
      elevation: 12,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: _canvasColor, width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: locations.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    localizations.emptyLocationsHint,
                    style: const TextStyle(
                      color: _mutedLabelColor,
                      fontSize: 14,
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final location in locations)
                      _QuickAddPopupOptionTile(
                        key: ValueKey('quick_add_location_${location.id}'),
                        icon: Icons.location_on_outlined,
                        label: location.name,
                        isSelected: selectedLocationIds.contains(location.id),
                        accentColor: _resolveColor(location.color, _accentCyan),
                        onTap: () => onToggleLocation(location.id),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Resolves a `#RRGGBB` color string or falls back to [fallback].
  Color _resolveColor(String? rawHex, Color fallback) {
    final parsed = TdfColor.tryParseArgb(rawHex);
    return parsed != null ? Color(parsed) : fallback;
  }
}
