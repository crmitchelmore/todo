# Capture WEB app feature inventory

## 1) capture-single
- **title:** Single-item capture
- **surface:** web
- **trigger:** Type into `placeholder="Capture anything… (paste/drop images or markdown lists)"` in the top capture bar, then press `Enter` or click `Capture ⏎`.  
- **expected:** Creates a new task in `proposed` status immediately; input clears synchronously; suggestion enrichment runs in background.
- **determinism:** deterministic
- **key_strings:** `capture-bar`, `Capture anything… (paste/drop images or markdown lists)`, `Capture ⏎`, `capture-agent-options`
- **notes:** If input is empty and no attachments exist, submit is ignored. Capture bar auto-focuses on mount. `App.tsx:155`, `CaptureBar.tsx:83-100`, `tasks.ts:19-37`

## 2) capture-images
- **title:** Image attachment capture
- **surface:** web
- **trigger:** Paste or drag/drop image files onto the capture bar; attachment preview appears under `aria-label="Pending image attachments"`.
- **expected:** Up to 4 images are attached; capture submits with image attachments; attached previews are removable via image buttons with `title="Remove image"`.
- **determinism:** deterministic
- **key_strings:** `Pending image attachments`, `capture-attachment`, `Remove image`, `Attached 1 image`, `Attached N images`
- **notes:** Unsupported/too-large images show `Image was too large or unsupported`. `CaptureBar.tsx:34-44, 66-137`, `attachments.ts:1-103`

## 3) markdown-list-capture
- **title:** Paste markdown / checkbox list capture
- **surface:** web
- **trigger:** Paste a list into `Capture anything… (paste/drop images or markdown lists)`.
- **expected:** Each line becomes its own captured item; nested list items become parent/child tasks; checked boxes import as `done`.
- **determinism:** deterministic
- **key_strings:** `Added X items from list`, `parseMarkdownList`, `captureBatch`
- **notes:** Only activates when parser detects list-like input. `CaptureBar.tsx:46-64`, `markdownList.ts:1-130`, `tasks.ts:81-122`

## 4) capture-agent-options
- **title:** Capture agent mode toggles
- **surface:** web
- **trigger:** In capture bar, toggle `Attempt after research`; if enabled, toggle `Confirm plan first`.
- **expected:** These settings alter capture options passed to task creation (`agentMode='research'|'attempt'`, `agentPlanConfirmation` true/false).
- **determinism:** deterministic
- **key_strings:** `Attempt after research`, `Confirm plan first`, `Agent automation options`
- **notes:** `Confirm plan first` only appears when `Attempt after research` is checked. `CaptureBar.tsx:116-135`, `tasks.ts:14-36`

## 5) confirm-card-accept
- **title:** Confirm proposed task
- **surface:** web
- **trigger:** In `Needs confirming`, edit fields then click `Confirm Y`, or focus the card and press `Enter`/`Y`, or `Cmd/Ctrl+Enter`.
- **expected:** Task transitions `proposed -> active`; edited title/due/category/tags are saved.
- **determinism:** deterministic
- **key_strings:** `Needs confirming ·`, `Confirm Y`, `Reject N`, `card-title`, `Due`, `Tags`
- **notes:** Card is focusable. Keyboard accept only when card itself is focused for `Enter`/`Y`; `Cmd/Ctrl+Enter` works if not on a button. `ConfirmCard.tsx:19-118`, `tasks.ts:124-149`

## 6) confirm-card-reject
- **title:** Reject proposed task
- **surface:** web
- **trigger:** Click `Reject N` in a confirm card, or focus the card and press `Esc`, `N`, `Backspace`, or `Delete`.
- **expected:** Task transitions to `cancelled`; appears in `Rejected` section.
- **determinism:** deterministic
- **key_strings:** `Reject N`, `Rejected ·`, `row-rejected`
- **notes:** Shortcuts require the card itself to be focused. `ConfirmCard.tsx:43-58, 104-110`, `tasks.ts:207-212`

