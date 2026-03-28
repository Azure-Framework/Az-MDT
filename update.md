# Az-MDT — Expanded Weekly Change Log

_Date range covered: recent week of chat work (conversation-based recap)._

## Main themes this week
- Much tighter Az-5PD integration
- Better records / lookup realism
- Web + in-game parity improvements
- Cleaner role / dispatch workflow
- Better persistence and better default UX

## Dashboard / UX changes
- User wanted MDT to always open on **Dashboard** by default.
- User also wanted the MDT to preserve typed text when closing it or navigating elsewhere instead of losing notes/forms.
- General direction was to keep CAD workflow state more persistent and less frustrating.

## Search / records / profile data improvements
Work centered around making searches feel more complete and realistic:
- Show **vehicle registrations**
- Show **DOB**
- Show **insurance**
- Sometimes generate or attach **past tickets**, **prior behaviors**, or similar history to peds / stops

The intent was for a stop or lookup to feel more like a real system instead of a blank profile.

## Az-5PD integration work
This was one of the biggest parts of the week.

### Sim / Scene Tools integration
- Sim / Scene Tools from Az-5PD were moved into Az-MDT when `Config.UseAz5PD = true`.
- Added a dedicated **Sim / Scene Tools** tab inside the MDT.
- MDT became the UI host while Az-5PD remained responsible for gameplay and state.
- Exposed `window.MDT` so the embedded toolset could detect it was running inside the MDT shell.
- Fixed scrolling issues in the NUI for Sim / Scene Tools.

### Expected sync behavior between MDT and 5PD
The broader integration goals repeatedly covered:
- call acceptance / deny / en-route / on-scene state should sync correctly
- name search, plate search, vehicles, and status should stay aligned across systems
- traffic stop outcomes should surface useful record information inside MDT

## Supervisor / admin / dispatch direction
The week’s work and requests around MDT also included broader CAD operations:

### Supervisor role
- Supervisors should be distinct from full admins.
- Supervisors should be able to manage calls, warrants, and BOLOs from web or in-game MDT.
- There was also a request for admin-side employee editing so roles / permissions like dispatch, supervisor, and LEO can be managed centrally.

### Dispatch module / dashboard
- A dedicated dispatch role and dashboard was requested.
- Dispatch should be able to monitor officers, manage calls, and run name/plate searches.
- Goal was to make dispatch operations feel closer to an actual 911 / radio workflow.

## Duty / status / chat workflow
- Keep officers on duty even if the CAD is closed.
- Add cleaner status dropdown options such as:
  - 10-8
  - 10-7
  - 10-6
- Duty chat behavior needed to be more persistent and less brittle.
- “Live Chat” was effectively being replaced by a persistent LEO duty chat direction.
- Attach-to-call behavior was expected to interact better with TTS / alert logic.

## TTS / panic / notifications expectations
The MDT side of the system was expected to work with improved notification logic:
- TTS should be configurable on/off
- Call TTS logic should be refined so it can trigger at the right stage
- Panic alerts should always remain noticeable even if normal TTS is disabled
- Panic should include a strong red alert / red blip / waypoint behavior

## 911 / postals / location workflow
- Requested integration with `postals.json` for better location handling.
- Call location retrieval, notifications, and TTS should use postal context where available.
- UI notifications were requested in a **top-center dropdown** style.
- User specifically did **not** want box shadows or borders on those notification popups.

## Civilian / records / deletion logic
Repeated requests around record integrity included:
- flagged civilians should save and update live
- add warrant deletion
- deleting a civilian should also clean up related records like:
  - warrants
  - notes
  - flags
  - associated vehicles
  - associated weapons

## Search UX changes
- Civilian registry and past calls search should not show default results immediately.
- Search pages should be blank by default with a Clear button near Search.
- Vehicle and weapon records should appear in LEO-view during name searches.
- civMDT should list or otherwise expose a player’s created civilians.

## Vehicle / weapon registration expectations
- `/regcar` should grab plate and model when inside a vehicle.
- If a player has multiple characters, registration flow should prompt for which character.
- Plate search needed to be more reliable.
- There was concern about cross-character leakage of vehicle records.

## Web CAD / parity expectations carried through this week
The broader MDT thread also reinforced:
- web CAD should not stay read-only
- full support should exist for:
  - attaching / detaching units
  - clearing calls
  - room / chat interactions
  - searching names / plates
  - live updates
- CAD tab / section should persist on reopen

## Theme Studio / theming direction
The MDT work also carried a theme system requirement:
- DB-backed theming
- live load/save/broadcast
- customizable colors / fonts / borders / radius / shadows / tags / buttons
- built-in presets like:
  - Blue Command
  - Classic CAD
  - Neon Tablet
- theme table expected as `mdt_theme_settings`

## Known technical issues mentioned around MDT
- Missing table errors for `mdt_theme_settings`
- Lua server errors involving:
  - `randomLinkCode`
  - `webSessionTtl`
- website full-screen hosting and Discord OAuth / link-code web login flow needed cleanup
- public base URL and cookie/session lifecycle were part of the web-CAD stability pass

## Config / structure cleanup
- Fixed or moved toward fixing a duplicate `config.lua` problem.
- Consolidated toward a single root config for more maintainable behavior.

## Summary of actual MDT direction
By the end of the week, Az-MDT was not just being treated as a simple records viewer. The target was:
- dashboard-first
- persistent
- integrated with 5PD scene logic
- role-aware
- dispatch-capable
- web-compatible
- richer and more realistic in vehicle / person lookups
