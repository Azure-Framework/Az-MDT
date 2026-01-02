-- schema.lua
-- Simple schema creator for Az-MDT tables.
-- Make sure this file is listed in fxmanifest BEFORE your main server.lua:
-- server_scripts {
--   'schema.lua',
--   'server.lua'
-- }

local RESOURCE_NAME = GetCurrentResourceName()

Config = Config or {}
if Config.Debug == nil then Config.Debug = true end

-------------------------------------------------
-- DEBUG
-------------------------------------------------
local function dprint(...)
    if not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(("^3[%s SCHEMA]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

-------------------------------------------------
-- DB DRIVER WRAPPER (oxmysql OR mysql-async)
-------------------------------------------------
local DB = {}

local hasOx = GetResourceState("oxmysql") == "started"
if hasOx then
    dprint("Using oxmysql for schema creation.")
else
    dprint("oxmysql not detected; falling back to MySQL.Async (if available) for schema creation.")
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
        dprint("DB.execute: NO DB DRIVER AVAILABLE for schema!")
        cb(0)
    end
end

-------------------------------------------------
-- SCHEMA STATEMENTS
-------------------------------------------------

local schemaStatements = {
    {
        name = "mdt_action_log",
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
        name = "mdt_last_seen",
        sql = [[
            CREATE TABLE IF NOT EXISTS `mdt_last_seen` (
              `charid` varchar(64) NOT NULL,
              `last_seen` datetime NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`charid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = "mdt_identity_flags",
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
        name = "mdt_quick_notes",
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
        name = "mdt_id_records",
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
        name = "mdt_bolos",
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
        name = "mdt_reports",
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
        name = "mdt_warrants",
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
        name = "mdt_live_chat",
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
    }
}

-------------------------------------------------
-- ENSURE SCHEMA ON RESOURCE START
-------------------------------------------------

local function ensureSchema()
    dprint("Ensuring MDT schema...")

    for i, stmt in ipairs(schemaStatements) do
        DB.execute(stmt.sql, {}, function()
            dprint(("Ensured table: %s (%d/%d)"):format(stmt.name, i, #schemaStatements))
        end)
    end
end

AddEventHandler("onResourceStart", function(res)
    if res ~= RESOURCE_NAME then return end
    ensureSchema()
end)
