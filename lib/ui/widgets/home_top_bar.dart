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

import '../../l10n/app_localizations.dart';
import 'label_hub_dialog.dart';
import 'location_status_dialog.dart';

/// Top navigation bar displaying the menu button, optional active label name,
/// inline search field, and right-aligned action buttons.
class HomeTopBar extends StatelessWidget {
  /// Creates a [HomeTopBar].
  const HomeTopBar({
    super.key,
    this.activeLabelId,
    required this.activeLabelName,
    required this.isSearching,
    required this.searchController,
    required this.onSearchChanged,
    required this.onToggleSearch,
  });

  /// Active label identifier when filtered, or `null` when unfiltered.
  final String? activeLabelId;

  /// Active label display name when filtered, or `null` when unfiltered.
  final String? activeLabelName;

  /// Whether the inline search input is currently expanded.
  final bool isSearching;

  /// Callback invoked when the search input text changes.
  final ValueChanged<String> onSearchChanged;

  /// Callback invoked when the search button or close button is pressed.
  final VoidCallback onToggleSearch;

  /// Controller for the inline search input field.
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _TopBarMenuButton(tooltip: localizations.tooltipMenu),
          Expanded(
            child: _TopBarCenterArea(
              activeLabelId: activeLabelId,
              activeLabelName: activeLabelName,
              isSearching: isSearching,
              searchController: searchController,
              onSearchChanged: onSearchChanged,
            ),
          ),
          _TopBarSearchButton(
            isSearching: isSearching,
            onPressed: onToggleSearch,
          ),
          const TopBarLocationButton(),
        ],
      ),
    );
  }
}

/// Multi-child layout hosting the optional active label title and inline search
/// field inside [_TopBarCenterArea].
class _TopBarAnimatedSlots extends StatelessWidget {
  /// Creates [_TopBarAnimatedSlots].
  const _TopBarAnimatedSlots({
    required this.activeLabelId,
    required this.activeLabelName,
    required this.isSearching,
    required this.onSearchChanged,
    required this.searchController,
    required this.searchProgress,
  });

  /// Active label identifier when filtered, or `null`.
  final String? activeLabelId;

  /// Active label display name when filtered, or `null`.
  final String? activeLabelName;

  /// Whether inline search is currently expanded.
  final bool isSearching;

  /// Search input change callback.
  final ValueChanged<String> onSearchChanged;

  /// Controller for the inline search field.
  final TextEditingController searchController;

  /// Current `0.0..1.0` animation progress of search expansion.
  final double searchProgress;

  @override
  Widget build(BuildContext context) {
    final labelName = activeLabelName;
    final showSearch = isSearching || searchProgress > 0.0;
    return CustomMultiChildLayout(
      delegate: _TopBarLayoutDelegate(searchProgress: searchProgress),
      children: [
        if (labelName != null)
          LayoutId(
            id: _TopBarSlot.title,
            child: _TopBarTitle(
              key: const ValueKey('top_bar_title'),
              activeLabelId: activeLabelId,
              title: labelName,
            ),
          ),
        if (showSearch)
          LayoutId(
            id: _TopBarSlot.search,
            child: Opacity(
              opacity: searchProgress.clamp(0.0, 1.0),
              child: IgnorePointer(
                ignoring: !isSearching,
                child: _TopBarSearchField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Animated middle region of [HomeTopBar] that smoothly glides the active label
/// name left and expands the search input when search is toggled.
class _TopBarCenterArea extends StatelessWidget {
  /// Creates a [_TopBarCenterArea].
  const _TopBarCenterArea({
    required this.activeLabelId,
    required this.activeLabelName,
    required this.isSearching,
    required this.searchController,
    required this.onSearchChanged,
  });

  /// Active label identifier when filtered, or `null`.
  final String? activeLabelId;

  /// Active label display name when filtered, or `null`.
  final String? activeLabelName;

  /// Whether inline search is currently expanded.
  final bool isSearching;

  /// Search input change callback.
  final ValueChanged<String> onSearchChanged;

  /// Controller for the inline search field.
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: isSearching ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        builder: (context, searchProgress, _) => _TopBarAnimatedSlots(
          activeLabelId: activeLabelId,
          activeLabelName: activeLabelName,
          isSearching: isSearching,
          onSearchChanged: onSearchChanged,
          searchController: searchController,
          searchProgress: searchProgress,
        ),
      ),
    );
  }
}

/// Interactive wrapper around the active label title that opens [LabelHubDialog].
class _TopBarInteractiveTitle extends StatelessWidget {
  /// Creates a [_TopBarInteractiveTitle].
  const _TopBarInteractiveTitle({
    super.key,
    required this.labelId,
    required this.title,
  });

  /// Identifier of the active label.
  final String labelId;

  /// Display name of the active label.
  final String title;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Tooltip(
      message: localizations.tooltipOpenLabelHub,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('top_bar_label_hub_trigger'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => showLabelHubDialog(context, labelId: labelId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: _TopBarTitleRow(showInfoIcon: true, title: title),
          ),
        ),
      ),
    );
  }
}

/// Layout delegate positioning the optional active label title and inline
/// search field according to [searchProgress].
class _TopBarLayoutDelegate extends MultiChildLayoutDelegate {
  /// Creates a [_TopBarLayoutDelegate].
  _TopBarLayoutDelegate({required this.searchProgress});

  /// Current `0.0..1.0` animation progress of search expansion.
  final double searchProgress;

  @override
  void performLayout(Size size) {
    var titleRightEdge = 0.0;
    final hasTitle = hasChild(_TopBarSlot.title);

    if (hasTitle) {
      final maxTitleWidth = size.width * (1.0 - (0.45 * searchProgress));
      final titleSize = layoutChild(
        _TopBarSlot.title,
        BoxConstraints(
          maxWidth: maxTitleWidth.clamp(0.0, size.width),
          maxHeight: size.height,
        ),
      );
      final centeredX = (size.width - titleSize.width) / 2.0;
      final titleX = centeredX * (1.0 - searchProgress);
      final titleY = (size.height - titleSize.height) / 2.0;
      positionChild(_TopBarSlot.title, Offset(titleX, titleY));
      titleRightEdge = titleX + titleSize.width + 12.0;
    }

    if (hasChild(_TopBarSlot.search)) {
      final availableWidth = (size.width - titleRightEdge).clamp(
        0.0,
        size.width,
      );
      final searchWidth = hasTitle
          ? availableWidth
          : size.width * searchProgress;
      final searchX = hasTitle ? titleRightEdge : size.width - searchWidth;
      final searchSize = layoutChild(
        _TopBarSlot.search,
        BoxConstraints(
          minWidth: searchWidth,
          maxWidth: searchWidth,
          maxHeight: size.height,
        ),
      );
      final searchY = (size.height - searchSize.height) / 2.0;
      positionChild(_TopBarSlot.search, Offset(searchX, searchY));
    }
  }

  @override
  bool shouldRelayout(_TopBarLayoutDelegate oldDelegate) {
    return oldDelegate.searchProgress != searchProgress;
  }
}

/// Leading drawer menu button inside [HomeTopBar].
class _TopBarMenuButton extends StatelessWidget {
  /// Creates a [_TopBarMenuButton].
  const _TopBarMenuButton({required this.tooltip});

  /// Localized tooltip text.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(Icons.menu_rounded, color: mutedColor, size: 28),
      onPressed: () => Scaffold.of(context).openDrawer(),
    );
  }
}

