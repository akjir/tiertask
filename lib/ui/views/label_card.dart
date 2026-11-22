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

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tdf_error.dart';
import '../../models/tdf_location.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/entity_actions_provider.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../../providers/ui_telemetry.dart';
import '../components/ui_color_wheel.dart';
import '../components/ui_ordered_item_list.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_pill.dart';
import '../primitives/ui_segmented_control.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import '../widgets/entity_card_chrome.dart';
import '../widgets/entity_conditions_section.dart';
import '../widgets/entity_inline_name_editor.dart';
import '../widgets/entity_links_section.dart';
import '../widgets/entity_note_section.dart';

/// Leading rounded-square color dot size inside expanded and collapsed Label card headers (`U-CARD-001`).
const double _labelColorDotSize = 12.0;

/// Unified expandable Label entity card sharing single-expand coordination (`U-CARD-001`..`005`).
class LabelCard extends ConsumerWidget {
  /// Creates a [LabelCard].
  const LabelCard({
    super.key,
    required this.cardScrollKey,
    required this.label,
  });

  /// [GlobalKey] attached around the card for smooth reveal scrolling.
  final GlobalKey cardScrollKey;

  /// Persisted domain label rendered by this card.
  final TdfLabel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entityRef = EntityRef(kind: EntityKind.label, id: label.id);
    final openCount = ref.watch(
      taskNotifierProvider.select(
        (boardAsync) =>
            boardAsync.asData?.value.openTaskCountsByLabel[label.id] ?? 0,
      ),
    );
    final isExpanded = ref.watch(
      shellProvider.select((shell) => shell.expandedEntity == entityRef),
    );
    final editingSection = ref.watch(
      shellProvider.select(
        (shell) => _parseInlineEditSection(shell.activeInlineEdit, label.id),
      ),
    );
    final isConfirmingDelete = ref.watch(
      shellProvider.select((shell) => shell.activeDeleteConfirm == entityRef),
    );
    final isBusy = ref.watch(
      entityActionsProvider.select((state) => state.isBusy),
    );

    return KeyedSubtree(
      key: cardScrollKey,
      child: _LabelExpandableCardView(
        label: label,
        openCount: openCount,
        isExpanded: isExpanded,
        editingSection: editingSection,
        isConfirmingDelete: isConfirmingDelete,
        isBusy: isBusy,
      ),
    );
  }
}

/// Accent-bordered uncommitted Label Draft Card replacing the Quick-Create bar in place (`U-CARD-006`).
class LabelDraftCard extends ConsumerStatefulWidget {
  /// Creates a [LabelDraftCard].
  const LabelDraftCard({
    super.key,
    required this.seedTitle,
    required this.initialColorHex,
    required this.onCancel,
  });

  /// Rotating preset `#RRGGBB` color seeding [UiColorWheel].
  final String initialColorHex;

  /// Callback discarding the draft without mutating the board.
  final VoidCallback onCancel;

  /// Initial label name transferred from Quick-Create.
  final String seedTitle;

  @override
  ConsumerState<LabelDraftCard> createState() => _LabelDraftCardState();
}

/// Label-specific [EntityCardMetaBar] wiring Copy ID, open count pill, and inline Delete confirmation.
class _LabelCardMetaBar extends ConsumerWidget {
  /// Creates a [_LabelCardMetaBar].
  const _LabelCardMetaBar({
    required this.label,
    required this.openCount,
    required this.isConfirmingDelete,
  });

  /// Whether inline delete confirmation is open.
  final bool isConfirmingDelete;

  /// Persisted domain label rendered by this card.
  final TdfLabel label;

  /// Count of open tasks referencing [label].
  final int openCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final shellNotifier = ref.read(shellProvider.notifier);

    return EntityCardMetaBar(
      entityId: label.id,
      copyIdTooltip: localizations.actionCopy,
      onCopyId: () => unawaited(
        _copyLabelId(
          context,
          ref,
          labelId: label.id,
          copiedNotice: localizations.labelIdCopiedNotice,
        ),
      ),
      statusPillLabel: localizations.openTasksCountPill('$openCount'),
      statusPillTone: UiPillTone.soft,
      deleteConfirmMessage: localizations.inlineDeleteLabelConfirm,
      isConfirmingDelete: isConfirmingDelete,
      onCancelDelete: shellNotifier.cancelInlineDelete,
      onConfirmDelete: () =>
          unawaited(_confirmDeleteLabel(context, ref, label.id)),
    );
  }
}

/// Static uncapped [Wrap] of collapsed label metadata badges inside [_LabelCollapsedMetadataStrip].
class _LabelCollapsedMetadataBadges extends StatelessWidget {
  /// Creates a [_LabelCollapsedMetadataBadges].
  const _LabelCollapsedMetadataBadges({
    required this.label,
    required this.openCount,
  });

  /// Persisted domain label.
  final TdfLabel label;

  /// Count of open tasks referencing [label].
  final int openCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        _LabelScopeBadge(isScoped: label.isScoped),
        UiPill(
          label: localizations.openTasksCountPill('$openCount'),
          variant: UiPillVariant.meta,
        ),
        if (_hasNonEmptyNote(label.note))
          UiPill(
            label: localizations.tooltipIndicatorNote,
            variant: UiPillVariant.meta,
            icon: Icons.description_outlined,
          ),
        if (label.links.isNotEmpty)
          _LabelLinksBadge(linkCount: label.links.length),
        if (label.conditions.isNotEmpty)
          UiPill(
            label: localizations.tooltipIndicatorConditions,
            variant: UiPillVariant.meta,
            icon: Icons.tune_rounded,
          ),
      ],
    );
  }
}

/// Uncapped collapsed metadata strip displaying Scope, open task count, Note, Links, and Conditions badges (`U-CARD-005`).
class _LabelCollapsedMetadataStrip extends StatelessWidget {
  /// Creates a [_LabelCollapsedMetadataStrip].
  const _LabelCollapsedMetadataStrip({
    required this.label,
    required this.openCount,
    required this.onToggleExpand,
  });

  /// Persisted domain label.
  final TdfLabel label;

  /// Callback toggling expansion of the owning label card.
  final VoidCallback onToggleExpand;

  /// Count of open tasks referencing [label].
  final int openCount;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggleExpand,
        child: _LabelCollapsedMetadataBadges(
          label: label,
          openCount: openCount,
        ),
      ),
    );
  }
}

/// Inline Color editor inset card embedding [UiColorWheel] and [EntityInlineEditorFooter].
class _LabelColorEditCard extends StatelessWidget {
  /// Creates a [_LabelColorEditCard].
  const _LabelColorEditCard({
    required this.selectedColor,
    required this.hasPersistedColor,
    required this.errorText,
    required this.isBusy,
    required this.onColorChanged,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
  });

  /// Optional inline validation or persistence error text.
  final String? errorText;

  /// Controls visibility of the footer `Clear` button.
  final bool hasPersistedColor;

  /// Disables controls while submitting.
  final bool isBusy;

  /// Callback cancelling inline editing.
  final VoidCallback onCancel;

  /// Callback clearing the persisted label color.
  final Future<void> Function() onClear;

  /// Callback emitted when the user chooses a color in [UiColorWheel].
  final ValueChanged<Color> onColorChanged;

  /// Callback saving the selected `#RRGGBB` color.
  final Future<void> Function() onSave;

  /// Active selected color.
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      isEditing: true,
      headerIcon: Icons.palette_outlined,
      headerTitle: localizations.labelColorSectionTitle,
      footer: EntityInlineEditorFooter(
        errorText: errorText,
        clearLabel: hasPersistedColor ? localizations.inlineClearAction : null,
        onClear: hasPersistedColor ? () => unawaited(onClear()) : null,
        onCancel: onCancel,
        onSave: () => unawaited(onSave()),
        isBusy: isBusy,
      ),
      child: _LabelColorWheelField(
        value: selectedColor,
        enabled: !isBusy,
        onChanged: onColorChanged,
      ),
    );
  }
}

/// Read-only Color inset card displaying swatch, uppercase `#RRGGBB` hex, and Edit pencil.
class _LabelColorReadOnlyCard extends StatelessWidget {
  /// Creates a [_LabelColorReadOnlyCard].
  const _LabelColorReadOnlyCard({
    required this.labelId,
    required this.colorHex,
    required this.colorValue,
    required this.isBusy,
    required this.onStartEdit,
  });

  /// Persisted `#RRGGBB` string, or empty when unset.
  final String colorHex;

  /// Parsed ARGB integer color, or `null` when unset.
  final int? colorValue;

  /// Disables the Edit trigger while busy.
  final bool isBusy;

  /// Canonical label identifier for deterministic test keys.
  final String labelId;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.palette_outlined,
      headerTitle: localizations.labelColorSectionTitle,
      headerTrailing: UiButton(
        key: ValueKey<String>('label_edit_color_$labelId'),
        leadingIcon: Icons.edit_outlined,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.dense,
        tooltip: localizations.actionEdit,
        onPressed: isBusy ? null : onStartEdit,
      ),
      child: _LabelColorSwatchReadout(
        colorHex: colorHex,
        colorValue: colorValue,
      ),
    );
  }
}

