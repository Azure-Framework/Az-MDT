const AZ_MDT_CONFIG = window.AZ_MDT_CONFIG || {};
const MDT_RUNTIME = {
    isNui: typeof GetParentResourceName === 'function',
    isBrowser: typeof GetParentResourceName !== 'function'
};

const MDT = {
    root: null,
    windowEl: null,
    state: {
        officer: null,
        role: 'leo',
        status: 'OFFDUTY',
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
        alertedCalls: {},
        isAdmin: false,
        isSupervisor: false,
        canManageDispatch: false,
        warrants: [],
        actionLog: [],
        modalContext: null,
        civRegistry: [],
        dmvResults: [],
        leoChat: [],
        callRooms: {},
        activeCallRoom: null,
        pendingCallRoomRequest: null,
        callHistory: [],
        myCivilians: [],
        selectedCivilianId: null,
        lastCallRoomAnnouncement: { id: null, at: 0 },
        webAuth: { configured: false, authenticated: false, linked: false, loginUrl: '', logoutUrl: '', user: null },
        themeSettings: { preset: 'blue-command', label: 'Blue Command', vars: {} },
        ttsEnabled: true,
        lastQueries: { nameFirst: '', nameLast: '', plate: '', weapon: '', dmv: '', civ: '', calls: '', reports: '', nameMeta: null, plateMeta: null },
        liveRefreshStarted: false,
        employeeAccessState: { open: {}, drafts: {}, lastSavedAt: 0 },
        pendingExternalSearch: null,
        replayingExternalSearch: false,
        externalSearchRunState: { key: '', at: 0, completedKey: '', completedAt: 0 },
        liveMap: {
            config: { enabled: true, updateIntervalMs: 1750, showPostalLabels: false, bounds: { minX: -4200, maxX: 4500, minY: -4500, maxY: 8500 } },
            icons: {},
            postals: [],
            filter: 'all',
            pendingUploads: {},
            view: { scale: 1, x: 0, y: 0, ready: false, hasFitted: false },
            dragging: { active: false, startX: 0, startY: 0, baseX: 0, baseY: 0 }
        }
    },
    els: {}
};

window.MDT = MDT;

function ttsStorageKey() {
    return 'az_mdt_tts_enabled';
}

function isSpeechTtsEnabled() {
    try {
        const raw = window.localStorage.getItem(ttsStorageKey());
        if (raw === null) return true;
        return raw !== '0' && raw !== 'false';
    } catch (_) {
        return true;
    }
}

function setSpeechTtsEnabled(enabled) {
    MDT.state.ttsEnabled = !!enabled;
    try {
        window.localStorage.setItem(ttsStorageKey(), MDT.state.ttsEnabled ? '1' : '0');
    } catch (_) {}
    renderTtsToggle();
}

function renderTtsToggle() {
    if (!MDT.els || !MDT.els.ttsToggle) return;
    MDT.els.ttsToggle.textContent = MDT.state.ttsEnabled ? 'TTS ON' : 'TTS OFF';
    MDT.els.ttsToggle.classList.toggle('btn-primary', MDT.state.ttsEnabled);
    MDT.els.ttsToggle.classList.toggle('btn-secondary', !MDT.state.ttsEnabled);
}

function splitNamePrefill(value) {
    const text = String(value || '').trim();
    if (!text) return { first: '', last: '' };
    const parts = text.split(/\s+/);
    if (parts.length <= 1) return { first: text, last: '' };
    return { first: parts.shift() || '', last: parts.join(' ') };
}

function resolveExternalSearchPage(wrapper, search, kind) {
    const explicit = String((wrapper && wrapper.page) || (search && search.page) || '').trim();
    if (explicit) return explicit;
    if (kind === 'plate') return 'plateSearch';
    if (kind === 'name') return 'nameSearch';
    if (kind === 'report' || kind === 'reports') return 'reports';
    return '';
}

function normalizeExternalSearchPayload(payload) {
    const wrapper = safeParse(payload, 'externalSearchPrefill') || payload || {};
    const nested = (wrapper && typeof wrapper.search === 'object' && wrapper.search) ? wrapper.search : {};
    const merged = { ...(wrapper || {}), ...(nested || {}) };
    const preservePage = merged.preservePage === true || merged.prefillOnly === true;
    const autoSearch = merged.autoSearch;
    let kind = String(merged.kind || merged.type || '').trim().toLowerCase();
    const explicitPage = String((wrapper && wrapper.page) || (nested && nested.page) || '').trim();
    const page = preservePage ? explicitPage : resolveExternalSearchPage(wrapper, merged, kind);
    const rawValue = String(merged.value || merged.term || merged.name || '').trim();
    const plate = String(merged.plate || merged.lp || merged.license || '').trim();
    const firstRaw = String(merged.first || merged.firstname || '').trim();
    const lastRaw = String(merged.last || merged.lastname || '').trim();
    const fallbackName = String(merged.name || rawValue || '').trim();
    const nameParts = (firstRaw || lastRaw) ? { first: firstRaw, last: lastRaw } : splitNamePrefill(fallbackName || rawValue);
    if (!kind) {
        if (plate && !fallbackName && !nameParts.first && !nameParts.last) kind = 'plate';
        else if (nameParts.first || nameParts.last || fallbackName) kind = 'name';
        else if (plate) kind = 'plate';
    }
    return {
        page,
        kind,
        value: rawValue,
        plate,
        first: nameParts.first || '',
        last: nameParts.last || '',
        preservePage,
        autoSearch,
        raw: merged
    };
}

function dispatchInputSync(el) {
    if (!el) return;
    try { el.dispatchEvent(new Event('input', { bubbles: true })); } catch (_) {}
    try { el.dispatchEvent(new Event('change', { bubbles: true })); } catch (_) {}
}

function setInputValue(el, value) {
    if (!el) return false;
    const next = String(value ?? '');
    if (el.value !== next) el.value = next;
    dispatchInputSync(el);
    return true;
}

function normalizeNameToken(value) {
    return String(value || '').trim().toLowerCase().replace(/\s+/g, ' ');
}

function isPlaceholderNameValue(value) {
    const v = normalizeNameToken(value);
    return v === '' || v === 'unknown' || v === 'unknown unknown' || v === 'n/a' || v === 'na' || v === 'none';
}

function shouldProtectActiveNameInputs() {
    const active = document.activeElement;
    return active === getNameFirstInput() || active === getNameLastInput();
}

function getNameFirstInput() {
    return MDT.els.nameFirst || document.getElementById('first-name-input');
}

function getNameLastInput() {
    return MDT.els.nameLast || document.getElementById('last-name-input');
}

function getPlateInput() {
    return MDT.els.plateInput || document.getElementById('plate-input');
}


function cloneSearchMeta(meta) {
    return meta ? { ...meta } : null;
}

function buildNameSearchPayload(first, last) {
    const payload = {
        first: String(first || '').trim(),
        last: String(last || '').trim()
    };
    payload.term = `${payload.first} ${payload.last}`.trim();

    const meta = MDT.state.lastQueries && MDT.state.lastQueries.nameMeta ? MDT.state.lastQueries.nameMeta : null;
    if (meta) {
        const sameFirst = String(meta.first || '').trim().toLowerCase() === payload.first.toLowerCase();
        const sameLast = String(meta.last || '').trim().toLowerCase() === payload.last.toLowerCase();
        const metaTerm = String(meta.term || `${meta.first || ''} ${meta.last || ''}`).trim().toLowerCase();
        const payloadTerm = payload.term.toLowerCase();
        if ((payloadTerm && payloadTerm === metaTerm) || (sameFirst && sameLast && (payload.first || payload.last))) {
            if (meta.source) payload.source = meta.source;
            if (meta.netId) payload.netId = meta.netId;
            if (meta.name) payload.name = meta.name;
        }
    }

    return payload;
}

function buildPlateSearchPayload(plate) {
    const payload = {
        plate: String(plate || '').trim()
    };
    if (payload.plate) payload.term = payload.plate;

    const meta = MDT.state.lastQueries && MDT.state.lastQueries.plateMeta ? MDT.state.lastQueries.plateMeta : null;
    if (meta && payload.plate && String(meta.plate || '').trim().toLowerCase() === payload.plate.toLowerCase()) {
        if (meta.source) payload.source = meta.source;
        if (meta.owner) payload.owner = meta.owner;
        if (meta.owner_name) payload.owner_name = meta.owner_name;
        if (meta.model) payload.model = meta.model;
        if (meta.make) payload.make = meta.make;
        if (meta.color) payload.color = meta.color;
        if (meta.status) payload.status = meta.status;
    }

    return payload;
}

function externalSearchFingerprint(pending) {
    if (!pending) return '';
    return [
        String(pending.page || '').trim().toLowerCase(),
        String(pending.kind || '').trim().toLowerCase(),
        String(pending.plate || '').trim().toLowerCase(),
        String(pending.first || '').trim().toLowerCase(),
        String(pending.last || '').trim().toLowerCase(),
        String(pending.value || '').trim().toLowerCase()
    ].join('|');
}

function shouldRunExternalSearch(pending) {
    const key = externalSearchFingerprint(pending);
    if (!key) return { run: false, key: '' };
    const state = MDT.state.externalSearchRunState || (MDT.state.externalSearchRunState = { key: '', at: 0, completedKey: '', completedAt: 0 });
    const now = Date.now();
    if (state.completedKey === key && (now - (state.completedAt || 0)) < 8000) {
        return { run: false, key };
    }
    if (state.key === key && (now - (state.at || 0)) < 2500) {
        return { run: false, key };
    }
    state.key = key;
    state.at = now;
    return { run: true, key };
}

function markExternalSearchCompleted(pending) {
    const key = externalSearchFingerprint(pending);
    if (!key) return;
    const state = MDT.state.externalSearchRunState || (MDT.state.externalSearchRunState = { key: '', at: 0, completedKey: '', completedAt: 0 });
    state.completedKey = key;
    state.completedAt = Date.now();
    if (MDT.state.pendingExternalSearch && externalSearchFingerprint(MDT.state.pendingExternalSearch) === key) {
        MDT.state.pendingExternalSearch.completed = true;
        MDT.state.pendingExternalSearch.completedAt = state.completedAt;
    }
}

function clearPendingExternalSearch() {
    if (MDT.state.pendingExternalSearch) {
        MDT.state.pendingExternalSearch.completed = true;
        MDT.state.pendingExternalSearch.completedAt = Date.now();
    }
    MDT.state.pendingExternalSearch = null;
    const state = MDT.state.externalSearchRunState || (MDT.state.externalSearchRunState = { key: '', at: 0, completedKey: '', completedAt: 0 });
    state.key = '';
    state.at = 0;
    try { nuiPost('ClearExternalPrefill', {}); } catch (_) {}
}

function shouldPromoteResultPage(targetPage) {
    const activePage = String(MDT.state.activePage || '').trim();
    if (activePage === targetPage) return true;

    const pending = MDT.state.pendingExternalSearch;
    if (!pending || pending.completed || pending.preservePage) return false;

    const pendingPage = String(pending.page || resolveExternalSearchPage(null, pending, pending.kind) || '').trim();
    return pendingPage === targetPage;
}

function replayPendingExternalSearch(runSearch = false) {
    const pending = MDT.state.pendingExternalSearch;
    if (!pending || (!pending.kind && !pending.page && !pending.plate && !pending.first && !pending.last && !(pending.raw && (pending.raw.name || pending.raw.plate)))) return;

    const previousReplay = MDT.state.replayingExternalSearch;
    MDT.state.replayingExternalSearch = true;
    try {
        if (pending.page && !pending.preservePage) setActivePage(pending.page);

        const gate = runSearch ? shouldRunExternalSearch(pending) : { run: false, key: externalSearchFingerprint(pending) };
        const canAutoSearch = pending.autoSearch !== false && !pending.preservePage;

        const plate = String(pending.plate || pending.value || '').trim();
        const first = String(pending.first || '').trim();
        const last = String(pending.last || '').trim();
        const rawName = String((pending.raw && pending.raw.name) || pending.value || '').trim();
        const inferredName = (first || last) ? { first, last } : splitNamePrefill(rawName);
        const finalFirst = first || inferredName.first || '';
        const finalLast = last || inferredName.last || '';

        if (plate) {
            MDT.state.lastQueries.plate = plate;
            MDT.state.lastQueries.plateMeta = cloneSearchMeta({
                plate,
                source: pending.raw && pending.raw.source ? pending.raw.source : '',
                owner: pending.raw && pending.raw.owner ? pending.raw.owner : '',
                owner_name: pending.raw && pending.raw.owner_name ? pending.raw.owner_name : '',
                model: pending.raw && pending.raw.model ? pending.raw.model : '',
                make: pending.raw && pending.raw.make ? pending.raw.make : '',
                color: pending.raw && pending.raw.color ? pending.raw.color : '',
                status: pending.raw && pending.raw.status ? pending.raw.status : ''
            });
            const applyPlate = () => setInputValue(getPlateInput(), plate);
            applyPlate();
            setTimeout(applyPlate, 0);
            setTimeout(applyPlate, 90);
            setTimeout(applyPlate, 220);
        }

        const hasUsefulName = (finalFirst || finalLast)
            && !isPlaceholderNameValue(finalFirst)
            && !isPlaceholderNameValue(finalLast)
            && !(normalizeNameToken(`${finalFirst} ${finalLast}`) === 'unknown unknown');

        if (hasUsefulName) {
            MDT.state.lastQueries.nameFirst = finalFirst;
            MDT.state.lastQueries.nameLast = finalLast;
            MDT.state.lastQueries.nameMeta = cloneSearchMeta({
                first: finalFirst,
                last: finalLast,
                term: `${finalFirst} ${finalLast}`.trim(),
                source: pending.raw && pending.raw.source ? pending.raw.source : '',
                netId: pending.raw && pending.raw.netId ? pending.raw.netId : '',
                name: rawName || `${finalFirst} ${finalLast}`.trim()
            });
            const applyName = () => {
                if (shouldProtectActiveNameInputs()) return;
                setInputValue(getNameFirstInput(), MDT.state.lastQueries.nameFirst);
                setInputValue(getNameLastInput(), MDT.state.lastQueries.nameLast);
            };
            applyName();
            setTimeout(applyName, 0);
            setTimeout(applyName, 90);
            setTimeout(applyName, 220);
        }

        if (!runSearch || !gate.run || !canAutoSearch) return;

        if (pending.kind === 'plate' && plate) {
            nuiPost('PlateSearch', {
                plate,
                term: plate,
                source: pending.raw && pending.raw.source ? pending.raw.source : 'external',
                owner: pending.raw && pending.raw.owner ? pending.raw.owner : '',
                owner_name: pending.raw && pending.raw.owner_name ? pending.raw.owner_name : '',
                model: pending.raw && pending.raw.model ? pending.raw.model : '',
                color: pending.raw && pending.raw.color ? pending.raw.color : ''
            });
            return;
        }

        if (pending.kind === 'name' && (finalFirst || finalLast)) {
            nuiPost('NameSearch', {
                first: finalFirst,
                last: finalLast,
                term: `${finalFirst} ${finalLast}`.trim(),
                source: pending.raw && pending.raw.source ? pending.raw.source : 'external',
                netId: pending.raw && pending.raw.netId ? pending.raw.netId : ''
            });
        }
    } finally {
        MDT.state.replayingExternalSearch = previousReplay;
    }
}

function applyExternalSearchPrefill(payload) {
    const normalized = normalizeExternalSearchPayload(payload);
    MDT.state.pendingExternalSearch = normalized;
    replayPendingExternalSearch(false);
    setTimeout(() => replayPendingExternalSearch(false), 0);
    setTimeout(() => replayPendingExternalSearch(false), 120);
    setTimeout(() => replayPendingExternalSearch(false), 320);
    setTimeout(() => replayPendingExternalSearch(false), 700);
    setTimeout(() => replayPendingExternalSearch(false), 1200);
}

function employeeAccessState() {
    if (!MDT.state.employeeAccessState) {
        MDT.state.employeeAccessState = { open: {}, drafts: {}, lastSavedAt: 0 };
    }
    return MDT.state.employeeAccessState;
}

function collectEmployeeAccessEditorDraft(editor) {
    const draft = { pages: {}, actions: {} };
    if (!editor) return draft;

    editor.querySelectorAll('[data-employee-perm]').forEach((input) => {
        const key = input.dataset.employeePerm;
        if (!key) return;
        draft[key] = input.type === 'checkbox' ? !!input.checked : (input.value || '');
    });

    editor.querySelectorAll('[data-employee-page]').forEach((input) => {
        const key = input.dataset.employeePage;
        if (key) draft.pages[key] = !!input.checked;
    });

    editor.querySelectorAll('[data-employee-action]').forEach((input) => {
        const key = input.dataset.employeeAction;
        if (key) draft.actions[key] = !!input.checked;
    });

    return draft;
}

function applyEmployeeAccessEditorDraft(editor, draft) {
    if (!editor || !draft) return;

    editor.querySelectorAll('[data-employee-perm]').forEach((input) => {
        const key = input.dataset.employeePerm;
        if (!key || draft[key] === undefined) return;
        if (input.type === 'checkbox') input.checked = !!draft[key];
        else input.value = draft[key] || '';
    });

    editor.querySelectorAll('[data-employee-page]').forEach((input) => {
        const key = input.dataset.employeePage;
        if (key && draft.pages && draft.pages[key] !== undefined) input.checked = !!draft.pages[key];
    });

    editor.querySelectorAll('[data-employee-action]').forEach((input) => {
        const key = input.dataset.employeeAction;
        if (key && draft.actions && draft.actions[key] !== undefined) input.checked = !!draft.actions[key];
    });
}

function snapshotEmployeeAccessEditors() {
    const container = MDT.els && MDT.els.employeeList;
    if (!container) return;
    const state = employeeAccessState();

    container.querySelectorAll('.mdt-employee-access-editor').forEach((editor) => {
        const rowId = String(editor.dataset.employeeAccessEditor || '');
        if (!rowId) return;
        const isOpen = editor.classList.contains('open');
        state.open[rowId] = isOpen;
        if (isOpen) {
            state.drafts[rowId] = collectEmployeeAccessEditorDraft(editor);
        }
    });
}

function restoreEmployeeAccessEditors() {
    const container = MDT.els && MDT.els.employeeList;
    if (!container) return;
    const state = employeeAccessState();

    Object.entries(state.open || {}).forEach(([rowId, shouldOpen]) => {
        if (!shouldOpen) return;
        const editor = container.querySelector(`.mdt-employee-access-editor[data-employee-access-editor="${rowId}"]`);
        if (!editor) return;
        editor.classList.add('open');
        applyEmployeeAccessEditorDraft(editor, state.drafts[rowId]);
    });
}

function setEmployeeAccessEditorOpen(rowId, isOpen, editor) {
    const key = String(rowId || '');
    if (!key) return;
    const state = employeeAccessState();
    state.open[key] = !!isOpen;
    if (isOpen && editor) {
        state.drafts[key] = collectEmployeeAccessEditorDraft(editor);
    } else if (!isOpen) {
        delete state.drafts[key];
    }
}

function persistEmployeeAccessDraftFromInput(input) {
    const editor = input && input.closest ? input.closest('.mdt-employee-access-editor') : null;
    if (!editor) return;
    const rowId = String(editor.dataset.employeeAccessEditor || '');
    if (!rowId) return;
    const state = employeeAccessState();
    state.open[rowId] = true;
    state.drafts[rowId] = collectEmployeeAccessEditorDraft(editor);
}

function rowLikelyMatchesCurrentViewer(row) {
    const viewer = MDT.state.officer || {};
    if (!row || !viewer) return false;
    const rowDiscord = String(row.discordid || row.discordId || '').trim();
    const rowLicense = String(row.license || '').trim();
    const rowIdentifier = String(row.identifier || '').trim();
    const viewerDiscord = String(viewer.discordid || viewer.discordId || '').trim();
    const viewerLicense = String(viewer.license || '').trim();
    const viewerIdentifier = String(viewer.identifier || '').trim();
    return !!((rowDiscord && viewerDiscord && rowDiscord === viewerDiscord) ||
        (rowLicense && viewerLicense && rowLicense === viewerLicense) ||
        (rowIdentifier && viewerIdentifier && rowIdentifier === viewerIdentifier));
}

function queueLiveRefresh(ms = 200) {
    const delay = Math.max(0, Number(ms) || 0);
    if (MDT.state.liveRefreshTimer) {
        window.clearTimeout(MDT.state.liveRefreshTimer);
    }
    MDT.state.liveRefreshTimer = window.setTimeout(() => {
        MDT.state.liveRefreshTimer = null;
        refreshActiveView();
    }, delay);
}

function canUseDispatchRole() {
    return (MDT.state.role || 'leo') === 'dispatch';
}

function isLeoLikeRole() {
    const role = MDT.state.role || 'leo';
    return role === 'leo' || role === 'dispatch';
}

const ROLE_PAGE_DEFAULTS = {
    admin: { dashboard:true, liveMap:true, nameSearch:true, plateSearch:true, weaponSearch:true, bolos:true, reports:true, dutyChat:true, callsHub:true, simTools:true, civCenter:true, dmv:true, warrants:true, employees:true, themes:true, iaLogs:true },
    dispatch: { dashboard:true, liveMap:true, nameSearch:true, plateSearch:true, weaponSearch:true, bolos:true, reports:true, dutyChat:true, callsHub:true, simTools:true, civCenter:false, dmv:true, warrants:true, employees:true, themes:false, iaLogs:false },
    supervisor: { dashboard:true, liveMap:true, nameSearch:true, plateSearch:true, weaponSearch:true, bolos:true, reports:true, dutyChat:true, callsHub:true, simTools:true, civCenter:true, dmv:true, warrants:true, employees:true, themes:false, iaLogs:false },
    civ: { dashboard:true, liveMap:false, nameSearch:false, plateSearch:false, weaponSearch:false, bolos:false, reports:true, dutyChat:false, callsHub:false, simTools:false, civCenter:true, dmv:true, warrants:false, employees:false, themes:false, iaLogs:false },
    leo: { dashboard:true, liveMap:true, nameSearch:true, plateSearch:true, weaponSearch:true, bolos:true, reports:true, dutyChat:true, callsHub:true, simTools:true, civCenter:true, dmv:true, warrants:true, employees:true, themes:false, iaLogs:false }
};

const ROLE_ACTION_DEFAULTS = {
    admin: { lookupName:true, lookupPlate:true, lookupWeapon:true, createBolo:true, deleteBolo:true, createReport:true, deleteReport:true, createWarrant:true, deleteWarrant:true, attachCalls:true, detachCalls:true, waypointCalls:true, clearCalls:true, statusCheck:true, updateUnitStatus:true, editDmv:true, quickNotes:true, flags:true, saveProfile:true, registerVehicle:true, registerWeapon:true, deleteCivilianAssets:true, editEmployeeAccess:true, deleteEmployee:true, viewActionLog:true, sendLeoChat:true },
    dispatch: { lookupName:true, lookupPlate:true, lookupWeapon:true, createBolo:true, deleteBolo:true, createReport:true, deleteReport:false, createWarrant:true, deleteWarrant:true, attachCalls:true, detachCalls:true, waypointCalls:true, clearCalls:true, statusCheck:true, updateUnitStatus:true, editDmv:true, quickNotes:true, flags:true, saveProfile:true, registerVehicle:false, registerWeapon:false, deleteCivilianAssets:false, editEmployeeAccess:false, deleteEmployee:false, viewActionLog:false, sendLeoChat:true },
    supervisor: { lookupName:true, lookupPlate:true, lookupWeapon:true, createBolo:true, deleteBolo:true, createReport:true, deleteReport:false, createWarrant:true, deleteWarrant:true, attachCalls:true, detachCalls:true, waypointCalls:true, clearCalls:true, statusCheck:true, updateUnitStatus:true, editDmv:true, quickNotes:true, flags:true, saveProfile:true, registerVehicle:true, registerWeapon:true, deleteCivilianAssets:true, editEmployeeAccess:false, deleteEmployee:false, viewActionLog:false, sendLeoChat:true },
    civ: { lookupName:false, lookupPlate:false, lookupWeapon:false, createBolo:false, deleteBolo:false, createReport:true, deleteReport:false, createWarrant:false, deleteWarrant:false, attachCalls:false, detachCalls:false, waypointCalls:false, clearCalls:false, statusCheck:false, updateUnitStatus:false, editDmv:true, quickNotes:false, flags:false, saveProfile:false, registerVehicle:true, registerWeapon:true, deleteCivilianAssets:true, editEmployeeAccess:false, deleteEmployee:false, viewActionLog:false, sendLeoChat:false },
    leo: { lookupName:true, lookupPlate:true, lookupWeapon:true, createBolo:true, deleteBolo:false, createReport:true, deleteReport:false, createWarrant:true, deleteWarrant:false, attachCalls:true, detachCalls:true, waypointCalls:true, clearCalls:false, statusCheck:false, updateUnitStatus:false, editDmv:true, quickNotes:true, flags:true, saveProfile:true, registerVehicle:true, registerWeapon:true, deleteCivilianAssets:true, editEmployeeAccess:false, deleteEmployee:false, viewActionLog:false, sendLeoChat:true }
};

function deepClone(obj) {
    return JSON.parse(JSON.stringify(obj || {}));
}

function getRoleDefaults(role) {
    return {
        pages: deepClone(ROLE_PAGE_DEFAULTS[role] || ROLE_PAGE_DEFAULTS.leo),
        actions: deepClone(ROLE_ACTION_DEFAULTS[role] || ROLE_ACTION_DEFAULTS.leo)
    };
}

function getActivePermissionSet() {
    const role = String((MDT.state.officer?.permissions?.role) || MDT.state.role || 'leo').toLowerCase();
    if (MDT.state.isAdmin || MDT.state.officer?.isAdmin) return getRoleDefaults('admin');
    const defaults = getRoleDefaults(role);
    const perms = MDT.state.officer?.permissions || {};
    const pages = { ...defaults.pages, ...((perms.pages && typeof perms.pages === 'object') ? perms.pages : {}) };
    const actions = { ...defaults.actions, ...((perms.actions && typeof perms.actions === 'object') ? perms.actions : {}) };
    return { pages, actions };
}

function canUsePage(page) {
    const perms = getActivePermissionSet();
    if (page in perms.pages) return !!perms.pages[page];
    return true;
}

function canUseAction(action) {
    const perms = getActivePermissionSet();
    if (action in perms.actions) return !!perms.actions[action];
    return true;
}

