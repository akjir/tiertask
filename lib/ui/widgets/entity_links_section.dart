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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/floating_notice_controller.dart';
import '../../presentation/link_action_controller.dart';
import '../../presentation/shell_models.dart';
import '../../presentation/task_controller.dart';
import '../../presentation/view_model_primitives.dart';
import 'entity_card_chrome.dart';

/// Maximum reference links allowed per task or label (`TDF 0.8.0`).
const int _maxLinksPerEntity = 20;

/// Maximum single-line text length allowed by `TDF 0.8.0` (`maxTdfTextLength`).
const int _maxSingleLineLength = 500;

/// Shared read-only and inline-editable Reference Links section for Tasks and Labels (`U-COMP-006`).
class EntityLinksSection extends ConsumerStatefulWidget {
  /// Creates an [EntityLinksSection].
  const EntityLinksSection({
    super.key,
    required this.links,
    required this.isEditing,
    required this.canEdit,
    required this.isLabel,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSave,
    this.isBusy = false,
  });

  /// Whether this section can enter inline edit mode.
  final bool canEdit;

  /// Whether an asynchronous parent mutation is currently in progress.
  final bool isBusy;

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Distinguishes label link limits from task link limits during validation.
  final bool isLabel;

  /// Persisted reference links attached to the entity.
  final List<EntityLinkViewModel> links;

  /// Callback closing inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback validating and persisting the edited links list.
  final Future<ActionResult> Function(List<EntityLinkViewModel> links) onSave;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  @override
  ConsumerState<EntityLinksSection> createState() => _EntityLinksSectionState();
}

/// Wraps [child] with the canonical `1px` offset `accent` keyboard focus ring (`U-A11Y-001`).
class _EntityFocusRingBox extends StatelessWidget {
  /// Creates an [_EntityFocusRingBox].
  const _EntityFocusRingBox({
    required this.visible,
    required this.radius,
    required this.child,
  });

  /// Focusable surface widget.
  final Widget child;

  /// Base corner radius of [child].
  final double radius;

  /// Whether the outer `1px` `accent` keyboard focus ring is currently painted.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final ringInset = tokens.focus.ringOffset + tokens.focus.ringWidth;

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        if (visible)
          Positioned.fill(
            left: -ringInset,
            top: -ringInset,
            right: -ringInset,
            bottom: -ringInset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius + ringInset),
                  border: Border.all(
                    color: tokens.colors.accent,
                    width: tokens.focus.ringWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Renders the Add/Update link button and optional row-edit Cancel button.
class _EntityLinkFormActions extends StatelessWidget {
  /// Creates an [_EntityLinkFormActions].
  const _EntityLinkFormActions({
    required this.isEditingExisting,
    required this.enabled,
    required this.onSubmitLink,
    required this.onCancelRowEdit,
  });

  /// Whether buttons accept interaction.
  final bool enabled;

  /// Switches label from `Add link` to `Update link` and exposes `Cancel`.
  final bool isEditingExisting;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback adding or updating the link row.
  final VoidCallback onSubmitLink;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        UiButton(
          label: isEditingExisting
              ? localizations.tooltipSaveLink
              : localizations.tooltipAddLink,
          leadingIcon: isEditingExisting ? null : Icons.add_rounded,
          variant: UiButtonVariant.secondary,
          density: UiButtonDensity.compact,
          onPressed: enabled ? onSubmitLink : null,
        ),
        if (isEditingExisting)
          UiButton(
            label: localizations.actionCancel,
            variant: UiButtonVariant.text,
            density: UiButtonDensity.compact,
            tooltip: localizations.tooltipCancelEditLink,
            onPressed: enabled ? onCancelRowEdit : null,
          ),
      ],
    );
  }
}

/// Renders inline title + URI fields, validation error, and Add/Update link buttons.
class _EntityLinkFormBar extends StatelessWidget {
  /// Creates an [_EntityLinkFormBar].
  const _EntityLinkFormBar({
    required this.titleController,
    required this.uriController,
    required this.isEditingExisting,
    required this.errorText,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitLink,
    required this.onCancelRowEdit,
  });

