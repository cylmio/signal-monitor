# UI review — 2026-09-16

## Follow-up: six presentation fixes and initial editing focus

- Missing focused IDs remain visible as unavailable rows in the focus manager,
  preserving manual order and allowing deselection to release capacity. They
  are not silently purged when a folder becomes temporarily unavailable.
- Both distribution entry points now use FloatingStripController for layout,
  saved placement, drag resistance, screen changes, and reduced-motion handling.
  Screen changes during drag are deferred until drag completion, before settling.
- LiveMenuSession observes store changes only while a menu is open (no polling).
  FocusedTasksMenuSection reconciles rows by task ID, preserving row identity,
  actions, and open submenus. Demo/connection notices update in place.
- Grid accessibility no longer overrides individual task names and statuses.
  Runtime AX inspection confirmed all 11 current cards have distinct labels.
- Nicknames use an editing draft and commit on submit/focus loss. Runtime
  inspection verified a trailing space and the completed draft "UI Test";
  the original nickname was restored without retaining test data.
- Opening the cached focus window clears automatic field-editor focus.
  Runtime AX inspection confirmed the window, not the first nickname, is focused.

Verification: 33 package tests pass, including four new presentation regressions;
direct entry point compiles via SwiftPM and universal App Store Debug build passes.
The installed app was updated. Physical display hot-unplug during drag has not
been exercised. Live system-menu automation timed out, so full tracking-mode
interaction remains a manual acceptance check. Keyboard limitations of custom
menu views remain outside these six fixes. Core status parsing/bridging was not
changed in this follow-up.

## Follow-up: two-phase reflow

Whole-window settlement now uses `NSAnimationContext.animate` with SwiftUI
`.spring(duration: 0.42, bounce: 0.12)` on macOS 15+, retaining native ease on
older systems and immediate placement for Reduced Motion. This applies to the
second phase of layout settlement, not internal card reflow or drag resistance.
Capacity is now 6 rows × 8 columns (48 tasks); the maximum grid measures
660 × 610 points. Settings help derives these limits from the store constants.
29 package tests and universal build pass. Runtime spring feel still requires
user acceptance; build success is not a motion measurement.

Apple reference: https://developer.apple.com/documentation/appkit/nsanimationcontext/animate(_:changes:completion:)

The installed App Store build now animates each card's explicit top-left-relative
offset using SwiftUI ease-in-out (0.20 seconds). Unchanged offsets do not animate.
A temporary transparent canvas contains both layouts. After that interval the
canvas is trimmed to the final grid size and the panel translates, with native
animation, only if its final frame exceeds the cached safe bounds. New layout
requests cancel pending settlement; beginning a drag also cancels it. Reduced
Motion skips the waiting interval and animated movement. A regression test checks
11 tasks, 3→4 columns: the first three offsets and top-left anchor are unchanged,
and subsequent right-edge correction preserves size and top alignment.

This supersedes the earlier note below about removing card animation. The
settings command is also now replaced with the same cached-window action used
by the menu, avoiding a second Settings window. Redundant menu-name tooltips
have been removed. Verification: 28 package tests and universal build pass.

Reviewed source surfaces: floating cards/grid, both menu-bar entry points, persistent menu rows, focus manager, help/demo/support links, native folder chooser and alerts, and direct-distribution diagnostics.

## Implemented

- Grid fills the hosting window and aligns top-leading throughout resize. Removed its independent implicit column animation; AppKit owns window easing. For 11 tasks, 3→4 columns changes four rows to three: previously two animation/layout paths and content centering could move the unchanged first row vertically.
- Both build variants use shared grid dimensions and top-left anchoring, with hosting content size constraints disabled.
- Reduced Motion pauses task animation and disables layout/rebound animation in the main resize/drag paths.
- Focus controls now expose task-specific accessible names. Truncated task titles/paths have full hover help. Task tiles expose an activation action and localized state labels.
- Persistent menu views implement accessibility press and have native target/action wiring. Their underlying menu-item titles follow content refresh. Custom menu views still have AppKit keyboard-navigation limitations; this does not claim full keyboard parity with native menu items.
- Settings scenes previously contained `EmptyView`, confirmed by opening ⌘, in the installed app. Both now show the actual focus manager. App Store settings also exit demo when connected, matching the menu route.
- Help instructions now describe columns/rows and capacity. Focus window gets a practical initial size and explicit minimum size.

## Preserved / limitations

Native folder chooser, alert handling, support links and diagnostics scrollable report remain appropriate for their functions. Outside-click field-editor dismissal is restricted to the owning focus window and retains monitor teardown. Existing visual style, nicknames and selected task order are preserved.

The two app variants still have separate menu/window delegates; merging those is a larger architectural task. Menu custom-view keyboard behavior and full VoiceOver traversal require manual acceptance testing. The 11-task reflow fix needs motion verification, not merely a passing geometry test. No frame-by-frame recording was performed.

## References

- https://developer.apple.com/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:)
- https://developer.apple.com/documentation/swiftui/nshostingview/sizingoptions
- https://developer.apple.com/documentation/appkit/nsmenuitem/view
- https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MenuList/Articles/ViewsInMenuItems.html

Verification: package tests and universal App Store build; live accessibility inspection confirmed 11 task buttons with localized labels and exposed the empty Settings scene before correction.