/// Search toggle button inside [HomeTopBar] with animated icon transition.
class _TopBarSearchButton extends StatelessWidget {
  /// Creates a [_TopBarSearchButton].
  const _TopBarSearchButton({
    required this.isSearching,
    required this.onPressed,
  });

  /// Whether inline search is currently expanded.
  final bool isSearching;

  /// Callback invoked when the button is pressed.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      key: const ValueKey('top_bar_search_button'),
      tooltip: isSearching
          ? localizations.actionClose
          : localizations.tooltipSearch,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: Icon(
          isSearching ? Icons.close_rounded : Icons.search_rounded,
          key: ValueKey<bool>(isSearching),
          color: mutedColor,
          size: 26,
        ),
      ),
      onPressed: onPressed,
    );
  }
}

/// Inline search [TextField] displayed inside [HomeTopBar].
class _TopBarSearchField extends StatelessWidget {
  /// Creates a [_TopBarSearchField].
  const _TopBarSearchField({required this.controller, required this.onChanged});

  /// Controller for the inline search input.
  final TextEditingController controller;

  /// Callback invoked when the search query changes.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      style: TextStyle(color: colorScheme.onSurface),
      decoration: InputDecoration(
        filled: false,
        hintText: localizations.searchHint,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
      ),
    );
  }
}

/// Layout slot identifiers for [_TopBarLayoutDelegate].
enum _TopBarSlot {
  /// Active label title slot.
  title,

  /// Inline search input slot.
  search,
}

/// Active label title displayed inside [HomeTopBar].
class _TopBarTitle extends StatelessWidget {
  /// Creates a [_TopBarTitle].
  const _TopBarTitle({super.key, this.activeLabelId, required this.title});

  /// Optional active label identifier enabling one-tap [LabelHubDialog] access.
  final String? activeLabelId;

  /// Display name of the active label.
  final String title;

  @override
  Widget build(BuildContext context) {
    final child = switch (activeLabelId) {
      final labelId? => _TopBarInteractiveTitle(
        key: ValueKey<String>(title),
        labelId: labelId,
        title: title,
      ),
      null => _TopBarTitleRow(
        key: ValueKey<String>(title),
        showInfoIcon: false,
        title: title,
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: child,
    );
  }
}

/// Ellipsized label title text with optional compact trailing info icon.
class _TopBarTitleRow extends StatelessWidget {
  /// Creates a [_TopBarTitleRow].
  const _TopBarTitleRow({
    super.key,
    required this.showInfoIcon,
    required this.title,
  });

  /// Whether a trailing `16px` info icon should be shown when width allows.
  final bool showInfoIcon;

  /// Display name of the active label.
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textWidget = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
    if (!showInfoIcon) {
      return textWidget;
    }
    return LayoutBuilder(
      builder: (context, innerConstraints) {
        if (innerConstraints.maxWidth < 28) {
          return textWidget;
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: textWidget),
            const SizedBox(width: 6),
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        );
      },
    );
  }
}