  /// Whether inputs and submit button are enabled.
  final bool enabled;

  /// Optional inline link validation error text.
  final String? errorText;

  /// Swaps `Add link` to `Update link` + `Cancel` when true.
  final bool isEditingExisting;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback notified when either input changes.
  final ValueChanged<String> onChanged;

  /// Callback validating and committing the typed link row.
  final VoidCallback onSubmitLink;

  /// Link title controller.
  final TextEditingController titleController;

  /// Link URI controller.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final error = errorText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _EntityLinkFormInputsGrid(
          titleController: titleController,
          uriController: uriController,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitLink: onSubmitLink,
        ),
        if (error != null && error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6.0),
          EntityInlineErrorText(message: error),
        ],
        SizedBox(height: tokens.spacing.space2),
        _EntityLinkFormActions(
          isEditingExisting: isEditingExisting,
          enabled: enabled,
          onSubmitLink: onSubmitLink,
          onCancelRowEdit: onCancelRowEdit,
        ),
      ],
    );
  }
}

/// Renders the responsive two-column title and URI inputs inside [_EntityLinkFormBar].
class _EntityLinkFormInputsGrid extends StatelessWidget {
  /// Creates an [_EntityLinkFormInputsGrid].
  const _EntityLinkFormInputsGrid({
    required this.titleController,
    required this.uriController,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitLink,
  });

  /// Whether inputs accept interaction.
  final bool enabled;

  /// Callback notified when either input changes.
  final ValueChanged<String> onChanged;

  /// Callback validating and committing the typed link row.
  final VoidCallback onSubmitLink;

  /// Link title controller.
  final TextEditingController titleController;

  /// Link URI controller.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    return UiResponsiveGrid(
      preset: UiGridPreset.twoColumnCompactCollapse,
      spacing: tokens.spacing.space2,
      runSpacing: tokens.spacing.space2,
      children: <Widget>[
        UiField(
          kind: UiFieldKind.text,
          controller: titleController,
          hintText: localizations.linkTitleHint,
          maxLength: _maxSingleLineLength,
          autofocus: true,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitLink(),
        ),
        UiField(
          kind: UiFieldKind.text,
          controller: uriController,
          hintText: localizations.linkUriHint,
          isMonospace: true,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitLink(),
        ),
      ],
    );
  }
}

/// Renders one link title and monospace URI stack inside read-only cards and [UiOrderedItemList].
class _EntityLinkListItem extends StatelessWidget {
  /// Creates an [_EntityLinkListItem].
  const _EntityLinkListItem({required this.link});

  /// Reference link displayed in this row.
  final EntityLinkViewModel link;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          link.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.control.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          link.uri,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}

/// Renders the inline editing inset card for [EntityLinksSection].
class _EntityLinksEditCard extends StatelessWidget {
  /// Creates an [_EntityLinksEditCard].
  const _EntityLinksEditCard({
    required this.draftLinks,
    required this.hasPersistedLinks,
    required this.editingIndex,
    required this.titleController,
    required this.uriController,
    required this.inputErrorText,
    required this.saveErrorText,
    required this.isBusy,
    required this.onReorder,
    required this.onStartRowEdit,
    required this.onDeleteRow,
    required this.onInputChanged,
    required this.onCommitLinkInput,
    required this.onCancelRowEdit,
    required this.onClearAll,
    required this.onCancel,
    required this.onSave,
  });

  /// Editable draft links list.
  final List<EntityLinkViewModel> draftLinks;

  /// Row index currently being updated inline, or `null` when adding.
  final int? editingIndex;

  /// Controls whether the footer Clear button is shown.
  final bool hasPersistedLinks;

  /// Optional validation error for the inline link form inputs.
  final String? inputErrorText;

  /// Disables controls while submitting.
  final bool isBusy;

  /// Callback cancelling the whole links section edit.
  final VoidCallback onCancel;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback clearing all persisted links.
  final VoidCallback onClearAll;

  /// Callback adding or updating the typed link row.
  final VoidCallback onCommitLinkInput;

