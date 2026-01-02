// az_mdt NUI script with sounds + TTS + admin mode + notes/flags/warrants modals
// ----------------------------------------------------

const AZ_MDT_CONFIG = window.AZ_MDT_CONFIG || {};

const MDT = {
    root: null,
    windowEl: null,
    state: {
        officer: null,
        status: 'AVAILABLE',
        activePage: 'dashboard',
        nameResults: [],
        plateResults: null,
        weaponResults: null,
        bolos: [],
        reports: [],
        employees: [],
        units: [],
        calls: [],
        chat: [],
        recordTarget: null,
        seenCalls: {},
        isAdmin: false,
        warrants: [],
        actionLog: [],
        modalContext: null
    },
    els: {}
};

// ---------- audio + TTS ----------

const MDT_AUDIO = {
    click: null,
    panic: null,
    call: null,
    bolo: null
};

function initAudio() {
    try {
        MDT_AUDIO.click = new Audio('sounds/click.ogg');
        MDT_AUDIO.click.volume = 0.4;
    } catch (e) {
        console.warn('[az_mdt] click sound init failed', e);
    }

    try {
        MDT_AUDIO.panic = new Audio('sounds/panic.ogg');
        MDT_AUDIO.panic.volume = 0.7;
    } catch (e) {
        console.warn('[az_mdt] panic sound init failed', e);
    }

    try {
        MDT_AUDIO.call = new Audio('sounds/911.ogg');
        MDT_AUDIO.call.volume = 0.7;
    } catch (e) {
        console.warn('[az_mdt] call sound init failed', e);
    }

    try {
        MDT_AUDIO.bolo = new Audio('sounds/bolo.ogg');
        MDT_AUDIO.bolo.volume = 0.6;
    } catch (e) {
        console.warn('[az_mdt] bolo sound init failed', e);
    }
}

function playSound(name) {
    const snd = MDT_AUDIO[name];
    if (!snd) return;
    try {
        snd.currentTime = 0;
        snd.play().catch(() => {});
    } catch (e) {
        console.warn('[az_mdt] playSound failed', name, e);
    }
}

function speak(text) {
    if (!text || !window.speechSynthesis || typeof SpeechSynthesisUtterance === 'undefined') return;
    try {
        const u = new SpeechSynthesisUtterance(text);
        u.lang = 'en-US';
        u.rate = 1.0;
        u.pitch = 1.0;
        window.speechSynthesis.speak(u);
    } catch (e) {
        console.warn('[az_mdt] TTS failed', e);
    }
}

// ---------- helpers ----------

function safeParse(input, label) {
    if (input === undefined || input === null || input === '') return null;

    if (typeof input === 'object') {
        return input;
    }

    if (typeof input === 'string') {
        try {
            return JSON.parse(input);
        } catch (e) {
            console.error('[az_mdt] JSON parse failed for', label || 'data', input, e);
            return null;
        }
    }

    return input;
}

function nuiPost(name, data) {
    fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
        body: JSON.stringify(data || {})
    }).catch(err => {
        console.error('[az_mdt] NUI post failed', name, err);
    });
}

function showRoot() {
    if (!MDT.root) return;
    MDT.root.classList.remove('hidden');
}

function hideRoot() {
    if (!MDT.root) return;
    MDT.root.classList.add('hidden');
}

function setActivePage(id) {
    MDT.state.activePage = id;

    const pages = document.querySelectorAll('[data-mdt-page], .mdt-page');
    pages.forEach(page => {
        const pageId =
            page.dataset.mdtPage ||
            page.dataset.page ||
            (page.id && page.id.startsWith('page-') ? page.id.slice(5) : page.id);

        if (pageId === id) {
            page.classList.add('active');
        } else {
            page.classList.remove('active');
        }
    });

    const navButtons = document.querySelectorAll('[data-mdt-nav], [data-page]');
    navButtons.forEach(btn => {
        const navId = btn.dataset.mdtNav || btn.dataset.page;
        if (navId === id) {
            btn.classList.add('active');
        } else {
            btn.classList.remove('active');
        }
    });
}

