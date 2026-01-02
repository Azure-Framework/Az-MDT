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

local mdtOpen    = false
local unitsCache = {}

-------------------------------------------------
-- NUI OPEN / CLOSE
-------------------------------------------------

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

local function openMDT(ctx)
    if mdtOpen then return end
    mdtOpen = true

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    ctx = ctx or {}
    dprint(("Opening MDT for %s dept=%s grade=%s"):format(
        ctx.name or "UNKNOWN",
        ctx.department or "NONE",
        tostring(ctx.grade or 0)
    ))

    sendOpenMessages(ctx)
end

local function closeMDT()
    if not mdtOpen then return end
    mdtOpen = false

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)

    dprint("Closing MDT NUI")
    sendCloseMessages()
end

RegisterNetEvent("az_mdt:client:open", function(ctx)
    openMDT(ctx or {})
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

-------------------------------------------------
-- SIMPLE NOTIFY
-------------------------------------------------

RegisterNetEvent("az_mdt:client:notify", function(data)
    data = data or {}
    local msg   = data.message or "Notification"
    local _type = data.type or "info"
    dprint(("NOTIFY [%s] %s"):format(_type, msg))
    -- hook your own notification system here if needed
end)

-------------------------------------------------
-- NUI CALLBACK REGISTRATION HELPER
-------------------------------------------------

local function registerAliases(aliases, fn)
    for _, name in ipairs(aliases) do
        RegisterNUICallback(name, fn)
    end
end

-------------------------------------------------
-- NUI → SERVER
-------------------------------------------------

-- Name search
registerAliases({ "nameSearch", "NameSearch", "searchName", "SearchName" }, function(data, cb)
    dprint("NUI NameSearch:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:NameSearch", data or {})
    cb({ ok = true })
end)

-- Quick notes / flags / warrants
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

-- Plate search
registerAliases({ "plateSearch", "PlateSearch", "searchPlate" }, function(data, cb)
    dprint("NUI PlateSearch:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:PlateSearch", data or {})
    cb({ ok = true })
end)

-- Weapon search
registerAliases({ "weaponSearch", "WeaponSearch", "searchWeapon" }, function(data, cb)
    dprint("NUI WeaponSearch:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:WeaponSearch", data or {})
    cb({ ok = true })
end)

-- BOLOS
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

-- REPORTS
registerAliases({ "getReports", "GetReports", "reportsList" }, function(_, cb)
    dprint("NUI RequestReports")
    TriggerServerEvent("az_mdt:RequestReports")
    cb({ ok = true })
end)

registerAliases({ "createReport", "CreateReport" }, function(data, cb)
    dprint("NUI CreateReport:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:CreateReport", data or {})
    cb({ ok = true })
end)

-- EMPLOYEES
registerAliases({ "viewEmployees", "ViewEmployees", "employeesList" }, function(_, cb)
    dprint("NUI ViewEmployees")
    TriggerServerEvent("az_mdt:ViewEmployees")
    cb({ ok = true })
end)

-- UNITS
registerAliases({ "getUnits", "GetUnits", "RequestUnits" }, function(_, cb)
    dprint("NUI RequestUnits")
    TriggerServerEvent("az_mdt:RequestUnits")
    cb({ ok = true })
end)

-- STATUS / PANIC / HOSPITAL
registerAliases({ "setUnitStatus", "SetUnitStatus" }, function(data, cb)
    dprint("NUI SetUnitStatus:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SetUnitStatus", (data and data.status) or "AVAILABLE")
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

-- 911 CALLS
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

registerAliases({ "CallWaypoint", "callWaypoint" }, function(data, cb)
    dprint("NUI CallWaypoint:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:SetCallWaypoint", (data and data.id) or 0)
    cb({ ok = true })
end)

-- LIVE CHAT
-- LIVE CHAT
registerAliases({ "LiveChatSend", "liveChatSend" }, function(data, cb)
    dprint("NUI LiveChatSend:", jsonEncode(data or {}))
    TriggerServerEvent("az_mdt:LiveChatSend", data or {})
    cb({ ok = true })
end)

-- Request chat history from server
registerAliases({ "RequestChatHistory", "requestChatHistory", "GetChatHistory" }, function(_, cb)
    dprint("NUI RequestChatHistory")
    TriggerServerEvent("az_mdt:RequestChatHistory")
    cb({ ok = true })
end)


-- ADMIN ACTIONS
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

-------------------------------------------------
-- SERVER → NUI
-------------------------------------------------

-- Name results
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

-- Plate results
RegisterNetEvent("az_mdt:client:plateResults", function(payload)
    payload = payload or {}
    dprint("PlateResults vehicles:", tostring(payload.vehicles and #payload.vehicles or 0),
           "records:", tostring(payload.records and #payload.records or 0))

    SendNUIMessage({
        action = "plateResults",
        data   = jsonEncode(payload)
    })
end)

-- Weapon results
RegisterNetEvent("az_mdt:client:weaponResults", function(payload)
    payload = payload or {}
    dprint("WeaponResults (stub)")

    SendNUIMessage({
        action = "weaponResults",
        data   = jsonEncode(payload)
    })
end)

-- BOLOs
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

-- Panic broadcast
RegisterNetEvent("az_mdt:client:panic", function(payload)
    payload = payload or {}
    dprint("Panic payload from server")
    SendNUIMessage({
        action = "panic",
        data   = jsonEncode(payload)
    })
end)

-- Reports
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

-- Employees
RegisterNetEvent("az_mdt:client:employees", function(list)
    list = list or {}
    dprint("Employees count:", #list)

    SendNUIMessage({
        action = "employeesList",
        data   = jsonEncode(list)
    })
end)

-- Units snapshot
RegisterNetEvent("az_mdt:client:unitsSnapshot", function(payload)
    payload = payload or {}
    unitsCache = payload.units or {}

    SendNUIMessage({
        action = "unitsUpdate",
        data   = jsonEncode(unitsCache)
    })
end)

-- 911 calls
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

-- Call waypoint
RegisterNetEvent("az_mdt:client:setWaypoint", function(coords)
    if not coords or not coords.x or not coords.y then return end
    SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
end)

-- Live chat
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

-- Status
RegisterNetEvent("az_mdt:client:statusUpdate", function(status)
    SendNUIMessage({
        action = "statusUpdate",
        status = status or "AVAILABLE"
    })
end)

-- Warrants
RegisterNetEvent("az_mdt:client:warrantsList", function(list)
    list = list or {}
    dprint("WarrantsList count:", #list)

    SendNUIMessage({
        action = "warrantsList",
        data   = jsonEncode(list)
    })
end)

-- IA / Action log
RegisterNetEvent("az_mdt:client:actionLog", function(list)
    list = list or {}
    dprint("ActionLog count:", #list)

    SendNUIMessage({
        action = "actionLog",
        data   = jsonEncode(list)
    })
end)

-------------------------------------------------
-- /911 CLIENT COMMAND
-------------------------------------------------

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
