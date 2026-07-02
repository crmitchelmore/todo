# Capture native apps — user-facing feature inventory

## App IDs / launch roots
- **macOS bundle id:** `dev.crmitchelmore.capture.mac` (`/Users/cm/work/todo/clients/apps/CaptureMac/Info.plist`)
- **iOS bundle id:** `dev.crmitchelmore.capture.ios` (`/Users/cm/work/todo/clients/apps/CaptureiOS/Info.plist`)

**Launch / root**
- **macOS:** app launches via `AppDelegate.applicationDidFinishLaunching`; main window title is **"Capture"** and initially swaps between **`SignInViewController`** and **`MacCaptureViewController`** (`/Users/cm/work/todo/clients/apps/CaptureMac/Sources/AppDelegate.swift:28-56`, `81-99`).
- **iOS:** `@main AppDelegate` creates a scene; root swaps between **`SignInViewController`** and **`UINavigationController(rootViewController: CaptureViewController)`** (`/Users/cm/work/todo/clients/apps/CaptureiOS/Sources/AppDelegate.swift:4-14`, `17-69`).

---

## capture-quick-hotkey
**title:** Quick capture from anywhere  
**surface:** macos  
**trigger:** Press global hotkey **`⌥Space`** (default) or use menu bar app menu item **`Open Capture`** / **`Capture anything… (⌥Space to summon)`** field in the main window. Also app menu item **`Capture anything…`** title is dynamic via `quickCaptureTitle(for:)` (`/Users/cm/work/todo/clients/apps/CaptureMac/Sources/AppDelegate.swift:41-47`, `128-151`; `/Users/cm/work/todo/clients/apps/CaptureMac/Sources/MacCaptureViewController.swift:135-144`).  
**expected:** Borderless floating panel appears; field focus enters `AttachmentCaptureTextField`; Enter submits instantly and hides panel; Esc dismisses without saving.  
**determinism:** deterministic  
**key_strings:** `Capture anything…`, `⌥Space`, `⏎ capture   ·   esc dismiss`, `Open Capture`  
**notes:** Spotlight-style, non-activating panel; paste/dropped images supported. `submit()` ignores blank input.

---

## capture-main-command-deck
**title:** Main capture field / command deck  
**surface:** macos+ios  
**trigger:** Click the top capture field in the main window/screen (`"Capture anything…  (⌥Space to summon)"` on macOS, `"Capture anything…"` on iOS). Submit with Return.  
**expected:** Text is captured locally-first; field clears immediately; proposed item appears in **NEEDS CONFIRMING**.  
**determinism:** deterministic  
**key_strings:** `COMMAND DECK`, `Capture anything…`, `Attempt after research`, `Confirm plan first` (macOS); `COMMAND DECK`, `Capture anything…`, `Attempt after research`, `Confirm plan` (iOS)  
**notes:** macOS title bar has `Notifications` and `Settings` buttons. iOS has right nav buttons for settings/notifications/passkey.

---

## capture-paste-list-ingest
**title:** Paste markdown/checklist as multiple tasks  
**surface:** macos+ios  
**trigger:** Paste a markdown/checkbox list into the capture field (`windowWillReturnFieldEditor` on macOS; custom paste override on iOS).  
**expected:** Each list item is ingested as separate task(s) instead of plain text.  
**determinism:** deterministic  
**key_strings:** `CapturePasteTextView`, `ingestIfList`, `onPasteList`  
**notes:** Nested items become parent-linked subtasks; checked items import as done. If text is not a list, normal capture continues.

---

## capture-image-attachment
**title:** Capture with image attachment(s)  
**surface:** macos+ios  
**trigger:** Paste or drag/drop images onto capture field.  
**expected:** Attached image drafts are created; capture uses first attachment filename if text is empty; capture is submitted and field clears.  
**determinism:** deterministic  
**key_strings:** `Image attachment`, `Attached image`, `onPasteImages`, `onDroppedImages`  
**notes:** macOS supports up to 4 images via paste/drop; iOS supports paste, pasteboard image, and drag/drop. iOS shows error banner if image too large.

---

