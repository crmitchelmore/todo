# EventKit calendar feasibility

CaptureCore includes a permission-gated EventKit feasibility scorer for suggested due dates.

## Info.plist

Apps that instantiate `EventKitCalendarProvider` must include:

- `NSCalendarsFullAccessUsageDescription` — explain that Capture reads calendar availability to warn when a suggested task due time conflicts with meetings or leaves too little working time.

## Permission flow

1. Read `CalendarFeasibility.authorizationStatus`.
2. If it is `.notDetermined`, call `await requestAccess()` from explicit user intent.
3. Only `.authorized` and `.fullAccess` allow calendar reads. Other statuses produce `.permissionRequired(...)` or `.unavailable(...)`; the scorer does not throw for missing permission.

## Scoring

`CalendarFeasibility.assess(dueAt:)` fetches events for the candidate due date's calendar day, then scores the focus window before the due time. The default focus window is the four hours before the due time, clipped to the start of the day.

- `.conflicted`: at least one event overlaps the exact due time.
- `.tight`: no direct conflict, but the focus window is busy enough, has multiple relevant events, or the latest meeting ends less than 30 minutes before the due time.
- `.clear`: no conflict and the focus window leaves adequate time.

The assessment evidence includes the day interval, focus window, total busy minutes with overlapping meetings merged, overlapping event summaries, nearby event summaries, and title/count conveniences for confirm UX copy such as “you have 3 meetings that afternoon”.