## 7) confirm-card-suggestions
- **title:** Live suggestion prefill
- **surface:** web
- **trigger:** Open/observe a proposed card.
- **expected:** Suggested due/category populate from `task.suggested_due_at` / `task.suggested_category` until the user touches those fields.
- **determinism:** deterministic
- **key_strings:** `suggested {confidence}%`, `Due`, category chips
- **notes:** If touched, suggestion stops auto-updating. `ConfirmCard.tsx:26-32, 111-115`

## 8) active-list-filter
- **title:** Active task filtering by tags
- **surface:** web
- **trigger:** Click tag chips in `Filter`; click `Clear` to reset.
- **expected:** Active tasks filter with AND/intersection semantics; header shows `Active · N of M` when filtered.
- **determinism:** deterministic
- **key_strings:** `Filter`, `Clear`, `Active ·`, `No items match this filter.`
- **notes:** Filter is case-insensitive; empty selection shows all. `TagFilter.tsx:5-50`, `App.tsx:191-218`

## 9) task-row-complete-toggle
- **title:** Mark task done / reopen
- **surface:** web
- **trigger:** In an active row, click checkbox; or in detail pane click `Mark done` / `Reopen`.
- **expected:** Status changes `active/confirmed <-> done`; completed tasks show static due text.
- **determinism:** deterministic
- **key_strings:** checkbox, `Mark done`, `Reopen`, `row-done`
- **notes:** Checkbox stops row click propagation. `TaskRow.tsx:36-52`, `TaskDetailPane.tsx:534-543`, `tasks.ts:214-220`

## 10) task-row-select
- **title:** Open task detail pane from stream
- **surface:** web
- **trigger:** Click any task row, or focus row and press `Enter`/`Space`; click `Inspect` on a proposed item.
- **expected:** Task becomes selected; right-side detail pane opens with that task.
- **determinism:** deterministic
- **key_strings:** `Inspect`, `row-selected`, `detail-pane`, `Select a task`
- **notes:** Selection clears when the task disappears from visible lists. `TaskRow.tsx:25-35`, `App.tsx:180-185, 205-210`, `TaskDetailPane.tsx:400-407`

## 11) task-detail-edit-autosave
- **title:** Detail pane field editing and autosave
- **surface:** web
- **trigger:** Edit title/notes/due/category/priority/tags in detail pane.
- **expected:** Non-proposed tasks autosave after ~650ms; status text changes among `Autosaving…`, `Autosave pending`, `Autosave failed`, `Autosaved`.
- **determinism:** deterministic
- **key_strings:** `Properties`, `Description autosaves. Comments are added to history.`, `Autosaved`, `Autosave pending`
- **notes:** `Cmd/Ctrl+Enter` manually persists current edits; proposed tasks do not autosave, they confirm. `TaskDetailPane.tsx:381-439, 505-545`

## 12) task-detail-confirm-proposed
- **title:** Confirm structure from detail pane
- **surface:** web
- **trigger:** On a `proposed` task in detail pane, click `Confirm structure` or press `Cmd/Ctrl+Enter`.
- **expected:** Task transitions to `active`; structure fields are persisted.
- **determinism:** deterministic
- **key_strings:** `Confirm structure`, `Reject`
- **notes:** Proposed task detail pane uses confirm/reject instead of autosave controls. `TaskDetailPane.tsx:441-460, 524-533`

## 13) task-detail-agent-loop
- **title:** Agent handoff from detail pane
- **surface:** web
- **trigger:** Enter optional text in `Optional direction: what should the agent look for, avoid, or try first?`, click `Research` or `Attempt plan`.
- **expected:** Sends agent handoff request; message shows success/failure. `Research` requests a research turn; `Attempt plan` asks for attempted execution plan.
- **determinism:** llm-gated
- **key_strings:** `AI loop`, `human gated`, `Research`, `Attempt plan`, `Requesting…`, `Preparing…`
- **notes:** `Attempt plan` message implies research first then pause before external action. `TaskDetailPane.tsx:547-570`, `agentHandoff.ts:13-51`

