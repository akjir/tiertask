(() => {
  window.TT2 = window.TT2 || {};
  const { escapeHtml, renderIcon, renderAppLogo } = window.TT2;
  const {
    t,
    formatLocalDate,
    formatLocalTimestamp,
    formatLocalDatetimeInput,
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
          ${renderAppLogo()}
          <span>TierTask</span>
          ${state.isDevBuild ? `<span class="dev-badge">${escapeHtml(t(lang, 'devBadgeLabel'))}</span>` : ''}
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

  function renderSidebarSectionHeader({
    kind,
    title,
    count,
    collapsed,
    filterOpen,
    manageActive,
    filterLabel,
    manageLabel,
    collapseLabel,
    expandLabel,
    activeDotHtml = '',
  }) {
    const toggleLabel = collapsed ? expandLabel : collapseLabel;
    return `
      <div class="section-head">
        <span class="section-head-title">
          <span class="eyebrow">${escapeHtml(title)}</span>
          ${collapsed ? activeDotHtml : ''}
          ${collapsed ? `<span class="section-head-count">${count}</span>` : ''}
        </span>
        <div class="section-head-actions">
          <button
            type="button"
            class="icon-button section-head-btn ${filterOpen ? 'is-active' : ''}"
            data-toggle-sidebar-filter="${kind}"
            aria-pressed="${filterOpen}"
            title="${escapeHtml(filterLabel)}"
            aria-label="${escapeHtml(filterLabel)}"
          >${renderIcon('filter', 'icon-xs')}</button>
          <button
            type="button"
            class="icon-button section-head-btn ${manageActive ? 'is-active' : ''}"
            data-view="${kind}"
            ${manageActive ? 'aria-current="page"' : ''}
            title="${escapeHtml(manageLabel)}"
            aria-label="${escapeHtml(manageLabel)}"
          >${renderIcon('pencil', 'icon-xs')}</button>
          <button
            type="button"
            class="icon-button section-head-btn"
            data-toggle-sidebar-section="${kind}"
            aria-expanded="${!collapsed}"
            title="${escapeHtml(toggleLabel)}"
            aria-label="${escapeHtml(toggleLabel)}"
          >${renderIcon(collapsed ? 'chevron-right' : 'chevron-down', 'icon-xs')}</button>
        </div>
      </div>
    `;
  }

  function renderSidebarFilterBox(inputAttr, clearAttr, value, placeholder, lang) {
    return `
      <div class="sidebar-filter-wrap">
        ${renderIcon('search', 'icon-xs')}
        <input type="search" ${inputAttr} value="${escapeHtml(value)}" placeholder="${escapeHtml(placeholder)}" autocomplete="off" aria-label="${escapeHtml(placeholder)}">
        ${
          value
            ? `<button type="button" class="icon-button compact sidebar-filter-clear" ${clearAttr} aria-label="${escapeHtml(t(lang, 'searchClear'))}">${renderIcon('x', 'icon-xs')}</button>`
            : ''
        }
      </div>
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

    const labelsCollapsed = Boolean(state.sidebarLabelsCollapsed);
    const labelsFilterOpen = !labelsCollapsed && Boolean(state.sidebarLabelFilterOpen);
    const labelFilterValue = labelsFilterOpen
      ? String(state.sidebarLabelFilter || '')
      : '';
    const labelQuery = labelFilterValue.trim().toLowerCase();
    const visibleLabels = labelQuery
      ? sortedLabels.filter((lbl) => lbl.name.toLowerCase().includes(labelQuery))
      : sortedLabels;
    const activeLabel =
      state.view === 'tasks' && state.label
        ? sortedLabels.find((lbl) => lbl.id === state.label)
        : null;

    const locationsCollapsed = Boolean(state.sidebarLocationsCollapsed);
    const locationsFilterOpen =
      !locationsCollapsed && Boolean(state.sidebarLocationFilterOpen);
    const locationFilterValue = locationsFilterOpen
      ? String(state.sidebarLocationFilter || '')
      : '';
    const locationQuery = locationFilterValue.trim().toLowerCase();
    const visibleLocations = locationQuery
      ? sortedLocations.filter((loc) =>
          loc.name.toLowerCase().includes(locationQuery),
        )
      : sortedLocations;

    const labelRowsHtml = visibleLabels.length
      ? visibleLabels
          .map((label) => {
            const isExpandedInManage =
              state.view === 'labels' &&
              state.expandedEntity?.kind === 'label' &&
              state.expandedEntity?.id === label.id;
            return `
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
            <button type="button" class="icon-button compact nav-hub-btn ${isExpandedInManage ? 'is-accent' : ''}" data-open-managed="labels:${escapeHtml(label.id)}" title="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}" aria-label="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}">
              ${renderIcon('info', 'icon-sm')}
            </button>
          </div>`;
          })
          .join('')
      : labelQuery
        ? `<div class="sidebar-filter-empty">${escapeHtml(t(lang, 'sidebarFilterLabelsEmpty'))}</div>`
        : '';

    const locationRowsHtml = visibleLocations.length
      ? visibleLocations
          .map((loc) => {
            const isExpandedInManage =
              state.view === 'locations' &&
              state.expandedEntity?.kind === 'location' &&
              state.expandedEntity?.id === loc.id;
            return `
          <button type="button" class="nav-row nav-entity-row" data-open-managed="locations:${escapeHtml(loc.id)}" title="${escapeHtml(t(lang, 'locationHubOpenTooltip'))}" ${isExpandedInManage ? 'aria-current="page"' : ''}>
            ${renderIcon('map-pin')}
            <span class="nav-label-name">${escapeHtml(loc.name)}</span>
            <span class="count">${evalRes.openCountByLocation.get(loc.id) || 0}</span>
            <span class="nav-hub-hint" aria-hidden="true">${renderIcon('info', 'icon-sm')}</span>
          </button>`;
          })
          .join('')
      : locationQuery
        ? `<div class="sidebar-filter-empty">${escapeHtml(t(lang, 'sidebarFilterLocationsEmpty'))}</div>`
        : '';

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

      <section class="sidebar-section ${labelsCollapsed ? 'is-collapsed' : ''}">
        ${renderSidebarSectionHeader({
          kind: 'labels',
          title: t(lang, 'sectionLabels'),
          count: sortedLabels.length,
          collapsed: labelsCollapsed,
          filterOpen: labelsFilterOpen,
          manageActive: state.view === 'labels',
          filterLabel: t(lang, 'sidebarFilterLabelsToggle'),
          manageLabel: t(lang, 'sidebarManageLabels'),
          collapseLabel: t(lang, 'sidebarCollapseLabels'),
          expandLabel: t(lang, 'sidebarExpandLabels'),
          activeDotHtml: activeLabel
            ? `<span class="dot" style="--label-color:${escapeHtml(activeLabel.color || '#00648b')}" title="${escapeHtml(activeLabel.name)}"></span>`
            : '',
        })}
        ${
          labelsCollapsed
            ? ''
            : `
          ${
            labelsFilterOpen
              ? renderSidebarFilterBox(
                  'data-sidebar-label-filter',
                  'data-clear-sidebar-label-filter',
                  labelFilterValue,
                  t(lang, 'sidebarFilterLabelsPlaceholder'),
                  lang,
                )
              : ''
          }
          <button type="button" class="nav-row" data-label="" ${
            state.view === 'tasks' && !state.label ? 'aria-current="page"' : ''
          }>
            ${renderIcon('layers')}
            <span class="nav-label-name">${escapeHtml(t(lang, 'allTasks'))}</span>
          </button>
          <div class="sidebar-entity-list">${labelRowsHtml}</div>
        `
        }
      </section>

      <section class="sidebar-section ${locationsCollapsed ? 'is-collapsed' : ''}">
        ${renderSidebarSectionHeader({
          kind: 'locations',
          title: t(lang, 'sectionLocations'),
          count: sortedLocations.length,
          collapsed: locationsCollapsed,
          filterOpen: locationsFilterOpen,
          manageActive: state.view === 'locations',
          filterLabel: t(lang, 'sidebarFilterLocationsToggle'),
          manageLabel: t(lang, 'sidebarManageLocations'),
          collapseLabel: t(lang, 'sidebarCollapseLocations'),
          expandLabel: t(lang, 'sidebarExpandLocations'),
        })}
        ${
          locationsCollapsed
            ? ''
            : `
          ${
            locationsFilterOpen
              ? renderSidebarFilterBox(
                  'data-sidebar-location-filter',
                  'data-clear-sidebar-location-filter',
                  locationFilterValue,
                  t(lang, 'sidebarFilterLocationsPlaceholder'),
                  lang,
                )
              : ''
          }
          <div class="sidebar-entity-list">${locationRowsHtml}</div>
        `
        }
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

  function renderLoadingView(state) {
    const lang = state.lang;
    return `
      <div class="loading-state" role="status" aria-live="polite">
        <span class="loading-spinner" aria-hidden="true"></span>
        <h2>${escapeHtml(t(lang, 'loadingBoardTitle'))}</h2>
        <p class="subtitle centered">${escapeHtml(t(lang, 'loadingBoardSub'))}</p>
      </div>
    `;
  }

  function renderActiveLabelBar(state, workspace) {
    if (!state.label) return '';
    const lang = state.lang;
    const activeLabel = workspace.labels.find((item) => item.id === state.label);
    if (!activeLabel) return '';
    return `
      <div class="active-label-bar" role="region" aria-label="${escapeHtml(t(lang, 'activeFilterLabel'))}">
        <button type="button" class="active-label-bar-main" data-open-managed="labels:${escapeHtml(activeLabel.id)}" title="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}">
          <span class="dot" style="--label-color:${escapeHtml(activeLabel.color || '#00648b')}"></span>
          <span>${escapeHtml(activeLabel.name)}</span>
          ${activeLabel.scoped ? `<span class="pill-badge tone-accent">${escapeHtml(t(lang, 'scopedQueue'))}</span>` : ''}
          ${renderIcon('info', 'icon-xs')}
        </button>
        <button type="button" class="icon-button compact" data-clear-active-label title="${escapeHtml(t(lang, 'activeFilterClear'))}" aria-label="${escapeHtml(t(lang, 'activeFilterClear'))}">
          ${renderIcon('x', 'icon-xs')}
        </button>
      </div>
    `;
  }

  function renderFloatingNotices(state) {
    const lang = state.lang;
    const undoDepth = state.undoStack.length;
    if (!state.message && !state.recoveryNotice) return '';
    const msgToneClass =
      state.messageTone === 'danger'
        ? 'tone-danger'
        : state.messageTone === 'warning'
          ? 'tone-warning'
          : '';
    return `
      <div class="floating-notice-layer" aria-live="polite">
        ${
          state.recoveryNotice
            ? `<div class="notice-toast tone-warning" role="status">
                <span class="notice-toast-text">
                  ${renderIcon('alert-triangle', 'icon-sm')}
                  <span>${escapeHtml(t(lang, state.recoveryNotice))}</span>
                </span>
                <div class="notice-toast-actions">
                  <button type="button" class="text-button" data-dismiss-recovery>${escapeHtml(t(lang, 'actionClose'))}</button>
                </div>
              </div>`
            : ''
        }
        ${
          state.message
            ? `<div class="notice-toast ${msgToneClass}" role="status">
                <span class="notice-toast-text">
                  ${state.messageTone === 'danger' ? renderIcon('alert-circle', 'icon-sm') : ''}
                  <span>${escapeHtml(state.message)}</span>
                </span>
                <div class="notice-toast-actions">
                  ${
                    undoDepth > 0 && state.showUndoAction
                      ? `<button type="button" class="undo-btn" data-undo>
                          ${renderIcon('undo', 'icon-xs')}
                          <span>${escapeHtml(t(lang, 'actionUndo'))}</span>
                          <kbd class="kbd-hint">Ctrl+Z</kbd>
                        </button>`
                      : ''
                  }
                  <button type="button" class="icon-button compact" data-dismiss-notice title="${escapeHtml(t(lang, 'actionDismiss'))}" aria-label="${escapeHtml(t(lang, 'actionDismiss'))}">
                    ${renderIcon('x', 'icon-xs')}
                  </button>
                </div>
              </div>`
            : ''
        }
      </div>
    `;
  }

  function formatRadiusMeters(radius) {
    const num = Number(radius);
    if (!Number.isFinite(num)) return '0 m';
    if (num >= 1000) {
      const km = (num / 1000).toFixed(2).replace(/\.?0+$/, '');
      return `${km} km`;
    }
    return `${num} m`;
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

  function renderInlineEditBtn(kind, id, section, lang, extraClass = 'ml-auto') {
    return `<button type="button" class="icon-button compact${extraClass ? ` ${extraClass}` : ''}" data-ie-open="${section}" data-ie-kind="${kind}" data-ie-id="${escapeHtml(id)}" title="${escapeHtml(t(lang, 'actionEdit'))}" aria-label="${escapeHtml(t(lang, 'actionEdit'))}">${renderIcon('pencil', 'icon-xs')}</button>`;
  }

  function renderAddFieldChip(kind, id, section, iconName, labelText) {
    return `<button type="button" class="add-field-chip" data-ie-open="${section}" data-ie-kind="${kind}" data-ie-id="${escapeHtml(id)}">${renderIcon(iconName, 'icon-xs')}<span>${escapeHtml(labelText)}</span></button>`;
  }

  function renderEntityToggleItem({
    managedView,
    id,
    label,
    sublabel = '',
    leadingHtml,
    active,
    toggleAttrs,
    infoTooltip,
  }) {
    return `
      <div class="label-toggle-item ${active ? 'is-selected' : ''}">
        <button type="button" class="label-toggle-btn" ${toggleAttrs} aria-pressed="${active}">
          ${leadingHtml}
          <span>${escapeHtml(label)}</span>
          ${sublabel ? `<span class="label-toggle-sub">${escapeHtml(sublabel)}</span>` : ''}
          ${active ? renderIcon('check', 'icon-xs') : ''}
        </button>
        <button type="button" class="label-toggle-hub" data-open-managed="${managedView}:${escapeHtml(id)}" title="${escapeHtml(infoTooltip)}" aria-label="${escapeHtml(infoTooltip)}">
          ${renderIcon('info', 'icon-xs')}
        </button>
      </div>
    `;
  }

  function filterPickerLabels(workspace, rawQuery, scopeFilter = 'all') {
    const sortedLabels = [...workspace.labels].sort((a, b) =>
      a.name.localeCompare(b.name),
    );
    let scopedCount = 0;
    let globalCount = 0;
    for (const lbl of sortedLabels) {
      if (lbl.scoped) scopedCount += 1;
      else globalCount += 1;
    }
    const hasBothScopes = scopedCount > 0 && globalCount > 0;
    const effectiveScope = hasBothScopes ? scopeFilter : 'all';
    const trimmedQuery = String(rawQuery || '').trim();
    const normalizedQuery = trimmedQuery.toLowerCase();

    const filtered = sortedLabels.filter((lbl) => {
      if (effectiveScope === 'scoped' && !lbl.scoped) return false;
      if (effectiveScope === 'global' && lbl.scoped) return false;
      if (normalizedQuery && !lbl.name.toLowerCase().includes(normalizedQuery)) {
        return false;
      }
      return true;
    });

    const canCreate =
      trimmedQuery.length > 0 &&
      trimmedQuery.length <= 120 &&
      !sortedLabels.some((lbl) => lbl.name.toLowerCase() === normalizedQuery);

    return {
      sortedLabels,
      filtered,
      totalCount: sortedLabels.length,
      scopedCount,
      globalCount,
      hasBothScopes,
      effectiveScope,
      trimmedQuery,
      canCreate,
    };
  }

  function renderAssignedLabelChips({
    labels,
    targetKind,
    taskId = '',
    lang,
    showAddButton = false,
    compact = false,
    readOnly = false,
  }) {
    const chipsHtml = labels
      .map((lbl) => {
        const removeTitle = t(lang, 'labelPickerRemoveTooltip', {
          name: lbl.name,
        });
        if (targetKind === 'task') {
          return `
            <div class="assigned-label-chip ${compact ? 'is-compact' : ''}">
              <button type="button" class="assigned-label-chip-main" data-open-managed="labels:${escapeHtml(lbl.id)}" title="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}">
                <span class="dot" style="--label-color:${escapeHtml(lbl.color || '#00648b')}"></span>
                <span>${escapeHtml(lbl.name)}</span>
              </button>
              ${
                readOnly
                  ? ''
                  : `<button type="button" class="assigned-label-chip-remove" data-direct-toggle-label="${escapeHtml(lbl.id)}" data-task-id="${escapeHtml(taskId)}" title="${escapeHtml(removeTitle)}" aria-label="${escapeHtml(removeTitle)}">
                      ${renderIcon('x', 'icon-xs')}
                    </button>`
              }
            </div>
          `;
        }
        const removeAttr =
          targetKind === 'entity-draft'
            ? `data-entity-draft-toggle-label="${escapeHtml(lbl.id)}"`
            : `data-draft-toggle-label="${escapeHtml(lbl.id)}"`;
        return `
          <div class="assigned-label-chip ${compact ? 'is-compact' : ''}">
            <span class="assigned-label-chip-main is-static">
              <span class="dot" style="--label-color:${escapeHtml(lbl.color || '#00648b')}"></span>
              <span>${escapeHtml(lbl.name)}</span>
            </span>
            <button type="button" class="assigned-label-chip-remove" ${removeAttr} title="${escapeHtml(removeTitle)}" aria-label="${escapeHtml(removeTitle)}">
              ${renderIcon('x', 'icon-xs')}
            </button>
          </div>
        `;
      })
      .join('');

    const addBtnHtml =
      showAddButton && !readOnly
        ? targetKind === 'entity-draft'
          ? `<button type="button" class="add-field-chip" data-open-entity-draft-label-picker>${renderIcon('plus', 'icon-xs')}<span>${escapeHtml(t(lang, 'actionAdd'))}</span></button>`
          : `<button type="button" class="add-field-chip" data-open-task-label-picker="${escapeHtml(taskId)}">${renderIcon('plus', 'icon-xs')}<span>${escapeHtml(t(lang, 'actionAdd'))}</span></button>`
        : '';

    return `<div class="assigned-label-chips">${chipsHtml}${addBtnHtml}</div>`;
  }

  function renderLabelPickerBody({
    mode,
    taskId = '',
    selectedIds,
    pickerState,
    workspace,
    evalRes,
    lang,
    showSelectedStrip = true,
  }) {
    const query = pickerState.query || '';
    const {
      sortedLabels,
      filtered,
      totalCount,
      scopedCount,
      globalCount,
      hasBothScopes,
      effectiveScope,
      trimmedQuery,
      canCreate,
    } = filterPickerLabels(workspace, query, pickerState.scopeFilter || 'all');

    const selectedSet = new Set(selectedIds);
    const selectedLabels = sortedLabels.filter((lbl) => selectedSet.has(lbl.id));
    const totalSelectable = filtered.length + (canCreate ? 1 : 0);
    const rawActiveIndex = pickerState.activeIndex;
    const activeIndex =
      totalSelectable > 0 && rawActiveIndex >= 0
        ? Math.min(rawActiveIndex, totalSelectable - 1)
        : -1;

    const selectedStripHtml =
      showSelectedStrip && selectedLabels.length
        ? renderAssignedLabelChips({
            labels: selectedLabels,
            targetKind: mode,
            taskId,
            lang,
            compact: true,
          })
        : '';

    const filterTabsHtml = hasBothScopes
      ? `<div class="label-picker-filters" role="group" aria-label="${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}">
          <button type="button" class="lp-filter-pill" data-lp-scope="${mode}:all" aria-pressed="${effectiveScope === 'all'}">${escapeHtml(t(lang, 'labelPickerFilterAll', { count: totalCount }))}</button>
          <button type="button" class="lp-filter-pill" data-lp-scope="${mode}:scoped" aria-pressed="${effectiveScope === 'scoped'}">${escapeHtml(t(lang, 'labelPickerFilterScoped', { count: scopedCount }))}</button>
          <button type="button" class="lp-filter-pill" data-lp-scope="${mode}:global" aria-pressed="${effectiveScope === 'global'}">${escapeHtml(t(lang, 'labelPickerFilterGlobal', { count: globalCount }))}</button>
        </div>`
      : '';

    const rowsHtml = filtered
      .map((lbl, idx) => {
        const active = selectedSet.has(lbl.id);
        const highlighted = idx === activeIndex;
        const openCount = evalRes.openCountByLabel.get(lbl.id) || 0;
        const toggleAttrs =
          mode === 'task'
            ? `data-direct-toggle-label="${escapeHtml(lbl.id)}" data-task-id="${escapeHtml(taskId)}"`
            : mode === 'entity-draft'
              ? `data-entity-draft-toggle-label="${escapeHtml(lbl.id)}"`
              : `data-draft-toggle-label="${escapeHtml(lbl.id)}"`;
        return `
          <div class="label-picker-row ${active ? 'is-selected' : ''} ${highlighted ? 'is-highlighted' : ''}" data-lp-row-idx="${idx}">
            <button type="button" class="label-picker-row-main" ${toggleAttrs} role="option" aria-selected="${active}">
              <span class="lp-check ${active ? 'is-checked' : ''}">${active ? renderIcon('check', 'icon-xs') : ''}</span>
              <span class="dot" style="--label-color:${escapeHtml(lbl.color || '#00648b')}"></span>
              <span class="lp-row-name">${escapeHtml(lbl.name)}</span>
              ${lbl.scoped ? `<span class="lp-scoped-badge">${escapeHtml(t(lang, 'scopedQueue'))}</span>` : ''}
              <span class="lp-row-count">${escapeHtml(t(lang, 'labelPickerOpenCount', { count: openCount }))}</span>
            </button>
            <button type="button" class="icon-button compact label-picker-row-info" data-open-managed="labels:${escapeHtml(lbl.id)}" title="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}" aria-label="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}">
              ${renderIcon('info', 'icon-xs')}
            </button>
          </div>
        `;
      })
      .join('');

    const emptyHtml =
      !filtered.length && !canCreate
        ? `<div class="label-picker-empty">${escapeHtml(t(lang, totalCount ? 'labelPickerNoMatches' : 'labelPickerEmptyHint'))}</div>`
        : '';

    const createHtml = canCreate
      ? `<button type="button" class="label-picker-create ${activeIndex === filtered.length ? 'is-highlighted' : ''}" data-lp-create="${mode}" data-lp-row-idx="${filtered.length}">
          ${renderIcon('plus', 'icon-xs')}
          <span>${escapeHtml(t(lang, 'labelPickerCreateAction', { name: trimmedQuery }))}</span>
        </button>`
      : '';

    return `
      <div class="label-picker-body">
        ${selectedStripHtml}
        <div class="label-picker-search">
          ${renderIcon('search', 'icon-xs')}
          <input type="search" data-lp-search="${mode}" value="${escapeHtml(query)}" placeholder="${escapeHtml(t(lang, 'labelPickerSearchPlaceholder'))}" maxlength="120" autocomplete="off" aria-label="${escapeHtml(t(lang, 'labelPickerSearchPlaceholder'))}">
          ${
            query
              ? `<button type="button" class="icon-button compact lp-clear-btn" data-lp-clear="${mode}" aria-label="${escapeHtml(t(lang, 'searchClear'))}">${renderIcon('x', 'icon-xs')}</button>`
              : ''
          }
        </div>
        ${filterTabsHtml}
        <div class="label-picker-list" role="listbox" aria-multiselectable="true" aria-label="${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}">
          ${rowsHtml}
          ${emptyHtml}
          ${createHtml}
        </div>
      </div>
    `;
  }

  function renderMobileLabelPickerSheet(state, workspace, evalRes) {
    if (!state.isCompact) return '';
    const lang = state.lang;
    let mode = null;
    let taskId = '';
    let selectedIds = [];
    let pickerState = null;

    if (state.taskLabelPicker) {
      const task = workspace.tasks.find(
        (item) => item.id === state.taskLabelPicker.taskId,
      );
      if (task) {
        mode = 'task';
        taskId = task.id;
        selectedIds = task.labels || [];
        pickerState = state.taskLabelPicker;
      }
    } else if (state.entityDraftLabelPicker && state.entityDraft?.kind === 'task') {
      mode = 'entity-draft';
      selectedIds = state.entityDraft.labels || [];
      pickerState = state.entityDraftLabelPicker;
    } else if (state.draftLabelPicker) {
      mode = 'draft';
      selectedIds = state.draft.labels || [];
      pickerState = state.draftLabelPicker;
    }

    if (!mode || !pickerState) return '';

    return `
      <div class="sheet-backdrop" data-sheet-backdrop>
        <div class="bottom-sheet" role="dialog" aria-modal="true" aria-label="${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}">
          <div class="bottom-sheet-handle" aria-hidden="true"><span></span></div>
          <div class="bottom-sheet-head">
            ${renderIcon('tags', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}</strong>
            <span class="info-sub">${selectedIds.length}</span>
            <button type="button" class="secondary compact ml-auto" data-close-label-sheet>${escapeHtml(t(lang, 'actionDone'))}</button>
          </div>
          <div class="bottom-sheet-body">
            ${renderLabelPickerBody({
              mode,
              taskId,
              selectedIds,
              pickerState,
              workspace,
              evalRes,
              lang,
              showSelectedStrip: true,
            })}
          </div>
        </div>
      </div>
    `;
  }

  function renderNoteSection({ kind, id, note, isEditing, draft, error, lang, readOnly = false }) {
    if (isEditing && !readOnly) {
      return `
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
              error,
              note ? 'data-ie-clear="note"' : '',
              t(lang, 'inlineClear'),
            )}
          </div>
        </div>
      `;
    }
    if (!note) return '';
    return `
      <div class="info-card">
        <div class="info-card-head">
          ${renderIcon('file-text', 'icon-sm')}
          <strong>${escapeHtml(t(lang, 'taskInfoNoteTitle'))}</strong>
          <div class="info-head-actions ml-auto">
            <button type="button" class="icon-button compact" data-copy-note="${escapeHtml(note)}" title="${escapeHtml(t(lang, 'actionCopy'))}">
              ${renderIcon('copy', 'icon-xs')}
            </button>
            ${readOnly ? '' : renderInlineEditBtn(kind, id, 'note', lang, '')}
          </div>
        </div>
        <p class="info-note">${escapeHtml(note)}</p>
      </div>
    `;
  }

  function renderLinksSection({ kind, id, links, isEditing, draft, error, lang, readOnly = false }) {
    if (isEditing && !readOnly) {
      const editingLinkIdx = draft.editingLinkIndex;
      return `
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
              error,
              links?.length ? 'data-ie-clear="links"' : '',
              t(lang, 'inlineClear'),
            )}
          </div>
        </div>
      `;
    }
    if (!links?.length) return '';
    return `
      <div class="info-card">
        <div class="info-card-head">
          ${renderIcon('link', 'icon-sm')}
          <strong>${escapeHtml(t(lang, 'taskInfoLinksTitle'))}</strong>
          ${readOnly ? '' : renderInlineEditBtn(kind, id, 'links', lang)}
        </div>
        <div class="hub-links-list">
          ${links
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
    `;
  }

  function renderConditionsReadRules(rules, workspace, lang, showStatusPrefix) {
    return `
      <ul class="info-simple-list">
        ${rules
          .map((rule) => {
            const prefix = showStatusPrefix ? (rule.satisfied ? '✓ ' : '✕ ') : '';
            if (rule.type === 'locations') {
              const locChips = rule.locationIds
                .map((locId) => {
                  const loc = workspace.locations.find((item) => item.id === locId);
                  const locLabel = loc ? loc.name : locId;
                  return `<button type="button" class="inline-loc-chip" data-open-managed="locations:${escapeHtml(locId)}" title="${escapeHtml(t(lang, 'locationHubOpenTooltip'))}">${renderIcon('map-pin', 'icon-xs')}<span>${escapeHtml(locLabel)}</span>${renderIcon('info', 'icon-xs')}</button>`;
                })
                .join('');
              return `<li>${prefix}${escapeHtml(t(lang, 'condLocations'))}:<span class="cond-loc-links">${locChips}</span></li>`;
            }
            return `<li>${prefix}${escapeHtml(formatConditionLine(rule, workspace.locations, lang))}</li>`;
          })
          .join('')}
      </ul>
    `;
  }

  function renderConditionsEditorBody({
    draft,
    workspace,
    lang,
    includeModes,
    suspendedActive = false,
  }) {
    const weekdays =
      window.TT2.i18n.strings[window.TT2.i18n.resolveLang(lang)].weekdays;
    const sortedLocations = [...workspace.locations].sort((a, b) =>
      a.name.localeCompare(b.name),
    );
    const condModeSelect = (label, key) => `
      <label class="field">${escapeHtml(label)}
        <select data-ie="${key}">
          <option value="inherit" ${draft[key] === 'inherit' ? 'selected' : ''}>${escapeHtml(t(lang, 'condInherit'))}</option>
          <option value="any" ${draft[key] === 'any' ? 'selected' : ''}>${escapeHtml(t(lang, 'condAny'))}</option>
          <option value="custom" ${draft[key] === 'custom' ? 'selected' : ''}>${escapeHtml(t(lang, 'condCustom'))}</option>
        </select>
      </label>
    `;

    const showDays = !includeModes || draft.daysMode === 'custom';
    const showTimes = !includeModes || draft.timeMode === 'custom';
    const showPlaces = !includeModes || draft.placesMode === 'custom';

    const daysPicker = `
      <div class="day-pills">
        ${weekdays
          .map(
            (day, i) => `
          <label>
            <input type="checkbox" data-ie-day="${i + 1}" ${draft.days.includes(i + 1) ? 'checked' : ''}>
            <span>${day}</span>
          </label>`,
          )
          .join('')}
      </div>
    `;

    const timesPicker = `
      <div>
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
        <button type="button" class="secondary compact mt-8" data-ie-add-time>${escapeHtml(t(lang, 'actionAddTime'))}</button>
      </div>
    `;

    const locationsPicker = sortedLocations.length
      ? `<div class="label-toggle-grid">
          ${sortedLocations
            .map((loc) =>
              renderEntityToggleItem({
                managedView: 'locations',
                id: loc.id,
                label: loc.name,
                sublabel: formatRadiusMeters(loc.radius),
                leadingHtml: renderIcon('map-pin', 'icon-xs'),
                active: draft.locationIds.includes(loc.id),
                toggleAttrs: `data-ie-toggle-place="${escapeHtml(loc.id)}"`,
                infoTooltip: t(lang, 'locationHubOpenTooltip'),
              }),
            )
            .join('')}
        </div>`
      : `<div class="info-sub">${escapeHtml(t(lang, 'emptyLocations'))}</div>`;

    return `
      ${
        includeModes && suspendedActive
          ? `<div class="inline-warning-box">${renderIcon('alert-triangle', 'icon-sm')}<span>${escapeHtml(t(lang, 'suspendedDisablesConditions'))}</span></div>`
          : ''
      }
      <div class="${includeModes && suspendedActive ? 'is-dimmed-disabled' : ''}">
        ${
          includeModes
            ? `<label class="check-field compact-check">
                <input type="checkbox" data-ie="ignoreLabels" ${draft.ignoreLabels ? 'checked' : ''}>
                <span>${escapeHtml(t(lang, 'fieldIgnoreLabels'))}<small>${escapeHtml(t(lang, 'fieldIgnoreLabelsDesc'))}</small></span>
              </label>
              <div class="edit-divider"></div>`
            : `<small class="info-sub">${escapeHtml(t(lang, 'descLabelConditions'))}</small>
              <div class="edit-divider"></div>`
        }
        ${
          includeModes
            ? condModeSelect(t(lang, 'condDays'), 'daysMode')
            : `<div class="field-label-sm">${escapeHtml(t(lang, 'condDays'))}</div>`
        }
        ${showDays ? daysPicker : ''}
        <div class="edit-divider"></div>
        ${
          includeModes
            ? condModeSelect(t(lang, 'condTimes'), 'timeMode')
            : `<div class="field-label-sm">${escapeHtml(t(lang, 'condTimes'))}</div>`
        }
        ${showTimes ? timesPicker : ''}
        <div class="edit-divider"></div>
        ${
          includeModes
            ? condModeSelect(t(lang, 'condLocations'), 'placesMode')
            : `<div class="field-label-sm">${escapeHtml(t(lang, 'condLocations'))}</div>`
        }
        ${showPlaces ? locationsPicker : ''}
      </div>
    `;
  }

  function renderEntitySlideShell({
    kind,
    id,
    isAnimating,
    regionLabel,
    metaExtraHtml = '',
    deleteConfirmText,
    isConfirmingDelete,
    sectionsHtml,
    addChipsHtml,
    lang,
  }) {
    const key = `${kind}:${id}`;
    return `
      <div class="task-slide-panel ${isAnimating ? '' : 'is-open'}" data-slide-panel="${escapeHtml(key)}" role="region" aria-label="${escapeHtml(regionLabel)}">
        <div class="task-slide-inner">
          <div class="task-slide-meta-bar">
            <code class="mono-sm">${escapeHtml(t(lang, 'taskInfoIdLabel', { id }))}</code>
            <button type="button" class="icon-button compact" data-copy-id="${escapeHtml(id)}" data-copy-kind="${kind}" title="${escapeHtml(t(lang, 'actionCopy'))}">
              ${renderIcon('copy', 'icon-xs')}
            </button>
            ${metaExtraHtml}
            ${
              isConfirmingDelete
                ? `<div class="inline-delete-confirm ml-auto">
                    <span>${escapeHtml(deleteConfirmText)}</span>
                    <button type="button" class="secondary compact" data-inline-del-no>${escapeHtml(t(lang, 'actionKeep'))}</button>
                    <button type="button" class="danger compact" data-inline-del-yes="${escapeHtml(key)}">${escapeHtml(t(lang, 'actionConfirmDelete'))}</button>
                  </div>`
                : `<button type="button" class="icon-button compact is-danger-hover ml-auto" data-inline-del-ask="${escapeHtml(key)}" title="${escapeHtml(t(lang, 'actionDelete'))}" aria-label="${escapeHtml(t(lang, 'actionDelete'))}">
                    ${renderIcon('trash', 'icon-xs')}
                  </button>`
            }
          </div>
          <div class="task-slide-sections">
            ${sectionsHtml}
          </div>
          ${
            addChipsHtml
              ? `<div class="task-add-fields-bar">${addChipsHtml}</div>`
              : ''
          }
        </div>
      </div>
    `;
  }

  function renderEntityCard({
    kind,
    id,
    extraCardClass = '',
    isExpanded,
    isEditingTitle,
    allowTitleEdit = true,
    title,
    titleField,
    titleMaxLength,
    titleAriaLabel,
    titleEditDraft,
    titleEditError,
    leadingHtml,
    extraActionsHtml = '',
    collapsedMetadataHtml = '',
    slidePanelHtml = '',
    lang,
  }) {
    const key = `${kind}:${id}`;
    return `
      <article class="task ${extraCardClass} ${isExpanded ? 'is-expanded' : ''}" data-entity-card="${escapeHtml(key)}">
        <div class="task-top">
          ${leadingHtml}
          ${
            isEditingTitle
              ? `<div class="inline-title-edit">
                  <div class="inline-title-edit-row">
                    <input type="text" data-ie="${titleField}" value="${escapeHtml(titleEditDraft)}" maxlength="${titleMaxLength}" aria-label="${escapeHtml(titleAriaLabel)}">
                    <button type="button" class="primary compact" data-ie-save>${escapeHtml(t(lang, 'actionSave'))}</button>
                    <button type="button" class="secondary compact" data-ie-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>
                  </div>
                  ${titleEditError ? `<div class="edit-error inline-edit-error" role="status">${escapeHtml(titleEditError)}</div>` : ''}
                </div>`
              : `<button type="button" class="task-title" data-toggle-entity="${escapeHtml(key)}" aria-expanded="${isExpanded}">
                  ${escapeHtml(title)}
                </button>
                <div class="task-actions">
                  ${
                    isExpanded && allowTitleEdit
                      ? `<button type="button" class="icon-button compact" data-ie-open="${titleField}" data-ie-kind="${kind}" data-ie-id="${escapeHtml(id)}" title="${escapeHtml(titleAriaLabel)}" aria-label="${escapeHtml(titleAriaLabel)}">
                          ${renderIcon('pencil', 'icon-sm')}
                        </button>`
                      : ''
                  }
                  ${extraActionsHtml}
                </div>`
          }
        </div>
        ${!isExpanded ? collapsedMetadataHtml : ''}
        ${isExpanded ? slidePanelHtml : ''}
      </article>
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
      state.inlineEdit &&
      state.inlineEdit.kind === 'task' &&
      state.inlineEdit.id === task.id
        ? state.inlineEdit
        : null;
    const editing = edit ? edit.section : null;
    const draft = edit ? edit.draft : null;
    const err = edit ? edit.error : '';

    const labelsById = new Map(workspace.labels.map((l) => [l.id, l]));
    const taskLabels = (task.labels || [])
      .map((id) => labelsById.get(id))
      .filter(Boolean)
      .sort((a, b) => a.name.localeCompare(b.name));
    const isTaskLabelPickerOpen = state.taskLabelPicker?.taskId === task.id;
    const showInlineLabelPicker = isTaskLabelPickerOpen && !state.isCompact;
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
      isCompleted ? '' : renderInlineEditBtn('task', task.id, section, lang);

    const editHistIdx = state.editingHistoryIndex;
    const sections = [];

    // 2. Note (shared)
    const noteHtml = renderNoteSection({
      kind: 'task',
      id: task.id,
      note: task.note,
      isEditing: editing === 'note',
      draft,
      error: err,
      lang,
      readOnly: isCompleted,
    });
    if (noteHtml) sections.push(noteHtml);

    // 3. Links (shared)
    const linksHtml = renderLinksSection({
      kind: 'task',
      id: task.id,
      links: task.links,
      isEditing: editing === 'links',
      draft,
      error: err,
      lang,
      readOnly: isCompleted,
    });
    if (linksHtml) sections.push(linksHtml);

    // 4. Subtasks
    if (editing === 'subtasks' && !isCompleted) {
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
            ${isCompleted ? '' : renderInlineEditBtn('task', task.id, 'subtasks', lang, '')}
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

    // 5. History (always live interactive, with optional local wall-clock timestamp)
    const histCount = (task.history || []).length;
    sections.push(`
      <div class="info-card">
        <div class="info-card-head">
          ${renderIcon('history', 'icon-sm')}
          <strong>${escapeHtml(t(lang, 'taskInfoHistoryTitle'))}</strong>
          <span class="info-sub ml-auto">${histCount} / 200</span>
        </div>
        ${
          histCount
            ? `<div class="info-history-list">
                ${task.history
                  .map((entry, idx) =>
                    editHistIdx === idx
                      ? `<div class="history-inline-edit">
                          <div class="history-inline-edit-row">
                            <input type="datetime-local" data-info-hist-edit-time value="${escapeHtml(state.historyEditTimeDraft || formatLocalDatetimeInput(entry.timestampUtc, offset))}" aria-label="${escapeHtml(t(lang, 'fieldHistoryTimestamp'))}">
                          </div>
                          <div class="history-inline-edit-row">
                            <input type="text" data-info-hist-edit-input value="${escapeHtml(state.historyEditDraft || entry.text)}" maxlength="500">
                            <button type="button" class="primary compact" data-info-hist-save="${idx}">${escapeHtml(t(lang, 'actionSave'))}</button>
                            <button type="button" class="secondary compact" data-info-hist-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>
                          </div>
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
          <input type="text" data-info-hist-new value="${escapeHtml(state.historyNewDraft || '')}" placeholder="${escapeHtml(t(lang, 'taskInfoHistoryPlaceholder'))}" maxlength="500">
          <button type="button" class="icon-button compact ${state.historyTimeOpen ? 'is-accent' : ''}" data-info-hist-toggle-time title="${escapeHtml(t(lang, 'actionToggleHistoryTimestamp'))}" aria-label="${escapeHtml(t(lang, 'actionToggleHistoryTimestamp'))}" aria-pressed="${Boolean(state.historyTimeOpen)}">
            ${renderIcon('clock', 'icon-xs')}
          </button>
          <button type="button" class="secondary compact" data-info-hist-add>${escapeHtml(t(lang, 'taskInfoHistoryAdd'))}</button>
        </div>
        ${
          state.historyTimeOpen
            ? `<div class="history-timestamp-row">
                <span class="info-sub">${escapeHtml(t(lang, 'fieldHistoryTimestamp'))}</span>
                <input type="datetime-local" data-info-hist-new-time value="${escapeHtml(state.historyNewTimeDraft || '')}" aria-label="${escapeHtml(t(lang, 'fieldHistoryTimestamp'))}">
              </div>`
            : ''
        }
        ${state.historyError ? `<div class="edit-error inline-edit-error" role="status">${escapeHtml(state.historyError)}</div>` : ''}
      </div>
    `);

    // 6. Labels (assigned chips + on-demand searchable picker; empty collapses to + Labels chip)
    if (showInlineLabelPicker && !isCompleted) {
      sections.push(`
        <div class="info-card is-editing label-picker-card">
          <div class="info-card-head">
            ${renderIcon('tags', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}</strong>
            <span class="info-sub">${taskLabels.length}</span>
            <button type="button" class="secondary compact ml-auto" data-close-task-label-picker>${escapeHtml(t(lang, 'actionDone'))}</button>
          </div>
          ${renderLabelPickerBody({
            mode: 'task',
            taskId: task.id,
            selectedIds: task.labels || [],
            pickerState: state.taskLabelPicker,
            workspace,
            evalRes,
            lang,
            showSelectedStrip: true,
          })}
        </div>
      `);
    } else if (taskLabels.length) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('tags', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}</strong>
            <span class="info-sub ml-auto">${taskLabels.length}</span>
          </div>
          ${renderAssignedLabelChips({
            labels: taskLabels,
            targetKind: 'task',
            taskId: task.id,
            lang,
            showAddButton: !isCompleted,
            readOnly: isCompleted,
          })}
        </div>
      `);
    }

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

    // 12. Activation Conditions (shared)
    if (editing === 'conditions') {
      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('sliders', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoConditionsTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            ${renderConditionsEditorBody({
              draft,
              workspace,
              lang,
              includeModes: true,
              suspendedActive,
            })}
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
              ? renderConditionsReadRules(condEval.rules, workspace, lang, true)
              : `<small class="info-sub">${escapeHtml(t(lang, 'fieldIgnoreLabels'))}</small>`
          }
        </div>
      `);
    }

    // 13. Compact "+ Add" & direct quick-toggle bar for unset fields (active tasks only)
    const addChips = [];
    if (!isCompleted) {
      if (!task.note && editing !== 'note') {
        addChips.push(
          renderAddFieldChip('task', task.id, 'note', 'file-text', t(lang, 'inlineAddNote')),
        );
      }
      if (!task.links?.length && editing !== 'links') {
        addChips.push(
          renderAddFieldChip('task', task.id, 'links', 'link', t(lang, 'inlineAddLinks')),
        );
      }
      if (!task.subtasks?.length && editing !== 'subtasks') {
        addChips.push(
          renderAddFieldChip('task', task.id, 'subtasks', 'list-checks', t(lang, 'inlineAddSubtasks')),
        );
      }
      if (!taskLabels.length && !showInlineLabelPicker) {
        addChips.push(
          `<button type="button" class="add-field-chip" data-open-task-label-picker="${escapeHtml(task.id)}">${renderIcon('tags', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddLabels'))}</span></button>`,
        );
      }
      if (!task.dueAt && editing !== 'due') {
        addChips.push(
          renderAddFieldChip('task', task.id, 'due', 'calendar-days', t(lang, 'inlineAddDue')),
        );
      }
      if (currentMode === 'queue') {
        addChips.push(
          `<button type="button" class="add-field-chip is-direct" data-direct-mode="priority" data-task-id="${escapeHtml(task.id)}">${renderIcon('zap', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddPriority'))}</span></button>`,
        );
        addChips.push(
          `<button type="button" class="add-field-chip is-direct" data-direct-mode="someday" data-task-id="${escapeHtml(task.id)}">${renderIcon('lightbulb', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddSomeday'))}</span></button>`,
        );
      }
      if (!task.repeat && editing !== 'repeat') {
        addChips.push(
          renderAddFieldChip('task', task.id, 'repeat', 'repeat', t(lang, 'inlineAddRepeat')),
        );
      }
      if (!suspendedActive && editing !== 'suspended') {
        addChips.push(
          renderAddFieldChip('task', task.id, 'suspended', 'pause-circle', t(lang, 'inlineAddSuspend')),
        );
      }
      if ((!depEval || depEval.total === 0) && editing !== 'prereqs') {
        addChips.push(
          renderAddFieldChip('task', task.id, 'prereqs', 'lock', t(lang, 'inlineAddPrereqs')),
        );
      }
      if (!hasConditions && editing !== 'conditions') {
        addChips.push(
          renderAddFieldChip('task', task.id, 'conditions', 'sliders', t(lang, 'inlineAddConditions')),
        );
      }
    }

    return renderEntitySlideShell({
      kind: 'task',
      id: task.id,
      isAnimating,
      regionLabel: t(lang, 'taskInfoTitle'),
      metaExtraHtml: isCompleted
        ? `<span class="pill-badge">${escapeHtml(t(lang, 'completedReadOnlyHint'))}</span>`
        : '',
      deleteConfirmText: t(lang, 'inlineDeleteConfirm'),
      isConfirmingDelete: state.inlineDeleteConfirmKey === `task:${task.id}`,
      sectionsHtml: sections.join(''),
      addChipsHtml: addChips.join(''),
      lang,
    });
  }

  const MAX_VISIBLE_SECONDARY_BADGES = 3;

  function renderTaskCard(task, tierIdx, state, workspace, evalRes, showTierBadge = false) {
    const lang = state.lang;
    const offset = resolveOffsetMinutes(workspace.config);
    const isCompleted = Boolean(task.finishedAt);
    const key = `task:${task.id}`;
    const isExpanded =
      state.expandedEntity?.kind === 'task' && state.expandedEntity?.id === task.id;
    const isAnimating = state.justExpandedKey === key;
    const canDowngrade = !isCompleted && tierIdx <= 2;
    const isEditingTitle =
      isExpanded &&
      !isCompleted &&
      state.inlineEdit?.kind === 'task' &&
      state.inlineEdit?.id === task.id &&
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
      const isAutoPrioritized =
        !isCompleted &&
        !task.priority &&
        evalRes.effectivePriorityIds.has(task.id);
      const suspendedActive = isTaskSuspendedActive(task, state.nowMs);
      const depEval = evalRes.dependencyDetailsByTask.get(task.id);
      const condEval = evalRes.conditionDetailsByTask.get(task.id);

      const primaryBadges = [];
      const secondaryBadges = [];
      const toggleAttr = `data-toggle-entity="${escapeHtml(key)}"`;

      if (showTierBadge) {
        primaryBadges.push(
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
        primaryBadges.push(
          `<button type="button" class="meta-pill is-interactive ${dueTone}" ${toggleAttr}>${renderIcon('calendar-days', 'icon-xs')}${escapeHtml(dueText)}</button>`,
        );
      }

      if (task.priority && !isCompleted) {
        secondaryBadges.push(
          `<button type="button" class="meta-pill is-interactive tone-accent" ${toggleAttr}>${renderIcon('zap', 'icon-xs')}${escapeHtml(t(lang, 'badgePriority'))}</button>`,
        );
      } else if (isAutoPrioritized) {
        secondaryBadges.push(
          `<button type="button" class="meta-pill is-interactive tone-warning" ${toggleAttr}>${renderIcon('zap', 'icon-xs')}${escapeHtml(t(lang, 'badgeAutoPriority'))}</button>`,
        );
      }

      if (suspendedActive) {
        const suspText =
          task.suspendedMode === 'forever'
            ? t(lang, 'badgeSuspendedForever')
            : t(lang, 'badgeSuspendedUntil', {
                date: formatLocalDate(task.suspendedAt, offset),
              });
        secondaryBadges.push(
          `<button type="button" class="meta-pill is-interactive tone-warning" ${toggleAttr}>${renderIcon('pause-circle', 'icon-xs')}${escapeHtml(suspText)}</button>`,
        );
      }

      if (depEval && !depEval.satisfied) {
        secondaryBadges.push(
          `<button type="button" class="meta-pill is-interactive tone-warning" ${toggleAttr}>${renderIcon('lock', 'icon-xs')}${escapeHtml(t(lang, 'badgeBlockedBy', { done: depEval.satisfiedCount, total: depEval.total }))}</button>`,
        );
      }

      if (condEval && condEval.rules.length > 0) {
        secondaryBadges.push(
          `<button type="button" class="meta-pill is-interactive ${condEval.satisfied ? '' : 'tone-warning'}" ${toggleAttr}>${renderIcon('sliders', 'icon-xs')}${escapeHtml(t(lang, 'badgeConditions'))}</button>`,
        );
      }

      if (task.subtasks?.length) {
        const doneCount = task.subtasks.filter((s) => s.done).length;
        secondaryBadges.push(
          `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${renderIcon(task.subtasksAutoFinish ? 'check-square' : 'list-checks', 'icon-xs')}${escapeHtml(t(lang, 'badgeSteps', { done: doneCount, total: task.subtasks.length }))}</button>`,
        );
      }

      if (task.repeat) {
        secondaryBadges.push(
          `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${renderIcon('repeat', 'icon-xs')}${escapeHtml(formatRepeatSummary(task, lang))}</button>`,
        );
      }

      if (task.note) {
        secondaryBadges.push(
          `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${renderIcon('file-text', 'icon-xs')}${escapeHtml(t(lang, 'badgeNote'))}</button>`,
        );
      }

      if (task.links?.length) {
        secondaryBadges.push(
          `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${renderIcon('link', 'icon-xs')}${escapeHtml(t(lang, task.links.length === 1 ? 'badgeLinkSingular' : 'badgeLinks', { count: task.links.length }))}</button>`,
        );
      }

      if (task.history?.length) {
        secondaryBadges.push(
          `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${renderIcon('history', 'icon-xs')}${escapeHtml(t(lang, 'badgeHistory', { count: task.history.length }))}</button>`,
        );
      }

      const displayedSecondary =
        secondaryBadges.length > MAX_VISIBLE_SECONDARY_BADGES
          ? [
              ...secondaryBadges.slice(0, MAX_VISIBLE_SECONDARY_BADGES),
              `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${escapeHtml(t(lang, 'badgeMoreIndicators', { count: secondaryBadges.length - MAX_VISIBLE_SECONDARY_BADGES }))}</button>`,
            ]
          : secondaryBadges;

      const allBadges = [...primaryBadges, ...displayedSecondary];

      if (taskLabels.length || allBadges.length) {
        metadataHtml = `<div class="metadata">
          ${taskLabels
            .map(
              (lbl) => `
            <button type="button" class="tag-chip" data-open-managed="labels:${escapeHtml(lbl.id)}" title="${escapeHtml(t(lang, 'labelHubOpenTooltip'))}">
              <span class="dot" style="--label-color:${escapeHtml(lbl.color || '#00648b')}"></span>
              <span>${escapeHtml(lbl.name)}</span>
            </button>`,
            )
            .join('')}
          ${allBadges.join('')}
        </div>`;
      }
    }

    return renderEntityCard({
      kind: 'task',
      id: task.id,
      extraCardClass: isCompleted ? 'is-completed' : '',
      isExpanded,
      isEditingTitle,
      allowTitleEdit: !isCompleted,
      title: task.title,
      titleField: 'title',
      titleMaxLength: 300,
      titleAriaLabel: t(lang, 'inlineEditTitle'),
      titleEditDraft: isEditingTitle ? state.inlineEdit.draft.title : '',
      titleEditError: isEditingTitle ? state.inlineEdit.error : '',
      leadingHtml: `
        <button type="button" class="complete" data-complete="${escapeHtml(task.id)}" aria-label="${escapeHtml(task.title)} ${escapeHtml(t(lang, isCompleted ? 'actionRestore' : 'actionComplete'))}">
          <span class="circle ${isCompleted ? 'is-checked' : ''}">${isCompleted ? renderIcon('check', 'icon-xs') : ''}</span>
        </button>
      `,
      extraActionsHtml: canDowngrade
        ? `<button type="button" class="icon-button compact" data-downgrade="${escapeHtml(task.id)}" title="${escapeHtml(t(lang, 'actionDowngrade'))}" aria-label="${escapeHtml(t(lang, 'actionDowngrade'))}">
            ${renderIcon('chevron-right', 'icon-sm')}
          </button>`
        : '',
      collapsedMetadataHtml: metadataHtml,
      slidePanelHtml: isExpanded
        ? renderTaskSlidePanel(task, state, workspace, evalRes, isAnimating)
        : '',
      lang,
    });
  }

  function renderTaskDraftCard(state, workspace, evalRes) {
    const draft = state.entityDraft;
    if (!draft || draft.kind !== 'task') return '';
    const lang = state.lang;
    const labelsById = new Map(workspace.labels.map((l) => [l.id, l]));
    const draftLabels = (draft.labels || [])
      .map((id) => labelsById.get(id))
      .filter(Boolean)
      .sort((a, b) => a.name.localeCompare(b.name));
    const showInlinePicker =
      Boolean(state.entityDraftLabelPicker) && !state.isCompact;
    const open = draft.openSections || {};

    const sections = [];

    // Placement
    sections.push(`
      <div class="info-card">
        <div class="info-card-head">
          ${renderIcon('zap', 'icon-sm')}
          <strong>${escapeHtml(t(lang, 'inlinePlacementTitle'))}</strong>
        </div>
        <div class="segmented" role="group" aria-label="${escapeHtml(t(lang, 'inlinePlacementTitle'))}">
          <button type="button" data-ed-task-mode="queue" aria-pressed="${draft.mode === 'queue'}">${escapeHtml(t(lang, 'modeQueue'))}</button>
          <button type="button" data-ed-task-mode="priority" aria-pressed="${draft.mode === 'priority'}">${escapeHtml(t(lang, 'modePriority'))}</button>
          <button type="button" data-ed-task-mode="someday" aria-pressed="${draft.mode === 'someday'}">${escapeHtml(t(lang, 'modeSomeday'))}</button>
        </div>
      </div>
    `);

    // Labels
    if (showInlinePicker) {
      sections.push(`
        <div class="info-card is-editing label-picker-card">
          <div class="info-card-head">
            ${renderIcon('tags', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}</strong>
            <span class="info-sub">${draftLabels.length}</span>
            <button type="button" class="secondary compact ml-auto" data-close-entity-draft-label-picker>${escapeHtml(t(lang, 'actionDone'))}</button>
          </div>
          ${renderLabelPickerBody({
            mode: 'entity-draft',
            selectedIds: draft.labels || [],
            pickerState: state.entityDraftLabelPicker,
            workspace,
            evalRes,
            lang,
            showSelectedStrip: true,
          })}
        </div>
      `);
    } else if (draftLabels.length) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('tags', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}</strong>
            <span class="info-sub ml-auto">${draftLabels.length}</span>
          </div>
          ${renderAssignedLabelChips({
            labels: draftLabels,
            targetKind: 'entity-draft',
            lang,
            showAddButton: true,
          })}
        </div>
      `);
    }

    if (open.note) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('file-text', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoNoteTitle'))}</strong>
          </div>
          <label class="field">
            <textarea data-ed-field="note" rows="3" maxlength="10000" aria-label="${escapeHtml(t(lang, 'taskInfoNoteTitle'))}">${escapeHtml(draft.note || '')}</textarea>
          </label>
        </div>
      `);
    }

    if (open.due) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('calendar-days', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoDueTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            <label class="field">${escapeHtml(t(lang, 'fieldDue'))}
              <input type="datetime-local" data-ed-field="dueLocal" value="${escapeHtml(draft.dueLocal || '')}">
            </label>
            <label class="check-field compact-check">
              <input type="checkbox" data-ed-field="autoDue" ${draft.autoDue ? 'checked' : ''}>
              <span>${escapeHtml(t(lang, 'fieldDueAuto'))}<small>${escapeHtml(t(lang, 'fieldDueAutoDesc'))}</small></span>
            </label>
            <label class="field">${escapeHtml(t(lang, 'fieldDueNote'))}
              <textarea data-ed-field="dueNote" rows="2" placeholder="${escapeHtml(t(lang, 'placeholderDueNote'))}">${escapeHtml(draft.dueNote || '')}</textarea>
            </label>
          </div>
        </div>
      `);
    }

    if (open.repeat) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('repeat', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoRepeatTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            <div class="field-grid">
              <label class="field">${escapeHtml(t(lang, 'fieldRepeatEvery'))}
                <input type="number" min="1" max="3650" data-ed-field="repeatEvery" value="${escapeHtml(draft.repeatEvery)}">
              </label>
              <label class="field">${escapeHtml(t(lang, 'fieldRepeatUnit'))}
                <select data-ed-field="repeatUnit">
                  <option value="days" ${draft.repeatUnit === 'days' ? 'selected' : ''}>${escapeHtml(t(lang, 'unitDays'))}</option>
                  <option value="weeks" ${draft.repeatUnit === 'weeks' ? 'selected' : ''}>${escapeHtml(t(lang, 'unitWeeks'))}</option>
                  <option value="months" ${draft.repeatUnit === 'months' ? 'selected' : ''}>${escapeHtml(t(lang, 'unitMonths'))}</option>
                </select>
              </label>
            </div>
            ${
              draft.dueLocal
                ? `<label class="field">${escapeHtml(t(lang, 'fieldRepeatLead'))}
                    <input type="number" min="0" max="3650" data-ed-field="repeatLeadDays" value="${escapeHtml(draft.repeatLeadDays)}" placeholder="0">
                    <small class="field-hint">${escapeHtml(t(lang, 'hintRepeatLead'))}</small>
                  </label>`
                : `<small class="info-sub">${escapeHtml(t(lang, 'inlineRepeatLeadNeedsDue'))}</small>`
            }
          </div>
        </div>
      `);
    }

    if (open.suspended) {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('pause-circle', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoSuspendedTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            <label class="field">${escapeHtml(t(lang, 'fieldSuspended'))}
              <select data-ed-field="suspendedMode">
                <option value="until" ${draft.suspendedMode === 'until' ? 'selected' : ''}>${escapeHtml(t(lang, 'optSuspendedUntil'))}</option>
                <option value="forever" ${draft.suspendedMode === 'forever' ? 'selected' : ''}>${escapeHtml(t(lang, 'optSuspendedForever'))}</option>
              </select>
            </label>
            ${
              draft.suspendedMode === 'until'
                ? `<label class="field">${escapeHtml(t(lang, 'fieldSuspendedUntil'))}
                    <input type="datetime-local" data-ed-field="suspendedLocal" value="${escapeHtml(draft.suspendedLocal || '')}">
                  </label>`
                : ''
            }
            <label class="field">${escapeHtml(t(lang, 'fieldSuspendedNote'))}
              <textarea data-ed-field="suspendedNote" rows="2" placeholder="${escapeHtml(t(lang, 'placeholderSuspendedNote'))}">${escapeHtml(draft.suspendedNote || '')}</textarea>
            </label>
          </div>
        </div>
      `);
    }

    if (open.subtasks) {
      sections.push(`
        <div class="info-card">
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
                        <input type="text" data-ed-step-text="${idx}" value="${escapeHtml(step.text)}" maxlength="200">
                        <button type="button" class="icon-button compact is-danger-hover" data-ed-step-remove="${idx}" title="${escapeHtml(t(lang, 'actionRemove'))}">${renderIcon('trash', 'icon-xs')}</button>
                      </div>`,
                      )
                      .join('')}
                  </div>`
                : ''
            }
            <div class="edit-add-row">
              <input type="text" data-ed-new-step placeholder="${escapeHtml(t(lang, 'placeholderSubtask'))}" maxlength="200">
              <button type="button" class="secondary compact" data-ed-add-step>${escapeHtml(t(lang, 'actionAdd'))}</button>
            </div>
            <label class="check-field compact-check">
              <input type="checkbox" data-ed-field="subtasksAutoFinish" ${draft.subtasksAutoFinish ? 'checked' : ''}>
              <span>${escapeHtml(t(lang, 'fieldAutoFinish'))}<small>${escapeHtml(t(lang, 'fieldAutoFinishDesc'))}</small></span>
            </label>
          </div>
        </div>
      `);
    }

    if (open.links) {
      const editingLinkIdx = draft.editingLinkIndex;
      sections.push(`
        <div class="info-card">
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
                        <button type="button" class="icon-button compact" data-ed-link-up="${index}" ${index === 0 ? 'disabled' : ''} title="${escapeHtml(t(lang, 'actionUp'))}">${renderIcon('arrow-up', 'icon-xs')}</button>
                        <button type="button" class="icon-button compact" data-ed-link-down="${index}" ${index === draft.links.length - 1 ? 'disabled' : ''} title="${escapeHtml(t(lang, 'actionDown'))}">${renderIcon('arrow-down', 'icon-xs')}</button>
                        <button type="button" class="icon-button compact" data-ed-link-edit="${index}" title="${escapeHtml(t(lang, 'actionEdit'))}">${renderIcon('pencil', 'icon-xs')}</button>
                        <button type="button" class="icon-button compact is-danger-hover" data-ed-link-remove="${index}" title="${escapeHtml(t(lang, 'actionRemove'))}">${renderIcon('trash', 'icon-xs')}</button>
                      </div>
                    </div>`,
                    )
                    .join('')
                : `<div class="info-sub">${escapeHtml(t(lang, 'emptyLinks'))}</div>`
            }
            <div class="field-grid">
              <label class="field">${escapeHtml(t(lang, 'fieldLinkTitle'))}
                <input data-ed-link-title value="${escapeHtml(draft.linkTitleDraft || '')}" placeholder="${escapeHtml(t(lang, 'placeholderLinkTitle'))}">
              </label>
              <label class="field">${escapeHtml(t(lang, 'fieldLinkUri'))}
                <input data-ed-link-uri value="${escapeHtml(draft.linkUriDraft || '')}" placeholder="${escapeHtml(t(lang, 'placeholderLinkUri'))}">
              </label>
            </div>
            <div class="inline-btn-row">
              <button type="button" class="secondary compact" data-ed-link-submit>${escapeHtml(t(lang, editingLinkIdx !== null && editingLinkIdx !== undefined ? 'actionSaveLink' : 'actionAddLink'))}</button>
              ${
                editingLinkIdx !== null && editingLinkIdx !== undefined
                  ? `<button type="button" class="text-button" data-ed-link-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>`
                  : ''
              }
            </div>
          </div>
        </div>
      `);
    }

    const addChips = [];
    if (!draftLabels.length && !showInlinePicker) {
      addChips.push(
        `<button type="button" class="add-field-chip" data-open-entity-draft-label-picker>${renderIcon('tags', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddLabels'))}</span></button>`,
      );
    }
    if (!open.note) {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ed-toggle-section="note">${renderIcon('file-text', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddNote'))}</span></button>`,
      );
    }
    if (!open.links) {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ed-toggle-section="links">${renderIcon('link', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddLinks'))}</span></button>`,
      );
    }
    if (!open.subtasks) {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ed-toggle-section="subtasks">${renderIcon('list-checks', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddSubtasks'))}</span></button>`,
      );
    }
    if (!open.due) {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ed-toggle-section="due">${renderIcon('calendar-days', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddDue'))}</span></button>`,
      );
    }
    if (!open.repeat) {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ed-toggle-section="repeat">${renderIcon('repeat', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddRepeat'))}</span></button>`,
      );
    }
    if (!open.suspended) {
      addChips.push(
        `<button type="button" class="add-field-chip" data-ed-toggle-section="suspended">${renderIcon('pause-circle', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddSuspend'))}</span></button>`,
      );
    }

    return `
      <section class="draft-card" aria-label="${escapeHtml(t(lang, 'draftNewTaskTitle'))}">
        <div class="draft-card-head">
          <div>
            <strong>${escapeHtml(t(lang, 'draftNewTaskTitle'))}</strong>
            <div class="info-sub">${escapeHtml(t(lang, 'draftHintUncommitted'))}</div>
          </div>
          <button type="button" class="icon-button compact" data-draft-entity-cancel aria-label="${escapeHtml(t(lang, 'actionCancel'))}">${renderIcon('x', 'icon-sm')}</button>
        </div>
        <input type="text" class="draft-card-title-input" data-ed-field="title" value="${escapeHtml(draft.title || '')}" placeholder="${escapeHtml(t(lang, 'placeholderTaskTitle'))}" maxlength="300" autocomplete="off">
        <div class="task-slide-sections">${sections.join('')}</div>
        ${addChips.length ? `<div class="task-add-fields-bar">${addChips.join('')}</div>` : ''}
        ${draft.error ? `<div class="edit-error inline-edit-error" role="status">${escapeHtml(draft.error)}</div>` : ''}
        <div class="draft-card-footer">
          <span></span>
          <div class="inline-edit-buttons">
            <button type="button" class="secondary compact" data-draft-entity-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>
            <button type="button" class="primary compact" data-draft-entity-commit>${renderIcon('plus', 'icon-xs')}${escapeHtml(t(lang, 'actionCreateTask'))}</button>
          </div>
        </div>
      </section>
    `;
  }

  function renderLabelDraftCard(state) {
    const draft = state.entityDraft;
    if (!draft || draft.kind !== 'label') return '';
    const lang = state.lang;
    const open = draft.openSections || {};

    return `
      <section class="draft-card" aria-label="${escapeHtml(t(lang, 'draftNewLabelTitle'))}">
        <div class="draft-card-head">
          <div>
            <strong>${escapeHtml(t(lang, 'draftNewLabelTitle'))}</strong>
            <div class="info-sub">${escapeHtml(t(lang, 'draftHintUncommitted'))}</div>
          </div>
          <button type="button" class="icon-button compact" data-draft-entity-cancel aria-label="${escapeHtml(t(lang, 'actionCancel'))}">${renderIcon('x', 'icon-sm')}</button>
        </div>
        <input type="text" class="draft-card-title-input" data-ed-field="name" value="${escapeHtml(draft.name || '')}" placeholder="${escapeHtml(t(lang, 'placeholderLabelName'))}" maxlength="120" autocomplete="off">
        <div class="task-slide-sections">
          <div class="info-card">
            <div class="info-card-head">
              ${renderIcon('palette', 'icon-sm')}
              <strong>${escapeHtml(t(lang, 'labelInfoColorTitle'))}</strong>
            </div>
            <div class="inline-edit-body">
              <div class="color-input-row">
                <span class="color-swatch-preview" style="background:${escapeHtml(draft.color || '#2196F3')}"></span>
                <input data-ed-field="color" value="${escapeHtml(draft.color || '#2196F3')}" placeholder="#2196F3" maxlength="7" aria-label="${escapeHtml(t(lang, 'fieldColorHex'))}">
                <button type="button" class="secondary compact" data-open-color-picker="entity-draft">${renderIcon('palette', 'icon-xs')}${escapeHtml(t(lang, 'actionCustomColor'))}</button>
              </div>
              <div class="color-presets">
                ${LABEL_COLOR_PRESETS.map(
                  (hex) => `
                  <button type="button" class="color-preset-chip ${String(draft.color).toUpperCase() === hex ? 'is-selected' : ''}" data-ed-color-preset="${hex}">
                    <span class="dot" style="--label-color:${hex}"></span>
                    <span>${hex}</span>
                  </button>`,
                ).join('')}
              </div>
            </div>
          </div>
          <div class="info-card">
            <div class="info-card-head">
              ${renderIcon('layers', 'icon-sm')}
              <strong>${escapeHtml(t(lang, 'labelInfoScopeTitle'))}</strong>
            </div>
            <div class="segmented" role="group" aria-label="${escapeHtml(t(lang, 'labelInfoScopeTitle'))}">
              <button type="button" data-ed-label-scope="false" aria-pressed="${!draft.scoped}">${escapeHtml(t(lang, 'globalContext'))}</button>
              <button type="button" data-ed-label-scope="true" aria-pressed="${Boolean(draft.scoped)}">${escapeHtml(t(lang, 'scopedQueue'))}</button>
            </div>
            <small class="info-sub">${escapeHtml(t(lang, 'labelScopedDesc'))}</small>
          </div>
          ${
            open.note
              ? `<div class="info-card">
                  <div class="info-card-head">
                    ${renderIcon('file-text', 'icon-sm')}
                    <strong>${escapeHtml(t(lang, 'taskInfoNoteTitle'))}</strong>
                  </div>
                  <label class="field">
                    <textarea data-ed-field="note" rows="3" maxlength="10000" aria-label="${escapeHtml(t(lang, 'taskInfoNoteTitle'))}">${escapeHtml(draft.note || '')}</textarea>
                  </label>
                </div>`
              : ''
          }
        </div>
        ${
          !open.note
            ? `<div class="task-add-fields-bar">
                <button type="button" class="add-field-chip" data-ed-toggle-section="note">${renderIcon('file-text', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddNote'))}</span></button>
              </div>`
            : ''
        }
        ${draft.error ? `<div class="edit-error inline-edit-error" role="status">${escapeHtml(draft.error)}</div>` : ''}
        <div class="draft-card-footer">
          <span></span>
          <div class="inline-edit-buttons">
            <button type="button" class="secondary compact" data-draft-entity-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>
            <button type="button" class="primary compact" data-draft-entity-commit>${renderIcon('plus', 'icon-xs')}${escapeHtml(t(lang, 'actionCreateLabel'))}</button>
          </div>
        </div>
      </section>
    `;
  }

  function renderLocationDraftCard(state) {
    const draft = state.entityDraft;
    if (!draft || draft.kind !== 'location') return '';
    const lang = state.lang;
    const isGps = draft.sourceType === 'gps';
    const open = draft.openSections || {};

    return `
      <section class="draft-card" aria-label="${escapeHtml(t(lang, 'draftNewLocationTitle'))}">
        <div class="draft-card-head">
          <div>
            <strong>${escapeHtml(t(lang, 'draftNewLocationTitle'))}</strong>
            <div class="info-sub">${escapeHtml(t(lang, 'draftHintUncommitted'))}</div>
          </div>
          <button type="button" class="icon-button compact" data-draft-entity-cancel aria-label="${escapeHtml(t(lang, 'actionCancel'))}">${renderIcon('x', 'icon-sm')}</button>
        </div>
        <input type="text" class="draft-card-title-input" data-ed-field="name" value="${escapeHtml(draft.name || '')}" placeholder="${escapeHtml(t(lang, 'placeholderLocationName'))}" maxlength="120" autocomplete="off">
        <div class="task-slide-sections">
          <div class="info-card">
            <div class="info-card-head">
              ${renderIcon('locate', 'icon-sm')}
              <strong>${escapeHtml(t(lang, 'locInfoCoordsTitle'))}</strong>
            </div>
            <div class="inline-edit-body">
              <div class="field-grid">
                <label class="field">${escapeHtml(t(lang, 'fieldSourceType'))}
                  <select data-ed-field="sourceType">
                    <option value="gps" ${draft.sourceType === 'gps' ? 'selected' : ''}>${escapeHtml(t(lang, 'sourceGps'))}</option>
                    <option value="address" ${draft.sourceType === 'address' ? 'selected' : ''}>${escapeHtml(t(lang, 'sourceAddress'))}</option>
                    <option value="plusCode" ${draft.sourceType === 'plusCode' ? 'selected' : ''}>${escapeHtml(t(lang, 'sourcePlusCode'))}</option>
                  </select>
                </label>
                <label class="field">${escapeHtml(t(lang, 'fieldRadius'))}
                  <input data-ed-field="radiusText" value="${escapeHtml(draft.radiusText)}" placeholder="150m">
                </label>
              </div>
              ${
                !isGps
                  ? `<label class="field">${escapeHtml(t(lang, draft.sourceType === 'address' ? 'sourceAddress' : 'sourcePlusCode'))}
                      <input data-ed-field="source" value="${escapeHtml(draft.source || '')}" placeholder="${escapeHtml(t(lang, draft.sourceType === 'address' ? 'placeholderAddress' : 'placeholderPlusCode'))}">
                    </label>`
                  : ''
              }
              <div class="field-grid">
                <label class="field">${escapeHtml(t(lang, 'fieldLat'))}
                  <input data-ed-field="latitude" type="number" step="any" min="-90" max="90" value="${escapeHtml(draft.latitude || '')}" ${!isGps ? 'readonly' : ''}>
                </label>
                <label class="field">${escapeHtml(t(lang, 'fieldLon'))}
                  <input data-ed-field="longitude" type="number" step="any" min="-180" max="180" value="${escapeHtml(draft.longitude || '')}" ${!isGps ? 'readonly' : ''}>
                </label>
              </div>
              <div class="inline-btn-row">
                <button type="button" class="secondary compact" data-ed-use-gps ${!isGps ? 'disabled' : ''}>
                  ${renderIcon('locate', 'icon-xs')}${escapeHtml(t(lang, 'actionUseGps'))}
                </button>
                <button type="button" class="secondary compact" data-ed-resolve ${isGps ? 'disabled' : ''}>
                  ${renderIcon('search', 'icon-xs')}${escapeHtml(t(lang, 'actionResolveSource'))}
                </button>
              </div>
            </div>
          </div>
          ${
            open.note
              ? `<div class="info-card">
                  <div class="info-card-head">
                    ${renderIcon('file-text', 'icon-sm')}
                    <strong>${escapeHtml(t(lang, 'taskInfoNoteTitle'))}</strong>
                  </div>
                  <label class="field">
                    <textarea data-ed-field="note" rows="3" maxlength="10000" aria-label="${escapeHtml(t(lang, 'taskInfoNoteTitle'))}">${escapeHtml(draft.note || '')}</textarea>
                  </label>
                </div>`
              : ''
          }
        </div>
        ${
          !open.note
            ? `<div class="task-add-fields-bar">
                <button type="button" class="add-field-chip" data-ed-toggle-section="note">${renderIcon('file-text', 'icon-xs')}<span>${escapeHtml(t(lang, 'inlineAddNote'))}</span></button>
              </div>`
            : ''
        }
        ${draft.error ? `<div class="edit-error inline-edit-error" role="status">${escapeHtml(draft.error)}</div>` : ''}
        <div class="draft-card-footer">
          <span></span>
          <div class="inline-edit-buttons">
            <button type="button" class="secondary compact" data-draft-entity-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>
            <button type="button" class="primary compact" data-draft-entity-commit>${renderIcon('plus', 'icon-xs')}${escapeHtml(t(lang, 'actionCreateLocation'))}</button>
          </div>
        </div>
      </section>
    `;
  }

  function renderQuickComposer(state, workspace, evalRes) {
    const lang = state.lang;
    const draft = state.draft;
    const modeHintText =
      draft.mode === 'priority'
        ? t(lang, 'hintPriority')
        : draft.mode === 'someday'
          ? t(lang, 'hintSomeday')
          : t(lang, 'hintQueue');
    const labelsById = new Map(workspace.labels.map((l) => [l.id, l]));
    const draftLabels = (draft.labels || [])
      .map((id) => labelsById.get(id))
      .filter(Boolean)
      .sort((a, b) => a.name.localeCompare(b.name));
    const isDraftPickerOpen = Boolean(state.draftLabelPicker);
    const showDesktopPopover = isDraftPickerOpen && !state.isCompact;

    return `
      <div class="composer ${state.mobileQuickAddOpen ? 'mobile-expanded' : ''}">
        <button type="button" class="mobile-add-trigger primary" data-toggle-mobile-add>
          ${renderIcon('plus')}
          <span>${escapeHtml(t(lang, 'quickAddNewMobile'))}</span>
        </button>

        <div class="composer-box">
          ${
            showDesktopPopover
              ? `<div class="composer-label-popover" role="dialog" aria-label="${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}">
                  <div class="composer-popover-head">
                    ${renderIcon('tags', 'icon-sm')}
                    <strong>${escapeHtml(t(lang, 'taskInfoLabelsTitle'))}</strong>
                    <span class="info-sub">${draftLabels.length}</span>
                    <button type="button" class="secondary compact ml-auto" data-close-draft-label-picker>${escapeHtml(t(lang, 'actionDone'))}</button>
                  </div>
                  ${renderLabelPickerBody({
                    mode: 'draft',
                    selectedIds: draft.labels || [],
                    pickerState: state.draftLabelPicker,
                    workspace,
                    evalRes,
                    lang,
                    showSelectedStrip: false,
                  })}
                </div>`
              : ''
          }
          <form data-form="quick-task">
            <div class="entry-row">
              <input name="title" data-draft="title" value="${escapeHtml(draft.title)}" maxlength="300" aria-label="${escapeHtml(t(lang, 'quickAddPlaceholder'))}" placeholder="${escapeHtml(t(lang, 'quickAddPlaceholder'))}" autocomplete="off" required>
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
              <div class="composer-labels-bar">
                ${
                  draftLabels.length
                    ? renderAssignedLabelChips({
                        labels: draftLabels,
                        targetKind: 'draft',
                        lang,
                        compact: true,
                      })
                    : ''
                }
                <button type="button" class="add-field-chip composer-label-trigger ${isDraftPickerOpen ? 'is-active' : ''}" data-toggle-draft-label-picker aria-expanded="${isDraftPickerOpen}">
                  ${renderIcon(draftLabels.length ? 'plus' : 'tags', 'icon-xs')}
                  <span>${escapeHtml(t(lang, draftLabels.length ? 'actionAdd' : 'inlineAddLabels'))}</span>
                </button>
              </div>
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
    const activeLabelBarHtml = renderActiveLabelBar(state, workspace);

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
        ${activeLabelBarHtml}
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

      ${activeLabelBarHtml}

      <div class="heading">
        <div>
          <h2>${escapeHtml(tierName(lang, state.tier))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, `tier${state.tier}Sub`))}</div>
        </div>
        <span class="limit">${queue.length}${limitSuffix}</span>
      </div>

      ${renderTaskDraftCard(state, workspace, evalRes)}

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
    `;
  }

  function renderLabelSlidePanel(label, state, workspace, openCount, isAnimating) {
    const lang = state.lang;
    const edit =
      state.inlineEdit &&
      state.inlineEdit.kind === 'label' &&
      state.inlineEdit.id === label.id
        ? state.inlineEdit
        : null;
    const editing = edit ? edit.section : null;
    const draft = edit ? edit.draft : null;
    const err = edit ? edit.error : '';

    const c = label.conditions || {};
    const rules = [];
    if (c.days?.length) rules.push({ type: 'days', days: c.days });
    if (c.times?.length) rules.push({ type: 'times', times: c.times });
    if (c.locationIds?.length) {
      rules.push({ type: 'locations', locationIds: c.locationIds });
    }
    const hasConditions = rules.length > 0;
    const editBtn = (section) => renderInlineEditBtn('label', label.id, section, lang);

    const sections = [];

    // 1. Note (shared)
    const noteHtml = renderNoteSection({
      kind: 'label',
      id: label.id,
      note: label.note,
      isEditing: editing === 'note',
      draft,
      error: err,
      lang,
    });
    if (noteHtml) sections.push(noteHtml);

    // 2. Links (shared)
    const linksHtml = renderLinksSection({
      kind: 'label',
      id: label.id,
      links: label.links,
      isEditing: editing === 'links',
      draft,
      error: err,
      lang,
    });
    if (linksHtml) sections.push(linksHtml);

    // 3. Color
    if (editing === 'color') {
      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('palette', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'labelInfoColorTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            <div class="color-input-row">
              <span class="color-swatch-preview" style="background:${escapeHtml(draft.color || '#2196F3')}"></span>
              <input data-ie="color" value="${escapeHtml(draft.color)}" placeholder="#2196F3" maxlength="7" aria-label="${escapeHtml(t(lang, 'fieldColorHex'))}">
              <button type="button" class="secondary compact" data-open-color-picker>${renderIcon('palette', 'icon-xs')}${escapeHtml(t(lang, 'actionCustomColor'))}</button>
            </div>
            <div class="color-presets">
              ${LABEL_COLOR_PRESETS.map(
                (hex) => `
                <button type="button" class="color-preset-chip ${String(draft.color).toUpperCase() === hex ? 'is-selected' : ''}" data-ie-color-preset="${hex}">
                  <span class="dot" style="--label-color:${hex}"></span>
                  <span>${hex}</span>
                </button>`,
              ).join('')}
            </div>
            ${renderInlineEditActions(lang, err, '', '')}
          </div>
        </div>
      `);
    } else {
      const hex = (label.color || '#2196F3').toUpperCase();
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('palette', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'labelInfoColorTitle'))}</strong>
            ${editBtn('color')}
          </div>
          <div class="inline-color-read">
            <span class="dot dot-lg" style="--label-color:${escapeHtml(hex)}"></span>
            <code class="mono-sm">${escapeHtml(hex)}</code>
          </div>
        </div>
      `);
    }

    // 4. Board Scope (direct 1-click toggle, matching Task placement)
    sections.push(`
      <div class="info-card">
        <div class="info-card-head">
          ${renderIcon('layers', 'icon-sm')}
          <strong>${escapeHtml(t(lang, 'labelInfoScopeTitle'))}</strong>
        </div>
        <div class="segmented" role="group" aria-label="${escapeHtml(t(lang, 'labelInfoScopeTitle'))}">
          <button type="button" data-direct-label-scope="false" data-label-id="${escapeHtml(label.id)}" aria-pressed="${!label.scoped}">${escapeHtml(t(lang, 'globalContext'))}</button>
          <button type="button" data-direct-label-scope="true" data-label-id="${escapeHtml(label.id)}" aria-pressed="${Boolean(label.scoped)}">${escapeHtml(t(lang, 'scopedQueue'))}</button>
        </div>
        <small class="info-sub">${escapeHtml(t(lang, 'labelScopedDesc'))}</small>
      </div>
    `);

    // 5. Activation Conditions (shared)
    if (editing === 'conditions') {
      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('sliders', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'taskInfoConditionsTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            ${renderConditionsEditorBody({
              draft,
              workspace,
              lang,
              includeModes: false,
            })}
            ${renderInlineEditActions(
              lang,
              err,
              hasConditions ? 'data-ie-clear="conditions"' : '',
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
            ${editBtn('conditions')}
          </div>
          ${renderConditionsReadRules(rules, workspace, lang, false)}
        </div>
      `);
    }

    // 6. Unset fields bar (shared)
    const addChips = [];
    if (!label.note && editing !== 'note') {
      addChips.push(
        renderAddFieldChip('label', label.id, 'note', 'file-text', t(lang, 'inlineAddNote')),
      );
    }
    if (!label.links?.length && editing !== 'links') {
      addChips.push(
        renderAddFieldChip('label', label.id, 'links', 'link', t(lang, 'inlineAddLinks')),
      );
    }
    if (!hasConditions && editing !== 'conditions') {
      addChips.push(
        renderAddFieldChip('label', label.id, 'conditions', 'sliders', t(lang, 'inlineAddConditions')),
      );
    }

    return renderEntitySlideShell({
      kind: 'label',
      id: label.id,
      isAnimating,
      regionLabel: t(lang, 'labelInfoTitle'),
      metaExtraHtml: `<span class="meta-pill tone-soft">${escapeHtml(t(lang, 'openTasksCount', { count: openCount }))}</span>`,
      deleteConfirmText: t(lang, 'inlineDeleteLabelConfirm'),
      isConfirmingDelete: state.inlineDeleteConfirmKey === `label:${label.id}`,
      sectionsHtml: sections.join(''),
      addChipsHtml: addChips.join(''),
      lang,
    });
  }

  function renderLabelCard(label, state, workspace, evalRes) {
    const lang = state.lang;
    const key = `label:${label.id}`;
    const openCount = evalRes.openCountByLabel.get(label.id) || 0;
    const isExpanded =
      state.expandedEntity?.kind === 'label' && state.expandedEntity?.id === label.id;
    const isAnimating = state.justExpandedKey === key;
    const isEditingName =
      isExpanded &&
      state.inlineEdit?.kind === 'label' &&
      state.inlineEdit?.id === label.id &&
      state.inlineEdit?.section === 'name';

    let metadataHtml = '';
    if (!isExpanded) {
      const toggleAttr = `data-toggle-entity="${escapeHtml(key)}"`;
      const c = label.conditions || {};
      const hasConditions = Boolean(
        c.days?.length || c.times?.length || c.locationIds?.length,
      );
      const badges = [
        `<button type="button" class="meta-pill is-interactive ${label.scoped ? 'tone-accent' : ''}" ${toggleAttr}>${renderIcon('layers', 'icon-xs')}${escapeHtml(t(lang, label.scoped ? 'scopedQueue' : 'globalContext'))}</button>`,
        `<button type="button" class="meta-pill is-interactive tone-soft" ${toggleAttr}>${escapeHtml(t(lang, 'openTasksCount', { count: openCount }))}</button>`,
      ];
      if (label.note) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${renderIcon('file-text', 'icon-xs')}${escapeHtml(t(lang, 'badgeNote'))}</button>`,
        );
      }
      if (label.links?.length) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${renderIcon('link', 'icon-xs')}${escapeHtml(t(lang, label.links.length === 1 ? 'badgeLinkSingular' : 'badgeLinks', { count: label.links.length }))}</button>`,
        );
      }
      if (hasConditions) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${renderIcon('sliders', 'icon-xs')}${escapeHtml(t(lang, 'badgeConditions'))}</button>`,
        );
      }
      metadataHtml = `<div class="metadata">${badges.join('')}</div>`;
    }

    return renderEntityCard({
      kind: 'label',
      id: label.id,
      isExpanded,
      isEditingTitle: isEditingName,
      title: label.name,
      titleField: 'name',
      titleMaxLength: 120,
      titleAriaLabel: t(lang, 'inlineEditName'),
      titleEditDraft: isEditingName ? state.inlineEdit.draft.name : '',
      titleEditError: isEditingName ? state.inlineEdit.error : '',
      leadingHtml: `
        <button type="button" class="entity-lead" data-toggle-entity="${escapeHtml(key)}" aria-expanded="${isExpanded}" aria-label="${escapeHtml(label.name)}">
          <span class="dot dot-lg" style="--label-color:${escapeHtml(label.color || '#00648b')}"></span>
        </button>
      `,
      collapsedMetadataHtml: metadataHtml,
      slidePanelHtml: isExpanded
        ? renderLabelSlidePanel(label, state, workspace, openCount, isAnimating)
        : '',
      lang,
    });
  }

  function locationSourceLabel(sourceType, lang) {
    if (sourceType === 'address') return t(lang, 'sourceAddress');
    if (sourceType === 'plusCode') return t(lang, 'sourcePlusCode');
    return t(lang, 'sourceGps');
  }

  function renderLocationSlidePanel(loc, state, openCount, isAnimating) {
    const lang = state.lang;
    const edit =
      state.inlineEdit &&
      state.inlineEdit.kind === 'location' &&
      state.inlineEdit.id === loc.id
        ? state.inlineEdit
        : null;
    const editing = edit ? edit.section : null;
    const draft = edit ? edit.draft : null;
    const err = edit ? edit.error : '';

    const editBtn = (section) =>
      renderInlineEditBtn('location', loc.id, section, lang);

    const sections = [];

    // 1. Note (shared)
    const noteHtml = renderNoteSection({
      kind: 'location',
      id: loc.id,
      note: loc.note,
      isEditing: editing === 'note',
      draft,
      error: err,
      lang,
    });
    if (noteHtml) sections.push(noteHtml);

    // 2. Coordinates, Source & Radius
    if (editing === 'coordinates') {
      const isGps = draft.sourceType === 'gps';
      sections.push(`
        <div class="info-card is-editing">
          <div class="info-card-head">
            ${renderIcon('locate', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'locInfoCoordsTitle'))}</strong>
          </div>
          <div class="inline-edit-body">
            <div class="field-grid">
              <label class="field">${escapeHtml(t(lang, 'fieldSourceType'))}
                <select data-ie="sourceType">
                  <option value="gps" ${draft.sourceType === 'gps' ? 'selected' : ''}>${escapeHtml(t(lang, 'sourceGps'))}</option>
                  <option value="address" ${draft.sourceType === 'address' ? 'selected' : ''}>${escapeHtml(t(lang, 'sourceAddress'))}</option>
                  <option value="plusCode" ${draft.sourceType === 'plusCode' ? 'selected' : ''}>${escapeHtml(t(lang, 'sourcePlusCode'))}</option>
                </select>
              </label>
              <label class="field">${escapeHtml(t(lang, 'fieldRadius'))}
                <input data-ie="radiusText" value="${escapeHtml(draft.radiusText)}" placeholder="150m">
              </label>
            </div>
            ${
              !isGps
                ? `<label class="field">${escapeHtml(t(lang, draft.sourceType === 'address' ? 'sourceAddress' : 'sourcePlusCode'))}
                    <input data-ie="source" value="${escapeHtml(draft.source)}" placeholder="${escapeHtml(t(lang, draft.sourceType === 'address' ? 'placeholderAddress' : 'placeholderPlusCode'))}">
                  </label>`
                : ''
            }
            <div class="field-grid">
              <label class="field">${escapeHtml(t(lang, 'fieldLat'))}
                <input data-ie="latitude" type="number" step="any" min="-90" max="90" value="${escapeHtml(draft.latitude)}" ${!isGps ? 'readonly' : ''}>
              </label>
              <label class="field">${escapeHtml(t(lang, 'fieldLon'))}
                <input data-ie="longitude" type="number" step="any" min="-180" max="180" value="${escapeHtml(draft.longitude)}" ${!isGps ? 'readonly' : ''}>
              </label>
            </div>
            <div class="inline-btn-row">
              <button type="button" class="secondary compact" data-ie-use-gps ${!isGps ? 'disabled' : ''}>
                ${renderIcon('locate', 'icon-xs')}${escapeHtml(t(lang, 'actionUseGps'))}
              </button>
              <button type="button" class="secondary compact" data-ie-resolve ${isGps ? 'disabled' : ''}>
                ${renderIcon('search', 'icon-xs')}${escapeHtml(t(lang, 'actionResolveSource'))}
              </button>
            </div>
            ${renderInlineEditActions(lang, err, '', '')}
          </div>
        </div>
      `);
    } else {
      sections.push(`
        <div class="info-card">
          <div class="info-card-head">
            ${renderIcon('locate', 'icon-sm')}
            <strong>${escapeHtml(t(lang, 'locInfoCoordsTitle'))}</strong>
            <span class="pill-badge">${escapeHtml(locationSourceLabel(loc.sourceType, lang))}</span>
            ${editBtn('coordinates')}
          </div>
          ${
            loc.sourceType !== 'gps' && loc.source
              ? `<div>${escapeHtml(loc.source)}</div>`
              : ''
          }
          <code class="mono-sm">${Number(loc.latitude).toFixed(6)}, ${Number(loc.longitude).toFixed(6)}</code>
          <small class="info-sub">${escapeHtml(t(lang, 'locInfoRadius', { radius: formatRadiusMeters(loc.radius) }))}</small>
        </div>
      `);
    }

    // 3. Unset fields bar (shared)
    const addChips = [];
    if (!loc.note && editing !== 'note') {
      addChips.push(
        renderAddFieldChip('location', loc.id, 'note', 'file-text', t(lang, 'inlineAddNote')),
      );
    }

    return renderEntitySlideShell({
      kind: 'location',
      id: loc.id,
      isAnimating,
      regionLabel: t(lang, 'locationInfoTitle'),
      metaExtraHtml: `<span class="meta-pill tone-soft">${escapeHtml(t(lang, 'openTasksCount', { count: openCount }))}</span>`,
      deleteConfirmText: t(lang, 'inlineDeleteLocationConfirm'),
      isConfirmingDelete: state.inlineDeleteConfirmKey === `location:${loc.id}`,
      sectionsHtml: sections.join(''),
      addChipsHtml: addChips.join(''),
      lang,
    });
  }

  function renderLocationCard(loc, state, evalRes) {
    const lang = state.lang;
    const key = `location:${loc.id}`;
    const openCount = evalRes.openCountByLocation.get(loc.id) || 0;
    const isExpanded =
      state.expandedEntity?.kind === 'location' && state.expandedEntity?.id === loc.id;
    const isAnimating = state.justExpandedKey === key;
    const isEditingName =
      isExpanded &&
      state.inlineEdit?.kind === 'location' &&
      state.inlineEdit?.id === loc.id &&
      state.inlineEdit?.section === 'name';

    let metadataHtml = '';
    if (!isExpanded) {
      const toggleAttr = `data-toggle-entity="${escapeHtml(key)}"`;
      const badges = [
        `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${renderIcon('locate', 'icon-xs')}${escapeHtml(locationSourceLabel(loc.sourceType, lang))}</button>`,
        `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${Number(loc.latitude).toFixed(4)}, ${Number(loc.longitude).toFixed(4)} · ${escapeHtml(formatRadiusMeters(loc.radius))}</button>`,
        `<button type="button" class="meta-pill is-interactive tone-soft" ${toggleAttr}>${escapeHtml(t(lang, 'openTasksCount', { count: openCount }))}</button>`,
      ];
      if (loc.note) {
        badges.push(
          `<button type="button" class="meta-pill is-interactive" ${toggleAttr}>${renderIcon('file-text', 'icon-xs')}${escapeHtml(t(lang, 'badgeNote'))}</button>`,
        );
      }
      metadataHtml = `<div class="metadata">${badges.join('')}</div>`;
    }

    return renderEntityCard({
      kind: 'location',
      id: loc.id,
      isExpanded,
      isEditingTitle: isEditingName,
      title: loc.name,
      titleField: 'name',
      titleMaxLength: 120,
      titleAriaLabel: t(lang, 'inlineEditName'),
      titleEditDraft: isEditingName ? state.inlineEdit.draft.name : '',
      titleEditError: isEditingName ? state.inlineEdit.error : '',
      leadingHtml: `
        <button type="button" class="entity-lead" data-toggle-entity="${escapeHtml(key)}" aria-expanded="${isExpanded}" aria-label="${escapeHtml(loc.name)}">
          ${renderIcon('map-pin')}
        </button>
      `,
      collapsedMetadataHtml: metadataHtml,
      slidePanelHtml: isExpanded
        ? renderLocationSlidePanel(loc, state, openCount, isAnimating)
        : '',
      lang,
    });
  }

  function renderManagerView(kind, state, workspace, evalRes) {
    const lang = state.lang;
    const isLabels = kind === 'labels';
    const items = [
      ...(isLabels ? workspace.labels : workspace.locations),
    ].sort((a, b) => a.name.localeCompare(b.name));
    const backLabel = state.returnContext?.searchOpen
      ? t(lang, 'actionBackSearch')
      : t(lang, 'actionBackTasks');

    return `
      <button type="button" class="back" data-go-back>${renderIcon('arrow-left', 'icon-sm')}${escapeHtml(backLabel)}</button>
      <div class="heading">
        <div>
          <h2>${escapeHtml(t(lang, isLabels ? 'sectionLabels' : 'sectionLocations'))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, isLabels ? 'labelsManagerSub' : 'locationsManagerSub'))}</div>
        </div>
        <span class="limit">${items.length}</span>
      </div>

      <form class="quick-create-card" data-form="quick-create-${kind}">
        <input name="name" placeholder="${escapeHtml(t(lang, isLabels ? 'placeholderQuickLabel' : 'placeholderQuickLocation'))}" autocomplete="off" maxlength="120" required>
        <div class="quick-create-actions">
          <button type="button" class="text-button" data-quick-create-expand="${kind}">
            ${renderIcon('sliders', 'icon-xs')} ${escapeHtml(t(lang, 'quickAddAdvanced'))}
          </button>
          <button type="submit" class="primary">
            ${renderIcon('plus', 'icon-sm')}<span>${escapeHtml(t(lang, 'actionAdd'))}</span>
          </button>
        </div>
      </form>

      ${isLabels ? renderLabelDraftCard(state) : renderLocationDraftCard(state)}

      <div class="tasks">
        ${
          items.length
            ? items
                .map((item) =>
                  isLabels
                    ? renderLabelCard(item, state, workspace, evalRes)
                    : renderLocationCard(item, state, evalRes),
                )
                .join('')
            : `<div class="empty">${escapeHtml(t(lang, isLabels ? 'emptyLabels' : 'emptyLocations'))}</div>`
        }
      </div>
    `;
  }

  window.TT2.viewsCore = {
    TIER_ICONS,
    tierName,
    filterPickerLabels,
    renderChrome,
    renderSidebar,
    renderBanners,
    renderFullFileReadError,
    renderLoadingView,
    renderFloatingNotices,
    renderTaskView,
    renderQuickComposer,
    renderManagerView,
    renderMobileLabelPickerSheet,
  };
})();