## proposed-confirm-reject
**title:** Confirm or reject proposed tasks  
**surface:** macos+ios  
**trigger:** In the **NEEDS CONFIRMING** / **NEEDS CONFIRMING · N** list, tap/click the row primary action **Confirm** or secondary action **Reject**; on macOS FastConfirmTableView also supports keyboard: `Enter`/`y` confirm, `Esc`/`n`/`Delete` reject, `e` edit.  
**expected:**  
- Confirm: proposal transitions `proposed -> active` (confirmed).  
- Reject: proposal transitions `proposed -> cancelled`.  
**determinism:** deterministic  
**key_strings:** `NEEDS CONFIRMING ·`, `STRUCTURE CHECK`, `Confirm`, `Reject`, `Confirm structure`  
**notes:** macOS proposed row title becomes **`Confirm structure`** and detail panel has **`Confirm structure`** / **`Reject`** actions. iOS proposed rows support swipe actions too.

---

## proposal-edit-detail
**title:** Edit a proposed item before confirmation  
**surface:** macos+ios  
**trigger:** Open a proposed item row / tap proposed row; in detail panel/screen edit title, due, category, tags, notes, priority, then confirm.  
**expected:** Edited proposal is confirmed into active with the edited structure.  
**determinism:** deterministic  
**key_strings:** macOS: `Save changes`, `Confirm structure`, `Select a task`, `Structure`, `Expansion`, `AI + activity`; iOS: `Task`, `Confirm`, `Properties`, `Expansion`, `AI + activity history`  
**notes:** macOS detail pane supports `⌘↩` save/confirm. iOS detail screen uses navigation bar **Reject** / **Confirm**.

---

## active-done-reopen
**title:** Mark active work done or reopen done work  
**surface:** macos+ios  
**trigger:** In active list or detail pane, tap/click **Mark done** / **Done**; on done items use **Reopen**.  
**expected:** Task status toggles `active <-> done`.  
**determinism:** deterministic  
**key_strings:** `Mark done`, `Done`, `Reopen`, `ACTIVE`, `DONE`  
**notes:** In iOS lists, swipe action is **Done** / **Reopen**; macOS detail shows secondary button title changes based on status.

---

## rejected-list
**title:** View rejected tasks  
**surface:** macos+ios  
**trigger:** Open the rejected section/list.  
**expected:** Rejected items are visible as read-only bin entries; they cannot be selected/acted on like active tasks.  
**determinism:** deterministic  
**key_strings:** `REJECTED`, `REJECTED ·`, `Rejected`  
**notes:** macOS active table has rejected rows rendered separately; iOS has a dedicated **REJECTED · N** section.

---

## list-filter-by-tag
**title:** Filter tasks by tag chips  
**surface:** macos+ios  
**trigger:** Click/tap a tag chip in the horizontal filter bar (`Filter` label on macOS; scrolling chip bar on iOS). Tap multiple chips to AND-filter. Use **Clear** to remove filters.  
**expected:** Lists recalculate active/done/rejected counts based on tag intersection.  
**determinism:** deterministic  
**key_strings:** `Filter`, `Clear`, tag names from `viewModel.allTags`  
**notes:** macOS filter bar is under the capture field; iOS filter bar is under the capture bar. Tag filter is intersection (AND), not OR.

---

## task-detail-properties
**title:** Edit task properties in detail/inspector  
**surface:** macos+ios  
**trigger:** Open a task row. In detail view/screen edit:
- title
- due date toggle/date picker
- category selector
- priority
- tags
- notes  
**expected:** Saved changes persist; list/detail refresh; due-date feasibility updates.  
**determinism:** deterministic  
**key_strings:** macOS: `Structure`, `Due`, `Calendar`, `Category`, `Priority`, `Tags`, `Expansion`; iOS: `Properties`, `Due`, `Calendar`, `Category`, `Priority`, `Tags`, `Expansion`  
**notes:** macOS uses inspector pane; iOS uses pushed `TaskDetailViewController`. Category is `None` or one of `CAPTURE_CATEGORIES`. Tags use chips and add/remove buttons.

---

## task-detail-handoff-research-attempt
**title:** Hand off task to AI for research or attempt  
**surface:** macos+ios  
**trigger:** In task detail, enter text in AI handoff field and tap/click **Research** or **Attempt**.  
**expected:** Backend agent-handoff request is queued; status label updates (`Research queued` / `Attempt queued` on iOS).  
**determinism:** llm-gated  
**key_strings:** macOS: `AI loop`, `Ask the AI loop what to research or try next`, `Research`, `Attempt`, `Research queued`, `Attempt queued`; iOS: `Ask for research or an attempted next action`, `Research`, `Attempt`, `Research queued`, `Attempt queued`  
**notes:** macOS can hide/show confirm-plan checkbox when **Attempt after research** is enabled. Handoff disabled for cancelled tasks.