/// Always-visible Color inset section supporting read-only swatch/hex display and inline [UiColorWheel] editing.
class _LabelColorSection extends StatefulWidget {
  /// Creates a [_LabelColorSection].
  const _LabelColorSection({
    required this.labelId,
    required this.colorHex,
    required this.colorValue,
    required this.isEditing,
    required this.isBusy,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSave,
    required this.onClear,
  });

  /// Persisted `#RRGGBB` string, or empty string when unset.
  final String colorHex;

  /// Parsed ARGB integer color, or `null` when unset.
  final int? colorValue;

  /// Disables actions while a parent mutation is in flight.
  final bool isBusy;

  /// Whether inline [UiColorWheel] editing mode is active.
  final bool isEditing;

  /// Canonical label identifier for deterministic test keys.
  final String labelId;

  /// Callback cancelling inline editing.
  final VoidCallback onCancelEdit;

  /// Callback clearing the persisted label color.
  final Future<ActionResult> Function() onClear;

  /// Callback saving a normalized `#RRGGBB` color string.
  final Future<ActionResult> Function(String colorHex) onSave;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  @override
  State<_LabelColorSection> createState() => _LabelColorSectionState();
}

/// Wires always-visible [_LabelColorSection] to [entityActionsProvider] for one label card.
class _LabelColorSectionCard extends ConsumerWidget {
  /// Creates a [_LabelColorSectionCard].
  const _LabelColorSectionCard({
    required this.label,
    required this.isEditing,
    required this.isBusy,
  });

  /// Disables controls while a mutation is in flight.
  final bool isBusy;

  /// Whether inline [UiColorWheel] editing is active.
  final bool isEditing;

  /// Persisted domain label.
  final TdfLabel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    final shellNotifier = ref.read(shellProvider.notifier);
    final entityNotifier = ref.read(entityActionsProvider.notifier);

    return _LabelColorSection(
      labelId: label.id,
      colorHex: label.color ?? '',
      colorValue: TaskScheduleHelper.parseLabelColorValue(label.color),
      isEditing: isEditing,
      isBusy: isBusy,
      onStartEdit: () => shellNotifier.openInlineEdit(
        InlineEditTarget.label(label.id, LabelSectionKind.color),
      ),
      onCancelEdit: shellNotifier.closeInlineEdit,
      onSave: (colorHex) =>
          entityNotifier.saveLabelColor(label.id, colorHex, locale: locale),
      onClear: () => entityNotifier.clearLabelColor(label.id, locale: locale),
    );
  }
}

/// Manages selected color state and save/clear submission for [_LabelColorSection].
class _LabelColorSectionState extends State<_LabelColorSection> {
  String? _errorText;
  bool _isSubmitting = false;
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = _resolveSeedColor(widget.colorHex);
  }

  @override
  void didUpdateWidget(covariant _LabelColorSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _selectedColor = _resolveSeedColor(widget.colorHex);
      _errorText = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _errorText = null;
      _isSubmitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditing) {
      return _LabelColorReadOnlyCard(
        labelId: widget.labelId,
        colorHex: widget.colorHex,
        colorValue: widget.colorValue,
        isBusy: widget.isBusy,
        onStartEdit: widget.onStartEdit,
      );
    }
    return _LabelColorEditCard(
      selectedColor: _selectedColor,
      hasPersistedColor: widget.colorHex.isNotEmpty,
      errorText: _errorText,
      isBusy: widget.isBusy || _isSubmitting,
      onColorChanged: _handleColorChanged,
      onClear: _handleClear,
      onCancel: widget.onCancelEdit,
      onSave: _handleSave,
    );
  }

  /// Applies [result] from save or clear to inline error state.
  void _applyActionResult(ActionResult result) {
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        break;
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() => _errorText = message);
    }
  }

  /// Clears the persisted label color while guarding against overlapping submissions.
  Future<void> _handleClear() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await widget.onClear();
      _applyActionResult(result);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Updates the active draft color selected from [UiColorWheel].
  void _handleColorChanged(Color color) {
    setState(() {
      _selectedColor = color;
      _errorText = null;
    });
  }

  /// Commits the selected `#RRGGBB` color string via [widget.onSave].
  Future<void> _handleSave() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await widget.onSave(
        UiColorWheel.formatHex(_selectedColor),
      );
      _applyActionResult(result);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Parses [colorHex] or falls back to the first canonical preset when color is unset.
  Color _resolveSeedColor(String colorHex) {
    return UiColorWheel.tryParseHex(colorHex) ??
        UiColorWheel.canonicalPresets.first;
  }
}

/// Displays the square-rounded swatch and monospace `#RRGGBB` readout (or hint when unset).
class _LabelColorSwatchReadout extends StatelessWidget {
  /// Creates a [_LabelColorSwatchReadout].
  const _LabelColorSwatchReadout({
    required this.colorHex,
    required this.colorValue,
  });

  /// Persisted `#RRGGBB` string, or empty when unset.
  final String colorHex;

  /// Parsed ARGB integer color, or `null` when unset.
  final int? colorValue;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final hasColor = colorHex.isNotEmpty && colorValue != null;
    final swatchColor = switch (colorValue) {
      final int value => Color(value),
      null => Colors.transparent,
    };

    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Container(
            width: 14.0,
            height: 14.0,
            decoration: BoxDecoration(
              color: swatchColor,
              borderRadius: BorderRadius.circular(tokens.radii.dotLg),
              border: Border.all(
                color: hasColor ? colors.line : colors.muted,
                width: tokens.radii.borderWidth,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8.0),
        Text(
          hasColor ? colorHex.toUpperCase() : localizations.labelColorHint,
          style: hasColor
              ? UiTypographyTokens.mono(
                  tokens.typography.monoSmall.copyWith(color: colors.ink),
                )
              : tokens.typography.meta.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}

/// Shared localized adapter wrapping [UiColorWheel] for both Label Draft and inline Color editing (`U-COMP-007`).
class _LabelColorWheelField extends StatelessWidget {
  /// Creates a [_LabelColorWheelField].
  const _LabelColorWheelField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  /// Whether color inputs and wheel trigger accept interaction.
  final bool enabled;

  /// Callback emitted when a color is selected.
  final ValueChanged<Color> onChanged;

  /// Active color value.
  final Color value;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiColorWheel(
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      customButtonLabel: localizations.tooltipPickCustomColor,
      modalTitle: localizations.labelColorPickerDialogTitle,
      brightnessLabel: localizations.labelColorBrightnessLabel,
      cancelLabel: localizations.actionCancel,
      confirmLabel: localizations.actionSelectColor,
      closeTooltip: localizations.actionClose,
      invalidHexError: localizations.labelColorErrorInvalid,
    );
  }
}

/// Renders [EntityConditionsSection] with lazily computed summary chips and draft for an expanded label card.
class _LabelConditionsSectionBody extends ConsumerWidget {
  /// Creates a [_LabelConditionsSectionBody].
  const _LabelConditionsSectionBody({
    required this.label,
    required this.allLocations,
    required this.hasConditions,
    required this.isEditing,
    required this.isBusy,
  });

  /// Saved workspace locations selectable inside GPS conditions.
  final List<TdfLocation> allLocations;

  /// Whether [label] currently declares activation conditions.
  final bool hasConditions;

  /// Disables controls while a mutation is in flight.
  final bool isBusy;

  /// Whether inline Activation Conditions editing is active.
  final bool isEditing;

  /// Persisted domain label.
  final TdfLabel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final shellNotifier = ref.read(shellProvider.notifier);
    final entityNotifier = ref.read(entityActionsProvider.notifier);

    return EntityConditionsSection(
      isTask: false,
      hasConditions: hasConditions,
      conditionsSummary: _buildLabelConditionsSummary(
        label,
        allLocations,
        localizations,
      ),
      conditionDraft: TaskScheduleHelper.buildConditionDraft(
        label.conditions,
        isTask: false,
      ),
      allLocations: allLocations,
      isEditing: isEditing,
      canEdit: true,
      isBusy: isBusy,
      onStartEdit: () => shellNotifier.openInlineEdit(
        InlineEditTarget.label(label.id, LabelSectionKind.conditions),
      ),
      onCancelEdit: shellNotifier.closeInlineEdit,
      onSave: (draft) =>
          entityNotifier.saveLabelConditions(label.id, draft, locale: locale),
      onClear: () => _clearLabelConditions(context, ref, label.id),
      onOpenLocation: (locationId) => shellNotifier.openEntityInManager(
        EntityRef(kind: EntityKind.location, id: locationId),
        preserveReturnContext: false,
      ),
    );
  }
}

/// Lazily subscribes to workspace locations when an expanded label has or edits activation conditions.
class _LabelConditionsSectionCard extends ConsumerWidget {
  /// Creates a [_LabelConditionsSectionCard].
  const _LabelConditionsSectionCard({
    required this.label,
    required this.isEditing,
    required this.isBusy,
  });

