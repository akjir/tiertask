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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tdf_error.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/config_providers.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/task_schedule_helper.dart';
import '../components/ui_ordered_item_list.dart';
import '../layout/ui_responsive_grid.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_pill.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import 'entity_card_chrome.dart';

/// Pure reusable Reference Links reorderable list and inline add/edit form body (`U-COMP-006`).
class EntityLinksEditorBody extends StatelessWidget {
  /// Creates an [EntityLinksEditorBody].
  const EntityLinksEditorBody({
    super.key,
    required this.links,
    required this.editingIndex,
    required this.titleController,
    required this.uriController,
    required this.onReorder,
    required this.onStartRowEdit,
    required this.onDeleteRow,
    required this.onCommitLink,
    required this.onCancelRowEdit,
    this.inputErrorText,
    this.onInputChanged,
    this.enabled = true,
    this.autofocusTitle = false,
    this.itemKeyPrefix = 'entity_link',
  });

  /// Requests initial focus on the title input when mounted (used for live inline edit).
  final bool autofocusTitle;

  /// Row index currently being updated inline, or `null` when adding a new link.
  final int? editingIndex;

  /// Whether row actions, inputs, and submit buttons accept interaction.
  final bool enabled;

  /// Optional validation error for the inline title/URI inputs.
  final String? inputErrorText;

  /// Deterministic prefix applied to each ordered row [ValueKey].
  final String itemKeyPrefix;

  /// Current editable links list.
  final List<TaskLink> links;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Callback adding or updating the typed link row.
  final VoidCallback onCommitLink;

  /// Callback removing a link row.
  final UiOrderedItemActionCallback<TaskLink> onDeleteRow;

  /// Optional callback notified whenever title or URI text changes.
  final ValueChanged<String>? onInputChanged;

  /// Callback moving a link row up or down.
  final UiOrderedItemReorderCallback onReorder;

  /// Callback loading an existing link row into the inline form inputs.
  final UiOrderedItemActionCallback<TaskLink> onStartRowEdit;

  /// Title text controller.
  final TextEditingController titleController;

  /// URI text controller.
  final TextEditingController uriController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiOrderedItemList<TaskLink>(
      items: links,
      itemKey: (link, index) =>
          ValueKey<String>('${itemKeyPrefix}_${index}_${link.uri}'),
      editingIndex: editingIndex,
      onReorder: enabled ? onReorder : null,
      moveUpTooltip: localizations.tooltipMoveLinkUp,
      moveDownTooltip: localizations.tooltipMoveLinkDown,
      onEdit: enabled ? onStartRowEdit : null,
      editTooltip: localizations.tooltipEditLink,
      onDelete: enabled ? onDeleteRow : null,
      deleteTooltip: localizations.tooltipRemoveLink,
      itemBuilder: (context, link, index, isEditingRow) =>
          _EntityLinkListItem(link: link),
      addBar: _EntityLinkFormBar(
        titleController: titleController,
        uriController: uriController,
        isEditingExisting: editingIndex != null,
        autofocusTitle: autofocusTitle,
        errorText: inputErrorText,
        enabled: enabled,
        onChanged: onInputChanged,
        onSubmitLink: onCommitLink,
        onCancelRowEdit: onCancelRowEdit,
      ),
    );
  }
}

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
  final List<TaskLink> links;

  /// Callback closing inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback validating and persisting the edited links list.
  final Future<ActionResult> Function(List<TaskLink> links) onSave;

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

/// Renders inline title + URI fields, validation error, and Add/Update link buttons.
class _EntityLinkFormBar extends StatelessWidget {
  /// Creates an [_EntityLinkFormBar].
  const _EntityLinkFormBar({
    required this.titleController,
    required this.uriController,
    required this.isEditingExisting,
    required this.autofocusTitle,
    required this.errorText,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitLink,
    required this.onCancelRowEdit,
  });

  /// Requests initial focus on the title field when true.
  final bool autofocusTitle;

  /// Whether inputs and submit button are enabled.
  final bool enabled;

  /// Optional inline link validation error text.
  final String? errorText;

  /// Swaps `Add link` to `Update link` + `Cancel` when true.
  final bool isEditingExisting;

  /// Callback cancelling an active row edit.
  final VoidCallback onCancelRowEdit;

  /// Optional callback notified when either input changes.
  final ValueChanged<String>? onChanged;

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
    final error = errorText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _EntityLinkFormInputsGrid(
          titleController: titleController,
          uriController: uriController,
          autofocusTitle: autofocusTitle,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitLink: onSubmitLink,
        ),
        if (error != null && error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6.0),
          EntityInlineErrorText(message: error),
        ],
        SizedBox(height: tokens.spacing.space2),
        Wrap(
          spacing: 6.0,
          runSpacing: 6.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            UiButton(
              label: isEditingExisting
                  ? localizations.tooltipSaveLink
                  : localizations.tooltipAddLink,
              leadingIcon: isEditingExisting ? null : Icons.add_rounded,
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
    required this.autofocusTitle,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitLink,
  });

  /// Requests initial focus on the title input when true.
  final bool autofocusTitle;

  /// Whether inputs accept interaction.
  final bool enabled;

  /// Optional callback notified when either input changes.
  final ValueChanged<String>? onChanged;

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
          controller: titleController,
          hintText: localizations.linkTitleHint,
          maxLength: maxTdfTextLength,
          autofocus: autofocusTitle,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitLink(),
        ),
        UiField(
          controller: uriController,
          hintText: localizations.linkUriHint,
          maxLength: maxTdfTextLength,
          isMonospace: true,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitLink(),
        ),
      ],
    );
  }
}