const THEME_PRESETS = {
    'blue-command': {
        key: 'blue-command',
        label: 'Blue Command',
        description: 'Deep command-board blue with geometric command-glass panels inspired by the blue dashboard reference.',
        vars: {
            'font-family-main': '"Segoe UI", Inter, system-ui, sans-serif',
            'font-size-base': '14px',
            'bg-main': '#061225',
            'bg-card': 'rgba(8, 18, 38, 0.92)',
            'bg-card-soft': 'rgba(9, 20, 42, 0.92)',
            'bg-input': '#08142a',
            'bg-input-soft': '#0a1730',
            'bg-sidebar': '#071225',
            'bg-header': '#0b1730',
            'bg-window': '#04101f',
            'bg-window-secondary': '#071630',
            'accent': '#1d8cff',
            'accent-2': '#4d72ff',
            'accent-soft': 'rgba(29, 140, 255, 0.16)',
            'accent-strong': '#63beff',
            'border-subtle': 'rgba(70, 122, 207, 0.24)',
            'border-strong': 'rgba(103, 159, 255, 0.42)',
            'text-main': '#edf5ff',
            'text-sub': '#96b2d9',
            'text-muted': '#5f7da4',
            'danger': '#ff5d66',
            'danger-soft': 'rgba(255, 93, 102, 0.16)',
            'success': '#30d49b',
            'radius-lg': '18px',
            'radius-md': '10px',
            'window-radius': '24px',
            'nav-radius': '12px',
            'card-header-bg': 'linear-gradient(180deg, rgba(36, 108, 220, 0.96), rgba(15, 71, 168, 0.96))',
            'card-header-color': '#f3f8ff',
            'card-header-border': '1px solid rgba(125, 182, 255, 0.22)',
            'row-bg': 'rgba(10, 23, 48, 0.96)',
            'row-tag-bg': 'rgba(7, 18, 40, 0.98)',
            'row-tag-text': '#8fb6e7',
            'nav-text': '#93b4da',
            'nav-hover-bg': 'rgba(15, 39, 84, 0.78)',
            'nav-active-bg': 'linear-gradient(135deg, #1d8cff, #4d72ff)',
            'nav-active-text': '#eef6ff',
            'button-primary-bg': 'linear-gradient(135deg, #1d8cff, #4d72ff)',
            'button-primary-text': '#eef6ff',
            'shadow-soft': '0 18px 45px rgba(2, 8, 26, 0.72)'
        }
    },
    'classic-cad': {
        key: 'classic-cad',
        label: 'Classic CAD',
        description: 'Legacy dispatch desktop styling with light gray chrome, warm cream work areas, and bright royal-blue section bars.',
        vars: {
            'font-family-main': 'Tahoma, "Segoe UI", Arial, sans-serif',
            'font-size-base': '13px',
            'bg-main': '#d3d6dc',
            'bg-card': '#ece7d4',
            'bg-card-soft': '#ece7d4',
            'bg-input': '#f2eedf',
            'bg-input-soft': '#f2eedf',
            'bg-sidebar': '#c7ccd4',
            'bg-header': '#e8ebf0',
            'bg-window': '#d8dce2',
            'bg-window-secondary': '#eef1f4',
            'accent': '#2450c7',
            'accent-2': '#1039b2',
            'accent-soft': 'rgba(36, 80, 199, 0.10)',
            'accent-strong': '#113ec1',
            'border-subtle': 'rgba(118, 122, 130, 0.28)',
            'border-strong': 'rgba(90, 99, 120, 0.36)',
            'text-main': '#1b2436',
            'text-sub': '#5d6a7c',
            'text-muted': '#768092',
            'danger': '#ad4550',
            'danger-soft': 'rgba(173, 69, 80, 0.12)',
            'success': '#2d7956',
            'radius-lg': '4px',
            'radius-md': '3px',
            'window-radius': '2px',
            'nav-radius': '3px',
            'card-header-bg': 'linear-gradient(180deg, #2d63da 0%, #1a4fca 58%, #0f3fb5 100%)',
            'card-header-color': '#f8fbff',
            'card-header-border': '1px solid rgba(96, 112, 144, 0.46)',
            'row-bg': '#f4f0e1',
            'row-tag-bg': '#e1e6f1',
            'row-tag-text': '#445372',
            'row-tag-border': 'rgba(94, 108, 138, 0.38)',
            'nav-text': '#5b6678',
            'nav-hover-bg': 'rgba(122, 131, 145, 0.12)',
            'nav-active-bg': 'linear-gradient(180deg, #2d63da 0%, #1a4fca 58%, #0f3fb5 100%)',
            'nav-active-text': '#f8fbff',
            'button-primary-bg': 'linear-gradient(180deg, #2d63da 0%, #1a4fca 58%, #0f3fb5 100%)',
            'button-primary-text': '#f8fbff',
            'button-secondary-bg': '#eef1f5',
            'button-secondary-text': '#20314b',
            'button-danger-bg': '#f2e8db',
            'button-danger-text': '#983947',
            'shadow-soft': '0 12px 24px rgba(56, 58, 64, 0.14)'
        }
    },
    'neon-tablet': {
        key: 'neon-tablet',
        label: 'Neon Tablet',
        description: 'Modern dark tablet with bright cyan action glow, rounded panels, and softer cyber-police styling.',
        vars: {
            'font-family-main': 'Inter, "Segoe UI", system-ui, sans-serif',
            'font-size-base': '14px',
            'bg-main': '#060b16',
            'bg-card': 'rgba(13, 18, 34, 0.92)',
            'bg-card-soft': 'rgba(15, 20, 38, 0.9)',
            'bg-input': 'rgba(17, 25, 45, 0.94)',
            'bg-input-soft': 'rgba(17, 25, 45, 0.88)',
            'bg-sidebar': '#070d18',
            'bg-header': '#070d18',
            'bg-window': '#060b16',
            'bg-window-secondary': '#0b1223',
            'accent': '#2d8cff',
            'accent-2': '#5d73ff',
            'accent-soft': 'rgba(45, 140, 255, 0.16)',
            'accent-strong': '#8addff',
            'border-subtle': 'rgba(101, 122, 170, 0.18)',
            'border-strong': 'rgba(101, 164, 255, 0.34)',
            'text-main': '#f1f5fe',
            'text-sub': '#a0adcb',
            'text-muted': '#72819d',
            'danger': '#ff4e59',
            'danger-soft': 'rgba(255, 78, 89, 0.16)',
            'success': '#30d49b',
            'radius-lg': '18px',
            'radius-md': '10px',
            'window-radius': '18px',
            'nav-radius': '10px',
            'card-header-bg': 'linear-gradient(180deg, rgba(12, 24, 48, 0.98), rgba(9, 18, 37, 0.98))',
            'card-header-color': '#f0f5ff',
            'card-header-border': '1px solid rgba(74, 99, 255, 0.18)',
            'row-bg': 'rgba(8, 18, 42, 0.94)',
            'row-tag-bg': 'rgba(7, 14, 30, 0.98)',
            'row-tag-text': '#9eb2d5',
            'nav-text': '#92a5c7',
            'nav-hover-bg': 'rgba(20, 31, 58, 0.92)',
            'nav-active-bg': 'linear-gradient(135deg, #2d8cff, #5d73ff)',
            'nav-active-text': '#f1f6ff',
            'button-primary-bg': 'linear-gradient(135deg, #2d8cff, #5d73ff)',
            'button-primary-text': '#eff6ff',
            'shadow-soft': '0 18px 48px rgba(0, 0, 0, 0.56)'
        }
    }
};

const THEME_EDITOR_FIELDS = [
    { key: 'font-family-main', label: 'Font Family', type: 'font', section: 'Typography' },
    { key: 'font-size-base', label: 'Base Font Size', type: 'size', section: 'Typography' },

    { key: 'accent', label: 'Accent', type: 'color', section: 'Core Colors' },
    { key: 'accent-2', label: 'Accent 2', type: 'color', section: 'Core Colors' },
    { key: 'accent-soft', label: 'Accent Soft', type: 'color-alpha', section: 'Core Colors' },
    { key: 'accent-strong', label: 'Accent Strong', type: 'color', section: 'Core Colors' },
    { key: 'danger', label: 'Danger', type: 'color', section: 'Core Colors' },
    { key: 'danger-soft', label: 'Danger Soft', type: 'color-alpha', section: 'Core Colors' },
    { key: 'success', label: 'Success', type: 'color', section: 'Core Colors' },

    { key: 'bg-main', label: 'Main Background', type: 'color', section: 'Surfaces' },
    { key: 'bg-window', label: 'Window Background', type: 'color', section: 'Surfaces' },
    { key: 'bg-window-secondary', label: 'Window Secondary', type: 'color', section: 'Surfaces' },
    { key: 'bg-sidebar', label: 'Sidebar Background', type: 'color', section: 'Surfaces' },
    { key: 'bg-header', label: 'Header Background', type: 'color', section: 'Surfaces' },
    { key: 'bg-card', label: 'Card Background', type: 'color-alpha', section: 'Surfaces' },
    { key: 'bg-card-soft', label: 'Soft Card Background', type: 'color-alpha', section: 'Surfaces' },
    { key: 'bg-input', label: 'Input Background', type: 'color-alpha', section: 'Surfaces' },
    { key: 'bg-input-soft', label: 'Soft Input Background', type: 'color-alpha', section: 'Surfaces' },
    { key: 'row-bg', label: 'Row Background', type: 'color-alpha', section: 'Surfaces' },
    { key: 'row-tag-bg', label: 'Row Tag Background', type: 'color-alpha', section: 'Surfaces' },

    { key: 'card-header-bg', label: 'Card Header Background', type: 'gradient', section: 'Headers & Nav' },
    { key: 'card-header-color', label: 'Card Header Text', type: 'color', section: 'Headers & Nav' },
    { key: 'card-header-border', label: 'Card Header Border', type: 'border', section: 'Headers & Nav' },
    { key: 'nav-text', label: 'Navigation Text', type: 'color', section: 'Headers & Nav' },
    { key: 'nav-hover-bg', label: 'Navigation Hover Background', type: 'color-alpha', section: 'Headers & Nav' },
    { key: 'nav-active-bg', label: 'Navigation Active Background', type: 'gradient', section: 'Headers & Nav' },
    { key: 'nav-active-text', label: 'Navigation Active Text', type: 'color', section: 'Headers & Nav' },

    { key: 'button-primary-bg', label: 'Primary Button Background', type: 'gradient', section: 'Buttons & Inputs' },
    { key: 'button-primary-text', label: 'Primary Button Text', type: 'color', section: 'Buttons & Inputs' },
    { key: 'button-secondary-bg', label: 'Secondary Button Background', type: 'color-alpha', section: 'Buttons & Inputs' },
    { key: 'button-secondary-text', label: 'Secondary Button Text', type: 'color', section: 'Buttons & Inputs' },
    { key: 'button-danger-bg', label: 'Danger Button Background', type: 'color-alpha', section: 'Buttons & Inputs' },
    { key: 'button-danger-text', label: 'Danger Button Text', type: 'color', section: 'Buttons & Inputs' },
    { key: 'border-subtle', label: 'Subtle Border', type: 'color-alpha', section: 'Buttons & Inputs' },
    { key: 'border-strong', label: 'Strong Border', type: 'color-alpha', section: 'Buttons & Inputs' },

    { key: 'text-main', label: 'Primary Text', type: 'color', section: 'Text & Tags' },
    { key: 'text-sub', label: 'Secondary Text', type: 'color', section: 'Text & Tags' },
    { key: 'text-muted', label: 'Muted Text', type: 'color', section: 'Text & Tags' },
    { key: 'row-tag-text', label: 'Row Tag Text', type: 'color', section: 'Text & Tags' },
    { key: 'row-tag-border', label: 'Row Tag Border', type: 'color-alpha', section: 'Text & Tags' },

    { key: 'radius-lg', label: 'Large Radius', type: 'size', section: 'Shape & Shadow' },
    { key: 'radius-md', label: 'Medium Radius', type: 'size', section: 'Shape & Shadow' },
    { key: 'window-radius', label: 'Window Radius', type: 'size', section: 'Shape & Shadow' },
    { key: 'nav-radius', label: 'Nav Radius', type: 'size', section: 'Shape & Shadow' },
    { key: 'shadow-soft', label: 'Soft Shadow', type: 'shadow', section: 'Shape & Shadow' }
];

function cloneTheme(theme) {
    return JSON.parse(JSON.stringify(theme || { preset: 'blue-command', label: 'Blue Command', vars: {} }));
}

function normalizeThemeSettings(theme) {
    const fallback = cloneTheme({ preset: 'blue-command', label: 'Blue Command', vars: {} });
    const raw = theme && typeof theme === 'object' ? theme : {};
    const preset = (String(raw.preset || raw.theme_key || fallback.preset).trim() || fallback.preset);
    const presetDef = THEME_PRESETS[preset] || THEME_PRESETS[fallback.preset];
    const label = String(raw.label || raw.theme_label || presetDef.label || fallback.label).trim() || presetDef.label;
    const varsIn = raw.vars && typeof raw.vars === 'object' ? raw.vars : {};
    const vars = {};
    Object.entries(varsIn).forEach(([key, value]) => {
        const safeKey = String(key || '').trim().replace(/[^\w\-_]/g, '');
        const safeValue = String(value ?? '').trim();
        if (safeKey && safeValue) vars[safeKey] = safeValue;
    });
    return { preset: presetDef.key, label, vars };
}

function resolveThemeSettings(theme) {
    const normalized = normalizeThemeSettings(theme);
    const preset = THEME_PRESETS[normalized.preset] || THEME_PRESETS['blue-command'];
    return {
        preset: preset.key,
        label: normalized.label || preset.label,
        vars: { ...(preset.vars || {}), ...(normalized.vars || {}) }
    };
}

function applyTheme(theme) {
    const resolved = resolveThemeSettings(theme || MDT.state.themeSettings);
    MDT.state.themeSettings = normalizeThemeSettings(theme || MDT.state.themeSettings || resolved);
    const root = document.documentElement;
    root.setAttribute('data-mdt-theme', resolved.preset || 'blue-command');
    const themeKeys = new Set([
        ...THEME_EDITOR_FIELDS.map(field => field.key),
        ...Object.keys((THEME_PRESETS['blue-command'] || {}).vars || {}),
        ...Object.keys((THEME_PRESETS['classic-cad'] || {}).vars || {}),
        ...Object.keys((THEME_PRESETS['neon-tablet'] || {}).vars || {})
    ]);
    themeKeys.forEach((key) => root.style.removeProperty(`--${key}`));
    Object.entries(resolved.vars || {}).forEach(([key, value]) => {
        root.style.setProperty(`--${key}`, String(value));
    });
    if (MDT.els.themeActiveBadge) {
        MDT.els.themeActiveBadge.textContent = resolved.label || (THEME_PRESETS[resolved.preset] || {}).label || 'GLOBAL THEME';
    }
}

const AUTO_DERIVED_THEME_FIELDS = ['card-header-bg', 'nav-active-bg', 'button-primary-bg'];

function getThemeEditorFieldEl(fieldKey) {
    return document.querySelector(`[data-theme-field="${fieldKey}"]`);
}

function buildAccentGradient(accent, accent2) {
    const a = String(accent || '#1d8cff').trim() || '#1d8cff';
    const b = String(accent2 || a).trim() || a;
    return `linear-gradient(180deg, ${a} 0%, ${b} 58%, ${b} 100%)`;
}

function syncDerivedThemeFields(force = false) {
    const accent = getThemeEditorFieldEl('accent')?.value || '#1d8cff';
    const accent2 = getThemeEditorFieldEl('accent-2')?.value || accent;
    const derivedGradient = buildAccentGradient(accent, accent2);
    AUTO_DERIVED_THEME_FIELDS.forEach((fieldKey) => {
        const el = getThemeEditorFieldEl(fieldKey);
        if (!el) return;
        const shouldWrite = force || el.dataset.autoDerived !== '0';
        if (!shouldWrite) return;
        el.value = derivedGradient;
        el.dataset.autoDerived = '1';
    });
}

function clampThemeNumber(value, min, max) {
    const num = Number(value);
    if (!Number.isFinite(num)) return min;
    return Math.min(max, Math.max(min, num));
}

function padHex(value) {
    return Math.round(clampThemeNumber(value, 0, 255)).toString(16).padStart(2, '0');
}

function hexToRgba(hex) {
    const raw = String(hex || '').trim().replace('#', '');
    if (![3, 4, 6, 8].includes(raw.length) || /[^0-9a-f]/i.test(raw)) return null;
    const expanded = raw.length <= 4 ? raw.split('').map(ch => ch + ch).join('') : raw;
    const hasAlpha = expanded.length === 8;
    return {
        r: parseInt(expanded.slice(0, 2), 16),
        g: parseInt(expanded.slice(2, 4), 16),
        b: parseInt(expanded.slice(4, 6), 16),
        a: hasAlpha ? Number((parseInt(expanded.slice(6, 8), 16) / 255).toFixed(3)) : 1
    };
}

function parseCssColor(value) {
    const raw = String(value || '').trim();
    if (!raw) return null;
    if (raw.startsWith('#')) return hexToRgba(raw);
    const rgbMatch = raw.match(/^rgba?\(([^)]+)\)$/i);
    if (!rgbMatch) return null;
    const parts = rgbMatch[1].split(',').map(part => part.trim());
    if (parts.length < 3) return null;
    const [r, g, b, a] = parts;
    const parsed = {
        r: clampThemeNumber(parseFloat(r), 0, 255),
        g: clampThemeNumber(parseFloat(g), 0, 255),
        b: clampThemeNumber(parseFloat(b), 0, 255),
        a: parts.length >= 4 ? clampThemeNumber(parseFloat(a), 0, 1) : 1
    };
    return parsed;
}

function rgbaToCss(color, allowAlpha = false) {
    if (!color) return '';
    const alpha = clampThemeNumber(color.a ?? 1, 0, 1);
    if (allowAlpha && alpha < 0.999) {
        return `rgba(${Math.round(color.r)}, ${Math.round(color.g)}, ${Math.round(color.b)}, ${Number(alpha.toFixed(2))})`;
    }
    return `#${padHex(color.r)}${padHex(color.g)}${padHex(color.b)}`;
}

function getThemeFieldDef(fieldKey) {
    return THEME_EDITOR_FIELDS.find(field => field.key === fieldKey) || null;
}

function syncThemeFieldPreview(fieldKey, value) {
    const preview = document.querySelector(`[data-theme-preview="${fieldKey}"]`);
    if (!preview) return;
    const parsed = parseCssColor(value);
    if (parsed) {
        preview.style.background = rgbaToCss(parsed, parsed.a < 0.999);
        preview.style.opacity = String(Math.max(0.25, parsed.a));
        preview.classList.remove('is-empty');
        return;
    }
    preview.style.background = 'transparent';
    preview.style.opacity = '1';
    preview.classList.add('is-empty');
}

function syncThemeColorControls(fieldKey, value) {
    const colorInput = document.querySelector(`[data-theme-color="${fieldKey}"]`);
    const alphaInput = document.querySelector(`[data-theme-alpha="${fieldKey}"]`);
    const alphaValue = document.querySelector(`[data-theme-alpha-value="${fieldKey}"]`);
    const parsed = parseCssColor(value);
    if (colorInput) colorInput.value = parsed ? rgbaToCss(parsed, false) : '#1d8cff';
    if (alphaInput) alphaInput.value = String(Math.round((parsed ? parsed.a : 1) * 100));
    if (alphaValue) alphaValue.textContent = `${Math.round((parsed ? parsed.a : 1) * 100)}%`;
    syncThemeFieldPreview(fieldKey, value);
}

function buildThemeColorValue(fieldKey) {
    const field = getThemeFieldDef(fieldKey);
    const colorInput = document.querySelector(`[data-theme-color="${fieldKey}"]`);
    const alphaInput = document.querySelector(`[data-theme-alpha="${fieldKey}"]`);
    const textInput = document.querySelector(`[data-theme-field="${fieldKey}"]`);
    if (!field || !colorInput || !textInput) return null;
    const parsed = hexToRgba(colorInput.value) || { r: 29, g: 140, b: 255, a: 1 };
    parsed.a = field.type === 'color-alpha' && alphaInput ? clampThemeNumber(Number(alphaInput.value) / 100, 0, 1) : 1;
    const cssValue = rgbaToCss(parsed, field.type === 'color-alpha');
    textInput.value = cssValue;
    syncThemeColorControls(fieldKey, cssValue);
    return cssValue;
}

function themeDraftFromEditor() {
    const preset = (MDT.els.themePresetSelect?.value || MDT.state.themeSettings?.preset || 'blue-command').trim() || 'blue-command';
    const label = (MDT.els.themeLabelInput?.value || (THEME_PRESETS[preset] || {}).label || 'Theme').trim() || ((THEME_PRESETS[preset] || {}).label || 'Theme');
    const vars = {};
    THEME_EDITOR_FIELDS.forEach(field => {
        const el = document.querySelector(`[data-theme-field="${field.key}"]`);
        if (!el) return;
        const value = String(el.value || '').trim();
        if (value) vars[field.key] = value;
    });
    return normalizeThemeSettings({ preset, label, vars });
}

function fillThemeEditor(theme) {
    const normalized = normalizeThemeSettings(theme);
    const resolved = resolveThemeSettings(normalized);
    if (MDT.els.themePresetSelect) MDT.els.themePresetSelect.value = resolved.preset;
    if (MDT.els.themeLabelInput) MDT.els.themeLabelInput.value = resolved.label || (THEME_PRESETS[resolved.preset] || {}).label || '';
    THEME_EDITOR_FIELDS.forEach(field => {
        const el = document.querySelector(`[data-theme-field="${field.key}"]`);
        if (el) {
            el.value = resolved.vars[field.key] || '';
            if (AUTO_DERIVED_THEME_FIELDS.includes(field.key)) {
                el.dataset.autoDerived = '1';
            }
            syncThemeColorControls(field.key, el.value);
        }
    });
    syncDerivedThemeFields(true);
}

function renderThemePresetCards() {
    const grid = MDT.els.themePresetsGrid;
    const select = MDT.els.themePresetSelect;
    if (!grid || !select) return;
    const activePreset = (MDT.els.themePresetSelect?.value || MDT.state.themeSettings?.preset || 'blue-command');
    select.innerHTML = Object.values(THEME_PRESETS).map(preset => `<option value="${escapeAttr(preset.key)}">${escapeHtml(preset.label)}</option>`).join('');
    select.value = activePreset;
    grid.innerHTML = Object.values(THEME_PRESETS).map(preset => {
        const swatches = ['accent', 'accent-2', 'bg-card', 'bg-main'].map(key => `<span class="mdt-theme-swatch" style="background:${escapeAttr(preset.vars[key] || '#000')};"></span>`).join('');
        return `
            <button type="button" class="mdt-theme-preset ${preset.key === activePreset ? 'is-active' : ''}" data-theme-preset-card="${escapeAttr(preset.key)}">
                <div class="mdt-theme-preset-header">
                    <span class="mdt-theme-preset-title">${escapeHtml(preset.label)}</span>
                    <span class="mdt-row-tag">${escapeHtml(preset.key)}</span>
                </div>
                <div class="mdt-theme-preset-desc">${escapeHtml(preset.description || '')}</div>
                <div class="mdt-theme-swatches">${swatches}</div>
            </button>
        `;
    }).join('');
}

function renderThemeEditorFields() {
    const container = MDT.els.themeEditorFields;
    if (!container || container.dataset.ready === '1') return;

    const sections = [];
    const seen = new Set();
    THEME_EDITOR_FIELDS.forEach(field => {
        const section = field.section || 'Theme';
        if (!seen.has(section)) {
            seen.add(section);
            sections.push(section);
        }
    });

    container.innerHTML = sections.map(section => {
        const fieldsHtml = THEME_EDITOR_FIELDS.filter(field => (field.section || 'Theme') === section).map(field => {
            const isColor = field.type === 'color' || field.type === 'color-alpha';
            const isGradient = field.type === 'gradient';
            const isLong = ['gradient', 'border', 'shadow', 'font'].includes(field.type);
            const helper = isColor
                ? (field.type === 'color-alpha' ? 'Color wheel + opacity slider. Text stays synced as rgba or hex.' : 'Color wheel + hex value.')
                : isGradient
                    ? 'Use any CSS gradient value for bars and buttons.'
                    : field.type === 'shadow'
                        ? 'Use a CSS box-shadow value.'
                        : field.type === 'size'
                            ? 'Use px, rem, %, or similar size values.'
                            : field.type === 'border'
                                ? 'Use a full CSS border value like 1px solid rgba(125,182,255,0.22).'
                                : 'Free-form CSS value.';
            const inputMarkup = isLong
                ? `<textarea id="theme-field-${escapeAttr(field.key)}" class="mdt-theme-css-input" rows="2" data-theme-field="${escapeAttr(field.key)}" placeholder="${isColor ? 'Color value' : isGradient ? 'CSS gradient' : 'CSS value'}"></textarea>`
                : `<input id="theme-field-${escapeAttr(field.key)}" type="text" data-theme-field="${escapeAttr(field.key)}" placeholder="${isColor ? 'Color value' : isGradient ? 'CSS gradient' : 'CSS value'}" />`;
            return `
                <div class="mdt-theme-field ${isColor ? 'mdt-theme-field-color' : ''} ${isLong ? 'mdt-theme-field-wide' : ''}" data-theme-field-wrap="${escapeAttr(field.key)}">
                    <label for="theme-field-${escapeAttr(field.key)}">${escapeHtml(field.label)}</label>
                    ${isColor ? `
                        <div class="mdt-theme-color-tools">
                            <div class="mdt-theme-color-top">
                                <div class="mdt-theme-color-picker-wrap">
                                    <input id="theme-color-${escapeAttr(field.key)}" class="mdt-theme-color-picker" type="color" data-theme-color="${escapeAttr(field.key)}" />
                                </div>
                                <span class="mdt-theme-color-preview is-empty" data-theme-preview="${escapeAttr(field.key)}"></span>
                                ${field.type === 'color-alpha' ? `<span class="mdt-theme-alpha-value" data-theme-alpha-value="${escapeAttr(field.key)}">100%</span>` : '<span class="mdt-theme-alpha-placeholder">Solid</span>'}
                            </div>
                            ${field.type === 'color-alpha' ? `
                                <div class="mdt-theme-alpha-wrap">
                                    <input class="mdt-theme-alpha-slider" type="range" min="0" max="100" value="100" data-theme-alpha="${escapeAttr(field.key)}" />
                                    <span class="mdt-theme-alpha-mini">Opacity</span>
                                </div>
                            ` : ''}
                        </div>
                    ` : ''}
                    ${inputMarkup}
                    <div class="mdt-theme-field-help">${escapeHtml(helper)}</div>
                </div>
            `;
        }).join('');
        return `
            <section class="mdt-theme-section">
                <div class="mdt-theme-section-title">${escapeHtml(section)}</div>
                <div class="mdt-theme-fields-grid">${fieldsHtml}</div>
            </section>
        `;
    }).join('');

    container.dataset.ready = '1';
}

function renderThemeStudio() {
    renderThemeEditorFields();
    renderThemePresetCards();
    fillThemeEditor(MDT.state.themeSettings || { preset: 'blue-command', label: 'Blue Command', vars: {} });
    if (MDT.els.themeEditorStatus) {
        if (!(MDT.state.officer && MDT.state.officer.isAdmin)) {
            MDT.els.themeEditorStatus.textContent = 'Only MDT admins can manage the global theme.';
        } else if (!MDT.state.isAdmin) {
            MDT.els.themeEditorStatus.textContent = 'Enter admin mode in Employees to save global theme changes.';
        } else {
            MDT.els.themeEditorStatus.textContent = 'Theme changes are applied live in the preview. Color fields use the color wheel, and global save happens when you press Apply Global Theme.';
        }
    }
    applyTheme(MDT.state.themeSettings);
}

function applyThemeFromEditor() {
    const draft = themeDraftFromEditor();
    applyTheme(draft);
    return draft;
}

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

function playFallbackBeep(name) {
    try {
        const AudioCtx = window.AudioContext || window.webkitAudioContext;
        if (!AudioCtx) return;
        MDT.state.audioCtx = MDT.state.audioCtx || new AudioCtx();
        const ctx = MDT.state.audioCtx;
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        const now = ctx.currentTime || 0;
        const profile = name === 'panic'
            ? { freq: 880, gain: 0.06, len: 0.22 }
            : name === 'bolo'
                ? { freq: 660, gain: 0.045, len: 0.16 }
                : { freq: 740, gain: 0.05, len: 0.18 };
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(profile.freq, now);
        gain.gain.setValueAtTime(0.0001, now);
        gain.gain.exponentialRampToValueAtTime(profile.gain, now + 0.01);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + profile.len);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + profile.len + 0.02);
    } catch (e) {
        console.warn('[az_mdt] fallback beep failed', name, e);
    }
}