  /// Disables controls while a mutation is in flight.
  final bool isBusy;

  /// Whether inline Activation Conditions editing is active.
  final bool isEditing;

  /// Persisted domain label.
  final TdfLabel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasConditions = label.conditions.isNotEmpty;
    if (!hasConditions && !isEditing) {
      return const SizedBox.shrink();
    }
    final allLocations = ref.watch(
      taskNotifierProvider.select(
        (boardAsync) =>
            boardAsync.asData?.value.sortedLocations ?? const <TdfLocation>[],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: UiThemeTokens.of(context).spacing.space2),
      child: _LabelConditionsSectionBody(
        label: label,
        allLocations: allLocations,
        hasConditions: hasConditions,
        isEditing: isEditing,
        isBusy: isBusy,
      ),
    );
  }
}

/// Trailing danger-styled delete icon button rendered while a Label card is expanded (`U-CARD-001`).
class _LabelDeleteButton extends ConsumerWidget {
  /// Creates a [_LabelDeleteButton].
  const _LabelDeleteButton({
    required this.labelId,
    required this.isConfirmingDelete,
    required this.isBusy,
  });

  /// Disables the button while a mutation is in flight.
  final bool isBusy;

  /// Disables the button while the inline delete confirmation banner is open.
  final bool isConfirmingDelete;

  /// Canonical label identifier for deterministic test keys and delete requests.
  final String labelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return EntityHeaderDeleteButton(
      key: ValueKey<String>('label_delete_$labelId'),
      tooltip: localizations.tooltipDeleteLabel,
      isConfirmingDelete: isConfirmingDelete,
      isBusy: isBusy,
      onRequestDelete: () => ref
          .read(shellProvider.notifier)
          .requestInlineDelete(EntityRef(kind: EntityKind.label, id: labelId)),
    );
  }
}

/// Dashed `+ Add` chip bar revealing optional Note, Links, and Conditions sections inside [LabelDraftCard].
class _LabelDraftAddChipsBar extends StatelessWidget {
  /// Creates a [_LabelDraftAddChipsBar].
  const _LabelDraftAddChipsBar({
    required this.showNote,
    required this.showLinks,
    required this.showConditions,
    required this.enabled,
    required this.onOpenNote,
    required this.onOpenLinks,
    required this.onOpenConditions,
  });

  /// Whether add chips accept clicks.
  final bool enabled;

  /// Callback revealing draft Conditions.
  final VoidCallback onOpenConditions;

  /// Callback revealing draft Links.
  final VoidCallback onOpenLinks;

  /// Callback revealing draft Note.
  final VoidCallback onOpenNote;

  /// Whether `+ Conditions` chip is shown.
  final bool showConditions;

  /// Whether `+ Links` chip is shown.
  final bool showLinks;

  /// Whether `+ Note` chip is shown.
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        if (showNote)
          UiPill(
            key: const ValueKey<String>('label_draft_add_note'),
            label: localizations.inlineAddNote,
            icon: Icons.description_outlined,
            variant: UiPillVariant.addField,
            enabled: enabled,
            onPressed: enabled ? onOpenNote : null,
          ),
        if (showLinks)
          UiPill(
            key: const ValueKey<String>('label_draft_add_links'),
            label: localizations.inlineAddLinks,
            icon: Icons.link_rounded,
            variant: UiPillVariant.addField,
            enabled: enabled,
            onPressed: enabled ? onOpenLinks : null,
          ),
        if (showConditions)
          UiPill(
            key: const ValueKey<String>('label_draft_add_conditions'),
            label: localizations.inlineAddConditions,
            icon: Icons.tune_rounded,
            variant: UiPillVariant.addField,
            enabled: enabled,
            onPressed: enabled ? onOpenConditions : null,
          ),
      ],
    );
  }
}

/// Vertical body container stacking primary draft fields, optional sections, and `+ Add` chips inside [LabelDraftCard].
class _LabelDraftBody extends StatelessWidget {
  /// Creates a [_LabelDraftBody].
  const _LabelDraftBody({
    required this.primaryData,
    required this.showNote,
    required this.noteController,
    required this.noteError,
    required this.onNoteChanged,
    required this.showLinks,
    required this.linksData,
    required this.showConditions,
    required this.conditionsData,
    required this.isBusy,
    required this.onRevealSection,
  });

  /// Bundled draft conditions state and callbacks.
  final _LabelDraftConditionsData conditionsData;

  /// Disables all draft controls while submitting.
  final bool isBusy;

  /// Bundled draft links state and callbacks.
  final _LabelDraftLinksData linksData;

  /// Draft note controller.
  final TextEditingController noteController;

  /// Optional inline validation error for draft note.
  final String? noteError;

  /// Callback clearing note errors on text change.
  final ValueChanged<String> onNoteChanged;

  /// Callback revealing one optional draft section.
  final ValueChanged<LabelSectionKind> onRevealSection;

  /// Bundled always-visible Name, Color, and Board Scope state.
  final _LabelDraftPrimaryData primaryData;

  /// Whether draft Activation Conditions section is open.
  final bool showConditions;

  /// Whether draft Reference Links section is open.
  final bool showLinks;

  /// Whether draft Note section is open.
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final hasHiddenOptional = !showNote || !showLinks || !showConditions;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LabelDraftPrimaryFields(data: primaryData, isBusy: isBusy),
        _LabelDraftOptionalSections(
          showNote: showNote,
          noteController: noteController,
          noteError: noteError,
          onNoteChanged: onNoteChanged,
          showLinks: showLinks,
          linksData: linksData,
          showConditions: showConditions,
          conditionsData: conditionsData,
          isBusy: isBusy,
        ),
        if (hasHiddenOptional) ...<Widget>[
          SizedBox(height: tokens.spacing.space3),
          _LabelDraftAddChipsBar(
            showNote: !showNote,
            showLinks: !showLinks,
            showConditions: !showConditions,
            enabled: !isBusy,
            onOpenNote: () => onRevealSection(LabelSectionKind.note),
            onOpenLinks: () => onRevealSection(LabelSectionKind.links),
            onOpenConditions: () =>
                onRevealSection(LabelSectionKind.conditions),
          ),
        ],
      ],
    );
  }
}

/// Manages uncommitted form state for [LabelDraftCard].
class _LabelDraftCardState extends ConsumerState<LabelDraftCard> {
  late final TextEditingController _linkTitleController;
  late final TextEditingController _linkUriController;
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late final TextEditingController _timeEndController;
  late final TextEditingController _timeStartController;

  ConditionDraft _conditionDraft = ConditionDraft();
  List<TaskLink> _draftLinks = const <TaskLink>[];
  int? _editingLinkIndex;
  Map<String, String> _fieldErrors = const <String, String>{};
  String? _generalError;
  bool _isScoped = false;
  bool _isSubmitting = false;
  String? _linkInputError;
  late Color _selectedColor;
  bool _showConditions = false;
  bool _showLinks = false;
  bool _showNote = false;
  String? _timeInputError;

  /// Bundled draft activation conditions state and callbacks.
  _LabelDraftConditionsData get _conditionsData => _LabelDraftConditionsData(
    draft: _conditionDraft,
    timeStartController: _timeStartController,
    timeEndController: _timeEndController,
    timeInputError: _timeInputError,
    onToggleWeekday: _handleToggleWeekday,
    onAddTimeWindow: _handleAddTimeWindow,
    onRemoveTimeWindow: _handleRemoveTimeWindow,
    onToggleLocation: _handleToggleLocation,
  );

  /// Bundled draft reference links state and callbacks.
  _LabelDraftLinksData get _linksData => _LabelDraftLinksData(
    links: _draftLinks,
    editingIndex: _editingLinkIndex,
    titleController: _linkTitleController,
    uriController: _linkUriController,
    inputError: _linkInputError,
    onReorder: _handleReorderLink,
    onEdit: _handleStartLinkEdit,
    onDelete: _handleDeleteLink,
    onInputChanged: _handleLinkInputChanged,
    onCommitLink: _handleCommitLinkInput,
    onCancelRowEdit: _handleCancelLinkEdit,
  );

