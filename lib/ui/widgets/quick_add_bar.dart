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
import '../edit_task_screen.dart';
import 'clearable_text_field.dart';

const double _pixel9ProAspectRatio = 1280.0 / 2856.0;
const double _pixel9ProLogicalWidth = 488.0;
const String _popupTapRegionGroupId = 'quick_add_popup_region';

/// Inline bottom task creation bar with title input, Priority, Someday, upward Labels selector, Advanced dialog trigger, and Cancel actions.
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

/// Horizontal row of action icon buttons inside [QuickAddBar].
class _QuickAddActionButtons extends StatelessWidget {
  /// Creates a [_QuickAddActionButtons] row.
  const _QuickAddActionButtons({
    required this.hasSelectedLabels,
    required this.isLabelsPopupOpen,
    required this.mode,
    required this.onAdvanced,
    required this.onCancel,
    required this.onToggleLabelsPopup,
    required this.onTogglePriority,
    required this.onToggleSomeday,
  });

  /// Whether at least one label is selected.
  final bool hasSelectedLabels;

  /// Whether the upward Labels popup menu is currently open.
  final bool isLabelsPopupOpen;

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// Callback to open the extended task creation dialog.
  final VoidCallback onAdvanced;

  /// Callback invoked when the Cancel button is pressed.
  final VoidCallback onCancel;

  /// Callback to toggle the upward Labels popup menu.
  final VoidCallback onToggleLabelsPopup;

  /// Callback to toggle Priority mode.
  final VoidCallback onTogglePriority;

  /// Callback to toggle Someday mode.
  final VoidCallback onToggleSomeday;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QuickAddActionIconButton(
          buttonKey: const ValueKey('quick_add_priority_button'),
          icon: Icons.bolt_rounded,
          isActive: mode == QuickAddMode.priority,
          activeColor: colorScheme.primary,
          tooltip: localizations.quickAddPriority,
          onTap: onTogglePriority,
        ),
        _QuickAddActionIconButton(
          buttonKey: const ValueKey('quick_add_someday_button'),
          icon: Icons.lightbulb_outline_rounded,
          isActive: mode == QuickAddMode.someday,
          activeColor: colorScheme.secondary,
          tooltip: localizations.tierName(TaskTier.someday),
          onTap: onToggleSomeday,
        ),
        TapRegion(
          groupId: _popupTapRegionGroupId,
          child: _QuickAddActionIconButton(
            buttonKey: const ValueKey('quick_add_labels_button'),
            icon: Icons.label_outline_rounded,
            isActive: isLabelsPopupOpen || hasSelectedLabels,
            activeColor: colorScheme.primary,
            tooltip: localizations.drawerLabels,
            onTap: onToggleLabelsPopup,
          ),
        ),
        _QuickAddActionIconButton(
          buttonKey: const ValueKey('quick_add_advanced_button'),
          icon: Icons.tune_rounded,
          isActive: false,
          activeColor: colorScheme.tertiary,
          tooltip: localizations.quickAddAdvanced,
          onTap: onAdvanced,
        ),
        _QuickAddActionIconButton(
          buttonKey: const ValueKey('quick_add_cancel_button'),
          icon: Icons.close_rounded,
          isActive: false,
          activeColor: colorScheme.onSurfaceVariant,
          tooltip: localizations.actionCancel,
          onTap: onCancel,
        ),
      ],
    );
  }
}

/// Compact icon button rendered inside [_QuickAddActionButtons].
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
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
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
                color: isActive ? activeColor : mutedColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Responsive layout inside [QuickAddBar] that stacks the text input above the action buttons at or below the Pixel 9 Pro width threshold and places them side-by-side on wider viewports.
class _QuickAddBarLayout extends StatelessWidget {
  /// Creates a [_QuickAddBarLayout].
  const _QuickAddBarLayout({
    required this.controller,
    required this.effectiveTier,
    required this.hasSelectedLabels,
    required this.hasTaskText,
    required this.isLabelsPopupOpen,
    required this.mode,
    required this.onAdvanced,
    required this.onCancel,
    required this.onSubmit,
    required this.onToggleLabelsPopup,
    required this.onTogglePriority,
    required this.onToggleSomeday,
  });

  /// Text controller for the task title input.
  final TextEditingController controller;

  /// Target tier corresponding to [mode].
  final TaskTier effectiveTier;

  /// Whether at least one label is selected.
  final bool hasSelectedLabels;

  /// Whether the task title input contains non-whitespace text.
  final bool hasTaskText;

  /// Whether the upward Labels popup menu is currently open.
  final bool isLabelsPopupOpen;

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// Callback to open the extended task creation dialog.
  final VoidCallback onAdvanced;

  /// Callback invoked when the Cancel button is pressed.
  final VoidCallback onCancel;

  /// Callback invoked when the task is submitted.
  final VoidCallback onSubmit;

