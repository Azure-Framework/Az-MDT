local RESOURCE_NAME = GetCurrentResourceName()

Config = Config or {}
if Config.Debug == nil then Config.Debug = true end

Config.Tables = Config.Tables or {}
Config.ACEPermissions = Config.ACEPermissions or Config.ACEPERMISSIONS or {
    open = "az_mdt.open",
    admin = "az_mdt.admin"
}
Config.ACEPERMISSIONS = Config.ACEPermissions
if Config.PreferEmployeeAccessOverAce == nil then Config.PreferEmployeeAccessOverAce = true end
Config.DefaultDepartment = Config.DefaultDepartment or "police"
Config.DefaultOfficerGrade = tonumber(Config.DefaultOfficerGrade) or 0
Config.DefaultCallsignPrefix = Config.DefaultCallsignPrefix or "U"
Config.CivCommandName = Config.CivCommandName or "civmdt"
Config.Roles = Config.Roles or {}
Config.Duty = Config.Duty or {}
Config.CivilianDefaults = Config.CivilianDefaults or {}
Config.Postals = Config.Postals or {}
Config.CharacterStateKeys = Config.CharacterStateKeys or {
    'citizenid', 'citizenId', 'charid', 'charId', 'characterid', 'characterId', 'character_id', 'cid'
}

randomLinkCode = randomLinkCode
sourceHasFireDutyState = sourceHasFireDutyState
resolveOpenUnitStatus = resolveOpenUnitStatus
ensureUnitRegisteredForOperationalSource = ensureUnitRegisteredForOperationalSource
resolveFireBridgeResourceName = resolveFireBridgeResourceName
resolveParkRangerBridgeResourceName = resolveParkRangerBridgeResourceName
resolvePoliceBridgeResourceName = resolvePoliceBridgeResourceName
resolveAmbulanceBridgeResourceName = resolveAmbulanceBridgeResourceName
webSqlNow = webSqlNow
getCharacter = getCharacter
webLinkCodeTtl = webLinkCodeTtl
webConfiguredBaseUrl = webConfiguredBaseUrl
ThemeState = ThemeState or nil
webSyncCallStatus = webSyncCallStatus
AccessCache = AccessCache or {}
PendingVehicleRegistration = PendingVehicleRegistration or {}
FireDutyHold = FireDutyHold or {}
FIRE_DUTY_HOLD_SECONDS = FIRE_DUTY_HOLD_SECONDS or 30

function markFireDutyHold(src, active)
    src = tonumber(src) or 0
    if src <= 0 then return end
    if active == true then
        FireDutyHold[src] = os.time() + FIRE_DUTY_HOLD_SECONDS
    else
        FireDutyHold[src] = nil
    end
end

function hasFireDutyHold(src)
    src = tonumber(src) or 0
    if src <= 0 then return false end
    local expires = tonumber(FireDutyHold[src] or 0) or 0
    if expires <= 0 then return false end
    if expires < os.time() then
        FireDutyHold[src] = nil
        return false
    end
    return true
end

function hasAzFramework()
    local state = GetResourceState('Az-Framework')
    return state == 'started' or state == 'starting'
end

function fwExport(name, ...)
    if not hasAzFramework() then return nil end

    local args = { ... }
    local fw = exports['Az-Framework']
    local fn = fw and fw[name]
    if type(fn) ~= 'function' then return nil end

    local ok, a, b, c, d, e = pcall(function()
        return fn(fw, table.unpack(args))
    end)
    if ok then
        return a, b, c, d, e
    end

    ok, a, b, c, d, e = pcall(function()
        return fn(table.unpack(args))
    end)
    if ok then
        return a, b, c, d, e
    end

    return nil
end


function getFrameworkJobName(src)
    if Config.Standalone == false and hasAzFramework() then
        local job = fwExport('getPlayerJob', src)
        if type(job) == 'table' then
            job = job.name or job.job or job.id or job.label
        end
        if job ~= nil then
            return tostring(job)
        end
    end
    return ''
end


local function safeTableName(name, fallback)
    name = tostring(name or fallback or "")
    name = name:gsub("[^%w_]", "")
    if name == "" then return fallback end
    return name
end

local TABLES = {
    citizens  = safeTableName(Config.Tables.citizens, "az_mdt_citizens"),
    vehicles  = safeTableName(Config.Tables.vehicles, "az_mdt_vehicles"),
    weapons   = safeTableName(Config.Tables.weapons, "az_mdt_weapons"),
    employees = safeTableName(Config.Tables.employees, "az_mdt_employees")
}

local function qTable(name)
    return "`" .. TABLES[name] .. "`"
end

function az5pdEnabled()
    return Config.UseAz5PD == true
end

function az5pdTable(name, fallback)
    local tbls = (Config.Az5PD and Config.Az5PD.Tables) or {}
    return safeTableName(tbls[name], fallback)
end

function qAz5pd(name, fallback)
    return "`" .. az5pdTable(name, fallback) .. "`"
end

local function resolveAcePermission(key)
    local perms = Config.ACEPermissions or Config.ACEPERMISSIONS or {}
    return perms[key]
        or perms[string.lower(key)]
        or perms[string.upper(key)]
        or perms[key:sub(1, 1):upper() .. key:sub(2)]
        or ""
end

local function hasAce(src, key)
    local perm = resolveAcePermission(key)
    if perm == "" then return false end
    return IsPlayerAceAllowed(src, perm)
end

local function cachedPerm(src, key)
    local entry = AccessCache[src]
    return entry and entry[key] == true or false
end

local function canUseMDT(src)
    return hasAce(src, 'open') or cachedPerm(src, 'open')
end

local function canUseAdmin(src)
    return hasAce(src, 'admin') or cachedPerm(src, 'admin')
end

local function canUseSupervisor(src)
    return canUseAdmin(src) or hasAce(src, 'supervisor') or cachedPerm(src, 'supervisor')
end

local function canUseDispatch(src)
    return canUseAdmin(src) or hasAce(src, 'dispatch') or cachedPerm(src, 'dispatch')
end

local function canUseOperationalMDT(src)
    return canUseMDT(src) or canUseDispatch(src)
end

local function canManageDispatchConsole(src)
    return canUseSupervisor(src) or canUseDispatch(src)
end

local function canUseCiv(src)
    return hasAce(src, 'civ') or hasAce(src, 'dmv') or cachedPerm(src, 'civ') or canUseMDT(src)
end

local function canUseDMV(src)
    return hasAce(src, 'dmv') or cachedPerm(src, 'dmv') or canUseAdmin(src)
end

local function canUseLeoChat(src)
    return hasAce(src, 'leochat') or cachedPerm(src, 'leochat') or canUseOperationalMDT(src)
end

