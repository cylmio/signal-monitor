# Floating window implementation review — 2026-09-16

Scope: the current App Store build's floating grid, drag handling, layout and persistence. This is not a complete audit of Codex ingestion or approval detection.

## Findings and changes

- The previous `constrainFrameRect` override was not a reliable drag callback. Apple documents placement and resizing of titled windows, not per-event dragging of a borderless panel. The previous claim that runtime resistance was verified was unsupported.
- A panel-owned `NSPanGestureRecognizer` now owns drag begin/change/end/cancel. Native background movement is disabled. Mouse displacement is measured in screen coordinates against one initial frame, avoiding incremental feedback from an already resisted frame. Click handling is delayed by the recognizer until the pan fails.
- One cached visible frame governs drag and settlement. Rubber-band overshoot is bounded below 64 points. Release uses the existing native frame animation. No global/local event monitors or movement-notification frame writes remain.
- `NSHostingView.sizingOptions = []` gives the explicitly sized panel sole responsibility for its dimensions. Previously content-derived constraints could compete with manual sizing. The one-row view minimum was 106 points while the geometry produced 105; these now agree.
- `StripGeometry` is the shared source for App Store window dimensions, grid spacing and pure boundary calculations. Task status changes are filtered by count before reaching the resize path. Layout changes during a drag are deferred until the gesture finishes.
- Position is persisted on drag completion, layout adjustment and termination, rather than on each movement event. Screen-configuration changes explicitly refresh the cached visible frame when not dragging.

## Validation and remaining scope

27 Swift package tests pass, including grid dimensions, negative-coordinate displays, corner settlement, unchanged interior movement and bounded overshoot. These tests do not validate gesture routing or perceived smoothness. Manual checks must cover clicking versus dragging, all four screen edges, cancellation and changing grid settings.

The separate direct-distribution `AppMain.swift` entry point still uses native background dragging and its own window setup. A later cross-distribution unification should move window ownership to a shared controller; ingestion and menu differences should stay outside it. This change intentionally targets the installed App Store build. Fixed-screen dragging also deliberately does not provide cross-display transfer.

## Apple references

- https://developer.apple.com/documentation/appkit/nswindow/constrainframerect(_:to:)
- https://developer.apple.com/documentation/appkit/nspangesturerecognizer
- https://developer.apple.com/documentation/appkit/nsgesturerecognizer/delaysprimarymousebuttonevents
- https://developer.apple.com/documentation/swiftui/nshostingview/sizingoptions

AppKit supplies the gesture recognition and frame animation. The rubber-band boundary formula is application code, not an Apple-provided window physics API.