  /// Bundled always-visible draft Name, Color, and Board Scope state and callbacks.
  _LabelDraftPrimaryData get _primaryData => _LabelDraftPrimaryData(
    nameController: _nameController,
    nameError: _fieldErrors['name'],
    selectedColor: _selectedColor,
    isScoped: _isScoped,
    onNameChanged: (_) => _clearFieldError('name'),
    onSubmitFromField: _handleSubmit,
    onColorChanged: _handleColorChanged,
    onScopeChanged: _handleScopeChanged,
  );

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.seedTitle);
    _noteController = TextEditingController();
    _linkTitleController = TextEditingController();
    _linkUriController = TextEditingController();
    _timeStartController = TextEditingController();
    _timeEndController = TextEditingController();
    _selectedColor =
        UiColorWheel.tryParseHex(widget.initialColorHex) ??
        UiColorWheel.canonicalPresets.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _linkTitleController.dispose();
    _linkUriController.dispose();
    _timeStartController.dispose();
    _timeEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isBusy =
        _isSubmitting ||
        ref.watch(entityActionsProvider.select((state) => state.isBusy));

    return UiCard.draft(
      key: const ValueKey<String>('label_draft_card'),
      title: localizations.draftNewLabelTitle,
      subtitle: localizations.draftUncommittedHint,
      closeTooltip: localizations.actionCancel,
      onClose: isBusy ? null : widget.onCancel,
      errorText: _generalError,
      footer: _LabelDraftFooter(
        isBusy: isBusy,
        onCancel: widget.onCancel,
        onSubmit: _handleSubmit,
      ),
      child: _LabelDraftBody(
        primaryData: _primaryData,
        showNote: _showNote,
        noteController: _noteController,
        noteError: _fieldErrors['note'],
        onNoteChanged: (_) => _clearFieldError('note'),
        showLinks: _showLinks,
        linksData: _linksData,
        showConditions: _showConditions,
        conditionsData: _conditionsData,
        isBusy: isBusy,
        onRevealSection: _handleRevealSection,
      ),
    );
  }

  /// Applies [result] from `createLabelDraft` to inline error state.
  void _applySubmitResult(ActionResult result) {
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        break;
      case ActionValidationFailed(:final message, :final fieldErrors):
        setState(() {
          _fieldErrors = fieldErrors;
          _generalError = _resolveDraftBannerError(
            message,
            fieldErrors,
            showNote: _showNote,
          );
        });
      case ActionPersistFailed(:final message):
        setState(() => _generalError = message);
    }
  }

  /// Builds the immutable [LabelDraftInput] snapshot from active form state.
  LabelDraftInput _buildDraftInput() {
    final hasDraftConditions =
        _showConditions &&
        (_conditionDraft.weekdays.isNotEmpty ||
            _conditionDraft.timeWindows.isNotEmpty ||
            _conditionDraft.locationIds.isNotEmpty);
    return LabelDraftInput(
      name: _nameController.text,
      colorHex: UiColorWheel.formatHex(_selectedColor),
      isScoped: _isScoped,
      note: _showNote ? _noteController.text : '',
      links: _showLinks ? _draftLinks : const <TaskLink>[],
      conditions: hasDraftConditions ? _conditionDraft : null,
    );
  }

  /// Clears a single per-field validation error and any banner-level fallback error.
  void _clearFieldError(String fieldKey) {
    if (!_fieldErrors.containsKey(fieldKey) && _generalError == null) {
      return;
    }
    final nextErrors = Map<String, String>.of(_fieldErrors)..remove(fieldKey);
    setState(() {
      _fieldErrors = nextErrors;
      _generalError = null;
    });
  }

  /// Commits any typed pending link or time-window inputs before submitting the draft.
  bool _flushPendingSubInputs() {
    final hasPendingLink =
        _showLinks &&
        (_linkTitleController.text.trim().isNotEmpty ||
            _linkUriController.text.trim().isNotEmpty);
    if (hasPendingLink && !_handleCommitLinkInput()) {
      return false;
    }
    final hasPendingTime =
        _showConditions &&
        (_timeStartController.text.trim().isNotEmpty ||
            _timeEndController.text.trim().isNotEmpty);
    if (hasPendingTime && !_handleAddTimeWindow()) {
      return false;
    }
    return true;
  }

  /// Validates and appends a `HH:MM`..`HH:MM` daily time window into [_conditionDraft].
  bool _handleAddTimeWindow() {
    final localizations = AppLocalizations.of(context);
    final startToken = _timeStartController.text.trim();
    final endToken = _timeEndController.text.trim();
    if (TimeWindowTaskCondition.tryParse(startToken, endToken) == null) {
      setState(() => _timeInputError = localizations.conditionTimeErrorInvalid);
      return false;
    }
    final nextWindows = <TimeWindowDraft>[
      ..._conditionDraft.timeWindows,
      TimeWindowDraft(start: startToken, end: endToken),
    ];
    setState(() {
      _conditionDraft = _conditionDraft.copyWith(timeWindows: nextWindows);
      _timeStartController.clear();
      _timeEndController.clear();
      _timeInputError = null;
      _generalError = null;
    });
    return true;
  }

  /// Cancels an in-progress draft link row update.
  void _handleCancelLinkEdit() {
    setState(() {
      _editingLinkIndex = null;
      _linkTitleController.clear();
      _linkUriController.clear();
      _linkInputError = null;
    });
  }

  /// Updates [_selectedColor] and clears any prior color error.
  void _handleColorChanged(Color color) {
    setState(() {
      _selectedColor = color;
      _generalError = null;
    });
    _clearFieldError('color');
  }

  /// Validates and inserts or updates the typed draft link row.
  bool _handleCommitLinkInput() {
    final editingIndex = _editingLinkIndex;
    final error = TaskScheduleHelper.validateLinkInput(
      rawTitle: _linkTitleController.text,
      rawUri: _linkUriController.text,
      currentCount: _draftLinks.length,
      localizations: AppLocalizations.of(context),
      isEditingExisting: editingIndex != null,
      isLabel: true,
    );
    if (error != null) {
      setState(() => _linkInputError = error);
      return false;
    }
    final entry = TaskLink(
      title: _linkTitleController.text.trim(),
      uri: _linkUriController.text.trim(),
    );
    final nextLinks = List<TaskLink>.of(_draftLinks);
    if (editingIndex != null &&
        editingIndex >= 0 &&
        editingIndex < nextLinks.length) {
      nextLinks[editingIndex] = entry;
    } else {
      nextLinks.add(entry);
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingLinkIndex = null;
      _linkTitleController.clear();
      _linkUriController.clear();
      _linkInputError = null;
      _generalError = null;
    });
    return true;
  }

  /// Deletes the draft link row at [index].
  void _handleDeleteLink(TaskLink link, int index) {
    if (index < 0 || index >= _draftLinks.length) {
      return;
    }
    final nextLinks = List<TaskLink>.of(_draftLinks)..removeAt(index);
    int? nextEditing = _editingLinkIndex;
    if (nextEditing == index) {
      nextEditing = null;
      _linkTitleController.clear();
      _linkUriController.clear();
    } else if (nextEditing != null && nextEditing > index) {
      nextEditing -= 1;
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingLinkIndex = nextEditing;
      _linkInputError = null;
    });
  }

  /// Clears inline draft link errors while editing link text fields.
  void _handleLinkInputChanged(String value) {
    if (_linkInputError != null) {
      setState(() => _linkInputError = null);
    }
  }

  /// Removes the draft time window at [index].
  void _handleRemoveTimeWindow(TimeWindowDraft window, int index) {
    if (index < 0 || index >= _conditionDraft.timeWindows.length) {
      return;
    }
    final nextWindows = List<TimeWindowDraft>.of(_conditionDraft.timeWindows)
      ..removeAt(index);
    setState(() {
      _conditionDraft = _conditionDraft.copyWith(timeWindows: nextWindows);
      _generalError = null;
    });
  }

  /// Moves a draft link row from [oldIndex] to [newIndex].
  void _handleReorderLink(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _draftLinks.length ||
        newIndex < 0 ||
        newIndex >= _draftLinks.length ||
        oldIndex == newIndex) {
      return;
    }
    final nextLinks = List<TaskLink>.of(_draftLinks);
    final moved = nextLinks.removeAt(oldIndex);
    nextLinks.insert(newIndex, moved);
    int? nextEditing = _editingLinkIndex;
    if (nextEditing == oldIndex) {
      nextEditing = newIndex;
    } else if (nextEditing == newIndex) {
      nextEditing = oldIndex;
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingLinkIndex = nextEditing;
    });
  }

  /// Opens one optional draft [section] (`note`, `links`, or `conditions`).
  void _handleRevealSection(LabelSectionKind section) {
    setState(() {
      switch (section) {
        case LabelSectionKind.note:
          _showNote = true;
        case LabelSectionKind.links:
          _showLinks = true;
        case LabelSectionKind.conditions:
          _showConditions = true;
        case LabelSectionKind.color:
        case LabelSectionKind.title:
          break;
      }
    });
  }

  /// Updates draft Board Scope selection (`Global Context` vs `Scoped Queue`).
  void _handleScopeChanged(bool nextScoped) {
    setState(() => _isScoped = nextScoped);
  }

  /// Loads draft [link] at [index] into the inline link inputs.
  void _handleStartLinkEdit(TaskLink link, int index) {
    setState(() {
      _editingLinkIndex = index;
      _linkTitleController.text = link.title;
      _linkUriController.text = link.uri;
      _linkInputError = null;
    });
  }

  /// Validates pending sub-inputs and commits the full [LabelDraftInput] via [entityActionsProvider].
  Future<void> _handleSubmit() async {
    if (_isSubmitting || !_flushPendingSubInputs()) {
      return;
    }
    final input = _buildDraftInput();
    setState(() {
      _isSubmitting = true;
      _fieldErrors = const <String, String>{};
      _generalError = null;
    });
    try {
      final result = await ref
          .read(entityActionsProvider.notifier)
          .createLabelDraft(input, locale: Localizations.localeOf(context));
      _applySubmitResult(result);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Toggles [locationId] inside draft GPS location conditions.
  void _handleToggleLocation(String locationId) {
    final nextIds = List<String>.of(_conditionDraft.locationIds);
    if (!nextIds.remove(locationId)) {
      nextIds.add(locationId);
    }
    setState(() {
      _conditionDraft = _conditionDraft.copyWith(locationIds: nextIds);
      _generalError = null;
    });
  }

  /// Toggles ISO weekday [isoWeekday] (`1..7`) inside draft weekday conditions.
  void _handleToggleWeekday(int isoWeekday) {
    final nextDays = List<int>.of(_conditionDraft.weekdays);
    if (!nextDays.remove(isoWeekday)) {
      nextDays.add(isoWeekday);
      nextDays.sort();
    }
    setState(() {
      _conditionDraft = _conditionDraft.copyWith(weekdays: nextDays);
      _generalError = null;
    });
  }
}

/// Always-visible Color inset card inside [LabelDraftCard].
class _LabelDraftColorSection extends StatelessWidget {
  /// Creates a [_LabelDraftColorSection].
  const _LabelDraftColorSection({
    required this.selectedColor,
    required this.enabled,
    required this.onColorChanged,
  });

  /// Whether color controls accept interaction.
  final bool enabled;

  /// Callback emitted when a color is selected.
  final ValueChanged<Color> onColorChanged;

  /// Active draft color.
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.palette_outlined,
      headerTitle: localizations.labelColorSectionTitle,
      child: _LabelColorWheelField(
        value: selectedColor,
        enabled: enabled,
        onChanged: onColorChanged,
      ),
    );
  }
}

