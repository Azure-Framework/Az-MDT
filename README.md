<div align="center">

# Az MDT

### Standalone FiveM MDT / CAD with MySQL, ACE permissions, civilian tools, live calls, and a Discord-authenticated web portal

<p>
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#ace-permissions">ACE Permissions</a> •
  <a href="#discord-oauth--web-setup">Discord OAuth</a> •
  <a href="#usage">Usage</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

</div>

---

## Overview

Az MDT is a **standalone** Mobile Data Terminal / CAD resource for FiveM. It does **not** require a framework to run. It uses **MySQL** for persistence, **ACE permissions** for access control, and includes both an **in-game NUI** and a **fullscreen website mode** served directly from the FiveM resource through `SetHttpHandler`.

This build includes:

- LEO MDT access
- Civilian MDT access
- DMV tools
- BOLOs, warrants, reports, and quick notes
- Live duty chat and per-call rooms
- 911 / officer-created call workflows
- Postal lookup support
- Discord OAuth website login + in-game account linking
- Cookie-based website sessions with logout support

---

## Features

<details open>
<summary><strong>LEO MDT</strong></summary>
<br>

- Dashboard with active units, active 911 calls, and BOLOs
- Name search
- Vehicle / plate search
- Weapon serial search
- BOLO creation and live BOLO list
- Report creation and report search
- Warrants list
- Employees page
- Internal Affairs / action log view for admins
- LEO duty chat
- Calls Hub with live call rooms
- Panic button support
- Department + callsign save
- Status dropdown (`10-8`, `10-6`, `10-7`, etc.)

</details>

<details>
<summary><strong>CIV / DMV tools</strong></summary>
<br>

- `/civmdt` command for civilian-facing access
- Civilian Center for creating civilians
- Civilian registry search
- Civilian reports
- DMV lookup and license status updates
- Register vehicles to civilians
- Register weapons to civilians
- View and remove registered vehicles / weapons for owned civilians
- Delete your own civilian records
- Admins can delete any civilian record

</details>

<details>
<summary><strong>Calls / Dispatch</strong></summary>
<br>

- In-game `/911` command
- Officer-created calls
- Traffic stop call creation
- Per-call chat rooms
- Per-call notes
- Search past calls
- Attach to calls
- TTS / alert routing controlled by config
- Panic alerts for on-duty units

</details>

<details>
<summary><strong>Website mode</strong></summary>
<br>

- Fullscreen browser version served by the resource
- Discord OAuth login
- Cookie session persistence
- Logout button clears the cookie session
- In-game **Link Website** button generates a one-time link code
- Website link form connects Discord login to an in-game account
- Website can read live MDT data through built-in HTTP routes
- Responsive layout for browser / mobile use

</details>

---

## Installation

### 1) Dependencies

Az MDT uses **one** of the following database drivers:

- `oxmysql` **recommended**
- `mysql-async` fallback

### 2) Resource placement

Place the resource in your server resources folder.

Example:

```txt
resources/[local]/az_mdt
```

### 3) Ensure order

Make sure your DB resource starts **before** Az MDT.

Example `server.cfg`:

```cfg
ensure oxmysql
ensure az_mdt
```

If you use `mysql-async`, replace `oxmysql` with your DB resource name.

### 4) Start the resource

This build auto-runs `schema.lua` and creates required tables on startup.

---

## File structure

```txt
az_mdt/
├─ fxmanifest.lua
├─ config.lua
├─ client.lua
├─ server.lua
├─ schema.lua
├─ config/
│  └─ postals.json
├─ html/
│  ├─ index.html
│  ├─ style.css
│  ├─ script.js
│  ├─ config/
│  │  ├─ config.js
│  │  ├─ charges.json
│  │  └─ translate.json
│  └─ img/
│     └─ user.jpg
└─ postals.json
```

### Postal file note

The resource checks these postal file paths:

1. `config/postals.json`
2. `postals.json`

If you moved your postal file, update `Config.Postals.file` in `config.lua`.

---

## ACE Permissions

Az MDT uses **ACE permissions from `config.lua`**.

Current permission keys:

```lua
Config.ACEPermissions = {
    open = "az_mdt.open",
    admin = "az_mdt.admin",
    civ = "az_mdt.civ",
    dmv = "az_mdt.dmv",
    leochat = "az_mdt.leochat"
}
```