## 14) task-detail-ai-briefs
- **title:** Task-specific AI briefs and decision buttons
- **surface:** web
- **trigger:** Open detail pane for a task with pending proposals.
- **expected:** Shows brief cards with `Archive useful` / `Dismiss` for non-action briefs; action briefs say review in approval queue.
- **determinism:** llm-gated
- **key_strings:** `agent-briefs`, `Archive useful`, `Dismiss`, `Review this in the approval queue before the agent continues.`
- **notes:** Brief content comes from agent proposals; some are merely contextual, some require queue approval. `TaskDetailPane.tsx:571-597`, `proposals.ts:61-72`

## 15) task-detail-history
- **title:** AI + activity history timeline
- **surface:** web
- **trigger:** Open any task detail pane.
- **expected:** Timeline shows comments, capture/confirm/update/completion events, attachments, and raw DB-change details when available.
- **determinism:** deterministic
- **key_strings:** `AI + activity history`, `No synced history yet. Capture, confirmation, edits and AI updates appear here.`, `Raw database change`
- **notes:** Attachment previews render inline; event icons depend on event type/actor. `TaskDetailPane.tsx:700-750`, `eventIcon`, `timelineDisplay`

## 16) task-detail-attachments
- **title:** Attachment history in detail pane
- **surface:** web
- **trigger:** Open task detail with attachments.
- **expected:** Attached images appear in timeline with filename/mime/time and preview image.
- **determinism:** deterministic
- **key_strings:** `Attached image`, `timeline-attachment`
- **notes:** Includes descendant attachments for subtasks too. `TaskDetailPane.tsx:700-723`, `tasks.ts:39-57`

## 17) task-detail-subtask-rollup
- **title:** Subtask completion rollup
- **surface:** web
- **trigger:** Open task with descendant tasks.
- **expected:** Shows `done/total complete`, `open`, percentage, and progress bar.
- **determinism:** deterministic
- **key_strings:** `Subtasks`, `rollup-track`, `% of subtasks complete`
- **notes:** Derived from recursive query over descendants. `TaskDetailPane.tsx:600-611`

## 18) due-editor-inline
- **title:** Due editor presets and datetime picker
- **surface:** web
- **trigger:** Use `Due` control in detail pane or confirm card; click preset chips, use `datetime-local`, or `Clear`.
- **expected:** Due date updates in-place; empty state shows `+ date` in rows.
- **determinism:** deterministic
- **key_strings:** `chip`, `Clear`, `+ date`, `datetime-local`
- **notes:** Row due popover closes after change. `DueEditor.tsx:14-69`, `TaskRow.tsx:47-51`

## 19) task-row-tag-display
- **title:** Read-only tag chips in rows
- **surface:** web
- **trigger:** View any task row with tags.
- **expected:** Tags show as colored chips; category shows as a single `tag`.
- **determinism:** deterministic
- **key_strings:** `tag-chip sm`, `tag`, `tag-chips`
- **notes:** No chips render if tag set is empty. `TaskRow.tsx:44-52`, `TagChips.tsx:50-63`

## 20) tag-editor-inline
- **title:** Inline tag editing
- **surface:** web
- **trigger:** In confirm card or detail pane, type into `placeholder="+ tag"` and press `Enter`; click `×` on a chip to remove.
- **expected:** Tag set updates immediately; Backspace on empty input removes last tag.
- **determinism:** deterministic
- **key_strings:** `+ tag`, `remove ${t}`, `tag-chip-x`
- **notes:** Dedupes case-insensitively; existing tag names are preserved. `TagChips.tsx:4-47`, `tasks.ts:187-196, 160-185`

## 21) tag-manager-crud
- **title:** Tag manager
- **surface:** web
- **trigger:** Open `Manage labels`; use `New tag…`, `Add`, click tag name to rename, swatch buttons to recolor, `×` to delete.
- **expected:** Tag list updates; empty state says `No tags yet. Add one, or paste a nested list.`
- **determinism:** deterministic
- **key_strings:** `Manage labels`, `New tag…`, `Add`, `Delete tag`, `tag-swatch`
- **notes:** Rename uses inline input on click; `Escape` cancels. `TagManager.tsx:7-93`, `tags.ts:80-157`