  /// Callback removing a link row.
  final UiOrderedItemActionCallback<EntityLinkViewModel> onDeleteRow;

  /// Callback clearing input validation error when text changes.
  final ValueChanged<String> onInputChanged;

  /// Callback moving a link row up or down.
  final UiOrderedItemReorderCallback onReorder;

  /// Callback saving the entire links list.
  final VoidCallback onSave;

  /// Callback starting inline edit on a link row.
  final UiOrderedItemActionCallback<EntityLinkViewModel> onStartRowEdit;

  /// Optional persistence or validation error returned by `onSave`.
  final String? saveErrorText;

  /// Title text controller.
  final TextEditingController titleController;

  /// URI text controller.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      isEditing: true,
      headerIcon: Icons.link_rounded,
      headerTitle: localizations.linksSectionTitle,
      headerBadge: UiPill(
        label: '${draftLinks.length} / $_maxLinksPerEntity',
        variant: UiPillVariant.count,
      ),
      footer: EntityInlineEditorFooter(
        errorText: saveErrorText,
        clearLabel: hasPersistedLinks ? localizations.inlineClearAction : null,
        onClear: hasPersistedLinks ? onClearAll : null,
        onCancel: onCancel,
        onSave: onSave,
        isBusy: isBusy,
      ),
      child: _EntityLinksOrderedList(
        draftLinks: draftLinks,
        editingIndex: editingIndex,
        titleController: titleController,
        uriController: uriController,
        inputErrorText: inputErrorText,
        isBusy: isBusy,
        onReorder: onReorder,
        onStartRowEdit: onStartRowEdit,
        onDeleteRow: onDeleteRow,
        onInputChanged: onInputChanged,
        onCommitLinkInput: onCommitLinkInput,
        onCancelRowEdit: onCancelRowEdit,
      ),
    );
  }
}

/// Renders the reorderable draft link items and inline add/edit bar inside [_EntityLinksEditCard].
class _EntityLinksOrderedList extends StatelessWidget {
  /// Creates an [_EntityLinksOrderedList].
  const _EntityLinksOrderedList({
    required this.draftLinks,
    required this.editingIndex,
    required this.titleController,
    required this.uriController,
    required this.inputErrorText,
    required this.isBusy,
    required this.onReorder,
    required this.onStartRowEdit,
    required this.onDeleteRow,
    required this.onInputChanged,
    required this.onCommitLinkInput,
    required this.onCancelRowEdit,
  });

  /// Editable draft links list.
  final List<EntityLinkViewModel> draftLinks;

  /// Row index currently being updated inline, or `null` when adding.
  final int? editingIndex;

  /// Optional validation error for the inline link form inputs.
  final String? inputErrorText;

  /// Disables row actions and inputs while submitting.
  final bool isBusy;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback adding or updating the typed link row.
  final VoidCallback onCommitLinkInput;

  /// Callback removing a link row.
  final UiOrderedItemActionCallback<EntityLinkViewModel> onDeleteRow;

  /// Callback clearing input validation error when text changes.
  final ValueChanged<String> onInputChanged;

  /// Callback moving a link row up or down.
  final UiOrderedItemReorderCallback onReorder;

  /// Callback starting inline edit on a link row.
  final UiOrderedItemActionCallback<EntityLinkViewModel> onStartRowEdit;

  /// Title text controller.
  final TextEditingController titleController;

  /// URI text controller.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiOrderedItemList<EntityLinkViewModel>(
      items: draftLinks,
      itemKey: (link, index) =>
          ValueKey<String>('entity_link_${index}_${link.uri}'),
      editingIndex: editingIndex,
      onReorder: isBusy ? null : onReorder,
      moveUpTooltip: localizations.tooltipMoveLinkUp,
      moveDownTooltip: localizations.tooltipMoveLinkDown,
      onEdit: isBusy ? null : onStartRowEdit,
      editTooltip: localizations.tooltipEditLink,
      onDelete: isBusy ? null : onDeleteRow,
      deleteTooltip: localizations.tooltipRemoveLink,
      itemBuilder: (context, link, index, isEditingRow) =>
          _EntityLinkListItem(link: link),
      addBar: _EntityLinkFormBar(
        titleController: titleController,
        uriController: uriController,
        isEditingExisting: editingIndex != null,
        errorText: inputErrorText,
        enabled: !isBusy,
        onChanged: onInputChanged,
        onSubmitLink: onCommitLinkInput,
        onCancelRowEdit: onCancelRowEdit,
      ),
    );
  }
}