function playSound(name) {
    const snd = MDT_AUDIO[name];
    if (!snd) {
        playFallbackBeep(name);
        return;
    }
    try {
        snd.currentTime = 0;
        const playPromise = snd.play();
        if (playPromise && typeof playPromise.catch === 'function') {
            playPromise.catch(() => playFallbackBeep(name));
        }
    } catch (e) {
        console.warn('[az_mdt] playSound failed', name, e);
        playFallbackBeep(name);
    }
}


function stripDispatchTokenPrefix(value) {
    let text = String(value == null ? '' : value).trim();
    if (!text) return '';
    text = text.replace(/^(?:\[[^\]]+\]\s*)+/, '');
    text = text.replace(/^(?:\([^\)]+\)\s*)+/, '');
    text = text.replace(/^(?:\{[^\}]+\}\s*)+/, '');
    return text.trim();
}

function prettifyServiceLabel(value) {
    const raw = String(value == null ? '' : value).trim();
    const normalized = raw.toLowerCase();
    if (!normalized) return 'Call';
    if (normalized === 'ems') return 'EMS';
    if (normalized === 'leo' || normalized === '5pd') return 'Police';
    if (normalized === 'fire') return 'Fire';
    if (normalized === 'parkranger' || normalized === 'park_ranger' || normalized === 'park-ranger' || normalized === 'ranger' || normalized === 'parkrangers') return 'Park Ranger';
    if (normalized === '911') return '911';
    return raw.replace(/[_-]+/g, ' ').replace(/\w/g, c => c.toUpperCase());
}

function speak(text) {
    if (!MDT.state.ttsEnabled) return;
    if (!text || !window.speechSynthesis || typeof SpeechSynthesisUtterance === 'undefined') {
        console.warn('[az_mdt] TTS unavailable');
        return;
    }
    try {
        const synth = window.speechSynthesis;
        const u = new SpeechSynthesisUtterance(String(text));
        u.lang = 'en-US';
        u.rate = 1.0;
        u.pitch = 1.0;
        u.volume = 1.0;

        const voices = typeof synth.getVoices === 'function' ? synth.getVoices() : [];
        const preferred = voices.find(v => /en-US/i.test(v.lang || '')) || voices.find(v => /en/i.test(v.lang || ''));
        if (preferred) u.voice = preferred;

        try { synth.cancel(); } catch (_) {}
        synth.speak(u);
        try { synth.resume(); } catch (_) {}
    } catch (e) {
        console.warn('[az_mdt] TTS failed', e);
    }
}


function buildCallSpeechText(call) {
    call = call || {};
    const service = prettifyServiceLabel(call.service || call.type || 'Call');
    const callId = call.id != null ? String(call.id) : '';
    const status = String(call.status || 'ACTIVE').trim();
    const caller = String(call.caller || '').trim();
    const units = Array.isArray(call.units)
        ? call.units.map(u => String((u && (u.callsign || u.unit || u.name)) || '').trim()).filter(Boolean).join(', ')
        : String(call.unitsLabel || '').trim();
    const time = String(call.created_at || call.createdAt || '').trim();
    const location = String(call.location || call.street || call.notificationMessage || '').trim();
    const details = stripDispatchTokenPrefix(String(call.message || call.details || call.reason || '').trim());
    const parts = [];
    parts.push(`${service}${callId ? ` call ${callId}` : ''}.`);
    if (status) parts.push(`Status ${status}.`);
    if (caller) parts.push(`Caller ${caller}.`);
    if (units) parts.push(`Units ${units}.`);
    if (time) parts.push(`Time ${time}.`);
    if (location) parts.push(`Location ${location}.`);
    if (details) parts.push(details.endsWith('.') ? details : `${details}.`);
    parts.push('Press E to respond.');
    return parts.join(' ');
}

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

function getBrowserBasePath() {
    const raw = String(window.location.pathname || '/');
    if (raw.endsWith('/')) return raw;
    const tail = raw.split('/').pop() || '';
    const looksLikeFile = tail.includes('.');
    if (!looksLikeFile && raw !== '/') return `${raw}/`;
    const lastSlash = raw.lastIndexOf('/');
    if (lastSlash >= 0) return raw.slice(0, lastSlash + 1);
    return '/';
}

function getBrowserToken() {
    try {
        const params = new URLSearchParams(window.location.search || '');
        const token = (params.get('token') || '').trim();
        if (token) {
            window.localStorage.setItem('az_mdt_web_token', token);
            return token;
        }
        return (window.localStorage.getItem('az_mdt_web_token') || '').trim();
    } catch (e) {
        return '';
    }
}

function buildBrowserApiUrl(path, params) {
    const base = getBrowserBasePath();
    const clean = String(path || '').replace(/^\/+/, '');
    const url = new URL(`${base}${clean}`, window.location.origin);
    const query = params || {};
    Object.entries(query).forEach(([key, value]) => {
        if (value === undefined || value === null || value === '') return;
        url.searchParams.set(key, typeof value === 'object' ? JSON.stringify(value) : String(value));
    });
    const token = getBrowserToken();
    if (token) {
        url.searchParams.set('token', token);
    }
    return url.toString();
}

function buildBrowserRelativeUrl(path, params) {
    const base = getBrowserBasePath();
    const clean = String(path || '').replace(/^\/+/, '');
    const url = new URL(`${base}${clean}`, window.location.origin);
    Object.entries(params || {}).forEach(([key, value]) => {
        if (value === undefined || value === null || value === '') return;
        url.searchParams.set(key, typeof value === 'object' ? JSON.stringify(value) : String(value));
    });
    return url.toString();
}

function setWebAuthState(auth) {
    MDT.state.webAuth = {
        configured: false,
        authenticated: false,
        linked: false,
        loginUrl: buildBrowserRelativeUrl('auth/login'),
        logoutUrl: buildBrowserRelativeUrl('auth/logout'),
        user: null,
        ...(auth || {})
    };

    if (!MDT_RUNTIME.isBrowser) return;

    if (MDT.els.webLoginBtn) {
        MDT.els.webLoginBtn.href = MDT.state.webAuth.loginUrl || buildBrowserRelativeUrl('auth/login');
    }

    if (MDT.els.webAuthFooter) {
        const user = MDT.state.webAuth.user || {};
        if (!MDT.state.webAuth.configured) {
            MDT.els.webAuthFooter.textContent = 'Set Config.Web.DiscordOAuth.clientId / clientSecret / redirectUri in config.lua, and add the redirect URI in your Discord developer portal.';
        } else if (!MDT.state.webAuth.authenticated) {
            MDT.els.webAuthFooter.textContent = 'Your login session is stored with a cookie so you do not have to sign in every visit.';
        } else if (!MDT.state.webAuth.linked) {
            MDT.els.webAuthFooter.textContent = `Logged in as ${user.globalName || user.username || 'Discord user'}. Enter the one-time in-game link code to connect your account.`;
        } else {
            MDT.els.webAuthFooter.textContent = `Linked as ${user.linkedName || user.globalName || user.username || 'Discord user'}.`;
        }
    }

    if (MDT.els.webAuthMessage) {
        if (!MDT.state.webAuth.configured) {
            MDT.els.webAuthMessage.textContent = 'Discord OAuth is not configured yet.';
        } else if (!MDT.state.webAuth.authenticated) {
            MDT.els.webAuthMessage.textContent = 'Sign in with Discord to access the fullscreen CAD/MDT website.';
        } else if (!MDT.state.webAuth.linked) {
            MDT.els.webAuthMessage.textContent = 'You are logged in. Press Link Website in-game, then enter that code here.';
        } else {
            MDT.els.webAuthMessage.textContent = 'Website linked successfully.';
        }
    }

    if (MDT.els.webAuthLogin) MDT.els.webAuthLogin.classList.toggle('hidden', MDT.state.webAuth.authenticated || !MDT.state.webAuth.configured);
    if (MDT.els.webAuthLink) MDT.els.webAuthLink.classList.toggle('hidden', !MDT.state.webAuth.authenticated || MDT.state.webAuth.linked);
    if (MDT.els.webAuthOverlay) MDT.els.webAuthOverlay.classList.toggle('hidden', !!(MDT.state.webAuth.authenticated && MDT.state.webAuth.linked));
    if (MDT.els.webLogoutBtn) MDT.els.webLogoutBtn.classList.toggle('hidden', !MDT.state.webAuth.authenticated);
}

async function browserFetchJson(path, params) {
    const headers = {
        'Accept': 'application/json',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache'
    };
    const token = getBrowserToken();
    if (token) headers['x-az-mdt-token'] = token;

    const mergedParams = { ...(params || {}), _ts: Date.now() };
    const response = await fetch(buildBrowserApiUrl(path, mergedParams), {
        method: 'GET',
        headers,
        cache: 'no-store',
        credentials: 'same-origin'
    });

    const text = await response.text();
    let payload = null;
    try {
        payload = text ? JSON.parse(text) : null;
    } catch (e) {
        payload = { ok: false, error: text || `HTTP ${response.status}` };
    }

    if (!response.ok) {
        const message = payload && (payload.error || payload.message) ? (payload.error || payload.message) : `HTTP ${response.status}`;
        throw new Error(message);
    }

    return payload;
}

function dispatchIncoming(action, data) {
    handleIncomingMessage({ action, data });
}

async function browserHandleAction(name, data) {
    const payload = data || {};
    try {
        switch (name) {
            case 'close':
            case 'closeMDT':
            case 'mdt:close':
                hideRoot();
                return;
            case 'GetBolos': {
                const rows = await browserFetchJson('api/bolos');
                dispatchIncoming('boloList', rows.rows || []);
                return;
            }
            case 'GetReports': {
                const rows = await browserFetchJson('api/reports');
                dispatchIncoming('reportList', rows.rows || []);
                return;
            }
            case 'GetUnits': {
                const rows = await browserFetchJson('api/units');
                dispatchIncoming('unitsUpdate', rows.rows || []);
                return;
            }
            case 'GetCalls': {
                const rows = await browserFetchJson('api/calls');
                dispatchIncoming('callList', rows.rows || []);
                return;
            }
            case 'GetWarrants': {
                const rows = await browserFetchJson('api/warrants');
                dispatchIncoming('warrantsList', rows.rows || []);
                return;
            }
            case 'GetActionLog': {
                const rows = await browserFetchJson('api/action-log');
                dispatchIncoming('actionLog', rows.rows || []);
                return;
            }
            case 'GetThemeSettings': {
                const result = await browserFetchJson('api/theme');
                dispatchIncoming('themeSettings', result.theme || {});
                return result.theme || {};
            }
            case 'GetLiveMapIcons': {
                const result = await browserFetchJson('api/live-map-icons');
                dispatchIncoming('liveMapIcons', result.liveMap || {});
                return result.liveMap || {};
            }
            case 'SaveLiveMapIcons': {
                const result = await browserFetchJson('api/action/save-live-map-icons', { icons: JSON.stringify(payload || {}) });
                dispatchIncoming('liveMapIcons', result.liveMap || {});
                if (result && result.message) {
                    pushNotification({ type: 'success', title: 'LiveMap', message: result.message });
                }
                return result.liveMap || {};
            }
            case 'ViewEmployees': {
                const rows = await browserFetchJson('api/employees');
                dispatchIncoming('employeesList', rows.rows || []);
                return rows.rows || [];
            }
            case 'SaveEmployeeAccess': {
                const result = await browserFetchJson('api/action/save-employee-access', payload);
                dispatchIncoming('employeesList', result.rows || []);
                const editedRowId = String(payload.id || payload.employeeId || '');
                if (editedRowId) {
                    const state = employeeAccessState();
                    state.lastSavedAt = Date.now();
                    state.open[editedRowId] = true;
                    const match = (result.rows || []).find((row) => String(row.id || '') === editedRowId);
                    if (match) {
                        state.drafts[editedRowId] = { ...normalizedEmployeePerms(match) };
                    }
                    if (match && rowLikelyMatchesCurrentViewer(match)) {
                        await browserBootstrap(true);
                        queueLiveRefresh(200);
                    }
                }
                if (result && result.message) {
                    pushNotification({ type: 'success', title: 'Employee Access', message: result.message });
                }
                return result.rows || [];
            }
            case 'SetOtherUnitStatus': {
                const rows = await browserFetchJson('api/action/set-unit-status', { targetId: payload.targetId || payload.id || payload.sourceId, status: payload.status });
                dispatchIncoming('unitsUpdate', rows.rows || []);
                return;
            }
            case 'DispatchStatusCheck': {
                await browserFetchJson('api/action/dispatch-status-check', { targetId: payload.targetId || payload.id || payload.sourceId });
                return;
            }
            case 'SaveThemeSettings': {
                const result = await browserFetchJson('api/action/save-theme', { theme: JSON.stringify(payload || {}) });
                dispatchIncoming('themeSettings', result.theme || payload || {});
                if (result && result.message) {
                    pushNotification({ type: 'success', title: 'Theme Updated', message: result.message });
                }
                return result.theme || {};
            }
            case 'RequestLeoChat': {
                const rows = await browserFetchJson('api/leo-chat');
                dispatchIncoming('leoChatHistory', rows.rows || []);
                return;
            }
            case 'RequestChatHistory': {
                const rows = await browserFetchJson('api/live-chat');
                dispatchIncoming('liveChatHistory', rows.rows || []);
                return;
            }
            case 'CreateBolo': {
                await browserFetchJson('api/action/create-bolo', payload);
                const rows = await browserFetchJson('api/bolos');
                dispatchIncoming('boloList', rows.rows || []);
                return;
            }
            case 'CreateReport': {
                await browserFetchJson('api/action/create-report', payload);
                const rows = await browserFetchJson('api/reports');
                dispatchIncoming('reportList', rows.rows || []);
                return;
            }
            case 'CreateQuickNote': {
                const result = await browserFetchJson('api/action/create-quick-note', payload);
                queueLiveRefresh(160);
                if (result && result.message) {
                    pushNotification({ type: 'success', title: 'Quick Note', message: result.message });
                }
                return result || true;
            }
            case 'DeleteQuickNote': {
                await browserFetchJson('api/action/delete-quick-note', payload);
                return;
            }
            case 'SetIdentityFlags': {
                const flagsPayload = { ...payload, flags: JSON.stringify(payload.flags || {}) };
                const result = await browserFetchJson('api/action/set-identity-flags', flagsPayload);
                queueLiveRefresh(160);
                if (result && result.message) {
                    pushNotification({ type: 'success', title: 'Identity Flags', message: result.message });
                }
                return result || true;
            }
            case 'CreateWarrant': {
                await browserFetchJson('api/action/create-warrant', payload);
                const rows = await browserFetchJson('api/warrants');
                dispatchIncoming('warrantsList', rows.rows || []);
                return;
            }
            case 'LiveChatSend': {
                const rows = await browserFetchJson('api/action/live-chat-send', payload);
                dispatchIncoming('liveChatHistory', rows.rows || []);
                return;
            }
            case 'LeoChatSend': {
                const rows = await browserFetchJson('api/action/leo-chat-send', payload);
                dispatchIncoming('leoChatHistory', rows.rows || []);
                return;
            }
            case 'CallRoomSend': {
                const rows = await browserFetchJson('api/action/call-room-send', payload);
                dispatchIncoming('callRoomOpened', rows.room || {});
                return;
            }
            case 'CallRoomNote': {
                const rows = await browserFetchJson('api/action/call-room-note', payload);
                dispatchIncoming('callRoomOpened', rows.room || {});
                return;
            }
            case 'AttachCall': {
                const rows = await browserFetchJson('api/action/attach-call', { id: payload.id || payload.callId });
                dispatchIncoming('callList', rows.rows || []);
                if (rows.room) dispatchIncoming('callRoomOpened', rows.room);
                return;
            }
            case 'DetachCall': {
                const rows = await browserFetchJson('api/action/detach-call', { id: payload.id || payload.callId });
                dispatchIncoming('callList', rows.rows || []);
                if (rows.room) dispatchIncoming('callRoomOpened', rows.room);
                return;
            }
            case 'AdminDeleteBolo': {
                const rows = await browserFetchJson('api/action/delete-bolo', payload);
                dispatchIncoming('boloList', rows.rows || []);
                return;
            }
            case 'AdminDeleteReport': {
                const rows = await browserFetchJson('api/action/delete-report', payload);
                dispatchIncoming('reportList', rows.rows || []);
                return;
            }
            case 'AdminDeleteWarrant': {
                const rows = await browserFetchJson('api/action/delete-warrant', payload);
                dispatchIncoming('warrantsList', rows.rows || []);
                return;
            }
            case 'AdminDeleteCall': {
                const rows = await browserFetchJson('api/action/delete-call', payload);
                dispatchIncoming('callList', rows.rows || []);
                return;
            }
            case 'NameSearch': {
                const rows = await browserFetchJson('api/search/name', { first: payload.first, last: payload.last, term: payload.term });
                dispatchIncoming('nameResults', rows);
                return;
            }
            case 'PlateSearch': {
                const rows = await browserFetchJson('api/search/plate', { plate: payload.plate, term: payload.term });
                dispatchIncoming('plateResults', rows);
                return;
            }
            case 'WeaponSearch': {
                const rows = await browserFetchJson('api/search/weapon', { serial: payload.serial, term: payload.term });
                dispatchIncoming('weaponResults', rows);
                return;
            }
            case 'SearchReports': {
                const rows = await browserFetchJson('api/search/reports', { query: payload.query, term: payload.term });
                dispatchIncoming('reportSearchResults', rows.rows || []);
                return;
            }
            case 'SearchCivilianRegistry': {
                const rows = await browserFetchJson('api/search/civilians', { term: payload.term, name: payload.name });
                dispatchIncoming('civilianRegistry', rows.rows || []);
                return;
            }
            case 'SearchDMV': {
                const rows = await browserFetchJson('api/search/dmv', { term: payload.term, name: payload.name, plate: payload.plate });
                dispatchIncoming('dmvResults', rows.rows || []);
                return;
            }
            case 'SearchCallHistory': {
                const rows = await browserFetchJson('api/search/calls', { query: payload.query, term: payload.term });
                dispatchIncoming('callHistoryResults', rows.rows || []);
                return;
            }
            case 'RequestCallRoom': {
                const rows = await browserFetchJson('api/call-room', { id: payload.callId || payload.id });
                dispatchIncoming('callRoomOpened', rows);
                return;
            }
            case 'RequestMyCivilians': {
                const rows = await browserFetchJson('api/my/civilians');
                dispatchIncoming('myCivilians', rows.rows || []);
                return;
            }
            case 'UpdateUnitProfile': {
                const result = await browserFetchJson('api/action/update-unit-profile', payload);
                if (result && result.viewer) dispatchIncoming('unitProfileUpdated', result.viewer);
                if (result && result.message) {
                    pushNotification({ type: 'success', title: 'Profile Updated', message: result.message });
                }
                return result && result.viewer ? result.viewer : null;
            }
            default:
                pushNotification({
                    type: 'info',
                    title: 'Web Mode',
                    message: 'That action is only available inside FiveM.'
                });
                return;
        }
    } catch (err) {
        console.error('[az_mdt] browser action failed', name, err);
        pushNotification({
            type: 'error',
            title: 'Web Mode',
            message: err && err.message ? err.message : `Failed to load ${name}.`
        });
    }
}

function nuiPost(name, data) {
    if (!MDT_RUNTIME.isNui) {
        return browserHandleAction(name, data);
    }

    if (shouldSkipNuiPost(name, data)) {
        return Promise.resolve({ skipped: true, name });
    }

    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
        body: JSON.stringify(data || {})
    }).catch(err => {
        console.error('[az_mdt] NUI post failed', name, err);
        throw err;
    });
}

const NUI_POST_GUARD_WINDOWS = {
    PlateSearch: 900,
    NameSearch: 900,
    WeaponSearch: 900,
    GetBolos: 1500,
    GetReports: 1500,
    GetUnits: 500,
    GetCalls: 500,
    GetWarrants: 1500,
    RequestLeoChat: 1000,
    SearchCallHistory: 900,
    SearchCivilianRegistry: 600,
    SearchDMV: 600
};

function stableCloneForGuard(value) {
    if (Array.isArray(value)) {
        return value.map(stableCloneForGuard);
    }
    if (value && typeof value === 'object') {
        const out = {};
        Object.keys(value).sort().forEach((key) => {
            out[key] = stableCloneForGuard(value[key]);
        });
        return out;
    }
    return value;
}

function shouldSkipNuiPost(name, data) {
    if (!MDT_RUNTIME.isNui) return false;
    const windowMs = Number(NUI_POST_GUARD_WINDOWS[name] || 0);
    if (!windowMs) return false;

    const state = MDT.state.nuiPostGuard || (MDT.state.nuiPostGuard = {});
    const key = `${name}:${JSON.stringify(stableCloneForGuard(data || {}))}`;
    const now = Date.now();
    const lastAt = Number(state[key] || 0);

    if (lastAt && (now - lastAt) < windowMs) {
        return true;
    }

    state[key] = now;
    return false;
}

function showRoot() {
    if (!MDT.root) return;
    MDT.root.classList.remove('hidden');
}

function hideRoot() {
    if (!MDT.root) return;
    MDT.root.classList.add('hidden');
}

function pageStorageKey(role) {
    const mode = MDT_RUNTIME.isBrowser ? 'web' : 'nui';
    return `az_mdt_last_page_${mode}_${role || 'leo'}`;
}

function defaultPageForRole(role) {
    return (role || 'leo') === 'civ' ? 'civCenter' : 'dashboard';
}

function pageElementExists(id) {
    if (!id) return false;
    return !!document.querySelector(`[data-mdt-page="${id}"]`) || !!document.getElementById(`page-${id}`) || !!document.getElementById(id);
}

function isPageAllowedForRole(id, role) {
    if (!id) return false;
    if (!pageElementExists(id)) return false;
    if (role === 'civ' && id === 'themes') return false;
    if ((id === 'themes' || id === 'iaLogs') && !(MDT.state.officer?.isAdmin || MDT.state.isAdmin)) {
        return false;
    }
    return canUsePage(id);
}

function rememberActivePage(id, role) {
    try {
        window.localStorage.setItem(pageStorageKey(role), String(id || defaultPageForRole(role)));
    } catch (_) {}
}

function restoreActivePage(role) {
    const fallback = defaultPageForRole(role);
    try {
        const saved = (window.localStorage.getItem(pageStorageKey(role)) || '').trim();
        if (saved && pageElementExists(saved) && isPageAllowedForRole(saved, role)) {
            return saved;
        }
    } catch (_) {}
    return fallback;
}

function setActivePage(id, options = {}) {
    const role = MDT.state.role || 'leo';
    const previousPage = MDT.state.activePage || '';
    if (!pageElementExists(id) || !isPageAllowedForRole(id, role)) {
        id = defaultPageForRole(role);
    }
    MDT.state.activePage = id;
    rememberActivePage(id, role);
    const changedPage = previousPage !== id;

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

    if (window.AzMdtSimTools && typeof window.AzMdtSimTools.onPageActivated === 'function') {
        window.AzMdtSimTools.onPageActivated(id);
    }

    const pending = MDT.state.pendingExternalSearch;
    if (!MDT.state.replayingExternalSearch && pending && pending.page === id) {
        setTimeout(() => replayPendingExternalSearch(false), 0);
        setTimeout(() => replayPendingExternalSearch(false), 90);
    }

    if (!MDT_RUNTIME.isBrowser && changedPage && options.refresh !== false) {
        queueLiveRefresh(0);
    }
}