## 22) category-manager-crud
- **title:** Category manager
- **surface:** web
- **trigger:** Open `Manage labels` → `Categories`; use `New category…`, `Add`, seed buttons like `+ engineering`, rename, recolor, delete.
- **expected:** Categories update; empty state says `No categories yet. Add the defaults or create your own vocabulary.`
- **determinism:** deterministic
- **key_strings:** `New category…`, `+ engineering`, `Delete category`
- **notes:** Missing default categories are surfaced as one-click seed buttons. `CategoryManager.tsx:7-105`, `categories.ts:4-72`

## 23) categorisation-rules
- **title:** AI categorisation rules manager
- **surface:** web
- **trigger:** Open `AI categorisation rules`; fill `Rule title`, instructions textarea, category select, tags field, `Enabled`; click `Add rule` or edit existing rule via `rule-main`.
- **expected:** Rules CRUD list updates; disabled rules appear muted; empty state says `No rules yet. Add one like “wok research → errands + shopping”.`
- **determinism:** deterministic
- **key_strings:** `Rule title`, `When should this apply? Mention words, contexts, projects, people, or intent.`, `tags, comma-separated`, `Enabled`, `Save rule`
- **notes:** Editing pre-fills draft from selected rule. `CategorisationRulesManager.tsx:24-131`, `categorisationRules.ts:4-70`

## 24) approval-queue
- **title:** Consequential action approval queue
- **surface:** web
- **trigger:** Presence of pending `action` proposals renders `Approval queue · N`.
- **expected:** Queue blocks agent continuation until user clicks `Approve` or `Reject`; `HITL` badge shows. Error text appears if decision fails.
- **determinism:** llm-gated
- **key_strings:** `Approval queue ·`, `Consequential agent work pauses here until you explicitly approve or reject it.`, `HITL`, `Approve`, `Reject`
- **notes:** Empty queue renders nothing. `ApprovalQueue.tsx:13-142`

## 25) approval-queue-interview
- **title:** Interview-style proposal handling
- **surface:** web
- **trigger:** Open queue card where `proposal_type === 'task_interview'`.
- **expected:** Shows question text, clickable option buttons, optional `Something else` textarea; `Approve` requires text when free-text is allowed.
- **determinism:** llm-gated
- **key_strings:** `interview-prompt`, `interview-question`, `interview-option`, `Something else`, `Add context only if the options do not fit…`
- **notes:** Option click approves with selected option metadata; free text is trimmed and optional if not enabled. `ApprovalQueue.tsx:76-135`, `proposals.ts:61-72`

## 26) agent-operations-panel
- **title:** Agent operations summary panel
- **surface:** web
- **trigger:** Always visible under header.
- **expected:** Shows `AI operations loop`, `Capture → research → approve → history`, metrics for confirm/research/approve/attempts/sync; research subline appears when research proposals exist.
- **determinism:** deterministic
- **key_strings:** `AI operations loop`, `Capture → research → approve → history`, `signal`, `danger`, `live`
- **notes:** Counts reflect capture inbox and proposal queues. `AgentOperationsPanel.tsx:7-48`

## 27) notification-history
- **title:** Notification history drawer
- **surface:** web
- **trigger:** Click header `Notifications` button.
- **expected:** Opens `Notification history` section with latest 50 notifications; `Close` button hides it; badge count appears on header when non-empty.
- **determinism:** deterministic
- **key_strings:** `Notification history`, `Notifications`, `Close`, `No notifications yet.`
- **notes:** Also triggers system `Notification` API permission request/delivery for new items. `App.tsx:64-114, 139-170`, `NotificationHistory.tsx:13-45`

## 28) settings-appearance
- **title:** Appearance settings
- **surface:** web
- **trigger:** Click header `Settings` → `Appearance`.
- **expected:** One of `System`, `Dark`, `Light` becomes selected and persists to localStorage / document dataset.
- **determinism:** deterministic
- **key_strings:** `Appearance`, `System`, `Dark`, `Light`, `appearance-choice selected`
- **notes:** `Dark` is default fallback if no stored preference. `SettingsPanel.tsx:19-95`, `preferences.ts:20-32`

