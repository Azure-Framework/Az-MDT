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
      .mdt-sim-statusbar{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-bottom:12px}
      .mdt-sim-tabs{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:12px}
      .mdt-sim-tab{border:none;border-radius:10px;padding:10px 12px;background:var(--bg-card-soft,rgba(255,255,255,0.06));color:var(--text-main,#fff);cursor:pointer;font-weight:700}
      .mdt-sim-tab.active{background:linear-gradient(180deg,var(--accent,#2563eb),rgba(37,99,235,.72));color:#fff}
      .mdt-sim-content{display:flex;flex-direction:column;gap:12px;min-height:max-content;padding-bottom:8px}
      .mdt-sim-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
      .mdt-sim-grid-3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}
      .mdt-sim-card,.mdt-sim-pill,.mdt-sim-note,.mdt-sim-list-item{background:var(--bg-card-soft,rgba(255,255,255,0.05));border-radius:12px;padding:14px}
      .mdt-sim-card h4{margin:0 0 10px;font-size:14px;font-weight:800}
      .mdt-sim-meta{font-size:12px;line-height:1.55;color:var(--text-soft,#cbd5e1)}
      .mdt-sim-strong{font-weight:800;color:var(--text-main,#fff)}
      .mdt-sim-actions{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px}
      .mdt-sim-btn{border:none;border-radius:10px;padding:10px 12px;cursor:pointer;font-size:12px;font-weight:800;background:var(--bg-input,#0f172a);color:var(--text-main,#fff)}
      .mdt-sim-btn.primary{background:linear-gradient(180deg,var(--accent,#2563eb),rgba(37,99,235,.78))}
      .mdt-sim-btn.warn{background:linear-gradient(180deg,#dc2626,rgba(220,38,38,.78))}
      .mdt-sim-list{display:flex;flex-direction:column;gap:10px}
      .mdt-sim-list-head{display:flex;justify-content:space-between;gap:8px;font-weight:800;margin-bottom:6px}
      .mdt-sim-badge,.mdt-sim-section-sub,.mdt-sim-pill-label{font-size:11px;color:var(--text-soft,#cbd5e1)}
      .mdt-sim-badge{padding:4px 8px;border-radius:999px;background:rgba(37,99,235,.16)}
      .mdt-sim-pill-value,.mdt-sim-section-title{font-weight:800;color:var(--text-main,#fff)}
      .mdt-sim-section-title{font-size:18px}
      .mdt-sim-section-sub{margin-top:4px}
      .mdt-sim-empty{padding:22px;text-align:center;color:var(--text-soft,#cbd5e1);background:var(--bg-card-soft,rgba(255,255,255,0.05));border-radius:12px}
      .mdt-sim-note{line-height:1.5;color:var(--text-main,#fff)}
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

  function renderOverview(data) {
    const shift = data.shift;
    const incident = data.incident;
    const dispatch = Array.isArray(data.dispatch) ? data.dispatch.slice(0, 3) : [];
    const bolos = Array.isArray(data.bolos) ? data.bolos.slice(0, 3) : [];
    return `
      <div><div class="mdt-sim-section-title">Overview</div><div class="mdt-sim-section-sub">Fast Az-5PD actions directly inside Az-MDT.</div></div>
      ${data.syncMessage ? `<div class="mdt-sim-note">${esc(data.syncMessage)}</div>` : ''}
      <div class="mdt-sim-note">Recommended next action: <span class="mdt-sim-strong">${esc(data.recommendedAction || 'Open or claim a scene.')}</span></div>
      <div class="mdt-sim-grid">
        ${card('Shift', `<div class="mdt-sim-meta">${shift ? `<span class="mdt-sim-strong">${esc(shift.callsign || 'UNIT')}</span><br>Status: ${esc(shift.status || '10-7')}<br>Zone: ${esc(shift.zone || 'General Patrol')}<br>Goal: ${esc(shift.patrolGoal || 'Patrol')}` : 'No active shift.'}</div>`, shift ? `${btn('Change Status', 'changeStatus', 'primary')}${btn('End Shift', 'endShift')}` : `${btn('Start Shift', 'startShift', 'primary')}`)}
        ${card('Active Scene', `<div class="mdt-sim-meta">${incident ? `<span class="mdt-sim-strong">${esc(incident.id || 'Scene')}</span><br>Type: ${esc(incident.incidentType || 'Unknown')}<br>Status: ${esc(incident.status || 'pending')}<br>Target: ${esc(incident.context && incident.context.subjectLabel || 'Unknown')}` : 'No active scene right now.'}</div>`, incident ? `${btn('Refresh Scene State', 'refreshState', 'primary')}` : `${btn('Open Ped Scene', 'openPedScene', 'primary')}${btn('Open Vehicle Scene', 'openVehicleScene')}`)}
      </div>
      ${card('Dispatch Snapshot', dispatch.length ? `<div class="mdt-sim-list">${dispatch.map(call => `<div class="mdt-sim-list-item"><div class="mdt-sim-list-head"><span>${esc(call.id || 'CALL')} • ${esc(call.title || 'Dispatch')}</span><span class="mdt-sim-badge">P${esc(call.priority || 3)}</span></div><div class="mdt-sim-meta">${esc(trim(call.callerUpdate || call.zone || '', 110))}</div><div class="mdt-sim-actions">${btn('Claim Secondary', 'claimDispatch', '', call.id)}${btn('Open as Scene', 'openDispatchScene', 'primary', call.id)}</div></div>`).join('')}</div>` : `<div class="mdt-sim-empty">No active dispatch calls.</div>`, `${btn('Panic / Emergency Traffic', 'panic', 'warn')}${btn('Add BOLO / APB', 'addBolo', 'primary')}`)}
      ${card('BOLO / APB Board', bolos.length ? `<div class="mdt-sim-list">${bolos.map(b => `<div class="mdt-sim-list-item"><div class="mdt-sim-list-head"><span>${esc(b.id || 'BOLO')} • ${esc(b.label || 'BOLO')}</span><span class="mdt-sim-badge">${esc(b.category || 'General')}</span></div><div class="mdt-sim-meta">${esc(trim(b.reason || '', 110))}</div><div class="mdt-sim-actions">${btn('Clear', 'clearBolo', '', b.id)}</div></div>`).join('')}</div>` : `<div class="mdt-sim-empty">No active BOLOs.</div>`)}
    `;
  }

  function renderShift(data) {
    const shift = data.shift;
    return `
      <div><div class="mdt-sim-section-title">Shift / Duty</div><div class="mdt-sim-section-sub">Start, update, or end your patrol shift.</div></div>
      ${card('Shift Status', `<div class="mdt-sim-grid-3"><div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Callsign</div><div class="mdt-sim-pill-value">${esc(shift && shift.callsign || 'Not Started')}</div></div><div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Status</div><div class="mdt-sim-pill-value">${esc(shift && shift.status || '10-7')}</div></div><div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Zone</div><div class="mdt-sim-pill-value">${esc(shift && shift.zone || 'General Patrol')}</div></div></div>`, shift ? `${btn('Change Status', 'changeStatus', 'primary')}${btn('End Shift', 'endShift')}` : `${btn('Start Shift', 'startShift', 'primary')}`)}
    `;
  }

  function renderDispatch(data) {
    const dispatch = Array.isArray(data.dispatch) ? data.dispatch : [];
    const bolos = Array.isArray(data.bolos) ? data.bolos : [];
    return `
      <div><div class="mdt-sim-section-title">Dispatch / BOLO / Radio</div><div class="mdt-sim-section-sub">Claim calls, open scenes, issue BOLOs, and trigger emergency traffic.</div></div>
      ${card('Quick Actions', `<div class="mdt-sim-meta">Keep dispatch actions inside MDT without bouncing back to a separate 5PD UI.</div>`, `${btn('Panic / Emergency Traffic', 'panic', 'warn')}${btn('Add BOLO / APB', 'addBolo', 'primary')}${btn('Refresh State', 'refreshState')}`)}
      ${card('Active Dispatch Calls', dispatch.length ? `<div class="mdt-sim-list">${dispatch.map(call => `<div class="mdt-sim-list-item"><div class="mdt-sim-list-head"><span>${esc(call.id || 'CALL')} • ${esc(call.title || 'Dispatch')}</span><span class="mdt-sim-badge">P${esc(call.priority || 3)}</span></div><div class="mdt-sim-meta">${esc(trim(call.callerUpdate || '', 130))}<br>${esc(call.zone || 'Unknown zone')}</div><div class="mdt-sim-actions">${btn('Claim Secondary', 'claimDispatch', '', call.id)}${btn('Open as Primary', 'openDispatchScene', 'primary', call.id)}</div></div>`).join('')}</div>` : `<div class="mdt-sim-empty">No active dispatch calls.</div>`)}
      ${card('BOLO / APB Board', bolos.length ? `<div class="mdt-sim-list">${bolos.map(b => `<div class="mdt-sim-list-item"><div class="mdt-sim-list-head"><span>${esc(b.id || 'BOLO')} • ${esc(b.label || 'BOLO')}</span><span class="mdt-sim-badge">${esc(b.category || 'General')}</span></div><div class="mdt-sim-meta">${esc(trim(b.reason || '', 120))}</div><div class="mdt-sim-actions">${btn('Clear BOLO', 'clearBolo', '', b.id)}</div></div>`).join('')}</div>` : `<div class="mdt-sim-empty">No active BOLOs.</div>`)}
    `;
  }

  function renderScene(data) {
    const incident = data.incident;
    if (!incident) {
      return `<div><div class="mdt-sim-section-title">Scene / Incident Tools</div><div class="mdt-sim-section-sub">Open a scene from a nearby ped or vehicle.</div></div>${card('No Active Scene', `<div class="mdt-sim-meta">Face a nearby ped or vehicle, then open a new scene from here.</div>`, `${btn('Open Nearby Ped Scene', 'openPedScene', 'primary')}${btn('Open Nearby Vehicle Scene', 'openVehicleScene')}`)}`;
    }
    const roleText = Array.isArray(incident.roles) && incident.roles.length ? incident.roles.map(unit => `${unit.callsign || unit.name || 'Unit'} (${unit.role || 'unit'})`).join(', ') : 'No attached units yet';
    return `
      <div><div class="mdt-sim-section-title">Scene / Incident Tools</div><div class="mdt-sim-section-sub">Primary / secondary roles, notes, witnesses, backup, and closeout.</div></div>
      ${card(`Scene ${incident.id || ''}`, `<div class="mdt-sim-meta">Type: <span class="mdt-sim-strong">${esc(incident.incidentType || 'Unknown')}</span><br>Status: ${esc(incident.status || 'pending')}<br>Priority: ${esc(incident.priority || 3)}<br>Units: ${esc(roleText)}<br>Location: ${esc(trim(incident.context && (incident.context.street || incident.context.areaLabel) || 'Unknown', 120))}</div>`, `${btn('Set Status', 'setSceneStatus', 'primary')}${btn('Safe / Unsafe Flags', 'sceneFlags')}${btn('Attach Role', 'attachRole')}`)}
      ${card('Scene Documentation', `<div class="mdt-sim-meta">Shared note, witness statement, observation, K9, and backup tools.</div>`, `${btn('Shared Note', 'sharedNote', 'primary')}${btn('Witness', 'witness')}${btn('Observation', 'observation')}${btn('Request Backup', 'backup')}${btn('K9 Request', 'k9')}`)}
      ${card('Closeout', `<div class="mdt-sim-meta">Checklist, narrative summary, and final scene closeout.</div>`, `${btn('Scene Checklist', 'sceneChecklist')}${btn('Generate Summary', 'generateSummary')}${btn('Close Scene', 'closeScene', 'warn')}`)}
    `;
  }

  function renderStops(data) {
    const incident = data.incident;
    if (!incident) {
      return `<div><div class="mdt-sim-section-title">Traffic Stop / Contact Workflow</div><div class="mdt-sim-section-sub">Open a stop scene first.</div></div><div class="mdt-sim-empty">No active stop or contact scene.</div>`;
    }
    return `
      <div><div class="mdt-sim-section-title">Traffic Stop / Contact Workflow</div><div class="mdt-sim-section-sub">Reason, returns, DUI, legal basis, evidence, and tow flow.</div></div>
      ${card('Stop Summary', `<div class="mdt-sim-meta">Target: <span class="mdt-sim-strong">${esc(incident.context && incident.context.subjectLabel || 'Unknown')}</span><br>Plate: ${esc(incident.context && incident.context.plate || 'N/A')}<br>Demeanor: ${esc(incident.suspect && incident.suspect.demeanor || 'Unknown')}<br>ID Outcome: ${esc(incident.stop && incident.stop.idOutcome || 'pending')}<br>Search Mode: ${esc(incident.search && incident.search.mode || 'none')}</div>`)}
      ${card('Core Stop Actions', `<div class="mdt-sim-meta">Record the reason, run returns, and document interview cues.</div>`, `${btn('Reason for Stop', 'recordReason', 'primary')}${btn('Vehicle Return / VIN', 'vehicleCheck')}${btn('ID / License Check', 'idCheck')}${btn('Interview Prompt', 'interview')}${btn('Observed Cue', 'cue')}${btn('DUI Workflow', 'dui')}`)}
      ${card('Legal Basis / Evidence', `<div class="mdt-sim-meta">Document consent or probable cause before searching.</div>`, `${btn('Search Decision', 'searchDecision', 'primary')}${btn('Probable Cause', 'probableCause')}${btn('Plain View / Evidence', 'plainViewEvidence')}${btn('Felony / Tow / Transport', 'felonyTow')}${btn('Behavior / De-escalation', 'behaviorAction')}${btn('Stop Checklist', 'stopChecklist')}`)}
    `;
  }

  function renderReports(data) {
    const recent = Array.isArray(data.recent) ? data.recent : [];
    return `
      <div><div class="mdt-sim-section-title">Reports / Court / Detective</div><div class="mdt-sim-section-sub">Charges, warrant flow, report preview, and follow-up case reopen.</div></div>
      ${card('Report Tools', `<div class="mdt-sim-meta">Build out your report with generated details and court workflow.</div>`, `${btn('Add Charge', 'addCharge', 'primary')}${btn('Auto Recommend Charges', 'autoCharges')}${btn('Request Warrant', 'requestWarrant')}${btn('Generate Report Preview', 'reportPreview')}`)}
      ${card('Recent Scenes', recent.length ? `<div class="mdt-sim-list">${recent.map(item => `<div class="mdt-sim-list-item"><div class="mdt-sim-list-head"><span>${esc(item.id || 'Scene')}</span><span class="mdt-sim-badge">${esc(item.status || item.type || 'recent')}</span></div><div class="mdt-sim-meta">${esc(trim(item.type || '', 40))}${item.score ? `<br>Score: ${esc(item.score.total || '?')} (${esc(item.score.rating || '')})` : ''}</div><div class="mdt-sim-actions">${btn('Reopen', 'reopenIncident', 'primary', item.id)}</div></div>`).join('')}</div>` : `<div class="mdt-sim-empty">No recent scenes yet.</div>`)}
    `;
  }

  function renderTraining(data) {
    const shift = data.shift || {};
    const weekly = data.weekly || {};
    return `
      <div><div class="mdt-sim-section-title">Training / Scorecards</div><div class="mdt-sim-section-sub">Academy scenarios and weekly performance snapshots.</div></div>
      ${card('Performance', `<div class="mdt-sim-grid-3"><div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Shift Incidents</div><div class="mdt-sim-pill-value">${esc(shift.stats && shift.stats.incidents || 0)}</div></div><div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Average Score</div><div class="mdt-sim-pill-value">${esc(Number(shift.stats && shift.stats.averageScore || 0).toFixed(1))}</div></div><div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Weekly Reviews</div><div class="mdt-sim-pill-value">${esc(weekly.reviews || 0)}</div></div></div>`, `${btn('Start Training Scenario', 'startTraining', 'primary')}`)}
    `;
  }

  function renderPolicy() {
    return `<div><div class="mdt-sim-section-title">Policy / IA / Commendations</div><div class="mdt-sim-section-sub">Supervisor notes, complaints, commendations, and review actions.</div></div>${card('Policy Actions', `<div class="mdt-sim-meta">Use this for commendations, complaints, force review, or supervisor coaching notes.</div>`, `${btn('Supervisor / IA Action', 'policyAction', 'primary')}`)}`;
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
    const shift = data.shift || null;
    const incident = data.incident || null;
    const dispatchCount = Array.isArray(data.dispatch) ? data.dispatch.length : 0;
    const boloCount = Array.isArray(data.bolos) ? data.bolos.length : 0;
    statusbar.innerHTML = `
      <div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Unit / Status</div><div class="mdt-sim-pill-value">${esc(shift && shift.callsign || 'UNIT')} • ${esc(shift && shift.status || '10-7')}</div></div>
      <div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Active Scene</div><div class="mdt-sim-pill-value">${esc(incident && incident.id || 'None')}</div></div>
      <div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Dispatch / BOLO</div><div class="mdt-sim-pill-value">${esc(dispatchCount)} Calls • ${esc(boloCount)} BOLOs</div></div>
      <div class="mdt-sim-pill"><div class="mdt-sim-pill-label">Recommended Next Step</div><div class="mdt-sim-pill-value">${esc(data.recommendedAction || 'Open or claim a dispatch call.')}</div></div>
    `;
    tabs.innerHTML = [
      sectionButton('overview', 'Overview'),
      sectionButton('shift', 'Shift / Duty'),
      sectionButton('dispatch', 'Dispatch / BOLO'),
      sectionButton('scene', 'Scene Tools'),
      sectionButton('stops', 'Traffic Stops'),
      sectionButton('reports', 'Reports / Court'),
      sectionButton('training', 'Training'),
      sectionButton('policy', 'Policy / IA')
    ].join('');
    let html = '';
    switch (state.section) {
      case 'shift': html = renderShift(data); break;
      case 'dispatch': html = renderDispatch(data); break;
      case 'scene': html = renderScene(data); break;
      case 'stops': html = renderStops(data); break;
      case 'reports': html = renderReports(data); break;
      case 'training': html = renderTraining(data); break;
      case 'policy': html = renderPolicy(data); break;
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

  window.AzMdtSimTools = { render, requestRefresh, onPageActivated, setData(payload) { state.data = payload || {}; if (payload && payload.section) state.section = payload.section; render(); } };
  render();
})();