/// Renders read-only Reference Links card with clickable `panel` link rows.
class _EntityLinksReadOnlyCard extends StatelessWidget {
  /// Creates an [_EntityLinksReadOnlyCard].
  const _EntityLinksReadOnlyCard({
    required this.links,
    required this.canEdit,
    required this.isBusy,
    required this.onStartEdit,
    required this.onOpenLink,
  });

  /// Whether the edit pencil button is displayed.
  final bool canEdit;

  /// Disables edit trigger while busy.
  final bool isBusy;

  /// Reference links to display.
  final List<EntityLinkViewModel> links;

  /// Callback launching a link URI.
  final ValueChanged<String> onOpenLink;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      headerIcon: Icons.link_rounded,
      headerTitle: localizations.linksSectionTitle,
      headerBadge: UiPill(
        label: '${links.length} / $_maxLinksPerEntity',
        variant: UiPillVariant.count,
      ),
      headerTrailing: canEdit
          ? UiButton(
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.dense,
              tooltip: localizations.actionEdit,
              onPressed: isBusy ? null : onStartEdit,
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < links.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 6.0),
            _EntityReadOnlyLinkRow(
              link: links[index],
              onTap: () => onOpenLink(links[index].uri),
            ),
          ],
        ],
      ),
    );
  }
}

/// Manages inline link list editing and external link launching for [EntityLinksSection].
class _EntityLinksSectionState extends ConsumerState<EntityLinksSection> {
  late final TextEditingController _titleController;
  late final TextEditingController _uriController;

  List<EntityLinkViewModel> _draftLinks = const <EntityLinkViewModel>[];
  int? _editingIndex;
  String? _inputErrorText;
  bool _isSubmitting = false;
  String? _saveErrorText;

  @override
  void initState() {
    super.initState();
    _draftLinks = List<EntityLinkViewModel>.of(widget.links);
    _titleController = TextEditingController();
    _uriController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant EntityLinksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _draftLinks = List<EntityLinkViewModel>.of(widget.links);
      _editingIndex = null;
      _titleController.clear();
      _uriController.clear();
      _inputErrorText = null;
      _saveErrorText = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _editingIndex = null;
      _inputErrorText = null;
      _saveErrorText = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _uriController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditing) {
      return widget.links.isNotEmpty
          ? _EntityLinksReadOnlyCard(
              links: widget.links,
              canEdit: widget.canEdit,
              isBusy: widget.isBusy,
              onStartEdit: widget.onStartEdit,
              onOpenLink: _handleOpenLink,
            )
          : const SizedBox.shrink();
    }