## 29) settings-obsidian
- **title:** Obsidian URL summaries settings
- **surface:** web
- **trigger:** Open `Settings` → `Obsidian URL summaries`; toggle `Enabled`, edit `Vault`, `Summary folder`, `CLI command`.
- **expected:** Settings persist locally; hint shows env vars like `OBSIDIAN_CLI_ENABLED`, `OBSIDIAN_VAULT`, `OBSIDIAN_SUMMARY_FOLDER`, `OBSIDIAN_CLI_COMMAND`.
- **determinism:** deterministic
- **key_strings:** `Obsidian URL summaries`, `Enabled`, `Vault`, `Summary folder`, `CLI command`
- **notes:** Used for URL-only capture summaries into Obsidian via local worker config. `SettingsPanel.tsx:104-148`, `preferences.ts:34-61`, `urlSummary.ts:1-13`

## 30) sync-diagnostics
- **title:** Sync diagnostics
- **surface:** web
- **trigger:** Open `Settings` → `Sync diagnostics`, or click `Refresh`.
- **expected:** Shows server/local counts, account/session info, warning banner when mismatched, and endpoint/session details in `<details>`.
- **determinism:** deterministic
- **key_strings:** `Sync diagnostics`, `Refresh`, `Checking…`, `Endpoint and session details`, `Web local cache and server diagnostics agree.`
- **notes:** Detects owner mismatch, endpoint mismatch, local cache mismatch. `SettingsPanel.tsx:97-234`, `diagnostics.ts:48-122`

## 31) settings-agent-memory
- **title:** User memory manager
- **surface:** web
- **trigger:** Open `Settings` → `Agent memory`; add/edit entries in `Preference or fact…`, `domain, e.g. shopping`, `tags, comma-separated`, date, status.
- **expected:** Memory records CRUD; can disable or delete; empty state says `No memories yet. Add facts or preferences the agent should consider.`
- **determinism:** deterministic
- **key_strings:** `Add memory`, `Save memory`, `Disabled`, `Active`, `↺`, `–`, `×`
- **notes:** Deleted records are excluded from query. `UserMemoryManager.tsx:18-125`, `userMemories.ts:5-63`

## 32) auth-signin-password
- **title:** Sign in with email and password
- **surface:** web
- **trigger:** On auth screen, stay on `Sign In` tab; fill `Email`, `Password`; click `Sign In`.
- **expected:** On success, session stored and app enters main UI. Errors show inline below form.
- **determinism:** deterministic
- **key_strings:** `Sign In`, `Create Account`, `Email`, `Password`, `Sign In`
- **notes:** Register mode uses same form with `Create Account`. Password minimum 8 chars on register. `SignIn.tsx:141-223`, `auth.ts:135-147`

## 33) auth-register
- **title:** Create account
- **surface:** web
- **trigger:** On auth screen click `Create Account`, then submit `Email` + `Password` with `Create Account`.
- **expected:** New account is created and user signed in.
- **determinism:** deterministic
- **key_strings:** `Create Account`, `Password must be at least 8 characters.`
- **notes:** Same email/password endpoint as sign-in, with register mode. `SignIn.tsx:171-201`, `auth.ts:144-147`

## 34) auth-email-code
- **title:** Passwordless email-code sign-in
- **surface:** web
- **trigger:** Click `Email me a sign-in code`; enter `Email`; click `Send me a code`; then enter `6-digit code` and click `Sign In`.
- **expected:** Email is sent, then code verification creates a session.
- **determinism:** deterministic
- **key_strings:** `Email me a sign-in code`, `Send me a code`, `6-digit code`, `Use a different email`, `Back to password sign-in`
- **notes:** Uses two-step `sent` state. `SignIn.tsx:225-248`, `auth.ts:179-187`