---

## task-detail-history
**title:** View synced task activity/history  
**surface:** macos+ios  
**trigger:** Open task detail.  
**expected:** History area shows capture, confirmation, edits, AI updates, attachments; empty state appears when no history yet.  
**determinism:** deterministic  
**key_strings:** `No synced history yet. Capture, confirmation, edits and AI updates appear here.`, `Attached image`, event titles/bodies  
**notes:** macOS and iOS both render attachments and events. Event icons differ by actor/type.

---

## task-detail-rollup
**title:** Inspect subtask rollup/completion  
**surface:** macos+ios  
**trigger:** Open task detail for a task with descendants.  
**expected:** Rollup card shows completed/open counts and a progress bar.  
**determinism:** deterministic  
**key_strings:** `Subtasks`, `complete`, `open`, `%`  
**notes:** Hidden when rollup total is 0.

---

## task-due-date-editor
**title:** Set/clear due date  
**surface:** macos+ios  
**trigger:** In detail screen, enable **Due** switch and choose date; or on iOS use swipe action **Date** / action sheet presets.  
**expected:** Due date is saved or cleared; calendar feasibility text updates.  
**determinism:** deterministic  
**key_strings:** `Due`, `Set due date`, `Pick date…`, `Clear date`, `Date`, `Calendar`  
**notes:** iOS row swipe on active tasks exposes **Date** and a separate date picker sheet. macOS uses inline `NSDatePicker`.

---

## task-category-management
**title:** Manage categories  
**surface:** macos+ios  
**trigger:** Open Settings → Categories/`Categories & Tags`; create/rename/recolor/delete categories.  
**expected:** Category rows update; tasks reference renamed categories by stable metadata row.  
**determinism:** deterministic  
**key_strings:** macOS: `Categories & Tags`, `Create category`, `Rename category`, `Recolour category`, `Delete category`, default categories `engineering`, `leadership`, `home`, `errands`, `health`, `finance`, `personal`, `inbox`; iOS: `Categories`, `Add category`, `New category`, `Rename category`, `Colour`, `Delete`  
**notes:** iOS task detail category picker includes `None` plus current and default categories.

---

## task-tag-management
**title:** Manage tags  
**surface:** macos+ios  
**trigger:** Open Settings → Categories/Tags; create/rename/recolor/delete tags.  
**expected:** Tag palette updates and tag chips appear in filters and task details.  
**determinism:** deterministic  
**key_strings:** macOS: `Create tag`, `Rename tag`, `Recolour tag`, `Delete tag`, `Add managed tags…`; iOS: `Tags`, `Add tag`, `New tag`, `Rename tag`, `project-name`  
**notes:** Task detail on iOS adds tags via `+ Tag`; macOS uses token field with comma tokenization.

---

## categorisation-rules
**title:** Manage AI categorisation rules  
**surface:** macos+ios  
**trigger:** Open Settings → Categorisation rules / AI Categorisation Rules; add/edit/delete rules.  
**expected:** Rule rows update; future captures use these rules for suggestions only.  
**determinism:** llm-gated  
**key_strings:** macOS: `Categories & Tags`, `Create categorisation rule`, `Update categorisation rule`, `Delete categorisation rule`; iOS: `AI Categorisation Rules`, `Add rule`, `New rule`, `Edit rule`, `Rule title`, `When should this apply?`, `Category (optional)`, `tags, comma-separated`  
**notes:** UI explicitly says rules guide suggestions only; human confirmation still required.

---

## agent-memory
**title:** Manage agent memory / user facts  
**surface:** macos+ios  
**trigger:** Open Settings → Agent Memory; add/edit/disable/delete a memory.  
**expected:** Memories update and become available as agent context.  
**determinism:** llm-gated  
**key_strings:** macOS: `Create memory`, `Update memory`, `Set memory status`, `Memory`; iOS: `Agent Memory`, `Add memory`, `New memory`, `Edit memory`, `Disable`, `Enable`, `Delete`  
**notes:** iOS memory row shows `domain`, `source`, tags, expiry. Disabled/deleted memories are dimmed.

---

