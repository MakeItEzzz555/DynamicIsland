# Collapsed-notch contextual menu — 2026-10-14

Baseline: verified rescue snapshot `e567b8b`, which is based on camera PR #32 `1cd01b4`. Implemented in a clean isolated worktree outside Documents, using a fresh Git repository because the original common repository has a broken Codex checkpoint ref. Original source checkouts/indexes are not modified.

## Behavior and authority

Right-click in accessible unused collapsed top-shell space opens native Settings…, Clipboard → Open Clipboard History, separator, Quit Island. The actual `MenuBarController` owns and dispatches all three actions. Clipboard is disabled when history is off and revalidates the preference at dispatch. Quit calls the existing normal termination callback. No second settings window, clipboard store, termination service or event tap.

The panel routes only local rightMouseDown events with matching window identity. The background geometry tests the actual shell, its top clearance, physical camera cutout and registered native regions. Context-only exclusions also reserve the existing 16pt compact row wings, including SwiftUI media/agent/HUD controls. The blank shoulder band remains reachable; notchless shells use a top-clearance fallback. Physical camera-cutout clicks are explicitly excluded; no OS delivery there is claimed. Expanded controls, File Tray items and desktop outside the shell retain their native routes. Left-click expansion, configured long press and expanded double-click/menu behavior are unchanged.

NativeMenuTrackingLifecycle remains the tracking authority. Its existing depth now releases one bounded deferred workspace action only after the last submenu ends. A nativeMenu transient owner freezes pending collapsed hover/preview work without clearing editor or camera owners. Animated collapsed activity geometry updates wait until dismissal. Pointer passthrough stays disabled while the native menu owns the island, and ordinary hover collapse resumes after its tracking loop unwinds. No permanent hold or parallel polling loop.

## Validation

Focused: 26 tests, 0 failures, 0 skipped, 0.627 seconds. Nine new notch-context cases plus existing notch-click, hover containment and native-popover tests.

Actual AppKit evidence:
- Hosted NSPanel/NSView event routing across three shell widths, left/right shoulder regions and accessible center clearance.
- Real AppKit hit testing and sendEvent deliver a protected file control's rightMouseDown rather than an island action.
- Native NSMenu popup was displayed from the test-owned nonactivating panel, entered/ended real tracking notifications, and dismissed using an Escape event posted only to the test application's local event queue. The bounded cancelTracking fallback was not used.
- Popup left application activation and key-panel status unchanged, and released only its menu hold while a workspace-editor hold survived.
- Genuine shared selectors dispatch Settings/Clipboard/Quit into test callbacks; the test runner is never quit.
- Nested tracking defers Clipboard exactly once until final dismissal, and disabled preference/stale/morph routes are rejected.

Log: `/tmp/dynamicisland-notch-menu-focused.log`. No assertion weakened. The first fixture run failed because AppKit was not initialized before status-item creation; the corrected fixture initializes NSApplication and orders its own offscreen panel before native event dispatch.

Ponytail review: incremental sources plus menu callers, shell geometry, ownership, clipboard/termination callbacks and tests reviewed. No blocking finding in this focused slice. Native human right-click on a physical notch, external displays/Spaces, real Clipboard presentation and activity/menu coexistence in the packaged composition remain acceptance gates; hosted synthetic events do not claim those passed.