## 35) auth-forgot-password
- **title:** Password reset flow
- **surface:** web
- **trigger:** Click `Forgot password?`; enter `Email`; click `Send reset code`; then enter reset `6-digit code` and `New password`; click `Reset & Sign In`.
- **expected:** Reset code is emailed; successful reset signs the user in.
- **determinism:** deterministic
- **key_strings:** `Forgot password?`, `Send reset code`, `New password`, `Reset & Sign In`
- **notes:** Initial request intentionally does not reveal account existence. `SignIn.tsx:103-117, 251-279`, `auth.ts:189-197`

## 36) auth-passkey
- **title:** Passkey sign-in
- **surface:** web
- **trigger:** On auth screen click `Sign in with a passkey`; optionally prefill email first.
- **expected:** WebAuthn passkey auth starts; on success session is stored and user signs in.
- **determinism:** deterministic
- **key_strings:** `Sign in with a passkey`, `Add passkey`
- **notes:** GitHub sign-in button appears only when OAuth provider probe reports configured GitHub. `SignIn.tsx:209-217`, `auth.ts:232-250`

## 37) auth-github
- **title:** GitHub sign-in
- **surface:** web
- **trigger:** On auth screen click `Sign in with GitHub` when shown.
- **expected:** Redirect/auth flow completes and consumes `#capture_oauth=1...` URL hash to establish session.
- **determinism:** deterministic
- **key_strings:** `Sign in with GitHub`
- **notes:** Error messages include GitHub email-linking, verified-email, and not-configured cases. `SignIn.tsx:214-217`, `auth.ts:60-86, 253-260`

## 38) auth-mfa-challenge
- **title:** MFA challenge completion
- **surface:** web
- **trigger:** During sign-in/reset flows, if challenged, enter `Authenticator or recovery code` and submit `Verify & Sign In`.
- **expected:** MFA verification exchanges challenge for session.
- **determinism:** deterministic
- **key_strings:** `Authenticator or recovery code`, `Verify & Sign In`, `Back to sign-in`
- **notes:** Challenge message says to enter authenticator or recovery code. `SignIn.tsx:147-168`, `auth.ts:112-142`

## 39) auth-security-passkey
- **title:** Account security passkey enrollment
- **surface:** web
- **trigger:** Open `Settings` → `Account security`; click `Add passkey`.
- **expected:** WebAuthn registration options are requested, browser prompt runs, account gains passkey.
- **determinism:** deterministic
- **key_strings:** `Device-native sign-in`, `Add passkey`
- **notes:** Uses `registerPasskey()`. `AuthSecurity.tsx:32-51`, `auth.ts:232-237`

## 40) auth-security-2fa
- **title:** 2FA setup / rotate / disable
- **surface:** web
- **trigger:** Open `Settings` → `Account security`; click `Set up authenticator`; enter `6-digit code`; click `Verify & enable`. Use `Authenticator or recovery code` to `Rotate recovery codes` or `Disable 2FA`.
- **expected:** Shows TOTP secret/otpauth URI during setup, then recovery codes after verification; rotate/disable updates message and displayed codes.
- **determinism:** deterministic
- **key_strings:** `Set up authenticator`, `Verify & enable`, `Rotate recovery codes`, `Disable 2FA`, `Recovery codes`
- **notes:** Recovery codes are rendered in `<code>` elements with `aria-live="polite"`. `AuthSecurity.tsx:53-147`, `auth.ts:212-230`

## 41) app-shell-status
- **title:** App shell / sync status / sign-out
- **surface:** web
- **trigger:** In header, click `Manage labels`, `Settings`, or `Notifications`; observe sync pill; use settings `Sign out`.
- **expected:** Header shows `synced`/`offline`; `detail-open` class toggles when a task is selected; sign-out clears session/local user context.
- **determinism:** deterministic
- **key_strings:** `Capture`, `Manage labels`, `Settings`, `Notifications`, `synced`, `offline`
- **notes:** Notification badge count appears in header. `App.tsx:128-170, 171-257`, `auth.ts:88-92`, `SettingsPanel.tsx:156-163`