# Mac App Store metadata — English (U.S.)

## Name

Signal Monitor for codex

## Promotional text

Keep the Codex tasks you care about visible at a glance with compact, color-coded floating cards.

## Description

Signal Monitor is a lightweight macOS companion for Codex. It keeps selected tasks visible as compact floating cards while you work in other apps.

See task state at a glance:

• Gray — idle
• Blue — running
• Amber — waiting for input
• Green — completed and not yet reviewed

Choose the tasks you want to focus on, give them short local nicknames, arrange them manually, and configure a grid of up to 6 rows and 8 columns. Click a card to open the corresponding task in Codex.

Signal Monitor is free, local-first, and independent. It has no account, ads, analytics, telemetry, or cloud service of its own. The Mac App Store edition uses macOS App Sandbox and reads only the hidden .codex folder you explicitly select. Access is read-only.

Current limitation: status changes depend on local Codex data becoming available and may be delayed. Signal Monitor is an at-a-glance companion, not an immediate approval notification system.

Signal Monitor is an independent community project and is not affiliated with or endorsed by OpenAI.

## Keywords

Codex,task monitor,menu bar,developer tools,workflow,status,productivity,macOS

## Support URL

https://github.com/cylmio/signal-monitor/issues

## Marketing URL

https://github.com/cylmio/signal-monitor

## Copyright

2026 CAI YULI

## App Review notes

Signal Monitor does not require an account or login.

### Self-contained review path (no Codex installation or data required)

1. Launch Signal Monitor and click its terminal-shaped menu-bar icon.
2. Choose “Getting Started…” under Help, then “Use Demo Mode.” Four local example cards appear: gray (idle), blue (running), amber (waiting for input), and green (completed).
3. Demo cards remain inside Signal Monitor and never send synthetic task identifiers to Codex. Click the green completed card to acknowledge it; it changes to gray without opening another app or showing an error.
4. Demo Mode previews the four states; it does not replace saved live-task focus selections. Use the live-data path below to test task selection, ordering, and nicknames.
5. Choose “Exit Demo Mode” in the help window or menu to leave the preview.

### Live Codex data initialization

1. Click the menu-bar icon and choose “Choose Codex Data Folder…”.
2. Select the hidden `.codex` folder in the current user's home directory. The folder must contain `state_5.sqlite`. The Open panel displays hidden folders, and the app receives read-only access only to the selected folder.
3. Open the menu again and choose “Manage Focus…”.
4. Check the tasks that should appear in the floating strip. Checked tasks can be manually reordered and given local nicknames; the same window controls rows and columns. Return saves a nickname and exits editing.
5. With Codex installed, clicking a live task card opens the corresponding task in Codex.

If a previously authorized folder is unavailable after reinstall or migration, Signal Monitor falls back to Demo Mode instead of presenting a blocking startup error. The user can select a new `.codex` folder at any time.

The app has no analytics, advertising, telemetry, account system, or network service of its own.