    return _EntityLinksEditCard(
      draftLinks: _draftLinks,
      hasPersistedLinks: widget.links.isNotEmpty,
      editingIndex: _editingIndex,
      titleController: _titleController,
      uriController: _uriController,
      inputErrorText: _inputErrorText,
      saveErrorText: _saveErrorText,
      isBusy: widget.isBusy || _isSubmitting,
      onReorder: _handleReorder,
      onStartRowEdit: _handleStartRowEdit,
      onDeleteRow: _handleDeleteRow,
      onInputChanged: _handleInputChanged,
      onCommitLinkInput: _handleCommitLinkInput,
      onCancelRowEdit: _handleCancelRowEdit,
      onClearAll: _handleClearAll,
      onCancel: widget.onCancelEdit,
      onSave: _handleSave,
    );
  }

  /// Exits inline row editing and clears the title/URI inputs.
  void _handleCancelRowEdit() {
    setState(() {
      _editingIndex = null;
      _titleController.clear();
      _uriController.clear();
      _inputErrorText = null;
    });
  }

  /// Persists an empty links list when clearing all links.
  Future<void> _handleClearAll() => _submitLinks(const <EntityLinkViewModel>[]);

  /// Validates the inline title/URI inputs and inserts or updates the target link row.
  bool _handleCommitLinkInput() {
    final editingIndex = _editingIndex;
    final error = TaskController.validateLinkInput(
      rawTitle: _titleController.text,
      rawUri: _uriController.text,
      currentCount: _draftLinks.length,
      isEditingExisting: editingIndex != null,
      isLabel: widget.isLabel,
      locale: Localizations.localeOf(context),
    );
    if (error != null) {
      setState(() => _inputErrorText = error);
      return false;
    }
    final nextLink = EntityLinkViewModel(
      title: _titleController.text.trim(),
      uri: _uriController.text.trim(),
    );
    final nextLinks = List<EntityLinkViewModel>.of(_draftLinks);
    if (editingIndex != null &&
        editingIndex >= 0 &&
        editingIndex < nextLinks.length) {
      nextLinks[editingIndex] = nextLink;
    } else {
      nextLinks.add(nextLink);
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingIndex = null;
      _titleController.clear();
      _uriController.clear();
      _inputErrorText = null;
      _saveErrorText = null;
    });
    return true;
  }

  /// Deletes the draft link row at [index] and keeps [_editingIndex] consistent.
  void _handleDeleteRow(EntityLinkViewModel link, int index) {
    if (index < 0 || index >= _draftLinks.length) {
      return;
    }
    final nextLinks = List<EntityLinkViewModel>.of(_draftLinks)
      ..removeAt(index);
    int? nextEditingIndex = _editingIndex;
    if (nextEditingIndex == index) {
      nextEditingIndex = null;
      _titleController.clear();
      _uriController.clear();
    } else if (nextEditingIndex != null && nextEditingIndex > index) {
      nextEditingIndex -= 1;
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingIndex = nextEditingIndex;
      _inputErrorText = null;
      _saveErrorText = null;
    });
  }

  /// Clears transient inline input validation errors when typing resumes.
  void _handleInputChanged(String value) {
    if (_inputErrorText != null) {
      setState(() => _inputErrorText = null);
    }
  }

  /// Opens [uri] through [linkActionControllerProvider] and shows a danger notice on failure.
  Future<void> _handleOpenLink(String uri) async {
    final outcome = await ref.read(linkActionControllerProvider).openLink(uri);
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case LinkOpenOutcome.opened:
        return;
      case LinkOpenOutcome.failed:
        final localizations = AppLocalizations.of(context);
        ref
            .read(floatingNoticeControllerProvider.notifier)
            .showNotice(
              localizations.errorOpenLinkFailed,
              tone: NoticeTone.danger,
            );
    }
  }

  /// Reorders the draft links list between [oldIndex] and [newIndex].
  void _handleReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _draftLinks.length ||
        newIndex < 0 ||
        newIndex >= _draftLinks.length ||
        oldIndex == newIndex) {
      return;
    }
    final nextLinks = List<EntityLinkViewModel>.of(_draftLinks);
    final moved = nextLinks.removeAt(oldIndex);
    nextLinks.insert(newIndex, moved);
    int? nextEditingIndex = _editingIndex;
    if (nextEditingIndex == oldIndex) {
      nextEditingIndex = newIndex;
    } else if (nextEditingIndex == newIndex) {
      nextEditingIndex = oldIndex;
    }
    setState(() {
      _draftLinks = nextLinks;
      _editingIndex = nextEditingIndex;
      _saveErrorText = null;
    });
  }

  /// Commits any typed pending link input and saves [_draftLinks].
  Future<void> _handleSave() async {
    final hasPendingInput =
        _titleController.text.trim().isNotEmpty ||
        _uriController.text.trim().isNotEmpty;
    if (hasPendingInput && !_handleCommitLinkInput()) {
      return;
    }
    await _submitLinks(_draftLinks);
  }

  /// Loads [link] at [index] into the inline link inputs for updating.
  void _handleStartRowEdit(EntityLinkViewModel link, int index) {
    setState(() {
      _editingIndex = index;
      _titleController.text = link.title;
      _uriController.text = link.uri;
      _inputErrorText = null;
    });
  }

  /// Submits [links] to [widget.onSave] and displays inline failure messages if rejected.
  Future<void> _submitLinks(List<EntityLinkViewModel> links) async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _saveErrorText = null;
    });
    final result = await widget.onSave(
      List<EntityLinkViewModel>.unmodifiable(links),
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() => _isSubmitting = false);
      case ActionValidationFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _saveErrorText = message;
        });
      case ActionPersistFailed(:final message):
        setState(() {
          _isSubmitting = false;
          _saveErrorText = message;
        });
    }
  }
}