/// Renders one link title and monospace URI stack inside read-only cards and [EntityLinksEditorBody].
class _EntityLinkListItem extends StatelessWidget {
  /// Creates an [_EntityLinkListItem].
  const _EntityLinkListItem({required this.link});

  /// Reference link displayed in this row.
  final TaskLink link;

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

/// Renders read-only Reference Links card with clickable `panel` link rows.
class _EntityLinksReadOnlyCard extends StatelessWidget {
  /// Creates an [_EntityLinksReadOnlyCard].
  const _EntityLinksReadOnlyCard({
    required this.links,
    required this.maxLinks,
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
  final List<TaskLink> links;

  /// Maximum number of links permitted on this entity.
  final int maxLinks;

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
        label: '${links.length} / $maxLinks',
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

  List<TaskLink> _draftLinks = const <TaskLink>[];
  int? _editingIndex;
  String? _inputErrorText;
  bool _isSubmitting = false;
  String? _saveErrorText;

  @override
  void initState() {
    super.initState();
    _draftLinks = List<TaskLink>.of(widget.links);
    _titleController = TextEditingController();
    _uriController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant EntityLinksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _draftLinks = List<TaskLink>.of(widget.links);
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
    final maxLinks = widget.isLabel ? maxTdfLinksPerLabel : maxTdfLinksPerTask;
    if (!widget.isEditing) {
      return widget.links.isNotEmpty
          ? _EntityLinksReadOnlyCard(
              links: widget.links,
              maxLinks: maxLinks,
              canEdit: widget.canEdit,
              isBusy: widget.isBusy,
              onStartEdit: widget.onStartEdit,
              onOpenLink: _handleOpenLink,
            )
          : const SizedBox.shrink();
    }

    final localizations = AppLocalizations.of(context);
    final effectiveBusy = widget.isBusy || _isSubmitting;
    return UiCard.inset(
      isEditing: true,
      headerIcon: Icons.link_rounded,
      headerTitle: localizations.linksSectionTitle,
      headerBadge: UiPill(
        label: '${_draftLinks.length} / $maxLinks',
        variant: UiPillVariant.count,
      ),
      footer: EntityInlineEditorFooter(
        errorText: _saveErrorText,
        clearLabel: widget.links.isNotEmpty
            ? localizations.inlineClearAction
            : null,
        onClear: widget.links.isNotEmpty ? _handleClearAll : null,
        onCancel: widget.onCancelEdit,
        onSave: _handleSave,
        isBusy: effectiveBusy,
      ),
      child: EntityLinksEditorBody(
        links: _draftLinks,
        editingIndex: _editingIndex,
        titleController: _titleController,
        uriController: _uriController,
        inputErrorText: _inputErrorText,
        enabled: !effectiveBusy,
        autofocusTitle: true,
        onReorder: _handleReorder,
        onStartRowEdit: _handleStartRowEdit,
        onDeleteRow: _handleDeleteRow,
        onInputChanged: _handleInputChanged,
        onCommitLink: _handleCommitLinkInput,
        onCancelRowEdit: _handleCancelRowEdit,
      ),
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
  Future<void> _handleClearAll() => _submitLinks(const <TaskLink>[]);

  /// Validates the inline title/URI inputs and inserts or updates the target link row.
  bool _handleCommitLinkInput() {
    final editingIndex = _editingIndex;
    final error = TaskScheduleHelper.validateLinkInput(
      rawTitle: _titleController.text,
      rawUri: _uriController.text,
      currentCount: _draftLinks.length,
      localizations: AppLocalizations.of(context),
      isEditingExisting: editingIndex != null,
      isLabel: widget.isLabel,
    );
    if (error != null) {
      setState(() => _inputErrorText = error);
      return false;
    }
    final nextLink = TaskLink(
      title: _titleController.text.trim(),
      uri: _uriController.text.trim(),
    );
    final nextLinks = List<TaskLink>.of(_draftLinks);
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
  void _handleDeleteRow(TaskLink link, int index) {
    if (index < 0 || index >= _draftLinks.length) {
      return;
    }
    final nextLinks = List<TaskLink>.of(_draftLinks)..removeAt(index);
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

  /// Opens [uri] through [openExternalLinkProvider] and shows a danger notice on failure.
  Future<void> _handleOpenLink(String uri) async {
    final opened = await ref.read(openExternalLinkProvider)(uri);
    if (!mounted || opened) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    ref
        .read(floatingNoticeProvider.notifier)
        .showNotice(
          localizations.errorOpenLinkFailed,
          tone: FloatingNoticeTone.danger,
        );
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
    final nextLinks = List<TaskLink>.of(_draftLinks);
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
  void _handleStartRowEdit(TaskLink link, int index) {
    setState(() {
      _editingIndex = index;
      _titleController.text = link.title;
      _uriController.text = link.uri;
      _inputErrorText = null;
    });
  }

  /// Submits [links] to [widget.onSave] and displays inline failure messages if rejected.
  Future<void> _submitLinks(List<TaskLink> links) async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _saveErrorText = null;
    });
    try {
      final result = await widget.onSave(List<TaskLink>.unmodifiable(links));
      if (!mounted) {
        return;
      }
      switch (result) {
        case ActionSucceeded():
          break;
        case ActionValidationFailed(:final message):
        case ActionPersistFailed(:final message):
          setState(() => _saveErrorText = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

/// Full-width clickable `panel` link card rendered inside a `bg` inset well (`U-COMP-006`).
class _EntityReadOnlyLinkRow extends StatefulWidget {
  /// Creates an [_EntityReadOnlyLinkRow].
  const _EntityReadOnlyLinkRow({required this.link, required this.onTap});

  /// Link title and target URI.
  final TaskLink link;

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
  final TaskLink link;

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
