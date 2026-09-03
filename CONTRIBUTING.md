# Contributing

Bug reports and focused pull requests are welcome. Before submitting a change:

1. Run `swift test`.
2. Run `python3 scripts/verify_bridge.py` with Codex installed.
3. Build the app with `zsh scripts/package_app.sh` and verify the menu, focus manager, horizontal and vertical strips, task deep links, and integration install/remove flow.
4. Keep task data local and do not add analytics or network dependencies without an explicit design discussion.

For behavior changes, include a short explanation and before/after screenshots when the UI is affected.
