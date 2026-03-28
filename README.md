# Az-MDT

Standalone Mobile Data Terminal using MySQL and ACE permissions.

## What changed
- Removed the hard dependency on Az-Framework.
- Keeps MySQL support through oxmysql or mysql-async.
- Uses ACE permissions from `config.lua`.
- Uses standalone tables for citizens, vehicles, weapons, and employees.

## Permissions
Set your permissions in `config.lua`, then grant them in `server.cfg`.

Example:
```cfg
add_ace group.leo az_mdt.open allow
add_ace group.command az_mdt.admin allow
```

## Commands
- `/mdt`
- `/911`

## Notes
The resource auto-creates its MySQL tables on start.


## Added in this standalone ACE build

- `/mdt` for LEO access
- `/civmdt` for civilian / DMV access
- ACE permissions:
  - `az_mdt.open`
  - `az_mdt.admin`
  - `az_mdt.civ`
  - `az_mdt.dmv`
  - `az_mdt.leochat`
- Civilian Center UI for creating/searching civilians
- DMV lookup with license status updates
- LEO duty chat that resets on duty state changes
- Call rooms with per-call live chat + notes
- Search past call numbers and reports


## Web endpoint

This build also serves a browser version from the resource itself using FiveM's HTTP handler.

Open it at:

`http://YOUR_SERVER_IP:30120/<resource-name>/`

Example if the folder/resource name is `az_mdt`:

`http://YOUR_SERVER_IP:30120/az_mdt/`

Notes:
- Browser mode is read-only by default in this build.
- Create/edit actions still happen in-game through NUI unless you add your own authenticated write endpoints.
- You can lock the browser mode down with `Config.Web.publicReadOnly = false` and `Config.Web.readToken = "yourtoken"`.