function initialsFromName(name) {
    if (!name) return 'AZ';
    const parts = name.trim().split(/\s+/);
    if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

// ---------- admin UI ----------

function updateAdminUI() {
    const isAdmin = MDT.state.isAdmin;

    if (MDT.els.adminIndicator) {
        MDT.els.adminIndicator.style.display = isAdmin ? 'inline-flex' : 'none';
    }
    if (MDT.els.adminLoginRow) {
        MDT.els.adminLoginRow.classList.toggle('hidden', isAdmin);
    }
    if (MDT.els.adminActionsRow) {
        MDT.els.adminActionsRow.classList.toggle('hidden', !isAdmin);
    }

    if (MDT.els.iaLogList) {
        renderActionLog(MDT.state.actionLog);
    }
}

function statusLabel(code) {
    code = (code || 'AVAILABLE').toUpperCase();
    if (code === 'PANIC') return 'PANIC BUTTON';
    if (code === 'ENROUTE') return '10-8 ENROUTE';
    if (code === 'ONSCENE') return '10-8 ONSCENE';
    if (code === 'TRANSPORT') return '10-8 TRANSPORT';
    if (code === 'HOSPITAL') return '10-8 HOSPITAL';
    return '10-8 AVAILABLE';
}

function renderOfficer() {
    const o = MDT.state.officer || {};
    if (MDT.els.officerName) MDT.els.officerName.textContent = o.name || 'Unknown';
    if (MDT.els.officerMeta) {
        const dept = o.department || 'police';
        const grade = o.grade || 0;
        const status = MDT.state.status || 'AVAILABLE';
        MDT.els.officerMeta.textContent = `${dept} · ${grade} · ${status}`;
    }
    if (MDT.els.officerInitials) {
        MDT.els.officerInitials.textContent = initialsFromName(o.name);
    }
    if (MDT.els.statusBtn) {
        MDT.els.statusBtn.textContent = `Status: ${statusLabel(MDT.state.status)}`;
    }
    if (MDT.els.myStatus) {
        MDT.els.myStatus.textContent = statusLabel(MDT.state.status);
    }
}

// ---------- MODALS ----------

function showModal(type, ctx) {
    MDT.state.modalContext = { type, ...(ctx || {}) };
    if (!MDT.els.modalBackdrop) return;

    ['modalNote', 'modalFlags', 'modalWarrant'].forEach(key => {
        if (MDT.els[key]) MDT.els[key].classList.add('hidden');
    });

    if (type === 'note') {
        if (MDT.els.noteTarget) MDT.els.noteTarget.textContent = ctx.targetValue || '';
        if (MDT.els.noteText) MDT.els.noteText.value = '';
        MDT.els.modalNote && MDT.els.modalNote.classList.remove('hidden');
    } else if (type === 'flags') {
        if (MDT.els.flagsTarget) MDT.els.flagsTarget.textContent = ctx.targetValue || '';

        const flags = ctx.flags || {};
        if (MDT.els.flagOfficerSafety) MDT.els.flagOfficerSafety.checked = !!flags.officer_safety;
        if (MDT.els.flagArmed) MDT.els.flagArmed.checked = !!flags.armed;
        if (MDT.els.flagGang) MDT.els.flagGang.checked = !!flags.gang;
        if (MDT.els.flagMental) MDT.els.flagMental.checked = !!flags.mental_health;
        if (MDT.els.flagsNotes) MDT.els.flagsNotes.value = ctx.notes || '';

        MDT.els.modalFlags && MDT.els.modalFlags.classList.remove('hidden');
    } else if (type === 'warrant') {
        if (MDT.els.warrantName) MDT.els.warrantName.value = ctx.targetName || '';
        if (MDT.els.warrantCharid) MDT.els.warrantCharid.value = ctx.charid || '';
        if (MDT.els.warrantReason) MDT.els.warrantReason.value = '';
        MDT.els.modalWarrant && MDT.els.modalWarrant.classList.remove('hidden');
    }

    MDT.els.modalBackdrop.classList.remove('hidden');
}

function closeModal() {
    MDT.state.modalContext = null;
    if (!MDT.els.modalBackdrop) return;
    MDT.els.modalBackdrop.classList.add('hidden');
    if (MDT.els.modalNote) MDT.els.modalNote.classList.add('hidden');
    if (MDT.els.modalFlags) MDT.els.modalFlags.classList.add('hidden');
    if (MDT.els.modalWarrant) MDT.els.modalWarrant.classList.add('hidden');
}

// ---------- rendering ----------

// NAME SEARCH
function renderNameResults(payload) {
    const el = MDT.els.nameResults;
    if (!el) return;

    el.innerHTML = '';
    el.style.overflowY = 'auto';
    el.style.maxHeight = 'calc(100vh - 260px)';

    if (!payload || ((!payload.citizens || payload.citizens.length === 0) &&
        (!payload.records || payload.records.length === 0))) {
        el.innerHTML = '<div class="mdt-empty">No results.</div>';
        return;
    }

    if (payload.citizens && payload.citizens.length > 0) {
        const sectionHeader = document.createElement('div');
        sectionHeader.className = 'mdt-row-meta';
        sectionHeader.textContent = 'Characters';
        el.appendChild(sectionHeader);

        payload.citizens.forEach(c => {
            const row = document.createElement('div');
            row.className = 'mdt-row';

            const licenseStatus = c.license_status || c.license || 'Unknown';
            const mug = c.mugshot || '';
            const name = c.name || 'Unknown';
            const safeNameAttr = String(name).replace(/"/g, '&quot;');
            const lastSeen = c.last_seen || null;

            const flagsObj = (c.flags && c.flags.flags) || {};
            const flagLabels = [];
            if (flagsObj.officer_safety) flagLabels.push('Officer Safety');
            if (flagsObj.armed)          flagLabels.push('Armed & Dangerous');
            if (flagsObj.gang)           flagLabels.push('Gang Affiliation');
            if (flagsObj.mental_health)  flagLabels.push('Mental Health');

            const quickNotes = Array.isArray(c.quick_notes) ? c.quick_notes.slice(0, 2) : [];

            const flagsHtml = flagLabels.length
                ? `<div style="margin-top:4px;display:flex;flex-wrap:wrap;gap:4px;">
                        ${flagLabels.map(lbl => `<span class="mdt-row-tag">${lbl}</span>`).join('')}
                   </div>`
                : `<div style="margin-top:4px;font-size:11px;color:var(--text-muted);">No flags.</div>`;

            const notesHtml = quickNotes.length
                ? `<ul style="margin-top:4px;padding-left:16px;font-size:11px;color:var(--text-muted);">
                        ${quickNotes.map(n => `<li>${n.note}</li>`).join('')}
                   </ul>`
                : `<div style="margin-top:4px;font-size:11px;color:var(--text-muted);">No quick notes.</div>`;

            const lastSeenHtml = lastSeen
                ? `<div style="font-size:11px;">Last Seen: ${lastSeen}</div>`
                : `<div style="font-size:11px;">Last Seen: Unknown</div>`;

            const flagAttrs = `
                data-flags-officer-safety="${flagsObj.officer_safety ? '1' : '0'}"
                data-flags-armed="${flagsObj.armed ? '1' : '0'}"
                data-flags-gang="${flagsObj.gang ? '1' : '0'}"
                data-flags-mental="${flagsObj.mental_health ? '1' : '0'}"
            `;

            row.innerHTML = `
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${name}</div>
                    <span class="mdt-row-tag">${(c.active_department || 'Unknown').toUpperCase()}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>Char ID: ${c.charid || c.id || '—'}</span>
                    <span>License: ${licenseStatus}</span>
                    <span>Discord: ${c.discordid || '—'}</span>
                </div>
                <div class="mdt-row-body" style="display:flex;gap:10px;align-items:flex-start;">
                    ${mug ? `<img src="${mug}" alt="Mugshot" style="width:72px;height:72px;border-radius:10px;object-fit:cover;border:1px solid rgba(148,163,184,0.35);flex-shrink:0;">` : ''}
                    <div style="flex:1;font-size:12px;color:var(--text-muted);">
                        ${lastSeenHtml}
                        ${flagsHtml}
                        <div style="margin-top:4px;font-size:11px;font-weight:500;">Quick Notes:</div>
                        ${notesHtml}
                    </div>
                </div>
                <div class="mdt-row-actions" style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap;">
                    <button class="btn-xs btn-secondary"
                            data-report-type="citation"
                            data-target-type="name"
                            data-target-value="${safeNameAttr}">
                        New Ticket
                    </button>
                    <button class="btn-xs btn-secondary"
                            data-report-type="arrest"
                            data-target-type="name"
                            data-target-value="${safeNameAttr}">
                        New Arrest
                    </button>
                    <button class="btn-xs btn-secondary"
                            data-report-type="incident"
                            data-target-type="name"
                            data-target-value="${safeNameAttr}">
                        New Report
                    </button>
                    <button class="btn-xs btn-secondary"
                            data-quicknote-name="${safeNameAttr}">
                        Add Note
                    </button>
                    <button class="btn-xs btn-secondary"
                            data-flags-name="${safeNameAttr}"
                            ${flagAttrs}>
                        Flags
                    </button>
                    <button class="btn-xs btn-secondary"
                            data-warrant-name="${safeNameAttr}"
                            data-warrant-charid="${c.charid || ''}">
                        New Warrant
                    </button>
                </div>
            `;
            el.appendChild(row);
        });
    }

    if (payload.records && payload.records.length > 0) {
        const sectionHeader = document.createElement('div');
        sectionHeader.className = 'mdt-row-meta';
        sectionHeader.style.marginTop = '6px';
        sectionHeader.textContent = 'Associated Records';
        el.appendChild(sectionHeader);

        payload.records.forEach(rec => {
            const row = document.createElement('div');
            row.className = 'mdt-row';

            const title = rec.title || rec.rtype || 'Record';
            const ts = rec.timestamp || rec.created_at || '';
            const body = (rec.description || rec.body || rec.notes || '').replace(/\n/g, '<br>');

            row.innerHTML = `
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${title}</div>
                    <span class="mdt-row-tag">${(rec.rtype || rec.type || 'record').toUpperCase()}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>${rec.target_value || ''}</span>
                    <span>${ts}</span>
                    <span>#${rec.id || ''}</span>
                </div>
                <div class="mdt-row-body">${body}</div>
            `;
            el.appendChild(row);
        });
    }
}

// PLATE / VEHICLE RESULTS
function renderPlateResults(payload) {
    const el = MDT.els.plateResults;
    if (!el) return;

    el.innerHTML = '';

    if (!payload || ((!payload.vehicles || payload.vehicles.length === 0) &&
        (!payload.records || payload.records.length === 0))) {
        el.innerHTML = '<div class="mdt-empty">No results.</div>';
        return;
    }

    if (payload.vehicles && payload.vehicles.length > 0) {
        const sectionHeader = document.createElement('div');
        sectionHeader.className = 'mdt-row-meta';
        sectionHeader.textContent = 'Vehicles';
        el.appendChild(sectionHeader);

        payload.vehicles.forEach(v => {
            const row = document.createElement('div');
            row.className = 'mdt-row';

            const plate = v.plate || '—';
            const owner = v.owner_name || v.ownerName || v.discordid || 'Unknown';
            const model = v.model || 'Unknown';
            const policy = v.policy_type || 'none';
            const policyText = policy ? `${policy.toUpperCase()} (${v.active ? 'Active' : 'Inactive'})` : 'None';

            const safePlate = String(plate).replace(/"/g, '&quot;');

            row.innerHTML = `
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${plate}</div>
                    <span class="mdt-row-tag">${policyText}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>Model: ${model}</span>
                    <span>Owner: ${owner}</span>
                    <span>Discord: ${v.discordid || '—'}</span>
                </div>
                <div class="mdt-row-actions" style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap;">
                    <button class="btn-xs btn-secondary"
                            data-report-type="citation"
                            data-target-type="plate"
                            data-target-value="${safePlate}">
                        New Ticket
                    </button>
                    <button class="btn-xs btn-secondary"
                            data-report-type="arrest"
                            data-target-type="plate"
                            data-target-value="${safePlate}">
                        New Arrest
                    </button>
                    <button class="btn-xs btn-secondary"
                            data-report-type="incident"
                            data-target-type="plate"
                            data-target-value="${safePlate}">
                        New Report
                    </button>
                </div>
            `;
            el.appendChild(row);
        });
    }

    if (payload.records && payload.records.length > 0) {
        const sectionHeader = document.createElement('div');
        sectionHeader.className = 'mdt-row-meta';
        sectionHeader.style.marginTop = '6px';
        sectionHeader.textContent = 'Associated Records';
        el.appendChild(sectionHeader);

        payload.records.forEach(rec => {
            const row = document.createElement('div');
            row.className = 'mdt-row';

            const title = rec.title || rec.rtype || 'Record';
            const ts = rec.timestamp || rec.created_at || '';
            const body = (rec.description || rec.body || rec.notes || '').replace(/\n/g, '<br>');

            row.innerHTML = `
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${title}</div>
                    <span class="mdt-row-tag">${(rec.rtype || rec.type || 'record').toUpperCase()}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>${rec.target_value || ''}</span>
                    <span>${ts}</span>
                    <span>#${rec.id || ''}</span>
                </div>
                <div class="mdt-row-body">${body}</div>
            `;
            el.appendChild(row);
        });
    }
}

// WEAPON RESULTS
function renderWeaponResults(payload) {
    const el = MDT.els.weaponResults;
    if (!el) return;

    el.innerHTML = '';

    if (!payload || ((!payload.weapons || payload.weapons.length === 0) &&
        (!payload.records || payload.records.length === 0))) {
        el.innerHTML = '<div class="mdt-empty">No results.</div>';
        return;
    }

    if (payload.weapons && payload.weapons.length > 0) {
        const sectionHeader = document.createElement('div');
        sectionHeader.className = 'mdt-row-meta';
        sectionHeader.textContent = 'Weapons';
        el.appendChild(sectionHeader);

        payload.weapons.forEach(w => {
            const row = document.createElement('div');
            row.className = 'mdt-row';

            const serial = w.serial || w.serial_number || '—';
            const owner = w.owner || w.owner_name || w.discordid || 'Unknown';
            const wtype = w.type || 'Weapon';

            row.innerHTML = `
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${serial}</div>
                    <span class="mdt-row-tag">${wtype.toUpperCase()}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>Owner: ${owner}</span>
                </div>
            `;
            el.appendChild(row);
        });
    }

    if (payload.records && payload.records.length > 0) {
        const sectionHeader = document.createElement('div');
        sectionHeader.className = 'mdt-row-meta';
        sectionHeader.style.marginTop = '6px';
        sectionHeader.textContent = 'Associated Records';
        el.appendChild(sectionHeader);

        payload.records.forEach(rec => {
            const row = document.createElement('div');
            row.className = 'mdt-row';

            const title = rec.title || rec.rtype || 'Record';
            const ts = rec.timestamp || rec.created_at || '';
            const body = (rec.description || rec.body || rec.notes || '').replace(/\n/g, '<br>');

            row.innerHTML = `
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${title}</div>
                    <span class="mdt-row-tag">${(rec.rtype || rec.type || 'record').toUpperCase()}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>${rec.target_value || ''}</span>
                    <span>${ts}</span>
                    <span>#${rec.id || ''}</span>
                </div>
                <div class="mdt-row-body">${body}</div>
            `;
            el.appendChild(row);
        });
    }
}

function renderBolos(list) {
    const container = MDT.els.boloList;
    if (!container) return;

    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No active BOLOs.</div>';
        return;
    }

    list.forEach(row => {
        const body = row.body || safeParse(row.data, 'boloRow') || {};
        const details = body.details || body.description || '';
        const ts = row.created_at || row.timestamp || '';

        let adminControls = '';
        if (MDT.state.isAdmin && row.id) {
            adminControls = `
                <div class="mdt-row-actions" style="margin-top:6px;display:flex;gap:6px;flex-wrap:wrap;">
                    <button class="btn-xs btn-danger"
                            data-admin-action="delete-bolo"
                            data-bolo-id="${row.id}">
                        Delete BOLO
                    </button>
                </div>
            `;
        }

        const div = document.createElement('div');
        div.className = 'mdt-row';

        div.innerHTML = `
            <div class="mdt-row-header">
                <div class="mdt-row-title">${body.title || row.title || 'BOLO'}</div>
                <span class="mdt-row-tag">${(row.type || body.type || 'VEHICLE').toUpperCase()}</span>
            </div>
            <div class="mdt-row-meta">
                <span>#${row.id || '—'}</span>
                <span>${ts}</span>
            </div>
            <div class="mdt-row-body">${String(details).replace(/\n/g, '<br>')}</div>
            ${adminControls}
        `;
        container.appendChild(div);
    });
}

function renderDashboardBolos(list) {
    const container = MDT.els.dashboardBolos;
    if (!container) return;

    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No active BOLOs.</div>';
        return;
    }

    list.slice(0, 3).forEach(row => {
        const body = row.body || {};
        const details = body.details || '';
        const ts = row.created_at || '';

        const div = document.createElement('div');
        div.className = 'mdt-row';

        div.innerHTML = `
            <div class="mdt-row-header">
                <div class="mdt-row-title">${body.title || 'BOLO'}</div>
                <span class="mdt-row-tag">${(row.type || 'VEHICLE').toUpperCase()}</span>
            </div>
            <div class="mdt-row-meta">
                <span>#${row.id || '—'}</span>
                <span>${ts}</span>
            </div>
            <div class="mdt-row-body">${String(details).replace(/\n/g, '<br>')}</div>
        `;
        container.appendChild(div);
    });
}

function renderReports(list) {
    const container = MDT.els.reportList;
    if (!container) return;

    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No reports.</div>';
        return;
    }

    list.forEach(row => {
        const body = row.body || safeParse(row.data, 'reportRow') || {};
        const ts = row.created_at || row.timestamp || '';

        let adminControls = '';
        if (MDT.state.isAdmin && row.id) {
            adminControls = `
                <div class="mdt-row-actions" style="margin-top:6px;display:flex;gap:6px;flex-wrap:wrap;">
                    <button class="btn-xs btn-danger"
                            data-admin-action="delete-report"
                            data-report-id="${row.id}">
                        Delete Report
                    </button>
                </div>
            `;
        }

        const div = document.createElement('div');
        div.className = 'mdt-row';

        div.innerHTML = `
            <div class="mdt-row-header">
                <div class="mdt-row-title">${body.title || row.title || 'Report'}</div>
                <span class="mdt-row-tag">${(row.type || 'incident').toUpperCase()}</span>
            </div>
            <div class="mdt-row-meta">
                <span>#${row.id || '—'}</span>
                <span>${ts}</span>
                <span>Officer: ${body.officer || 'Unknown'}</span>
            </div>
            <div class="mdt-row-body">${String(body.info || body.body || '').replace(/\n/g, '<br>')}</div>
            ${adminControls}
        `;
        container.appendChild(div);
    });
}

