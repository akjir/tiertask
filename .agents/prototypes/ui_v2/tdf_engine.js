(() => {
  window.TT2 = window.TT2 || {};
  const { t, utcMsToLocalParts, formatLocalTimestamp, formatRepeatPhrase } =
    window.TT2.i18n;

  const NOW_UTC_ISO = '2026-11-21T10:30:00Z';
  const NOW_UTC_MS = Date.parse(NOW_UTC_ISO);

  const LABEL_COLOR_PRESETS = [
    '#2196F3',
    '#4CAF50',
    '#FF9100',
    '#E91E63',
    '#9C27B0',
    '#00BCD4',
    '#EB06FF',
    '#00E5FF',
  ];

  const SUPPORTED_UTC_OFFSETS = [
    -720, -660, -600, -570, -540, -480, -420, -360, -300, -240, -210, -180,
    -120, -60, 0, 60, 120, 180, 210, 240, 270, 300, 330, 345, 360, 390, 420,
    480, 540, 570, 600, 630, 660, 720, 765, 780, 840,
  ];

  const DUE_LEAD_MS = {
    off: null,
    at_due: 0,
    hours12: 12 * 3600 * 1000,
    hours24: 24 * 3600 * 1000,
    hours48: 48 * 3600 * 1000,
    days7: 7 * 24 * 3600 * 1000,
  };

  const SIMULATED_LOCATIONS = {
    office: {
      status: 'found',
      placeName: 'Riverdale · Office',
      latitude: 47.1204,
      longitude: 8.5173,
      source: 'gps',
    },
    home: {
      status: 'found',
      placeName: 'Southside · Home',
      latitude: 47.1012,
      longitude: 8.509,
      source: 'system',
    },
    away: {
      status: 'found',
      placeName: 'Harborview Transit',
      latitude: 47.4197,
      longitude: 7.8231,
      source: 'internet',
    },
    unavailable: {
      status: 'unavailable',
      placeName: null,
      latitude: null,
      longitude: null,
      source: null,
    },
  };

  const BASE62 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  let idCounter = 4096;

  function generateBase62Id() {
    idCounter += 7919;
    let seed = (Date.now() ^ (idCounter * 2654435761)) >>> 0;
    let out = '';
    for (let i = 0; i < 10; i += 1) {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      out += BASE62[seed % 62];
    }
    return out;
  }

  function resolveOffsetMinutes(config) {
    if (config.timeZoneMode === 'manual') {
      return Number(config.manualTimeZoneOffsetMinutes || 0);
    }
    return 60; // Deterministic Europe/Berlin winter CET (+01:00) for prototype
  }

  function haversineMeters(lat1, lon1, lat2, lon2) {
    const R = 6371000;
    const toRad = (deg) => (deg * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
    return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  function parseRadiusMeters(raw) {
    const text = String(raw ?? '').trim().toLowerCase().replace(',', '.');
    if (!text) return null;
    let multiplier = 1;
    let numericText = text;
    if (text.endsWith('km')) {
      multiplier = 1000;
      numericText = text.slice(0, -2).trim();
    } else if (text.endsWith('m')) {
      numericText = text.slice(0, -1).trim();
    }
    const value = Number(numericText);
    if (!Number.isFinite(value)) return null;
    const meters = value * multiplier;
    if (meters < 0.01 || meters > 100000) return null;
    return Math.round(meters * 100) / 100;
  }

  function resolveWebDavEndpoint(config) {
    let raw = String(config.serverUrl || '').trim();
    if (!raw) return null;
    if (!/^https?:\/\//i.test(raw)) raw = `https://${raw}`;
    raw = raw.replace(/\/+$/, '');
    try {
      const parsed = new URL(raw);
      if (!parsed.hostname) return null;
    } catch {
      return null;
    }
    const file = String(config.filePath || 'tasks.tdf')
      .trim()
      .replace(/^\/+/, '');
    if (!file || file.includes('..') || file.includes('\\')) return null;
    if (raw.toLowerCase().endsWith('.tdf')) return raw;
    if (
      raw.includes('/remote.php/dav/files/') ||
      raw.includes('/remote.php/webdav')
    ) {
      return `${raw}/${file}`;
    }
    const user = String(config.username || '').trim();
    if (!user) return `${raw}/remote.php/webdav/${file}`;
    return `${raw}/remote.php/dav/files/${encodeURIComponent(user)}/${file}`;
  }

  function defaultConfig(overrides = {}) {
    return {
      storageMode: 'local',
      localFilePath: 'tasks.tdf',
      localDirectory: '/home/demo/.local/share/tiertask',
      localWatchEnabled: true,
      serverUrl: '',
      username: '',
      password: '',
      filePath: 'tasks.tdf',
      language: 'english',
      themeMode: 'dark',
      themePalette: 'calm',
      timeZoneMode: 'automatic',
      manualTimeZoneOffsetMinutes: 60,
      dueLeadWindow: 'hours24',
      locationEnabled: true,
      diagnosticsEnabled: false,
      logLevel: 'info',
      logStorageMode: 'local',
      ...overrides,
    };
  }

  function createStressTestLabels() {
    const specs = [
      ['Directory Services', '#1E88E5', false],
      ['Archival', '#78909C', false],
      ['Automation', '#00ACC1', false],
      ['Backup & Recovery', '#43A047', false],
      ['CI/CD Pipelines', '#8E24AA', false],
      ['Cloud Migration', '#3949AB', true],
      ['Compliance Audits', '#D81B60', false],
      ['DNS', '#00897B', false],
      ['Documentation', '#5E35B1', false],
      ['Endpoint Security', '#E53935', false],
      ['Firewall & VPN', '#F4511E', false],
      ['Hardware Inventory', '#6D4C41', false],
      ['Service Desk Escalations', '#FB8C00', false],
      ['Incident Response', '#C62828', true],
      ['Container Cluster', '#039BE5', false],
      ['Client Northstar Labs', '#EC407A', false],
      ['Client Cobalt Logistics', '#AB47BC', false],
      ['Client Solis Energy', '#26A69A', false],
      ['Licenses & Contracts', '#7CB342', false],
      ['Server Fleet', '#558B2F', false],
      ['Mail & Messaging', '#0288D1', false],
      ['Monitoring & Alerts', '#FFA000', false],
      ['Core Networking', '#00838F', false],
      ['Team Onboarding', '#29B6F6', false],
      ['Patch Management', '#66BB6A', false],
      ['Project Ledger ERP Replacement', '#5C6BC0', true],
      ['Project Harbor Grid Modernization', '#26C6DA', true],
      ['Q4 Release Readiness', '#FF7043', true],
      ['Storage Arrays', '#8D6E63', false],
      ['Voice & Telephony', '#9CCC65', false],
    ];

    return specs.map(([name, color, scoped], idx) => {
      const num = String(idx + 1).padStart(2, '0');
      const day = String((idx % 18) + 1).padStart(2, '0');
      return {
        id: `LblStr00${num}`,
        name,
        color,
        scoped,
        note:
          idx % 3 === 0
            ? `Standard context and operational guidelines for ${name}.`
            : '',
        links:
          idx % 4 === 0
            ? [
                {
                  title: `${name} Runbook`,
                  uri: `https://docs.example.com/labels/str-${num}`,
                },
              ]
            : [],
        conditions:
          idx === 13
            ? {
                days: [1, 2, 3, 4, 5],
                times: [{ start: '07:00', end: '19:00' }],
                locationIds: [],
              }
            : { days: [], times: [], locationIds: [] },
        modifiedAt: `2026-11-${day}T09:${String((idx * 2) % 60).padStart(2, '0')}:00Z`,
      };
    });
  }

  function createStressTestTasks() {
    const activeSpecs = [
      ['Inspect database replication lag on primary cluster', ['LblStr0004', 'LblStr0022'], '2026-11-24T11:00:00Z', true],
      ['Plan DNSSEC key rollover for primary domain', ['LblStr0008', 'LblStr0023'], '2026-11-25T15:00:00Z', false],
      ['Rotate SAML signing certificate on identity gateway', ['LblStr0001', 'LblStr0010'], '2026-11-26T09:30:00Z', true],
      ['Migrate infrastructure state locking to object storage', ['LblStr0003', 'LblStr0005'], null, false],
      ['Streamline alert routing rules for weekend shifts', ['LblStr0022', 'LblInfra03'], '2026-11-27T14:00:00Z', false],
      ['Rotate VPN peer keys for field engineering laptops', ['LblStr0011', 'LblStr0010'], '2026-11-28T16:00:00Z', true],
      ['Collect quarterly access review evidence for audit', ['LblStr0007', 'LblStr0009'], '2026-11-30T17:00:00Z', true],
      ['Upgrade container base images to latest LTS release', ['LblStr0005', 'LblStr0020', 'LblStr0025'], null, false],
      ['Verify mail transport rules for staging domain', ['LblStr0021', 'LblStr0016'], '2026-12-01T10:00:00Z', false],
      ['Review storage controller firmware compatibility matrix', ['LblStr0029', 'LblStr0012'], null, false],
      ['Consolidate telemetry dashboards for monthly SLA review', ['LblStr0022', 'LblStr0017'], '2026-12-02T12:00:00Z', false],
      ['Extend configuration playbook for automated kernel updates', ['LblStr0003', 'LblStr0020', 'LblStr0025'], null, false],
      ['Reconcile asset ledger for returned workstation leases', ['LblStr0012', 'LblStr0019'], '2026-12-03T16:00:00Z', false],
      ['Refine service desk macros for credential recovery', ['LblStr0013', 'LblStr0009'], null, false],
      ['Test voice trunk failover with backup carrier', ['LblStr0030', 'LblStr0018'], '2026-12-04T09:00:00Z', true],
      ['Validate workstation bootstrap script for new hires', ['LblStr0024', 'LblStr0003'], null, false],
      ['Upgrade cluster ingress controller to latest minor version', ['LblStr0015', 'LblStr0025'], '2026-12-05T13:00:00Z', true],
      ['Confirm archive retention policy with finance team', ['LblStr0002', 'LblStr0007'], null, false],
      ['Analyze 30-day DMARC aggregate mail reports', ['LblStr0021', 'LblStr0008', 'LblStr0010'], '2026-12-06T11:00:00Z', false],
      ['Verify core switch configuration backups in repository', ['LblStr0023', 'LblStr0004'], null, false],
      ['Review battery maintenance contract for server room UPS', ['LblStr0019', 'LblStr0012'], '2026-12-08T15:00:00Z', false],
      ['Benchmark client portal latency under peak load', ['LblStr0016', 'LblStr0017', 'LblStr0022'], null, false],
    ];

    const scopedSpecs = [
      ['Approve cloud landing zone network peering topology', ['LblStr0006', 'LblStr0023'], '2026-11-29T14:00:00Z'],
      ['Update tabletop incident drill playbook for security team', ['LblStr0014', 'LblStr0010'], '2026-11-26T16:00:00Z'],
      ['Run dry-run migration for Ledger ERP cost centers', ['LblStr0026', 'LblStr0009'], '2026-12-02T10:00:00Z'],
      ['Measure fiber handoff attenuation for Harbor Grid sites', ['LblStr0027', 'LblStr0023'], '2026-12-04T11:30:00Z'],
      ['Sign off Q4 release launch checklist with product leads', ['LblStr0028', 'LblStr0005'], '2026-12-07T09:00:00Z'],
    ];

    const blockedSpecs = [
      {
        title: 'Run redundant switch failover test at Data Center',
        labels: ['LblStr0023', 'LblInfra03'],
        conds: { placesMode: 'custom', locationIds: ['LocDcSite2'] },
        note: 'Physical uplink failover check directly at Rack B4.',
      },
      {
        title: 'Submit annual license renewal after budget sign-off',
        labels: ['LblStr0019', 'LblStr0007'],
        suspendedMode: 'until',
        suspendedAt: '2026-12-10T08:00:00Z',
        suspendedNote: 'Waiting on executive budget sign-off after Q4 planning.',
      },
      {
        title: 'Decommission legacy file host after security review',
        labels: ['LblStr0029', 'LblStr0002'],
        blockedBy: [{ taskId: 'TskSecAud3', requiredCompletion: 1 }],
        note: 'Must wait until North Campus firewall review finishes.',
      },
      {
        title: 'Prepare automated evening patch window for compute fleet',
        labels: ['LblStr0025', 'LblStr0020'],
        conds: {
          daysMode: 'custom',
          days: [2, 4],
          timeMode: 'custom',
          times: [{ start: '18:00', end: '21:00' }],
        },
        note: 'Allowed only on Tuesday and Thursday evening windows.',
      },
      {
        title: 'Return retired edge router once carrier confirms disconnect',
        labels: ['LblStr0011', 'LblStr0012'],
        suspendedMode: 'forever',
        suspendedNote: 'Waiting for return shipping label from carrier.',
      },
    ];

    const somedaySpecs = [
      ['Draft dual-stack IPv6 architecture for guest Wi-Fi', ['LblStr0023', 'LblStr0008']],
      ['Migrate internal handbook to static site pipeline', ['LblStr0009', 'LblStr0005']],
      ['Track four-week power draw baseline on lab rack servers', ['LblStr0012', 'LblStr0022']],
      ['Record onboarding walkthrough clips for ticket portal', ['LblStr0013', 'LblStr0024']],
    ];

    const completedSpecs = [
      ['Documented edge router BGP prefix filters', ['LblStr0023', 'LblStr0009'], '2026-11-18T15:20:00Z'],
      ['Completed quarterly privileged account access audit', ['LblStr0001', 'LblStr0007'], '2026-11-17T11:45:00Z'],
      ['Verified emergency restore drill for knowledge base', ['LblStr0004', 'LblStr0020'], '2026-11-15T14:10:00Z'],
      ['Provisioned desk handsets for front reception', ['LblStr0030', 'LblStr0024'], '2026-11-14T16:30:00Z'],
    ];

    const tasks = [];
    const queueIds = [];
    let seq = 1;

    const makeBaseTask = (title, labels, extra = {}) => {
      const id = `TskStr${String(seq).padStart(4, '0')}`;
      const day = String(((seq - 1) % 19) + 1).padStart(2, '0');
      const hour = String(8 + (seq % 9)).padStart(2, '0');
      seq += 1;
      return {
        id,
        title,
        note: '',
        labels,
        priority: false,
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
        createdAt: `2026-11-${day}T${hour}:00:00Z`,
        modifiedAt: `2026-11-${day}T${hour}:15:00Z`,
        finishedAt: null,
        ...extra,
      };
    };

    activeSpecs.forEach(([title, labels, dueAt, rich], idx) => {
      const task = makeBaseTask(title, labels, {
        dueAt,
        duePassive: dueAt ? idx % 3 === 1 : false,
        dueNote: dueAt && rich ? 'Coordinate timing before the scheduled maintenance window.' : '',
        note:
          rich || idx % 2 === 0
            ? `Operational checklist #${idx + 1}: Technical verification and notes for "${title}".`
            : '',
        repeat:
          idx % 6 === 0
            ? { count: idx === 0 ? 2 : 4, unit: 'weeks', leadDays: dueAt ? 2 : 0 }
            : null,
        subtasksAutoFinish: rich && idx % 4 === 0,
        subtasks: rich
          ? [
              { text: 'Check prerequisites and telemetry logs', done: true },
              { text: 'Validate change in staging environment', done: idx % 2 === 0 },
              { text: 'Record final result in operations handbook', done: false },
            ]
          : idx % 3 === 0
            ? [
                { text: 'Complete initial inventory check', done: false },
                { text: 'Collect peer sign-off', done: false },
              ]
            : [],
        links: rich
          ? [
              {
                title: 'Operations Runbook',
                uri: `https://docs.example.com/ops/task-${idx + 1}`,
              },
              {
                title: 'Change Request',
                uri: `https://tickets.example.com/browse/OPS-${400 + idx}`,
              },
            ]
          : idx % 5 === 0
            ? [
                {
                  title: 'Monitoring Dashboard',
                  uri: `https://monitor.example.com/dash/${idx + 1}`,
                },
              ]
            : [],
        history: rich
          ? [
              {
                timestampUtc: '2026-11-19T10:15:00Z',
                text: 'Started initial review and logged dependencies.',
              },
            ]
          : [],
      });
      tasks.push(task);
      queueIds.push(task.id);
    });

    scopedSpecs.forEach(([title, labels, dueAt], idx) => {
      const task = makeBaseTask(title, labels, {
        dueAt,
        note: `Dedicated project queue item (${idx + 1}/5).`,
        subtasks: [
          { text: 'Prepare review checklist', done: true },
          { text: 'Document final sign-off', done: false },
        ],
      });
      tasks.push(task);
      queueIds.push(task.id);
    });

    blockedSpecs.forEach((spec) => {
      const task = makeBaseTask(spec.title, spec.labels, {
        note: spec.note || '',
        suspendedMode: spec.suspendedMode || 'none',
        suspendedAt: spec.suspendedAt || null,
        suspendedNote: spec.suspendedNote || '',
        blockedBy: spec.blockedBy || [],
        conditions: {
          ignoreLabels: false,
          daysMode: spec.conds?.daysMode || 'inherit',
          days: spec.conds?.days || [],
          timeMode: spec.conds?.timeMode || 'inherit',
          times: spec.conds?.times || [],
          placesMode: spec.conds?.placesMode || 'inherit',
          locationIds: spec.conds?.locationIds || [],
        },
      });
      tasks.push(task);
      queueIds.push(task.id);
    });

    somedaySpecs.forEach(([title, labels]) => {
      tasks.push(
        makeBaseTask(title, labels, {
          note: 'Backlog idea parked outside the active pull queue.',
        }),
      );
    });

    completedSpecs.forEach(([title, labels, finishedAt]) => {
      tasks.push(
        makeBaseTask(title, labels, {
          completions: 1,
          finishedAt,
          modifiedAt: finishedAt,
          history: [
            {
              timestampUtc: finishedAt,
              text: 'Completed and verified.',
            },
          ],
        }),
      );
    });

    return { tasks, queueIds };
  }

  function createSeedWorkspaces() {
    const stressLabels = createStressTestLabels();
    const stressTasks = createStressTestTasks();
    return [
      {
        id: 'ws_work',
        name: 'Work',
        config: defaultConfig({
          storageMode: 'both',
          localFilePath: 'work.tdf',
          serverUrl: 'https://cloud.example.com',
          username: 'demo',
          password: 'app-password-demo',
          filePath: 'TierTask/work.tdf',
          diagnosticsEnabled: true,
          logStorageMode: 'both',
        }),
        localFiles: ['work.tdf', 'personal.tdf', 'archive_2025.tdf'],
        deleted: {
          generation: 3,
          tasks: [{ id: '9zOldTsk01', deletedAt: '2026-11-12T08:15:00Z' }],
          labels: [],
          locations: [],
        },
        locations: [
          {
            id: 'LocOffice1',
            name: 'Office',
            sourceType: 'gps',
            source: 'gps',
            latitude: 47.1204,
            longitude: 8.5173,
            radius: 150,
            note: 'North Campus headquarters, Floor 4.',
            modifiedAt: '2026-11-01T08:00:00Z',
          },
          {
            id: 'LocDcSite2',
            name: 'Data Center',
            sourceType: 'plusCode',
            source: '8FVC4G92+RP',
            latitude: 47.1321,
            longitude: 8.5318,
            radius: 250,
            note: 'Bring access badge and hardware token.',
            modifiedAt: '2026-11-03T11:20:00Z',
          },
        ],
        labels: [
          {
            id: 'LblOrbVoi1',
            name: 'Project Orbit VoIP',
            color: '#2196F3',
            scoped: true,
            note: 'Rollout and migration of the Orbit voice platform.\nContacts: Alex Rivera (IT) and Department Operations.',
            links: [
              {
                title: 'Orbit VoIP Migration Runbook',
                uri: 'https://docs.example.com/orbit/voip-runbook',
              },
              {
                title: 'Orbit Ticket Board',
                uri: 'https://tickets.example.com/projects/orbit-voip',
              },
            ],
            conditions: {
              days: [],
              times: [{ start: '08:00', end: '18:00' }],
              locationIds: [],
            },
            modifiedAt: '2026-11-10T09:00:00Z',
          },
          {
            id: 'LblVspCli2',
            name: 'Client Vespera Systems',
            color: '#E91E63',
            scoped: false,
            note: 'Ongoing managed services and monthly maintenance windows.',
            links: [
              {
                title: 'Vespera Maintenance Schedule',
                uri: 'https://wiki.example.com/vespera/maintenance',
              },
            ],
            conditions: {
              days: [],
              times: [],
              locationIds: [],
            },
            modifiedAt: '2026-11-05T14:30:00Z',
          },
          {
            id: 'LblInfra03',
            name: 'Infrastructure',
            color: '#4CAF50',
            scoped: false,
            note: 'Internal servers, backups, and monitoring.',
            links: [],
            conditions: {
              days: [],
              times: [],
              locationIds: [],
            },
            modifiedAt: '2026-11-02T07:45:00Z',
          },
          ...stressLabels,
        ],
        queue: [
          'TskBkup001',
          'TskVspRpt2',
          'TskSecAud3',
          'TskPrxCfg4',
          'TskTlsRen5',
          'TskMonAlert',
          'TskDocNet7',
          'TskLicChk8',
          'TskPlan009',
          'TskDcRack9',
          'TskWkDay10',
          'TskSusp011',
          'TskBlkd012',
          'TskOrb0001',
          'TskOrb0002',
          'TskOrb0003',
          'TskOrb0004',
          'TskOrb0005',
          'TskOrb0006',
          'TskOrb0007',
          'TskOrb0008',
          'TskOrb0009',
          'TskOrb0010',
          ...stressTasks.queueIds,
        ],
        tasks: [
          {
            id: 'TskBkup001',
            title: 'Verify offsite backup checksums',
            note: 'Compare SHA-256 checksums of the latest monthly snapshots against the inventory ledger.',
            labels: ['LblInfra03'],
            priority: true,
            dueAt: '2026-11-20T16:00:00Z',
            dueAnchor: '2026-11-20 17:00:00',
            duePassive: false,
            dueNote: 'Must be documented before the monthly compliance report.',
            suspendedMode: 'none',
            suspendedAt: null,
            suspendedNote: '',
            repeat: { count: 1, unit: 'months', leadDays: 3 },
            completions: 4,
            subtasksAutoFinish: true,
            subtasks: [
              { text: 'Fetch latest snapshot hash', done: true },
              { text: 'Run restore check in sandbox', done: true },
              { text: 'Archive verification report in wiki', done: false },
            ],
            links: [
              {
                title: 'Backup Runbook',
                uri: 'https://docs.example.com/infra/backups',
              },
              {
                title: 'Storage Monitoring',
                uri: 'https://monitor.example.com/storage',
              },
            ],
            history: [
              {
                timestampUtc: '2026-10-20T14:12:00Z',
                text: 'October snapshot verified cleanly (0 mismatches).',
              },
              {
                timestampUtc: '2026-11-21T08:40:00Z',
                text: 'Started hash download and prepared sandbox VM.',
              },
            ],
            blockedBy: [],
            conditions: {
              ignoreLabels: false,
              daysMode: 'inherit',
              days: [],
              timeMode: 'inherit',
              times: [],
              placesMode: 'custom',
              locationIds: ['LocOffice1'],
            },
            createdAt: '2026-07-01T08:00:00Z',
            modifiedAt: '2026-11-21T08:40:00Z',
            finishedAt: null,
          },
          {
            id: 'TskVspRpt2',
            title: 'Finalize monthly report for Vespera Systems',
            note: 'Summarize SLA metrics and ticket response stats from the last quarter.',
            labels: ['LblVspCli2'],
            priority: false,
            dueAt: '2026-11-21T16:30:00Z',
            dueAnchor: '2026-11-21 18:30:00',
            duePassive: false,
            dueNote: 'Deliver no later than 17:30 today.',
            suspendedMode: 'none',
            suspendedAt: null,
            suspendedNote: '',
            repeat: null,
            completions: 0,
            subtasksAutoFinish: false,
            subtasks: [
              { text: 'Export SLA CSV dataset', done: true },
              { text: 'Review and approve final PDF', done: false },
            ],
            links: [
              {
                title: 'Vespera Report Template',
                uri: 'https://cloud.example.com/s/vespera-template',
              },
            ],
            history: [
              {
                timestampUtc: '2026-11-20T15:00:00Z',
                text: 'Exported raw metrics from the ticket tracker.',
              },
            ],
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
            createdAt: '2026-11-15T10:00:00Z',
            modifiedAt: '2026-11-20T15:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskSecAud3',
            title: 'Review firewall ruleset for North Campus',
            note: 'Reduce inbound ports to least-privilege allowlists.',
            labels: ['LblInfra03'],
            priority: false,
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
            createdAt: '2026-11-16T09:10:00Z',
            modifiedAt: '2026-11-16T09:10:00Z',
            finishedAt: null,
          },
          {
            id: 'TskPrxCfg4',
            title: 'Test reverse proxy headers for WebDAV endpoint',
            note: 'Verify ETag and If-Match forwarding under concurrent load.',
            labels: ['LblInfra03'],
            priority: false,
            dueAt: '2026-11-21T17:00:00Z',
            dueAnchor: null,
            duePassive: true,
            dueNote: 'Internal target date only (auto-priority disabled).',
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
            createdAt: '2026-11-16T10:00:00Z',
            modifiedAt: '2026-11-16T10:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskTlsRen5',
            title: 'Renew TLS certificate chain on mail relay',
            note: '',
            labels: ['LblInfra03'],
            priority: false,
            dueAt: '2026-11-28T12:00:00Z',
            dueAnchor: null,
            duePassive: false,
            dueNote: '',
            suspendedMode: 'none',
            suspendedAt: null,
            suspendedNote: '',
            repeat: { count: 12, unit: 'weeks', leadDays: 5 },
            completions: 2,
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
            createdAt: '2026-11-16T11:00:00Z',
            modifiedAt: '2026-11-16T11:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskMonAlert',
            title: 'Tune disk usage alerting thresholds',
            note: '',
            labels: ['LblInfra03'],
            priority: false,
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
            createdAt: '2026-11-17T08:00:00Z',
            modifiedAt: '2026-11-17T08:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskDocNet7',
            title: 'Update network diagram for Vespera Systems',
            note: '',
            labels: ['LblVspCli2'],
            priority: false,
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
            createdAt: '2026-11-17T09:00:00Z',
            modifiedAt: '2026-11-17T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskLicChk8',
            title: 'Audit software license renewals for Q1',
            note: '',
            labels: ['LblVspCli2'],
            priority: false,
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
            createdAt: '2026-11-18T08:30:00Z',
            modifiedAt: '2026-11-18T08:30:00Z',
            finishedAt: null,
          },
          {
            id: 'TskPlan009',
            title: 'Expand on-call handoff documentation',
            note: 'Link escalation contacts and emergency recovery scripts.',
            labels: ['LblInfra03'],
            priority: false,
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
            createdAt: '2026-11-18T10:00:00Z',
            modifiedAt: '2026-11-18T10:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskDcRack9',
            title: 'Label patch panel in Rack B',
            note: 'Requires physical access on site at the Data Center.',
            labels: ['LblInfra03'],
            priority: false,
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
              placesMode: 'custom',
              locationIds: ['LocDcSite2'],
            },
            createdAt: '2026-11-18T12:00:00Z',
            modifiedAt: '2026-11-18T12:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskWkDay10',
            title: 'Call hardware supplier on shipment ETA (Mon-Fri)',
            note: 'Confirm delivery schedule for replacement switches.',
            labels: ['LblInfra03'],
            priority: false,
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
              daysMode: 'custom',
              days: [1, 2, 3, 4, 5],
              timeMode: 'custom',
              times: [{ start: '09:00', end: '16:30' }],
              placesMode: 'inherit',
              locationIds: [],
            },
            createdAt: '2026-11-18T13:00:00Z',
            modifiedAt: '2026-11-18T13:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskSusp011',
            title: 'Quarterly budget review with finance team',
            note: '',
            labels: ['LblVspCli2'],
            priority: false,
            dueAt: null,
            dueAnchor: null,
            duePassive: false,
            dueNote: '',
            suspendedMode: 'until',
            suspendedAt: '2026-11-24T08:00:00Z',
            suspendedNote: 'Waiting for month-end close sign-off on Tuesday morning.',
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
            createdAt: '2026-11-18T14:00:00Z',
            modifiedAt: '2026-11-18T14:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskBlkd012',
            title: 'Send audit summary to leadership',
            note: 'Ready to send once offsite backup verification finishes.',
            labels: ['LblInfra03'],
            priority: false,
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
            blockedBy: [{ taskId: 'TskBkup001', requiredCompletion: 5 }],
            conditions: {
              ignoreLabels: false,
              daysMode: 'inherit',
              days: [],
              timeMode: 'inherit',
              times: [],
              placesMode: 'inherit',
              locationIds: [],
            },
            createdAt: '2026-11-19T09:00:00Z',
            modifiedAt: '2026-11-19T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskSome013',
            title: 'Evaluate automated update playbooks',
            note: 'Long-term automation improvement idea.',
            labels: ['LblInfra03'],
            priority: false,
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
            createdAt: '2026-11-10T10:00:00Z',
            modifiedAt: '2026-11-10T10:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskDone014',
            title: 'Provision VPN credentials for new teammate',
            note: 'Delivered profile via encrypted channel.',
            labels: ['LblInfra03'],
            priority: false,
            dueAt: null,
            dueAnchor: null,
            duePassive: false,
            dueNote: '',
            suspendedMode: 'none',
            suspendedAt: null,
            suspendedNote: '',
            repeat: null,
            completions: 1,
            subtasksAutoFinish: false,
            subtasks: [
              { text: 'Generate key pair', done: true },
              { text: 'Confirm connectivity test', done: true },
            ],
            links: [],
            history: [
              {
                timestampUtc: '2026-11-19T14:20:00Z',
                text: 'Connection test completed cleanly.',
              },
            ],
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
            createdAt: '2026-11-18T11:00:00Z',
            modifiedAt: '2026-11-19T14:20:00Z',
            finishedAt: '2026-11-19T14:20:00Z',
          },
          // Scoped queue tasks (Project Orbit VoIP)
          {
            id: 'TskOrb0001',
            title: 'Confirm Orbit project contacts and cutover schedule',
            note: 'Lock in the final migration window with operations leads.',
            labels: ['LblOrbVoi1'],
            priority: true,
            dueAt: '2026-11-10T09:00:00Z',
            dueAnchor: null,
            duePassive: false,
            dueNote: 'Overdue: follow up first.',
            suspendedMode: 'none',
            suspendedAt: null,
            suspendedNote: '',
            repeat: null,
            completions: 0,
            subtasksAutoFinish: false,
            subtasks: [],
            links: [
              {
                title: 'Orbit Contact Directory',
                uri: 'https://docs.example.com/orbit/contacts',
              },
            ],
            history: [
              {
                timestampUtc: '2026-11-11T09:00:00Z',
                text: 'Sent follow-up message to operations lead.',
              },
            ],
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
            createdAt: '2026-11-01T09:00:00Z',
            modifiedAt: '2026-11-11T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskOrb0002',
            title: 'Orbit VoIP: brief department leads and introduce Samira',
            note: '',
            labels: ['LblOrbVoi1'],
            priority: false,
            dueAt: null,
            dueAnchor: null,
            duePassive: false,
            dueNote: '',
            suspendedMode: 'none',
            suspendedAt: null,
            suspendedNote: '',
            repeat: null,
            completions: 0,
            subtasksAutoFinish: true,
            subtasks: [
              { text: 'Prepare rollout summary', done: true },
              { text: 'Confirm briefing slot', done: false },
            ],
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
            createdAt: '2026-11-02T09:00:00Z',
            modifiedAt: '2026-11-02T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskOrb0003',
            title: 'Orbit VoIP: run lab test setup with Alex Rivera',
            note: '',
            labels: ['LblOrbVoi1'],
            priority: false,
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
            subtasks: [
              { text: 'Configure test bench handsets', done: false },
              { text: 'Document call quality metrics', done: false },
            ],
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
            createdAt: '2026-11-03T09:00:00Z',
            modifiedAt: '2026-11-03T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskOrb0004',
            title: 'Prepare handover documentation for Orbit VoIP',
            note: '',
            labels: ['LblOrbVoi1'],
            priority: false,
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
            createdAt: '2026-11-04T09:00:00Z',
            modifiedAt: '2026-11-04T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskOrb0005',
            title: 'Verify phone templates and ring groups',
            note: '',
            labels: ['LblOrbVoi1'],
            priority: false,
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
            createdAt: '2026-11-05T09:00:00Z',
            modifiedAt: '2026-11-05T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskOrb0006',
            title: 'Collect open setup questions from pilot users',
            note: '',
            labels: ['LblOrbVoi1'],
            priority: false,
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
            createdAt: '2026-11-06T09:00:00Z',
            modifiedAt: '2026-11-06T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskOrb0007',
            title: 'Prepare project closeout review',
            note: '',
            labels: ['LblOrbVoi1'],
            priority: false,
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
            createdAt: '2026-11-07T09:00:00Z',
            modifiedAt: '2026-11-07T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskOrb0008',
            title: 'Review Orbit rollout checklist',
            note: '',
            labels: ['LblOrbVoi1'],
            priority: false,
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
            createdAt: '2026-11-08T09:00:00Z',
            modifiedAt: '2026-11-08T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskOrb0009',
            title: 'Archive VoIP migration documentation',
            note: '',
            labels: ['LblOrbVoi1'],
            priority: false,
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
            createdAt: '2026-11-09T09:00:00Z',
            modifiedAt: '2026-11-09T09:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskOrb0010',
            title: 'Await client sign-off on number porting',
            note: '',
            labels: ['LblOrbVoi1'],
            priority: false,
            dueAt: null,
            dueAnchor: null,
            duePassive: false,
            dueNote: '',
            suspendedMode: 'forever',
            suspendedAt: null,
            suspendedNote: 'Waiting for signed number porting authorization.',
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
            createdAt: '2026-11-09T11:00:00Z',
            modifiedAt: '2026-11-09T11:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskOrb0011',
            title: 'Revise end-user phone training slides',
            note: '',
            labels: ['LblOrbVoi1'],
            priority: false,
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
            createdAt: '2026-11-09T12:00:00Z',
            modifiedAt: '2026-11-09T12:00:00Z',
            finishedAt: null,
          },
          ...stressTasks.tasks,
        ],
      },
      {
        id: 'ws_personal',
        name: 'Personal',
        config: defaultConfig({
          storageMode: 'local',
          localFilePath: 'personal.tdf',
          diagnosticsEnabled: false,
        }),
        localFiles: ['work.tdf', 'personal.tdf'],
        deleted: { generation: 0, tasks: [], labels: [], locations: [] },
        locations: [
          {
            id: 'LocHome001',
            name: 'Home',
            sourceType: 'address',
            source: '42 Maple Lane, 4105 Riverdale',
            latitude: 47.1012,
            longitude: 8.509,
            radius: 100,
            note: 'Southside apartment.',
            modifiedAt: '2026-11-01T10:00:00Z',
          },
        ],
        labels: [
          {
            id: 'LblHouse01',
            name: 'Household',
            color: '#00BCD4',
            scoped: false,
            note: 'Groceries and weekly home errands.',
            links: [],
            conditions: { days: [], times: [], locationIds: [] },
            modifiedAt: '2026-11-01T10:00:00Z',
          },
        ],
        queue: ['TskPrv0001', 'TskPrv0002'],
        tasks: [
          {
            id: 'TskPrv0001',
            title: 'Tidy home office and sort cables',
            note: '',
            labels: ['LblHouse01'],
            priority: false,
            dueAt: null,
            dueAnchor: null,
            duePassive: false,
            dueNote: '',
            suspendedMode: 'none',
            suspendedAt: null,
            suspendedNote: '',
            repeat: null,
            completions: 0,
            subtasksAutoFinish: true,
            subtasks: [
              { text: 'Clear desk surface', done: true },
              { text: 'Label power adapters', done: false },
            ],
            links: [],
            history: [],
            blockedBy: [],
            conditions: {
              ignoreLabels: false,
              daysMode: 'inherit',
              days: [],
              timeMode: 'inherit',
              times: [],
              placesMode: 'custom',
              locationIds: ['LocHome001'],
            },
            createdAt: '2026-11-12T10:00:00Z',
            modifiedAt: '2026-11-12T10:00:00Z',
            finishedAt: null,
          },
          {
            id: 'TskPrv0002',
            title: 'Check winter tire pressure',
            note: '',
            labels: ['LblHouse01'],
            priority: true,
            dueAt: '2026-11-22T15:00:00Z',
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
            createdAt: '2026-11-18T10:00:00Z',
            modifiedAt: '2026-11-18T10:00:00Z',
            finishedAt: null,
          },
        ],
      },
    ];
  }

  function createSeedLogs(workspaceId) {
    return [
      `@meta version=0.4.0+a1b2c3d platform=linux workspace=${workspaceId}`,
      `@meta file=tiertask_2026-11-21_linux_${workspaceId}.log level=INFO tz=UTC+01:00`,
      '2026-11-21T10:25:01Z [INFO] [LIFECYCLE] app.start | build=0.4.0+a1b2c3d platform=linux',
      `2026-11-21T10:25:01Z [INFO] [STORAGE] settings.loaded | workspaces=2 active=${workspaceId}`,
      '2026-11-21T10:25:02Z [DEBUG] [TDF] tdf.parse | version=0.8.0 tasks=66 labels=33 locations=2',
      '2026-11-21T10:25:02Z [INFO] [SYNC] sync.complete | stage=3 etag="9f2c8b1" local_converged=true',
      '2026-11-21T10:26:14Z [INFO] [STORAGE] watch.attached | mode=parent_dir debounce_ms=350',
      '2026-11-21T10:28:40Z [WARN] [SYNC] webdav.retry | status=412 attempt=1 action=cas_rebase',
      '2026-11-21T10:28:41Z [INFO] [SYNC] sync.converged | generation=3 pruned=0',
      '2026-11-21T10:29:15Z [DEBUG] [DOMAIN] eval.summary | focus=3 ready=5 planned=23 blocked=9 someday=5 completed=5',
    ];
  }

  function isTaskSuspendedActive(task, nowMs) {
    if (task.suspendedMode === 'forever') return true;
    if (task.suspendedMode === 'until' && task.suspendedAt) {
      const targetMs = Date.parse(task.suspendedAt);
      return !Number.isNaN(targetMs) && targetMs > nowMs;
    }
    return false;
  }

  function isTaskWithinDueLeadWindow(task, nowMs, dueLeadKey) {
    if (!task.dueAt || task.duePassive || task.finishedAt) return false;
    const windowMs = DUE_LEAD_MS[dueLeadKey];
    if (windowMs === null || windowMs === undefined) return false;
    const dueMs = Date.parse(task.dueAt);
    if (Number.isNaN(dueMs)) return false;
    return nowMs >= dueMs - windowMs;
  }

  function isTaskOverdue(task, nowMs) {
    if (!task.dueAt || task.finishedAt) return false;
    const dueMs = Date.parse(task.dueAt);
    return !Number.isNaN(dueMs) && nowMs >= dueMs;
  }

  function computeEffectiveConditions(task, labelsById) {
    const cond = task.conditions || {
      ignoreLabels: false,
      daysMode: 'inherit',
      days: [],
      timeMode: 'inherit',
      times: [],
      placesMode: 'inherit',
      locationIds: [],
    };
    const inheritedDays = new Set();
    const inheritedTimes = [];
    const inheritedLocations = new Set();

    if (!cond.ignoreLabels) {
      for (const labelId of task.labels || []) {
        const label = labelsById.get(labelId);
        if (!label?.conditions) continue;
        for (const d of label.conditions.days || []) inheritedDays.add(d);
        for (const tw of label.conditions.times || []) inheritedTimes.push(tw);
        for (const locId of label.conditions.locationIds || []) {
          inheritedLocations.add(locId);
        }
      }
    }

    const days =
      cond.daysMode === 'custom'
        ? [...(cond.days || [])]
        : cond.daysMode === 'any' || cond.ignoreLabels
          ? []
          : [...inheritedDays];
    const times =
      cond.timeMode === 'custom'
        ? [...(cond.times || [])]
        : cond.timeMode === 'any' || cond.ignoreLabels
          ? []
          : inheritedTimes;
    const locationIds =
      cond.placesMode === 'custom'
        ? [...(cond.locationIds || [])]
        : cond.placesMode === 'any' || cond.ignoreLabels
          ? []
          : [...inheritedLocations];

    return { days, times, locationIds };
  }

  function evaluateConditions(task, workspace, context) {
    const labelsById = new Map(workspace.labels.map((l) => [l.id, l]));
    const locationsById = new Map(workspace.locations.map((l) => [l.id, l]));
    const eff = computeEffectiveConditions(task, labelsById);
    const localParts = utcMsToLocalParts(
      context.nowMs,
      resolveOffsetMinutes(workspace.config),
    );

    const results = [];
    let allSatisfied = true;

    if (eff.days.length > 0) {
      const ok = eff.days.includes(localParts.isoWeekday);
      if (!ok) allSatisfied = false;
      results.push({ type: 'days', days: eff.days, satisfied: ok });
    }

    if (eff.times.length > 0) {
      const nowMin = localParts.hour * 60 + localParts.minute;
      const ok = eff.times.some((tw) => {
        const [sh, sm] = String(tw.start || '00:00').split(':').map(Number);
        const [eh, em] = String(tw.end || '23:59').split(':').map(Number);
        const startMin = sh * 60 + sm;
        const endMin = eh * 60 + em;
        if (startMin <= endMin) return nowMin >= startMin && nowMin <= endMin;
        return nowMin >= startMin || nowMin <= endMin;
      });
      if (!ok) allSatisfied = false;
      results.push({ type: 'times', times: eff.times, satisfied: ok });
    }

    if (eff.locationIds.length > 0) {
      const fix = workspace.config.locationEnabled ? context.locationFix : null;
      const ok =
        fix &&
        fix.status === 'found' &&
        fix.latitude != null &&
        fix.longitude != null &&
        eff.locationIds.some((locId) => {
          const loc = locationsById.get(locId);
          if (!loc) return false;
          const dist = haversineMeters(
            fix.latitude,
            fix.longitude,
            loc.latitude,
            loc.longitude,
          );
          return dist <= loc.radius;
        });
      if (!ok) allSatisfied = false;
      results.push({
        type: 'locations',
        locationIds: eff.locationIds,
        satisfied: Boolean(ok),
      });
    }

    return { satisfied: allSatisfied, rules: results, effective: eff };
  }

  function evaluateDependencies(task, tasksById) {
    const deps = task.blockedBy || [];
    if (deps.length === 0) {
      return { satisfied: true, satisfiedCount: 0, total: 0, items: [] };
    }
    let satisfiedCount = 0;
    const items = [];
    for (const dep of deps) {
      const target = tasksById.get(dep.taskId);
      const isSat =
        !target || (target.completions || 0) >= (dep.requiredCompletion || 1);
      if (isSat) satisfiedCount += 1;
      items.push({
        taskId: dep.taskId,
        title: target ? target.title : dep.taskId,
        satisfied: isSat,
      });
    }
    return {
      satisfied: satisfiedCount === items.length,
      satisfiedCount,
      total: items.length,
      items,
    };
  }

  function evaluateBoard(workspace, context) {
    const nowMs = context.nowMs ?? NOW_UTC_MS;
    const activeLabelId = context.activeLabelId || null;
    const labelsById = new Map(workspace.labels.map((l) => [l.id, l]));
    const tasksById = new Map(workspace.tasks.map((task) => [task.id, task]));
    const queueIndex = new Map(
      workspace.queue.map((taskId, index) => [taskId, index]),
    );

    const openCountByLabel = new Map();
    const openCountByLocation = new Map();
    for (const label of workspace.labels) openCountByLabel.set(label.id, 0);
    for (const loc of workspace.locations) openCountByLocation.set(loc.id, 0);

    for (const task of workspace.tasks) {
      if (task.finishedAt) continue;
      for (const lid of task.labels || []) {
        openCountByLabel.set(lid, (openCountByLabel.get(lid) || 0) + 1);
      }
      const eff = computeEffectiveConditions(task, labelsById);
      for (const locId of eff.locationIds) {
        openCountByLocation.set(
          locId,
          (openCountByLocation.get(locId) || 0) + 1,
        );
      }
    }

    const visible = [];
    const scopedHidden = [];
    for (const task of workspace.tasks) {
      if (activeLabelId) {
        if ((task.labels || []).includes(activeLabelId)) visible.push(task);
        else scopedHidden.push(task);
      } else {
        const hasScoped = (task.labels || []).some(
          (lid) => labelsById.get(lid)?.scoped,
        );
        if (hasScoped) scopedHidden.push(task);
        else visible.push(task);
      }
    }

    const completed = [];
    const someday = [];
    const blocked = [];
    const activeQueueCandidates = [];
    const effectivePriorityIds = new Set();
    const conditionDetailsByTask = new Map();
    const dependencyDetailsByTask = new Map();

    for (const task of visible) {
      if (task.finishedAt) {
        completed.push(task);
        continue;
      }
      const suspended = isTaskSuspendedActive(task, nowMs);
      const inQueue = queueIndex.has(task.id);
      const depEval = evaluateDependencies(task, tasksById);
      const condEval = evaluateConditions(task, workspace, context);
      dependencyDetailsByTask.set(task.id, depEval);
      conditionDetailsByTask.set(task.id, condEval);

      if (!inQueue && !suspended) {
        someday.push(task);
        continue;
      }
      if (suspended || !depEval.satisfied || !condEval.satisfied) {
        blocked.push(task);
        continue;
      }

      const autoDue = isTaskWithinDueLeadWindow(
        task,
        nowMs,
        workspace.config.dueLeadWindow,
      );
      if (task.priority || autoDue) {
        effectivePriorityIds.add(task.id);
      }
      activeQueueCandidates.push(task);
    }

    // Sort active queue: effective priority first, preserving queue order within each partition.
    activeQueueCandidates.sort((a, b) => {
      const aPrio = effectivePriorityIds.has(a.id) ? 0 : 1;
      const bPrio = effectivePriorityIds.has(b.id) ? 0 : 1;
      if (aPrio !== bPrio) return aPrio - bPrio;
      return (queueIndex.get(a.id) ?? 999999) - (queueIndex.get(b.id) ?? 999999);
    });

    const focus = activeQueueCandidates.slice(0, 3);
    const ready = activeQueueCandidates.slice(3, 8);
    const planned = activeQueueCandidates.slice(8);

    completed.sort(
      (a, b) => Date.parse(b.finishedAt || 0) - Date.parse(a.finishedAt || 0),
    );

    const tiers = [focus, ready, planned, blocked, someday, completed];
    const tierOfTask = new Map();
    tiers.forEach((list, idx) => {
      for (const task of list) tierOfTask.set(task.id, idx);
    });

    return {
      tiers,
      focus,
      ready,
      planned,
      blocked,
      someday,
      completed,
      scopedHidden,
      tierOfTask,
      effectivePriorityIds,
      conditionDetailsByTask,
      dependencyDetailsByTask,
      openCountByLabel,
      openCountByLocation,
    };
  }

  function wouldCreateDependencyCycle(workspace, sourceTaskId, candidateId) {
    if (!sourceTaskId || !candidateId) return false;
    if (sourceTaskId === candidateId) return true;
    const tasksById = new Map(workspace.tasks.map((item) => [item.id, item]));
    const visited = new Set();
    const stack = [candidateId];
    while (stack.length > 0) {
      const current = stack.pop();
      if (current === sourceTaskId) return true;
      if (visited.has(current)) continue;
      visited.add(current);
      const node = tasksById.get(current);
      if (!node) continue;
      for (const dep of node.blockedBy || []) {
        stack.push(dep.taskId);
      }
    }
    return false;
  }

  function computeNextDueIso(baseIsoUtc, repeat, offsetMinutes) {
    const baseMs = Date.parse(baseIsoUtc);
    const d = new Date(baseMs + offsetMinutes * 60000);
    if (repeat.unit === 'days') d.setUTCDate(d.getUTCDate() + repeat.count);
    else if (repeat.unit === 'weeks') d.setUTCDate(d.getUTCDate() + repeat.count * 7);
    else {
      const targetDay = d.getUTCDate();
      d.setUTCDate(1);
      d.setUTCMonth(d.getUTCMonth() + repeat.count);
      const lastDay = new Date(
        Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0),
      ).getUTCDate();
      d.setUTCDate(Math.min(targetDay, lastDay));
    }
    return new Date(d.getTime() - offsetMinutes * 60000)
      .toISOString()
      .replace(/\.\d{3}Z$/, 'Z');
  }

  function completeTask(workspace, taskId, context) {
    const task = workspace.tasks.find((item) => item.id === taskId);
    if (!task) return { repeated: false };
    const nowIso = new Date(context.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');
    task.completions = (task.completions || 0) + 1;
    task.modifiedAt = nowIso;

    if (task.repeat) {
      const offset = resolveOffsetMinutes(workspace.config);
      task.subtasks = (task.subtasks || []).map((step) => ({
        ...step,
        done: false,
      }));
      task.priority = false;
      task.finishedAt = null;
      const anchorBase = task.dueAt || nowIso;
      const nextDue = computeNextDueIso(anchorBase, task.repeat, offset);
      if (task.dueAt) {
        task.dueAt = nextDue;
        task.dueAnchor = formatLocalTimestamp(nextDue, offset) + ':00';
        task.duePassive = false;
        if (task.repeat.leadDays > 0) {
          const leadMs = task.repeat.leadDays * 24 * 3600 * 1000;
          const suspMs = Date.parse(nextDue) - leadMs;
          if (suspMs > context.nowMs) {
            task.suspendedMode = 'until';
            task.suspendedAt = new Date(suspMs)
              .toISOString()
              .replace(/\.\d{3}Z$/, 'Z');
          } else {
            task.suspendedMode = 'none';
            task.suspendedAt = null;
          }
        }
      } else {
        task.suspendedMode = 'until';
        task.suspendedAt = nextDue;
      }
      if (!workspace.queue.includes(task.id)) workspace.queue.push(task.id);
      return { repeated: true };
    }

    task.finishedAt = nowIso;
    task.priority = false;
    workspace.queue = workspace.queue.filter((id) => id !== task.id);
    return { repeated: false };
  }

  function restoreTask(workspace, taskId, context) {
    const task = workspace.tasks.find((item) => item.id === taskId);
    if (!task) return;
    task.finishedAt = null;
    task.dueAt = null;
    task.dueAnchor = null;
    task.duePassive = false;
    task.suspendedMode = 'none';
    task.suspendedAt = null;
    task.modifiedAt = new Date(context.nowMs)
      .toISOString()
      .replace(/\.\d{3}Z$/, 'Z');
    if (!workspace.queue.includes(task.id)) workspace.queue.push(task.id);
  }

  function downgradeTask(workspace, taskId, context) {
    const evalRes = evaluateBoard(workspace, context);
    const tier = evalRes.tierOfTask.get(taskId);
    const task = workspace.tasks.find((item) => item.id === taskId);
    if (!task || tier === undefined || tier > 2) return false;
    const nowIso = new Date(context.nowMs).toISOString().replace(/\.\d{3}Z$/, 'Z');
    task.modifiedAt = nowIso;

    if (tier === 0) {
      // Focus -> Ready: clear priority, demote active due to passive, move after 3rd active item in queue
      task.priority = false;
      if (
        isTaskWithinDueLeadWindow(
          task,
          context.nowMs,
          workspace.config.dueLeadWindow,
        )
      ) {
        task.duePassive = true;
      }
      const others = workspace.queue.filter((id) => id !== taskId);
      const anchorTask = evalRes.ready[0] || evalRes.focus[evalRes.focus.length - 1];
      if (anchorTask && anchorTask.id !== taskId) {
        const idx = others.indexOf(anchorTask.id);
        others.splice(idx >= 0 ? idx + 1 : others.length, 0, taskId);
      } else {
        others.push(taskId);
      }
      workspace.queue = others;
      return true;
    }

    if (tier === 1) {
      // Ready -> Planned (move to queue tail)
      task.priority = false;
      if (
        isTaskWithinDueLeadWindow(
          task,
          context.nowMs,
          workspace.config.dueLeadWindow,
        )
      ) {
        task.duePassive = true;
      }
      workspace.queue = workspace.queue.filter((id) => id !== taskId);
      workspace.queue.push(taskId);
      return true;
    }

    // Planned -> Someday (remove from queue)
    task.priority = false;
    workspace.queue = workspace.queue.filter((id) => id !== taskId);
    return true;
  }

  function serializeTdf080(workspace) {
    const q = (value) =>
      `"${String(value ?? '')
        .replace(/\\/g, '\\\\')
        .replace(/"/g, '\\"')
        .replace(/\n/g, '\\n')}"`;
    const fmtTs = (iso) =>
      String(iso || NOW_UTC_ISO)
        .replace('T', ' ')
        .replace('Z', '');

    const lines = ['tdf 0.8.0', ''];

    // queue block
    lines.push('queue {');
    lines.push(`    modified ${fmtTs(NOW_UTC_ISO)}`);
    for (const taskId of workspace.queue) {
      lines.push(`    task     ${taskId}`);
    }
    lines.push('}');
    lines.push('');

    // deleted block
    const del = workspace.deleted;
    if (
      del &&
      (del.generation > 0 ||
        del.tasks.length ||
        del.labels.length ||
        del.locations.length)
    ) {
      lines.push('deleted {');
      lines.push(`    generation ${del.generation}`);
      for (const rec of del.tasks) {
        lines.push(`    task       ${rec.id} ${fmtTs(rec.deletedAt)}`);
      }
      for (const rec of del.labels) {
        lines.push(`    label      ${rec.id} ${fmtTs(rec.deletedAt)}`);
      }
      for (const rec of del.locations) {
        lines.push(`    location   ${rec.id} ${fmtTs(rec.deletedAt)}`);
      }
      lines.push('}');
      lines.push('');
    }

    // locations
    for (const loc of workspace.locations) {
      lines.push(`location ${loc.id} {`);
      lines.push(`    name     ${q(loc.name)}`);
      lines.push(
        `    coords   ${Number(loc.latitude).toFixed(6)} ${Number(loc.longitude).toFixed(6)} ${Number(loc.radius).toFixed(2)}m`,
      );
      if (loc.source) lines.push(`    source   ${q(loc.source)}`);
      if (loc.note) lines.push(`    note     ${q(loc.note)}`);
      lines.push(`    modified ${fmtTs(loc.modifiedAt)}`);
      lines.push('}');
      lines.push('');
    }

    // labels
    for (const label of workspace.labels) {
      lines.push(`label ${label.id}${label.scoped ? ' scoped' : ''} {`);
      lines.push(`    name     ${q(label.name)}`);
      if (label.color) lines.push(`    color    ${q(label.color.toUpperCase())}`);
      if (label.note) lines.push(`    note     ${q(label.note)}`);
      for (const link of label.links || []) {
        lines.push(`    link     ${q(link.title)} ${q(link.uri)}`);
      }
      const c = label.conditions || {};
      if (
        (c.days && c.days.length) ||
        (c.times && c.times.length) ||
        (c.locationIds && c.locationIds.length)
      ) {
        lines.push('    condition {');
        if (c.days?.length) {
          const toks = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
          lines.push(
            `        day      ${c.days.map((d) => toks[d - 1]).join(' ')}`,
          );
        }
        for (const tw of c.times || []) {
          lines.push(`        time     ${tw.start} ${tw.end}`);
        }
        if (c.locationIds?.length) {
          lines.push(`        location ${c.locationIds.join(' ')}`);
        }
        lines.push('    }');
      }
      lines.push(`    modified ${fmtTs(label.modifiedAt)}`);
      lines.push('}');
      lines.push('');
    }

    // tasks
    for (const task of workspace.tasks) {
      lines.push(`task ${task.id}${task.priority ? ' priority' : ''} {`);
      lines.push(`    name        ${q(task.title)}`);
      lines.push(`    created     ${fmtTs(task.createdAt)}`);
      lines.push(`    modified    ${fmtTs(task.modifiedAt)}`);
      if (task.finishedAt) {
        lines.push(`    finished    ${fmtTs(task.finishedAt)}`);
      }
      if (task.completions > 0) {
        lines.push(`    completions ${task.completions}`);
      }
      if (task.labels?.length) {
        lines.push(`    labels      ${task.labels.join(' ')}`);
      }
      if (task.note) {
        lines.push(`    note        ${q(task.note)}`);
      }
      if (task.dueAt) {
        let dueLine = `    due         ${fmtTs(task.dueAt)}`;
        if (task.dueAnchor) dueLine += ` anchor ${task.dueAnchor}`;
        if (task.duePassive) dueLine += ' passive';
        if (task.dueNote) dueLine += ` ${q(task.dueNote)}`;
        lines.push(dueLine);
      }
      if (task.suspendedMode === 'forever') {
        lines.push(
          `    suspended   forever${task.suspendedNote ? ` ${q(task.suspendedNote)}` : ''}`,
        );
      } else if (task.suspendedMode === 'until' && task.suspendedAt) {
        lines.push(
          `    suspended   ${fmtTs(task.suspendedAt)}${task.suspendedNote ? ` ${q(task.suspendedNote)}` : ''}`,
        );
      }
      if (task.repeat) {
        let rep = `    repeat      ${task.repeat.count} ${task.repeat.unit}`;
        if (task.dueAt && task.repeat.leadDays > 0) {
          rep += ` lead ${task.repeat.leadDays} days`;
        }
        lines.push(rep);
      }
      for (const dep of task.blockedBy || []) {
        lines.push(
          `    blocked     ${dep.taskId} ${dep.requiredCompletion || 1}`,
        );
      }
      for (const link of task.links || []) {
        lines.push(`    link        ${q(link.title)} ${q(link.uri)}`);
      }
      for (const entry of task.history || []) {
        lines.push(
          `    history     ${fmtTs(entry.timestampUtc)} ${q(entry.text)}`,
        );
      }
      if (task.subtasks?.length) {
        lines.push(
          `    subtasks${task.subtasksAutoFinish ? ' auto-finish' : ''} {`,
        );
        for (const step of task.subtasks) {
          lines.push(`        step ${step.done ? 'true ' : 'false'} ${q(step.text)}`);
        }
        lines.push('    }');
      }
      const c = task.conditions;
      if (
        c &&
        (c.ignoreLabels ||
          c.daysMode !== 'inherit' ||
          c.timeMode !== 'inherit' ||
          c.placesMode !== 'inherit')
      ) {
        lines.push('    condition {');
        if (c.ignoreLabels) lines.push('        any');
        if (c.daysMode === 'any') lines.push('        day      any');
        else if (c.daysMode === 'custom' && c.days?.length) {
          const toks = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
          lines.push(
            `        day      ${c.days.map((d) => toks[d - 1]).join(' ')}`,
          );
        }
        if (c.timeMode === 'any') lines.push('        time     any');
        else if (c.timeMode === 'custom') {
          for (const tw of c.times || []) {
            lines.push(`        time     ${tw.start} ${tw.end}`);
          }
        }
        if (c.placesMode === 'any') lines.push('        location any');
        else if (c.placesMode === 'custom' && c.locationIds?.length) {
          lines.push(`        location ${c.locationIds.join(' ')}`);
        }
        lines.push('    }');
      }
      lines.push('}');
      lines.push('');
    }

    return lines.join('\n');
  }

  function simulateResolveLocationSource(sourceType, rawInput) {
    const query = String(rawInput || '').trim();
    if (!query) return { ok: false, errorKey: 'errLocSourceEmpty' };
    if (sourceType === 'plusCode') {
      return {
        ok: true,
        candidates: [
          {
            displayName: `Plus Code ${query.toUpperCase()} · Riverdale`,
            latitude: 47.1321,
            longitude: 8.5318,
          },
        ],
      };
    }
    const lower = query.toLowerCase();
    if (
      lower.includes('market') ||
      lower.includes('riverdale') ||
      lower.includes('main') ||
      lower.includes('central')
    ) {
      return {
        ok: true,
        candidates: [
          {
            displayName: `${query}, Old Town, 4100 Riverdale`,
            latitude: 47.120407,
            longitude: 8.517262,
          },
          {
            displayName: `${query}, Northgate, 4109 Riverdale`,
            latitude: 47.13689,
            longitude: 8.53241,
          },
          {
            displayName: `${query}, Eastbridge, 4130 Riverdale`,
            latitude: 47.11912,
            longitude: 8.58544,
          },
        ],
      };
    }
    return {
      ok: true,
      candidates: [
        {
          displayName: `${query}, Riverdale District`,
          latitude: 47.12421,
          longitude: 8.52188,
        },
      ],
    };
  }

  function formatConditionLine(rule, locations, lang) {
    const weekdays = window.TT2.i18n.strings[window.TT2.i18n.resolveLang(lang)].weekdays;
    if (rule.type === 'days') {
      return `${t(lang, 'condDays')}: ${rule.days.map((d) => weekdays[d - 1]).join(', ')}`;
    }
    if (rule.type === 'times') {
      return `${t(lang, 'condTimes')}: ${rule.times.map((tw) => `${tw.start}–${tw.end}`).join(', ')}`;
    }
    if (rule.type === 'locations') {
      const names = rule.locationIds.map(
        (id) => locations.find((l) => l.id === id)?.name || id,
      );
      return `${t(lang, 'condLocations')}: ${names.join(', ')}`;
    }
    return '';
  }

  function formatRepeatSummary(task, lang) {
    if (!task.repeat) return '';
    return formatRepeatPhrase(task.repeat.count, task.repeat.unit, lang);
  }

  window.TT2.engine = {
    NOW_UTC_ISO,
    NOW_UTC_MS,
    LABEL_COLOR_PRESETS,
    SUPPORTED_UTC_OFFSETS,
    DUE_LEAD_MS,
    SIMULATED_LOCATIONS,
    generateBase62Id,
    resolveOffsetMinutes,
    parseRadiusMeters,
    resolveWebDavEndpoint,
    defaultConfig,
    createSeedWorkspaces,
    createSeedLogs,
    isTaskSuspendedActive,
    isTaskWithinDueLeadWindow,
    isTaskOverdue,
    computeEffectiveConditions,
    evaluateConditions,
    evaluateDependencies,
    evaluateBoard,
    wouldCreateDependencyCycle,
    completeTask,
    restoreTask,
    downgradeTask,
    serializeTdf080,
    simulateResolveLocationSource,
    formatConditionLine,
    formatRepeatSummary,
  };
})();