  /// Callback to toggle the upward Labels popup menu.
  final VoidCallback onToggleLabelsPopup;

  /// Callback to toggle Priority mode.
  final VoidCallback onTogglePriority;

  /// Callback to toggle Someday mode.
  final VoidCallback onToggleSomeday;

  @override
  Widget build(BuildContext context) {
    final viewportSize = MediaQuery.sizeOf(context);
    final textField = _QuickAddTextField(
      controller: controller,
      effectiveTier: effectiveTier,
      hasText: hasTaskText,
      onSubmit: onSubmit,
    );
    final actionButtons = _QuickAddActionButtons(
      hasSelectedLabels: hasSelectedLabels,
      isLabelsPopupOpen: isLabelsPopupOpen,
      mode: mode,
      onAdvanced: onAdvanced,
      onCancel: onCancel,
      onToggleLabelsPopup: onToggleLabelsPopup,
      onTogglePriority: onTogglePriority,
      onToggleSomeday: onToggleSomeday,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : viewportSize.width;
        final isStacked =
            barWidth <= _pixel9ProLogicalWidth ||
            barWidth <= viewportSize.height * _pixel9ProAspectRatio;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: isStacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    textField,
                    Align(
                      alignment: Alignment.centerRight,
                      child: actionButtons,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: textField),
                    actionButtons,
                  ],
                ),
        );
      },
    );
  }
}

/// State for [QuickAddBar].
class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final TextEditingController _controller = TextEditingController();
  final LayerLink _labelsLayerLink = LayerLink();
  final OverlayPortalController _labelsPopupController =
      OverlayPortalController();
  QuickAddMode _mode = QuickAddMode.standard;
  final Set<String> _selectedLabelIds = <String>{};

  /// Whether the task title input contains non-whitespace text.
  bool get _hasTaskText => _controller.text.trim().isNotEmpty;

  /// Whether the upward Labels popup menu is currently open.
  bool get _isLabelsPopupOpen => _labelsPopupController.isShowing;

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
    final labels = ref.watch(
      taskNotifierProvider.select(
        (boardAsync) => boardAsync.asData?.value.labels ?? const <TdfLabel>[],
      ),
    );

    return CompositedTransformTarget(
      link: _labelsLayerLink,
      child: OverlayPortal(
        controller: _labelsPopupController,
        overlayChildBuilder: (_) => _QuickAddLabelsOverlay(
          labels: labels,
          layerLink: _labelsLayerLink,
          selectedLabelIds: _selectedLabelIds,
          onDismiss: _dismissPopup,
          onToggleLabel: _toggleLabel,
        ),
        child: _QuickAddBarSurface(
          child: _QuickAddBarLayout(
            controller: _controller,
            effectiveTier: _mode.targetTier,
            hasSelectedLabels: _selectedLabelIds.isNotEmpty,
            hasTaskText: _hasTaskText,
            isLabelsPopupOpen: _isLabelsPopupOpen,
            mode: _mode,
            onAdvanced: _openAdvancedDialog,
            onCancel: _cancel,
            onSubmit: _submit,
            onToggleLabelsPopup: _toggleLabelsPopup,
            onTogglePriority: _togglePriority,
            onToggleSomeday: _toggleSomeday,
          ),
        ),
      ),
    );
  }

  /// Clears pending state and invokes [QuickAddBar.onCancel].
  void _cancel() {
    _controller.clear();
    setState(() {
      if (_labelsPopupController.isShowing) {
        _labelsPopupController.hide();
      }
      _selectedLabelIds.clear();
      _mode = QuickAddMode.standard;
    });
    widget.onCancel?.call();
  }

  /// Closes the upward labels popup menu when open.
  void _dismissPopup() {
    if (!_labelsPopupController.isShowing) {
      return;
    }
    setState(() {
      _labelsPopupController.hide();
    });
  }

  /// Rebuilds the widget when the task title text changes.
  void _handleControllerChanged() {
    setState(() {});
  }

  /// Opens the shared [EditTaskScreen] pre-filled with the current draft values.
  Future<void> _openAdvancedDialog() async {
    _dismissPopup();
    await openEditTaskScreen(
      context,
      initialTitle: _controller.text,
      initialMode: _mode,
      initialLabelIds: Set<String>.from(_selectedLabelIds),
      onSubmitted: () {
        if (!mounted) {
          return;
        }
        _controller.clear();
        setState(() {
          if (_labelsPopupController.isShowing) {
            _labelsPopupController.hide();
          }
          _selectedLabelIds.clear();
          _mode = QuickAddMode.standard;
        });
        widget.onSubmitted?.call();
      },
    );
  }

  /// Submits the entered task title, priority/someday selection, and labels.
  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    final selectedMode = _mode;
    final board = ref.read(taskNotifierProvider).asData?.value;
    if (board != null && board.hasDuplicateTaskTitle(text)) {
      return;
    }
    final submittedLabelIds = <String>[
      if (board != null)
        for (final label in board.labels)
          if (_selectedLabelIds.contains(label.id)) label.id,
    ];

    _controller.clear();
    setState(() {
      if (_labelsPopupController.isShowing) {
        _labelsPopupController.hide();
      }
      _selectedLabelIds.clear();
      _mode = QuickAddMode.standard;
    });

    await ref
        .read(taskNotifierProvider.notifier)
        .addTask(
          text,
          targetTier: selectedMode.targetTier,
          isPriority: selectedMode == QuickAddMode.priority,
          labelIds: submittedLabelIds,
        );
    widget.onSubmitted?.call();
  }

  /// Toggles selection of [labelId] for the task being created.
  void _toggleLabel(String labelId) {
    setState(() {
      if (!_selectedLabelIds.remove(labelId)) {
        _selectedLabelIds.add(labelId);
      }
    });
  }

  /// Toggles the upward Labels selection menu.
  void _toggleLabelsPopup() {
    setState(() {
      if (_labelsPopupController.isShowing) {
        _labelsPopupController.hide();
      } else {
        _labelsPopupController.show();
      }
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

/// Elevated bottom surface container for [QuickAddBar].
class _QuickAddBarSurface extends StatelessWidget {
  /// Creates a [_QuickAddBarSurface].
  const _QuickAddBarSurface({required this.child});

  /// Inner layout displayed inside the surface.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('quick_add_bar'),
      elevation: 8,
      color: theme.cardColor,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.scaffoldBackgroundColor, width: 1.5),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Floating overlay wrapper that anchors [_UpwardLabelsMenu] above [QuickAddBar].
class _QuickAddLabelsOverlay extends StatelessWidget {
  /// Creates a [_QuickAddLabelsOverlay].
  const _QuickAddLabelsOverlay({
    required this.labels,
    required this.layerLink,
    required this.selectedLabelIds,
    required this.onDismiss,
    required this.onToggleLabel,
  });

  /// Available labels on the board.
  final List<TdfLabel> labels;

  /// Layer link connected to the [QuickAddBar] surface.
  final LayerLink layerLink;

  /// Callback invoked when the user taps outside the popup region.
  final VoidCallback onDismiss;

  /// Callback invoked when a label option is tapped.
  final ValueChanged<String> onToggleLabel;

  /// Currently selected label IDs.
  final Set<String> selectedLabelIds;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topRight,
        followerAnchor: Alignment.bottomRight,
        offset: const Offset(-16, -8),
        child: TapRegion(
          groupId: _popupTapRegionGroupId,
          onTapOutside: (_) => onDismiss(),
          child: _UpwardLabelsMenu(
            labels: labels,
            selectedLabelIds: selectedLabelIds,
            onToggleLabel: onToggleLabel,
          ),
        ),
      ),
    );
  }
}

