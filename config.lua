Config = Config or {}

Config.Debug = true


Config.CommandName = "mdt"
Config.CivCommandName = "civmdt"
Config.DispatchCommandName = "dispatchmdt"

Config.VehicleRegisterCommandName = "mdtregistervehicle"
Config.VehicleRegisterCommandAliases = { "mdtregvehicle", "regvehicle", "regcar" }
Config.AllowAutoCreateCivilianOnVehicleCommand = true


Config.Standalone = false
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
    { id = "police",   label = "Police" },
    { id = "sheriff",  label = "Sheriff" },
    { id = "state",    label = "State" },
    { id = "fire",     label = "Fire" },
    { id = "ems",      label = "EMS" },
    { id = "dispatch", label = "Dispatch" },
    { id = "civilian", label = "Civilian" }
}

Config.TTS = {
    
    
    
    callMode = "all_onduty",
    panicMode = "all_onduty",
    boloMode = "all_onduty"
}






Config.ACEPermissions = {
    open = "az_mdt.open",
    admin = "az_mdt.admin",
    supervisor = "az_mdt.supervisor",
    dispatch = "az_mdt.dispatch",
    civ = "az_mdt.civ",
    dmv = "az_mdt.dmv",
    leochat = "az_mdt.leochat"
}


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

Config.CallAutoArrival = {
    enabled = true,
    arrivalDistance = 75.0,
    recheckIntervalMs = 1000,
    repeatCooldownMs = 15000
}

Config.QuickRespond = {
    windowMs = 45000,
    alertDurationMs = 20000,
    attachRetryMs = { 150, 900, 2200, 5000, 8000 },
    externalAttachRetryMs = { 500, 1800 },
    externalAttachRetryServiceMs = { 500, 1800, 4200 },
    useImmediateAttachForExternalAccept = false
}

Config.LiveMap = {
    enabled = true,
    updateIntervalMs = 1750,
    showPostalLabels = false,
    iconStoreFile = 'config/live_map_icons.json',
    mapImage = 'img/gta5-roadmap-2048.jpg',
    stageSize = 2048,
    bounds = {
        minX = -4200.0,
        maxX =  4500.0,
        minY = -4500.0,
        maxY =  8500.0
    },
    mapRect = {
        left = 289,
        top = 35,
        right = 1730,
        bottom = 2046
    },
    defaultIcons = {
        police = { className = '', imageUrl = 'img/pin-police.svg', label = 'Police', emoji = '🚓' },
        fire   = { className = '', imageUrl = 'img/pin-fire.svg',   label = 'Fire',   emoji = '🚒' },
        ems    = { className = '', imageUrl = 'img/pin-ems.svg',    label = 'EMS',    emoji = '🚑' }
    }
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


Config.UseAzAmbulance = true
Config.AzAmbulance = Config.AzAmbulance or {}
Config.AzAmbulance.ResourceNames = Config.AzAmbulance.ResourceNames or { 'Az-Ambulance', 'az_ambulance', 'az-ambulance' }
Config.AzAmbulance.JobNames = Config.AzAmbulance.JobNames or { 'ambulance', 'ems', 'doctor', 'paramedic' }

Config.UseAzFire = true
Config.AzFire = Config.AzFire or {}
Config.AzFire.ResourceNames = Config.AzFire.ResourceNames or { 'Az-Fire', 'az_fire', 'az-fire' }
Config.AzFire.JobNames = Config.AzFire.JobNames or { 'fire', 'firefighter', 'safd' }


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
