(() => {
  window.TT2 = window.TT2 || {};
  const { escapeHtml, renderIcon } = window.TT2;
  const {
    t,
    formatUtcOffset,
    suggestWorkspaceFileName,
  } = window.TT2.i18n;
  const {
    SUPPORTED_UTC_OFFSETS,
    resolveWebDavEndpoint,
    serializeTdf080,
  } = window.TT2.engine;

  function renderSegmented(attrName, currentValue, options) {
    return `
      <div class="segmented" role="group">
        ${options
          .map(
            ([val, label]) => `
          <button type="button" data-seg="${attrName}" data-seg-val="${escapeHtml(val)}" aria-pressed="${String(currentValue) === String(val)}">
            ${escapeHtml(label)}
          </button>`,
          )
          .join('')}
      </div>
    `;
  }

  function renderSettingsView(state, workspace) {
    const lang = state.lang;
    const cfg = workspace.config;
    const usesLocal = cfg.storageMode === 'local' || cfg.storageMode === 'both';
    const usesWebDav = cfg.storageMode === 'webdav' || cfg.storageMode === 'both';
    const resolvedLocal = `${cfg.localDirectory}/${cfg.localFilePath}`;
    const resolvedRemote = resolveWebDavEndpoint(cfg);
    const activeLogFile = `tiertask_2026-11-21_linux_${workspace.id}.log`;

    return `
      <button type="button" class="back" data-view="tasks">${renderIcon('arrow-left', 'icon-sm')}${escapeHtml(t(lang, 'actionBackTasks'))}</button>
      <div class="heading">
        <div>
          <h2>${escapeHtml(t(lang, 'settingsTitle'))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, 'settingsSubtitle', { workspace: workspace.name }))}</div>
        </div>
      </div>

      ${
        state.settingsBanner
          ? `<div class="status-banner ${state.settingsBanner.tone === 'error' ? 'tone-danger' : 'tone-success'}" role="status">
              ${renderIcon(state.settingsBanner.tone === 'error' ? 'alert-circle' : 'circle-check', 'icon-sm')}
              <div class="banner-body">${escapeHtml(state.settingsBanner.text)}</div>
            </div>`
          : ''
      }

      <div class="settings-grid">
        <section class="edit-card">
          <h3>${renderIcon('sliders', 'icon-sm')} ${escapeHtml(t(lang, 'setLangTitle'))}</h3>
          <p class="edit-description">${escapeHtml(t(lang, 'setLangDesc'))}</p>
          ${renderSegmented('language', cfg.language, [
            ['system', t(lang, 'setLangSystem')],
            ['english', t(lang, 'setLangEn')],
            ['german', t(lang, 'setLangDe')],
          ])}

          <div class="edit-divider"></div>

          <h3>${renderIcon('palette', 'icon-sm')} ${escapeHtml(t(lang, 'setThemeTitle'))}</h3>
          <p class="edit-description">${escapeHtml(t(lang, 'setThemeDesc'))}</p>
          ${renderSegmented('themeMode', cfg.themeMode, [
            ['system', t(lang, 'setThemeSystem')],
            ['light', t(lang, 'setThemeLight')],
            ['dark', t(lang, 'setThemeDark')],
          ])}

          <div class="edit-divider"></div>

          <h3>${escapeHtml(t(lang, 'setPaletteTitle'))}</h3>
          <p class="edit-description">${escapeHtml(t(lang, 'setPaletteDesc'))}</p>
          ${renderSegmented('themePalette', cfg.themePalette, [
            ['calm', 'Calm'],
            ['plum-umber', 'Plum Umber'],
          ])}
        </section>

        <section class="edit-card">
          <h3>${renderIcon('clock', 'icon-sm')} ${escapeHtml(t(lang, 'setTzTitle'))}</h3>
          <p class="edit-description">${escapeHtml(t(lang, 'setTzDesc'))}</p>
          ${renderSegmented('timeZoneMode', cfg.timeZoneMode, [
            ['automatic', t(lang, 'setTzAuto')],
            ['manual', t(lang, 'setTzManual')],
          ])}
          ${
            cfg.timeZoneMode === 'manual'
              ? `<label class="field mt-12">${escapeHtml(t(lang, 'setTzOffset'))}
                  <select data-set-field="manualTimeZoneOffsetMinutes">
                    ${SUPPORTED_UTC_OFFSETS.map(
                      (min) =>
                        `<option value="${min}" ${Number(cfg.manualTimeZoneOffsetMinutes) === min ? 'selected' : ''}>${formatUtcOffset(min)}</option>`,
                    ).join('')}
                  </select>
                </label>`
              : ''
          }

          <div class="edit-divider"></div>

          <h3>${renderIcon('zap', 'icon-sm')} ${escapeHtml(t(lang, 'setLeadTitle'))}</h3>
          <p class="edit-description">${escapeHtml(t(lang, 'setLeadDesc'))}</p>
          <label class="field">${escapeHtml(t(lang, 'setLeadLabel'))}
            <select data-set-field="dueLeadWindow">
              <option value="off" ${cfg.dueLeadWindow === 'off' ? 'selected' : ''}>${escapeHtml(t(lang, 'leadOff'))}</option>
              <option value="at_due" ${cfg.dueLeadWindow === 'at_due' ? 'selected' : ''}>${escapeHtml(t(lang, 'leadAtDue'))}</option>
              <option value="hours12" ${cfg.dueLeadWindow === 'hours12' ? 'selected' : ''}>${escapeHtml(t(lang, 'lead12h'))}</option>
              <option value="hours24" ${cfg.dueLeadWindow === 'hours24' ? 'selected' : ''}>${escapeHtml(t(lang, 'lead24h'))}</option>
              <option value="hours48" ${cfg.dueLeadWindow === 'hours48' ? 'selected' : ''}>${escapeHtml(t(lang, 'lead48h'))}</option>
              <option value="days7" ${cfg.dueLeadWindow === 'days7' ? 'selected' : ''}>${escapeHtml(t(lang, 'lead7d'))}</option>
            </select>
          </label>
        </section>

        <section class="edit-card">
          <h3>${renderIcon('locate', 'icon-sm')} ${escapeHtml(t(lang, 'setLocTitle'))}</h3>
          <p class="edit-description">${escapeHtml(t(lang, 'setLocDesc'))}</p>
          ${renderSegmented('locationEnabled', String(cfg.locationEnabled), [
            ['false', t(lang, 'setLocOff')],
            ['true', t(lang, 'setLocOn')],
          ])}

          <div class="edit-divider"></div>

          <h3>${renderIcon('bug', 'icon-sm')} ${escapeHtml(t(lang, 'setDiagTitle'))}</h3>
          <p class="edit-description">${escapeHtml(t(lang, 'setDiagDesc'))}</p>
          <label class="check-field">
            <input type="checkbox" data-set-bool="diagnosticsEnabled" ${cfg.diagnosticsEnabled ? 'checked' : ''}>
            <span>${escapeHtml(t(lang, 'setDiagEnable'))}</span>
          </label>
          ${
            cfg.diagnosticsEnabled
              ? `<div class="diag-details">
                  <div class="field-label-sm">${escapeHtml(t(lang, 'setDiagLevel'))}</div>
                  ${renderSegmented('logLevel', cfg.logLevel, [
                    ['debug', 'Debug'],
                    ['info', 'Info'],
                    ['warn', 'Warn'],
                    ['error', 'Error'],
                  ])}
                  <div class="field-label-sm mt-12">${escapeHtml(t(lang, 'setDiagStorage'))}</div>
                  ${renderSegmented('logStorageMode', cfg.logStorageMode, [
                    ['local', t(lang, 'storageLocal')],
                    ['webdav', t(lang, 'storageWebDav')],
                    ['both', t(lang, 'storageBoth')],
                  ])}
                  <div class="diag-file-row">
                    <span class="mono-sm">${escapeHtml(activeLogFile)}</span>
                    <button type="button" class="secondary compact" data-view="logs">
                      ${renderIcon('bug', 'icon-xs')}${escapeHtml(t(lang, 'setDiagOpenViewer'))}
                    </button>
                  </div>
                </div>`
              : ''
          }
        </section>

        <section class="edit-card">
          <h3>${renderIcon('layers', 'icon-sm')} ${escapeHtml(t(lang, 'setStorageModeTitle'))}</h3>
          <p class="edit-description">${escapeHtml(t(lang, 'setStorageModeDesc'))}</p>
          ${renderSegmented('storageMode', cfg.storageMode, [
            ['local', t(lang, 'storageLocal')],
            ['webdav', t(lang, 'storageWebDav')],
            ['both', t(lang, 'storageBoth')],
          ])}

          ${
            usesLocal
              ? `<div class="edit-divider"></div>
                <h3>${renderIcon('folder', 'icon-sm')} ${escapeHtml(t(lang, 'setLocalTitle'))}</h3>
                <p class="edit-description">${escapeHtml(t(lang, 'setLocalDesc'))}</p>
                <div class="resolved-box">
                  <span class="resolved-label">${escapeHtml(t(lang, 'setLocalResolved'))}</span>
                  <code class="mono-sm">${escapeHtml(resolvedLocal)}</code>
                </div>
                <div class="local-actions-grid">
                  <button type="button" class="secondary compact" data-open-modal="select-local">${renderIcon('file-text', 'icon-xs')}${escapeHtml(t(lang, 'actionSelect'))}</button>
                  <button type="button" class="secondary compact" data-move-local>${renderIcon('folder-input', 'icon-xs')}${escapeHtml(t(lang, 'actionMove'))}</button>
                  <button type="button" class="secondary compact" data-open-modal="rename-local">${renderIcon('pencil', 'icon-xs')}${escapeHtml(t(lang, 'actionRename'))}</button>
                  <button type="button" class="danger compact" data-open-wipe="local">${renderIcon('trash', 'icon-xs')}${escapeHtml(t(lang, 'actionDelete'))}</button>
                </div>
                <label class="check-field mt-12">
                  <input type="checkbox" data-set-bool="localWatchEnabled" ${cfg.localWatchEnabled ? 'checked' : ''}>
                  <span>${escapeHtml(t(lang, 'setLocalWatch'))}<small>${escapeHtml(t(lang, 'setLocalWatchDesc'))}</small></span>
                </label>`
              : ''
          }

          ${
            usesWebDav
              ? `<div class="edit-divider"></div>
                <h3>${renderIcon('cloud', 'icon-sm')} ${escapeHtml(t(lang, 'setWebDavTitle'))}</h3>
                <p class="edit-description">${escapeHtml(t(lang, 'setWebDavDesc'))}</p>
                <label class="field">${escapeHtml(t(lang, 'setWebDavUrl'))}
                  <input type="url" data-set-field="serverUrl" value="${escapeHtml(cfg.serverUrl)}" placeholder="https://cloud.example.com">
                </label>
                <div class="field-grid">
                  <label class="field">${escapeHtml(t(lang, 'setWebDavUser'))}
                    <input type="text" data-set-field="username" value="${escapeHtml(cfg.username)}" placeholder="example-user">
                  </label>
                  <label class="field">${escapeHtml(t(lang, 'setWebDavPass'))}
                    <div class="password-wrap">
                      <input type="${state.showPassword ? 'text' : 'password'}" data-set-field="password" value="${escapeHtml(cfg.password)}">
                      <button type="button" class="icon-button compact" data-toggle-password aria-label="Toggle password">
                        ${renderIcon(state.showPassword ? 'eye-off' : 'eye', 'icon-sm')}
                      </button>
                    </div>
                  </label>
                </div>
                <label class="field">${escapeHtml(t(lang, 'setWebDavPath'))}
                  <input type="text" data-set-field="filePath" value="${escapeHtml(cfg.filePath)}" placeholder="tasks.tdf">
                </label>
                ${
                  resolvedRemote
                    ? `<div class="resolved-box">
                        <span class="resolved-label">${escapeHtml(t(lang, 'setWebDavResolved'))}</span>
                        <code class="mono-sm">${escapeHtml(resolvedRemote)}</code>
                      </div>`
                    : ''
                }
                <div class="mt-12">
                  <button type="button" class="danger" data-open-wipe="remote">${renderIcon('trash', 'icon-sm')}${escapeHtml(t(lang, 'setWebDavWipe'))}</button>
                </div>`
              : ''
          }
        </section>
      </div>

      <div class="task-editor-actions">
        <span></span>
        <div>
          <button type="button" class="secondary" data-settings-save>${escapeHtml(t(lang, 'actionSave'))}</button>
          <button type="button" class="primary" data-settings-test-sync ${!usesWebDav ? 'disabled' : ''}>
            ${renderIcon('refresh-cw', 'icon-sm')}${escapeHtml(t(lang, 'setActionTestSync'))}
          </button>
        </div>
      </div>
    `;
  }

  function renderLogViewerView(state, workspace) {
    const lang = state.lang;
    const cfg = workspace.config;
    const allLines = state.logs;
    const levelOrder = { debug: 0, info: 1, warn: 2, error: 3, crash: 4 };
    const minOrd = levelOrder[state.logFilterLevel] ?? 0;
    const tagFilter = state.logFilterTag;

    let entryCount = 0;
    let warnCount = 0;
    let errCount = 0;
    for (const line of allLines) {
      if (line.startsWith('@meta ') || line.startsWith('===')) continue;
      entryCount += 1;
      if (line.includes('[WARN]')) warnCount += 1;
      if (line.includes('[ERROR]') || line.includes('[CRASH]')) errCount += 1;
    }

    const filtered = allLines.filter((line) => {
      if (line.startsWith('@meta ') || line.startsWith('===')) return true;
      const lvlMatch = line.match(/\[(DEBUG|INFO|WARN|ERROR|CRASH)\]/);
      const tagMatch = line.match(/\[(LIFECYCLE|TDF|DOMAIN|SYNC|STORAGE|UI)\]/);
      const ord = lvlMatch ? levelOrder[lvlMatch[1].toLowerCase()] ?? 1 : 1;
      if (ord < minOrd) return false;
      if (tagFilter && (!tagMatch || tagMatch[1] !== tagFilter)) return false;
      return true;
    });

    const canUploadLog =
      (cfg.logStorageMode === 'webdav' || cfg.logStorageMode === 'both') &&
      Boolean(resolveWebDavEndpoint(cfg));
    const logFileName = `tiertask_2026-11-21_linux_${workspace.id}.log`;

    return `
      <button type="button" class="back" data-view="tasks">${renderIcon('arrow-left', 'icon-sm')}${escapeHtml(t(lang, 'actionBackTasks'))}</button>
      <div class="heading">
        <div>
          <h2>${escapeHtml(t(lang, 'logViewerTitle'))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, 'logViewerSub'))}</div>
        </div>
        <div class="inline-btn-row">
          ${
            canUploadLog
              ? `<button type="button" class="secondary compact" data-log-sync>${renderIcon('cloud-upload', 'icon-xs')}${escapeHtml(t(lang, 'logSyncNow'))}</button>`
              : ''
          }
          <button type="button" class="secondary compact" data-log-copy>${renderIcon('copy', 'icon-xs')}${escapeHtml(t(lang, 'logCopyAll'))}</button>
          <button type="button" class="secondary compact" data-log-bottom>${renderIcon('arrow-down-to-line', 'icon-xs')}${escapeHtml(t(lang, 'logScrollBottom'))}</button>
          <button type="button" class="danger compact" data-log-clear>${renderIcon('trash', 'icon-xs')}${escapeHtml(t(lang, 'logClear'))}</button>
        </div>
      </div>

      ${window.TT2.viewsCore.renderNotice(state)}

      <div class="log-meta-card">
        <div class="mono-sm">${escapeHtml(logFileName)} · v0.4.0+a1b2c3d (linux) · ${escapeHtml(workspace.id)} · ${escapeHtml(cfg.logLevel.toUpperCase())}</div>
        <small>${escapeHtml(t(lang, 'logStats', { entries: entryCount, warnings: warnCount, errors: errCount }))}</small>
      </div>

      <div class="log-filter-bar">
        <label class="field-inline">
          <span>${escapeHtml(t(lang, 'logFilterLevel'))}</span>
          <select data-log-level>
            <option value="debug" ${state.logFilterLevel === 'debug' ? 'selected' : ''}>DEBUG</option>
            <option value="info" ${state.logFilterLevel === 'info' ? 'selected' : ''}>INFO</option>
            <option value="warn" ${state.logFilterLevel === 'warn' ? 'selected' : ''}>WARN</option>
            <option value="error" ${state.logFilterLevel === 'error' ? 'selected' : ''}>ERROR</option>
          </select>
        </label>
        <label class="field-inline">
          <span>${escapeHtml(t(lang, 'logFilterTag'))}</span>
          <select data-log-tag>
            <option value="" ${!tagFilter ? 'selected' : ''}>${escapeHtml(t(lang, 'logAllTags'))}</option>
            ${['LIFECYCLE', 'TDF', 'DOMAIN', 'SYNC', 'STORAGE', 'UI']
              .map(
                (tag) =>
                  `<option value="${tag}" ${tagFilter === tag ? 'selected' : ''}>${tag}</option>`,
              )
              .join('')}
          </select>
        </label>
      </div>

      <div class="log-console" data-log-console>
        ${
          filtered.length
            ? filtered
                .map((line) => {
                  let cls = 'log-line';
                  if (line.includes('[CRASH]')) cls += ' sev-crash';
                  else if (line.includes('[ERROR]')) cls += ' sev-error';
                  else if (line.includes('[WARN]')) cls += ' sev-warn';
                  else if (line.startsWith('@meta ')) cls += ' sev-meta';
                  return `<div class="${cls}">${escapeHtml(line)}</div>`;
                })
                .join('')
            : `<div class="empty">${escapeHtml(t(lang, 'logEmpty'))}</div>`
        }
      </div>
    `;
  }

  function renderRawTdfView(state, workspace) {
    const lang = state.lang;
    const serialized = serializeTdf080(workspace);
    const bytes = new TextEncoder().encode(serialized).length;
    const lineCount = serialized.split('\n').length;

    return `
      <button type="button" class="back" data-view="tasks">${renderIcon('arrow-left', 'icon-sm')}${escapeHtml(t(lang, 'actionBackTasks'))}</button>
      <div class="heading">
        <div>
          <h2>${escapeHtml(t(lang, 'rawTdfTitle'))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, 'rawTdfSub'))}</div>
        </div>
        <button type="button" class="primary compact" data-copy-raw-tdf>
          ${renderIcon('copy', 'icon-xs')}${escapeHtml(t(lang, 'actionCopy'))}
        </button>
      </div>
      ${window.TT2.viewsCore.renderNotice(state)}
      <div class="log-meta-card">
        <div class="mono-sm">${escapeHtml(t(lang, 'rawTdfStats', { bytes, lines: lineCount }))}</div>
      </div>
      <pre class="raw-tdf-code"><code>${escapeHtml(serialized)}</code></pre>
    `;
  }

  function renderConflictResolutionView(state) {
    const lang = state.lang;
    const items = state.conflictItems;
    return `
      <button type="button" class="back" data-view="tasks">${renderIcon('arrow-left', 'icon-sm')}${escapeHtml(t(lang, 'actionBackTasks'))}</button>
      <div class="heading">
        <div>
          <h2>${escapeHtml(t(lang, 'conflictTitle'))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, 'conflictSub'))}</div>
        </div>
      </div>

      <div class="conflict-list">
        ${items
          .map(
            (item) => `
          <section class="edit-card conflict-card">
            <div class="conflict-head">
              <span class="pill-badge tone-warning">${escapeHtml(item.entityType.toUpperCase())} · ${escapeHtml(item.id)}</span>
              <strong>${escapeHtml(item.title)}</strong>
            </div>
            <p class="edit-description">${escapeHtml(item.detail[lang] || item.detail.de)}</p>
            <div class="segmented" role="group">
              <button type="button" data-conflict-choice="${escapeHtml(item.id)}" data-choice="undelete" aria-pressed="${item.choice === 'undelete'}">
                ${escapeHtml(t(lang, 'conflictKeepEdit'))}
              </button>
              <button type="button" data-conflict-choice="${escapeHtml(item.id)}" data-choice="delete" aria-pressed="${item.choice === 'delete'}">
                ${escapeHtml(t(lang, 'conflictConfirmDelete'))}
              </button>
            </div>
          </section>`,
          )
          .join('')}
      </div>

      <div class="task-editor-actions">
        <span></span>
        <div>
          <button type="button" class="secondary" data-view="tasks">${escapeHtml(t(lang, 'actionCancel'))}</button>
          <button type="button" class="primary" data-apply-conflicts>${escapeHtml(t(lang, 'conflictApply'))}</button>
        </div>
      </div>
    `;
  }

  function renderRecoveryResolutionView(state) {
    const lang = state.lang;
    const items = state.recoveryItems;
    return `
      <button type="button" class="back" data-view="tasks">${renderIcon('arrow-left', 'icon-sm')}${escapeHtml(t(lang, 'actionBackTasks'))}</button>
      <div class="heading">
        <div>
          <h2>${escapeHtml(t(lang, 'recoveryTitle'))}</h2>
          <div class="subtitle">${escapeHtml(t(lang, 'recoverySub'))}</div>
        </div>
      </div>

      <div class="conflict-list">
        ${items
          .map(
            (item) => `
          <section class="edit-card conflict-card">
            <div class="conflict-head">
              <span class="pill-badge tone-warning">${escapeHtml(item.entityType.toUpperCase())} · ${escapeHtml(item.id)}</span>
              <strong>${escapeHtml(item.title)}</strong>
            </div>
            <p class="edit-description">${escapeHtml(item.detail[lang] || item.detail.de)}</p>
            <div class="segmented" role="group">
              <button type="button" data-recovery-choice="${escapeHtml(item.id)}" data-choice="recoverAsNew" aria-pressed="${item.choice === 'recoverAsNew'}">
                ${escapeHtml(t(lang, 'recoveryAsNew'))}
              </button>
              <button type="button" data-recovery-choice="${escapeHtml(item.id)}" data-choice="discard" aria-pressed="${item.choice === 'discard'}">
                ${escapeHtml(t(lang, 'recoveryDiscard'))}
              </button>
            </div>
          </section>`,
          )
          .join('')}
      </div>

      <div class="task-editor-actions">
        <span></span>
        <div>
          <button type="button" class="secondary" data-view="tasks">${escapeHtml(t(lang, 'actionCancel'))}</button>
          <button type="button" class="primary" data-apply-recovery>${escapeHtml(t(lang, 'recoveryApply'))}</button>
        </div>
      </div>
    `;
  }

  /* ==========================================================================
     Modal Dialogs
     ========================================================================== */

  function renderWorkspacesModal(state) {
    const lang = state.lang;
    const modal = state.modal;
    const draftName = modal.createName || '';
    const suggestedFile = suggestWorkspaceFileName(draftName);
    const canDelete = state.workspaces.length > 1;

    return `
      <div class="modal-card" role="dialog" aria-modal="true" aria-label="${escapeHtml(t(lang, 'workspacesTitle'))}">
        <div class="modal-header">
          <div class="modal-header-text">
            <h3>${escapeHtml(t(lang, 'workspacesTitle'))}</h3>
            <p class="modal-subtitle">${escapeHtml(t(lang, 'workspacesDesc'))}</p>
          </div>
          <button type="button" class="icon-button compact" data-close-modal aria-label="${escapeHtml(t(lang, 'actionClose'))}">
            ${renderIcon('x')}
          </button>
        </div>

        <div class="modal-body">
          <div class="ws-create-box">
            <div class="edit-add-row">
              <input type="text" data-ws-create-input value="${escapeHtml(draftName)}" placeholder="${escapeHtml(t(lang, 'workspaceCreatePlaceholder'))}" maxlength="128">
              <button type="button" class="primary compact" data-ws-create-submit ${!draftName.trim() ? 'disabled' : ''}>
                ${renderIcon('plus', 'icon-xs')}${escapeHtml(t(lang, 'actionAdd'))}
              </button>
            </div>
            ${
              draftName.trim()
                ? `<div class="mono-sm mt-8" data-ws-suggested>${escapeHtml(t(lang, 'workspaceSuggestedFile', { file: suggestedFile }))}</div>`
                : ''
            }
          </div>

          ${modal.error ? `<div class="status-banner tone-danger">${escapeHtml(modal.error)}</div>` : ''}

          <div class="ws-list">
            ${state.workspaces
              .map((ws) => {
                const isActive = ws.id === state.activeWorkspaceId;
                const isRenaming = modal.renamingId === ws.id;
                const isConfirmDelete = modal.deletingId === ws.id;
                const usesWebDav =
                  ws.config.storageMode === 'webdav' ||
                  ws.config.storageMode === 'both';
                const fileName =
                  ws.config.storageMode === 'webdav'
                    ? ws.config.filePath
                    : ws.config.localFilePath;

                return `
                  <div class="ws-row-card ${isActive ? 'is-active' : ''}">
                    ${
                      isRenaming
                        ? `<div class="ws-rename-row">
                            <input type="text" data-ws-rename-input value="${escapeHtml(modal.renameDraft || ws.name)}" maxlength="128">
                            <button type="button" class="secondary compact" data-ws-rename-cancel>${escapeHtml(t(lang, 'actionCancel'))}</button>
                            <button type="button" class="primary compact" data-ws-rename-save="${escapeHtml(ws.id)}">${escapeHtml(t(lang, 'actionSave'))}</button>
                          </div>`
                        : `<div class="ws-row-main">
                            <button type="button" class="ws-select-area" data-ws-select="${escapeHtml(ws.id)}">
                              <span class="ws-badge-icon">${renderIcon(isActive ? 'circle-check' : 'workspaces', 'icon-sm')}</span>
                              <span class="ws-card-meta">
                                <strong>${escapeHtml(ws.name)}</strong>
                                <small>${renderIcon(usesWebDav ? 'cloud' : 'folder', 'icon-xs')} ${escapeHtml(fileName)}</small>
                              </span>
                              ${isActive ? `<span class="pill-badge tone-accent">${escapeHtml(t(lang, 'workspaceActiveBadge'))}</span>` : ''}
                            </button>
                            <div class="record-actions">
                              <button type="button" class="icon-button compact" data-ws-start-rename="${escapeHtml(ws.id)}" title="${escapeHtml(t(lang, 'actionRename'))}">${renderIcon('pencil', 'icon-xs')}</button>
                              <button type="button" class="icon-button compact is-danger-hover" data-ws-ask-delete="${escapeHtml(ws.id)}" ${!canDelete ? 'disabled' : ''} title="${escapeHtml(t(lang, 'actionDelete'))}">${renderIcon('trash', 'icon-xs')}</button>
                            </div>
                          </div>`
                    }
                    ${
                      isConfirmDelete
                        ? `<div class="inline-confirm-bar">
                            <span>${escapeHtml(t(lang, 'workspaceDeleteConfirm', { name: ws.name }))}</span>
                            <div class="inline-confirm-actions">
                              <button type="button" class="secondary compact" data-ws-cancel-delete>${escapeHtml(t(lang, 'actionCancel'))}</button>
                              <button type="button" class="danger compact" data-ws-confirm-delete="${escapeHtml(ws.id)}">${escapeHtml(t(lang, 'actionDelete'))}</button>
                            </div>
                          </div>`
                        : ''
                    }
                  </div>
                `;
              })
              .join('')}
          </div>
        </div>
      </div>
    `;
  }

  function renderLocationStatusModal(state) {
    const lang = state.lang;
    const searching = state.locationSearching;
    const fix = state.locationFix;
    const statusText = searching
      ? t(lang, 'locationStatusSearching')
      : fix.status === 'found'
        ? t(lang, 'locationStatusFound')
        : t(lang, 'locationStatusUnavailable');
    const sourceText =
      fix.source === 'gps'
        ? t(lang, 'locationSourceGps')
        : fix.source === 'system'
          ? t(lang, 'locationSourceSystem')
          : t(lang, 'locationSourceInternet');

    return `
      <div class="modal-card modal-sm" role="dialog" aria-modal="true" aria-label="${escapeHtml(t(lang, 'locationDialogTitle'))}">
        <div class="modal-header">
          <h3>${escapeHtml(t(lang, 'locationDialogTitle'))}</h3>
          <button type="button" class="icon-button compact" data-close-modal aria-label="${escapeHtml(t(lang, 'actionClose'))}">
            ${renderIcon('x')}
          </button>
        </div>

        <div class="modal-body">
          <div class="loc-status-row">
            <span class="${searching ? 'is-spinning' : fix.status === 'found' ? 'is-accent' : ''}">${renderIcon(searching ? 'refresh-cw' : fix.status === 'found' ? 'locate' : 'locate-off')}</span>
            <strong>${escapeHtml(statusText)}</strong>
          </div>

          ${
            !searching && fix.status === 'found'
              ? `<div class="resolved-box">
                  <span class="resolved-label">${escapeHtml(t(lang, 'locationPlaceLabel'))}</span>
                  <strong>${escapeHtml(fix.placeName)}</strong>
                </div>
                <div class="resolved-box">
                  <span class="resolved-label">${escapeHtml(t(lang, 'locationCoordsLabel'))}</span>
                  <code class="mono-sm">${Number(fix.latitude).toFixed(6)}, ${Number(fix.longitude).toFixed(6)}</code>
                </div>
                <div class="resolved-box">
                  <span class="resolved-label">${escapeHtml(t(lang, 'locationSourceLabel'))}</span>
                  <span>${escapeHtml(sourceText)}</span>
                </div>`
              : ''
          }

          <div class="edit-divider"></div>
          <label class="field">${escapeHtml(t(lang, 'locationSimLabel'))}
            <select data-sim-location>
              <option value="office" ${state.simLocationKey === 'office' ? 'selected' : ''}>${escapeHtml(t(lang, 'locationSimOffice'))}</option>
              <option value="home" ${state.simLocationKey === 'home' ? 'selected' : ''}>${escapeHtml(t(lang, 'locationSimHome'))}</option>
              <option value="away" ${state.simLocationKey === 'away' ? 'selected' : ''}>${escapeHtml(t(lang, 'locationSimAway'))}</option>
              <option value="unavailable" ${state.simLocationKey === 'unavailable' ? 'selected' : ''}>${escapeHtml(t(lang, 'locationSimUnavailable'))}</option>
            </select>
          </label>
        </div>

        <div class="modal-footer">
          <button type="button" class="secondary" data-refresh-location ${searching ? 'disabled' : ''}>
            ${renderIcon('refresh-cw', 'icon-xs')}${escapeHtml(t(lang, 'actionRefresh'))}
          </button>
          <button type="button" class="primary" data-close-modal>${escapeHtml(t(lang, 'actionClose'))}</button>
        </div>
      </div>
    `;
  }

  function renderSelectLocalFileModal(state, workspace) {
    const lang = state.lang;
    const modal = state.modal;
    const files = workspace.localFiles || ['tasks.tdf'];
    const current = modal.fileInput ?? workspace.config.localFilePath;
    const valid =
      Boolean(current.trim()) &&
      !current.includes('/') &&
      !current.includes('\\') &&
      !current.includes('..');

    return `
      <div class="modal-card modal-sm" role="dialog" aria-modal="true" aria-label="${escapeHtml(t(lang, 'selectLocalTitle'))}">
        <div class="modal-header">
          <div class="modal-header-text">
            <h3>${escapeHtml(t(lang, 'selectLocalTitle'))}</h3>
            <p class="modal-subtitle">${escapeHtml(t(lang, 'selectLocalDesc'))}</p>
          </div>
          <button type="button" class="icon-button compact" data-close-modal>${renderIcon('x')}</button>
        </div>
        <div class="modal-body">
          <div class="file-list-box">
            ${files
              .map(
                (file) => `
              <button type="button" class="file-list-row ${file === current ? 'is-selected' : ''}" data-pick-local-file="${escapeHtml(file)}">
                ${renderIcon('file-text', 'icon-sm')}
                <span class="mono-sm">${escapeHtml(file)}</span>
              </button>`,
              )
              .join('')}
          </div>
          <label class="field mt-12">${escapeHtml(t(lang, 'localFileInputLabel'))}
            <input type="text" data-local-file-input value="${escapeHtml(current)}">
          </label>
          ${!valid && current ? `<div class="edit-error">${escapeHtml(t(lang, 'errInvalidFileName'))}</div>` : ''}
        </div>
        <div class="modal-footer">
          <button type="button" class="secondary" data-close-modal>${escapeHtml(t(lang, 'actionCancel'))}</button>
          <button type="button" class="primary" data-confirm-select-local ${!valid ? 'disabled' : ''}>${escapeHtml(t(lang, 'actionSelect'))}</button>
        </div>
      </div>
    `;
  }

  function renderRenameLocalFileModal(state, workspace) {
    const lang = state.lang;
    const modal = state.modal;
    const currentFile = workspace.config.localFilePath;
    const input = modal.fileInput ?? currentFile.replace(/\.tdf$/i, '');
    const valid =
      Boolean(input.trim()) &&
      !input.includes('/') &&
      !input.includes('\\') &&
      !input.includes('..');

    return `
      <div class="modal-card modal-sm" role="dialog" aria-modal="true" aria-label="${escapeHtml(t(lang, 'renameLocalTitle'))}">
        <div class="modal-header">
          <div class="modal-header-text">
            <h3>${escapeHtml(t(lang, 'renameLocalTitle'))}</h3>
            <p class="modal-subtitle">${escapeHtml(t(lang, 'renameLocalDesc', { file: currentFile }))}</p>
          </div>
          <button type="button" class="icon-button compact" data-close-modal>${renderIcon('x')}</button>
        </div>
        <div class="modal-body">
          <label class="field">${escapeHtml(t(lang, 'localFileInputLabel'))}
            <input type="text" data-local-file-input value="${escapeHtml(input)}">
          </label>
          ${!valid && input ? `<div class="edit-error">${escapeHtml(t(lang, 'errInvalidFileName'))}</div>` : ''}
        </div>
        <div class="modal-footer">
          <button type="button" class="secondary" data-close-modal>${escapeHtml(t(lang, 'actionCancel'))}</button>
          <button type="button" class="primary" data-confirm-rename-local ${!valid ? 'disabled' : ''}>${escapeHtml(t(lang, 'actionRename'))}</button>
        </div>
      </div>
    `;
  }

  function renderWipeTdfModal(state, workspace) {
    const lang = state.lang;
    const modal = state.modal;
    const isRemote = modal.target === 'remote';
    const rawPath = isRemote
      ? workspace.config.filePath
      : workspace.config.localFilePath;
    const fileName = rawPath.split('/').pop() || 'tasks.tdf';
    const expectedBase = fileName.replace(/\.tdf$/i, '');
    const typed = modal.confirmInput || '';
    const matches = typed.trim() === expectedBase;

    return `
      <div class="modal-card modal-sm" role="dialog" aria-modal="true" aria-label="${escapeHtml(t(lang, isRemote ? 'wipeRemoteTitle' : 'wipeLocalTitle'))}">
        <div class="modal-header">
          <div class="modal-header-text">
            <h3>${escapeHtml(t(lang, isRemote ? 'wipeRemoteTitle' : 'wipeLocalTitle'))}</h3>
            <p class="modal-subtitle">${escapeHtml(t(lang, isRemote ? 'wipeRemoteDesc' : 'wipeLocalDesc', { file: fileName, base: expectedBase }))}</p>
          </div>
          <button type="button" class="icon-button compact" data-close-modal>${renderIcon('x')}</button>
        </div>
        <div class="modal-body">
          <label class="field">${escapeHtml(t(lang, 'wipeConfirmLabel'))}
            <input type="text" data-wipe-confirm-input value="${escapeHtml(typed)}" placeholder="${escapeHtml(expectedBase)}">
          </label>
          <label class="check-field">
            <input type="checkbox" data-wipe-backup ${modal.createBackup ? 'checked' : ''}>
            <span>${escapeHtml(t(lang, 'wipeBackupLabel'))}</span>
          </label>
        </div>
        <div class="modal-footer">
          <button type="button" class="secondary" data-close-modal>${escapeHtml(t(lang, 'actionCancel'))}</button>
          <button type="button" class="danger" data-confirm-wipe ${!matches ? 'disabled' : ''}>${escapeHtml(t(lang, 'wipeConfirmButton'))}</button>
        </div>
      </div>
    `;
  }

  function renderColorPickerModal(state) {
    const lang = state.lang;
    const modal = state.modal;
    return `
      <div class="modal-card modal-sm" role="dialog" aria-modal="true" aria-label="${escapeHtml(t(lang, 'colorPickerTitle'))}">
        <div class="modal-header">
          <h3>${escapeHtml(t(lang, 'colorPickerTitle'))}</h3>
          <button type="button" class="icon-button compact" data-close-modal>${renderIcon('x')}</button>
        </div>
        <div class="modal-body color-wheel-body">
          <div class="color-preview-bar">
            <span class="color-swatch-preview" data-wheel-swatch style="background:${escapeHtml(modal.hex)}"></span>
            <code class="mono-lg" data-wheel-hex>${escapeHtml(modal.hex)}</code>
          </div>
          <canvas class="hsv-wheel-canvas" width="210" height="210" data-hsv-wheel></canvas>
          <label class="field">
            <span>${escapeHtml(t(lang, 'colorPickerBrightness'))}</span>
            <input type="range" min="0" max="100" value="${Math.round((modal.v ?? 0.95) * 100)}" data-hsv-value>
          </label>
        </div>
        <div class="modal-footer">
          <button type="button" class="secondary" data-close-modal>${escapeHtml(t(lang, 'actionCancel'))}</button>
          <button type="button" class="primary" data-confirm-color-picker>${escapeHtml(t(lang, 'colorPickerConfirm'))}</button>
        </div>
      </div>
    `;
  }

  function renderGeocodingCandidatesModal(state) {
    const lang = state.lang;
    const candidates = state.modal.candidates || [];
    return `
      <div class="modal-card modal-sm" role="dialog" aria-modal="true" aria-label="${escapeHtml(t(lang, 'candidateDialogTitle'))}">
        <div class="modal-header">
          <div class="modal-header-text">
            <h3>${escapeHtml(t(lang, 'candidateDialogTitle'))}</h3>
            <p class="modal-subtitle">${escapeHtml(t(lang, 'candidateDialogSub'))}</p>
          </div>
          <button type="button" class="icon-button compact" data-close-modal>${renderIcon('x')}</button>
        </div>
        <div class="modal-body">
          <div class="file-list-box">
            ${candidates
              .map(
                (cand, idx) => `
              <button type="button" class="candidate-row" data-pick-candidate="${idx}">
                ${renderIcon('map-pin', 'icon-sm')}
                <span>
                  <strong>${escapeHtml(cand.displayName)}</strong>
                  <small class="mono-sm">${Number(cand.latitude).toFixed(6)}, ${Number(cand.longitude).toFixed(6)}</small>
                </span>
              </button>`,
              )
              .join('')}
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="secondary" data-close-modal>${escapeHtml(t(lang, 'actionCancel'))}</button>
        </div>
      </div>
    `;
  }

  function renderActiveModal(state, workspace) {
    if (!state.modal) return '';
    let inner = '';
    switch (state.modal.type) {
      case 'workspaces':
        inner = renderWorkspacesModal(state);
        break;
      case 'location-status':
        inner = renderLocationStatusModal(state);
        break;
      case 'select-local':
        inner = renderSelectLocalFileModal(state, workspace);
        break;
      case 'rename-local':
        inner = renderRenameLocalFileModal(state, workspace);
        break;
      case 'wipe-tdf':
        inner = renderWipeTdfModal(state, workspace);
        break;
      case 'color-picker':
        inner = renderColorPickerModal(state);
        break;
      case 'geo-candidates':
        inner = renderGeocodingCandidatesModal(state);
        break;
      default:
        return '';
    }
    if (!inner) return '';
    return `
      <div class="modal-backdrop" data-modal-backdrop>
        ${inner}
      </div>
    `;
  }

  window.TT2.viewsSecondary = {
    renderSettingsView,
    renderLogViewerView,
    renderRawTdfView,
    renderConflictResolutionView,
    renderRecoveryResolutionView,
    renderActiveModal,
  };
})();