## obsidian-url-summaries
**title:** Configure URL-only capture summaries / Obsidian write-back  
**surface:** macos+ios  
**trigger:** Open Settings → `Obsidian URL Summaries` / `Obsidian URL Summaries`; toggle enable and fill vault/folder/command fields.  
**expected:** Preferences persist; URL-only captures are summarized and can be mirrored to Obsidian CLI.  
**determinism:** deterministic  
**key_strings:** macOS: `Obsidian URL Summaries`, `OBSIDIAN_CLI_ENABLED=...`, `Vault`, `Summary folder`, `CLI command`; iOS: `Obsidian URL Summaries`, `Enable CLI write-back`, `Vault name`, `Capture/Summaries`, `obsidian`  
**notes:** iOS help text: “URL-only captures generate an overview plus a 3-5 paragraph markdown summary.”

---

## url-only-capture-summary
**title:** URL-only capture normalization  
**surface:** macos+ios  
**trigger:** Capture a plain URL (http/https) or paste a URL-only string.  
**expected:** Raw text is normalized to URL-only capture source `url-summary`; backend receives summarized URL rather than free text.  
**determinism:** deterministic  
**key_strings:** `url-summary`, `raw_text`, `source`  
**notes:** A capture with only one HTTP(S) URL and no whitespace is detected by `URLSummaryCapture.urlOnly`.

---

## sync-diagnostics
**title:** Sync diagnostics / local vs server health  
**surface:** macos+ios  
**trigger:** Open Settings → `Sync Diagnostics`; on iOS also tap the sync pill in the main screen (`Double tap to refresh sync diagnostics.`); macOS has `Refresh` button.  
**expected:** Shows alignment/mismatch state, counts, account/session, backend/PowerSync URLs, and local owner IDs.  
**determinism:** deterministic  
**key_strings:** macOS: `Sync Diagnostics`, `Refresh`, `Account`, `Session`, `Server total`, `Local total`, `Server updated`, `Local updated`, `Backend`, `PowerSync`, `Local owners`; iOS: `Refresh diagnostics`, `Checking sync state…`, `Sync looks aligned`, `Account mismatch`, `Local cache has another owner`, `Counts differ`  
**notes:** iOS top-right sync pill state strings: `sync checking`, `synced`, `account mismatch`, `sync catching up`, `sync unknown`.

---

## notifications-history
**title:** Notification history  
**surface:** macos+ios  
**trigger:** macOS app menu **Notifications…** or toolbar button **Notifications** / symbol `◆`; iOS top-right bell icon opens `Notifications`.  
**expected:** Dedicated notification history surface shows recent notifications, or empty state if none.  
**determinism:** deterministic  
**key_strings:** macOS: `Notifications`, `No notifications yet.`, `Research, interview and attempt updates stay here even if the system banner was missed.`; iOS: `Notifications`, `No notifications yet.\nResearch and attempt updates will stay here.`  
**notes:** Not settings. macOS list is a separate window; iOS pushes a notifications screen. Notification kinds and severity tint rows.

---

## auth-email-password
**title:** Email/password sign in or account creation  
**surface:** macos+ios  
**trigger:** Launch app when signed out; use segmented control `Sign In` / `Create Account`; fill `Email` and `Password`; tap **Sign In** or **Create Account**.  
**expected:** Auth session stored; app swaps from sign-in gate to capture UI.  
**determinism:** deterministic  
**key_strings:** macOS: `Sign In`, `Create Account`, `Email`, `Password`, `Forgot password?`, `Email me a sign-in code`, `Sign in with a passkey`; iOS: same strings  
**notes:** Password minimum 8 chars when creating an account. Both platforms use keyboard-safe layouts.

---

## auth-email-code
**title:** Email code sign-in / password reset  
**surface:** macos+ios  
**trigger:** In sign-in gate tap **Email me a sign-in code** or **Forgot password?**; in sheet/screen enter `Email`, then `6-digit code`, and for reset a `New password`.  
**expected:** Code is sent, then verified; login resets or signs in and dismisses back to capture UI.  
**determinism:** deterministic  
**key_strings:** macOS: `Sign in with a code`, `Reset password`, `Send me a code`, `Send reset code`, `Sign In`, `Reset & Sign In`, `6-digit code`, `New password`; iOS: same strings  
**notes:** macOS uses sheet modal; iOS uses form sheet pushed inside nav controller. Invalid/missing input shows inline error label.

---

