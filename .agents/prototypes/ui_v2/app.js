(() => {
  const root = document.getElementById('tt2');
  const app = root.querySelector('.app');

  const escapeHtml = (value) =>
    String(value ?? '').replace(
      /[&<>"']/g,
      (character) =>
        ({
          '&': '&amp;',
          '<': '&lt;',
          '>': '&gt;',
          '"': '&quot;',
          "'": '&#39;',
        })[character],
    );

  // Offline inline SVG icon registry (zero external CDN dependencies).
  const iconPaths = {
    'arrow-left': '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>',
    'calendar-days':
      '<path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',
    'circle-check':
      '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
    'circle-slash':
      '<circle cx="12" cy="12" r="10"/><line x1="9" x2="15" y1="15" y2="9"/>',
    'cloud-check':
      '<path d="m17 15-5.5 5.5L9 18"/><path d="M5 17.743A7 7 0 1 1 15.71 10h1.79a4.5 4.5 0 0 1 1.5 8.742"/>',
    layers:
      '<path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>',
    lightbulb:
      '<path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"/><path d="M9 18h6"/><path d="M10 22h4"/>',
    'list-ordered':
      '<path d="M10 12h11"/><path d="M10 18h11"/><path d="M10 6h11"/><path d="M4 10h2"/><path d="M4 6h1v4"/><path d="M6 18H4c0-1 2-2 2-3s-1-1.5-2-1"/>',
    'map-pin':
      '<path d="M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/>',
    pencil:
      '<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/><path d="m15 5 4 4"/>',
    plus: '<path d="M5 12h14"/><path d="M12 5v14"/>',
    tags: '<path d="m15 5 6.3 6.3a2.4 2.4 0 0 1 0 3.4L17 19"/><path d="M9.586 5.586A2 2 0 0 0 8.172 5H3a1 1 0 0 0-1 1v5.172a2 2 0 0 0 .586 1.414L8.29 18.29a2.426 2.426 0 0 0 3.42 0l3.58-3.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="6.5" cy="9.5" r=".5" fill="currentColor"/>',
    zap: '<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/>',
  };

  const renderIcon = (name) =>
    `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${iconPaths[name] ?? ''}</svg>`;

  const tiers = [
    'Fokus',
    'Bereit',
    'Geplant',
    'Blockiert',
    'Irgendwann',
    'Erledigt',
  ];
  const tierIcons = [
    'zap',
    'list-ordered',
    'calendar-days',
    'circle-slash',
    'lightbulb',
    'circle-check',
  ];

  const labels = [
    {
      id: 1,
      name: 'Projekt AWO 3cx',
      color: '#2196f3',
      scoped: true,
      note: 'Abstimmung und Einführung von 3CX.',
      link: 'Projektunterlagen',
      url: '',
      condition: '',
    },
    {
      id: 2,
      name: 'Kunde GEW Sachsen',
      color: '#cc3f90',
      scoped: false,
      note: '',
      link: '',
      url: '',
      condition: '',
    },
    {
      id: 3,
      name: 'Privat',
      color: '#54927f',
      scoped: false,
      note: '',
      link: '',
      url: '',
      condition: '',
    },
  ];

  const locations = [
    {
      id: 1,
      name: 'Büro',
      source: 'GPS',
      lat: '51.05',
      lon: '13.74',
      radius: '150',
      note: 'Beispielort',
      address: '',
    },
    {
      id: 2,
      name: 'Zuhause',
      source: 'GPS',
      lat: '51.04',
      lon: '13.73',
      radius: '100',
      note: 'Beispielort',
      address: '',
    },
  ];

  const tasks = [
    {
      id: 1,
      title: 'AWO Projekt Kontakt',
      labels: [1],
      meta: 'Fällig: 10.11.2026 · überfällig',
      steps: [],
      priority: true,
    },
    {
      id: 2,
      title: '3CX AWO: Bereichsleitung informieren und Jens ankündigen',
      labels: [1],
      meta: '1 / 2 Schritte',
      steps: [
        { text: 'Information vorbereiten', done: true },
        { text: 'Termin abstimmen', done: false },
      ],
    },
    {
      id: 3,
      title: '3CX AWO: MIT-Testaufbau mit Jan Müller durchführen',
      labels: [1],
      meta: '2 Schritte',
      steps: [
        { text: 'Testaufbau vorbereiten', done: false },
        { text: 'Ergebnis dokumentieren', done: false },
      ],
    },
    { id: 4, title: 'Dokumentation für die Übergabe vorbereiten', labels: [1], meta: '', steps: [] },
    { id: 5, title: 'Telefonvorlagen prüfen', labels: [1], meta: '', steps: [] },
    { id: 6, title: 'Rückfragen zur Einrichtung sammeln', labels: [1], meta: '', steps: [] },
    { id: 7, title: 'Abschlussgespräch vorbereiten', labels: [1], meta: '', steps: [] },
    { id: 8, title: 'Rollout-Checkliste prüfen', labels: [1], meta: '', steps: [] },
    { id: 9, title: 'Dokumentation archivieren', labels: [1], meta: '', steps: [] },
    { id: 10, title: 'Rückmeldung vom Kunden abwarten', labels: [1], meta: 'Wartet auf Freigabe', blocked: true, steps: [] },
    { id: 11, title: 'Schulungsunterlagen überarbeiten', labels: [1], meta: '', someday: true, steps: [] },
    { id: 12, title: 'Unterlagen für GEW prüfen', labels: [2], meta: '', steps: [] },
    { id: 13, title: 'Arbeitszimmer aufräumen', labels: [3], meta: '', steps: [] },
  ];

  const state = {
    view: 'tasks',
    tier: 0,
    label: 1,
    drawer: false,
    expanded: null,
    edit: null,
    taskEdit: null,
    editorTab: 'overview',
    deleteConfirm: false,
    editorError: '',
    message: '',
    undo: null,
    draft: { title: '', mode: 'queue', labels: [1], note: '', location: '' },
  };

  function matchesContext(task) {
    if (state.label) {
      return task.labels.includes(state.label);
    }
    return !task.labels.some(
      (id) => labels.find((label) => label.id === id)?.scoped,
    );
  }

  function tasksInTier(tierIndex) {
    const visible = tasks.filter(matchesContext);
    const active = visible.filter(
      (task) => !task.done && !task.someday && !task.blocked,
    );
    if (tierIndex === 0) return active.slice(0, 3);
    if (tierIndex === 1) return active.slice(3, 8);
    if (tierIndex === 2) return active.slice(8);
    if (tierIndex === 3) return visible.filter((task) => !task.done && task.blocked);
    if (tierIndex === 4) return visible.filter((task) => !task.done && task.someday);
    return visible.filter((task) => task.done);
  }

  function renderSelectOptions(items, selectedValue, placeholderLabel) {
    const firstOption = placeholderLabel
      ? `<option value="">${placeholderLabel}</option>`
      : '';
    return (
      firstOption +
      items
        .map(
          (item) =>
            `<option value="${item.id}" ${
              String(selectedValue) === String(item.id) ? 'selected' : ''
            }>${escapeHtml(item.name)}</option>`,
        )
        .join('')
    );
  }

  function renderSidebar() {
    return `
      <section>
        <div class="section-head"><span class="eyebrow">Aufgaben</span></div>
        ${tiers
          .map(
            (tier, index) => `
          <button class="nav-row" type="button" data-tier="${index}" ${
            state.view === 'tasks' && state.tier === index
              ? 'aria-current="page"'
              : ''
          }>
            ${renderIcon(tierIcons[index])}
            <span>${tier}</span>
            <span class="count">${tasksInTier(index).length}</span>
          </button>`,
          )
          .join('')}
      </section>

      <section>
        <div class="section-head">
          <span class="eyebrow">Labels</span>
          <button class="text-button" type="button" data-view="labels">Verwalten</button>
        </div>
        <button type="button" class="nav-row" data-label="0" ${
          state.view === 'tasks' && !state.label ? 'aria-current="page"' : ''
        }>
          ${renderIcon('layers')}
          <span class="nav-label-name">Alle Aufgaben</span>
        </button>
        ${labels
          .map(
            (label) => `
          <button class="nav-row" type="button" data-label="${label.id}" ${
            state.view === 'tasks' && state.label === label.id
              ? 'aria-current="page"'
              : ''
          }>
            <span class="dot" style="--label-color:${escapeHtml(label.color)}"></span>
            <span class="nav-label-name">
              ${escapeHtml(label.name)}
              ${label.scoped ? '<span class="label-mode">Eigene Warteschlange</span>' : ''}
            </span>
            <span class="count">${
              tasks.filter((task) => !task.done && task.labels.includes(label.id))
                .length
            }</span>
          </button>`,
          )
          .join('')}
      </section>

      <section>
        <div class="section-head">
          <span class="eyebrow">Orte</span>
          <button class="text-button" type="button" data-view="locations">Verwalten</button>
        </div>
        ${locations
          .map(
            (location) => `
          <button type="button" class="nav-row" data-edit-location="${location.id}">
            ${renderIcon('map-pin')}
            <span class="nav-label-name">${escapeHtml(location.name)}</span>
          </button>`,
          )
          .join('')}
      </section>

      <div class="sidebar-footer">
        Workspace: Work<br>
        Labels und Orte gelten für diesen Workspace.
      </div>
    `;
  }

  function renderNotice() {
    return `<div class="notice" aria-live="polite">${escapeHtml(state.message)}${
      state.undo
        ? '<button type="button" class="text-button" data-undo>Rückgängig</button>'
        : ''
    }</div>`;
  }

  function renderTaskCard(task) {
    const isExpanded = state.expanded === task.id;
    return `
      <article class="task">
        <div class="task-top">
          <button type="button" class="complete" data-complete="${task.id}" aria-label="${escapeHtml(task.title)} ${task.done ? 'wiederherstellen' : 'abschließen'}">
            <span class="circle">${task.done ? '✓' : ''}</span>
          </button>
          <button type="button" class="task-title" data-detail="${task.id}" aria-expanded="${isExpanded}">
            ${escapeHtml(task.title)}
          </button>
          <button type="button" class="task-edit-button" data-edit-task="${task.id}" aria-label="${escapeHtml(task.title)} bearbeiten">
            Bearbeiten
          </button>
        </div>
        <div class="metadata">
          ${task.labels
            .map(
              (id) =>
                `<span class="tag">${escapeHtml(labels.find((label) => label.id === id)?.name)}</span>`,
            )
            .join('')}
          ${task.priority ? '<span>Priorität</span>' : ''}
          ${task.meta ? `<span>${escapeHtml(task.meta)}</span>` : ''}
        </div>
        ${
          isExpanded
            ? `
          <div class="task-detail">
            ${task.note ? `<p>${escapeHtml(task.note)}</p>` : ''}
            ${
              task.steps.length
                ? task.steps
                    .map(
                      (step, stepIndex) => `
                <label>
                  <input type="checkbox" data-step="${stepIndex}" data-task="${task.id}" ${step.done ? 'checked' : ''}>
                  ${escapeHtml(step.text)}
                </label>`,
                    )
                    .join('')
                : 'Keine Teilschritte.'
            }
            ${
              task.location
                ? `<div class="subtitle">Bedingung: am Ort ${escapeHtml(locations.find((location) => location.id === task.location)?.name)}</div>`
                : ''
            }
          </div>`
            : ''
        }
      </article>
    `;
  }

  function modeHint() {
    if (state.draft.mode === 'priority') {
      return 'Priorisiert in die aktive Warteschlange einordnen.';
    }
    if (state.draft.mode === 'someday') {
      return 'Außerhalb der aktiven Warteschlange sammeln.';
    }
    return 'Am Ende der Warteschlange einordnen.';
  }

  function renderQuickComposer() {
    const draft = state.draft;
    return `
      <div class="composer">
        <form data-form="task">
          <div class="entry-row">
            <input name="title" data-draft="title" value="${escapeHtml(draft.title)}" aria-label="Neue Aufgabe" placeholder="Neue Aufgabe …" autocomplete="off" required>
            <div class="entry-options">
              <select name="mode" data-draft="mode" aria-label="Einordnung">
                <option value="queue" ${draft.mode === 'queue' ? 'selected' : ''}>Warteschlange</option>
                <option value="priority" ${draft.mode === 'priority' ? 'selected' : ''}>Priorität</option>
                <option value="someday" ${draft.mode === 'someday' ? 'selected' : ''}>Irgendwann</option>
              </select>
              <button type="button" data-save class="primary">
                ${renderIcon('plus')}<span>Hinzufügen</span>
              </button>
            </div>
          </div>

          <details class="label-picker">
            <summary>${renderIcon('tags')}<span data-label-summary>Labels · ${draft.labels.length} ausgewählt</span></summary>
            <div class="label-checks">
              ${labels
                .map(
                  (label) => `
                <label>
                  <input type="checkbox" data-draft-label="${label.id}" ${draft.labels.includes(label.id) ? 'checked' : ''}>
                  ${escapeHtml(label.name)}
                </label>`,
                )
                .join('')}
            </div>
          </details>

          <details class="draft-extra">
            <summary>Weitere Angaben</summary>
            <div>
              <label class="field">Notiz<textarea data-draft="note">${escapeHtml(draft.note)}</textarea></label>
              <label class="field">Bedingung · Ort<select data-draft="location">${renderSelectOptions(locations, draft.location, 'Kein Ort')}</select></label>
              <button type="button" class="full-editor-button" data-full-editor>Vollständigen Aufgaben-Editor öffnen</button>
            </div>
          </details>
        </form>
        <div class="composer-hint" data-mode-hint>${modeHint()}</div>
      </div>
    `;
  }

  function renderTaskView() {
    const currentLabel = labels.find((label) => label.id === state.label);
    const queue = tasksInTier(state.tier);
    const subtitle =
      state.tier === 0
        ? 'Drei Aufgaben. Ein klarer nächster Schritt.'
        : state.tier === 1
          ? 'Diese Aufgaben rücken als Nächstes nach.'
          : 'Aufgaben in diesem Tier.';
    const limitSuffix =
      state.tier === 0 ? ' / 3' : state.tier === 1 ? ' / 5' : '';

    return `
      <div class="context-bar">
        <span>Kontext</span>
        <select aria-label="Label-Kontext" data-context>
          <option value="0" ${!state.label ? 'selected' : ''}>Alle Aufgaben</option>
          ${renderSelectOptions(labels, state.label)}
        </select>
        ${
          currentLabel
            ? `<button type="button" class="icon-button" data-edit-label="${currentLabel.id}" aria-label="Label-Details und Einstellungen"><span>Details</span></button>`
            : ''
        }
      </div>

      <label class="tier-mobile">
        Ansicht
        <select data-tier-select>
          ${tiers
            .map(
              (tier, index) =>
                `<option value="${index}" ${state.tier === index ? 'selected' : ''}>${tier} · ${tasksInTier(index).length}</option>`,
            )
            .join('')}
        </select>
      </label>

      <div class="heading">
        <div>
          <h2>${tiers[state.tier]}</h2>
          <div class="subtitle">${subtitle}</div>
        </div>
        <span class="limit">${queue.length}${limitSuffix}</span>
      </div>

      <div class="tasks">
        ${
          queue.length
            ? queue.map(renderTaskCard).join('')
            : '<div class="empty">Keine Aufgaben in dieser Ansicht.</div>'
        }
      </div>

      ${renderNotice()}
      ${renderQuickComposer()}
    `;
  }

  function renderManagerView(kind) {
    const isLabels = kind === 'labels';
    const items = isLabels ? labels : locations;
    return `
      <button type="button" class="back" data-view="tasks">${renderIcon('arrow-left')}Zurück zum Fokus</button>
      <div class="heading">
        <div>
          <h2>${isLabels ? 'Labels' : 'Orte'}</h2>
          <div class="subtitle">${
            isLabels
              ? 'Kontexte, eigene Warteschlangen und gemeinsame Bedingungen.'
              : 'Orte für Bedingungen an Aufgaben und Labels.'
          }</div>
        </div>
        <button type="button" class="primary" data-new="${kind}">${renderIcon('plus')}Neu</button>
      </div>
      ${renderNotice()}
      <div class="manager-list">
        ${items
          .map(
            (item) => `
          <button type="button" class="manager-row" data-edit-${isLabels ? 'label' : 'location'}="${item.id}">
            ${
              isLabels
                ? `<span class="dot" style="--label-color:${escapeHtml(item.color)}"></span>`
                : renderIcon('map-pin')
            }
            <span>
              <strong>${escapeHtml(item.name)}</strong>
              <small>${
                isLabels
                  ? item.scoped
                    ? 'Eigene Warteschlange'
                    : 'Globaler Kontext'
                  : `${escapeHtml(item.source)} · Radius ${escapeHtml(item.radius)} m`
              }</small>
            </span>
            ${renderIcon('pencil')}
          </button>`,
          )
          .join('')}
      </div>
    `;
  }

  function renderLabelEditor() {
    const item = state.edit;
    return `
      <button type="button" class="back" data-view="labels">${renderIcon('arrow-left')}Alle Labels</button>
      <div class="heading">
        <div>
          <h2>${item.id ? 'Label bearbeiten' : 'Neues Label'}</h2>
          <div class="subtitle">Einstellungen für diesen Kontext.</div>
        </div>
      </div>
      <form class="editor" data-form="label">
        <label class="field">Name<input name="name" value="${escapeHtml(item.name)}" required maxlength="120"></label>
        <label class="field">Farbe<input type="color" name="color" value="${escapeHtml(item.color)}"></label>
        <label class="check-field">
          <input type="checkbox" name="scoped" ${item.scoped ? 'checked' : ''}>
          <span>Eigene Warteschlange<small>Aufgaben sind im eigenen Label-Kontext sichtbar und werden dort eingeordnet.</small></span>
        </label>
        <label class="field">Notizen<textarea name="note">${escapeHtml(item.note)}</textarea></label>
        <details class="editor-section">
          <summary>Links</summary>
          <label class="field">Titel<input name="link" value="${escapeHtml(item.link)}" placeholder="Projektunterlagen"></label>
          <label class="field">URL<input type="url" name="url" value="${escapeHtml(item.url)}" placeholder="https://…"></label>
        </details>
        <details class="editor-section">
          <summary>Bedingungen</summary>
          <label class="field">Ort<select name="condition">${renderSelectOptions(locations, item.condition, 'Keine Ortsbedingung')}</select></label>
          <div class="subtitle">Weitere Regeln: Wochentag und Uhrzeit.</div>
        </details>
        <div class="editor-actions">
          <button type="button" class="secondary" data-view="labels">Abbrechen</button>
          <button type="button" data-save class="primary">Speichern</button>
        </div>
      </form>
    `;
  }

  function renderLocationEditor() {
    const item = state.edit;
    return `
      <button type="button" class="back" data-view="locations">${renderIcon('arrow-left')}Alle Orte</button>
      <div class="heading">
        <div>
          <h2>${item.id ? 'Ort bearbeiten' : 'Neuer Ort'}</h2>
          <div class="subtitle">Diesen Ort in Aufgaben- oder Label-Bedingungen verwenden.</div>
        </div>
      </div>
      <form class="editor" data-form="location">
        <label class="field">Name<input name="name" value="${escapeHtml(item.name)}" required></label>
        <div class="field-grid">
          <label class="field">Quelle<select name="source" data-source>${['GPS', 'Adresse', 'Plus Code'].map((source) => `<option ${item.source === source ? 'selected' : ''}>${source}</option>`).join('')}</select></label>
          <label class="field">Radius in Metern<input name="radius" type="number" min="1" max="100000" value="${escapeHtml(item.radius)}" required></label>
        </div>
        <div data-gps ${item.source !== 'GPS' ? 'hidden' : ''}>
          <div class="field-grid">
            <label class="field">Breitengrad<input name="lat" type="number" step="any" min="-90" max="90" value="${escapeHtml(item.lat)}"></label>
            <label class="field">Längengrad<input name="lon" type="number" step="any" min="-180" max="180" value="${escapeHtml(item.lon)}"></label>
          </div>
        </div>
        <div data-address ${item.source === 'GPS' ? 'hidden' : ''}>
          <label class="field"><span data-source-label>${item.source === 'Adresse' ? 'Adresse' : 'Plus Code'}</span><input name="address" value="${escapeHtml(item.address)}" placeholder="Ort eingeben"></label>
          <div class="subtitle">Positionsauflösung erfolgt in der App. Die Vorschau verwendet Beispieldaten.</div>
        </div>
        <label class="field">Notizen<textarea name="note">${escapeHtml(item.note)}</textarea></label>
        <div class="editor-actions">
          <button type="button" class="secondary" data-view="locations">Abbrechen</button>
          <button type="button" data-save class="primary">Speichern</button>
        </div>
      </form>
    `;
  }

  function openTaskEditor(id) {
    const original = tasks.find((task) => task.id === id);
    const base = original || {
      title: state.draft.title,
      labels: [...state.draft.labels],
      note: state.draft.note,
      location: state.draft.location,
      steps: [],
      priority: state.draft.mode === 'priority',
      someday: state.draft.mode === 'someday',
    };
    state.taskEdit = structuredClone({
      mode: base.someday ? 'someday' : base.priority ? 'priority' : 'queue',
      suspension: 'none',
      suspendedUntil: '',
      suspendedNote: '',
      due: base.id === 1 ? '2026-11-10T00:00' : '',
      autoDue: true,
      dueNote: '',
      repeatEnabled: false,
      repeatEvery: 1,
      repeatUnit: 'weeks',
      lead: 0,
      autoFinish: false,
      links: [],
      history: [],
      prerequisites: [],
      daysMode: 'inherit',
      days: [],
      timeMode: 'inherit',
      times: [],
      placesMode: base.location ? 'custom' : 'inherit',
      places: base.location ? [Number(base.location)] : [],
      ignoreLabels: false,
      ...base,
    });
    state.editorTab = 'overview';
    state.deleteConfirm = false;
    state.editorError = '';
    state.view = 'task-edit';
    state.drawer = false;
    render();
  }

  function editorField(label, key, type = 'text', extra = '') {
    const value = state.taskEdit[key];
    return `<label class="field">${label}<input type="${type}" data-e="${key}" value="${escapeHtml(value)}" ${extra}></label>`;
  }

  function editorCheck(label, key, description = '') {
    return `<label class="check-field"><input type="checkbox" data-e="${key}" ${state.taskEdit[key] ? 'checked' : ''}><span>${label}${description ? `<small>${description}</small>` : ''}</span></label>`;
  }

  function editorSelect(label, key, items) {
    return `<label class="field">${label}<select data-e="${key}">${items.map(([value, name]) => `<option value="${value}" ${String(state.taskEdit[key]) === String(value) ? 'selected' : ''}>${name}</option>`).join('')}</select></label>`;
  }

  function conditionMode(label, key) {
    return editorSelect(label, key, [
      ['inherit', 'Label-Bedingungen übernehmen'],
      ['any', 'Beliebig · Label-Regel ignorieren'],
      ['custom', 'Eigene Bedingung'],
    ]);
  }

  function renderTaskEditorOverview() {
    const draft = state.taskEdit;
    return `
      <div class="edit-grid">
        <div class="edit-column">
          <section class="edit-card">
            <h3>Aufgabendetails</h3>
            ${editorField('Aufgabenname', 'title', 'text', 'required maxlength="300"')}
            <label class="field">Notiz<textarea data-e="note" rows="3">${escapeHtml(draft.note)}</textarea></label>
          </section>

          <section class="edit-card">
            <h3>Labels</h3>
            <div class="edit-chips">
              ${labels
                .map(
                  (label) => `
                <label class="edit-chip">
                  <input type="checkbox" data-e-label="${label.id}" ${draft.labels.includes(label.id) ? 'checked' : ''}>
                  <span class="dot" style="--label-color:${escapeHtml(label.color)}"></span>
                  <span>${escapeHtml(label.name)}</span>
                </label>`,
                )
                .join('')}
            </div>
          </section>

          <section class="edit-card">
            <h3>Unteraufgaben <span class="edit-counter">${draft.steps.length}</span></h3>
            ${draft.steps
              .map(
                (step, index) => `
              <div class="edit-list-row">
                <label class="edit-step">
                  <input type="checkbox" data-e-step="${index}" ${step.done ? 'checked' : ''}>
                  <span>${escapeHtml(step.text)}</span>
                </label>
                <button type="button" class="remove-item" data-remove-step="${index}" aria-label="Unteraufgabe ${index + 1} entfernen">Entfernen</button>
              </div>`,
              )
              .join('')}
            <div class="edit-add-row">
              <input data-new-step aria-label="Neue Unteraufgabe" placeholder="Unteraufgabe hinzufügen …">
              <button type="button" class="secondary" data-add-step>Hinzufügen</button>
            </div>
            ${editorCheck('Automatisch abschließen', 'autoFinish', 'Die Aufgabe abschließen, sobald alle Unteraufgaben erledigt sind.')}
          </section>
        </div>

        <div class="edit-column">
          <section class="edit-card">
            <h3>Planung &amp; Status</h3>
            ${editorSelect('Einordnung', 'mode', [
              ['queue', 'Warteschlange'],
              ['priority', 'Priorität'],
              ['someday', 'Irgendwann'],
            ])}
            ${editorSelect('Zurückgestellt', 'suspension', [
              ['none', 'Nicht zurückgestellt'],
              ['until', 'Bis zu einem Zeitpunkt'],
              ['forever', 'Unbegrenzt'],
            ])}
            <div data-conditional="suspension" ${draft.suspension !== 'until' ? 'hidden' : ''}>
              ${editorField('Zurückgestellt bis', 'suspendedUntil', 'datetime-local')}
            </div>
            <div data-suspend-note ${draft.suspension === 'none' ? 'hidden' : ''}>
              ${editorField('Notiz zur Zurückstellung', 'suspendedNote')}
            </div>
            <div class="edit-divider"></div>
            ${editorField('Fällig am · optional', 'due', 'datetime-local')}
            <div data-due-options ${!draft.due ? 'hidden' : ''}>
              ${editorCheck('Bei nahender Fälligkeit priorisieren', 'autoDue', 'Ab Beginn der Vorlaufzeit vor reguläre Aufgaben ziehen.')}
              ${editorField('Fälligkeitsnotiz', 'dueNote')}
            </div>
            <div class="edit-divider"></div>
            ${editorCheck('Wiederholen', 'repeatEnabled')}
            <div data-repeat-options ${!draft.repeatEnabled ? 'hidden' : ''}>
              <div class="field-grid">
                ${editorField('Alle', 'repeatEvery', 'number', 'min="1" max="999"')}
                ${editorSelect('Einheit', 'repeatUnit', [
                  ['days', 'Tage'],
                  ['weeks', 'Wochen'],
                  ['months', 'Monate'],
                  ['years', 'Jahre'],
                ])}
              </div>
              ${editorField('Vorbereitung · Tage vorher', 'lead', 'number', 'min="0" max="999"')}
            </div>
          </section>
        </div>
      </div>
    `;
  }

  function renderTaskEditorRecords() {
    const draft = state.taskEdit;
    return `
      <div class="edit-grid equal">
        <section class="edit-card">
          <h3>Links <span class="edit-counter">${draft.links.length}</span></h3>
          ${
            draft.links.length
              ? draft.links
                  .map(
                    (link, index) => `
              <div class="record">
                <div><strong>${escapeHtml(link.title)}</strong><span>${escapeHtml(link.url)}</span></div>
                <button type="button" class="remove-item" data-remove-link="${index}" aria-label="Link ${index + 1} entfernen">Entfernen</button>
              </div>`,
                  )
                  .join('')
              : '<div class="edit-empty">Noch keine Links.</div>'
          }
          <label class="field">Link-Titel<input data-new-link-title placeholder="z. B. Dokumentation"></label>
          <label class="field">URI<input data-new-link-url placeholder="https://…"></label>
          <button type="button" class="secondary" data-add-link>Link hinzufügen</button>
        </section>

        <section class="edit-card">
          <h3>Verlauf <span class="edit-counter">${draft.history.length}</span></h3>
          ${
            draft.history.length
              ? draft.history
                  .map(
                    (entry, index) => `
              <div class="record">
                <div><small>${escapeHtml(entry.time.replace('T', ' · '))}</small><span>${escapeHtml(entry.text)}</span></div>
                <button type="button" class="remove-item" data-remove-history="${index}" aria-label="Verlaufseintrag ${index + 1} entfernen">Entfernen</button>
              </div>`,
                  )
                  .join('')
              : '<div class="edit-empty">Noch keine Verlaufseinträge.</div>'
          }
          <label class="field">Zeitstempel · leer bedeutet jetzt<input type="datetime-local" data-new-history-time></label>
          <label class="field">Verlaufseintrag<textarea data-new-history-text rows="3" placeholder="Fortschritt oder Ergebnis festhalten …"></textarea></label>
          <button type="button" class="secondary" data-add-history>Eintrag hinzufügen</button>
        </section>
      </div>
    `;
  }

  function renderTaskEditorRules() {
    const draft = state.taskEdit;
    return `
      <div class="edit-grid equal">
        <section class="edit-card">
          <h3>Voraussetzungen <span class="edit-counter">${draft.prerequisites.length}</span></h3>
          <p class="edit-description">Diese Aufgaben müssen zuerst erledigt sein.</p>
          <label class="field">Offene Aufgaben suchen<input type="search" data-prereq-search placeholder="Aufgabenname eingeben …"></label>
          <div class="prereq-list">
            ${tasks
              .filter((task) => !task.done && task.id !== draft.id)
              .map(
                (task) => `
              <label class="prereq-row" data-prereq-name="${escapeHtml(task.title.toLowerCase())}" ${draft.prerequisites.includes(task.id) ? '' : 'hidden'}>
                <input type="checkbox" data-prereq="${task.id}" ${draft.prerequisites.includes(task.id) ? 'checked' : ''}>
                <span>${escapeHtml(task.title)}</span>
              </label>`,
              )
              .join('')}
          </div>
        </section>

        <section class="edit-card">
          <h3>Aktivierungsbedingungen</h3>
          <p class="edit-description">Bestimmen, wann und wo diese Aufgabe aktiv wird.</p>
          ${editorCheck('Alle Label-Bedingungen ignorieren', 'ignoreLabels', 'Ohne eigene Regeln gilt die Aufgabe dann jederzeit und überall.')}
          <div class="edit-divider"></div>
          ${conditionMode('Wochentage', 'daysMode')}
          <div data-days ${draft.daysMode !== 'custom' ? 'hidden' : ''}>
            <div class="day-pills">
              ${['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
                .map(
                  (day, index) => `
                <label>
                  <input type="checkbox" data-day="${index}" ${draft.days.includes(index) ? 'checked' : ''}>
                  <span>${day}</span>
                </label>`,
                )
                .join('')}
            </div>
          </div>
          <div class="edit-divider"></div>
          ${conditionMode('Zeitfenster', 'timeMode')}
          <div data-times ${draft.timeMode !== 'custom' ? 'hidden' : ''}>
            ${draft.times
              .map(
                (time, index) => `
              <div class="edit-list-row">
                <span>${escapeHtml(time.start)} - ${escapeHtml(time.end)}</span>
                <button type="button" class="remove-item" data-remove-time="${index}" aria-label="Zeitfenster ${index + 1} entfernen">Entfernen</button>
              </div>`,
              )
              .join('')}
            <div class="field-grid">
              <label class="field">Von<input type="time" data-new-time-start></label>
              <label class="field">Bis<input type="time" data-new-time-end></label>
            </div>
            <button type="button" class="secondary" data-add-time>Zeitfenster hinzufügen</button>
          </div>
          <div class="edit-divider"></div>
          ${conditionMode('Standorte (GPS)', 'placesMode')}
          <div data-places ${draft.placesMode !== 'custom' ? 'hidden' : ''}>
            ${
              locations
                .map(
                  (location) => `
              <label class="prereq-row">
                <input type="checkbox" data-place="${location.id}" ${draft.places.includes(location.id) ? 'checked' : ''}>
                <span>${escapeHtml(location.name)}<small>Radius ${escapeHtml(location.radius)} m</small></span>
              </label>`,
                )
                .join('') || '<div class="edit-empty">Noch keine Orte erstellt.</div>'
            }
          </div>
        </section>
      </div>
    `;
  }

  function renderTaskEditor() {
    const draft = state.taskEdit;
    const modeLabel =
      draft.mode === 'priority'
        ? 'Priorität'
        : draft.mode === 'someday'
          ? 'Irgendwann'
          : 'Warteschlange';
    const tabs = [
      ['overview', 'Aufgabe', ''],
      ['records', 'Links &amp; Verlauf', String(draft.links.length + draft.history.length)],
      ['rules', 'Regeln', String(draft.prerequisites.length)],
    ];

    return `
      <button type="button" class="back" data-cancel-task>${renderIcon('arrow-left')}Zurück zu den Aufgaben</button>
      <div class="heading">
        <div>
          <h2>${draft.id ? 'Aufgabe bearbeiten' : 'Neue Aufgabe'}</h2>
          <div class="subtitle">${draft.id ? escapeHtml(draft.title) : 'Alle Angaben an einem Ort.'}</div>
        </div>
        <span class="limit">${modeLabel}</span>
      </div>

      <div class="edit-tabs" role="tablist" aria-label="Bereiche der Aufgabenbearbeitung">
        ${tabs
          .map(
            ([key, label, count]) => `
          <button type="button" role="tab" id="tt2-tab-${key}" aria-controls="tt2-edit-panel" aria-selected="${state.editorTab === key}" data-editor-tab="${key}">
            ${label}${count ? `<span>${count}</span>` : ''}
          </button>`,
          )
          .join('')}
      </div>

      <form data-form="task-editor" class="task-editor">
        <div role="tabpanel" id="tt2-edit-panel" aria-labelledby="tt2-tab-${state.editorTab}">
          ${
            state.editorTab === 'overview'
              ? renderTaskEditorOverview()
              : state.editorTab === 'records'
                ? renderTaskEditorRecords()
                : renderTaskEditorRules()
          }
        </div>

        <div class="edit-error" role="status">${escapeHtml(state.editorError)}</div>

        ${
          state.deleteConfirm
            ? `
          <div class="delete-question">
            <span>Diese Beispielaufgabe löschen?</span>
            <button type="button" class="secondary" data-delete-no>Behalten</button>
            <button type="button" class="danger" data-delete-yes>Ja, löschen</button>
          </div>`
            : ''
        }

        <div class="task-editor-actions">
          ${draft.id ? '<button type="button" class="danger" data-delete-task>Löschen</button>' : '<span></span>'}
          <div>
            <button type="button" class="secondary" data-cancel-task>Abbrechen</button>
            <button type="button" class="primary" data-save-task>Speichern</button>
          </div>
        </div>
        <div class="edit-footnote">Änderungen gelten nur für diese Vorschau.</div>
      </form>
    `;
  }

  function setEditorError(message) {
    state.editorError = message;
    const area = app.querySelector('.edit-error');
    if (area) {
      area.textContent = message;
    }
  }

  function refreshConditionalFields() {
    const draft = state.taskEdit;
    const mappings = [
      ['[data-days]', draft.daysMode === 'custom'],
      ['[data-times]', draft.timeMode === 'custom'],
      ['[data-places]', draft.placesMode === 'custom'],
      ['[data-conditional="suspension"]', draft.suspension === 'until'],
      ['[data-suspend-note]', draft.suspension !== 'none'],
      ['[data-due-options]', Boolean(draft.due)],
      ['[data-repeat-options]', Boolean(draft.repeatEnabled)],
    ];
    for (const [selector, visible] of mappings) {
      const element = app.querySelector(selector);
      if (element) {
        element.hidden = !visible;
      }
    }
  }

  function saveTaskEditor() {
    const draft = state.taskEdit;
    if (!draft.title.trim()) {
      state.editorTab = 'overview';
      render();
      setEditorError('Bitte einen Aufgabennamen eingeben.');
      return;
    }
    if (draft.suspension === 'until' && !draft.suspendedUntil) {
      state.editorTab = 'overview';
      render();
      setEditorError('Bitte einen Zeitpunkt für die Zurückstellung wählen.');
      return;
    }
    if (draft.repeatEnabled && Number(draft.repeatEvery) < 1) {
      setEditorError('Das Wiederholungsintervall muss mindestens 1 sein.');
      return;
    }

    const original = tasks.find((task) => task.id === draft.id);
    const updated = structuredClone(draft);
    updated.title = updated.title.trim();
    updated.priority = updated.mode === 'priority';
    updated.someday = updated.mode === 'someday';
    updated.blocked =
      updated.suspension !== 'none' ||
      updated.prerequisites.some(
        (prereqId) => !tasks.find((task) => task.id === prereqId)?.done,
      );
    updated.done =
      updated.done ||
      (updated.autoFinish &&
        updated.steps.length > 0 &&
        updated.steps.every((step) => step.done));
    updated.meta = updated.due
      ? `Fällig: ${updated.due.replace('T', ' · ')}`
      : updated.steps.length
        ? `${updated.steps.filter((step) => step.done).length} / ${updated.steps.length} Schritte`
        : '';

    if (original) {
      const idx = tasks.indexOf(original);
      tasks.splice(idx, 1, updated);
      if (updated.priority && !original.priority) {
        tasks.splice(tasks.indexOf(updated), 1);
        tasks.unshift(updated);
      }
    } else {
      updated.id = Math.max(0, ...tasks.map((task) => task.id)) + 1;
      if (updated.priority) {
        tasks.unshift(updated);
      } else {
        tasks.push(updated);
      }
      state.draft = {
        title: '',
        mode: 'queue',
        labels: state.label ? [state.label] : [],
        note: '',
        location: '',
      };
    }

    state.view = 'tasks';
    state.taskEdit = null;
    state.message = 'Aufgabe in dieser Vorschau gespeichert.';
    state.undo = null;
    render();
  }

  function renderMainContent() {
    if (state.view === 'task-edit') return renderTaskEditor();
    if (state.view === 'tasks') return renderTaskView();
    if (state.view === 'labels' || state.view === 'locations') {
      return renderManagerView(state.view);
    }
    if (state.view === 'label-edit') return renderLabelEditor();
    return renderLocationEditor();
  }

  function render() {
    app.innerHTML = `
      <header class="chrome">
        <button type="button" class="menu" data-menu aria-label="Navigation öffnen oder schließen" aria-expanded="${state.drawer}">
          <span>${state.drawer ? 'Zu' : 'Menü'}</span>
        </button>
        <div class="brand">
          <span class="mark" aria-hidden="true"><b></b><b></b><b></b></span>
          TierTask
        </div>
        <span class="workspace">Workspace · Work</span>
        <span class="sync">${renderIcon('cloud-check')}Aktuell</span>
      </header>
      <div class="layout">
        ${state.drawer ? '<button type="button" class="shade" data-menu aria-label="Navigation schließen"></button>' : ''}
        <nav class="sidebar ${state.drawer ? 'drawer-open' : ''}" aria-label="Aufgaben, Labels und Orte">
          ${renderSidebar()}
        </nav>
        <main class="main">${renderMainContent()}</main>
      </div>
    `;
  }

  function changeContext(labelId) {
    state.label = labelId;
    state.view = 'tasks';
    state.tier = 0;
    state.expanded = null;
    state.drawer = false;
    state.draft.labels = labelId ? [labelId] : [];
    state.message = '';
    render();
  }

  function handleEditorAction(button) {
    const draft = state.taskEdit;
    if (button.hasAttribute('data-edit-task')) {
      openTaskEditor(Number(button.dataset.editTask));
      return;
    }
    if (button.hasAttribute('data-full-editor')) {
      openTaskEditor(null);
      return;
    }
    if (button.hasAttribute('data-editor-tab')) {
      state.editorTab = button.dataset.editorTab;
      state.editorError = '';
      render();
      return;
    }
    if (button.hasAttribute('data-cancel-task')) {
      state.view = 'tasks';
      state.taskEdit = null;
      render();
      return;
    }
    if (button.hasAttribute('data-save-task')) {
      saveTaskEditor();
      return;
    }
    if (button.hasAttribute('data-delete-task')) {
      state.deleteConfirm = true;
      render();
      return;
    }
    if (button.hasAttribute('data-delete-no')) {
      state.deleteConfirm = false;
      render();
      return;
    }
    if (button.hasAttribute('data-delete-yes')) {
      tasks.splice(
        tasks.findIndex((task) => task.id === draft.id),
        1,
      );
      state.taskEdit = null;
      state.view = 'tasks';
      state.message = 'Beispielaufgabe gelöscht.';
      state.undo = null;
      render();
      return;
    }
    if (button.hasAttribute('data-add-step')) {
      const input = app.querySelector('[data-new-step]');
      if (input.value.trim()) {
        draft.steps.push({ text: input.value.trim(), done: false });
        render();
      }
      return;
    }
    if (button.hasAttribute('data-add-link')) {
      const title = app.querySelector('[data-new-link-title]').value.trim();
      const url = app.querySelector('[data-new-link-url]').value.trim();
      try {
        const parsed = new URL(url);
        if (!title || !parsed.protocol) {
          throw new Error('Invalid link');
        }
      } catch {
        setEditorError('Bitte einen Link-Titel und eine vollständige URI angeben.');
        return;
      }
      draft.links.push({ title, url });
      render();
      return;
    }
    if (button.hasAttribute('data-add-history')) {
      const text = app.querySelector('[data-new-history-text]').value.trim();
      if (!text) {
        setEditorError('Bitte einen Verlaufseintrag eingeben.');
        return;
      }
      const time =
        app.querySelector('[data-new-history-time]').value ||
        new Date()
          .toLocaleString('sv-SE', { timeZone: 'Europe/Berlin' })
          .replace(' ', 'T')
          .slice(0, 16);
      draft.history.unshift({ text, time });
      render();
      return;
    }
    if (button.hasAttribute('data-add-time')) {
      const start = app.querySelector('[data-new-time-start]').value;
      const end = app.querySelector('[data-new-time-end]').value;
      if (!start || !end) {
        setEditorError('Bitte Anfang und Ende des Zeitfensters wählen.');
        return;
      }
      draft.times.push({ start, end });
      render();
      return;
    }
    const removals = [
      ['data-remove-step', 'steps'],
      ['data-remove-link', 'links'],
      ['data-remove-history', 'history'],
      ['data-remove-time', 'times'],
    ];
    for (const [attribute, key] of removals) {
      if (button.hasAttribute(attribute)) {
        draft[key].splice(Number(button.getAttribute(attribute)), 1);
        render();
        return;
      }
    }
  }

  function saveForm(form) {
    if (form.dataset.form === 'task-editor') {
      saveTaskEditor();
      return;
    }
    const values = new FormData(form);
    if (form.dataset.form === 'task') {
      const title = String(values.get('title') || '').trim();
      if (!title) return;
      const mode = values.get('mode');
      const task = {
        id: Math.max(0, ...tasks.map((entry) => entry.id)) + 1,
        title,
        labels: [...state.draft.labels],
        meta: '',
        priority: mode === 'priority',
        someday: mode === 'someday',
        note: state.draft.note,
        location: Number(state.draft.location) || null,
        steps: [],
      };
      if (mode === 'priority') {
        tasks.unshift(task);
      } else {
        tasks.push(task);
      }
      state.draft = {
        title: '',
        mode: 'queue',
        labels: state.label ? [state.label] : [],
        note: '',
        location: '',
      };
      state.message =
        mode === 'priority'
          ? 'Priorisiert eingeordnet. Der Fokus bleibt bei maximal drei Aufgaben.'
          : mode === 'someday'
            ? 'Zu Irgendwann hinzugefügt.'
            : 'Am Ende der Warteschlange hinzugefügt.';
      if (!matchesContext(task)) {
        state.message += ' Im passenden Label-Kontext sichtbar.';
      }
      state.undo = null;
    } else {
      const isLabel = form.dataset.form === 'label';
      const list = isLabel ? labels : locations;
      const item = {
        ...state.edit,
        name: String(values.get('name') || '').trim(),
        note: String(values.get('note') || ''),
      };
      if (!item.name) return;
      if (isLabel) {
        item.color = String(values.get('color'));
        item.scoped = values.has('scoped');
        item.link = String(values.get('link') || '');
        item.url = String(values.get('url') || '');
        item.condition = String(values.get('condition') || '');
      } else {
        item.source = String(values.get('source'));
        item.radius = String(values.get('radius'));
        item.lat = String(values.get('lat') || '');
        item.lon = String(values.get('lon') || '');
        item.address = String(values.get('address') || '');
      }
      if (item.id) {
        list.splice(
          list.findIndex((entry) => entry.id === item.id),
          1,
          item,
        );
      } else {
        item.id = Math.max(0, ...list.map((entry) => entry.id)) + 1;
        list.push(item);
      }
      state.view = isLabel ? 'labels' : 'locations';
      state.message = isLabel
        ? 'Label in dieser Vorschau gespeichert.'
        : 'Ort in dieser Vorschau gespeichert.';
    }
    render();
  }

  // Event wiring
  const editorButtonPattern =
    /^data-(edit-task|full-editor|editor-tab|cancel-task|save-task|delete-task|delete-no|delete-yes|add-step|add-link|add-history|add-time|remove-step|remove-link|remove-history|remove-time)$/;

  app.addEventListener(
    'click',
    (event) => {
      const button = event.target.closest('button');
      if (!button) return;
      if (
        [...button.attributes].some((attribute) =>
          editorButtonPattern.test(attribute.name),
        )
      ) {
        event.stopImmediatePropagation();
        handleEditorAction(button);
      }
    },
    true,
  );

  app.addEventListener('click', (event) => {
    const button = event.target.closest('button');
    if (!button) return;
    const has = (name) => button.hasAttribute(`data-${name}`);

    if (has('save')) {
      const form = button.closest('form');
      if (form.reportValidity()) saveForm(form);
    } else if (has('menu')) {
      state.drawer = !state.drawer;
      render();
    } else if (has('view')) {
      state.view = button.dataset.view;
      state.drawer = false;
      state.message = '';
      render();
    } else if (has('tier')) {
      state.tier = Number(button.dataset.tier);
      state.view = 'tasks';
      state.drawer = false;
      state.message = '';
      render();
    } else if (has('label')) {
      changeContext(Number(button.dataset.label));
    } else if (has('edit-label')) {
      state.edit = {
        ...labels.find((label) => label.id === Number(button.dataset.editLabel)),
      };
      state.view = 'label-edit';
      state.drawer = false;
      render();
    } else if (has('edit-location')) {
      state.edit = {
        ...locations.find(
          (location) => location.id === Number(button.dataset.editLocation),
        ),
      };
      state.view = 'location-edit';
      state.drawer = false;
      render();
    } else if (has('new')) {
      if (button.dataset.new === 'labels') {
        state.edit = {
          name: '',
          color: '#2196f3',
          scoped: false,
          note: '',
          link: '',
          url: '',
          condition: '',
        };
        state.view = 'label-edit';
      } else {
        state.edit = {
          name: '',
          source: 'GPS',
          lat: '',
          lon: '',
          radius: 100,
          note: '',
          address: '',
        };
        state.view = 'location-edit';
      }
      render();
    } else if (has('detail')) {
      const id = Number(button.dataset.detail);
      state.expanded = state.expanded === id ? null : id;
      render();
    } else if (has('complete')) {
      const task = tasks.find(
        (entry) => entry.id === Number(button.dataset.complete),
      );
      state.undo = { id: task.id, done: task.done };
      task.done = !task.done;
      state.message = task.done
        ? 'Erledigt. Freie Fokusplätze werden nachbesetzt.'
        : 'Aufgabe wiederhergestellt.';
      render();
    } else if (has('undo')) {
      const task = tasks.find((entry) => entry.id === state.undo.id);
      task.done = state.undo.done;
      state.undo = null;
      state.message = 'Aktion rückgängig gemacht.';
      render();
    }
  });

  app.addEventListener('input', (event) => {
    const element = event.target;
    if (element.hasAttribute('data-draft')) {
      state.draft[element.dataset.draft] = element.value;
    }
    if (element.hasAttribute('data-e') && state.taskEdit) {
      state.taskEdit[element.dataset.e] =
        element.type === 'checkbox' ? element.checked : element.value;
      refreshConditionalFields();
    }
    if (element.hasAttribute('data-prereq-search')) {
      const query = element.value.toLowerCase();
      app.querySelectorAll('[data-prereq-name]').forEach((row) => {
        row.hidden = !(
          row.querySelector('input').checked ||
          (query && row.dataset.prereqName.includes(query))
        );
      });
    }
  });

  app.addEventListener('change', (event) => {
    const element = event.target;
    if (element.hasAttribute('data-context')) {
      changeContext(Number(element.value));
      return;
    }
    if (element.hasAttribute('data-tier-select')) {
      state.tier = Number(element.value);
      render();
      return;
    }
    if (element.hasAttribute('data-draft')) {
      state.draft[element.dataset.draft] = element.value;
      const hint = app.querySelector('[data-mode-hint]');
      if (hint) hint.textContent = modeHint();
      return;
    }
    if (element.hasAttribute('data-draft-label')) {
      const id = Number(element.dataset.draftLabel);
      state.draft.labels = state.draft.labels.filter((labelId) => labelId !== id);
      if (element.checked) state.draft.labels.push(id);
      const summary = app.querySelector('[data-label-summary]');
      if (summary) {
        summary.textContent = `Labels · ${state.draft.labels.length} ausgewählt`;
      }
      return;
    }
    if (element.hasAttribute('data-step')) {
      tasks.find((task) => task.id === Number(element.dataset.task)).steps[
        Number(element.dataset.step)
      ].done = element.checked;
      return;
    }
    if (element.hasAttribute('data-source')) {
      app.querySelector('[data-gps]').hidden = element.value !== 'GPS';
      app.querySelector('[data-address]').hidden = element.value === 'GPS';
      app.querySelector('[data-source-label]').textContent =
        element.value === 'Adresse' ? 'Adresse' : 'Plus Code';
      return;
    }

    const draft = state.taskEdit;
    if (!draft) return;
    if (element.hasAttribute('data-e')) {
      draft[element.dataset.e] =
        element.type === 'checkbox' ? element.checked : element.value;
      refreshConditionalFields();
    }
    const multiFields = [
      ['data-e-label', 'labels'],
      ['data-prereq', 'prerequisites'],
      ['data-day', 'days'],
      ['data-place', 'places'],
    ];
    for (const [attribute, key] of multiFields) {
      if (element.hasAttribute(attribute)) {
        const value = Number(element.getAttribute(attribute));
        draft[key] = draft[key].filter((item) => item !== value);
        if (element.checked) draft[key].push(value);
      }
    }
    if (element.hasAttribute('data-e-step')) {
      draft.steps[Number(element.dataset.eStep)].done = element.checked;
    }
  });

  app.addEventListener('submit', (event) => {
    event.preventDefault();
    if (event.target.reportValidity()) saveForm(event.target);
  });

  app.addEventListener(
    'keydown',
    (event) => {
      if (state.view === 'task-edit') {
        if (event.key === 'Enter' && event.target.matches('input')) {
          event.preventDefault();
          event.stopImmediatePropagation();
          if (event.target.hasAttribute('data-new-step')) {
            handleEditorAction(app.querySelector('[data-add-step]'));
          }
          return;
        }
        if (event.key === 'Escape') {
          event.preventDefault();
          state.view = 'tasks';
          state.taskEdit = null;
          render();
          return;
        }
      }
      if (
        event.key === 'Enter' &&
        event.target.matches('input') &&
        event.target.closest('form')
      ) {
        event.preventDefault();
        const form = event.target.closest('form');
        if (form.reportValidity()) saveForm(form);
      }
    },
    true,
  );

  // Preview toolbar bindings (Device, Theme Preset, Light/Dark Mode)
  root.querySelectorAll('[data-device]').forEach((button) => {
    button.addEventListener('click', () => {
      root
        .querySelector('.stage')
        .classList.toggle('mobile', button.dataset.device === 'mobile');
      root
        .querySelectorAll('[data-device]')
        .forEach((control) =>
          control.setAttribute('aria-pressed', String(control === button)),
        );
    });
  });

  root.querySelectorAll('[data-theme-preset]').forEach((button) => {
    button.addEventListener('click', () => {
      document.documentElement.dataset.theme = button.dataset.themePreset;
      root
        .querySelectorAll('[data-theme-preset]')
        .forEach((control) =>
          control.setAttribute('aria-pressed', String(control === button)),
        );
    });
  });

  root.querySelectorAll('[data-color-mode]').forEach((button) => {
    button.addEventListener('click', () => {
      document.documentElement.dataset.mode = button.dataset.colorMode;
      root
        .querySelectorAll('[data-color-mode]')
        .forEach((control) =>
          control.setAttribute('aria-pressed', String(control === button)),
        );
    });
  });

  // Start on the primary Task View so both Focus list and Task Editor are one click apart.
  render();
})();
