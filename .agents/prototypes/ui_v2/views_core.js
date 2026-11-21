(() => {
  window.TT2 = window.TT2 || {};
  const { escapeHtml, renderIcon } = window.TT2;
  const {
    t,
    formatLocalDate,
    formatLocalTimestamp,
    formatRemainingDuration,
    formatRepeatPhrase,
  } = window.TT2.i18n;
  const {
    LABEL_COLOR_PRESETS,
    resolveOffsetMinutes,
    isTaskSuspendedActive,
    isTaskWithinDueLeadWindow,
    isTaskOverdue,
    wouldCreateDependencyCycle,
    formatConditionLine,
    formatRepeatSummary,
  } = window.TT2.engine;

  const TIER_ICONS = [
    'zap',
    'list-ordered',
    'calendar-days',
    'circle-slash',
    'lightbulb',
    'circle-check',
  ];

  function tierName(lang, index) {
    return t(lang, `tier${index}`);
  }

  function renderChrome(state, workspace) {
    const lang = state.lang;
    const cfg = workspace.config;
    const sim = state.simState;
    const usesWebDav = cfg.storageMode === 'webdav' || cfg.storageMode === 'both';

    let syncIcon = 'cloud-check';
    let syncLabel = t(lang, 'syncStatusSynced');
    let syncClass = 'sync-btn';
    if (!usesWebDav) {
      syncIcon = 'folder';
      syncLabel = t(lang, 'syncStatusLocal');
    } else if (state.syncing || sim === 'syncing') {
      syncIcon = 'refresh-cw';
      syncLabel = t(lang, 'syncStatusSyncing');
      syncClass += ' is-syncing';
    } else if (
      sim === 'conflict_deletion' ||
      sim === 'conflict_recovery'
    ) {
      syncIcon = 'alert-triangle';
      syncLabel = t(lang, 'syncStatusConflict');
      syncClass += ' is-warning';
    } else if (
      sim === 'sync_error' ||
      sim === 'file_read_banner' ||
      sim === 'file_read_full' ||
      sim === 'generation_rollback'
    ) {
      syncIcon = 'cloud-off';
      syncLabel = t(lang, 'syncStatusError');
      syncClass += ' is-danger';
    }

    const locStatus = state.locationSearching
      ? 'searching'
      : state.locationFix.status;
    const locIcon =
      locStatus === 'found'
        ? 'locate'
        : locStatus === 'searching'
          ? 'refresh-cw'
          : 'locate-off';

    return `
      <header class="chrome ${state.searchOpen ? 'is-searching' : ''}">
        <button type="button" class="menu" data-menu aria-label="${escapeHtml(t(lang, state.drawer ? 'menuClose' : 'menuOpen'))}" aria-expanded="${state.drawer}">
          ${renderIcon(state.drawer ? 'x' : 'menu')}
        </button>
        <button type="button" class="brand-btn" data-view="tasks" aria-label="${escapeHtml(t(lang, 'appTitle'))}">
          <span class="mark" aria-hidden="true"><b></b><b></b><b></b></span>
          <span>TierTask</span>
        </button>
        <button type="button" class="workspace-pill" data-open-modal="workspaces" title="${escapeHtml(t(lang, 'workspacesTitle'))}">
          ${renderIcon('workspaces', 'icon-sm')}
          <span>${escapeHtml(workspace.name)}</span>
          ${renderIcon('chevrons-up-down', 'icon-xs')}
        </button>
        <div class="chrome-spacer"></div>
        ${
          state.searchOpen
            ? `<div class="chrome-search">
                ${renderIcon('search', 'icon-sm')}
                <input type="search" data-global-search value="${escapeHtml(state.searchQuery)}" placeholder="${escapeHtml(t(lang, 'searchPlaceholder'))}" aria-label="${escapeHtml(t(lang, 'searchPlaceholder'))}">
                <button type="button" class="icon-button compact" data-toggle-search aria-label="${escapeHtml(t(lang, 'searchClear'))}">
                  ${renderIcon('x', 'icon-sm')}
                </button>
              </div>`
            : `<button type="button" class="icon-button" data-toggle-search title="${escapeHtml(t(lang, 'searchPlaceholder'))}" aria-label="${escapeHtml(t(lang, 'searchPlaceholder'))}">
                ${renderIcon('search')}
              </button>`
        }
        ${
          cfg.locationEnabled
            ? `<button type="button" class="icon-button ${locStatus === 'found' ? 'is-accent' : ''} ${locStatus === 'searching' ? 'is-spinning' : ''}" data-open-modal="location-status" title="${escapeHtml(t(lang, 'locationDialogTitle'))}" aria-label="${escapeHtml(t(lang, 'locationDialogTitle'))}">
                ${renderIcon(locIcon)}
              </button>`
            : ''
        }
        <button type="button" class="${syncClass}" data-trigger-sync title="${escapeHtml(t(lang, 'syncWebDav'))}">
          ${renderIcon(syncIcon, 'icon-sm')}
          <span class="sync-label">${escapeHtml(syncLabel)}</span>
        </button>
      </header>
    `;
  }

  function renderSidebar(state, workspace, evalRes) {
    const lang = state.lang;
    const cfg = workspace.config;
    const sortedLabels = [...workspace.labels].sort((a, b) =>
      a.name.localeCompare(b.name),
    );
    const sortedLocations = [...workspace.locations].sort((a, b) =>
      a.name.localeCompare(b.name),
    );
    const usesWebDav = cfg.storageMode === 'webdav' || cfg.storageMode === 'both';
    const activeFile =
      cfg.storageMode === 'webdav' ? cfg.filePath : cfg.localFilePath;

    return `
      <button type="button" class="sidebar-ws-card" data-open-modal="workspaces">
        <span class="ws-badge-icon">${renderIcon('workspaces', 'icon-sm')}</span>
        <span class="ws-card-meta">
          <strong>${escapeHtml(workspace.name)}</strong>
          <small>${renderIcon(usesWebDav ? 'cloud' : 'folder', 'icon-xs')} ${escapeHtml(activeFile)}</small>
        </span>
        ${renderIcon('chevrons-up-down', 'icon-sm')}
      </button>

      <section>
        <div class="section-head"><span class="eyebrow">${escapeHtml(t(lang, 'sectionTasks'))}</span></div>
        ${[0, 1, 2, 3, 4, 5]
          .map(
            (idx) => `
          <button class="nav-row" type="button" data-tier="${idx}" ${
            state.view === 'tasks' && !state.searchOpen && state.tier === idx
              ? 'aria-current="page"'
              : ''
          }>
            ${renderIcon(TIER_ICONS[idx])}
            <span>${escapeHtml(tierName(lang, idx))}</span>
            <span class="count">${evalRes.tiers[idx].length}</span>
          </button>`,
          )
          .join('')}
      </section>

      <section>
        <div class="section-head">
          <span class="eyebrow">${escapeHtml(t(lang, 'sectionLabels'))}</span>
          <button class="text-button" type="button" data-view="labels">${escapeHtml(t(lang, 'manage'))}</button>
        </div>
        <button type="button" class="nav-row" data-label="" ${
          state.view === 'tasks' && !state.label ? 'aria-current="page"' : ''
        }>
          ${renderIcon('layers')}
          <span class="nav-label-name">${escapeHtml(t(lang, 'allTasks'))}</span>
        </button>
        ${sortedLabels
          .map(
            (label) => `
          <div class="nav-label-row ${state.view === 'tasks' && state.label === label.id ? 'is-current' : ''}">
            <button class="nav-row nav-label-select" type="button" data-label="${escapeHtml(label.id)}" ${
              state.view === 'tasks' && state.label === label.id
                ? 'aria-current="page"'
                : ''
            }>
              <span class="dot" style="--label-color:${escapeHtml(label.color || '#00648b')}"></span>
              <span class="nav-label-name">
                ${escapeHtml(label.name)}
                ${label.scoped ? `<span class="label-mode">${escapeHtml(t(lang, 'scopedQueue'))}</span>` : ''}
              </span>
              <span class="count">${evalRes.openCountByLabel.get(label.id) || 0}</span>
            </button>
            <button type="button" class="icon-button compact nav-hub-btn" data-open-label-hub="${escapeHtml(label.id)}" title="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}" aria-label="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}">
              ${renderIcon('info', 'icon-sm')}
            </button>
          </div>`,
          )
          .join('')}
      </section>

      <section>
        <div class="section-head">
          <span class="eyebrow">${escapeHtml(t(lang, 'sectionLocations'))}</span>
          <button class="text-button" type="button" data-view="locations">${escapeHtml(t(lang, 'manage'))}</button>
        </div>
        ${sortedLocations
          .map(
            (loc) => `
          <button type="button" class="nav-row" data-edit-location="${escapeHtml(loc.id)}">
            ${renderIcon('map-pin')}
            <span class="nav-label-name">${escapeHtml(loc.name)}</span>
            <span class="count">${evalRes.openCountByLocation.get(loc.id) || 0}</span>
          </button>`,
          )
          .join('')}
      </section>

      <section class="sidebar-utils">
        <div class="section-head"><span class="eyebrow">${escapeHtml(t(lang, 'sectionUtilities'))}</span></div>
        ${
          usesWebDav
            ? `<button type="button" class="nav-row" data-trigger-sync>
                ${renderIcon('refresh-cw')}
                <span>${escapeHtml(t(lang, 'syncWebDav'))}</span>
              </button>`
            : ''
        }
        <button type="button" class="nav-row" data-view="raw-tdf" ${state.view === 'raw-tdf' ? 'aria-current="page"' : ''}>
          ${renderIcon('code')}
          <span>${escapeHtml(t(lang, 'rawTdfPreview'))}</span>
        </button>
        ${
          cfg.diagnosticsEnabled
            ? `<button type="button" class="nav-row" data-view="logs" ${state.view === 'logs' ? 'aria-current="page"' : ''}>
                ${renderIcon('bug')}
                <span>${escapeHtml(t(lang, 'diagnosticLog'))}</span>
              </button>`
            : ''
        }
        <button type="button" class="nav-row" data-view="settings" ${state.view === 'settings' ? 'aria-current="page"' : ''}>
          ${renderIcon('settings')}
          <span>${escapeHtml(t(lang, 'settings'))}</span>
        </button>
      </section>

      <div class="sidebar-footer">
        <span class="version-main">Version 0.4.0</span><span class="version-build">+a1b2c3d</span>
      </div>
    `;
  }

  function renderBanners(state, workspace) {
    const lang = state.lang;
    const sim = state.simState;
    const cfg = workspace.config;
    const out = [];

    if (
      (cfg.storageMode === 'webdav' || cfg.storageMode === 'both') &&
      (!cfg.serverUrl.trim() || !cfg.username.trim() || !cfg.password)
    ) {
      out.push(`
        <div class="status-banner tone-warning" role="status">
          ${renderIcon('alert-triangle', 'icon-sm')}
          <div class="banner-body">${escapeHtml(t(lang, 'bannerUnconfigured'))}</div>
          <button type="button" class="secondary compact" data-view="settings">${escapeHtml(t(lang, 'actionConfigure'))}</button>
        </div>
      `);
    }

    if (sim === 'sync_error' && !state.bannerDismissed) {
      out.push(`
        <div class="status-banner tone-danger" role="alert">
          ${renderIcon('cloud-off', 'icon-sm')}
          <div class="banner-body">${escapeHtml(t(lang, 'bannerSyncError'))}</div>
          <button type="button" class="secondary compact" data-trigger-sync>${escapeHtml(t(lang, 'actionRetry'))}</button>
          <button type="button" class="icon-button compact" data-dismiss-banner aria-label="${escapeHtml(t(lang, 'actionClose'))}">${renderIcon('x', 'icon-sm')}</button>
        </div>
      `);
    } else if (sim === 'file_read_banner' && !state.bannerDismissed) {
      out.push(`
        <div class="status-banner tone-danger" role="alert">
          ${renderIcon('alert-circle', 'icon-sm')}
          <div class="banner-body">
            <strong>${escapeHtml(t(lang, 'fileReadSumLocalFailRemoteOk'))}</strong>
            <div class="banner-sublines">
              <div>${renderIcon('alert-circle', 'icon-xs')} ${escapeHtml(t(lang, 'fileReadTargetLocal'))}: ${escapeHtml(t(lang, 'fileReadUnreadable'))} (${escapeHtml(t(lang, 'fileReadReasonFormat'))})</div>
              <div>${renderIcon('circle-check', 'icon-xs')} ${escapeHtml(t(lang, 'fileReadTargetRemote'))}: ${escapeHtml(t(lang, 'fileReadOk'))}</div>
            </div>
          </div>
          <button type="button" class="icon-button compact" data-dismiss-banner aria-label="${escapeHtml(t(lang, 'actionClose'))}">${renderIcon('x', 'icon-sm')}</button>
        </div>
      `);
    } else if (sim === 'conflict_deletion') {
      out.push(`
        <div class="status-banner tone-warning" role="alert">
          ${renderIcon('alert-triangle', 'icon-sm')}
          <div class="banner-body">${escapeHtml(t(lang, 'bannerDeletionConflict'))}</div>
          ${
            state.view !== 'conflict-resolution'
              ? `<button type="button" class="primary compact" data-view="conflict-resolution">${escapeHtml(t(lang, 'actionResolveConflict'))}</button>`
              : ''
          }
        </div>
      `);
    } else if (sim === 'conflict_recovery') {
      out.push(`
        <div class="status-banner tone-warning" role="alert">
          ${renderIcon('alert-triangle', 'icon-sm')}
          <div class="banner-body">${escapeHtml(t(lang, 'bannerRecoveryRequired'))}</div>
          ${
            state.view !== 'recovery-resolution'
              ? `<button type="button" class="primary compact" data-view="recovery-resolution">${escapeHtml(t(lang, 'actionResolveRecovery'))}</button>`
              : ''
          }
        </div>
      `);
    } else if (sim === 'generation_rollback' && !state.bannerDismissed) {
      out.push(`
        <div class="status-banner tone-danger" role="alert">
          ${renderIcon('alert-circle', 'icon-sm')}
          <div class="banner-body">${escapeHtml(t(lang, 'bannerGenRollback'))}</div>
          <button type="button" class="secondary compact" data-view="settings">${escapeHtml(t(lang, 'settings'))}</button>
          <button type="button" class="icon-button compact" data-dismiss-banner aria-label="${escapeHtml(t(lang, 'actionClose'))}">${renderIcon('x', 'icon-sm')}</button>
        </div>
      `);
    }

    return out.join('');
  }

  function renderFullFileReadError(state) {
    const lang = state.lang;
    return `
      <div class="full-error-state">
        <div class="full-error-icon">${renderIcon('cloud-off', 'icon-lg')}</div>
        <h2>${escapeHtml(t(lang, 'fileReadErrorTitle'))}</h2>
        <p class="subtitle centered">${escapeHtml(t(lang, 'fileReadSumBothFail'))}</p>
        <div class="read-report-card">
          <div class="read-report-row">
            <span class="report-icon is-danger">${renderIcon('alert-circle')}</span>
            <div class="report-detail">
              <div class="report-title-line">
                <strong>${escapeHtml(t(lang, 'fileReadTargetLocal'))}</strong>
                <span class="pill-badge tone-danger">${escapeHtml(t(lang, 'fileReadUnreadable'))}</span>
              </div>
              <small>${escapeHtml(t(lang, 'fileReadReasonFormat'))}</small>
            </div>
          </div>
          <div class="read-report-row">
            <span class="report-icon is-danger">${renderIcon('alert-circle')}</span>
            <div class="report-detail">
              <div class="report-title-line">
                <strong>${escapeHtml(t(lang, 'fileReadTargetRemote'))}</strong>
                <span class="pill-badge tone-danger">${escapeHtml(t(lang, 'fileReadUnreadable'))}</span>
              </div>
              <small>${escapeHtml(t(lang, 'fileReadReasonVersion'))}</small>
            </div>
          </div>
        </div>
        <div class="full-error-actions">
          <button type="button" class="secondary" data-view="settings">${renderIcon('settings', 'icon-sm')}${escapeHtml(t(lang, 'settings'))}</button>
          <button type="button" class="primary" data-reset-sim>${renderIcon('refresh-cw', 'icon-sm')}${escapeHtml(t(lang, 'actionRetry'))}</button>
        </div>
      </div>
    `;
  }

  function renderNotice(state) {
    const lang = state.lang;
    const undoDepth = state.undoStack.length;
    if (!state.message && !state.recoveryNotice) return '';
    return `
      <div class="notice-stack" aria-live="polite">
        ${
          state.recoveryNotice
            ? `<div class="notice-toast tone-warning">
                ${renderIcon('alert-triangle', 'icon-sm')}
                <span>${escapeHtml(t(lang, state.recoveryNotice))}</span>
                <button type="button" class="text-button" data-dismiss-recovery>${escapeHtml(t(lang, 'actionClose'))}</button>
              </div>`
            : ''
        }
        ${
          state.message
            ? `<div class="notice-toast">
                <span>${escapeHtml(state.message)}</span>
                ${
                  undoDepth > 0 && state.showUndoAction
                    ? `<button type="button" class="undo-btn" data-undo>
                        ${renderIcon('undo', 'icon-xs')}
                        <span>${escapeHtml(t(lang, 'actionUndo'))}</span>
                        <kbd class="kbd-hint">Ctrl+Z</kbd>
                      </button>`
                    : ''
                }
              </div>`
            : ''
        }
      </div>
    `;
  }

  function renderInlineEditActions(lang, error, clearAttr, clearLabel) {
    return `
      ${error ? `<div class="edit-error inline-edit-error" role="status">${escapeHtml(error)}</div>` : ''}
      <div class="inline-edit-actions">
        ${
          clearAttr
            ? `<button type="button" class="text-button is-danger-text" ${clearAttr}>${escapeHtml(clearLabel)}</button>`
            : '<span></span>'
        }
        <div class="inline-edit-buttons">
          <button type="button" class="secondary compact" data-ie-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>
          <button type="button" class="primary compact" data-ie-save>${escapeHtml(t(lang, 'actionSave'))}</button>
        </div>
      </div>
    `;
  }

  function renderTaskSlidePanel(task, state, workspace, evalRes, isAnimating) {
    const lang = state.lang;
    const offset = resolveOffsetMinutes(workspace.config);
    const isCompleted = Boolean(task.finishedAt);
    const inQueue = workspace.queue.includes(task.id);
    const currentMode = task.priority
      ? 'priority'
      : !inQueue && !isCompleted
        ? 'someday'
        : 'queue';

    const edit =
      state.inlineEdit && state.inlineEdit.taskId === task.id
        ? state.inlineEdit
        : null;
    const editing = edit ? edit.section : null;
    const draft = edit ? edit.draft : null;
    const err = edit ? edit.error : '';

    const labelsById = new Map(workspace.labels.map((l) => [l.id, l]));
    const taskLabels = (task.labels || [])
      .map((id) => labelsById.get(id))
      .filter(Boolean);
    const sortedLabels = [...workspace.labels].sort((a, b) =>
      a.name.localeCompare(b.name),
    );
    const depEval = evalRes.dependencyDetailsByTask.get(task.id);
    const condEval = evalRes.conditionDetailsByTask.get(task.id);
    const suspendedActive = isTaskSuspendedActive(task, state.nowMs);
    const overdue = isTaskOverdue(task, state.nowMs);
    const withinLead = isTaskWithinDueLeadWindow(
      task,
      state.nowMs,
      workspace.config.dueLeadWindow,
    );
    const c = task.conditions || {};
    const hasCustomTaskConds = Boolean(
      c.ignoreLabels ||
        (c.daysMode && c.daysMode !== 'inherit') ||
        (c.timeMode && c.timeMode !== 'inherit') ||
        (c.placesMode && c.placesMode !== 'inherit'),
    );
    const hasConditions =
      (condEval && condEval.rules.length > 0) || hasCustomTaskConds;

    const editBtn = (section) =>
      `<button type="button" class="icon-button compact ml-auto" data-ie-open="${section}" data-ie-task="${escapeHtml(task.id)}" title="${escapeHtml(t(lang, 'actionEdit'))}" aria-label="${escapeHtml(t(lang, 'actionEdit'))}">${renderIcon('pencil', 'icon-xs')}</button>`;

    const editHistIdx = state.editingHistoryIndex;
    const sections = [];

    // 2. Note
    if (editing === 'note') {
      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('file-text', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoNoteTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            <label class="field">
              <textarea data-ie="note" rows="3" maxlength="10000" aria-label="${escapeHtml(t(lang, 'taskInfoNoteTitle'))}">${escapeHtml(draft.note)}</textarea>
            </label>
            ${renderInlineEditActions(
              lang,
              err,
              task.note ? 'data-ie-clear="note"' : '',
              t(lang, 'inlineClear'),
            )}
          </div>
        </div>
      `);
    } else if (task.note) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('file-text', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoNoteTitle'))}</strong>
            <div class="info-head-actions ml-auto">
              <button type="button" class="icon-button compact" data-copy-note="${escapeHtml(task.note)}" title="${escapeHtml(t(lang, 'actionCopy'))}">
                ${renderIcon('copy', 'icon-xs')}
              </button>
              <button type="button" class="icon-button compact" data-ie-open="note" data-ie-task="${escapeHtml(task.id)}" title="${escapeHtml(t(lang, 'actionEdit'))}">
                ${renderIcon('pencil', 'icon-xs')}
              </button>
            </div>
          </div>
          <p class="info-note">${escapeHtml(task.note)}</p>
        </div>
      `);
    }

    // 3. Links
    if (editing === 'links') {
      const editingLinkIdx = draft.editingLinkIndex;
      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('link', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoLinksTitle'))}</strong>
            <span class="info-sub ml-auto">${draft.links.length} / 20</span>
          </div>
          <div class="inline-edit-body">
            ${
              draft.links.length
                ? draft.links
                    .map(
                      (link, index) => `
                    <div class="record ${editingLinkIdx === index ? 'is-editing' : ''}">
                      <div class="record-text">
                        <strong>${escapeHtml(link.title)}</strong>
                        <span class="mono-sm">${escapeHtml(link.uri)}</span>
                      </div>
                      <div class="record-actions">
                        <button type="button" class="icon-button compact" data-ie-link-up="${index}" ${index === 0 ? 'disabled' : ''} title="${escapeHtml(t(lang, 'actionUp'))}">${renderIcon('arrow-up', 'icon-xs')}</button>
                        <button type="button" class="icon-button compact" data-ie-link-down="${index}" ${index === draft.links.length - 1 ? 'disabled' : ''} title="${escapeHtml(t(lang, 'actionDown'))}">${renderIcon('arrow-down', 'icon-xs')}</button>
                        <button type="button" class="icon-button compact" data-ie-link-edit="${index}" title="${escapeHtml(t(lang, 'actionEdit'))}">${renderIcon('pencil', 'icon-xs')}</button>
                        <button type="button" class="icon-button compact is-danger-hover" data-ie-link-remove="${index}" title="${escapeHtml(t(lang, 'actionRemove'))}">${renderIcon('trash', 'icon-xs')}</button>
                      </div>
                    </div>`,
                    )
                    .join('')
                : `<div class="info-sub">${escapeHtml(t(lang, 'emptyLinks'))}</div>`
            }
            <div class="field-grid">
              <label class="field">${escapeHtml(t(lang, 'fieldLinkTitle'))}
                <input data-ie-link-title value="${escapeHtml(draft.linkTitleDraft || '')}" placeholder="${escapeHtml(t(lang, 'placeholderLinkTitle'))}">
              </label>
              <label class="field">${escapeHtml(t(lang, 'fieldLinkUri'))}
                <input data-ie-link-uri value="${escapeHtml(draft.linkUriDraft || '')}" placeholder="${escapeHtml(t(lang, 'placeholderLinkUri'))}">
              </label>
            </div>
            <div class="inline-btn-row">
              <button type="button" class="secondary compact" data-ie-link-submit>${escapeHtml(t(lang, editingLinkIdx !== null && editingLinkIdx !== undefined ? 'actionSaveLink' : 'actionAddLink'))}</button>
              ${
                editingLinkIdx !== null && editingLinkIdx !== undefined
                  ? `<button type="button" class="text-button" data-ie-link-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>`
                  : ''
              }
            </div>
            ${renderInlineEditActions(
              lang,
              err,
              task.links?.length ? 'data-ie-clear="links"' : '',
              t(lang, 'inlineClear'),
            )}
          </div>
        </div>
      `);
    } else if (task.links?.length) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('link', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoLinksTitle'))}</strong>
            ${editBtn('links')}
          </div>
          <div class="hub-links-list">
            ${task.links
              .map(
                (link) => `
              <button type="button" class="hub-link-row" data-open-uri="${escapeHtml(link.uri)}">
                <span>
                  <strong>${escapeHtml(link.title)}</strong>
                  <small class="mono-sm">${escapeHtml(link.uri)}</small>
                </span>
                ${renderIcon('external-link', 'icon-sm')}
              </button>`,
              )
              .join('')}
          </div>
        </div>
      `);
    }

    // 4. Subtasks
    if (editing === 'subtasks') {
      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon(draft.subtasksAutoFinish ? 'check-square' : 'list-checks', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoSubtasksTitle'))}</strong>
            <span class="info-sub ml-auto">${draft.subtasks.length}</span>
          </div>
          <div class="inline-edit-body">
            ${
              draft.subtasks.length
                ? `<div class="inline-subtask-edit-list">
                    ${draft.subtasks
                      .map(
                        (step, idx) => `
                      <div class="inline-subtask-edit-row">
                        <input type="checkbox" data-ie-step-done="${idx}" ${step.done ? 'checked' : ''} aria-label="${escapeHtml(step.text)}">
                        <input type="text" data-ie-step-text="${idx}" value="${escapeHtml(step.text)}" maxlength="200">
                        <button type="button" class="icon-button compact" data-ie-step-up="${idx}" ${idx === 0 ? 'disabled' : ''} title="${escapeHtml(t(lang, 'actionUp'))}">${renderIcon('arrow-up', 'icon-xs')}</button>
                        <button type="button" class="icon-button compact" data-ie-step-down="${idx}" ${idx === draft.subtasks.length - 1 ? 'disabled' : ''} title="${escapeHtml(t(lang, 'actionDown'))}">${renderIcon('arrow-down', 'icon-xs')}</button>
                        <button type="button" class="icon-button compact is-danger-hover" data-ie-step-remove="${idx}" title="${escapeHtml(t(lang, 'actionRemove'))}">${renderIcon('trash', 'icon-xs')}</button>
                      </div>`,
                      )
                      .join('')}
                  </div>`
                : ''
            }
            <div class="edit-add-row">
              <input type="text" data-ie-new-step placeholder="${escapeHtml(t(lang, 'placeholderSubtask'))}" maxlength="200">
              <button type="button" class="secondary compact" data-ie-add-step>${escapeHtml(t(lang, 'actionAdd'))}</button>
            </div>
            <label class="check-field compact-check">
              <input type="checkbox" data-ie="subtasksAutoFinish" ${draft.subtasksAutoFinish ? 'checked' : ''}>
              <span>${escapeHtml(t(lang, 'fieldAutoFinish'))}<small>${escapeHtml(t(lang, 'fieldAutoFinishDesc'))}</small></span>
            </label>
            ${renderInlineEditActions(
              lang,
              err,
              task.subtasks?.length ? 'data-ie-clear="subtasks"' : '',
              t(lang, 'inlineClear'),
            )}
          </div>
        </div>
      `);
    } else if (task.subtasks?.length) {
      const done = task.subtasks.filter((s) => s.done).length;
      const pct = Math.round((done / task.subtasks.length) * 100);
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon(task.subtasksAutoFinish ? 'check-square' : 'list-checks', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoSubtasksTitle'))}</strong>
            <span class="info-sub ml-auto">${escapeHtml(t(lang, 'taskInfoSubtasksProgress', { completed: done, total: task.subtasks.length }))}</span>
            <button type="button" class="icon-button compact" data-ie-open="subtasks" data-ie-task="${escapeHtml(task.id)}" title="${escapeHtml(t(lang, 'actionEdit'))}">
              ${renderIcon('pencil', 'icon-xs')}
            </button>
          </div>
          <div class="progress-bar"><span style="width:${pct}%"></span></div>
          ${task.subtasksAutoFinish ? `<small class="info-sub">${escapeHtml(t(lang, 'taskInfoAutoFinishActive'))}</small>` : ''}
          <div class="info-subtasks-list">
            ${task.subtasks
              .map(
                (step, idx) => `
              <label class="info-step-row ${step.done ? 'is-done' : ''}">
                <input type="checkbox" data-info-step="${idx}" data-task-id="${escapeHtml(task.id)}" ${step.done ? 'checked' : ''} ${isCompleted ? 'disabled' : ''}>
                <span>${escapeHtml(step.text)}</span>
              </label>`,
              )
              .join('')}
          </div>
        </div>
      `);
    }

    // 5. History (always live interactive)
    sections.push(`
      <div class="info-card">
        <div class="info-card-head">
          ${renderIcon('history', 'icon-sm')}
          <strong>${escapeHtml(t(lang, 'taskInfoHistoryTitle'))}</strong>
          <span class="info-sub ml-auto">${(task.history || []).length}</span>
        </div>
        ${
          task.history?.length
            ? `<div class="info-history-list">
                ${task.history
                  .map((entry, idx) =>
                    editHistIdx === idx
                      ? `<div class="history-inline-edit">
                          <input type="text" data-info-hist-edit-input value="${escapeHtml(state.historyEditDraft || entry.text)}" maxlength="500">
                          <button type="button" class="primary compact" data-info-hist-save="${idx}">${escapeHtml(t(lang, 'actionSave'))}</button>
                          <button type="button" class="secondary compact" data-info-hist-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>
                        </div>`
                      : `<div class="history-entry-row">
                          <div class="record-text">
                            <small class="mono-sm">${escapeHtml(formatLocalTimestamp(entry.timestampUtc, offset))}</small>
                            <span>${escapeHtml(entry.text)}</span>
                          </div>
                          <div class="record-actions">
                            <button type="button" class="icon-button compact" data-info-hist-start-edit="${idx}" title="${escapeHtml(t(lang, 'actionEdit'))}">${renderIcon('pencil', 'icon-xs')}</button>
                            <button type="button" class="icon-button compact is-danger-hover" data-info-hist-delete="${idx}" title="${escapeHtml(t(lang, 'actionDelete'))}">${renderIcon('trash', 'icon-xs')}</button>
                          </div>
                        </div>`,
                  )
                  .join('')}
              </div>`
            : `<div class="info-sub">${escapeHtml(t(lang, 'taskInfoHistoryEmpty'))}</div>`
        }
        <div class="edit-add-row mt-8">
          <input type="text" data-info-hist-new placeholder="${escapeHtml(t(lang, 'taskInfoHistoryPlaceholder'))}" maxlength="500">
          <button type="button" class="secondary compact" data-info-hist-add>${escapeHtml(t(lang, 'taskInfoHistoryAdd'))}</button>
        </div>
      </div>
    `);

    // 6. Labels (direct 1-click toggle)
    sections.push(`
      <div class="info-card">
        <div class="info-card-head">
          ${renderIcon('tags', 'icon-sm')}
          <strong>${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}</strong>
          <span class="info-sub ml-auto">${taskLabels.length}</span>
        </div>
        ${
          sortedLabels.length
            ? `<div class="label-toggle-grid">
                ${sortedLabels
                  .map((lbl) => {
                    const active = (task.labels || []).includes(lbl.id);
                    return `
                      <div class="label-toggle-item ${active ? 'is-selected' : ''}">
                        <button type="button" class="label-toggle-btn" data-direct-toggle-label="${escapeHtml(lbl.id)}" data-task-id="${escapeHtml(task.id)}" aria-pressed="${active}">
                          <span class="dot" style="--label-color:${escapeHtml(lbl.color || '#00648b')}"></span>
                          <span>${escapeHtml(lbl.name)}</span>
                          ${active ? renderIcon('check', 'icon-xs') : ''}
                        </button>
                        <button type="button" class="label-toggle-hub" data-open-label-hub="${escapeHtml(lbl.id)}" title="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}" aria-label="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}">
                          ${renderIcon('info', 'icon-xs')}
                        </button>
                      </div>
                    `;
                  })
                  .join('')}
              </div>`
            : `<div class="info-sub">${escapeHtml(t(lang, 'inlineLabelsEmpty'))}</div>`
        }
      </div>
    `);

    // 7. Due
    if (editing === 'due') {
      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('calendar-days', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoDueTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            <label class="field">${escapeHtml(t(lang, 'fieldDue'))}
              <input type="datetime-local" data-ie="dueLocal" value="${escapeHtml(draft.dueLocal)}">
            </label>
            <label class="check-field compact-check">
              <input type="checkbox" data-ie="autoDue" ${draft.autoDue ? 'checked' : ''}>
              <span>${escapeHtml(t(lang, 'fieldDueAuto'))}<small>${escapeHtml(t(lang, 'fieldDueAutoDesc'))}</small></span>
            </label>
            <label class="field">${escapeHtml(t(lang, 'fieldDueNote'))}
              <textarea data-ie="dueNote" rows="2" placeholder="${escapeHtml(t(lang, 'placeholderDueNote'))}">${escapeHtml(draft.dueNote)}</textarea>
            </label>
            ${renderInlineEditActions(
              lang,
              err,
              task.dueAt ? 'data-ie-clear="due"' : '',
              t(lang, 'inlineClear'),
            )}
          </div>
        </div>
      `);
    } else if (task.dueAt) {
      const localTs = formatLocalTimestamp(task.dueAt, offset);
      const diff = Date.parse(task.dueAt) - state.nowMs;
      const dueMain = overdue
        ? t(lang, 'taskInfoDueOverdue', { timestamp: localTs })
        : t(lang, 'taskInfoDueAt', {
            timestamp: localTs,
            duration: formatRemainingDuration(diff, lang),
          });
      let dueStatus = '';
      if (!isCompleted) {
        const lw = workspace.config.dueLeadWindow;
        if (task.duePassive) dueStatus = t(lang, 'taskInfoDuePassive');
        else if (lw === 'off') dueStatus = t(lang, 'taskInfoDueLeadOff');
        else if (withinLead) dueStatus = t(lang, 'taskInfoDueAutoActive');
        else if (lw === 'at_due') dueStatus = t(lang, 'taskInfoDueAutoAtDue');
        else {
          const shortMap = {
            hours12: t(lang, 'leadShort12h'),
            hours24: t(lang, 'leadShort24h'),
            hours48: t(lang, 'leadShort48h'),
            days7: t(lang, 'leadShort7d'),
          };
          dueStatus = t(lang, 'taskInfoDueAutoScheduled', {
            window: shortMap[lw] || '24h',
          });
        }
      }
      const showAnchor =
        task.dueAnchor && !task.dueAnchor.startsWith(localTs);
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('calendar-days', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoDueTitle'))}</strong>
            ${editBtn('due')}
          </div>
          <div class="${overdue && !isCompleted ? 'text-danger' : withinLead && !isCompleted ? 'text-warning' : ''}">${escapeHtml(dueMain)}</div>
          ${dueStatus ? `<small class="info-sub">${escapeHtml(dueStatus)}</small>` : ''}
          ${showAnchor ? `<small class="info-sub mono-sm">${escapeHtml(t(lang, 'taskInfoDueAnchor', { anchor: task.dueAnchor }))}</small>` : ''}
          ${task.dueNote ? `<p class="info-note">${escapeHtml(task.dueNote)}</p>` : ''}
        </div>
      `);
    }

    // 8. Priority & Queue Placement (direct 1-click toggle)
    if (!isCompleted && (task.priority || currentMode === 'someday')) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('zap', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'inlinePlacementTitle'))}</strong>
          </div>
          <div class="segmented" role="group" aria-label="${escapeHtml(t(lang, 'inlinePlacementTitle'))}">
            <button type="button" data-direct-mode="queue" data-task-id="${escapeHtml(task.id)}" aria-pressed="${currentMode === 'queue'}">${escapeHtml(t(lang, 'modeQueue'))}</button>
            <button type="button" data-direct-mode="priority" data-task-id="${escapeHtml(task.id)}" aria-pressed="${currentMode === 'priority'}">${escapeHtml(t(lang, 'modePriority'))}</button>
            <button type="button" data-direct-mode="someday" data-task-id="${escapeHtml(task.id)}" aria-pressed="${currentMode === 'someday'}">${escapeHtml(t(lang, 'modeSomeday'))}</button>
          </div>
        </div>
      `);
    }

    // 9. Repeat
    if (editing === 'repeat') {
      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('repeat', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoRepeatTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            <div class="field-grid">
              <label class="field">${escapeHtml(t(lang, 'fieldRepeatEvery'))}
                <input type="number" min="1" max="3650" data-ie="repeatEvery" value="${escapeHtml(draft.repeatEvery)}">
              </label>
              <label class="field">${escapeHtml(t(lang, 'fieldRepeatUnit'))}
                <select data-ie="repeatUnit">
                  <option value="days" ${draft.repeatUnit === 'days' ? 'selected' : ''}>${escapeHtml(t(lang, 'unitDays'))}</option>
                  <option value="weeks" ${draft.repeatUnit === 'weeks' ? 'selected' : ''}>${escapeHtml(t(lang, 'unitWeeks'))}</option>
                  <option value="months" ${draft.repeatUnit === 'months' ? 'selected' : ''}>${escapeHtml(t(lang, 'unitMonths'))}</option>
                </select>
              </label>
            </div>
            ${
              task.dueAt
                ? `<label class="field">${escapeHtml(t(lang, 'fieldRepeatLead'))}
                    <input type="number" min="0" max="3650" data-ie="repeatLeadDays" value="${escapeHtml(draft.repeatLeadDays)}" placeholder="0">
                    <small class="field-hint">${escapeHtml(t(lang, 'hintRepeatLead'))}</small>
                  </label>`
                : `<small class="info-sub">${escapeHtml(t(lang, 'inlineRepeatLeadNeedsDue'))}</small>`
            }
            ${renderInlineEditActions(
              lang,
              err,
              task.repeat ? 'data-ie-clear="repeat"' : '',
              t(lang, 'inlineDisableRepeat'),
            )}
          </div>
        </div>
      `);
    } else if (task.repeat) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('repeat', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoRepeatTitle'))}</strong>
            ${editBtn('repeat')}
          </div>
          <div>${escapeHtml(formatRepeatPhrase(task.repeat.count, task.repeat.unit, lang))}</div>
          ${task.completions > 0 ? `<small class="info-sub">${escapeHtml(t(lang, task.completions === 1 ? 'taskInfoRepeatCompletionsSingular' : 'taskInfoRepeatCompletions', { count: task.completions }))}</small>` : ''}
          ${task.dueAt && task.repeat.leadDays > 0 ? `<small class="info-sub">${escapeHtml(t(lang, task.repeat.leadDays === 1 ? 'taskInfoRepeatLeadDaysSingular' : 'taskInfoRepeatLeadDays', { days: task.repeat.leadDays }))}</small>` : ''}
        </div>
      `);
    }

    // 10. Suspended
    if (editing === 'suspended') {
      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('pause-circle', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoSuspendedTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            <label class="field">${escapeHtml(t(lang, 'fieldSuspended'))}
              <select data-ie="suspendedMode">
                <option value="until" ${draft.suspendedMode === 'until' ? 'selected' : ''}>${escapeHtml(t(lang, 'optSuspendedUntil'))}</option>
                <option value="forever" ${draft.suspendedMode === 'forever' ? 'selected' : ''}>${escapeHtml(t(lang, 'optSuspendedForever'))}</option>
              </select>
            </label>
            ${
              draft.suspendedMode === 'until'
                ? `<label class="field">${escapeHtml(t(lang, 'fieldSuspendedUntil'))}
                    <input type="datetime-local" data-ie="suspendedLocal" value="${escapeHtml(draft.suspendedLocal)}">
                  </label>`
                : ''
            }
            <label class="field">${escapeHtml(t(lang, 'fieldSuspendedNote'))}
              <textarea data-ie="suspendedNote" rows="2" placeholder="${escapeHtml(t(lang, 'placeholderSuspendedNote'))}">${escapeHtml(draft.suspendedNote)}</textarea>
            </label>
            ${renderInlineEditActions(
              lang,
              err,
              suspendedActive ? 'data-ie-clear="suspended"' : '',
              t(lang, 'inlineResumeTask'),
            )}
          </div>
        </div>
      `);
    } else if (suspendedActive) {
      let suspVal = t(lang, 'taskInfoSuspendedForever');
      if (task.suspendedMode === 'until' && task.suspendedAt) {
        const diff = Date.parse(task.suspendedAt) - state.nowMs;
        suspVal = t(lang, 'taskInfoSuspendedUntil', {
          timestamp: formatLocalTimestamp(task.suspendedAt, offset),
          duration: formatRemainingDuration(diff, lang),
        });
      }
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('pause-circle', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoSuspendedTitle'))}</strong>
            ${editBtn('suspended')}
          </div>
          <div>${escapeHtml(suspVal)}</div>
          ${task.suspendedNote ? `<p class="info-note">${escapeHtml(task.suspendedNote)}</p>` : ''}
        </div>
      `);
    }

    // 11. Prerequisites
    if (editing === 'prereqs') {
      const candidates = workspace.tasks.filter(
        (cand) =>
          cand.id !== task.id &&
          (!cand.finishedAt || draft.prerequisites.includes(cand.id)),
      );
      const query = (draft.prereqQuery || '').trim().toLowerCase();
      const selectedPrereqs = candidates.filter((cand) =>
        draft.prerequisites.includes(cand.id),
      );
      const matchingUnselected = candidates.filter(
        (cand) =>
          !draft.prerequisites.includes(cand.id) &&
          (!query || cand.title.toLowerCase().includes(query)),
      );

      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('lock', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoBlockedByTitle'))}</strong>
            <span class="info-sub ml-auto">${draft.prerequisites.length}</span>
          </div>
          <div class="inline-edit-body">
            <small class="info-sub">${escapeHtml(t(lang, 'descPrereqs'))}</small>
            ${
              selectedPrereqs.length
                ? `<div class="edit-chips prereq-selected">
                    ${selectedPrereqs
                      .map(
                        (item) => `
                      <label class="edit-chip">
                        <input type="checkbox" data-ie-prereq="${escapeHtml(item.id)}" checked>
                        <span>${escapeHtml(item.title)}</span>
                      </label>`,
                      )
                      .join('')}
                  </div>`
                : ''
            }
            <label class="field">${escapeHtml(t(lang, 'fieldPrereqSearch'))}
              <input type="search" data-ie-prereq-search value="${escapeHtml(draft.prereqQuery || '')}" placeholder="${escapeHtml(t(lang, 'placeholderPrereqSearch'))}">
            </label>
            ${
              matchingUnselected.length
                ? `<div class="prereq-list inline-prereq-list">
                    ${matchingUnselected
                      .map((cand) => {
                        const cycle = wouldCreateDependencyCycle(
                          workspace,
                          task.id,
                          cand.id,
                        );
                        return `
                          <label class="prereq-row ${cycle ? 'is-disabled' : ''}">
                            <input type="checkbox" data-ie-prereq="${escapeHtml(cand.id)}" ${cycle ? 'disabled' : ''}>
                            <span>${escapeHtml(cand.title)}${cycle ? `<small>${escapeHtml(t(lang, 'prereqCycleHint'))}</small>` : ''}</span>
                          </label>
                        `;
                      })
                      .join('')}
                  </div>`
                : `<div class="info-sub">${escapeHtml(t(lang, 'prereqNoResults'))}</div>`
            }
            ${renderInlineEditActions(
              lang,
              err,
              task.blockedBy?.length ? 'data-ie-clear="prereqs"' : '',
              t(lang, 'inlineClear'),
            )}
          </div>
        </div>
      `);
    } else if (depEval && depEval.total > 0) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('lock', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoBlockedByTitle'))}</strong>
            ${editBtn('prereqs')}
          </div>
          <div>${escapeHtml(t(lang, 'taskInfoBlockedByProgress', { satisfied: depEval.satisfiedCount, total: depEval.total }))}</div>
          <ul class="info-simple-list">
            ${depEval.items
              .map(
                (dep) =>
                  `<li class="${dep.satisfied ? 'is-done' : ''}">${dep.satisfied ? '✓ ' : '○ '}${escapeHtml(dep.title)}</li>`,
              )
              .join('')}
          </ul>
        </div>
      `);
    }

    // 12. Activation Conditions
    if (editing === 'conditions') {
      const weekdays =
        window.TT2.i18n.strings[window.TT2.i18n.resolveLang(lang)].weekdays;
      const condModeSelect = (label, key) => `
        <label class="field">${escapeHtml(label)}
          <select data-ie="${key}">
            <option value="inherit" ${draft[key] === 'inherit' ? 'selected' : ''}>${escapeHtml(t(lang, 'condInherit'))}</option>
            <option value="any" ${draft[key] === 'any' ? 'selected' : ''}>${escapeHtml(t(lang, 'condAny'))}</option>
            <option value="custom" ${draft[key] === 'custom' ? 'selected' : ''}>${escapeHtml(t(lang, 'condCustom'))}</option>
          </select>
        </label>
      `;

      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('sliders', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoConditionsTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            ${
              suspendedActive
                ? `<div class="inline-warning-box">${renderIcon('alert-triangle', 'icon-sm')}<span>${escapeHtml(t(lang, 'suspendedDisablesConditions'))}</span></div>`
                : ''
            }
            <div class="${suspendedActive ? 'is-dimmed-disabled' : ''}">
              <label class="check-field compact-check">
                <input type="checkbox" data-ie="ignoreLabels" ${draft.ignoreLabels ? 'checked' : ''}>
                <span>${escapeHtml(t(lang, 'fieldIgnoreLabels'))}<small>${escapeHtml(t(lang, 'fieldIgnoreLabelsDesc'))}</small></span>
              </label>
              <div class="edit-divider"></div>
              ${condModeSelect(t(lang, 'condDays'), 'daysMode')}
              ${
                draft.daysMode === 'custom'
                  ? `<div class="day-pills">
                      ${weekdays
                        .map(
                          (day, i) => `
                        <label>
                          <input type="checkbox" data-ie-day="${i + 1}" ${draft.days.includes(i + 1) ? 'checked' : ''}>
                          <span>${day}</span>
                        </label>`,
                        )
                        .join('')}
                    </div>`
                  : ''
              }
              <div class="edit-divider"></div>
              ${condModeSelect(t(lang, 'condTimes'), 'timeMode')}
              ${
                draft.timeMode === 'custom'
                  ? `<div>
                      ${draft.times
                        .map(
                          (tw, idx) => `
                        <div class="edit-list-row">
                          <span>${escapeHtml(tw.start)} - ${escapeHtml(tw.end)}</span>
                          <button type="button" class="remove-item" data-ie-remove-time="${idx}">${escapeHtml(t(lang, 'actionRemove'))}</button>
                        </div>`,
                        )
                        .join('')}
                      <div class="field-grid">
                        <label class="field">${escapeHtml(t(lang, 'condFrom'))}<input type="time" data-ie-time-start></label>
                        <label class="field">${escapeHtml(t(lang, 'condTo'))}<input type="time" data-ie-time-end></label>
                      </div>
                      <button type="button" class="secondary compact" data-ie-add-time>${escapeHtml(t(lang, 'actionAddTime'))}</button>
                    </div>`
                  : ''
              }
              <div class="edit-divider"></div>
              ${condModeSelect(t(lang, 'condLocations'), 'placesMode')}
              ${
                draft.placesMode === 'custom'
                  ? `<div>
                      ${
                        workspace.locations.length
                          ? workspace.locations
                              .map(
                                (loc) => `
                            <label class="prereq-row">
                              <input type="checkbox" data-ie-place="${escapeHtml(loc.id)}" ${draft.locationIds.includes(loc.id) ? 'checked' : ''}>
                              <span>${escapeHtml(loc.name)}<small>${loc.radius} m</small></span>
                            </label>`,
                              )
                              .join('')
                          : `<div class="info-sub">${escapeHtml(t(lang, 'emptyLocations'))}</div>`
                      }
                    </div>`
                  : ''
              }
            </div>
            ${renderInlineEditActions(
              lang,
              err,
              hasCustomTaskConds ? 'data-ie-clear="conditions"' : '',
              t(lang, 'inlineClear'),
            )}
          </div>
        </div>
      `);
    } else if (hasConditions) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('sliders', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoConditionsTitle'))}</strong>
            ${
              condEval && condEval.rules.length > 0
                ? `<span class="pill-badge ${condEval.satisfied ? 'tone-success' : 'tone-warning'}">
                    ${escapeHtml(t(lang, condEval.satisfied ? 'taskInfoCondSatisfied' : 'taskInfoCondBlocked'))}
                  </span>`
                : ''
            }
            ${editBtn('conditions')}
          </div>
          ${
            condEval && condEval.rules.length > 0
              ? `<ul class="info-simple-list">
                  ${condEval.rules
                    .map(
                      (rule) =>
                        `<li>${rule.satisfied ? '✓ ' : '✕ '}${escapeHtml(formatConditionLine(rule, workspace.locations, lang))}</li>`,
                    )
                    .join('')}
                </ul>`
              : `<small class="info-sub">${escapeHtml(t(lang, 'fieldIgnoreLabels'))}</small>`
          }
        </div>
      `);
    }

    // 13. Compact "+ Add" & direct quick-toggle bar for unset fields
    const addChips = [];
    if (!task.note && editing !== 'note') {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ie-open="note" data-ie-task="${escapeHtml(task.id)}">${renderIcon('file-text', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddNote'))}</span></button>`,
      );
    }
    if (!task.links?.length && editing !== 'links') {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ie-open="links" data-ie-task="${escapeHtml(task.id)}">${renderIcon('link', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddLinks'))}</span></button>`,
      );
    }
    if (!task.subtasks?.length && editing !== 'subtasks') {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ie-open="subtasks" data-ie-task="${escapeHtml(task.id)}">${renderIcon('list-checks', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddSubtasks'))}</span></button>`,
      );
    }
    if (!task.dueAt && editing !== 'due') {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ie-open="due" data-ie-task="${escapeHtml(task.id)}">${renderIcon('calendar-days', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddDue'))}</span></button>`,
      );
    }
    if (!isCompleted && currentMode === 'queue') {
      addChips.push(
        `<button type="button" class="add-field-chip is-direct" data-direct-mode="priority" data-task-id="${escapeHtml(task.id)}">${renderIcon('zap', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddPriority'))}</span></button>`,
      );
      addChips.push(
        `<button type="button" class="add-field-chip is-direct" data-direct-mode="someday" data-task-id="${escapeHtml(task.id)}">${renderIcon('lightbulb', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddSomeday'))}</span></button>`,
      );
    }
    if (!task.repeat && editing !== 'repeat') {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ie-open="repeat" data-ie-task="${escapeHtml(task.id)}">${renderIcon('repeat', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddRepeat'))}</span></button>`,
      );
    }
    if (!suspendedActive && !isCompleted && editing !== 'suspended') {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ie-open="suspended" data-ie-task="${escapeHtml(task.id)}">${renderIcon('pause-circle', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddSuspend'))}</span></button>`,
      );
    }
    if ((!depEval || depEval.total === 0) && editing !== 'prereqs') {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ie-open="prereqs" data-ie-task="${escapeHtml(task.id)}">${renderIcon('lock', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddPrereqs'))}</span></button>`,
      );
    }
    if (!hasConditions && editing !== 'conditions') {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ie-open="conditions" data-ie-task="${escapeHtml(task.id)}">${renderIcon('sliders', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddConditions'))}</span></button>`,
      );
    }

    const confirmingDelete = state.inlineDeleteConfirmTaskId === task.id;

    return `
      <div class="task-slide-panel ${isAnimating ? '' : 'is-open'}" data-slide-panel="${escapeHtml(task.id)}" role="region" aria-label="${escapeHtml(t(lang, 'taskInfoTitle'))}">
        <div class="task-slide-inner">
          <div class="task-slide-meta-bar">
            <code class="mono-sm">${escapeHtml(t(lang, 'taskInfoIdLabel', { id: task.id }))}</code>
            <button type="button" class="icon-button compact" data-copy-id="${escapeHtml(task.id)}" title="${escapeHtml(t(lang, 'actionCopy'))}">
              ${renderIcon('copy', 'icon-xs')}
            </button>
            ${
              confirmingDelete
                ? `<div class="inline-delete-confirm ml-auto">
                    <span>${escapeHtml(t(lang, 'inlineDeleteConfirm'))}</span>
                    <button type="button" class="secondary compact" data-inline-del-no>${escapeHtml(t(lang, 'actionKeep'))}</button>
                    <button type="button" class="danger compact" data-inline-del-yes="${escapeHtml(task.id)}">${escapeHtml(t(lang, 'actionConfirmDelete'))}</button>
                  </div>`
                : `<button type="button" class="icon-button compact is-danger-hover ml-auto" data-inline-del-ask="${escapeHtml(task.id)}" title="${escapeHtml(t(lang, 'actionDelete'))}" aria-label="${escapeHtml(t(lang, 'actionDelete'))}">
                    ${renderIcon('trash', 'icon-xs')}
                  </button>`
            }
          </div>
          <div class="task-slide-sections">
            ${sections.join('')}
          </div>
          ${
            addChips.length
              ? `<div class="task-add-fields-bar">${addChips.join('')}</div>`
              : ''
          }
        </div>
      </div>
    `;
  }

  function renderTaskCard(task, tierIdx, state, workspace, evalRes, showTierBadge = false) {
    const lang = state.lang;
    const offset = resolveOffsetMinutes(workspace.config);
    const isCompleted = Boolean(task.finishedAt);
    const isExpanded = state.expandedTaskId === task.id;
    const isAnimating = state.justExpandedTaskId === task.id;
    const canDowngrade = !isCompleted && tierIdx <= 2;
    const isEditingTitle =
      isExpanded &&
      state.inlineEdit?.taskId === task.id &&
      state.inlineEdit?.section === 'title';

    let metadataHtml = '';
    if (!isExpanded) {
      const labelsById = new Map(workspace.labels.map((l) => [l.id, l]));
      const taskLabels = (task.labels || [])
        .map((id) => labelsById.get(id))
        .filter(Boolean);

      const overdue = isTaskOverdue(task, state.nowMs);
      const withinLead = isTaskWithinDueLeadWindow(
        task,
        state.nowMs,
        workspace.config.dueLeadWindow,
      );
      const suspendedActive = isTaskSuspendedActive(task, state.nowMs);
      const depEval = evalRes.dependencyDetailsByTask.get(task.id);
      const condEval = evalRes.conditionDetailsByTask.get(task.id);

      const badges = [];

      if (showTierBadge) {
        badges.push(
          `<span class="meta-pill tone-soft">${renderIcon(TIER_ICONS[tierIdx], 'icon-xs')}${escapeHtml(tierName(lang, tierIdx))}</span>`,
        );
      }

      if (task.dueAt) {
        const dateStr = formatLocalDate(task.dueAt, offset);
        const dueTone = isCompleted
          ? ''
          : overdue
            ? 'tone-danger'
            : withinLead
              ? 'tone-warning'
              : '';
        const dueText =
          overdue && !isCompleted
            ? t(lang, 'badgeOverduePrefix', { date: dateStr })
            : t(lang, 'badgeDuePrefix', { date: dateStr });
        badges.push(
          `<button type="button" class="meta-pill is-interactive ${dueTone}" data-toggle-task="${escapeHtml(task.id)}">${renderIcon('calendar-days', 'icon-xs')}${escapeHtml(dueText)}</button>`,
        );
      }

      if (task.priority && !isCompleted) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive tone-accent" data-toggle-task="${escapeHtml(task.id)}">${renderIcon('zap', 'icon-xs')}${escapeHtml(t(lang, 'badgePriority'))}</button>`,
        );
      }

      if (suspendedActive) {
        const suspText =
          task.suspendedMode === 'forever'
            ? t(lang, 'badgeSuspendedForever')
            : t(lang, 'badgeSuspendedUntil', {
                date: formatLocalDate(task.suspendedAt, offset),
              });
        badges.push(
          `<button type="button" class="meta-pill is-interactive tone-warning" data-toggle-task="${escapeHtml(task.id)}">${renderIcon('pause-circle', 'icon-xs')}${escapeHtml(suspText)}</button>`,
        );
      }

      if (depEval && !depEval.satisfied) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive tone-warning" data-toggle-task="${escapeHtml(task.id)}">${renderIcon('lock', 'icon-xs')}${escapeHtml(t(lang, 'badgeBlockedBy', { done: depEval.satisfiedCount, total: depEval.total }))}</button>`,
        );
      }

      if (condEval && condEval.rules.length > 0) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive ${condEval.satisfied ? '' : 'tone-warning'}" data-toggle-task="${escapeHtml(task.id)}">${renderIcon('sliders', 'icon-xs')}${escapeHtml(t(lang, 'badgeConditions'))}</button>`,
        );
      }

      if (task.repeat) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive" data-toggle-task="${escapeHtml(task.id)}">${renderIcon('repeat', 'icon-xs')}${escapeHtml(formatRepeatSummary(task, lang))}</button>`,
        );
      }

      if (task.subtasks?.length) {
        const doneCount = task.subtasks.filter((s) => s.done).length;
        badges.push(
          `<button type="button" class="meta-pill is-interactive" data-toggle-task="${escapeHtml(task.id)}">${renderIcon(task.subtasksAutoFinish ? 'check-square' : 'list-checks', 'icon-xs')}${escapeHtml(t(lang, 'badgeSteps', { done: doneCount, total: task.subtasks.length }))}</button>`,
        );
      }

      if (task.note) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive" data-toggle-task="${escapeHtml(task.id)}">${renderIcon('file-text', 'icon-xs')}${escapeHtml(t(lang, 'badgeNote'))}</button>`,
        );
      }

      if (task.links?.length) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive" data-toggle-task="${escapeHtml(task.id)}">${renderIcon('link', 'icon-xs')}${escapeHtml(t(lang, task.links.length === 1 ? 'badgeLinkSingular' : 'badgeLinks', { count: task.links.length }))}</button>`,
        );
      }

      if (task.history?.length) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive" data-toggle-task="${escapeHtml(task.id)}">${renderIcon('history', 'icon-xs')}${escapeHtml(t(lang, 'badgeHistory', { count: task.history.length }))}</button>`,
        );
      }

      if (taskLabels.length || badges.length) {
        metadataHtml = `<div class="metadata">
          ${taskLabels
            .map(
              (lbl) => `
            <button type="button" class="tag-chip" data-open-label-hub="${escapeHtml(lbl.id)}" title="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}">
              <span class="dot" style="--label-color:${escapeHtml(lbl.color || '#00648b')}"></span>
              <span>${escapeHtml(lbl.name)}</span>
            </button>`,
            )
            .join('')}
          ${badges.join('')}
        </div>`;
      }
    }

    return `
      <article class="task ${isCompleted ? 'is-completed' : ''} ${isExpanded ? 'is-expanded' : ''}">
        <div class="task-top">
          <button type="button" class="complete" data-complete="${escapeHtml(task.id)}" aria-label="${escapeHtml(task.title)} ${escapeHtml(t(lang, isCompleted ? 'actionRestore' : 'actionComplete'))}">
            <span class="circle ${isCompleted ? 'is-checked' : ''}">${isCompleted ? renderIcon('check', 'icon-xs') : ''}</span>
          </button>
          ${
            isEditingTitle
              ? `<div class="inline-title-edit">
                  <div class="inline-title-edit-row">
                    <input type="text" data-ie="title" value="${escapeHtml(state.inlineEdit.draft.title)}" maxlength="300" aria-label="${escapeHtml(t(lang, 'inlineEditTitle'))}">
                    <button type="button" class="primary compact" data-ie-save>${escapeHtml(t(lang, 'actionSave'))}</button>
                    <button type="button" class="secondary compact" data-ie-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>
                  </div>
                  ${state.inlineEdit.error ? `<div class="edit-error inline-edit-error" role="status">${escapeHtml(state.inlineEdit.error)}</div>` : ''}
                </div>`
              : `<button type="button" class="task-title" data-toggle-task="${escapeHtml(task.id)}" aria-expanded="${isExpanded}">
                  ${escapeHtml(task.title)}
                </button>
                <div class="task-actions">
                  ${
                    isExpanded
                      ? `<button type="button" class="icon-button compact" data-ie-open="title" data-ie-task="${escapeHtml(task.id)}" title="${escapeHtml(t(lang, 'inlineEditTitle'))}" aria-label="${escapeHtml(t(lang, 'inlineEditTitle'))}">
                          ${renderIcon('pencil', 'icon-sm')}
                        </button>`
                      : ''
                  }
                  ${
                    canDowngrade
                      ? `<button type="button" class="icon-button compact" data-downgrade="${escapeHtml(task.id)}" title="${escapeHtml(t(lang, 'actionDowngrade'))}" aria-label="${escapeHtml(t(lang, 'actionDowngrade'))}">
                          ${renderIcon('chevron-right', 'icon-sm')}
                        </button>`
                      : ''
                  }
                </div>`
          }
        </div>
        ${metadataHtml}
        ${isExpanded ? renderTaskSlidePanel(task, state, workspace, evalRes, isAnimating) : ''}
      </article>
    `;
  }

  function renderQuickComposer(state, workspace) {
    const lang = state.lang;
    const draft = state.draft;
    const modeHintText =
      draft.mode === 'priority'
        ? t(lang, 'hintPriority')
        : draft.mode === 'someday'
          ? t(lang, 'hintSomeday')
          : t(lang, 'hintQueue');
    const sortedLabels = [...workspace.labels].sort((a, b) =>
      a.name.localeCompare(b.name),
    );

    return `
      <div class="composer ${state.mobileQuickAddOpen ? 'mobile-expanded' : ''}">
        <button type="button" class="mobile-add-trigger primary" data-toggle-mobile-add>
          ${renderIcon('plus')}
          <span>${escapeHtml(t(lang, 'quickAddNewMobile'))}</span>
        </button>

        <div class="composer-box">
          <form data-form="quick-task">
            <div class="entry-row">
              <input name="title" data-draft="title" value="${escapeHtml(draft.title)}" aria-label="${escapeHtml(t(lang, 'quickAddPlaceholder'))}" placeholder="${escapeHtml(t(lang, 'quickAddPlaceholder'))}" autocomplete="off" required>
              <div class="entry-options">
                <select name="mode" data-draft="mode" aria-label="${escapeHtml(t(lang, 'fieldPlacement'))}">
                  <option value="queue" ${draft.mode === 'queue' ? 'selected' : ''}>${escapeHtml(t(lang, 'modeQueue'))}</option>
                  <option value="priority" ${draft.mode === 'priority' ? 'selected' : ''}>${escapeHtml(t(lang, 'modePriority'))}</option>
                  <option value="someday" ${draft.mode === 'someday' ? 'selected' : ''}>${escapeHtml(t(lang, 'modeSomeday'))}</option>
                </select>
                <button type="button" data-save class="primary">
                  ${renderIcon('plus', 'icon-sm')}<span>${escapeHtml(t(lang, 'actionAdd'))}</span>
                </button>
                <button type="button" class="icon-button compact mobile-close-composer" data-toggle-mobile-add aria-label="${escapeHtml(t(lang, 'actionCancel'))}">
                  ${renderIcon('x', 'icon-sm')}
                </button>
              </div>
            </div>

            <div class="composer-footer-row">
              <details class="label-picker">
                <summary>${renderIcon('tags', 'icon-sm')}<span data-label-summary>${escapeHtml(t(lang, 'quickAddLabelsSummary', { count: draft.labels.length }))}</span></summary>
                <div class="label-checks">
                  ${sortedLabels
                    .map(
                      (label) => `
                    <label>
                      <input type="checkbox" data-draft-label="${escapeHtml(label.id)}" ${draft.labels.includes(label.id) ? 'checked' : ''}>
                      <span class="dot" style="--label-color:${escapeHtml(label.color || '#00648b')}"></span>
                      <span>${escapeHtml(label.name)}</span>
                    </label>`,
                    )
                    .join('')}
                </div>
              </details>
              <button type="button" class="text-button" data-quick-add-expand>
                ${renderIcon('sliders', 'icon-xs')} ${escapeHtml(t(lang, 'quickAddAdvanced'))}
              </button>
            </div>
          </form>
          <div class="composer-hint" data-mode-hint>${escapeHtml(modeHintText)}</div>
        </div>
      </div>
    `;
  }

  function renderTaskView(state, workspace, evalRes) {
    const lang = state.lang;

    if (state.searchOpen) {
      const query = state.searchQuery.trim().toLowerCase();
      const matches = [];
      for (let tierIdx = 0; tierIdx < 6; tierIdx += 1) {
        for (const task of evalRes.tiers[tierIdx]) {
          if (!query || task.title.toLowerCase().includes(query)) {
            matches.push({ task, tierIdx });
          }
        }
      }
      return `
        <div class="heading">
          <div>
            <h2>${escapeHtml(t(lang, 'searchTitle'))}</h2>
            <div class="subtitle">${escapeHtml(t(lang, 'searchSubtitle'))}</div>
          </div>
          <span class="limit">${matches.length}</span>
        </div>
        <div class="tasks">
          ${
            matches.length
              ? matches
                  .map(({ task, tierIdx }) =>
                    renderTaskCard(task, tierIdx, state, workspace, evalRes, true),
                  )
                  .join('')
              : `<div class="empty">${escapeHtml(t(lang, 'searchEmpty'))}</div>`
          }
        </div>
        ${renderNotice(state)}
      `;
    }

    const queue = evalRes.tiers[state.tier];
    const limitSuffix =
      state.tier === 0 ? ' / 3' : state.tier === 1 ? ' / 5' : '';

    return `
      <label class="tier-mobile">
        <span>${escapeHtml(t(lang, 'viewLabel'))}</span>
        <select data-tier-select>
          ${[0, 1, 2, 3, 4, 5]
            .map(
              (idx) =>
                `<option value="${idx}" ${state.tier === idx ? 'selected' : ''}>${escapeHtml(tierName(lang, idx))} · ${evalRes.tiers[idx].length}</option>`,
            )
            .join('')}
        </select>
      </label>

      <div class="heading">
        <div>
          <h2>${escapeHtml(tierName(lang, state.tier))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, `tier${state.tier}Sub`))}</div>
        </div>
        <span class="limit">${queue.length}${limitSuffix}</span>
      </div>

      <div class="tasks">
        ${
          queue.length
            ? queue
                .map((task) =>
                  renderTaskCard(task, state.tier, state, workspace, evalRes, false),
                )
                .join('')
            : `<div class="empty">${escapeHtml(t(lang, `emptyTier${state.tier}`))}</div>`
        }
      </div>

      ${renderNotice(state)}
      ${renderQuickComposer(state, workspace)}
    `;
  }

  function renderManagerView(kind, state, workspace, evalRes) {
    const lang = state.lang;
    const isLabels = kind === 'labels';
    const items = [
      ...(isLabels ? workspace.labels : workspace.locations),
    ].sort((a, b) => a.name.localeCompare(b.name));

    return `
      <button type="button" class="back" data-view="tasks">${renderIcon('arrow-left', 'icon-sm')}${escapeHtml(t(lang, 'actionBackTasks'))}</button>
      <div class="heading">
        <div>
          <h2>${escapeHtml(t(lang, isLabels ? 'sectionLabels' : 'sectionLocations'))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, isLabels ? 'labelsManagerSub' : 'locationsManagerSub'))}</div>
        </div>
        <button type="button" class="primary" data-new="${kind}">${renderIcon('plus', 'icon-sm')}${escapeHtml(t(lang, 'actionNew'))}</button>
      </div>

      <form class="quick-create-card" data-form="quick-create-${kind}">
        <input name="name" placeholder="${escapeHtml(t(lang, isLabels ? 'placeholderQuickLabel' : 'placeholderQuickLocation'))}" autocomplete="off" required>
        <button type="submit" class="secondary">${renderIcon('plus', 'icon-sm')}${escapeHtml(t(lang, 'actionAdd'))}</button>
      </form>

      ${renderNotice(state)}

      <div class="manager-list">
        ${
          items.length
            ? items
                .map((item) => {
                  const openCount = isLabels
                    ? evalRes.openCountByLabel.get(item.id) || 0
                    : evalRes.openCountByLocation.get(item.id) || 0;
                  const confirming = state.managerDeleteConfirm === item.id;
                  return `
                    <div class="manager-card">
                      <div class="manager-row">
                        <button type="button" class="manager-row-main" data-edit-${isLabels ? 'label' : 'location'}="${escapeHtml(item.id)}">
                          ${
                            isLabels
                              ? `<span class="dot dot-lg" style="--label-color:${escapeHtml(item.color || '#00648b')}"></span>`
                              : renderIcon('map-pin')
                          }
                          <span class="manager-row-text">
                            <strong>${escapeHtml(item.name)}</strong>
                            <small>${
                              isLabels
                                ? `${escapeHtml(t(lang, item.scoped ? 'scopedQueue' : 'globalContext'))}${item.links?.length ? ` · ${item.links.length} Links` : ''}`
                                : `${escapeHtml(item.sourceType.toUpperCase())} · ${Number(item.latitude).toFixed(4)}, ${Number(item.longitude).toFixed(4)} · ${item.radius} m`
                            }</small>
                          </span>
                          <span class="pill-badge">${escapeHtml(t(lang, 'openTasksCount', { count: openCount }))}</span>
                        </button>
                        <div class="manager-row-actions">
                          ${
                            isLabels
                              ? `<button type="button" class="icon-button compact" data-open-label-hub="${escapeHtml(item.id)}" title="${escapeHtml(t(lang, 'labelHub'))}">${renderIcon('info', 'icon-sm')}</button>`
                              : ''
                          }
                          <button type="button" class="icon-button compact" data-edit-${isLabels ? 'label' : 'location'}="${escapeHtml(item.id)}" title="${escapeHtml(t(lang, 'actionEdit'))}">${renderIcon('pencil', 'icon-sm')}</button>
                          <button type="button" class="icon-button compact is-danger-hover" data-manager-ask-delete="${escapeHtml(item.id)}" title="${escapeHtml(t(lang, 'actionDelete'))}">${renderIcon('trash', 'icon-sm')}</button>
                        </div>
                      </div>
                      ${
                        confirming
                          ? `<div class="inline-confirm-bar">
                              <span>${escapeHtml(t(lang, isLabels ? 'deleteLabelQuestion' : 'deleteLocationQuestion', { name: item.name }))}</span>
                              <div class="inline-confirm-actions">
                                <button type="button" class="secondary compact" data-manager-cancel-delete>${escapeHtml(t(lang, 'actionCancel'))}</button>
                                <button type="button" class="danger compact" data-manager-confirm-delete="${kind}:${escapeHtml(item.id)}">${escapeHtml(t(lang, 'actionDelete'))}</button>
                              </div>
                            </div>`
                          : ''
                      }
                    </div>
                  `;
                })
                .join('')
            : `<div class="empty">${escapeHtml(t(lang, isLabels ? 'emptyLabels' : 'emptyLocations'))}</div>`
        }
      </div>
    `;
  }

  function renderLinksEditorCard(links, editState, lang, prefix) {
    const editingIdx = editState.editingLinkIndex;
    return `
      <section class="edit-card">
        <h3>${renderIcon('link', 'icon-sm')} ${escapeHtml(t(lang, 'cardLinks'))} <span class="edit-counter">${links.length} / 20</span></h3>
        ${
          links.length
            ? links
                .map(
                  (link, index) => `
                <div class="record ${editingIdx === index ? 'is-editing' : ''}">
                  <div class="record-text">
                    <strong>${escapeHtml(link.title)}</strong>
                    <span class="mono-sm">${escapeHtml(link.uri)}</span>
                  </div>
                  <div class="record-actions">
                    <button type="button" class="icon-button compact" data-${prefix}-link-up="${index}" ${index === 0 ? 'disabled' : ''} title="${escapeHtml(t(lang, 'actionUp'))}">${renderIcon('arrow-up', 'icon-xs')}</button>
                    <button type="button" class="icon-button compact" data-${prefix}-link-down="${index}" ${index === links.length - 1 ? 'disabled' : ''} title="${escapeHtml(t(lang, 'actionDown'))}">${renderIcon('arrow-down', 'icon-xs')}</button>
                    <button type="button" class="icon-button compact" data-open-uri="${escapeHtml(link.uri)}" title="${escapeHtml(t(lang, 'actionOpen'))}">${renderIcon('external-link', 'icon-xs')}</button>
                    <button type="button" class="icon-button compact" data-${prefix}-link-edit="${index}" title="${escapeHtml(t(lang, 'actionEdit'))}">${renderIcon('pencil', 'icon-xs')}</button>
                    <button type="button" class="icon-button compact is-danger-hover" data-${prefix}-link-remove="${index}" title="${escapeHtml(t(lang, 'actionRemove'))}">${renderIcon('trash', 'icon-xs')}</button>
                  </div>
                </div>`,
                )
                .join('')
            : `<div class="edit-empty">${escapeHtml(t(lang, 'emptyLinks'))}</div>`
        }
        <label class="field">${escapeHtml(t(lang, 'fieldLinkTitle'))}
          <input data-${prefix}-link-title value="${escapeHtml(editState.linkTitleDraft || '')}" placeholder="${escapeHtml(t(lang, 'placeholderLinkTitle'))}">
        </label>
        <label class="field">${escapeHtml(t(lang, 'fieldLinkUri'))}
          <input data-${prefix}-link-uri value="${escapeHtml(editState.linkUriDraft || '')}" placeholder="${escapeHtml(t(lang, 'placeholderLinkUri'))}">
        </label>
        <div class="inline-btn-row">
          <button type="button" class="secondary" data-${prefix}-link-submit>${escapeHtml(t(lang, editingIdx !== null && editingIdx !== undefined ? 'actionSaveLink' : 'actionAddLink'))}</button>
          ${
            editingIdx !== null && editingIdx !== undefined
              ? `<button type="button" class="text-button" data-${prefix}-link-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>`
              : ''
          }
        </div>
      </section>
    `;
  }

  function renderLabelEditor(state, workspace) {
    const lang = state.lang;
    const item = state.labelEdit;
    const weekdays = window.TT2.i18n.strings[window.TT2.i18n.resolveLang(lang)].weekdays;

    return `
      <button type="button" class="back" data-view="labels">${renderIcon('arrow-left', 'icon-sm')}${escapeHtml(t(lang, 'actionBackLabels'))}</button>
      <div class="heading">
        <div>
          <h2>${escapeHtml(t(lang, item.id ? 'labelEditorEdit' : 'labelEditorNew'))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, 'labelEditorSub'))}</div>
        </div>
      </div>

      <form class="task-editor" data-form="label-editor">
        <div class="edit-grid">
          <div class="edit-column">
            <section class="edit-card">
              <h3>${escapeHtml(t(lang, 'sectionLabels'))}</h3>
              <label class="field">${escapeHtml(t(lang, 'fieldName'))}
                <input data-le="name" value="${escapeHtml(item.name)}" required maxlength="120">
              </label>
              <label class="field">${escapeHtml(t(lang, 'fieldNote'))}
                <textarea data-le="note" rows="3">${escapeHtml(item.note)}</textarea>
              </label>
              <label class="check-field">
                <input type="checkbox" data-le="scoped" ${item.scoped ? 'checked' : ''}>
                <span>${escapeHtml(t(lang, 'labelScopedTitle'))}<small>${escapeHtml(t(lang, 'labelScopedDesc'))}</small></span>
              </label>
            </section>

            <section class="edit-card">
              <h3>${renderIcon('palette', 'icon-sm')} ${escapeHtml(t(lang, 'fieldColorHex'))}</h3>
              <div class="color-input-row">
                <span class="color-swatch-preview" style="background:${escapeHtml(item.color || '#2196F3')}"></span>
                <input data-le="color" value="${escapeHtml(item.color)}" placeholder="#2196F3" maxlength="7">
                <button type="button" class="secondary" data-open-color-picker>${renderIcon('palette', 'icon-sm')}${escapeHtml(t(lang, 'actionCustomColor'))}</button>
              </div>
              <div class="color-presets">
                ${LABEL_COLOR_PRESETS.map(
                  (hex) => `
                  <button type="button" class="color-preset-chip ${String(item.color).toUpperCase() === hex ? 'is-selected' : ''}" data-le-preset="${hex}">
                    <span class="dot" style="--label-color:${hex}"></span>
                    <span>${hex}</span>
                  </button>`,
                ).join('')}
              </div>
            </section>

            ${renderLinksEditorCard(item.links, item, lang, 'le')}
          </div>

          <div class="edit-column">
            <section class="edit-card">
              <h3>${renderIcon('sliders', 'icon-sm')} ${escapeHtml(t(lang, 'cardConditions'))}</h3>
              <p class="edit-description">${escapeHtml(t(lang, 'descLabelConditions'))}</p>

              <div class="field-label-sm">${escapeHtml(t(lang, 'condDays'))}</div>
              <div class="day-pills">
                ${weekdays
                  .map(
                    (day, i) => `
                  <label>
                    <input type="checkbox" data-le-day="${i + 1}" ${item.conditions.days.includes(i + 1) ? 'checked' : ''}>
                    <span>${day}</span>
                  </label>`,
                  )
                  .join('')}
              </div>

              <div class="edit-divider"></div>

              <div class="field-label-sm">${escapeHtml(t(lang, 'condTimes'))}</div>
              ${item.conditions.times
                .map(
                  (tw, index) => `
                <div class="edit-list-row">
                  <span>${escapeHtml(tw.start)} – ${escapeHtml(tw.end)}</span>
                  <button type="button" class="remove-item" data-le-remove-time="${index}">${escapeHtml(t(lang, 'actionRemove'))}</button>
                </div>`,
                )
                .join('')}
              <div class="field-grid">
                <label class="field">${escapeHtml(t(lang, 'condFrom'))}<input type="time" data-le-time-start></label>
                <label class="field">${escapeHtml(t(lang, 'condTo'))}<input type="time" data-le-time-end></label>
              </div>
              <button type="button" class="secondary" data-le-add-time>${escapeHtml(t(lang, 'actionAddTime'))}</button>

              <div class="edit-divider"></div>

              <div class="field-label-sm">${escapeHtml(t(lang, 'condLocations'))}</div>
              ${
                workspace.locations.length
                  ? workspace.locations
                      .map(
                        (loc) => `
                    <label class="prereq-row">
                      <input type="checkbox" data-le-place="${escapeHtml(loc.id)}" ${item.conditions.locationIds.includes(loc.id) ? 'checked' : ''}>
                      <span>${escapeHtml(loc.name)}<small>${loc.radius} m</small></span>
                    </label>`,
                      )
                      .join('')
                  : `<div class="edit-empty">${escapeHtml(t(lang, 'emptyLocations'))}</div>`
              }
            </section>
          </div>
        </div>

        <div class="edit-error" role="status">${escapeHtml(state.editorError)}</div>

        <div class="task-editor-actions">
          <span></span>
          <div>
            <button type="button" class="secondary" data-view="labels">${escapeHtml(t(lang, 'actionCancel'))}</button>
            <button type="button" class="primary" data-save-label>${escapeHtml(t(lang, 'actionSave'))}</button>
          </div>
        </div>
      </form>
    `;
  }

  function renderLocationEditor(state) {
    const lang = state.lang;
    const item = state.locationEdit;
    const isGps = item.sourceType === 'gps';

    return `
      <button type="button" class="back" data-view="locations">${renderIcon('arrow-left', 'icon-sm')}${escapeHtml(t(lang, 'actionBackLocations'))}</button>
      <div class="heading">
        <div>
          <h2>${escapeHtml(t(lang, item.id ? 'locationEditorEdit' : 'locationEditorNew'))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, 'locationEditorSub'))}</div>
        </div>
      </div>

      <form class="task-editor" data-form="location-editor">
        <div class="edit-grid equal">
          <section class="edit-card">
            <h3>${renderIcon('map-pin', 'icon-sm')} ${escapeHtml(t(lang, 'sectionLocations'))}</h3>
            <label class="field">${escapeHtml(t(lang, 'fieldName'))}
              <input data-loce="name" value="${escapeHtml(item.name)}" required maxlength="120">
            </label>
            <label class="field">${escapeHtml(t(lang, 'fieldNote'))}
              <textarea data-loce="note" rows="4">${escapeHtml(item.note)}</textarea>
            </label>
          </section>

          <section class="edit-card">
            <h3>${renderIcon('locate', 'icon-sm')} ${escapeHtml(t(lang, 'fieldSourceType'))}</h3>
            <div class="field-grid">
              <label class="field">${escapeHtml(t(lang, 'fieldSourceType'))}
                <select data-loce="sourceType">
                  <option value="gps" ${item.sourceType === 'gps' ? 'selected' : ''}>${escapeHtml(t(lang, 'sourceGps'))}</option>
                  <option value="address" ${item.sourceType === 'address' ? 'selected' : ''}>${escapeHtml(t(lang, 'sourceAddress'))}</option>
                  <option value="plusCode" ${item.sourceType === 'plusCode' ? 'selected' : ''}>${escapeHtml(t(lang, 'sourcePlusCode'))}</option>
                </select>
              </label>
              <label class="field">${escapeHtml(t(lang, 'fieldRadius'))}
                <input data-loce="radiusText" value="${escapeHtml(item.radiusText)}" placeholder="150m">
              </label>
            </div>

            ${
              !isGps
                ? `<label class="field">${escapeHtml(t(lang, item.sourceType === 'address' ? 'sourceAddress' : 'sourcePlusCode'))}
                    <input data-loce="source" value="${escapeHtml(item.source)}" placeholder="${escapeHtml(t(lang, item.sourceType === 'address' ? 'placeholderAddress' : 'placeholderPlusCode'))}">
                  </label>`
                : ''
            }

            <div class="field-grid">
              <label class="field">${escapeHtml(t(lang, 'fieldLat'))}
                <input data-loce="latitude" type="number" step="any" min="-90" max="90" value="${escapeHtml(item.latitude)}" ${!isGps ? 'readonly' : ''}>
              </label>
              <label class="field">${escapeHtml(t(lang, 'fieldLon'))}
                <input data-loce="longitude" type="number" step="any" min="-180" max="180" value="${escapeHtml(item.longitude)}" ${!isGps ? 'readonly' : ''}>
              </label>
            </div>

            <div class="inline-btn-row">
              <button type="button" class="secondary" data-loce-use-gps ${!isGps ? 'disabled' : ''}>
                ${renderIcon('locate', 'icon-sm')}${escapeHtml(t(lang, 'actionUseGps'))}
              </button>
              <button type="button" class="secondary" data-loce-resolve ${isGps ? 'disabled' : ''}>
                ${renderIcon('search', 'icon-sm')}${escapeHtml(t(lang, 'actionResolveSource'))}
              </button>
            </div>
          </section>
        </div>

        <div class="edit-error" role="status">${escapeHtml(state.editorError)}</div>

        <div class="task-editor-actions">
          <span></span>
          <div>
            <button type="button" class="secondary" data-view="locations">${escapeHtml(t(lang, 'actionCancel'))}</button>
            <button type="button" class="primary" data-save-location>${escapeHtml(t(lang, 'actionSave'))}</button>
          </div>
        </div>
      </form>
    `;
  }

  window.TT2.viewsCore = {
    TIER_ICONS,
    tierName,
    renderChrome,
    renderSidebar,
    renderBanners,
    renderFullFileReadError,
    renderNotice,
    renderTaskView,
    renderManagerView,
    renderLabelEditor,
    renderLocationEditor,
  };
})();
