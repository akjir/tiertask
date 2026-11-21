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
import 'package:tiertask_ui/tiertask_ui.dart';

import 'gallery_sections.dart';

/// Launches the interactive TierTask UI component gallery.
void main() {
  runApp(const TierTaskUiGalleryApp());
}

/// Simulated preview viewport width preset in the gallery top bar.
enum _PreviewViewport {
  /// Expanded desktop (`1280px`).
  desktop(1280.0, 'Desktop 1280'),

  /// Medium breakpoint (`760px`).
  medium(760.0, 'Medium 760'),

  /// Compact mobile (`390px`).
  compact(390.0, 'Compact 390');

  /// Creates a [_PreviewViewport].
  const _PreviewViewport(this.width, this.label);

  /// Display label for the preview bar chip.
  final String label;

  /// Simulated logical width.
  final double width;
}

/// Standalone gallery application exercising all 17 `tiertask_ui` widgets across presets, modes, and viewports.
class TierTaskUiGalleryApp extends StatefulWidget {
  /// Creates a [TierTaskUiGalleryApp].
  const TierTaskUiGalleryApp({super.key});

  @override
  State<TierTaskUiGalleryApp> createState() => _TierTaskUiGalleryAppState();
}

/// Coordinates preset, color mode, `DEV` badge, viewport simulation, and shell preview state.
class _TierTaskUiGalleryAppState extends State<TierTaskUiGalleryApp> {
  /// Active theme preset (`Calm` default or `Plum Umber`).
  UiThemePreset _preset = UiThemePresets.calm;

  /// Active color mode brightness.
  Brightness _brightness = Brightness.light;

  /// Simulated `DEV` build profile pill visibility.
  bool _showDevPill = false;

  /// Simulated viewport width preset.
  _PreviewViewport _viewport = _PreviewViewport.desktop;

  /// Active showcase section in the gallery shell.
  GallerySection _section = GallerySection.tokens;

  /// Compact drawer open state.
  bool _drawerOpen = false;

  /// Collapsible demo sidebar Labels section state.
  bool _labelsCollapsed = false;

  /// Collapsible demo sidebar Labels filter state.
  bool _labelsFilterOpen = false;

  /// Active sidebar filter query.
  String _labelsQuery = '';

  /// Optional active label filter displayed inline or in compact chrome.
  String? _activeLabelFilter = 'Backend';

  /// Floating Undo toast visibility.
  bool _showFloatingToast = false;

  /// Docked quick-add popover visibility.
  bool _composerPopoverOpen = false;