function renderEmployees(list) {
    const container = MDT.els.employeeList;
    if (!container) return;

    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No employees found.</div>';
        return;
    }

    list.forEach(row => {
        const div = document.createElement('div');
        div.className = 'mdt-row';

        let adminControls = '';
        if (MDT.state.isAdmin && row.id && (row.active_department || row.department)) {
            adminControls = `
                <div class="mdt-row-actions" style="margin-top:6px;display:flex;gap:6px;flex-wrap:wrap;">
                    <button class="btn-xs btn-danger"
                            data-admin-action="delete-employee"
                            data-employee-id="${row.id}"
                            data-employee-dept="${row.active_department || row.department}">
                        Remove From Dept
                    </button>
                </div>
            `;
        }

        div.innerHTML = `
            <div class="mdt-row-header">
                <div class="mdt-row-title">${row.name || 'Unknown'}</div>
                <span class="mdt-row-tag">${(row.active_department || row.department || 'police').toUpperCase()}</span>
            </div>
            <div class="mdt-row-meta">
                <span>Char ID: ${row.charid || row.id || '—'}</span>
                <span>Callsign: ${row.callsign || '—'}</span>
                <span>Grade: ${row.paycheck || row.grade || '—'}</span>
            </div>
            ${adminControls}
        `;
        container.appendChild(div);
    });
}

