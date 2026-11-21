(() => {
  const root = document.getElementById('tt2');
  const app = root.querySelector('.app');

  const {
    t,
    resolveLang,
    formatLocalDatetimeInput,
    localDatetimeInputToIsoUtc,
    suggestWorkspaceFileName,
  } = window.TT2.i18n;

  const {
    NOW_UTC_MS,
    LABEL_COLOR_PRESETS,
    SIMULATED_LOCATIONS,
    generateBase62Id,
    resolveOffsetMinutes,
    parseRadiusMeters,
    defaultConfig,
    createSeedWorkspaces,
    createSeedLogs,
    evaluateBoard,
    completeTask,
    restoreTask,
    downgradeTask,
    serializeTdf080,
    simulateResolveLocationSource,
  } = window.TT2.engine;

  const {
    tierName,
    filterPickerLabels,
    renderChrome,
    renderSidebar,
    renderBanners,
    renderFullFileReadError,
    renderTaskView,
    renderManagerView,
    renderMobileLabelPickerSheet,
  } = window.TT2.viewsCore;

  const {
    renderSettingsView,
    renderLogViewerView,
    renderRawTdfView,
    renderConflictResolutionView,
    renderRecoveryResolutionView,
    renderActiveModal,
  } = window.TT2.viewsSecondary;

  const workspaces = createSeedWorkspaces();

  const state = {
    lang: 'en',
    workspaces,
    activeWorkspaceId: workspaces[0].id,
    nowMs: NOW_UTC_MS,
    view: 'tasks',
    tier: 0,
    label: '',
    drawer: false,
    searchOpen: false,
    searchQuery: '',
    mobileQuickAddOpen: false,
    isCompact: false,
    sidebarLabelFilter: '',
    taskLabelPicker: null,
    draftLabelPicker: null,
    expandedEntity: null,
    justExpandedKey: null,
    scrollToEntityKey: null,
    inlineEdit: null,
    inlineDeleteConfirmKey: null,
    editingHistoryIndex: null,
    historyEditDraft: '',
    draft: { title: '', mode: 'queue', labels: [] },
    message: '',
    showUndoAction: false,
    recoveryNotice: null,
    undoStack: [],
    modal: null,
    simState: 'normal',
    bannerDismissed: false,
    syncing: false,
    simLocationKey: 'office',
    locationFix: { ...SIMULATED_LOCATIONS.office },
    locationSearching: false,
    showPassword: false,
    settingsBanner: null,
    logs: createSeedLogs(workspaces[0].id),
    logFilterLevel: 'debug',
    logFilterTag: '',
    conflictItems: [],
    recoveryItems: [],
  };

  function activeWorkspace() {
    return (
      state.workspaces.find((w) => w.id === state.activeWorkspaceId) ||
      state.workspaces[0]
    );
  }

  function logEvent(level, tag, eventName, fields = {}) {
    const ws = activeWorkspace();
    if (!ws.config.diagnosticsEnabled) return;
    const ts = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
    const kv = Object.entries(fields)
      .map(([k, v]) => `${k}=${v}`)
      .join(' ');
    const line = `${ts} [${level.toUpperCase()}] [${tag.toUpperCase()}] ${eventName}${kv ? ` | ${kv}` : ''}`;
    state.logs.push(line);
    if (state.logs.length > 500) state.logs.splice(2, state.logs.length - 500);
  }

  function evalContext() {
    return {
      nowMs: state.nowMs,
      activeLabelId: state.label || null,
      locationFix: state.locationFix,
    };
  }

  function copyToClipboard(text, messageKey) {
    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(text).catch(() => {});
    }
    state.message = t(state.lang, messageKey);
    state.showUndoAction = false;
    render();
  }

  function pushUndo(kind, taskTitle) {
    const ws = activeWorkspace();
    state.undoStack.push({
      kind,
      taskTitle,
      tasks: structuredClone(ws.tasks),
      queue: [...ws.queue],
      deleted: structuredClone(ws.deleted),
    });
    if (state.undoStack.length > 10) state.undoStack.shift();
    state.showUndoAction = true;
  }

  function performUndo() {
    if (!state.undoStack.length) return;
    const ws = activeWorkspace();
    const entry = state.undoStack.pop();
    ws.tasks = entry.tasks;
    ws.queue = entry.queue;
    ws.deleted = entry.deleted;
    state.showUndoAction = state.undoStack.length > 0;
    state.message =
      state.undoStack.length > 0
        ? t(state.lang, 'msgUndoDone', { remaining: state.undoStack.length })
        : t(state.lang, 'msgUndoEmpty');
    logEvent('info', 'ui', 'ui.undo.applied', {
      kind: entry.kind,
      remaining: state.undoStack.length,
    });
    render();
  }

  function seedConflictItems() {
    const ws = activeWorkspace();
    const firstTask = ws.tasks[0];
    const secondTask = ws.tasks[1];
    state.conflictItems = [
      {
        entityType: 'task',
        id: firstTask ? firstTask.id : 'TskConf001',
        title: firstTask ? firstTask.title : 'Conflicted task',
        choice: 'undelete',
        detail: {
          de: 'Lokal bearbeitet (2026-11-21 09:40), aber auf WebDAV als gelöscht markiert (2026-11-21 09:12).',
          en: 'Edited locally (2026-11-21 09:40), while deleted on WebDAV (2026-11-21 09:12).',
        },
      },
      {
        entityType: 'label',
        id: ws.labels[1]?.id || 'LblConf002',
        title: ws.labels[1]?.name || 'Client Vespera Systems',
        choice: 'undelete',
        detail: {
          de: 'Referenz-Link lokal hinzugefügt, während ein anderes Gerät das Label gelöscht hat.',
          en: 'Reference link added locally while another device deleted the label.',
        },
      },
    ];
    if (secondTask) {
      state.recoveryItems = [
        {
          entityType: 'task',
          id: secondTask.id,
          title: secondTask.title,
          choice: 'recoverAsNew',
          detail: {
            de: 'Löschgeneration stieg von 3 auf 5. Lokale Aufgabe fehlt auf dem Remote-Stand und benötigt eine Wiederherstellungsentscheidung.',
            en: 'Deletion generation advanced from 3 to 5. Local task is absent remotely and requires recovery.',
          },
        },
      ];
    }
  }

  function syncPreviewToolbarFromConfig() {
    const ws = activeWorkspace();
    const cfg = ws.config;
    document.documentElement.dataset.theme = cfg.themePalette;
    const effectiveMode = cfg.themeMode === 'dark' ? 'dark' : 'light';
    document.documentElement.dataset.mode = effectiveMode;
    document.documentElement.lang = state.lang;

    root.querySelectorAll('[data-theme-preset]').forEach((btn) => {
      btn.setAttribute(
        'aria-pressed',
        String(btn.dataset.themePreset === cfg.themePalette),
      );
    });
    root.querySelectorAll('[data-color-mode]').forEach((btn) => {
      btn.setAttribute(
        'aria-pressed',
        String(btn.dataset.colorMode === effectiveMode),
      );
    });
    root.querySelectorAll('[data-lang]').forEach((btn) => {
      btn.setAttribute('aria-pressed', String(btn.dataset.lang === state.lang));
    });

    const labelMap = {
      view: 'previewView',
      theme: 'previewTheme',
      mode: 'previewMode',
      lang: 'previewLang',
      sim: 'previewSim',
    };
    root.querySelectorAll('[data-preview-label]').forEach((el) => {
      const key = labelMap[el.dataset.previewLabel];
      if (key) el.textContent = t(state.lang, key);
    });
    const mobBtn = root.querySelector('[data-device="mobile"]');
    if (mobBtn) mobBtn.textContent = t(state.lang, 'previewMobile');
    const lightBtn = root.querySelector('[data-color-mode="light"]');
    if (lightBtn) lightBtn.textContent = t(state.lang, 'previewLight');
    const darkBtn = root.querySelector('[data-color-mode="dark"]');
    if (darkBtn) darkBtn.textContent = t(state.lang, 'previewDark');

    const simOptionKeys = {
      normal: 'simNormal',
      syncing: 'simSyncing',
      sync_error: 'simSyncError',
      file_read_banner: 'simFileReadBanner',
      file_read_full: 'simFileReadFull',
      conflict_deletion: 'simConflictDeletion',
      conflict_recovery: 'simConflictRecovery',
      generation_rollback: 'simGenRollback',
      settings_backup: 'simSettingsBackup',
      settings_quarantine: 'simSettingsQuarantine',
    };
    root.querySelectorAll('[data-sim-state] option').forEach((opt) => {
      const key = simOptionKeys[opt.value];
      if (key) opt.textContent = t(state.lang, key);
    });
  }

  function renderMainContent(workspace, evalRes) {
    if (state.simState === 'file_read_full' && state.view === 'tasks') {
      return renderFullFileReadError(state);
    }
    switch (state.view) {
      case 'tasks':
        return renderTaskView(state, workspace, evalRes);
      case 'labels':
      case 'locations':
        return renderManagerView(state.view, state, workspace, evalRes);
      case 'settings':
        return renderSettingsView(state, workspace);
      case 'logs':
        return renderLogViewerView(state, workspace);
      case 'raw-tdf':
        return renderRawTdfView(state, workspace);
      case 'conflict-resolution':
        return renderConflictResolutionView(state);
      case 'recovery-resolution':
        return renderRecoveryResolutionView(state);
      default:
        return renderTaskView(state, workspace, evalRes);
    }
  }

  function captureFocusDescriptor() {
    const active = document.activeElement;
    if (!active || !app.contains(active)) return null;
    if (!active.matches('input, textarea, select')) return null;
    for (const attr of active.attributes) {
      if (attr.name.startsWith('data-')) {
        return {
          selector: `[${attr.name}="${CSS.escape(attr.value)}"]`,
          start: active.selectionStart,
          end: active.selectionEnd,
        };
      }
    }
    return null;
  }

  function restoreFocusDescriptor(desc) {
    if (!desc) return;
    const target = app.querySelector(desc.selector);
    if (!target) return;
    target.focus({ preventScroll: true });
    if (
      typeof desc.start === 'number' &&
      typeof target.setSelectionRange === 'function'
    ) {
      try {
        target.setSelectionRange(desc.start, desc.end);
      } catch {
        // Ignore non-selectable input types (number, time, etc.)
      }
    }
  }

  let lastMainScrollScope = '';
  let lastSidebarWorkspaceId = '';
  let lastLabelPickerScope = '';

  function isCompactViewport() {
    return (
      Boolean(root.querySelector('.stage')?.classList.contains('mobile')) ||
      window.innerWidth <= 720
    );
  }

  function render() {
    state.isCompact = isCompactViewport();
    const focusDesc = captureFocusDescriptor();
    const prevSidebarScroll = app.querySelector('.sidebar')?.scrollTop || 0;
    const prevSidebarLabelScroll =
      app.querySelector('.sidebar-label-list')?.scrollTop || 0;
    const prevMainScroll = app.querySelector('.main')?.scrollTop || 0;
    const prevPickerListScroll =
      app.querySelector('.label-picker-list')?.scrollTop || 0;
    const ws = activeWorkspace();
    const evalRes = evaluateBoard(ws, evalContext());
    syncPreviewToolbarFromConfig();

    const mainScrollScope = `${state.activeWorkspaceId}:${state.view}:${state.tier}:${state.label}:${state.searchOpen}`;
    const labelPickerScope = state.taskLabelPicker
      ? `task:${state.taskLabelPicker.taskId}:${state.taskLabelPicker.scopeFilter}:${state.taskLabelPicker.query}`
      : state.draftLabelPicker
        ? `draft:${state.draftLabelPicker.scopeFilter}:${state.draftLabelPicker.query}`
        : '';

    app.innerHTML = `
      ${renderChrome(state, ws)}
      <div class="layout">
        ${state.drawer ? '<button type="button" class="shade" data-menu aria-label="Close menu"></button>' : ''}
        <nav class="sidebar ${state.drawer ? 'drawer-open' : ''}" aria-label="Primary Navigation">
          ${renderSidebar(state, ws, evalRes)}
        </nav>
        <main class="main">
          ${renderBanners(state, ws)}
          ${renderMainContent(ws, evalRes)}
        </main>
      </div>
      ${renderMobileLabelPickerSheet(state, ws, evalRes)}
      ${renderActiveModal(state, ws)}
    `;

    const nextSidebar = app.querySelector('.sidebar');
    if (nextSidebar && lastSidebarWorkspaceId === state.activeWorkspaceId) {
      nextSidebar.scrollTop = prevSidebarScroll;
    }
    const nextSidebarLabels = app.querySelector('.sidebar-label-list');
    if (nextSidebarLabels && lastSidebarWorkspaceId === state.activeWorkspaceId) {
      nextSidebarLabels.scrollTop = prevSidebarLabelScroll;
    }
    lastSidebarWorkspaceId = state.activeWorkspaceId;

    const nextMain = app.querySelector('.main');
    if (nextMain && lastMainScrollScope === mainScrollScope) {
      nextMain.scrollTop = prevMainScroll;
    }
    lastMainScrollScope = mainScrollScope;

    const nextPickerList = app.querySelector('.label-picker-list');
    if (nextPickerList && labelPickerScope && lastLabelPickerScope === labelPickerScope) {
      nextPickerList.scrollTop = prevPickerListScroll;
    }
    lastLabelPickerScope = labelPickerScope;

    if (state.justExpandedKey) {
      const panel = app.querySelector(
        `[data-slide-panel="${CSS.escape(state.justExpandedKey)}"]`,
      );
      if (panel) {
        void panel.offsetHeight;
        panel.classList.add('is-open');
      }
      state.justExpandedKey = null;
    }

    if (state.scrollToEntityKey) {
      const card = app.querySelector(
        `[data-entity-card="${CSS.escape(state.scrollToEntityKey)}"]`,
      );
      if (card) {
        card.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      }
      state.scrollToEntityKey = null;
    }

    if (state.modal?.type === 'color-picker') {
      drawHsvWheel();
    }
    restoreFocusDescriptor(focusDesc);
  }

  /* ==========================================================================
     HSV Color Wheel Helpers
     ========================================================================== */

  function hexToHsv(rawHex) {
    const clean = String(rawHex || '#2196F3').replace('#', '');
    if (!/^[0-9a-fA-F]{6}$/.test(clean)) return { h: 207, s: 0.86, v: 0.95 };
    const r = parseInt(clean.slice(0, 2), 16) / 255;
    const g = parseInt(clean.slice(2, 4), 16) / 255;
    const b = parseInt(clean.slice(4, 6), 16) / 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const d = max - min;
    let h = 0;
    if (d !== 0) {
      if (max === r) h = 60 * (((g - b) / d) % 6);
      else if (max === g) h = 60 * ((b - r) / d + 2);
      else h = 60 * ((r - g) / d + 4);
    }
    if (h < 0) h += 360;
    const s = max === 0 ? 0 : d / max;
    return { h, s, v: max };
  }

  function hsvToHex(h, s, v) {
    const c = v * s;
    const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
    const m = v - c;
    let r = 0;
    let g = 0;
    let b = 0;
    if (h < 60) [r, g, b] = [c, x, 0];
    else if (h < 120) [r, g, b] = [x, c, 0];
    else if (h < 180) [r, g, b] = [0, c, x];
    else if (h < 240) [r, g, b] = [0, x, c];
    else if (h < 300) [r, g, b] = [x, 0, c];
    else [r, g, b] = [c, 0, x];
    const toHex = (n) =>
      Math.round((n + m) * 255)
        .toString(16)
        .padStart(2, '0')
        .toUpperCase();
    return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
  }

  function drawHsvWheel() {
    const canvas = app.querySelector('[data-hsv-wheel]');
    if (!canvas || state.modal?.type !== 'color-picker') return;
    const ctx = canvas.getContext('2d');
    const size = canvas.width;
    const radius = size / 2;
    const { h, s, v } = state.modal;

    const image = ctx.createImageData(size, size);
    const data = image.data;
    for (let y = 0; y < size; y += 1) {
      for (let x = 0; x < size; x += 1) {
        const dx = x - radius;
        const dy = y - radius;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist > radius) continue;
        const sat = Math.min(1, dist / radius);
        let deg = (Math.atan2(dy, dx) * 180) / Math.PI;
        if (deg < 0) deg += 360;
        const hex = hsvToHex(deg, sat, v);
        const idx = (y * size + x) * 4;
        data[idx] = parseInt(hex.slice(1, 3), 16);
        data[idx + 1] = parseInt(hex.slice(3, 5), 16);
        data[idx + 2] = parseInt(hex.slice(5, 7), 16);
        data[idx + 3] = 255;
      }
    }
    ctx.putImageData(image, 0, 0);

    // Draw thumb indicator
    const rad = (h * Math.PI) / 180;
    const tx = radius + Math.cos(rad) * s * (radius - 2);
    const ty = radius + Math.sin(rad) * s * (radius - 2);
    ctx.beginPath();
    ctx.arc(tx, ty, 8, 0, Math.PI * 2);
    ctx.fillStyle = state.modal.hex;
    ctx.fill();
    ctx.lineWidth = 2.5;
    ctx.strokeStyle = '#ffffff';
    ctx.stroke();
    ctx.lineWidth = 1;
    ctx.strokeStyle = 'rgba(0,0,0,0.5)';
    ctx.stroke();
  }

  function updateWheelFromPointer(canvas, clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    const x = ((clientX - rect.left) / rect.width) * canvas.width;
    const y = ((clientY - rect.top) / rect.height) * canvas.height;
    const radius = canvas.width / 2;
    const dx = x - radius;
    const dy = y - radius;
    const s = Math.min(1, Math.sqrt(dx * dx + dy * dy) / radius);
    let h = (Math.atan2(dy, dx) * 180) / Math.PI;
    if (h < 0) h += 360;
    state.modal.h = h;
    state.modal.s = s;
    state.modal.hex = hsvToHex(h, s, state.modal.v);
    drawHsvWheel();
    const swatch = app.querySelector('[data-wheel-swatch]');
    const hexEl = app.querySelector('[data-wheel-hex]');
    if (swatch) swatch.style.background = state.modal.hex;
    if (hexEl) hexEl.textContent = state.modal.hex;
  }

  /* ==========================================================================
     Unified Inline Section Editing, Expandable Entities & Direct Toggles
     ========================================================================== */

  function clearExpandedState() {
    state.expandedEntity = null;
    state.justExpandedKey = null;
    state.scrollToEntityKey = null;
    state.inlineEdit = null;
    state.taskLabelPicker = null;
    state.inlineDeleteConfirmKey = null;
    state.editingHistoryIndex = null;
    state.historyEditDraft = '';
  }

  function openManagedEntity(viewKind, id) {
    const entityKind = viewKind === 'labels' ? 'label' : 'location';
    const key = `${entityKind}:${id}`;
    const alreadyExpanded =
      state.view === viewKind &&
      state.expandedEntity?.kind === entityKind &&
      state.expandedEntity?.id === id;
    state.drawer = false;
    state.modal = null;
    state.draftLabelPicker = null;
    state.searchOpen = false;
    state.view = viewKind;
    if (!alreadyExpanded) {
      clearExpandedState();
      state.expandedEntity = { kind: entityKind, id };
      state.justExpandedKey = key;
    }
    state.scrollToEntityKey = key;
    logEvent('info', 'ui', 'ui.managed_entity.open', { kind: entityKind, id });
    render();
  }

  function buildTaskInlineDraft(task, section, offset) {
    const c = task.conditions || {};
    if (section === 'title') return { title: task.title };
    if (section === 'note') return { note: task.note || '' };
    if (section === 'links') {
      return {
        links: structuredClone(task.links || []),
        editingLinkIndex: null,
        linkTitleDraft: '',
        linkUriDraft: '',
      };
    }
    if (section === 'subtasks') {
      return {
        subtasksAutoFinish: Boolean(task.subtasksAutoFinish),
        subtasks: structuredClone(task.subtasks || []),
      };
    }
    if (section === 'due') {
      return {
        dueLocal: task.dueAt ? formatLocalDatetimeInput(task.dueAt, offset) : '',
        autoDue: !task.duePassive,
        dueNote: task.dueNote || '',
      };
    }
    if (section === 'repeat') {
      return {
        repeatEvery: task.repeat?.count ?? 1,
        repeatUnit: task.repeat?.unit ?? 'weeks',
        repeatLeadDays: task.repeat?.leadDays ?? 0,
      };
    }
    if (section === 'suspended') {
      return {
        suspendedMode:
          task.suspendedMode && task.suspendedMode !== 'none'
            ? task.suspendedMode
            : 'until',
        suspendedLocal: task.suspendedAt
          ? formatLocalDatetimeInput(task.suspendedAt, offset)
          : '',
        suspendedNote: task.suspendedNote || '',
      };
    }
    if (section === 'prereqs') {
      return {
        prerequisites: (task.blockedBy || []).map((d) => d.taskId),
        prereqQuery: '',
      };
    }
    if (section === 'conditions') {
      return {
        ignoreLabels: Boolean(c.ignoreLabels),
        daysMode: c.daysMode || 'inherit',
        days: [...(c.days || [])],
        timeMode: c.timeMode || 'inherit',
        times: structuredClone(c.times || []),
        placesMode: c.placesMode || 'inherit',
        locationIds: [...(c.locationIds || [])],
      };
    }
    return null;
  }

  function buildLabelInlineDraft(label, section) {
    const c = label.conditions || {};
    if (section === 'name') return { name: label.name };
    if (section === 'note') return { note: label.note || '' };
    if (section === 'color') return { color: label.color || '#2196F3' };
    if (section === 'links') {
      return {
        links: structuredClone(label.links || []),
        editingLinkIndex: null,
        linkTitleDraft: '',
        linkUriDraft: '',
      };
    }
    if (section === 'conditions') {
      return {
        days: [...(c.days || [])],
        times: structuredClone(c.times || []),
        locationIds: [...(c.locationIds || [])],
      };
    }
    return null;
  }

  function buildLocationInlineDraft(loc, section) {
    if (section === 'name') return { name: loc.name };
    if (section === 'note') return { note: loc.note || '' };
    if (section === 'coordinates') {
      return {
        sourceType: loc.sourceType || 'gps',
        source: loc.sourceType === 'gps' ? '' : loc.source || '',
        latitude: String(loc.latitude),
        longitude: String(loc.longitude),
        radiusText: `${loc.radius}m`,
      };
    }
    return null;
  }

  function startInlineEdit(kind, id, section) {
    const ws = activeWorkspace();
    let draft = null;

    if (kind === 'task') {
      const task = ws.tasks.find((item) => item.id === id);
      if (!task) return;
      draft = buildTaskInlineDraft(task, section, resolveOffsetMinutes(ws.config));
    } else if (kind === 'label') {
      const label = ws.labels.find((item) => item.id === id);
      if (!label) return;
      draft = buildLabelInlineDraft(label, section);
    } else if (kind === 'location') {
      const loc = ws.locations.find((item) => item.id === id);
      if (!loc) return;
      draft = buildLocationInlineDraft(loc, section);
    }
    if (!draft) return;

    state.expandedEntity = { kind, id };
    state.justExpandedKey = null;
    state.taskLabelPicker = null;
    state.draftLabelPicker = null;
    state.inlineDeleteConfirmKey = null;
    state.editingHistoryIndex = null;
    state.historyEditDraft = '';
    state.inlineEdit = { kind, id, section, draft, error: '' };
    render();

    const focusTarget = app.querySelector(
      '.info-card.is-editing input:not([type="checkbox"]), .info-card.is-editing textarea, .inline-title-edit input',
    );
    if (focusTarget) focusTarget.focus();
  }

  function announceTierChangeIfMoved(ws, taskId, fallbackKey) {
    const lang = state.lang;
    const evalRes = evaluateBoard(ws, evalContext());
    const nextTier = evalRes.tierOfTask.get(taskId);
    if (
      state.view === 'tasks' &&
      !state.searchOpen &&
      nextTier !== undefined &&
      nextTier !== state.tier
    ) {
      clearExpandedState();
      state.message = t(lang, 'msgTaskMovedTier', {
        tier: tierName(lang, nextTier),
      });
    } else if (fallbackKey) {
      state.message = t(lang, fallbackKey);
    }
    state.showUndoAction = false;
  }

  function saveLabelInlineEdit(ws, edit, nowIso) {
    const lang = state.lang;
    const label = ws.labels.find((item) => item.id === edit.id);
    if (!label) {
      state.inlineEdit = null;
      render();
      return;
    }
    const { section, draft } = edit;
    if (section === 'name') {
      const trimmed = String(draft.name || '').trim();
      if (!trimmed) {
        edit.error = t(lang, 'errLabelNameEmpty');
        render();
        return;
      }
      const dup = ws.labels.some(
        (item) =>
          item.id !== label.id &&
          item.name.trim().toLowerCase() === trimmed.toLowerCase(),
      );
      if (dup) {
        edit.error = t(lang, 'errLabelNameDup');
        render();
        return;
      }
      label.name = trimmed;
    } else if (section === 'note') {
      label.note = String(draft.note || '').trim();
    } else if (section === 'links') {
      label.links = structuredClone(draft.links || []);
    } else if (section === 'color') {
      const color = String(draft.color || '').trim().toUpperCase();
      if (color && !/^#[0-9A-F]{6}$/.test(color)) {
        edit.error = t(lang, 'errColorInvalid');
        render();
        return;
      }
      label.color = color || '#2196F3';
    } else if (section === 'conditions') {
      label.conditions = {
        days: [...(draft.days || [])].sort((a, b) => a - b),
        times: structuredClone(draft.times || []),
        locationIds: [...(draft.locationIds || [])],
      };
    }

    label.modifiedAt = nowIso;
    state.inlineEdit = null;
    state.message = t(lang, 'msgSavedLabel');
    state.showUndoAction = false;
    logEvent('info', 'domain', 'label.inline_updated', {
      id: label.id,
      section,
    });
    render();
  }

  function saveLocationInlineEdit(ws, edit, nowIso) {
    const lang = state.lang;
    const loc = ws.locations.find((item) => item.id === edit.id);
    if (!loc) {
      state.inlineEdit = null;
      render();
      return;
    }
    const { section, draft } = edit;
    if (section === 'name') {
      const trimmed = String(draft.name || '').trim();
      if (!trimmed) {
        edit.error = t(lang, 'errLocNameEmpty');
        render();
        return;
      }
      loc.name = trimmed;
    } else if (section === 'note') {
      loc.note = String(draft.note || '').trim();
    } else if (section === 'coordinates') {
      const lat = Number(draft.latitude);
      const lon = Number(draft.longitude);
      const radius = parseRadiusMeters(draft.radiusText);
      if (
        !Number.isFinite(lat) ||
        lat < -90 ||
        lat > 90 ||
        !Number.isFinite(lon) ||
        lon < -180 ||
        lon > 180 ||
        radius === null
      ) {
        edit.error = t(lang, 'errLocCoordsInvalid');
        render();
        return;
      }
      loc.sourceType = draft.sourceType;
      loc.source =
        draft.sourceType === 'gps' ? 'gps' : String(draft.source || '').trim();
      loc.latitude = Math.round(lat * 1e6) / 1e6;
      loc.longitude = Math.round(lon * 1e6) / 1e6;
      loc.radius = radius;
    }

    loc.modifiedAt = nowIso;
    state.inlineEdit = null;
    state.message = t(lang, 'msgSavedLocation');
    state.showUndoAction = false;
    logEvent('info', 'domain', 'location.inline_updated', {
      id: loc.id,
      section,
    });
    render();
  }

  function saveInlineEdit() {
    const edit = state.inlineEdit;
    if (!edit) return;
    const ws = activeWorkspace();
    const lang = state.lang;
    const nowIso = new Date(state.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');

    if (edit.kind === 'label') {
      saveLabelInlineEdit(ws, edit, nowIso);
      return;
    }
    if (edit.kind === 'location') {
      saveLocationInlineEdit(ws, edit, nowIso);
      return;
    }

    const task = ws.tasks.find((item) => item.id === edit.id);
    if (!task) {
      state.inlineEdit = null;
      render();
      return;
    }

    const offset = resolveOffsetMinutes(ws.config);
    const draft = edit.draft;
    const section = edit.section;

    if (section === 'title') {
      const trimmed = String(draft.title || '').trim();
      if (!trimmed) {
        edit.error = t(lang, 'errTaskNameEmpty');
        render();
        return;
      }
      const dup = ws.tasks.some(
        (item) =>
          item.id !== task.id &&
          item.title.trim().toLowerCase() === trimmed.toLowerCase(),
      );
      if (dup) {
        edit.error = t(lang, 'errTaskNameDup');
        render();
        return;
      }
      task.title = trimmed;
    } else if (section === 'note') {
      task.note = String(draft.note || '').trim();
    } else if (section === 'links') {
      task.links = structuredClone(draft.links || []);
    } else if (section === 'subtasks') {
      const cleaned = (draft.subtasks || [])
        .map((step) => ({
          text: String(step.text || '').trim(),
          done: Boolean(step.done),
        }))
        .filter((step) => step.text.length > 0);
      task.subtasks = cleaned;
      task.subtasksAutoFinish = Boolean(draft.subtasksAutoFinish);
      if (
        !task.finishedAt &&
        task.subtasksAutoFinish &&
        cleaned.length > 0 &&
        cleaned.every((step) => step.done)
      ) {
        pushUndo('complete', task.title);
        const res = completeTask(ws, task.id, evalContext());
        clearExpandedState();
        state.message = t(
          lang,
          res.repeated ? 'msgCompletedRepeat' : 'msgCompleted',
          { title: task.title },
        );
        logEvent('info', 'domain', 'task.auto_finished', { id: task.id });
        render();
        return;
      }
    } else if (section === 'due') {
      const dueAt = draft.dueLocal
        ? localDatetimeInputToIsoUtc(draft.dueLocal, offset)
        : null;
      task.dueAt = dueAt;
      task.dueAnchor = dueAt ? task.dueAnchor : null;
      task.duePassive = dueAt ? !draft.autoDue : false;
      task.dueNote = dueAt ? String(draft.dueNote || '').trim() : '';
      if (!dueAt && task.repeat) {
        task.repeat.leadDays = 0;
      }
    } else if (section === 'repeat') {
      const repEvery = Number(draft.repeatEvery);
      if (!Number.isInteger(repEvery) || repEvery < 1 || repEvery > 3650) {
        edit.error = t(lang, 'errRepeatRange');
        render();
        return;
      }
      const leadDays = Number(draft.repeatLeadDays || 0);
      if (
        task.dueAt &&
        (!Number.isInteger(leadDays) || leadDays < 0 || leadDays > 3650)
      ) {
        edit.error = t(lang, 'errLeadRange');
        render();
        return;
      }
      task.repeat = {
        count: repEvery,
        unit: draft.repeatUnit,
        leadDays: task.dueAt ? leadDays : 0,
      };
    } else if (section === 'suspended') {
      if (draft.suspendedMode === 'until' && !draft.suspendedLocal) {
        edit.error = t(lang, 'errSuspendedUntilReq');
        render();
        return;
      }
      task.suspendedMode = draft.suspendedMode;
      task.suspendedAt =
        draft.suspendedMode === 'until'
          ? localDatetimeInputToIsoUtc(draft.suspendedLocal, offset)
          : null;
      task.suspendedNote = String(draft.suspendedNote || '').trim();
    } else if (section === 'prereqs') {
      task.blockedBy = (draft.prerequisites || []).map((prereqId) => {
        const target = ws.tasks.find((item) => item.id === prereqId);
        const req = target
          ? target.finishedAt
            ? Math.max(1, target.completions || 1)
            : (target.completions || 0) + 1
          : 1;
        return { taskId: prereqId, requiredCompletion: req };
      });
    } else if (section === 'conditions') {
      task.conditions = {
        ignoreLabels: Boolean(draft.ignoreLabels),
        daysMode: draft.daysMode,
        days: [...(draft.days || [])].sort((a, b) => a - b),
        timeMode: draft.timeMode,
        times: structuredClone(draft.times || []),
        placesMode: draft.placesMode,
        locationIds: [...(draft.locationIds || [])],
      };
    }

    task.modifiedAt = nowIso;
    state.inlineEdit = null;
    logEvent('info', 'domain', 'task.inline_updated', {
      id: task.id,
      section,
    });
    announceTierChangeIfMoved(ws, task.id, 'msgSavedTask');
    render();
  }

  function clearInlineSection(section) {
    const edit = state.inlineEdit;
    if (!edit) return;
    const ws = activeWorkspace();
    const lang = state.lang;
    const nowIso = new Date(state.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');

    if (edit.kind === 'label') {
      const label = ws.labels.find((item) => item.id === edit.id);
      if (!label) return;
      if (section === 'note') label.note = '';
      else if (section === 'links') label.links = [];
      else if (section === 'conditions') {
        label.conditions = { days: [], times: [], locationIds: [] };
      }
      label.modifiedAt = nowIso;
      state.inlineEdit = null;
      state.message = t(lang, 'msgSavedLabel');
      state.showUndoAction = false;
      logEvent('info', 'domain', 'label.inline_cleared', {
        id: label.id,
        section,
      });
      render();
      return;
    }

    if (edit.kind === 'location') {
      const loc = ws.locations.find((item) => item.id === edit.id);
      if (!loc) return;
      if (section === 'note') loc.note = '';
      loc.modifiedAt = nowIso;
      state.inlineEdit = null;
      state.message = t(lang, 'msgSavedLocation');
      state.showUndoAction = false;
      logEvent('info', 'domain', 'location.inline_cleared', {
        id: loc.id,
        section,
      });
      render();
      return;
    }

    const task = ws.tasks.find((item) => item.id === edit.id);
    if (!task) return;

    if (section === 'note') {
      task.note = '';
    } else if (section === 'links') {
      task.links = [];
    } else if (section === 'subtasks') {
      task.subtasks = [];
      task.subtasksAutoFinish = false;
    } else if (section === 'due') {
      task.dueAt = null;
      task.dueAnchor = null;
      task.duePassive = false;
      task.dueNote = '';
      if (task.repeat) task.repeat.leadDays = 0;
    } else if (section === 'repeat') {
      task.repeat = null;
    } else if (section === 'suspended') {
      task.suspendedMode = 'none';
      task.suspendedAt = null;
      task.suspendedNote = '';
    } else if (section === 'prereqs') {
      task.blockedBy = [];
    } else if (section === 'conditions') {
      task.conditions = {
        ignoreLabels: false,
        daysMode: 'inherit',
        days: [],
        timeMode: 'inherit',
        times: [],
        placesMode: 'inherit',
        locationIds: [],
      };
    }

    task.modifiedAt = nowIso;
    state.inlineEdit = null;
    logEvent('info', 'domain', 'task.inline_cleared', {
      id: task.id,
      section,
    });
    announceTierChangeIfMoved(ws, task.id, 'msgSavedTask');
    render();
  }

  function directSetLabelScope(labelId, scoped) {
    const ws = activeWorkspace();
    const label = ws.labels.find((item) => item.id === labelId);
    if (!label || Boolean(label.scoped) === scoped) return;
    label.scoped = scoped;
    label.modifiedAt = new Date(state.nowMs)
      .toISOString()
      .replace(/\.\d{3}Z$/, 'Z');
    state.message = t(state.lang, 'msgSavedLabel');
    state.showUndoAction = false;
    logEvent('info', 'domain', 'label.scope_toggled', {
      id: label.id,
      scoped,
    });
    render();
  }

  function directToggleLabel(taskId, labelId) {
    const ws = activeWorkspace();
    const lang = state.lang;
    const task = ws.tasks.find((item) => item.id === taskId);
    const label = ws.labels.find((item) => item.id === labelId);
    if (!task || !label) return;

    task.labels = task.labels || [];
    const hadLabel = task.labels.includes(labelId);
    if (hadLabel) {
      task.labels = task.labels.filter((id) => id !== labelId);
    } else {
      task.labels.push(labelId);
    }
    task.modifiedAt = new Date(state.nowMs)
      .toISOString()
      .replace(/\.\d{3}Z$/, 'Z');

    logEvent('info', 'domain', 'task.label_toggled', {
      id: task.id,
      labelId,
      added: !hadLabel,
    });

    const evalRes = evaluateBoard(ws, evalContext());
    const nextTier = evalRes.tierOfTask.get(task.id);
    if (nextTier === undefined) {
      clearExpandedState();
      state.message =
        !hadLabel && label.scoped
          ? t(lang, 'msgTaskMovedScoped', { label: label.name })
          : t(lang, hadLabel ? 'msgLabelRemoved' : 'msgLabelAdded', {
              name: label.name,
            });
    } else if (
      state.view === 'tasks' &&
      !state.searchOpen &&
      nextTier !== state.tier
    ) {
      clearExpandedState();
      state.message = t(lang, 'msgTaskMovedTier', {
        tier: tierName(lang, nextTier),
      });
    } else {
      state.message = t(lang, hadLabel ? 'msgLabelRemoved' : 'msgLabelAdded', {
        name: label.name,
      });
    }
    state.showUndoAction = false;
    render();
  }

  function toggleDraftLabel(labelId) {
    const ws = activeWorkspace();
    if (!ws.labels.some((item) => item.id === labelId)) return;
    const had = state.draft.labels.includes(labelId);
    state.draft.labels = had
      ? state.draft.labels.filter((id) => id !== labelId)
      : [...state.draft.labels, labelId];
    render();
  }

  function createAndAssignLabelFromPicker(mode) {
    const ws = activeWorkspace();
    const lang = state.lang;
    const picker =
      mode === 'task' ? state.taskLabelPicker : state.draftLabelPicker;
    if (!picker) return;
    const name = String(picker.query || '').trim();
    if (!name || name.length > 120) return;
    if (ws.labels.some((l) => l.name.toLowerCase() === name.toLowerCase())) {
      return;
    }

    const nowIso = new Date(state.nowMs)
      .toISOString()
      .replace(/\.\d{3}Z$/, 'Z');
    const created = {
      id: generateBase62Id(),
      name,
      color: LABEL_COLOR_PRESETS[ws.labels.length % LABEL_COLOR_PRESETS.length],
      scoped: false,
      note: '',
      links: [],
      conditions: { days: [], times: [], locationIds: [] },
      modifiedAt: nowIso,
    };
    ws.labels.push(created);
    logEvent('info', 'domain', 'label.added', {
      id: created.id,
      source: `picker:${mode}`,
    });

    if (mode === 'task') {
      const task = ws.tasks.find((item) => item.id === picker.taskId);
      if (task) {
        task.labels = [...(task.labels || []), created.id];
        task.modifiedAt = nowIso;
        logEvent('info', 'domain', 'task.label_toggled', {
          id: task.id,
          labelId: created.id,
          added: true,
        });
      }
    } else {
      state.draft.labels = [...state.draft.labels, created.id];
    }

    picker.query = '';
    picker.scopeFilter = 'all';
    picker.activeIndex = -1;
    state.message = t(lang, 'msgLabelCreatedAssigned', { name: created.name });
    state.showUndoAction = false;
    render();
  }

  function directSetMode(taskId, mode) {
    const ws = activeWorkspace();
    const lang = state.lang;
    const task = ws.tasks.find((item) => item.id === taskId);
    if (!task || task.finishedAt) return;

    const wasPriority = Boolean(task.priority);
    if (mode === 'someday') {
      task.priority = false;
      ws.queue = ws.queue.filter((id) => id !== task.id);
    } else if (mode === 'priority') {
      task.priority = true;
      ws.queue = [task.id, ...ws.queue.filter((id) => id !== task.id)];
    } else {
      task.priority = false;
      if (!ws.queue.includes(task.id)) {
        ws.queue.push(task.id);
      }
    }
    task.modifiedAt = new Date(state.nowMs)
      .toISOString()
      .replace(/\.\d{3}Z$/, 'Z');

    logEvent('info', 'domain', 'task.mode_toggled', { id: task.id, mode });

    const fallbackKey =
      mode === 'priority'
        ? 'msgPriorityToggledOn'
        : mode === 'someday'
          ? 'msgMovedToSomeday'
          : wasPriority
            ? 'msgPriorityToggledOff'
            : 'msgMovedToQueue';
    announceTierChangeIfMoved(ws, task.id, fallbackKey);
    render();
  }

  function createQuickTask(expandAfter) {
    const ws = activeWorkspace();
    const lang = state.lang;
    const form = app.querySelector('form[data-form="quick-task"]');
    const title = state.draft.title.trim();
    if (!title) {
      if (form) form.reportValidity();
      return;
    }
    const nowIso = new Date(state.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');
    const mode = state.draft.mode;
    const newTask = {
      id: generateBase62Id(),
      title,
      note: '',
      labels: [...state.draft.labels],
      priority: mode === 'priority',
      dueAt: null,
      dueAnchor: null,
      duePassive: false,
      dueNote: '',
      suspendedMode: 'none',
      suspendedAt: null,
      suspendedNote: '',
      repeat: null,
      completions: 0,
      subtasksAutoFinish: false,
      subtasks: [],
      links: [],
      history: [],
      blockedBy: [],
      conditions: {
        ignoreLabels: false,
        daysMode: 'inherit',
        days: [],
        timeMode: 'inherit',
        times: [],
        placesMode: 'inherit',
        locationIds: [],
      },
      createdAt: nowIso,
      modifiedAt: nowIso,
      finishedAt: null,
    };
    ws.tasks.push(newTask);
    if (mode === 'priority') ws.queue.unshift(newTask.id);
    else if (mode === 'queue') ws.queue.push(newTask.id);

    state.draft = {
      title: '',
      mode: 'queue',
      labels: state.label ? [state.label] : [],
    };
    state.draftLabelPicker = null;
    state.mobileQuickAddOpen = false;
    state.message = t(lang, 'msgSavedTask');
    state.showUndoAction = false;
    logEvent('info', 'domain', 'task.quick_added', {
      id: newTask.id,
      mode,
      expandAfter,
    });

    if (expandAfter) {
      const evalRes = evaluateBoard(ws, evalContext());
      const targetTier = evalRes.tierOfTask.get(newTask.id);
      if (targetTier !== undefined) {
        state.tier = targetTier;
      }
      state.view = 'tasks';
      state.searchOpen = false;
      clearExpandedState();
      state.expandedEntity = { kind: 'task', id: newTask.id };
      state.justExpandedKey = `task:${newTask.id}`;
      state.scrollToEntityKey = `task:${newTask.id}`;
    }
    render();
  }

  function createQuickManagedEntity(kind, expandAfter) {
    const ws = activeWorkspace();
    const lang = state.lang;
    const form = app.querySelector(`form[data-form="quick-create-${kind}"]`);
    const input = form?.querySelector('input[name="name"]');
    const name = String(input?.value || '').trim();
    if (!name) {
      if (form) form.reportValidity();
      return;
    }
    const nowIso = new Date(state.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');

    if (kind === 'labels') {
      if (ws.labels.some((l) => l.name.toLowerCase() === name.toLowerCase())) {
        state.message = t(lang, 'errLabelNameDup');
        state.showUndoAction = false;
        render();
        return;
      }
      const created = {
        id: generateBase62Id(),
        name,
        color: '#2196F3',
        scoped: false,
        note: '',
        links: [],
        conditions: { days: [], times: [], locationIds: [] },
        modifiedAt: nowIso,
      };
      ws.labels.push(created);
      state.message = t(lang, 'msgSavedLabel');
      state.showUndoAction = false;
      logEvent('info', 'domain', 'label.added', {
        id: created.id,
        expandAfter,
      });
      if (expandAfter) {
        clearExpandedState();
        state.expandedEntity = { kind: 'label', id: created.id };
        state.justExpandedKey = `label:${created.id}`;
        state.scrollToEntityKey = `label:${created.id}`;
      }
      render();
      return;
    }

    const fix = state.locationFix;
    const created = {
      id: generateBase62Id(),
      name,
      sourceType: 'gps',
      source: 'gps',
      latitude:
        fix.status === 'found'
          ? Math.round(Number(fix.latitude) * 1e6) / 1e6
          : 51.0504,
      longitude:
        fix.status === 'found'
          ? Math.round(Number(fix.longitude) * 1e6) / 1e6
          : 13.7373,
      radius: 100,
      note: '',
      modifiedAt: nowIso,
    };
    ws.locations.push(created);
    state.message = t(lang, 'msgSavedLocation');
    state.showUndoAction = false;
    logEvent('info', 'domain', 'location.added', {
      id: created.id,
      expandAfter,
    });
    if (expandAfter) {
      clearExpandedState();
      state.expandedEntity = { kind: 'location', id: created.id };
      state.justExpandedKey = `location:${created.id}`;
      state.scrollToEntityKey = `location:${created.id}`;
    }
    render();
  }

  function handleLinkListAction(container, prefix, button, setError) {
    const lang = state.lang;
    if (button.hasAttribute(`data-${prefix}-link-up`)) {
      const idx = Number(button.getAttribute(`data-${prefix}-link-up`));
      if (idx > 0) {
        const [moved] = container.links.splice(idx, 1);
        container.links.splice(idx - 1, 0, moved);
        container.editingLinkIndex = null;
        render();
      }
      return true;
    }
    if (button.hasAttribute(`data-${prefix}-link-down`)) {
      const idx = Number(button.getAttribute(`data-${prefix}-link-down`));
      if (idx < container.links.length - 1) {
        const [moved] = container.links.splice(idx, 1);
        container.links.splice(idx + 1, 0, moved);
        container.editingLinkIndex = null;
        render();
      }
      return true;
    }
    if (button.hasAttribute(`data-${prefix}-link-edit`)) {
      const idx = Number(button.getAttribute(`data-${prefix}-link-edit`));
      const target = container.links[idx];
      if (target) {
        container.editingLinkIndex = idx;
        container.linkTitleDraft = target.title;
        container.linkUriDraft = target.uri;
        setError('');
        render();
      }
      return true;
    }
    if (button.hasAttribute(`data-${prefix}-link-cancel`)) {
      container.editingLinkIndex = null;
      container.linkTitleDraft = '';
      container.linkUriDraft = '';
      setError('');
      render();
      return true;
    }
    if (button.hasAttribute(`data-${prefix}-link-remove`)) {
      const idx = Number(button.getAttribute(`data-${prefix}-link-remove`));
      container.links.splice(idx, 1);
      if (container.editingLinkIndex === idx) {
        container.editingLinkIndex = null;
        container.linkTitleDraft = '';
        container.linkUriDraft = '';
      }
      render();
      return true;
    }
    if (button.hasAttribute(`data-${prefix}-link-submit`)) {
      const title = (container.linkTitleDraft || '').trim();
      const uri = (container.linkUriDraft || '').trim();
      if (container.editingLinkIndex === null && container.links.length >= 20) {
        setError(t(lang, 'errLinkMax'));
        render();
        return true;
      }
      let validUri = false;
      try {
        const parsed = new URL(uri);
        validUri = Boolean(parsed.protocol && parsed.protocol.endsWith(':'));
      } catch {
        validUri = false;
      }
      if (!title || !validUri) {
        setError(t(lang, 'errLinkInvalid'));
        render();
        return true;
      }
      if (container.editingLinkIndex !== null) {
        container.links[container.editingLinkIndex] = { title, uri };
      } else {
        container.links.push({ title, uri });
      }
      container.editingLinkIndex = null;
      container.linkTitleDraft = '';
      container.linkUriDraft = '';
      setError('');
      render();
      return true;
    }
    return false;
  }

  function switchWorkspace(wsId) {
    const target = state.workspaces.find((w) => w.id === wsId);
    if (!target) return;
    state.activeWorkspaceId = target.id;
    state.label = '';
    state.tier = 0;
    state.view = 'tasks';
    state.searchOpen = false;
    state.searchQuery = '';
    state.drawer = false;
    state.modal = null;
    state.sidebarLabelFilter = '';
    state.draftLabelPicker = null;
    clearExpandedState();
    state.undoStack = [];
    state.showUndoAction = false;
    state.draft = { title: '', mode: 'queue', labels: [] };
    state.logs = createSeedLogs(target.id);
    state.lang = resolveLang(target.config.language);
    state.message = t(state.lang, 'msgWorkspaceSwitched', { name: target.name });
    logEvent('info', 'lifecycle', 'workspace.switched', { id: target.id });
    render();
  }

  /* ==========================================================================
     Click Event Delegation
     ========================================================================== */

  app.addEventListener('click', (event) => {
    // Click on modal backdrop closes modal
    if (event.target.hasAttribute('data-modal-backdrop')) {
      state.modal = null;
      render();
      return;
    }

    // Click on mobile label sheet backdrop closes label picker
    if (event.target.hasAttribute('data-sheet-backdrop')) {
      state.taskLabelPicker = null;
      state.draftLabelPicker = null;
      render();
      return;
    }

    // Click outside desktop quick-add label popover closes it without swallowing clicks
    if (
      state.draftLabelPicker &&
      !state.isCompact &&
      !event.target.closest('.composer-label-popover') &&
      !event.target.closest('[data-toggle-draft-label-picker]')
    ) {
      state.draftLabelPicker = null;
      if (!event.target.closest('button, input, select, textarea, a, label')) {
        render();
        return;
      }
    }

    const button = event.target.closest('button');
    if (!button) return;
    const ws = activeWorkspace();
    const lang = state.lang;
    const has = (attr) => button.hasAttribute(`data-${attr}`);

    // Navigation & Chrome
    if (has('menu')) {
      state.drawer = !state.drawer;
      render();
      return;
    }
    if (has('close-modal')) {
      state.modal = null;
      render();
      return;
    }
    if (has('view')) {
      state.view = button.dataset.view;
      state.drawer = false;
      state.modal = null;
      state.draftLabelPicker = null;
      clearExpandedState();
      state.settingsBanner = null;
      if (state.view === 'tasks') state.searchOpen = false;
      render();
      return;
    }
    if (has('tier')) {
      state.tier = Number(button.dataset.tier);
      state.view = 'tasks';
      state.searchOpen = false;
      state.drawer = false;
      state.draftLabelPicker = null;
      clearExpandedState();
      state.message = '';
      render();
      return;
    }
    if (has('label')) {
      state.label = button.dataset.label;
      state.view = 'tasks';
      state.tier = 0;
      state.drawer = false;
      state.draftLabelPicker = null;
      clearExpandedState();
      state.draft.labels = state.label ? [state.label] : [];
      state.message = '';
      render();
      return;
    }
    if (has('clear-sidebar-label-filter')) {
      state.sidebarLabelFilter = '';
      render();
      app.querySelector('[data-sidebar-label-filter]')?.focus();
      return;
    }
    if (has('toggle-search')) {
      state.searchOpen = !state.searchOpen;
      state.searchQuery = '';
      state.draftLabelPicker = null;
      if (state.searchOpen) state.view = 'tasks';
      render();
      if (state.searchOpen) {
        const searchInput = app.querySelector('[data-global-search]');
        if (searchInput) searchInput.focus();
      }
      return;
    }
    if (has('toggle-mobile-add')) {
      state.mobileQuickAddOpen = !state.mobileQuickAddOpen;
      if (!state.mobileQuickAddOpen) state.draftLabelPicker = null;
      render();
      return;
    }
    if (has('trigger-sync')) {
      if (state.simState === 'conflict_deletion') {
        state.view = 'conflict-resolution';
        render();
        return;
      }
      if (state.simState === 'conflict_recovery') {
        state.view = 'recovery-resolution';
        render();
        return;
      }
      state.syncing = true;
      state.bannerDismissed = false;
      render();
      setTimeout(() => {
        state.syncing = false;
        if (state.simState === 'sync_error' || state.simState === 'syncing') {
          state.simState = 'normal';
          const simSelect = root.querySelector('[data-sim-state]');
          if (simSelect) simSelect.value = 'normal';
        }
        state.message = t(state.lang, 'msgSyncedNow');
        state.showUndoAction = false;
        logEvent('info', 'sync', 'sync.manual_complete', { workspace: ws.id });
        render();
      }, 450);
      return;
    }
    if (has('dismiss-banner')) {
      state.bannerDismissed = true;
      render();
      return;
    }
    if (has('dismiss-recovery')) {
      state.recoveryNotice = null;
      render();
      return;
    }
    if (has('reset-sim')) {
      state.simState = 'normal';
      state.bannerDismissed = false;
      const simSelect = root.querySelector('[data-sim-state]');
      if (simSelect) simSelect.value = 'normal';
      render();
      return;
    }

    // Modals & Contextual Hubs
    if (has('open-modal')) {
      const type = button.dataset.openModal;
      state.drawer = false;
      if (type === 'workspaces') {
        state.modal = {
          type: 'workspaces',
          createName: '',
          renamingId: null,
          renameDraft: '',
          deletingId: null,
          error: '',
        };
      } else if (type === 'location-status') {
        state.modal = { type: 'location-status' };
      } else if (type === 'select-local') {
        state.modal = {
          type: 'select-local',
          fileInput: ws.config.localFilePath,
        };
      } else if (type === 'rename-local') {
        state.modal = {
          type: 'rename-local',
          fileInput: ws.config.localFilePath.replace(/\.tdf$/i, ''),
        };
      }
      render();
      return;
    }
    if (has('toggle-entity')) {
      const [kind, id] = button.dataset.toggleEntity.split(':');
      const isOpening =
        state.expandedEntity?.kind !== kind || state.expandedEntity?.id !== id;
      clearExpandedState();
      if (isOpening) {
        state.expandedEntity = { kind, id };
        state.justExpandedKey = `${kind}:${id}`;
      }
      logEvent('info', 'ui', 'ui.entity_panel.toggle', {
        kind,
        id,
        expanded: isOpening,
      });
      render();
      return;
    }
    if (has('open-managed')) {
      const [viewKind, id] = button.dataset.openManaged.split(':');
      openManagedEntity(viewKind, id);
      return;
    }
    if (has('ie-open')) {
      startInlineEdit(
        button.dataset.ieKind,
        button.dataset.ieId,
        button.dataset.ieOpen,
      );
      return;
    }
    if (has('ie-cancel')) {
      state.inlineEdit = null;
      render();
      return;
    }
    if (has('ie-save')) {
      saveInlineEdit();
      return;
    }
    if (has('ie-clear')) {
      clearInlineSection(button.dataset.ieClear);
      return;
    }
    if (has('inline-del-ask')) {
      state.inlineEdit = null;
      state.inlineDeleteConfirmKey = button.dataset.inlineDelAsk;
      render();
      return;
    }
    if (has('inline-del-no')) {
      state.inlineDeleteConfirmKey = null;
      render();
      return;
    }
    if (has('inline-del-yes')) {
      const [kind, id] = button.dataset.inlineDelYes.split(':');
      const nowIso = new Date(state.nowMs)
        .toISOString()
        .replace(/\.\d{3}Z$/, 'Z');
      if (kind === 'task') {
        const target = ws.tasks.find((item) => item.id === id);
        if (target) {
          pushUndo('delete', target.title);
          ws.tasks = ws.tasks.filter((item) => item.id !== id);
          ws.queue = ws.queue.filter((qid) => qid !== id);
          ws.deleted.tasks.push({ id: target.id, deletedAt: nowIso });
          state.message = t(lang, 'msgDeleted', { title: target.title });
          logEvent('info', 'domain', 'task.deleted', { id: target.id });
        }
      } else if (kind === 'label') {
        ws.labels = ws.labels.filter((l) => l.id !== id);
        for (const task of ws.tasks) {
          task.labels = (task.labels || []).filter((lid) => lid !== id);
        }
        ws.deleted.labels.push({ id, deletedAt: nowIso });
        if (state.label === id) state.label = '';
        state.draft.labels = state.draft.labels.filter((lid) => lid !== id);
        state.message = t(lang, 'msgDeletedLabel');
        state.showUndoAction = false;
        logEvent('info', 'domain', 'label.deleted', { id });
      } else if (kind === 'location') {
        ws.locations = ws.locations.filter((l) => l.id !== id);
        for (const task of ws.tasks) {
          if (task.conditions?.locationIds) {
            task.conditions.locationIds = task.conditions.locationIds.filter(
              (locId) => locId !== id,
            );
          }
        }
        for (const label of ws.labels) {
          if (label.conditions?.locationIds) {
            label.conditions.locationIds = label.conditions.locationIds.filter(
              (locId) => locId !== id,
            );
          }
        }
        ws.deleted.locations.push({ id, deletedAt: nowIso });
        state.message = t(lang, 'msgDeletedLocation');
        state.showUndoAction = false;
        logEvent('info', 'domain', 'location.deleted', { id });
      }
      clearExpandedState();
      render();
      return;
    }
    if (has('direct-toggle-label')) {
      directToggleLabel(
        button.dataset.taskId,
        button.dataset.directToggleLabel,
      );
      return;
    }
    if (has('open-task-label-picker')) {
      const taskId = button.dataset.openTaskLabelPicker;
      state.inlineEdit = null;
      state.draftLabelPicker = null;
      state.taskLabelPicker = {
        taskId,
        query: '',
        scopeFilter: 'all',
        activeIndex: -1,
      };
      render();
      if (!state.isCompact) {
        app.querySelector('[data-lp-search="task"]')?.focus();
      }
      return;
    }
    if (has('close-task-label-picker')) {
      state.taskLabelPicker = null;
      render();
      return;
    }
    if (has('toggle-draft-label-picker')) {
      if (state.draftLabelPicker) {
        state.draftLabelPicker = null;
        render();
      } else {
        state.taskLabelPicker = null;
        state.draftLabelPicker = {
          query: '',
          scopeFilter: 'all',
          activeIndex: -1,
        };
        render();
        if (!state.isCompact) {
          app.querySelector('[data-lp-search="draft"]')?.focus();
        }
      }
      return;
    }
    if (has('close-draft-label-picker')) {
      state.draftLabelPicker = null;
      render();
      return;
    }
    if (has('close-label-sheet')) {
      state.taskLabelPicker = null;
      state.draftLabelPicker = null;
      render();
      return;
    }
    if (has('draft-toggle-label')) {
      toggleDraftLabel(button.dataset.draftToggleLabel);
      return;
    }
    if (has('lp-scope')) {
      const [mode, scope] = button.dataset.lpScope.split(':');
      const picker =
        mode === 'task' ? state.taskLabelPicker : state.draftLabelPicker;
      if (picker) {
        picker.scopeFilter = scope;
        picker.activeIndex = picker.query.trim() ? 0 : -1;
        render();
      }
      return;
    }
    if (has('lp-clear')) {
      const mode = button.dataset.lpClear;
      const picker =
        mode === 'task' ? state.taskLabelPicker : state.draftLabelPicker;
      if (picker) {
        picker.query = '';
        picker.activeIndex = -1;
        render();
        app.querySelector(`[data-lp-search="${mode}"]`)?.focus();
      }
      return;
    }
    if (has('lp-create')) {
      createAndAssignLabelFromPicker(button.dataset.lpCreate);
      return;
    }
    if (has('direct-mode')) {
      directSetMode(button.dataset.taskId, button.dataset.directMode);
      return;
    }
    if (has('direct-label-scope')) {
      directSetLabelScope(
        button.dataset.labelId,
        button.dataset.directLabelScope === 'true',
      );
      return;
    }

    // Task Actions (Complete, Restore, Downgrade, Undo)
    if (has('complete')) {
      const taskId = button.dataset.complete;
      const task = ws.tasks.find((item) => item.id === taskId);
      if (!task) return;
      if (task.finishedAt) {
        restoreTask(ws, taskId, evalContext());
        state.message = t(lang, 'msgRestored', { title: task.title });
        state.showUndoAction = false;
        logEvent('info', 'domain', 'task.restored', { id: taskId });
      } else {
        pushUndo('complete', task.title);
        const res = completeTask(ws, taskId, evalContext());
        state.message = t(
          lang,
          res.repeated ? 'msgCompletedRepeat' : 'msgCompleted',
          { title: task.title },
        );
        logEvent('info', 'domain', 'task.completed', {
          id: taskId,
          repeated: res.repeated,
        });
      }
      if (
        state.expandedEntity?.kind === 'task' &&
        state.expandedEntity?.id === taskId
      ) {
        clearExpandedState();
      }
      render();
      return;
    }
    if (has('downgrade')) {
      const taskId = button.dataset.downgrade;
      const task = ws.tasks.find((item) => item.id === taskId);
      if (!task) return;
      pushUndo('downgrade', task.title);
      if (downgradeTask(ws, taskId, evalContext())) {
        state.message = t(lang, 'msgDowngraded', { title: task.title });
        if (
          state.expandedEntity?.kind === 'task' &&
          state.expandedEntity?.id === taskId
        ) {
          clearExpandedState();
        }
        logEvent('info', 'domain', 'task.downgraded', { id: taskId });
      } else {
        state.undoStack.pop();
      }
      render();
      return;
    }
    if (has('undo')) {
      performUndo();
      return;
    }

    // Clipboard & External Link Actions
    if (has('copy-id')) {
      const copyKind = button.dataset.copyKind;
      const msgKey =
        copyKind === 'label'
          ? 'msgCopiedLabelId'
          : copyKind === 'location'
            ? 'msgCopiedLocationId'
            : 'msgCopiedId';
      copyToClipboard(button.dataset.copyId, msgKey);
      return;
    }
    if (has('copy-note')) {
      copyToClipboard(button.dataset.copyNote, 'msgCopiedNote');
      return;
    }
    if (has('open-uri')) {
      const uri = button.dataset.openUri;
      state.message = t(lang, 'msgOpenedLink', { uri });
      state.showUndoAction = false;
      logEvent('info', 'ui', 'link.opened', { scheme: uri.split(':')[0] });
      render();
      return;
    }

    // Expanded Task Slide Panel: Live History Journal
    if (state.expandedEntity?.kind === 'task') {
      const task = ws.tasks.find(
        (item) => item.id === state.expandedEntity.id,
      );
      if (task) {
        if (has('info-hist-add')) {
          const input = app.querySelector('[data-info-hist-new]');
          const text = String(input?.value || '')
            .replace(/[\r\n\t]+/g, ' ')
            .trim();
          if (!text) return;
          task.history = task.history || [];
          task.history.push({
            timestampUtc: new Date(state.nowMs)
              .toISOString()
              .replace(/\.\d{3}Z$/, 'Z'),
            text: text.slice(0, 500),
          });
          logEvent('info', 'ui', 'ui.task_panel.history_added', { id: task.id });
          render();
          return;
        }
        if (has('info-hist-start-edit')) {
          const idx = Number(button.dataset.infoHistStartEdit);
          state.editingHistoryIndex = idx;
          state.historyEditDraft = task.history[idx]?.text || '';
          render();
          return;
        }
        if (has('info-hist-cancel')) {
          state.editingHistoryIndex = null;
          state.historyEditDraft = '';
          render();
          return;
        }
        if (has('info-hist-save')) {
          const idx = Number(button.dataset.infoHistSave);
          const input = app.querySelector('[data-info-hist-edit-input]');
          const text = String(input?.value || '')
            .replace(/[\r\n\t]+/g, ' ')
            .trim();
          if (text && task.history[idx]) {
            task.history[idx].text = text.slice(0, 500);
          }
          state.editingHistoryIndex = null;
          state.historyEditDraft = '';
          render();
          return;
        }
        if (has('info-hist-delete')) {
          const idx = Number(button.dataset.infoHistDelete);
          task.history.splice(idx, 1);
          state.editingHistoryIndex = null;
          state.historyEditDraft = '';
          logEvent('info', 'ui', 'ui.task_panel.history_removed', { id: task.id });
          render();
          return;
        }
      }
    }

    // Quick-Add Submit & Add + Expand (Tasks, Labels, Locations)
    if (has('save')) {
      const form = button.closest('form');
      if (form?.dataset.form === 'quick-task') {
        createQuickTask(false);
      }
      return;
    }
    if (has('quick-add-expand')) {
      createQuickTask(true);
      return;
    }
    if (has('quick-create-expand')) {
      createQuickManagedEntity(button.dataset.quickCreateExpand, true);
      return;
    }

    // Unified Inline Section Edit Sub-Controls (Tasks, Labels, Locations)
    if (state.inlineEdit) {
      const draft = state.inlineEdit.draft;
      if (state.inlineEdit.section === 'links') {
        if (
          handleLinkListAction(draft, 'ie', button, (msg) => {
            state.inlineEdit.error = msg;
          })
        ) {
          return;
        }
      }
      if (state.inlineEdit.section === 'subtasks') {
        if (has('ie-add-step')) {
          const input = app.querySelector('[data-ie-new-step]');
          const text = String(input?.value || '').trim();
          if (text && draft.subtasks.length < 100) {
            draft.subtasks.push({ text, done: false });
            render();
            const nextInput = app.querySelector('[data-ie-new-step]');
            if (nextInput) nextInput.focus();
          }
          return;
        }
        if (has('ie-step-up')) {
          const idx = Number(button.dataset.ieStepUp);
          if (idx > 0) {
            const [moved] = draft.subtasks.splice(idx, 1);
            draft.subtasks.splice(idx - 1, 0, moved);
            render();
          }
          return;
        }
        if (has('ie-step-down')) {
          const idx = Number(button.dataset.ieStepDown);
          if (idx < draft.subtasks.length - 1) {
            const [moved] = draft.subtasks.splice(idx, 1);
            draft.subtasks.splice(idx + 1, 0, moved);
            render();
          }
          return;
        }
        if (has('ie-step-remove')) {
          draft.subtasks.splice(Number(button.dataset.ieStepRemove), 1);
          render();
          return;
        }
      }
      if (state.inlineEdit.section === 'conditions') {
        if (has('ie-add-time')) {
          const start = app.querySelector('[data-ie-time-start]')?.value;
          const end = app.querySelector('[data-ie-time-end]')?.value;
          if (!start || !end) {
            state.inlineEdit.error = t(lang, 'errTimeInvalid');
            render();
            return;
          }
          draft.times.push({ start, end });
          state.inlineEdit.error = '';
          render();
          return;
        }
        if (has('ie-remove-time')) {
          draft.times.splice(Number(button.dataset.ieRemoveTime), 1);
          render();
          return;
        }
        if (has('ie-toggle-place')) {
          const locId = button.dataset.ieTogglePlace;
          if (draft.locationIds.includes(locId)) {
            draft.locationIds = draft.locationIds.filter((x) => x !== locId);
          } else {
            draft.locationIds.push(locId);
          }
          render();
          return;
        }
      }
      if (state.inlineEdit.section === 'color') {
        if (has('ie-color-preset')) {
          draft.color = button.dataset.ieColorPreset;
          state.inlineEdit.error = '';
          render();
          return;
        }
        if (has('open-color-picker')) {
          const hsv = hexToHsv(draft.color);
          state.modal = {
            type: 'color-picker',
            h: hsv.h,
            s: hsv.s,
            v: hsv.v,
            hex: hsvToHex(hsv.h, hsv.s, hsv.v),
          };
          render();
          return;
        }
      }
      if (state.inlineEdit.section === 'coordinates') {
        if (has('ie-use-gps')) {
          if (state.locationFix.status === 'found') {
            draft.latitude = Number(state.locationFix.latitude).toFixed(6);
            draft.longitude = Number(state.locationFix.longitude).toFixed(6);
            state.inlineEdit.error = '';
            state.message = t(lang, 'msgGpsApplied');
            state.showUndoAction = false;
            render();
          }
          return;
        }
        if (has('ie-resolve')) {
          const res = simulateResolveLocationSource(
            draft.sourceType,
            draft.source,
          );
          if (!res.ok) {
            state.inlineEdit.error = t(lang, res.errorKey);
            render();
            return;
          }
          if (res.candidates.length === 1) {
            draft.latitude = res.candidates[0].latitude.toFixed(6);
            draft.longitude = res.candidates[0].longitude.toFixed(6);
            state.inlineEdit.error = '';
            state.message = t(lang, 'msgResolvedSingle');
            state.showUndoAction = false;
            render();
          } else {
            state.modal = {
              type: 'geo-candidates',
              candidates: res.candidates,
            };
            render();
          }
          return;
        }
      }
    }

    // Color Picker Confirm
    if (has('confirm-color-picker') && state.modal?.type === 'color-picker') {
      if (
        state.inlineEdit?.kind === 'label' &&
        state.inlineEdit?.section === 'color'
      ) {
        state.inlineEdit.draft.color = state.modal.hex;
        state.inlineEdit.error = '';
      }
      state.modal = null;
      render();
      return;
    }

    // Geocoding Candidate Confirm
    if (has('pick-candidate') && state.modal?.type === 'geo-candidates') {
      const cand = state.modal.candidates[Number(button.dataset.pickCandidate)];
      if (
        cand &&
        state.inlineEdit?.kind === 'location' &&
        state.inlineEdit?.section === 'coordinates'
      ) {
        state.inlineEdit.draft.latitude = cand.latitude.toFixed(6);
        state.inlineEdit.draft.longitude = cand.longitude.toFixed(6);
        state.inlineEdit.draft.source = cand.displayName;
        state.inlineEdit.error = '';
      }
      state.modal = null;
      render();
      return;
    }

    // Workspaces Modal Actions
    if (state.modal?.type === 'workspaces') {
      const m = state.modal;
      if (has('ws-create-submit')) {
        const name = (m.createName || '').trim();
        if (!name || name.length > 128) {
          m.error = t(lang, 'errWorkspaceEmpty');
          render();
          return;
        }
        if (state.workspaces.length >= 32) {
          m.error = t(lang, 'errWorkspaceMax');
          render();
          return;
        }
        if (
          state.workspaces.some(
            (w) => w.name.toLowerCase() === name.toLowerCase(),
          )
        ) {
          m.error = t(lang, 'errWorkspaceDup');
          render();
          return;
        }
        const fileName = suggestWorkspaceFileName(name);
        const newWs = {
          id: `ws_${generateBase62Id().toLowerCase()}`,
          name,
          config: defaultConfig({
            localFilePath: fileName,
            filePath: fileName,
            language: ws.config.language,
            themeMode: ws.config.themeMode,
            themePalette: ws.config.themePalette,
          }),
          localFiles: [fileName],
          deleted: { generation: 0, tasks: [], labels: [], locations: [] },
          locations: [],
          labels: [],
          queue: [],
          tasks: [],
        };
        state.workspaces.push(newWs);
        switchWorkspace(newWs.id);
        return;
      }
      if (has('ws-select')) {
        switchWorkspace(button.dataset.wsSelect);
        return;
      }
      if (has('ws-start-rename')) {
        const target = state.workspaces.find(
          (w) => w.id === button.dataset.wsStartRename,
        );
        if (target) {
          m.renamingId = target.id;
          m.renameDraft = target.name;
          m.deletingId = null;
          m.error = '';
          render();
        }
        return;
      }
      if (has('ws-rename-cancel')) {
        m.renamingId = null;
        m.renameDraft = '';
        render();
        return;
      }
      if (has('ws-rename-save')) {
        const id = button.dataset.wsRenameSave;
        const input = app.querySelector('[data-ws-rename-input]');
        const nextName = String(input?.value || '').trim();
        if (!nextName) {
          m.error = t(lang, 'errWorkspaceEmpty');
          render();
          return;
        }
        if (
          state.workspaces.some(
            (w) => w.id !== id && w.name.toLowerCase() === nextName.toLowerCase(),
          )
        ) {
          m.error = t(lang, 'errWorkspaceDup');
          render();
          return;
        }
        const target = state.workspaces.find((w) => w.id === id);
        if (target) target.name = nextName;
        m.renamingId = null;
        m.error = '';
        render();
        return;
      }
      if (has('ws-ask-delete')) {
        if (state.workspaces.length <= 1) {
          m.error = t(lang, 'errWorkspaceLast');
        } else {
          m.deletingId = button.dataset.wsAskDelete;
          m.renamingId = null;
          m.error = '';
        }
        render();
        return;
      }
      if (has('ws-cancel-delete')) {
        m.deletingId = null;
        render();
        return;
      }
      if (has('ws-confirm-delete')) {
        const id = button.dataset.wsConfirmDelete;
        if (state.workspaces.length <= 1) return;
        state.workspaces = state.workspaces.filter((w) => w.id !== id);
        m.deletingId = null;
        if (state.activeWorkspaceId === id) {
          switchWorkspace(state.workspaces[0].id);
          return;
        }
        render();
        return;
      }
    }

    // Location Status Modal Refresh
    if (has('refresh-location')) {
      state.locationSearching = true;
      render();
      setTimeout(() => {
        state.locationSearching = false;
        state.locationFix = { ...SIMULATED_LOCATIONS[state.simLocationKey] };
        logEvent('info', 'ui', 'location.refreshed', {
          status: state.locationFix.status,
        });
        render();
      }, 400);
      return;
    }

    // Settings Actions & Segmented Controls
    if (has('seg')) {
      const key = button.dataset.seg;
      const rawVal = button.dataset.segVal;
      const val = rawVal === 'true' ? true : rawVal === 'false' ? false : rawVal;
      ws.config[key] = val;
      if (key === 'language') {
        state.lang = resolveLang(val);
      }
      if (key === 'themePalette' || key === 'themeMode') {
        // Apply across all workspaces for cohesive preview feel
        for (const w of state.workspaces) w.config[key] = val;
      }
      logEvent('info', 'storage', 'settings.preference_updated', { key, val });
      render();
      return;
    }
    if (has('toggle-password')) {
      state.showPassword = !state.showPassword;
      render();
      return;
    }
    if (has('move-local')) {
      ws.config.localDirectory =
        ws.config.localDirectory.endsWith('/sync')
          ? '/home/demo/.local/share/tiertask'
          : '/home/demo/Documents/tiertask/sync';
      state.settingsBanner = {
        tone: 'success',
        text: t(lang, 'setMovedBanner'),
      };
      logEvent('info', 'storage', 'local_file.moved', {
        dir: ws.config.localDirectory,
      });
      render();
      return;
    }
    if (has('pick-local-file') && state.modal?.type === 'select-local') {
      state.modal.fileInput = button.dataset.pickLocalFile;
      render();
      return;
    }
    if (has('confirm-select-local') && state.modal?.type === 'select-local') {
      let name = state.modal.fileInput.trim();
      if (!name.toLowerCase().endsWith('.tdf')) name += '.tdf';
      ws.config.localFilePath = name;
      if (!ws.localFiles.includes(name)) ws.localFiles.push(name);
      state.modal = null;
      state.settingsBanner = {
        tone: 'success',
        text: t(lang, 'setSelectedBanner'),
      };
      render();
      return;
    }
    if (has('confirm-rename-local') && state.modal?.type === 'rename-local') {
      let name = state.modal.fileInput.trim();
      if (!name.toLowerCase().endsWith('.tdf')) name += '.tdf';
      const oldName = ws.config.localFilePath;
      ws.config.localFilePath = name;
      ws.localFiles = ws.localFiles.map((f) => (f === oldName ? name : f));
      state.modal = null;
      state.settingsBanner = {
        tone: 'success',
        text: t(lang, 'setRenamedBanner'),
      };
      render();
      return;
    }
    if (has('open-wipe')) {
      state.modal = {
        type: 'wipe-tdf',
        target: button.dataset.openWipe,
        confirmInput: '',
        createBackup: true,
      };
      render();
      return;
    }
    if (has('confirm-wipe') && state.modal?.type === 'wipe-tdf') {
      const isRemote = state.modal.target === 'remote';
      ws.tasks = [];
      ws.queue = [];
      ws.labels = [];
      ws.locations = [];
      ws.deleted = { generation: 0, tasks: [], labels: [], locations: [] };
      state.undoStack = [];
      state.modal = null;
      state.settingsBanner = {
        tone: 'success',
        text: t(
          lang,
          isRemote ? 'setWipedRemoteBanner' : 'setWipedLocalBanner',
        ),
      };
      logEvent('warn', 'storage', 'tdf.wiped', {
        target: isRemote ? 'remote' : 'local',
      });
      render();
      return;
    }
    if (has('settings-save')) {
      state.settingsBanner = {
        tone: 'success',
        text: t(lang, 'setSavedBanner'),
      };
      logEvent('info', 'storage', 'settings.saved', { workspace: ws.id });
      render();
      return;
    }
    if (has('settings-test-sync')) {
      state.settingsBanner = {
        tone: 'success',
        text: t(lang, 'setSyncedBanner'),
      };
      logEvent('info', 'sync', 'settings.test_sync_ok', { workspace: ws.id });
      render();
      return;
    }

    // Log Viewer & Raw TDF Actions
    if (has('log-copy')) {
      copyToClipboard(state.logs.join('\n'), 'logCopiedMsg');
      return;
    }
    if (has('log-clear')) {
      state.logs = state.logs.slice(0, 2);
      state.message = t(lang, 'logClearedMsg');
      state.showUndoAction = false;
      render();
      return;
    }
    if (has('log-sync')) {
      state.message = t(lang, 'logSyncedMsg');
      state.showUndoAction = false;
      logEvent('info', 'sync', 'log.uploaded_webdav', { workspace: ws.id });
      render();
      return;
    }
    if (has('log-bottom')) {
      const consoleEl = app.querySelector('[data-log-console]');
      if (consoleEl) consoleEl.scrollTop = consoleEl.scrollHeight;
      return;
    }
    if (has('copy-raw-tdf')) {
      copyToClipboard(serializeTdf080(ws), 'rawTdfCopied');
      return;
    }

    // Conflict & Recovery Resolution
    if (has('conflict-choice')) {
      const id = button.dataset.conflictChoice;
      const item = state.conflictItems.find((c) => c.id === id);
      if (item) {
        item.choice = button.dataset.choice;
        render();
      }
      return;
    }
    if (has('apply-conflicts')) {
      for (const item of state.conflictItems) {
        if (item.choice === 'delete' && item.entityType === 'task') {
          ws.tasks = ws.tasks.filter((task) => task.id !== item.id);
          ws.queue = ws.queue.filter((qid) => qid !== item.id);
        }
      }
      ws.deleted.generation += 1;
      state.undoStack = [];
      state.simState = 'normal';
      const simSelect = root.querySelector('[data-sim-state]');
      if (simSelect) simSelect.value = 'normal';
      state.view = 'tasks';
      state.message = t(lang, 'conflictResolvedMsg');
      state.showUndoAction = false;
      logEvent('info', 'sync', 'sync.deletion_conflicts_resolved', {
        generation: ws.deleted.generation,
      });
      render();
      return;
    }
    if (has('recovery-choice')) {
      const id = button.dataset.recoveryChoice;
      const item = state.recoveryItems.find((c) => c.id === id);
      if (item) {
        item.choice = button.dataset.choice;
        render();
      }
      return;
    }
    if (has('apply-recovery')) {
      for (const item of state.recoveryItems) {
        if (item.choice === 'discard') {
          ws.tasks = ws.tasks.filter((task) => task.id !== item.id);
          ws.queue = ws.queue.filter((qid) => qid !== item.id);
        } else {
          const target = ws.tasks.find((task) => task.id === item.id);
          if (target) {
            const freshId = generateBase62Id();
            ws.queue = ws.queue.map((qid) => (qid === target.id ? freshId : qid));
            target.id = freshId;
          }
        }
      }
      ws.deleted.generation += 2;
      state.undoStack = [];
      state.simState = 'normal';
      const simSelect = root.querySelector('[data-sim-state]');
      if (simSelect) simSelect.value = 'normal';
      state.view = 'tasks';
      state.message = t(lang, 'recoveryResolvedMsg');
      state.showUndoAction = false;
      logEvent('info', 'sync', 'sync.recovery_completed', {
        generation: ws.deleted.generation,
      });
      render();
    }
  });

  /* ==========================================================================
     Input, Change, Submit, Pointer, Keyboard Events
     ========================================================================== */

  let draggingWheel = false;

  app.addEventListener('pointerdown', (event) => {
    const canvas = event.target.closest('[data-hsv-wheel]');
    if (!canvas) return;
    draggingWheel = true;
    canvas.setPointerCapture(event.pointerId);
    updateWheelFromPointer(canvas, event.clientX, event.clientY);
  });

  app.addEventListener('pointermove', (event) => {
    if (!draggingWheel) return;
    const canvas = app.querySelector('[data-hsv-wheel]');
    if (canvas) updateWheelFromPointer(canvas, event.clientX, event.clientY);
  });

  app.addEventListener('pointerup', () => {
    draggingWheel = false;
  });

  app.addEventListener('input', (event) => {
    const el = event.target;
    const ws = activeWorkspace();

    if (el.hasAttribute('data-global-search')) {
      state.searchQuery = el.value;
      render();
      return;
    }
    if (el.hasAttribute('data-sidebar-label-filter')) {
      state.sidebarLabelFilter = el.value;
      render();
      return;
    }
    if (el.hasAttribute('data-lp-search')) {
      const mode = el.dataset.lpSearch;
      const picker =
        mode === 'task' ? state.taskLabelPicker : state.draftLabelPicker;
      if (picker) {
        picker.query = el.value;
        picker.activeIndex = el.value.trim() ? 0 : -1;
        render();
      }
      return;
    }
    if (el.hasAttribute('data-draft')) {
      state.draft[el.dataset.draft] = el.value;
      return;
    }
    if (el.hasAttribute('data-ie') && state.inlineEdit) {
      state.inlineEdit.draft[el.dataset.ie] =
        el.type === 'checkbox' ? el.checked : el.value;
      state.inlineEdit.error = '';
      if (el.dataset.ie === 'color') {
        const swatch = app.querySelector('.color-swatch-preview');
        if (swatch && /^#[0-9a-fA-F]{6}$/.test(el.value.trim())) {
          swatch.style.background = el.value.trim();
        }
      }
      return;
    }
    if (el.hasAttribute('data-ie-link-title') && state.inlineEdit) {
      state.inlineEdit.draft.linkTitleDraft = el.value;
      return;
    }
    if (el.hasAttribute('data-ie-link-uri') && state.inlineEdit) {
      state.inlineEdit.draft.linkUriDraft = el.value;
      return;
    }
    if (el.hasAttribute('data-ie-step-text') && state.inlineEdit) {
      const step = state.inlineEdit.draft.subtasks[Number(el.dataset.ieStepText)];
      if (step) step.text = el.value;
      return;
    }
    if (el.hasAttribute('data-ie-prereq-search') && state.inlineEdit) {
      state.inlineEdit.draft.prereqQuery = el.value;
      render();
      return;
    }
    if (el.hasAttribute('data-set-field')) {
      ws.config[el.dataset.setField] = el.value;
      if (
        el.dataset.setField === 'serverUrl' ||
        el.dataset.setField === 'username' ||
        el.dataset.setField === 'filePath'
      ) {
        render();
      }
      return;
    }
    if (el.hasAttribute('data-ws-create-input') && state.modal?.type === 'workspaces') {
      state.modal.createName = el.value;
      state.modal.error = '';
      render();
      return;
    }
    if (el.hasAttribute('data-local-file-input') && state.modal) {
      state.modal.fileInput = el.value;
      render();
      return;
    }
    if (el.hasAttribute('data-wipe-confirm-input') && state.modal?.type === 'wipe-tdf') {
      state.modal.confirmInput = el.value;
      render();
      return;
    }
    if (el.hasAttribute('data-hsv-value') && state.modal?.type === 'color-picker') {
      state.modal.v = Number(el.value) / 100;
      state.modal.hex = hsvToHex(state.modal.h, state.modal.s, state.modal.v);
      drawHsvWheel();
      const swatch = app.querySelector('[data-wheel-swatch]');
      const hexEl = app.querySelector('[data-wheel-hex]');
      if (swatch) swatch.style.background = state.modal.hex;
      if (hexEl) hexEl.textContent = state.modal.hex;
    }
  });

  app.addEventListener('change', (event) => {
    const el = event.target;
    const ws = activeWorkspace();
    const lang = state.lang;

    if (el.hasAttribute('data-tier-select')) {
      state.tier = Number(el.value);
      clearExpandedState();
      render();
      return;
    }
    if (el.hasAttribute('data-draft')) {
      state.draft[el.dataset.draft] = el.value;
      const hint = app.querySelector('[data-mode-hint]');
      if (hint) {
        hint.textContent =
          el.value === 'priority'
            ? t(lang, 'hintPriority')
            : el.value === 'someday'
              ? t(lang, 'hintSomeday')
              : t(lang, 'hintQueue');
      }
      return;
    }
    if (el.hasAttribute('data-info-step')) {
      const idx = Number(el.dataset.infoStep);
      const task = ws.tasks.find((item) => item.id === el.dataset.taskId);
      if (!task || !task.subtasks[idx]) return;
      const willAutoFinish =
        task.subtasksAutoFinish &&
        el.checked &&
        task.subtasks.every((s, i) => (i === idx ? true : s.done));
      if (willAutoFinish) {
        pushUndo('complete', task.title);
      }
      task.subtasks[idx].done = el.checked;
      if (willAutoFinish) {
        const res = completeTask(ws, task.id, evalContext());
        state.message = t(
          lang,
          res.repeated ? 'msgCompletedRepeat' : 'msgCompleted',
          { title: task.title },
        );
        if (
          state.expandedEntity?.kind === 'task' &&
          state.expandedEntity?.id === task.id
        ) {
          clearExpandedState();
        }
        logEvent('info', 'domain', 'task.auto_finished', { id: task.id });
      }
      render();
      return;
    }
    if (el.hasAttribute('data-sim-location')) {
      state.simLocationKey = el.value;
      state.locationFix = { ...SIMULATED_LOCATIONS[el.value] };
      logEvent('info', 'ui', 'location.simulated_changed', {
        preset: el.value,
      });
      render();
      return;
    }
    if (el.hasAttribute('data-set-field')) {
      ws.config[el.dataset.setField] =
        el.dataset.setField === 'manualTimeZoneOffsetMinutes'
          ? Number(el.value)
          : el.value;
      render();
      return;
    }
    if (el.hasAttribute('data-set-bool')) {
      ws.config[el.dataset.setBool] = el.checked;
      render();
      return;
    }
    if (el.hasAttribute('data-wipe-backup') && state.modal?.type === 'wipe-tdf') {
      state.modal.createBackup = el.checked;
      return;
    }
    if (el.hasAttribute('data-log-level')) {
      state.logFilterLevel = el.value;
      render();
      return;
    }
    if (el.hasAttribute('data-log-tag')) {
      state.logFilterTag = el.value;
      render();
      return;
    }

    // Unified inline section editor controls (Tasks, Labels, Locations)
    if (state.inlineEdit) {
      const draft = state.inlineEdit.draft;
      if (el.hasAttribute('data-ie')) {
        const key = el.dataset.ie;
        draft[key] = el.type === 'checkbox' ? el.checked : el.value;
        state.inlineEdit.error = '';
        if (
          key === 'suspendedMode' ||
          key === 'daysMode' ||
          key === 'timeMode' ||
          key === 'placesMode' ||
          key === 'sourceType'
        ) {
          render();
        }
        return;
      }
      if (el.hasAttribute('data-ie-step-done')) {
        const step = draft.subtasks[Number(el.dataset.ieStepDone)];
        if (step) step.done = el.checked;
        return;
      }
      if (el.hasAttribute('data-ie-prereq')) {
        const id = el.dataset.iePrereq;
        draft.prerequisites = draft.prerequisites.filter((x) => x !== id);
        if (el.checked) draft.prerequisites.push(id);
        render();
        return;
      }
      if (el.hasAttribute('data-ie-day')) {
        const d = Number(el.dataset.ieDay);
        draft.days = draft.days.filter((x) => x !== d);
        if (el.checked) draft.days.push(d);
        draft.days.sort((a, b) => a - b);
      }
    }
  });

  app.addEventListener('submit', (event) => {
    event.preventDefault();
    const form = event.target;

    if (form.dataset.form === 'quick-task') {
      const saveBtn = form.querySelector('[data-save]');
      if (saveBtn) saveBtn.click();
      return;
    }
    if (form.dataset.form === 'quick-create-labels') {
      createQuickManagedEntity('labels', false);
      return;
    }
    if (form.dataset.form === 'quick-create-locations') {
      createQuickManagedEntity('locations', false);
    }
  });

  document.addEventListener('keydown', (event) => {
    const isInput = event.target?.matches('input, textarea, select');

    if (event.target?.hasAttribute('data-lp-search')) {
      const mode = event.target.dataset.lpSearch;
      const picker =
        mode === 'task' ? state.taskLabelPicker : state.draftLabelPicker;
      if (picker) {
        const ws = activeWorkspace();
        const { filtered, canCreate } = filterPickerLabels(
          ws,
          picker.query,
          picker.scopeFilter,
        );
        const total = filtered.length + (canCreate ? 1 : 0);

        if (event.key === 'ArrowDown' && total > 0) {
          event.preventDefault();
          picker.activeIndex =
            picker.activeIndex < 0 ? 0 : Math.min(total - 1, picker.activeIndex + 1);
          render();
          app
            .querySelector(`[data-lp-row-idx="${picker.activeIndex}"]`)
            ?.scrollIntoView({ block: 'nearest' });
          return;
        }
        if (event.key === 'ArrowUp' && total > 0) {
          event.preventDefault();
          picker.activeIndex =
            picker.activeIndex < 0 ? total - 1 : Math.max(0, picker.activeIndex - 1);
          render();
          app
            .querySelector(`[data-lp-row-idx="${picker.activeIndex}"]`)
            ?.scrollIntoView({ block: 'nearest' });
          return;
        }
        if (event.key === 'Enter') {
          event.preventDefault();
          if (total === 0) return;
          const idx =
            picker.activeIndex < 0
              ? 0
              : Math.min(picker.activeIndex, total - 1);
          if (idx < filtered.length) {
            const targetId = filtered[idx].id;
            if (mode === 'task') {
              directToggleLabel(picker.taskId, targetId);
            } else {
              toggleDraftLabel(targetId);
            }
          } else if (canCreate) {
            createAndAssignLabelFromPicker(mode);
          }
          return;
        }
        if (event.key === 'Escape') {
          event.preventDefault();
          if (picker.query) {
            picker.query = '';
            picker.activeIndex = -1;
            render();
          } else {
            if (mode === 'task') state.taskLabelPicker = null;
            else state.draftLabelPicker = null;
            render();
          }
          return;
        }
      }
    }

    if (event.key === 'Enter' && event.target) {
      const ieKey = event.target.getAttribute('data-ie');
      if (
        (ieKey === 'title' && state.inlineEdit?.section === 'title') ||
        (ieKey === 'name' && state.inlineEdit?.section === 'name')
      ) {
        event.preventDefault();
        saveInlineEdit();
        return;
      }
      if (event.target.hasAttribute('data-ie-new-step')) {
        event.preventDefault();
        app.querySelector('[data-ie-add-step]')?.click();
        return;
      }
      if (event.target.hasAttribute('data-info-hist-new')) {
        event.preventDefault();
        app.querySelector('[data-info-hist-add]')?.click();
        return;
      }
      if (event.target.hasAttribute('data-ws-create-input')) {
        event.preventDefault();
        app.querySelector('[data-ws-create-submit]')?.click();
        return;
      }
    }

    if (event.key === 'Escape') {
      if (state.modal) {
        state.modal = null;
        render();
        return;
      }
      if (state.taskLabelPicker || state.draftLabelPicker) {
        state.taskLabelPicker = null;
        state.draftLabelPicker = null;
        render();
        return;
      }
      if (state.searchOpen) {
        state.searchOpen = false;
        state.searchQuery = '';
        render();
        return;
      }
      if (state.inlineEdit) {
        state.inlineEdit = null;
        render();
        return;
      }
      if (state.inlineDeleteConfirmKey) {
        state.inlineDeleteConfirmKey = null;
        render();
        return;
      }
      if (state.expandedEntity) {
        clearExpandedState();
        render();
        return;
      }
    }

    if (
      (event.ctrlKey || event.metaKey) &&
      !event.shiftKey &&
      !event.altKey &&
      event.key.toLowerCase() === 'z' &&
      !isInput &&
      state.view === 'tasks' &&
      !state.modal &&
      state.undoStack.length > 0
    ) {
      event.preventDefault();
      performUndo();
      return;
    }

    if (
      !isInput &&
      !state.modal &&
      state.view === 'tasks' &&
      !state.searchOpen
    ) {
      if (event.key === 'ArrowLeft' && state.tier > 0) {
        event.preventDefault();
        state.tier -= 1;
        clearExpandedState();
        render();
      } else if (event.key === 'ArrowRight' && state.tier < 5) {
        event.preventDefault();
        state.tier += 1;
        clearExpandedState();
        render();
      }
    }
  });

  /* ==========================================================================
     Preview Harness Toolbar Bindings
     ========================================================================== */

  root.querySelectorAll('[data-device]').forEach((button) => {
    button.addEventListener('click', () => {
      root
        .querySelector('.stage')
        .classList.toggle('mobile', button.dataset.device === 'mobile');
      root.querySelectorAll('[data-device]').forEach((ctrl) => {
        ctrl.setAttribute('aria-pressed', String(ctrl === button));
      });
      render();
    });
  });

  window.addEventListener('resize', () => {
    if (isCompactViewport() !== state.isCompact) {
      render();
    }
  });

  root.querySelectorAll('[data-theme-preset]').forEach((button) => {
    button.addEventListener('click', () => {
      const preset = button.dataset.themePreset;
      for (const ws of state.workspaces) ws.config.themePalette = preset;
      render();
    });
  });

  root.querySelectorAll('[data-color-mode]').forEach((button) => {
    button.addEventListener('click', () => {
      const mode = button.dataset.colorMode;
      for (const ws of state.workspaces) ws.config.themeMode = mode;
      render();
    });
  });

  root.querySelectorAll('[data-lang]').forEach((button) => {
    button.addEventListener('click', () => {
      state.lang = button.dataset.lang;
      const ws = activeWorkspace();
      ws.config.language = state.lang === 'en' ? 'english' : 'german';
      render();
    });
  });

  const simSelect = root.querySelector('[data-sim-state]');
  if (simSelect) {
    simSelect.addEventListener('change', () => {
      const value = simSelect.value;
      state.bannerDismissed = false;
      state.recoveryNotice = null;
      if (value === 'settings_backup') {
        state.simState = 'normal';
        state.recoveryNotice = 'noticeSettingsBackup';
        state.view = 'tasks';
      } else if (value === 'settings_quarantine') {
        state.simState = 'normal';
        state.recoveryNotice = 'noticeSettingsQuarantine';
        state.view = 'tasks';
      } else {
        state.simState = value;
        if (value === 'conflict_deletion' || value === 'conflict_recovery') {
          seedConflictItems();
        }
        if (value === 'file_read_full') {
          state.view = 'tasks';
        }
      }
      render();
    });
  }

  render();
})();