/// Immutable bundle of draft Activation Conditions state and callbacks inside [LabelDraftCard].
@immutable
class _LabelDraftConditionsData {
  /// Creates a [_LabelDraftConditionsData].
  const _LabelDraftConditionsData({
    required this.draft,
    required this.timeStartController,
    required this.timeEndController,
    required this.timeInputError,
    required this.onToggleWeekday,
    required this.onAddTimeWindow,
    required this.onRemoveTimeWindow,
    required this.onToggleLocation,
  });

  /// Current editable condition draft.
  final ConditionDraft draft;

  /// Callback adding a typed `HH:MM`..`HH:MM` time window.
  final VoidCallback onAddTimeWindow;

  /// Callback removing a draft time window row.
  final UiOrderedItemActionCallback<TimeWindowDraft> onRemoveTimeWindow;

  /// Callback toggling a draft GPS location condition.
  final ValueChanged<String> onToggleLocation;

  /// Callback toggling a draft weekday condition.
  final ValueChanged<int> onToggleWeekday;

  /// End `HH:MM` controller.
  final TextEditingController timeEndController;

  /// Optional inline time window validation error text.
  final String? timeInputError;

  /// Start `HH:MM` controller.
  final TextEditingController timeStartController;
}

/// Optional Activation Conditions inset card inside the uncommitted Label Draft Card.
class _LabelDraftConditionsSection extends ConsumerWidget {
  /// Creates a [_LabelDraftConditionsSection].
  const _LabelDraftConditionsSection({
    required this.data,
    required this.enabled,
  });

  /// Bundled draft conditions state and callbacks.
  final _LabelDraftConditionsData data;

  /// Whether condition pickers accept input.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final allLocations = ref.watch(
      taskNotifierProvider.select(
        (boardAsync) =>
            boardAsync.asData?.value.sortedLocations ?? const <TdfLocation>[],
      ),
    );

    return UiCard.inset(
      headerIcon: Icons.tune_rounded,
      headerTitle: localizations.taskConditionsSectionTitle,
      child: EntityConditionsEditorBody(
        isTask: false,
        draft: data.draft,
        allLocations: allLocations,
        timeStartController: data.timeStartController,
        timeEndController: data.timeEndController,
        timeInputError: data.timeInputError,
        enabled: enabled,
        onToggleWeekday: data.onToggleWeekday,
        onAddTimeWindow: data.onAddTimeWindow,
        onRemoveTimeWindow: data.onRemoveTimeWindow,
        onToggleLocation: data.onToggleLocation,
      ),
    );
  }
}

/// Right-aligned `Cancel` + `Create label` footer rendered at the bottom of [LabelDraftCard].
class _LabelDraftFooter extends StatelessWidget {
  /// Creates a [_LabelDraftFooter].
  const _LabelDraftFooter({
    required this.isBusy,
    required this.onCancel,
    required this.onSubmit,
  });

  /// Disables actions and spins Create indicator while true.
  final bool isBusy;

  /// Callback cancelling the draft card.
  final VoidCallback onCancel;

  /// Callback committing the draft label.
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: tokens.colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: tokens.spacing.space3),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8.0,
          runSpacing: 8.0,
          children: <Widget>[
            UiButton(
              label: localizations.actionCancel,
              density: UiButtonDensity.compact,
              onPressed: isBusy ? null : onCancel,
            ),
            UiButton(
              label: localizations.actionCreateLabel,
              leadingIcon: isBusy ? Icons.sync_rounded : Icons.add_rounded,
              variant: UiButtonVariant.primary,
              density: UiButtonDensity.compact,
              isLoading: isBusy,
              onPressed: isBusy ? null : () => unawaited(onSubmit()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Immutable bundle of draft Reference Links state and callbacks inside [LabelDraftCard].
@immutable
class _LabelDraftLinksData {
  /// Creates a [_LabelDraftLinksData].
  const _LabelDraftLinksData({
    required this.links,
    required this.editingIndex,
    required this.titleController,
    required this.uriController,
    required this.inputError,
    required this.onReorder,
    required this.onEdit,
    required this.onDelete,
    required this.onInputChanged,
    required this.onCommitLink,
    required this.onCancelRowEdit,
  });

  /// Row index currently being edited, if any.
  final int? editingIndex;

  /// Optional link input validation error text.
  final String? inputError;

  /// Current draft links list.
  final List<TaskLink> links;

  /// Callback cancelling an active link row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback committing the typed link row.
  final VoidCallback onCommitLink;

  /// Callback deleting a draft link row.
  final UiOrderedItemActionCallback<TaskLink> onDelete;

  /// Callback starting inline edit on a draft link row.
  final UiOrderedItemActionCallback<TaskLink> onEdit;

  /// Callback clearing input errors when typing.
  final ValueChanged<String> onInputChanged;

  /// Callback reordering draft link rows.
  final UiOrderedItemReorderCallback onReorder;

  /// Link title text controller.
  final TextEditingController titleController;

  /// Link URI text controller.
  final TextEditingController uriController;
}

/// Optional Reference Links inset card inside the uncommitted Label Draft Card.
class _LabelDraftLinksSection extends StatelessWidget {
  /// Creates a [_LabelDraftLinksSection].
  const _LabelDraftLinksSection({required this.data, required this.enabled});

  /// Bundled draft links state and callbacks.
  final _LabelDraftLinksData data;

  /// Whether controls accept interaction.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.link_rounded,
      headerTitle: localizations.linksSectionTitle,
      headerBadge: UiPill(
        label: '${data.links.length} / $maxTdfLinksPerLabel',
        variant: UiPillVariant.count,
      ),
      child: EntityLinksEditorBody(
        links: data.links,
        editingIndex: data.editingIndex,
        titleController: data.titleController,
        uriController: data.uriController,
        inputErrorText: data.inputError,
        enabled: enabled,
        itemKeyPrefix: 'label_draft_link',
        onReorder: data.onReorder,
        onStartRowEdit: data.onEdit,
        onDeleteRow: data.onDelete,
        onInputChanged: data.onInputChanged,
        onCommitLink: data.onCommitLink,
        onCancelRowEdit: data.onCancelRowEdit,
      ),
    );
  }
}

/// Optional Note inset card inside the uncommitted Label Draft Card.
class _LabelDraftNoteSection extends StatelessWidget {
  /// Creates a [_LabelDraftNoteSection].
  const _LabelDraftNoteSection({
    required this.controller,
    required this.errorText,
    required this.enabled,
    required this.onChanged,
  });

  /// Multiline note controller.
  final TextEditingController controller;

  /// Whether the input accepts typing.
  final bool enabled;

  /// Optional inline validation error message.
  final String? errorText;

  /// Callback notified when note text changes.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.description_outlined,
      headerTitle: localizations.taskNoteLabel,
      child: UiField(
        key: const ValueKey<String>('label_draft_note_field'),
        kind: UiFieldKind.multiline,
        controller: controller,
        hintText: localizations.taskNoteHint,
        maxLength: maxTdfNoteLength,
        enabled: enabled,
        errorText: errorText,
        onChanged: onChanged,
      ),
    );
  }
}

