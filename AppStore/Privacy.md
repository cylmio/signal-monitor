# Mac App Store privacy answers

## App privacy questionnaire

- Data collection: **No, this app does not collect data**
- Tracking: **No**
- Third-party analytics or advertising: **None**
- Account or login: **Not required**

## Local data access

The user may grant read-only access to a selected hidden `.codex` folder. Signal Monitor processes the local task index and lifecycle metadata on the Mac to display task identifiers, titles, working directories, states, and timestamps. It does not upload, transmit, sell, or share this data.

The app stores the selected folder bookmark, focused task identifiers, nicknames, ordering, layout, language, and window position in local macOS preferences. This information remains on the Mac.

The Mac App Store edition does not install Codex hooks, invoke Node.js or the `sqlite3` command-line tool, connect to a private socket, or modify the selected Codex data folder.

## Suggested privacy-policy statement

Signal Monitor for Mac App Store runs locally and has no analytics, advertising, telemetry, account system, or cloud service of its own. It reads only the Codex data folder the user explicitly selects, using read-only macOS sandbox access. Local task metadata and preferences are not transmitted off the Mac by Signal Monitor.

