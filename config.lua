Config = Config or {}

Config.Debug = true

-- Jobs allowed to open the MDT
Config.AllowedJobs = {
    police = true,
    sheriff = true,
    state = true,
    bcso = true,
    lspd = true
}

-- Command / keybind
Config.CommandName = "mdt"

-- Optional: try to pull character / job data from Az-Framework if it is running
Config.UseAzFramework = false

-- Database table names (you can rename these if you want)
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