/// Optional Note, Links, and Activation Conditions cards revealed inside [LabelDraftCard].
class _LabelDraftOptionalSections extends StatelessWidget {
  /// Creates a [_LabelDraftOptionalSections].
  const _LabelDraftOptionalSections({
    required this.showNote,
    required this.noteController,
    required this.noteError,
    required this.onNoteChanged,
    required this.showLinks,
    required this.linksData,
    required this.showConditions,
    required this.conditionsData,
    required this.isBusy,
  });

  /// Bundled draft conditions state and callbacks.
  final _LabelDraftConditionsData conditionsData;

  /// Disables inputs while submitting.
  final bool isBusy;

  /// Bundled draft links state and callbacks.
  final _LabelDraftLinksData linksData;

  /// Draft note controller.
  final TextEditingController noteController;

  /// Optional inline validation error for draft note.
  final String? noteError;

  /// Callback clearing note errors on text change.
  final ValueChanged<String> onNoteChanged;

  /// Whether draft Activation Conditions section is open.
  final bool showConditions;

  /// Whether draft Reference Links section is open.
  final bool showLinks;

  /// Whether draft Note section is open.
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    if (!showNote && !showLinks && !showConditions) {
      return const SizedBox.shrink();
    }
    final gap = SizedBox(height: UiThemeTokens.of(context).spacing.space2);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showNote) ...<Widget>[
          gap,
          _LabelDraftNoteSection(
            controller: noteController,
            errorText: noteError,
            enabled: !isBusy,
            onChanged: onNoteChanged,
          ),
        ],
        if (showLinks) ...<Widget>[
          gap,
          _LabelDraftLinksSection(data: linksData, enabled: !isBusy),
        ],
        if (showConditions) ...<Widget>[
          gap,
          _LabelDraftConditionsSection(data: conditionsData, enabled: !isBusy),
        ],
      ],
    );
  }
}

/// Immutable bundle of Name, Color, and Board Scope form state inside [LabelDraftCard].
@immutable
class _LabelDraftPrimaryData {
  /// Creates a [_LabelDraftPrimaryData].
  const _LabelDraftPrimaryData({
    required this.nameController,
    required this.nameError,
    required this.selectedColor,
    required this.isScoped,
    required this.onNameChanged,
    required this.onSubmitFromField,
    required this.onColorChanged,
    required this.onScopeChanged,
  });

  /// Draft Board Scope selection.
  final bool isScoped;

  /// Draft label name controller.
  final TextEditingController nameController;

  /// Optional inline validation error for label name.
  final String? nameError;

  /// Callback updating the draft color.
  final ValueChanged<Color> onColorChanged;

  /// Callback clearing name errors when typing.
  final ValueChanged<String> onNameChanged;

  /// Callback toggling draft Board Scope.
  final ValueChanged<bool> onScopeChanged;

  /// Callback submitting on Enter in the Name field.
  final Future<void> Function() onSubmitFromField;

  /// Currently selected draft color.
  final Color selectedColor;
}

/// Always-visible Name, Color, and Board Scope inputs inside [LabelDraftCard].
class _LabelDraftPrimaryFields extends StatelessWidget {
  /// Creates a [_LabelDraftPrimaryFields].
  const _LabelDraftPrimaryFields({required this.data, required this.isBusy});

  /// Bundled primary draft field controllers, values, and callbacks.
  final _LabelDraftPrimaryData data;

  /// Disables controls while submitting.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiField(
          key: const ValueKey<String>('label_draft_name_field'),
          controller: data.nameController,
          label: localizations.labelNameLabel,
          hintText: localizations.labelNameHint,
          maxLength: maxTdfTextLength,
          autofocus: true,
          enabled: !isBusy,
          errorText: data.nameError,
          onChanged: data.onNameChanged,
          onSubmitted: (_) => unawaited(data.onSubmitFromField()),
        ),
        SizedBox(height: tokens.spacing.space3),
        _LabelDraftColorSection(
          selectedColor: data.selectedColor,
          enabled: !isBusy,
          onColorChanged: data.onColorChanged,
        ),
        SizedBox(height: tokens.spacing.space2),
        _LabelScopeSection(
          labelId: 'draft',
          isScoped: data.isScoped,
          enabled: !isBusy,
          onChanged: data.onScopeChanged,
        ),
      ],
    );
  }
}

/// Trailing inline name edit pencil rendered only while a Label card is expanded.
class _LabelEditNameButton extends ConsumerWidget {
  /// Creates a [_LabelEditNameButton].
  const _LabelEditNameButton({required this.labelId, required this.isBusy});

  /// Disables the button while busy.
  final bool isBusy;

  /// Canonical label identifier for deterministic test keys.
  final String labelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      key: ValueKey<String>('label_edit_name_$labelId'),
      leadingIcon: Icons.edit_outlined,
      variant: UiButtonVariant.icon,
      density: UiButtonDensity.compact,
      tooltip: localizations.inlineEditNameTooltip,
      onPressed: isBusy
          ? null
          : () => ref
                .read(shellProvider.notifier)
                .openInlineEdit(
                  InlineEditTarget.label(labelId, LabelSectionKind.title),
                ),
    );
  }
}

/// Stateless presentation shell configuring [UiCard.expandable] for one label card.
class _LabelExpandableCardView extends ConsumerWidget {
  /// Creates a [_LabelExpandableCardView].
  const _LabelExpandableCardView({
    required this.label,
    required this.openCount,
    required this.isExpanded,
    required this.editingSection,
    required this.isConfirmingDelete,
    required this.isBusy,
  });

  /// Currently open inline section editor on this card, if any.
  final LabelSectionKind? editingSection;

  /// Disables actions while a mutation is in flight.
  final bool isBusy;

  /// Whether inline delete confirmation is open.
  final bool isConfirmingDelete;

  /// Whether this card is currently expanded.
  final bool isExpanded;

  /// Persisted domain label.
  final TdfLabel label;

  /// Count of open tasks referencing [label].
  final int openCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEditingName =
        isExpanded && editingSection == LabelSectionKind.title;
    void toggleExpand() => _toggleExpand(ref);

    return UiCard.expandable(
      key: ValueKey<String>('label_card_${label.id}'),
      title: label.name,
      isExpanded: isExpanded,
      onToggleExpand: toggleExpand,
      leading: _LabelLeadingColorDot(
        colorValue: TaskScheduleHelper.parseLabelColorValue(label.color),
        onTap: toggleExpand,
      ),
      isEditingTitle: isEditingName,
      titleEditor: isEditingName
          ? _LabelInlineNameEditor(label: label, isBusy: isBusy)
          : null,
      trailingActions: <Widget>[
        if (isExpanded && !isEditingName) ...<Widget>[
          _LabelEditNameButton(labelId: label.id, isBusy: isBusy),
          _LabelDeleteButton(
            labelId: label.id,
            isConfirmingDelete: isConfirmingDelete,
            isBusy: isBusy,
          ),
        ],
      ],
      collapsedMetadata: _LabelCollapsedMetadataStrip(
        label: label,
        openCount: openCount,
        onToggleExpand: toggleExpand,
      ),
      expandedChild: isExpanded
          ? _LabelExpandedPanel(
              label: label,
              openCount: openCount,
              editingSection: editingSection,
              isConfirmingDelete: isConfirmingDelete,
              isBusy: isBusy,
            )
          : null,
    );
  }

  /// Toggles single-expand state for [label] in [shellProvider].
  void _toggleExpand(WidgetRef ref) {
    ref
        .read(shellProvider.notifier)
        .toggleExpandEntity(EntityRef(kind: EntityKind.label, id: label.id));
  }
}

/// Expanded Label card body rendering meta bar, canonical sections (Note, Links, Color, Board Scope, Conditions), and `+ Add` chips (`U-CARD-002`).
class _LabelExpandedPanel extends ConsumerWidget {
  /// Creates a [_LabelExpandedPanel].
  const _LabelExpandedPanel({
    required this.label,
    required this.openCount,
    required this.editingSection,
    required this.isConfirmingDelete,
    required this.isBusy,
  });

  /// Currently open inline section editor on this label card, if any.
  final LabelSectionKind? editingSection;

  /// Disables interactive triggers while an asynchronous mutation is in flight.
  final bool isBusy;

  /// Whether the inline delete confirmation banner is active in [EntityCardMetaBar].
  final bool isConfirmingDelete;

  /// Persisted domain label.
  final TdfLabel label;