  /// Controller for the docked Task Quick-Add composer.
  final TextEditingController _composerController = TextEditingController();

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }

  /// Active [UiThemeTokens] for the chosen preset and brightness.
  UiThemeTokens get _activeTokens =>
      _brightness == Brightness.dark ? _preset.dark : _preset.light;

  @override
  Widget build(BuildContext context) {
    final tokens = _activeTokens;
    return MaterialApp(
      title: 'TierTask UI Component Gallery',
      debugShowCheckedModeBanner: false,
      theme: tokens.toThemeData(),
      home: Scaffold(
        backgroundColor: tokens.colors.pageBg,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _GalleryPreviewControlsBar(
                preset: _preset,
                brightness: _brightness,
                showDevPill: _showDevPill,
                viewport: _viewport,
                onPresetChanged: (next) => setState(() => _preset = next),
                onBrightnessChanged: (next) =>
                    setState(() => _brightness = next),
                onToggleDevPill: () =>
                    setState(() => _showDevPill = !_showDevPill),
                onViewportChanged: (next) => setState(() {
                  _viewport = next;
                  _drawerOpen = false;
                }),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final frameWidth = math.min(
                      _viewport.width,
                      constraints.maxWidth,
                    );
                    final frameHeight = constraints.maxHeight;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(size: Size(frameWidth, frameHeight)),
                          child: SizedBox(
                            width: frameWidth,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                tokens.radii.shell,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: tokens.colors.line,
                                    width: tokens.radii.borderWidth,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    tokens.radii.shell,
                                  ),
                                ),
                                child: _buildShellPreview(tokens),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the live interactive [UiAdaptiveAppShell] preview inside the simulated frame.
  Widget _buildShellPreview(UiThemeTokens tokens) {
    final colors = tokens.colors;
    final demoLabels = <UiSidebarNavItem>[
      UiSidebarNavItem(
        id: 'backend',
        label: 'Backend',
        subtitle: 'Scoped Queue',
        colorDot: const Color(0xFF2196F3),
        countLabel: '4',
        isSelected: _activeLabelFilter == 'Backend',
        onTap: () => setState(() {
          _activeLabelFilter = _activeLabelFilter == 'Backend'
              ? null
              : 'Backend';
          _drawerOpen = false;
        }),
        trailingIcon: Icons.info_outline_rounded,
        trailingTooltip: 'Open Backend label',
        onTrailingTap: () {},
      ),
      UiSidebarNavItem(
        id: 'design',
        label: 'Design',
        colorDot: const Color(0xFF9C27B0),
        countLabel: '2',
        isSelected: _activeLabelFilter == 'Design',
        onTap: () => setState(() {
          _activeLabelFilter = _activeLabelFilter == 'Design' ? null : 'Design';
          _drawerOpen = false;
        }),
        trailingIcon: Icons.info_outline_rounded,
        trailingTooltip: 'Open Design label',
        onTrailingTap: () {},
      ),
    ];
    final filteredLabels = _labelsQuery.trim().isEmpty
        ? demoLabels
        : demoLabels
              .where(
                (item) => item.label.toLowerCase().contains(
                  _labelsQuery.trim().toLowerCase(),
                ),
              )
              .toList();

    return UiAdaptiveAppShell(
      brand: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const UiAppLogo(size: 22.0),
          const SizedBox(width: 9.0),
          Flexible(
            child: Text(
              'TierTask',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.brand.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
      workspaceTrigger: UiButton(
        label: 'Gallery Workspace',
        leadingIcon: Icons.grid_view_outlined,
        trailingIcon: Icons.unfold_more_rounded,
        variant: UiButtonVariant.secondary,
        density: UiButtonDensity.chrome,
        onPressed: () {},
      ),
      buildBadge: _showDevPill
          ? const UiPill(
              label: 'DEV',
              variant: UiPillVariant.badge,
              tone: UiPillTone.warning,
              isMono: true,
            )
          : null,
      trailingActions: <Widget>[
        UiButton(
          label: _viewport == _PreviewViewport.compact ? null : 'Synced',
          leadingIcon: Icons.cloud_done_outlined,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.chrome,
          tone: UiButtonTone.muted,
          tooltip: 'Sync status',
          onPressed: () => setState(() => _showFloatingToast = true),
        ),
      ],
      isDrawerOpen: _drawerOpen,
      onToggleDrawer: () => setState(() => _drawerOpen = !_drawerOpen),
      menuOpenTooltip: 'Open navigation menu',
      menuCloseTooltip: 'Close navigation menu',
      sidebarBody: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          UiSidebarSection(
            title: 'Catalog',
            items: <UiSidebarNavItem>[
              UiSidebarNavItem(
                id: 'tokens',
                label: 'Tokens',
                icon: Icons.palette_outlined,
                isSelected: _section == GallerySection.tokens,
                onTap: () => _selectSection(GallerySection.tokens),
              ),
              UiSidebarNavItem(
                id: 'primitives',
                label: 'Primitives',
                icon: Icons.widgets_outlined,
                countLabel: '8',
                isSelected: _section == GallerySection.primitives,
                onTap: () => _selectSection(GallerySection.primitives),
              ),
              UiSidebarNavItem(
                id: 'layouts',
                label: 'Layouts',
                icon: Icons.view_quilt_outlined,
                countLabel: '4',
                isSelected: _section == GallerySection.layouts,
                onTap: () => _selectSection(GallerySection.layouts),
              ),
              UiSidebarNavItem(
                id: 'composites',
                label: 'Composites',
                icon: Icons.dashboard_customize_outlined,
                countLabel: '5',
                isSelected: _section == GallerySection.composites,
                onTap: () => _selectSection(GallerySection.composites),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.space4),
          UiSidebarSection(
            title: 'Labels',
            isCollapsible: true,
            isCollapsed: _labelsCollapsed,
            onToggleCollapse: () =>
                setState(() => _labelsCollapsed = !_labelsCollapsed),
            collapsedCountLabel: '${demoLabels.length}',
            collapsedActiveColorDot: _activeLabelFilter != null
                ? const Color(0xFF2196F3)
                : null,
            isFilterable: true,
            isFilterOpen: _labelsFilterOpen,
            onToggleFilter: () =>
                setState(() => _labelsFilterOpen = !_labelsFilterOpen),
            filterQuery: _labelsQuery,
            onFilterChanged: (next) => setState(() => _labelsQuery = next),
            filterPlaceholder: 'Filter labels',
            filterClearTooltip: 'Clear filter',
            filterEmptyText: 'No matching labels',
            filterTooltip: 'Filter labels',
            manageTooltip: 'Manage labels',
            collapseTooltip: 'Collapse labels',
            expandTooltip: 'Expand labels',
            onManage: () {},
            items: filteredLabels,
          ),
        ],
      ),
      sidebarFooter: Text(
        'Version 0.4.0+gallery',
        style: UiTypographyTokens.mono(
          tokens.typography.eyebrow.copyWith(
            color: colors.muted,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.0,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: tokens.spacing.mainContentPadding(
          UiBreakpoints.classify(_viewport.width),
        ),
        child: _buildActiveSection(),
      ),
      floatingNotice: _showFloatingToast
          ? UiBanner(
              variant: UiBannerVariant.toast,
              message: 'Sample task saved in Focus',
              actionLabel: 'Undo',
              kbdHint: 'Ctrl+Z',
              onAction: () => setState(() => _showFloatingToast = false),
              onDismiss: () => setState(() => _showFloatingToast = false),
              dismissTooltip: 'Close notice',
            )
          : null,
      bottomDock: UiQuickComposer(
        controller: _composerController,
        placeholder: 'Add a task to preview docked composer',
        submitLabel: '+ Add',
        expandDraftLabel: 'Open as draft',
        compactTriggerLabel: '+ New task',
        compactCloseTooltip: 'Close composer',
        modeHint: 'Docked below floating notices',
        draftChips: UiPill(
          label: 'Labels',
          variant: UiPillVariant.selectable,
          icon: Icons.label_outline_rounded,
          isSelected: _composerPopoverOpen,
          onPressed: () =>
              setState(() => _composerPopoverOpen = !_composerPopoverOpen),
        ),
        isPopoverOpen: _composerPopoverOpen,
        onDismissPopover: () => setState(() => _composerPopoverOpen = false),
        popoverContent: const Text('Upward desktop popover (TapRegion)'),
        onSubmit: () {
          _composerController.clear();
          setState(() => _showFloatingToast = true);
        },
        onExpandDraft: () => setState(() => _showFloatingToast = true),
      ),
    );
  }

  /// Selects a gallery section and closes the compact drawer.
  void _selectSection(GallerySection section) {
    setState(() {
      _section = section;
      _drawerOpen = false;
    });
  }

  /// Builds the currently selected gallery section content.
  Widget _buildActiveSection() {
    return switch (_section) {
      GallerySection.tokens => const TokensGallerySection(),
      GallerySection.primitives => PrimitivesGallerySection(
        onShowToast: () => setState(() => _showFloatingToast = true),
      ),
      GallerySection.layouts => LayoutsGallerySection(
        activeLabel: _activeLabelFilter,
        onClearActiveLabel: () => setState(() => _activeLabelFilter = null),
      ),
      GallerySection.composites => const CompositesGallerySection(),
    };
  }
}

/// Top harness bar letting developers switch preset, brightness, `DEV` badge, and viewport width.
class _GalleryPreviewControlsBar extends StatelessWidget {
  /// Creates a [_GalleryPreviewControlsBar].
  const _GalleryPreviewControlsBar({
    required this.preset,
    required this.brightness,
    required this.showDevPill,
    required this.viewport,
    required this.onPresetChanged,
    required this.onBrightnessChanged,
    required this.onToggleDevPill,
    required this.onViewportChanged,
  });

  /// Active color mode brightness.
  final Brightness brightness;

  /// Updates brightness.
  final ValueChanged<Brightness> onBrightnessChanged;

  /// Updates theme preset.
  final ValueChanged<UiThemePreset> onPresetChanged;

  /// Toggles `DEV` badge pill.
  final VoidCallback onToggleDevPill;

  /// Updates simulated viewport width.
  final ValueChanged<_PreviewViewport> onViewportChanged;

  /// Active preset.
  final UiThemePreset preset;

  /// Whether `DEV` pill is visible.
  final bool showDevPill;

  /// Active simulated viewport width.
  final _PreviewViewport viewport;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(
          bottom: BorderSide(
            color: colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        child: Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            UiPill(
              label: 'Calm',
              variant: UiPillVariant.selectable,
              isSelected: preset == UiThemePresets.calm,
              onPressed: () => onPresetChanged(UiThemePresets.calm),
            ),
            UiPill(
              label: 'Plum Umber',
              variant: UiPillVariant.selectable,
              isSelected: preset == UiThemePresets.plumUmber,
              onPressed: () => onPresetChanged(UiThemePresets.plumUmber),
            ),
            UiPill(
              label: 'Light',
              variant: UiPillVariant.selectable,
              isSelected: brightness == Brightness.light,
              onPressed: () => onBrightnessChanged(Brightness.light),
            ),
            UiPill(
              label: 'Dark',
              variant: UiPillVariant.selectable,
              isSelected: brightness == Brightness.dark,
              onPressed: () => onBrightnessChanged(Brightness.dark),
            ),
            UiPill(
              label: 'DEV pill',
              variant: UiPillVariant.selectable,
              isSelected: showDevPill,
              onPressed: onToggleDevPill,
            ),
            for (final candidate in _PreviewViewport.values)
              UiPill(
                label: candidate.label,
                variant: UiPillVariant.selectable,
                isSelected: viewport == candidate,
                onPressed: () => onViewportChanged(candidate),
              ),
          ],
        ),
      ),
    );
  }
}