### What each permission does

| Permission | Purpose |
|---|---|
| `az_mdt.open` | Opens the main LEO MDT with `/mdt` |
| `az_mdt.admin` | Enables admin-only server actions such as admin deletes and protected admin endpoints |
| `az_mdt.civ` | Grants civilian MDT access with `/civmdt` |
| `az_mdt.dmv` | Grants DMV access and DMV-only update actions |
| `az_mdt.leochat` | Grants access to LEO duty chat if you do not already have full MDT access |

### Example `server.cfg`

```cfg
add_ace group.leo az_mdt.open allow
add_ace group.command az_mdt.admin allow
add_ace group.civ az_mdt.civ allow
add_ace group.dmv az_mdt.dmv allow
add_ace group.leo az_mdt.leochat allow
```

### Example principals

```cfg
add_principal identifier.license:YOUR_LICENSE group.leo
add_principal identifier.discord:YOUR_DISCORD_ID group.command
add_principal identifier.license:YOUR_CIV_LICENSE group.civ
add_principal identifier.license:YOUR_DMV_LICENSE group.dmv
```

### Permission behavior notes

- `az_mdt.open` is the main law-enforcement permission.
- `az_mdt.civ` allows civilian-side access.
- `az_mdt.dmv` also counts as higher civilian record access for DMV actions.
- `az_mdt.admin` is checked **server-side** for admin deletes and protected tools.
- `az_mdt.leochat` is useful if you want someone to read/send in duty chat without giving full MDT access.

---

## Commands

| Command | Purpose |
|---|---|
| `/mdt` | Opens the LEO MDT |
| `/civmdt` | Opens the civilian MDT |
| `/911 [message]` | Sends a 911 call using the caller's current street location |

---

## Configuration

Main settings live in `config.lua`.

<details open>
<summary><strong>Core config</strong></summary>
<br>

```lua
Config.CommandName = "mdt"
Config.CivCommandName = "civmdt"
Config.Standalone = true
Config.DefaultDepartment = "police"
Config.DefaultOfficerGrade = 0
Config.DefaultCallsignPrefix = "U"
```

</details>

<details>
<summary><strong>Departments vs LEO departments</strong></summary>
<br>

These are **not** the same thing.

### `Config.Departments`
This is the **UI dropdown list** for selectable departments.

```lua
Config.Departments = {
    { id = "police",  label = "Police" },
    { id = "sheriff", label = "Sheriff" },
    { id = "state",   label = "State" }
}
```

### `Config.Roles.leoDepartments`
This is the **backend list** of department IDs treated as law enforcement.

```lua
Config.Roles = {
    leoDepartments = { "police", "sheriff", "state", "pd", "so", "trooper" },
    civilianDepartment = "civilian"
}
```

### Important
If you want a department to **show in the UI dropdown**, it must exist in `Config.Departments`.

If you want a department to be treated as **LEO on the backend**, it must exist in `Config.Roles.leoDepartments`.

For best results, keep them in sync.

</details>

<details>
<summary><strong>Duty + TTS</strong></summary>
<br>

```lua
Config.Duty = {
    defaultStatus = "OFFDUTY",
    resetLeoChatOnDutyChange = true
}

Config.TTS = {
    callMode = "all_onduty",
    panicMode = "all_onduty",
    boloMode = "all_onduty"
}
```

### TTS modes

| Value | Meaning |
|---|---|
| `all_onduty` | Alert all on-duty LEO units |
| `attached_only` | Only speak once the officer opens / attaches to that call |
| `none` | Disable that TTS category |

</details>

<details>
<summary><strong>Postals</strong></summary>
<br>

```lua
Config.Postals = {
    enabled = true,
    file = "config/postals.json",
    includeInCallLocation = false,
    speakInTTS = true
}
```

### Postal options

| Setting | Meaning |
|---|---|
| `enabled` | Enables postal lookup |
| `file` | Path inside the resource |
| `includeInCallLocation` | Appends the postal to visible location text |
| `speakInTTS` | Includes the postal in TTS callouts |

</details>

<details>
<summary><strong>Database table names</strong></summary>
<br>

You can override these if needed:

```lua
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
```

Additional auto-created tables include:

- `mdt_action_log`
- `mdt_last_seen`
- `mdt_identity_flags`
- `mdt_quick_notes`
- `mdt_id_records`
- `mdt_civilian_reports`
- `mdt_calls`
- `mdt_call_units`
- `mdt_call_messages`
- `mdt_call_notes`
- `mdt_web_link_codes`
- `mdt_web_discord_links`
- `mdt_web_sessions`
- `mdt_warrants`
- `mdt_live_chat`

</details>

---

## Discord OAuth & Web Setup

Az MDT includes a built-in fullscreen website served by FiveM through `SetHttpHandler`.

### Step 1: Enable web mode in `config.lua`

```lua
Config.Web = {
    enabled = true,
    publicReadOnly = false,
    autoRefreshMs = 15000,
    readToken = "",
    title = "Az MDT Web",
    notice = "Discord-authenticated website mode is active.",
    fullScreenBrowser = true,
    publicBaseUrl = "http://YOUR_IP:30120/az_mdt/",
    sessionCookieName = "az_mdt_web_session",
    sessionDurationSeconds = 2592000,
    linkCodeDurationSeconds = 900,
    adminDiscordIds = { "YOUR_DISCORD_ID" },
    DiscordOAuth = {
        enabled = true,
        clientId = "YOUR_CLIENT_ID",
        clientSecret = "YOUR_CLIENT_SECRET",
        redirectUri = "http://YOUR_IP:30120/az_mdt/auth/callback",
        redirectPath = "auth/callback",
        scopes = "identify"
    }
}
```

### Step 2: Use the exact resource URL

Your website URL is:

```txt
http://YOUR_IP:30120/RESOURCE_NAME/
```

Example:

```txt
http://76.144.200.195:30120/az_mdt/
```

### Important
Use the **trailing slash** on `publicBaseUrl`.

Correct:

```txt
http://76.144.200.195:30120/az_mdt/
```

Wrong:

```txt
http://76.144.200.195:30120/az_mdt
```

### Step 3: Configure Discord Developer Portal

In the Discord Developer Portal:

1. Create an application
2. Go to **OAuth2**
3. Copy the **Client ID**
4. Generate a **Client Secret**
5. Add your redirect URL exactly as:

```txt
http://YOUR_IP:30120/RESOURCE_NAME/auth/callback
```

6. Save changes

### Example redirect

```txt
http://76.144.200.195:30120/az_mdt/auth/callback
```

### Step 4: Restart the resource

After updating `config.lua`, restart the resource so the HTTP handler picks up the new settings.

```cfg
restart az_mdt
```

---

## Website auth flow

### How players log in

1. Open the website URL
2. Click **Login with Discord**
3. Complete Discord login
4. If not linked yet, use the in-game **Link Website** button
5. Copy the one-time code
6. Enter it on the website link form
7. The browser session is stored in a cookie
8. Use **Logout** to clear the cookie session

### What gets saved

The web session uses the cookie name defined in:

```lua
Config.Web.sessionCookieName
```

The default is:

```lua
az_mdt_web_session
```

### Admin website access

Add Discord IDs to:

```lua
Config.Web.adminDiscordIds = { "982768967275921408" }
```

These IDs can access website admin-only routes such as the action log endpoint.

---

## Web access modes

### Option A: Discord session required

```lua
Config.Web.publicReadOnly = false
```

This requires a valid Discord website session unless a matching read token is sent.

### Option B: Public read-only mode

```lua
Config.Web.publicReadOnly = true
```

This allows read access to web data without requiring Discord auth for GET routes.

### Option C: Token-based read access

```lua
Config.Web.readToken = "my_secret_token"
```

Then read requests can include either:

- query parameter: `?token=my_secret_token`
- header: `X-AZ-MDT-TOKEN: my_secret_token`

---

## Web routes

### Auth routes

| Route | Purpose |
|---|---|
| `/auth/login` | Starts Discord OAuth |
| `/auth/callback` | Discord OAuth callback |
| `/auth/logout` | Clears the web session cookie |

### Main web API routes

