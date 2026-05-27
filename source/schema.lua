local RESOURCE_NAME = GetCurrentResourceName()

Config = Config or {}
if Config.Debug == nil then Config.Debug = true end

_G.AZ_MDT_SCHEMA_READY = false
Config.Tables = Config.Tables or {}

local function dprint(...)
    if not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(("^3[%s SCHEMA]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

local function safeTableName(name, fallback)
    name = tostring(name or fallback or "")
    name = name:gsub("[^%w_]", "")
    if name == "" then
        return fallback
    end
    return name
end

local TABLES = {
    citizens  = safeTableName(Config.Tables.citizens, "az_mdt_citizens"),
    vehicles  = safeTableName(Config.Tables.vehicles, "az_mdt_vehicles"),
    weapons   = safeTableName(Config.Tables.weapons, "az_mdt_weapons"),
    notes     = safeTableName(Config.Tables.notes, "az_mdt_notes"),
    charges   = safeTableName(Config.Tables.charges, "az_mdt_charges"),
    bolos     = safeTableName(Config.Tables.bolos, "az_mdt_bolos"),
    reports   = safeTableName(Config.Tables.reports, "az_mdt_reports"),
    employees = safeTableName(Config.Tables.employees, "az_mdt_employees")
}

local function qTable(name)
    return "`" .. TABLES[name] .. "`"
end

local DB = {}
local hasOx = GetResourceState("oxmysql") == "started"

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
        dprint("DB.execute: NO DB DRIVER AVAILABLE for schema!")
        cb(0)
    end
end

local schemaStatements = {
    {
        name = TABLES.citizens,
        sql = ([[
            CREATE TABLE IF NOT EXISTS %s (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `name` varchar(128) NOT NULL,
              `charid` varchar(64) DEFAULT NULL,
              `discordid` varchar(64) DEFAULT NULL,
              `license` varchar(64) DEFAULT NULL,
              `active_department` varchar(64) DEFAULT NULL,
              `license_status` varchar(64) DEFAULT 'valid',
              `mugshot` text DEFAULT NULL,
              `metadata` longtext DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
              PRIMARY KEY (`id`),
              KEY `idx_name` (`name`),
              KEY `idx_charid` (`charid`),
              KEY `idx_discordid` (`discordid`),
              KEY `idx_license` (`license`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]):format(qTable('citizens'))
    },
    {
        name = TABLES.vehicles,
        sql = ([[
            CREATE TABLE IF NOT EXISTS %s (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `plate` varchar(32) NOT NULL,
              `model` varchar(128) DEFAULT NULL,
              `owner_name` varchar(128) DEFAULT NULL,
              `owner_identifier` varchar(64) DEFAULT NULL,
              `discordid` varchar(64) DEFAULT NULL,
              `policy_type` varchar(64) DEFAULT NULL,
              `premium` decimal(10,2) DEFAULT 0.00,
              `deductible` decimal(10,2) DEFAULT 0.00,
              `active` tinyint(1) NOT NULL DEFAULT 1,
              `vehicle_props` longtext DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
              PRIMARY KEY (`id`),
              UNIQUE KEY `uniq_plate` (`plate`),
              KEY `idx_owner_identifier` (`owner_identifier`),
              KEY `idx_discordid` (`discordid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]):format(qTable('vehicles'))
    },
    {
        name = TABLES.weapons,
        sql = ([[
            CREATE TABLE IF NOT EXISTS %s (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `serial` varchar(128) NOT NULL,
              `type` varchar(64) DEFAULT NULL,
              `owner` varchar(128) DEFAULT NULL,
              `owner_name` varchar(128) DEFAULT NULL,
              `owner_identifier` varchar(64) DEFAULT NULL,
              `discordid` varchar(64) DEFAULT NULL,
              `notes` text DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
              PRIMARY KEY (`id`),
              UNIQUE KEY `uniq_serial` (`serial`),
              KEY `idx_owner_identifier` (`owner_identifier`),
              KEY `idx_discordid` (`discordid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]):format(qTable('weapons'))
    },
    {
        name = TABLES.employees,
        sql = ([[
            CREATE TABLE IF NOT EXISTS %s (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `identifier` varchar(64) DEFAULT NULL,
              `license` varchar(64) DEFAULT NULL,
              `discordid` varchar(64) DEFAULT NULL,
              `name` varchar(128) NOT NULL,
              `callsign` varchar(64) DEFAULT NULL,
              `department` varchar(64) DEFAULT NULL,
              `grade` int(11) NOT NULL DEFAULT 0,
              `mdt_role` varchar(32) DEFAULT 'leo',
              `mdt_perms_json` longtext DEFAULT NULL,
              `active` tinyint(1) NOT NULL DEFAULT 1,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
              PRIMARY KEY (`id`),
              KEY `idx_identifier` (`identifier`),
              KEY `idx_license` (`license`),
              KEY `idx_discordid` (`discordid`),
              KEY `idx_department` (`department`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]):format(qTable('employees'))
    },
    {
        name = TABLES.notes,
        sql = ([[
            CREATE TABLE IF NOT EXISTS %s (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `target_type` varchar(32) NOT NULL,
              `target_value` varchar(128) NOT NULL,
              `note` text DEFAULT NULL,
              `created_by` varchar(128) DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`),
              KEY `idx_target` (`target_type`,`target_value`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]):format(qTable('notes'))
    },
    {
        name = TABLES.charges,
        sql = ([[
            CREATE TABLE IF NOT EXISTS %s (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `label` varchar(255) NOT NULL,
              `fine` int(11) NOT NULL DEFAULT 0,
              `jail_time` int(11) NOT NULL DEFAULT 0,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]):format(qTable('charges'))
    },
    {
        name = 'mdt_action_log',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_action_log` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `officer_name` varchar(128) DEFAULT NULL,
              `officer_discord` varchar(64) DEFAULT NULL,
              `action` varchar(64) DEFAULT NULL,
              `target` varchar(128) DEFAULT NULL,
              `meta` text DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_last_seen',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_last_seen` (
              `charid` varchar(64) NOT NULL,
              `last_seen` datetime NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`charid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_identity_flags',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_identity_flags` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `target_type` varchar(32) NOT NULL,
              `target_value` varchar(128) NOT NULL,
              `flags_json` text DEFAULT NULL,
              `notes` text DEFAULT NULL,
              `updated_by` varchar(128) DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
              PRIMARY KEY (`id`),
              UNIQUE KEY `uniq_identity` (`target_type`,`target_value`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_quick_notes',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_quick_notes` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `target_type` varchar(32) NOT NULL,
              `target_value` varchar(128) NOT NULL,
              `note` text DEFAULT NULL,
              `creator_name` varchar(128) DEFAULT NULL,
              `creator_discord` varchar(64) DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`),
              KEY `idx_quick_notes_target` (`target_type`,`target_value`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_id_records',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_id_records` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `target_type` varchar(32) NOT NULL,
              `target_value` varchar(128) NOT NULL,
              `rtype` varchar(32) DEFAULT NULL,
              `title` varchar(255) DEFAULT NULL,
              `description` text DEFAULT NULL,
              `timestamp` datetime NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`),
              KEY `idx_id_records_target` (`target_type`,`target_value`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_bolos',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_bolos` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `type` varchar(32) NOT NULL,
              `data` text DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_reports',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_reports` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `type` varchar(32) NOT NULL,
              `data` text DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_warrants',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_warrants` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `target_name` varchar(128) NOT NULL,
              `target_charid` varchar(64) DEFAULT NULL,
              `reason` text DEFAULT NULL,
              `status` varchar(32) NOT NULL DEFAULT 'active',
              `created_by` varchar(128) DEFAULT NULL,
              `created_discord` varchar(64) DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`),
              KEY `idx_warrants_status` (`status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_live_chat',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_live_chat` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `sender` varchar(128) DEFAULT NULL,
              `source` varchar(64) DEFAULT NULL,
              `message` text DEFAULT NULL,
              `time` varchar(16) DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_civilian_reports',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_civilian_reports` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `title` varchar(255) DEFAULT NULL,
              `report_type` varchar(64) DEFAULT NULL,
              `body` text DEFAULT NULL,
              `citizen_name` varchar(128) DEFAULT NULL,
              `citizen_identifier` varchar(64) DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_calls',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_calls` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `call_id` int(11) NOT NULL,
              `caller` varchar(128) DEFAULT NULL,
              `message` text DEFAULT NULL,
              `location` varchar(255) DEFAULT NULL,
              `postal` varchar(16) DEFAULT NULL,
              `coords_json` text DEFAULT NULL,
              `status` varchar(32) NOT NULL DEFAULT 'PENDING',
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
              PRIMARY KEY (`id`),
              UNIQUE KEY `uniq_call_id` (`call_id`),
              KEY `idx_call_status` (`status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_call_units',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_call_units` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `call_id` int(11) NOT NULL,
              `unit_source` varchar(32) DEFAULT NULL,
              `unit_name` varchar(128) DEFAULT NULL,
              `unit_callsign` varchar(64) DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`),
              KEY `idx_call_room_units` (`call_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_call_messages',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_call_messages` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `call_id` int(11) NOT NULL,
              `sender` varchar(128) DEFAULT NULL,
              `source` varchar(64) DEFAULT NULL,
              `message` text DEFAULT NULL,
              `time` varchar(16) DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`),
              KEY `idx_call_room_messages` (`call_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_call_notes',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_call_notes` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `call_id` int(11) NOT NULL,
              `author` varchar(128) DEFAULT NULL,
              `note` text DEFAULT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`),
              KEY `idx_call_room_notes` (`call_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_web_link_codes',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_web_link_codes` (
              `code` varchar(32) NOT NULL,
              `player_name` varchar(128) DEFAULT NULL,
              `license` varchar(64) DEFAULT NULL,
              `charid` varchar(64) DEFAULT NULL,
              `identifier` varchar(64) DEFAULT NULL,
              `player_discord` varchar(64) DEFAULT NULL,
              `role` varchar(32) DEFAULT NULL,
              `department` varchar(64) DEFAULT NULL,
              `created_at` datetime NOT NULL,
              `expires_at` datetime NOT NULL,
              `used_at` datetime DEFAULT NULL,
              `used_by_discord` varchar(64) DEFAULT NULL,
              PRIMARY KEY (`code`),
              KEY `idx_web_link_codes_expires` (`expires_at`),
              KEY `idx_web_link_codes_used_by` (`used_by_discord`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_web_discord_links',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_web_discord_links` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `discord_id` varchar(64) NOT NULL,
              `username` varchar(128) DEFAULT NULL,
              `global_name` varchar(128) DEFAULT NULL,
              `avatar` varchar(128) DEFAULT NULL,
              `linked_name` varchar(128) DEFAULT NULL,
              `linked_license` varchar(64) DEFAULT NULL,
              `linked_charid` varchar(64) DEFAULT NULL,
              `linked_identifier` varchar(64) DEFAULT NULL,
              `linked_player_discord` varchar(64) DEFAULT NULL,
              `linked_role` varchar(32) DEFAULT NULL,
              `linked_department` varchar(64) DEFAULT NULL,
              `created_at` datetime NOT NULL,
              `updated_at` datetime NOT NULL,
              PRIMARY KEY (`id`),
              UNIQUE KEY `uniq_web_discord_id` (`discord_id`),
              KEY `idx_web_linked_license` (`linked_license`),
              KEY `idx_web_linked_charid` (`linked_charid`),
              KEY `idx_web_linked_identifier` (`linked_identifier`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_web_sessions',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_web_sessions` (
              `session_id` varchar(96) NOT NULL,
              `discord_id` varchar(64) NOT NULL,
              `username` varchar(128) DEFAULT NULL,
              `global_name` varchar(128) DEFAULT NULL,
              `avatar` varchar(128) DEFAULT NULL,
              `linked_name` varchar(128) DEFAULT NULL,
              `linked_license` varchar(64) DEFAULT NULL,
              `linked_charid` varchar(64) DEFAULT NULL,
              `linked_identifier` varchar(64) DEFAULT NULL,
              `linked_player_discord` varchar(64) DEFAULT NULL,
              `linked_role` varchar(32) DEFAULT NULL,
              `linked_department` varchar(64) DEFAULT NULL,
              `created_at` datetime NOT NULL,
              `expires_at` datetime NOT NULL,
              `last_seen_at` datetime NOT NULL,
              PRIMARY KEY (`session_id`),
              KEY `idx_web_sessions_discord` (`discord_id`),
              KEY `idx_web_sessions_expires` (`expires_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_user_prefs',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_user_prefs` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `pref_key` varchar(128) NOT NULL,
              `prefs_json` longtext DEFAULT NULL,
              `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
              PRIMARY KEY (`id`),
              UNIQUE KEY `uniq_mdt_user_prefs_key` (`pref_key`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'mdt_theme_settings',
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_theme_settings` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `theme_key` varchar(64) NOT NULL DEFAULT 'blue-command',
              `theme_label` varchar(128) DEFAULT NULL,
              `overrides_json` longtext DEFAULT NULL,
              `updated_by` varchar(128) DEFAULT NULL,
              `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    }
}

local schemaPatches = {
    {
        name = 'mdt_calls.postal_patch',
        sql = [[
            ALTER TABLE `mdt_calls`
            ADD COLUMN IF NOT EXISTS `postal` varchar(16) DEFAULT NULL AFTER `location`
        ]]
    },
    {
        name = 'mdt_web_link_codes.datetime_patch',
        sql = [[
            ALTER TABLE `mdt_web_link_codes`
                MODIFY `created_at` DATETIME NOT NULL,
                MODIFY `expires_at` DATETIME NOT NULL,
                MODIFY `used_at` DATETIME NULL
        ]]
    },
    {
        name = 'mdt_web_discord_links.datetime_patch',
        sql = [[
            ALTER TABLE `mdt_web_discord_links`
                MODIFY `created_at` DATETIME NOT NULL,
                MODIFY `updated_at` DATETIME NOT NULL
        ]]
    },
    {
        name = 'mdt_web_sessions.datetime_patch',
        sql = [[
            ALTER TABLE `mdt_web_sessions`
                MODIFY `created_at` DATETIME NOT NULL,
                MODIFY `expires_at` DATETIME NOT NULL,
                MODIFY `last_seen_at` DATETIME NOT NULL
        ]]
    },
    {
        name = 'employees.mdt_role_patch',
        sql = ([[
            ALTER TABLE %s
                ADD COLUMN IF NOT EXISTS `mdt_role` varchar(32) DEFAULT 'leo' AFTER `grade`
        ]]):format(qTable('employees'))
    },
    {
        name = 'employees.mdt_perms_patch',
        sql = ([[
            ALTER TABLE %s
                ADD COLUMN IF NOT EXISTS `mdt_perms_json` longtext DEFAULT NULL AFTER `mdt_role`
        ]]):format(qTable('employees'))
    }
}

local function runStatementsSequentially(statements, index, done)
    index = tonumber(index) or 1
    if index > #(statements or {}) then
        if done then done() end
        return
    end

    local entry = statements[index]
    if not entry or not entry.sql then
        runStatementsSequentially(statements, index + 1, done)
        return
    end

    DB.execute(entry.sql, {}, function()
        dprint(("Ensured: %s (%d/%d)"):format(entry.name or ("statement_" .. index), index, #statements))
        runStatementsSequentially(statements, index + 1, done)
    end)
end

local function ensureSchema()
    dprint("Ensuring MDT schema...")

    runStatementsSequentially(schemaStatements, 1, function()
        runStatementsSequentially(schemaPatches, 1, function()
            _G.AZ_MDT_SCHEMA_READY = true
            dprint("MDT schema ready.")
            TriggerEvent("az_mdt:schemaReady")
        end)
    end)
end

AddEventHandler("onResourceStart", function(res)
    if res ~= RESOURCE_NAME then return end
    ensureSchema()
end)
