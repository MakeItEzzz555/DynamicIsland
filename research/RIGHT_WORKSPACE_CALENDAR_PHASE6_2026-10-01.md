# Phase 6 — Right Workspace Calendar 2.0 (2026-10-01)

## Sources inspected
- Droppy `Extensions/ToDo/ToDoView.swift` (`ToDoDueDateCircleButtonView`, `ToDoDueDatePopoverContentView`, popover lifecycle), `NotchWindowController.swift` (`hasActivePopoverWindow`, `isInteractingWithPopover` collapse guards).
- ExploreSwiftUI: DatePicker colors (`.tint(.red)`), Graphical, StepperField styles. Techniques only (no reuse license on the site).
- Droppy recordings: contact sheets of all four; none contains calendar/date UI. Frames 9.04.02 PM @ 46.5 s and 61 s sampled for density only (black surfaces, semibold white primary, muted secondary). One recording is unrelated personal content and was not analysed further.

## Architecture
- `CalendarEventsController` evolved (same `EKEventStore`, same `EKEventStoreChanged` observer): `selectedDay` + `dayEvents`, `dayInterval(containing:calendar:)` (calendar day boundaries, 23/25 h DST days), overlap filtering, all-day first then chronological, cap 40. The 7-day upcoming API is unchanged.
- Selection never requests permission and reads nothing without full access; midnight / time-zone changes move a "today" selection and keep an explicit day.
- EventKit is queried once per selected day, never from a view body.

## Selected-date semantics
The selected day shows every event overlapping that local day, including earlier events today, in-progress, all-day and cross-midnight events; an event ending exactly at midnight belongs to the previous day. An empty day shows "No events on this date" and never falls back to other events.

## UI
Day navigator (‹ [calendar · date] ›, red Today capsule only off-today), popover with native `.graphical` DatePicker tinted red, rows with day-relative times, all-day, calendar colour/name, real "Now" marker and meeting-link indicator (exact URL, otherwise Calendar.app). Permission states unchanged (explicit Allow; Open Privacy Settings when denied/restricted/write-only).

## Popover containment
A date-picker popover is a separate AppKit window. Fix: `.nativePopover` hold (visible app-owned popover window), owner-scoped `calendarDatePicker` transient hold from the presenting view, and scroll events in popover windows bypass workspace gesture routing. NSMenu tracking (df38f23) unchanged.

## Validation
- Tests: controller (DST, overlap, sorting, refresh, permission, rollover), presentation, containment, snapshot bounds at 14/16-inch, 1440×900, 1920×1080, 2560×1440, 3840×2160 classes.
- Real EventKit: IMPLEMENTED BUT REAL VALIDATION BLOCKED BY CALENDAR PERMISSION (test process `notDetermined`); opt-in `CalendarLiveTests` prints counts only.
- CALENDAR RELEASE VALIDATION BLOCKED — ENTITLEMENT REQUIRES USER APPROVAL: hardened (Developer ID) builds need `com.apple.security.personal-information.calendars`, not added.

## Intentional differences
Red identity, no time selection, Today as the only quick preset, AppKit grid keeps the system accent colour.