| Route | Purpose |
|---|---|
| `/api/bootstrap` | Website bootstrap / viewer payload |
| `/api/auth/link?code=CODE` | Links a Discord website session to an in-game account |
| `/api/my/civilians` | Returns civilians owned by the linked account |
| `/api/units` | Active units |
| `/api/calls` | Active calls |
| `/api/bolos` | BOLO list |
| `/api/reports` | Report list |
| `/api/warrants` | Warrants list |
| `/api/action-log` | Admin-only action log |
| `/api/leo-chat` | Duty chat messages |
| `/api/search/name` | Name search |
| `/api/search/plate` | Plate search |
| `/api/search/weapon` | Weapon search |
| `/api/search/reports` | Report search |
| `/api/search/civilians` | Civilian registry search |
| `/api/search/dmv` | DMV lookup |
| `/api/search/calls` | Past calls search |
| `/api/call-room` | Call room data |

---

## Usage

<details open>
<summary><strong>LEO workflow</strong></summary>
<br>

1. Grant yourself `az_mdt.open`
2. Run `/mdt`
3. Set your duty state
4. Set your department and callsign
5. Use Dashboard, searches, BOLOs, reports, warrants, and Calls Hub as needed
6. Use panic only while on duty

</details>

<details>
<summary><strong>Civilian workflow</strong></summary>
<br>

1. Grant yourself `az_mdt.civ`
2. Run `/civmdt`
3. Create civilians
4. Use **My Civilians** or civilian search
5. Register vehicles / weapons to owned civilians
6. Remove owned assets if needed
7. Submit civilian reports

</details>

<details>
<summary><strong>DMV workflow</strong></summary>
<br>

1. Grant `az_mdt.dmv`
2. Open the civilian MDT or full MDT
3. Search civilians in DMV
4. Update license status
5. Manage civilian vehicles and weapon registrations

</details>

<details>
<summary><strong>Admin workflow</strong></summary>
<br>

1. Grant `az_mdt.admin`
2. Open `/mdt`
3. Enter the Employees page to enable local admin mode in the UI
4. Admin-only delete actions and protected actions are still enforced **server-side** by ACE

### Important admin note
The current build checks admin authority from **server-side ACE**, not from the value in `html/config/config.js`.

</details>

---

## Notes on `html/config/config.js`

The file exists as:

```js
window.AZ_MDT_CONFIG = {
  adminPassword: ""
};
```

In the current build, **server-side admin permission enforcement is ACE-based**. Do not rely on this field as your real security layer.

Use:

- `az_mdt.admin` for in-game admin authority
- `Config.Web.adminDiscordIds` for website admin authority

---

## Troubleshooting

<details open>
<summary><strong>Website logs in, then goes back to login screen</strong></summary>
<br>

Check all of the following:

- `Config.Web.publicBaseUrl` ends with `/`
- `Config.Web.DiscordOAuth.redirectUri` exactly matches the Discord portal redirect
- the resource name in the URL matches the actual folder/resource name
- `clientId` and `clientSecret` are correct
- the redirect URL in Discord includes `/auth/callback`

Example:

```lua
publicBaseUrl = "http://76.144.200.195:30120/az_mdt/"
redirectUri = "http://76.144.200.195:30120/az_mdt/auth/callback"
```

</details>

<details>
<summary><strong>Postal lookup says no postal file found</strong></summary>
<br>

Make sure one of these files exists in the resource:

- `config/postals.json`
- `postals.json`

And make sure `Config.Postals.file` matches where you placed it.

Recommended:

```lua
Config.Postals = {
    enabled = true,
    file = "config/postals.json"
}
```

</details>

<details>
<summary><strong>Discord OAuth still does not work</strong></summary>
<br>

Verify:

- the callback route is reachable from your public IP
- port `30120` is accessible externally
- Discord redirect URL is exact
- the OAuth secret is current and not rotated / expired
- there are no syntax errors in `config.lua`

A missing comma in `config.lua` can break the entire web config block.

</details>

<details>
<summary><strong>ACE perms do not work</strong></summary>
<br>

Check:

- your `add_ace` lines exist
- your `add_principal` lines target the correct identifiers
- the identifiers are the ones FiveM actually shows for that player
- the permission strings match `Config.ACEPermissions`

</details>

<details>
<summary><strong>Database data does not save</strong></summary>
<br>

Check:

- `oxmysql` or `mysql-async` is running before `az_mdt`
- your DB connection is valid
- the tables were created on resource start
- there are no SQL syntax errors in your server console

</details>

---

## Credits

<div align="center">

Built by **Azure (TheStoicBear)**

Standalone MDT / CAD resource for FiveM

</div>
