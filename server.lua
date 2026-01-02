local RESOURCE_NAME = GetCurrentResourceName()
local fw            = exports['Az-Framework']

Config = Config or {}
if Config.Debug == nil then Config.Debug = true end

-------------------------------------------------
-- DEBUG
-------------------------------------------------
local function dprint(...)
    if not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(("^3[%s S]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

-------------------------------------------------
-- DB DRIVER WRAPPER (oxmysql OR mysql-async)
-------------------------------------------------
local DB = {}

local hasOx = GetResourceState("oxmysql") == "started"
if hasOx then
    dprint("Using oxmysql for database access.")
else
    dprint("oxmysql not detected; falling back to MySQL.Async (if available).")
end

function DB.fetchAll(query, params, cb)
    params = params or {}
    if hasOx and exports.oxmysql and exports.oxmysql.execute then
        exports.oxmysql:execute(query, params, function(result)
            cb(result or {})
        end)
    elseif MySQL and MySQL.Async and MySQL.Async.fetchAll then
        MySQL.Async.fetchAll(query, params, cb)
    else
        dprint("DB.fetchAll: NO DB DRIVER AVAILABLE!")
        cb({})
    end
end

function DB.insert(query, params, cb)
    params = params or {}
    cb = cb or function() end
    if hasOx and exports.oxmysql and exports.oxmysql.insert then
        exports.oxmysql:insert(query, params, function(id)
            cb(id or 0)
        end)
    elseif MySQL and MySQL.Async and MySQL.Async.insert then
        MySQL.Async.insert(query, params, cb)
    else
        dprint("DB.insert: NO DB DRIVER AVAILABLE!")
        cb(0)
    end
end

function DB.execute(query, params, cb)
    params = params or {}
    cb = cb or function() end
    if hasOx and exports.oxmysql and exports.oxmysql.update then
        exports.oxmysql:update(query, params, function(affected)
            cb(affected or 0)
        end)
    elseif MySQL and MySQL.Async and MySQL.Async.execute then
        MySQL.Async.execute(query, params, function(affected)
            cb(affected or 0)
        end)
    else
        dprint("DB.execute: NO DB DRIVER AVAILABLE!")
        cb(0)
    end
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function trim(s)
    if not s then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(s)
    return string.lower(s or "")
end

local function jsonDecode(s)
    if not s or s == "" then return nil end
    local ok, result = pcall(function() return json.decode(s) end)
    if ok then return result end
    return nil
end

local function jsonEncode(tbl)
    local ok, result = pcall(function() return json.encode(tbl or {}) end)
    if ok then return result end
    return "[]"
end

local function buildPlaceholders(count)
    if count <= 0 then return "NULL" end
    local t = {}
    for i = 1, count do t[i] = "?" end
    return table.concat(t, ",")
end

-------------------------------------------------
-- PLAYER / FRAMEWORK HELPERS
-------------------------------------------------

local function getDiscordId(src)
    local id = fw:getDiscordID(src)
    if id and id ~= "" then return id end

    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1, 8) == "discord:" then
            return identifier:sub(9)
        end
    end
    return nil
end

local function getCharacter(src)
    local charId = fw:GetPlayerCharacter(src)
    if not charId then return nil end

    local discordId = getDiscordId(src)
    if not discordId then return nil end

    return {
        discordid = tostring(discordId),
        charid    = tostring(charId)
    }
end

local function loadOfficerContext(src, cb)
    local ident = getCharacter(src)
    if not ident then
        dprint("loadOfficerContext: missing ident for", src)
        cb(nil)
        return
    end

    DB.fetchAll([[
        SELECT name, active_department, charid, discordid, license_status
        FROM user_characters
        WHERE discordid = ? AND charid = ?
        LIMIT 1
    ]], { ident.discordid, ident.charid }, function(rows)
        local row = rows[1]
        if not row then
            dprint("loadOfficerContext: no user_characters row for", ident.discordid, ident.charid)
            cb(nil)
            return
        end

        DB.fetchAll([[
            SELECT paycheck, department
            FROM econ_departments
            WHERE discordid = ? AND charid = ? AND department = ?
            LIMIT 1
        ]], { ident.discordid, ident.charid, row.active_department }, function(jobRows)
            local job   = jobRows[1]
            local grade = job and job.paycheck or 0

            local fakeCallsign = ("U-%s"):format(tostring(row.charid or "0"):sub(-3))

            cb({
                name          = row.name,
                department    = row.active_department,
                grade         = grade,
                callsign      = fakeCallsign,
                licenseStatus = row.license_status,
                discordid     = row.discordid,
                charid        = row.charid
            })
        end)
    end)
end

local function loadCharacterWithMugshot(discordId, charId, cb)
    DB.fetchAll([[
        SELECT uc.id, uc.name, uc.charid, uc.discordid, uc.active_department, uc.license_status,
               ic.mugshot
        FROM user_characters uc
        LEFT JOIN az_id_cards ic
          ON ic.char_id   = uc.charid
         AND ic.discord_id = uc.discordid
        WHERE uc.discordid = ? AND uc.charid = ?
        LIMIT 1
    ]], { discordId, charId }, function(rows)
        cb(rows[1])
    end)
end

-------------------------------------------------
-- INTERNAL AFFAIRS / LAST SEEN HELPERS
-------------------------------------------------

local function logAction(src, action, target, meta)
    local officerName    = GetPlayerName(src) or ("src " .. tostring(src))
    local officerDiscord = getDiscordId(src) or ""

    local metaJson
    if type(meta) == "table" then
        metaJson = jsonEncode(meta)
    elseif type(meta) == "string" and meta ~= "" then
        metaJson = jsonEncode({ text = meta })
    else
        metaJson = jsonEncode({})
    end

    DB.insert([[
        INSERT INTO mdt_action_log (officer_name, officer_discord, action, target, meta)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        officerName,
        officerDiscord,
        action or "unknown",
        target or "",
        metaJson
    })
end

local function updateLastSeen(charid)
    charid = tostring(charid or "")
    if charid == "" then return end

    DB.execute([[
        INSERT INTO mdt_last_seen (charid) VALUES (?)
        ON DUPLICATE KEY UPDATE last_seen = CURRENT_TIMESTAMP
    ]], { charid })
end

-------------------------------------------------
-- UNITS / CALLS STATE
-------------------------------------------------

local Units    = {}  -- [src] = { id, name, department, callsign, status }
local UnitMeta = {}  -- [src] = officer context

local Calls       = {}  -- [id] = call table
local NextCallId  = 1

local function broadcastUnits()
    local arr = {}
    for _, u in pairs(Units) do
        arr[#arr + 1] = u
    end

    TriggerClientEvent("az_mdt:client:unitsSnapshot", -1, {
        units = arr
    })
end

local function setUnitStatus(src, status, ctx)
    status = tostring(status or "AVAILABLE")
    ctx    = ctx or UnitMeta[src] or {}

    local unit = {
        id         = src,
        name       = ctx.name or ("Unit " .. tostring(src)),
        department = ctx.department or "police",
        callsign   = ctx.callsign or "",
        status     = status
    }

    Units[src]    = unit
    UnitMeta[src] = ctx ~= nil and ctx or UnitMeta[src]

    broadcastUnits()
    TriggerClientEvent("az_mdt:client:statusUpdate", src, status)
end

local function snapshotCalls()
    local arr = {}
    for _, c in pairs(Calls) do
        arr[#arr + 1] = c
    end
    table.sort(arr, function(a, b) return (a.id or 0) > (b.id or 0) end)
    return arr
end

local function broadcastCalls()
    TriggerClientEvent("az_mdt:client:callsSnapshot", -1, snapshotCalls())
end

-------------------------------------------------
-- MDT OPEN
-------------------------------------------------

RegisterCommand("mdt", function(src)
    if src == 0 then
        print("mdt command is player only")
        return
    end

    loadOfficerContext(src, function(ctx)
        if not ctx then
            TriggerClientEvent("az_mdt:client:notify", src, {
                type = "error",
                message = "Unable to load your officer profile."
            })
            return
        end

        dprint(("Opening MDT for %s (%d) dept=%s grade=%s"):format(
            ctx.name or "UNKNOWN",
            src,
            ctx.department or "NONE",
            tostring(ctx.grade or 0)
        ))

        UnitMeta[src] = ctx
        setUnitStatus(src, "AVAILABLE", ctx)

        if ctx.charid then
            updateLastSeen(ctx.charid)
        end

        TriggerClientEvent("az_mdt:client:open", src, ctx)
        TriggerClientEvent("az_mdt:client:callsSnapshot", src, snapshotCalls())
        broadcastUnits()
    end)
end, false)

-------------------------------------------------
-- NAME SEARCH
-------------------------------------------------

RegisterNetEvent("az_mdt:NameSearch", function(data)
    local src  = source
    data       = data or {}

    local first = trim(data.first or "")
    local last  = trim(data.last or "")
    local term  = trim(data.term or (first .. " " .. last))

    if term == "" then
        dprint(("NameSearch from %d with empty query – returning none."):format(src))
        TriggerClientEvent("az_mdt:client:nameResults", src, {
            term      = "",
            citizens  = {},
            records   = {}
        })
        return
    end

    local likeTerm = "%" .. lower(term) .. "%"

    dprint(("NameSearch from %d term='%s'"):format(src, term))

    -- 1) MAIN CHARACTER ROWS + FLAGS + LAST SEEN + MUGSHOT
    DB.fetchAll([[
        SELECT
            uc.id,
            uc.name,
            uc.charid,
            uc.discordid,
            uc.active_department,
            uc.license_status,
            ls.last_seen,
            f.flags_json,
            ic.mugshot
        FROM user_characters uc
        LEFT JOIN mdt_last_seen ls
               ON ls.charid = uc.charid
        LEFT JOIN mdt_identity_flags f
               ON f.target_type = 'name'
              AND f.target_value = uc.name
        LEFT JOIN az_id_cards ic
               ON ic.char_id   = uc.charid
              AND ic.discord_id = uc.discordid
        WHERE LOWER(uc.name) LIKE ?
        ORDER BY uc.name ASC
        LIMIT 50
    ]], { likeTerm }, function(citizenRows)

        citizenRows = citizenRows or {}

        for _, row in ipairs(citizenRows) do
            local flags = jsonDecode(row.flags_json or "")
            row.flags = { flags = flags or {} }
            row.flags_json = nil
        end

        -- 2) QUICK NOTES FOR THOSE NAMES
        DB.fetchAll([[
            SELECT target_value, note, created_at
            FROM mdt_quick_notes
            WHERE target_type = 'name'
              AND LOWER(target_value) LIKE ?
            ORDER BY created_at DESC
        ]], { likeTerm }, function(noteRows)

            noteRows = noteRows or {}
            local notesByName = {}

            for _, n in ipairs(noteRows) do
                local key = lower(n.target_value or "")
                if key ~= "" then
                    notesByName[key] = notesByName[key] or {}
                    if #notesByName[key] < 5 then
                        table.insert(notesByName[key], {
                            note       = n.note,
                            created_at = n.created_at
                        })
                    end
                end
            end

            -- 3) GENERIC RECORDS (mdt_id_records) FOR NAMES
            DB.fetchAll([[
                SELECT id, target_type, target_value, rtype, title, description, timestamp
                FROM mdt_id_records
                WHERE target_type = 'name'
                  AND LOWER(target_value) LIKE ?
                ORDER BY timestamp DESC
                LIMIT 100
            ]], { likeTerm }, function(recordRows)

                recordRows = recordRows or {}

                for _, c in ipairs(citizenRows) do
                    local key = lower(c.name or "")
                    c.quick_notes = notesByName[key] or {}
                end

                dprint(("NameSearch %d results: %d citizens, %d records"):format(
                    src, #citizenRows, #recordRows
                ))

                TriggerClientEvent("az_mdt:client:nameResults", src, {
                    term      = term,
                    citizens  = citizenRows,
                    records   = recordRows
                })
            end)
        end)
    end)
end)

-------------------------------------------------
-- PUBLIC LAST-SEEN EVENT (OPTIONAL FOR OTHER RESOURCES)
-------------------------------------------------

RegisterNetEvent("az_mdt:UpdateLastSeen", function(charid)
    local src = source
    if not charid then
        local ident = getCharacter(src)
        if not ident or not ident.charid then return end
        charid = ident.charid
    end
    updateLastSeen(charid)
end)

-------------------------------------------------
-- PLATE / VEHICLE SEARCH
-------------------------------------------------

RegisterNetEvent("az_mdt:PlateSearch", function(data)
    local src = source
    data = data or {}

    local plate = trim(data.plate or data.Plate or data.term)
    if plate == "" then
        dprint(("PlateSearch from %d with empty query – returning none."):format(src))
        TriggerClientEvent("az_mdt:client:plateResults", src, {
            term     = "",
            vehicles = {},
            records  = {}
        })
        return
    end

    local term = "%" .. lower(plate) .. "%"

    dprint(("PlateSearch from %d term='%s'"):format(src, plate))

    DB.fetchAll([[
        SELECT
            uv.id,
            uv.discordid,
            uv.plate,
            uv.model,
            uvi.policy_type,
            uvi.premium,
            uvi.deductible,
            uvi.active,
            uvi.vehicle_props
        FROM user_vehicles uv
        LEFT JOIN user_vehicle_insurance uvi
          ON uvi.discordid = uv.discordid
         AND uvi.plate     = uv.plate
        WHERE LOWER(uv.plate) LIKE ?
        ORDER BY uv.plate ASC
        LIMIT 50
    ]], { term }, function(vehicleRows)
        for _, row in ipairs(vehicleRows) do
            if row.vehicle_props then
                local props = jsonDecode(row.vehicle_props)
                if props and props.ownerName then
                    row.owner_name = props.ownerName
                end
                row.vehicle_props = nil
            end
        end

        DB.fetchAll([[
            SELECT id, target_type, target_value, rtype, title, description, timestamp
            FROM mdt_id_records
            WHERE target_type = 'plate'
              AND LOWER(target_value) LIKE ?
            ORDER BY timestamp DESC
            LIMIT 100
        ]], { term }, function(recordRows)
            dprint(("PlateSearch %d results: %d vehicles, %d records"):format(
                src, #vehicleRows, #recordRows
            ))

            TriggerClientEvent("az_mdt:client:plateResults", src, {
                term     = plate,
                vehicles = vehicleRows,
                records  = recordRows
            })
        end)
    end)
end)

-------------------------------------------------
-- WEAPON SEARCH (stub – returns empty)
-------------------------------------------------

RegisterNetEvent("az_mdt:WeaponSearch", function(data)
    local src = source
    data = data or {}
    local serial = trim(data.serial or data.weapon or data.term)

    if serial == "" then
        dprint(("WeaponSearch from %d with empty query – returning none."):format(src))
        TriggerClientEvent("az_mdt:client:weaponResults", src, {
            term    = "",
            weapons = {},
            records = {}
        })
        return
    end

    dprint(("WeaponSearch from %d serial='%s' (stub, no DB query)"):format(src, serial))

    TriggerClientEvent("az_mdt:client:weaponResults", src, {
        term    = serial,
        weapons = {},
        records = {}
    })
end)

-------------------------------------------------
-- BOLOS
-------------------------------------------------

RegisterNetEvent("az_mdt:RequestBolos", function()
    local src = source
    dprint("RequestBolos from", src)

    DB.fetchAll([[
        SELECT id, type, data, created_at
        FROM mdt_bolos
        ORDER BY id DESC
        LIMIT 100
    ]], {}, function(rows)
        for _, row in ipairs(rows) do
            row.body = jsonDecode(row.data) or {}
            row.data = nil
        end

        TriggerClientEvent("az_mdt:client:boloList", src, rows)
    end)
end)

RegisterNetEvent("az_mdt:CreateBolo", function(payload)
    local src = source
    payload = payload or {}

    local boloType = trim(payload.type or payload.boloType or "vehicle")
    local body = {
        title   = trim(payload.title or ""),
        type    = boloType,
        details = trim(payload.details or "")
    }

    local encoded = jsonEncode(body)

    dprint(("CreateBolo from %d type=%s title=%s"):format(
        src, boloType, tostring(body.title or "n/a")
    ))

    DB.insert([[
        INSERT INTO mdt_bolos (type, data)
        VALUES (?, ?)
    ]], { boloType, encoded }, function(insertId)
        DB.fetchAll("SELECT id, type, data, created_at FROM mdt_bolos WHERE id = ?", { insertId }, function(rows)
            local row = rows[1]
            if not row then return end
            row.body = jsonDecode(row.data) or {}
            row.data = nil

            TriggerClientEvent("az_mdt:client:boloCreated", -1, row)

            logAction(src, "bolo_create", ("BOLO #" .. tostring(insertId)), {
                type  = boloType,
                title = body.title or ""
            })
        end)
    end)
end)

-------------------------------------------------
-- REPORTS + MDT_ID_RECORDS MIRROR
-------------------------------------------------

RegisterNetEvent("az_mdt:RequestReports", function()
    local src = source
    dprint("RequestReports from", src)

    DB.fetchAll([[
        SELECT id, type, data, created_at
        FROM mdt_reports
        ORDER BY id DESC
        LIMIT 100
    ]], {}, function(rows)
        for _, row in ipairs(rows) do
            row.body = jsonDecode(row.data) or {}
            row.data = nil
        end

        TriggerClientEvent("az_mdt:client:reportList", src, rows)
    end)
end)

RegisterNetEvent("az_mdt:CreateReport", function(payload)
    local src = source
    payload = payload or {}

    local rType = trim(payload.type or payload.reportType or "incident")

    local officerCtx = UnitMeta[src] or {}
    local body = {
        title   = trim(payload.title or ""),
        type    = rType,
        info    = trim(payload.info or payload.body or ""),
        officer = officerCtx.name or ("Unit " .. src)
    }

    local targetType  = trim(payload.targetType or payload.target_type or "")
    local targetValue = trim(payload.targetValue or payload.target_value or "")

    local encoded = jsonEncode(body)

    dprint(("CreateReport from %d type=%s title=%s targetType=%s targetValue=%s"):format(
        src, rType, tostring(body.title or "n/a"), targetType ~= "" and targetType or "none", targetValue ~= "" and targetValue or "none"
    ))

    DB.insert([[
        INSERT INTO mdt_reports (type, data)
        VALUES (?, ?)
    ]], { rType, encoded }, function(insertId)
        DB.fetchAll("SELECT id, type, data, created_at FROM mdt_reports WHERE id = ?", { insertId }, function(rows)
            local row = rows[1]
            if not row then return end
            row.body = jsonDecode(row.data) or {}
            row.data = nil

            TriggerClientEvent("az_mdt:client:reportCreated", -1, row)

            logAction(src, "report_create", ("Report #" .. tostring(insertId)), {
                type        = rType,
                title       = body.title or "",
                targetType  = targetType,
                targetValue = targetValue
            })
        end)
    end)

    if targetType ~= "" and targetValue ~= "" then
        DB.insert([[
            INSERT INTO mdt_id_records (target_type, target_value, rtype, title, description)
            VALUES (?, ?, ?, ?, ?)
        ]], {
            targetType,
            targetValue,
            rType,
            body.title or "",
            body.info or ""
        })
    end
end)

-------------------------------------------------
-- QUICK NOTES (CITIZENS / VEHICLES)
-------------------------------------------------

RegisterNetEvent("az_mdt:CreateQuickNote", function(payload)
    local src = source
    payload = payload or {}

    local targetType  = trim(payload.targetType or payload.target_type or "name")
    local targetValue = trim(payload.targetValue or payload.target_value or "")
    local note        = trim(payload.note or payload.text or "")

    if targetValue == "" or note == "" then return end

    local officerName    = GetPlayerName(src) or ("src " .. tostring(src))
    local officerDiscord = getDiscordId(src) or ""

    dprint(("CreateQuickNote from %d target=%s:%s note=%s"):format(
        src, targetType, targetValue, note
    ))

    DB.insert([[
        INSERT INTO mdt_quick_notes (target_type, target_value, note, creator_name, creator_discord)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        targetType,
        targetValue,
        note,
        officerName,
        officerDiscord
    }, function(insertId)
        logAction(src, "quick_note_create", targetType .. ":" .. targetValue, {
            id   = insertId,
            note = note
        })

        TriggerClientEvent("az_mdt:client:notify", src, {
            type    = "success",
            message = ("Quick note saved for %s."):format(targetValue)
        })
    end)
end)

-------------------------------------------------
-- IDENTITY FLAGS (OFFICER SAFETY / ARMED / GANG / MENTAL HEALTH)
-------------------------------------------------

local VALID_FLAGS = {
    officer_safety = true,
    armed          = true,
    gang           = true,
    mental_health  = true
}

RegisterNetEvent("az_mdt:SetIdentityFlags", function(payload)
    local src = source
    payload = payload or {}

    local targetType  = trim(payload.targetType or payload.target_type or "name")
    local targetValue = trim(payload.targetValue or payload.target_value or "")
    local flags       = payload.flags

    if targetValue == "" or type(flags) ~= "table" then return end

    local cleaned = {}
    for k, v in pairs(flags) do
        if VALID_FLAGS[k] and v then
            cleaned[k] = true
        end
    end

    local encoded     = jsonEncode(cleaned)
    local officerName = GetPlayerName(src) or ("src " .. tostring(src))

    dprint(("SetIdentityFlags from %d target=%s:%s flags=%s"):format(
        src, targetType, targetValue, encoded
    ))

    DB.execute([[
        INSERT INTO mdt_identity_flags (target_type, target_value, flags_json, notes, updated_by)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            flags_json = VALUES(flags_json),
            notes      = VALUES(notes),
            updated_by = VALUES(updated_by),
            updated_at = CURRENT_TIMESTAMP
    ]], {
        targetType,
        targetValue,
        encoded,
        trim(payload.notes or ""),
        officerName
    }, function()
        logAction(src, "identity_flags_update", targetType .. ":" .. targetValue, cleaned)

        TriggerClientEvent("az_mdt:client:notify", src, {
            type    = "success",
            message = ("Flags updated for %s."):format(targetValue)
        })
    end)
end)

-------------------------------------------------
-- WARRANTS
-------------------------------------------------

RegisterNetEvent("az_mdt:CreateWarrant", function(payload)
    local src = source
    payload = payload or {}

    local targetName   = trim(payload.targetName or payload.name or "")
    local targetCharid = trim(payload.charid or payload.targetCharid or "")
    local reason       = trim(payload.reason or "")

    if targetName == "" or reason == "" then return end

    local officerName    = GetPlayerName(src) or ("src " .. tostring(src))
    local officerDiscord = getDiscordId(src) or ""

    dprint(("CreateWarrant from %d name=%s charid=%s reason=%s"):format(
        src, targetName, targetCharid, reason
    ))

    DB.insert([[
        INSERT INTO mdt_warrants (target_name, target_charid, reason, status, created_by, created_discord)
        VALUES (?, ?, ?, 'active', ?, ?)
    ]], {
        targetName,
        targetCharid ~= "" and targetCharid or nil,
        reason,
        officerName,
        officerDiscord
    }, function(insertId)
        logAction(src, "warrant_create", targetName, {
            id      = insertId,
            charid  = targetCharid,
            reason  = reason
        })

        TriggerClientEvent("az_mdt:client:notify", src, {
            type    = "success",
            message = ("Warrant created for %s."):format(targetName)
        })
    end)
end)

RegisterNetEvent("az_mdt:RequestWarrants", function()
    local src = source

    DB.fetchAll([[
        SELECT id, target_name, target_charid, reason, status,
               created_by, created_discord, created_at
        FROM mdt_warrants
        ORDER BY id DESC
        LIMIT 200
    ]], {}, function(rows)
        TriggerClientEvent("az_mdt:client:warrantsList", src, rows or {})
    end)
end)

-------------------------------------------------
-- INTERNAL AFFAIRS / ACTION LOG
-------------------------------------------------

RegisterNetEvent("az_mdt:RequestActionLog", function()
    local src = source

    DB.fetchAll([[
        SELECT id, officer_name, officer_discord, action, target, meta, created_at
        FROM mdt_action_log
        ORDER BY id DESC
        LIMIT 200
    ]], {}, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            row.meta = jsonDecode(row.meta) or {}
        end
        TriggerClientEvent("az_mdt:client:actionLog", src, rows)
    end)
end)

-------------------------------------------------
-- EMPLOYEES
-------------------------------------------------

RegisterNetEvent("az_mdt:ViewEmployees", function()
    local src = source

    loadOfficerContext(src, function(ctx)
        if not ctx then
            TriggerClientEvent("az_mdt:client:employees", src, {})
            return
        end

        dprint(("ViewEmployees from %d dept=%s"):format(src, ctx.department or "NONE"))

        DB.fetchAll([[
            SELECT uc.id, uc.name, uc.charid, uc.discordid, uc.active_department,
                   ed.paycheck
            FROM user_characters uc
            LEFT JOIN econ_departments ed
              ON ed.discordid = uc.discordid
             AND ed.charid    = uc.charid
             AND ed.department = uc.active_department
            WHERE uc.active_department = ?
            ORDER BY uc.name ASC
        ]], { ctx.department }, function(rows)
            for _, row in ipairs(rows) do
                row.callsign = row.callsign or ("U-" .. tostring(row.charid or "0"):sub(-3))
            end

            TriggerClientEvent("az_mdt:client:employees", src, rows)
        end)
    end)
end)

-------------------------------------------------
-- UNITS / STATUS / PANIC / HOSPITAL
-------------------------------------------------

RegisterNetEvent("az_mdt:SetUnitStatus", function(status)
    local src = source
    status = tostring(status or "AVAILABLE")
    dprint(("UnitStatus %d -> %s"):format(src, status))

    setUnitStatus(src, status, UnitMeta[src])
    TriggerClientEvent("az_mdt:client:unitStatus", -1, src, status)
end)

RegisterNetEvent("az_mdt:Panic", function()
    local src = source
    dprint("Panic button from", src)

    local ctx = UnitMeta[src] or {}
    local officerName = ctx.name or ("Unit " .. src)

    setUnitStatus(src, "PANIC", ctx)

    local payload = {
        source   = src,
        officer  = officerName,
        callsign = ctx.callsign or "",
        time     = os.date("%H:%M:%S")
    }

    TriggerClientEvent("az_mdt:client:panic", -1, payload)

    TriggerClientEvent("az_mdt:client:notify", -1, {
        type    = "panic",
        message = ("PANIC BUTTON – %s"):format(officerName)
    })

    logAction(src, "panic_button", officerName, {})
end)

RegisterNetEvent("az_mdt:Hospital", function()
    local src = source
    dprint("Hospital button from", src)
    TriggerClientEvent("az_mdt:client:hospital", -1, src)
end)

RegisterNetEvent("az_mdt:RequestUnits", function()
    local src = source
    local arr = {}
    for _, u in pairs(Units) do
        arr[#arr + 1] = u
    end

    TriggerClientEvent("az_mdt:client:unitsSnapshot", src, {
        units = arr
    })
end)

AddEventHandler("playerDropped", function()
    local src = source
    Units[src]    = nil
    UnitMeta[src] = nil
    broadcastUnits()
end)

-------------------------------------------------
-- 911 CALLS
-------------------------------------------------

RegisterNetEvent("az_mdt:Create911", function(payload)
    local src = source
    payload = payload or {}

    local callerName = GetPlayerName(src)
    local message    = trim(payload.message or "")
    local location   = trim(payload.location or "Unknown location")
    local coords     = payload.coords or {}

    if message == "" then return end

    local id = NextCallId
    NextCallId = NextCallId + 1

    local call = {
        id         = id,
        caller     = callerName,
        message    = message,
        location   = location,
        coords     = coords,
        units      = {},
        status     = "PENDING",
        created_at = os.date("%H:%M:%S")
    }

    Calls[id] = call

    dprint(("Create911 #%d from %s @ %s: %s"):format(id, callerName, location, message))

    logAction(src, "911_create", ("Call #" .. tostring(id)), {
        location = location,
        message  = message
    })

    TriggerClientEvent("az_mdt:client:callUpdated", -1, call)
end)

RegisterNetEvent("az_mdt:RequestCalls", function()
    local src = source
    TriggerClientEvent("az_mdt:client:callsSnapshot", src, snapshotCalls())
end)

RegisterNetEvent("az_mdt:AttachToCall", function(callId)
    local src = source
    callId = tonumber(callId) or 0
    local call = Calls[callId]
    if not call then return end

    local ctx = UnitMeta[src] or { name = ("Unit " .. src), callsign = "" }
    local found = false

    for _, u in ipairs(call.units) do
        if u.id == src then
            found = true
            break
        end
    end

    if not found then
        table.insert(call.units, {
            id       = src,
            name     = ctx.name,
            callsign = ctx.callsign
        })
    end

    call.status = "ENROUTE"
    dprint(("AttachToCall #%d by %s"):format(callId, ctx.name or src))

    TriggerClientEvent("az_mdt:client:callUpdated", -1, call)
end)

RegisterNetEvent("az_mdt:SetCallWaypoint", function(callId)
    local src = source
    callId = tonumber(callId) or 0
    local call = Calls[callId]
    if not call or not call.coords or not call.coords.x or not call.coords.y then return end

    TriggerClientEvent("az_mdt:client:setWaypoint", src, call.coords)
end)

-------------------------------------------------
-- LIVE CHAT (simple relay)
-------------------------------------------------

-------------------------------------------------
-- LIVE CHAT (persistent via DB)
-------------------------------------------------

local ChatHistory = {}        -- last N messages in memory
local CHAT_MAX    = 100       -- how many messages we keep & send to NUI

local function pushChatMessage(msg, skipDb)
    -- keep in-memory buffer trimmed
    ChatHistory[#ChatHistory + 1] = msg
    if #ChatHistory > CHAT_MAX then
        table.remove(ChatHistory, 1)
    end

    -- optional: persist to DB (skipped when we're loading from DB)
    if not skipDb then
        DB.insert([[
            INSERT INTO mdt_live_chat (sender, source, message, time)
            VALUES (?, ?, ?, ?)
        ]], {
            msg.sender or "",
            msg.source or "",
            msg.message or "",
            msg.time or os.date("%H:%M:%S")
        })
    end
end

local function loadChatHistoryFromDb()
    DB.fetchAll([[
        SELECT sender, source, message, time
        FROM mdt_live_chat
        ORDER BY id DESC
        LIMIT 100
    ]], {}, function(rows)
        rows = rows or {}
        ChatHistory = {}

        -- rows are newest → oldest, we want oldest → newest in ChatHistory
        for i = #rows, 1, -1 do
            local r = rows[i]
            pushChatMessage({
                sender  = r.sender  or "Unknown",
                source  = r.source  or "",
                message = r.message or "",
                time    = r.time    or ""
            }, true) -- true = don't re-insert into DB
        end

        dprint(("LiveChat: loaded %d messages from DB."):format(#ChatHistory))
    end)
end

local function ensureLiveChatTable()
    DB.execute([[
        CREATE TABLE IF NOT EXISTS `mdt_live_chat` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `sender` varchar(128) DEFAULT NULL,
          `source` varchar(64) DEFAULT NULL,
          `message` text DEFAULT NULL,
          `time` varchar(16) DEFAULT NULL,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function()
        dprint("LiveChat: ensured mdt_live_chat table exists.")
    end)
end

RegisterNetEvent("az_mdt:LiveChatSend", function(data)
    local src = source
    data = data or {}

    local ctx = UnitMeta[src] or {}
    local sender = ctx.callsign and (ctx.callsign .. " | " .. (ctx.name or "")) or (ctx.name or ("Unit " .. src))

    local msgText = trim(data.message or "")
    if msgText == "" then return end

    local payload = {
        sender  = sender,
        source  = ctx.callsign or tostring(src),
        message = msgText,
        time    = os.date("%H:%M:%S")
    }

    -- add to in-memory buffer + persist to DB
    pushChatMessage(payload, false)

    -- broadcast to all MDT clients
    TriggerClientEvent("az_mdt:client:liveChatMessage", -1, payload)
end)

RegisterNetEvent("az_mdt:RequestChatHistory", function()
    local src = source
    TriggerClientEvent("az_mdt:client:liveChatHistory", src, ChatHistory)
end)


-------------------------------------------------
-- ADMIN ACTIONS
-------------------------------------------------

RegisterNetEvent("az_mdt:AdminDeleteBolo", function(id)
    local src = source
    id = tonumber(id) or 0
    if id <= 0 then return end

    dprint(("AdminDeleteBolo from %d id=%d"):format(src, id))
    logAction(src, "admin_delete_bolo", tostring(id), {})

    DB.execute("DELETE FROM mdt_bolos WHERE id = ?", { id }, function()
        DB.fetchAll([[
            SELECT id, type, data, created_at
            FROM mdt_bolos
            ORDER BY id DESC
            LIMIT 100
        ]], {}, function(rows)
            for _, row in ipairs(rows) do
                row.body = jsonDecode(row.data) or {}
                row.data = nil
            end
            TriggerClientEvent("az_mdt:client:boloList", -1, rows)
        end)
    end)
end)

RegisterNetEvent("az_mdt:AdminDeleteReport", function(id)
    local src = source
    id = tonumber(id) or 0
    if id <= 0 then return end

    dprint(("AdminDeleteReport from %d id=%d"):format(src, id))
    logAction(src, "admin_delete_report", tostring(id), {})

    DB.execute("DELETE FROM mdt_reports WHERE id = ?", { id }, function()
        DB.fetchAll([[
            SELECT id, type, data, created_at
            FROM mdt_reports
            ORDER BY id DESC
            LIMIT 100
        ]], {}, function(rows)
            for _, row in ipairs(rows) do
                row.body = jsonDecode(row.data) or {}
                row.data = nil
            end
            TriggerClientEvent("az_mdt:client:reportList", -1, rows)
        end)
    end)
end)

RegisterNetEvent("az_mdt:AdminDeleteCall", function(id)
    local src = source
    id = tonumber(id) or 0
    if id <= 0 then return end
    if not Calls[id] then return end

    dprint(("AdminDeleteCall from %d id=%d"):format(src, id))
    logAction(src, "admin_delete_call", tostring(id), {})

    Calls[id] = nil
    broadcastCalls()
end)

RegisterNetEvent("az_mdt:AdminDeleteEmployee", function(payload)
    local src = source
    payload = payload or {}

    local rowId = tonumber(payload.id) or 0
    local dept  = trim(payload.department or "")

    if rowId <= 0 or dept == "" then return end

    dprint(("AdminDeleteEmployee from %d rowId=%d dept=%s"):format(src, rowId, dept))
    logAction(src, "admin_delete_employee", dept .. ":" .. tostring(rowId), {})

    DB.execute("UPDATE user_characters SET active_department = NULL WHERE id = ? AND active_department = ?", { rowId, dept }, function()
        DB.fetchAll([[
            SELECT uc.id, uc.name, uc.charid, uc.discordid, uc.active_department,
                   ed.paycheck
            FROM user_characters uc
            LEFT JOIN econ_departments ed
              ON ed.discordid = uc.discordid
             AND ed.charid    = uc.charid
             AND ed.department = uc.active_department
            WHERE uc.active_department = ?
            ORDER BY uc.name ASC
        ]], { dept }, function(rows)
            for _, row in ipairs(rows) do
                row.callsign = row.callsign or ("U-" .. tostring(row.charid or "0"):sub(-3))
            end
            TriggerClientEvent("az_mdt:client:employees", -1, rows)
        end)
    end)
end)

-------------------------------------------------
-- RESOURCE START
-------------------------------------------------

AddEventHandler("onResourceStart", function(res)
    if res ~= RESOURCE_NAME then return end

    dprint("MySQL ready for " .. RESOURCE_NAME)

    -- Make sure the chat table exists
    ensureLiveChatTable()

    -- Reload last N messages into memory so RequestChatHistory works
    loadChatHistoryFromDb()

    dprint("Schema ensured and live chat history loaded.")
end)
