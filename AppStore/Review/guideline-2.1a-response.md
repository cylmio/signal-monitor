Hello App Review,

Thank you for identifying the Demo Mode issue. We addressed two clean-review-environment paths in build 5:

1. Demo cards previously used synthetic task identifiers. Clicking one could ask Codex to open a task that did not exist. Demo cards now remain entirely inside Signal Monitor; clicking the green completed card demonstrates acknowledgement by changing it to gray.
2. A stale or inaccessible security-scoped folder bookmark could display a data-source error at launch. The app now silently falls back to its self-contained Demo Mode when a saved folder is unavailable.

To review without Codex data:

1. Launch Signal Monitor.
2. Click its terminal-shaped menu-bar icon.
3. Choose “Getting Started…” to view the in-app initialization guide.
4. Choose “Use Demo Mode.”
5. Four floating cards appear: gray (idle), blue (running), amber (waiting for input), and green (completed).
6. Demo Mode is a state preview and does not overwrite saved live-task focus selections. Selection, ordering, and nicknames can be tested using the optional live-data path below.
7. Click the green demo card to acknowledge it; it changes to gray without opening another app or showing an error.

For optional live Codex data, the initialization sequence is also documented in “Getting Started…”:

1. Choose “Choose Codex Data Folder…” and select the user’s `.codex` folder. The selected folder must contain `state_5.sqlite`; Signal Monitor reads it without modifying it.
2. Choose “Manage Focus…” and select the tasks to display. This screen also controls manual ordering, nicknames, and grid rows/columns. Return saves a nickname and exits editing.

We also added an automated regression test for the Demo Mode click path and verified a clean App Store Debug build on macOS. No account, network connection, file selection, Codex installation, or permissions are required for this review path.

Thank you.
