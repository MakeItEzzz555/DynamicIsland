# Window Snap: Move to Next Display

Roadmap source: P9 multi-display Window Snap in
`research/DROPPY_PARITY_MASTER_PLAN_2026-09-29.md` and the recovered execution
ledger's explicit move-to-next-display gap.

The existing native Window Snap menu now offers Move to Next Display. The
controller uses the existing Accessibility provider and largest-intersection
screen resolver, advances cyclically through the provider's display order,
and preserves the window's size and offset from the visible frame's origin.
An oversized window is reduced to fit; offsets are clamped to the destination's
visible bounds. A single display produces an actionable error. The existing
enabled/permission checks remain authoritative. Success clears any old snap
target and preview so a previous Left Half indication is not left visible.

Four new controller regressions cover negative display origins, different
menu/Dock insets, wraparound, oversized windows, normal-size edge clamping,
stale preview cleanup, one display, denied permission and disabled behavior.
The connected Audio + Window Snap + Productivity filter passes 63 tests,
zero skips/failures. Log:
`/private/tmp/dynamicisland-audio-display-final-focused.log`.

The native menu uses the existing SwiftUI Menu, labels and tile style. No
dependency, permission request, Settings schema key or shortcut was added.
An earlier optional workspace screenshot test was skipped because no output
directory was configured; no popup screenshot or real window move is claimed.

Code review and final integration are pending. A physical Mac with multiple
displays and the existing Accessibility permission must confirm the window
move and native menu behavior. This does not approve installation or release.