function initialsFromName(name) {
    if (!name) return 'AZ';
    const parts = name.trim().split(/\s+/);
    if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function escapeAttr(value) {
    return escapeHtml(value);
}

function conditionalButton(show, html) {
    return show ? html : '';
}

function notificationMeta(type) {
    const kind = String(type || 'info').toLowerCase();
    if (kind === 'success') return { icon: '✓', title: 'Success', cls: 'success' };
    if (kind === 'error') return { icon: '!', title: 'Error', cls: 'error' };
    if (kind === 'panic') return { icon: '!', title: 'Panic Alert', cls: 'panic' };
    if (kind === 'call') return { icon: '911', title: '911 Call', cls: 'call' };
    return { icon: 'i', title: 'Notification', cls: 'info' };
}

function pushNotification(data) {
    const stack = MDT.els.notifyStack || document.getElementById('mdt-notify-stack');
    if (!stack) return;

    const payload = data || {};
    const meta = notificationMeta(payload.type);
    const title = payload.title || meta.title;
    const message = payload.message || 'Notification';
    const duration = Math.max(2000, Number(payload.duration) || 4500);

    const item = document.createElement('div');
    item.className = `mdt-notify mdt-notify--${meta.cls}`;
    item.innerHTML = `
        <div class="mdt-notify-accent">${escapeHtml(meta.icon)}</div>
        <div class="mdt-notify-body">
            <div class="mdt-notify-title">${escapeHtml(title)}</div>
            <div class="mdt-notify-message">${escapeHtml(message)}</div>
        </div>
    `;

    stack.prepend(item);
    if (stack.children.length > 4) {
        const last = stack.lastElementChild;
        if (last) last.remove();
    }

    requestAnimationFrame(() => item.classList.add('is-visible'));
    const remove = () => {
        item.classList.add('is-leaving');
        setTimeout(() => item.remove(), 180);
    };
    window.setTimeout(remove, duration);
}

function pushNotify(data) {
    return pushNotification(data);
}

function emitCallBanner(call) {
    if (!call || !call.id) return;
    if (MDT.state.alertedCalls[call.id]) return;
    MDT.state.alertedCalls[call.id] = true;

    const loc = String(call.location || call.street || call.notificationMessage || 'unknown location').trim();
    const postal = call.postal ? ` • Postal ${call.postal}` : '';
    const serviceLabel = prettifyServiceLabel(call.service || call.type || '911');
    const title = call.notificationTitle || call.title || `New ${serviceLabel} Call #${call.id}`;
    const reason = stripDispatchTokenPrefix(String(call.message || call.details || call.reason || '').trim());
    const closedHint = MDT.root && MDT.root.classList.contains('hidden') ? ' • Press E to respond' : '';
    const caller = String(call.caller || '').trim();
    const units = Array.isArray(call.units)
        ? call.units.map(u => String((u && (u.callsign || u.unit || u.name)) || '').trim()).filter(Boolean).join(', ')
        : String(call.unitsLabel || '').trim();
    const time = String(call.created_at || call.createdAt || '').trim();
    const meta = [caller ? `Caller: ${caller}` : '', units ? `Units: ${units}` : '', time].filter(Boolean).join(' • ');
    const baseMessage = [loc + postal, reason, meta, closedHint ? closedHint.replace(/^\s*•\s*/, '') : ''].filter(Boolean).join(' • ');
    const message = stripDispatchTokenPrefix(String(call.notificationMessage || '').trim()) || baseMessage;
    pushNotify({
        type: call.notificationType || 'call',
        title,
        message,
        duration: Number(call.notificationDuration) || 12000
    });
}

const WEAPON_SERIAL_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function generateRandomWeaponSerial() {
    const chunk = (len) => {
        let out = '';
        for (let i = 0; i < len; i++) {
            out += WEAPON_SERIAL_ALPHABET.charAt(Math.floor(Math.random() * WEAPON_SERIAL_ALPHABET.length));
        }
        return out;
    };
    return `AZ-${chunk(4)}-${chunk(6)}`;
}

function ensureWeaponSerialValue(force = false) {
    const el = MDT.els && MDT.els.dmvWeaponSerial;
    if (!el) return '';
    if (force || !(el.value || '').trim()) {
        el.value = generateRandomWeaponSerial();
    }
    return (el.value || '').trim();
}

function selectedOwnedCivilianLabel() {
    const select = MDT.els.dmvCivilianSelect;
    if (!select) return '';
    const option = select.options[select.selectedIndex];
    if (!option) return '';
    const raw = option.textContent || option.label || '';
    return String(raw).replace(/\s*\(#\d+\)\s*$/, '').trim();
}

function canDeleteCivilian(row) {
    const o = MDT.state.officer || {};
    const isAdmin = !!o.isAdmin;
    const isOwner = !!(row && (
        (row.charid && o.charid && row.charid === o.charid) ||
        (row.discordid && o.discordid && row.discordid === o.discordid) ||
        (row.license && o.license && row.license === o.license)
    ));
    return { isAdmin, isOwner, allowed: isAdmin || isOwner };
}

function clearCallRoom(callId) {
    if (!callId || !MDT.state.callRooms[callId]) return;
    delete MDT.state.callRooms[callId];
    if (MDT.state.activeCallRoom === callId) {
        const remaining = Object.keys(MDT.state.callRooms).map(Number).sort((a, b) => b - a);
        MDT.state.activeCallRoom = remaining.length ? remaining[0] : null;
    }
    renderActiveCallRoom();
}


function canManageDispatchControls() {
    const officer = MDT.state.officer || {};
    return !!(MDT.state.isAdmin || MDT.state.canManageDispatch || officer.canManageDispatch || officer.isSupervisor);
}

function clearSearchView(type) {
    if (type === 'calls') {
        MDT.state.callHistory = [];
        if (MDT.els.callHistoryInput) MDT.els.callHistoryInput.value = '';
        renderCallHistory([]);
    } else if (type === 'civ') {
        MDT.state.civRegistry = [];
        if (MDT.els.civilianSearchInput) MDT.els.civilianSearchInput.value = '';
        renderCivilianRegistry([]);
    } else if (type === 'dmv') {
        MDT.state.dmvResults = [];
        if (MDT.els.dmvInput) MDT.els.dmvInput.value = '';
        renderDMVResults([]);
    }
}

function updateAdminUI() {
    const canAdmin = !!(MDT.state.officer && MDT.state.officer.isAdmin);
    const isAdmin = !!MDT.state.isAdmin && canAdmin;
    MDT.state.isAdmin = isAdmin;

    if (MDT.els.adminIndicator) {
        MDT.els.adminIndicator.style.display = isAdmin ? 'inline-flex' : 'none';
    }
    if (MDT.els.adminLoginRow) {
        MDT.els.adminLoginRow.classList.toggle('hidden', !canAdmin || isAdmin);
    }
    if (MDT.els.adminActionsRow) {
        MDT.els.adminActionsRow.classList.toggle('hidden', !isAdmin);
    }

    if (MDT.els.iaLogList) {
        renderActionLog(MDT.state.actionLog);
    }

    renderThemeStudio();
}

function statusLabel(code) {
    code = (code || 'AVAILABLE').toUpperCase();
    if (code === 'OFFDUTY') return '10-7 OFF DUTY';
    if (code === 'UNAVAILABLE') return '10-6 BUSY / UNAVAILABLE';
    if (code === 'PANIC') return 'PANIC BUTTON';
    if (code === 'ENROUTE') return '10-8 ENROUTE';
    if (code === 'ONSCENE') return '10-8 ONSCENE';
    if (code === 'TRANSPORT') return '10-8 TRANSPORT';
    if (code === 'HOSPITAL') return '10-8 HOSPITAL';
    return '10-8 AVAILABLE';
}

function renderOfficer() {
    const o = MDT.state.officer || {};
    const webMode = MDT_RUNTIME.isBrowser;
    if (MDT.els.officerName) MDT.els.officerName.textContent = o.name || 'Unknown';
    if (MDT.els.officerMeta) {
        const dept = o.department || (MDT.state.role === 'civ' ? 'civilian' : (MDT.state.role === 'dispatch' ? 'dispatch' : 'police'));
        const grade = o.grade || 0;
        const status = MDT.state.status || 'OFFDUTY';
        MDT.els.officerMeta.textContent = `${dept} · ${grade} · ${status}`;
    }
    if (MDT.els.officerInitials) {
        MDT.els.officerInitials.textContent = initialsFromName(o.name);
    }
    if (MDT.els.statusSelect) {
        MDT.els.statusSelect.value = (MDT.state.status || 'OFFDUTY').toUpperCase();
        MDT.els.statusSelect.style.display = (!webMode && isLeoLikeRole()) ? '' : 'none';
    }
    if (MDT.els.myStatus) {
        MDT.els.myStatus.textContent = webMode ? ((MDT.state.role === 'dispatch') ? 'DISPATCH ACCESS' : ((MDT.state.role === 'civ') ? 'CIVILIAN ACCESS' : 'WEB ACCESS')) : (isLeoLikeRole() ? statusLabel(MDT.state.status) : 'CIVILIAN ACCESS');
    }
    if (MDT.els.dutyBtn) {
        const onDuty = (MDT.state.status || '').toUpperCase() !== 'OFFDUTY';
        MDT.els.dutyBtn.style.display = (!webMode && isLeoLikeRole()) ? '' : 'none';
        MDT.els.dutyBtn.textContent = onDuty ? 'Go Off Duty' : 'Go On Duty';
    }
    if (MDT.els.panicBtn) {
        const onDuty = (MDT.state.status || '').toUpperCase() !== 'OFFDUTY';
        MDT.els.panicBtn.style.display = (!webMode && MDT.state.role === 'leo' && onDuty) ? '' : 'none';
    }
    if (MDT.els.exitBtn) {
        MDT.els.exitBtn.style.display = webMode ? 'none' : '';
    }
    renderTtsToggle();

    if (MDT.els.linkBtn) {
        MDT.els.linkBtn.style.display = (!webMode) ? '' : 'none';
    }
    if (MDT.els.webLogoutBtn) {
        MDT.els.webLogoutBtn.style.display = (webMode && MDT.state.webAuth && MDT.state.webAuth.authenticated) ? '' : 'none';
    }
    renderUnitControls();
    renderTtsToggle();
}

function renderUnitControls() {
    const role = MDT.state.role || 'leo';
    const officer = MDT.state.officer || {};
    const ui = officer.ui || {};
    const options = Array.isArray(ui.departments) ? ui.departments : [];
    const showProfile = role === 'leo' || role === 'dispatch';

    if (MDT.els.departmentSelect) {
        MDT.els.departmentSelect.style.display = showProfile ? '' : 'none';
        if (showProfile) {
            MDT.els.departmentSelect.innerHTML = options.map(opt => `<option value="${escapeAttr(opt.id || '')}">${escapeHtml(opt.label || opt.id || '')}</option>`).join('');
            MDT.els.departmentSelect.value = officer.department || '';
        }
    }

    if (MDT.els.nameInput) {
        MDT.els.nameInput.style.display = showProfile ? '' : 'none';
        if (showProfile) MDT.els.nameInput.value = officer.name || '';
    }

    if (MDT.els.callsignInput) {
        MDT.els.callsignInput.style.display = showProfile ? '' : 'none';
        if (showProfile) MDT.els.callsignInput.value = officer.callsign || '';
    }

    if (MDT.els.saveUnitBtn) {
        MDT.els.saveUnitBtn.style.display = showProfile ? '' : 'none';
    }
}

function renderOwnedCivilians() {
    const sel = MDT.els.dmvCivilianSelect;
    if (!sel) return;
    const list = MDT.state.myCivilians || [];
    if (!list.length) {
        sel.innerHTML = '<option value="">No civilians created yet</option>';
        MDT.state.selectedCivilianId = null;
        return;
    }
    sel.innerHTML = list.map(row => `<option value="${escapeAttr(String(row.id || ''))}">${escapeHtml(row.name || 'Unknown')} (#${escapeHtml(String(row.id || 0))})</option>`).join('');
    const hasSelected = list.some(row => String(row.id) === String(MDT.state.selectedCivilianId || ''));
    if (!hasSelected) MDT.state.selectedCivilianId = list[0].id;
    sel.value = String(MDT.state.selectedCivilianId || list[0].id || '');
}

function renderOwnedCivilianAssets() {
    const civId = String(MDT.state.selectedCivilianId || MDT.els.dmvCivilianSelect?.value || '');
    const row = (MDT.state.myCivilians || []).find(entry => String(entry.id) === civId) || null;
    const vehiclesEl = MDT.els.dmvOwnedVehicles;
    const weaponsEl = MDT.els.dmvOwnedWeapons;
    if (vehiclesEl) {
        const vehicles = row?.vehicles || [];
        vehiclesEl.innerHTML = vehicles.length
            ? vehicles.map(v => `
                <div class="mdt-row">
                    <div class="mdt-row-header">
                        <div class="mdt-row-title">${escapeHtml(v.plate || 'Unknown Plate')}</div>
                        <span class="mdt-row-tag">${escapeHtml(v.model || 'Vehicle')}</span>
                    </div>
                    <div class="mdt-row-actions">
                        <button class="btn btn-danger btn-xs" data-delete-owned-vehicle="${escapeAttr(String(v.id || 0))}" data-civilian-id="${escapeAttr(String(row?.id || 0))}">Remove</button>
                    </div>
                </div>`).join('')
            : '<div class="mdt-empty">No vehicles registered to this civilian.</div>';
    }
    if (weaponsEl) {
        const weapons = row?.weapons || [];
        weaponsEl.innerHTML = weapons.length
            ? weapons.map(w => `
                <div class="mdt-row">
                    <div class="mdt-row-header">
                        <div class="mdt-row-title">${escapeHtml(w.serial || 'Unknown Serial')}</div>
                        <span class="mdt-row-tag">${escapeHtml(w.type || 'Weapon')}</span>
                    </div>
                    <div class="mdt-row-actions">
                        <button class="btn btn-danger btn-xs" data-delete-owned-weapon="${escapeAttr(String(w.id || 0))}" data-civilian-id="${escapeAttr(String(row?.id || 0))}">Remove</button>
                    </div>
                </div>`).join('')
            : '<div class="mdt-empty">No weapons registered to this civilian.</div>';
    }
}

function renderCitizenAssetDropdowns(row) {
    const vehicles = row?.vehicles || [];
    const weapons = row?.weapons || [];
    const vehiclesHtml = `
        <details class="mdt-asset-details">
            <summary>Vehicles (${vehicles.length})</summary>
            ${vehicles.length ? vehicles.map(v => `<div class="mdt-asset-item"><span>${escapeHtml(v.plate || 'Unknown')}</span><span>${escapeHtml(v.model || 'Vehicle')}</span></div>`).join('') : '<div class="mdt-empty">No registered vehicles.</div>'}
        </details>`;
    const weaponsHtml = `
        <details class="mdt-asset-details">
            <summary>Weapons (${weapons.length})</summary>
            ${weapons.length ? weapons.map(w => `<div class="mdt-asset-item"><span>${escapeHtml(w.serial || 'Unknown')}</span><span>${escapeHtml(w.type || 'Weapon')}</span></div>`).join('') : '<div class="mdt-empty">No registered weapons.</div>'}
        </details>`;
    return `<div class="mdt-asset-group">${vehiclesHtml}${weaponsHtml}</div>`;
}

function refreshNameSearch() {
    const first = (MDT.els.nameFirst?.value || '').trim();
    const last = (MDT.els.nameLast?.value || '').trim();
    const term = `${first} ${last}`.trim();
    if (!term) return Promise.resolve();
    return Promise.resolve(nuiPost('NameSearch', buildNameSearchPayload(first, last)));
}

function getCallTtsMode() {
    return ((MDT.state.officer || {}).tts || {}).callMode || (((MDT.state.officer || {}).ui || {}).tts || {}).callMode || 'attached_only';
}

function shouldAnnounceCallRoom(callId) {
    const id = Number(callId || 0);
    if (!id) return false;
    const now = Date.now();
    const last = MDT.state.lastCallRoomAnnouncement || { id: null, at: 0 };
    if (last.id === id && (now - (last.at || 0)) < 2500) {
        return false;
    }
    MDT.state.lastCallRoomAnnouncement = { id, at: now };
    return true;
}

function getPanicTtsMode() {
    return ((MDT.state.officer || {}).tts || {}).panicMode || (((MDT.state.officer || {}).ui || {}).tts || {}).panicMode || 'all_onduty';
}

function getBoloTtsMode() {
    return ((MDT.state.officer || {}).tts || {}).boloMode || (((MDT.state.officer || {}).ui || {}).tts || {}).boloMode || 'all_onduty';
}

function showModal(type, ctx) {
    MDT.state.modalContext = { type, ...(ctx || {}) };
    if (!MDT.els.modalBackdrop) return;

    ['modalNote', 'modalFlags', 'modalWarrant', 'modalLink', 'modalVehicleRegister'].forEach(key => {
        if (MDT.els[key]) MDT.els[key].classList.add('hidden');
    });

    if (type === 'note') {
        if (MDT.els.noteTarget) MDT.els.noteTarget.textContent = ctx.targetLabel || ctx.targetValue || '';
        if (MDT.els.noteText) MDT.els.noteText.value = '';
        MDT.els.modalNote && MDT.els.modalNote.classList.remove('hidden');
    } else if (type === 'flags') {
        if (MDT.els.flagsTarget) MDT.els.flagsTarget.textContent = ctx.targetLabel || ctx.targetValue || '';
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
    } else if (type === 'link') {
        if (MDT.els.linkSite) MDT.els.linkSite.textContent = ctx.websiteUrl || '';
        if (MDT.els.linkCodeDisplay) MDT.els.linkCodeDisplay.value = ctx.code || '';
        if (MDT.els.linkExpiry) MDT.els.linkExpiry.textContent = ctx.expiresInMinutes ? `Expires in about ${ctx.expiresInMinutes} minute(s).` : '';
        MDT.els.modalLink && MDT.els.modalLink.classList.remove('hidden');
    } else if (type === 'vehicle-register') {
        if (MDT.els.vehicleRegisterPlate) MDT.els.vehicleRegisterPlate.value = ctx.plate || '';
        if (MDT.els.vehicleRegisterModel) MDT.els.vehicleRegisterModel.value = ctx.model || '';
        if (MDT.els.vehicleRegisterCivilian) {
            const civilians = Array.isArray(ctx.civilians) ? ctx.civilians : [];
            MDT.els.vehicleRegisterCivilian.innerHTML = civilians.map(row => `<option value="${escapeAttr(String(row.id || ''))}">${escapeHtml(row.name || 'Unknown')} (#${escapeHtml(String(row.id || 0))})</option>`).join('');
            if (civilians.length > 0) {
                MDT.els.vehicleRegisterCivilian.value = String(civilians[0].id || '');
            }
        }
        MDT.els.modalVehicleRegister && MDT.els.modalVehicleRegister.classList.remove('hidden');
    }

    MDT.els.modalBackdrop.classList.remove('hidden');
}

function closeModal() {
    MDT.state.modalContext = null;
    if (!MDT.els.modalBackdrop) return;
    MDT.els.modalBackdrop.classList.add('hidden');
    ['modalNote', 'modalFlags', 'modalWarrant', 'modalLink', 'modalVehicleRegister'].forEach(key => {
        if (MDT.els[key]) MDT.els[key].classList.add('hidden');
    });
}

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
            const safeNameAttr = escapeAttr(name);
            const lastSeen = c.last_seen || null;

            const flagsObj = (c.flags && c.flags.flags) || {};
            const flagNotes = (c.flags && c.flags.notes) || '';
            const flagLabels = [];
            if (flagsObj.officer_safety) flagLabels.push('Officer Safety');
            if (flagsObj.armed)          flagLabels.push('Armed & Dangerous');
            if (flagsObj.gang)           flagLabels.push('Gang Affiliation');
            if (flagsObj.mental_health)  flagLabels.push('Mental Health');

            const quickNotes = Array.isArray(c.quick_notes) ? c.quick_notes.slice(0, 5) : [];

            const flagsHtml = flagLabels.length
                ? `<div style="margin-top:4px;display:flex;flex-wrap:wrap;gap:4px;">
                        ${flagLabels.map(lbl => `<span class="mdt-row-tag">${lbl}</span>`).join('')}
                   </div>`
                : `<div style="margin-top:4px;font-size:11px;color:var(--text-muted);">No flags.</div>`;

            const notesHtml = quickNotes.length
                ? `<div style="margin-top:4px;font-size:11px;color:var(--text-muted);">
                        ${quickNotes.map(n => `<div class="quicknote-item"><span>${escapeHtml(n.note || '')}</span><button class="btn btn-danger btn-xs" data-delete-quicknote="${escapeAttr(String(n.id || 0))}">X</button></div>`).join('')}
                   </div>`
                : `<div style="margin-top:4px;font-size:11px;color:var(--text-muted);">No quick notes.</div>`;

            const lastSeenHtml = lastSeen
                ? `<div style="font-size:11px;">Last Seen: ${lastSeen}</div>`
                : `<div style="font-size:11px;">Last Seen: Unknown</div>`;

            const flagAttrs = `
                data-flags-officer-safety="${flagsObj.officer_safety ? '1' : '0'}"
                data-flags-armed="${flagsObj.armed ? '1' : '0'}"
                data-flags-gang="${flagsObj.gang ? '1' : '0'}"
                data-flags-mental="${flagsObj.mental_health ? '1' : '0'}"
                data-flags-notes="${escapeAttr(flagNotes)}"
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
                    ${conditionalButton(canUseAction('createReport'), `<button class="btn-xs btn-secondary" data-report-type="citation" data-target-type="name" data-target-value="${safeNameAttr}">New Ticket</button>`) }
                    ${conditionalButton(canUseAction('createReport'), `<button class="btn-xs btn-secondary" data-report-type="arrest" data-target-type="name" data-target-value="${safeNameAttr}">New Arrest</button>`) }
                    ${conditionalButton(canUseAction('createReport'), `<button class="btn-xs btn-secondary" data-report-type="incident" data-target-type="name" data-target-value="${safeNameAttr}">New Report</button>`) }
                    ${conditionalButton(canUseAction('quickNotes'), `<button class="btn-xs btn-secondary" data-quicknote-target-type="citizen" data-quicknote-target-value="${escapeAttr(String(c.id || ''))}" data-quicknote-target-label="${safeNameAttr}">Add Note</button>`) }
                    ${conditionalButton(canUseAction('flags'), `<button class="btn-xs btn-secondary" data-flags-target-type="citizen" data-flags-target-value="${escapeAttr(String(c.id || ''))}" data-flags-target-label="${safeNameAttr}" ${flagAttrs}>Flags</button>`) }
                    ${conditionalButton(canUseAction('createWarrant'), `<button class="btn-xs btn-secondary" data-warrant-name="${safeNameAttr}" data-warrant-charid="${c.charid || ''}">New Warrant</button>`) }
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
            const savedBy = rec.creator_identifier || rec.creator_name || rec.officer_name || '';

            row.innerHTML = `
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${title}</div>
                    <span class="mdt-row-tag">${(rec.rtype || rec.type || 'record').toUpperCase()}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>${rec.target_value || ''}</span>
                    <span>${ts}</span>
                    <span>${savedBy ? `Saved by: ${escapeHtml(savedBy)}` : `#${rec.id || ''}`}</span>
                </div>
                <div class="mdt-row-body">${body}</div>
            `;
            el.appendChild(row);
        });
    }
}

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
            const policy = String(v.policy_type || '').trim();
            const insuranceStatus = String(v.insurance_status || (policy ? (v.active ? 'ACTIVE' : 'INACTIVE') : 'NONE')).trim() || 'NONE';
            const registrationStatus = String(v.registration_status || 'VALID').trim() || 'VALID';
            const policyText = policy ? `${policy.toUpperCase()} (${insuranceStatus})` : `INSURANCE ${insuranceStatus}`;

            const safePlate = String(plate).replace(/"/g, '&quot;');

            row.innerHTML = `
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${plate}</div>
                    <span class="mdt-row-tag">${policyText}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>Model: ${model}</span>
                    <span>Owner: ${owner}</span>
                    <span>Registration: ${registrationStatus}</span>
                    <span>Insurance: ${insuranceStatus}</span>
                    <span>Discord: ${v.discordid || '—'}</span>
                </div>
                <div class="mdt-row-actions" style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap;">
                    ${conditionalButton(canUseAction('createReport'), `<button class="btn-xs btn-secondary" data-report-type="citation" data-target-type="plate" data-target-value="${safePlate}">New Ticket</button>`) }
                    ${conditionalButton(canUseAction('createReport'), `<button class="btn-xs btn-secondary" data-report-type="arrest" data-target-type="plate" data-target-value="${safePlate}">New Arrest</button>`) }
                    ${conditionalButton(canUseAction('createReport'), `<button class="btn-xs btn-secondary" data-report-type="incident" data-target-type="plate" data-target-value="${safePlate}">New Report</button>`) }
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
            const savedBy = rec.creator_identifier || rec.creator_name || rec.officer_name || '';

            row.innerHTML = `
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${title}</div>
                    <span class="mdt-row-tag">${(rec.rtype || rec.type || 'record').toUpperCase()}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>${rec.target_value || ''}</span>
                    <span>${ts}</span>
                    <span>${savedBy ? `Saved by: ${escapeHtml(savedBy)}` : `#${rec.id || ''}`}</span>
                </div>
                <div class="mdt-row-body">${body}</div>
            `;
            el.appendChild(row);
        });
    }
}

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
        if (canManageDispatchControls() && canUseAction('deleteBolo') && row.id) {
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
        if (MDT.state.isAdmin && canUseAction('deleteReport') && row.id) {
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

function normalizedEmployeePerms(row) {
    const base = { ...((row && row.permissions) || {}) };
    const role = String(base.role || ((row && row.mdt_role) || 'leo')).toLowerCase();
    const defaults = getRoleDefaults(role);
    return {
        role,
        loginRole: String(base.loginRole || (role === 'dispatch' ? 'dispatch' : (role === 'civ' ? 'civ' : 'leo'))).toLowerCase(),
        open: !!base.open,
        admin: !!base.admin,
        supervisor: !!base.supervisor,
        dispatch: !!base.dispatch,
        civ: !!base.civ,
        dmv: !!base.dmv,
        leochat: !!base.leochat,
        pages: { ...defaults.pages, ...((base.pages && typeof base.pages === 'object') ? base.pages : {}) },
        actions: { ...defaults.actions, ...((base.actions && typeof base.actions === 'object') ? base.actions : {}) }
    };
}

function applyRoleDefaultsToEmployeeEditor(editor, role) {
    if (!editor) return;
    const defaults = getRoleDefaults(role);
    const loginRoleInput = editor.querySelector('[data-employee-perm="loginRole"]');
    if (loginRoleInput) {
        loginRoleInput.value = role === 'dispatch' ? 'dispatch' : (role === 'civ' ? 'civ' : 'leo');
    }
    editor.querySelectorAll('[data-employee-perm]').forEach((input) => {
        const key = input.dataset.employeePerm;
        if (!key || input.type !== 'checkbox') return;
        if (Object.prototype.hasOwnProperty.call(defaults, key)) {
            input.checked = !!defaults[key];
        }
    });
    editor.querySelectorAll('[data-employee-page]').forEach((input) => {
        const key = input.dataset.employeePage;
        if (key && defaults.pages && Object.prototype.hasOwnProperty.call(defaults.pages, key)) {
            input.checked = !!defaults.pages[key];
        }
    });
    editor.querySelectorAll('[data-employee-action]').forEach((input) => {
        const key = input.dataset.employeeAction;
        if (key && defaults.actions && Object.prototype.hasOwnProperty.call(defaults.actions, key)) {
            input.checked = !!defaults.actions[key];
        }
    });
    const rowId = String(editor.dataset.employeeAccessEditor || '');
    if (rowId) {
        const state = employeeAccessState();
        state.open[rowId] = true;
        state.drafts[rowId] = collectEmployeeAccessEditorDraft(editor);
    }
}

function employeeAccessEditorHtml(row) {
    const perms = normalizedEmployeePerms(row);
    const pageEntries = [
        ['dashboard','Dashboard'],['liveMap','Live Map'],['nameSearch','Name Search'],['plateSearch','Plate Search'],['weaponSearch','Weapon Search'],
        ['bolos','BOLOs'],['reports','Reports'],['dutyChat','LEO Chat'],['callsHub','Calls Hub'],['civCenter','Civilian Center'],
        ['dmv','DMV'],['warrants','Warrants'],['employees','Employees'],['themes','Theme Studio'],['iaLogs','IA Logs']
    ];
    const actionEntries = [
        ['lookupName','Name Lookup'],['lookupPlate','Plate Lookup'],['lookupWeapon','Weapon Lookup'],['createBolo','Create BOLO'],
        ['deleteBolo','Delete BOLO'],['createReport','Create Report'],['deleteReport','Delete Report'],['createWarrant','Create Warrant'],
        ['deleteWarrant','Delete Warrant'],['attachCalls','Attach Calls'],['detachCalls','Detach Calls'],['waypointCalls','Waypoint Calls'],
        ['clearCalls','Clear Calls'],['statusCheck','Status Check'],['updateUnitStatus','Update Unit Status'],['editDmv','Edit DMV'],
        ['quickNotes','Quick Notes'],['flags','Flags'],['saveProfile','Save Profile'],['registerVehicle','Register Vehicle'],
        ['registerWeapon','Register Weapon'],['deleteCivilianAssets','Delete Civilian Assets'],['editEmployeeAccess','Edit Employee Access'],
        ['deleteEmployee','Delete Employee'],['viewActionLog','View IA Logs'],['sendLeoChat','Send LEO Chat']
    ];
    return `
        <div class="mdt-employee-access-editor" data-employee-access-editor="${row.id}">
            <div class="mdt-row-meta" style="margin-bottom:8px;">Set MDT access, dispatch routing, web login mode, visible sections, and action buttons for this employee.</div>
            <div class="mdt-access-grid">
                <label class="mdt-access-field">
                    <span>MDT Role</span>
                    <select data-employee-perm="role">
                        <option value="leo" ${perms.role === 'leo' ? 'selected' : ''}>LEO</option>
                        <option value="supervisor" ${perms.role === 'supervisor' ? 'selected' : ''}>Supervisor</option>
                        <option value="dispatch" ${perms.role === 'dispatch' ? 'selected' : ''}>Dispatch</option>
                        <option value="admin" ${perms.role === 'admin' ? 'selected' : ''}>Admin</option>
                        <option value="civ" ${perms.role === 'civ' ? 'selected' : ''}>Civilian</option>
                    </select>
                </label>
                <label class="mdt-access-field">
                    <span>Web Login Opens As</span>
                    <select data-employee-perm="loginRole">
                        <option value="leo" ${perms.loginRole === 'leo' ? 'selected' : ''}>LEO MDT</option>
                        <option value="dispatch" ${perms.loginRole === 'dispatch' ? 'selected' : ''}>Dispatch CAD</option>
                        <option value="civ" ${perms.loginRole === 'civ' ? 'selected' : ''}>Civilian MDT</option>
                    </select>
                </label>
            </div>
            <div class="mdt-access-checks">
                ${[
                    ['open', 'Open MDT'], ['admin', 'MDT Admin'], ['supervisor', 'Supervisor'], ['dispatch', 'Dispatch'],
                    ['civ', 'Civilian Access'], ['dmv', 'DMV'], ['leochat', 'LEO Chat']
                ].map(([key, label]) => `
                    <label class="mdt-check">
                        <input type="checkbox" data-employee-perm="${key}" ${perms[key] ? 'checked' : ''} />
                        <span>${label}</span>
                    </label>
                `).join('')}
            </div>
            <div class="mdt-access-panel-grid">
                <div class="mdt-access-panel">
                    <div class="mdt-access-panel-title">Visible Sections</div>
                    <div class="mdt-access-checks mdt-access-checks-compact">
                        ${pageEntries.map(([key, label]) => `
                            <label class="mdt-check">
                                <input type="checkbox" data-employee-page="${key}" ${perms.pages[key] ? 'checked' : ''} />
                                <span>${label}</span>
                            </label>
                        `).join('')}
                    </div>
                </div>
                <div class="mdt-access-panel">
                    <div class="mdt-access-panel-title">Buttons / Actions</div>
                    <div class="mdt-access-checks mdt-access-checks-compact">
                        ${actionEntries.map(([key, label]) => `
                            <label class="mdt-check">
                                <input type="checkbox" data-employee-action="${key}" ${perms.actions[key] ? 'checked' : ''} />
                                <span>${label}</span>
                            </label>
                        `).join('')}
                    </div>
                </div>
            </div>
            <div class="mdt-row-actions" style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap;">
                <button class="btn-xs btn-primary" data-employee-access-save="${row.id}">Save Access</button>
                <button class="btn-xs btn-secondary" data-employee-access-toggle="${row.id}">Close Editor</button>
            </div>
        </div>
    `;
}

function renderEmployees(list) {
    const container = MDT.els.employeeList;
    if (!container) return;

    snapshotEmployeeAccessEditors();
    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No employees found.</div>';
        return;
    }

    list.forEach(row => {
        const div = document.createElement('div');
        div.className = 'mdt-row';

        const perms = normalizedEmployeePerms(row);
        const showAdminTools = !!(MDT.state.isAdmin && MDT.state.officer && MDT.state.officer.isAdmin && canUseAction('editEmployeeAccess'));
        const dept = (row.active_department || row.department || 'police').toUpperCase();
        const roleLabel = String(perms.role || 'leo').toUpperCase();

        let adminControls = '';
        if (showAdminTools && row.id && (row.active_department || row.department)) {
            adminControls = `
                <div class="mdt-row-actions" style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap;">
                    <button class="btn-xs btn-secondary" data-employee-access-toggle="${row.id}">Edit MDT Access</button>
                    <button class="btn-xs btn-danger"
                            data-admin-action="delete-employee"
                            data-employee-id="${row.id}"
                            data-employee-dept="${row.active_department || row.department}">
                        Remove From Dept
                    </button>
                </div>
                ${employeeAccessEditorHtml(row)}
            `;
        }

        div.innerHTML = `
            <div class="mdt-row-header">
                <div class="mdt-row-title">${row.name || 'Unknown'}</div>
                <span class="mdt-row-tag">${dept}</span>
            </div>
            <div class="mdt-row-meta">
                <span>Char ID: ${row.charid || row.id || '—'}</span>
                <span>Callsign: ${row.callsign || '—'}</span>
                <span>Grade: ${row.paycheck || row.grade || '—'}</span>
                <span>Role: ${roleLabel}</span>
            </div>
            <div class="mdt-row-meta">
                <span>Open: ${perms.open ? 'Yes' : 'No'}</span>
                <span>Supervisor: ${perms.supervisor ? 'Yes' : 'No'}</span>
                <span>Dispatch: ${perms.dispatch ? 'Yes' : 'No'}</span>
                <span>Admin: ${perms.admin ? 'Yes' : 'No'}</span>
                <span>Web Mode: ${(perms.loginRole || 'leo').toUpperCase()}</span>
            </div>
            ${adminControls}
        `;
        container.appendChild(div);
    });

    restoreEmployeeAccessEditors();
}

function renderUnits(list) {
    const container = MDT.els.unitsList;
    if (!container) return;

    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No active units.</div>';
        renderLiveMap();
        return;
    }

    const canDispatchManage = (canUseDispatchRole() || canManageDispatchControls()) && (canUseAction('statusCheck') || canUseAction('updateUnitStatus'));
    const statuses = [
        ['AVAILABLE', '10-8 AVAILABLE'],
        ['UNAVAILABLE', '10-6 UNAVAILABLE'],
        ['ENROUTE', 'ENROUTE'],
        ['ONSCENE', 'ON SCENE'],
        ['TRANSPORT', 'TRANSPORT'],
        ['HOSPITAL', 'AT HOSPITAL'],
        ['OFFDUTY', '10-7 OFF DUTY']
    ];

    list.forEach(u => {
        const div = document.createElement('div');
        div.className = 'mdt-row';
        const canManageThis = canDispatchManage && String(u.id || '') !== getCurrentOfficerUnitId();
        const currentStatus = (u.status || 'AVAILABLE').toUpperCase();
        const actions = canManageThis ? `
            <div class="mdt-row-actions" style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap;align-items:center;">
                <select class="mdt-inline-select" data-unit-status-select="${u.id}">
                    ${statuses.map(([value, label]) => `<option value="${value}" ${value === currentStatus ? 'selected' : ''}>${label}</option>`).join('')}
                </select>
                <button class="btn-xs btn-secondary" data-unit-action="status-check" data-unit-id="${u.id}">Status Check</button>
                <button class="btn-xs btn-primary" data-unit-action="apply-status" data-unit-id="${u.id}">Update Status</button>
            </div>` : '';

        div.innerHTML = `
            <div class="mdt-row-header">
                <div class="mdt-row-title">${u.name || ('Unit ' + (u.id || ''))}</div>
                <span class="mdt-row-tag">${(u.department || 'police').toUpperCase()}</span>
            </div>
            <div class="mdt-row-meta">
                <span>Callsign: ${u.callsign || '—'}</span>
                <span>Status: ${u.status || 'AVAILABLE'}</span>
            </div>
            ${actions}
        `;
        container.appendChild(div);
    });

    renderLiveMap();
}


function getLiveMapDefaults() {
    return {
        enabled: true,
        updateIntervalMs: 1750,
        showPostalLabels: false,
        allowCustomIcons: true,
        mapImage: 'img/gta5-roadmap-2048.jpg',
        stageSize: 2048,
        bounds: { minX: -4200, maxX: 4500, minY: -4500, maxY: 8500 },
        mapRect: { left: 289, top: 35, right: 1730, bottom: 2046 },
        icons: {
            police: { className: 'fa-solid fa-car-side', imageUrl: '', label: 'Police', emoji: '🚓' },
            fire: { className: 'fa-solid fa-fire-truck', imageUrl: '', label: 'Fire', emoji: '🚒' },
            ems: { className: 'fa-solid fa-truck-medical', imageUrl: '', label: 'EMS', emoji: '🚑' }
        }
    };
}

function normalizeLiveMapService(value) {
    const v = String(value || '').trim().toLowerCase();
    if (['fire', 'firefighter', 'safd'].includes(v)) return 'fire';
    if (['ems', 'ambulance', 'paramedic', 'doctor', 'medical'].includes(v)) return 'ems';
    return 'police';
}

function getLiveMapState() {
    MDT.state.liveMap = MDT.state.liveMap || { config: {}, icons: {}, postals: [], filter: 'all', pendingUploads: {}, selectedUnitId: '', view: { scale: 1, x: 0, y: 0, ready: false, hasFitted: false }, dragging: { active: false, startX: 0, startY: 0, baseX: 0, baseY: 0 } };
    return MDT.state.liveMap;
}

function getLiveMapConfig() {
    const state = getLiveMapState();
    const defaults = getLiveMapDefaults();
    return {
        ...defaults,
        ...(state.config || {}),
        stageSize: Math.max(512, Number((state.config || {}).stageSize || defaults.stageSize) || defaults.stageSize),
        mapImage: String((state.config || {}).mapImage || defaults.mapImage || '').trim(),
        bounds: { ...(defaults.bounds || {}), ...(((state.config || {}).bounds) || {}) },
        mapRect: { ...(defaults.mapRect || {}), ...(((state.config || {}).mapRect) || {}) },
        icons: { ...(defaults.icons || {}), ...(state.icons || {}), ...((((state.config || {}).icons) || {})) }
    };
}

function applyLiveMapState(payload) {
    const state = getLiveMapState();
    const incoming = (payload && typeof payload === 'object') ? payload : {};
    const defaults = getLiveMapDefaults();
    state.config = {
        enabled: incoming.enabled !== false,
        updateIntervalMs: Number(incoming.updateIntervalMs || defaults.updateIntervalMs) || defaults.updateIntervalMs,
        showPostalLabels: incoming.showPostalLabels === true,
        allowCustomIcons: incoming.allowCustomIcons !== false,
        mapImage: String(incoming.mapImage || defaults.mapImage || '').trim(),
        stageSize: Math.max(512, Number(incoming.stageSize || defaults.stageSize) || defaults.stageSize),
        bounds: { ...(defaults.bounds || {}), ...((incoming.bounds && typeof incoming.bounds === 'object') ? incoming.bounds : {}) },
        mapRect: { ...(defaults.mapRect || {}), ...((incoming.mapRect && typeof incoming.mapRect === 'object') ? incoming.mapRect : {}) }
    };
    state.icons = { ...(defaults.icons || {}), ...((incoming.icons && typeof incoming.icons === 'object') ? incoming.icons : {}) };
    if (!Array.isArray(state.postals)) state.postals = [];
    renderLiveMapIconEditors();
    renderLiveMap();
}

function getLiveMapBounds() {
    const cfg = getLiveMapConfig();
    const bounds = cfg.bounds || {};
    return {
        minX: Number(bounds.minX ?? -4200),
        maxX: Number(bounds.maxX ?? 4500),
        minY: Number(bounds.minY ?? -4500),
        maxY: Number(bounds.maxY ?? 8500)
    };
}


function getLiveMapRect() {
    const cfg = getLiveMapConfig();
    const stageSize = Math.max(512, Number(cfg.stageSize || 2048) || 2048);
    const rect = (cfg.mapRect && typeof cfg.mapRect === 'object') ? cfg.mapRect : {};
    const left = Math.max(0, Math.min(stageSize - 1, Number(rect.left ?? 289) || 289));
    const top = Math.max(0, Math.min(stageSize - 1, Number(rect.top ?? 35) || 35));
    const right = Math.max(left + 1, Math.min(stageSize, Number(rect.right ?? 1730) || 1730));
    const bottom = Math.max(top + 1, Math.min(stageSize, Number(rect.bottom ?? 2046) || 2046));
    return { left, top, right, bottom, width: right - left, height: bottom - top };
}

function worldToLiveMapPoint(coords) {
    const bounds = getLiveMapBounds();
    const rect = getLiveMapRect();
    const x = Number(coords?.x || 0);
    const y = Number(coords?.y || 0);
    const nx = (x - bounds.minX) / Math.max(1, (bounds.maxX - bounds.minX));
    const ny = (y - bounds.minY) / Math.max(1, (bounds.maxY - bounds.minY));
    const px = rect.left + (Math.max(0, Math.min(1, nx)) * rect.width);
    const py = rect.bottom - (Math.max(0, Math.min(1, ny)) * rect.height);
    return { x: px, y: py };
}

function getLiveMapVisibleUnits() {
    const state = getLiveMapState();
    const filter = String(state.filter || 'all');
    return (MDT.state.units || []).filter((unit) => {
        if (!unit || !unit.coords || unit.status === 'OFFDUTY') return false;
        const service = normalizeLiveMapService(unit.department);
        if (filter !== 'all' && service !== filter) return false;
        return Number(unit.coords.x) === Number(unit.coords.x) && Number(unit.coords.y) === Number(unit.coords.y);
    });
}

function liveMapIconMarkup(service, overrideIcon = null) {
    const cfg = getLiveMapConfig();
    const icon = overrideIcon || (((cfg.icons || {})[service]) || {});
    const imageUrl = String(icon.imageUrl || '').trim();
    if (imageUrl) {
        return `<img src="${escapeHtml(imageUrl)}" alt="${escapeHtml(icon.label || service)}" />`;
    }
    const className = String(icon.className || '').trim();
    if (className) {
        return `<i class="${escapeHtml(className)}"></i>`;
    }
    return `<span>${escapeHtml(icon.emoji || '•')}</span>`;
}

function describeLiveMapUnit(unit) {
    if (!unit) return '';
    return String(unit.locationText || unit.streetLabel || unit.street || unit.lastStreet || '').trim();
}

function selectedLiveMapUnit() {
    const state = getLiveMapState();
    const targetId = String(state.selectedUnitId || '').trim();
    if (!targetId) return null;
    return (getLiveMapVisibleUnits() || []).find((unit) => String(unit.id || '') === targetId) || null;
}

function ensureLiveMapViewReady() {
    const state = getLiveMapState();
    const viewport = MDT.els.liveMapViewport;
    if (!viewport) return;
    if (!state.view.ready) {
        const cfg = getLiveMapConfig();
        const half = (Math.max(512, Number(cfg.stageSize || 2048) || 2048) * 0.5);
        state.view.scale = 1.05;
        state.view.x = (viewport.clientWidth * 0.5) - (half * state.view.scale);
        state.view.y = (viewport.clientHeight * 0.5) - (half * state.view.scale);
        state.view.ready = true;
    }
}

function updateLiveMapTransform() {
    const state = getLiveMapState();
    if (!MDT.els.liveMapStage) return;
    ensureLiveMapViewReady();
    MDT.els.liveMapStage.style.transform = `translate(${state.view.x}px, ${state.view.y}px) scale(${state.view.scale})`;
}

function liveMapFocusUnits(units) {
    const viewport = MDT.els.liveMapViewport;
    const state = getLiveMapState();
    if (!viewport || !units || !units.length) return;
    const points = units.map((unit) => worldToLiveMapPoint(unit.coords));
    const minX = Math.min(...points.map((p) => p.x));
    const maxX = Math.max(...points.map((p) => p.x));
    const minY = Math.min(...points.map((p) => p.y));
    const maxY = Math.max(...points.map((p) => p.y));
    const pad = 100;
    const spanX = Math.max(180, (maxX - minX) + pad);
    const spanY = Math.max(180, (maxY - minY) + pad);
    const scaleX = viewport.clientWidth / spanX;
    const scaleY = viewport.clientHeight / spanY;
    state.view.scale = Math.max(0.55, Math.min(2.6, Math.min(scaleX, scaleY)));
    const midX = (minX + maxX) * 0.5;
    const midY = (minY + maxY) * 0.5;
    state.view.x = (viewport.clientWidth * 0.5) - (midX * state.view.scale);
    state.view.y = (viewport.clientHeight * 0.5) - (midY * state.view.scale);
    state.view.ready = true;
    state.view.hasFitted = true;
    updateLiveMapTransform();
}

function getCurrentOfficerUnitId() {
    const officer = MDT.state.officer || {};
    return String(officer.source ?? officer.playerSource ?? officer.src ?? officer.id ?? '').trim();
}

function centerLiveMapOnUnit() {
    const meId = getCurrentOfficerUnitId();
    const me = (MDT.state.units || []).find((u) => String(u.id || '') === meId && u.coords);
    const viewport = MDT.els.liveMapViewport;
    const state = getLiveMapState();
    if (!viewport || !me || !me.coords) return;
    const point = worldToLiveMapPoint(me.coords);
    ensureLiveMapViewReady();
    state.view.x = (viewport.clientWidth * 0.5) - (point.x * state.view.scale);
    state.view.y = (viewport.clientHeight * 0.5) - (point.y * state.view.scale);
    updateLiveMapTransform();
}

function maybeLoadLiveMapPostals() {
    const state = getLiveMapState();
    const cfg = getLiveMapConfig();
    if (!cfg.showPostalLabels || state.postalsLoaded) return;
    state.postalsLoaded = true;
    fetch('config/postals.json').then((r) => r.json()).then((rows) => {
        state.postals = Array.isArray(rows) ? rows.slice(0, 3000) : [];
        renderLiveMap();
    }).catch(() => {
        state.postals = [];
    });
}

function renderLiveMapPostals() {
    if (!MDT.els.liveMapPostals) return;
    const state = getLiveMapState();
    const cfg = getLiveMapConfig();
    if (!cfg.showPostalLabels || !Array.isArray(state.postals) || state.view.scale < 1.3) {
        MDT.els.liveMapPostals.innerHTML = '';
        return;
    }
    const samples = state.postals.filter((_, idx) => idx % 30 === 0).slice(0, 100);
    MDT.els.liveMapPostals.innerHTML = samples.map((row) => {
        const point = worldToLiveMapPoint({ x: row.x, y: row.y });
        const code = escapeHtml(row.code || row.postal || '');
        return `<div class="mdt-live-map-postal" style="left:${point.x}px;top:${point.y}px;">${code}</div>`;
    }).join('');
}

function renderLiveMapIconEditors() {
    const state = getLiveMapState();
    const cfg = getLiveMapConfig();
    ['police', 'fire', 'ems'].forEach((service) => {
        const icon = (((cfg.icons || {})[service]) || {});
        const classInput = document.querySelector(`[data-live-map-class="${service}"]`);
        const urlInput = document.querySelector(`[data-live-map-url="${service}"]`);
        const preview = document.querySelector(`[data-live-map-preview="${service}"]`);
        const previewIcon = {
            ...icon,
            className: String(classInput?.value || icon.className || '').trim(),
            imageUrl: String((state.pendingUploads || {})[service] || urlInput?.value || icon.imageUrl || '').trim()
        };
        if (classInput && document.activeElement !== classInput) classInput.value = icon.className || '';
        if (urlInput && document.activeElement !== urlInput) urlInput.value = icon.imageUrl || '';
        if (preview) preview.innerHTML = `<div class="mdt-live-map-marker-icon service-${service}">${liveMapIconMarkup(service, previewIcon)}</div>`;
    });
    if (MDT.els.liveMapIconSettingsToggle) {
        MDT.els.liveMapIconSettingsToggle.classList.toggle('hidden', !MDT.state.isAdmin);
    }
}

function collectLiveMapIconPayload(resetDefaults = false) {
    if (resetDefaults) {
        const defaults = getLiveMapDefaults();
        return JSON.parse(JSON.stringify(defaults.icons || {}));
    }
    const state = getLiveMapState();
    const cfg = getLiveMapConfig();
    const out = {};
    ['police', 'fire', 'ems'].forEach((service) => {
        const classInput = document.querySelector(`[data-live-map-class="${service}"]`);
        const urlInput = document.querySelector(`[data-live-map-url="${service}"]`);
        const uploaded = (state.pendingUploads || {})[service] || '';
        const imageUrl = uploaded || String(urlInput?.value || '').trim() || String((((cfg.icons || {})[service]) || {}).imageUrl || '').trim();
        out[service] = {
            className: String(classInput?.value || '').trim() || String((((cfg.icons || {})[service]) || {}).className || '').trim(),
            imageUrl,
            label: String((((cfg.icons || {})[service]) || {}).label || service).trim(),
            emoji: String((((cfg.icons || {})[service]) || {}).emoji || '').trim()
        };
    });
    return out;
}


function applyLiveMapVisualConfig() {
    const cfg = getLiveMapConfig();
    const stageSize = Math.max(512, Number(cfg.stageSize || 2048) || 2048);
    if (MDT.els.liveMapStage) {
        MDT.els.liveMapStage.style.width = `${stageSize}px`;
        MDT.els.liveMapStage.style.height = `${stageSize}px`;
    }
    const base = MDT.els.liveMapShell ? MDT.els.liveMapShell.querySelector('.mdt-live-map-base') : null;
    if (base) {
        const mapImage = String(cfg.mapImage || '').trim();
        base.style.backgroundImage = mapImage ? `linear-gradient(rgba(2,6,23,0.08), rgba(2,6,23,0.18)), url("${mapImage.replace(/"/g, '&quot;')}")` : '';
        base.style.backgroundSize = 'cover';
        base.style.backgroundPosition = 'center center';
        base.style.backgroundRepeat = 'no-repeat';
    }
}

