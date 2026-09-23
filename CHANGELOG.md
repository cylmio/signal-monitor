# Changelog

## 0.1.2 / Mac App Store 1.0.1 (6) — 2026-09-22

- Store edition: moved SQLite reads and rollout parsing off the UI thread; polls no longer overlap and stale results are discarded.
- Avoid redundant snapshot and connection-label updates when data is unchanged.
- Database read failures no longer appear as an empty task list.
- Dragging updates the window position without explicitly requesting a redraw for every pointer event.
- Preserve movement before drag recognition and move on the first recognized event.
- Drag release settles immediately without waiting for grid reflow; existing resistance and spring animation are preserved.
- Added drag-start regression coverage and a locked-database responsiveness check (34 tests passing).

## 0.1.1 / Mac App Store 1.0 (5) — 2026-09-16

- Shared floating-window layout and screen-boundary handling across editions.
- Configurable grid up to 6 rows × 8 columns, with native movement and hide animations.
- Persistent menus update language and task rows without closing.
- Unavailable focused tasks remain removable; saved ordering is preserved.
- Improved task accessibility labels and nickname editing: Return saves and unfocuses.
- Focus management opens without automatically editing the first nickname.
- Store edition: self-contained demo interactions and an in-app setup/help window.
- Added geometry and presentation regression tests.

## 0.1.0 — 2026-09-06

- Native floating horizontal or vertical task cards with opaque status colors.
- Focus selection, local nicknames, manual focused ordering, and automatic ordering for other tasks.
- Live Codex task discovery and lifecycle status updates.
- Waiting-for-user detection for approval and permission requests.
- Click-to-open Codex task links.
- In-app Codex integration installer with non-destructive hook merging and backups.
- Launch at Login, diagnostics, bilingual UI, Universal macOS build, and application icon.