function renderUnits(list) {
    const container = MDT.els.unitsList;
    if (!container) return;

    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No active units.</div>';
        return;
    }

    list.forEach(u => {
        const div = document.createElement('div');
        div.className = 'mdt-row';

        div.innerHTML = `
            <div class="mdt-row-header">
                <div class="mdt-row-title">${u.name || ('Unit ' + (u.id || ''))}</div>
                <span class="mdt-row-tag">${(u.department || 'police').toUpperCase()}</span>
            </div>
            <div class="mdt-row-meta">
                <span>Callsign: ${u.callsign || '—'}</span>
                <span>Status: ${u.status || 'AVAILABLE'}</span>
            </div>
        `;
        container.appendChild(div);
    });
}

function renderCalls(list) {
    const container = MDT.els.callsList;
    if (!container) return;

    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No active 911 calls.</div>';
        return;
    }

    list.forEach(c => {
        const div = document.createElement('div');
        div.className = 'mdt-row';

        const units = (c.units || []).map(u => u.callsign || u.name || u.id).join(', ');

        let adminButton = '';
        if (MDT.state.isAdmin && c.id) {
            adminButton = `
                <button class="btn-xs btn-danger"
                        data-admin-action="delete-call"
                        data-call-id="${c.id}">
                    Clear Call
                </button>
            `;
        }

        div.innerHTML = `
            <div class="mdt-row-header">
                <div class="mdt-row-title">#${c.id} – ${c.location || 'Unknown location'}</div>
                <span class="mdt-row-tag">${(c.status || 'PENDING').toUpperCase()}</span>
            </div>
            <div class="mdt-row-meta">
                <span>Caller: ${c.caller || 'Unknown'}</span>
                <span>Units: ${units || 'None'}</span>
                <span>${c.created_at || ''}</span>
            </div>
            <div class="mdt-row-body">${String(c.message || '').replace(/\n/g, '<br>')}</div>
            <div class="mdt-row-actions">
                <button class="btn-xs btn-primary" data-call-action="attach" data-call-id="${c.id}">Attach</button>
                <button class="btn-xs btn-secondary" data-call-action="waypoint" data-call-id="${c.id}">Waypoint</button>
                ${adminButton}
            </div>
        `;
        container.appendChild(div);
    });
}

function renderChat() {
    const container = MDT.els.chatMessages;
    if (!container) return;

    container.innerHTML = '';

    MDT.state.chat.forEach(msg => {
        const div = document.createElement('div');
        div.className = 'chat-line';

        const me = (MDT.state.officer && msg.source === MDT.state.officer.callsign);
        const bubbleClass = me ? 'chat-bubble me' : 'chat-bubble';

        div.innerHTML = `
            <div class="chat-meta">${msg.sender || 'Unknown'} · ${msg.time || ''}</div>
            <div class="${bubbleClass}">${String(msg.message || '').replace(/\n/g, '<br>')}</div>
        `;
        container.appendChild(div);
    });

    container.scrollTop = container.scrollHeight;
}