function renderLiveMap() {
    if (!MDT.els.liveMapMarkers || !MDT.els.liveMapShell) return;
    const state = getLiveMapState();
    const units = getLiveMapVisibleUnits();
    applyLiveMapVisualConfig();
    ensureLiveMapViewReady();
    if (!state.view.hasFitted && units.length) {
        const meId = getCurrentOfficerUnitId();
        const mine = units.find((unit) => String(unit.id || '') === meId && unit.coords);
        if (mine) centerLiveMapOnUnit();
        else liveMapFocusUnits(units);
        state.view.hasFitted = true;
    }
    if (state.selectedUnitId && !units.find((unit) => String(unit.id || '') === String(state.selectedUnitId))) {
        state.selectedUnitId = '';
    }
    MDT.els.liveMapEmpty.classList.toggle('hidden', units.length > 0);
    if (MDT.els.liveMapStatus) {
        MDT.els.liveMapStatus.textContent = `${units.length} unit${units.length === 1 ? '' : 's'} • ${(state.filter || 'all').toUpperCase()}`;
    }
    const meId = getCurrentOfficerUnitId();
    const selectedId = String(state.selectedUnitId || '');
    MDT.els.liveMapMarkers.innerHTML = units.map((unit) => {
        const point = worldToLiveMapPoint(unit.coords || {});
        const service = normalizeLiveMapService(unit.department);
        const unitId = String(unit.id || '');
        const isCurrent = unitId === meId;
        const isSelected = unitId !== '' && unitId === selectedId;
        const callsign = escapeHtml(unit.callsign || `Unit ${unitId || '—'}`);
        const name = escapeHtml(unit.name || `Unit ${unitId || ''}`);
        const status = escapeHtml(unit.status || 'AVAILABLE');
        const dept = escapeHtml((unit.department || service).toUpperCase());
        const location = escapeHtml(describeLiveMapUnit(unit) || 'Street unavailable');
        const updatedAt = unit.updatedAt ? escapeHtml(new Date(Number(unit.updatedAt) * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })) : '';
        return `<div class="mdt-live-map-marker ${isCurrent ? 'current' : ''} ${isSelected ? 'selected' : ''}" data-live-map-unit-id="${escapeAttr(unitId)}" style="left:${point.x}px;top:${point.y}px;">
            <button class="mdt-live-map-marker-hit" type="button" aria-label="Open unit ${callsign}">
                <div class="mdt-live-map-marker-pin service-${service}">${liveMapIconMarkup(service)}</div>
                <div class="mdt-live-map-marker-tag">${callsign}</div>
            </button>
            <div class="mdt-live-map-tooltip ${isSelected ? '' : 'hidden'}">
                <div class="mdt-live-map-tooltip-title">${callsign} · ${name}</div>
                <div class="mdt-live-map-tooltip-meta">${dept} · ${status}</div>
                <div class="mdt-live-map-tooltip-row"><strong>Street</strong><span>${location}</span></div>
                <div class="mdt-live-map-tooltip-row"><strong>Unit #</strong><span>${escapeHtml(unitId || '—')}</span></div>
                ${updatedAt ? `<div class="mdt-live-map-tooltip-row"><strong>Updated</strong><span>${updatedAt}</span></div>` : ''}
            </div>
        </div>`;
    }).join('');
    renderLiveMapIconEditors();
    renderLiveMapPostals();
    updateLiveMapTransform();
}


function initLiveMap() {
    const state = getLiveMapState();
    if (state.initialized) return;
    const viewport = MDT.els.liveMapViewport;
    const shell = MDT.els.liveMapShell || viewport;
    if (!viewport || !shell) return;
    state.initialized = true;
    maybeLoadLiveMapPostals();

    const beginDrag = (clientX, clientY) => {
        state.dragging.active = true;
        state.dragging.startX = clientX;
        state.dragging.startY = clientY;
        state.dragging.baseX = state.view.x || 0;
        state.dragging.baseY = state.view.y || 0;
        viewport.classList.add('is-dragging');
    };

    const moveDrag = (clientX, clientY) => {
        if (!state.dragging.active) return;
        state.view.x = state.dragging.baseX + (clientX - state.dragging.startX);
        state.view.y = state.dragging.baseY + (clientY - state.dragging.startY);
        updateLiveMapTransform();
    };

    const endDrag = () => {
        if (!state.dragging.active) return;
        state.dragging.active = false;
        viewport.classList.remove('is-dragging');
    };

    const handleWheel = (event) => {
        event.preventDefault();
        const rect = viewport.getBoundingClientRect();
        const cursorX = event.clientX - rect.left;
        const cursorY = event.clientY - rect.top;
        const oldScale = state.view.scale || 1;
        const nextScale = Math.max(0.55, Math.min(3.4, oldScale * (event.deltaY < 0 ? 1.12 : 0.9)));
        state.view.x = cursorX - ((cursorX - state.view.x) * (nextScale / oldScale));
        state.view.y = cursorY - ((cursorY - state.view.y) * (nextScale / oldScale));
        state.view.scale = nextScale;
        state.view.ready = true;
        updateLiveMapTransform();
        renderLiveMapPostals();
    };

    [viewport, shell].forEach((target) => {
        target.addEventListener('mousedown', (event) => {
            if (event.button !== 0) return;
            if (event.target && event.target.closest && event.target.closest('[data-live-map-unit-id]')) return;
            event.preventDefault();
            beginDrag(event.clientX, event.clientY);
        });
        target.addEventListener('wheel', handleWheel, { passive: false });
        target.addEventListener('touchstart', (event) => {
            const touch = event.touches && event.touches[0];
            if (!touch) return;
            if (event.target && event.target.closest && event.target.closest('[data-live-map-unit-id]')) return;
            event.preventDefault();
            beginDrag(touch.clientX, touch.clientY);
        }, { passive: false });
        target.addEventListener('touchmove', (event) => {
            const touch = event.touches && event.touches[0];
            if (!touch) return;
            event.preventDefault();
            moveDrag(touch.clientX, touch.clientY);
        }, { passive: false });
    });
    window.addEventListener('mousemove', (event) => moveDrag(event.clientX, event.clientY));
    window.addEventListener('mouseup', endDrag);
    window.addEventListener('touchend', endDrag, { passive: true });
    window.addEventListener('touchcancel', endDrag, { passive: true });
    viewport.addEventListener('mouseleave', () => { if (state.dragging.active) endDrag(); });
    document.querySelectorAll('[data-live-map-filter]').forEach((btn) => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('[data-live-map-filter]').forEach((node) => node.classList.remove('active'));
            btn.classList.add('active');
            state.filter = btn.dataset.liveMapFilter || 'all';
            renderLiveMap();
        });
    });
    MDT.els.liveMapCenterMe?.addEventListener('click', () => centerLiveMapOnUnit());
    MDT.els.liveMapFitAll?.addEventListener('click', () => liveMapFocusUnits(getLiveMapVisibleUnits()));
    MDT.els.liveMapIconSettingsToggle?.addEventListener('click', () => MDT.els.liveMapIconSettings?.classList.toggle('hidden'));
    MDT.els.liveMapIconsReset?.addEventListener('click', () => {
        state.pendingUploads = {};
        applyLiveMapState({ ...getLiveMapConfig(), icons: collectLiveMapIconPayload(true) });
    });
    MDT.els.liveMapIconsSave?.addEventListener('click', () => {
        const payload = collectLiveMapIconPayload(false);
        if (MDT_RUNTIME.isBrowser) browserHandleAction('SaveLiveMapIcons', payload);
        else nuiPost('SaveLiveMapIcons', payload);
        applyLiveMapState({ ...getLiveMapConfig(), icons: payload });
        pushNotification({ type: 'success', title: 'LiveMap', message: 'Live map icons saved.' });
    });
    document.querySelectorAll('[data-live-map-file]').forEach((input) => {
        input.addEventListener('change', () => {
            const service = input.dataset.liveMapFile;
            const file = input.files && input.files[0];
            if (!service || !file) return;
            const reader = new FileReader();
            reader.onload = () => {
                state.pendingUploads = state.pendingUploads || {};
                state.pendingUploads[service] = String(reader.result || '');
                renderLiveMapIconEditors();
            };
            reader.readAsDataURL(file);
        });
    });
    MDT.els.liveMapMarkers?.addEventListener('click', (event) => {
        const marker = event.target && event.target.closest ? event.target.closest('[data-live-map-unit-id]') : null;
        if (!marker) return;
        event.preventDefault();
        event.stopPropagation();
        const unitId = String(marker.dataset.liveMapUnitId || '');
        state.selectedUnitId = (state.selectedUnitId === unitId) ? '' : unitId;
        renderLiveMap();
    });
    shell.addEventListener('click', (event) => {
        const marker = event.target && event.target.closest ? event.target.closest('[data-live-map-unit-id]') : null;
        if (marker) return;
        if (state.selectedUnitId) {
            state.selectedUnitId = '';
            renderLiveMap();
        }
    });
    window.addEventListener('resize', () => {
        updateLiveMapTransform();
        renderLiveMap();
    });
}

