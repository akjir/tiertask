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
import 'package:tiertask_ui/tiertask_ui.dart';

/// Gallery showcase section selector rendered in the example app sidebar.
enum GallerySection {
  /// Layer 1 design tokens and live WCAG AA contrast verification.
  tokens,

  /// Layer 2 core primitives (`UiAppLogo`, `UiButton`, `UiPill`, `UiSegmentedControl`, `UiCard`, `UiField`, `UiToggleRow`, `UiBanner`).
  primitives,

  /// Layer 3 adaptive layout showcase (`UiPageHeader`, `UiResponsiveGrid`, `UiSidebarSection`, `UiAdaptiveAppShell`).
  layouts,

  /// Layer 4 composites (`UiDialogFrame`, `UiQuickComposer`, `UiSearchablePicker`, `UiOrderedItemList`, `UiColorWheel`).
  composites,
}

/// Interactive tokens and WCAG AA contrast readout section.
class TokensGallerySection extends StatelessWidget {
  /// Creates a [TokensGallerySection].
  const TokensGallerySection({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final pairs = UiContrastChecker.normativePairs(colors);
    final failures = UiContrastChecker.verifyTokens(colors);
    final passCount = pairs.length - failures.length;

    final swatches = <(String, Color)>[
      ('pageBg', colors.pageBg),
      ('bg', colors.bg),
      ('panel', colors.panel),
      ('ink', colors.ink),
      ('muted', colors.muted),
      ('line', colors.line),
      ('accent', colors.accent),
      ('soft', colors.soft),
      ('onAccent', colors.onAccent),
      ('danger', colors.danger),
      ('warning', colors.warning),
      ('success', colors.success),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiPageHeader(
          title: 'Tokens & Contrast',
          subtitle: 'Verified Layer 1 color roles, surface alternation, typography scale, and automated WCAG AA contrast checks.',
          countLabel: '$passCount / ${pairs.length} WCAG AA',
        ),
        SizedBox(height: tokens.spacing.space4),
        UiCard.standard(
          headerIcon: Icons.verified_outlined,
          headerTitle: 'Palette Swatches',
          headerBadge: UiPill(
            label: failures.isEmpty ? 'WCAG AA Pass' : 'Contrast Failure',
            tone: failures.isEmpty ? UiPillTone.success : UiPillTone.danger,
          ),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: <Widget>[
              for (final (name, color) in swatches)
                UiPill(
                  label: '$name ${UiColorWheel.formatHex(color)}',
                  variant: UiPillVariant.tag,
                  colorDot: color,
                  isMono: true,
                ),
            ],
          ),
        ),
        SizedBox(height: tokens.spacing.space3),
        const UiCard.standard(
          headerIcon: Icons.layers_outlined,
          headerTitle: 'Automatic Surface Alternation (U-SURFACE-003)',
          child: UiCard.inset(
            headerTitle: 'Nested Inset Well (bg)',
            isEditing: true,
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: <Widget>[
                UiPill(
                  label: 'Re-elevated Panel Pill',
                  variant: UiPillVariant.selectable,
                ),
                SizedBox(
                  width: 240.0,
                  child: UiField(
                    kind: UiFieldKind.text,
                    hintText: 'Re-elevated panel input',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Interactive showcase of all 8 Layer 2 core primitives.
class PrimitivesGallerySection extends StatefulWidget {
  /// Creates a [PrimitivesGallerySection].
  const PrimitivesGallerySection({super.key, required this.onShowToast});

  /// Triggers a live floating Undo toast in the outer shell.
  final VoidCallback onShowToast;

  @override
  State<PrimitivesGallerySection> createState() =>
      _PrimitivesGallerySectionState();
}

/// Holds interactive widget state for [PrimitivesGallerySection].
class _PrimitivesGallerySectionState extends State<PrimitivesGallerySection> {
  /// Selected segment value for the `UiSegmentedControl` demo.
  String _placement = 'queue';

  /// Expandable card open flag.
  bool _cardExpanded = false;

  /// Toggle row checked value.
  bool _watchEnabled = true;

  /// Selected dropdown value for `UiFieldKind.select`.
  String _selectedTier = 'focus';

  /// Inline confirmation open flag.
  bool _showDeleteConfirm = false;

  /// Controller for the text field showcase.
  final TextEditingController _textController = TextEditingController(
    text: 'Ship Phase 2 library',
  );

  /// Controller for the password field showcase.
  final TextEditingController _passwordController = TextEditingController(
    text: 'example-secret',
  );

  @override
  void dispose() {
    _textController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const UiPageHeader(
          title: 'Primitives',
          subtitle: 'All 8 orthogonal primitives: UiAppLogo, UiButton, UiPill, UiSegmentedControl, UiCard, UiField, UiToggleRow, and UiBanner.',
          countLabel: '8 widgets',
        ),
        SizedBox(height: tokens.spacing.space4),
        UiResponsiveGrid(
          preset: UiGridPreset.twoColumnMediumCollapse,
          children: <Widget>[
            UiCard.standard(
              headerIcon: Icons.smart_button_outlined,
              headerTitle: 'Buttons & Brand Mark',
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  const UiAppLogo(size: 26.0),
                  UiButton(
                    label: 'Primary',
                    variant: UiButtonVariant.primary,
                    onPressed: widget.onShowToast,
                  ),
                  UiButton(
                    label: 'Secondary',
                    variant: UiButtonVariant.secondary,
                    onPressed: () {},
                  ),
                  UiButton(
                    label: 'Danger',
                    variant: UiButtonVariant.danger,
                    density: UiButtonDensity.compact,
                    onPressed: () => setState(
                      () => _showDeleteConfirm = !_showDeleteConfirm,
                    ),
                  ),
                  UiButton(
                    label: 'Text action',
                    variant: UiButtonVariant.text,
                    density: UiButtonDensity.dense,
                    onPressed: () {},
                  ),
                  UiButton(
                    leadingIcon: Icons.sync_rounded,
                    variant: UiButtonVariant.icon,
                    tooltip: 'Sync',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            UiCard.standard(
              headerIcon: Icons.label_outline_rounded,
              headerTitle: 'Pills & Segmented Control',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Wrap(
                    spacing: 6.0,
                    runSpacing: 6.0,
                    children: <Widget>[
                      const UiPill(label: 'Auto-saved', tone: UiPillTone.soft),
                      const UiPill(label: 'Unsaved', tone: UiPillTone.warning),
                      const UiPill(label: 'Overdue', tone: UiPillTone.danger),
                      const UiPill(label: 'Synced', tone: UiPillTone.success),
                      const UiPill(
                        label: 'DEV',
                        tone: UiPillTone.warning,
                        isMono: true,
                      ),
                      const UiPill(
                        label: '2 / 3',
                        variant: UiPillVariant.count,
                      ),
                      UiPill(
                        label: 'Backend',
                        variant: UiPillVariant.splitChip,
                        colorDot: const Color(0xFF2196F3),
                        onPressed: () {},
                        onRemove: () {},
                        removeTooltip: 'Remove Backend',
                      ),
                      UiPill(
                        label: '+ Note',
                        variant: UiPillVariant.addField,
                        onPressed: () {},
                      ),
                      UiPill(
                        label: 'Priority',
                        variant: UiPillVariant.addField,
                        isDirect: true,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  SizedBox(height: tokens.spacing.space3),
                  UiSegmentedControl<String>(
                    value: _placement,
                    segments: const <UiSegment<String>>[
                      UiSegment<String>(value: 'queue', label: 'Queue'),
                      UiSegment<String>(value: 'priority', label: 'Priority'),
                      UiSegment<String>(value: 'someday', label: 'Someday'),
                    ],
                    onChanged: (next) => setState(() => _placement = next),
                  ),
                  SizedBox(height: tokens.spacing.space2),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        'Vertical mode',
                        style: tokens.typography.meta.copyWith(
                          color: tokens.colors.muted,
                        ),
                      ),
                      UiSegmentedControl<String>(
                        mode: UiSegmentedControlMode.vertical,
                        value: _placement,
                        segments: const <UiSegment<String>>[
                          UiSegment<String>(value: 'queue', label: 'Queue'),
                          UiSegment<String>(
                            value: 'priority',
                            label: 'Priority',
                          ),
                          UiSegment<String>(value: 'someday', label: 'Someday'),
                        ],
                        onChanged: (next) => setState(() => _placement = next),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.space3),
        UiCard.expandable(
          title: 'Unified expandable entity card',
          isExpanded: _cardExpanded,
          leading: Icon(
            Icons.radio_button_unchecked_rounded,
            color: tokens.colors.muted,
          ),
          collapsedMetadata: const Wrap(
            spacing: 6.0,
            runSpacing: 6.0,
            children: <Widget>[
              UiPill(
                label: 'Design',
                variant: UiPillVariant.tag,
                colorDot: Color(0xFF9C27B0),
              ),
              UiPill(
                label: 'Due tomorrow',
                variant: UiPillVariant.meta,
                tone: UiPillTone.warning,
                icon: Icons.calendar_today_outlined,
              ),
            ],
          ),
          expandedChild: const UiCard.inset(
            headerIcon: Icons.notes_rounded,
            headerTitle: 'Note',
            child: Text(
              'Tap the card title to toggle single-expand accordion behavior.',
            ),
          ),
          onToggleExpand: () => setState(() => _cardExpanded = !_cardExpanded),
        ),
        SizedBox(height: tokens.spacing.space3),
        UiCard.standard(
          headerIcon: Icons.input_rounded,
          headerTitle: 'Fields, Toggle & Banners',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              UiResponsiveGrid(
                preset: UiGridPreset.twoColumnCompactCollapse,
                children: <Widget>[
                  UiField(
                    kind: UiFieldKind.text,
                    label: 'Task title',
                    controller: _textController,
                    showClearButton: true,
                    clearTooltip: 'Clear title',
                  ),
                  UiField(
                    kind: UiFieldKind.password,
                    label: 'WebDAV password',
                    controller: _passwordController,
                    showPasswordTooltip: 'Show password',
                    hidePasswordTooltip: 'Hide password',
                  ),
                  UiField(
                    kind: UiFieldKind.select,
                    label: 'Tier selector',
                    selectValue: _selectedTier,
                    selectOptions: const <UiSelectOption>[
                      UiSelectOption(value: 'focus', label: 'Focus · 2'),
                      UiSelectOption(value: 'ready', label: 'Ready · 4'),
                      UiSelectOption(value: 'planned', label: 'Planned · 3'),
                    ],
                    onSelectChanged: (next) =>
                        setState(() => _selectedTier = next),
                  ),
                  const UiField(
                    kind: UiFieldKind.readOnlyDisplay,
                    label: 'Resolved endpoint',
                    displayValue: 'https://cloud.example.com/dav/tasks.tdf',
                    readOnly: true,
                  ),
                ],
              ),
              SizedBox(height: tokens.spacing.space2),
              UiToggleRow(
                label: 'Watch local .tdf file',
                description: 'Reconcile external edits automatically.',
                value: _watchEnabled,
                onChanged: (next) => setState(() => _watchEnabled = next),
              ),
              SizedBox(height: tokens.spacing.space2),
              const UiBanner(
                variant: UiBannerVariant.status,
                tone: UiBannerTone.warning,
                title: 'Sync notice',
                message: 'WebDAV endpoint is not configured yet.',
              ),
              if (_showDeleteConfirm) ...<Widget>[
                SizedBox(height: tokens.spacing.space2),
                UiBanner(
                  variant: UiBannerVariant.inlineConfirm,
                  message: 'Delete this sample item?',
                  cancelLabel: 'Keep',
                  onCancel: () => setState(() => _showDeleteConfirm = false),
                  confirmLabel: 'Yes, delete',
                  onConfirm: () => setState(() => _showDeleteConfirm = false),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Interactive showcase of Layer 3 adaptive layouts (`UiResponsiveGrid`, `UiPageHeader`, `UiSidebarSection`, `UiAdaptiveAppShell`).
class LayoutsGallerySection extends StatelessWidget {
  /// Creates a [LayoutsGallerySection].
  const LayoutsGallerySection({
    super.key,
    required this.activeLabel,
    required this.onClearActiveLabel,
  });

  /// Optional active label filter name shown inline on desktop headings.
  final String? activeLabel;

  /// Clears the active label filter.
  final VoidCallback onClearActiveLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiPageHeader(
          title: 'Adaptive Layouts',
          subtitle: 'Switch simulated width in the top bar (1280 / 760 / 390) to inspect live grid and shell breakpoint transitions.',
          countLabel: '4 layouts',
          activeFilterLabel: activeLabel,
          activeFilterTooltip: 'Clear active label filter',
          onClearActiveFilter: onClearActiveLabel,
        ),
        SizedBox(height: tokens.spacing.space4),
        UiCard.standard(
          headerIcon: Icons.grid_view_rounded,
          headerTitle:
              'Four-Action Local Storage Grid (4 cols > 720, 2x2 <= 720)',
          child: UiResponsiveGrid(
            preset: UiGridPreset.fourActionCompactTwo,
            children: <Widget>[
              UiButton(
                label: 'Select',
                leadingIcon: Icons.folder_open_outlined,
                onPressed: () {},
              ),
              UiButton(
                label: 'Move',
                leadingIcon: Icons.drive_file_move_outlined,
                onPressed: () {},
              ),
              UiButton(
                label: 'Rename',
                leadingIcon: Icons.edit_outlined,
                onPressed: () {},
              ),
              UiButton(
                label: 'Wipe',
                leadingIcon: Icons.delete_outline_rounded,
                variant: UiButtonVariant.danger,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Interactive showcase of all 5 Layer 4 composites.
class CompositesGallerySection extends StatefulWidget {
  /// Creates a [CompositesGallerySection].
  const CompositesGallerySection({super.key});

  @override
  State<CompositesGallerySection> createState() =>
      _CompositesGallerySectionState();
}

/// Holds interactive demo state for [CompositesGallerySection].
class _CompositesGallerySectionState extends State<CompositesGallerySection> {
  /// Selected label IDs inside the searchable picker demo.
  final Set<String> _selectedLabels = <String>{'work'};

  /// Active scope filter inside the searchable picker demo.
  String _activeScope = 'all';

  /// Dynamic label options supporting inline creation.
  final List<UiPickerOption<String>> _labelOptions = <UiPickerOption<String>>[
    const UiPickerOption<String>(
      id: 'work',
      value: 'work',
      label: 'Work',
      colorDot: Color(0xFF2196F3),
      badgeLabel: 'Scoped Queue',
      countLabel: '3',
      hasInfoAction: true,
    ),
    const UiPickerOption<String>(
      id: 'home',
      value: 'home',
      label: 'Home',
      colorDot: Color(0xFF4CAF50),
      countLabel: '2',
    ),
    const UiPickerOption<String>(
      id: 'cycle',
      value: 'cycle',
      label: 'Circular dependency',
      enabled: false,
      disabledHint: 'Cycle prevented',
    ),
  ];

  /// Ordered demo subtasks.
  final List<String> _subtasks = <String>[
    'Verify contrast tokens',
    'Test keyboard traversal',
    'Run multi-package verify',
  ];

  /// Active color wheel value.
  Color _selectedColor = UiColorWheel.canonicalPresets.first;

  /// Inline quick-create text controller.
  final TextEditingController _quickCreateController = TextEditingController();

  @override
  void dispose() {
    _quickCreateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const UiPageHeader(
          title: 'Composites',
          subtitle: 'Interactive UiDialogFrame, UiQuickComposer, UiSearchablePicker, UiOrderedItemList, and UiColorWheel.',
          countLabel: '5 composites',
        ),
        SizedBox(height: tokens.spacing.space4),
        UiCard.standard(
          headerIcon: Icons.open_in_new_rounded,
          headerTitle: 'Dialogs & Compact Bottom Sheets',
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: <Widget>[
              UiButton(
                label: 'Open Modal',
                variant: UiButtonVariant.primary,
                onPressed: () => _openSampleModal(context),
              ),
              UiButton(
                label: 'Open Bottom Sheet',
                variant: UiButtonVariant.secondary,
                onPressed: () => _openSampleSheet(context),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.spacing.space3),
        UiQuickComposer(
          controller: _quickCreateController,
          placeholder: 'Inline entity quick-create (max 120 chars)',
          maxLength: 120,
          submitLabel: 'Add',
          expandDraftLabel: 'Open as draft',
          isCollapsibleOnCompact: false,
          onSubmit: () => _quickCreateController.clear(),
          onExpandDraft: () {},
        ),
        SizedBox(height: tokens.spacing.space3),
        UiResponsiveGrid(
          preset: UiGridPreset.twoColumnMediumCollapse,
          children: <Widget>[
            UiCard.standard(
              headerIcon: Icons.search_rounded,
              headerTitle: 'Searchable Picker',
              child: UiSearchablePicker<String>(
                options: _labelOptions,
                selectedIds: _selectedLabels,
                scopeFilters: const <UiPickerScopeFilter>[
                  UiPickerScopeFilter(id: 'all', label: 'All'),
                  UiPickerScopeFilter(id: 'scoped', label: 'Scoped'),
                  UiPickerScopeFilter(id: 'global', label: 'Global'),
                ],
                activeScopeId: _activeScope,
                onScopeChanged: (id) => setState(() => _activeScope = id),
                searchPlaceholder: 'Search or create label',
                searchClearTooltip: 'Clear search',
                infoTooltip: 'Inspect label',
                removeChipTooltip: (option) => 'Remove ${option.label}',
                emptyText: 'No matching labels',
                inlineCreateLabel: (query) => 'Create & assign "$query"',
                onInlineCreate: (query) {
                  setState(() {
                    final id = query.toLowerCase();
                    _labelOptions.add(
                      UiPickerOption<String>(
                        id: id,
                        value: id,
                        label: query,
                        colorDot: const Color(0xFFFF9100),
                      ),
                    );
                    _selectedLabels.add(id);
                  });
                },
                onOptionInfo: (_) {},
                onToggleOption: (option) {
                  setState(() {
                    if (!_selectedLabels.remove(option.id)) {
                      _selectedLabels.add(option.id);
                    }
                  });
                },
              ),
            ),
            UiCard.standard(
              headerIcon: Icons.palette_outlined,
              headerTitle: 'Color Wheel & Presets',
              child: UiColorWheel(
                value: _selectedColor,
                onChanged: (next) => setState(() => _selectedColor = next),
                inputLabel: 'Label hex color',
                customButtonLabel: 'Custom color',
                modalTitle: 'Custom color wheel',
                brightnessLabel: 'Brightness',
                cancelLabel: 'Cancel',
                confirmLabel: 'Apply',
                closeTooltip: 'Close dialog',
                invalidHexError: 'Enter a valid #RRGGBB color',
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.space3),
        UiCard.standard(
          headerIcon: Icons.checklist_rounded,
          headerTitle: 'Ordered Item List',
          child: UiOrderedItemList<String>(
            title: 'Checklist steps',
            countLabel: '2 / ${_subtasks.length}',
            progressValue: _subtasks.isEmpty ? 0.0 : 2 / _subtasks.length,
            items: _subtasks,
            itemKey: (item, index) => ValueKey<String>('step_${item}_$index'),
            itemBuilder: (_, item, _, _) => Text(item),
            moveUpTooltip: 'Move up',
            moveDownTooltip: 'Move down',
            deleteTooltip: 'Remove step',
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final moved = _subtasks.removeAt(oldIndex);
                _subtasks.insert(newIndex, moved);
              });
            },
            onDelete: (_, index) => setState(() => _subtasks.removeAt(index)),
          ),
        ),
      ],
    );
  }

  /// Opens a centered [UiDialogFrame] modal example.
  Future<void> _openSampleModal(BuildContext context) async {
    await UiDialogFrame.showModal<void>(
      context: context,
      builder: (dialogContext) {
        return UiDialogFrame(
          title: 'Sample Dialog',
          subtitle:
              'Focus-trapped modal with Tab cycling and Escape dismissal.',
          size: UiDialogSize.small,
          closeTooltip: 'Close dialog',
          onClose: () => Navigator.of(dialogContext).pop(),
          body: const Text(
            'Press Tab to cycle focus or Escape to return focus to the trigger button.',
          ),
          footer: UiButton(
            label: 'Close',
            variant: UiButtonVariant.primary,
            density: UiButtonDensity.compact,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        );
      },
    );
  }

  /// Opens a compact mobile bottom sheet hosting [UiSearchablePicker] without search auto-focus.
  Future<void> _openSampleSheet(BuildContext context) async {
    await UiDialogFrame.showBottomSheet<void>(
      context: context,
      title: 'Assign Labels',
      icon: Icons.label_outline_rounded,
      countLabel: '${_selectedLabels.length}',
      doneLabel: 'Done',
      builder: (_) {
        return UiSearchablePicker<String>(
          options: _labelOptions,
          selectedIds: _selectedLabels,
          isCompactSheet: true,
          autoFocusSearch: true,
          emptyText: 'No matching labels',
          searchPlaceholder: 'Filter labels',
          onToggleOption: (option) {
            setState(() {
              if (!_selectedLabels.remove(option.id)) {
                _selectedLabels.add(option.id);
              }
            });
          },
        );
      },
    );
  }
}
