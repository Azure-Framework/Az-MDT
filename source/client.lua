local RESOURCE_NAME = GetCurrentResourceName()

Config = Config or {}
if Config.Debug == nil then Config.Debug = true end

local function dprint(...)
    if not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(("^3[%s C]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

local jsonEncode = (json and json.encode) or EncodeJson

local function trim(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function stripDispatchTokenPrefix(value)
    local cleaned = trim(value)
    if cleaned == '' then return '' end
    cleaned = cleaned:gsub('^(%b[])%s*', '')
    cleaned = cleaned:gsub('^(%b())%s*', '')
    cleaned = cleaned:gsub('^(%b{})%s*', '')
    return trim(cleaned)
end

local function prettifyServiceLabel(value)
    local raw = trim(value)
    if raw == '' then return 'Call' end
    local lowerRaw = string.lower(raw)
    if lowerRaw == 'ems' then return 'EMS' end
    if lowerRaw == 'leo' or lowerRaw == '5pd' then return 'Police' end
    if lowerRaw == 'fire' then return 'Fire' end
    if lowerRaw == 'parkranger' or lowerRaw == 'park_ranger' or lowerRaw == 'park-ranger' or lowerRaw == 'ranger' or lowerRaw == 'parkrangers' then
        return 'Park Ranger'
    end
    local pretty = raw:gsub('[_%-]+', ' ')
    pretty = pretty:gsub("(%a)([%w_']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest or '')
    end)
    return pretty
end

local function currentStreetLabelFromCoords(coords)
    if type(coords) ~= 'table' then return '', '', '' end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z) or 0.0
    if not x or not y then return '', '', '' end
    local streetHash, crossHash = GetStreetNameAtCoord(x, y, z)
    local street = trim(GetStreetNameFromHashKey(streetHash) or '')
    local cross = (crossHash and crossHash ~= 0) and trim(GetStreetNameFromHashKey(crossHash) or '') or ''
    local label = street
    if cross ~= '' then
        label = (label ~= '' and (label .. ' / ' .. cross)) or cross
    end
    return street, cross, label
end


local function callUnitsLabel(units)
    if type(units) ~= 'table' then return '' end
    local labels = {}
    for _, unit in ipairs(units) do
        if type(unit) == 'table' then
            local callsign = trim(unit.callsign or unit.unit or unit.name or '')
            if callsign ~= '' then
                labels[#labels + 1] = callsign
            end
        end
    end
    return table.concat(labels, ', ')
end

local function buildQuickRespondSpeech(call)
    call = call or {}
    local segments = {}
    local service = prettifyServiceLabel(call.service or call.type or '')
    local id = tostring(call.id or '')
    if service ~= '' and id ~= '' then
        segments[#segments + 1] = ('%s call %s.'):format(service, id)
    elseif id ~= '' then
        segments[#segments + 1] = ('Call %s.'):format(id)
    end

    local status = trim(call.status or '')
    if status ~= '' then segments[#segments + 1] = ('Status %s.'):format(status) end
    local caller = trim(call.caller or '')
    if caller ~= '' then segments[#segments + 1] = ('Caller %s.'):format(caller) end
    local unitsLabel = trim(call.unitsLabel or callUnitsLabel(call.units) or '')
    if unitsLabel ~= '' then segments[#segments + 1] = ('Units %s.'):format(unitsLabel) end
    local createdAt = trim(call.createdAt or call.created_at or '')
    if createdAt ~= '' then segments[#segments + 1] = ('Time %s.'):format(createdAt) end
    local location = trim(call.location or '')
    if location ~= '' then segments[#segments + 1] = ('Location %s.'):format(location) end
    local details = stripDispatchTokenPrefix(call.message or call.details or call.reason or '')
    if details ~= '' then segments[#segments + 1] = details end
    segments[#segments + 1] = 'Press E to respond.'
    return table.concat(segments, ' ')
end

local function drawQuickBannerText(text, x, y, scale, r, g, b, a, center, wrapStart, wrapEnd, font)
    SetTextFont(font or 4)
    SetTextProportional(1)
    SetTextScale(scale, scale)
    SetTextColour(r or 255, g or 255, b or 255, a or 255)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 180)
    SetTextOutline()
    SetTextCentre(center == true)
    SetTextWrap(wrapStart or 0.28, wrapEnd or 0.72)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(tostring(text or ''))
    EndTextCommandDisplayText(x, y)
end

local function drawQuickRespondBanner(data)
    if type(data) ~= 'table' then return end

    local service = string.upper(prettifyServiceLabel(data.service or data.type or 'CALL'))
    local callId = tostring(data.id or '?')
    local status = string.upper(trim(data.status or 'ACTIVE'))
    local caller = trim(data.caller or 'Dispatch')
    local unitsLabel = trim(data.unitsLabel or callUnitsLabel(data.units) or '')
    local createdAt = trim(data.createdAt or data.created_at or '')
    local location = trim(data.location or 'Unknown location')
    local details = stripDispatchTokenPrefix(data.message or data.details or data.reason or '')
    local prompt = trim(data.prompt or 'Press E to respond')

    local header = ('%s • Call #%s'):format(service ~= '' and service or 'CALL', callId)
    local metaLeft = ('Status: %s'):format(status ~= '' and status or 'ACTIVE')
    if caller ~= '' then metaLeft = metaLeft .. ('  •  Caller: %s'):format(caller) end
    local metaRight = ''
    if unitsLabel ~= '' then metaRight = ('Units: %s'):format(unitsLabel) end
    if createdAt ~= '' then
        metaRight = metaRight ~= '' and (metaRight .. ('  •  %s'):format(createdAt)) or createdAt
    end

    local x, y = 0.5, 0.065
    local w, h = 0.56, 0.13
    local accentR, accentG, accentB = 61, 130, 255
    local serviceKey = trim(data.service or ''):lower()
    if serviceKey == 'fire' then
        accentR, accentG, accentB = 217, 76, 76
    elseif serviceKey == 'ems' then
        accentR, accentG, accentB = 61, 178, 122
    elseif serviceKey == 'police' then
        accentR, accentG, accentB = 61, 130, 255
    end

    DrawRect(x, y, w, h, 6, 10, 22, 210)
    DrawRect(x, y - (h / 2) + 0.0045, w, 0.009, accentR, accentG, accentB, 235)
    DrawRect(x, y + (h / 2) - 0.001, w, 0.002, 255, 255, 255, 25)

    drawQuickBannerText(header, x, y - 0.05, 0.39, 255, 255, 255, 245, true, 0.24, 0.76, 4)
    drawQuickBannerText(metaLeft, x, y - 0.015, 0.29, 220, 228, 244, 235, true, 0.24, 0.76, 0)
    if metaRight ~= '' then
        drawQuickBannerText(metaRight, x, y + 0.002, 0.29, 220, 228, 244, 235, true, 0.24, 0.76, 0)
    end
    drawQuickBannerText(location, x, y + 0.024, 0.32, 255, 214, 120, 245, true, 0.25, 0.75, 0)
    if details ~= '' then
        drawQuickBannerText(details, x, y + 0.046, 0.29, 244, 244, 244, 235, true, 0.25, 0.75, 0)
    end
    drawQuickBannerText(prompt, x, y + 0.071, 0.28, accentR, accentG, accentB, 245, true, 0.28, 0.72, 0)
end

local function splitNameParts(value)
    local cleaned = trim(value)
    if cleaned == '' then return '', '' end
    local parts = {}
    for token in cleaned:gmatch('%S+') do parts[#parts + 1] = token end
    if #parts <= 1 then return cleaned, '' end
    local first = table.remove(parts, 1) or ''
    return first, table.concat(parts, ' ')
end

local function getAz5PDResourceName()
    if not Config.UseAz5PD then return nil end

    local names = ((Config.Az5PD or {}).ResourceNames) or { 'Az-5PD', 'az_5pd', 'az-5pd' }
    if type(GetResourceState) == 'function' then
        for _, name in ipairs(names) do
            if name and name ~= '' and GetResourceState(name) == 'started' then
                return name
            end
        end
    end

    return nil
end

local function fetchAz5PDContext(kind)
    local resourceName = getAz5PDResourceName()
    if not resourceName then return nil end

    local ok, payload = pcall(function()
        return exports[resourceName]:GetCurrentMDTContext(kind or '')
    end)
    if not ok or type(payload) ~= 'table' then
        return nil
    end
    return payload
end

local function mergeExternalPayloadFromAz5PD(kind, payload)
    if not Config.UseAz5PD then return payload or {} end

    kind = trim(kind or ''):lower()

    local ctx = fetchAz5PDContext(kind ~= '' and kind or nil)
    if type(ctx) ~= 'table' then return payload or {} end

    local merged = {}
    payload = payload or {}
    local nested = type(payload.search) == 'table' and payload.search or {}
    local preservePage = payload.preservePage == true or nested.preservePage == true or payload.prefillOnly == true or nested.prefillOnly == true

    for k, v in pairs(ctx) do merged[k] = v end
    for k, v in pairs(payload) do
        if v ~= nil and v ~= '' then merged[k] = v end
    end
    merged.search = {}
    for k, v in pairs(ctx) do merged.search[k] = v end
    for k, v in pairs(nested) do
        if v ~= nil and v ~= '' then merged.search[k] = v end
    end

    if kind == 'name' then
        if (merged.name == nil or merged.name == '') and (merged.search.name or '') ~= '' then merged.name = merged.search.name end
        if (merged.first == nil or merged.first == '') and (merged.search.first or '') ~= '' then merged.first = merged.search.first end
        if (merged.last == nil or merged.last == '') and (merged.search.last or '') ~= '' then merged.last = merged.search.last end
        if (merged.value == nil or merged.value == '') then
            merged.value = merged.name or (((merged.first or '') .. ' ' .. (merged.last or '')):gsub('^%s+', ''):gsub('%s+$', ''))
        end
        if not preservePage and (merged.page == nil or merged.page == '') then merged.page = 'nameSearch' end
    elseif kind == 'plate' then
        local ctxPlate = merged.plate or merged.lp or merged.license or merged.value or ''
        if (merged.plate == nil or merged.plate == '') then merged.plate = ctxPlate end
        if (merged.value == nil or merged.value == '') then merged.value = ctxPlate end
        if not preservePage and (merged.page == nil or merged.page == '') then merged.page = 'plateSearch' end
    else
        if (merged.kind == nil or merged.kind == '') and (merged.search.kind or '') ~= '' then merged.kind = merged.search.kind end
        if not preservePage and (merged.page == nil or merged.page == '') and (merged.search.page or '') ~= '' then merged.page = merged.search.page end
        if (merged.value == nil or merged.value == '') then
            merged.value = merged.search.value or merged.search.plate or merged.search.name or ''
        end
        if (merged.plate == nil or merged.plate == '') and (merged.search.plate or '') ~= '' then merged.plate = merged.search.plate end
        if (merged.name == nil or merged.name == '') and (merged.search.name or '') ~= '' then merged.name = merged.search.name end
        if (merged.first == nil or merged.first == '') and (merged.search.first or '') ~= '' then merged.first = merged.search.first end
        if (merged.last == nil or merged.last == '') and (merged.search.last or '') ~= '' then merged.last = merged.search.last end
    end

    if preservePage then
        merged.page = trim(payload.page or nested.page or '')
        merged.prefillOnly = true
        merged.preservePage = true
        merged.search.page = merged.page
        merged.search.prefillOnly = true
        merged.search.preservePage = true
        if payload.autoSearch ~= nil then merged.autoSearch = payload.autoSearch end
        if nested.autoSearch ~= nil and merged.search.autoSearch == nil then merged.search.autoSearch = nested.autoSearch end
    end

    return merged
end

local mdtOpen    = false
local unitsCache = {}
local callsCache = {}
local pendingQuickRespond = nil
local quickRespondAttachState = {}

local function queueQuickRespondAlert(callData)
    callData = callData or {}
    local callId = tonumber(callData.id) or callData.id
    if callId == nil then return end
    callsCache[callId] = callData
    local quickCfg = Config.QuickRespond or {}
    local windowMs = tonumber(quickCfg.windowMs) or 45000
    if windowMs < 15000 then windowMs = 15000 end
    pendingQuickRespond = {
        id = callId,
        expiresAt = GetGameTimer() + windowMs,
        title = tostring(callData.notificationTitle or callData.title or ('Call #' .. tostring(callId))),
        service = tostring(callData.service or callData.type or 'call'),
        status = tostring(callData.status or 'ACTIVE'),
        caller = tostring(callData.caller or 'Dispatch'),
        location = tostring(callData.location or callData.notificationMessage or 'Unknown location'),
        message = stripDispatchTokenPrefix(callData.message or callData.details or callData.reason or ''),
        reason = stripDispatchTokenPrefix(callData.reason or callData.details or callData.message or ''),
        details = stripDispatchTokenPrefix(callData.details or callData.message or callData.reason or ''),
        units = type(callData.units) == 'table' and callData.units or {},
        unitsLabel = tostring(callData.unitsLabel or callUnitsLabel(callData.units) or ''),
        createdAt = tostring(callData.created_at or callData.createdAt or ''),
        prompt = tostring(callData.prompt or 'Press E to respond'),
        speech = buildQuickRespondSpeech(callData),
        coords = type(callData.coords) == 'table' and callData.coords or nil,
        raw = callData,
        externalSource = tostring(callData.externalSource or callData.external_source or callData.sourceResource or callData.externalResource or callData.source or ''),
        metadata = type(callData.metadata) == 'table' and callData.metadata or {}
    }
    dprint('QueuedQuickRespond id:', tostring(callId))
end
local pendingExternalPrefill = nil
local pendingExternalPrefillSeq = 0

local function lowerTrim(value)
    return string.lower(trim(value))
end

local function isPlayerAttachedToCachedCall(callId)
    local id = tonumber(callId) or callId
    local call = id ~= nil and callsCache[id] or nil
    if type(call) ~= 'table' or type(call.units) ~= 'table' then return false end
    local mySrc = GetPlayerServerId(PlayerId())
    for _, unit in ipairs(call.units) do
        if type(unit) == 'table' then
            local unitId = tonumber(unit.id or unit.source or unit.sourceId or unit.unit_source)
            if unitId and unitId == mySrc then
                return true
            end
        end
    end
    return false
end

local function clearQuickRespondAttachState(callId)
    local id = tonumber(callId) or 0
    if id <= 0 then return end
    quickRespondAttachState[id] = nil
end

local function queueQuickRespondAttachRetries(callId, opts)
    local id = tonumber(callId) or 0
    if id <= 0 then return end
    opts = type(opts) == 'table' and opts or {}
    local quickCfg = Config.QuickRespond or {}
    local externalAccepted = opts.externalAccepted == true
    local externalSource = lowerTrim(opts.externalSource or opts.source or '')
    local retryMs = nil
    if externalAccepted then
        if externalSource:find('az%-ambulance', 1, false) or externalSource:find('az_ambulance', 1, true) or externalSource:find('az%-fire', 1, false) or externalSource:find('az_fire', 1, true) then
            retryMs = type(quickCfg.externalAttachRetryServiceMs) == 'table' and quickCfg.externalAttachRetryServiceMs or { 500, 1800, 4200 }
        else
            retryMs = type(quickCfg.externalAttachRetryMs) == 'table' and quickCfg.externalAttachRetryMs or { 500, 1800 }
        end
    else
        retryMs = type(quickCfg.attachRetryMs) == 'table' and quickCfg.attachRetryMs or { 150, 900, 2200, 5000, 8000 }
    end

    local token = GetGameTimer()
    quickRespondAttachState[id] = token

    local function tryAttach()
        if quickRespondAttachState[id] ~= token then return end
        if isPlayerAttachedToCachedCall(id) then
            clearQuickRespondAttachState(id)
            return
        end
        TriggerServerEvent('az_mdt:AttachToCall', id)
        TriggerServerEvent('az_mdt:SetCallWaypoint', id)
    end

    local immediate = (opts.immediate == true)
    if immediate then
        tryAttach()
    end

    for _, delay in ipairs(retryMs) do
        local waitMs = math.max(0, tonumber(delay) or 0)
        SetTimeout(waitMs, function()
            if quickRespondAttachState[id] ~= token then return end
            tryAttach()
        end)
    end
end

local function quickRespondAcceptExternal(callData)
    callData = type(callData) == 'table' and callData or {}
    local externalSource = lowerTrim(callData.externalSource or callData.external_source or callData.sourceResource or callData.externalResource or callData.source or '')
    local metadata = type(callData.metadata) == 'table' and callData.metadata or {}
    local location = trim(callData.location or '')
    local _, _, streetLabel = currentStreetLabelFromCoords(callData.coords or {})
    local derivedAddress = streetLabel ~= '' and streetLabel or location

    local function toId(value)
        if value == nil then return nil end
        local n = tonumber(value)
        if n and n > 0 then return n end
        local s = trim(value)
        return s ~= '' and s or nil
    end

    local accepted = false
    local calloutId = toId(metadata.calloutId or metadata.requestId or callData.calloutId or callData.requestId)
    local emsCallId = toId(metadata.emsCallId or metadata.callId or callData.emsCallId or callData.callId)
    local fireCallId = toId(metadata.fireCallId or metadata.callId or callData.fireCallId or callData.callId)

    if externalSource:find('az%-5pd', 1, false) or externalSource:find('az_5pd', 1, true) then
        if calloutId then
            TriggerServerEvent('az5pd:callouts:accept', calloutId)
            accepted = true
        end
    elseif externalSource:find('az%-parkrangers', 1, false) or externalSource:find('az_parkrangers', 1, true) or externalSource:find('azpr', 1, true) then
        if calloutId then
            TriggerServerEvent('azpr:callouts:accept', calloutId)
            accepted = true
        end
    elseif externalSource:find('az%-ambulance', 1, false) or externalSource:find('az_ambulance', 1, true) then
        if emsCallId then
            TriggerServerEvent('az_ambulance:acceptCallout', emsCallId, derivedAddress ~= '' and derivedAddress or nil)
            accepted = true
        end
    elseif externalSource:find('az%-fire', 1, false) or externalSource:find('az_fire', 1, true) then
        if fireCallId then
            TriggerServerEvent('az_fire:acceptCallout', fireCallId, derivedAddress ~= '' and derivedAddress or nil)
            accepted = true
        end
    end

    return accepted
end


local function sendOpenMessages(ctx)
    ctx = ctx or {}
    local ctxJson = jsonEncode(ctx)

    SendNUIMessage({
        action  = "open",
        officer = ctxJson,
        data    = ctxJson
    })
end

local function sendCloseMessages()
    SendNUIMessage({ action = "close" })
end

local function queueExternalPrefill(prefill, delays, token)
    if not prefill then return end
    delays = delays or { 60, 180, 420, 900, 1500 }
    local queueToken = tonumber(token or pendingExternalPrefillSeq or 0) or 0
    for _, delay in ipairs(delays) do
        Citizen.SetTimeout(delay, function()
            if queueToken ~= pendingExternalPrefillSeq or pendingExternalPrefill ~= prefill then return end
            if not prefill.preservePage and prefill.page and prefill.page ~= '' then
                SendNUIMessage({ action = 'externalPage', page = tostring(prefill.page) })
            end
            SendNUIMessage({
                action = 'externalSearchPrefill',
                data = prefill,
                json = jsonEncode(prefill)
            })
            SendNUIMessage({
                action = 'externalSearchPrefillRaw',
                page = prefill.page,
                kind = prefill.kind or (prefill.search and prefill.search.kind) or '',
                value = prefill.value or (prefill.search and prefill.search.value) or '',
                first = prefill.first or (prefill.search and prefill.search.first) or '',
                last = prefill.last or (prefill.search and prefill.search.last) or '',
                plate = prefill.plate or (prefill.search and prefill.search.plate) or '',
                name = prefill.name or (prefill.search and prefill.search.name) or '',
                source = prefill.source or (prefill.search and prefill.search.source) or 'external',
                search = prefill.search or {}
            })
        end)
    end
end

local function openMDT(ctx)
    if mdtOpen then return end
    mdtOpen = true
    pendingQuickRespond = nil

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    ctx = ctx or {}
    local az5pdResource = getAz5PDResourceName()
    ctx.useAz5PD = Config.UseAz5PD == true
    ctx.az5pdAvailable = az5pdResource ~= nil
    dprint(("Opening MDT for %s dept=%s grade=%s"):format(
        ctx.name or "UNKNOWN",
        ctx.department or "NONE",
        tostring(ctx.grade or 0)
    ))

    TriggerServerEvent('az_mdt:UIState', true)
    sendOpenMessages(ctx)
    if ctx.useAz5PD and ctx.az5pdAvailable then
        TriggerServerEvent('az5pd:sim:requestState')
    end
    if pendingExternalPrefill then
        queueExternalPrefill(pendingExternalPrefill, { 220, 420, 760, 1200, 1800 }, pendingExternalPrefillSeq)
    end
end

local function closeMDT()
    if not mdtOpen then return end
    mdtOpen = false

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)

    TriggerServerEvent('az_mdt:UIState', false)
    dprint("Closing MDT NUI")
    pendingExternalPrefill = nil
    pendingExternalPrefillSeq = pendingExternalPrefillSeq + 1
    sendCloseMessages()
end

RegisterNetEvent("az_mdt:client:open", function(ctx)
    openMDT(ctx or {})
end)

RegisterNetEvent("az_mdt:client:openExternal", function(ctx, payload)
    openMDT(ctx or {})
    payload = payload or {}

    local initialSearch = type(payload.search) == 'table' and payload.search or {}
    local requestedKind = trim(initialSearch.kind or initialSearch.type or payload.kind or payload.type or ''):lower()
    local requestedPage = trim(initialSearch.page or payload.page or '')
    local preservePage = payload.preservePage == true or initialSearch.preservePage == true or payload.prefillOnly == true or initialSearch.prefillOnly == true
    local autoSearch = payload.autoSearch
    if autoSearch == nil then autoSearch = initialSearch.autoSearch end
    if requestedKind == '' then
        if trim(initialSearch.plate or payload.plate or payload.lp or payload.license or '') ~= '' then
            requestedKind = 'plate'
        elseif trim(initialSearch.name or payload.name or initialSearch.first or payload.first or '') ~= '' then
            requestedKind = 'name'
        end
    end

    if requestedKind ~= '' then
        payload = mergeExternalPayloadFromAz5PD(requestedKind, payload)
    elseif Config.UseAz5PD and (requestedPage == '' or requestedPage == 'nameSearch' or requestedPage == 'plateSearch') then
        payload = mergeExternalPayloadFromAz5PD('', payload)
    end

    local rawSearch = type(payload.search) == 'table' and payload.search or {}
    local kind = trim(rawSearch.kind or rawSearch.type or payload.kind or payload.type or ''):lower()
    local page = trim(payload.page or rawSearch.page or '')
    local value = trim(rawSearch.value or rawSearch.term or rawSearch.name or rawSearch.plate or rawSearch.lp or rawSearch.license or payload.value or payload.term or payload.name or payload.plate or payload.lp or payload.license or '')
    local first = trim(rawSearch.first or rawSearch.firstname or payload.first or payload.firstname or '')
    local last = trim(rawSearch.last or rawSearch.lastname or payload.last or payload.lastname or '')
    local plate = trim(rawSearch.plate or rawSearch.lp or rawSearch.license or payload.plate or payload.lp or payload.license or '')
    local owner = trim(rawSearch.owner or rawSearch.owner_name or payload.owner or payload.owner_name or '')
    local ownerName = trim(rawSearch.owner_name or rawSearch.owner or payload.owner_name or payload.owner or '')
    local model = trim(rawSearch.model or rawSearch.make or payload.model or payload.make or '')
    local make = trim(rawSearch.make or rawSearch.model or payload.make or payload.model or '')
    local color = trim(rawSearch.color or payload.color or '')
    local status = trim(rawSearch.status or payload.status or '')
    local source = trim(rawSearch.source or payload.source or 'external')
    local netId = trim(rawSearch.netId or rawSearch.netid or payload.netId or payload.netid or '')
    local resolvedName = trim(rawSearch.name or payload.name or value)

    if kind == '' then
        if plate ~= '' then kind = 'plate'
        elseif first ~= '' or last ~= '' or resolvedName ~= '' then kind = 'name' end
    end
    if Config.UseAz5PD and kind ~= '' then
        local enriched = mergeExternalPayloadFromAz5PD(kind, {
            page = page,
            kind = kind,
            value = value,
            first = first,
            last = last,
            plate = plate,
            name = resolvedName,
            owner = owner,
            owner_name = ownerName,
            model = model,
            make = make,
            color = color,
            status = status,
            source = source,
            netId = netId,
            search = rawSearch
        })
        rawSearch = type(enriched.search) == 'table' and enriched.search or rawSearch
        page = trim(enriched.page or page)
        kind = trim(enriched.kind or kind):lower()
        value = trim(enriched.value or value)
        first = trim(enriched.first or first)
        last = trim(enriched.last or last)
        plate = trim(enriched.plate or enriched.lp or enriched.license or plate)
        owner = trim(enriched.owner or owner)
        ownerName = trim(enriched.owner_name or ownerName)
        model = trim(enriched.model or model)
        make = trim(enriched.make or make)
        color = trim(enriched.color or color)
        status = trim(enriched.status or status)
        source = trim(enriched.source or source)
        netId = trim(enriched.netId or netId)
        resolvedName = trim(enriched.name or resolvedName or value)
    end
    if kind == 'name' and (first == '' and last == '') then
        first, last = splitNameParts(resolvedName ~= '' and resolvedName or value)
    end
    if kind == 'plate' and plate == '' then
        plate = value
    end
    if value == '' then
        if kind == 'plate' then value = plate end
        if kind == 'name' then value = trim(((first ~= '' and first or '') .. ' ' .. (last ~= '' and last or ''))) end
    end
    if resolvedName == '' and kind == 'name' then
        resolvedName = value
    end

    if page == '' and not preservePage then
        if kind == 'plate' then
            page = 'plateSearch'
        elseif kind == 'name' then
            page = 'nameSearch'
        elseif kind == 'report' or kind == 'reports' then
            page = 'reports'
        end
    end

    local prefill = {
        page = page,
        kind = kind,
        value = value,
        first = first,
        last = last,
        plate = plate,
        name = resolvedName,
        owner = owner,
        owner_name = ownerName,
        model = model,
        make = make,
        color = color,
        source = source,
        netId = netId,
        preservePage = preservePage,
        prefillOnly = preservePage,
        autoSearch = autoSearch,
        search = {
            kind = kind,
            type = kind,
            value = value,
            term = value,
            first = first,
            last = last,
            name = resolvedName,
            plate = plate,
            owner = owner,
            owner_name = ownerName,
            model = model,
            make = make,
            color = color,
            status = status,
            source = source,
            netId = netId,
            preservePage = preservePage,
            prefillOnly = preservePage,
            autoSearch = autoSearch
        }
    }

    pendingExternalPrefillSeq = pendingExternalPrefillSeq + 1
    pendingExternalPrefill = prefill
    queueExternalPrefill(prefill, { 40, 120, 260, 520, 900, 1400, 2200 }, pendingExternalPrefillSeq)
end)


RegisterNUICallback("ClearExternalPrefill", function(_, cb)
    pendingExternalPrefill = nil
    pendingExternalPrefillSeq = pendingExternalPrefillSeq + 1
    cb({ ok = true })
end)

RegisterNUICallback("mdt:close", function(_, cb)
    closeMDT()
    cb({ ok = true })
end)

RegisterNUICallback("close", function(_, cb)
    closeMDT()
    cb({ ok = true })
end)

RegisterNUICallback("closeMDT", function(_, cb)
    closeMDT()
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE_NAME then return end
    TriggerServerEvent('az_mdt:UIState', false)
end)

RegisterNetEvent("az_mdt:client:notify", function(data)
    data = data or {}
    local msg   = data.message or "Notification"
    local _type = data.type or "info"
    dprint(("NOTIFY [%s] %s"):format(_type, msg))

    SendNUIMessage({
        action = "notify",
        data   = jsonEncode({
            type     = _type,
            title    = data.title,
            message  = msg,
            duration = tonumber(data.duration) or 4500
        })
    })
end)

RegisterNetEvent("az_mdt:client:webLinkCode", function(data)
    data = data or {}
    SendNUIMessage({
        action = "webLinkCode",
        data   = jsonEncode(data)
    })
end)

RegisterNetEvent('az_mdt:client:simState', function(payload)
    SendNUIMessage({
        action = 'sim:mdtState',
        payload = payload or {}
    })
end)

RegisterNUICallback('simAction', function(data, cb)
    if Config.UseAz5PD and getAz5PDResourceName() then
        TriggerEvent('az5pd:sim:mdtAction', data or {})
    else
        TriggerEvent('az_mdt:client:notify', {
            type = 'warning',
            title = 'Simulation / Scene Tools',
            message = 'Az-5PD is not available, so the integrated simulation panel cannot load.'
        })
    end
    cb({ ok = true })
end)


RegisterNetEvent('az_mdt:client:requestCurrentVehicleRegistration', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        TriggerEvent('chat:addMessage', { args = { '^1Az-MDT', 'Get in a vehicle first or use /regcar [plate] [model].' } })
        return
    end

    local plate = trim(GetVehicleNumberPlateText(veh) or ''):upper()
    local modelHash = GetEntityModel(veh)
    local display = GetDisplayNameFromVehicleModel(modelHash)
    local model = trim(GetLabelText(display) or '')
    if model == '' or model == 'NULL' then model = trim(display or '') end
    if model == '' then model = tostring(modelHash) end

    TriggerServerEvent('az_mdt:RegisterVehicleCurrentVehicleData', {
        plate = plate,
        model = model
    })
end)

RegisterNetEvent('az_mdt:client:promptVehicleRegistration', function(data)
    data = data or {}
    if not mdtOpen then
        openMDT({
            role = 'civ',
            isCiv = true,
            name = GetPlayerName(PlayerId()) or 'Civilian',
            department = 'civilian',
            grade = 0,
            status = 'CIV'
        })
    end
    SendNUIMessage({
        action = 'vehicleRegisterPrompt',
        data = jsonEncode(data)
    })
end)

local function registerAliases(aliases, fn)
    for _, name in ipairs(aliases) do
        RegisterNUICallback(name, fn)
    end
end

registerAliases({ "nameSearch", "NameSearch", "searchName", "SearchName" }, function(data, cb)
    dprint("NUI NameSearch:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:NameSearch", data or {})
    cb({ ok = true })
end)

registerAliases({ "CreateQuickNote", "createQuickNote" }, function(data, cb)
    dprint("NUI CreateQuickNote:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CreateQuickNote", data or {})
    cb({ ok = true })
end)

registerAliases({ "SetIdentityFlags", "setIdentityFlags" }, function(data, cb)
    dprint("NUI SetIdentityFlags:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SetIdentityFlags", data or {})
    cb({ ok = true })
end)

registerAliases({ "CreateWarrant", "createWarrant" }, function(data, cb)
    dprint("NUI CreateWarrant:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CreateWarrant", data or {})
    cb({ ok = true })
end)

registerAliases({ "GetWarrants", "getWarrants", "RequestWarrants", "requestWarrants" }, function(_, cb)
    dprint("NUI RequestWarrants")
    TriggerServerEvent("az_mdt:RequestWarrants")
    cb({ ok = true })
end)

registerAliases({ "AdminDeleteWarrant", "adminDeleteWarrant" }, function(data, cb)
    dprint("NUI AdminDeleteWarrant:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:AdminDeleteWarrant", (data and data.id) or 0)
    cb({ ok = true })
end)

registerAliases({ "plateSearch", "PlateSearch", "searchPlate" }, function(data, cb)
    dprint("NUI PlateSearch:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:PlateSearch", data or {})
    cb({ ok = true })
end)

registerAliases({ "weaponSearch", "WeaponSearch", "searchWeapon" }, function(data, cb)
    dprint("NUI WeaponSearch:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:WeaponSearch", data or {})
    cb({ ok = true })
end)

registerAliases({ "getBolos", "GetBolos", "bolosList" }, function(_, cb)
    dprint("NUI RequestBolos")
    TriggerServerEvent("az_mdt:RequestBolos")
    cb({ ok = true })
end)

registerAliases({ "createBolo", "CreateBolo" }, function(data, cb)
    dprint("NUI CreateBolo:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CreateBolo", data or {})
    cb({ ok = true })
end)

registerAliases({ "getReports", "GetReports", "reportsList" }, function(_, cb)
    dprint("NUI RequestReports")
    TriggerServerEvent("az_mdt:RequestReports")
    cb({ ok = true })
end)

registerAliases({ "SearchReports", "searchReports" }, function(data, cb)
    dprint("NUI SearchReports:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SearchReports", data or {})
    cb({ ok = true })
end)

registerAliases({ "createReport", "CreateReport" }, function(data, cb)
    dprint("NUI CreateReport:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CreateReport", data or {})
    cb({ ok = true })
end)

registerAliases({ "viewEmployees", "ViewEmployees", "employeesList" }, function(_, cb)
    dprint("NUI ViewEmployees")
    TriggerServerEvent("az_mdt:ViewEmployees")
    cb({ ok = true })
end)

registerAliases({ "SaveEmployeeAccess", "saveEmployeeAccess" }, function(data, cb)
    dprint("NUI SaveEmployeeAccess:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SaveEmployeeAccess", data or {})
    cb({ ok = true })
end)

registerAliases({ "RegisterVehicleToSelectedCivilian", "registerVehicleToSelectedCivilian" }, function(data, cb)
    dprint("NUI RegisterVehicleToSelectedCivilian:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:RegisterVehicleToSelectedCivilian", data or {})
    cb({ ok = true })
end)

registerAliases({ "CreateCivilian", "createCivilian" }, function(data, cb)
    dprint("NUI CreateCivilian:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CreateCivilian", data or {})
    cb({ ok = true })
end)

registerAliases({ "SearchCivilianRegistry", "searchCivilianRegistry" }, function(data, cb)
    dprint("NUI SearchCivilianRegistry:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SearchCivilianRegistry", data or {})
    cb({ ok = true })
end)

registerAliases({ "SearchDMV", "searchDMV" }, function(data, cb)
    dprint("NUI SearchDMV:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SearchDMV", data or {})
    cb({ ok = true })
end)

registerAliases({ "RequestMyCivilians", "requestMyCivilians" }, function(_, cb)
    dprint("NUI RequestMyCivilians")
    TriggerServerEvent("az_mdt:RequestMyCivilians")
    cb({ ok = true })
end)

registerAliases({ "CreateCivilianVehicle", "createCivilianVehicle" }, function(data, cb)
    dprint("NUI CreateCivilianVehicle:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CreateCivilianVehicle", data or {})
    cb({ ok = true })
end)

registerAliases({ "RegisterCivilianWeapon", "registerCivilianWeapon" }, function(data, cb)
    dprint("NUI RegisterCivilianWeapon:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:RegisterCivilianWeapon", data or {})
    cb({ ok = true })
end)

registerAliases({ "DeleteCivilianVehicle", "deleteCivilianVehicle" }, function(data, cb)
    dprint("NUI DeleteCivilianVehicle:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:DeleteCivilianVehicle", data or {})
    cb({ ok = true })
end)

registerAliases({ "DeleteCivilianWeapon", "deleteCivilianWeapon" }, function(data, cb)
    dprint("NUI DeleteCivilianWeapon:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:DeleteCivilianWeapon", data or {})
    cb({ ok = true })
end)

registerAliases({ "CreateOfficerCall", "createOfficerCall" }, function(data, cb)
    data = data or {}
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    if not data.coords then
        data.coords = { x = coords.x, y = coords.y, z = coords.z }
    end
    if not data.location or tostring(data.location) == '' then
        local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
        local street = GetStreetNameFromHashKey(streetHash)
        local cross = (crossHash and crossHash ~= 0) and GetStreetNameFromHashKey(crossHash) or nil
        local location = street or "Unknown"
        if cross and cross ~= "" then
            location = ("%s / %s"):format(location, cross)
        end
        data.location = location
    end
    dprint("NUI CreateOfficerCall:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CreateOfficerCall", data or {})
    cb({ ok = true })
end)

registerAliases({ "CreateTrafficStop", "createTrafficStop" }, function(data, cb)
    data = data or {}
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    if not data.coords then
        data.coords = { x = coords.x, y = coords.y, z = coords.z }
    end
    if not data.location or tostring(data.location) == '' then
        local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
        local street = GetStreetNameFromHashKey(streetHash)
        local cross = (crossHash and crossHash ~= 0) and GetStreetNameFromHashKey(crossHash) or nil
        local location = street or "Unknown"
        if cross and cross ~= "" then
            location = ("%s / %s"):format(location, cross)
        end
        data.location = location
    end
    dprint("NUI CreateTrafficStop:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CreateTrafficStop", data or {})
    cb({ ok = true })
end)

registerAliases({ "DeleteQuickNote", "deleteQuickNote" }, function(data, cb)
    dprint("NUI DeleteQuickNote:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:DeleteQuickNote", data or {})
    cb({ ok = true })
end)

registerAliases({ "UpdateUnitProfile", "updateUnitProfile" }, function(data, cb)
    dprint("NUI UpdateUnitProfile:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:UpdateUnitProfile", data or {})
    cb({ ok = true })
end)

registerAliases({ "RequestWebLinkCode", "requestWebLinkCode" }, function(_, cb)
    dprint("NUI RequestWebLinkCode")
    TriggerServerEvent("az_mdt:RequestWebLinkCode")
    cb({ ok = true })
end)

registerAliases({ "DeleteCivilian", "deleteCivilian" }, function(data, cb)
    dprint("NUI DeleteCivilian:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:DeleteCivilian", data or {})
    cb({ ok = true })
end)

registerAliases({ "UpdateDMVStatus", "updateDMVStatus" }, function(data, cb)
    dprint("NUI UpdateDMVStatus:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:UpdateDMVStatus", data or {})
    cb({ ok = true })
end)

registerAliases({ "CreateCivilianReport", "createCivilianReport" }, function(data, cb)
    dprint("NUI CreateCivilianReport:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CreateCivilianReport", data or {})
    cb({ ok = true })
end)

registerAliases({ "getUnits", "GetUnits", "RequestUnits" }, function(_, cb)
    dprint("NUI RequestUnits")
    TriggerServerEvent("az_mdt:RequestUnits")
    cb({ ok = true })
end)

registerAliases({ "setUnitStatus", "SetUnitStatus" }, function(data, cb)
    dprint("NUI SetUnitStatus:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SetUnitStatus", (data and data.status) or "AVAILABLE")
    cb({ ok = true })
end)

registerAliases({ "SetDutyState", "setDutyState" }, function(data, cb)
    dprint("NUI SetDutyState:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SetDutyState", data or {})
    cb({ ok = true })
end)

registerAliases({ "panic", "Panic" }, function(_, cb)
    dprint("NUI Panic")
    TriggerServerEvent("az_mdt:Panic")
    cb({ ok = true })
end)

registerAliases({ "hospital", "Hospital" }, function(_, cb)
    dprint("NUI Hospital")
    TriggerServerEvent("az_mdt:Hospital")
    cb({ ok = true })
end)

registerAliases({ "GetCalls", "getCalls" }, function(_, cb)
    dprint("NUI RequestCalls")
    TriggerServerEvent("az_mdt:RequestCalls")
    cb({ ok = true })
end)

registerAliases({ "AttachCall", "attachCall" }, function(data, cb)
    dprint("NUI AttachCall:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:AttachToCall", (data and data.id) or 0)
    cb({ ok = true })
end)

registerAliases({ "DetachCall", "detachCall" }, function(data, cb)
    dprint("NUI DetachCall:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:DetachFromCall", (data and data.id) or 0)
    cb({ ok = true })
end)

registerAliases({ "CallWaypoint", "callWaypoint" }, function(data, cb)
    dprint("NUI CallWaypoint:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SetCallWaypoint", (data and data.id) or 0)
    cb({ ok = true })
end)

registerAliases({ "LiveChatSend", "liveChatSend" }, function(data, cb)
    dprint("NUI LiveChatSend:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:LiveChatSend", data or {})
    cb({ ok = true })
end)

registerAliases({ "RequestChatHistory", "requestChatHistory", "GetChatHistory" }, function(_, cb)
    dprint("NUI RequestChatHistory")
    TriggerServerEvent("az_mdt:RequestChatHistory")
    cb({ ok = true })
end)

registerAliases({ "RequestLeoChat", "requestLeoChat", "GetLeoChat" }, function(_, cb)
    dprint("NUI RequestLeoChat")
    TriggerServerEvent("az_mdt:RequestLeoChat")
    cb({ ok = true })
end)

registerAliases({ "SaveLiveMapIcons", "saveLiveMapIcons" }, function(data, cb)
    dprint("NUI SaveLiveMapIcons:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SaveLiveMapIcons", data or {})
    cb({ ok = true })
end)

registerAliases({ "LeoChatSend", "leoChatSend" }, function(data, cb)
    dprint("NUI LeoChatSend:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:LeoChatSend", data or {})
    cb({ ok = true })
end)

registerAliases({ "RequestCallRoom", "requestCallRoom", "GetCallRoom" }, function(data, cb)
    dprint("NUI RequestCallRoom:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:RequestCallRoom", data or {})
    cb({ ok = true })
end)

registerAliases({ "CallRoomSend", "callRoomSend" }, function(data, cb)
    dprint("NUI CallRoomSend:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CallRoomSend", data or {})
    cb({ ok = true })
end)

registerAliases({ "CallRoomNote", "callRoomNote" }, function(data, cb)
    dprint("NUI CallRoomNote:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CallRoomNote", data or {})
    cb({ ok = true })
end)

registerAliases({ "SearchCallHistory", "searchCallHistory" }, function(data, cb)
    dprint("NUI SearchCallHistory:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SearchCallHistory", data or {})
    cb({ ok = true })
end)

registerAliases({ "GetActionLog", "getActionLog" }, function(_, cb)
    dprint("NUI RequestActionLog")
    TriggerServerEvent("az_mdt:RequestActionLog")
    cb({ ok = true })
end)

registerAliases({ "SetOtherUnitStatus", "setOtherUnitStatus" }, function(data, cb)
    dprint("NUI SetOtherUnitStatus:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SetOtherUnitStatus", data or {})
    cb({ ok = true })
end)

registerAliases({ "DispatchStatusCheck", "dispatchStatusCheck" }, function(data, cb)
    dprint("NUI DispatchStatusCheck:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:DispatchStatusCheck", data or {})
    cb({ ok = true })
end)

registerAliases({ "GetThemeSettings", "getThemeSettings" }, function(_, cb)
    dprint("NUI RequestThemeSettings")
    TriggerServerEvent("az_mdt:RequestThemeSettings")
    cb({ ok = true })
end)

registerAliases({ "SaveThemeSettings", "saveThemeSettings" }, function(data, cb)
    dprint("NUI SaveThemeSettings:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SaveThemeSettings", data or {})
    cb({ ok = true })
end)

registerAliases({ "AdminDeleteBolo", "adminDeleteBolo" }, function(data, cb)
    dprint("NUI AdminDeleteBolo:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:AdminDeleteBolo", (data and data.id) or 0)
    cb({ ok = true })
end)

registerAliases({ "AdminDeleteReport", "adminDeleteReport" }, function(data, cb)
    dprint("NUI AdminDeleteReport:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:AdminDeleteReport", (data and data.id) or 0)
    cb({ ok = true })
end)

registerAliases({ "AdminDeleteCall", "adminDeleteCall" }, function(data, cb)
    dprint("NUI AdminDeleteCall:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:AdminDeleteCall", (data and data.id) or 0)
    cb({ ok = true })
end)

registerAliases({ "AdminDeleteEmployee", "adminDeleteEmployee" }, function(data, cb)
    dprint("NUI AdminDeleteEmployee:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:AdminDeleteEmployee", data or {})
    cb({ ok = true })
end)

RegisterNetEvent("az_mdt:client:nameResults", function(payload)
    payload = payload or {}
    local payloadJson = jsonEncode(payload)

    dprint(("NameResults term='%s' citizens=%s records=%s"):format(
        tostring(payload.term or ""),
        tostring(payload.citizens and #payload.citizens or 0),
        tostring(payload.records and #payload.records or 0)
    ))

    SendNUIMessage({
        action = "nameResults",
        data   = payloadJson
    })

    SendNUIMessage({
        action = "NameSearchResults",
        data   = payloadJson
    })
end)

RegisterNetEvent("az_mdt:client:plateResults", function(payload)
    payload = payload or {}
    dprint("PlateResults vehicles:", tostring(payload.vehicles and #payload.vehicles or 0),
           "records:", tostring(payload.records and #payload.records or 0))

    SendNUIMessage({
        action = "plateResults",
        data   = jsonEncode(payload)
    })
end)

RegisterNetEvent("az_mdt:client:weaponResults", function(payload)
    payload = payload or {}
    dprint("WeaponResults (stub)")

    SendNUIMessage({
        action = "weaponResults",
        data   = jsonEncode(payload)
    })
end)

RegisterNetEvent("az_mdt:client:boloList", function(list)
    list = list or {}
    dprint("BoloList count:", #list)
    local listJson = jsonEncode(list)

    SendNUIMessage({
        action = "boloList",
        data   = listJson
    })
end)

RegisterNetEvent("az_mdt:client:boloCreated", function(row)
    row = row or {}
    dprint("BoloCreated id:", tostring(row.id or "nil"))

    SendNUIMessage({
        action = "boloCreated",
        data   = jsonEncode(row)
    })
end)

RegisterNetEvent("az_mdt:client:boloAlert", function(row)
    row = row or {}
    dprint("BoloAlert id:", tostring(row.id or "nil"))

    SendNUIMessage({
        action = "boloAlert",
        data   = jsonEncode(row)
    })
end)

RegisterNetEvent("az_mdt:client:panic", function(payload)
    payload = payload or {}
    dprint("Panic payload from server")

    local coords = payload.coords or {}
    if coords.x and coords.y then
        SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
        local blip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, (coords.z or 0.0) + 0.0)
        if blip and blip ~= 0 then
            SetBlipSprite(blip, 161)
            SetBlipScale(blip, 1.3)
            SetBlipColour(blip, 1)
            SetBlipFlashes(blip, true)
            SetBlipFlashTimer(blip, 30000)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(('PANIC | %s'):format(payload.callsign or payload.officer or 'Officer'))
            EndTextCommandSetBlipName(blip)
            CreateThread(function()
                Wait(180000)
                if DoesBlipExist(blip) then
                    RemoveBlip(blip)
                end
            end)
        end
    end

    SendNUIMessage({
        action = "panic",
        data   = jsonEncode(payload)
    })
end)

RegisterNetEvent("az_mdt:client:reportList", function(list)
    list = list or {}
    dprint("ReportList count:", #list)
    local listJson = jsonEncode(list)

    SendNUIMessage({
        action = "reportList",
        data   = listJson
    })
end)

RegisterNetEvent("az_mdt:client:reportCreated", function(row)
    row = row or {}
    dprint("ReportCreated id:", tostring(row.id or "nil"))

    SendNUIMessage({
        action = "reportCreated",
        data   = jsonEncode(row)
    })
end)

RegisterNetEvent("az_mdt:client:employees", function(list)
    list = list or {}
    dprint("Employees count:", #list)

    SendNUIMessage({
        action = "employeesList",
        data   = jsonEncode(list)
    })
end)

local function resolveStreetLocationFromCoords(coords)
    if type(coords) ~= 'table' or coords.x == nil or coords.y == nil then return nil end
    local x = tonumber(coords.x) or 0.0
    local y = tonumber(coords.y) or 0.0
    local z = tonumber(coords.z) or 0.0
    local streetHash, crossHash = GetStreetNameAtCoord(x, y, z)
    local street = trim(GetStreetNameFromHashKey(streetHash) or '')
    local cross = (crossHash and crossHash ~= 0) and trim(GetStreetNameFromHashKey(crossHash) or '') or ''
    if street == '' then return nil end
    if cross ~= '' and cross ~= street then
        return ('%s / %s'):format(street, cross)
    end
    return street
end

local function locationLooksLikeCoords(value)
    value = string.lower(trim(value or ''))
    if value == '' then return true end
    if value == 'unknown location' or value == 'unknown address' then return true end
    if value:match('^near%s+%-?%d+[%.%d]*%s*/%s*%-?%d+[%.%d]*$') then return true end
    if value:match('^%-?%d+[%.%d]*%s*,%s*%-?%d+[%.%d]*$') then return true end
    return false
end

local function enrichIncomingCall(call)
    if type(call) ~= 'table' then return call end
    local streetLocation = resolveStreetLocationFromCoords(call.coords)
    if streetLocation and locationLooksLikeCoords(call.location) then
        call.location = streetLocation
    end
    if streetLocation and trim(call.street or '') == '' then
        call.street = streetLocation
    end
    if streetLocation and locationLooksLikeCoords(call.notificationMessage) then
        call.notificationMessage = streetLocation
    end
    return call
end

local function enrichIncomingCalls(list)
    if type(list) ~= 'table' then return list end
    for i = 1, #list do
        list[i] = enrichIncomingCall(list[i])
    end
    return list
end

RegisterNetEvent("az_mdt:client:unitsSnapshot", function(payload)
    payload = payload or {}
    unitsCache = payload.units or {}

    SendNUIMessage({
        action = "unitsUpdate",
        data   = jsonEncode(unitsCache)
    })
end)

RegisterNetEvent("az_mdt:client:liveMapIcons", function(payload)
    payload = payload or {}
    SendNUIMessage({
        action = "liveMapIcons",
        data   = jsonEncode(payload)
    })
end)

RegisterNetEvent("az_mdt:client:callsSnapshot", function(list)
    list = enrichIncomingCalls(list or {})
    callsCache = {}
    for _, call in ipairs(list) do
        if type(call) == 'table' and call.id ~= nil then
            callsCache[tonumber(call.id) or call.id] = call
        end
    end
    dprint("Calls snapshot count:", #list)

    SendNUIMessage({
        action = "callList",
        data   = jsonEncode(list)
    })
end)

RegisterNetEvent("az_mdt:client:callUpdated", function(callData)
    callData = enrichIncomingCall(callData or {})
    local callId = tonumber(callData.id) or callData.id
    if callId ~= nil then
        local status = tostring(callData.status or ''):upper()
        if status == 'CLEARED' or status == 'CLOSED' then
            callsCache[callId] = nil
            clearQuickRespondAttachState(callId)
        else
            callsCache[callId] = callData
            if isPlayerAttachedToCachedCall(callId) then
                clearQuickRespondAttachState(callId)
            end
        end
    end
    dprint("CallUpdated id:", tostring(callData.id or "nil"))

    SendNUIMessage({
        action = "callUpdated",
        data   = jsonEncode(callData)
    })
end)

RegisterNetEvent("az_mdt:client:newCallAlert", function(callData)
    callData = enrichIncomingCall(callData or {})
    local callId = tonumber(callData.id) or callData.id
    if callId ~= nil then
        callsCache[callId] = callData
        if not mdtOpen then
            queueQuickRespondAlert(callData)
        end
    end
    dprint("NewCallAlert id:", tostring(callData.id or "nil"))

    SendNUIMessage({
        action = "newCallAlert",
        data   = jsonEncode(callData)
    })
end)

RegisterNetEvent("az_mdt:client:quickRespondAlert", function(callData)
    if mdtOpen then return end
    queueQuickRespondAlert(enrichIncomingCall(callData or {}))
end)

RegisterNetEvent("az_mdt:client:setWaypoint", function(coords)
    if not coords or not coords.x or not coords.y then return end
    SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
end)

RegisterNetEvent("az_mdt:client:liveChatHistory", function(list)
    list = list or {}
    SendNUIMessage({
        action = "liveChatHistory",
        data   = jsonEncode(list)
    })
end)

RegisterNetEvent("az_mdt:client:liveChatMessage", function(msg)
    msg = msg or {}
    SendNUIMessage({
        action = "liveChatMessage",
        data   = jsonEncode(msg)
    })
end)

RegisterNetEvent("az_mdt:client:statusUpdate", function(status)
    SendNUIMessage({
        action = "statusUpdate",
        status = status or "AVAILABLE"
    })
end)

RegisterNetEvent("az_mdt:client:warrantsList", function(list)
    list = list or {}
    dprint("WarrantsList count:", #list)

    SendNUIMessage({
        action = "warrantsList",
        data   = jsonEncode(list)
    })
end)

RegisterNetEvent("az_mdt:client:actionLog", function(list)
    list = list or {}
    dprint("ActionLog count:", #list)

    SendNUIMessage({
        action = "actionLog",
        data   = jsonEncode(list)
    })
end)

RegisterNetEvent("az_mdt:client:themeSettings", function(theme)
    theme = theme or {}
    SendNUIMessage({
        action = "themeSettings",
        data   = jsonEncode(theme)
    })
end)

RegisterNetEvent("az_mdt:client:reportSearchResults", function(list)
    list = list or {}
    SendNUIMessage({ action = "reportSearchResults", data = jsonEncode(list) })
end)

RegisterNetEvent("az_mdt:client:civilianRegistry", function(list)
    list = list or {}
    SendNUIMessage({ action = "civilianRegistry", data = jsonEncode(list) })
end)

RegisterNetEvent("az_mdt:client:myCivilians", function(list)
    list = list or {}
    SendNUIMessage({ action = "myCivilians", data = jsonEncode(list) })
end)

RegisterNetEvent("az_mdt:client:unitProfileUpdated", function(ctx)
    ctx = ctx or {}
    SendNUIMessage({ action = "unitProfileUpdated", data = jsonEncode(ctx) })
end)

RegisterNetEvent("az_mdt:client:dmvResults", function(list)
    list = list or {}
    SendNUIMessage({ action = "dmvResults", data = jsonEncode(list) })
end)

RegisterNetEvent("az_mdt:client:leoChatHistory", function(list)
    list = list or {}
    SendNUIMessage({ action = "leoChatHistory", data = jsonEncode(list) })
end)

RegisterNetEvent("az_mdt:client:leoChatMessage", function(msg)
    msg = msg or {}
    SendNUIMessage({ action = "leoChatMessage", data = jsonEncode(msg) })
end)

RegisterNetEvent("az_mdt:client:leoChatReset", function(data)
    data = data or {}
    SendNUIMessage({ action = "leoChatReset", data = jsonEncode(data) })
end)

RegisterNetEvent("az_mdt:client:callRoomOpened", function(payload)
    payload = payload or {}
    SendNUIMessage({ action = "callRoomOpened", data = jsonEncode(payload) })
end)

RegisterNetEvent("az_mdt:client:callRoomMessage", function(payload)
    payload = payload or {}
    SendNUIMessage({ action = "callRoomMessage", data = jsonEncode(payload) })
end)

RegisterNetEvent("az_mdt:client:callRoomNote", function(payload)
    payload = payload or {}
    SendNUIMessage({ action = "callRoomNote", data = jsonEncode(payload) })
end)

RegisterNetEvent("az_mdt:client:callHistoryResults", function(list)
    list = list or {}
    SendNUIMessage({ action = "callHistoryResults", data = jsonEncode(list) })
end)

RegisterCommand("911", function(_, args)
    local message = table.concat(args, " ")
    if message == "" then
        dprint("Usage: /911 [message]")
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local cross  = (crossHash and crossHash ~= 0) and GetStreetNameFromHashKey(crossHash) or nil
    local location = street or "Unknown"
    if cross and cross ~= "" then
        location = ("%s / %s"):format(location, cross)
    end

    TriggerServerEvent("az_mdt:Create911", {
        message  = message,
        coords   = { x = coords.x, y = coords.y, z = coords.z },
        location = location
    })
end, false)


RegisterNetEvent("az_mdt:client:dispatchStatusCheck", function(payload)
    payload = payload or {}
    SendNUIMessage({
        action = "dispatchStatusCheck",
        data   = jsonEncode(payload)
    })
end)


CreateThread(function()
    local interval = tonumber((Config.LiveMap or {}).updateIntervalMs) or 1750
    if interval < 750 then interval = 750 end
    while true do
        Wait(interval)
        local ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            local coords = GetEntityCoords(ped)
            local vehicle = GetVehiclePedIsIn(ped, false)
            local street, crossStreet, locationText = currentStreetLabelFromCoords({ x = coords.x, y = coords.y, z = coords.z })
            TriggerServerEvent('az_mdt:UpdateUnitLocation', {
                coords = { x = coords.x, y = coords.y, z = coords.z },
                heading = GetEntityHeading(ped),
                inVehicle = vehicle ~= 0,
                vehicleClass = vehicle ~= 0 and GetVehicleClass(vehicle) or -1,
                street = street,
                crossStreet = crossStreet,
                locationText = locationText
            })
        end
    end
end)


local function isLocalUnitAttachedToCall(call, src)
    if type(call) ~= 'table' or type(call.units) ~= 'table' then return false end
    for _, unit in ipairs(call.units) do
        local unitId = tonumber((unit and (unit.id or unit.source or unit.sourceId)))
        if unitId and unitId == src then
            return true
        end
    end
    return false
end

local function findNearestAttachedCall(coords, src)
    local bestCall, bestDist = nil, nil
    for _, call in pairs(callsCache) do
        local callCoords = type(call) == 'table' and type(call.coords) == 'table' and call.coords or nil
        local status = tostring((call and call.status) or ''):upper()
        if callCoords and callCoords.x and callCoords.y and status ~= 'CLEARED' and status ~= 'CLOSED' and isLocalUnitAttachedToCall(call, src) then
            local dx = (coords.x - tonumber(callCoords.x))
            local dy = (coords.y - tonumber(callCoords.y))
            local dz = (coords.z - (tonumber(callCoords.z) or 0.0))
            local dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
            if not bestDist or dist < bestDist then
                bestCall, bestDist = call, dist
            end
        end
    end
    return bestCall, bestDist
end

CreateThread(function()
    local cfg = Config.CallAutoArrival or {}
    if cfg.enabled == false then return end
    local interval = tonumber(cfg.recheckIntervalMs) or 1000
    if interval < 500 then interval = 500 end
    local arrivalDistance = tonumber(cfg.arrivalDistance) or 75.0
    if arrivalDistance < 5.0 then arrivalDistance = 5.0 end
    local repeatCooldownMs = tonumber(cfg.repeatCooldownMs) or 15000
    if repeatCooldownMs < 2000 then repeatCooldownMs = 2000 end
    local lastReportedByCall = {}

    while true do
        Wait(interval)
        local ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
            local src = GetPlayerServerId(PlayerId())
            local coords = GetEntityCoords(ped)
            local nearestCall, nearestDist = findNearestAttachedCall(coords, src)
            if nearestCall and nearestDist and nearestDist <= arrivalDistance then
                local callId = tonumber(nearestCall.id) or nearestCall.id
                local now = GetGameTimer()
                local lastAt = tonumber(lastReportedByCall[callId]) or 0
                if (now - lastAt) >= repeatCooldownMs then
                    TriggerServerEvent('az_mdt:MarkUnitOnSceneForCall', callId, { distance = nearestDist })
                    lastReportedByCall[callId] = now
                end
            end
        else
            Wait(250)
        end
    end
end)


CreateThread(function()
    while true do
        if pendingQuickRespond and not mdtOpen then
            Wait(0)
            if (tonumber(pendingQuickRespond.expiresAt) or 0) <= GetGameTimer() then
                pendingQuickRespond = nil
            else
                DisableControlAction(0, 199, true)
                if IsControlJustReleased(0, 38) then
                    local quick = pendingQuickRespond
                    local callId = tonumber(quick and quick.id) or 0
                    local handledExternal = quickRespondAcceptExternal((quick and quick.raw) or quick or {})
                    if callId > 0 then
                        local quickCfg = Config.QuickRespond or {}
                        if handledExternal then
                            queueQuickRespondAttachRetries(callId, {
                                externalAccepted = true,
                                externalSource = (((quick and quick.raw) or quick or {}).externalSource or ((quick and quick.raw) or quick or {}).external_source or ((quick and quick.raw) or quick or {}).sourceResource or ((quick and quick.raw) or quick or {}).externalResource or ''),
                                immediate = quickCfg.useImmediateAttachForExternalAccept == true
                            })
                        else
                            queueQuickRespondAttachRetries(callId, { immediate = true })
                        end
                        TriggerEvent('az_mdt:client:notify', {
                            type = 'success',
                            title = 'Call Response',
                            message = ('Responding to call #%s.'):format(tostring(callId))
                        })
                    end
                    pendingQuickRespond = nil
                    Wait(250)
                end
            end
        else
            Wait(250)
        end
    end
end)