## auth-passkey
**title:** Passkey registration and sign-in  
**surface:** macos+ios  
**trigger:** In sign-in gate tap **Sign in with a passkey**; or when signed in tap key icon / menu item **Add Passkey…**.  
**expected:** Passkey auth sheet runs; on success session is stored and user is signed in; on registration, alert says passkey added.  
**determinism:** deterministic  
**key_strings:** `Sign in with a passkey`, `Add Passkey…`, `Passkey added`, `Passkey unavailable`, `This Mac can now sign in to Capture with a passkey.`  
**notes:** iOS passkey auth available only where `ASAuthorization` is supported; anchor is the current window.

---

## mac-settings-window
**title:** macOS Settings window  
**surface:** macos  
**trigger:** App menu **Settings…** or top-right `⚙︎` button.  
**expected:** Separate titled window **Settings** appears.  
**determinism:** deterministic  
**key_strings:** `Settings`, `Global Hotkey`, `Appearance`, `Diagnostics & Debug`, `Obsidian URL Summaries`, `Agent Backend Computer`, `Categories & Tags`, `Sync Diagnostics`  
**notes:** Window controller is `SettingsWindowController`; stays as separate AppKit window.

---

## mac-global-hotkey-settings
**title:** Rebind global capture hotkey  
**surface:** macos  
**trigger:** Settings → Global Hotkey → click recorder field and press a combo with at least one modifier.  
**expected:** Global shortcut is re-registered and displayed; invalid combos are rejected and previous shortcut remains.  
**determinism:** deterministic  
**key_strings:** `Global Hotkey`, `Press this combination anywhere to summon quick capture. Click the field, then press your shortcut — it needs at least one modifier (⌘ ⌥ ⌃ ⇧).`  
**notes:** Default is **⌥Space**.

---

## mac-appearance
**title:** Toggle app appearance  
**surface:** macos  
**trigger:** Settings → Appearance segmented control (**System**, **Dark**, **Light**).  
**expected:** App appearance changes immediately and persists.  
**determinism:** deterministic  
**key_strings:** `System`, `Dark`, `Light`, `Appearance`  
**notes:** iOS uses the same three modes in Settings but with UIUserInterfaceStyle on the window.

---

## mac-agent-backend-device
**title:** Register/select/disable this Mac as agent backend  
**surface:** macos  
**trigger:** Settings → Agent Backend Computer. Use harness picker / selected backend toggle and press the registration action.  
**expected:** Current Mac gets registered with device id, harness kind/label, capabilities; can be selected as backend or disabled.  
**determinism:** deterministic  
**key_strings:** `Agent Backend Computer`, `Register this Mac`, `Registering this Mac…`, `Backend device selected.`, `Device disabled.`  
**notes:** This is the “backend-device/harness registration” surface. Action labels in code include `Register this Mac`, `Select backend Mac`, `Disable backend Mac`.

---

## mac-main-cockpit
**title:** Main cockpit layout  
**surface:** macos  
**trigger:** Launch app signed in.  
**expected:** Large split window appears with left command deck/list and right inspector pane.  
**determinism:** deterministic  
**key_strings:** `COMMAND DECK`, `NEEDS CONFIRMING ·`, `ACTIVE ·`, `NOTHING TO CONFIRM`, `Select a task`  
**notes:** Right pane is `MacTaskDetailView`; left side contains capture field, notifications/settings buttons, proposed list, filters, active list.

---

## ios-main-capture-screen
**title:** Main iOS capture screen  
**surface:** ios  
**trigger:** Launch app signed in.  
**expected:** Navigation controller root shows Capture screen with capture bar, sync pill, filter chips, and task sections.  
**determinism:** deterministic  
**key_strings:** `Capture`, `COMMAND DECK`, `sync checking`, `synced`, `Capture anything…`  
**notes:** `CaptureViewController` is the root; settings/notifications/passkey are nav bar right buttons.

---

## ios-confirm-sheet
**title:** iOS dedicated confirm sheet  
**surface:** ios  
**trigger:** (If routed) open `ConfirmViewController` for a proposed task.  
**expected:** User can edit title, due date, and category, then confirm or reject.  
**determinism:** deterministic  
**key_strings:** `Confirm`, `Reject`, `Due`, `Category`, `Done`, `P0`, `P1`, `P2`, `P3`, `P4`  
**notes:** This controller exists as a dedicated confirm surface; current main list also supports inline confirmation actions.