function isCurrentOfficerAttachedToCall(call) {
    const officer = MDT.state.officer || {};
    const meSource = String(officer.source ?? officer.playerSource ?? officer.src ?? '').trim();
    const meId = String(officer.id || '').trim();
    const meCallsign = String(officer.callsign || '').trim().toUpperCase();
    const meName = String(officer.name || '').trim().toUpperCase();
    const units = Array.isArray(call && call.units) ? call.units : [];
    return units.some((unit) => {
        if (!unit || typeof unit !== 'object') return false;
        const unitId = String(unit.id ?? unit.source ?? unit.sourceId ?? unit.unit_source ?? '').trim();
        const unitCallsign = String(unit.callsign || unit.unit || '').trim().toUpperCase();
        const unitName = String(unit.name || '').trim().toUpperCase();
        if (meSource && unitId && unitId === meSource) return true;
        if (meId && unitId && unitId === meId) return true;
        if (meCallsign && unitCallsign && unitCallsign === meCallsign) return true;
        if (meName && unitName && unitName === meName) return true;
        return false;
    });
}

function syncAttachedCallRoomFromList(list) {
    const calls = Array.isArray(list) ? list : [];
    const attached = calls
        .filter(isCurrentOfficerAttachedToCall)
        .sort((a, b) => Number(b?.id || 0) - Number(a?.id || 0));

    if (!attached.length) return;

    const preferred = attached[0] || {};
    const preferredId = Number(preferred.id || 0);
    if (!preferredId) return;

    const activeId = Number(MDT.state.activeCallRoom || 0);
    const activeStillAttached = activeId > 0 && attached.some((call) => Number(call?.id || 0) === activeId);
    const hasPreferredRoom = !!MDT.state.callRooms[preferredId];

    if (activeStillAttached && MDT.state.callRooms[activeId]) {
        return;
    }

    if (hasPreferredRoom) {
        MDT.state.activeCallRoom = preferredId;
        renderActiveCallRoom();
        setActivePage('callsHub');
        return;
    }

    if (MDT.state.pendingCallRoomRequest === preferredId) {
        return;
    }

    MDT.state.pendingCallRoomRequest = preferredId;
    Promise.resolve(nuiPost('RequestCallRoom', { callId: preferredId }))
        .catch(() => {})
        .finally(() => {
            if (MDT.state.pendingCallRoomRequest === preferredId) {
                MDT.state.pendingCallRoomRequest = null;
            }
        });
}

