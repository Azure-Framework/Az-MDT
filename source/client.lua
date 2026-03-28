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
local pendingExternalPrefill = nil
local pendingExternalPrefillSeq = 0

local function sendOpenMessages(ctx)
    ctx = ctx or {}
    local ctxJson = jsonEncode(ctx)

    SendNUIMessage({
        action  = "open",
        officer = ctxJson,
        data    = ctxJson
    })

    SendNUIMessage({
        action  = "openMDT",
        officer = ctxJson,
        data    = ctxJson
    })

    SendNUIMessage({
        action  = "mdt:open",
        officer = ctxJson,
        data    = ctxJson
    })
end

local function sendCloseMessages()
    SendNUIMessage({ action = "close" })
    SendNUIMessage({ action = "closeMDT" })
    SendNUIMessage({ action = "mdt:close" })
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

RegisterNetEvent("az_mdt:client:unitsSnapshot", function(payload)
    payload = payload or {}
    unitsCache = payload.units or {}

    SendNUIMessage({
        action = "unitsUpdate",
        data   = jsonEncode(unitsCache)
    })
end)

RegisterNetEvent("az_mdt:client:callsSnapshot", function(list)
    list = list or {}
    dprint("Calls snapshot count:", #list)

    SendNUIMessage({
        action = "callList",
        data   = jsonEncode(list)
    })
end)

RegisterNetEvent("az_mdt:client:callUpdated", function(callData)
    callData = callData or {}
    dprint("CallUpdated id:", tostring(callData.id or "nil"))

    SendNUIMessage({
        action = "callUpdated",
        data   = jsonEncode(callData)
    })
end)

RegisterNetEvent("az_mdt:client:newCallAlert", function(callData)
    callData = callData or {}
    dprint("NewCallAlert id:", tostring(callData.id or "nil"))

    SendNUIMessage({
        action = "newCallAlert",
        data   = jsonEncode(callData)
    })
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