function renderWarrants(list) {
    const container = MDT.els.warrantsList;
    if (!container) return;

    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No warrants.</div>';
        return;
    }

    list.forEach(w => {
        const div = document.createElement('div');
        div.className = 'mdt-row';

        const meta = `${w.created_by || 'Unknown'} · ${w.created_at || ''}`;
        const status = (w.status || 'active').toUpperCase();

        div.innerHTML = `
            <div class="mdt-row-header">
                <div class="mdt-row-title">${w.target_name || 'Unknown'}</div>
                <span class="mdt-row-tag">${status}</span>
            </div>
            <div class="mdt-row-meta">
                <span>Char ID: ${w.target_charid || '—'}</span>
                <span>${meta}</span>
                <span>#${w.id || ''}</span>
            </div>
            <div class="mdt-row-body">${String(w.reason || '').replace(/\n/g, '<br>')}</div>
        `;
        container.appendChild(div);
    });
}

function renderActionLog(list) {
    const container = MDT.els.iaLogList;
    if (!container) return;

    if (!MDT.state.isAdmin) {
        container.innerHTML = '<div class="mdt-empty">Enter admin mode to view Internal Affairs logs.</div>';
        return;
    }

    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No logged actions.</div>';
        return;
    }

    list.forEach(row => {
        const div = document.createElement('div');
        div.className = 'mdt-row';

        const metaStr = row.meta && Object.keys(row.meta).length
            ? JSON.stringify(row.meta)
            : '';

        div.innerHTML = `
            <div class="mdt-row-header">
                <div class="mdt-row-title">${row.action || 'action'}</div>
                <span class="mdt-row-tag">${row.officer_name || 'Unknown'}</span>
            </div>
            <div class="mdt-row-meta">
                <span>${row.created_at || ''}</span>
                <span>Target: ${row.target || '—'}</span>
                <span>Discord: ${row.officer_discord || '—'}</span>
            </div>
            <div class="mdt-row-body" style="font-size:11px;color:var(--text-muted);">
                ${metaStr}
            </div>
        `;
        container.appendChild(div);
    });
}

// ---------- incoming messages from Lua ----------

window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (!msg.action) return;

    console.log('[az_mdt] NUI message', msg.action, msg);

    switch (msg.action) {
        case 'open':
        case 'openMDT':
        case 'mdt:open': {
            MDT.state.officer = safeParse(msg.officer, 'officer') || msg.officer || {};
            MDT.state.status = MDT.state.officer.status || 'AVAILABLE';
            renderOfficer();
            showRoot();
            setActivePage('dashboard');

            nuiPost('GetBolos', {});
            nuiPost('GetReports', {});
            nuiPost('GetUnits', {});
            nuiPost('GetCalls', {});
            nuiPost('GetWarrants', {});
            nuiPost('GetActionLog', {});
            nuiPost('RequestChatHistory', {});
            break;
        }

        case 'close':
        case 'closeMDT':
        case 'mdt:close': {
            hideRoot();
            break;
        }

        case 'nameResults':
        case 'NameSearchResults': {
            const payload = safeParse(msg.data, 'nameResults') || msg.data;
            MDT.state.nameResults = payload || {};
            renderNameResults(payload);
            setActivePage('nameSearch');
            break;
        }

        case 'plateResults':
        case 'PlateSearchResults': {
            const payload = safeParse(msg.data, 'plateResults') || msg.data;
            MDT.state.plateResults = payload || {};
            renderPlateResults(payload);
            setActivePage('plateSearch');
            break;
        }

        case 'weaponResults':
        case 'WeaponSearchResults': {
            const payload = safeParse(msg.data, 'weaponResults') || msg.data;
            MDT.state.weaponResults = payload || {};
            renderWeaponResults(payload);
            setActivePage('weaponSearch');
            break;
        }

        case 'boloList': {
            const list = safeParse(msg.data, 'boloList') || msg.data || [];
            MDT.state.bolos = list;
            renderBolos(list);
            renderDashboardBolos(list);
            break;
        }

        case 'boloCreated': {
            const bolo = safeParse(msg.data, 'boloCreated') || msg.data;
            if (bolo) {
                MDT.state.bolos.push(bolo);
                renderBolos(MDT.state.bolos);
                renderDashboardBolos(MDT.state.bolos);

                playSound('bolo');
                const title = (bolo.body && bolo.body.title) || bolo.title || 'BOLO';
                speak(`New BOLO created: ${title}.`);
            }
            break;
        }

        case 'reportList': {
            const list = safeParse(msg.data, 'reportList') || msg.data || [];
            MDT.state.reports = list;
            renderReports(list);
            break;
        }

        case 'reportCreated': {
            const rep = safeParse(msg.data, 'reportCreated') || msg.data;
            if (rep) {
                MDT.state.reports.push(rep);
                renderReports(MDT.state.reports);
            }
            break;
        }

        case 'employeesList': {
            const list = safeParse(msg.data, 'employeesList') || msg.data || [];
            MDT.state.employees = list;
            renderEmployees(list);
            break;
        }

        case 'unitsUpdate': {
            const list = safeParse(msg.data, 'unitsUpdate') || msg.data || [];
            MDT.state.units = list;
            renderUnits(list);
            break;
        }

        case 'callList': {
            const list = safeParse(msg.data, 'callList') || msg.data || [];
            MDT.state.calls = list;
            renderCalls(list);
            break;
        }

        case 'callCreated':
        case 'callUpdated': {
            const call = safeParse(msg.data, 'callUpdated') ||
                         safeParse(msg.data, 'callCreated') ||
                         msg.data;
            if (call && call.id) {
                const idx = MDT.state.calls.findIndex(c => c.id === call.id);
                if (idx >= 0) MDT.state.calls[idx] = call;
                else MDT.state.calls.push(call);
                renderCalls(MDT.state.calls);

                const isPending = (call.status || 'PENDING').toUpperCase() === 'PENDING';
                if (isPending && !MDT.state.seenCalls[call.id]) {
                    MDT.state.seenCalls[call.id] = true;
                    playSound('call');
                    const loc = call.location || 'unknown location';
                    speak(`New nine one one call at ${loc}.`);
                }
            }
            break;
        }

        case 'liveChatHistory': {
            const list = safeParse(msg.data, 'liveChatHistory') || msg.data || [];
            MDT.state.chat = list;
            renderChat();
            break;
        }

        case 'liveChatMessage': {
            const msgObj = safeParse(msg.data, 'liveChatMessage') || msg.data;
            if (msgObj) {
                MDT.state.chat.push(msgObj);
                renderChat();
            }
            break;
        }

        case 'panic': {
            const panic = safeParse(msg.data, 'panic') || msg.data || {};
            playSound('panic');
            const name = panic.officer || panic.callsign || 'an officer';
            speak(`Panic button activated by ${name}.`);
            break;
        }

        case 'statusUpdate': {
            const status = msg.status || 'AVAILABLE';
            MDT.state.status = status;
            renderOfficer();
            break;
        }

        case 'warrantsList': {
            const list = safeParse(msg.data, 'warrantsList') || msg.data || [];
            MDT.state.warrants = list;
            renderWarrants(list);
            break;
        }

        case 'actionLog': {
            const list = safeParse(msg.data, 'actionLog') || msg.data || [];
            MDT.state.actionLog = list;
            renderActionLog(list);
            break;
        }

        default:
            break;
    }
});

