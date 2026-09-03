# Privacy

Signal Monitor runs locally on macOS. It has no analytics, advertising SDK, account system, telemetry endpoint, or built-in network service.

To show task names and states, it reads Codex's local task index and lifecycle markers such as task started, task completed, and turn aborted from local rollout logs. It parses event metadata and does not copy rollout message or tool content into its own snapshot. The snapshot can contain task identifiers, task titles, working directories, states, and timestamps. A task title may itself have been derived by Codex from the beginning of a user request. Optional Codex lifecycle hooks write only a task identifier, lifecycle event name, and receipt time to small JSON files under `~/Library/Application Support/Signal Monitor/events`. The app stores focused task identifiers, nicknames, layout choices, language, and window position in macOS user preferences.

The app does not intentionally read task prompts, responses, source files, or credentials. Its diagnostics report excludes task titles, prompts, code, and the full home-directory path. Data stays on the Mac unless the user copies or shares it.

Removing the Codex integration from the menu removes Signal Monitor's hook entries while preserving unrelated hooks. Uninstalling the app does not automatically delete local preferences or the Application Support folder; users may remove those manually after quitting the app.

This policy describes version 0.1.0 and may be updated if the app's behavior changes.