/// Full-width clickable `panel` link card rendered inside a `bg` inset well (`U-COMP-006`).
class _EntityReadOnlyLinkRow extends StatefulWidget {
  /// Creates an [_EntityReadOnlyLinkRow].
  const _EntityReadOnlyLinkRow({required this.link, required this.onTap});

  /// Link title and target URI.
  final EntityLinkViewModel link;

  /// Callback launching [link].
  final VoidCallback onTap;

  @override
  State<_EntityReadOnlyLinkRow> createState() => _EntityReadOnlyLinkRowState();
}

/// Manages pointer hover border and keyboard focus ring for [_EntityReadOnlyLinkRow].
class _EntityReadOnlyLinkRowState extends State<_EntityReadOnlyLinkRow> {
  bool _isHovered = false;
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: '${widget.link.title} (${localizations.tooltipOpenLink})',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: _handleHoverHighlight,
        onShowFocusHighlight: _handleFocusHighlight,
        actions: _buildActivateActions(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: _EntityReadOnlyLinkSurface(
            link: widget.link,
            isHovered: _isHovered,
            showFocusRing: _showFocusRing,
          ),
        ),
      ),
    );
  }

  /// Builds keyboard activation actions delegating Enter and Space to [widget.onTap].
  Map<Type, Action<Intent>> _buildActivateActions() {
    return <Type, Action<Intent>>{
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onTap();
          return null;
        },
      ),
      ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
        onInvoke: (_) {
          widget.onTap();
          return null;
        },
      ),
    };
  }

  /// Updates keyboard focus ring visibility when focus state changes.
  void _handleFocusHighlight(bool focused) {
    if (_showFocusRing != focused) {
      setState(() => _showFocusRing = focused);
    }
  }

  /// Updates hover highlight state when pointer hover changes.
  void _handleHoverHighlight(bool hovered) {
    if (_isHovered != hovered) {
      setState(() => _isHovered = hovered);
    }
  }
}

/// Paints the `panel` card body and optional `1px` `accent` focus ring for [_EntityReadOnlyLinkRow].
class _EntityReadOnlyLinkSurface extends StatelessWidget {
  /// Creates an [_EntityReadOnlyLinkSurface].
  const _EntityReadOnlyLinkSurface({
    required this.link,
    required this.isHovered,
    required this.showFocusRing,
  });

  /// Highlights the border and trailing icon in `accent` while hovered.
  final bool isHovered;

  /// Link title and target URI.
  final EntityLinkViewModel link;

  /// Renders an outer `1px` `accent` keyboard focus ring when true.
  final bool showFocusRing;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final radius = tokens.radii.md;
    final card = AnimatedContainer(
      duration: tokens.focus.hoverDuration,
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isHovered ? colors.accent : colors.line,
          width: tokens.radii.borderWidth,
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: _EntityLinkListItem(link: link)),
          const SizedBox(width: 10.0),
          ExcludeSemantics(
            child: Icon(
              Icons.open_in_new_rounded,
              size: tokens.spacing.iconSm,
              color: isHovered ? colors.accent : colors.muted,
            ),
          ),
        ],
      ),
    );

    return _EntityFocusRingBox(
      visible: showFocusRing,
      radius: radius,
      child: card,
    );
  }
}
