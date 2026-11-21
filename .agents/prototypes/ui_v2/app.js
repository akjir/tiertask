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
    renderChrome,
    renderSidebar,
    renderBanners,
    renderFullFileReadError,
    renderTaskView,
    renderManagerView,
    renderLabelEditor,
    renderLocationEditor,
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
    expandedTaskId: null,
    justExpandedTaskId: null,
    inlineEdit: null,
    inlineDeleteConfirmTaskId: null,
    editingHistoryIndex: null,
    historyEditDraft: '',
    draft: { title: '', mode: 'queue', labels: [] },
    labelEdit: null,
    locationEdit: null,
    managerDeleteConfirm: null,
    editorError: '',
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
        title: ws.labels[1]?.name || 'Kunde GEW Sachsen',
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
      case 'label-edit':
        return renderLabelEditor(state, workspace);
      case 'location-edit':
        return renderLocationEditor(state);
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

  function render() {
    const focusDesc = captureFocusDescriptor();
    const ws = activeWorkspace();
    const evalRes = evaluateBoard(ws, evalContext());
    syncPreviewToolbarFromConfig();

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
      ${renderActiveModal(state, ws)}
    `;

    if (state.justExpandedTaskId) {
      const panel = app.querySelector(
        `[data-slide-panel="${CSS.escape(state.justExpandedTaskId)}"]`,
      );
      if (panel) {
        void panel.offsetHeight;
        panel.classList.add('is-open');
      }
      state.justExpandedTaskId = null;
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
     Inline Task Section Editing & Direct Toggles
     ========================================================================== */

  function clearExpandedTaskState() {
    state.expandedTaskId = null;
    state.justExpandedTaskId = null;
    state.inlineEdit = null;
    state.inlineDeleteConfirmTaskId = null;
    state.editingHistoryIndex = null;
    state.historyEditDraft = '';
  }

  function startInlineEdit(taskId, section) {
    const ws = activeWorkspace();
    const task = ws.tasks.find((item) => item.id === taskId);
    if (!task) return;
    const offset = resolveOffsetMinutes(ws.config);
    const c = task.conditions || {};
    let draft = {};

    if (section === 'title') {
      draft = { title: task.title };
    } else if (section === 'note') {
      draft = { note: task.note || '' };
    } else if (section === 'links') {
      draft = {
        links: structuredClone(task.links || []),
        editingLinkIndex: null,
        linkTitleDraft: '',
        linkUriDraft: '',
      };
    } else if (section === 'subtasks') {
      draft = {
        subtasksAutoFinish: Boolean(task.subtasksAutoFinish),
        subtasks: structuredClone(task.subtasks || []),
      };
    } else if (section === 'due') {
      draft = {
        dueLocal: task.dueAt
          ? formatLocalDatetimeInput(task.dueAt, offset)
          : '',
        autoDue: !task.duePassive,
        dueNote: task.dueNote || '',
      };
    } else if (section === 'repeat') {
      draft = {
        repeatEvery: task.repeat?.count ?? 1,
        repeatUnit: task.repeat?.unit ?? 'weeks',
        repeatLeadDays: task.repeat?.leadDays ?? 0,
      };
    } else if (section === 'suspended') {
      draft = {
        suspendedMode:
          task.suspendedMode && task.suspendedMode !== 'none'
            ? task.suspendedMode
            : 'until',
        suspendedLocal: task.suspendedAt
          ? formatLocalDatetimeInput(task.suspendedAt, offset)
          : '',
        suspendedNote: task.suspendedNote || '',
      };
    } else if (section === 'prereqs') {
      draft = {
        prerequisites: (task.blockedBy || []).map((d) => d.taskId),
        prereqQuery: '',
      };
    } else if (section === 'conditions') {
      draft = {
        ignoreLabels: Boolean(c.ignoreLabels),
        daysMode: c.daysMode || 'inherit',
        days: [...(c.days || [])],
        timeMode: c.timeMode || 'inherit',
        times: structuredClone(c.times || []),
        placesMode: c.placesMode || 'inherit',
        locationIds: [...(c.locationIds || [])],
      };
    } else {
      return;
    }

    state.expandedTaskId = task.id;
    state.justExpandedTaskId = null;
    state.inlineDeleteConfirmTaskId = null;
    state.editingHistoryIndex = null;
    state.historyEditDraft = '';
    state.inlineEdit = { taskId: task.id, section, draft, error: '' };
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
      state.expandedTaskId = null;
      state.inlineEdit = null;
      state.message = t(lang, 'msgTaskMovedTier', {
        tier: tierName(lang, nextTier),
      });
    } else if (fallbackKey) {
      state.message = t(lang, fallbackKey);
    }
    state.showUndoAction = false;
  }

  function saveInlineEdit() {
    const edit = state.inlineEdit;
    if (!edit) return;
    const ws = activeWorkspace();
    const lang = state.lang;
    const task = ws.tasks.find((item) => item.id === edit.taskId);
    if (!task) {
      state.inlineEdit = null;
      render();
      return;
    }

    const offset = resolveOffsetMinutes(ws.config);
    const nowIso = new Date(state.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');
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
        state.inlineEdit = null;
        clearExpandedTaskState();
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
    const task = ws.tasks.find((item) => item.id === edit.taskId);
    if (!task) return;
    const nowIso = new Date(state.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');

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
      clearExpandedTaskState();
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
      clearExpandedTaskState();
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
      state.expandedTaskId = newTask.id;
      state.justExpandedTaskId = newTask.id;
      state.inlineEdit = null;
      state.inlineDeleteConfirmTaskId = null;
    }
    render();
  }

  /* ==========================================================================
     Label & Location Editors Setup & Save
     ========================================================================== */

  function openLabelEditor(labelId) {
    const ws = activeWorkspace();
    const existing = labelId
      ? ws.labels.find((l) => l.id === labelId)
      : null;
    state.labelEdit = existing
      ? {
          id: existing.id,
          name: existing.name,
          color: existing.color || '#2196F3',
          scoped: Boolean(existing.scoped),
          note: existing.note || '',
          links: structuredClone(existing.links || []),
          editingLinkIndex: null,
          linkTitleDraft: '',
          linkUriDraft: '',
          conditions: structuredClone(
            existing.conditions || { days: [], times: [], locationIds: [] },
          ),
        }
      : {
          id: null,
          name: '',
          color: '#2196F3',
          scoped: false,
          note: '',
          links: [],
          editingLinkIndex: null,
          linkTitleDraft: '',
          linkUriDraft: '',
          conditions: { days: [], times: [], locationIds: [] },
        };
    state.editorError = '';
    state.modal = null;
    state.drawer = false;
    state.view = 'label-edit';
    render();
  }

  function saveLabelEditor() {
    const ws = activeWorkspace();
    const lang = state.lang;
    const item = state.labelEdit;
    const name = item.name.trim();
    if (!name) {
      state.editorError = t(lang, 'errLabelNameEmpty');
      render();
      return;
    }
    if (
      ws.labels.some(
        (l) => l.id !== item.id && l.name.trim().toLowerCase() === name.toLowerCase(),
      )
    ) {
      state.editorError = t(lang, 'errLabelNameDup');
      render();
      return;
    }
    const color = item.color.trim().toUpperCase();
    if (color && !/^#[0-9A-F]{6}$/.test(color)) {
      state.editorError = t(lang, 'errColorInvalid');
      render();
      return;
    }
    const nowIso = new Date(state.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');
    const updated = {
      id: item.id || generateBase62Id(),
      name,
      color: color || '#2196F3',
      scoped: Boolean(item.scoped),
      note: item.note.trim(),
      links: structuredClone(item.links),
      conditions: structuredClone(item.conditions),
      modifiedAt: nowIso,
    };
    const idx = ws.labels.findIndex((l) => l.id === updated.id);
    if (idx >= 0) ws.labels.splice(idx, 1, updated);
    else ws.labels.push(updated);

    logEvent('info', 'domain', idx >= 0 ? 'label.updated' : 'label.added', {
      id: updated.id,
      scoped: updated.scoped,
    });
    state.view = 'labels';
    state.labelEdit = null;
    state.editorError = '';
    state.message = t(lang, 'msgSavedLabel');
    state.showUndoAction = false;
    render();
  }

  function openLocationEditor(locId) {
    const ws = activeWorkspace();
    const existing = locId
      ? ws.locations.find((l) => l.id === locId)
      : null;
    state.locationEdit = existing
      ? {
          id: existing.id,
          name: existing.name,
          sourceType: existing.sourceType || 'gps',
          source: existing.source || '',
          latitude: String(existing.latitude),
          longitude: String(existing.longitude),
          radiusText: `${existing.radius}m`,
          note: existing.note || '',
        }
      : {
          id: null,
          name: '',
          sourceType: 'gps',
          source: '',
          latitude:
            state.locationFix.status === 'found'
              ? Number(state.locationFix.latitude).toFixed(6)
              : '51.050400',
          longitude:
            state.locationFix.status === 'found'
              ? Number(state.locationFix.longitude).toFixed(6)
              : '13.737300',
          radiusText: '100m',
          note: '',
        };
    state.editorError = '';
    state.modal = null;
    state.drawer = false;
    state.view = 'location-edit';
    render();
  }

  function saveLocationEditor() {
    const ws = activeWorkspace();
    const lang = state.lang;
    const item = state.locationEdit;
    const name = item.name.trim();
    if (!name) {
      state.editorError = t(lang, 'errLocNameEmpty');
      render();
      return;
    }
    const lat = Number(item.latitude);
    const lon = Number(item.longitude);
    const radius = parseRadiusMeters(item.radiusText);
    if (
      !Number.isFinite(lat) ||
      lat < -90 ||
      lat > 90 ||
      !Number.isFinite(lon) ||
      lon < -180 ||
      lon > 180 ||
      radius === null
    ) {
      state.editorError = t(lang, 'errLocCoordsInvalid');
      render();
      return;
    }
    const nowIso = new Date(state.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');
    const updated = {
      id: item.id || generateBase62Id(),
      name,
      sourceType: item.sourceType,
      source: item.sourceType === 'gps' ? 'gps' : item.source.trim(),
      latitude: Math.round(lat * 1e6) / 1e6,
      longitude: Math.round(lon * 1e6) / 1e6,
      radius,
      note: item.note.trim(),
      modifiedAt: nowIso,
    };
    const idx = ws.locations.findIndex((l) => l.id === updated.id);
    if (idx >= 0) ws.locations.splice(idx, 1, updated);
    else ws.locations.push(updated);

    logEvent('info', 'domain', idx >= 0 ? 'location.updated' : 'location.added', {
      id: updated.id,
      radius,
    });
    state.view = 'locations';
    state.locationEdit = null;
    state.editorError = '';
    state.message = t(lang, 'msgSavedLocation');
    state.showUndoAction = false;
    render();
  }

  function handleLinkListAction(
    container,
    prefix,
    button,
    setError = (msg) => {
      state.editorError = msg;
    },
  ) {
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
    clearExpandedTaskState();
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
      clearExpandedTaskState();
      state.managerDeleteConfirm = null;
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
      clearExpandedTaskState();
      state.message = '';
      render();
      return;
    }
    if (has('label')) {
      state.label = button.dataset.label;
      state.view = 'tasks';
      state.tier = 0;
      state.drawer = false;
      clearExpandedTaskState();
      state.draft.labels = state.label ? [state.label] : [];
      state.message = '';
      render();
      return;
    }
    if (has('toggle-search')) {
      state.searchOpen = !state.searchOpen;
      state.searchQuery = '';
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
    if (has('toggle-task')) {
      const taskId = button.dataset.toggleTask;
      const isOpening = state.expandedTaskId !== taskId;
      clearExpandedTaskState();
      if (isOpening) {
        state.expandedTaskId = taskId;
        state.justExpandedTaskId = taskId;
      }
      logEvent('info', 'ui', 'ui.task_panel.toggle', {
        id: taskId,
        expanded: isOpening,
      });
      render();
      return;
    }
    if (has('ie-open')) {
      startInlineEdit(button.dataset.ieTask, button.dataset.ieOpen);
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
      state.inlineDeleteConfirmTaskId = button.dataset.inlineDelAsk;
      render();
      return;
    }
    if (has('inline-del-no')) {
      state.inlineDeleteConfirmTaskId = null;
      render();
      return;
    }
    if (has('inline-del-yes')) {
      const taskId = button.dataset.inlineDelYes;
      const target = ws.tasks.find((item) => item.id === taskId);
      if (target) {
        pushUndo('delete', target.title);
        ws.tasks = ws.tasks.filter((item) => item.id !== taskId);
        ws.queue = ws.queue.filter((id) => id !== taskId);
        ws.deleted.tasks.push({
          id: target.id,
          deletedAt: new Date(state.nowMs)
            .toISOString()
            .replace(/\.\d{3}Z$/, 'Z'),
        });
        state.message = t(lang, 'msgDeleted', { title: target.title });
        logEvent('info', 'domain', 'task.deleted', { id: target.id });
      }
      clearExpandedTaskState();
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
    if (has('direct-mode')) {
      directSetMode(button.dataset.taskId, button.dataset.directMode);
      return;
    }
    if (has('open-label-hub')) {
      state.drawer = false;
      state.modal = {
        type: 'label-hub',
        labelId: button.dataset.openLabelHub,
      };
      logEvent('info', 'ui', 'ui.label_hub.open', { id: state.modal.labelId });
      render();
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
      if (state.expandedTaskId === taskId) {
        clearExpandedTaskState();
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
        if (state.expandedTaskId === taskId) {
          clearExpandedTaskState();
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
      copyToClipboard(button.dataset.copyId, 'msgCopiedId');
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
    if (state.expandedTaskId) {
      const task = ws.tasks.find((item) => item.id === state.expandedTaskId);
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

    // Quick-Add Submit & Add + Expand
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

    // Open Label / Location Editors
    if (has('edit-label')) {
      openLabelEditor(button.dataset.editLabel);
      return;
    }
    if (has('edit-location')) {
      openLocationEditor(button.dataset.editLocation);
      return;
    }
    if (has('new')) {
      if (button.dataset.new === 'labels') openLabelEditor(null);
      else openLocationEditor(null);
      return;
    }

    // Inline Task Section Edit Sub-Controls
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
      }
    }

    // Manager Delete Confirmations
    if (has('manager-ask-delete')) {
      state.managerDeleteConfirm = button.dataset.managerAskDelete;
      render();
      return;
    }
    if (has('manager-cancel-delete')) {
      state.managerDeleteConfirm = null;
      render();
      return;
    }
    if (has('manager-confirm-delete')) {
      const [kind, id] = button.dataset.managerConfirmDelete.split(':');
      const nowIso = new Date(state.nowMs)
        .toISOString()
        .replace(/\.\d{3}Z$/, 'Z');
      if (kind === 'labels') {
        ws.labels = ws.labels.filter((l) => l.id !== id);
        for (const task of ws.tasks) {
          task.labels = (task.labels || []).filter((lid) => lid !== id);
        }
        ws.deleted.labels.push({ id, deletedAt: nowIso });
        if (state.label === id) state.label = '';
        state.message = t(lang, 'msgDeletedLabel');
      } else {
        ws.locations = ws.locations.filter((l) => l.id !== id);
        ws.deleted.locations.push({ id, deletedAt: nowIso });
        state.message = t(lang, 'msgDeletedLocation');
      }
      state.managerDeleteConfirm = null;
      state.showUndoAction = false;
      render();
      return;
    }

    // Label Editor Controls
    if (state.view === 'label-edit' && state.labelEdit) {
      const item = state.labelEdit;
      if (has('save-label')) {
        saveLabelEditor();
        return;
      }
      if (has('le-preset')) {
        item.color = button.dataset.lePreset;
        render();
        return;
      }
      if (has('open-color-picker')) {
        const hsv = hexToHsv(item.color);
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
      if (handleLinkListAction(item, 'le', button)) return;
      if (has('le-add-time')) {
        const start = app.querySelector('[data-le-time-start]')?.value;
        const end = app.querySelector('[data-le-time-end]')?.value;
        if (!start || !end) {
          state.editorError = t(lang, 'errTimeInvalid');
          render();
          return;
        }
        item.conditions.times.push({ start, end });
        state.editorError = '';
        render();
        return;
      }
      if (has('le-remove-time')) {
        item.conditions.times.splice(Number(button.dataset.leRemoveTime), 1);
        render();
        return;
      }
    }

    // Color Picker Confirm
    if (has('confirm-color-picker') && state.modal?.type === 'color-picker') {
      if (state.labelEdit) state.labelEdit.color = state.modal.hex;
      state.modal = null;
      render();
      return;
    }

    // Location Editor Controls
    if (state.view === 'location-edit' && state.locationEdit) {
      const item = state.locationEdit;
      if (has('save-location')) {
        saveLocationEditor();
        return;
      }
      if (has('loce-use-gps')) {
        if (state.locationFix.status === 'found') {
          item.latitude = Number(state.locationFix.latitude).toFixed(6);
          item.longitude = Number(state.locationFix.longitude).toFixed(6);
          state.editorError = '';
          state.message = t(lang, 'msgGpsApplied');
          render();
        }
        return;
      }
      if (has('loce-resolve')) {
        const res = simulateResolveLocationSource(item.sourceType, item.source);
        if (!res.ok) {
          state.editorError = t(lang, res.errorKey);
          render();
          return;
        }
        if (res.candidates.length === 1) {
          item.latitude = res.candidates[0].latitude.toFixed(6);
          item.longitude = res.candidates[0].longitude.toFixed(6);
          state.editorError = '';
          state.message = t(lang, 'msgResolvedSingle');
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
    if (has('pick-candidate') && state.modal?.type === 'geo-candidates') {
      const cand = state.modal.candidates[Number(button.dataset.pickCandidate)];
      if (cand && state.locationEdit) {
        state.locationEdit.latitude = cand.latitude.toFixed(6);
        state.locationEdit.longitude = cand.longitude.toFixed(6);
        state.locationEdit.source = cand.displayName;
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
          ? '/home/stefan/.local/share/tiertask'
          : '/home/stefan/Documents/tiertask/sync';
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
    if (el.hasAttribute('data-draft')) {
      state.draft[el.dataset.draft] = el.value;
      return;
    }
    if (el.hasAttribute('data-ie') && state.inlineEdit) {
      state.inlineEdit.draft[el.dataset.ie] =
        el.type === 'checkbox' ? el.checked : el.value;
      state.inlineEdit.error = '';
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
    if (el.hasAttribute('data-le') && state.labelEdit) {
      state.labelEdit[el.dataset.le] =
        el.type === 'checkbox' ? el.checked : el.value;
      if (el.dataset.le === 'color') {
        const swatch = app.querySelector('.color-swatch-preview');
        if (swatch && /^#[0-9a-fA-F]{6}$/.test(el.value.trim())) {
          swatch.style.background = el.value.trim();
        }
      }
      return;
    }
    if (el.hasAttribute('data-le-link-title') && state.labelEdit) {
      state.labelEdit.linkTitleDraft = el.value;
      return;
    }
    if (el.hasAttribute('data-le-link-uri') && state.labelEdit) {
      state.labelEdit.linkUriDraft = el.value;
      return;
    }
    if (el.hasAttribute('data-loce') && state.locationEdit) {
      state.locationEdit[el.dataset.loce] = el.value;
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
      clearExpandedTaskState();
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
    if (el.hasAttribute('data-draft-label')) {
      const id = el.dataset.draftLabel;
      state.draft.labels = state.draft.labels.filter((lid) => lid !== id);
      if (el.checked) state.draft.labels.push(id);
      const summary = app.querySelector('[data-label-summary]');
      if (summary) {
        summary.textContent = t(lang, 'quickAddLabelsSummary', {
          count: state.draft.labels.length,
        });
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
        if (state.expandedTaskId === task.id) {
          clearExpandedTaskState();
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
    if (el.hasAttribute('data-loce') && state.locationEdit) {
      state.locationEdit[el.dataset.loce] = el.value;
      if (el.dataset.loce === 'sourceType') render();
      return;
    }

    // Label editor multi-checkboxes
    if (state.labelEdit) {
      const item = state.labelEdit;
      if (el.hasAttribute('data-le-day')) {
        const d = Number(el.dataset.leDay);
        item.conditions.days = item.conditions.days.filter((x) => x !== d);
        if (el.checked) item.conditions.days.push(d);
        item.conditions.days.sort((a, b) => a - b);
        return;
      }
      if (el.hasAttribute('data-le-place')) {
        const id = el.dataset.lePlace;
        item.conditions.locationIds = item.conditions.locationIds.filter(
          (x) => x !== id,
        );
        if (el.checked) item.conditions.locationIds.push(id);
        return;
      }
    }

    // Inline task section editor controls
    if (state.inlineEdit) {
      const draft = state.inlineEdit.draft;
      if (el.hasAttribute('data-ie')) {
        const key = el.dataset.ie;
        draft[key] = el.type === 'checkbox' ? el.checked : el.value;
        if (
          key === 'suspendedMode' ||
          key === 'daysMode' ||
          key === 'timeMode' ||
          key === 'placesMode'
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
        return;
      }
      if (el.hasAttribute('data-ie-place')) {
        const id = el.dataset.iePlace;
        draft.locationIds = draft.locationIds.filter((x) => x !== id);
        if (el.checked) draft.locationIds.push(id);
      }
    }
  });

  app.addEventListener('submit', (event) => {
    event.preventDefault();
    const form = event.target;
    const ws = activeWorkspace();
    const nowIso = new Date(state.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');

    if (form.dataset.form === 'quick-task') {
      const saveBtn = form.querySelector('[data-save]');
      if (saveBtn) saveBtn.click();
      return;
    }
    if (form.dataset.form === 'quick-create-labels') {
      const name = String(new FormData(form).get('name') || '').trim();
      if (!name) return;
      if (ws.labels.some((l) => l.name.toLowerCase() === name.toLowerCase())) {
        state.message = t(state.lang, 'errLabelNameDup');
        render();
        return;
      }
      ws.labels.push({
        id: generateBase62Id(),
        name,
        color: '#2196F3',
        scoped: false,
        note: '',
        links: [],
        conditions: { days: [], times: [], locationIds: [] },
        modifiedAt: nowIso,
      });
      state.message = t(state.lang, 'msgSavedLabel');
      render();
      return;
    }
    if (form.dataset.form === 'quick-create-locations') {
      const name = String(new FormData(form).get('name') || '').trim();
      if (!name) return;
      const fix = state.locationFix;
      ws.locations.push({
        id: generateBase62Id(),
        name,
        sourceType: 'gps',
        source: 'gps',
        latitude: fix.status === 'found' ? fix.latitude : 0,
        longitude: fix.status === 'found' ? fix.longitude : 0,
        radius: 100,
        note: '',
        modifiedAt: nowIso,
      });
      state.message = t(state.lang, 'msgSavedLocation');
      render();
    }
  });

  document.addEventListener('keydown', (event) => {
    const isInput = event.target?.matches('input, textarea, select');

    if (event.key === 'Enter' && event.target) {
      if (
        event.target.getAttribute('data-ie') === 'title' &&
        state.inlineEdit?.section === 'title'
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
      if (state.inlineDeleteConfirmTaskId) {
        state.inlineDeleteConfirmTaskId = null;
        render();
        return;
      }
      if (state.expandedTaskId) {
        clearExpandedTaskState();
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
        clearExpandedTaskState();
        render();
      } else if (event.key === 'ArrowRight' && state.tier < 5) {
        event.preventDefault();
        state.tier += 1;
        clearExpandedTaskState();
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
    });
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