/// Single option row inside [_UpwardLabelsMenu].
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

  /// Display name of the label.
  final String label;

  /// Callback invoked when this row is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                    color: isSelected
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
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
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Borderless inline task title [TextField] inside [_QuickAddBarLayout].
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
    final colorScheme = Theme.of(context).colorScheme;
    final heading = localizations.tierName(effectiveTier);

    return ClearableTextField(
      fieldKey: const ValueKey('quick_add_input'),
      controller: controller,
      autofocus: true,
      cursorColor: colorScheme.primary,
      style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        filled: false,
        hintText: localizations.quickAddHint(heading),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
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
                icon: Icon(
                  Icons.check_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
                onPressed: onSubmit,
              )
            : null,
      ),
    );
  }
}

/// Upward floating selection menu for choosing task labels.
class _UpwardLabelsMenu extends StatelessWidget {
  /// Creates an [_UpwardLabelsMenu].
  const _UpwardLabelsMenu({
    required this.labels,
    required this.selectedLabelIds,
    required this.onToggleLabel,
  });

  /// Available labels on the board.
  final List<TdfLabel> labels;

  /// Callback invoked when a label option is tapped.
  final ValueChanged<String> onToggleLabel;

  /// Currently selected label IDs.
  final Set<String> selectedLabelIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      key: const ValueKey('quick_add_labels_menu'),
      color: theme.cardColor,
      elevation: 12,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.scaffoldBackgroundColor, width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: labels.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    localizations.emptyLabelsHint,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final label in labels)
                      _QuickAddPopupOptionTile(
                        key: ValueKey('quick_add_label_${label.id}'),
                        icon: Icons.label_outline_rounded,
                        label: label.name,
                        isSelected: selectedLabelIds.contains(label.id),
                        accentColor: _resolveColor(
                          label.color,
                          colorScheme.primary,
                        ),
                        onTap: () => onToggleLabel(label.id),
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