  /// Count of open tasks referencing [label].
  final int openCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final shellNotifier = ref.read(shellProvider.notifier);
    final visibleUnset = <LabelSectionKind>[
      for (final section in _computeUnsetLabelSections(label))
        if (section != editingSection) section,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LabelCardMetaBar(
          label: label,
          openCount: openCount,
          isConfirmingDelete: isConfirmingDelete,
        ),
        _LabelExpandedSectionsStack(
          label: label,
          editingSection: editingSection,
          isBusy: isBusy,
        ),
        if (visibleUnset.isNotEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.space2),
          _LabelUnsetChipsBar(
            sections: visibleUnset,
            enabled: !isBusy,
            onSelectSection: (section) => shellNotifier.openInlineEdit(
              InlineEditTarget.label(label.id, section),
            ),
          ),
        ],
      ],
    );
  }
}

/// Canonical vertical stack of populated-only and always-visible Label sections (`Note -> Links -> Color -> Board Scope -> Conditions`).
class _LabelExpandedSectionsStack extends StatelessWidget {
  /// Creates a [_LabelExpandedSectionsStack].
  const _LabelExpandedSectionsStack({
    required this.label,
    required this.editingSection,
    required this.isBusy,
  });

  /// Active inline section editor, if any.
  final LabelSectionKind? editingSection;

  /// Disables actions while busy.
  final bool isBusy;

  /// Persisted domain label.
  final TdfLabel label;

  @override
  Widget build(BuildContext context) {
    final topGap = SizedBox(height: UiThemeTokens.of(context).spacing.space2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LabelNoteSectionCard(
          label: label,
          isEditing: editingSection == LabelSectionKind.note,
          isBusy: isBusy,
        ),
        _LabelLinksSectionCard(
          label: label,
          isEditing: editingSection == LabelSectionKind.links,
          isBusy: isBusy,
        ),
        topGap,
        _LabelColorSectionCard(
          label: label,
          isEditing: editingSection == LabelSectionKind.color,
          isBusy: isBusy,
        ),
        topGap,
        _LabelScopeSectionCard(label: label, isBusy: isBusy),
        _LabelConditionsSectionCard(
          label: label,
          isEditing: editingSection == LabelSectionKind.conditions,
          isBusy: isBusy,
        ),
      ],
    );
  }
}

/// Inline label name editor swapped into the expanded card header (`U-CARD-001`).
class _LabelInlineNameEditor extends ConsumerWidget {
  /// Creates a [_LabelInlineNameEditor].
  const _LabelInlineNameEditor({required this.label, required this.isBusy});

  /// Disables actions while a parent mutation is in flight.
  final bool isBusy;

  /// Persisted domain label seeding the text input and target identifier.
  final TdfLabel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    return EntityInlineNameEditor(
      initialValue: label.name,
      hintText: localizations.labelNameHint,
      inputKey: ValueKey<String>('label_name_input_${label.id}'),
      isBusy: isBusy,
      onCancel: ref.read(shellProvider.notifier).closeInlineEdit,
      onSave: (value) => ref
          .read(entityActionsProvider.notifier)
          .saveLabelName(label.id, value, locale: locale),
    );
  }
}

/// Optical `12px` rounded-square color dot centered inside the `34x34px` leading header slot (`U-CARD-001`).
class _LabelLeadingColorDot extends StatelessWidget {
  /// Creates a [_LabelLeadingColorDot].
  const _LabelLeadingColorDot({required this.colorValue, required this.onTap});

  /// Parsed ARGB color value, falling back to `tokens.colors.accent` when unset.
  final int? colorValue;

  /// Toggles parent card expansion when tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final dotColor = switch (colorValue) {
      final int value => Color(value),
      null => tokens.colors.accent,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: tokens.spacing.chromeControlHeight,
        height: tokens.spacing.chromeControlHeight,
        child: Center(
          child: ExcludeSemantics(
            child: Container(
              width: _labelColorDotSize,
              height: _labelColorDotSize,
              decoration: BoxDecoration(
                color: dotColor,
                borderRadius: BorderRadius.circular(tokens.radii.dotLg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Collapsed link-count metadata pill rendered inside [_LabelCollapsedMetadataBadges].
class _LabelLinksBadge extends StatelessWidget {
  /// Creates a [_LabelLinksBadge].
  const _LabelLinksBadge({required this.linkCount});

  /// Total attached links on the label.
  final int linkCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final labelText = linkCount == 1
        ? localizations.badgeLinkSingular
        : localizations.taskInfoLinksCount('$linkCount');
    return UiPill(
      label: labelText,
      variant: UiPillVariant.meta,
      icon: Icons.link_rounded,
    );
  }
}

/// Wires [EntityLinksSection] (`isLabel: true`) to [entityActionsProvider] for one label card.
class _LabelLinksSectionCard extends ConsumerWidget {
  /// Creates a [_LabelLinksSectionCard].
  const _LabelLinksSectionCard({
    required this.label,
    required this.isEditing,
    required this.isBusy,
  });

  /// Disables controls while a mutation is in flight.
  final bool isBusy;

  /// Whether inline Links editing is active.
  final bool isEditing;

  /// Persisted domain label.
  final TdfLabel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (label.links.isEmpty && !isEditing) {
      return const SizedBox.shrink();
    }
    final locale = Localizations.localeOf(context);
    final tokens = UiThemeTokens.of(context);
    final shellNotifier = ref.read(shellProvider.notifier);
    final entityNotifier = ref.read(entityActionsProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.space2),
      child: EntityLinksSection(
        links: label.links,
        isEditing: isEditing,
        canEdit: true,
        isLabel: true,
        isBusy: isBusy,
        onStartEdit: () => shellNotifier.openInlineEdit(
          InlineEditTarget.label(label.id, LabelSectionKind.links),
        ),
        onCancelEdit: shellNotifier.closeInlineEdit,
        onSave: (links) =>
            entityNotifier.saveLabelLinks(label.id, links, locale: locale),
      ),
    );
  }
}

/// Wires [EntityNoteSection] to [entityActionsProvider] and [UiTelemetry] for one label card.
class _LabelNoteSectionCard extends ConsumerWidget {
  /// Creates a [_LabelNoteSectionCard].
  const _LabelNoteSectionCard({
    required this.label,
    required this.isEditing,
    required this.isBusy,
  });

  /// Disables controls while a mutation is in flight.
  final bool isBusy;

  /// Whether inline Note editing is active.
  final bool isEditing;

  /// Persisted domain label.
  final TdfLabel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_hasNonEmptyNote(label.note) && !isEditing) {
      return const SizedBox.shrink();
    }
    final locale = Localizations.localeOf(context);
    final tokens = UiThemeTokens.of(context);
    final shellNotifier = ref.read(shellProvider.notifier);
    final entityNotifier = ref.read(entityActionsProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.space2),
      child: EntityNoteSection(
        note: label.note,
        isEditing: isEditing,
        canEdit: true,
        isBusy: isBusy,
        onStartEdit: () => shellNotifier.openInlineEdit(
          InlineEditTarget.label(label.id, LabelSectionKind.note),
        ),
        onCancelEdit: shellNotifier.closeInlineEdit,
        onSave: (rawNote) =>
            entityNotifier.saveLabelNote(label.id, rawNote, locale: locale),
        onClear: () => _clearLabelNote(context, ref, label.id),
        onNoteCopied: () => UiTelemetry.logLabelNoteCopied(
          labelId: label.id,
          length: label.note?.length ?? 0,
        ),
      ),
    );
  }
}

/// Collapsed board-scope metadata pill rendered inside [_LabelCollapsedMetadataBadges].
class _LabelScopeBadge extends StatelessWidget {
  /// Creates a [_LabelScopeBadge].
  const _LabelScopeBadge({required this.isScoped});

  /// Whether the label uses a dedicated scoped queue.
  final bool isScoped;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiPill(
      label: isScoped
          ? localizations.scopedQueueLabel
          : localizations.globalContextLabel,
      variant: UiPillVariant.meta,
      tone: isScoped ? UiPillTone.soft : UiPillTone.neutral,
      icon: Icons.layers_outlined,
    );
  }
}

/// Always-visible Board Scope inset card with a live 2-way [UiSegmentedControl] (`U-CARD-003`).
class _LabelScopeSection extends StatelessWidget {
  /// Creates a [_LabelScopeSection].
  const _LabelScopeSection({
    required this.labelId,
    required this.isScoped,
    required this.enabled,
    required this.onChanged,
  });

  /// Whether the segmented control accepts input.
  final bool enabled;

  /// Whether `Scoped Queue` is currently active.
  final bool isScoped;

  /// Label identifier (or `'draft'`) for deterministic keys.
  final String labelId;

  /// Callback invoked when the scope segment changes.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);