function renderCalls(list) {
    const container = MDT.els.callsList;
    if (!container) return;

    container.innerHTML = '';

    if (!list || list.length === 0) {
        container.innerHTML = '<div class="mdt-empty">No active calls.</div>';
        return;
    }

    list.forEach(c => {
        const div = document.createElement('div');
        div.className = 'mdt-row';

        const units = (c.units || []).map(u => u.callsign || u.name || u.id).join(', ');
        const isAttached = isCurrentOfficerAttachedToCall(c);
        const attachmentNote = isAttached ? '<span class="mdt-row-tag" style="margin-left:8px;">ATTACHED</span>' : '';

        let adminButton = '';
        if (canManageDispatchControls() && canUseAction('clearCalls') && c.id) {
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
                <div class="mdt-row-title">#${c.id} – ${escapeHtml(c.location || 'Unknown location')}</div>
                <div style="display:flex;align-items:center;gap:8px;">${attachmentNote}<span class="mdt-row-tag">${(c.status || 'PENDING').toUpperCase()}</span></div>
            </div>
            <div class="mdt-row-meta">
                <span>Caller: ${escapeHtml(c.caller || 'Unknown')}</span>
                <span>Units: ${escapeHtml(units || 'None')}</span>
                <span>${c.postal ? `Postal: ${escapeHtml(c.postal)}` : ''}</span>
                <span>${c.created_at || ''}</span>
            </div>
            <div class="mdt-row-body">${escapeHtml(String(c.message || '')).replace(/\n/g, '<br>')}</div>
            <div class="mdt-row-actions">
                ${conditionalButton(canUseAction('attachCalls') && !isAttached, `<button class="btn-xs btn-primary" data-call-action="attach" data-call-id="${c.id}">Attach</button>`)}
                ${conditionalButton(canUseAction('attachCalls') && isAttached, `<button class="btn-xs btn-primary" disabled>Attached</button>`)}
                ${conditionalButton(canUseAction('detachCalls') && isAttached && (MDT_RUNTIME.isBrowser ? (MDT.state.officer?.canAttachDetach || isLeoLikeRole()) : isLeoLikeRole()), `<button class="btn-xs btn-secondary" data-call-action="detach" data-call-id="${c.id}">Detach</button>`)}
                ${conditionalButton(canUseAction('waypointCalls'), `<button class="btn-xs btn-secondary" data-call-action="waypoint" data-call-id="${c.id}">Waypoint</button>`)}
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
            ${(canManageDispatchControls() && canUseAction('deleteWarrant')) ? `<div class="mdt-row-actions" style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap;">
                <button class="btn btn-danger btn-xs" data-admin-action="delete-warrant" data-warrant-id="${w.id || 0}">Delete Warrant</button>
            </div>` : ''}
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

function applyRoleUI() {
    const role = MDT.state.role || 'leo';
    const officer = MDT.state.officer || {};
    document.querySelectorAll('[data-page], [data-mdt-nav]').forEach(btn => {
        const page = btn.dataset.page || btn.dataset.mdtNav;
        let show = canUsePage(page);
        if (page === 'themes') show = !!officer.isAdmin && canUsePage('themes');
        if (page === 'iaLogs') show = !!officer.isAdmin && canUsePage('iaLogs');
        if (page === 'simTools') show = !!officer.useAz5PD && !!officer.az5pdAvailable && canUsePage('simTools');
        if (page === 'livechat') show = false;
        btn.style.display = show ? '' : 'none';
    });

    const boloCard = MDT.els.boloForm?.closest('.mdt-card');
    if (boloCard) boloCard.style.display = canUseAction('createBolo') ? '' : 'none';
    const reportCard = MDT.els.reportForm?.closest('.mdt-card');
    if (reportCard) reportCard.style.display = canUseAction('createReport') ? '' : 'none';
    if (MDT.els.leoChatForm) MDT.els.leoChatForm.style.display = canUseAction('sendLeoChat') ? '' : 'none';
    if (MDT.els.saveUnitBtn) MDT.els.saveUnitBtn.style.display = (role === 'leo' || role === 'dispatch') && canUseAction('saveProfile') ? '' : 'none';
}

function renderLeoChat() {
    const container = MDT.els.leoChatMessages;
    if (!container) return;
    const list = MDT.state.leoChat || [];
    if (!list.length) {
        container.innerHTML = '<div class="mdt-empty">No duty chat messages yet.</div>';
        return;
    }
    container.innerHTML = list.map(msg => `
        <div class="mdt-row">
            <div class="mdt-row-header">
                <div class="mdt-row-title">${msg.sender || 'Unknown'}</div>
                <span class="mdt-row-tag">${msg.time || ''}</span>
            </div>
            <div class="mdt-row-body">${msg.message || ''}</div>
        </div>
    `).join('');
    container.scrollTop = container.scrollHeight;
}

function renderCivilianRegistry(list) {
    const container = MDT.els.civilianRegistryResults;
    if (!container) return;
    list = list || [];
    if (!list.length) {
        container.innerHTML = '<div class="mdt-empty">Use search to view civilians.</div>';
        return;
    }
    container.innerHTML = list.map(row => {
        const meta = row.metadata || {};
        const del = canDeleteCivilian(row);
        return `
            <div class="mdt-row">
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${escapeHtml(row.name || 'Unknown')}</div>
                    <span class="mdt-row-tag">#${row.id || 0}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>DOB: ${escapeHtml(meta.dob || '—')}</span>
                    <span>Phone: ${escapeHtml(meta.phone || '—')}</span>
                    <span>Address: ${escapeHtml(meta.address || '—')}</span>
                    <span>License: ${escapeHtml(row.license_status || 'valid')}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>CharID: ${escapeHtml(row.charid || '—')}</span>
                    <span>Discord: ${escapeHtml(row.discordid || '—')}</span>
                    <span>License #: ${escapeHtml(row.license || '—')}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>Vehicles: ${row.vehicle_count || (row.vehicles || []).length || 0}</span>
                    <span>Weapons: ${row.weapon_count || (row.weapons || []).length || 0}</span>
                </div>
                ${renderCitizenAssetDropdowns(row)}
                ${del.allowed ? `<div class="mdt-row-actions" style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap;">
                    <button class="btn btn-danger btn-xs" data-delete-civilian="${row.id}">${del.isAdmin ? 'Delete Civilian' : 'Delete My Civilian'}</button>
                </div>` : ''}
            </div>
        `;
    }).join('');
}

function renderDMVResults(list) {
    const container = MDT.els.dmvResults;
    if (!container) return;
    list = list || [];
    if (!list.length) {
        container.innerHTML = '<div class="mdt-empty">Use search to view DMV records.</div>';
        return;
    }
    container.innerHTML = list.map(row => {
        const canEdit = !!(MDT.state.officer && MDT.state.officer.canUseDMV);
        return `
            <div class="mdt-row">
                <div class="mdt-row-header">
                    <div class="mdt-row-title">${escapeHtml(row.name || 'Unknown')}</div>
                    <span class="mdt-row-tag">${escapeHtml(row.license_status || 'valid')}</span>
                </div>
                <div class="mdt-row-meta">
                    <span>CharID: ${escapeHtml(row.charid || '—')}</span>
                    <span>License: ${escapeHtml(row.license || '—')}</span>
                    <span>Vehicles: ${row.vehicle_count || 0}</span>
                    <span>Weapons: ${row.weapon_count || (row.weapons || []).length || 0}</span>
                </div>
                ${renderCitizenAssetDropdowns(row)}
                ${canEdit ? `<div class="mdt-form-row" style="margin-top:8px;display:flex;gap:6px;">
                    <button class="btn btn-secondary btn-xs" data-dmv-status="valid" data-citizen-id="${row.id}">Valid</button>
                    <button class="btn btn-secondary btn-xs" data-dmv-status="suspended" data-citizen-id="${row.id}">Suspend</button>
                    <button class="btn btn-secondary btn-xs" data-dmv-status="revoked" data-citizen-id="${row.id}">Revoke</button>
                </div>` : ''}
            </div>
        `;
    }).join('');
}

function renderCallRoomTabs() {
    const container = MDT.els.callRoomTabs;
    if (!container) return;
    const rooms = Object.values(MDT.state.callRooms || {}).sort((a,b) => (b.callId||0) - (a.callId||0));
    if (!rooms.length) {
        container.innerHTML = '<div class="mdt-empty">No active call rooms.</div>';
        return;
    }
    container.innerHTML = rooms.map(room => `
        <div class="call-room-tab">
            <button class="btn btn-secondary btn-xs ${MDT.state.activeCallRoom === room.callId ? 'active' : ''}" data-call-room-select="${room.callId}">Call #${room.callId}</button>
            <button class="call-room-tab-close" type="button" title="Close room" data-call-room-close="${room.callId}">×</button>
        </div>
    `).join('');
}

function renderActiveCallRoom() {
    const summary = MDT.els.callRoomSummary;
    const msgContainer = MDT.els.callRoomMessages;
    const noteContainer = MDT.els.callRoomNotes;
    if (!summary || !msgContainer || !noteContainer) return;

    const id = MDT.state.activeCallRoom;
    const room = id ? MDT.state.callRooms[id] : null;
    if (!room) {
        summary.textContent = 'Attach to a call to open its live room.';
        msgContainer.innerHTML = '<div class="mdt-empty">No active call room selected.</div>';
        noteContainer.innerHTML = '<div class="mdt-empty">No notes yet.</div>';
        renderCallRoomTabs();
        return;
    }

    const postalText = room.postal ? ` · Postal ${room.postal}` : '';
    summary.textContent = `Working Call Room #${id}${postalText}`;
    msgContainer.innerHTML = (room.messages || []).length ? (room.messages || []).map(msg => `
        <div class="mdt-row">
            <div class="mdt-row-header"><div class="mdt-row-title">${msg.sender || 'Unknown'}</div><span class="mdt-row-tag">${msg.time || ''}</span></div>
            <div class="mdt-row-body">${msg.message || ''}</div>
        </div>
    `).join('') : '<div class="mdt-empty">No room messages yet.</div>';
    noteContainer.innerHTML = (room.notes || []).length ? (room.notes || []).map(note => `
        <div class="mdt-row">
            <div class="mdt-row-header"><div class="mdt-row-title">${note.author || 'Unknown'}</div><span class="mdt-row-tag">${note.created_at || ''}</span></div>
            <div class="mdt-row-body">${note.note || ''}</div>
        </div>
    `).join('') : '<div class="mdt-empty">No notes yet.</div>';
    msgContainer.scrollTop = msgContainer.scrollHeight;
    noteContainer.scrollTop = noteContainer.scrollHeight;
    renderCallRoomTabs();
}

function renderCallHistory(list) {
    const container = MDT.els.callHistoryResults;
    if (!container) return;
    list = list || [];
    if (!list.length) {
        container.innerHTML = '<div class="mdt-empty">Search for a call number, caller, location, or postal.</div>';
        return;
    }
    container.innerHTML = list.map(row => `
        <div class="mdt-row">
            <div class="mdt-row-header">
                <div class="mdt-row-title">Call #${row.call_id}</div>
                <span class="mdt-row-tag">${row.status || 'PENDING'}</span>
            </div>
            <div class="mdt-row-meta">
                <span>Caller: ${escapeHtml(row.caller || 'Unknown')}</span>
                <span>Location: ${escapeHtml(row.location || 'Unknown')}</span>
                <span>${row.postal ? `Postal: ${escapeHtml(row.postal)}` : ''}</span>
                <span>${row.created_at || ''}</span>
            </div>
            <div class="mdt-row-body">${escapeHtml(row.message || '')}</div>
            <div class="mdt-form-row" style="margin-top:8px;display:flex;gap:6px;">
                <button class="btn btn-secondary btn-xs" data-call-room-open="${row.call_id}">Open Room</button>
            </div>
        </div>
    `).join('');
}

function handleIncomingMessage(msg) {
    msg = msg || {};
    if (!msg.action) return;

    console.log('[az_mdt] NUI message', msg.action, msg);

    switch (msg.action) {
        case 'open':
        case 'openMDT':
        case 'mdt:open': {
            MDT.state.officer = safeParse(msg.officer, 'officer') || msg.officer || {};
            MDT.state.role = MDT.state.officer.role || (MDT.state.officer.isCiv ? 'civ' : 'leo');
            MDT.state.ttsEnabled = isSpeechTtsEnabled();
            MDT.state.themeSettings = normalizeThemeSettings((MDT.state.officer.ui && MDT.state.officer.ui.theme) || MDT.state.themeSettings);
            applyTheme(MDT.state.themeSettings);
            applyLiveMapState((MDT.state.officer.ui && MDT.state.officer.ui.liveMap) || MDT.state.liveMap.config);
            MDT.state.status = MDT.state.officer.status || (isLeoLikeRole() ? 'OFFDUTY' : 'CIV');
            MDT.state.isAdmin = !!MDT.state.officer.isAdmin;
            MDT.state.isSupervisor = !!MDT.state.officer.isSupervisor;
            MDT.state.canManageDispatch = !!MDT.state.officer.canManageDispatch;
            MDT.state.useAz5PD = !!MDT.state.officer.useAz5PD;
            MDT.state.az5pdAvailable = !!MDT.state.officer.az5pdAvailable;
            applyRoleUI();
            renderOfficer();
            updateAdminUI();
            renderLiveMapIconEditors();
            renderLiveMap();
            MDT.state.callHistory = [];
            MDT.state.myCivilians = [];
            MDT.state.selectedCivilianId = null;
            renderCallHistory([]);
            showRoot();
            const pendingExternalPage = (MDT.state.pendingExternalSearch && !MDT.state.pendingExternalSearch.completed && !MDT.state.pendingExternalSearch.preservePage)
                ? MDT.state.pendingExternalSearch.page
                : '';
            const preferredPage = pendingExternalPage || restoreActivePage(MDT.state.role);
            setActivePage(preferredPage);
            setTimeout(() => {
                replayPendingExternalSearch(false);
                refreshActiveView();
            }, 120);
            setTimeout(() => replayPendingExternalSearch(true), 260);

            if (isLeoLikeRole()) {
                nuiPost('GetBolos', {});
                nuiPost('GetReports', {});
                nuiPost('GetUnits', {});
                nuiPost('GetCalls', {});
                nuiPost('GetWarrants', {});
                nuiPost('GetActionLog', {});
                nuiPost('RequestChatHistory', {});
                nuiPost('RequestLeoChat', {});
            } else {
                MDT.state.units = [];
                MDT.state.calls = [];
                MDT.state.bolos = [];
                MDT.state.civRegistry = [];
                MDT.state.dmvResults = [];
                renderCivilianRegistry([]);
                renderDMVResults([]);
                if (MDT.els.unitsList) MDT.els.unitsList.innerHTML = '<div class="mdt-empty">Civilian access does not include active units.</div>';
                if (MDT.els.callsList) MDT.els.callsList.innerHTML = '<div class="mdt-empty">Civilian access does not include active calls.</div>';
                if (MDT.els.dashboardBolos) MDT.els.dashboardBolos.innerHTML = '<div class="mdt-empty">Civilian access does not include BOLOs.</div>';
                if (MDT.els.liveMapEmpty) MDT.els.liveMapEmpty.classList.remove('hidden');
                nuiPost('SearchReports', {});
                nuiPost('RequestMyCivilians', {});
            }
            break;
        }

        case 'close':
        case 'closeMDT':
        case 'mdt:close': {
            hideRoot();
            break;
        }

        case 'externalPage': {
            if (msg.page) setActivePage(String(msg.page));
            setTimeout(() => replayPendingExternalSearch(false), 0);
            setTimeout(() => replayPendingExternalSearch(false), 140);
            break;
        }

        case 'externalSearchPrefill': {
            applyExternalSearchPrefill(msg.data || msg.json || msg.search || msg);
            setTimeout(() => replayPendingExternalSearch(false), 0);
            break;
        }

        case 'externalSearchPrefillRaw': {
            applyExternalSearchPrefill(msg);
            setTimeout(() => replayPendingExternalSearch(false), 0);
            break;
        }

        case 'nameResults':
        case 'NameSearchResults': {
            const payload = safeParse(msg.data, 'nameResults') || msg.data;
            MDT.state.nameResults = payload || {};
            renderNameResults(payload);
            if (shouldPromoteResultPage('nameSearch')) {
                setActivePage('nameSearch');
            }
            markExternalSearchCompleted(MDT.state.pendingExternalSearch);
            setTimeout(() => replayPendingExternalSearch(false), 0);
            setTimeout(() => replayPendingExternalSearch(false), 90);
            break;
        }

        case 'plateResults':
        case 'PlateSearchResults': {
            const payload = safeParse(msg.data, 'plateResults') || msg.data;
            MDT.state.plateResults = payload || {};
            renderPlateResults(payload);
            if (shouldPromoteResultPage('plateSearch')) {
                setActivePage('plateSearch');
            }
            markExternalSearchCompleted(MDT.state.pendingExternalSearch);
            setTimeout(() => replayPendingExternalSearch(false), 0);
            setTimeout(() => replayPendingExternalSearch(false), 90);
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
                const existingIndex = (MDT.state.bolos || []).findIndex(entry => Number(entry.id || 0) === Number(bolo.id || 0));
                if (existingIndex >= 0) {
                    MDT.state.bolos[existingIndex] = bolo;
                } else {
                    MDT.state.bolos.push(bolo);
                }
                renderBolos(MDT.state.bolos);
                renderDashboardBolos(MDT.state.bolos);
            }
            break;
        }

        case 'boloAlert': {
            const bolo = safeParse(msg.data, 'boloAlert') || msg.data;
            if (bolo) {
                playSound('bolo');
                const title = (bolo.body && bolo.body.title) || bolo.title || 'BOLO';
                if (getBoloTtsMode() !== 'none') {
                    speak(`New BOLO created: ${title}.`);
                }
                pushNotification({
                    type: 'warning',
                    title: 'New BOLO',
                    message: title,
                    duration: 5000
                });
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
            const officer = MDT.state.officer || {};
            const meSource = String(officer.source ?? officer.playerSource ?? officer.src ?? '').trim();
            const meId = String(officer.id || '').trim();
            const meCallsign = String(officer.callsign || '').trim().toUpperCase();
            const meName = String(officer.name || '').trim().toUpperCase();
            const mine = list.find(u => {
                const unitId = String(u.id ?? u.source ?? u.sourceId ?? u.unit_source ?? '').trim();
                const unitCallsign = String(u.callsign || '').trim().toUpperCase();
                const unitName = String(u.name || '').trim().toUpperCase();
                return (meSource && unitId === meSource)
                    || (meId && unitId === meId)
                    || (meCallsign && unitCallsign === meCallsign)
                    || (meName && unitName === meName);
            });
            if (mine) {
                if (mine.status) MDT.state.status = String(mine.status).toUpperCase();
                MDT.state.officer = {
                    ...(MDT.state.officer || {}),
                    source: mine.id ?? mine.source ?? mine.sourceId ?? mine.unit_source ?? (MDT.state.officer || {}).source,
                    playerSource: mine.id ?? mine.source ?? mine.sourceId ?? mine.unit_source ?? (MDT.state.officer || {}).playerSource,
                    department: mine.department || (MDT.state.officer || {}).department,
                    callsign: mine.callsign ?? (MDT.state.officer || {}).callsign,
                    name: mine.name || (MDT.state.officer || {}).name
                };
                renderOfficer();
            }
            renderUnits(list);
            renderLiveMap();
            break;
        }

        case 'callList': {
            const list = safeParse(msg.data, 'callList') || msg.data || [];
            MDT.state.calls = list;
            renderCalls(list);
            syncAttachedCallRoomFromList(list);
            break;
        }

        case 'newCallAlert': {
            const call = safeParse(msg.data, 'newCallAlert') || msg.data || {};
            if (call && call.id && !MDT.state.seenCalls[call.id]) {
                MDT.state.seenCalls[call.id] = true;
                playSound('call');
                emitCallBanner(call);
                speak(buildCallSpeechText(call));
            }
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
                    emitCallBanner(call);
                    if (getCallTtsMode() === 'all_onduty') {
                        speak(buildCallSpeechText(call));
                    }
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

        case 'reportSearchResults': {
            const list = safeParse(msg.data, 'reportSearchResults') || msg.data || [];
            MDT.state.reports = list;
            renderReports(list);
            break;
        }

        case 'civilianRegistry': {
            const list = safeParse(msg.data, 'civilianRegistry') || msg.data || [];
            MDT.state.civRegistry = list;
            renderCivilianRegistry(list);
            break;
        }

        case 'myCivilians': {
            const list = safeParse(msg.data, 'myCivilians') || msg.data || [];
            MDT.state.myCivilians = list;
            renderOwnedCivilians();
            renderOwnedCivilianAssets();
            if ((MDT.state.activePage || '') === 'civCenter' && !((MDT.els.civilianSearchInput?.value || '').trim())) {
                renderCivilianRegistry(list);
            }
            break;
        }

        case 'unitProfileUpdated': {
            const ctx = safeParse(msg.data, 'unitProfileUpdated') || msg.data || {};
            MDT.state.officer = { ...(MDT.state.officer || {}), ...(ctx || {}) };
            if (ctx.role) MDT.state.role = ctx.role;
            if (ctx.isAdmin !== undefined) MDT.state.isAdmin = !!ctx.isAdmin;
            if (ctx.isSupervisor !== undefined) MDT.state.isSupervisor = !!ctx.isSupervisor;
            if (ctx.canManageDispatch !== undefined) MDT.state.canManageDispatch = !!ctx.canManageDispatch;
            applyRoleUI();
            updateAdminUI();
            renderOfficer();
            queueLiveRefresh(120);
            break;
        }

        case 'dmvResults': {
            const list = safeParse(msg.data, 'dmvResults') || msg.data || [];
            MDT.state.dmvResults = list;
            renderDMVResults(list);
            break;
        }

        case 'leoChatHistory': {
            const list = safeParse(msg.data, 'leoChatHistory') || msg.data || [];
            MDT.state.leoChat = list;
            renderLeoChat();
            break;
        }

        case 'leoChatMessage': {
            const chatMsg = safeParse(msg.data, 'leoChatMessage') || msg.data;
            if (chatMsg) {
                MDT.state.leoChat.push(chatMsg);
                renderLeoChat();
            }
            break;
        }

        case 'leoChatReset': {
            MDT.state.leoChat = [];
            renderLeoChat();
            break;
        }

        case 'callRoomOpened': {
            const payload = safeParse(msg.data, 'callRoomOpened') || msg.data || {};
            if (payload.callId) {
                const callMeta = MDT.state.calls.find(c => c.id === payload.callId) || {};
                const alreadyOpen = !!MDT.state.callRooms[payload.callId];
                payload.postal = payload.postal || callMeta.postal || null;
                MDT.state.callRooms[payload.callId] = payload;
                MDT.state.activeCallRoom = payload.callId;
                if (MDT.state.pendingCallRoomRequest === payload.callId) {
                    MDT.state.pendingCallRoomRequest = null;
                }
                renderActiveCallRoom();
                setActivePage('callsHub');

                if (!alreadyOpen && shouldAnnounceCallRoom(payload.callId)) {
                    const loc = payload.location || callMeta.location || 'unknown location';
                    const postal = payload.postal ? `, postal ${payload.postal}` : '';
                    playSound('call');
                    pushNotify({
                        type: 'call',
                        title: `Attached to Call #${payload.callId}`,
                        message: `${loc}${payload.postal ? ` • Postal ${payload.postal}` : ''}`,
                        duration: 4500
                    });
                    speak(`Attached to call ${payload.callId} at ${loc}${postal}.`);
                }
            }
            break;
        }

        case 'callRoomMessage': {
            const payload = safeParse(msg.data, 'callRoomMessage') || msg.data || {};
            if (payload.callId) {
                MDT.state.callRooms[payload.callId] = MDT.state.callRooms[payload.callId] || { callId: payload.callId, messages: [], notes: [] };
                MDT.state.callRooms[payload.callId].messages.push(payload);
                renderActiveCallRoom();
            }
            break;
        }

        case 'callRoomNote': {
            const payload = safeParse(msg.data, 'callRoomNote') || msg.data || {};
            if (payload.callId) {
                MDT.state.callRooms[payload.callId] = MDT.state.callRooms[payload.callId] || { callId: payload.callId, messages: [], notes: [] };
                MDT.state.callRooms[payload.callId].notes.push(payload);
                renderActiveCallRoom();
            }
            break;
        }

        case 'callHistoryResults': {
            const list = safeParse(msg.data, 'callHistoryResults') || msg.data || [];
            MDT.state.callHistory = list;
            renderCallHistory(list);
            break;
        }

        case 'dispatchStatusCheck': {
            const payload = safeParse(msg.data, 'dispatchStatusCheck') || msg.data || {};
            playSound('call');
            pushNotification({ type: 'info', title: 'Dispatch Status Check', message: payload.from ? `Requested by ${payload.from}` : 'Dispatch is requesting your current status.', duration: 4500 });
            if (MDT.state.ttsEnabled) {
                speak(payload.from ? `Dispatch status check from ${payload.from}.` : 'Dispatch status check.');
            }
            break;
        }

        case 'panic': {
            const panic = safeParse(msg.data, 'panic') || msg.data || {};
            playSound('panic');
            const name = panic.officer || panic.callsign || 'an officer';
            const postal = panic.postal ? ` at postal ${panic.postal}` : '';
            if (getPanicTtsMode() !== 'none') {
                speak(`Panic button activated by ${name}${postal}.`);
            }
            break;
        }

        case 'statusUpdate': {
            const status = msg.status || 'AVAILABLE';
            MDT.state.status = status;
            if (MDT.els.statusSelect) MDT.els.statusSelect.value = status;
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

        case 'themeSettings': {
            const theme = safeParse(msg.data, 'themeSettings') || msg.data || {};
            MDT.state.themeSettings = normalizeThemeSettings(theme);
            if (MDT.state.officer) {
                MDT.state.officer.ui = MDT.state.officer.ui || {};
                MDT.state.officer.ui.theme = MDT.state.themeSettings;
            }
            renderThemeStudio();
            applyTheme(MDT.state.themeSettings);
            break;
        }

        case 'liveMapIcons': {
            const payload = safeParse(msg.data, 'liveMapIcons') || msg.data || {};
            applyLiveMapState(payload);
            break;
        }

        case 'notify': {
            const payload = safeParse(msg.data, 'notify') || msg.data || {};
            pushNotification(payload);
            break;
        }

        case 'webLinkCode': {
            const payload = safeParse(msg.data, 'webLinkCode') || msg.data || {};
            showModal('link', payload);
            pushNotification({ type: 'success', title: payload.title || 'Website Link Code', message: payload.code ? `Code ${payload.code} created.` : 'Website link code created.' });
            break;
        }

        case 'vehicleRegisterPrompt': {
            const payload = safeParse(msg.data, 'vehicleRegisterPrompt') || msg.data || {};
            showModal('vehicle-register', payload);
            break;
        }

        default:
            break;
    }
}

window.addEventListener('message', (event) => {
    handleIncomingMessage(event.data || {});
});

async function browserBootstrap(silent = false) {
    try {
        const boot = await browserFetchJson('api/bootstrap');
        const viewer = boot.viewer || {
            name: boot.title || 'Web Viewer',
            department: 'browser',
            grade: 0,
            role: 'civ',
            ui: { departments: boot.departments || [] },
            tts: boot.tts || {}
        };

        MDT.state.officer = viewer;
        MDT.state.role = viewer.role || 'civ';
        MDT.state.ttsEnabled = isSpeechTtsEnabled();
        MDT.state.status = viewer.status || 'WEB';
        MDT.state.isAdmin = !!viewer.isAdmin;
        MDT.state.isSupervisor = !!viewer.isSupervisor;
        MDT.state.canManageDispatch = !!viewer.canManageDispatch;
        MDT.state.themeSettings = normalizeThemeSettings(boot.theme || (viewer.ui && viewer.ui.theme) || MDT.state.themeSettings);
        applyTheme(MDT.state.themeSettings);

        document.body.classList.add('mdt-browser-mode');
        applyRoleUI();
        renderOfficer();
        updateAdminUI();
        showRoot();
        setActivePage(restoreActivePage(viewer.role || 'civ'));
        setTimeout(() => refreshActiveView(), 120);

        setWebAuthState(boot.auth || {});

        if (!silent) {
            const params = new URLSearchParams(window.location.search || '');
            const authError = params.get('authError');
            if (authError) {
                pushNotification({ type: 'error', title: 'Discord Login', message: authError });
                params.delete('authError');
                const clean = params.toString();
                const next = `${window.location.pathname}${clean ? `?${clean}` : ''}${window.location.hash || ''}`;
                window.history.replaceState({}, document.title, next);
            } else if (boot.auth && boot.auth.authenticated && boot.auth.linked) {
                pushNotification({ type: 'success', title: 'Website Linked', message: 'Signed in with Discord and linked to your in-game account.' });
            }
        }

        if (boot.auth && boot.auth.authenticated) {
            await Promise.all([
                browserHandleAction('GetUnits', {}),
                browserHandleAction('GetCalls', {}),
                browserHandleAction('GetBolos', {}),
                browserHandleAction('GetReports', {}),
                browserHandleAction('GetWarrants', {}),
                browserHandleAction('RequestLeoChat', {}),
                browserHandleAction('RequestMyCivilians', {}),
                browserHandleAction('GetThemeSettings', {})
            ]);

            if (window.__azMdtWebRefresh) window.clearInterval(window.__azMdtWebRefresh);
            const refreshMs = Math.max(5000, Number((boot.web || {}).autoRefreshMs || 15000));
            window.__azMdtWebRefresh = window.setInterval(() => {
                browserHandleAction('GetUnits', {});
                browserHandleAction('GetCalls', {});
                browserHandleAction('GetBolos', {});
                if (MDT.state.activePage !== 'themes') browserHandleAction('GetThemeSettings', {});
                if (MDT.state.activeCallRoom) {
                    browserHandleAction('RequestCallRoom', { callId: MDT.state.activeCallRoom });
                }
            }, refreshMs);
        }
    } catch (err) {
        console.error('[az_mdt] browser bootstrap failed', err);
        showRoot();
        pushNotification({
            type: 'error',
            title: 'Web Mode',
            message: err && err.message ? err.message : 'Failed to load web mode.'
        });
    }
}


function refreshActiveView() {
    if (!MDT.root || MDT.root.classList.contains('hidden')) return;
    const page = MDT.state.activePage || 'dashboard';
    if (page === 'dashboard') {
        nuiPost('GetUnits', {});
        nuiPost('GetCalls', {});
        nuiPost('GetBolos', {});
        return;
    }
    if (page === 'liveMap') {
        nuiPost('GetUnits', {});
        if (MDT_RUNTIME.isBrowser) nuiPost('GetLiveMapIcons', {});
        return;
    }
    if (page === 'employees') {
        nuiPost('ViewEmployees', {});
        return;
    }
    if (page === 'iaLogs' && MDT.state.isAdmin) {
        nuiPost('GetActionLog', {});
        return;
    }
    if (page === 'civCenter') {
        nuiPost('RequestMyCivilians', {});
        const term = (MDT.state.lastQueries.civ || MDT.els.civilianSearchInput?.value || '').trim();
        if (term) nuiPost('SearchCivilianRegistry', { term });
        return;
    }
    if (page === 'dmv') {
        nuiPost('RequestMyCivilians', {});
        const term = (MDT.state.lastQueries.dmv || MDT.els.dmvInput?.value || selectedOwnedCivilianLabel() || '').trim();
        if (term) nuiPost('SearchDMV', { term });
        return;
    }
    if (page === 'nameSearch') {
        const first = (MDT.els.nameFirst?.value || MDT.state.lastQueries.nameFirst || '').trim();
        const last = (MDT.els.nameLast?.value || MDT.state.lastQueries.nameLast || '').trim();
        const full = normalizeNameToken(`${first} ${last}`);
        if ((first || last) && !isPlaceholderNameValue(first) && !isPlaceholderNameValue(last) && full !== 'unknown unknown') {
            MDT.state.lastQueries.nameFirst = first;
            MDT.state.lastQueries.nameLast = last;
            nuiPost('NameSearch', buildNameSearchPayload(first, last));
        }
        return;
    }
    if (page === 'plateSearch') {
        const plate = (MDT.state.lastQueries.plate || MDT.els.plateInput?.value || '').trim();
        if (plate) {
            MDT.state.lastQueries.plate = plate;
            nuiPost('PlateSearch', buildPlateSearchPayload(plate));
        }
        return;
    }
    if (page === 'weaponSearch') {
        const serial = (MDT.state.lastQueries.weapon || MDT.els.weaponInput?.value || '').trim();
        if (serial) {
            MDT.state.lastQueries.weapon = serial;
            nuiPost('WeaponSearch', { serial });
        }
        return;
    }
    if (page === 'reports') {
        nuiPost('GetReports', {});
        return;
    }
    if (page === 'warrants') {
        nuiPost('GetWarrants', {});
        return;
    }
    if (page === 'bolos') {
        nuiPost('GetBolos', {});
        return;
    }
    if (page === 'dutyChat') {
        nuiPost('RequestLeoChat', {});
        return;
    }
    if (page === 'callsHub') {
        const query = (MDT.state.lastQueries.calls || MDT.els.callHistoryInput?.value || '').trim();
        nuiPost('SearchCallHistory', { query });
    }
}

function startLiveRefreshLoop() {
    if (MDT.state.liveRefreshStarted) return;
    MDT.state.liveRefreshStarted = true;





    if (!MDT_RUNTIME.isBrowser) {
        return;
    }

    window.setInterval(() => refreshActiveView(), 5000);
}

document.addEventListener('DOMContentLoaded', () => {
    MDT.root     = document.getElementById('mdt-wrapper');
    MDT.windowEl = document.querySelector('.mdt-window');
    MDT.els.notifyStack = document.getElementById('mdt-notify-stack');

    initAudio();
    initWindowDrag();
    startLiveRefreshLoop();

    MDT.state.ttsEnabled = isSpeechTtsEnabled();

    if (MDT_RUNTIME.isBrowser) {
        showRoot();
    }

    MDT.els.officerName     = document.getElementById('mdt-user-name');
    MDT.els.officerMeta     = document.getElementById('mdt-user-meta');
    MDT.els.officerInitials = document.querySelector('.mdt-user-initials');
    MDT.els.myStatus        = document.getElementById('mdt-my-status');

    MDT.els.statusSelect = document.getElementById('mdt-status-select');
    MDT.els.dutyBtn     = document.getElementById('mdt-duty-btn');
    MDT.els.departmentSelect = document.getElementById('mdt-department-select');
    MDT.els.nameInput = document.getElementById('mdt-name-input');
    MDT.els.callsignInput = document.getElementById('mdt-callsign-input');
    MDT.els.saveUnitBtn = document.getElementById('mdt-save-unit-btn');
    MDT.els.linkBtn = document.getElementById('mdt-link-btn');
    MDT.els.ttsToggle = document.getElementById('mdt-tts-toggle');
    MDT.els.webLogoutBtn = document.getElementById('mdt-web-logout-btn');
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

    MDT.els.reportForm        = document.getElementById('report-form');
    MDT.els.reportTitle       = document.getElementById('report-title');
    MDT.els.reportType        = document.getElementById('report-type');
    MDT.els.reportBody        = document.getElementById('report-body');
    MDT.els.reportList        = document.getElementById('report-list');
    MDT.els.reportSearchForm  = document.getElementById('report-search-form');
    MDT.els.reportSearchInput = document.getElementById('report-search-input');

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
    MDT.els.liveMapShell = document.getElementById('mdt-live-map');
    MDT.els.liveMapViewport = document.getElementById('mdt-live-map-viewport');
    MDT.els.liveMapStage = document.getElementById('mdt-live-map-stage');
    MDT.els.liveMapMarkers = document.getElementById('mdt-live-map-markers');
    MDT.els.liveMapPostals = document.getElementById('mdt-live-map-postals');
    MDT.els.liveMapEmpty = document.getElementById('mdt-live-map-empty');
    MDT.els.liveMapStatus = document.getElementById('mdt-live-map-status');
    MDT.els.liveMapFilterBar = document.getElementById('mdt-live-map-filter');
    MDT.els.liveMapCenterMe = document.getElementById('mdt-live-map-center-me');
    MDT.els.liveMapFitAll = document.getElementById('mdt-live-map-fit-all');
    MDT.els.liveMapIconSettingsToggle = document.getElementById('mdt-live-map-icon-settings-toggle');
    MDT.els.liveMapIconSettings = document.getElementById('mdt-live-map-icon-settings');
    MDT.els.liveMapIconsSave = document.getElementById('mdt-live-map-icons-save');
    MDT.els.liveMapIconsReset = document.getElementById('mdt-live-map-icons-reset');
    initLiveMap();

    MDT.els.chatForm        = document.getElementById('livechat-form');
    MDT.els.chatMessages    = document.getElementById('livechat-messages');
    MDT.els.chatInput       = document.getElementById('livechat-input');
    MDT.els.leoChatForm     = document.getElementById('leochat-form');
    MDT.els.leoChatMessages = document.getElementById('leochat-messages');
    MDT.els.leoChatInput    = document.getElementById('leochat-input');
    MDT.els.callHistoryForm = document.getElementById('call-history-form');
    MDT.els.callHistoryInput = document.getElementById('call-history-input');
    MDT.els.callHistoryResults = document.getElementById('call-history-results');
    MDT.els.callHistoryClear = document.getElementById('call-history-clear');
    MDT.els.callRoomTabs = document.getElementById('call-room-tabs');
    MDT.els.callRoomSummary = document.getElementById('call-room-summary');
    MDT.els.callRoomMessages = document.getElementById('call-room-messages');
    MDT.els.callRoomChatForm = document.getElementById('call-room-chat-form');
    MDT.els.callRoomChatInput = document.getElementById('call-room-chat-input');
    MDT.els.callRoomNotes = document.getElementById('call-room-notes');
    MDT.els.callRoomNoteForm = document.getElementById('call-room-note-form');
    MDT.els.callRoomNoteInput = document.getElementById('call-room-note-input');
    MDT.els.civilianCreateForm = document.getElementById('civilian-create-form');
    MDT.els.civilianName = document.getElementById('civilian-name');
    MDT.els.civilianDob = document.getElementById('civilian-dob');
    MDT.els.civilianPhone = document.getElementById('civilian-phone');
    MDT.els.civilianAddress = document.getElementById('civilian-address');
    MDT.els.civilianLicenseStatus = document.getElementById('civilian-license-status');
    MDT.els.civilianSearchForm = document.getElementById('civilian-search-form');
    MDT.els.civilianSearchInput = document.getElementById('civilian-search-input');
    MDT.els.civilianRegistryResults = document.getElementById('civilian-registry-results');
    MDT.els.civilianSearchClear = document.getElementById('civilian-search-clear');
    MDT.els.dmvForm = document.getElementById('dmv-search-form');
    MDT.els.dmvInput = document.getElementById('dmv-search-input');
    MDT.els.dmvResults = document.getElementById('dmv-results');
    MDT.els.dmvClear = document.getElementById('dmv-search-clear');
    MDT.els.dmvCivilianSelect = document.getElementById('dmv-civilian-select');
    MDT.els.dmvVehicleForm = document.getElementById('dmv-vehicle-form');
    MDT.els.dmvVehiclePlate = document.getElementById('dmv-vehicle-plate');
    MDT.els.dmvVehicleModel = document.getElementById('dmv-vehicle-model');
    MDT.els.dmvWeaponForm = document.getElementById('dmv-weapon-form');
    MDT.els.dmvWeaponSerial = document.getElementById('dmv-weapon-serial');
    if (MDT.els.dmvWeaponSerial && !(MDT.els.dmvWeaponSerial.value || '').trim()) MDT.els.dmvWeaponSerial.value = generateRandomWeaponSerial();
    MDT.els.dmvWeaponType = document.getElementById('dmv-weapon-type');
    MDT.els.dmvOwnedVehicles = document.getElementById('dmv-owned-vehicles');
    MDT.els.dmvOwnedWeapons = document.getElementById('dmv-owned-weapons');
    MDT.els.civilianSearchOwned = document.getElementById('civilian-search-owned');

    MDT.els.officerCallForm = document.getElementById('officer-call-form');
    MDT.els.officerCallLocation = document.getElementById('officer-call-location');
    MDT.els.officerCallPostal = document.getElementById('officer-call-postal');
    MDT.els.officerCallDetails = document.getElementById('officer-call-details');
    MDT.els.trafficStopForm = document.getElementById('traffic-stop-form');
    MDT.els.trafficStopVehicle = document.getElementById('traffic-stop-vehicle');
    MDT.els.trafficStopLocation = document.getElementById('traffic-stop-location');
    MDT.els.trafficStopPostal = document.getElementById('traffic-stop-postal');
    MDT.els.trafficStopDetails = document.getElementById('traffic-stop-details');

    MDT.els.warrantsList = document.getElementById('warrants-list');
    MDT.els.iaLogList    = document.getElementById('ia-log-list');
    MDT.els.themeStudioNav = document.getElementById('theme-studio-nav');
    MDT.els.themeActiveBadge = document.getElementById('theme-active-badge');
    MDT.els.themePresetsGrid = document.getElementById('theme-presets-grid');
    MDT.els.themeEditorStatus = document.getElementById('theme-editor-status');
    MDT.els.themePresetSelect = document.getElementById('theme-preset-select');
    MDT.els.themeLabelInput = document.getElementById('theme-label-input');
    MDT.els.themeEditorFields = document.getElementById('theme-editor-fields');
    MDT.els.themeResetBtn = document.getElementById('theme-reset-btn');
    MDT.els.themeReloadBtn = document.getElementById('theme-reload-btn');
    MDT.els.themeSaveBtn = document.getElementById('theme-save-btn');

    MDT.els.modalBackdrop = document.getElementById('mdt-modal-backdrop');
    MDT.els.modalNote     = document.getElementById('mdt-modal-note');
    MDT.els.modalFlags    = document.getElementById('mdt-modal-flags');
    MDT.els.modalWarrant  = document.getElementById('mdt-modal-warrant');
    MDT.els.modalLink = document.getElementById('mdt-modal-link');
    MDT.els.linkSite = document.getElementById('mdt-link-site');
    MDT.els.linkCodeDisplay = document.getElementById('mdt-link-code-display');
    MDT.els.linkExpiry = document.getElementById('mdt-link-expiry');
    MDT.els.linkCopy = document.getElementById('mdt-link-copy');
    MDT.els.linkClose = document.getElementById('mdt-link-close');

    MDT.els.webAuthOverlay = document.getElementById('mdt-web-auth-overlay');
    MDT.els.webAuthTitle = document.getElementById('mdt-web-auth-title');
    MDT.els.webAuthMessage = document.getElementById('mdt-web-auth-message');
    MDT.els.webLoginBtn = document.getElementById('mdt-web-login-btn');
    MDT.els.webAuthLogin = document.getElementById('mdt-web-auth-login');
    MDT.els.webAuthLink = document.getElementById('mdt-web-auth-link');
    MDT.els.webLinkForm = document.getElementById('mdt-web-link-form');
    MDT.els.webLinkCode = document.getElementById('mdt-web-link-code');
    MDT.els.webLinkRefresh = document.getElementById('mdt-web-link-refresh');
    MDT.els.webAuthFooter = document.getElementById('mdt-web-auth-footer');

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
    MDT.els.modalVehicleRegister = document.getElementById('mdt-modal-vehicle-register');
    MDT.els.vehicleRegisterForm = document.getElementById('mdt-vehicle-register-form');
    MDT.els.vehicleRegisterPlate = document.getElementById('mdt-vehicle-register-plate');
    MDT.els.vehicleRegisterModel = document.getElementById('mdt-vehicle-register-model');
    MDT.els.vehicleRegisterCivilian = document.getElementById('mdt-vehicle-register-civilian');
    MDT.els.vehicleRegisterCancel = document.getElementById('mdt-vehicle-register-cancel');

    hideRoot();
    updateAdminUI();

    document.querySelectorAll('[data-page], [data-mdt-nav]').forEach(btn => {
        btn.addEventListener('click', () => {
            const section = btn.dataset.page || btn.dataset.mdtNav;
            if (!section) return;

            clearPendingExternalSearch();
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
            } else if (section === 'liveMap') {
                nuiPost('GetUnits', {});
                if (MDT_RUNTIME.isBrowser) nuiPost('GetLiveMapIcons', {});
                renderLiveMap();
            } else if (section === 'warrants') {
                nuiPost('GetWarrants', {});
            } else if (section === 'iaLogs') {
                nuiPost('GetActionLog', {});
            } else if (section === 'livechat') {
                nuiPost('RequestChatHistory', {});
            } else if (section === 'dutyChat') {
                nuiPost('RequestLeoChat', {});
            } else if (section === 'callsHub') {
                MDT.state.lastQueries.calls = '';
                nuiPost('SearchCallHistory', { query: '' });
            } else if (section === 'civCenter') {
                nuiPost('RequestMyCivilians', {});
                if ((MDT.els.civilianSearchInput?.value || '').trim()) {
                    MDT.state.lastQueries.civ = (MDT.els.civilianSearchInput?.value || '').trim();
                    nuiPost('SearchCivilianRegistry', { term: MDT.state.lastQueries.civ });
                } else {
                    renderCivilianRegistry(MDT.state.myCivilians || []);
                }
            } else if (section === 'dmv') {
                nuiPost('SearchDMV', { term: '' });
                nuiPost('RequestMyCivilians', {});
            }
        });
    });

    if (MDT.els.nameForm) {
        MDT.els.nameForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const first = (MDT.els.nameFirst?.value || '').trim();
            const last  = (MDT.els.nameLast?.value || '').trim();

            MDT.state.lastQueries.nameFirst = first;
            MDT.state.lastQueries.nameLast = last;
            nuiPost('NameSearch', buildNameSearchPayload(first, last));
        });
    }

    if (MDT.els.nameResults) {
        MDT.els.nameResults.addEventListener('click', (ev) => {
            const deleteNoteBtn = ev.target.closest('[data-delete-quicknote]');
            if (deleteNoteBtn) {
                const id = parseInt(deleteNoteBtn.dataset.deleteQuicknote, 10);
                if (!id) return;
                nuiPost('DeleteQuickNote', { id });
                setTimeout(() => refreshNameSearch(), 150);
                return;
            }

            const noteBtn = ev.target.closest('[data-quicknote-target-value]');
            if (noteBtn) {
                const targetValue = noteBtn.dataset.quicknoteTargetValue || '';
                if (!targetValue) return;

                showModal('note', {
                    targetType: noteBtn.dataset.quicknoteTargetType || 'citizen',
                    targetValue,
                    targetLabel: noteBtn.dataset.quicknoteTargetLabel || targetValue
                });
                return;
            }

            const flagsBtn = ev.target.closest('[data-flags-target-value]');
            if (flagsBtn) {
                const targetValue = flagsBtn.dataset.flagsTargetValue || '';
                if (!targetValue) return;

                const flags = {
                    officer_safety: flagsBtn.dataset.flagsOfficerSafety === '1',
                    armed:          flagsBtn.dataset.flagsArmed === '1',
                    gang:           flagsBtn.dataset.flagsGang === '1',
                    mental_health:  flagsBtn.dataset.flagsMental === '1'
                };

                showModal('flags', {
                    targetType: flagsBtn.dataset.flagsTargetType || 'citizen',
                    targetValue,
                    targetLabel: flagsBtn.dataset.flagsTargetLabel || targetValue,
                    notes: flagsBtn.dataset.flagsNotes || '',
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
            MDT.state.lastQueries.plate = plate;
            nuiPost('PlateSearch', buildPlateSearchPayload(plate));
        });
    }

    if (MDT.els.weaponForm) {
        MDT.els.weaponForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const serial = (MDT.els.weaponInput?.value || '').trim();
            MDT.state.lastQueries.weapon = serial;
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
            if (MDT.state.role === 'civ') {
                nuiPost('CreateCivilianReport', {
                    title,
                    reportType: type,
                    body,
                    citizenName: MDT.state.officer?.name || ''
                });
            } else {
                nuiPost('CreateReport', {
                    title,
                    type,
                    info: body,
                    body,
                    targetType: target.type || '',
                    targetValue: target.value || ''
                });
            }

            MDT.els.reportTitle.value = '';
            MDT.els.reportBody.value  = '';
            MDT.state.recordTarget    = null;
        });
    }

    if (MDT.els.reportSearchForm) {
        MDT.els.reportSearchForm.addEventListener('submit', (e) => {
            e.preventDefault();
            nuiPost('SearchReports', { query: (MDT.els.reportSearchInput?.value || '').trim() });
        });
    }

    if (MDT.els.civilianCreateForm) {
        MDT.els.civilianCreateForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const createdName = (MDT.els.civilianName?.value || '').trim();
            nuiPost('CreateCivilian', {
                name: createdName,
                dob: (MDT.els.civilianDob?.value || '').trim(),
                phone: (MDT.els.civilianPhone?.value || '').trim(),
                address: (MDT.els.civilianAddress?.value || '').trim(),
                licenseStatus: MDT.els.civilianLicenseStatus?.value || 'valid'
            });
            if (MDT.els.civilianName) MDT.els.civilianName.value = '';
            if (MDT.els.civilianDob) MDT.els.civilianDob.value = '';
            if (MDT.els.civilianPhone) MDT.els.civilianPhone.value = '';
            if (MDT.els.civilianAddress) MDT.els.civilianAddress.value = '';
            if (createdName) {
                if (MDT.els.civilianSearchInput) MDT.els.civilianSearchInput.value = createdName;
                setTimeout(() => nuiPost('SearchCivilianRegistry', { term: createdName }), 150);
            }
            setTimeout(() => nuiPost('RequestMyCivilians', {}), 150);
        });
    }

    if (MDT.els.civilianSearchForm) {
        MDT.els.civilianSearchForm.addEventListener('submit', (e) => {
            e.preventDefault();
            nuiPost('SearchCivilianRegistry', { term: (MDT.els.civilianSearchInput?.value || '').trim() });
        });
    }

    if (MDT.els.civilianSearchOwned) {
        MDT.els.civilianSearchOwned.addEventListener('click', () => {
            if (MDT.els.civilianSearchInput) MDT.els.civilianSearchInput.value = '';
            nuiPost('RequestMyCivilians', {});
            renderCivilianRegistry(MDT.state.myCivilians || []);
        });
    }

    if (MDT.els.dmvForm) {
        MDT.els.dmvForm.addEventListener('submit', (e) => {
            e.preventDefault();
            MDT.state.lastQueries.dmv = (MDT.els.dmvInput?.value || '').trim();
            nuiPost('SearchDMV', { term: MDT.state.lastQueries.dmv });
        });
    }

    if (MDT.els.dmvResults) {
        MDT.els.dmvResults.addEventListener('click', (ev) => {
            const btn = ev.target.closest('[data-dmv-status]');
            if (btn) {
                const id = parseInt(btn.dataset.citizenId, 10);
                const status = btn.dataset.dmvStatus;
                if (!id || !status) return;
                nuiPost('UpdateDMVStatus', { id, status });
                setTimeout(() => nuiPost('SearchDMV', { term: (MDT.els.dmvInput?.value || '').trim() }), 150);
                return;
            }

            const delVeh = ev.target.closest('[data-delete-owned-vehicle]');
            if (delVeh) {
                const id = parseInt(delVeh.dataset.deleteOwnedVehicle, 10);
                const civilianId = parseInt(delVeh.dataset.civilianId, 10);
                if (!id || !civilianId) return;
                nuiPost('DeleteCivilianVehicle', { id, civilianId });
                setTimeout(() => nuiPost('RequestMyCivilians', {}), 150);
                setTimeout(() => { const term = selectedOwnedCivilianLabel() || (MDT.els.dmvInput?.value || '').trim(); if (term) nuiPost('SearchDMV', { term }); }, 220);
                return;
            }

            const delWeap = ev.target.closest('[data-delete-owned-weapon]');
            if (delWeap) {
                const id = parseInt(delWeap.dataset.deleteOwnedWeapon, 10);
                const civilianId = parseInt(delWeap.dataset.civilianId, 10);
                if (!id || !civilianId) return;
                nuiPost('DeleteCivilianWeapon', { id, civilianId });
                setTimeout(() => nuiPost('RequestMyCivilians', {}), 150);
                setTimeout(() => { const term = selectedOwnedCivilianLabel() || (MDT.els.dmvInput?.value || '').trim(); if (term) nuiPost('SearchDMV', { term }); }, 220);
            }
        });
    }

    const handleOwnedAssetDelete = (ev) => {
        const delVeh = ev.target.closest('[data-delete-owned-vehicle]');
        if (delVeh) {
            const id = parseInt(delVeh.dataset.deleteOwnedVehicle, 10);
            const civilianId = parseInt(delVeh.dataset.civilianId, 10);
            if (!id || !civilianId) return;
            nuiPost('DeleteCivilianVehicle', { id, civilianId });
            setTimeout(() => nuiPost('RequestMyCivilians', {}), 150);
            setTimeout(() => { const term = selectedOwnedCivilianLabel() || (MDT.els.dmvInput?.value || '').trim(); if (term) nuiPost('SearchDMV', { term }); }, 220);
            return;
        }

        const delWeap = ev.target.closest('[data-delete-owned-weapon]');
        if (delWeap) {
            const id = parseInt(delWeap.dataset.deleteOwnedWeapon, 10);
            const civilianId = parseInt(delWeap.dataset.civilianId, 10);
            if (!id || !civilianId) return;
            nuiPost('DeleteCivilianWeapon', { id, civilianId });
            setTimeout(() => nuiPost('RequestMyCivilians', {}), 150);
            setTimeout(() => { const term = selectedOwnedCivilianLabel() || (MDT.els.dmvInput?.value || '').trim(); if (term) nuiPost('SearchDMV', { term }); }, 220);
        }
    };

    if (MDT.els.dmvOwnedVehicles) MDT.els.dmvOwnedVehicles.addEventListener('click', handleOwnedAssetDelete);
    if (MDT.els.dmvOwnedWeapons) MDT.els.dmvOwnedWeapons.addEventListener('click', handleOwnedAssetDelete);

    if (MDT.els.dmvCivilianSelect) {
        MDT.els.dmvCivilianSelect.addEventListener('change', () => {
            MDT.state.selectedCivilianId = parseInt(MDT.els.dmvCivilianSelect.value, 10) || null;
            renderOwnedCivilianAssets();
        });
    }

    if (MDT.els.dmvVehicleForm) {
        MDT.els.dmvVehicleForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const civilianId = MDT.state.selectedCivilianId || parseInt(MDT.els.dmvCivilianSelect?.value || '0', 10);
            const plate = (MDT.els.dmvVehiclePlate?.value || '').trim();
            const model = (MDT.els.dmvVehicleModel?.value || '').trim();
            if (!civilianId || !plate) return;
            const refreshTerm = selectedOwnedCivilianLabel() || (MDT.els.dmvInput?.value || '').trim();
            nuiPost('CreateCivilianVehicle', { civilianId, plate, model });
            if (MDT.els.dmvVehiclePlate) MDT.els.dmvVehiclePlate.value = '';
            if (MDT.els.dmvVehicleModel) MDT.els.dmvVehicleModel.value = '';
            if (refreshTerm && MDT.els.dmvInput) MDT.els.dmvInput.value = refreshTerm;
            setTimeout(() => nuiPost('RequestMyCivilians', {}), 125);
            setTimeout(() => {
                if (refreshTerm) nuiPost('SearchDMV', { term: refreshTerm });
            }, 220);
        });
    }

    if (MDT.els.dmvWeaponForm) {
        ensureWeaponSerialValue();
        MDT.els.dmvWeaponForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const civilianId = MDT.state.selectedCivilianId || parseInt(MDT.els.dmvCivilianSelect?.value || '0', 10);
            const serial = ensureWeaponSerialValue();
            const weaponType = (MDT.els.dmvWeaponType?.value || '').trim();
            if (!civilianId) return;
            const refreshTerm = selectedOwnedCivilianLabel() || (MDT.els.dmvInput?.value || '').trim();
            nuiPost('RegisterCivilianWeapon', { civilianId, serial, weaponType });
            ensureWeaponSerialValue(true);
            if (MDT.els.dmvWeaponType) MDT.els.dmvWeaponType.value = '';
            if (refreshTerm && MDT.els.dmvInput) MDT.els.dmvInput.value = refreshTerm;
            setTimeout(() => nuiPost('RequestMyCivilians', {}), 125);
            setTimeout(() => {
                if (refreshTerm) nuiPost('SearchDMV', { term: refreshTerm });
            }, 220);
        });
    }

    if (MDT.els.civilianRegistryResults) {
        MDT.els.civilianRegistryResults.addEventListener('click', (ev) => {
            const btn = ev.target.closest('[data-delete-civilian]');
            if (!btn) return;
            const id = parseInt(btn.dataset.deleteCivilian, 10);
            if (!id) return;
            nuiPost('DeleteCivilian', { id });
            setTimeout(() => nuiPost('SearchCivilianRegistry', { term: (MDT.els.civilianSearchInput?.value || '').trim() }), 150);
            setTimeout(() => nuiPost('RequestMyCivilians', {}), 150);
        });
    }

    if (MDT.els.officerCallForm) {
        MDT.els.officerCallForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const location = (MDT.els.officerCallLocation?.value || '').trim();
            const postal = (MDT.els.officerCallPostal?.value || '').trim();
            const details = (MDT.els.officerCallDetails?.value || '').trim();
            nuiPost('CreateOfficerCall', { location, postal, details });
            if (MDT.els.officerCallLocation) MDT.els.officerCallLocation.value = '';
            if (MDT.els.officerCallPostal) MDT.els.officerCallPostal.value = '';
            if (MDT.els.officerCallDetails) MDT.els.officerCallDetails.value = '';
        });
    }

    if (MDT.els.trafficStopForm) {
        MDT.els.trafficStopForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const vehicleModel = (MDT.els.trafficStopVehicle?.value || '').trim();
            const location = (MDT.els.trafficStopLocation?.value || '').trim();
            const postal = (MDT.els.trafficStopPostal?.value || '').trim();
            const details = (MDT.els.trafficStopDetails?.value || '').trim();
            if (!vehicleModel) {
                pushNotification({ type: 'error', title: 'Vehicle Required', message: 'Enter the vehicle model for a traffic stop.' });
                return;
            }
            nuiPost('CreateTrafficStop', { vehicleModel, location, postal, details });
            if (MDT.els.trafficStopVehicle) MDT.els.trafficStopVehicle.value = '';
            if (MDT.els.trafficStopLocation) MDT.els.trafficStopLocation.value = '';
            if (MDT.els.trafficStopPostal) MDT.els.trafficStopPostal.value = '';
            if (MDT.els.trafficStopDetails) MDT.els.trafficStopDetails.value = '';
        });
    }

    if (MDT.els.leoChatForm) {
        MDT.els.leoChatForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const text = (MDT.els.leoChatInput?.value || '').trim();
            if (!text) return;
            nuiPost('LeoChatSend', { message: text });
            MDT.els.leoChatInput.value = '';
        });
    }

    if (MDT.els.callHistoryForm) {
        MDT.els.callHistoryForm.addEventListener('submit', (e) => {
            e.preventDefault();
            nuiPost('SearchCallHistory', { query: (MDT.els.callHistoryInput?.value || '').trim() });
        });
    }

    if (MDT.els.callHistoryClear) {
        MDT.els.callHistoryClear.addEventListener('click', () => {
            MDT.state.callHistory = [];
            if (MDT.els.callHistoryInput) MDT.els.callHistoryInput.value = '';
            renderCallHistory([]);
        });
    }

    if (MDT.els.callHistoryResults) {
        MDT.els.callHistoryResults.addEventListener('click', (ev) => {
            const btn = ev.target.closest('[data-call-room-open]');
            if (!btn) return;
            const id = parseInt(btn.dataset.callRoomOpen, 10);
            if (!id) return;
            nuiPost('RequestCallRoom', { callId: id });
        });
    }

    if (MDT.els.callRoomTabs) {
        MDT.els.callRoomTabs.addEventListener('click', (ev) => {
            const closeBtn = ev.target.closest('[data-call-room-close]');
            if (closeBtn) {
                const id = parseInt(closeBtn.dataset.callRoomClose, 10);
                if (!id) return;
                clearCallRoom(id);
                return;
            }

            const btn = ev.target.closest('[data-call-room-select]');
            if (!btn) return;
            const id = parseInt(btn.dataset.callRoomSelect, 10);
            if (!id) return;
            MDT.state.activeCallRoom = id;
            renderActiveCallRoom();
        });
    }

    if (MDT.els.callRoomChatForm) {
        MDT.els.callRoomChatForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const text = (MDT.els.callRoomChatInput?.value || '').trim();
            const callId = MDT.state.activeCallRoom;
            if (!callId || !text) return;
            nuiPost('CallRoomSend', { callId, message: text });
            MDT.els.callRoomChatInput.value = '';
        });
    }

    if (MDT.els.callRoomNoteForm) {
        MDT.els.callRoomNoteForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const text = (MDT.els.callRoomNoteInput?.value || '').trim();
            const callId = MDT.state.activeCallRoom;
            if (!callId || !text) return;
            nuiPost('CallRoomNote', { callId, note: text });
            MDT.els.callRoomNoteInput.value = '';
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

    if (MDT.els.unitsList) {
        MDT.els.unitsList.addEventListener('click', (ev) => {
            const btn = ev.target.closest('[data-unit-action]');
            if (!btn) return;
            const id = parseInt(btn.dataset.unitId, 10);
            if (!id) return;
            const action = btn.dataset.unitAction;
            if (action === 'status-check') {
                nuiPost('DispatchStatusCheck', { targetId: id });
            } else if (action === 'apply-status') {
                const select = MDT.els.unitsList.querySelector(`[data-unit-status-select="${id}"]`);
                const status = (select?.value || 'AVAILABLE').toUpperCase();
                nuiPost('SetOtherUnitStatus', { targetId: id, status });
            }
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
                nuiPost('RequestCallRoom', { callId: id });
            } else if (action === 'detach') {
                nuiPost('DetachCall', { id });
            } else if (action === 'waypoint') {
                nuiPost('CallWaypoint', { id });
            }
        });
    }

    if (MDT.els.statusSelect) {
        MDT.els.statusSelect.addEventListener('change', () => {
            const next = (MDT.els.statusSelect.value || 'AVAILABLE').toUpperCase();
            MDT.state.status = next;
            renderOfficer();
            if (next === 'OFFDUTY') {
                MDT.state.leoChat = [];
                renderLeoChat();
            }
            nuiPost('SetUnitStatus', { status: next });
        });
    }

    if (MDT.els.dutyBtn) {
        MDT.els.dutyBtn.addEventListener('click', () => {
            const onDuty = (MDT.state.status || '').toUpperCase() !== 'OFFDUTY';
            const next = onDuty ? 'OFFDUTY' : 'AVAILABLE';
            MDT.state.status = next;
            MDT.state.leoChat = [];
            renderOfficer();
            renderLeoChat();
            nuiPost('SetDutyState', {
                onDuty: !onDuty,
                department: MDT.els.departmentSelect?.value || (MDT.state.officer || {}).department || ''
            });
            if (!onDuty) {
                MDT.state.status = 'AVAILABLE';
                if (MDT.els.statusSelect) MDT.els.statusSelect.value = 'AVAILABLE';
                nuiPost('RequestLeoChat', {});
            } else if (MDT.els.statusSelect) {
                MDT.els.statusSelect.value = 'OFFDUTY';
            }
        });
    }

    if (MDT.els.saveUnitBtn) {
        MDT.els.saveUnitBtn.addEventListener('click', () => {
            nuiPost('UpdateUnitProfile', {
                department: MDT.els.departmentSelect?.value || '',
                name: (MDT.els.nameInput?.value || '').trim(),
                callsign: (MDT.els.callsignInput?.value || '').trim()
            });
        });
    }

    if (MDT.els.ttsToggle) {
        MDT.els.ttsToggle.addEventListener('click', () => {
            const next = !MDT.state.ttsEnabled;
            setSpeechTtsEnabled(next);
            pushNotification({ type: 'info', title: 'Audio', message: next ? 'Text-to-speech enabled. Panic alert tones always stay active while on duty.' : 'Text-to-speech disabled. Panic alert tones still play while on duty.' });
        });
    }

    if (MDT.els.linkBtn) {
        MDT.els.linkBtn.addEventListener('click', () => {
            nuiPost('RequestWebLinkCode', {});
        });
    }

    if (MDT.els.webLogoutBtn) {
        MDT.els.webLogoutBtn.addEventListener('click', () => {
            if (MDT_RUNTIME.isBrowser) window.location.href = buildBrowserRelativeUrl('auth/logout');
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

            if (!(MDT.state.officer && MDT.state.officer.isAdmin)) {
                if (MDT.els.adminLoginError) {
                    MDT.els.adminLoginError.textContent = 'You do not have admin access.';
                }
                playSound('panic');
                return;
            }

            MDT.state.isAdmin = true;
            if (MDT.els.adminPassword) MDT.els.adminPassword.value = '';
            if (MDT.els.adminLoginError) MDT.els.adminLoginError.textContent = '';
            updateAdminUI();
            renderBolos(MDT.state.bolos);
            renderReports(MDT.state.reports);
            renderEmployees(MDT.state.employees);
            renderCalls(MDT.state.calls);
            renderActionLog(MDT.state.actionLog);
            speak('MDT admin mode enabled.');
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

            refreshNameSearch();
            queueLiveRefresh(180);

            speak(`Quick note added.`);
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
        MDT.els.flagsForm.addEventListener('submit', async (e) => {
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

            const submitBtn = MDT.els.flagsForm.querySelector('button[type="submit"]');
            if (submitBtn) submitBtn.disabled = true;
            try {
                await Promise.resolve(nuiPost('SetIdentityFlags', {
                    targetType,
                    targetValue,
                    flags,
                    notes
                }));
                await refreshNameSearch();
                queueLiveRefresh(320);
                speak(`Flags updated.`);
                closeModal();
            } finally {
                if (submitBtn) submitBtn.disabled = false;
            }
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

    if (MDT.els.vehicleRegisterForm) {
        MDT.els.vehicleRegisterForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const ctx = MDT.state.modalContext || {};
            if (ctx.type !== 'vehicle-register') return;

            const civilianId = parseInt((MDT.els.vehicleRegisterCivilian?.value || '0'), 10) || 0;
            const plate = (MDT.els.vehicleRegisterPlate?.value || ctx.plate || '').trim();
            const model = (MDT.els.vehicleRegisterModel?.value || ctx.model || '').trim();

            if (!civilianId || !plate) {
                pushNotification({
                    type: 'error',
                    title: 'Vehicle Registration',
                    message: 'Choose a character and make sure the vehicle plate is filled in.'
                });
                return;
            }

            const submitBtn = MDT.els.vehicleRegisterForm.querySelector('button[type="submit"]');
            if (submitBtn) submitBtn.disabled = true;
            try {
                await Promise.resolve(nuiPost('RegisterVehicleToSelectedCivilian', {
                    civilianId,
                    plate,
                    model
                }));
                closeModal();
                queueLiveRefresh(180);
                setTimeout(() => nuiPost('RequestMyCivilians', {}), 120);
                const refreshTerm = selectedOwnedCivilianLabel() || (MDT.els.dmvInput?.value || '').trim();
                if (refreshTerm) {
                    setTimeout(() => nuiPost('SearchDMV', { term: refreshTerm }), 220);
                }
            } finally {
                if (submitBtn) submitBtn.disabled = false;
            }
        });
    }

    if (MDT.els.vehicleRegisterCancel) {
        MDT.els.vehicleRegisterCancel.addEventListener('click', (e) => {
            e.preventDefault();
            closeModal();
        });
    }

    if (MDT.els.linkCopy) {
        MDT.els.linkCopy.addEventListener('click', async () => {
            const value = MDT.els.linkCodeDisplay?.value || '';
            if (!value) return;
            let copied = false;
            try {
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    await navigator.clipboard.writeText(value);
                    copied = true;
                }
            } catch (_) {}
            if (!copied) {
                try {
                    const temp = document.createElement('textarea');
                    temp.value = value;
                    temp.setAttribute('readonly', 'readonly');
                    temp.style.position = 'fixed';
                    temp.style.opacity = '0';
                    document.body.appendChild(temp);
                    temp.focus();
                    temp.select();
                    copied = document.execCommand('copy');
                    document.body.removeChild(temp);
                } catch (_) {}
            }
            if (copied) pushNotification({ type: 'success', title: 'Copied', message: 'Link code copied to your clipboard.' });
            else pushNotification({ type: 'info', title: 'Copy', message: `Code: ${value}` });
        });
    }

    if (MDT.els.linkClose) {
        MDT.els.linkClose.addEventListener('click', () => closeModal());
    }

    if (MDT.els.webLinkForm) {
        MDT.els.webLinkForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const code = (MDT.els.webLinkCode?.value || '').trim();
            if (!code) return;
            try {
                const result = await browserFetchJson('api/auth/link', { code });
                pushNotification({ type: 'success', title: 'Website Linked', message: result.message || 'Website linked to your in-game account.' });
                if (MDT.els.webLinkCode) MDT.els.webLinkCode.value = '';
                await browserBootstrap(true);
            } catch (err) {
                pushNotification({ type: 'error', title: 'Link Failed', message: err && err.message ? err.message : 'Could not link account.' });
            }
        });
    }

    if (MDT.els.webLinkRefresh) {
        MDT.els.webLinkRefresh.addEventListener('click', () => browserBootstrap(true));
    }

    renderThemeEditorFields();
    renderThemePresetCards();
    fillThemeEditor(MDT.state.themeSettings || { preset: 'blue-command', label: 'Blue Command', vars: {} });

    if (MDT.els.themePresetSelect) {
        MDT.els.themePresetSelect.addEventListener('change', () => {
            const preset = MDT.els.themePresetSelect.value || 'blue-command';
            const presetDef = THEME_PRESETS[preset] || THEME_PRESETS['blue-command'];
            fillThemeEditor({ preset, label: presetDef.label, vars: { ...(presetDef.vars || {}) } });
            renderThemePresetCards();
            syncDerivedThemeFields(true);
            applyThemeFromEditor();
        });
    }

    if (MDT.els.themeLabelInput) {
        MDT.els.themeLabelInput.addEventListener('input', () => applyThemeFromEditor());
    }

    if (MDT.els.themeEditorFields) {
        const syncAndApplyThemeEditor = (event) => {
            const target = event.target;
            if (!target) return;

            if (target.matches('[data-theme-color]')) {
                const fieldKey = target.dataset.themeColor || '';
                buildThemeColorValue(fieldKey);
                if (fieldKey === 'accent' || fieldKey === 'accent-2') {
                    syncDerivedThemeFields(false);
                }
            } else if (target.matches('[data-theme-alpha]')) {
                buildThemeColorValue(target.dataset.themeAlpha || '');
            } else if (target.matches('[data-theme-field]')) {
                const fieldKey = target.dataset.themeField || '';
                if (AUTO_DERIVED_THEME_FIELDS.includes(fieldKey)) {
                    target.dataset.autoDerived = '0';
                }
                syncThemeColorControls(fieldKey, target.value || '');
                if (fieldKey === 'accent' || fieldKey === 'accent-2') {
                    syncDerivedThemeFields(false);
                }
            }

            applyThemeFromEditor();
        };

        MDT.els.themeEditorFields.addEventListener('input', syncAndApplyThemeEditor);
        MDT.els.themeEditorFields.addEventListener('change', syncAndApplyThemeEditor);
    }

    if (MDT.els.themePresetsGrid) {
        MDT.els.themePresetsGrid.addEventListener('click', (e) => {
            const card = e.target.closest('[data-theme-preset-card]');
            if (!card) return;
            const preset = card.dataset.themePresetCard || 'blue-command';
            if (MDT.els.themePresetSelect) MDT.els.themePresetSelect.value = preset;
            const presetDef = THEME_PRESETS[preset] || THEME_PRESETS['blue-command'];
            fillThemeEditor({ preset, label: presetDef.label, vars: { ...(presetDef.vars || {}) } });
            renderThemePresetCards();
            syncDerivedThemeFields(true);
            applyThemeFromEditor();
        });
    }

    if (MDT.els.themeResetBtn) {
        MDT.els.themeResetBtn.addEventListener('click', () => {
            const preset = MDT.els.themePresetSelect?.value || MDT.state.themeSettings?.preset || 'blue-command';
            const presetDef = THEME_PRESETS[preset] || THEME_PRESETS['blue-command'];
            fillThemeEditor({ preset, label: presetDef.label, vars: { ...(presetDef.vars || {}) } });
            renderThemePresetCards();
            syncDerivedThemeFields(true);
            applyThemeFromEditor();
            pushNotification({ type: 'info', title: 'Theme Reset', message: 'Editor values were reset to the selected preset.' });
        });
    }

    if (MDT.els.themeReloadBtn) {
        MDT.els.themeReloadBtn.addEventListener('click', () => {
            if (MDT_RUNTIME.isBrowser) browserHandleAction('GetThemeSettings', {});
            else nuiPost('GetThemeSettings', {});
        });
    }

    if (MDT.els.themeSaveBtn) {
        MDT.els.themeSaveBtn.addEventListener('click', () => {
            if (!(MDT.state.officer && MDT.state.officer.isAdmin)) {
                pushNotification({ type: 'error', title: 'Theme Editor', message: 'Only MDT admins can save themes.' });
                return;
            }
            if (!MDT.state.isAdmin) {
                pushNotification({ type: 'error', title: 'Admin Mode', message: 'Enter admin mode in Employees before saving the global theme.' });
                return;
            }
            const draft = applyThemeFromEditor();
            if (MDT_RUNTIME.isBrowser) browserHandleAction('SaveThemeSettings', draft);
            else nuiPost('SaveThemeSettings', draft);
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

    document.addEventListener('click', async (ev) => {
        const toggle = ev.target.closest('[data-employee-access-toggle]');
        if (toggle) {
            const rowEl = toggle.closest('.mdt-row');
            const editor = rowEl && rowEl.querySelector('.mdt-employee-access-editor');
            if (editor) {
                const nextOpen = !editor.classList.contains('open');
                editor.classList.toggle('open', nextOpen);
                setEmployeeAccessEditorOpen(toggle.dataset.employeeAccessToggle, nextOpen, editor);
            }
            return;
        }

        const save = ev.target.closest('[data-employee-access-save]');
        if (save) {
            if (!(MDT.state.isAdmin && MDT.state.officer && MDT.state.officer.isAdmin)) return;
            const rowEl = save.closest('.mdt-row');
            const editor = rowEl && rowEl.querySelector('.mdt-employee-access-editor');
            if (!editor) return;
            const payload = { id: parseInt(save.dataset.employeeAccessSave, 10) || 0, pages: {}, actions: {} };
            editor.querySelectorAll('[data-employee-perm]').forEach((input) => {
                const key = input.dataset.employeePerm;
                if (!key) return;
                if (input.type === 'checkbox') payload[key] = !!input.checked;
                else payload[key] = input.value;
            });
            editor.querySelectorAll('[data-employee-page]').forEach((input) => {
                const key = input.dataset.employeePage;
                if (key) payload.pages[key] = !!input.checked;
            });
            editor.querySelectorAll('[data-employee-action]').forEach((input) => {
                const key = input.dataset.employeeAction;
                if (key) payload.actions[key] = !!input.checked;
            });
            setEmployeeAccessEditorOpen(payload.id, true, editor);
            save.disabled = true;
            try {
                await Promise.resolve(nuiPost('SaveEmployeeAccess', payload));
                queueLiveRefresh(320);
            } finally {
                save.disabled = false;
            }
            return;
        }
    });

    document.addEventListener('input', (ev) => {
        if (!ev.target.closest || !ev.target.closest('.mdt-employee-access-editor')) return;
        persistEmployeeAccessDraftFromInput(ev.target);
    });

    document.addEventListener('change', (ev) => {
        if (!ev.target.closest || !ev.target.closest('.mdt-employee-access-editor')) return;
        const editor = ev.target.closest('.mdt-employee-access-editor');
        if (ev.target.matches('[data-employee-perm="role"]')) {
            applyRoleDefaultsToEmployeeEditor(editor, String(ev.target.value || 'leo').toLowerCase());
        }
        persistEmployeeAccessDraftFromInput(ev.target);
    });

    document.addEventListener('click', (ev) => {
        const btn = ev.target.closest('[data-admin-action]');
        if (!btn) return;

        const action = btn.dataset.adminAction;
        const canDispatch = canManageDispatchControls();
        const needsAdmin = action === 'delete-report' || action === 'delete-employee';
        if (needsAdmin && !MDT.state.isAdmin) return;
        if (!needsAdmin && !canDispatch) return;

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
        } else if (action === 'delete-warrant') {
            const id = parseInt(btn.dataset.warrantId, 10);
            if (!id) return;
            nuiPost('AdminDeleteWarrant', { id });
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

    if (MDT_RUNTIME.isBrowser) {
        browserBootstrap();
    }

    console.log('[az_mdt] NUI script initialised');
});

function initWindowDrag() {
    MDT.windowEl = document.querySelector('.mdt-window');
    const handle = document.querySelector('.mdt-header');
    if (!MDT.windowEl || !handle) return;

    const key = 'az_mdt_window_position';
    try {
        const raw = localStorage.getItem(key);
        if (raw) {
            const saved = JSON.parse(raw);
            if (typeof saved.left === 'number' && typeof saved.top === 'number') {
                MDT.windowEl.style.left = `${saved.left}px`;
                MDT.windowEl.style.top = `${saved.top}px`;
                MDT.windowEl.style.transform = 'none';
            }
        }
    } catch (_) {}

    let dragging = false;
    let startX = 0;
    let startY = 0;

    const clamp = () => {
        if (!MDT.windowEl) return;
        const rect = MDT.windowEl.getBoundingClientRect();
        let left = rect.left;
        let top = rect.top;
        left = Math.max(0, Math.min(window.innerWidth - rect.width, left));
        top = Math.max(0, Math.min(window.innerHeight - rect.height, top));
        MDT.windowEl.style.left = `${left}px`;
        MDT.windowEl.style.top = `${top}px`;
        MDT.windowEl.style.transform = 'none';
        try {
            localStorage.setItem(key, JSON.stringify({ left, top }));
        } catch (_) {}
    };

    handle.addEventListener('mousedown', (e) => {
        if (e.target.closest('button, input, select, textarea, label')) return;
        dragging = true;
        const rect = MDT.windowEl.getBoundingClientRect();
        startX = e.clientX - rect.left;
        startY = e.clientY - rect.top;
        MDT.windowEl.style.left = `${rect.left}px`;
        MDT.windowEl.style.top = `${rect.top}px`;
        MDT.windowEl.style.transform = 'none';
        document.body.style.userSelect = 'none';
    });

    window.addEventListener('mousemove', (e) => {
        if (!dragging) return;
        let left = e.clientX - startX;
        let top = e.clientY - startY;
        left = Math.max(0, Math.min(window.innerWidth - MDT.windowEl.offsetWidth, left));
        top = Math.max(0, Math.min(window.innerHeight - MDT.windowEl.offsetHeight, top));
        MDT.windowEl.style.left = `${left}px`;
        MDT.windowEl.style.top = `${top}px`;
        MDT.windowEl.style.transform = 'none';
    });

    window.addEventListener('mouseup', () => {
        if (!dragging) return;
        dragging = false;
        document.body.style.userSelect = '';
        clamp();
    });

    window.addEventListener('resize', clamp);
}
