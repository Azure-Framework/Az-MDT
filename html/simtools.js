(function () {
  const state = { section: 'overview', data: {} };

  function send(action, payload) {
    try {
      fetch(`https://${GetParentResourceName()}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {})
      }).catch(() => {});
    } catch (_) {}
  }

  function esc(str) {
    return String(str == null ? '' : str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function trim(str, len) {
    const out = String(str == null ? '' : str).replace(/\s+/g, ' ').trim();
    return len && out.length > len ? `${out.slice(0, len - 1)}…` : out;
  }

  function officer() {
    return (window.MDT && window.MDT.state && window.MDT.state.officer) || {};
  }

  function isEnabled() { return !!officer().useAz5PD; }
  function isAvailable() { return !!officer().az5pdAvailable; }
  function statusbarEl() { return document.getElementById('mdt-sim-statusbar'); }
  function tabsEl() { return document.getElementById('mdt-sim-tabs'); }
  function contentEl() { return document.getElementById('mdt-sim-content'); }

  function injectStyle() {
    if (document.getElementById('az-mdt-simtools-style')) return;
    const style = document.createElement('style');
    style.id = 'az-mdt-simtools-style';
    style.textContent = `
      .mdt-sim-shell{flex:1;min-height:0}
      .mdt-sim-shell .mdt-card-body{flex:1;min-height:0;overflow-y:auto;overflow-x:hidden;padding-right:6px;scrollbar-gutter:stable;overscroll-behavior:contain;-webkit-overflow-scrolling:touch}
      .mdt-sim-statusbar{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin-bottom:10px}
      .mdt-sim-tabs{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:12px}
      .mdt-sim-tab{border:none;border-radius:10px;padding:9px 12px;background:var(--bg-card-soft,rgba(255,255,255,0.06));color:var(--text-main,#fff);cursor:pointer;font-weight:800}
      .mdt-sim-tab.active{background:linear-gradient(180deg,var(--accent,#2563eb),rgba(37,99,235,.72));color:#fff}
      .mdt-sim-content{display:flex;flex-direction:column;gap:12px;min-height:max-content;padding-bottom:8px}
      .mdt-sim-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
      .mdt-sim-grid-3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}
      .mdt-sim-card,.mdt-sim-pill,.mdt-sim-note,.mdt-sim-list-item,.mdt-sim-toolbar{background:var(--bg-card-soft,rgba(255,255,255,0.05));border-radius:12px;padding:14px}
      .mdt-sim-toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
      .mdt-sim-card h4{margin:0 0 8px;font-size:14px;font-weight:800}
      .mdt-sim-meta{font-size:12px;line-height:1.55;color:var(--text-soft,#cbd5e1)}
      .mdt-sim-strong{font-weight:800;color:var(--text-main,#fff)}
      .mdt-sim-actions{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px}
      .mdt-sim-btn{border:none;border-radius:10px;padding:10px 12px;cursor:pointer;font-size:12px;font-weight:800;background:var(--bg-input,#0f172a);color:var(--text-main,#fff)}
      .mdt-sim-btn.primary{background:linear-gradient(180deg,var(--accent,#2563eb),rgba(37,99,235,.78))}
      .mdt-sim-btn.warn{background:linear-gradient(180deg,#dc2626,rgba(220,38,38,.78))}
      .mdt-sim-list{display:flex;flex-direction:column;gap:10px}
      .mdt-sim-list-head{display:flex;justify-content:space-between;gap:8px;font-weight:800;margin-bottom:6px}
      .mdt-sim-badge,.mdt-sim-section-sub,.mdt-sim-pill-label,.mdt-sim-kicker{font-size:11px;color:var(--text-soft,#cbd5e1)}
      .mdt-sim-badge{padding:4px 8px;border-radius:999px;background:rgba(37,99,235,.16)}
      .mdt-sim-pill-value,.mdt-sim-section-title{font-weight:800;color:var(--text-main,#fff)}
      .mdt-sim-section-title{font-size:18px}
      .mdt-sim-section-sub{margin-top:4px}
      .mdt-sim-empty{padding:22px;text-align:center;color:var(--text-soft,#cbd5e1);background:var(--bg-card-soft,rgba(255,255,255,0.05));border-radius:12px}
      .mdt-sim-note{line-height:1.5;color:var(--text-main,#fff)}
      .mdt-sim-note strong{display:block;margin-bottom:4px}
      .mdt-sim-kicker{text-transform:uppercase;letter-spacing:.08em;margin-bottom:6px}
      @media (max-width:1100px){.mdt-sim-statusbar,.mdt-sim-grid,.mdt-sim-grid-3{grid-template-columns:1fr}}
    `;
    document.head.appendChild(style);
  }

  function sectionButton(id, label) {
    const active = state.section === id ? ' active' : '';
    return `<button class="mdt-sim-tab${active}" data-sim-section="${id}">${esc(label)}</button>`;
  }

  function card(title, body, actions) {
    return `<div class="mdt-sim-card"><h4>${esc(title)}</h4>${body || ''}${actions ? `<div class="mdt-sim-actions">${actions}</div>` : ''}</div>`;
  }

  function btn(label, action, kind, id) {
    return `<button class="mdt-sim-btn${kind ? ' ' + kind : ''}" data-sim-action="${esc(action)}"${id ? ` data-sim-id="${esc(id)}"` : ''}>${esc(label)}</button>`;
  }

  function incidentType(incident) {
    return (incident && incident.incidentType ? String(incident.incidentType) : '').toLowerCase();
  }

  function isStopScene(incident) {
    const type = incidentType(incident);
    return ['traffic_stop', 'vehicle_stop', 'felony_stop', 'field_contact', 'ped_contact'].includes(type) || !!(incident && incident.stop);
  }

  function tabsFor(data) {
    const out = [
      { id: 'overview', label: 'Overview' },
      { id: 'dispatch', label: 'Dispatch' },
      { id: 'scene', label: 'Scene' }
    ];
    if (isStopScene(data.incident)) out.push({ id: 'stops', label: 'Stop Flow' });
    out.push({ id: 'reports', label: 'Reports' });
    return out;
  }

  function ensureValidSection(data) {
    const ids = tabsFor(data).map(item => item.id);
    if (!ids.includes(state.section)) state.section = 'overview';
  }

  function buildQuickBar(data) {
    const incident = data.incident || null;
    const dispatch = Array.isArray(data.dispatch) ? data.dispatch : [];
    const shift = data.shift || null;
    const buttons = [];

    if (!shift) buttons.push(btn('Start Shift', 'startShift', 'primary'));
    else buttons.push(btn('Change Status', 'changeStatus'));

    if (!incident) {
      buttons.push(btn('Open Ped Scene', 'openPedScene', 'primary'));
      buttons.push(btn('Open Vehicle Scene', 'openVehicleScene'));
      if (dispatch[0] && dispatch[0].id) buttons.push(btn('Open Dispatch', 'openDispatchScene', '', dispatch[0].id));
    } else {
      buttons.push(btn('Refresh Scene', 'refreshState', 'primary'));
      if (isStopScene(incident)) buttons.push(btn('Run ID Check', 'idCheck'));
      buttons.push(btn('Shared Note', 'sharedNote'));
    }

    buttons.push(btn('Panic', 'panic', 'warn'));
    return `<div class="mdt-sim-toolbar">${buttons.join('')}</div>`;
  }

  function renderOverview(data) {
    const shift = data.shift;
    const incident = data.incident;
    const dispatch = Array.isArray(data.dispatch) ? data.dispatch.slice(0, 3) : [];
    const nextDispatch = dispatch[0] || null;
    const incidentSummary = incident
      ? `Scene <span class="mdt-sim-strong">${esc(incident.id || 'Active')}</span><br>Type: ${esc(incident.incidentType || 'Unknown')}<br>Status: ${esc(incident.status || 'pending')}<br>Target: ${esc(incident.context && incident.context.subjectLabel || incident.context && incident.context.plate || 'Unknown')}`
      : 'No active scene right now.';
    const dispatchSummary = nextDispatch
      ? `<span class="mdt-sim-strong">${esc(nextDispatch.id || 'CALL')}</span> • ${esc(nextDispatch.title || 'Dispatch')}<br>${esc(nextDispatch.zone || 'Unknown zone')}<br>${esc(trim(nextDispatch.callerUpdate || '', 110))}`
      : 'No active dispatch calls.';

    return `
      <div><div class="mdt-sim-section-title">Scene Tools</div><div class="mdt-sim-section-sub">The common field actions are up front. Shift, scene, and dispatch are no longer split across a pile of tabs.</div></div>
      ${buildQuickBar(data)}
      ${data.syncMessage ? `<div class="mdt-sim-note"><strong>Sync</strong>${esc(data.syncMessage)}</div>` : ''}
      <div class="mdt-sim-grid">
        ${card('Next Step', `<div class="mdt-sim-meta"><div class="mdt-sim-kicker">Recommended</div><span class="mdt-sim-strong">${esc(data.recommendedAction || 'Open or claim a scene.')}</span></div>`, `${incident ? btn('Go to Scene', 'refreshState', 'primary') : btn('Open Ped Scene', 'openPedScene', 'primary')}${nextDispatch ? btn('Open Dispatch', 'openDispatchScene', '', nextDispatch.id) : btn('Add BOLO', 'addBolo')}`)}
        ${card('Shift', `<div class="mdt-sim-meta"><div class="mdt-sim-kicker">Unit Status</div>${shift ? `<span class="mdt-sim-strong">${esc(shift.callsign || 'UNIT')}</span><br>Status: ${esc(shift.status || '10-7')}<br>Zone: ${esc(shift.zone || 'General Patrol')}<br>Goal: ${esc(shift.patrolGoal || 'Patrol')}` : 'No active shift.'}</div>`, shift ? `${btn('Change Status', 'changeStatus', 'primary')}${btn('End Shift', 'endShift')}` : `${btn('Start Shift', 'startShift', 'primary')}`)}
      </div>
      <div class="mdt-sim-grid">
        ${card('Current Scene', `<div class="mdt-sim-meta">${incidentSummary}</div>`, incident ? `${btn('Refresh Scene', 'refreshState', 'primary')}${isStopScene(incident) ? btn('Open Stop Flow', 'refreshState') : btn('Shared Note', 'sharedNote')}` : `${btn('Open Ped Scene', 'openPedScene', 'primary')}${btn('Open Vehicle Scene', 'openVehicleScene')}`)}
        ${card('Dispatch Snapshot', `<div class="mdt-sim-meta">${dispatchSummary}</div>`, nextDispatch ? `${btn(nextDispatch.accepted ? 'Join Call' : 'Claim Call', 'claimDispatch', 'primary', nextDispatch.id)}${btn('Open as Scene', 'openDispatchScene', '', nextDispatch.id)}` : `${btn('Refresh State', 'refreshState')}${btn('Add BOLO', 'addBolo', 'primary')}`)}
      </div>
      ${dispatch.length ? card('More Open Calls', `<div class="mdt-sim-list">${dispatch.map(call => `<div class="mdt-sim-list-item"><div class="mdt-sim-list-head"><span>${esc(call.id || 'CALL')} • ${esc(call.title || 'Dispatch')}</span><span class="mdt-sim-badge">P${esc(call.priority || 3)}</span></div><div class="mdt-sim-meta">${esc(trim(call.callerUpdate || call.zone || '', 110))}</div><div class="mdt-sim-actions">${btn(call.accepted ? 'Join' : 'Claim', 'claimDispatch', '', call.id)}${btn('Open', 'openDispatchScene', 'primary', call.id)}</div></div>`).join('')}</div>`) : ''}
    `;
  }

  function renderDispatch(data) {
    const dispatch = Array.isArray(data.dispatch) ? data.dispatch : [];
    const bolos = Array.isArray(data.bolos) ? data.bolos : [];
    return `
      <div><div class="mdt-sim-section-title">Dispatch</div><div class="mdt-sim-section-sub">Claim, join, and open calls without digging through extra pages.</div></div>
      ${buildQuickBar(data)}
      ${card('Dispatch Actions', `<div class="mdt-sim-meta">Emergency traffic, BOLO work, and a clean call list.</div>`, `${btn('Panic / Emergency Traffic', 'panic', 'warn')}${btn('Add BOLO / APB', 'addBolo', 'primary')}${btn('Refresh State', 'refreshState')}`)}
      ${card('Active Calls', dispatch.length ? `<div class="mdt-sim-list">${dispatch.map(call => `<div class="mdt-sim-list-item"><div class="mdt-sim-list-head"><span>${esc(call.id || 'CALL')} • ${esc(call.title || 'Dispatch')}</span><span class="mdt-sim-badge">P${esc(call.priority || 3)}</span></div><div class="mdt-sim-meta">${esc(trim(call.callerUpdate || '', 130))}<br>${esc(call.zone || 'Unknown zone')}</div><div class="mdt-sim-actions">${btn(call.accepted ? 'Join / Secondary' : 'Claim', 'claimDispatch', 'primary', call.id)}${btn('Open Scene', 'openDispatchScene', '', call.id)}</div></div>`).join('')}</div>` : `<div class="mdt-sim-empty">No active dispatch calls.</div>`)}
      ${card('BOLO / APB', bolos.length ? `<div class="mdt-sim-list">${bolos.map(item => `<div class="mdt-sim-list-item"><div class="mdt-sim-list-head"><span>${esc(item.id || 'BOLO')} • ${esc(item.label || 'BOLO')}</span><span class="mdt-sim-badge">${esc(item.category || 'General')}</span></div><div class="mdt-sim-meta">${esc(trim(item.reason || '', 120))}</div><div class="mdt-sim-actions">${btn('Clear BOLO', 'clearBolo', '', item.id)}</div></div>`).join('')}</div>` : `<div class="mdt-sim-empty">No active BOLOs.</div>`)}
    `;
  }

  function renderScene(data) {
    const incident = data.incident;
    if (!incident) {
      return `<div><div class="mdt-sim-section-title">Scene</div><div class="mdt-sim-section-sub">Face a nearby ped or vehicle, then open a scene.</div></div>${buildQuickBar(data)}${card('No Active Scene', `<div class="mdt-sim-meta">Start from a nearby ped or vehicle. Once a scene is open, the panel focuses on only the actions you actually use in the field.</div>`, `${btn('Open Nearby Ped Scene', 'openPedScene', 'primary')}${btn('Open Nearby Vehicle Scene', 'openVehicleScene')}`)}`;
    }
    const roleText = Array.isArray(incident.roles) && incident.roles.length ? incident.roles.map(unit => `${unit.callsign || unit.name || 'Unit'} (${unit.role || 'unit'})`).join(', ') : 'No attached units yet';
    return `
      <div><div class="mdt-sim-section-title">Scene</div><div class="mdt-sim-section-sub">Status, notes, support requests, and closeout.</div></div>
      ${buildQuickBar(data)}
      <div class="mdt-sim-grid">
        ${card(`Scene ${incident.id || ''}`, `<div class="mdt-sim-meta">Type: <span class="mdt-sim-strong">${esc(incident.incidentType || 'Unknown')}</span><br>Status: ${esc(incident.status || 'pending')}<br>Priority: ${esc(incident.priority || 3)}<br>Units: ${esc(roleText)}<br>Location: ${esc(trim(incident.context && (incident.context.street || incident.context.areaLabel) || 'Unknown', 120))}</div>`, `${btn('Set Status', 'setSceneStatus', 'primary')}${btn('Attach Role', 'attachRole')}${btn('Safe / Unsafe Flags', 'sceneFlags')}`)}
        ${card('Field Notes', `<div class="mdt-sim-meta">Document the core scene facts first. Support requests stay separate so the page feels lighter.</div>`, `${btn('Shared Note', 'sharedNote', 'primary')}${btn('Witness', 'witness')}${btn('Observation', 'observation')}`)}
      </div>
      <div class="mdt-sim-grid">
        ${card('Support', `<div class="mdt-sim-meta">Quick access to backup and specialty support.</div>`, `${btn('Request Backup', 'backup', 'primary')}${btn('K9 Request', 'k9')}`)}
        ${card('Closeout', `<div class="mdt-sim-meta">When the scene is stable, finish the checklist and generate the wrap-up summary.</div>`, `${btn('Scene Checklist', 'sceneChecklist')}${btn('Generate Summary', 'generateSummary', 'primary')}${btn('Close Scene', 'closeScene', 'warn')}`)}
      </div>
    `;
  }

  function renderStops(data) {
    const incident = data.incident;
    if (!incident || !isStopScene(incident)) {
      return `<div><div class="mdt-sim-section-title">Stop Flow</div><div class="mdt-sim-section-sub">Open a traffic stop or contact scene first.</div></div><div class="mdt-sim-empty">No active stop or contact scene.</div>`;
    }
    return `
      <div><div class="mdt-sim-section-title">Stop Flow</div><div class="mdt-sim-section-sub">The stop workflow is grouped into three chunks instead of a wall of buttons.</div></div>
      ${buildQuickBar(data)}
      ${card('Stop Snapshot', `<div class="mdt-sim-meta">Target: <span class="mdt-sim-strong">${esc(incident.context && incident.context.subjectLabel || 'Unknown')}</span><br>Plate: ${esc(incident.context && incident.context.plate || 'N/A')}<br>Demeanor: ${esc(incident.suspect && incident.suspect.demeanor || 'Unknown')}<br>ID Outcome: ${esc(incident.stop && incident.stop.idOutcome || 'pending')}<br>Search Mode: ${esc(incident.search && incident.search.mode || 'none')}</div>`)}
      <div class="mdt-sim-grid">
        ${card('Reason / Returns', `<div class="mdt-sim-meta">The first stop actions stay together.</div>`, `${btn('Reason for Stop', 'recordReason', 'primary')}${btn('Vehicle Return / VIN', 'vehicleCheck')}${btn('ID / License Check', 'idCheck')}`)}
        ${card('Driver Contact', `<div class="mdt-sim-meta">Interview and behavior observations.</div>`, `${btn('Interview Prompt', 'interview', 'primary')}${btn('Observed Cue', 'cue')}${btn('DUI Workflow', 'dui')}`)}
      </div>
      <div class="mdt-sim-grid">
        ${card('Legal Basis / Search', `<div class="mdt-sim-meta">Document consent or probable cause before a search.</div>`, `${btn('Search Decision', 'searchDecision', 'primary')}${btn('Probable Cause', 'probableCause')}${btn('Plain View / Evidence', 'plainViewEvidence')}`)}
        ${card('Resolution', `<div class="mdt-sim-meta">Tow, behavior management, and final checklists.</div>`, `${btn('Felony / Tow / Transport', 'felonyTow', 'primary')}${btn('Behavior / De-escalation', 'behaviorAction')}${btn('Stop Checklist', 'stopChecklist')}`)}
      </div>
    `;
  }

  function renderReports(data) {
    const recent = Array.isArray(data.recent) ? data.recent : [];
    return `
      <div><div class="mdt-sim-section-title">Reports</div><div class="mdt-sim-section-sub">Charges, warrants, summaries, and reopen tools. Training and policy live here instead of taking over the main nav.</div></div>
      ${buildQuickBar(data)}
      <div class="mdt-sim-grid">
        ${card('Report Builder', `<div class="mdt-sim-meta">Finish the casework once the field side is done.</div>`, `${btn('Add Charge', 'addCharge', 'primary')}${btn('Auto Recommend Charges', 'autoCharges')}${btn('Request Warrant', 'requestWarrant')}${btn('Generate Report Preview', 'reportPreview')}`)}
        ${card('Supervisor / Training', `<div class="mdt-sim-meta">Less-used actions are still here without cluttering the main workflow.</div>`, `${btn('Start Training Scenario', 'startTraining', 'primary')}${btn('Supervisor / IA Action', 'policyAction')}`)}
      </div>
      ${card('Recent Scenes', recent.length ? `<div class="mdt-sim-list">${recent.map(item => `<div class="mdt-sim-list-item"><div class="mdt-sim-list-head"><span>${esc(item.id || 'Scene')}</span><span class="mdt-sim-badge">${esc(item.status || item.type || 'recent')}</span></div><div class="mdt-sim-meta">${esc(trim(item.type || '', 40))}${item.score ? `<br>Score: ${esc(item.score.total || '?')} (${esc(item.score.rating || '')})` : ''}</div><div class="mdt-sim-actions">${btn('Reopen', 'reopenIncident', 'primary', item.id)}</div></div>`).join('')}</div>` : `<div class="mdt-sim-empty">No recent scenes yet.</div>`)}
    `;
  }

  function render() {
    injectStyle();
    const statusbar = statusbarEl();
    const tabs = tabsEl();
    const content = contentEl();
    if (!statusbar || !tabs || !content) return;
    if (!isEnabled()) {
      statusbar.innerHTML = '';
      tabs.innerHTML = '';
      content.innerHTML = '<div class="mdt-sim-empty">Enable <span class="mdt-sim-strong">Config.UseAz5PD = true</span> to embed Az-5PD scene tools into Az-MDT.</div>';
      return;
    }
    if (!isAvailable()) {
      statusbar.innerHTML = '';
      tabs.innerHTML = '';
      content.innerHTML = '<div class="mdt-sim-empty">Az-5PD is not started, so the integrated scene tools are currently unavailable.</div>';
      return;
    }
    const data = state.data || {};
    ensureValidSection(data);
    const shift = data.shift || null;
    const incident = data.incident || null;
    const dispatchCount = Array.isArray(data.dispatch) ? data.dispatch.length : 0;
    statusbar.innerHTML = `
      <div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Unit</div><div class="mdt-sim-pill-value">${esc(shift && shift.callsign || 'UNIT')}</div></div>
      <div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Status / Scene</div><div class="mdt-sim-pill-value">${esc(shift && shift.status || '10-7')} • ${esc(incident && incident.id || 'No Scene')}</div></div>
      <div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Next Step</div><div class="mdt-sim-pill-value">${esc(data.recommendedAction || (dispatchCount > 0 ? 'Open a dispatch call.' : 'Open or claim a scene.'))}</div></div>
    `;
    const tabsList = tabsFor(data);
    tabs.innerHTML = tabsList.map(item => sectionButton(item.id, item.label)).join('');
    let html = '';
    switch (state.section) {
      case 'dispatch': html = renderDispatch(data); break;
      case 'scene': html = renderScene(data); break;
      case 'stops': html = renderStops(data); break;
      case 'reports': html = renderReports(data); break;
      default: html = renderOverview(data); break;
    }
    content.innerHTML = html;
  }

  function requestRefresh() {
    if (!isEnabled() || !isAvailable()) return;
    send('simAction', { action: 'refreshState' });
  }

  function onPageActivated(page) {
    if (page !== 'simTools') return;
    render();
    requestRefresh();
  }

  document.addEventListener('click', (ev) => {
    const tab = ev.target.closest('[data-sim-section]');
    if (tab) {
      state.section = tab.dataset.simSection || 'overview';
      render();
      return;
    }
    const action = ev.target.closest('[data-sim-action]');
    if (action) {
      send('simAction', { action: action.dataset.simAction, id: action.dataset.simId || '', section: state.section });
    }
  });

  window.addEventListener('message', (event) => {
    const d = event.data || {};
    if (d.action === 'sim:mdtState') {
      const payload = d.payload || {};
      state.data = payload;
      if (payload.section) state.section = payload.section;
      render();
    } else if (d.action === 'open' || d.action === 'openMDT' || d.action === 'mdt:open') {
      render();
    }
  });

  if (window.MDT && typeof window.MDT.registerPageHook === 'function') {
    window.MDT.registerPageHook(onPageActivated);
  }
})();