    return UiCard.inset(
      headerIcon: Icons.layers_outlined,
      headerTitle: localizations.labelScopedSectionTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          UiSegmentedControl<bool>(
            key: ValueKey<String>('label_scope_switch_$labelId'),
            semanticLabel: localizations.labelScopedSectionTitle,
            value: isScoped,
            enabled: enabled,
            onChanged: onChanged,
            segments: <UiSegment<bool>>[
              UiSegment<bool>(
                value: false,
                label: localizations.globalContextLabel,
              ),
              UiSegment<bool>(
                value: true,
                label: localizations.scopedQueueLabel,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.space2),
          Text(
            localizations.labelScopedSwitchSubtitle,
            style: tokens.typography.meta.copyWith(color: tokens.colors.muted),
          ),
        ],
      ),
    );
  }
}

/// Wires always-visible live [_LabelScopeSection] to [EntityActionsNotifier.setLabelScoped].
class _LabelScopeSectionCard extends ConsumerWidget {
  /// Creates a [_LabelScopeSectionCard].
  const _LabelScopeSectionCard({required this.label, required this.isBusy});

  /// Disables the segmented toggle while a mutation is in flight.
  final bool isBusy;

  /// Persisted domain label.
  final TdfLabel label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _LabelScopeSection(
      labelId: label.id,
      isScoped: label.isScoped,
      enabled: !isBusy,
      onChanged: (nextScoped) {
        if (nextScoped != label.isScoped) {
          unawaited(_updateLabelScope(context, ref, label.id, nextScoped));
        }
      },
    );
  }
}

/// Bottom dashed `+ Add` chips bar for unset optional Label sections (`+ Note`, `+ Links`, `+ Conditions`).
class _LabelUnsetChipsBar extends StatelessWidget {
  /// Creates a [_LabelUnsetChipsBar].
  const _LabelUnsetChipsBar({
    required this.sections,
    required this.enabled,
    required this.onSelectSection,
  });

  /// Whether chips accept clicks.
  final bool enabled;

  /// Callback opening inline edit mode for the selected section.
  final ValueChanged<LabelSectionKind> onSelectSection;

  /// Ordered unset optional sections to expose as dashed chips.
  final List<LabelSectionKind> sections;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: <Widget>[
        for (final section in sections)
          _LabelUnsetSectionChip(
            section: section,
            enabled: enabled,
            onPressed: () => onSelectSection(section),
          ),
      ],
    );
  }
}

/// Single dashed `+ Add` chip opening inline editing for an unset [LabelSectionKind].
class _LabelUnsetSectionChip extends StatelessWidget {
  /// Creates a [_LabelUnsetSectionChip].
  const _LabelUnsetSectionChip({
    required this.section,
    required this.enabled,
    required this.onPressed,
  });

  /// Whether the chip accepts interaction.
  final bool enabled;

  /// Callback opening inline editing for [section].
  final VoidCallback onPressed;

  /// Unset label section represented by this chip.
  final LabelSectionKind section;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final metadata = _labelSectionChipMetadata(section, localizations);
    return UiPill(
      label: metadata.label,
      icon: metadata.icon,
      variant: UiPillVariant.addField,
      enabled: enabled,
      onPressed: enabled ? onPressed : null,
    );
  }
}

/// Lazily builds read-only [ConditionSummaryChip] items for [label] against [allLocations].
List<ConditionSummaryChip> _buildLabelConditionsSummary(
  TdfLabel label,
  List<TdfLocation> allLocations,
  AppLocalizations localizations,
) {
  final locationsById = <String, TdfLocation>{
    for (final location in allLocations) location.id: location,
  };
  return TaskScheduleHelper.buildConditionSummaryChips(
    ownRules: label.conditions,
    inheritedRules: const <TaskCondition>[],
    locationsById: locationsById,
    localizations: localizations,
  );
}

/// Clears all activation conditions on [labelId] and surfaces any failure via a danger floating notice.
Future<void> _clearLabelConditions(
  BuildContext context,
  WidgetRef ref,
  String labelId,
) async {
  final result = await ref
      .read(entityActionsProvider.notifier)
      .clearLabelConditions(labelId, locale: Localizations.localeOf(context));
  if (!context.mounted) {
    return;
  }
  _reportActionFailure(ref, result);
}

/// Clears the optional note on [labelId] and surfaces any failure via a danger floating notice.
Future<void> _clearLabelNote(
  BuildContext context,
  WidgetRef ref,
  String labelId,
) async {
  final result = await ref
      .read(entityActionsProvider.notifier)
      .clearLabelNote(labelId, locale: Localizations.localeOf(context));
  if (!context.mounted) {
    return;
  }
  _reportActionFailure(ref, result);
}

/// Computes the ordered optional [LabelSectionKind] sections not yet populated on [label].
List<LabelSectionKind> _computeUnsetLabelSections(TdfLabel label) {
  return <LabelSectionKind>[
    if (!_hasNonEmptyNote(label.note)) LabelSectionKind.note,
    if (label.links.isEmpty) LabelSectionKind.links,
    if (label.conditions.isEmpty) LabelSectionKind.conditions,
  ];
}

/// Confirms deletion of [labelId] and surfaces any persistence failure via a danger floating notice.
Future<void> _confirmDeleteLabel(
  BuildContext context,
  WidgetRef ref,
  String labelId,
) async {
  final result = await ref
      .read(entityActionsProvider.notifier)
      .deleteLabel(labelId, locale: Localizations.localeOf(context));
  if (!context.mounted) {
    return;
  }
  _reportActionFailure(ref, result);
}

/// Copies canonical [labelId] to the system clipboard and emits [copiedNotice].
Future<void> _copyLabelId(
  BuildContext context,
  WidgetRef ref, {
  required String labelId,
  required String copiedNotice,
}) async {
  await Clipboard.setData(ClipboardData(text: labelId));
  if (!context.mounted) {
    return;
  }
  ref.read(floatingNoticeProvider.notifier).showNotice(copiedNotice);
}

/// Returns `true` when [note] contains at least one non-whitespace character.
bool _hasNonEmptyNote(String? note) => note != null && note.trim().isNotEmpty;

/// Resolves localized label and outline icon for an unset [LabelSectionKind] add chip.
({String label, IconData icon}) _labelSectionChipMetadata(
  LabelSectionKind section,
  AppLocalizations localizations,
) {
  return switch (section) {
    LabelSectionKind.note => (
      label: localizations.inlineAddNote,
      icon: Icons.description_outlined,
    ),
    LabelSectionKind.links => (
      label: localizations.inlineAddLinks,
      icon: Icons.link_rounded,
    ),
    LabelSectionKind.conditions => (
      label: localizations.inlineAddConditions,
      icon: Icons.tune_rounded,
    ),
    LabelSectionKind.color => (
      label: localizations.labelColorSectionTitle,
      icon: Icons.palette_outlined,
    ),
    LabelSectionKind.title => (
      label: localizations.inlineEditNameTooltip,
      icon: Icons.edit_outlined,
    ),
  };
}

/// Resolves the active [LabelSectionKind] targeted by [target] when it belongs to [labelId].
LabelSectionKind? _parseInlineEditSection(
  InlineEditTarget? target,
  String labelId,
) {
  if (target == null ||
      target.entity.kind != EntityKind.label ||
      target.entity.id != labelId) {
    return null;
  }
  for (final section in LabelSectionKind.values) {
    if (section.name == target.sectionKey) {
      return section;
    }
  }
  return null;
}

/// Emits a `danger` floating notice when a non-inline mutation returns a failure [result].
void _reportActionFailure(WidgetRef ref, ActionResult result) {
  switch (result) {
    case ActionSucceeded():
      return;
    case ActionValidationFailed(:final message):
      ref
          .read(floatingNoticeProvider.notifier)
          .showNotice(message, tone: FloatingNoticeTone.danger);
    case ActionPersistFailed(:final message):
      ref
          .read(floatingNoticeProvider.notifier)
          .showNotice(message, tone: FloatingNoticeTone.danger);
  }
}

/// Resolves any draft validation error lacking a visible inline field target for the card banner.
String? _resolveDraftBannerError(
  String fallbackMessage,
  Map<String, String> fieldErrors, {
  required bool showNote,
}) {
  if (fieldErrors.isEmpty) {
    return fallbackMessage;
  }
  for (final entry in fieldErrors.entries) {
    final hasFieldTarget =
        entry.key == 'name' || (showNote && entry.key == 'note');
    if (!hasFieldTarget) {
      return entry.value;
    }
  }
  return null;
}

/// Persists an immediate live Board Scope change on [labelId] and surfaces any failure notice.
Future<void> _updateLabelScope(
  BuildContext context,
  WidgetRef ref,
  String labelId,
  bool isScoped,
) async {
  final result = await ref
      .read(entityActionsProvider.notifier)
      .setLabelScoped(
        labelId,
        isScoped,
        locale: Localizations.localeOf(context),
      );
  if (!context.mounted) {
    return;
  }
  _reportActionFailure(ref, result);
}