local function dprint(...)
    if not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(("^3[%s S]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

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

function DB.fetchScalar(query, params, cb)
    params = params or {}
    cb = cb or function() end
    if hasOx and exports.oxmysql and exports.oxmysql.scalar then
        exports.oxmysql:scalar(query, params, function(result)
            cb(result)
        end)
    elseif MySQL and MySQL.Async and MySQL.Async.fetchScalar then
        MySQL.Async.fetchScalar(query, params, function(result)
            cb(result)
        end)
    else
        DB.fetchAll(query, params, function(rows)
            local value = nil
            if type(rows) == 'table' and rows[1] then
                local firstRow = rows[1]
                if type(firstRow) == 'table' then
                    for _, v in pairs(firstRow) do
                        value = v
                        break
                    end
                else
                    value = firstRow
                end
            end
            cb(value)
        end)
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

local function trim(s)
    if s == nil then return "" end
    s = tostring(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(s)
    if s == nil then return "" end
    return string.lower(tostring(s))
end

local function upper(s)
    if s == nil then return "" end
    return string.upper(tostring(s))
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
    local normalized = lower(raw)
    if normalized == 'ems' then return 'EMS' end
    if normalized == 'leo' or normalized == '5pd' then return 'Police' end
    if normalized == 'fire' then return 'Fire' end
    if normalized == 'parkranger' or normalized == 'park_ranger' or normalized == 'park-ranger' or normalized == 'ranger' or normalized == 'parkrangers' then
        return 'Park Ranger'
    end
    local pretty = raw:gsub('[_%-]+', ' ')
    pretty = pretty:gsub('(%a)([%w_]*)', function(first, rest)
        return string.upper(first) .. string.lower(rest or '')
    end)
    return pretty
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

local function roleDefaults(role)
    role = lower(trim(role or ''))
    return {
        open = (role == 'leo' or role == 'supervisor' or role == 'dispatch' or role == 'admin'),
        admin = (role == 'admin'),
        supervisor = (role == 'supervisor' or role == 'dispatch' or role == 'admin'),
        dispatch = (role == 'dispatch' or role == 'admin'),
        civ = (role == 'civ'),
        dmv = (role == 'leo' or role == 'supervisor' or role == 'dispatch' or role == 'admin'),
        leochat = (role == 'leo' or role == 'supervisor' or role == 'dispatch' or role == 'admin')
    }
end

local function rolePageDefaults(role)
    role = lower(trim(role or 'leo'))
    if role == 'admin' then
        return {
            dashboard = true, nameSearch = true, plateSearch = true, weaponSearch = true, bolos = true,
            reports = true, dutyChat = true, callsHub = true, civCenter = true, dmv = true,
            warrants = true, employees = true, themes = true, iaLogs = true
        }
    elseif role == 'dispatch' then
        return {
            dashboard = true, nameSearch = true, plateSearch = true, weaponSearch = true, bolos = true,
            reports = true, dutyChat = true, callsHub = true, civCenter = false, dmv = true,
            warrants = true, employees = true, themes = false, iaLogs = false
        }
    elseif role == 'supervisor' then
        return {
            dashboard = true, nameSearch = true, plateSearch = true, weaponSearch = true, bolos = true,
            reports = true, dutyChat = true, callsHub = true, civCenter = true, dmv = true,
            warrants = true, employees = true, themes = false, iaLogs = false
        }
    elseif role == 'civ' then
        return {
            dashboard = true, nameSearch = false, plateSearch = false, weaponSearch = false, bolos = false,
            reports = true, dutyChat = false, callsHub = false, civCenter = true, dmv = true,
            warrants = false, employees = false, themes = false, iaLogs = false
        }
    end
    return {
        dashboard = true, nameSearch = true, plateSearch = true, weaponSearch = true, bolos = true,
        reports = true, dutyChat = true, callsHub = true, civCenter = true, dmv = true,
        warrants = true, employees = true, themes = false, iaLogs = false
    }
end

local function roleActionDefaults(role)
    role = lower(trim(role or 'leo'))
    local admin = role == 'admin'
    local dispatch = role == 'dispatch'
    local supervisor = role == 'supervisor'
    local civ = role == 'civ'
    local leo = role == 'leo'
    return {
        lookupName = admin or dispatch or supervisor or leo,
        lookupPlate = admin or dispatch or supervisor or leo,
        lookupWeapon = admin or dispatch or supervisor or leo,
        createBolo = admin or dispatch or supervisor or leo,
        deleteBolo = admin or dispatch or supervisor,
        createReport = admin or dispatch or supervisor or leo or civ,
        deleteReport = admin,
        createWarrant = admin or dispatch or supervisor or leo,
        deleteWarrant = admin or dispatch or supervisor,
        attachCalls = admin or dispatch or supervisor or leo,
        detachCalls = admin or dispatch or supervisor or leo,
        waypointCalls = admin or dispatch or supervisor or leo,
        clearCalls = admin or dispatch or supervisor,
        statusCheck = admin or dispatch or supervisor,
        updateUnitStatus = admin or dispatch or supervisor,
        editDmv = admin or dispatch or supervisor or leo or civ,
        quickNotes = admin or dispatch or supervisor or leo,
        flags = admin or dispatch or supervisor or leo,
        saveProfile = admin or dispatch or supervisor or leo,
        registerVehicle = admin or civ or leo,
        registerWeapon = admin or civ or leo,
        deleteCivilianAssets = admin or dispatch or supervisor or leo or civ,
        editEmployeeAccess = admin,
        deleteEmployee = admin,
        viewActionLog = admin,
        sendLeoChat = admin or dispatch or supervisor or leo
    }
end

local function boolish(value)
    if value == true or value == 1 then return true end
    if value == false or value == nil or value == 0 then return false end
    local s = lower(trim(tostring(value)))
    return s == '1' or s == 'true' or s == 'yes' or s == 'on'
end

local function decodePermissionMap(value)
    if type(value) == 'string' then
        value = jsonDecode(value) or {}
    end
    if type(value) ~= 'table' then
        return {}
    end
    return value
end

local function normalizeBooleanMap(input, defaults)
    local out = {}
    input = decodePermissionMap(input)
    defaults = defaults or {}
    for key, value in pairs(defaults) do
        out[key] = value and true or false
    end
    for key, value in pairs(input) do
        if defaults[key] ~= nil then
            out[key] = boolish(value)
        end
    end
    return out
end

local function finalizeAccessIdentity(access, fallbackRole)
    access = access or {}
    local role = lower(trim(access.role or fallbackRole or ''))
    local loginRole = lower(trim(access.loginRole or ''))

    if access.admin then
        role = 'admin'
        loginRole = 'leo'
    elseif access.dispatch then
        if role == '' or role == 'none' or role == 'leo' then role = 'dispatch' end
        if loginRole == '' or loginRole == 'none' then loginRole = 'dispatch' end
    elseif access.supervisor then
        if role == '' or role == 'none' then role = 'supervisor' end
        if loginRole == '' or loginRole == 'none' then loginRole = 'leo' end
    elseif access.civ and not access.open then
        if role == '' or role == 'none' then role = 'civ' end
        if loginRole == '' or loginRole == 'none' then loginRole = 'civ' end
    elseif access.open or access.dmv or access.leochat then
        if role == '' or role == 'none' then role = 'leo' end
        if loginRole == '' or loginRole == 'none' then loginRole = 'leo' end
    end

    if role == '' or role == 'none' then role = lower(trim(fallbackRole or 'leo')) end
    if loginRole ~= 'dispatch' and loginRole ~= 'civ' and loginRole ~= 'leo' then
        loginRole = role == 'dispatch' and 'dispatch' or (role == 'civ' and 'civ' or 'leo')
    end

    access.role = role
    access.loginRole = loginRole
    access.pages = normalizeBooleanMap(access.pages, rolePageDefaults(role))
    access.actions = normalizeBooleanMap(access.actions, roleActionDefaults(role))
    return access
end

local function employeePermPayloadFromAccess(access, fallbackRole)
    access = finalizeAccessIdentity(access or {}, fallbackRole)
    return {
        role = access.role,
        loginRole = access.loginRole,
        open = access.open and true or false,
        admin = access.admin and true or false,
        supervisor = access.supervisor and true or false,
        dispatch = access.dispatch and true or false,
        civ = access.civ and true or false,
        dmv = access.dmv and true or false,
        leochat = access.leochat and true or false,
        pages = access.pages or rolePageDefaults(access.role),
        actions = access.actions or roleActionDefaults(access.role)
    }
end

local function normalizeEmployeeAccessRow(row)
    row = row or {}
    local role = lower(trim(row.mdt_role or row.role or ''))
    if role == '' then role = 'leo' end

    local perms = row.mdt_perms_json or row.perms or {}
    if type(perms) == 'string' then
        perms = jsonDecode(perms) or {}
    end
    if type(perms) ~= 'table' then
        perms = {}
    end

    local access = roleDefaults(role)
    access.role = role
    access.loginRole = role == 'dispatch' and 'dispatch' or (role == 'civ' and 'civ' or 'leo')

    for _, key in ipairs({ 'open', 'admin', 'supervisor', 'dispatch', 'civ', 'dmv', 'leochat' }) do
        if perms[key] ~= nil then
            access[key] = boolish(perms[key])
        end
    end

    if perms.loginRole ~= nil then
        local v = lower(trim(perms.loginRole))
        if v == 'dispatch' or v == 'civ' or v == 'leo' then
            access.loginRole = v
        end
    end

    if access.admin then
        access.open = true
        access.supervisor = true
        access.dispatch = true
        access.dmv = true
        access.leochat = true
        if perms.loginRole == nil then
            access.loginRole = 'leo'
        end
    end
    if access.dispatch then
        access.open = true
        access.supervisor = true
        access.dmv = true
        access.leochat = true
    end
    if access.supervisor then
        access.open = true
        access.dmv = true
        access.leochat = true
    end

    access.pages = normalizeBooleanMap(perms.pages, rolePageDefaults(role))
    access.actions = normalizeBooleanMap(perms.actions, roleActionDefaults(role))
    if access.admin then
        access.pages = normalizeBooleanMap(access.pages or rolePageDefaults('admin'), rolePageDefaults('admin'))
        access.actions = normalizeBooleanMap(access.actions or roleActionDefaults('admin'), roleActionDefaults('admin'))
    end
    return finalizeAccessIdentity(access, role)
end

local function applyAccessOverridesForSource(src, access, row)
    access = access or normalizeEmployeeAccessRow({ mdt_role = 'none' })

    local hasDbRow = row ~= nil and row ~= false
    local useAce = (Config.PreferEmployeeAccessOverAce == false) or not hasDbRow

    if useAce then
        if hasAce(src, 'admin') then access.admin = true end
        if hasAce(src, 'dispatch') then access.dispatch = true end
        if hasAce(src, 'supervisor') then access.supervisor = true end
        if hasAce(src, 'open') then access.open = true end
        if hasAce(src, 'dmv') then access.dmv = true end
        if hasAce(src, 'leochat') then access.leochat = true end
        if hasAce(src, 'civ') then access.civ = true end
    end

    if access.admin then
        access.open = true
        access.supervisor = true
        access.dispatch = true
        access.dmv = true
        access.leochat = true
    elseif access.dispatch then
        access.open = true
        access.supervisor = true
        access.dmv = true
        access.leochat = true
    elseif access.supervisor then
        access.open = true
        access.dmv = true
        access.leochat = true
    end

    if access.civ and not access.open and not access.dispatch and not access.supervisor and not access.admin then
        access.loginRole = 'civ'
    elseif access.dispatch and not access.admin then
        access.loginRole = 'dispatch'
    end

    return finalizeAccessIdentity(access, (row and (row.mdt_role or row.role)) or access.role or 'leo')
end

local function cacheSourceAccess(src, access, row)
    if not src then return end
    access = applyAccessOverridesForSource(src, access or {}, row)
    access.employeeId = row and tonumber(row.id) or access.employeeId
    access.department = row and trim(row.department or row.active_department or '') or access.department
    AccessCache[src] = access
end

local function employeePermPayloadFromRow(row)
    return employeePermPayloadFromAccess(normalizeEmployeeAccessRow(row), row and (row.mdt_role or row.role) or 'leo')
end

local function fetchEmployeeRowByIdentity(ident, cb)
    ident = ident or {}
    cb = cb or function() end
    DB.fetchAll(([[
        SELECT id, identifier, license, discordid, name, callsign, department, grade, active, mdt_role, mdt_perms_json
        FROM %s
        WHERE active = 1
          AND (
              (license IS NOT NULL AND license != '' AND license = ?)
              OR (identifier IS NOT NULL AND identifier != '' AND identifier = ?)
              OR (discordid IS NOT NULL AND discordid != '' AND discordid = ?)
          )
        ORDER BY id DESC
        LIMIT 1
    ]]):format(qTable('employees')), { trim(ident.license or ''), trim(ident.identifier or ''), trim(ident.discordid or '') }, function(rows)
        cb(rows and rows[1] or nil)
    end)
end

local function refreshSourceAccess(src, cb)
    local ident = getCharacter(src)
    fetchEmployeeRowByIdentity(ident, function(row)
        local access = normalizeEmployeeAccessRow(row or { mdt_role = 'none', mdt_perms_json = '{}' })
        cacheSourceAccess(src, access, row)
        cb(access, row, ident)
    end)
end

local function refreshOnlineAccessForEmployeeRow(employeeRow)
    employeeRow = employeeRow or {}
    local rowLicense = trim(employeeRow.license or '')
    local rowIdentifier = trim(employeeRow.identifier or '')
    local rowDiscord = trim(employeeRow.discordid or '')
    if rowLicense == '' and rowIdentifier == '' and rowDiscord == '' then return end

    for _, srcValue in ipairs(GetPlayers()) do
        local src = tonumber(srcValue)
        if src then
            local ident = getCharacter(src)
            local matched = false
            if rowLicense ~= '' and trim(ident.license or '') == rowLicense then matched = true end
            if not matched and rowIdentifier ~= '' and trim(ident.identifier or '') == rowIdentifier then matched = true end
            if not matched and rowDiscord ~= '' and trim(ident.discordid or '') == rowDiscord then matched = true end
            if matched then
                refreshSourceAccess(src, function(access, row)
                    local role = access and access.role or 'leo'
                    local loginRole = access and access.loginRole or role
                    local ctx = {
                        name = trim((row and row.name) or ((UnitMeta[src] or {}).name or GetPlayerName(src) or 'Officer')),
                        callsign = trim((row and row.callsign) or ((UnitMeta[src] or {}).callsign or defaultCallsign((ident and (ident.charid or ident.identifier or ident.license or ident.discordid)) or src))),
                        department = sanitizeDepartmentId((row and row.department) or ((UnitMeta[src] or {}).department) or Config.DefaultDepartment) or (Config.DefaultDepartment or 'police'),
                        grade = tonumber((row and row.grade) or ((UnitMeta[src] or {}).grade) or 0) or 0,
                        role = loginRole,
                        isAdmin = access and access.admin or false,
                        isSupervisor = access and access.supervisor or false,
                        isDispatch = loginRole == 'dispatch',
                        isLEO = loginRole == 'dispatch' or loginRole == 'leo',
                        permissions = employeePermPayloadFromRow(row or { mdt_role = role, mdt_perms_json = jsonEncode(access or {}) }),
                        license = trim(ident.license or ''),
                        identifier = trim(ident.identifier or ''),
                        discordid = trim(ident.discordid or '')
                    }
                    TriggerClientEvent('az_mdt:client:unitProfileUpdated', src, ctx)
                end)
            end
        end
    end
end

local PostalPoints = {}



local function defaultThemeState()
    return {
        preset = 'blue-command',
        label = 'Blue Command',
        vars = {}
    }
end

local function cleanThemeValue(value, maxLen)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    maxLen = tonumber(maxLen) or 256
    if #value > maxLen then
        value = value:sub(1, maxLen)
    end
    return value
end

local function normalizeThemeState(payload)
    local base = defaultThemeState()
    if type(payload) ~= 'table' then
        return base
    end

    local preset = cleanThemeValue(payload.preset or payload.theme_key, 64) or base.preset
    if not preset:match('^[%w%-%_]+$') then
        preset = base.preset
    end

    local label = cleanThemeValue(payload.label or payload.theme_label, 128) or base.label
    local varsIn = payload.vars or payload.overrides or payload.values
    local vars = {}
    local total = 0

    if type(varsIn) == 'table' then
        for k, v in pairs(varsIn) do
            if total >= 96 then break end
            local key = tostring(k or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[^%w%-%_]', '')
            local val = cleanThemeValue(v, 512)
            if key ~= '' and val then
                vars[key] = val
                total = total + 1
            end
        end
    end

    return {
        preset = preset,
        label = label,
        vars = vars
    }
end

local function getThemeState()
    if type(ThemeState) ~= 'table' then
        ThemeState = defaultThemeState()
    end
    return ThemeState
end
local function ensureThemeTable(cb)
    DB.execute([[
        CREATE TABLE IF NOT EXISTS `mdt_theme_settings` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `theme_key` varchar(64) NOT NULL DEFAULT 'blue-command',
          `theme_label` varchar(128) DEFAULT NULL,
          `overrides_json` longtext DEFAULT NULL,
          `updated_by` varchar(128) DEFAULT NULL,
          `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
          PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function()
        if cb then cb() end
    end)
end


local function loadThemeState(cb)
    ensureThemeTable(function()
        DB.fetchAll([[SELECT id, theme_key, theme_label, overrides_json, updated_by, updated_at FROM mdt_theme_settings ORDER BY id ASC LIMIT 1]], {}, function(rows)
            local row = rows and rows[1] or nil
            if row then
                local normalized = normalizeThemeState({
                    preset = row.theme_key,
                    label = row.theme_label,
                    vars = jsonDecode(row.overrides_json or '') or {}
                })
                normalized.updatedBy = row.updated_by
                normalized.updatedAt = row.updated_at
                ThemeState = normalized
            else
                ThemeState = defaultThemeState()
            end
            if cb then cb(ThemeState) end
        end)
    end)
end

local function saveThemeState(payload, actorName, cb)
    local normalized = normalizeThemeState(payload)
    ensureThemeTable(function()
        DB.execute([[
            INSERT INTO mdt_theme_settings (id, theme_key, theme_label, overrides_json, updated_by)
            VALUES (1, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                theme_key = VALUES(theme_key),
                theme_label = VALUES(theme_label),
                overrides_json = VALUES(overrides_json),
                updated_by = VALUES(updated_by),
                updated_at = CURRENT_TIMESTAMP
        ]], {
            normalized.preset,
            normalized.label,
            jsonEncode(normalized.vars or {}),
            tostring(actorName or '')
        }, function()
            loadThemeState(function(state)
                if cb then cb(state or normalized) end
            end)
        end)
    end)
end

local function broadcastThemeState()
    triggerMdtViewers('az_mdt:client:themeSettings', getThemeState())
end

local LiveMapIconState = nil

local function defaultLiveMapIconState()
    local cfg = Config.LiveMap or {}
    local defaults = type(cfg.defaultIcons) == 'table' and cfg.defaultIcons or {}

    local function build(service, fallbackClass, fallbackLabel, fallbackEmoji)
        local row = type(defaults[service]) == 'table' and defaults[service] or {}
        return {
            className = trim(row.className or fallbackClass),
            imageUrl = trim(row.imageUrl or row.url or ''),
            label = trim(row.label or fallbackLabel),
            emoji = trim(row.emoji or fallbackEmoji)
        }
    end

    return {
        police = build('police', 'fa-solid fa-car-side', 'Police', '🚓'),
        fire   = build('fire',   'fa-solid fa-fire-truck', 'Fire', '🚒'),
        ems    = build('ems',    'fa-solid fa-truck-medical', 'EMS', '🚑')
    }
end

local function sanitizeLiveMapIconState(payload)
    local defaults = defaultLiveMapIconState()
    local output = {}

    local function cleanText(value, fallback, maxLen)
        local cleaned = trim(value or fallback or '')
        if maxLen and #cleaned > maxLen then
            cleaned = cleaned:sub(1, maxLen)
        end
        return cleaned
    end

    for service, fallback in pairs(defaults) do
        local incoming = type(payload) == 'table' and type(payload[service]) == 'table' and payload[service] or {}
        output[service] = {
            className = cleanText(incoming.className, fallback.className, 96),
            imageUrl = cleanText(incoming.imageUrl or incoming.url, fallback.imageUrl, 350000),
            label = cleanText(incoming.label, fallback.label, 32),
            emoji = cleanText(incoming.emoji, fallback.emoji, 16)
        }
    end

    return output
end

local function loadLiveMapIconState()
    if LiveMapIconState ~= nil then
        return LiveMapIconState
    end

    local filePath = tostring(((Config.LiveMap or {}).iconStoreFile) or 'config/live_map_icons.json')
    local raw = LoadResourceFile(RESOURCE_NAME, filePath)
    local parsed = raw and raw ~= '' and jsonDecode(raw) or nil
    LiveMapIconState = sanitizeLiveMapIconState(parsed)
    return LiveMapIconState
end

local function saveLiveMapIconState(payload, cb)
    local state = sanitizeLiveMapIconState(payload)
    local filePath = tostring(((Config.LiveMap or {}).iconStoreFile) or 'config/live_map_icons.json')
    SaveResourceFile(RESOURCE_NAME, filePath, jsonEncode(state), -1)
    LiveMapIconState = state
    if cb then cb(state) end
end

local function getLiveMapState()
    local cfg = Config.LiveMap or {}
    local bounds = type(cfg.bounds) == 'table' and cfg.bounds or {}
    local rect = type(cfg.mapRect) == 'table' and cfg.mapRect or {}
    return {
        enabled = cfg.enabled ~= false,
        updateIntervalMs = tonumber(cfg.updateIntervalMs) or 1750,
        showPostalLabels = cfg.showPostalLabels == true,
        allowCustomIcons = true,
        mapImage = trim(cfg.mapImage or 'img/gta5-roadmap-2048.jpg'),
        stageSize = math.max(512, tonumber(cfg.stageSize) or 2048),
        bounds = {
            minX = tonumber(bounds.minX) or -4200.0,
            maxX = tonumber(bounds.maxX) or 4500.0,
            minY = tonumber(bounds.minY) or -4500.0,
            maxY = tonumber(bounds.maxY) or 8500.0
        },
        mapRect = {
            left = tonumber(rect.left) or 289,
            top = tonumber(rect.top) or 35,
            right = tonumber(rect.right) or 1730,
            bottom = tonumber(rect.bottom) or 2046
        },
        icons = loadLiveMapIconState()
    }
end

local function broadcastLiveMapState()
    triggerMdtViewers('az_mdt:client:liveMapIcons', getLiveMapState())
end

local function loadPostals()
    if Config.Postals.enabled == false then
        return
    end

    local configured = tostring((Config.Postals and Config.Postals.file) or 'config/postals.json')
    local tried = {}
    local candidates = {}

    local function addCandidate(path)
        path = trim(path or '')
        if path == '' then return end
        for _, existing in ipairs(candidates) do
            if existing == path then
                return
            end
        end
        candidates[#candidates + 1] = path
    end

    addCandidate(configured)
    addCandidate('config/postals.json')
    addCandidate('postals.json')

    local raw, loadedPath
    for _, fileName in ipairs(candidates) do
        tried[#tried + 1] = fileName
        raw = LoadResourceFile(RESOURCE_NAME, fileName)
        if raw and raw ~= '' then
            loadedPath = fileName
            break
        end
    end

    if not raw or raw == '' then
        dprint(('No postal file found at %s; postal lookup disabled.'):format(table.concat(tried, ', ')))
        return
    end

    local rows = jsonDecode(raw)
    if type(rows) ~= 'table' then
        dprint(('Postal file %s could not be decoded.'):format(loadedPath or configured))
        return
    end

    local loaded = 0
    PostalPoints = {}
    for _, row in ipairs(rows) do
        local x = tonumber(row.x or row.X or row.lng or row.lon or row.longitude)
        local y = tonumber(row.y or row.Y or row.lat or row.latitude)
        local code = trim(row.code or row.postal or row.zip or row.id or '')
        local name = trim(row.name or row.street or row.location or '')
        if x and y and code ~= '' then
            PostalPoints[#PostalPoints + 1] = { x = x, y = y, code = code, name = name }
            loaded = loaded + 1
        end
    end

    dprint(('Loaded %d postal points from %s.'):format(loaded, loadedPath or configured))
end

RecentCallRoomOpen = RecentCallRoomOpen or {}

function shouldEmitCallRoomOpened(src, callId, cooldownMs)
    src = tonumber(src) or 0
    callId = tonumber(callId) or 0
    if src <= 0 or callId <= 0 then return false end
    local waitMs = math.max(0, tonumber(cooldownMs) or 15000)
    local now = GetGameTimer()
    local key = tostring(src) .. ':' .. tostring(callId)
    local last = tonumber(RecentCallRoomOpen[key]) or 0
    if last > 0 and (now - last) < waitMs then
        return false
    end
    RecentCallRoomOpen[key] = now
    return true
end

function clearCallRoomOpenCooldown(src, callId)
    src = tonumber(src) or 0
    callId = tonumber(callId) or 0
    if src <= 0 or callId <= 0 then return end
    RecentCallRoomOpen[tostring(src) .. ':' .. tostring(callId)] = nil
end

local function getNearestPostal(coords)
    if type(coords) ~= 'table' or not coords.x or not coords.y or #PostalPoints == 0 then
        return nil
    end

    local best, bestDist
    local x, y = tonumber(coords.x), tonumber(coords.y)
    if not x or not y then return nil end

    for i = 1, #PostalPoints do
        local p = PostalPoints[i]
        local dx = x - p.x
        local dy = y - p.y
        local dist = (dx * dx) + (dy * dy)
        if not bestDist or dist < bestDist then
            best = p
            bestDist = dist
        end
    end

    if not best then return nil end

    return {
        code = best.code,
        name = best.name,
        distance = math.sqrt(bestDist or 0.0)
    }
end

local function buildPlaceholders(count)
    if count <= 0 then return "NULL" end
    local t = {}
    for i = 1, count do t[i] = "?" end
    return table.concat(t, ",")
end


local FrameworkSchemaCache = {}

function frameworkModeEnabled()
    return Config.Standalone == false and hasAzFramework()
end

function fwCompactPlate(value)
    return lower(trim(tostring(value or '')):gsub('%s+', ''))
end

function frameworkColumnCacheKey(tableName, columnName)
    return ('%s:%s'):format(tostring(tableName or ''), tostring(columnName or ''))
end

function frameworkHasColumn(tableName, columnName, cb)
    cb = cb or function() end
    if not frameworkModeEnabled() then
        cb(false)
        return
    end

    tableName = trim(tableName or '')
    columnName = trim(columnName or '')
    if tableName == '' or columnName == '' then
        cb(false)
        return
    end

    local cacheKey = frameworkColumnCacheKey(tableName, columnName)
    if FrameworkSchemaCache[cacheKey] ~= nil then
        cb(FrameworkSchemaCache[cacheKey] == true)
        return
    end

    DB.fetchScalar([[SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?]], { tableName, columnName }, function(result)
        local exists = tonumber(result or 0) > 0
        FrameworkSchemaCache[cacheKey] = exists
        cb(exists)
    end)
end

function frameworkResolveColumns(tableName, columns, cb)
    cb = cb or function() end
    columns = columns or {}
    if not frameworkModeEnabled() then
        cb({})
        return
    end

    local resolved, index = {}, 1
    local function step()
        if index > #columns then
            cb(resolved)
            return
        end
        local col = columns[index]
        index = index + 1
        frameworkHasColumn(tableName, col, function(exists)
            resolved[col] = exists == true
            step()
        end)
    end
    step()
end

function frameworkCitizenSelectSql(cols)
    local parts = {
        (cols.id and 'uc.id' or 'NULL') .. ' AS id',
        (cols.name and 'uc.name' or "''") .. ' AS name',
        (cols.charid and 'uc.charid' or "''") .. ' AS charid',
        (cols.discordid and 'uc.discordid' or "''") .. ' AS discordid',
        (cols.license and 'uc.license' or "''") .. ' AS license',
        (cols.active_department and 'uc.active_department' or "''") .. ' AS active_department',
        (cols.license_status and 'uc.license_status' or "'valid'") .. ' AS license_status',
        (cols.metadata and 'uc.metadata' or 'NULL') .. ' AS metadata',
        'NULL AS mugshot',
        (cols.created_at and 'uc.created_at' or 'NULL') .. ' AS created_at'
    }
    return table.concat(parts, ', ')
end

function normalizeFrameworkCitizenRows(rows)
    rows = rows or {}
    for _, row in ipairs(rows) do
        row.name = trim(row.name or '')
        row.charid = trim(row.charid or '')
        row.discordid = trim(row.discordid or '')
        row.license = trim(row.license or '')
        row.active_department = trim(row.active_department or '')
        row.license_status = trim(row.license_status or '') ~= '' and trim(row.license_status or '') or 'valid'
        row._framework = true
        row._mdt_source = row._mdt_source or 'framework'
    end
    return rows
end

function fetchFrameworkCitizensByWhere(whereSql, params, cb, limitSql)
    cb = cb or function() end
    if not frameworkModeEnabled() then
        cb({})
        return
    end

    frameworkResolveColumns('user_characters', { 'id', 'name', 'charid', 'discordid', 'license', 'active_department', 'license_status', 'metadata', 'created_at' }, function(cols)
        if not cols.name then
            cb({})
            return
        end

        local query = ([[
            SELECT
                %s
            FROM user_characters uc
            WHERE %s
            ORDER BY uc.name ASC
            %s
        ]]):format(frameworkCitizenSelectSql(cols), whereSql, limitSql or '')

        DB.fetchAll(query, params or {}, function(rows)
            cb(normalizeFrameworkCitizenRows(rows or {}))
        end)
    end)
end

function frameworkVehicleSelectSql(cols)
    local parts = {
        (cols.id and 'uv.id' or 'NULL') .. ' AS id',
        (cols.plate and 'uv.plate' or "''") .. ' AS plate',
        (cols.model and 'uv.model' or "''") .. ' AS model',
        (cols.discordid and 'uv.discordid' or "''") .. ' AS discordid',
        (cols.charid and 'uv.charid' or "''") .. ' AS charid',
        (cols.owner_name and 'uv.owner_name' or "''") .. ' AS owner_name',
        (cols.vehicle_props and 'uv.vehicle_props' or 'NULL') .. ' AS vehicle_props'
    }
    return table.concat(parts, ', ')
end

function normalizeFrameworkVehicleRows(rows)
    rows = rows or {}
    for _, row in ipairs(rows) do
        row.plate = trim(row.plate or '')
        row.model = trim(row.model or '')
        row.discordid = trim(row.discordid or '')
        row.charid = trim(row.charid or '')
        row.owner_name = trim(row.owner_name or '')
        row._framework = true
        row._mdt_source = row._mdt_source or 'framework'
        if row.vehicle_props then
            local props = jsonDecode(row.vehicle_props)
            if props then
                if row.owner_name == '' and trim(props.ownerName or '') ~= '' then
                    row.owner_name = trim(props.ownerName or '')
                end
                if row.model == '' and trim(props.model or '') ~= '' then
                    row.model = trim(props.model or '')
                end
            end
            row.vehicle_props = nil
        end
    end
    return rows
end

function attachFrameworkVehicleOwnership(vehicleRows, cb)
    cb = cb or function() end
    vehicleRows = normalizeFrameworkVehicleRows(vehicleRows or {})
    if not frameworkModeEnabled() or #vehicleRows == 0 then
        cb(vehicleRows)
        return
    end

    local charids, discordids = {}, {}
    local charSeen, discordSeen = {}, {}
    for _, row in ipairs(vehicleRows) do
        local charid = trim(row.charid or '')
        local discordid = trim(row.discordid or '')
        if charid ~= '' and not charSeen[charid] then
            charSeen[charid] = true
            charids[#charids + 1] = charid
        end
        if discordid ~= '' and not discordSeen[discordid] then
            discordSeen[discordid] = true
            discordids[#discordids + 1] = discordid
        end
    end

    if #charids == 0 and #discordids == 0 then
        cb(vehicleRows)
        return
    end

    frameworkResolveColumns('user_characters', { 'name', 'charid', 'discordid' }, function(cols)
        if not cols.name then
            cb(vehicleRows)
            return
        end

        local clauses, params = {}, {}
        if cols.charid and #charids > 0 then
            clauses[#clauses + 1] = ('(uc.charid IN (%s))'):format(buildPlaceholders(#charids))
            for _, value in ipairs(charids) do params[#params + 1] = value end
        end
        if cols.discordid and #discordids > 0 then
            clauses[#clauses + 1] = ('(uc.discordid IN (%s))'):format(buildPlaceholders(#discordids))
            for _, value in ipairs(discordids) do params[#params + 1] = value end
        end

        if #clauses == 0 then
            cb(vehicleRows)
            return
        end

        local query = ([[
            SELECT
                uc.name AS name,
                %s AS charid,
                %s AS discordid
            FROM user_characters uc
            WHERE %s
        ]]):format(cols.charid and 'uc.charid' or "''", cols.discordid and 'uc.discordid' or "''", table.concat(clauses, ' OR '))

        DB.fetchAll(query, params, function(ownerRows)
            local byCharid, byDiscord = {}, {}
            for _, row in ipairs(ownerRows or {}) do
                local name = trim(row.name or '')
                local charid = trim(row.charid or '')
                local discordid = trim(row.discordid or '')
                if name ~= '' then
                    if charid ~= '' and byCharid[charid] == nil then
                        byCharid[charid] = name
                    end
                    if discordid ~= '' then
                        byDiscord[discordid] = byDiscord[discordid] or {}
                        byDiscord[discordid][#byDiscord[discordid] + 1] = name
                    end
                end
            end

            for _, vehicle in ipairs(vehicleRows) do
                if trim(vehicle.owner_name or '') == '' then
                    local charid = trim(vehicle.charid or '')
                    local discordid = trim(vehicle.discordid or '')
                    if charid ~= '' and byCharid[charid] then
                        vehicle.owner_name = byCharid[charid]
                    elseif discordid ~= '' and byDiscord[discordid] and #byDiscord[discordid] == 1 then
                        vehicle.owner_name = byDiscord[discordid][1]
                    end
                end
            end

            cb(vehicleRows)
        end)
    end)
end

function fetchFrameworkVehiclesByPlate(plate, cb)
    cb = cb or function() end
    if not frameworkModeEnabled() then
        cb({})
        return
    end

    frameworkResolveColumns('user_vehicles', { 'id', 'plate', 'model', 'discordid', 'charid', 'owner_name', 'vehicle_props' }, function(cols)
        if not cols.plate then
            cb({})
            return
        end

        local rawLike = '%' .. lower(trim(plate or '')) .. '%'
        local compactLike = '%' .. fwCompactPlate(plate) .. '%'
        local query = ([[
            SELECT
                %s
            FROM user_vehicles uv
            WHERE REPLACE(LOWER(uv.plate), ' ', '') LIKE ?
               OR LOWER(uv.plate) LIKE ?
            ORDER BY uv.plate ASC
            LIMIT 50
        ]]):format(frameworkVehicleSelectSql(cols))

        DB.fetchAll(query, { compactLike, rawLike }, function(rows)
            attachFrameworkVehicleOwnership(rows or {}, function(attachedRows)
                cb(attachedRows or rows or {})
            end)
        end)
    end)
end


math.randomseed((os.time() or 0) + (GetGameTimer() or 0))

local SERIAL_ALPHABET = { 'A','B','C','D','E','F','G','H','J','K','L','M','N','P','Q','R','S','T','U','V','W','X','Y','Z','2','3','4','5','6','7','8','9' }

local function randomSerialChunk(len)
    local out = {}
    for i = 1, len do
        out[i] = SERIAL_ALPHABET[math.random(1, #SERIAL_ALPHABET)]
    end
    return table.concat(out)
end

local function generateWeaponSerialCandidate()
    return ('AZ-%s-%s'):format(randomSerialChunk(4), randomSerialChunk(6))
end

local function resolveWeaponSerial(preferredSerial, cb, attempt)
    preferredSerial = trim(preferredSerial or ''):upper()
    attempt = tonumber(attempt) or 1

    local candidate = preferredSerial
    if candidate == '' or attempt > 1 then
        candidate = generateWeaponSerialCandidate()
    end

    DB.fetchAll(([[
        SELECT id
        FROM %s
        WHERE serial = ?
        LIMIT 1
    ]]):format(qTable('weapons')), { candidate }, function(rows)
        if rows and rows[1] then
            if attempt >= 25 then
                cb(generateWeaponSerialCandidate(), true)
                return
            end
            resolveWeaponSerial('', cb, attempt + 1)
            return
        end
        cb(candidate, attempt > 1 or preferredSerial == '')
    end)
end

local function uniqueCleanupValues(values)
    local seen, out = {}, {}
    for _, value in ipairs(values or {}) do
        value = trim(value)
        if value ~= '' and not seen[value] then
            seen[value] = true
            out[#out + 1] = value
        end
    end
    return out
end

local function runQueriesSequentially(queries, index, done)
    index = tonumber(index) or 1
    if index > #(queries or {}) then
        if done then done() end
        return
    end

    local entry = queries[index]
    if not entry or not entry.query then
        runQueriesSequentially(queries, index + 1, done)
        return
    end

    DB.execute(entry.query, entry.params or {}, function()
        runQueriesSequentially(queries, index + 1, done)
    end)
end

local function buildCivilianDeleteQueries(row)
    row = row or {}
    local queries = {}
    local citizenId = tonumber(row.id) or 0
    local name = trim(row.name or '')
    local ownerKeys = uniqueCleanupValues({ tostring(citizenId > 0 and citizenId or ''), row.charid or '', row.license or '' })

    if #ownerKeys > 0 then
        local placeholders = buildPlaceholders(#ownerKeys)
        queries[#queries + 1] = {
            query = ([[
                DELETE FROM %s
                WHERE owner_identifier IN (%s)
            ]]):format(qTable('vehicles'), placeholders),
            params = ownerKeys
        }
        queries[#queries + 1] = {
            query = ([[
                DELETE FROM %s
                WHERE owner_identifier IN (%s)
            ]]):format(qTable('weapons'), placeholders),
            params = ownerKeys
        }
    end

    local discordid = trim(row.discordid or '')
    if discordid ~= '' then
        queries[#queries + 1] = {
            query = ([[
                DELETE FROM %s
                WHERE discordid = ?
                  AND (owner_identifier IS NULL OR owner_identifier = '' OR owner_identifier = ?)
            ]]):format(qTable('vehicles')),
            params = { discordid, tostring(citizenId > 0 and citizenId or '') }
        }
        queries[#queries + 1] = {
            query = ([[
                DELETE FROM %s
                WHERE discordid = ?
                  AND (owner_identifier IS NULL OR owner_identifier = '' OR owner_identifier = ?)
            ]]):format(qTable('weapons')),
            params = { discordid, tostring(citizenId > 0 and citizenId or '') }
        }
    end

    if citizenId > 0 then
        local citizenKey = tostring(citizenId)
        queries[#queries + 1] = { query = [[DELETE FROM mdt_identity_flags WHERE target_type = 'citizen' AND target_value = ?]], params = { citizenKey } }
        queries[#queries + 1] = { query = [[DELETE FROM mdt_quick_notes WHERE target_type = 'citizen' AND target_value = ?]], params = { citizenKey } }
        queries[#queries + 1] = { query = [[DELETE FROM mdt_id_records WHERE target_type = 'citizen' AND target_value = ?]], params = { citizenKey } }
    end

    if name ~= '' then
        queries[#queries + 1] = { query = [[DELETE FROM mdt_identity_flags WHERE target_type = 'name' AND LOWER(target_value) = LOWER(?)]], params = { name } }
        queries[#queries + 1] = { query = [[DELETE FROM mdt_quick_notes WHERE target_type = 'name' AND LOWER(target_value) = LOWER(?)]], params = { name } }
        queries[#queries + 1] = { query = [[DELETE FROM mdt_id_records WHERE target_type = 'name' AND LOWER(target_value) = LOWER(?)]], params = { name } }
        queries[#queries + 1] = {
            query = [[
                DELETE FROM mdt_warrants
                WHERE LOWER(target_name) = LOWER(?)
                  AND (target_charid IS NULL OR target_charid = '')
            ]],
            params = { name }
        }
        queries[#queries + 1] = { query = [[DELETE FROM mdt_civilian_reports WHERE LOWER(citizen_name) = LOWER(?)]], params = { name } }
    end

    local charid = trim(row.charid or '')
    if charid ~= '' then
        queries[#queries + 1] = { query = [[DELETE FROM mdt_warrants WHERE target_charid = ?]], params = { charid } }
        queries[#queries + 1] = { query = [[DELETE FROM mdt_last_seen WHERE charid = ?]], params = { charid } }
        queries[#queries + 1] = { query = [[DELETE FROM mdt_civilian_reports WHERE citizen_identifier = ?]], params = { charid } }
    end

    local license = trim(row.license or '')
    if license ~= '' then
        queries[#queries + 1] = { query = [[DELETE FROM mdt_civilian_reports WHERE citizen_identifier = ?]], params = { license } }
    end

    return queries
end

local function citizenOwnerKeys(row)
    row = row or {}
    local citizenId = tostring((tonumber(row.id) or 0) > 0 and tonumber(row.id) or '')
    local charid = trim(row.charid or '')
    local license = trim(row.license or '')
    if charid ~= '' then
        return uniqueCleanupValues({ charid, citizenId })
    end
    return uniqueCleanupValues({ license, citizenId })
end

local function enrichCitizenRowsWithAssets(rows, cb)
    rows = rows or {}
    cb = cb or function() end

    if #rows == 0 then
        cb(rows)
        return
    end

    local keyToRows = {}
    local keys = {}
    local frameworkRows = {}
    local frameworkByCharid = {}
    local frameworkByDiscord = {}
    local frameworkByName = {}

    for _, row in ipairs(rows) do
        if type(row.metadata) == 'string' then
            row.metadata = jsonDecode(row.metadata) or {}
        else
            row.metadata = row.metadata or {}
        end
        row.vehicles = row.vehicles or {}
        row.weapons = row.weapons or {}
        local ownerKeys = citizenOwnerKeys(row)
        for _, key in ipairs(ownerKeys) do
            key = tostring(key or '')
            if key ~= '' then
                if not keyToRows[key] then
                    keyToRows[key] = {}
                    keys[#keys + 1] = key
                end
                keyToRows[key][#keyToRows[key] + 1] = row
            end
        end

        if row._framework == true then
            frameworkRows[#frameworkRows + 1] = row
            local charid = trim(row.charid or '')
            local discordid = trim(row.discordid or '')
            local nameKey = lower(trim(row.name or ''))
            if charid ~= '' then
                frameworkByCharid[charid] = frameworkByCharid[charid] or {}
                frameworkByCharid[charid][#frameworkByCharid[charid] + 1] = row
            end
            if discordid ~= '' then
                frameworkByDiscord[discordid] = frameworkByDiscord[discordid] or {}
                frameworkByDiscord[discordid][#frameworkByDiscord[discordid] + 1] = row
            end
            if nameKey ~= '' then
                frameworkByName[nameKey] = frameworkByName[nameKey] or {}
                frameworkByName[nameKey][#frameworkByName[nameKey] + 1] = row
            end
        end
    end

    local function finalizeRows()
        for _, row in ipairs(rows) do
            row.vehicle_count = tonumber(row.vehicle_count) or #(row.vehicles or {})
            row.weapon_count = tonumber(row.weapon_count) or #(row.weapons or {})
            row._vehicle_seen = nil
        end
        cb(rows)
    end

    local function attachFrameworkVehicles(done)
        done = done or function() end
        if not frameworkModeEnabled() or #frameworkRows == 0 then
            done()
            return
        end

        local charids, discordids = {}, {}
        local charSeen, discordSeen = {}, {}
        for _, row in ipairs(frameworkRows) do
            local charid = trim(row.charid or '')
            local discordid = trim(row.discordid or '')
            if charid ~= '' and not charSeen[charid] then
                charSeen[charid] = true
                charids[#charids + 1] = charid
            end
            if discordid ~= '' and not discordSeen[discordid] then
                discordSeen[discordid] = true
                discordids[#discordids + 1] = discordid
            end
        end

        frameworkResolveColumns('user_vehicles', { 'id', 'plate', 'model', 'discordid', 'charid', 'owner_name', 'vehicle_props' }, function(cols)
            if not cols.plate then
                done()
                return
            end

            local clauses, params = {}, {}
            if cols.charid and #charids > 0 then
                clauses[#clauses + 1] = ('(uv.charid IN (%s))'):format(buildPlaceholders(#charids))
                for _, value in ipairs(charids) do params[#params + 1] = value end
            end
            if cols.discordid and #discordids > 0 then
                clauses[#clauses + 1] = ('(uv.discordid IN (%s))'):format(buildPlaceholders(#discordids))
                for _, value in ipairs(discordids) do params[#params + 1] = value end
            end
            if #clauses == 0 then
                done()
                return
            end

            local query = ([[
                SELECT
                    %s
                FROM user_vehicles uv
                WHERE %s
                ORDER BY uv.plate ASC
            ]]):format(frameworkVehicleSelectSql(cols), table.concat(clauses, ' OR '))

            DB.fetchAll(query, params, function(frameworkVehicleRows)
                attachFrameworkVehicleOwnership(frameworkVehicleRows or {}, function(attachedVehicles)
                    for _, vehicle in ipairs(attachedVehicles or {}) do
                        local assigned = {}
                        local ownerNameKey = lower(trim(vehicle.owner_name or ''))
                        local charid = trim(vehicle.charid or '')
                        local discordid = trim(vehicle.discordid or '')

                        local function pushCitizen(citizen)
                            if type(citizen) ~= 'table' then return end
                            local citizenKey = tostring(citizen.id or citizen.charid or citizen.discordid or citizen.name or '')
                            if citizenKey == '' or assigned[citizenKey] then return end
                            local plateKey = compactPlate(vehicle.plate or '')
                            citizen._vehicle_seen = citizen._vehicle_seen or {}
                            if plateKey ~= '' and citizen._vehicle_seen[plateKey] then
                                assigned[citizenKey] = true
                                return
                            end
                            citizen.vehicles[#citizen.vehicles + 1] = {
                                id = vehicle.id,
                                plate = vehicle.plate,
                                model = vehicle.model,
                                owner_name = vehicle.owner_name,
                                owner_identifier = vehicle.charid ~= '' and vehicle.charid or vehicle.discordid,
                                discordid = vehicle.discordid,
                                active = 1,
                                _mdt_source = vehicle._mdt_source or 'framework'
                            }
                            if plateKey ~= '' then citizen._vehicle_seen[plateKey] = true end
                            assigned[citizenKey] = true
                        end

                        if charid ~= '' then
                            for _, citizen in ipairs(frameworkByCharid[charid] or {}) do pushCitizen(citizen) end
                        end
                        if ownerNameKey ~= '' then
                            for _, citizen in ipairs(frameworkByName[ownerNameKey] or {}) do pushCitizen(citizen) end
                        end
                        if next(assigned) == nil and discordid ~= '' then
                            local candidates = frameworkByDiscord[discordid] or {}
                            if #candidates == 1 then
                                pushCitizen(candidates[1])
                            end
                        end
                    end
                    done()
                end)
            end)
        end)
    end

    local function fetchWeapons()
        if #keys == 0 then
            attachFrameworkVehicles(finalizeRows)
            return
        end
        local placeholders = buildPlaceholders(#keys)
        DB.fetchAll(([[
            SELECT id, serial, type, owner, owner_name, owner_identifier, discordid, notes
            FROM %s
            WHERE owner_identifier IN (%s)
            ORDER BY serial ASC
        ]]):format(qTable('weapons'), placeholders), keys, function(weaponRows)
            weaponRows = weaponRows or {}
            for _, row in ipairs(weaponRows) do
                local ownerKey = tostring(row.owner_identifier or '')
                for _, citizen in ipairs(keyToRows[ownerKey] or {}) do
                    citizen.weapons[#citizen.weapons + 1] = row
                end
            end
            attachFrameworkVehicles(finalizeRows)
        end)
    end

    if #keys == 0 then
        fetchWeapons()
        return
    end

    local placeholders = buildPlaceholders(#keys)
    DB.fetchAll(([[
        SELECT id, plate, model, owner_name, owner_identifier, discordid, active
        FROM %s
        WHERE owner_identifier IN (%s)
        ORDER BY plate ASC
    ]]):format(qTable('vehicles'), placeholders), keys, function(vehicleRows)
        vehicleRows = vehicleRows or {}
        for _, row in ipairs(vehicleRows) do
            local ownerKey = tostring(row.owner_identifier or '')
            for _, citizen in ipairs(keyToRows[ownerKey] or {}) do
                citizen.vehicles[#citizen.vehicles + 1] = row
                citizen._vehicle_seen = citizen._vehicle_seen or {}
                local plateKey = compactPlate(row.plate or '')
                if plateKey ~= '' then citizen._vehicle_seen[plateKey] = true end
            end
        end
        fetchWeapons()
    end)
end

local function getIdentifierMap(src)
    local map = {}
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        local prefix, value = identifier:match("([^:]+):(.+)")
        if prefix and value and not map[prefix] then
            map[prefix] = value
        end
    end
    return map
end

local function getDiscordId(src)
    if Config.Standalone == false and hasAzFramework() then
        local fwDiscord = fwExport('getDiscordID', src)
        if fwDiscord ~= nil and tostring(fwDiscord) ~= '' then
            return tostring(fwDiscord)
        end
    end

    local ids = getIdentifierMap(src)
    return ids.discord
end

local function playerStateBag(src)
    local ok, player = pcall(function() return Player(src) end)
    if not ok or not player or not player.state then return nil end
    return player.state
end

local function normalizeStateId(value)
    if value == nil then return '' end
    local kind = type(value)
    if kind == 'string' or kind == 'number' or kind == 'boolean' then
        value = trim(tostring(value))
        if value == '' or value == 'false' or value == 'nil' or value == 'null' then return '' end
        return value
    end
    return ''
end

local function resolveCharacterIdFromState(src)
    local state = playerStateBag(src)
    if not state then return '' end

    for _, key in ipairs(Config.CharacterStateKeys or {}) do
        local val = normalizeStateId(state[key])
        if val ~= '' then return val end
    end

    local nestedTables = { 'character', 'charinfo', 'profile', 'metadata', 'identity' }
    local nestedKeys = { 'citizenid', 'citizenId', 'charid', 'charId', 'characterid', 'characterId', 'character_id', 'cid' }
    for _, tableKey in ipairs(nestedTables) do
        local node = state[tableKey]
        if type(node) == 'table' then
            for _, key in ipairs(nestedKeys) do
                local val = normalizeStateId(node[key])
                if val ~= '' then return val end
            end
        end
    end

    return ''
end

local function hasDistinctCharacterId(ident)
    ident = ident or {}
    local charid = trim(ident.charid or '')
    local license = trim(ident.license or '')
    return charid ~= '' and (license == '' or lower(charid) ~= lower(license))
end

getCharacter = function(src)
    local ids = getIdentifierMap(src)
    local license = ids.license or ids.license2 or ""
    local stateCharid = resolveCharacterIdFromState(src)
    local fallbackIdentifier = ids.fivem or ids.steam or ids.discord or ("src:" .. tostring(src))

    if Config.Standalone == false and hasAzFramework() then
        local fwChar = fwExport('GetPlayerCharacter', src)
        local fwDiscord = fwExport('getDiscordID', src)
        local charid = trim(fwChar and tostring(fwChar) or '')
        local discordid = trim(fwDiscord and tostring(fwDiscord) or '')
        local identifier = charid ~= '' and charid or (license ~= '' and license or fallbackIdentifier)
        return {
            discordid  = discordid ~= '' and discordid or (ids.discord and tostring(ids.discord) or ''),
            license    = tostring(license or ''),
            identifier = tostring(identifier or ''),
            charid     = tostring(charid ~= '' and charid or (stateCharid ~= '' and stateCharid or identifier))
        }
    end

    local charid = stateCharid ~= '' and stateCharid or (license ~= "" and license or fallbackIdentifier)
    local identifier = charid ~= '' and charid or (license ~= '' and license or fallbackIdentifier)
    return {
        discordid  = ids.discord and tostring(ids.discord) or "",
        license    = tostring(license or ""),
        identifier = tostring(identifier or ""),
        charid     = tostring(charid or "")
    }
end

local function defaultCallsign(charid)
    local suffix = tostring(charid or "0")
    suffix = suffix:gsub("[^%w]", "")
    suffix = suffix:sub(-3)
    if suffix == "" then suffix = tostring(math.random(100, 999)) end
    return ("%s-%s"):format(Config.DefaultCallsignPrefix, suffix)
end

local function addDepartmentOption(out, seen, id, label)
    id = trim(id)
    label = trim(label or id)
    if id == '' then return end
    local key = lower(id)
    if seen[key] then return end
    seen[key] = true
    out[#out + 1] = { id = id, label = label ~= '' and label or id }
end

local function getDepartmentOptions()
    local out = {}
    local seen = {}
    local source = Config.Departments

    if type(source) ~= 'table' or #source == 0 then
        source = {}
        for _, dept in ipairs((Config.Roles and Config.Roles.leoDepartments) or {}) do
            source[#source + 1] = { id = dept, label = dept }
        end
    end

    if #source == 0 then
        source = { { id = Config.DefaultDepartment or 'police', label = Config.DefaultDepartment or 'police' } }
    end

    for _, entry in ipairs(source) do
        local id, label
        if type(entry) == 'table' then
            id = trim(entry.id or entry.name or entry.department or entry.value)
            label = trim(entry.label or entry.name or entry.id or entry.department or entry.value)
        else
            id = trim(entry)
            label = id
        end
        addDepartmentOption(out, seen, id, label)
    end

    if Config.UseAzAmbulance == true then
        addDepartmentOption(out, seen, 'ems', 'EMS')
    end
    if Config.UseAzFire == true then
        addDepartmentOption(out, seen, 'fire', 'Fire')
    end

    local dispatchDept = trim(((Config.Dispatch or {}).defaultDepartment) or '')
    if dispatchDept ~= '' then
        addDepartmentOption(out, seen, dispatchDept, dispatchDept)
    end

    if #out == 0 then
        addDepartmentOption(out, seen, Config.DefaultDepartment or 'police', Config.DefaultDepartment or 'police')
    end

    return out
end

local function sanitizeDepartmentId(value)
    local dept = trim(value or '')
    if dept == '' then
        return trim(Config.DefaultDepartment or 'police')
    end
    for _, opt in ipairs(getDepartmentOptions()) do
        if lower(opt.id) == lower(dept) then
            return opt.id
        end
    end
    return nil
end

local function configuredJobMatch(job, jobNames)
    job = lower(trim(job or ''))
    if job == '' or type(jobNames) ~= 'table' then return false end
    for _, entry in ipairs(jobNames) do
        if lower(trim(entry)) == job then
            return true
        end
    end
    for key, value in pairs(jobNames) do
        if type(key) == 'string' and value == true and lower(trim(key)) == job then
            return true
        end
    end
    return false
end

local function resolveCurrentServiceDepartment(src, fallbackDept)
    local job = lower(trim(getFrameworkJobName(src) or ''))
    if job == '' then
        return sanitizeDepartmentId(fallbackDept) or sanitizeDepartmentId(Config.DefaultDepartment) or (Config.DefaultDepartment or 'police')
    end

    if Config.UseAzAmbulance == true and configuredJobMatch(job, ((Config.AzAmbulance or {}).JobNames) or { 'ambulance', 'ems', 'doctor', 'paramedic' }) then
        return sanitizeDepartmentId('ems') or 'ems'
    end

    if Config.UseAzFire == true and configuredJobMatch(job, ((Config.AzFire or {}).JobNames) or { 'fire', 'firefighter', 'safd' }) then
        return sanitizeDepartmentId('fire') or 'fire'
    end

    local dept = sanitizeDepartmentId(job)
    if dept then return dept end

    if configuredJobMatch(job, ((Config.Roles or {}).leoDepartments) or {}) then
        return sanitizeDepartmentId(job) or job
    end

    return sanitizeDepartmentId(fallbackDept) or sanitizeDepartmentId(Config.DefaultDepartment) or (Config.DefaultDepartment or 'police')
end

local function buildUiSettings()
    local tts = Config.TTS or {}
    return {
        departments = getDepartmentOptions(),
        tts = {
            callMode = tostring(tts.callMode or 'attached_only'),
            panicMode = tostring(tts.panicMode or 'all_onduty'),
            boloMode = tostring(tts.boloMode or 'all_onduty')
        },
        theme = getThemeState(),
        liveMap = getLiveMapState()
    }
end

local function attachUiSettings(ctx)
    if type(ctx) ~= 'table' then return ctx end
    local ui = buildUiSettings()
    ctx.ui = ui
    ctx.departments = ui.departments
    ctx.tts = ui.tts
    return ctx
end

local function denyNoPermission(src)
    TriggerClientEvent("az_mdt:client:notify", src, {
        type = "error",
        message = "You do not have permission to use the MDT."
    })
end

local function denyNoAdmin(src)
    TriggerClientEvent("az_mdt:client:notify", src, {
        type = "error",
        message = "You do not have MDT admin permission."
    })
end

local function loadOfficerContext(src, cb)
    if not canUseMDT(src) then
        cb(nil)
        return
    end

    local ident = getCharacter(src)
    local fallbackName = GetPlayerName(src) or ("Officer " .. tostring(src))
    local fallbackCtx = {
        name          = fallbackName,
        department    = resolveCurrentServiceDepartment(src, Config.DefaultDepartment),
        grade         = Config.DefaultOfficerGrade,
        callsign      = defaultCallsign(ident.charid),
        licenseStatus = "valid",
        discordid     = ident.discordid,
        charid        = ident.charid,
        identifier    = ident.identifier,
        isAdmin       = canUseAdmin(src),
        isSupervisor  = canUseSupervisor(src),
        isDispatch    = canUseDispatch(src),
        canManageDispatch = canManageDispatchConsole(src),
        canClearCalls = canManageDispatchConsole(src),
        canClearWarrants = canManageDispatchConsole(src),
        canClearBolos = canManageDispatchConsole(src),
        canAttachDetach = canUseOperationalMDT(src),
        role          = 'leo',
        isLEO         = true,
        isCiv         = false,
        canUseDMV     = canUseDMV(src),
        canUseCiv     = canUseCiv(src),
        canUseLeoChat = canUseLeoChat(src),
        license       = ident.license,
        source        = src,
        playerSource  = src,
        permissions   = employeePermPayloadFromAccess(AccessCache[src] or normalizeEmployeeAccessRow({ mdt_role = 'leo' }), 'leo')
    }

    if Config.Standalone == false then
        DB.fetchAll([[
            SELECT uc.id, uc.name, uc.charid, uc.discordid, uc.active_department, uc.license_status, ed.paycheck
            FROM user_characters uc
            LEFT JOIN econ_departments ed
              ON ed.discordid = uc.discordid
             AND ed.charid = uc.charid
             AND ed.department = uc.active_department
            WHERE uc.discordid = ? AND uc.charid = ?
            LIMIT 1
        ]], { ident.discordid, ident.charid }, function(rows)
            local row = rows and rows[1] or nil
            if not row then
                cacheSourceAccess(src, normalizeEmployeeAccessRow({ mdt_role = 'leo' }), nil)
                cb(attachUiSettings(fallbackCtx))
                return
            end

            cacheSourceAccess(src, normalizeEmployeeAccessRow({ mdt_role = 'leo' }), nil)
            cb(attachUiSettings({
                id            = row.id,
                name          = row.name or fallbackName,
                department    = resolveCurrentServiceDepartment(src, row.active_department or Config.DefaultDepartment),
                grade         = tonumber(row.paycheck) or Config.DefaultOfficerGrade,
                callsign      = defaultCallsign(row.charid or ident.charid),
                licenseStatus = row.license_status or 'valid',
                discordid     = row.discordid or ident.discordid,
                charid        = row.charid or ident.charid,
                identifier    = row.charid or ident.identifier,
                isAdmin       = canUseAdmin(src),
                isSupervisor  = canUseSupervisor(src),
                isDispatch    = canUseDispatch(src),
                canManageDispatch = canManageDispatchConsole(src),
                canClearCalls = canManageDispatchConsole(src),
                canClearWarrants = canManageDispatchConsole(src),
                canClearBolos = canManageDispatchConsole(src),
                canAttachDetach = canUseOperationalMDT(src),
                role          = canUseDispatch(src) and 'dispatch' or 'leo',
                isLEO         = true,
                isCiv         = false,
                canUseDMV     = canUseDMV(src),
                canUseCiv     = canUseCiv(src),
                canUseLeoChat = canUseLeoChat(src),
                license       = ident.license,
                source        = src,
                playerSource  = src,
                permissions   = employeePermPayloadFromAccess(AccessCache[src] or normalizeEmployeeAccessRow({ mdt_role = canUseDispatch(src) and 'dispatch' or 'leo' }), canUseDispatch(src) and 'dispatch' or 'leo')
            }))
        end)
        return
    end

    DB.fetchAll(([[
        SELECT id, identifier, license, discordid, name, callsign, department, grade, active, mdt_role, mdt_perms_json
        FROM %s
        WHERE active = 1
          AND (
              (license IS NOT NULL AND license != '' AND license = ?)
              OR (identifier IS NOT NULL AND identifier != '' AND identifier = ?)
              OR (discordid IS NOT NULL AND discordid != '' AND discordid = ?)
          )
        ORDER BY id DESC
        LIMIT 1
    ]]):format(qTable('employees')), { ident.license, ident.identifier, ident.discordid }, function(rows)
        local row = rows and rows[1] or nil
        if not row then
            cacheSourceAccess(src, normalizeEmployeeAccessRow({ mdt_role = 'leo' }), nil)
            cb(attachUiSettings(fallbackCtx))
            return
        end

        local access = normalizeEmployeeAccessRow(row)
        cacheSourceAccess(src, access, row)
        local loginRole = (access.dispatch and access.loginRole == 'dispatch') and 'dispatch' or 'leo'
        cb(attachUiSettings({
            id            = row.id,
            name          = row.name or fallbackName,
            department    = resolveCurrentServiceDepartment(src, row.department or Config.DefaultDepartment),
            grade         = tonumber(row.grade) or Config.DefaultOfficerGrade,
            callsign      = row.callsign ~= nil and tostring(row.callsign) or defaultCallsign(ident.charid),
            licenseStatus = "valid",
            discordid     = row.discordid or ident.discordid,
            charid        = ident.charid,
            identifier    = row.identifier or ident.identifier,
            isAdmin       = canUseAdmin(src),
            isSupervisor  = canUseSupervisor(src),
            isDispatch    = canUseDispatch(src) or loginRole == 'dispatch',
            canManageDispatch = canManageDispatchConsole(src),
            canClearCalls = canManageDispatchConsole(src),
            canClearWarrants = canManageDispatchConsole(src),
            canClearBolos = canManageDispatchConsole(src),
            canAttachDetach = canUseOperationalMDT(src),
            role          = loginRole,
            isLEO         = true,
            isCiv         = false,
            canUseDMV     = canUseDMV(src),
            canUseCiv     = canUseCiv(src),
            canUseLeoChat = canUseLeoChat(src),
            license       = ident.license,
            source        = src,
            playerSource  = src,
            permissions   = employeePermPayloadFromRow(row)
        }))
    end)
end

local fetchCiviliansForIdentity

local function loadDispatchContext(src, cb)
    if not canUseDispatch(src) then
        cb(nil)
        return
    end

    local ident = getCharacter(src)
    local fallbackName = GetPlayerName(src) or ("Dispatch " .. tostring(src))
    local fallbackDept = resolveCurrentServiceDepartment(src, sanitizeDepartmentId(((Config.Dispatch or {}).defaultDepartment) or 'dispatch') or (Config.DefaultDepartment or 'police'))
    local fallbackCtx = {
        name = fallbackName,
        department = fallbackDept,
        grade = Config.DefaultOfficerGrade,
        callsign = defaultCallsign(ident.charid),
        licenseStatus = "valid",
        discordid = ident.discordid,
        charid = ident.charid,
        identifier = ident.identifier,
        isAdmin = canUseAdmin(src),
        isSupervisor = true,
        isDispatch = true,
        role = 'dispatch',
        isLEO = true,
        isCiv = false,
        canManageDispatch = true,
        canClearCalls = true,
        canClearWarrants = true,
        canClearBolos = true,
        canAttachDetach = true,
        canUseDMV = true,
        canUseCiv = false,
        canUseLeoChat = true,
        license = ident.license,
        permissions = employeePermPayloadFromAccess(AccessCache[src] or normalizeEmployeeAccessRow({ mdt_role = 'dispatch' }), 'dispatch')
    }

    DB.fetchAll(([[
        SELECT id, identifier, license, discordid, name, callsign, department, grade, active, mdt_role, mdt_perms_json
        FROM %s
        WHERE active = 1
          AND (
              (license IS NOT NULL AND license != '' AND license = ?)
              OR (identifier IS NOT NULL AND identifier != '' AND identifier = ?)
              OR (discordid IS NOT NULL AND discordid != '' AND discordid = ?)
          )
        ORDER BY id DESC
        LIMIT 1
    ]]):format(qTable('employees')), { ident.license, ident.identifier, ident.discordid }, function(rows)
        local row = rows and rows[1] or nil
        if not row then
            cacheSourceAccess(src, normalizeEmployeeAccessRow({ mdt_role = 'dispatch' }), nil)
            cb(attachUiSettings(fallbackCtx))
            return
        end

        local access = normalizeEmployeeAccessRow(row)
        access.dispatch = true
        cacheSourceAccess(src, access, row)
        cb(attachUiSettings({
            id = row.id,
            name = row.name or fallbackName,
            department = resolveCurrentServiceDepartment(src, row.department or fallbackDept),
            grade = tonumber(row.grade) or Config.DefaultOfficerGrade,
            callsign = row.callsign ~= nil and tostring(row.callsign) or defaultCallsign(ident.charid),
            licenseStatus = "valid",
            discordid = row.discordid or ident.discordid,
            charid = ident.charid,
            identifier = row.identifier or ident.identifier,
            isAdmin = canUseAdmin(src),
            isSupervisor = true,
            isDispatch = true,
            role = 'dispatch',
            isLEO = true,
            isCiv = false,
            canManageDispatch = true,
            canClearCalls = true,
            canClearWarrants = true,
            canClearBolos = true,
            canAttachDetach = true,
            canUseDMV = true,
            canUseCiv = false,
            canUseLeoChat = true,
            license = ident.license,
            permissions = employeePermPayloadFromRow(row)
        }))
    end)
end

local function loadCivilianContext(src, cb)
    if not canUseCiv(src) then
        cb(nil)
        return
    end

    local ident = getCharacter(src)
    local fallbackName = GetPlayerName(src) or ("Civilian " .. tostring(src))
    fetchCiviliansForIdentity(ident, function(rows)
        local row = rows and rows[1] or nil
        local metadata = row and row.metadata or {}
        if type(metadata) == 'string' then
            metadata = jsonDecode(metadata) or {}
        end
        cacheSourceAccess(src, normalizeEmployeeAccessRow({ mdt_role = 'civ', mdt_perms_json = jsonEncode({ civ = true, loginRole = 'civ' }) }), nil)
        cb(attachUiSettings({
            id            = row and row.id or nil,
            name          = row and row.name or fallbackName,
            department    = Config.Roles.civilianDepartment or 'civilian',
            grade         = 0,
            callsign      = '',
            licenseStatus = (row and row.license_status) or (Config.CivilianDefaults.licenseStatus or 'valid'),
            discordid     = ident.discordid,
            charid        = ident.charid,
            identifier    = ident.identifier,
            isAdmin       = canUseAdmin(src),
            role          = 'civ',
            isLEO         = false,
            isCiv         = true,
            canUseDMV     = canUseDMV(src),
            canUseCiv     = true,
            canUseLeoChat = false,
            metadata      = metadata or {},
            license       = ident.license,
            permissions   = employeePermPayloadFromAccess(AccessCache[src] or normalizeEmployeeAccessRow({ mdt_role = 'civ', mdt_perms_json = jsonEncode({ civ = true, loginRole = 'civ' }) }), 'civ')
        }))
    end)
end

local function isCivilianOwnedBy(src, row)
    if type(row) ~= 'table' then return false end
    local ident = getCharacter(src)
    if hasDistinctCharacterId(ident) then
        return (row.charid ~= nil and row.charid ~= '' and row.charid == ident.charid)
    end
    return (row.charid ~= nil and row.charid ~= '' and row.charid == ident.charid)
        or (row.license ~= nil and row.license ~= '' and row.license == ident.license)
        or (row.discordid ~= nil and row.discordid ~= '' and row.discordid == ident.discordid)
end

fetchCiviliansForIdentity = function(ident, cb)
    ident = ident or {}
    cb = cb or function() end

    local function finish(rows)
        rows = rows or {}
        enrichCitizenRowsWithAssets(rows, function(enrichedRows)
            for _, row in ipairs(enrichedRows or rows) do
                row.owned = true
            end
            cb(enrichedRows or rows)
        end)
    end

    local function fetchFromMdtTables()
        if hasDistinctCharacterId(ident) then
            DB.fetchAll(([[
                SELECT id, name, charid, discordid, license, license_status, metadata, created_at
                FROM %s
                WHERE charid = ?
                ORDER BY id DESC
                LIMIT 100
            ]]):format(qTable('citizens')), { ident.charid }, function(rows)
                rows = rows or {}
                if #rows > 0 then
                    finish(rows)
                    return
                end
                DB.fetchAll(([[
                    SELECT id, name, charid, discordid, license, license_status, metadata, created_at
                    FROM %s
                    WHERE (
                        (license IS NOT NULL AND license != '' AND license = ?)
                        OR (discordid IS NOT NULL AND discordid != '' AND discordid = ?)
                    )
                    ORDER BY id DESC
                    LIMIT 100
                ]]):format(qTable('citizens')), { ident.license, ident.discordid }, finish)
            end)
            return
        end

        DB.fetchAll(([[
            SELECT id, name, charid, discordid, license, license_status, metadata, created_at
            FROM %s
            WHERE (
                (license IS NOT NULL AND license != '' AND license = ?)
                OR (charid IS NOT NULL AND charid != '' AND charid = ?)
                OR (discordid IS NOT NULL AND discordid != '' AND discordid = ?)
            )
            ORDER BY id DESC
            LIMIT 100
        ]]):format(qTable('citizens')), { ident.license, ident.charid, ident.discordid }, finish)
    end

    if frameworkModeEnabled() then
        if hasDistinctCharacterId(ident) and trim(ident.charid or '') ~= '' then
            fetchFrameworkCitizensByWhere('(uc.charid = ? OR (uc.discordid IS NOT NULL AND uc.discordid != "" AND uc.discordid = ?))', { ident.charid, ident.discordid }, function(rows)
                if rows and #rows > 0 then
                    finish(rows)
                    return
                end
                fetchFromMdtTables()
            end, 'LIMIT 100')
            return
        end

        fetchFrameworkCitizensByWhere('((uc.discordid IS NOT NULL AND uc.discordid != "" AND uc.discordid = ?))', { ident.discordid }, function(rows)
            if rows and #rows > 0 then
                finish(rows)
                return
            end
            fetchFromMdtTables()
        end, 'LIMIT 100')
        return
    end

    fetchFromMdtTables()
end

local function fetchOwnedCivilians(src, cb)
    fetchCiviliansForIdentity(getCharacter(src), cb)
end

local function persistOfficerProfileByIdentity(ident, ctx, cb)
    cb = cb or function() end
    ident = ident or {}
    ctx = ctx or {}

    local identifier = trim(ident.identifier or '')
    local license = trim(ident.license or '')
    local discordid = trim(ident.discordid or '')
    local charid = trim(ident.charid or identifier or license or discordid)
    local name = trim(ctx.name or ident.name or ('Officer ' .. tostring(identifier ~= '' and identifier or discordid ~= '' and discordid or 'unknown')))
    local callsign = trim(tostring(ctx.callsign ~= nil and ctx.callsign or defaultCallsign(charid)))
    local department = sanitizeDepartmentId(ctx.department) or (Config.DefaultDepartment or 'police')
    local grade = tonumber(ctx.grade) or Config.DefaultOfficerGrade or 0

    DB.fetchAll(([[
        SELECT id
        FROM %s
        WHERE active = 1
          AND (
              (license IS NOT NULL AND license != '' AND license = ?)
              OR (identifier IS NOT NULL AND identifier != '' AND identifier = ?)
              OR (discordid IS NOT NULL AND discordid != '' AND discordid = ?)
          )
        ORDER BY id DESC
        LIMIT 1
    ]]):format(qTable('employees')), { license, identifier, discordid }, function(rows)
        local row = rows and rows[1] or nil
        local function finish()
            cb({
                identifier = identifier,
                license = license,
                discordid = discordid,
                charid = charid,
                name = name,
                callsign = callsign,
                department = department,
                grade = grade
            })
        end
        if row and tonumber(row.id) then
            DB.execute(([[
                UPDATE %s
                SET name = ?, callsign = ?, department = ?, grade = ?, license = ?, identifier = ?, discordid = ?, active = 1
                WHERE id = ?
            ]]):format(qTable('employees')), { name, callsign, department, grade, license, identifier, discordid, tonumber(row.id) }, finish)
        else
            DB.insert(([[
                INSERT INTO %s (identifier, license, discordid, name, callsign, department, grade, active)
                VALUES (?, ?, ?, ?, ?, ?, ?, 1)
            ]]):format(qTable('employees')), { identifier, license, discordid, name, callsign, department, grade }, function()
                finish()
            end)
        end
    end)
end

local function persistOfficerUnitProfile(src, ctx, cb)
    if type(ctx) ~= 'table' then
        if cb then cb(nil) end
        return
    end
    local ident = getCharacter(src)
    ident.name = GetPlayerName(src) or ('Officer ' .. tostring(src))
    persistOfficerProfileByIdentity(ident, ctx, cb)
end

local function syncWebLinkedOfficerProfile(discordId, ctx)
    discordId = trim(discordId or '')
    if discordId == '' or type(ctx) ~= 'table' then return end
    local linkedName = trim(ctx.name or '')
    local linkedDepartment = trim(ctx.department or '')
    DB.execute([[UPDATE mdt_web_discord_links SET linked_name = ?, linked_department = ? WHERE discord_id = ?]], { linkedName, linkedDepartment, discordId })
    DB.execute([[UPDATE mdt_web_sessions SET linked_name = ?, linked_department = ? WHERE discord_id = ?]], { linkedName, linkedDepartment, discordId })
end

local function registerVehicleForCitizenRow(src, row, plate, model, cb)
    cb = cb or function() end
    local ident = getCharacter(src)
    local ownerIdentifier = trim(row.charid or '')
    if ownerIdentifier == '' then ownerIdentifier = trim(row.license or '') end
    if ownerIdentifier == '' then ownerIdentifier = tostring(row.id or '') end
    DB.execute(([[
        INSERT INTO %s (plate, model, owner_name, owner_identifier, discordid, active)
        VALUES (?, ?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE
            model = VALUES(model),
            owner_name = VALUES(owner_name),
            owner_identifier = VALUES(owner_identifier),
            discordid = VALUES(discordid),
            active = 1
    ]]):format(qTable('vehicles')), { plate, model, row.name or 'Unknown', ownerIdentifier, ident.discordid }, function()
        cb(true, row)
    end)
end

local function ensureOwnedCivilianForSource(src, cb)
    cb = cb or function() end
    fetchOwnedCivilians(src, function(rows)
        rows = rows or {}
        if rows[1] then
            cb(rows[1], false)
            return
        end
        if Config.AllowAutoCreateCivilianOnVehicleCommand == false then
            cb(nil, false, 'No civilian profile found for your current character.')
            return
        end
        local ident = getCharacter(src)
        local fallbackName = trim(((UnitMeta[src] or {}).name) or GetPlayerName(src) or ('Citizen ' .. tostring(src)))
        local metadata = {
            dob = '',
            phone = trim((Config.CivilianDefaults and Config.CivilianDefaults.phone) or 'Unknown'),
            address = trim((Config.CivilianDefaults and Config.CivilianDefaults.address) or 'Unknown')
        }
        local licenseStatus = trim((Config.CivilianDefaults and Config.CivilianDefaults.licenseStatus) or 'valid')
        DB.insert(([[
            INSERT INTO %s (name, charid, discordid, license, license_status, metadata)
            VALUES (?, ?, ?, ?, ?, ?)
        ]]):format(qTable('citizens')), {
            fallbackName,
            ident.charid,
            ident.discordid,
            ident.license,
            licenseStatus,
            jsonEncode(metadata)
        }, function(insertId)
            DB.fetchAll(([[SELECT id, name, charid, discordid, license FROM %s WHERE id = ? LIMIT 1]]):format(qTable('citizens')), { insertId }, function(createdRows)
                cb(createdRows and createdRows[1] or nil, true)
            end)
        end)
    end)
end

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

local Units    = {}
local UnitMeta = {}

function getOfficerDisplayLabel(src)
    local ctx = UnitMeta[src] or {}
    local ctxName = trim(ctx.name or '')
    if ctxName ~= '' then return ctxName end
    local playerName = trim(GetPlayerName(src) or '')
    if playerName ~= '' then return playerName end
    return 'Unit ' .. tostring(src)
end

function getOfficerDiscordLabel(src)
    local ctx = UnitMeta[src] or {}
    return trim(ctx.discordid or getDiscordId(src) or '')
end

function sortRowsByTimestampDesc(rows, key)
    key = key or 'timestamp'
    table.sort(rows, function(a, b)
        local av = tostring((a and a[key]) or (a and a.created_at) or '')
        local bv = tostring((b and b[key]) or (b and b.created_at) or '')
        return av > bv
    end)
end

local Calls       = {}
local syncOperationalUnitForOpen
local NextCallId  = 1

local LeoDutyChat = {}
local LEO_CHAT_MAX = 100
local CallRooms = {}
local MDTViewers = {}
local unitsBroadcastPending = false
local callsBroadcastPending = false

local function clearMdtViewer(src)
    src = tonumber(src) or 0
    if src <= 0 then return end
    MDTViewers[src] = nil
end

local function setMdtViewer(src, isOpen)
    src = tonumber(src) or 0
    if src <= 0 then return end
    if isOpen == true and canUseMDT(src) then
        MDTViewers[src] = true
    else
        MDTViewers[src] = nil
    end
end

local function triggerMdtViewers(eventName, ...)
    local args = { ... }
    local sent = false
    for target, _ in pairs(MDTViewers) do
        target = tonumber(target) or 0
        if target > 0 and GetPlayerPing(target) > 0 then
            TriggerClientEvent(eventName, target, table.unpack(args))
            sent = true
        else
            MDTViewers[target] = nil
        end
    end
    return sent
end

local function pushLeoDutyChat(msg)
    LeoDutyChat[#LeoDutyChat + 1] = msg
    if #LeoDutyChat > LEO_CHAT_MAX then
        table.remove(LeoDutyChat, 1)
    end
end

local function resetLeoDutyChat(reason)
    LeoDutyChat = {}
    triggerMdtViewers('az_mdt:client:leoChatReset', {
        reason = reason or 'duty_changed'
    })
end

local function ensureCallRoom(callId)
    callId = tonumber(callId) or 0
    if callId <= 0 then return nil end
    if not CallRooms[callId] then
        CallRooms[callId] = { messages = {}, notes = {} }
    end
    return CallRooms[callId]
end

local function callRoomSnapshot(callId)
    local room = ensureCallRoom(callId) or { messages = {}, notes = {} }
    return {
        callId = callId,
        messages = room.messages or {},
        notes = room.notes or {}
    }
end

local function isOnDutyStatus(status)
    return tostring(status or '') ~= '' and tostring(status or ''):upper() ~= 'OFFDUTY'
end

local function isPlayerOnDuty(src)
    local unit = Units[src]
    return unit ~= nil and isOnDutyStatus(unit.status)
end

local function triggerOnDutyClients(eventName, payload)
    for unitSrc, unit in pairs(Units) do
        if unit and isOnDutyStatus(unit.status) then
            TriggerClientEvent(eventName, unitSrc, payload)
        end
    end
end

local function broadcastUnits()
    if unitsBroadcastPending then return end
    unitsBroadcastPending = true
    SetTimeout(150, function()
        unitsBroadcastPending = false
        local arr = {}
        for _, u in pairs(Units) do
            arr[#arr + 1] = u
        end
        triggerMdtViewers("az_mdt:client:unitsSnapshot", {
            units = arr
        })
    end)
end

local function setUnitStatus(src, status, ctx)
    status = upper(trim(status or "AVAILABLE"))
    ctx    = ctx or UnitMeta[src] or {}

    local currentDepartment = sanitizeDepartmentId((ctx or {}).department or ((UnitMeta[src] or {}).department) or ((Units[src] or {}).department) or '')
    if currentDepartment == 'fire' and status ~= 'OFFDUTY' then
        markFireDutyHold(src, true)
    elseif status == 'OFFDUTY' and currentDepartment == 'fire' and not sourceHasFireDutyState(src) then
        markFireDutyHold(src, false)
    end
    local fireDutyProtected = Config.UseAzFire == true and currentDepartment == 'fire' and sourceHasFireDutyState(src)
    if status == 'OFFDUTY' and fireDutyProtected then
        status = upper(trim(((Units[src] and Units[src].status) or 'AVAILABLE')))
        if status == '' or status == 'OFFDUTY' then status = 'AVAILABLE' end
        dprint(('Ignoring stale OFFDUTY sync for fire unit %s while Fire duty state is still active.'):format(tostring(src)))
    end

    local wasOffDuty = not Units[src] or ((Units[src].status or '') == 'OFFDUTY')
    local isOffDuty = (status == 'OFFDUTY')

    if isOffDuty then
        Units[src] = nil
        UnitMeta[src] = ctx ~= nil and ctx or UnitMeta[src]
    else
        local existing = Units[src] or {}
        local unit = {
            id         = src,
            name       = ctx.name or ("Unit " .. tostring(src)),
            department = ctx.department or "police",
            callsign   = ctx.callsign or "",
            status     = status,
            coords     = existing.coords,
            heading    = existing.heading,
            inVehicle  = existing.inVehicle,
            vehicleClass = existing.vehicleClass,
            updatedAt  = existing.updatedAt
        }
        Units[src] = unit
        UnitMeta[src] = ctx ~= nil and ctx or UnitMeta[src]
    end

    if Config.Duty.resetLeoChatOnDutyChange and (wasOffDuty ~= isOffDuty) then
        resetLeoDutyChat(isOffDuty and 'off_duty' or 'on_duty')
    end

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
    if callsBroadcastPending then return end
    callsBroadcastPending = true
    SetTimeout(150, function()
        callsBroadcastPending = false
        triggerMdtViewers("az_mdt:client:callsSnapshot", snapshotCalls())
    end)
end

RegisterNetEvent('az_mdt:UIState', function(isOpen)
    local src = source
    if isOpen == true then
        if canUseMDT(src) then
            setMdtViewer(src, true)
        end
    else
        clearMdtViewer(src)
    end
end)

RegisterCommand(Config.CommandName or "mdt", function(src)
    if src == 0 then
        print("mdt command is player only")
        return
    end

    refreshSourceAccess(src, function(access)
        if not canUseMDT(src) then
            denyNoPermission(src)
            return
        end

        local loader = (access and access.loginRole == 'dispatch') and loadDispatchContext or loadOfficerContext
        loader(src, function(ctx)
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

            local existingStatus = resolveOpenUnitStatus(src, ctx, Config.Duty.defaultStatus or 'OFFDUTY')
            ctx.status = existingStatus
            UnitMeta[src] = ctx
            ctx.status = syncOperationalUnitForOpen(src, ctx, existingStatus, ctx.department)

            if ctx.charid then
                updateLastSeen(ctx.charid)
            end

            TriggerClientEvent("az_mdt:client:open", src, ctx)
            TriggerClientEvent("az_mdt:client:callsSnapshot", src, snapshotCalls())
            broadcastUnits()
        end)
    end)
end, false)

RegisterCommand(Config.DispatchCommandName or "dispatchmdt", function(src)
    if src == 0 then
        print("dispatchmdt command is player only")
        return
    end

    refreshSourceAccess(src, function()
        if not canUseDispatch(src) then
            denyNoPermission(src)
            return
        end

        loadDispatchContext(src, function(ctx)
            if not ctx then
                TriggerClientEvent("az_mdt:client:notify", src, { type = "error", message = "Unable to load your dispatch profile." })
                return
            end

            local existingStatus = (Units[src] and Units[src].status) or (((Config.Dispatch or {}).defaultStatus) or 'AVAILABLE')
            ctx.status = existingStatus
            UnitMeta[src] = ctx
            setUnitStatus(src, existingStatus, ctx)

            if ctx.charid then
                updateLastSeen(ctx.charid)
            end

            TriggerClientEvent("az_mdt:client:open", src, ctx)
            TriggerClientEvent("az_mdt:client:callsSnapshot", src, snapshotCalls())
            broadcastUnits()
        end)
    end)
end, false)

RegisterCommand(Config.CivCommandName or "civmdt", function(src)
    if src == 0 then
        print("civmdt command is player only")
        return
    end

    refreshSourceAccess(src, function()
        if not (canUseCiv(src) or canUseDMV(src) or canUseAdmin(src)) then
            denyNoPermission(src)
            return
        end

        loadCivilianContext(src, function(ctx)
            if not ctx then
                TriggerClientEvent("az_mdt:client:notify", src, {
                    type = "error",
                    message = "Unable to load your civilian profile."
                })
                return
            end

            if ctx.charid then
                updateLastSeen(ctx.charid)
            end

            TriggerClientEvent("az_mdt:client:open", src, ctx)
        end)
    end)
end, false)

local function completeVehicleRegistrationForCitizen(src, citizen, plate, model, created)
    registerVehicleForCitizenRow(src, citizen, plate, model, function()
        local msg = created
            and ('Civilian profile auto-created and vehicle %s registered to %s.'):format(plate, citizen.name or ('#' .. tostring(citizen.id or 0)))
            or ('Vehicle %s registered to %s.'):format(plate, citizen.name or ('#' .. tostring(citizen.id or 0)))
        TriggerClientEvent('az_mdt:client:notify', src, { type = 'success', message = msg })
        logAction(src, 'command_vehicle_register', citizen.name or tostring(citizen.id or 0), { plate = plate, model = model, autoCreatedCivilian = created and true or false })
        fetchOwnedCivilians(src, function(rows)
            TriggerClientEvent('az_mdt:client:myCivilians', src, rows or {})
        end)
    end)
end

local function promptVehicleRegistrationChoice(src, rows, plate, model)
    PendingVehicleRegistration[src] = {
        plate = plate,
        model = model,
        expires = os.time() + 120
    }
    loadCivilianContext(src, function(ctx)
        if ctx then
            TriggerClientEvent('az_mdt:client:open', src, ctx)
        end
        TriggerClientEvent('az_mdt:client:promptVehicleRegistration', src, {
            plate = plate,
            model = model,
            civilians = rows or {},
            title = 'Choose Character For Vehicle Registration'
        })
    end)
end

local function beginVehicleRegistrationSelection(src, plate, model)
    plate = trim(plate or ''):upper()
    model = trim(model or '')
    if plate == '' then
        TriggerClientEvent('az_mdt:client:notify', src, {
            type = 'error',
            message = ('Usage: /%s [plate] [vehicle model]'):format(tostring(Config.VehicleRegisterCommandName or 'mdtregistervehicle'))
        })
        return
    end

    fetchOwnedCivilians(src, function(rows)
        rows = rows or {}
        if #rows == 0 then
            ensureOwnedCivilianForSource(src, function(citizen, created, err)
                if not citizen then
                    TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = err or 'No civilian profile could be found for this character.' })
                    return
                end
                completeVehicleRegistrationForCitizen(src, citizen, plate, model, created)
            end)
            return
        end
        if #rows == 1 then
            completeVehicleRegistrationForCitizen(src, rows[1], plate, model, false)
            return
        end
        promptVehicleRegistrationChoice(src, rows, plate, model)
    end)
end

local function handleRegisterVehicleCommand(src, args)
    if src == 0 then
        print('vehicle register command is player only')
        return
    end
    if not (canUseCiv(src) or canUseMDT(src) or canUseDMV(src) or canUseAdmin(src)) then
        denyNoPermission(src)
        return
    end

    local plate = trim((args and args[1]) or ''):upper()
    local model = trim(table.concat(args or {}, ' ', 2))
    if plate == '' then
        TriggerClientEvent('az_mdt:client:requestCurrentVehicleRegistration', src, {})
        return
    end
    beginVehicleRegistrationSelection(src, plate, model)
end

RegisterCommand(Config.VehicleRegisterCommandName or 'mdtregistervehicle', function(src, args)
    handleRegisterVehicleCommand(src, args or {})
end, false)

for _, alias in ipairs(Config.VehicleRegisterCommandAliases or {}) do
    if trim(alias or '') ~= '' then
        RegisterCommand(alias, function(src, args)
            handleRegisterVehicleCommand(src, args or {})
        end, false)
    end
end

RegisterNetEvent('az_mdt:RegisterVehicleCurrentVehicleData', function(data)
    local src = source
    data = data or {}
    local plate = trim(data.plate or ''):upper()
    local model = trim(data.model or '')
    if plate == '' then
        TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Get in a vehicle first or use /regcar [plate] [model].' })
        return
    end
    beginVehicleRegistrationSelection(src, plate, model)
end)

RegisterNetEvent('az_mdt:RegisterVehicleToSelectedCivilian', function(data)
    local src = source
    data = data or {}
    local pending = PendingVehicleRegistration[src]
    if not pending or (pending.expires or 0) < os.time() then
        PendingVehicleRegistration[src] = nil
        TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Vehicle registration request expired. Please run the command again.' })
        return
    end
    local civilianId = tonumber(data.civilianId or 0) or 0
    if civilianId <= 0 then
        TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Choose a character first.' })
        return
    end
    DB.fetchAll(([[
        SELECT id, name, charid, discordid, license, license_status, metadata, created_at
        FROM %s
        WHERE id = ?
        LIMIT 1
    ]]):format(qTable('citizens')), { civilianId }, function(rows)
        local citizen = rows and rows[1] or nil
        if not citizen then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Selected character no longer exists.' })
            return
        end
        if not isCivilianOwnedBy(src, citizen) and not canUseAdmin(src) and not canUseDMV(src) then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'You can only register to a character you own.' })
            return
        end
        PendingVehicleRegistration[src] = nil
        local plate = trim((data.plate or pending.plate or '')):upper()
        local model = trim(data.model or pending.model or '')
        completeVehicleRegistrationForCitizen(src, citizen, plate, model, false)
    end)
end)

function mergeAz5PDLegacyNameSearch(term, likeTerm, citizenRows, recordRows, cb)
    if not az5pdEnabled() then
        cb(citizenRows or {}, recordRows or {})
        return
    end
    DB.fetchAll(([[
        SELECT netId, first_name, last_name, DATE_FORMAT(MAX(timestamp), '%%Y-%%m-%%d %%H:%%i:%%s') AS last_seen
        FROM %s
        WHERE LOWER(CONCAT(TRIM(COALESCE(first_name, '')), ' ', TRIM(COALESCE(last_name, '')))) LIKE ?
        GROUP BY netId, first_name, last_name
        ORDER BY MAX(timestamp) DESC
        LIMIT 50
    ]]):format(qAz5pd('idRecords', 'id_records')), { likeTerm }, function(legacyCitizens)
        citizenRows = citizenRows or {}
        recordRows = recordRows or {}
        local seen = {}
        for _, row in ipairs(citizenRows) do
            seen[lower(trim(row.name or ''))] = true
        end
        for _, row in ipairs(legacyCitizens or {}) do
            local fullName = trim(((row.first_name or '') .. ' ' .. (row.last_name or '')))
            local key = lower(fullName)
            if fullName ~= '' and not seen[key] then
                citizenRows[#citizenRows + 1] = {
                    id = 'az5pd:' .. tostring(row.netId or fullName),
                    name = fullName,
                    charid = tostring(row.netId or ''),
                    discordid = '',
                    license = '',
                    active_department = 'az5pd',
                    license_status = 'valid',
                    mugshot = nil,
                    last_seen = row.last_seen,
                    flags = { flags = {}, notes = '' },
                    quick_notes = {},
                    vehicles = {},
                    weapons = {},
                    vehicle_count = 0,
                    weapon_count = 0
                }
                seen[key] = true
            end
        end
        DB.fetchAll(([[
            SELECT id, netId, identifier, first_name, last_name, type,
                   DATE_FORMAT(timestamp, '%%Y-%%m-%%d %%H:%%i:%%s') AS timestamp
            FROM %s
            WHERE LOWER(CONCAT(TRIM(COALESCE(first_name, '')), ' ', TRIM(COALESCE(last_name, '')))) LIKE ?
            ORDER BY timestamp DESC
            LIMIT 100
        ]]):format(qAz5pd('idRecords', 'id_records')), { likeTerm }, function(legacyRecords)
            for _, row in ipairs(legacyRecords or {}) do
                local fullName = trim(((row.first_name or '') .. ' ' .. (row.last_name or '')))
                recordRows[#recordRows + 1] = {
                    id = 'az5pd_id_' .. tostring(row.id or 0),
                    target_type = 'name',
                    target_value = fullName,
                    rtype = trim(row.type or 'record'),
                    title = fullName ~= '' and fullName or trim(row.type or 'Record'),
                    description = ('Saved by %s%s'):format(trim(row.identifier or 'Unknown'), (trim(tostring(row.netId or '')) ~= '' and (' • Net ID ' .. tostring(row.netId)) or '')),
                    creator_identifier = trim(row.identifier or ''),
                    timestamp = row.timestamp
                }
            end
            sortRowsByTimestampDesc(recordRows, 'timestamp')
            cb(citizenRows, recordRows)
        end)
    end)
end

function compactPlate(value)
    return lower(trim(tostring(value or '')):gsub('%s+', ''))
end

local function stableAz5PDVehicleRoll(value)
    value = compactPlate(value)
    if value == '' then value = 'az5pd' end
    local total = 0
    for i = 1, #value do
        total = (total + ((string.byte(value, i) or 0) * i)) % 2147483647
    end
    if total <= 0 then total = 1 end
    return (total % 10) + 1
end

local function isAz5PDImportedVehicleRow(row)
    row = row or {}
    local sourceTag = lower(trim(row._mdt_source or row.source or ''))
    if sourceTag == 'az5pd' or sourceTag == 'az5pd_external' then return true end

    local idText = lower(trim(tostring(row.id or '')))
    if idText:sub(1, 5) == 'az5pd' or idText:sub(1, 6) == 'az5pdp' then return true end

    local ownerIdentifier = trim(row.owner_identifier or '')
    local discordId = trim(row.discordid or '')
    local policyType = lower(trim(row.policy_type or ''))
    if ownerIdentifier == '' and discordId == '' and (policyType == 'valid' or policyType == 'legacy' or policyType == 'none' or policyType == 'suspended' or policyType == 'expire' or policyType == 'expired') then
        return true
    end

    return false
end

local function getAz5PDInsuranceStatus(row)
    local roll = stableAz5PDVehicleRoll((row and row.plate) or '')
    return roll == 1 and 'INACTIVE' or 'ACTIVE'
end

function splitFullName(fullName)
    fullName = trim(fullName or '')
    if fullName == '' then return '', '' end
    local first, last = fullName:match('^(%S+)%s+(.+)$')
    if not first then return fullName, '' end
    return first, last
end

function seedAz5PDPlateContext(src, data, cb)
    if not az5pdEnabled() then
        cb(false)
        return
    end

    data = data or {}
    local plate = trim(data.plate or data.term or ''):upper()
    local owner = trim(data.owner or data.owner_name or data.name or '')
    local model = trim(data.model or data.make or '')
    local color = trim(data.color or '')
    local status = upper(trim(data.status or 'VALID'))

    if plate == '' then
        cb(false)
        return
    end

    local officerName = getOfficerDisplayLabel(src)
    local firstName, lastName = splitFullName(owner)
    local propsJson = jsonEncode({ ownerName = owner, color = color, model = model, source = 'az5pd_external' })
    local policyType = lower(status)
    if policyType == '' then policyType = 'valid' end
    local insuranceActive = getAz5PDInsuranceStatus({ plate = plate }) == 'ACTIVE' and 1 or 0

    DB.execute(([=[
        INSERT INTO %s (discordid, plate, model, owner_name, policy_type, premium, deductible, active, vehicle_props)
        VALUES (?, ?, ?, ?, ?, 0, 0, ?, ?)
        ON DUPLICATE KEY UPDATE
            model = CASE WHEN VALUES(model) <> '' THEN VALUES(model) ELSE model END,
            owner_name = CASE WHEN VALUES(owner_name) <> '' THEN VALUES(owner_name) ELSE owner_name END,
            policy_type = CASE WHEN VALUES(policy_type) <> '' THEN VALUES(policy_type) ELSE policy_type END,
            active = VALUES(active),
            vehicle_props = CASE WHEN VALUES(vehicle_props) <> '' THEN VALUES(vehicle_props) ELSE vehicle_props END
    ]=]):format(qTable('vehicles')), {
        '',
        plate,
        model ~= '' and model or 'Unknown',
        owner,
        policyType,
        insuranceActive,
        propsJson
    }, function()
        DB.execute(([=[
            INSERT INTO %s (plate, status)
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE status = COALESCE(NULLIF(status, ''), VALUES(status))
        ]=]):format(qAz5pd('plates', 'plates')), { plate, status ~= '' and status or 'VALID' }, function()
            DB.fetchScalar(([=[
                SELECT 1
                FROM %s
                WHERE COALESCE(plate, '') = ?
                  AND COALESCE(identifier, '') = ?
                  AND COALESCE(first_name, '') = ?
                  AND COALESCE(last_name, '') = ?
                  AND timestamp >= DATE_SUB(NOW(), INTERVAL 30 SECOND)
                LIMIT 1
            ]=]):format(qAz5pd('plateRecords', 'plate_records')), { plate, officerName, firstName, lastName }, function(existing)
                if existing then
                    cb(false)
                    return
                end
                DB.execute(([=[
                    INSERT INTO %s (plate, identifier, first_name, last_name)
                    VALUES (?, ?, ?, ?)
                ]=]):format(qAz5pd('plateRecords', 'plate_records')), { plate, officerName, firstName, lastName }, function()
                    cb(true)
                end)
            end)
        end)
    end)
end

function mergeAz5PDLegacyPlateSearch(plate, likeTerm, vehicleRows, recordRows, cb)
    if not az5pdEnabled() then
        cb(vehicleRows or {}, recordRows or {})
        return
    end

    local rawLike = '%' .. lower(trim(plate or '')) .. '%'
    local compactLike = '%' .. compactPlate(plate) .. '%'

    DB.fetchAll(([=[
        SELECT pr.id, pr.plate, pr.identifier, pr.first_name, pr.last_name,
               DATE_FORMAT(pr.timestamp, '%%Y-%%m-%%d %%H:%%i:%%s') AS timestamp,
               p.status AS legacy_status
        FROM %s pr
        LEFT JOIN %s p ON p.plate = pr.plate
        WHERE REPLACE(LOWER(pr.plate), ' ', '') LIKE ?
           OR LOWER(pr.plate) LIKE ?
        ORDER BY pr.timestamp DESC
        LIMIT 100
    ]=]):format(qAz5pd('plateRecords', 'plate_records'), qAz5pd('plates', 'plates')), { compactLike, rawLike }, function(legacyRows)
        vehicleRows = vehicleRows or {}
        recordRows = recordRows or {}
        local seenPlate = {}
        local vehicleByPlate = {}
        for _, row in ipairs(vehicleRows) do
            local plateKey = compactPlate(row.plate or '')
            seenPlate[plateKey] = true
            vehicleByPlate[plateKey] = row
        end
        for _, row in ipairs(legacyRows or {}) do
            local plateValue = trim(row.plate or '')
            local plateKey = compactPlate(plateValue)
            local statusText = trim(row.legacy_status or '')
            local existingVehicle = vehicleByPlate[plateKey]
            if existingVehicle then
                existingVehicle._mdt_source = existingVehicle._mdt_source or 'az5pd'
                if statusText ~= '' and (existingVehicle.registration_status == nil or trim(existingVehicle.registration_status or '') == '') then
                    existingVehicle.registration_status = statusText
                end
                existingVehicle.insurance_status = getAz5PDInsuranceStatus(existingVehicle)
                existingVehicle.active = existingVehicle.insurance_status == 'ACTIVE' and 1 or 0
            elseif plateValue ~= '' and not seenPlate[plateKey] then
                local insuranceStatus = getAz5PDInsuranceStatus({ plate = plateValue })
                vehicleRows[#vehicleRows + 1] = {
                    id = 'az5pdp:' .. plateValue,
                    discordid = '',
                    plate = plateValue,
                    model = 'Unknown',
                    owner_name = trim(((row.first_name or '') .. ' ' .. (row.last_name or ''))),
                    policy_type = statusText ~= '' and lower(statusText) or 'legacy',
                    premium = 0,
                    deductible = 0,
                    active = insuranceStatus == 'ACTIVE' and 1 or 0,
                    registration_status = statusText ~= '' and statusText or 'VALID',
                    insurance_status = insuranceStatus,
                    vehicle_props = nil,
                    _mdt_source = 'az5pd'
                }
                seenPlate[plateKey] = true
            end
            recordRows[#recordRows + 1] = {
                id = 'az5pd_plate_' .. tostring(row.id or 0),
                target_type = 'plate',
                target_value = plateValue,
                rtype = 'plate_record',
                title = plateValue,
                description = ('Owner %s • Saved by %s'):format(trim(((row.first_name or '') .. ' ' .. (row.last_name or ''))), trim(row.identifier or 'Unknown')),
                creator_identifier = trim(row.identifier or ''),
                timestamp = row.timestamp
            }
        end
        sortRowsByTimestampDesc(recordRows, 'timestamp')
        cb(vehicleRows, recordRows)
    end)
end


function mergeAz5PDLegacyReports(reportRows, term, cb)
    if not az5pdEnabled() then
        cb(reportRows or {})
        return
    end

    reportRows = reportRows or {}
    term = trim(term or '')
    local reportId = tonumber(term) or 0
    local like = ('%%%s%%'):format(term)

    local query = ([[
        SELECT id, creator_identifier, creator_discord, title, description, rtype,
               DATE_FORMAT(timestamp, '%%Y-%%m-%%d %%H:%%i:%%s') AS timestamp
        FROM %s
    ]]):format(qAz5pd('reports', 'reports'))
    local params = {}

    if term ~= '' then
        query = query .. [[
            WHERE (? = '' OR id = ? OR title LIKE ? OR description LIKE ? OR rtype LIKE ?)
        ]]
        params = { term, reportId, like, like, like }
    end

    query = query .. [[
        ORDER BY timestamp DESC
        LIMIT 100
    ]]

    DB.fetchAll(query, params, function(legacyRows)
        local seen = {}
        for _, row in ipairs(reportRows) do
            local body = row.body or {}
            local sig = table.concat({
                lower(trim(body.title or row.title or '')),
                lower(trim(body.info or body.body or row.description or '')),
                trim((row.created_at or row.timestamp or '')),
                lower(trim(body.officer or row.creator_identifier or row.creator_name or ''))
            }, '|')
            seen[sig] = true
        end

        for _, row in ipairs(legacyRows or {}) do
            local title = trim(row.title or '')
            local info = trim(row.description or '')
            local officer = trim(row.creator_identifier or '')
            local createdAt = trim(row.timestamp or '')
            local sig = table.concat({
                lower(title),
                lower(info),
                createdAt,
                lower(officer)
            }, '|')

            if not seen[sig] then
                reportRows[#reportRows + 1] = {
                    id = 'az5pd_report_' .. tostring(row.id or 0),
                    legacy_id = row.id,
                    type = trim(row.rtype or 'incident'),
                    created_at = createdAt,
                    creator_identifier = officer,
                    creator_discord = trim(row.creator_discord or ''),
                    source = 'az5pd',
                    body = {
                        title = title ~= '' and title or 'Report',
                        type = trim(row.rtype or 'incident'),
                        info = info,
                        officer = officer ~= '' and officer or 'Unknown'
                    }
                }
                seen[sig] = true
            end
        end

        sortRowsByTimestampDesc(reportRows, 'created_at')
        cb(reportRows)
    end)
end

function dispatchPlateSearchResults(src, plate, vehicles, records)
    dprint(("PlateSearch %d results: %d vehicles, %d records"):format(
        src, #(vehicles or {}), #(records or {})
    ))

    TriggerClientEvent("az_mdt:client:plateResults", src, {
        term     = plate,
        vehicles = vehicles or {},
        records  = records or {}
    })
end

function runPlateSearch(src, plate, data, cb)
    local rawLike = '%' .. lower(trim(plate or '')) .. '%'
    local compactLike = '%' .. compactPlate(plate) .. '%'

    local function normalizeVehicleRows(vehicleRows)
        vehicleRows = vehicleRows or {}
        for _, row in ipairs(vehicleRows) do
            if row.vehicle_props then
                local props = jsonDecode(row.vehicle_props)
                if props and props.ownerName and (not row.owner_name or row.owner_name == '') then
                    row.owner_name = props.ownerName
                end
                if (not row.model or row.model == '') and props and props.model then
                    row.model = props.model
                end
                if props and props.source then
                    row._mdt_source = tostring(props.source)
                end
                row.vehicle_props = nil
            end
            if isAz5PDImportedVehicleRow(row) then
                row.insurance_status = getAz5PDInsuranceStatus(row)
                row.active = row.insurance_status == 'ACTIVE' and 1 or 0
            elseif row.insurance_status == nil or trim(row.insurance_status or '') == '' then
                local policyType = trim(row.policy_type or '')
                if policyType ~= '' then
                    row.insurance_status = (tonumber(row.active or 0) == 1) and 'ACTIVE' or 'INACTIVE'
                else
                    row.insurance_status = 'NONE'
                end
            end
            if row.registration_status == nil or trim(row.registration_status or '') == '' then
                row.registration_status = 'VALID'
            end
        end
        return vehicleRows
    end

    local function finalizePlateSearch(vehicleRows)
        vehicleRows = normalizeVehicleRows(vehicleRows)
        DB.fetchAll([=[
            SELECT id, target_type, target_value, rtype, title, description, creator_identifier, timestamp
            FROM mdt_id_records
            WHERE target_type = 'plate'
              AND (REPLACE(LOWER(target_value), ' ', '') LIKE ? OR LOWER(target_value) LIKE ?)
            ORDER BY timestamp DESC
            LIMIT 100
        ]=], { compactLike, rawLike }, function(recordRows)
            mergeAz5PDLegacyPlateSearch(plate, compactLike, vehicleRows or {}, recordRows or {}, function(mergedVehicles, mergedRecords)
                cb(mergedVehicles or {}, mergedRecords or {})
            end)
        end)
    end

    DB.fetchAll(([=[
        SELECT
            id,
            discordid,
            plate,
            model,
            owner_name,
            policy_type,
            premium,
            deductible,
            active,
            vehicle_props
        FROM %s
        WHERE REPLACE(LOWER(plate), ' ', '') LIKE ?
           OR LOWER(plate) LIKE ?
        ORDER BY plate ASC
        LIMIT 50
    ]=]):format(qTable('vehicles')), { compactLike, rawLike }, function(vehicleRows)
        vehicleRows = vehicleRows or {}
        if frameworkModeEnabled() then
            fetchFrameworkVehiclesByPlate(plate, function(frameworkRows)
                local seen = {}
                for _, row in ipairs(vehicleRows) do
                    seen[compactPlate(row.plate or '')] = row
                end
                for _, row in ipairs(frameworkRows or {}) do
                    local key = compactPlate(row.plate or '')
                    local existing = seen[key]
                    if existing then
                        if trim(existing.owner_name or '') == '' and trim(row.owner_name or '') ~= '' then
                            existing.owner_name = row.owner_name
                        end
                        if trim(existing.model or '') == '' and trim(row.model or '') ~= '' then
                            existing.model = row.model
                        end
                        existing._mdt_source = existing._mdt_source or row._mdt_source or 'framework'
                    else
                        vehicleRows[#vehicleRows + 1] = row
                        seen[key] = row
                    end
                end
                finalizePlateSearch(vehicleRows)
            end)
            return
        end
        finalizePlateSearch(vehicleRows)
    end)
end

externalAz5PDNameSearchDeduper = {}
local mdtInboundRequestLimiter = {}

local function shouldThrottleInboundMdtRequest(src, bucket, query, minIntervalMs, duplicateWindowMs)
    src = tonumber(src) or 0
    if src <= 0 then return false end

    bucket = tostring(bucket or 'generic')
    local now = GetGameTimer()
    local srcKey = tostring(src)
    local bucketState = (mdtInboundRequestLimiter[srcKey] or {})[bucket]
    local cleanQuery = lower(trim(query or ''))
    local minInterval = tonumber(minIntervalMs) or 0
    local duplicateWindow = tonumber(duplicateWindowMs) or minInterval

    if bucketState then
        if minInterval > 0 and (now - (bucketState.lastAt or 0)) < minInterval then
            return true
        end
        if cleanQuery ~= '' and cleanQuery == (bucketState.lastQuery or '') and duplicateWindow > 0 and (now - (bucketState.lastAt or 0)) < duplicateWindow then
            return true
        end
    end

    local srcState = mdtInboundRequestLimiter[srcKey] or {}
    srcState[bucket] = {
        lastAt = now,
        lastQuery = cleanQuery
    }
    mdtInboundRequestLimiter[srcKey] = srcState
    return false
end

AddEventHandler('playerDropped', function()
    local src = source
    if src then
        mdtInboundRequestLimiter[tostring(src)] = nil
    end
end)

function shouldSkipDuplicateAz5PDNameSearch(src, term)
    local cleanTerm = lower(trim(term or ''))
    if cleanTerm == '' then return false end
    local now = GetGameTimer()
    local key = tostring(src) .. ':' .. cleanTerm
    local lastAt = externalAz5PDNameSearchDeduper[key] or 0
    if (now - lastAt) < 3500 then
        return true
    end
    externalAz5PDNameSearchDeduper[key] = now
    return false
end

function seedAz5PDNameContext(src, data, cb)
    if not az5pdEnabled() then
        cb(false)
        return
    end

    data = data or {}
    local first = trim(data.first or '')
    local last = trim(data.last or '')
    local fullName = trim(data.term or data.name or ((first .. ' ' .. last)))
    local netId = trim(data.netId or data.netid or '')

    if fullName == '' then
        cb(false)
        return
    end

    local firstName, lastName = splitFullName(fullName)
    local officerLabel = getOfficerDisplayLabel(src)

    DB.fetchScalar(([=[
        SELECT 1
        FROM %s
        WHERE COALESCE(netId, '') = ?
          AND COALESCE(identifier, '') = ?
          AND COALESCE(first_name, '') = ?
          AND COALESCE(last_name, '') = ?
          AND COALESCE(type, '') = 'external_lookup'
          AND timestamp >= DATE_SUB(NOW(), INTERVAL 30 SECOND)
        LIMIT 1
    ]=]):format(qAz5pd('idRecords', 'id_records')), {
        netId,
        officerLabel,
        firstName,
        lastName
    }, function(existing)
        if existing then
            cb(false)
            return
        end

        DB.execute(([=[
            INSERT INTO %s (netId, identifier, first_name, last_name, type)
            VALUES (?, ?, ?, ?, ?)
        ]=]):format(qAz5pd('idRecords', 'id_records')), {
            netId,
            officerLabel,
            firstName,
            lastName,
            'external_lookup'
        }, function()
            cb(true)
        end)
    end)
end

RegisterNetEvent("az_mdt:NameSearch", function(data)
    local src  = source
    data       = data or {}

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end

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

    local function continueNameSearch(citizenRows)
        citizenRows = citizenRows or {}
        local citizenIds = {}
        for _, row in ipairs(citizenRows) do
            row.flags = row.flags or { flags = {}, notes = '' }
            row.quick_notes = row.quick_notes or {}
            if row.id ~= nil then
                citizenIds[#citizenIds + 1] = tostring(row.id)
            end
        end

        local function finishRecords()
            DB.fetchAll([=[
                SELECT id, target_type, target_value, rtype, title, description, creator_identifier, timestamp
                FROM mdt_id_records
                WHERE target_type = 'name'
                  AND LOWER(target_value) LIKE ?
                ORDER BY timestamp DESC
                LIMIT 100
            ]=], { likeTerm }, function(recordRows)
                recordRows = recordRows or {}
                mergeAz5PDLegacyNameSearch(term, likeTerm, citizenRows, recordRows, function(mergedCitizens, mergedRecords)
                    dprint(("NameSearch %d results: %d citizens, %d records"):format(
                        src, #(mergedCitizens or {}), #(mergedRecords or {})
                    ))

                    enrichCitizenRowsWithAssets(mergedCitizens, function(enrichedRows)
                        TriggerClientEvent("az_mdt:client:nameResults", src, {
                            term      = term,
                            citizens  = enrichedRows or mergedCitizens,
                            records   = mergedRecords
                        })
                    end)
                end)
            end)
        end

        local function fetchQuickNotes()
            local query
            local params = {}
            if #citizenIds > 0 then
                query = ([=[
                    SELECT id, target_type, target_value, note, created_at
                    FROM mdt_quick_notes
                    WHERE ((target_type = 'citizen' AND target_value IN (%s))
                       OR (target_type = 'name' AND LOWER(target_value) LIKE ?))
                    ORDER BY created_at DESC
                ]=]):format(buildPlaceholders(#citizenIds))
                for _, id in ipairs(citizenIds) do params[#params + 1] = id end
                params[#params + 1] = likeTerm
            else
                query = [=[
                    SELECT id, target_type, target_value, note, created_at
                    FROM mdt_quick_notes
                    WHERE target_type = 'name' AND LOWER(target_value) LIKE ?
                    ORDER BY created_at DESC
                ]=]
                params = { likeTerm }
            end

            DB.fetchAll(query, params, function(noteRows)
                noteRows = noteRows or {}
                local notesByCitizen = {}
                local notesByName = {}

                for _, n in ipairs(noteRows) do
                    local targetValue = tostring(n.target_value or '')
                    local entry = {
                        id = tonumber(n.id) or 0,
                        note = n.note,
                        created_at = n.created_at
                    }

                    if n.target_type == 'citizen' and targetValue ~= '' then
                        notesByCitizen[targetValue] = notesByCitizen[targetValue] or {}
                        if #notesByCitizen[targetValue] < 5 then
                            table.insert(notesByCitizen[targetValue], entry)
                        end
                    elseif n.target_type == 'name' then
                        local key = lower(targetValue)
                        notesByName[key] = notesByName[key] or {}
                        if #notesByName[key] < 5 then
                            table.insert(notesByName[key], entry)
                        end
                    end
                end

                for _, c in ipairs(citizenRows) do
                    local idKey = tostring(c.id or '')
                    local nameKey = lower(c.name or '')
                    c.quick_notes = notesByCitizen[idKey] or notesByName[nameKey] or {}
                end

                finishRecords()
            end)
        end

        local function fetchFlags()
            local query
            local params = {}
            if #citizenIds > 0 then
                query = ([=[
                    SELECT target_type, target_value, flags_json, notes
                    FROM mdt_identity_flags
                    WHERE ((target_type = 'citizen' AND target_value IN (%s))
                       OR (target_type = 'name' AND LOWER(target_value) LIKE ?))
                ]=]):format(buildPlaceholders(#citizenIds))
                for _, id in ipairs(citizenIds) do params[#params + 1] = id end
                params[#params + 1] = likeTerm
            else
                query = [=[
                    SELECT target_type, target_value, flags_json, notes
                    FROM mdt_identity_flags
                    WHERE target_type = 'name' AND LOWER(target_value) LIKE ?
                ]=]
                params = { likeTerm }
            end

            DB.fetchAll(query, params, function(flagRows)
                flagRows = flagRows or {}
                local flagsByCitizen = {}
                local flagsByName = {}

                for _, row in ipairs(flagRows) do
                    local key = tostring(row.target_value or '')
                    local parsed = jsonDecode(row.flags_json or '') or {}
                    local payload = { flags = parsed, notes = row.notes or '' }
                    if row.target_type == 'citizen' then
                        flagsByCitizen[key] = payload
                    else
                        flagsByName[lower(key)] = payload
                    end
                end

                for _, c in ipairs(citizenRows) do
                    local idKey = tostring(c.id or '')
                    local nameKey = lower(c.name or '')
                    c.flags = flagsByCitizen[idKey] or flagsByName[nameKey] or { flags = {}, notes = '' }
                end

                fetchQuickNotes()
            end)
        end

        fetchFlags()
    end

    local function runNameSearchQuery()
        dprint(("NameSearch from %d term='%s'"):format(src, term))

        local function fetchMdtRows(done)
            DB.fetchAll(([=[
                SELECT
                    c.id,
                    c.name,
                    c.charid,
                    c.discordid,
                    c.license,
                    c.active_department,
                    c.license_status,
                    c.mugshot,
                    ls.last_seen
                FROM %s c
                LEFT JOIN mdt_last_seen ls
                       ON ls.charid = c.charid
                WHERE LOWER(c.name) LIKE ?
                ORDER BY c.name ASC
                LIMIT 50
            ]=]):format(qTable('citizens')), { likeTerm }, function(rows)
                done(rows or {})
            end)
        end

        if frameworkModeEnabled() then
            fetchFrameworkCitizensByWhere('LOWER(uc.name) LIKE ?', { likeTerm }, function(frameworkRows)
                fetchMdtRows(function(mdtRows)
                    local mergedRows = {}
                    local seen = {}
                    for _, row in ipairs(frameworkRows or {}) do
                        local key = lower(trim(row.name or '')) .. '|' .. trim(row.charid or '')
                        if key ~= '|' and not seen[key] then
                            seen[key] = true
                            mergedRows[#mergedRows + 1] = row
                        end
                    end
                    for _, row in ipairs(mdtRows or {}) do
                        local key = lower(trim(row.name or '')) .. '|' .. trim(row.charid or '')
                        if key == '|' then
                            key = lower(trim(row.name or '')) .. '|mdt:' .. tostring(row.id or '')
                        end
                        if not seen[key] then
                            seen[key] = true
                            mergedRows[#mergedRows + 1] = row
                        end
                    end
                    continueNameSearch(mergedRows)
                end)
            end, 'LIMIT 50')
            return
        end

        fetchMdtRows(function(rows)
            continueNameSearch(rows)
        end)
    end

    if az5pdEnabled() and lower(trim(data.source or '')) == 'az5pd' then
        if shouldSkipDuplicateAz5PDNameSearch(src, term) then
            dprint(("NameSearch deduped from %d term='%s'"):format(src, term))
            return
        end
        seedAz5PDNameContext(src, data, function()
            runNameSearchQuery()
        end)
        return
    end

    runNameSearchQuery()
end)

RegisterNetEvent("az_mdt:UpdateLastSeen", function(charid)
    local src = source
    if not charid then
        local ident = getCharacter(src)
        if not ident or not ident.charid then return end
        charid = ident.charid
    end
    updateLastSeen(charid)
end)

RegisterNetEvent("az_mdt:PlateSearch", function(data)
    local src = source
    data = data or {}

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end

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

    plate = upper(plate)
    if shouldThrottleInboundMdtRequest(src, 'PlateSearch', plate, 250, 1200) then
        dprint(("PlateSearch throttled from %d term='%s'"):format(src, plate))
        return
    end
    dprint(("PlateSearch from %d term='%s'"):format(src, plate))

    runPlateSearch(src, plate, data, function(mergedVehicles, mergedRecords)
        local needsSeed = #(mergedVehicles or {}) == 0
            and #(mergedRecords or {}) == 0
            and az5pdEnabled()
            and lower(trim(data.source or '')) == 'az5pd'
            and (trim(data.owner or data.owner_name or '') ~= '' or trim(data.model or data.make or '') ~= '')

        if needsSeed then
            seedAz5PDPlateContext(src, data, function()
                runPlateSearch(src, plate, data, function(seedVehicles, seedRecords)
                    dispatchPlateSearchResults(src, plate, seedVehicles, seedRecords)
                end)
            end)
            return
        end

        dispatchPlateSearchResults(src, plate, mergedVehicles, mergedRecords)
    end)
end)

RegisterNetEvent("az_mdt:WeaponSearch", function(data)
    local src = source
    data = data or {}

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end

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

    local term = "%" .. lower(serial) .. "%"
    dprint(("WeaponSearch from %d serial='%s'"):format(src, serial))

    DB.fetchAll(([[
        SELECT id, serial, type, owner, owner_name, owner_identifier, discordid, notes
        FROM %s
        WHERE LOWER(serial) LIKE ?
        ORDER BY serial ASC
        LIMIT 50
    ]]):format(qTable('weapons')), { term }, function(weaponRows)
        DB.fetchAll([[
            SELECT id, target_type, target_value, rtype, title, description, timestamp
            FROM mdt_id_records
            WHERE target_type = 'weapon'
              AND LOWER(target_value) LIKE ?
            ORDER BY timestamp DESC
            LIMIT 100
        ]], { term }, function(recordRows)
            TriggerClientEvent("az_mdt:client:weaponResults", src, {
                term    = serial,
                weapons = weaponRows or {},
                records = recordRows or {}
            })
        end)
    end)
end)

RegisterNetEvent("az_mdt:RequestBolos", function()
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    if shouldThrottleInboundMdtRequest(src, 'RequestBolos', '', 900, 2000) then
        dprint("RequestBolos throttled from", src)
        return
    end
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

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
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

            DB.fetchAll([[
                SELECT id, type, data, created_at
                FROM mdt_bolos
                ORDER BY id DESC
                LIMIT 200
            ]], {}, function(allRows)
                allRows = allRows or {}
                for _, boloRow in ipairs(allRows) do
                    boloRow.body = jsonDecode(boloRow.data or '') or {}
                    boloRow.data = nil
                end
                triggerMdtViewers("az_mdt:client:boloList", allRows)
                if tostring((((Config.TTS or {}).boloMode) or 'all_onduty')) ~= 'none' then
                    triggerOnDutyClients("az_mdt:client:boloAlert", row)
                end
            end)

            TriggerClientEvent("az_mdt:client:notify", src, {
                type = "success",
                message = ("BOLO #%s created."):format(tostring(insertId))
            })

            logAction(src, "bolo_create", ("BOLO #" .. tostring(insertId)), {
                type  = boloType,
                title = body.title or ""
            })
        end)
    end)
end)

RegisterNetEvent("az_mdt:RequestReports", function()
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    if shouldThrottleInboundMdtRequest(src, 'RequestReports', '', 900, 2000) then
        dprint("RequestReports throttled from", src)
        return
    end
    dprint("RequestReports from", src)

    DB.fetchAll([[
        SELECT id, type, data, created_at
        FROM mdt_reports
        ORDER BY id DESC
        LIMIT 100
    ]], {}, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            row.body = jsonDecode(row.data) or {}
            row.data = nil
        end

        mergeAz5PDLegacyReports(rows, nil, function(mergedRows)
            TriggerClientEvent("az_mdt:client:reportList", src, mergedRows)
        end)
    end)
end)

RegisterNetEvent("az_mdt:CreateReport", function(payload)
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    payload = payload or {}

    local rType = trim(payload.type or payload.reportType or "incident")

    local officerCtx = UnitMeta[src] or {}
    local officerName = getOfficerDisplayLabel(src)
    local officerDiscord = getOfficerDiscordLabel(src)
    local body = {
        title   = trim(payload.title or ""),
        type    = rType,
        info    = trim(payload.info or payload.body or ""),
        officer = officerName
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

            triggerMdtViewers("az_mdt:client:reportCreated", row)

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
            INSERT INTO mdt_id_records (target_type, target_value, rtype, title, description, creator_identifier, creator_discord, timestamp)
            VALUES (?, ?, ?, ?, ?, ?, ?, UNIX_TIMESTAMP())
        ]], {
            targetType,
            targetValue,
            rType,
            body.title or "",
            body.info or "",
            officerName,
            officerDiscord
        })
    end

    if az5pdEnabled() then
        DB.insert(([[
            INSERT INTO %s (creator_identifier, creator_discord, title, description, rtype)
            VALUES (?, ?, ?, ?, ?)
        ]]):format(qAz5pd('reports', 'reports')), {
            officerName,
            officerDiscord,
            body.title or "",
            body.info or "",
            rType
        })
    end
end)

RegisterNetEvent("az_mdt:CreateQuickNote", function(payload)
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
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

local VALID_FLAGS = {
    officer_safety = true,
    armed          = true,
    gang           = true,
    mental_health  = true
}

RegisterNetEvent("az_mdt:SetIdentityFlags", function(payload)
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
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

RegisterNetEvent("az_mdt:CreateWarrant", function(payload)
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
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

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end

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

RegisterNetEvent("az_mdt:AdminDeleteWarrant", function(id)
    local src = source
    id = tonumber(id) or 0

    if not canUseSupervisor(src) then
        denyNoAdmin(src)
        return
    end
    if id <= 0 then return end

    dprint(("AdminDeleteWarrant from %d id=%d"):format(src, id))
    logAction(src, "admin_delete_warrant", tostring(id), {})

    DB.execute("DELETE FROM mdt_warrants WHERE id = ?", { id }, function()
        DB.fetchAll([[
            SELECT id, target_name, target_charid, reason, status,
                   created_by, created_discord, created_at
            FROM mdt_warrants
            ORDER BY id DESC
            LIMIT 200
        ]], {}, function(rows)
            triggerMdtViewers("az_mdt:client:warrantsList", rows or {})
            TriggerClientEvent("az_mdt:client:notify", src, {
                type = "success",
                message = ("Warrant #%s deleted."):format(tostring(id))
            })
        end)
    end)
end)


RegisterNetEvent("az_mdt:RequestThemeSettings", function()
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        TriggerClientEvent('az_mdt:client:themeSettings', src, getThemeState())
        return
    end

    TriggerClientEvent('az_mdt:client:themeSettings', src, getThemeState())
end)

RegisterNetEvent("az_mdt:SaveThemeSettings", function(payload)
    local src = source

    if not canUseAdmin(src) then
        denyNoAdmin(src)
        return
    end

    local actorName = GetPlayerName(src) or ('src ' .. tostring(src))
    saveThemeState(payload or {}, actorName, function(state)
        broadcastThemeState()
        TriggerClientEvent('az_mdt:client:notify', src, {
            type = 'success',
            message = ('Theme updated to %s.'):format((state and state.label) or 'custom theme')
        })
        logAction(src, 'theme_update', (state and state.preset) or 'theme', state and state.vars or {})
    end)
end)

RegisterNetEvent("az_mdt:RequestActionLog", function()
    local src = source

    if not canUseAdmin(src) then
        TriggerClientEvent("az_mdt:client:actionLog", src, {})
        return
    end

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

RegisterNetEvent("az_mdt:ViewEmployees", function()
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        TriggerClientEvent("az_mdt:client:employees", src, {})
        return
    end

    local loader = canUseDispatch(src) and loadDispatchContext or loadOfficerContext
    loader(src, function(ctx)
        if not ctx then
            TriggerClientEvent("az_mdt:client:employees", src, {})
            return
        end

        dprint(("ViewEmployees from %d dept=%s"):format(src, ctx.department or "NONE"))

        if Config.Standalone == false then
            local queryText
            local params
            if ctx.isAdmin then
                queryText = [[
                    SELECT uc.id, uc.name, uc.charid AS identifier, uc.charid, uc.discordid, uc.active_department, ed.paycheck AS grade, uc.license_status
                    FROM user_characters uc
                    LEFT JOIN econ_departments ed
                      ON ed.discordid = uc.discordid
                     AND ed.charid = uc.charid
                     AND ed.department = uc.active_department
                    ORDER BY uc.active_department ASC, uc.name ASC
                ]]
                params = {}
            else
                queryText = [[
                    SELECT uc.id, uc.name, uc.charid AS identifier, uc.charid, uc.discordid, uc.active_department, ed.paycheck AS grade, uc.license_status
                    FROM user_characters uc
                    LEFT JOIN econ_departments ed
                      ON ed.discordid = uc.discordid
                     AND ed.charid = uc.charid
                     AND ed.department = uc.active_department
                    WHERE uc.active_department = ?
                    ORDER BY uc.name ASC
                ]]
                params = { ctx.department }
            end
            DB.fetchAll(queryText, params, function(rows)
                rows = rows or {}
                for _, row in ipairs(rows) do
                    row.callsign = row.callsign or defaultCallsign(row.charid or row.identifier or row.discordid or row.id)
                    row.permissions = employeePermPayloadFromRow({ mdt_role = 'leo' })
                end
                TriggerClientEvent("az_mdt:client:employees", src, rows)
            end)
            return
        end

        local queryText
        local params
        if ctx.isAdmin then
            queryText = ([[
                SELECT id, name, callsign, department AS active_department, grade, discordid, license, identifier, mdt_role, mdt_perms_json
                FROM %s
                WHERE active = 1
                ORDER BY department ASC, name ASC
            ]]):format(qTable('employees'))
            params = {}
        else
            queryText = ([[
                SELECT id, name, callsign, department AS active_department, grade, discordid, license, identifier, mdt_role, mdt_perms_json
                FROM %s
                WHERE active = 1
                  AND department = ?
                ORDER BY name ASC
            ]]):format(qTable('employees'))
            params = { ctx.department }
        end
        DB.fetchAll(queryText, params, function(rows)
            rows = rows or {}
            for _, row in ipairs(rows) do
                row.callsign = row.callsign or defaultCallsign(row.identifier or row.license or row.discordid or row.id)
                row.permissions = employeePermPayloadFromRow(row)
            end
            TriggerClientEvent("az_mdt:client:employees", src, rows)
        end)
    end)
end)

RegisterNetEvent("az_mdt:SaveEmployeeAccess", function(payload)
    local src = source
    if not canUseAdmin(src) then
        denyNoAdmin(src)
        return
    end

    if Config.Standalone == false then
        TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Employee access editing is disabled while Config.Standalone = false.' })
        return
    end

    payload = payload or {}
    local rowId = tonumber(payload.id or payload.employeeId or 0) or 0
    if rowId <= 0 then
        TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Invalid employee selected.' })
        return
    end

    local role = lower(trim(payload.role or 'leo'))
    if role ~= 'leo' and role ~= 'supervisor' and role ~= 'dispatch' and role ~= 'admin' and role ~= 'civ' then
        role = 'leo'
    end

    local perms = {
        loginRole = lower(trim(payload.loginRole or (role == 'dispatch' and 'dispatch' or (role == 'civ' and 'civ' or 'leo')))),
        open = boolish(payload.open),
        admin = boolish(payload.admin),
        supervisor = boolish(payload.supervisor),
        dispatch = boolish(payload.dispatch),
        civ = boolish(payload.civ),
        dmv = boolish(payload.dmv),
        leochat = boolish(payload.leochat),
        pages = decodePermissionMap(payload.pages),
        actions = decodePermissionMap(payload.actions)
    }
    if perms.loginRole ~= 'dispatch' and perms.loginRole ~= 'civ' then perms.loginRole = 'leo' end

    DB.execute(([[
        UPDATE %s
        SET mdt_role = ?, mdt_perms_json = ?, updated_at = CURRENT_TIMESTAMP()
        WHERE id = ?
    ]]):format(qTable('employees')), { role, jsonEncode(perms), rowId }, function()
        logAction(src, 'save_employee_access', tostring(rowId), { role = role, perms = perms })
        DB.fetchAll(([[
            SELECT id, identifier, license, discordid, name, callsign, department, grade, active, mdt_role, mdt_perms_json
            FROM %s
            WHERE id = ?
            LIMIT 1
        ]]):format(qTable('employees')), { rowId }, function(updatedRows)
            refreshOnlineAccessForEmployeeRow(updatedRows and updatedRows[1] or nil)
        end)
        local currentCtx = UnitMeta[src] or {}
        local queryText
        local params
        if canUseAdmin(src) then
            queryText = ([[
                SELECT id, name, callsign, department AS active_department, grade, discordid, license, identifier, mdt_role, mdt_perms_json
                FROM %s
                WHERE active = 1
                ORDER BY department ASC, name ASC
            ]]):format(qTable('employees'))
            params = {}
        else
            queryText = ([[
                SELECT id, name, callsign, department AS active_department, grade, discordid, license, identifier, mdt_role, mdt_perms_json
                FROM %s
                WHERE active = 1 AND department = ?
                ORDER BY name ASC
            ]]):format(qTable('employees'))
            params = { currentCtx.department or Config.DefaultDepartment }
        end
        DB.fetchAll(queryText, params, function(rows)
            rows = rows or {}
            for _, row in ipairs(rows) do
                row.callsign = row.callsign or defaultCallsign(row.identifier or row.license or row.discordid or row.id)
                row.permissions = employeePermPayloadFromRow(row)
            end
            TriggerClientEvent('az_mdt:client:employees', src, rows)
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'success', message = 'Employee MDT access saved.' })
        end)
    end)
end)

RegisterNetEvent("az_mdt:SetUnitStatus", function(status)
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    status = tostring(status or "AVAILABLE")
    dprint(("UnitStatus %d -> %s"):format(src, status))

    setUnitStatus(src, status, UnitMeta[src])
    triggerMdtViewers("az_mdt:client:unitStatus", src, status)
end)

RegisterNetEvent("az_mdt:Panic", function(data)
    local src = source
    data = data or {}

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    if not isPlayerOnDuty(src) then
        TriggerClientEvent("az_mdt:client:notify", src, {
            type = "error",
            message = "You must be on duty to use the panic button."
        })
        return
    end

    dprint("Panic button from", src)

    local ctx = UnitMeta[src] or {}
    local officerName = ctx.name or ("Unit " .. src)
    local coords = data.coords
    if type(coords) ~= 'table' then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local vec = GetEntityCoords(ped)
            if vec then
                coords = { x = vec.x + 0.0, y = vec.y + 0.0, z = vec.z + 0.0 }
            end
        end
    end
    local postal = getNearestPostal(coords)

    setUnitStatus(src, "PANIC", ctx)

    local payload = {
        source   = src,
        officer  = officerName,
        callsign = ctx.callsign or "",
        time     = os.date("%H:%M:%S"),
        coords   = coords or {},
        postal   = postal and postal.code or nil
    }

    triggerOnDutyClients("az_mdt:client:panic", payload)

    for unitSrc, unit in pairs(Units) do
        if unit and isOnDutyStatus(unit.status) then
            TriggerClientEvent("az_mdt:client:notify", unitSrc, {
                type    = "panic",
                message = (postal and postal.code and ("PANIC BUTTON – %s @ Postal %s") or ("PANIC BUTTON – %s")):format(officerName, postal and postal.code or '')
            })
        end
    end

    logAction(src, "panic_button", officerName, { postal = postal and postal.code or nil })
end)

RegisterNetEvent("az_mdt:Hospital", function()
    local src = source

    if not canUseMDT(src) then
        denyNoPermission(src)
        return
    end
    dprint("Hospital button from", src)
    triggerMdtViewers("az_mdt:client:hospital", src)
end)

RegisterNetEvent("az_mdt:RequestUnits", function()
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end

    local currentDepartment = sanitizeDepartmentId(((UnitMeta[src] or {}).department) or resolveCurrentServiceDepartment(src, Config.DefaultDepartment))
        or resolveCurrentServiceDepartment(src, Config.DefaultDepartment)
        or (Config.DefaultDepartment or 'police')
    if Config.UseAzFire == true and sourceHasFireDutyState(src) then
        markFireDutyHold(src, true)
        local existingStatus = upper(trim((Units[src] and Units[src].status) or ''))
        local fireStatus = existingStatus ~= '' and existingStatus or 'AVAILABLE'
        local fireResource = resolveFireBridgeResourceName()
        if fireResource then
            local ok, result = pcall(function()
                return exports[fireResource]:GetResponderMDTStatus(src)
            end)
            if ok and trim(tostring(result or '')) ~= '' then
                local candidate = upper(trim(tostring(result)))
                if candidate ~= 'OFFDUTY' then
                    fireStatus = candidate
                elseif fireStatus == '' or fireStatus == 'OFFDUTY' then
                    fireStatus = 'AVAILABLE'
                    dprint(('Ignoring fire OFFDUTY status during RequestUnits for %s because Fire duty is still active.'):format(tostring(src)))
                end
            end
        end
        if fireStatus == '' or fireStatus == 'OFFDUTY' then fireStatus = 'AVAILABLE' end
        ensureUnitRegisteredForOperationalSource(src, 'fire', fireStatus)
    end

    local arr = {}
    for _, u in pairs(Units) do
        arr[#arr + 1] = u
    end

    TriggerClientEvent("az_mdt:client:unitsSnapshot", src, {
        units = arr
    })
end)



RegisterNetEvent("az_mdt:UpdateUnitLocation", function(payload)
    local src = source
    if not canUseOperationalMDT(src) then return end
    if not Units[src] then return end

    payload = type(payload) == 'table' and payload or {}
    local coords = type(payload.coords) == 'table' and payload.coords or payload
    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z) or 0.0
    if not x or not y then return end

    Units[src].coords = { x = x, y = y, z = z }
    Units[src].heading = tonumber(payload.heading) or tonumber(Units[src].heading) or 0.0
    Units[src].inVehicle = payload.inVehicle == true
    Units[src].vehicleClass = tonumber(payload.vehicleClass) or Units[src].vehicleClass
    Units[src].street = trim(payload.street or Units[src].street or '')
    Units[src].crossStreet = trim(payload.crossStreet or payload.cross_street or Units[src].crossStreet or '')
    Units[src].locationText = trim(payload.locationText or payload.location_text or Units[src].locationText or '')
    Units[src].updatedAt = os.time()
    broadcastUnits()
end)

RegisterNetEvent("az_mdt:SaveLiveMapIcons", function(payload)
    local src = source
    if not canUseAdmin(src) then return end

    loadOfficerContext(src, function(ctx)
        saveLiveMapIconState(payload or {}, function(state)
            broadcastLiveMapState()
            TriggerClientEvent('az_mdt:client:notify', src, {
                type = 'success',
                message = 'LiveMap icons updated.'
            })
            logAction(src, 'live_map_icon_update', (ctx and ctx.name) or tostring(src), state or {})
        end)
    end)
end)
AddEventHandler("playerDropped", function()
    local src = source
    clearMdtViewer(src)
    markFireDutyHold(src, false)
    Units[src]    = nil
    UnitMeta[src] = nil
    AccessCache[src] = nil
    broadcastUnits()
end)

local function composeCallLocation(location, postal)
    location = trim(location or 'Unknown location')
    postal = trim(postal or '')
    if postal ~= '' and not string.find(location, postal, 1, true) then
        location = ('%s | Postal %s'):format(location, postal)
    end
    return location, postal
end

local function createOfficerGeneratedCall(src, opts)
    opts = opts or {}
    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    if not isPlayerOnDuty(src) then
        TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', title = 'Duty Required', message = 'Go on duty before creating calls.' })
        return
    end

    local kind = trim(opts.kind or 'OFFICER CALL')
    local location, postal = composeCallLocation(opts.location or 'Unknown location', opts.postal or '')
    local details = trim(opts.details or opts.message or '')
    local vehicleModel = trim(opts.vehicleModel or '')
    local coords = opts.coords or {}
    local ctx = UnitMeta[src] or {}
    local callerName = (ctx.callsign ~= '' and (ctx.callsign .. ' | ' .. (ctx.name or GetPlayerName(src) or ('Unit ' .. tostring(src)))) or (ctx.name or GetPlayerName(src) or ('Unit ' .. tostring(src))))

    local message = details
    if upper(kind) == 'TRAFFIC STOP' then
        local prefix = vehicleModel ~= '' and ('Traffic Stop • Vehicle: ' .. vehicleModel) or 'Traffic Stop'
        message = prefix .. (details ~= '' and ('\n' .. details) or '')
    elseif upper(kind) ~= '' and upper(kind) ~= 'OFFICER CALL' then
        message = kind .. (details ~= '' and ('\n' .. details) or '')
    end

    if message == '' then
        message = kind
    end

    local id = NextCallId
    NextCallId = NextCallId + 1

    local call = {
        id = id,
        caller = callerName,
        message = message,
        location = location,
        postal = postal ~= '' and postal or nil,
        coords = coords,
        units = { { id = src, name = ctx.name or GetPlayerName(src) or ('Unit ' .. tostring(src)), callsign = ctx.callsign or '' } },
        status = 'ACTIVE',
        type = upper(kind),
        created_at = os.date('%H:%M:%S')
    }

    Calls[id] = call
    ensureCallRoom(id)

    DB.execute([[
        INSERT INTO mdt_calls (call_id, caller, message, location, postal, coords_json, status)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE caller = VALUES(caller), message = VALUES(message), location = VALUES(location), postal = VALUES(postal), coords_json = VALUES(coords_json), status = VALUES(status)
    ]], { id, callerName, message, location, postal ~= '' and postal or nil, jsonEncode(coords), 'ACTIVE' })
    DB.execute([[INSERT INTO mdt_call_units (call_id, unit_source, unit_name, unit_callsign) VALUES (?, ?, ?, ?)]], { id, tostring(src), ctx.name or GetPlayerName(src) or ('Unit ' .. tostring(src)), ctx.callsign or '' })

    TriggerClientEvent('az_mdt:client:notify', src, {
        type = 'success',
        title = upper(kind) == 'TRAFFIC STOP' and 'Traffic Stop Created' or 'Call Created',
        message = ('%s #%d created.'):format(kind, id)
    })

    local notifyMessage = ('%s #%d @ %s'):format(kind, id, location)
    local callMode = tostring((((Config or {}).TTS or {}).callMode or 'all_onduty'))
    for unitSrc, unit in pairs(Units) do
        if unit and isOnDutyStatus(unit.status) then
            TriggerClientEvent('az_mdt:client:notify', unitSrc, {
                type = 'call',
                title = kind,
                message = notifyMessage,
                duration = 6500
            })
            if lower(callMode) == 'all_onduty' then
                TriggerClientEvent('az_mdt:client:newCallAlert', unitSrc, {
                    id = id,
                    caller = callerName,
                    message = message,
                    details = details,
                    reason = message,
                    location = location,
                    postal = postal ~= '' and postal or nil,
                    coords = coords,
                    status = call.status,
                    type = call.type,
                    units = call.units,
                    created_at = call.created_at
                })
            end
        end
    end

    triggerOnDutyClients('az_mdt:client:callUpdated', call)
    TriggerClientEvent('az_mdt:client:callRoomOpened', src, callRoomSnapshot(id))
    logAction(src, 'call_create', ('Call #' .. tostring(id)), { kind = kind, location = location, postal = postal, vehicle = vehicleModel, details = details })
end

RegisterNetEvent('az_mdt:CreateOfficerCall', function(data)
    data = data or {}
    createOfficerGeneratedCall(source, {
        kind = 'Officer Call',
        location = data.location or '',
        postal = data.postal or '',
        details = data.details or data.message or '',
        coords = data.coords or {}
    })
end)

RegisterNetEvent('az_mdt:CreateTrafficStop', function(data)
    data = data or {}
    createOfficerGeneratedCall(source, {
        kind = 'Traffic Stop',
        location = data.location or '',
        postal = data.postal or '',
        details = data.details or data.message or '',
        vehicleModel = data.vehicleModel or data.vehicle or '',
        coords = data.coords or {}
    })
end)

RegisterNetEvent("az_mdt:Create911", function(payload)
    local src = source
    payload = payload or {}

    local callerName = GetPlayerName(src)
    local message    = trim(payload.message or "")
    local location   = trim(payload.location or "Unknown location")
    local coords     = payload.coords or {}
    local requestedService = sanitizeDepartmentId(payload.department or payload.service or '')
    local serviceLabel = prettifyServiceLabel(requestedService or '911')
    local postalInfo = getNearestPostal(coords)
    local postalCode = postalInfo and postalInfo.code or nil

    if postalCode and Config.Postals.includeInCallLocation ~= false and not string.find(location, postalCode, 1, true) then
        location = ("%s | Postal %s"):format(location, postalCode)
    end

    if message == "" then return end

    local id = NextCallId
    NextCallId = NextCallId + 1

    local call = {
        id         = id,
        caller     = callerName,
        message    = message,
        location   = location,
        postal     = postalCode,
        coords     = coords,
        units      = {},
        status     = "PENDING",
        created_at = os.date("%H:%M:%S"),
        type       = requestedService and string.upper(requestedService) or nil,
        service    = requestedService
    }

    Calls[id] = call
    ensureCallRoom(id)

    DB.execute([[
        INSERT INTO mdt_calls (call_id, caller, message, location, postal, coords_json, status)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE caller = VALUES(caller), message = VALUES(message), location = VALUES(location), postal = VALUES(postal), coords_json = VALUES(coords_json), status = VALUES(status)
    ]], { id, callerName, message, location, postalCode, jsonEncode(coords), "PENDING" })

    dprint(("Create911 #%d from %s @ %s: %s"):format(id, callerName, location, message))

    logAction(src, "911_create", ("Call #" .. tostring(id)), {
        location = location,
        postal   = postalCode,
        message  = message
    })

    TriggerClientEvent("az_mdt:client:notify", src, {
        type = "success",
        title = "911 Sent",
        message = ("Your 911 call (#%d) was sent."):format(id)
    })

    local officerMessage = (postalCode and postalCode ~= '' and ("New %s call #%d @ %s (Postal %s)") or ("New %s call #%d @ %s")):format(serviceLabel, id, location, postalCode or '')
    local callMode = tostring((((Config or {}).TTS or {}).callMode or 'all_onduty'))
    for unitSrc, unit in pairs(Units) do
        if unit and isOnDutyStatus(unit.status) and lower(callMode) == 'all_onduty' then
            TriggerClientEvent("az_mdt:client:newCallAlert", unitSrc, {
                id = id,
                caller = callerName,
                message = message,
                details = message,
                reason = message,
                location = location,
                postal = postalCode,
                coords = coords,
                status = call.status,
                type = call.type,
                service = requestedService,
                units = call.units,
                created_at = call.created_at,
                notificationType = 'call',
                notificationTitle = ('New %s Call #%s'):format(serviceLabel, tostring(id)),
                notificationMessage = location ~= '' and message ~= '' and ('%s • %s'):format(location, message) or (location ~= '' and location or message)
            })
        end
    end

    triggerOnDutyClients("az_mdt:client:callUpdated", call)
end)

RegisterNetEvent("az_mdt:RequestCalls", function()
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    TriggerClientEvent("az_mdt:client:callsSnapshot", src, snapshotCalls())
end)

RegisterNetEvent("az_mdt:AttachToCall", function(callId)
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    callId = tonumber(callId) or 0
    local call = Calls[callId]
    if not call then return end

    local ctx = UnitMeta[src] or { name = ("Unit " .. src), callsign = "" }
    local found = false

    for _, u in ipairs(call.units) do
        if tonumber(u.id) == src then
            found = true
            break
        end
    end

    local attachedNow = false
    if not found then
        table.insert(call.units, {
            id       = src,
            name     = ctx.name,
            callsign = ctx.callsign
        })
        DB.execute([[INSERT INTO mdt_call_units (call_id, unit_source, unit_name, unit_callsign) VALUES (?, ?, ?, ?)]], { callId, tostring(src), ctx.name or ("Unit " .. src), ctx.callsign or "" })
        attachedNow = true
    end

    local statusChanged = tostring(call.status or '') ~= "ENROUTE"
    if statusChanged then
        call.status = "ENROUTE"
        DB.execute([[UPDATE mdt_calls SET status = ? WHERE call_id = ?]], { "ENROUTE", callId })
    end
    ensureCallRoom(callId)
    dprint(("AttachToCall #%d by %s"):format(callId, ctx.name or src))

    if attachedNow or statusChanged then
        triggerOnDutyClients("az_mdt:client:callUpdated", call)
    end
    if attachedNow and shouldEmitCallRoomOpened(src, callId, 15000) then
        TriggerClientEvent("az_mdt:client:callRoomOpened", src, callRoomSnapshot(callId))
    end
end)

RegisterNetEvent("az_mdt:DetachFromCall", function(callId)
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    callId = tonumber(callId) or 0
    local call = Calls[callId]
    if not call then return end

    local removed = false
    for i = #call.units, 1, -1 do
        local u = call.units[i]
        if tostring(u.id) == tostring(src) then
            table.remove(call.units, i)
            removed = true
        end
    end

    if removed then
        DB.execute([[DELETE FROM mdt_call_units WHERE call_id = ? AND unit_source = ?]], { callId, tostring(src) })
        clearCallRoomOpenCooldown(src, callId)
        webSyncCallStatus(callId)
        broadcastCalls()
        TriggerClientEvent('az_mdt:client:callRoomOpened', src, callRoomSnapshot(callId))
    end
end)

local VALID_UNIT_STATUSES = { AVAILABLE = true, UNAVAILABLE = true, ENROUTE = true, ONSCENE = true, TRANSPORT = true, HOSPITAL = true, OFFDUTY = true }

RegisterNetEvent("az_mdt:SetOtherUnitStatus", function(data)
    local src = source
    data = data or {}
    if not canManageDispatchConsole(src) then
        denyNoPermission(src)
        return
    end

    local targetId = tonumber(data.targetId or data.id or data.sourceId) or 0
    local status = upper(trim(data.status or 'AVAILABLE'))
    if targetId <= 0 or not VALID_UNIT_STATUSES[status] or not UnitMeta[targetId] then return end

    setUnitStatus(targetId, status, UnitMeta[targetId])
    TriggerClientEvent('az_mdt:client:notify', src, { type = 'success', message = ('Updated unit %s to %s.'):format(targetId, status) })
    TriggerClientEvent('az_mdt:client:notify', targetId, { type = 'info', title = 'Dispatch Update', message = ('Your status was updated to %s by dispatch.'):format(status) })
    logAction(src, 'dispatch_unit_status', tostring(targetId), { status = status })
end)

RegisterNetEvent("az_mdt:DispatchStatusCheck", function(data)
    local src = source
    data = data or {}
    if not canManageDispatchConsole(src) then
        denyNoPermission(src)
        return
    end

    local targetId = tonumber(data.targetId or data.id or data.sourceId) or 0
    if targetId <= 0 or not UnitMeta[targetId] then return end

    local actor = UnitMeta[src] or {}
    local sender = actor.callsign ~= '' and (actor.callsign .. ' | ' .. (actor.name or 'Dispatch')) or (actor.name or 'Dispatch')
    TriggerClientEvent('az_mdt:client:dispatchStatusCheck', targetId, { from = sender, dispatcher = sender, time = os.date('%H:%M:%S') })
    TriggerClientEvent('az_mdt:client:notify', src, { type = 'success', message = ('Status check sent to %s.'):format((UnitMeta[targetId].callsign ~= '' and UnitMeta[targetId].callsign) or (UnitMeta[targetId].name or ('Unit ' .. tostring(targetId)))) })
    logAction(src, 'dispatch_status_check', tostring(targetId), { target = UnitMeta[targetId].callsign or UnitMeta[targetId].name or targetId })
end)

RegisterNetEvent("az_mdt:SetCallWaypoint", function(callId)
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    callId = tonumber(callId) or 0
    local call = Calls[callId]
    if not call or not call.coords or not call.coords.x or not call.coords.y then return end

    TriggerClientEvent("az_mdt:client:setWaypoint", src, call.coords)
end)

local ChatHistory = {}
local CHAT_MAX    = 100

local function pushChatMessage(msg, skipDb)

    ChatHistory[#ChatHistory + 1] = msg
    if #ChatHistory > CHAT_MAX then
        table.remove(ChatHistory, 1)
    end

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

        for i = #rows, 1, -1 do
            local r = rows[i]
            pushChatMessage({
                sender  = r.sender  or "Unknown",
                source  = r.source  or "",
                message = r.message or "",
                time    = r.time    or ""
            }, true)
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

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
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

    pushChatMessage(payload, false)

    triggerMdtViewers("az_mdt:client:liveChatMessage", payload)
end)

RegisterNetEvent("az_mdt:RequestChatHistory", function()
    local src = source

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    TriggerClientEvent("az_mdt:client:liveChatHistory", src, ChatHistory)
end)

RegisterNetEvent("az_mdt:SearchReports", function(data)
    local src = source
    data = data or {}

    if not (canUseOperationalMDT(src) or canUseCiv(src)) then
        denyNoPermission(src)
        return
    end

    local query = trim(data.query or data.term or "")
    local reportId = tonumber(query) or 0
    local like = ("%%%s%%"):format(query)

    DB.fetchAll([[
        SELECT id, type, data, created_at
        FROM mdt_reports
        WHERE (? = '' OR id = ? OR data LIKE ? OR type LIKE ?)
        ORDER BY id DESC
        LIMIT 100
    ]], { query, reportId, like, like }, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            row.body = jsonDecode(row.data) or {}
            row.data = nil
        end
        TriggerClientEvent("az_mdt:client:reportSearchResults", src, rows)
    end)
end)

RegisterNetEvent("az_mdt:CreateCivilian", function(payload)
    local src = source
    payload = payload or {}

    if not (canUseCiv(src) or canUseDMV(src) or canUseAdmin(src)) then
        denyNoPermission(src)
        return
    end

    local ident = getCharacter(src)
    local name = trim(payload.name or payload.fullName or "")
    if name == "" then return end

    local metadata = {
        dob = trim(payload.dob or ""),
        phone = trim(payload.phone or Config.CivilianDefaults.phone or "Unknown"),
        address = trim(payload.address or Config.CivilianDefaults.address or "Unknown")
    }
    local licenseStatus = trim(payload.licenseStatus or Config.CivilianDefaults.licenseStatus or 'valid')

    DB.insert(([[
        INSERT INTO %s (name, charid, discordid, license, license_status, metadata)
        VALUES (?, ?, ?, ?, ?, ?)
    ]]):format(qTable('citizens')), {
        name,
        ident.charid,
        ident.discordid,
        ident.license,
        licenseStatus,
        jsonEncode(metadata)
    }, function(insertId)
        TriggerClientEvent("az_mdt:client:notify", src, {
            type = "success",
            message = ("Civilian profile created for %s (#%s)." ):format(name, tostring(insertId or 0))
        })
        logAction(src, "civilian_create", name, metadata)
    end)
end)

RegisterNetEvent("az_mdt:SearchCivilianRegistry", function(data)
    local src = source
    data = data or {}

    if not canUseCiv(src) then
        denyNoPermission(src)
        return
    end

    local term = trim(data.term or data.name or "")
    if term == '' then
        TriggerClientEvent("az_mdt:client:civilianRegistry", src, {})
        return
    end
    local like = ("%%%s%%"):format(term)

    if frameworkModeEnabled() then
        fetchFrameworkCitizensByWhere('(uc.name LIKE ? OR uc.charid LIKE ? OR uc.discordid LIKE ?)', { like, like, like }, function(rows)
            rows = rows or {}
            for _, row in ipairs(rows) do
                row.metadata = type(row.metadata) == 'table' and row.metadata or (jsonDecode(row.metadata) or {})
            end
            TriggerClientEvent("az_mdt:client:civilianRegistry", src, rows)
        end, 'LIMIT 100')
        return
    end

    DB.fetchAll(([[
        SELECT id, name, charid, discordid, license, license_status, metadata, created_at
        FROM %s
        WHERE (name LIKE ? OR charid LIKE ? OR discordid LIKE ? OR license LIKE ?)
        ORDER BY id DESC
        LIMIT 100
    ]]):format(qTable('citizens')), { like, like, like, like }, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            row.metadata = jsonDecode(row.metadata) or {}
        end
        TriggerClientEvent("az_mdt:client:civilianRegistry", src, rows)
    end)
end)

RegisterNetEvent("az_mdt:SearchDMV", function(data)
    local src = source
    data = data or {}

    if not (canUseCiv(src) or canUseDMV(src) or canUseMDT(src)) then
        denyNoPermission(src)
        return
    end

    local term = trim(data.term or data.name or data.plate or "")
    if term == '' then
        TriggerClientEvent("az_mdt:client:dmvResults", src, {})
        return
    end
    local like = ("%%%s%%"):format(term)

    if frameworkModeEnabled() then
        fetchFrameworkCitizensByWhere('(uc.name LIKE ? OR uc.charid LIKE ? OR uc.discordid LIKE ?)', { like, like, like }, function(rows)
            rows = rows or {}
            enrichCitizenRowsWithAssets(rows, function(enrichedRows)
                for _, row in ipairs(enrichedRows or rows) do
                    row.metadata = type(row.metadata) == 'table' and row.metadata or (jsonDecode(row.metadata) or {})
                    row.vehicle_count = tonumber(row.vehicle_count) or #((row.vehicles) or {})
                    row.weapon_count = tonumber(row.weapon_count) or #((row.weapons) or {})
                end
                TriggerClientEvent("az_mdt:client:dmvResults", src, enrichedRows or rows)
            end)
        end, 'LIMIT 100')
        return
    end

    DB.fetchAll(([[
        SELECT c.id, c.name, c.charid, c.discordid, c.license, c.license_status, c.metadata, c.created_at
        FROM %s c
        WHERE (
            c.name LIKE ?
            OR c.charid LIKE ?
            OR c.license LIKE ?
            OR EXISTS (
                SELECT 1
                FROM %s v
                WHERE LOWER(v.plate) LIKE ?
                  AND (
                    (c.charid IS NOT NULL AND c.charid != '' AND v.owner_identifier = c.charid)
                    OR ((c.charid IS NULL OR c.charid = '') AND c.license IS NOT NULL AND c.license != '' AND v.owner_identifier = c.license)
                    OR v.owner_identifier = CAST(c.id AS CHAR)
                  )
            )
        )
        ORDER BY c.name ASC
        LIMIT 100
    ]]):format(qTable('citizens'), qTable('vehicles')), { like, like, like, like }, function(rows)
        rows = rows or {}
        enrichCitizenRowsWithAssets(rows, function(enrichedRows)
            for _, row in ipairs(enrichedRows or rows) do
                row.metadata = type(row.metadata) == 'table' and row.metadata or (jsonDecode(row.metadata) or {})
                row.vehicle_count = tonumber(row.vehicle_count) or #((row.vehicles) or {})
                row.weapon_count = tonumber(row.weapon_count) or #((row.weapons) or {})
            end
            TriggerClientEvent("az_mdt:client:dmvResults", src, enrichedRows or rows)
        end)
    end)
end)

RegisterNetEvent("az_mdt:RequestMyCivilians", function()
    local src = source
    if not canUseCiv(src) then
        denyNoPermission(src)
        return
    end

    fetchOwnedCivilians(src, function(rows)
        TriggerClientEvent('az_mdt:client:myCivilians', src, rows or {})
    end)
end)

RegisterNetEvent("az_mdt:RequestWebLinkCode", function()
    local src = source
    if not (canUseOperationalMDT(src) or canUseCiv(src)) then
        denyNoPermission(src)
        return
    end

    local ident = getCharacter(src)
    local currentCtx = UnitMeta[src] or {}
    local role = trim(currentCtx.role or '')
    if role == '' then
        if canUseDispatch(src) then role = 'dispatch' elseif canUseMDT(src) then role = 'leo' else role = 'civ' end
    end
    local department = currentCtx.department or (role == 'dispatch' and ((((Config.Dispatch or {}).defaultDepartment) or Config.DefaultDepartment or 'dispatch'))) or (role == 'leo' and (Config.DefaultDepartment or 'police')) or ((Config.Roles and Config.Roles.civilianDepartment) or 'civilian')
    local playerName = (currentCtx.name or GetPlayerName(src) or ('Player ' .. tostring(src)))
    local code = randomLinkCode()
    local expiresAt = webSqlNow(webLinkCodeTtl())
    local siteUrl = webConfiguredBaseUrl()
    if siteUrl == '' then
        siteUrl = ('http://YOUR_SERVER_IP:30120/%s/'):format(RESOURCE_NAME)
    end

    DB.execute([[DELETE FROM mdt_web_link_codes WHERE expires_at < NOW()]], {})
    DB.execute([[
        INSERT INTO mdt_web_link_codes (
            code, player_name, license, charid, identifier, player_discord,
            role, department, created_at, expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            player_name = VALUES(player_name),
            license = VALUES(license),
            charid = VALUES(charid),
            identifier = VALUES(identifier),
            player_discord = VALUES(player_discord),
            role = VALUES(role),
            department = VALUES(department),
            created_at = VALUES(created_at),
            expires_at = VALUES(expires_at),
            used_at = NULL,
            used_by_discord = NULL
    ]], {
        code,
        playerName,
        ident.license,
        ident.charid,
        ident.identifier,
        ident.discordid,
        role,
        department,
        webSqlNow(0),
        expiresAt
    }, function()
        TriggerClientEvent("az_mdt:client:webLinkCode", src, {
            code = code,
            websiteUrl = siteUrl,
            expiresInMinutes = math.max(1, math.floor(webLinkCodeTtl() / 60)),
            title = 'Website Link Code'
        })
        TriggerClientEvent("az_mdt:client:notify", src, {
            type = 'success',
            title = 'Website Link',
            message = ('Link code %s created. Open the website and enter it after Discord login.'):format(code),
            duration = 9000
        })
    end)
end)

RegisterNetEvent("az_mdt:CreateCivilianVehicle", function(data)
    local src = source
    data = data or {}

    if not (canUseCiv(src) or canUseDMV(src) or canUseAdmin(src)) then
        denyNoPermission(src)
        return
    end

    local rowId = tonumber(data.civilianId or data.id) or 0
    local plate = trim(data.plate or ''):upper()
    local model = trim(data.model or data.vehicle or '')
    if rowId <= 0 or plate == '' then return end

    DB.fetchAll(([[
        SELECT id, name, charid, discordid, license
        FROM %s
        WHERE id = ?
        LIMIT 1
    ]]):format(qTable('citizens')), { rowId }, function(rows)
        local row = rows and rows[1] or nil
        if not row then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Civilian not found.' })
            return
        end
        if not canUseDMV(src) and not isCivilianOwnedBy(src, row) then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'You can only register vehicles to civilians you own.' })
            return
        end

        registerVehicleForCitizenRow(src, row, plate, model, function()
            TriggerClientEvent('az_mdt:client:notify', src, {
                type = 'success',
                message = ('Vehicle %s registered to %s.'):format(plate, row.name or ('#' .. tostring(rowId)))
            })
            logAction(src, 'civilian_vehicle_register', row.name or tostring(rowId), { plate = plate, model = model })
        end)
    end)
end)

RegisterNetEvent("az_mdt:RegisterCivilianWeapon", function(data)
    local src = source
    data = data or {}

    if not (canUseCiv(src) or canUseDMV(src) or canUseAdmin(src)) then
        denyNoPermission(src)
        return
    end

    local rowId = tonumber(data.civilianId or data.id) or 0
    local requestedSerial = trim(data.serial or ''):upper()
    local weaponType = trim(data.weaponType or data.type or '')
    if rowId <= 0 then return end

    DB.fetchAll(([[
        SELECT id, name, charid, discordid, license
        FROM %s
        WHERE id = ?
        LIMIT 1
    ]]):format(qTable('citizens')), { rowId }, function(rows)
        local row = rows and rows[1] or nil
        if not row then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Civilian not found.' })
            return
        end
        if not canUseDMV(src) and not isCivilianOwnedBy(src, row) then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'You can only register weapons to civilians you own.' })
            return
        end

        resolveWeaponSerial(requestedSerial, function(serial, regenerated)
            local ident = getCharacter(src)
            local ownerIdentifier = trim(row.charid or '')
            if ownerIdentifier == '' then ownerIdentifier = trim(row.license or '') end
            if ownerIdentifier == '' then ownerIdentifier = tostring(row.id) end

            DB.execute(([[
                INSERT INTO %s (serial, type, owner, owner_name, owner_identifier, discordid)
                VALUES (?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                    type = VALUES(type),
                    owner = VALUES(owner),
                    owner_name = VALUES(owner_name),
                    owner_identifier = VALUES(owner_identifier),
                    discordid = VALUES(discordid)
            ]]):format(qTable('weapons')), { serial, weaponType, row.name or 'Unknown', row.name or 'Unknown', ownerIdentifier, ident.discordid }, function()
                TriggerClientEvent('az_mdt:client:notify', src, {
                    type = 'success',
                    message = regenerated
                        and ('Weapon registered to %s with generated serial %s.'):format(row.name or ('#' .. tostring(rowId)), serial)
                        or ('Weapon %s registered to %s.'):format(serial, row.name or ('#' .. tostring(rowId)))
                })
                logAction(src, 'civilian_weapon_register', row.name or tostring(rowId), { serial = serial, weapon = weaponType, regenerated = regenerated and true or false })
            end)
        end)
    end)
end)

RegisterNetEvent("az_mdt:DeleteQuickNote", function(data)
    local src = source
    data = data or {}

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end

    local noteId = tonumber(data.id) or 0
    if noteId <= 0 then return end

    DB.execute([[DELETE FROM mdt_quick_notes WHERE id = ?]], { noteId }, function()
        TriggerClientEvent('az_mdt:client:notify', src, {
            type = 'success',
            message = 'Quick note deleted.'
        })
        logAction(src, 'quick_note_delete', tostring(noteId), {})
    end)
end)

RegisterNetEvent("az_mdt:UpdateUnitProfile", function(data)
    local src = source
    data = data or {}

    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end

    local ctx = UnitMeta[src] or {}
    local department = sanitizeDepartmentId(data.department or ctx.department)
    local name = trim(data.name or ctx.name or GetPlayerName(src) or ('Officer ' .. tostring(src)))
    if #name > 48 then name = name:sub(1, 48) end
    local callsign = tostring(data.callsign or ctx.callsign or '')
    callsign = trim(callsign)

    if not department then
        TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Invalid department.' })
        return
    end

    ctx.department = department
    ctx.name = name ~= '' and name or (ctx.name or GetPlayerName(src) or ('Officer ' .. tostring(src)))
    ctx.callsign = callsign
    UnitMeta[src] = attachUiSettings(ctx)

    if Units[src] then
        Units[src].department = department
        Units[src].name = ctx.name
        Units[src].callsign = callsign
    else
        local desiredStatus = upper(trim(ctx.status or Config.Duty.defaultStatus or 'OFFDUTY'))
        if desiredStatus ~= 'OFFDUTY' then
            setUnitStatus(src, desiredStatus, ctx)
        end
    end

    persistOfficerUnitProfile(src, ctx, function(saved)
        if saved then
            syncWebLinkedOfficerProfile(saved.discordid, saved)
        end
    end)
    broadcastUnits()

    TriggerClientEvent('az_mdt:client:unitProfileUpdated', src, UnitMeta[src])
    TriggerClientEvent('az_mdt:client:notify', src, {
        type = 'success',
        message = 'Unit profile updated.'
    })
end)

RegisterNetEvent("az_mdt:UpdateDMVStatus", function(data)
    local src = source
    data = data or {}
    if not canUseDMV(src) then
        denyNoAdmin(src)
        return
    end

    local rowId = tonumber(data.id) or 0
    local status = trim(data.status or '')
    if rowId <= 0 or status == '' then return end

    DB.execute(([[
        UPDATE %s SET license_status = ? WHERE id = ?
    ]]):format(qTable('citizens')), { status, rowId }, function()
        TriggerClientEvent("az_mdt:client:notify", src, {
            type = "success",
            message = "DMV status updated."
        })
        logAction(src, 'dmv_update', tostring(rowId), { status = status })
    end)
end)

RegisterNetEvent("az_mdt:CreateCivilianReport", function(data)
    local src = source
    data = data or {}
    if not canUseCiv(src) then
        denyNoPermission(src)
        return
    end

    local ident = getCharacter(src)
    local title = trim(data.title or '')
    local body = trim(data.body or data.description or '')
    local rtype = trim(data.reportType or data.type or 'civilian')
    local citizenName = trim(data.citizenName or GetPlayerName(src) or '')
    if title == '' and body == '' then return end

    DB.insert([[
        INSERT INTO mdt_civilian_reports (title, report_type, body, citizen_name, citizen_identifier)
        VALUES (?, ?, ?, ?, ?)
    ]], { title, rtype, body, citizenName, ident.charid ~= '' and ident.charid or ident.identifier }, function(insertId)
        TriggerClientEvent("az_mdt:client:notify", src, {
            type = "success",
            message = ("Civilian report submitted (#%s)." ):format(tostring(insertId or 0))
        })
        logAction(src, 'civilian_report_create', title ~= '' and title or ('report #' .. tostring(insertId or 0)), { type = rtype })
    end)
end)

RegisterNetEvent('az_mdt:DeleteCivilianVehicle', function(data)
    local src = source
    data = data or {}
    local assetId = tonumber(data.id) or 0
    local civilianId = tonumber(data.civilianId) or 0
    if assetId <= 0 or civilianId <= 0 then return end
    if not (canUseCiv(src) or canUseDMV(src) or canUseAdmin(src)) then
        denyNoPermission(src)
        return
    end

    DB.fetchAll(([[
        SELECT id, name, charid, discordid, license
        FROM %s
        WHERE id = ?
        LIMIT 1
    ]]):format(qTable('citizens')), { civilianId }, function(rows)
        local citizen = rows and rows[1] or nil
        if not citizen then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Civilian not found.' })
            return
        end
        if not canUseDMV(src) and not canUseAdmin(src) and not isCivilianOwnedBy(src, citizen) then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'You can only remove vehicles from civilians you own.' })
            return
        end
        local ownerKeys = citizenOwnerKeys(citizen)
        if #ownerKeys == 0 then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'This civilian has no removable vehicle ownership keys.' })
            return
        end
        DB.fetchAll(([[
            SELECT id, plate, owner_identifier
            FROM %s
            WHERE id = ?
            LIMIT 1
        ]]):format(qTable('vehicles')), { assetId }, function(vRows)
            local vehicle = vRows and vRows[1] or nil
            if not vehicle then
                TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Vehicle not found.' })
                return
            end
            local ok = false
            for _, key in ipairs(ownerKeys) do if tostring(key) == tostring(vehicle.owner_identifier or '') then ok = true break end end
            if not ok then
                TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'That vehicle is not registered to the selected civilian.' })
                return
            end
            DB.execute(([[
                DELETE FROM %s WHERE id = ?
            ]]):format(qTable('vehicles')), { assetId }, function()
                TriggerClientEvent('az_mdt:client:notify', src, { type = 'success', message = ('Vehicle %s removed.'):format(vehicle.plate or ('#' .. tostring(assetId))) })
                logAction(src, 'civilian_vehicle_remove', citizen.name or tostring(civilianId), { plate = vehicle.plate, civilianId = civilianId })
            end)
        end)
    end)
end)

RegisterNetEvent('az_mdt:DeleteCivilianWeapon', function(data)
    local src = source
    data = data or {}
    local assetId = tonumber(data.id) or 0
    local civilianId = tonumber(data.civilianId) or 0
    if assetId <= 0 or civilianId <= 0 then return end
    if not (canUseCiv(src) or canUseDMV(src) or canUseAdmin(src)) then
        denyNoPermission(src)
        return
    end

    DB.fetchAll(([[
        SELECT id, name, charid, discordid, license
        FROM %s
        WHERE id = ?
        LIMIT 1
    ]]):format(qTable('citizens')), { civilianId }, function(rows)
        local citizen = rows and rows[1] or nil
        if not citizen then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Civilian not found.' })
            return
        end
        if not canUseDMV(src) and not canUseAdmin(src) and not isCivilianOwnedBy(src, citizen) then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'You can only remove weapons from civilians you own.' })
            return
        end
        local ownerKeys = citizenOwnerKeys(citizen)
        if #ownerKeys == 0 then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'This civilian has no removable weapon ownership keys.' })
            return
        end
        DB.fetchAll(([[
            SELECT id, serial, owner_identifier
            FROM %s
            WHERE id = ?
            LIMIT 1
        ]]):format(qTable('weapons')), { assetId }, function(wRows)
            local weapon = wRows and wRows[1] or nil
            if not weapon then
                TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Weapon not found.' })
                return
            end
            local ok = false
            for _, key in ipairs(ownerKeys) do if tostring(key) == tostring(weapon.owner_identifier or '') then ok = true break end end
            if not ok then
                TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'That weapon is not registered to the selected civilian.' })
                return
            end
            DB.execute(([[
                DELETE FROM %s WHERE id = ?
            ]]):format(qTable('weapons')), { assetId }, function()
                TriggerClientEvent('az_mdt:client:notify', src, { type = 'success', message = ('Weapon %s removed.'):format(weapon.serial or ('#' .. tostring(assetId))) })
                logAction(src, 'civilian_weapon_remove', citizen.name or tostring(civilianId), { serial = weapon.serial, civilianId = civilianId })
            end)
        end)
    end)
end)

RegisterNetEvent("az_mdt:DeleteCivilian", function(data)
    local src = source
    data = data or {}

    if not canUseCiv(src) and not canUseAdmin(src) then
        denyNoPermission(src)
        return
    end

    local rowId = tonumber(data.id) or 0
    if rowId <= 0 then return end

    local ident = getCharacter(src)
    DB.fetchAll(([[
        SELECT id, name, charid, discordid, license
        FROM %s
        WHERE id = ?
        LIMIT 1
    ]]):format(qTable('citizens')), { rowId }, function(rows)
        local row = rows and rows[1] or nil
        if not row then
            TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Civilian not found.' })
            return
        end

        local ownsRow = (row.charid ~= nil and row.charid ~= '' and row.charid == ident.charid)
            or (row.license ~= nil and row.license ~= '' and row.license == ident.license)
            or (row.discordid ~= nil and row.discordid ~= '' and row.discordid == ident.discordid)

        if not canUseAdmin(src) and not ownsRow then
            TriggerClientEvent('az_mdt:client:notify', src, {
                type = 'error',
                message = 'You can only delete civilian records you own.'
            })
            return
        end

        local cleanupQueries = buildCivilianDeleteQueries(row)
        runQueriesSequentially(cleanupQueries, 1, function()
            DB.execute(([[
                DELETE FROM %s WHERE id = ?
            ]]):format(qTable('citizens')), { rowId }, function()
                TriggerClientEvent('az_mdt:client:notify', src, {
                    type = 'success',
                    message = ('Civilian %s deleted.'):format(row.name or ('#' .. tostring(rowId)))
                })
                logAction(src, 'civilian_delete', row.name or tostring(rowId), { id = rowId, owned = ownsRow, cascaded = #cleanupQueries })
            end)
        end)
    end)
end)

RegisterNetEvent("az_mdt:SetDutyState", function(data)
    local src = source
    data = data or {}
    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end

    local onDuty = data.onDuty == true
    local status = onDuty and 'AVAILABLE' or 'OFFDUTY'
    local ctx = UnitMeta[src] or buildFallbackOperationalContext(src, resolveCurrentServiceDepartment(src, Config.DefaultDepartment))
    local department = sanitizeDepartmentId(data.department or '')
        or resolveCurrentServiceDepartment(src, data.department or ctx.department or Config.DefaultDepartment)
        or sanitizeDepartmentId(ctx.department or '')
        or (Config.DefaultDepartment or 'police')
    ctx.department = department
    if trim(ctx.role or '') == '' then ctx.role = canUseDispatch(src) and 'dispatch' or 'leo' end
    if ctx.isLEO == nil then ctx.isLEO = true end
    UnitMeta[src] = attachUiSettings(ctx)

    if department == 'fire' then
        markFireDutyHold(src, onDuty)
        local fireResource = resolveFireBridgeResourceName()
        if fireResource then
            pcall(function()
                exports[fireResource]:SetDutyStateFromExternal(src, onDuty, true)
            end)
        end
    elseif department == 'ems' then
        local ambulanceResource = resolveAmbulanceBridgeResourceName()
        if ambulanceResource then
            pcall(function()
                exports[ambulanceResource]:SetDutyStateFromExternal(src, onDuty, ctx)
            end)
        end
    elseif department == 'ranger' then
        local rangerResource = resolveParkRangerBridgeResourceName()
        if rangerResource then
            pcall(function()
                exports[rangerResource]:SetDutyStateFromExternal(src, onDuty, ctx)
            end)
        end
    else
        local policeResource = resolvePoliceBridgeResourceName()
        if policeResource then
            pcall(function()
                exports[policeResource]:SetDutyStateFromExternal(src, onDuty, ctx)
            end)
        end
    end

    setUnitStatus(src, status, ctx)

    if department == 'fire' and onDuty then
        SetTimeout(750, function()
            if GetPlayerPing(src) > 0 and sourceHasFireDutyState(src) then
                ensureUnitRegisteredForOperationalSource(src, 'fire', 'AVAILABLE')
            end
        end)
    end

    TriggerClientEvent('az_mdt:client:notify', src, {
        type = 'success',
        message = onDuty and 'You are now on duty.' or 'You are now off duty.'
    })
end)

RegisterNetEvent("az_mdt:RequestLeoChat", function()
    local src = source
    if not canUseLeoChat(src) then
        denyNoPermission(src)
        return
    end
    TriggerClientEvent('az_mdt:client:leoChatHistory', src, LeoDutyChat)
end)

RegisterNetEvent("az_mdt:LeoChatSend", function(data)
    local src = source
    data = data or {}
    if not canUseLeoChat(src) then
        denyNoPermission(src)
        return
    end
    local unit = Units[src]
    if not unit or (unit.status or '') == 'OFFDUTY' then
        TriggerClientEvent('az_mdt:client:notify', src, {
            type = 'error',
            message = 'Go on duty before using LEO chat.'
        })
        return
    end

    local msgText = trim(data.message or '')
    if msgText == '' then return end
    local ctx = UnitMeta[src] or {}
    local payload = {
        sender = (ctx.callsign ~= '' and (ctx.callsign .. ' | ' .. (ctx.name or '')) or (ctx.name or ('Unit ' .. src))),
        source = ctx.callsign or tostring(src),
        message = msgText,
        time = os.date('%H:%M:%S')
    }
    pushLeoDutyChat(payload)
    triggerMdtViewers('az_mdt:client:leoChatMessage', payload)
end)

RegisterNetEvent("az_mdt:RequestCallRoom", function(data)
    local src = source
    data = data or {}
    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end

    local callId = tonumber(data.callId or data.id) or 0
    if callId <= 0 then return end
    local room = ensureCallRoom(callId)

    DB.fetchAll([[SELECT sender, source, message, time FROM mdt_call_messages WHERE call_id = ? ORDER BY id ASC LIMIT 200]], { callId }, function(messages)
        DB.fetchAll([[SELECT author, note, created_at FROM mdt_call_notes WHERE call_id = ? ORDER BY id ASC LIMIT 200]], { callId }, function(notes)
            room.messages = messages or {}
            room.notes = notes or {}
            TriggerClientEvent('az_mdt:client:callRoomOpened', src, callRoomSnapshot(callId))
        end)
    end)
end)

RegisterNetEvent("az_mdt:CallRoomSend", function(data)
    local src = source
    data = data or {}
    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    local callId = tonumber(data.callId or data.id) or 0
    local msgText = trim(data.message or '')
    if callId <= 0 or msgText == '' then return end

    local ctx = UnitMeta[src] or {}
    local payload = {
        callId = callId,
        sender = (ctx.callsign ~= '' and (ctx.callsign .. ' | ' .. (ctx.name or '')) or (ctx.name or ('Unit ' .. src))),
        source = ctx.callsign or tostring(src),
        message = msgText,
        time = os.date('%H:%M:%S')
    }
    local room = ensureCallRoom(callId)
    room.messages[#room.messages + 1] = payload
    DB.insert([[INSERT INTO mdt_call_messages (call_id, sender, source, message, time) VALUES (?, ?, ?, ?, ?)]], { callId, payload.sender, payload.source, payload.message, payload.time })
    triggerOnDutyClients('az_mdt:client:callRoomMessage', payload)
end)

RegisterNetEvent("az_mdt:CallRoomNote", function(data)
    local src = source
    data = data or {}
    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end
    local callId = tonumber(data.callId or data.id) or 0
    local noteText = trim(data.note or '')
    if callId <= 0 or noteText == '' then return end

    local ctx = UnitMeta[src] or {}
    local payload = {
        callId = callId,
        author = (ctx.callsign ~= '' and (ctx.callsign .. ' | ' .. (ctx.name or '')) or (ctx.name or ('Unit ' .. src))),
        note = noteText,
        created_at = os.date('%Y-%m-%d %H:%M:%S')
    }
    local room = ensureCallRoom(callId)
    room.notes[#room.notes + 1] = payload
    DB.insert([[INSERT INTO mdt_call_notes (call_id, author, note) VALUES (?, ?, ?)]], { callId, payload.author, payload.note })
    triggerOnDutyClients('az_mdt:client:callRoomNote', payload)
end)

RegisterNetEvent("az_mdt:SearchCallHistory", function(data)
    local src = source
    data = data or {}
    if not canUseOperationalMDT(src) then
        denyNoPermission(src)
        return
    end

    local query = trim(data.query or data.term or '')
    if query == '' then
        TriggerClientEvent('az_mdt:client:callHistoryResults', src, {})
        return
    end
    local callId = tonumber(query) or 0
    local like = ("%%%s%%"):format(query)

    DB.fetchAll([[
        SELECT call_id, caller, message, location, postal, status, created_at, updated_at
        FROM mdt_calls
        WHERE (call_id = ? OR caller LIKE ? OR location LIKE ? OR message LIKE ? OR postal LIKE ?)
        ORDER BY call_id DESC
        LIMIT 100
    ]], { callId, like, like, like, like }, function(rows)
        TriggerClientEvent('az_mdt:client:callHistoryResults', src, rows or {})
    end)
end)

RegisterNetEvent("az_mdt:AdminDeleteBolo", function(id)
    local src = source

    if not canUseSupervisor(src) then
        denyNoAdmin(src)
        return
    end
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
            triggerMdtViewers("az_mdt:client:boloList", rows)
        end)
    end)
end)

RegisterNetEvent("az_mdt:AdminDeleteReport", function(id)
    local src = source

    if not canUseAdmin(src) then
        denyNoAdmin(src)
        return
    end
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
            triggerMdtViewers("az_mdt:client:reportList", rows)
        end)
    end)
end)

RegisterNetEvent("az_mdt:AdminDeleteCall", function(id)
    local src = source

    if not canUseSupervisor(src) then
        denyNoAdmin(src)
        return
    end
    id = tonumber(id) or 0
    if id <= 0 then return end
    if not Calls[id] then return end

    dprint(("AdminDeleteCall from %d id=%d"):format(src, id))
    logAction(src, "admin_delete_call", tostring(id), {})

    Calls[id] = nil
    CallRooms[id] = nil
    DB.execute([[UPDATE mdt_calls SET status = ? WHERE call_id = ?]], { "CLEARED", id })
    DB.execute([[DELETE FROM mdt_call_units WHERE call_id = ?]], { id })
    broadcastCalls()
end)

RegisterNetEvent("az_mdt:AdminDeleteEmployee", function(payload)
    local src = source
    payload = payload or {}

    if not canUseAdmin(src) then
        denyNoAdmin(src)
        return
    end

    local rowId = tonumber(payload.id) or 0
    local dept  = trim(payload.department or "")

    if rowId <= 0 or dept == "" then return end

    dprint(("AdminDeleteEmployee from %d rowId=%d dept=%s"):format(src, rowId, dept))
    logAction(src, "admin_delete_employee", dept .. ":" .. tostring(rowId), {})

    DB.execute(([[DELETE FROM %s WHERE id = ? AND department = ?]]):format(qTable('employees')), { rowId, dept }, function()
        DB.fetchAll(([[
            SELECT id, name, callsign, department AS active_department, grade, discordid, license, identifier
            FROM %s
            WHERE active = 1 AND department = ?
            ORDER BY name ASC
        ]]):format(qTable('employees')), { dept }, function(rows)
            rows = rows or {}
            for _, row in ipairs(rows) do
                row.callsign = row.callsign or defaultCallsign(row.identifier or row.license or row.discordid or row.id)
            end
            triggerMdtViewers("az_mdt:client:employees", rows)
        end)
    end)
end)

RegisterNetEvent("az_mdt:OpenExternal", function(payload)
    local src = source
    payload = payload or {}
    if not canUseMDT(src) then
        denyNoPermission(src)
        return
    end
    refreshSourceAccess(src, function(access)
        local wantsDispatch = lower(trim(payload.role or '')) == 'dispatch'
        local loader = (wantsDispatch and canUseDispatch(src)) and loadDispatchContext or loadOfficerContext
        loader(src, function(ctx)
            if not ctx then
                TriggerClientEvent('az_mdt:client:notify', src, { type = 'error', message = 'Unable to load your MDT profile.' })
                return
            end
            local existingStatus = resolveOpenUnitStatus(src, ctx, ctx.status or Config.Duty.defaultStatus or 'OFFDUTY')
            ctx.status = existingStatus
            UnitMeta[src] = ctx
            ctx.status = syncOperationalUnitForOpen(src, ctx, existingStatus, ctx.department)
            if ctx.charid then updateLastSeen(ctx.charid) end
            TriggerClientEvent('az_mdt:client:openExternal', src, ctx, payload)
            TriggerClientEvent('az_mdt:client:callsSnapshot', src, snapshotCalls())
            broadcastUnits()
        end)
    end)
end)

local function resolveExternalBridgeResourceName(names)
    if type(names) ~= 'table' then return nil end
    for _, name in ipairs(names) do
        name = trim(name or '')
        if name ~= '' then
            local state = GetResourceState(name)
            if state == 'started' or state == 'starting' then
                return name
            end
        end
    end
    return nil
end

resolveFireBridgeResourceName = function()
    if Config.UseAzFire ~= true then return nil end
    return resolveExternalBridgeResourceName(((Config.AzFire or {}).ResourceNames) or { 'Az-Fire', 'az_fire', 'az-fire' })
end

resolveAmbulanceBridgeResourceName = function()
    if Config.UseAzAmbulance ~= true then return nil end
    return resolveExternalBridgeResourceName(((Config.AzAmbulance or {}).ResourceNames) or { 'Az-Ambulance', 'az_ambulance', 'az-ambulance' })
end

resolvePoliceBridgeResourceName = function()
    if Config.UseAz5PD ~= true then return nil end
    return resolveExternalBridgeResourceName(((Config.Az5PD or {}).ResourceNames) or { 'Az-5PD', 'az_5pd', 'az-5pd' })
end

resolveParkRangerBridgeResourceName = function()
    return resolveExternalBridgeResourceName(((Config.AzParkRangers or {}).ResourceNames) or { 'Az-ParkRangers', 'az_parkrangers', 'az-parkrangers', 'Az-ParkRanger', 'az_parkranger', 'az-parkranger', 'azpr' })
end

sourceHasFireDutyState = function(src)
    if hasFireDutyHold(src) then
        return true
    end

    local ply = Player(src)
    if ply and ply.state and (ply.state.az_fire_onDuty == true or ply.state.az_fire_onduty == true) then
        return true
    end

    if Config.UseAzFire == true then
        local fireResource = resolveFireBridgeResourceName()
        if fireResource then
            local ok, result = pcall(function()
                return exports[fireResource]:IsResponderOnDuty(src)
            end)
            if ok and result == true then
                return true
            end
        end
    end

    return false
end

resolveOpenUnitStatus = function(src, ctx, fallbackStatus)
    local existingStatus = upper(trim((Units[src] and Units[src].status) or fallbackStatus or ''))
    if existingStatus ~= '' and existingStatus ~= 'OFFDUTY' then
        return existingStatus
    end

    local department = sanitizeDepartmentId((ctx or {}).department or ((UnitMeta[src] or {}).department) or resolveCurrentServiceDepartment(src, Config.DefaultDepartment))
        or resolveCurrentServiceDepartment(src, Config.DefaultDepartment)
        or (Config.DefaultDepartment or 'police')

    if Config.UseAzFire == true and department == 'fire' and sourceHasFireDutyState(src) then
        local fireStatus = existingStatus ~= '' and existingStatus ~= 'OFFDUTY' and existingStatus or 'AVAILABLE'
        local fireResource = resolveFireBridgeResourceName()
        if fireResource then
            local ok, result = pcall(function()
                return exports[fireResource]:GetResponderMDTStatus(src)
            end)
            if ok and trim(tostring(result or '')) ~= '' then
                fireStatus = upper(trim(tostring(result)))
            end
        end
        if fireStatus == 'OFFDUTY' then fireStatus = 'AVAILABLE' end
        return fireStatus
    end

    return existingStatus ~= '' and existingStatus or upper(trim(Config.Duty.defaultStatus or 'OFFDUTY'))
end


syncOperationalUnitForOpen = function(src, ctx, desiredStatus, preferredDepartment)
    local currentStatus = upper(trim(desiredStatus or ((Units[src] and Units[src].status) or 'OFFDUTY')))
    if currentStatus == '' then currentStatus = 'OFFDUTY' end

    if sanitizeDepartmentId((ctx or {}).department or preferredDepartment or '') == 'fire' and sourceHasFireDutyState(src) then
        markFireDutyHold(src, true)
        local fireStatus = resolveOpenUnitStatus(src, ctx, currentStatus)
        if fireStatus == 'OFFDUTY' then fireStatus = 'AVAILABLE' end
        ctx.status = fireStatus
        ensureUnitRegisteredForOperationalSource(src, 'fire', fireStatus)
        return fireStatus
    end

    if Units[src] then
        setUnitStatus(src, currentStatus, ctx)
        return currentStatus
    end

    if currentStatus ~= 'OFFDUTY' then
        setUnitStatus(src, currentStatus, ctx)
        return currentStatus
    end

    UnitMeta[src] = ctx
    return currentStatus
end

local function buildFallbackOperationalContext(src, preferredDepartment)
    local ident = getCharacter(src)
    local existing = UnitMeta[src] or {}
    local department = sanitizeDepartmentId(preferredDepartment or existing.department)
        or resolveCurrentServiceDepartment(src, preferredDepartment or existing.department or Config.DefaultDepartment)
        or (Config.DefaultDepartment or 'police')
    local role = canUseDispatch(src) and 'dispatch' or 'leo'
    local ctx = {
        id = tonumber(existing.id) or src,
        name = trim(existing.name or getOfficerDisplayLabel(src) or GetPlayerName(src) or ('Unit ' .. tostring(src))),
        department = department,
        grade = tonumber(existing.grade or Config.DefaultOfficerGrade) or Config.DefaultOfficerGrade,
        callsign = trim(existing.callsign or defaultCallsign((ident and (ident.charid or ident.identifier or ident.license or ident.discordid)) or src)),
        licenseStatus = existing.licenseStatus or 'valid',
        discordid = existing.discordid or ident.discordid,
        charid = existing.charid or ident.charid,
        identifier = existing.identifier or ident.identifier,
        isAdmin = canUseAdmin(src),
        isSupervisor = canUseSupervisor(src),
        isDispatch = canUseDispatch(src),
        canManageDispatch = canManageDispatchConsole(src),
        canClearCalls = canManageDispatchConsole(src),
        canClearWarrants = canManageDispatchConsole(src),
        canClearBolos = canManageDispatchConsole(src),
        canAttachDetach = canUseOperationalMDT(src),
        role = trim(existing.role or role) ~= '' and trim(existing.role or role) or role,
        isLEO = existing.isLEO ~= false,
        isCiv = false,
        canUseDMV = canUseDMV(src),
        canUseCiv = canUseCiv(src),
        canUseLeoChat = canUseLeoChat(src),
        license = existing.license or ident.license,
        permissions = existing.permissions or employeePermPayloadFromRow({ mdt_role = role })
    }
    return attachUiSettings(ctx)
end

ensureUnitRegisteredForOperationalSource = function(src, preferredDepartment, status)
    src = tonumber(src) or 0
    if src <= 0 or not canUseOperationalMDT(src) then return false end
    local desiredStatus = upper(trim(status or ((Units[src] and Units[src].status) or 'AVAILABLE')))
    if desiredStatus == '' then desiredStatus = 'AVAILABLE' end
    local ctx = UnitMeta[src] or buildFallbackOperationalContext(src, preferredDepartment)
    local forcedDepartment = sanitizeDepartmentId(preferredDepartment or '')
    if forcedDepartment then ctx.department = forcedDepartment end
    if trim(ctx.role or '') == '' then ctx.role = canUseDispatch(src) and 'dispatch' or 'leo' end
    if ctx.isLEO == nil then ctx.isLEO = true end
    UnitMeta[src] = attachUiSettings(ctx)
    if sanitizeDepartmentId(ctx.department or preferredDepartment or '') == 'fire' and desiredStatus ~= 'OFFDUTY' then
        markFireDutyHold(src, true)
    end
    setUnitStatus(src, desiredStatus, ctx)
    return true
end

local function resourceNameMatches(value, names)
    value = lower(trim(value or ''))
    if value == '' or type(names) ~= 'table' then return false end
    for _, entry in ipairs(names) do
        if value == lower(trim(entry or '')) then
            return true
        end
    end
    return false
end

local function isExternalSourceEnabled(payload)
    payload = payload or {}
    local sourceName = trim(payload.sourceResource or payload.externalResource or payload.resource or payload.source or payload.origin or '')
    if sourceName == '' then return true end
    if Config.UseAzAmbulance ~= true and resourceNameMatches(sourceName, ((Config.AzAmbulance or {}).ResourceNames) or { 'Az-Ambulance', 'az_ambulance', 'az-ambulance' }) then
        return false
    end
    if Config.UseAzFire ~= true and resourceNameMatches(sourceName, ((Config.AzFire or {}).ResourceNames) or { 'Az-Fire', 'az_fire', 'az-fire' }) then
        return false
    end
    if Config.UseAz5PD ~= true and resourceNameMatches(sourceName, ((Config.Az5PD or {}).ResourceNames) or { 'Az-5PD', 'az_5pd', 'az-5pd' }) then
        return false
    end
    return true
end

function normalizeExternalCallStatus(status)
    status = upper(trim(status or 'PENDING'))
    if status == 'ONSCENE' then return 'ONSCENE' end
    if status == 'ENROUTE' then return 'ENROUTE' end
    if status == 'ASSIGNED' then return 'ENROUTE' end
    if status == 'ACTIVE' then return 'ACTIVE' end
    if status == 'CLEARED' or status == 'CLOSED' then return 'CLEARED' end
    return 'PENDING'
end

local function deriveExternalCallLocation(payload, existingCall)
    payload = payload or {}
    local coords = payload.coords or (existingCall and existingCall.coords) or {}
    local street = trim(payload.street or ((payload.metadata or {}).street) or '')
    local location = trim(payload.location or payload.address or (existingCall and existingCall.location) or '')
    local postal = trim(payload.postal or '')

    if postal == '' and type(coords) == 'table' then
        local nearest = getNearestPostal(coords)
        postal = nearest and trim(nearest.code or '') or ''
    end

    local normalized = lower(location)
    if street ~= '' then
        location = street
    elseif normalized == '' or normalized == 'unknown address' or normalized == 'unknown location' then
        if postal ~= '' then
            location = ('Near Postal %s'):format(postal)
        else
            location = 'Unknown location'
        end
    end

    return composeCallLocation(location, postal)
end


function resolveExternalCallDepartment(payload)
    payload = payload or {}
    local explicit = sanitizeDepartmentId(payload.department or payload.service or payload.job or ((payload.metadata or {}).department) or '')
    if explicit and explicit ~= '' and explicit ~= 'dispatch' and explicit ~= 'civilian' then
        return explicit
    end

    local sourceName = trim(payload.sourceResource or payload.externalResource or payload.resource or payload.source or payload.origin or '')
    if resourceNameMatches(sourceName, ((Config.AzFire or {}).ResourceNames) or { 'Az-Fire', 'az_fire', 'az-fire' }) then
        return sanitizeDepartmentId('fire') or 'fire'
    end
    if resourceNameMatches(sourceName, ((Config.AzAmbulance or {}).ResourceNames) or { 'Az-Ambulance', 'az_ambulance', 'az-ambulance' }) then
        return sanitizeDepartmentId('ems') or 'ems'
    end
    if resourceNameMatches(sourceName, ((Config.Az5PD or {}).ResourceNames) or { 'Az-5PD', 'az_5pd', 'az-5pd' }) then
        return sanitizeDepartmentId('police') or 'police'
    end
    if resourceNameMatches(sourceName, ((Config.AzParkRangers or {}).ResourceNames) or { 'Az-ParkRangers', 'az_parkrangers', 'az-parkrangers', 'Az-ParkRanger', 'az_parkranger', 'az-parkranger' }) then
        return sanitizeDepartmentId('ranger') or 'ranger'
    end

    local callType = lower(trim(payload.type or payload.kind or payload.title or ''))
    if string.find(callType, 'fire', 1, true) then return sanitizeDepartmentId('fire') or 'fire' end
    if string.find(callType, 'ems', 1, true) or string.find(callType, 'medical', 1, true) or string.find(callType, 'ambulance', 1, true) then return sanitizeDepartmentId('ems') or 'ems' end
    if string.find(callType, 'park ranger', 1, true) or string.find(callType, 'park_ranger', 1, true) or string.find(callType, 'parkranger', 1, true) or string.find(callType, 'ranger', 1, true) then return sanitizeDepartmentId('ranger') or 'ranger' end
    if string.find(callType, 'police', 1, true) or string.find(callType, 'leo', 1, true) or string.find(callType, 'traffic', 1, true) then return sanitizeDepartmentId('police') or 'police' end

    return nil
end

function unitMatchesCallDepartment(unitSrc, unit, targetDepartment)
    if type(unit) ~= 'table' or not isOnDutyStatus(unit.status) then return false end
    targetDepartment = sanitizeDepartmentId(targetDepartment or '')
    if not targetDepartment or targetDepartment == '' then return true end

    local src = tonumber(unitSrc or unit.id or 0) or 0
    local unitDepartment = sanitizeDepartmentId(unit.department or '')
        or sanitizeDepartmentId(((UnitMeta[tonumber(unit.id or 0)] or {}).department) or '')
    local resolvedDepartment = src > 0 and sanitizeDepartmentId(resolveCurrentServiceDepartment(src, unitDepartment or targetDepartment)) or nil
    local frameworkJob = lower(trim(src > 0 and (getFrameworkJobName(src) or '') or ''))

    if targetDepartment == 'police' then
        if unitDepartment == 'police' or resolvedDepartment == 'police' then
            return true
        end
        if configuredJobMatch(unitDepartment or '', ((Config.Roles or {}).leoDepartments) or {}) then
            return true
        end
        if configuredJobMatch(resolvedDepartment or '', ((Config.Roles or {}).leoDepartments) or {}) then
            return true
        end
        if frameworkJob ~= '' and (sanitizeDepartmentId(frameworkJob) == 'police' or configuredJobMatch(frameworkJob, ((Config.Roles or {}).leoDepartments) or {})) then
            return true
        end
        return false
    end

    if unitDepartment == targetDepartment or resolvedDepartment == targetDepartment then
        return true
    end

    if frameworkJob ~= '' then
        if targetDepartment == 'ems' and Config.UseAzAmbulance == true and configuredJobMatch(frameworkJob, ((Config.AzAmbulance or {}).JobNames) or { 'ambulance', 'ems', 'doctor', 'paramedic' }) then
            return true
        end
        if targetDepartment == 'fire' and Config.UseAzFire == true and configuredJobMatch(frameworkJob, ((Config.AzFire or {}).JobNames) or { 'fire', 'firefighter', 'safd' }) then
            return true
        end
        if targetDepartment == 'ranger' and configuredJobMatch(frameworkJob, ((Config.AzParkRangers or {}).JobNames) or { 'park_ranger', 'parkranger', 'ranger' }) then
            return true
        end
    end

    return false
end

function dispatchExternalCallAlert(call, payload)
    if type(call) ~= 'table' then return end
    local callMode = tostring((((Config or {}).TTS or {}).callMode or 'all_onduty'))
    if lower(callMode) ~= 'all_onduty' then return end

    payload = payload or {}
    local targetDepartment = resolveExternalCallDepartment(payload)
    local reason = stripDispatchTokenPrefix(call.message or payload.message or payload.details or payload.description or payload.title or call.type or 'New call')
    local location = trim(call.location or payload.location or payload.address or 'Unknown location')
    local sourceName = trim(call.external_source or payload.sourceResource or payload.externalResource or payload.resource or '')
    local serviceLabel = prettifyServiceLabel(targetDepartment or trim(call.type or 'CALL'))

    for unitSrc, unit in pairs(Units) do
        if unitMatchesCallDepartment(unitSrc, unit, targetDepartment) then
            dprint(('Dispatch alert -> src=%s dept=%s job=%s target=%s call=%s source=%s'):format(tostring(unitSrc), tostring(unit.department or ((UnitMeta[unitSrc] or {}).department) or ''), tostring(getFrameworkJobName(unitSrc) or ''), tostring(targetDepartment or ''), tostring(call.id or ''), tostring(sourceName or '')))
            local alertPayload = {
                id = call.id,
                caller = call.caller,
                message = call.message,
                details = reason,
                reason = reason,
                type = call.type,
                service = targetDepartment,
                location = location,
                postal = call.postal,
                coords = call.coords,
                notificationType = 'call',
                notificationTitle = ('New %s Call #%s'):format(serviceLabel ~= '' and serviceLabel or 'Call', tostring(call.id or '?')),
                notificationMessage = location ~= '' and reason ~= '' and ('%s • %s'):format(location, reason) or (location ~= '' and location or reason),
                externalSource = sourceName,
                quickRespond = true,
                status = call.status,
                units = call.units,
                created_at = call.created_at,
                notificationDuration = tonumber(((Config or {}).QuickRespond or {}).alertDurationMs) or 20000,
                prompt = 'Press E to respond',
                metadata = type(call.metadata) == 'table' and call.metadata or (type(payload.metadata) == 'table' and payload.metadata or {}),
                sourceResource = sourceName,
                externalResource = sourceName,
                external_source = sourceName
            }
            TriggerClientEvent('az_mdt:client:newCallAlert', unitSrc, alertPayload)
        end
    end
end

function createExternalCallInternal(payload)
    payload = payload or {}
    if not isExternalSourceEnabled(payload) then
        dprint(('External call rejected from %s (bridge disabled)'):format(trim(payload.sourceResource or payload.externalResource or payload.resource or payload.source or 'unknown')))
        return false
    end
    local id = NextCallId
    NextCallId = NextCallId + 1
    local location, postal = deriveExternalCallLocation(payload)
    local message = trim(payload.message or payload.details or payload.description or payload.title or 'External call')
    local caller = trim(payload.caller or payload.callerName or payload.origin or payload.title or 'External Call')
    local callType = upper(trim(payload.type or payload.kind or 'EXTERNAL'))
    local call = {
        id = id,
        caller = caller,
        message = message ~= '' and message or callType,
        location = location,
        postal = postal ~= '' and postal or nil,
        coords = payload.coords or {},
        units = {},
        status = normalizeExternalCallStatus(payload.status),
        type = callType,
        created_at = os.date('%H:%M:%S'),
        external = true,
        external_source = trim(payload.sourceResource or payload.externalResource or payload.resource or payload.source or payload.origin or ''),
        metadata = type(payload.metadata) == 'table' and payload.metadata or {},
        service = sanitizeDepartmentId(payload.department or payload.service or payload.job or ((payload.metadata or {}).department) or ''),
        sourceResource = trim(payload.sourceResource or payload.externalResource or payload.resource or payload.source or payload.origin or ''),
        externalResource = trim(payload.externalResource or payload.sourceResource or payload.resource or payload.source or payload.origin or '')
    }
    Calls[id] = call
    ensureCallRoom(id)
    DB.execute([[
        INSERT INTO mdt_calls (call_id, caller, message, location, postal, coords_json, status)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE caller = VALUES(caller), message = VALUES(message), location = VALUES(location), postal = VALUES(postal), coords_json = VALUES(coords_json), status = VALUES(status)
    ]], { id, call.caller, call.message, call.location, call.postal, jsonEncode(call.coords), call.status })
    triggerOnDutyClients('az_mdt:client:callUpdated', call)
    dispatchExternalCallAlert(call, payload)
    return id
end

exports('CreateExternalCall', function(payload)
    return createExternalCallInternal(payload)
end)

exports('UpdateExternalCall', function(callId, payload)
    callId = tonumber(callId) or 0
    payload = payload or {}
    local call = Calls[callId]
    if not call then return false end
    if payload.caller ~= nil then call.caller = trim(payload.caller) end
    if payload.message ~= nil then call.message = trim(payload.message) end
    if payload.coords ~= nil then call.coords = payload.coords end
    local updatedExternalSource = trim(payload.sourceResource or payload.externalResource or payload.resource or payload.source or payload.origin or '')
    if updatedExternalSource ~= '' then
        call.external_source = updatedExternalSource
        call.sourceResource = trim(payload.sourceResource or updatedExternalSource)
        call.externalResource = trim(payload.externalResource or updatedExternalSource)
    end
    if type(payload.metadata) == 'table' then
        call.metadata = payload.metadata
    end
    local updatedService = sanitizeDepartmentId(payload.department or payload.service or payload.job or ((payload.metadata or {}).department) or '')
    if updatedService and updatedService ~= '' then
        call.service = updatedService
    end
    if payload.location ~= nil or payload.address ~= nil or payload.postal ~= nil or payload.street ~= nil or ((payload.metadata or {}).street) ~= nil then
        local location, postal = deriveExternalCallLocation(payload, call)
        call.location = location
        call.postal = postal ~= '' and postal or nil
    end
    if payload.status ~= nil then call.status = normalizeExternalCallStatus(payload.status) end
    DB.execute([[UPDATE mdt_calls SET caller = ?, message = ?, location = ?, postal = ?, coords_json = ?, status = ? WHERE call_id = ?]], {
        call.caller, call.message, call.location, call.postal, jsonEncode(call.coords), call.status, callId
    })
    triggerOnDutyClients('az_mdt:client:callUpdated', call)
    return true
end)

exports('DeleteExternalCall', function(callId)
    callId = tonumber(callId) or 0
    if callId <= 0 or not Calls[callId] then return false end
    Calls[callId] = nil
    CallRooms[callId] = nil
    DB.execute([[UPDATE mdt_calls SET status = ? WHERE call_id = ?]], { 'CLEARED', callId })
    DB.execute([[DELETE FROM mdt_call_units WHERE call_id = ?]], { callId })
    broadcastCalls()
    return true
end)

exports('AttachUnitToExternalCall', function(callId, src, setEnroute)
    callId = tonumber(callId) or 0
    src = tonumber(src) or 0
    local call = Calls[callId]
    if callId <= 0 or src <= 0 or not call then return false end

    local ctx = UnitMeta[src] or { name = getOfficerDisplayLabel(src), callsign = '' }
    local externalSource = trim(call.external_source or '')
    if resourceNameMatches(externalSource, ((Config.AzFire or {}).ResourceNames) or { 'Az-Fire', 'az_fire', 'az-fire' }) then
        ctx.department = sanitizeDepartmentId('fire') or 'fire'
    elseif resourceNameMatches(externalSource, ((Config.AzAmbulance or {}).ResourceNames) or { 'Az-Ambulance', 'az_ambulance', 'az-ambulance' }) then
        ctx.department = sanitizeDepartmentId('ems') or 'ems'
    elseif resourceNameMatches(externalSource, ((Config.Az5PD or {}).ResourceNames) or { 'Az-5PD', 'az_5pd', 'az-5pd' }) then
        ctx.department = sanitizeDepartmentId('police') or 'police'
    elseif resourceNameMatches(externalSource, ((Config.AzParkRangers or {}).ResourceNames) or { 'Az-ParkRangers', 'az_parkrangers', 'az-parkrangers', 'azpr' }) then
        ctx.department = sanitizeDepartmentId('ranger') or 'ranger'
    end
    ctx.name = trim(ctx.name or getOfficerDisplayLabel(src) or ('Unit ' .. tostring(src)))
    ctx.callsign = trim(ctx.callsign or '')
    ctx.source = src
    ctx.playerSource = src
    ctx.department = sanitizeDepartmentId(ctx.department) or resolveCurrentServiceDepartment(src, ctx.department or Config.DefaultDepartment)
    if trim(ctx.role or '') == '' then ctx.role = 'leo' end
    if ctx.isLEO == nil then ctx.isLEO = true end
    UnitMeta[src] = ctx

    local unitStatusChanged = false
    if setEnroute ~= false then
        local currentUnitStatus = string.upper(tostring(((Units[src] or {}).status or '')))
        if currentUnitStatus ~= 'ENROUTE' or not Units[src] then
            setUnitStatus(src, 'ENROUTE', ctx)
            unitStatusChanged = true
        end
    elseif not Units[src] then
        setUnitStatus(src, 'AVAILABLE', ctx)
        unitStatusChanged = true
    end

    local statusChanged = false
    if setEnroute ~= false and tostring(call.status or '') ~= 'ENROUTE' then
        call.status = 'ENROUTE'
        DB.execute([[UPDATE mdt_calls SET status = ? WHERE call_id = ?]], { 'ENROUTE', callId })
        statusChanged = true
    end

    local found = false
    for _, u in ipairs(call.units) do
        if tonumber(u.id) == src then found = true break end
    end
    local attachedNow = false
    if not found then
        table.insert(call.units, { id = src, name = ctx.name or ('Unit ' .. tostring(src)), callsign = ctx.callsign or '' })
        DB.execute([[INSERT INTO mdt_call_units (call_id, unit_source, unit_name, unit_callsign) VALUES (?, ?, ?, ?)]], { callId, tostring(src), ctx.name or ('Unit ' .. tostring(src)), ctx.callsign or '' })
        attachedNow = true
    end

    ensureCallRoom(callId)
    if attachedNow or statusChanged or unitStatusChanged then
        triggerOnDutyClients('az_mdt:client:callUpdated', call)
    end
    if attachedNow and shouldEmitCallRoomOpened(src, callId, 15000) then
        TriggerClientEvent('az_mdt:client:callRoomOpened', src, callRoomSnapshot(callId))
    end
    return true
end)

exports('DetachUnitFromExternalCall', function(callId, src)
    callId = tonumber(callId) or 0
    src = tonumber(src) or 0
    local call = Calls[callId]
    if callId <= 0 or src <= 0 or not call then return false end

    local removed = false
    local kept = {}
    for _, unit in ipairs(call.units or {}) do
        if tonumber((unit and (unit.id or unit.source or unit.sourceId))) == src then
            removed = true
        else
            kept[#kept + 1] = unit
        end
    end
    if not removed then return true end

    call.units = kept
    DB.execute([[DELETE FROM mdt_call_units WHERE call_id = ? AND unit_source = ?]], { callId, tostring(src) })
    clearCallRoomOpenCooldown(src, callId)

    local hasUnits = type(call.units) == 'table' and #call.units > 0
    if not hasUnits and call.status ~= 'CLEARED' and call.status ~= 'CLOSED' then
        call.status = 'PENDING'
        DB.execute([[UPDATE mdt_calls SET status = ? WHERE call_id = ?]], { 'PENDING', callId })
    end

    triggerOnDutyClients('az_mdt:client:callUpdated', call)
    return true
end)


local function callHasUnitAttached(call, src)
    if type(call) ~= 'table' or type(call.units) ~= 'table' then return false end
    src = tonumber(src) or 0
    if src <= 0 then return false end
    for _, unit in ipairs(call.units) do
        if tonumber((unit and (unit.id or unit.source or unit.sourceId))) == src then
            return true
        end
    end
    return false
end

local function markUnitOnSceneForCallInternal(callId, src, extra)
    callId = tonumber(callId) or 0
    src = tonumber(src) or 0
    extra = type(extra) == 'table' and extra or {}
    local call = Calls[callId]
    if callId <= 0 or src <= 0 or not call then return false, 'invalid_call' end
    if not callHasUnitAttached(call, src) then return false, 'not_attached' end
    if call.status == 'CLEARED' or call.status == 'CLOSED' then return false, 'closed' end

    local ctx = UnitMeta[src] or { name = getOfficerDisplayLabel(src), callsign = '' }
    setUnitStatus(src, 'ONSCENE', ctx)

    if call.status ~= 'ONSCENE' then
        call.status = 'ONSCENE'
        DB.execute([[UPDATE mdt_calls SET status = ? WHERE call_id = ?]], { 'ONSCENE', callId })
    end

    triggerOnDutyClients('az_mdt:client:callUpdated', call)
    return true
end

exports('MarkUnitOnSceneForCall', function(callId, src, extra)
    return markUnitOnSceneForCallInternal(callId, src, extra)
end)

RegisterNetEvent('az_mdt:MarkUnitOnSceneForCall', function(callId, extra)
    local src = source
    if not canUseOperationalMDT(src) then return end
    markUnitOnSceneForCallInternal(callId, src, extra)
end)

exports('SetUnitStatusFromExternal', function(src, status, extra)
    src = tonumber(src) or 0
    extra = type(extra) == 'table' and extra or {}
    if src <= 0 then return false end
    local ctx = UnitMeta[src] or buildFallbackOperationalContext(src, extra.department or Config.DefaultDepartment)

    local current = Units[src]
    local currentDepartment = sanitizeDepartmentId(((current or {}).department) or ((UnitMeta[src] or {}).department) or '')
    local currentActive = current and isOnDutyStatus(current.status)
    local desiredStatus = upper(trim(status or 'AVAILABLE'))
    if desiredStatus == '' then desiredStatus = 'AVAILABLE' end

    local incomingDepartment = sanitizeDepartmentId(extra.department or '')
    if not incomingDepartment then
        incomingDepartment = resolveCurrentServiceDepartment(src, ctx.department or Config.DefaultDepartment)
    end

    if desiredStatus == 'OFFDUTY' and extra.forceOffDuty ~= true and currentActive and incomingDepartment and currentDepartment and incomingDepartment ~= currentDepartment then
        dprint(("Ignoring cross-department OFFDUTY status for %s incoming=%s current=%s"):format(tostring(src), tostring(incomingDepartment), tostring(currentDepartment)))
        return true
    end

    if extra.name ~= nil and trim(extra.name) ~= '' then ctx.name = trim(extra.name) end
    if extra.callsign ~= nil then ctx.callsign = trim(extra.callsign) end
    ctx.source = src
    ctx.playerSource = src
    if extra.grade ~= nil then ctx.grade = tonumber(extra.grade) or ctx.grade end
    ctx.department = incomingDepartment or ctx.department or Config.DefaultDepartment
    if extra.role ~= nil and trim(extra.role) ~= '' then ctx.role = trim(extra.role) end
    if extra.isLEO ~= nil then ctx.isLEO = extra.isLEO == true end
    ctx = attachUiSettings(ctx)
    UnitMeta[src] = ctx

    if ctx.department == 'fire' and desiredStatus == 'OFFDUTY' and extra.forceOffDuty ~= true then
        if sourceHasFireDutyState(src) or currentActive then
            local preserved = resolveOpenUnitStatus(src, ctx, (current and current.status) or 'AVAILABLE')
            if preserved == 'OFFDUTY' then preserved = 'AVAILABLE' end
            markFireDutyHold(src, true)
            dprint(('Ignoring unforced external fire OFFDUTY status for %s while MDT still has an active fire unit.'):format(tostring(src)))
            ensureUnitRegisteredForOperationalSource(src, 'fire', preserved)
            return true
        end
    end
    if ctx.department == 'fire' then
        if desiredStatus ~= 'OFFDUTY' then
            markFireDutyHold(src, true)
        elseif not sourceHasFireDutyState(src) then
            markFireDutyHold(src, false)
        end
        if desiredStatus == 'OFFDUTY' and sourceHasFireDutyState(src) then
            desiredStatus = resolveOpenUnitStatus(src, ctx, 'AVAILABLE')
            if desiredStatus == 'OFFDUTY' then desiredStatus = 'AVAILABLE' end
        end
        if desiredStatus ~= 'OFFDUTY' then
            ensureUnitRegisteredForOperationalSource(src, 'fire', desiredStatus)
        else
            setUnitStatus(src, desiredStatus, ctx)
        end
    else
        setUnitStatus(src, desiredStatus, ctx)
    end
    return true
end)

exports('SetDutyStateFromExternal', function(src, onDuty, extra)
    src = tonumber(src) or 0
    extra = type(extra) == 'table' and extra or {}
    if src <= 0 then return false end
    local department = sanitizeDepartmentId(extra.department or '') or resolveCurrentServiceDepartment(src, extra.department or Config.DefaultDepartment) or (Config.DefaultDepartment or 'police')
    local ctx = UnitMeta[src] or buildFallbackOperationalContext(src, department)

    local current = Units[src]
    local currentDepartment = sanitizeDepartmentId(((current or {}).department) or ((UnitMeta[src] or {}).department) or '')
    local currentActive = current and isOnDutyStatus(current.status)

    if onDuty ~= true and extra.forceOffDuty ~= true and currentActive and department and currentDepartment and department ~= currentDepartment then
        dprint(("Ignoring cross-department duty OFFDUTY for %s incoming=%s current=%s"):format(tostring(src), tostring(department), tostring(currentDepartment)))
        return true
    end

    if extra.name ~= nil and trim(extra.name) ~= '' then ctx.name = trim(extra.name) end
    if extra.callsign ~= nil then ctx.callsign = trim(extra.callsign) end
    ctx.source = src
    ctx.playerSource = src
    if extra.grade ~= nil then ctx.grade = tonumber(extra.grade) or ctx.grade end
    if extra.role ~= nil and trim(extra.role) ~= '' then ctx.role = trim(extra.role) end
    if extra.isLEO ~= nil then ctx.isLEO = extra.isLEO == true end
    ctx.department = department
    ctx = attachUiSettings(ctx)
    UnitMeta[src] = ctx

    local desiredStatus = onDuty == true and upper(trim(extra.status or 'AVAILABLE')) or 'OFFDUTY'
    if desiredStatus == '' then desiredStatus = 'AVAILABLE' end

    if department == 'fire' and onDuty ~= true and extra.forceOffDuty ~= true then
        if sourceHasFireDutyState(src) or currentActive then
            local preserved = resolveOpenUnitStatus(src, ctx, (current and current.status) or 'AVAILABLE')
            if preserved == 'OFFDUTY' then preserved = 'AVAILABLE' end
            markFireDutyHold(src, true)
            dprint(('Ignoring unforced external fire OFFDUTY duty sync for %s while MDT still has an active fire unit.'):format(tostring(src)))
            ensureUnitRegisteredForOperationalSource(src, 'fire', preserved)
            return true
        end
    end

    if department == 'fire' then
        markFireDutyHold(src, onDuty == true)
    end

    if onDuty == true and department == 'fire' then
        local fireResource = resolveFireBridgeResourceName()
        if fireResource then
            local ok, result = pcall(function()
                return exports[fireResource]:GetResponderMDTStatus(src)
            end)
            if ok and trim(tostring(result or '')) ~= '' then
                desiredStatus = upper(trim(tostring(result)))
            end
        end
        if desiredStatus == 'OFFDUTY' then desiredStatus = 'AVAILABLE' end
        ensureUnitRegisteredForOperationalSource(src, 'fire', desiredStatus)
    else
        setUnitStatus(src, desiredStatus, ctx)
    end
    return true
end)

local serverStartupDone = false

local function startMdtRuntime()
    if serverStartupDone then return end
    serverStartupDone = true

    loadPostals()

    dprint("Standalone MySQL ready for " .. RESOURCE_NAME)

    ensureLiveChatTable()
    ensureThemeTable()
    loadChatHistoryFromDb()
    loadThemeState(function(state)
        dprint(('Loaded MDT theme: %s'):format((state and state.preset) or 'blue-command'))
    end)

    DB.fetchAll([[SELECT COALESCE(MAX(call_id), 0) AS max_call_id FROM mdt_calls]], {}, function(rows)
        local maxId = rows and rows[1] and tonumber(rows[1].max_call_id) or 0
        NextCallId = math.max(NextCallId, (maxId or 0) + 1)
    end)

    DB.fetchAll([[SELECT call_id, caller, message, location, postal, coords_json, status, created_at FROM mdt_calls WHERE status != 'CLOSED' ORDER BY call_id DESC LIMIT 200]], {}, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            local callId = tonumber(row.call_id) or 0
            if callId > 0 then
                Calls[callId] = {
                    id = callId,
                    caller = row.caller,
                    message = row.message,
                    location = row.location,
                    postal = row.postal,
                    coords = jsonDecode(row.coords_json) or {},
                    units = {},
                    status = row.status or 'PENDING',
                    created_at = row.created_at or os.date('%H:%M:%S')
                }
                ensureCallRoom(callId)
            end
        end
        dprint(("Schema ensured and live chat history loaded. Restored %d calls."):format(#rows))
    end)
end

AddEventHandler("az_mdt:schemaReady", startMdtRuntime)

AddEventHandler("onResourceStart", function(res)
    if res ~= RESOURCE_NAME then return end
    if _G.AZ_MDT_SCHEMA_READY == true then
        startMdtRuntime()
        return
    end

    dprint("Waiting for MDT schema before loading live calls.")
end)

local function webUrlDecode(str)
    str = tostring(str or '')
    str = str:gsub('+', ' ')
    str = str:gsub('%%(%x%x)', function(hex)
        return string.char(tonumber(hex, 16) or 0)
    end)
    return str
end

local function webParsePathAndQuery(rawPath)
    rawPath = tostring(rawPath or '/')
    local pathOnly, qs = rawPath:match('^([^?]*)%??(.*)$')
    pathOnly = pathOnly or '/'
    if pathOnly == '' then pathOnly = '/' end

    local prefix = '/' .. RESOURCE_NAME
    if pathOnly == prefix then
        pathOnly = '/'
    elseif pathOnly:sub(1, #prefix + 1) == prefix .. '/' then
        pathOnly = pathOnly:sub(#prefix + 1)
    end

    local query = {}
    if qs and qs ~= '' then
        for pair in string.gmatch(qs, '([^&]+)') do
            local key, value = pair:match('([^=]+)=?(.*)')
            if key then
                query[webUrlDecode(key)] = webUrlDecode(value or '')
            end
        end
    end

    return pathOnly, query
end

local function webResponse(response, status, body, contentType, extraHeaders)
    local headers = {
        ['Content-Type'] = contentType or 'text/plain; charset=utf-8',
        ['Cache-Control'] = 'no-store, must-revalidate'
    }
    if extraHeaders then
        for k, v in pairs(extraHeaders) do headers[k] = v end
    end
    response.writeHead(status or 200, headers)
    response.send(body or '')
end

local function webJson(response, status, payload)
    webResponse(response, status, jsonEncode(payload or {}), 'application/json; charset=utf-8')
end

local function webMimeType(path)
    path = lower(path or '')
    if path:sub(-5) == '.html' then return 'text/html; charset=utf-8' end
    if path:sub(-4) == '.css' then return 'text/css; charset=utf-8' end
    if path:sub(-3) == '.js' then return 'application/javascript; charset=utf-8' end
    if path:sub(-5) == '.json' then return 'application/json; charset=utf-8' end
    if path:sub(-4) == '.png' then return 'image/png' end
    if path:sub(-4) == '.jpg' or path:sub(-5) == '.jpeg' then return 'image/jpeg' end
    if path:sub(-4) == '.svg' then return 'image/svg+xml' end
    if path:sub(-4) == '.ogg' then return 'audio/ogg' end
    return 'application/octet-stream'
end

local function webCanRead(request, query)
    if not (Config.Web and Config.Web.enabled) then
        return false, 'Web mode disabled in config.'
    end
    if Config.Web.publicReadOnly then
        return true
    end
    local token = trim((query and query.token) or '')
    local headers = (request and request.headers) or {}
    if token == '' then
        token = trim(headers['x-az-mdt-token'] or headers['X-AZ-MDT-TOKEN'] or '')
    end
    local expected = trim((Config.Web and Config.Web.readToken) or '')
    if expected ~= '' and token == expected then
        return true
    end
    return false, 'Missing or invalid web token.'
end

local function randomToken(len)
    len = tonumber(len) or 32
    local alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local out = {}
    for i = 1, len do
        local idx = math.random(1, #alphabet)
        out[i] = alphabet:sub(idx, idx)
    end
    return table.concat(out)
end

randomLinkCode = function()
    local alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local out = {}
    for i = 1, 8 do
        local idx = math.random(1, #alphabet)
        out[i] = alphabet:sub(idx, idx)
    end
    return table.concat(out)
end

local function urlEncode(str)
    str = tostring(str or '')
    str = str:gsub("\n", "\r\n")
    str = str:gsub('([^%w%-_%.~])', function(c)
        return string.format('%%%02X', string.byte(c))
    end)
    return str
end

webSqlNow = function(offsetSeconds)
    return os.date('%Y-%m-%d %H:%M:%S', os.time() + (tonumber(offsetSeconds) or 0))
end

local function webNormalizeSqlDateTime(value, fallback)
    local fallbackValue = fallback or webSqlNow(0)
    if value == nil then
        return fallbackValue
    end

    local numeric = tonumber(value)
    if numeric then
        numeric = math.floor(numeric)
        if numeric > 9999999999 then
            numeric = math.floor(numeric / 1000)
        end
        if numeric > 0 then
            return os.date('%Y-%m-%d %H:%M:%S', numeric)
        end
        return fallbackValue
    end

    local str = trim(tostring(value or ''))
    if str == '' then
        return fallbackValue
    end

    str = str:gsub('Z$', '')
    str = str:gsub('([%+%-]%d%d):?(%d%d)$', '')
    str = str:gsub('%.%d+$', '')

    if str:match('^%d%d%d%d%-%d%d%-%d%d[Tt ]%d%d:%d%d:%d%d$') then
        return (str:gsub('T', ' '))
    end

    if str:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$') then
        return str
    end

    return fallbackValue
end

local function webSessionTtl()
    return math.max(3600, tonumber(((Config.Web or {}).sessionDurationSeconds) or 2592000) or 2592000)
end

local function webNormalizeSessionDates(session)
    if type(session) ~= 'table' then
        return session
    end

    local now = webSqlNow(0)
    session.created_at = webNormalizeSqlDateTime(session.created_at, now)
    session.expires_at = webNormalizeSqlDateTime(session.expires_at, webSqlNow(webSessionTtl()))
    session.last_seen_at = webNormalizeSqlDateTime(session.last_seen_at, now)

    return session
end

local function webCookieName()
    return trim(((Config.Web or {}).sessionCookieName) or 'az_mdt_web_session')
end

local function webCookiePath()
    return '/' .. RESOURCE_NAME .. '/'
end

webLinkCodeTtl = function()
    return math.max(60, tonumber(((Config.Web or {}).linkCodeDurationSeconds) or 900) or 900)
end
webConfiguredBaseUrl = function()
    local raw = trim(((Config.Web or {}).publicBaseUrl) or '')
    if raw ~= '' and not raw:match('/$') then
        raw = raw .. '/'
    end
    return raw
end

local function webGetBaseUrl(request)
    local configured = webConfiguredBaseUrl()
    if configured ~= '' then
        return configured
    end

    local headers = (request and request.headers) or {}
    local host = trim(headers['x-forwarded-host'] or headers['X-Forwarded-Host'] or headers['host'] or headers['Host'] or '')
    local proto = trim(headers['x-forwarded-proto'] or headers['X-Forwarded-Proto'] or '')
    if proto == '' then proto = 'http' end
    if host ~= '' then
        return proto .. '://' .. host .. '/' .. RESOURCE_NAME .. '/'
    end
    return '/' .. RESOURCE_NAME .. '/'
end

local function webAbsoluteUrl(request, rel)
    local base = webGetBaseUrl(request)
    rel = tostring(rel or ''):gsub('^/+', '')
    return base .. rel
end

local function webBuildCookie(value, maxAge)
    return ('%s=%s; Path=%s; Max-Age=%d; HttpOnly; SameSite=Lax'):format(webCookieName(), tostring(value or ''), webCookiePath(), tonumber(maxAge) or 0)
end

local function webBuildStateCookie(value)
    return ('az_mdt_oauth_state=%s; Path=%s; Max-Age=600; HttpOnly; SameSite=Lax'):format(tostring(value or ''), webCookiePath())
end

local function webReadCookies(request)
    local headers = (request and request.headers) or {}
    local raw = tostring(headers['cookie'] or headers['Cookie'] or '')
    local out = {}
    for part in raw:gmatch('([^;]+)') do
        local key, value = part:match('^%s*([^=]+)%s*=%s*(.-)%s*$')
        if key and value then
            out[key] = value
        end
    end
    return out
end

local function webGetSessionToken(request)
    local cookies = webReadCookies(request)
    return trim(cookies[webCookieName()] or '')
end

local function webGetStateToken(request)
    local cookies = webReadCookies(request)
    return trim(cookies['az_mdt_oauth_state'] or '')
end

local function httpRequestCompat(url, method, data, headers, cb)
    method = method or 'GET'
    data = data or ''
    headers = headers or {}
    cb = cb or function() end

    if type(PerformHttpRequestAwait) == 'function' then
        local status, body, responseHeaders, errorData = PerformHttpRequestAwait(url, method, data, headers, { followLocation = true })
        cb(status, body, responseHeaders, errorData)
        return
    end

    PerformHttpRequest(url, function(status, body, responseHeaders, errorData)
        cb(status, body, responseHeaders, errorData)
    end, method, data, headers)
end

local function webGetOauthConfig(request)
    local oauth = ((Config.Web or {}).DiscordOAuth) or {}
    local clientId = trim(oauth.clientId or oauth.appId or '')
    local clientSecret = trim(oauth.clientSecret or '')
    local scopes = trim(oauth.scopes or 'identify')
    local redirectUri = trim(oauth.redirectUri or '')
    local redirectPath = trim(oauth.redirectPath or 'auth/callback')
    if redirectUri == '' then
        redirectUri = webAbsoluteUrl(request, redirectPath)
    end
    return {
        enabled = oauth.enabled ~= false and clientId ~= '' and clientSecret ~= '',
        clientId = clientId,
        clientSecret = clientSecret,
        scopes = scopes,
        redirectUri = redirectUri,
        redirectPath = redirectPath
    }
end

local function webBuildDiscordAuthorizeUrl(request, state)
    local oauth = webGetOauthConfig(request)
    return ('https://discord.com/oauth2/authorize?response_type=code&client_id=%s&scope=%s&redirect_uri=%s&state=%s')
        :format(urlEncode(oauth.clientId), urlEncode(oauth.scopes), urlEncode(oauth.redirectUri), urlEncode(state or ''))
end

local function webExchangeDiscordCode(request, code, cb)
    local oauth = webGetOauthConfig(request)
    if not oauth.enabled then
        cb(false, 'Discord OAuth is not configured in config.lua.')
        return
    end

    local payload = table.concat({
        'grant_type=authorization_code',
        'client_id=' .. urlEncode(oauth.clientId),
        'client_secret=' .. urlEncode(oauth.clientSecret),
        'code=' .. urlEncode(code or ''),
        'redirect_uri=' .. urlEncode(oauth.redirectUri)
    }, '&')

    httpRequestCompat('https://discord.com/api/v10/oauth2/token', 'POST', payload, {
        ['Content-Type'] = 'application/x-www-form-urlencoded'
    }, function(status, body)
        if tonumber(status or 0) < 200 or tonumber(status or 0) >= 300 then
            cb(false, 'Discord token exchange failed.', body)
            return
        end

        local tokenData = jsonDecode(body or '') or {}
        local accessToken = trim(tokenData.access_token or '')
        if accessToken == '' then
            cb(false, 'Discord did not return an access token.', tokenData)
            return
        end

        httpRequestCompat('https://discord.com/api/v10/users/@me', 'GET', '', {
            ['Authorization'] = 'Bearer ' .. accessToken,
            ['Content-Type'] = 'application/json'
        }, function(status2, body2)
            if tonumber(status2 or 0) < 200 or tonumber(status2 or 0) >= 300 then
                cb(false, 'Discord profile lookup failed.', body2)
                return
            end
            local user = jsonDecode(body2 or '') or {}
            if trim(user.id or '') == '' then
                cb(false, 'Discord profile response was invalid.', user)
                return
            end
            cb(true, user)
        end)
    end)
end

local function webFetchDiscordLink(discordId, cb)
    discordId = trim(discordId or '')
    if discordId == '' then
        cb(nil)
        return
    end
    DB.fetchAll([[
        SELECT *
        FROM mdt_web_discord_links
        WHERE discord_id = ?
        ORDER BY id DESC
        LIMIT 1
    ]], { discordId }, function(rows)
        cb(rows and rows[1] or nil)
    end)
end

local function webPersistSession(session, cb)
    cb = cb or function() end
    session = webNormalizeSessionDates(session or {})

    DB.execute([[
        INSERT INTO mdt_web_sessions (
            session_id, discord_id, username, global_name, avatar,
            linked_name, linked_license, linked_charid, linked_identifier, linked_player_discord,
            linked_role, linked_department, created_at, expires_at, last_seen_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            discord_id = VALUES(discord_id),
            username = VALUES(username),
            global_name = VALUES(global_name),
            avatar = VALUES(avatar),
            linked_name = VALUES(linked_name),
            linked_license = VALUES(linked_license),
            linked_charid = VALUES(linked_charid),
            linked_identifier = VALUES(linked_identifier),
            linked_player_discord = VALUES(linked_player_discord),
            linked_role = VALUES(linked_role),
            linked_department = VALUES(linked_department),
            expires_at = VALUES(expires_at),
            last_seen_at = VALUES(last_seen_at)
    ]], {
        session.session_id or '',
        session.discord_id or '',
        session.username or '',
        session.global_name or '',
        session.avatar or '',
        session.linked_name or '',
        session.linked_license or '',
        session.linked_charid or '',
        session.linked_identifier or '',
        session.linked_player_discord or '',
        session.linked_role or '',
        session.linked_department or '',
        session.created_at,
        session.expires_at,
        session.last_seen_at
    }, function()
        cb(session)
    end)
end

local function webCreateSessionForDiscordUser(discordUser, cb)
    local discordId = trim((discordUser or {}).id or '')
    if discordId == '' then
        cb(nil)
        return
    end

    webFetchDiscordLink(discordId, function(link)
        local session = {
            session_id = randomToken(64),
            discord_id = discordId,
            username = trim(discordUser.username or ''),
            global_name = trim(discordUser.global_name or ''),
            avatar = trim(discordUser.avatar or ''),
            linked_name = link and trim(link.linked_name or '') or '',
            linked_license = link and trim(link.linked_license or '') or '',
            linked_charid = link and trim(link.linked_charid or '') or '',
            linked_identifier = link and trim(link.linked_identifier or '') or '',
            linked_player_discord = link and trim(link.linked_player_discord or '') or '',
            linked_role = link and trim(link.linked_role or '') or '',
            linked_department = link and trim(link.linked_department or '') or '',
            created_at = webSqlNow(0),
            expires_at = webSqlNow(webSessionTtl())
        }
        webPersistSession(session, function(saved)
            cb(saved)
        end)
    end)
end

local function webFetchSession(request, cb)
    local sessionId = webGetSessionToken(request)
    if sessionId == '' then
        cb(nil)
        return
    end

    DB.fetchAll([[
        SELECT *
        FROM mdt_web_sessions
        WHERE session_id = ? AND expires_at >= NOW()
        LIMIT 1
    ]], { sessionId }, function(rows)
        local row = rows and rows[1] or nil
        if not row then
            cb(nil)
            return
        end

webFetchDiscordLink(row.discord_id, function(link)
    if link then
        row.linked_name = trim(link.linked_name or row.linked_name or '')
        row.linked_license = trim(link.linked_license or row.linked_license or '')
        row.linked_charid = trim(link.linked_charid or row.linked_charid or '')
        row.linked_identifier = trim(link.linked_identifier or row.linked_identifier or '')
        row.linked_player_discord = trim(link.linked_player_discord or row.linked_player_discord or '')
        row.linked_role = trim(link.linked_role or row.linked_role or '')
        row.linked_department = trim(link.linked_department or row.linked_department or '')
    end

    row = webNormalizeSessionDates(row)
    row.expires_at = webSqlNow(webSessionTtl())
    row.last_seen_at = webSqlNow(0)

    webPersistSession(row, function()
        cb(row)
    end)
end)
    end)
end

local function webSessionIsLinked(session)
    if type(session) ~= 'table' then return false end
    return trim(session.linked_identifier or '') ~= ''
        or trim(session.linked_license or '') ~= ''
        or trim(session.linked_charid or '') ~= ''
        or trim(session.linked_role or '') ~= ''
end

local function webIsAdminDiscord(discordId)
    discordId = trim(discordId or '')
    for _, entry in ipairs(((Config.Web or {}).adminDiscordIds) or {}) do
        if trim(entry) == discordId then
            return true
        end
    end
    return false
end

local function webIsSupervisorDiscord(discordId)
    discordId = trim(discordId or '')
    if discordId == '' then return false end
    if webIsAdminDiscord(discordId) then return true end
    for _, entry in ipairs(((Config.Web or {}).supervisorDiscordIds) or {}) do
        if trim(entry) == discordId then
            return true
        end
    end
    return false
end

local function webBuildViewer(session, cb)
    session = session or {}
    local isAdminDiscord = webIsAdminDiscord(session.discord_id)
    local isSupervisorDiscord = webIsSupervisorDiscord(session.discord_id)

    local viewer = attachUiSettings({
        name = trim(session.linked_name or session.global_name or session.username or 'Discord User'),
        department = trim(session.linked_department or ((Config.Roles and Config.Roles.civilianDepartment) or 'civilian')),
        grade = 0,
        callsign = '',
        licenseStatus = 'valid',
        discordid = trim(session.discord_id or ''),
        charid = trim(session.linked_charid or ''),
        identifier = trim(session.linked_identifier or ''),
        isAdmin = isAdminDiscord,
        isSupervisor = isSupervisorDiscord,
        isDispatch = false,
        canManageDispatch = isSupervisorDiscord,
        canClearCalls = isSupervisorDiscord,
        canClearWarrants = isSupervisorDiscord,
        canClearBolos = isSupervisorDiscord,
        canAttachDetach = false,
        role = 'civ',
        isLEO = false,
        isCiv = true,
        canUseDMV = isAdminDiscord,
        canUseCiv = true,
        canUseLeoChat = false,
        license = trim(session.linked_license or '')
    })

    fetchEmployeeRowByIdentity({
        license = trim(session.linked_license or ''),
        identifier = trim(session.linked_identifier or ''),
        discordid = trim(session.linked_player_discord or session.discord_id or '')
    }, function(row)
        local access = normalizeEmployeeAccessRow(row or { mdt_role = trim(session.linked_role or 'civ') })

        if row then
            viewer.name = trim(row.name or viewer.name)
            viewer.callsign = trim(row.callsign or viewer.callsign or defaultCallsign(session.linked_charid or session.linked_identifier or session.discord_id))
            viewer.department = sanitizeDepartmentId(row.department) or viewer.department
            viewer.grade = tonumber(row.grade) or viewer.grade
        end

        local role = access.loginRole or trim(session.linked_role or 'civ')
        if role ~= 'dispatch' and role ~= 'leo' and role ~= 'civ' then
            role = access.open and 'leo' or 'civ'
        end
        if role == 'dispatch' and not (access.dispatch or access.admin) then
            role = access.civ and not access.open and 'civ' or 'leo'
        end
        if role == 'civ' and access.open and not access.civ then
            role = 'leo'
        end

        local isDispatchRole = role == 'dispatch'
        local isLeoRole = role == 'leo' or isDispatchRole

        viewer.role = role
        viewer.isLEO = isLeoRole
        viewer.isCiv = not isLeoRole
        viewer.isDispatch = isDispatchRole
        viewer.isAdmin = isAdminDiscord or access.admin
        viewer.isSupervisor = isDispatchRole or isSupervisorDiscord or access.supervisor or viewer.isAdmin
        viewer.canManageDispatch = access.dispatch or isDispatchRole or access.supervisor or viewer.isAdmin
        viewer.canClearCalls = viewer.canManageDispatch
        viewer.canClearWarrants = viewer.canManageDispatch
        viewer.canClearBolos = viewer.canManageDispatch
        viewer.canAttachDetach = isLeoRole or (access.actions and access.actions.attachCalls == true)
        viewer.canUseDMV = access.dmv or isLeoRole or viewer.isAdmin
        viewer.canUseCiv = access.civ or (access.pages and access.pages.civCenter == true) or not isDispatchRole
        viewer.canUseLeoChat = access.leochat or isLeoRole
        viewer.permissions = employeePermPayloadFromRow(row or { mdt_role = role, mdt_perms_json = jsonEncode(access) })

        if isDispatchRole then
            viewer.department = sanitizeDepartmentId(viewer.department) or sanitizeDepartmentId(((Config.Dispatch or {}).defaultDepartment) or 'dispatch') or 'dispatch'
            if trim(viewer.callsign or '') == '' then
                viewer.callsign = defaultCallsign(session.linked_charid or session.linked_identifier or session.discord_id)
            end
        elseif isLeoRole then
            viewer.department = sanitizeDepartmentId(viewer.department) or sanitizeDepartmentId(Config.DefaultDepartment) or (Config.DefaultDepartment or 'police')
            if trim(viewer.callsign or '') == '' then
                viewer.callsign = defaultCallsign(session.linked_charid or session.linked_identifier or session.discord_id)
            end
        else
            viewer.department = trim(session.linked_department or ((Config.Roles and Config.Roles.civilianDepartment) or 'civilian'))
            viewer.callsign = ''
        end

        cb(viewer)
    end)
end

local function webRowsMyCivilians(session, cb)
    session = session or {}
    local ident = {
        license = trim(session.linked_license or ''),
        charid = trim(session.linked_charid or ''),
        discordid = trim(session.linked_player_discord or session.discord_id or '')
    }
    if ident.license == '' and ident.charid == '' and ident.discordid == '' then
        cb({})
        return
    end
    fetchCiviliansForIdentity(ident, cb)
end

local function webConsumeLinkCode(discordUser, code, cb)
    code = trim(code or ''):upper()
    if code == '' then
        cb(false, 'Enter the code from the in-game Link button first.')
        return
    end

    DB.fetchAll([[
        SELECT *
        FROM mdt_web_link_codes
        WHERE code = ? AND used_at IS NULL AND expires_at >= NOW()
        LIMIT 1
    ]], { code }, function(rows)
        local row = rows and rows[1] or nil
        if not row then
            cb(false, 'That code is invalid or expired.')
            return
        end

        local now = webSqlNow(0)
        DB.execute([[
            INSERT INTO mdt_web_discord_links (
                discord_id, username, global_name, avatar,
                linked_name, linked_license, linked_charid, linked_identifier, linked_player_discord,
                linked_role, linked_department, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                username = VALUES(username),
                global_name = VALUES(global_name),
                avatar = VALUES(avatar),
                linked_name = VALUES(linked_name),
                linked_license = VALUES(linked_license),
                linked_charid = VALUES(linked_charid),
                linked_identifier = VALUES(linked_identifier),
                linked_player_discord = VALUES(linked_player_discord),
                linked_role = VALUES(linked_role),
                linked_department = VALUES(linked_department),
                updated_at = VALUES(updated_at)
        ]], {
            trim(discordUser.id or ''),
            trim(discordUser.username or ''),
            trim(discordUser.global_name or ''),
            trim(discordUser.avatar or ''),
            trim(row.player_name or ''),
            trim(row.license or ''),
            trim(row.charid or ''),
            trim(row.identifier or ''),
            trim(row.player_discord or ''),
            trim(row.role or ''),
            trim(row.department or ''),
            now,
            now
        }, function()
            DB.execute([[
                UPDATE mdt_web_link_codes
                SET used_at = ?, used_by_discord = ?
                WHERE code = ?
            ]], { now, trim(discordUser.id or ''), code }, function()
                cb(true, row)
            end)
        end)
    end)
end

local function webCanReadWithSession(request, query, cb)
    if not (Config.Web and Config.Web.enabled) then
        cb(false, 'Web mode disabled in config.', nil)
        return
    end

    local tokenAllowed, tokenReason = webCanRead(request, query)
    if tokenAllowed then
        cb(true, nil, nil)
        return
    end

    webFetchSession(request, function(session)
        if session then
            cb(true, nil, session)
        else
            cb(false, tokenReason or 'Unauthorized', nil)
        end
    end)
end

local function webServeStatic(response, path)
    local rel = path
    if rel == '/' or rel == '' then rel = '/index.html' end
    if rel:find('%.%.', 1, true) then
        webResponse(response, 400, 'Bad request', 'text/plain; charset=utf-8')
        return
    end

    local candidates = {}
    if rel == '/postals.json' then
        candidates = { 'config/postals.json', 'postals.json' }
    else
        rel = rel:gsub('^/+', '')
        candidates = {
            'html/' .. rel,
            rel
        }
        if not rel:find('%.') then
            table.insert(candidates, 'html/index.html')
        end
    end

    for _, filePath in ipairs(candidates) do
        local blob = LoadResourceFile(RESOURCE_NAME, filePath)
        if blob and blob ~= '' then
            webResponse(response, 200, blob, webMimeType(filePath), {
                ['Access-Control-Allow-Origin'] = '*'
            })
            return
        end
    end

    webResponse(response, 404, 'Not found', 'text/plain; charset=utf-8')
end

local function webRowsUnits()
    local arr = {}
    for _, u in pairs(Units) do
        arr[#arr + 1] = u
    end
    table.sort(arr, function(a, b)
        return tostring(a.callsign or a.name or '') < tostring(b.callsign or b.name or '')
    end)
    return arr
end

local function webRowsCalls(cb)
    DB.fetchAll([[
        SELECT call_id AS id, caller, message, location, postal, status, created_at, updated_at, coords_json
        FROM mdt_calls
        ORDER BY call_id DESC
        LIMIT 100
    ]], {}, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            row.coords = jsonDecode(row.coords_json or '') or {}
            row.coords_json = nil
        end
        cb(rows)
    end)
end

local function webRowsBolos(cb)
    DB.fetchAll([[
        SELECT id, type, data, created_at
        FROM mdt_bolos
        ORDER BY id DESC
        LIMIT 100
    ]], {}, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            row.body = jsonDecode(row.data) or {}
            row.data = nil
        end
        cb(rows)
    end)
end

local function webRowsReports(cb)
    DB.fetchAll([[
        SELECT id, type, data, created_at
        FROM mdt_reports
        ORDER BY id DESC
        LIMIT 100
    ]], {}, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            row.body = jsonDecode(row.data) or {}
            row.data = nil
        end
        mergeAz5PDLegacyReports(rows, nil, cb)
    end)
end

local function webRowsWarrants(cb)
    DB.fetchAll([[
        SELECT id, target_name, target_charid, reason, status, created_by, created_discord, created_at
        FROM mdt_warrants
        ORDER BY id DESC
        LIMIT 100
    ]], {}, function(rows)
        cb(rows or {})
    end)
end

local function webRowsActionLog(cb)
    DB.fetchAll([[
        SELECT id, officer_name, officer_discord, action, target, meta AS meta_json, created_at
        FROM mdt_action_log
        ORDER BY id DESC
        LIMIT 100
    ]], {}, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            row.meta = jsonDecode(row.meta_json or '') or {}
            row.meta_json = nil
        end
        cb(rows)
    end)
end

local function webRowsNameSearch(query, cb)
    local first = trim((query.first or ''))
    local last = trim((query.last or ''))
    local term = trim((query.term or (first .. ' ' .. last)))
    if term == '' then
        cb({ term = '', citizens = {}, records = {} })
        return
    end
    local likeTerm = '%' .. lower(term) .. '%'
    DB.fetchAll(([[
        SELECT c.id, c.name, c.charid, c.discordid, c.license, c.active_department, c.license_status, c.mugshot, ls.last_seen
        FROM %s c
        LEFT JOIN mdt_last_seen ls ON ls.charid = c.charid
        WHERE LOWER(c.name) LIKE ?
        ORDER BY c.name ASC
        LIMIT 50
    ]]):format(qTable('citizens')), { likeTerm }, function(citizenRows)
        citizenRows = citizenRows or {}
        for _, row in ipairs(citizenRows) do
            row.flags = { flags = {}, notes = '' }
            row.quick_notes = {}
        end
        DB.fetchAll([[
            SELECT id, target_type, target_value, rtype, title, description, creator_identifier, timestamp
            FROM mdt_id_records
            WHERE target_type = 'name' AND LOWER(target_value) LIKE ?
            ORDER BY timestamp DESC
            LIMIT 100
        ]], { likeTerm }, function(recordRows)
            mergeAz5PDLegacyNameSearch(term, likeTerm, citizenRows or {}, recordRows or {}, function(mergedCitizens, mergedRecords)
                enrichCitizenRowsWithAssets(mergedCitizens, function(enrichedRows)
                    cb({ term = term, citizens = enrichedRows or mergedCitizens, records = mergedRecords or {} })
                end)
            end)
        end)
    end)
end

local function webRowsPlateSearch(query, cb)
    local plate = trim(query.plate or query.term or '')
    if plate == '' then
        cb({ term = '', vehicles = {}, records = {} })
        return
    end
    plate = upper(plate)
    runPlateSearch(0, plate, query or {}, function(vehicles, records)
        cb({ term = plate, vehicles = vehicles or {}, records = records or {} })
    end)
end

local function webRowsWeaponSearch(query, cb)
    local serial = trim(query.serial or query.term or '')
    if serial == '' then
        cb({ term = '', weapons = {}, records = {} })
        return
    end
    local likeTerm = '%' .. lower(serial) .. '%'
    DB.fetchAll(([[
        SELECT id, serial, type, owner, owner_name, owner_identifier, discordid, notes
        FROM %s
        WHERE LOWER(serial) LIKE ?
        ORDER BY serial ASC
        LIMIT 50
    ]]):format(qTable('weapons')), { likeTerm }, function(weaponRows)
        DB.fetchAll([[
            SELECT id, target_type, target_value, rtype, title, description, timestamp
            FROM mdt_id_records
            WHERE target_type = 'weapon' AND LOWER(target_value) LIKE ?
            ORDER BY timestamp DESC
            LIMIT 100
        ]], { likeTerm }, function(recordRows)
            cb({ term = serial, weapons = weaponRows or {}, records = recordRows or {} })
        end)
    end)
end

local function webRowsReportSearch(query, cb)
    local term = trim(query.query or query.term or '')
    if term == '' then
        cb({ rows = {} })
        return
    end
    local reportId = tonumber(term) or 0
    local like = ('%%%s%%'):format(term)
    DB.fetchAll([[
        SELECT id, type, data, created_at
        FROM mdt_reports
        WHERE (? = '' OR id = ? OR data LIKE ? OR type LIKE ?)
        ORDER BY id DESC
        LIMIT 100
    ]], { term, reportId, like, like }, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            row.body = jsonDecode(row.data) or {}
            row.data = nil
        end
        mergeAz5PDLegacyReports(rows, term, function(mergedRows)
            cb({ rows = mergedRows })
        end)
    end)
end

local function webRowsCivilians(query, cb)
    local term = trim(query.term or query.name or '')
    if term == '' then
        cb({ rows = {} })
        return
    end
    local like = ('%%%s%%'):format(term)
    DB.fetchAll(([[
        SELECT id, name, charid, discordid, license, license_status, metadata, created_at
        FROM %s
        WHERE (name LIKE ? OR charid LIKE ? OR discordid LIKE ? OR license LIKE ?)
        ORDER BY id DESC
        LIMIT 100
    ]]):format(qTable('citizens')), { like, like, like, like }, function(rows)
        rows = rows or {}
        enrichCitizenRowsWithAssets(rows, function(enrichedRows)
            cb({ rows = enrichedRows or rows })
        end)
    end)
end

local function webRowsDMV(query, cb)
    local term = trim(query.term or query.name or query.plate or '')
    if term == '' then
        cb({ rows = {} })
        return
    end
    local like = ('%%%s%%'):format(term)
    DB.fetchAll(([[
        SELECT c.id, c.name, c.charid, c.discordid, c.license, c.license_status, c.metadata, c.created_at
        FROM %s c
        WHERE (
            c.name LIKE ?
            OR c.charid LIKE ?
            OR c.license LIKE ?
            OR EXISTS (
                SELECT 1
                FROM %s v
                WHERE LOWER(v.plate) LIKE ?
                  AND (
                    (c.charid IS NOT NULL AND c.charid != '' AND v.owner_identifier = c.charid)
                    OR ((c.charid IS NULL OR c.charid = '') AND c.license IS NOT NULL AND c.license != '' AND v.owner_identifier = c.license)
                    OR v.owner_identifier = CAST(c.id AS CHAR)
                  )
            )
        )
        ORDER BY c.name ASC
        LIMIT 100
    ]]):format(qTable('citizens'), qTable('vehicles')), { like, like, like, like }, function(rows)
        rows = rows or {}
        enrichCitizenRowsWithAssets(rows, function(enrichedRows)
            for _, row in ipairs(enrichedRows or rows) do
                row.vehicle_count = tonumber(row.vehicle_count) or #((row.vehicles) or {})
                row.weapon_count = tonumber(row.weapon_count) or #((row.weapons) or {})
            end
            cb({ rows = enrichedRows or rows })
        end)
    end)
end

local function webRowsCallHistory(query, cb)
    local term = trim(query.query or query.term or '')
    if term == '' then
        cb({ rows = {} })
        return
    end
    local callId = tonumber(term) or 0
    local like = ('%%%s%%'):format(term)
    DB.fetchAll([[
        SELECT call_id, caller, message, location, postal, status, created_at, updated_at
        FROM mdt_calls
        WHERE (call_id = ? OR caller LIKE ? OR location LIKE ? OR message LIKE ? OR postal LIKE ?)
        ORDER BY call_id DESC
        LIMIT 100
    ]], { callId, like, like, like, like }, function(rows)
        cb({ rows = rows or {} })
    end)
end

local function webRowsCallRoom(query, cb)
    local callId = tonumber(query.id or query.callId or 0) or 0
    if callId <= 0 then
        cb({ callId = 0, messages = {}, notes = {} })
        return
    end
    DB.fetchAll([[SELECT sender, source, message, time FROM mdt_call_messages WHERE call_id = ? ORDER BY id ASC LIMIT 200]], { callId }, function(messages)
        DB.fetchAll([[SELECT author, note, created_at FROM mdt_call_notes WHERE call_id = ? ORDER BY id ASC LIMIT 200]], { callId }, function(notes)
            local snapshot = callRoomSnapshot(callId)
            snapshot.messages = messages or {}
            snapshot.notes = notes or {}
            local call = Calls[callId]
            if call then
                snapshot.location = call.location
                snapshot.postal = call.postal
            end
            cb(snapshot)
        end)
    end)
end

local function webRowsLiveChat(cb)
    cb(ChatHistory or {})
end


function webFetchLinkedViewer(request, cb)
    webFetchSession(request, function(session)
        if not session then
            cb(nil, nil, 'Login with Discord first.')
            return
        end
        if not webSessionIsLinked(session) then
            cb(session, nil, 'Link your in-game account first.')
            return
        end
        webBuildViewer(session, function(viewer)
            cb(session, viewer, nil)
        end)
    end)
end

function webLogAction(session, action, target, meta)
    local officerName = trim((session and (session.linked_name or session.global_name or session.username)) or 'Discord User')
    if officerName == '' then officerName = 'Discord User' end
    local officerDiscord = trim((session and session.discord_id) or '')

    local metaJson
    if type(meta) == 'table' then
        metaJson = jsonEncode(meta)
    elseif type(meta) == 'string' and meta ~= '' then
        metaJson = jsonEncode({ text = meta })
    else
        metaJson = jsonEncode({})
    end

    DB.insert([[
        INSERT INTO mdt_action_log (officer_name, officer_discord, action, target, meta)
        VALUES (?, ?, ?, ?, ?)
    ]], { officerName, officerDiscord, action or 'unknown', target or '', metaJson })
end

function webCanUseLeo(viewer)
    return type(viewer) == 'table' and viewer.isLEO == true
end

function webCanManageDispatch(viewer)
    return webCanUseLeo(viewer) and (viewer.canManageDispatch == true or viewer.isSupervisor == true or viewer.isAdmin == true)
end

function webUnitSourceKey(session)
    local base = trim((session and (session.discord_id or session.linked_player_discord or session.linked_identifier or session.linked_license)) or '')
    if base == '' then
        base = randomToken(12)
    end
    return 'web:' .. base
end

webSyncCallStatus = function(callId)
    local call = Calls[callId]
    if not call then return end
    local nextStatus = (#(call.units or {}) > 0) and 'ENROUTE' or 'PENDING'
    call.status = nextStatus
    DB.execute([[UPDATE mdt_calls SET status = ? WHERE call_id = ?]], { nextStatus, callId })
end

function webAttachSessionToCall(session, viewer, callId, cb)
    callId = tonumber(callId) or 0
    local call = Calls[callId]
    if callId <= 0 or not call then
        cb(false, 'Call not found.')
        return
    end

    local unitKey = webUnitSourceKey(session)
    call.units = call.units or {}
    for _, u in ipairs(call.units) do
        if tostring(u.id or '') == unitKey then
            ensureCallRoom(callId)
            cb(true, callRoomSnapshot(callId))
            return
        end
    end

    local entry = {
        id = unitKey,
        name = viewer.name or 'Web Unit',
        callsign = viewer.callsign or '',
        department = viewer.department or Config.DefaultDepartment or 'police',
        status = 'WEB'
    }
    table.insert(call.units, entry)
    ensureCallRoom(callId)
    DB.execute([[INSERT INTO mdt_call_units (call_id, unit_source, unit_name, unit_callsign) VALUES (?, ?, ?, ?)]], {
        callId,
        unitKey,
        entry.name,
        entry.callsign
    })
    webSyncCallStatus(callId)
    triggerOnDutyClients('az_mdt:client:callUpdated', call)
    cb(true, callRoomSnapshot(callId))
end

function webDetachSessionFromCall(session, viewer, callId, cb)
    callId = tonumber(callId) or 0
    local call = Calls[callId]
    if callId <= 0 or not call then
        cb(false, 'Call not found.')
        return
    end

    local unitKey = webUnitSourceKey(session)
    local kept = {}
    local removed = false
    for _, u in ipairs(call.units or {}) do
        if tostring(u.id or '') == unitKey then
            removed = true
        else
            kept[#kept + 1] = u
        end
    end
    call.units = kept
    DB.execute([[DELETE FROM mdt_call_units WHERE call_id = ? AND unit_source = ?]], { callId, unitKey })
    webSyncCallStatus(callId)
    triggerOnDutyClients('az_mdt:client:callUpdated', call)
    cb(true, { removed = removed, snapshot = callRoomSnapshot(callId) })
end

if Config.Web and Config.Web.enabled then
    SetHttpHandler(function(request, response)
        local path, query = webParsePathAndQuery(request.path or '/')
        local method = string.upper(tostring(request.method or 'GET'))

        if method == 'OPTIONS' then
            webResponse(response, 204, '', 'text/plain; charset=utf-8', {
                ['Access-Control-Allow-Origin'] = '*',
                ['Access-Control-Allow-Methods'] = 'GET, OPTIONS',
                ['Access-Control-Allow-Headers'] = 'Content-Type, X-AZ-MDT-TOKEN'
            })
            return
        end

        if path == '/auth/login' then
            local oauth = webGetOauthConfig(request)
            if not oauth.enabled then
                webResponse(response, 302, '', 'text/plain; charset=utf-8', {
                    ['Location'] = webAbsoluteUrl(request, '?authError=' .. urlEncode('Discord OAuth is not configured.'))
                })
                return
            end

            local state = randomToken(32)
            webResponse(response, 302, '', 'text/plain; charset=utf-8', {
                ['Location'] = webBuildDiscordAuthorizeUrl(request, state),
                ['Set-Cookie'] = webBuildStateCookie(state)
            })
            return
        elseif path == '/auth/callback' then
            local expectedState = webGetStateToken(request)
            local providedState = trim((query and query.state) or '')
            local code = trim((query and query.code) or '')
            if code == '' or expectedState == '' or expectedState ~= providedState then
                webResponse(response, 302, '', 'text/plain; charset=utf-8', {
                    ['Location'] = webAbsoluteUrl(request, '?authError=' .. urlEncode('Discord login could not be verified.'))
                })
                return
            end

            webExchangeDiscordCode(request, code, function(ok, result, extra)
                if not ok then
                    webResponse(response, 302, '', 'text/plain; charset=utf-8', {
                        ['Location'] = webAbsoluteUrl(request, '?authError=' .. urlEncode(result or 'Discord login failed.'))
                    })
                    return
                end

                webCreateSessionForDiscordUser(result, function(session)
                    if not session then
                        webResponse(response, 302, '', 'text/plain; charset=utf-8', {
                            ['Location'] = webAbsoluteUrl(request, '?authError=' .. urlEncode('Could not create a website session.'))
                        })
                        return
                    end

                    webResponse(response, 302, '', 'text/plain; charset=utf-8', {
                        ['Location'] = webAbsoluteUrl(request, ''),
                        ['Set-Cookie'] = webBuildCookie(session.session_id, webSessionTtl())
                    })
                end)
            end)
            return
        elseif path == '/auth/logout' then
            webResponse(response, 302, '', 'text/plain; charset=utf-8', {
                ['Location'] = webAbsoluteUrl(request, ''),
                ['Set-Cookie'] = webBuildCookie('', 0)
            })
            return
        end

        if path:sub(1, 5) == '/api/' then
            local route = path:sub(6)
            if method ~= 'GET' then
                webJson(response, 405, { ok = false, error = 'This web API currently supports GET only.' })
                return
            end

            if route == 'bootstrap' then
                local oauth = webGetOauthConfig(request)
                webFetchSession(request, function(session)
                    local auth = {
                        configured = oauth.enabled,
                        authenticated = session ~= nil,
                        linked = webSessionIsLinked(session),
                        loginUrl = webAbsoluteUrl(request, 'auth/login'),
                        logoutUrl = webAbsoluteUrl(request, 'auth/logout'),
                        baseUrl = webAbsoluteUrl(request, ''),
                        user = session and {
                            discordId = trim(session.discord_id or ''),
                            username = trim(session.username or ''),
                            globalName = trim(session.global_name or ''),
                            avatar = trim(session.avatar or ''),
                            linkedName = trim(session.linked_name or '')
                        } or nil
                    }

                    if session then
                        webBuildViewer(session, function(viewer)
                            webJson(response, 200, {
                                ok = true,
                                title = (Config.Web and Config.Web.title) or 'Az MDT Web',
                                notice = (Config.Web and Config.Web.notice) or 'Discord-authenticated website mode is active.',
                                web = Config.Web or {},
                                departments = Config.Departments or {},
                                tts = Config.TTS or {},
                                theme = getThemeState(),
                                authenticated = true,
                                linked = webSessionIsLinked(session),
                                auth = auth,
                                viewer = viewer
                            })
                        end)
                    else
                        webJson(response, 200, {
                            ok = true,
                            title = (Config.Web and Config.Web.title) or 'Az MDT Web',
                            notice = oauth.enabled and 'Sign in with Discord to access the fullscreen MDT website.' or 'Discord OAuth is not configured in config.lua yet.',
                            web = Config.Web or {},
                            departments = Config.Departments or {},
                            tts = Config.TTS or {},
                            theme = getThemeState(),
                            authenticated = false,
                            linked = false,
                            auth = auth,
                            viewer = {
                                name = (Config.Web and Config.Web.title) or 'Az MDT Web',
                                department = 'browser',
                                grade = 0,
                                status = 'WEB',
                                role = 'civ',
                                isAdmin = false,
                                ui = {
                                    departments = Config.Departments or {},
                                    tts = Config.TTS or {}
                                },
                                tts = Config.TTS or {}
                            }
                        })
                    end
                end)
                return
            elseif route == 'auth/link' then
                webFetchSession(request, function(session)
                    if not session then
                        webJson(response, 401, { ok = false, error = 'Login with Discord first.' })
                        return
                    end
                    local code = trim((query and query.code) or '')
                    local discordUser = {
                        id = session.discord_id,
                        username = session.username,
                        global_name = session.global_name,
                        avatar = session.avatar
                    }
                    webConsumeLinkCode(discordUser, code, function(ok, row)
                        if not ok then
                            webJson(response, 400, { ok = false, error = row or 'Invalid link code.' })
                            return
                        end
                        webFetchSession(request, function(updated)
                            webJson(response, 200, { ok = true, linked = webSessionIsLinked(updated), row = row, message = 'Website linked to your in-game account.' })
                        end)
                    end)
                end)
                return
            elseif route == 'my/civilians' then
                webFetchSession(request, function(session)
                    if not session then
                        webJson(response, 401, { ok = false, error = 'Login with Discord first.' })
                        return
                    end
                    if not webSessionIsLinked(session) then
                        webJson(response, 403, { ok = false, error = 'Link your in-game account to view owned civilians.' })
                        return
                    end
                    webRowsMyCivilians(session, function(rows)
                        webJson(response, 200, { ok = true, rows = rows or {} })
                    end)
                end)
                return
            end

            if route:sub(1, 7) == 'action/' then
                webFetchLinkedViewer(request, function(session, viewer, err)
                    if not viewer then
                        webJson(response, 403, { ok = false, error = err or 'Unauthorized' })
                        return
                    end

                    local action = route:sub(8)
                    local q = query or {}

                    if action == 'create-bolo' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local boloType = trim(q.type or q.boloType or 'vehicle')
                        local title = trim(q.title or '')
                        local details = trim(q.details or q.description or '')
                        local body = { title = title, type = boloType, details = details }
                        DB.insert([[INSERT INTO mdt_bolos (type, data) VALUES (?, ?)]], { boloType, jsonEncode(body) }, function(insertId)
                            DB.fetchAll([[SELECT id, type, data, created_at FROM mdt_bolos ORDER BY id DESC LIMIT 200]], {}, function(rows)
                                rows = rows or {}
                                for _, row in ipairs(rows) do
                                    row.body = jsonDecode(row.data or '') or {}
                                    row.data = nil
                                end
                                triggerMdtViewers('az_mdt:client:boloList', rows)
                                if tostring((((Config.TTS or {}).boloMode) or 'all_onduty')) ~= 'none' then
                                    DB.fetchAll([[SELECT id, type, data, created_at FROM mdt_bolos WHERE id = ? LIMIT 1]], { insertId }, function(single)
                                        local created = single and single[1] or nil
                                        if created then
                                            created.body = jsonDecode(created.data or '') or {}
                                            created.data = nil
                                            triggerOnDutyClients('az_mdt:client:boloAlert', created)
                                        end
                                    end)
                                end
                                webLogAction(session, 'web_bolo_create', 'BOLO #' .. tostring(insertId), { type = boloType, title = title })
                                webJson(response, 200, { ok = true, rows = rows, message = ('BOLO #%s created.'):format(tostring(insertId)) })
                            end)
                        end)
                        return
                    elseif action == 'create-report' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local rType = trim(q.type or q.reportType or 'incident')
                        local info = trim(q.info or q.body or '')
                        local title = trim(q.title or '')
                        local targetType = trim(q.targetType or q.target_type or '')
                        local targetValue = trim(q.targetValue or q.target_value or '')
                        local body = { title = title, type = rType, info = info, officer = viewer.name or 'Discord User' }
                        DB.insert([[INSERT INTO mdt_reports (type, data) VALUES (?, ?)]], { rType, jsonEncode(body) }, function(insertId)
                            if targetType ~= '' and targetValue ~= '' then
                                DB.insert([[INSERT INTO mdt_id_records (target_type, target_value, rtype, title, description) VALUES (?, ?, ?, ?, ?)]], { targetType, targetValue, rType, title, info })
                            end
                            DB.fetchAll([[SELECT id, type, data, created_at FROM mdt_reports WHERE id = ? LIMIT 1]], { insertId }, function(rows)
                                local row = rows and rows[1] or nil
                                if row then
                                    row.body = jsonDecode(row.data or '') or {}
                                    row.data = nil
                                    triggerMdtViewers('az_mdt:client:reportCreated', row)
                                end
                                webLogAction(session, 'web_report_create', 'Report #' .. tostring(insertId), { type = rType, title = title, targetType = targetType, targetValue = targetValue })
                                webJson(response, 200, { ok = true, row = row, message = ('Report #%s created.'):format(tostring(insertId)) })
                            end)
                        end)
                        return
                    elseif action == 'create-quick-note' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local targetType = trim(q.targetType or q.target_type or 'name')
                        local targetValue = trim(q.targetValue or q.target_value or '')
                        local note = trim(q.note or q.text or '')
                        if targetValue == '' or note == '' then
                            webJson(response, 400, { ok = false, error = 'Target and note are required.' })
                            return
                        end
                        DB.insert([[INSERT INTO mdt_quick_notes (target_type, target_value, note, creator_name, creator_discord) VALUES (?, ?, ?, ?, ?)]], { targetType, targetValue, note, viewer.name or 'Discord User', trim(session.discord_id or '') }, function(insertId)
                            webLogAction(session, 'web_quick_note_create', targetType .. ':' .. targetValue, { id = insertId, note = note })
                            webJson(response, 200, { ok = true, id = insertId, message = ('Quick note saved for %s.'):format(targetValue) })
                        end)
                        return
                    elseif action == 'delete-quick-note' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local noteId = tonumber(q.id) or 0
                        if noteId <= 0 then
                            webJson(response, 400, { ok = false, error = 'Invalid note id.' })
                            return
                        end
                        DB.execute([[DELETE FROM mdt_quick_notes WHERE id = ?]], { noteId }, function()
                            webLogAction(session, 'web_quick_note_delete', tostring(noteId), {})
                            webJson(response, 200, { ok = true, message = 'Quick note deleted.' })
                        end)
                        return
                    elseif action == 'set-identity-flags' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local targetType = trim(q.targetType or q.target_type or 'name')
                        local targetValue = trim(q.targetValue or q.target_value or '')
                        if targetValue == '' then
                            webJson(response, 400, { ok = false, error = 'Target is required.' })
                            return
                        end
                        local rawFlags = jsonDecode(q.flags or q.flags_json or '') or {}
                        local cleaned = {}
                        for k, v in pairs(rawFlags) do
                            if VALID_FLAGS[k] and v then
                                cleaned[k] = true
                            end
                        end
                        DB.execute([[
                            INSERT INTO mdt_identity_flags (target_type, target_value, flags_json, notes, updated_by)
                            VALUES (?, ?, ?, ?, ?)
                            ON DUPLICATE KEY UPDATE
                                flags_json = VALUES(flags_json),
                                notes = VALUES(notes),
                                updated_by = VALUES(updated_by),
                                updated_at = CURRENT_TIMESTAMP
                        ]], { targetType, targetValue, jsonEncode(cleaned), trim(q.notes or ''), viewer.name or 'Discord User' }, function()
                            webLogAction(session, 'web_identity_flags_update', targetType .. ':' .. targetValue, cleaned)
                            webJson(response, 200, { ok = true, message = ('Flags updated for %s.'):format(targetValue) })
                        end)
                        return
                    elseif action == 'create-warrant' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local targetName = trim(q.targetName or q.name or '')
                        local targetCharid = trim(q.charid or q.targetCharid or '')
                        local reasonText = trim(q.reason or '')
                        if targetName == '' or reasonText == '' then
                            webJson(response, 400, { ok = false, error = 'Target name and reason are required.' })
                            return
                        end
                        DB.insert([[INSERT INTO mdt_warrants (target_name, target_charid, reason, status, created_by, created_discord) VALUES (?, ?, ?, 'active', ?, ?)]], {
                            targetName,
                            targetCharid ~= '' and targetCharid or nil,
                            reasonText,
                            viewer.name or 'Discord User',
                            trim(session.discord_id or '')
                        }, function(insertId)
                            DB.fetchAll([[SELECT id, target_name, target_charid, reason, status, created_by, created_discord, created_at FROM mdt_warrants ORDER BY id DESC LIMIT 200]], {}, function(rows)
                                triggerMdtViewers('az_mdt:client:warrantsList', rows or {})
                                webLogAction(session, 'web_warrant_create', targetName, { id = insertId, charid = targetCharid, reason = reasonText })
                                webJson(response, 200, { ok = true, rows = rows or {}, message = ('Warrant created for %s.'):format(targetName) })
                            end)
                        end)
                        return
                    elseif action == 'live-chat-send' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local msgText = trim(q.message or '')
                        if msgText == '' then
                            webJson(response, 400, { ok = false, error = 'Message is required.' })
                            return
                        end
                        local payload = { sender = viewer.callsign ~= '' and (viewer.callsign .. ' | ' .. (viewer.name or '')) or (viewer.name or 'Discord User'), source = viewer.callsign or ('web:' .. trim(session.discord_id or '')), message = msgText, time = os.date('%H:%M:%S') }
                        pushChatMessage(payload, false)
                        triggerMdtViewers('az_mdt:client:liveChatMessage', payload)
                        webJson(response, 200, { ok = true, rows = ChatHistory or {} })
                        return
                    elseif action == 'leo-chat-send' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local msgText = trim(q.message or '')
                        if msgText == '' then
                            webJson(response, 400, { ok = false, error = 'Message is required.' })
                            return
                        end
                        local payload = { sender = viewer.callsign ~= '' and (viewer.callsign .. ' | ' .. (viewer.name or '')) or (viewer.name or 'Discord User'), source = viewer.callsign or ('web:' .. trim(session.discord_id or '')), message = msgText, time = os.date('%H:%M:%S') }
                        pushLeoDutyChat(payload)
                        triggerMdtViewers('az_mdt:client:leoChatMessage', payload)
                        webJson(response, 200, { ok = true, rows = LeoDutyChat or {} })
                        return
                    elseif action == 'call-room-send' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local callId = tonumber(q.callId or q.id) or 0
                        local msgText = trim(q.message or '')
                        if callId <= 0 or msgText == '' then
                            webJson(response, 400, { ok = false, error = 'Call and message are required.' })
                            return
                        end
                        local payload = { callId = callId, sender = viewer.callsign ~= '' and (viewer.callsign .. ' | ' .. (viewer.name or '')) or (viewer.name or 'Discord User'), source = viewer.callsign or ('web:' .. trim(session.discord_id or '')), message = msgText, time = os.date('%H:%M:%S') }
                        local room = ensureCallRoom(callId)
                        room.messages[#room.messages + 1] = payload
                        DB.insert([[INSERT INTO mdt_call_messages (call_id, sender, source, message, time) VALUES (?, ?, ?, ?, ?)]], { callId, payload.sender, payload.source, payload.message, payload.time })
                        triggerOnDutyClients('az_mdt:client:callRoomMessage', payload)
                        webRowsCallRoom({ id = callId }, function(snapshot) webJson(response, 200, { ok = true, room = snapshot }) end)
                        return
                    elseif action == 'call-room-note' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local callId = tonumber(q.callId or q.id) or 0
                        local noteText = trim(q.note or '')
                        if callId <= 0 or noteText == '' then
                            webJson(response, 400, { ok = false, error = 'Call and note are required.' })
                            return
                        end
                        local payload = { callId = callId, author = viewer.callsign ~= '' and (viewer.callsign .. ' | ' .. (viewer.name or '')) or (viewer.name or 'Discord User'), note = noteText, created_at = os.date('%Y-%m-%d %H:%M:%S') }
                        local room = ensureCallRoom(callId)
                        room.notes[#room.notes + 1] = payload
                        DB.insert([[INSERT INTO mdt_call_notes (call_id, author, note) VALUES (?, ?, ?)]], { callId, payload.author, payload.note })
                        triggerOnDutyClients('az_mdt:client:callRoomNote', payload)
                        webRowsCallRoom({ id = callId }, function(snapshot) webJson(response, 200, { ok = true, room = snapshot }) end)
                        return
                    elseif action == 'attach-call' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        webAttachSessionToCall(session, viewer, q.id or q.callId, function(ok, payload)
                            if not ok then
                                webJson(response, 400, { ok = false, error = payload or 'Could not attach to call.' })
                                return
                            end
                            webRowsCalls(function(rows) webJson(response, 200, { ok = true, rows = rows, room = payload, message = 'Attached to call.' }) end)
                        end)
                        return
                    elseif action == 'detach-call' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        webDetachSessionFromCall(session, viewer, q.id or q.callId, function(ok, payload)
                            if not ok then
                                webJson(response, 400, { ok = false, error = payload or 'Could not detach from call.' })
                                return
                            end
                            webRowsCalls(function(rows) webJson(response, 200, { ok = true, rows = rows, room = payload and payload.snapshot or nil, removed = payload and payload.removed or false, message = 'Detached from call.' }) end)
                        end)
                        return
                    elseif action == 'dispatch-status-check' then
                        if not webCanManageDispatch(viewer) then
                            webJson(response, 403, { ok = false, error = 'Dispatch, supervisor, or admin access required.' })
                            return
                        end
                        local targetId = tonumber(q.targetId or q.id or q.sourceId) or 0
                        if targetId <= 0 or not UnitMeta[targetId] then
                            webJson(response, 400, { ok = false, error = 'Unit not found.' })
                            return
                        end
                        local sender = viewer.callsign ~= '' and (viewer.callsign .. ' | ' .. (viewer.name or 'Dispatch')) or (viewer.name or 'Dispatch')
                        TriggerClientEvent('az_mdt:client:dispatchStatusCheck', targetId, { from = sender, dispatcher = sender, time = os.date('%H:%M:%S') })
                        webLogAction(session, 'web_dispatch_status_check', tostring(targetId), { target = UnitMeta[targetId].callsign or UnitMeta[targetId].name or targetId })
                        webJson(response, 200, { ok = true, message = 'Status check sent.' })
                        return
                    elseif action == 'set-unit-status' then
                        if not webCanManageDispatch(viewer) then
                            webJson(response, 403, { ok = false, error = 'Dispatch, supervisor, or admin access required.' })
                            return
                        end
                        local targetId = tonumber(q.targetId or q.id or q.sourceId) or 0
                        local status = upper(trim(q.status or 'AVAILABLE'))
                        local valid = { AVAILABLE=true, UNAVAILABLE=true, ENROUTE=true, ONSCENE=true, TRANSPORT=true, HOSPITAL=true, OFFDUTY=true }
                        if targetId <= 0 or not valid[status] or not UnitMeta[targetId] then
                            webJson(response, 400, { ok = false, error = 'Invalid unit or status.' })
                            return
                        end
                        setUnitStatus(targetId, status, UnitMeta[targetId])
                        TriggerClientEvent('az_mdt:client:notify', targetId, { type = 'info', title = 'Dispatch Update', message = ('Your status was updated to %s by dispatch.'):format(status) })
                        webLogAction(session, 'web_set_unit_status', tostring(targetId), { status = status })
                        webJson(response, 200, { ok = true, rows = webRowsUnits(), message = ('Unit updated to %s.'):format(status) })
                        return
                    elseif action == 'update-unit-profile' then
                        if not webCanUseLeo(viewer) then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local nextDepartment = sanitizeDepartmentId(q.department or viewer.department)
                        if not nextDepartment then
                            webJson(response, 400, { ok = false, error = 'Invalid department.' })
                            return
                        end
                        local nextName = trim(q.name or viewer.name or 'Discord User')
                        if nextName == '' then nextName = viewer.name or 'Discord User' end
                        if #nextName > 48 then nextName = nextName:sub(1, 48) end
                        local nextCallsign = trim(q.callsign or viewer.callsign or '')
                        local ident = {
                            identifier = trim(session.linked_identifier or ''),
                            license = trim(session.linked_license or ''),
                            discordid = trim(session.linked_player_discord or session.discord_id or ''),
                            charid = trim(session.linked_charid or session.linked_identifier or session.linked_license or session.discord_id or ''),
                            name = trim(session.linked_name or session.global_name or session.username or 'Discord User')
                        }
                        persistOfficerProfileByIdentity(ident, {
                            name = nextName,
                            callsign = nextCallsign,
                            department = nextDepartment,
                            grade = viewer.grade or 0
                        }, function(saved)
                            syncWebLinkedOfficerProfile(trim(session.discord_id or ''), saved or { name = nextName, department = nextDepartment })
                            session.linked_name = nextName
                            session.linked_department = nextDepartment
                            webPersistSession(session, function()
                                webBuildViewer(session, function(updatedViewer)
                                    webLogAction(session, 'web_unit_profile_update', tostring(updatedViewer.callsign or updatedViewer.name or 'viewer'), { name = nextName, callsign = nextCallsign, department = nextDepartment })
                                    webJson(response, 200, { ok = true, viewer = updatedViewer, message = 'Officer CAD profile updated.' })
                                end)
                            end)
                        end)
                        return
                    elseif action == 'delete-bolo' then
                        if not webCanManageDispatch(viewer) then
                            webJson(response, 403, { ok = false, error = 'Supervisor or admin access required.' })
                            return
                        end
                        local id = tonumber(q.id) or 0
                        if id <= 0 then
                            webJson(response, 400, { ok = false, error = 'Invalid BOLO id.' })
                            return
                        end
                        DB.execute([[DELETE FROM mdt_bolos WHERE id = ?]], { id }, function()
                            DB.fetchAll([[SELECT id, type, data, created_at FROM mdt_bolos ORDER BY id DESC LIMIT 100]], {}, function(rows)
                                rows = rows or {}
                                for _, row in ipairs(rows) do
                                    row.body = jsonDecode(row.data or '') or {}
                                    row.data = nil
                                end
                                triggerMdtViewers('az_mdt:client:boloList', rows)
                                webLogAction(session, 'web_delete_bolo', tostring(id), {})
                                webJson(response, 200, { ok = true, rows = rows, message = ('BOLO #%s deleted.'):format(tostring(id)) })
                            end)
                        end)
                        return
                    elseif action == 'delete-report' then
                        if not (viewer and viewer.isAdmin) then
                            webJson(response, 403, { ok = false, error = 'Website admin access required.' })
                            return
                        end
                        local id = tonumber(q.id) or 0
                        if id <= 0 then
                            webJson(response, 400, { ok = false, error = 'Invalid report id.' })
                            return
                        end
                        DB.execute([[DELETE FROM mdt_reports WHERE id = ?]], { id }, function()
                            DB.fetchAll([[SELECT id, type, data, created_at FROM mdt_reports ORDER BY id DESC LIMIT 100]], {}, function(rows)
                                rows = rows or {}
                                for _, row in ipairs(rows) do
                                    row.body = jsonDecode(row.data or '') or {}
                                    row.data = nil
                                end
                                triggerMdtViewers('az_mdt:client:reportList', rows)
                                webLogAction(session, 'web_delete_report', tostring(id), {})
                                webJson(response, 200, { ok = true, rows = rows, message = ('Report #%s deleted.'):format(tostring(id)) })
                            end)
                        end)
                        return
                    elseif action == 'delete-warrant' then
                        if not webCanManageDispatch(viewer) then
                            webJson(response, 403, { ok = false, error = 'Supervisor or admin access required.' })
                            return
                        end
                        local id = tonumber(q.id) or 0
                        if id <= 0 then
                            webJson(response, 400, { ok = false, error = 'Invalid warrant id.' })
                            return
                        end
                        DB.execute([[DELETE FROM mdt_warrants WHERE id = ?]], { id }, function()
                            DB.fetchAll([[SELECT id, target_name, target_charid, reason, status, created_by, created_discord, created_at FROM mdt_warrants ORDER BY id DESC LIMIT 200]], {}, function(rows)
                                triggerMdtViewers('az_mdt:client:warrantsList', rows or {})
                                webLogAction(session, 'web_delete_warrant', tostring(id), {})
                                webJson(response, 200, { ok = true, rows = rows or {}, message = ('Warrant #%s deleted.'):format(tostring(id)) })
                            end)
                        end)
                        return
                    elseif action == 'delete-call' then
                        if not webCanManageDispatch(viewer) then
                            webJson(response, 403, { ok = false, error = 'Supervisor or admin access required.' })
                            return
                        end
                        local id = tonumber(q.id) or 0
                        if id <= 0 or not Calls[id] then
                            webJson(response, 400, { ok = false, error = 'Call not found.' })
                            return
                        end
                        Calls[id] = nil
                        CallRooms[id] = nil
                        DB.execute([[UPDATE mdt_calls SET status = ? WHERE call_id = ?]], { 'CLEARED', id })
                        DB.execute([[DELETE FROM mdt_call_units WHERE call_id = ?]], { id })
                        broadcastCalls()
                        webLogAction(session, 'web_delete_call', tostring(id), {})
                        webRowsCalls(function(rows) webJson(response, 200, { ok = true, rows = rows, message = ('Call #%s cleared.'):format(tostring(id)) }) end)
                        return
                    elseif action == 'save-employee-access' then
                        if not (viewer and viewer.isAdmin) then
                            webJson(response, 403, { ok = false, error = 'Website admin access required.' })
                            return
                        end
                        local rowId = tonumber(q.id or q.employeeId) or 0
                        if rowId <= 0 then
                            webJson(response, 400, { ok = false, error = 'Invalid employee id.' })
                            return
                        end
                        local role = lower(trim(q.role or 'leo'))
                        if role ~= 'leo' and role ~= 'supervisor' and role ~= 'dispatch' and role ~= 'admin' and role ~= 'civ' then
                            role = 'leo'
                        end
                        local perms = {
                            loginRole = lower(trim(q.loginRole or (role == 'dispatch' and 'dispatch' or (role == 'civ' and 'civ' or 'leo')))),
                            open = boolish(q.open),
                            admin = boolish(q.admin),
                            supervisor = boolish(q.supervisor),
                            dispatch = boolish(q.dispatch),
                            civ = boolish(q.civ),
                            dmv = boolish(q.dmv),
                            leochat = boolish(q.leochat),
                            pages = decodePermissionMap(q.pages),
                            actions = decodePermissionMap(q.actions)
                        }
                        if perms.loginRole ~= 'dispatch' and perms.loginRole ~= 'civ' then perms.loginRole = 'leo' end
                        DB.execute(([[
                            UPDATE %s
                            SET mdt_role = ?, mdt_perms_json = ?, updated_at = CURRENT_TIMESTAMP()
                            WHERE id = ?
                        ]]):format(qTable('employees')), { role, jsonEncode(perms), rowId }, function()
                            webLogAction(session, 'web_save_employee_access', tostring(rowId), { role = role, perms = perms })
                            DB.fetchAll(([[
                                SELECT id, identifier, license, discordid, name, callsign, department, grade, active, mdt_role, mdt_perms_json
                                FROM %s
                                WHERE id = ?
                                LIMIT 1
                            ]]):format(qTable('employees')), { rowId }, function(updatedRows)
                                refreshOnlineAccessForEmployeeRow(updatedRows and updatedRows[1] or nil)
                            end)
                            local queryText = ([[
                                SELECT id, name, callsign, department AS active_department, grade, discordid, license, identifier, mdt_role, mdt_perms_json
                                FROM %s
                                WHERE active = 1
                                ORDER BY department ASC, name ASC
                            ]]):format(qTable('employees'))
                            DB.fetchAll(queryText, {}, function(rows)
                                rows = rows or {}
                                for _, row in ipairs(rows) do
                                    row.callsign = row.callsign or defaultCallsign(row.identifier or row.license or row.discordid or row.id)
                                    row.permissions = employeePermPayloadFromRow(row)
                                end
                                webJson(response, 200, { ok = true, rows = rows, message = 'Employee MDT access updated.' })
                            end)
                        end)
                        return
                    elseif action == 'save-theme' then
                        if not (viewer and viewer.isAdmin) then
                            webJson(response, 403, { ok = false, error = 'Website admin access required.' })
                            return
                        end
                        local payload = jsonDecode(q.theme or q.payload or '') or {}
                        saveThemeState(payload, viewer.name or 'Web Admin', function(state)
                            broadcastThemeState()
                            webLogAction(session, 'web_save_theme', (state and state.preset) or 'theme', state and state.vars or {})
                            webJson(response, 200, { ok = true, theme = state, message = ('Theme updated to %s.'):format((state and state.label) or 'custom theme') })
                        end)
                        return
                    elseif action == 'save-live-map-icons' then
                        if not (viewer and viewer.isAdmin) then
                            webJson(response, 403, { ok = false, error = 'Website admin access required.' })
                            return
                        end
                        local payload = jsonDecode(q.icons or q.payload or '') or {}
                        saveLiveMapIconState(payload, function(state)
                            broadcastLiveMapState()
                            webLogAction(session, 'web_save_live_map_icons', 'live_map_icons', state or {})
                            webJson(response, 200, { ok = true, liveMap = getLiveMapState(), message = 'LiveMap icons updated.' })
                        end)
                        return
                    end

                    webJson(response, 404, { ok = false, error = 'Unknown web action route.' })
                end)
                return
            end

            webCanReadWithSession(request, query, function(allowed, reason, session)
                if not allowed then
                    webJson(response, 401, { ok = false, error = reason or 'Unauthorized' })
                    return
                end

                if route == 'units' then
                    webJson(response, 200, { ok = true, rows = webRowsUnits() })
                elseif route == 'calls' then
                    webRowsCalls(function(rows) webJson(response, 200, { ok = true, rows = rows }) end)
                elseif route == 'bolos' then
                    webRowsBolos(function(rows) webJson(response, 200, { ok = true, rows = rows }) end)
                elseif route == 'reports' then
                    webRowsReports(function(rows) webJson(response, 200, { ok = true, rows = rows }) end)
                elseif route == 'warrants' then
                    webRowsWarrants(function(rows) webJson(response, 200, { ok = true, rows = rows }) end)
                elseif route == 'employees' then
                    webFetchLinkedViewer(request, function(session2, viewer2, err)
                        if not viewer2 then
                            webJson(response, 403, { ok = false, error = err or 'Unauthorized' })
                            return
                        end
                        if not viewer2.isLEO then
                            webJson(response, 403, { ok = false, error = 'LEO access required.' })
                            return
                        end
                        local queryText
                        local params
                        if viewer2.isAdmin then
                            queryText = ([[
                                SELECT id, name, callsign, department AS active_department, grade, discordid, license, identifier, mdt_role, mdt_perms_json
                                FROM %s
                                WHERE active = 1
                                ORDER BY department ASC, name ASC
                            ]]):format(qTable('employees'))
                            params = {}
                        else
                            queryText = ([[
                                SELECT id, name, callsign, department AS active_department, grade, discordid, license, identifier, mdt_role, mdt_perms_json
                                FROM %s
                                WHERE active = 1 AND department = ?
                                ORDER BY name ASC
                            ]]):format(qTable('employees'))
                            params = { viewer2.department or Config.DefaultDepartment }
                        end
                        DB.fetchAll(queryText, params, function(rows)
                            rows = rows or {}
                            for _, row in ipairs(rows) do
                                row.callsign = row.callsign or defaultCallsign(row.identifier or row.license or row.discordid or row.id)
                                row.permissions = employeePermPayloadFromRow(row)
                            end
                            webJson(response, 200, { ok = true, rows = rows })
                        end)
                    end)
                elseif route == 'action-log' then
                    webFetchLinkedViewer(request, function(session2, viewer2, err)
                        if not viewer2 then
                            webJson(response, 403, { ok = false, error = err or 'Unauthorized' })
                            return
                        end
                        if not viewer2.isAdmin then
                            webJson(response, 403, { ok = false, error = 'Action log requires MDT admin access.' })
                            return
                        end
                        webRowsActionLog(function(rows) webJson(response, 200, { ok = true, rows = rows }) end)
                    end)
                elseif route == 'leo-chat' then
                    webJson(response, 200, { ok = true, rows = LeoDutyChat or {} })
                elseif route == 'live-chat' then
                    webRowsLiveChat(function(rows) webJson(response, 200, { ok = true, rows = rows }) end)
                elseif route == 'search/name' then
                    webRowsNameSearch(query, function(payload) webJson(response, 200, payload) end)
                elseif route == 'search/plate' then
                    webRowsPlateSearch(query, function(payload) webJson(response, 200, payload) end)
                elseif route == 'search/weapon' then
                    webRowsWeaponSearch(query, function(payload) webJson(response, 200, payload) end)
                elseif route == 'search/reports' then
                    webRowsReportSearch(query, function(payload) webJson(response, 200, payload) end)
                elseif route == 'search/civilians' then
                    webRowsCivilians(query, function(payload) webJson(response, 200, payload) end)
                elseif route == 'search/dmv' then
                    webRowsDMV(query, function(payload) webJson(response, 200, payload) end)
                elseif route == 'search/calls' then
                    webRowsCallHistory(query, function(payload) webJson(response, 200, payload) end)
                elseif route == 'call-room' then
                    webRowsCallRoom(query, function(payload) webJson(response, 200, payload) end)
                elseif route == 'theme' then
                    webJson(response, 200, { ok = true, theme = getThemeState() })
                elseif route == 'live-map-icons' then
                    webJson(response, 200, { ok = true, liveMap = getLiveMapState() })
                else
                    webJson(response, 404, { ok = false, error = 'Unknown web API route.' })
                end
            end)
            return
        end

        webServeStatic(response, path)
    end)
end