// ---------- DOM wiring ----------

document.addEventListener('DOMContentLoaded', () => {
    MDT.root     = document.getElementById('mdt-wrapper');
    MDT.windowEl = document.querySelector('.mdt-window');

    initAudio();

    MDT.els.officerName     = document.getElementById('mdt-user-name');
    MDT.els.officerMeta     = document.getElementById('mdt-user-meta');
    MDT.els.officerInitials = document.querySelector('.mdt-user-initials');
    MDT.els.myStatus        = document.getElementById('mdt-my-status');

    MDT.els.statusBtn   = document.getElementById('mdt-status-btn');
    MDT.els.panicBtn    = document.getElementById('mdt-panic-btn');
    MDT.els.exitBtn     = document.getElementById('mdt-close-btn');
    MDT.els.hospitalBtn = null;

    MDT.els.nameForm    = document.getElementById('name-search-form');
    MDT.els.nameFirst   = document.getElementById('first-name-input');
    MDT.els.nameLast    = document.getElementById('last-name-input');
    MDT.els.nameResults = document.getElementById('name-search-results');

    MDT.els.plateForm    = document.getElementById('plate-search-form');
    MDT.els.plateInput   = document.getElementById('plate-input');
    MDT.els.plateResults = document.getElementById('plate-search-results');

    MDT.els.weaponForm    = document.getElementById('weapon-search-form');
    MDT.els.weaponInput   = document.getElementById('weapon-serial-input');
    MDT.els.weaponResults = document.getElementById('weapon-search-results');

    MDT.els.boloForm    = document.getElementById('bolo-form');
    MDT.els.boloTitle   = document.getElementById('bolo-title');
    MDT.els.boloType    = document.getElementById('bolo-type');
    MDT.els.boloDetails = document.getElementById('bolo-details');
    MDT.els.boloList    = document.getElementById('bolo-list');

    MDT.els.reportForm  = document.getElementById('report-form');
    MDT.els.reportTitle = document.getElementById('report-title');
    MDT.els.reportType  = document.getElementById('report-type');
    MDT.els.reportBody  = document.getElementById('report-body');
    MDT.els.reportList  = document.getElementById('report-list');

    MDT.els.employeeList     = document.getElementById('employee-list');
    MDT.els.adminIndicator   = document.getElementById('admin-mode-indicator');
    MDT.els.adminLoginRow    = document.getElementById('admin-login-row');
    MDT.els.adminLoginForm   = document.getElementById('admin-login-form');
    MDT.els.adminPassword    = document.getElementById('admin-password-input');
    MDT.els.adminLoginError  = document.getElementById('admin-login-error');
    MDT.els.adminActionsRow  = document.getElementById('admin-actions-row');
    MDT.els.adminExitButton  = document.getElementById('admin-exit-admin');

    MDT.els.unitsList      = document.getElementById('mdt-units-list');
    MDT.els.callsList      = document.getElementById('mdt-calls-list');
    MDT.els.dashboardBolos = document.getElementById('mdt-dashboard-bolos');

    MDT.els.chatForm     = document.getElementById('livechat-form');
    MDT.els.chatMessages = document.getElementById('livechat-messages');
    MDT.els.chatInput    = document.getElementById('livechat-input');

    MDT.els.warrantsList = document.getElementById('warrants-list');
    MDT.els.iaLogList    = document.getElementById('ia-log-list');

    MDT.els.modalBackdrop = document.getElementById('mdt-modal-backdrop');
    MDT.els.modalNote     = document.getElementById('mdt-modal-note');
    MDT.els.modalFlags    = document.getElementById('mdt-modal-flags');
    MDT.els.modalWarrant  = document.getElementById('mdt-modal-warrant');

    MDT.els.noteTarget = document.getElementById('mdt-note-target');
    MDT.els.noteForm   = document.getElementById('mdt-note-form');
    MDT.els.noteText   = document.getElementById('mdt-note-text');
    MDT.els.noteCancel = document.getElementById('mdt-note-cancel');

    MDT.els.flagsTarget       = document.getElementById('mdt-flags-target');
    MDT.els.flagsForm         = document.getElementById('mdt-flags-form');
    MDT.els.flagOfficerSafety = document.getElementById('mdt-flag-officer-safety');
    MDT.els.flagArmed         = document.getElementById('mdt-flag-armed');
    MDT.els.flagGang          = document.getElementById('mdt-flag-gang');
    MDT.els.flagMental        = document.getElementById('mdt-flag-mental');
    MDT.els.flagsNotes        = document.getElementById('mdt-flags-notes');
    MDT.els.flagsCancel       = document.getElementById('mdt-flags-cancel');

    MDT.els.warrantForm   = document.getElementById('mdt-warrant-form');
    MDT.els.warrantName   = document.getElementById('mdt-warrant-name');
    MDT.els.warrantCharid = document.getElementById('mdt-warrant-charid');
    MDT.els.warrantReason = document.getElementById('mdt-warrant-reason');
    MDT.els.warrantCancel = document.getElementById('mdt-warrant-cancel');

    hideRoot();
    updateAdminUI();

    document.querySelectorAll('[data-page], [data-mdt-nav]').forEach(btn => {
        btn.addEventListener('click', () => {
            const section = btn.dataset.page || btn.dataset.mdtNav;
            if (!section) return;

            setActivePage(section);

            if (section === 'bolos') {
                nuiPost('GetBolos', {});
            } else if (section === 'reports') {
                nuiPost('GetReports', {});
            } else if (section === 'employees') {
                nuiPost('ViewEmployees', {});
            } else if (section === 'dashboard') {
                nuiPost('GetUnits', {});
                nuiPost('GetCalls', {});
            } else if (section === 'warrants') {
                nuiPost('GetWarrants', {});
            } else if (section === 'iaLogs') {
                nuiPost('GetActionLog', {});
            } else if (section === 'livechat') {
                nuiPost('RequestChatHistory', {});
            }
        });
    });

    if (MDT.els.nameForm) {
        MDT.els.nameForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const first = (MDT.els.nameFirst?.value || '').trim();
            const last  = (MDT.els.nameLast?.value || '').trim();

            nuiPost('NameSearch', {
                first,
                last,
                term: `${first} ${last}`.trim()
            });
        });
    }

    if (MDT.els.nameResults) {
        MDT.els.nameResults.addEventListener('click', (ev) => {
            const noteBtn = ev.target.closest('[data-quicknote-name]');
            if (noteBtn) {
                const targetValue = noteBtn.dataset.quicknoteName || '';
                if (!targetValue) return;

                showModal('note', {
                    targetType: 'name',
                    targetValue
                });
                return;
            }

            const flagsBtn = ev.target.closest('[data-flags-name]');
            if (flagsBtn) {
                const targetValue = flagsBtn.dataset.flagsName || '';
                if (!targetValue) return;

                const flags = {
                    officer_safety: flagsBtn.dataset.flagsOfficerSafety === '1',
                    armed:          flagsBtn.dataset.flagsArmed === '1',
                    gang:           flagsBtn.dataset.flagsGang === '1',
                    mental_health:  flagsBtn.dataset.flagsMental === '1'
                };

                showModal('flags', {
                    targetType: 'name',
                    targetValue,
                    flags
                });
                return;
            }

            const warrantBtn = ev.target.closest('[data-warrant-name]');
            if (warrantBtn) {
                const targetName = warrantBtn.dataset.warrantName || '';
                const charid     = warrantBtn.dataset.warrantCharid || '';
                if (!targetName) return;

                showModal('warrant', {
                    targetName,
                    charid
                });
                return;
            }

            const btn = ev.target.closest('[data-report-type]');
            if (!btn) return;

            const type       = (btn.dataset.reportType || 'incident').toLowerCase();
            const value      = btn.dataset.targetValue || '';
            const targetType = btn.dataset.targetType || 'name';

            MDT.state.recordTarget = {
                type: targetType,
                value
            };

            setActivePage('reports');

            if (MDT.els.reportType) {
                MDT.els.reportType.value = type;
            }

            let titlePrefix = 'Report';
            if (type === 'citation') titlePrefix = 'Citation';
            else if (type === 'arrest') titlePrefix = 'Arrest';

            if (MDT.els.reportTitle) {
                MDT.els.reportTitle.value = value
                    ? `${titlePrefix} – ${value}`
                    : `${titlePrefix}`;
            }

            if (MDT.els.reportBody && value) {
                MDT.els.reportBody.value = `${value}\n\n`;
            }
        });
    }

    if (MDT.els.plateResults) {
        MDT.els.plateResults.addEventListener('click', (ev) => {
            const btn = ev.target.closest('[data-report-type]');
            if (!btn) return;

            const type = (btn.dataset.reportType || 'incident').toLowerCase();
            const value = btn.dataset.targetValue || '';
            const targetType = btn.dataset.targetType || 'plate';

            MDT.state.recordTarget = {
                type: targetType,
                value
            };

            setActivePage('reports');

            if (MDT.els.reportType) {
                MDT.els.reportType.value = type;
            }

            let titlePrefix = 'Report';
            if (type === 'citation') titlePrefix = 'Citation';
            else if (type === 'arrest') titlePrefix = 'Arrest';

            if (MDT.els.reportTitle) {
                MDT.els.reportTitle.value = value
                    ? `${titlePrefix} – ${value}`
                    : `${titlePrefix}`;
            }

            if (MDT.els.reportBody && value) {
                MDT.els.reportBody.value = `${value}\n\n`;
            }
        });
    }

    if (MDT.els.plateForm) {
        MDT.els.plateForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const plate = (MDT.els.plateInput?.value || '').trim();
            nuiPost('PlateSearch', { plate });
        });
    }

    if (MDT.els.weaponForm) {
        MDT.els.weaponForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const serial = (MDT.els.weaponInput?.value || '').trim();
            nuiPost('WeaponSearch', { serial });
        });
    }

    if (MDT.els.boloForm) {
        MDT.els.boloForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const title   = (MDT.els.boloTitle?.value || '').trim();
            const type    = (MDT.els.boloType?.value || '').trim() || 'vehicle';
            const details = (MDT.els.boloDetails?.value || '').trim();

            if (!title && !details) return;

            nuiPost('CreateBolo', { title, type, details });

            MDT.els.boloTitle.value   = '';
            MDT.els.boloDetails.value = '';
        });
    }

    if (MDT.els.reportForm) {
        MDT.els.reportForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const title = (MDT.els.reportTitle?.value || '').trim();
            const type  = (MDT.els.reportType?.value || '').trim() || 'incident';
            const body  = (MDT.els.reportBody?.value || '').trim();

            if (!title && !body) return;

            const target = MDT.state.recordTarget || {};
            nuiPost('CreateReport', {
                title,
                type,
                info: body,
                body,
                targetType: target.type || '',
                targetValue: target.value || ''
            });

            MDT.els.reportTitle.value = '';
            MDT.els.reportBody.value  = '';
            MDT.state.recordTarget    = null;
        });
    }

    if (MDT.els.chatForm) {
        MDT.els.chatForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const text = (MDT.els.chatInput?.value || '').trim();
            if (!text) return;

            nuiPost('LiveChatSend', { message: text });
            MDT.els.chatInput.value = '';
        });
    }

    if (MDT.els.callsList) {
        MDT.els.callsList.addEventListener('click', (ev) => {
            const btn = ev.target.closest('[data-call-action]');
            if (!btn) return;
            const id = parseInt(btn.dataset.callId, 10);
            if (!id) return;

            const action = btn.dataset.callAction;
            if (action === 'attach') {
                nuiPost('AttachCall', { id });
            } else if (action === 'waypoint') {
                nuiPost('CallWaypoint', { id });
            }
        });
    }

    const statusCycle = ['AVAILABLE', 'ENROUTE', 'ONSCENE', 'TRANSPORT', 'HOSPITAL'];
    if (MDT.els.statusBtn) {
        MDT.els.statusBtn.addEventListener('click', () => {
            const cur = (MDT.state.status || 'AVAILABLE').toUpperCase();
            const idx = statusCycle.indexOf(cur);
            const next = statusCycle[(idx + 1) % statusCycle.length];
            MDT.state.status = next;
            renderOfficer();
            nuiPost('SetUnitStatus', { status: next });
        });
    }

    if (MDT.els.panicBtn) {
        MDT.els.panicBtn.addEventListener('click', () => {
            nuiPost('Panic', {});
        });
    }

    if (MDT.els.hospitalBtn) {
        MDT.els.hospitalBtn.addEventListener('click', () => {
            nuiPost('Hospital', {});
        });
    }

    if (MDT.els.exitBtn) {
        MDT.els.exitBtn.addEventListener('click', () => {
            nuiPost('close', {});
        });
    }

    if (MDT.els.adminLoginForm) {
        MDT.els.adminLoginForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const entered = (MDT.els.adminPassword?.value || '').trim();
            const expected = AZ_MDT_CONFIG.adminPassword || 'changeme';
            if (!entered) return;

            if (entered === expected) {
                MDT.state.isAdmin = true;
                MDT.els.adminPassword.value = '';
                if (MDT.els.adminLoginError) MDT.els.adminLoginError.textContent = '';
                updateAdminUI();
                renderBolos(MDT.state.bolos);
                renderReports(MDT.state.reports);
                renderEmployees(MDT.state.employees);
                renderCalls(MDT.state.calls);
                renderActionLog(MDT.state.actionLog);
                speak('MDT admin mode enabled.');
            } else {
                if (MDT.els.adminLoginError) {
                    MDT.els.adminLoginError.textContent = 'Incorrect admin password.';
                }
                playSound('panic');
            }
        });
    }

    if (MDT.els.adminExitButton) {
        MDT.els.adminExitButton.addEventListener('click', (e) => {
            e.preventDefault();
            MDT.state.isAdmin = false;
            updateAdminUI();
            renderBolos(MDT.state.bolos);
            renderReports(MDT.state.reports);
            renderEmployees(MDT.state.employees);
            renderCalls(MDT.state.calls);
            renderActionLog(MDT.state.actionLog);
            speak('MDT admin mode disabled.');
        });
    }

    if (MDT.els.noteForm) {
        MDT.els.noteForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const ctx = MDT.state.modalContext || {};
            if (ctx.type !== 'note') return;

            const targetType  = ctx.targetType || 'name';
            const targetValue = ctx.targetValue || '';
            const note        = (MDT.els.noteText?.value || '').trim();

            if (!targetValue || !note) return;

            nuiPost('CreateQuickNote', {
                targetType,
                targetValue,
                note
            });

            const parts = targetValue.split(' ');
            const first = parts[0] || '';
            const last  = parts.slice(1).join(' ');
            nuiPost('NameSearch', { first, last, term: targetValue });

            speak(`Quick note added for ${targetValue}.`);
            closeModal();
        });
    }

    if (MDT.els.noteCancel) {
        MDT.els.noteCancel.addEventListener('click', (e) => {
            e.preventDefault();
            closeModal();
        });
    }

    if (MDT.els.flagsForm) {
        MDT.els.flagsForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const ctx = MDT.state.modalContext || {};
            if (ctx.type !== 'flags') return;

            const targetType  = ctx.targetType || 'name';
            const targetValue = ctx.targetValue || '';
            if (!targetValue) return;

            const flags = {
                officer_safety: !!(MDT.els.flagOfficerSafety && MDT.els.flagOfficerSafety.checked),
                armed:          !!(MDT.els.flagArmed && MDT.els.flagArmed.checked),
                gang:           !!(MDT.els.flagGang && MDT.els.flagGang.checked),
                mental_health:  !!(MDT.els.flagMental && MDT.els.flagMental.checked)
            };
            const notes = (MDT.els.flagsNotes?.value || '').trim();

            nuiPost('SetIdentityFlags', {
                targetType,
                targetValue,
                flags,
                notes
            });

            const parts = targetValue.split(' ');
            const first = parts[0] || '';
            const last  = parts.slice(1).join(' ');
            nuiPost('NameSearch', { first, last, term: targetValue });

            speak(`Flags updated for ${targetValue}.`);
            closeModal();
        });
    }

    if (MDT.els.flagsCancel) {
        MDT.els.flagsCancel.addEventListener('click', (e) => {
            e.preventDefault();
            closeModal();
        });
    }

    if (MDT.els.warrantForm) {
        MDT.els.warrantForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const ctx = MDT.state.modalContext || {};
            if (ctx.type !== 'warrant') return;

            const targetName = (MDT.els.warrantName?.value || '').trim();
            const charid     = (MDT.els.warrantCharid?.value || '').trim();
            const reason     = (MDT.els.warrantReason?.value || '').trim();

            if (!targetName || !reason) return;

            nuiPost('CreateWarrant', {
                targetName,
                charid,
                reason
            });

            const parts = targetName.split(' ');
            const first = parts[0] || '';
            const last  = parts.slice(1).join(' ');
            nuiPost('NameSearch', { first, last, term: targetName });
            nuiPost('GetWarrants', {});

            speak(`Warrant created for ${targetName}.`);
            closeModal();
        });
    }

    if (MDT.els.warrantCancel) {
        MDT.els.warrantCancel.addEventListener('click', (e) => {
            e.preventDefault();
            closeModal();
        });
    }

    if (MDT.els.modalBackdrop) {
        MDT.els.modalBackdrop.addEventListener('click', (e) => {
            if (e.target === MDT.els.modalBackdrop) {
                closeModal();
            }
        });
    }

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            if (MDT.state.modalContext) {
                closeModal();
            } else {
                nuiPost('close', {});
            }
        }
    });

    document.addEventListener('click', (ev) => {
        if (!MDT.root) return;
        if (!ev.target.closest('#mdt-wrapper')) return;
        if (ev.target.closest('button') || ev.target.closest('.btn') || ev.target.closest('.btn-xs')) {
            playSound('click');
        }
    });

    document.addEventListener('click', (ev) => {
        const btn = ev.target.closest('[data-admin-action]');
        if (!btn) return;
        if (!MDT.state.isAdmin) return;

        const action = btn.dataset.adminAction;

        if (action === 'delete-bolo') {
            const id = parseInt(btn.dataset.boloId, 10);
            if (!id) return;
            nuiPost('AdminDeleteBolo', { id });
        } else if (action === 'delete-report') {
            const id = parseInt(btn.dataset.reportId, 10);
            if (!id) return;
            nuiPost('AdminDeleteReport', { id });
        } else if (action === 'delete-call') {
            const id = parseInt(btn.dataset.callId, 10);
            if (!id) return;
            nuiPost('AdminDeleteCall', { id });
        } else if (action === 'delete-employee') {
            const id = parseInt(btn.dataset.employeeId, 10);
            const department = btn.dataset.employeeDept || '';
            if (!id || !department) return;
            nuiPost('AdminDeleteEmployee', { id, department });
        }
    });

    const handle = document.querySelector('.mdt-resize-handle');
    if (handle && MDT.windowEl) {
        let resizing = false;
        let startX = 0, startY = 0;
        let startW = 0, startH = 0;

        handle.addEventListener('mousedown', (ev) => {
            ev.preventDefault();
            resizing = true;
            startX = ev.clientX;
            startY = ev.clientY;
            const rect = MDT.windowEl.getBoundingClientRect();
            startW = rect.width;
            startH = rect.height;
            document.body.style.userSelect = 'none';
        });

        window.addEventListener('mousemove', (ev) => {
            if (!resizing) return;
            const deltaX = ev.clientX - startX;
            const deltaY = ev.clientY - startY;

            const newW = Math.max(900, Math.min(1550, startW + deltaX));
            const newH = Math.max(600, Math.min(950, startH + deltaY));

            MDT.windowEl.style.width = `${newW}px`;
            MDT.windowEl.style.height = `${newH}px`;
        });

        window.addEventListener('mouseup', () => {
            if (!resizing) return;
            resizing = false;
            document.body.style.userSelect = '';
        });
    }

    console.log('[az_mdt] NUI script initialised');
});
