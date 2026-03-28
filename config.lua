Config = Config or {}

Config.Debug = true

-- Command / keybind
Config.CommandName = "mdt"
Config.CivCommandName = "civmdt"
Config.DispatchCommandName = "dispatchmdt"

Config.VehicleRegisterCommandName = "mdtregistervehicle"
Config.VehicleRegisterCommandAliases = { "mdtregvehicle", "regvehicle", "regcar" }
Config.AllowAutoCreateCivilianOnVehicleCommand = true

-- Standalone mode (no framework dependency)
Config.Standalone = true
Config.DefaultDepartment = "police"
Config.DefaultOfficerGrade = 0
Config.DefaultCallsignPrefix = "U"

Config.CharacterStateKeys = {
    "citizenid",
    "citizenId",
    "charid",
    "charId",
    "characterid",
    "characterId",
    "character_id",
    "cid"
}

Config.Departments = {
    { id = "police",  label = "Police" },
    { id = "sheriff", label = "Sheriff" },
    { id = "state",   label = "State" }
}

Config.TTS = {
    -- all_onduty: every on-duty LEO hears new-call TTS
    -- attached_only: only speak the call once the officer opens/attaches to that call room
    -- none: disable the category entirely
    callMode = "all_onduty",
    panicMode = "all_onduty",
    boloMode = "all_onduty"
}

-- ACE permissions used by the resource
-- Add these in your server.cfg, for example:
-- add_ace group.leo az_mdt.open allow
-- add_ace group.command az_mdt.admin allow
-- add_ace group.supervisor az_mdt.supervisor allow
Config.ACEPermissions = {
    open = "az_mdt.open",
    admin = "az_mdt.admin",
    supervisor = "az_mdt.supervisor",
    dispatch = "az_mdt.dispatch",
    civ = "az_mdt.civ",
    dmv = "az_mdt.dmv",
    leochat = "az_mdt.leochat"
}

-- Backwards-compatible alias if you want to reference the name exactly as ACEPERMISSIONS
Config.ACEPERMISSIONS = Config.ACEPermissions
Config.PreferEmployeeAccessOverAce = true

Config.Roles = {
    leoDepartments = { "police", "sheriff", "state", "pd", "so", "trooper" },
    civilianDepartment = "civilian"
}

Config.Duty = {
    defaultStatus = "OFFDUTY",
    resetLeoChatOnDutyChange = true
}

Config.Dispatch = {
    defaultDepartment = "dispatch",
    defaultStatus = "AVAILABLE"
}

Config.Postals = {
    enabled = true,
    file = "config/postals.json",
    includeInCallLocation = false,
    speakInTTS = true
}

Config.CivilianDefaults = {
    licenseStatus = "valid",
    address = "Unknown",
    phone = "Unknown"
}


Config.Web = {
    enabled = true,
    publicReadOnly = false,
    autoRefreshMs = 15000,
    readToken = "",
    title = "Az MDT Web",
    notice = "Discord-authenticated website mode is active.",
    fullScreenBrowser = true,
    publicBaseUrl = "",
    sessionCookieName = "az_mdt_web_session",
    sessionDurationSeconds = 2592000,
    linkCodeDurationSeconds = 900,
    adminDiscordIds = {},
    supervisorDiscordIds = {},
    DiscordOAuth = {
        enabled = true,
        clientId = "",
        clientSecret = "",
        redirectUri = "",
        redirectPath = "auth/callback",
        scopes = "identify"
    }
}

-- Standalone MySQL tables used by this MDT
Config.Tables = {
    citizens  = "az_mdt_citizens",
    vehicles  = "az_mdt_vehicles",
    weapons   = "az_mdt_weapons",
    notes     = "az_mdt_notes",
    charges   = "az_mdt_charges",
    bolos     = "az_mdt_bolos",
    reports   = "az_mdt_reports",
    employees = "az_mdt_employees"
}


Config.UseAz5PD = true
Config.Az5PD = Config.Az5PD or {}
Config.Az5PD.ResourceNames = Config.Az5PD.ResourceNames or { 'Az-5PD', 'az_5pd', 'az-5pd' }
Config.Az5PD.Tables = Config.Az5PD.Tables or {
    idRecords = 'id_records',
    plateRecords = 'plate_records',
    plates = 'plates',
    reports = 'reports',
    warrants = 'warrants',
    dispatchCalls = 'dispatch_calls',
    mdtIdRecords = 'mdt_id_records'
}
