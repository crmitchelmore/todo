# Capture UX patterns

Capture is a command cockpit for fast capture, human confirmation, and AI-assisted follow-through. It should feel closer to a focused operations console than a generic task manager: dense, calm, immediate, and evidence-led.

## Product grammar

- **Command first.** The first interactive surface is always capture. It must clear instantly after submit and never wait on network, LLM, sync, or agent work.
- **Human decisions are amber.** Use the amber signal colour only for confirmation, rejection, due-date decisions, and other moments where the user chooses structure or consequence.
- **AI evidence is iris.** Agent/worker output, research, attempts, and provenance should use the iris/purple channel, not amber. Amber means "you decide"; iris means "the system found/did something".
- **Completion is mint.** Done/synced/safe-success states use mint. Avoid mint for suggestions or pending work.
- **History is semantic first.** Show the human meaning of a change by default. Column-level/database detail belongs behind expansion or lower-emphasis metadata.

## Layout patterns

- **Command deck.** Top-left capture command with minimal chrome, followed by confirmation queue and active outline. Settings and utilities are secondary glyph actions, never primary peers of capture.
- **Triage queue.** Proposed items are cards because they require decision. Each card should show: decision label, task title, AI/on-device suggestion, and confirm/reject actions. Keep keyboard confirm/reject/edit shortcuts working.
- **Active outline.** Active tasks are denser than proposed cards. Inline metadata (category, tags, due date, project) should be visible without opening the inspector.
- **Inspector card stack.** The right pane is a fixed-width card stack: identity/actions, optional subtasks, structure fields, expansion/notes, and AI/activity. It must never horizontally clip; if content is taller than the viewport, vertical scroll only.
- **Evidence timeline.** Task history reads as a timeline of semantic events. Agent events get a distinct iris treatment, user events are neutral, completion is mint, destructive/failure states are danger.

## Interaction patterns

- **Autosave routine edits.** Low-risk field edits should save automatically or with an inline action near the edited field. Large global "Save" buttons are reserved for explicit structure confirmation or pending dirty state.
- **Confirm before structure.** A captured item can be enriched automatically, but the user confirms its final structure before it becomes active.
- **Approval before consequence.** Any agent action that mutates external state needs an approval checkpoint and must record completion/failure back to task history.
- **Local-first optimism.** UI reflects local writes immediately and treats sync/agent work as asynchronous evidence that lands later.

## Visual patterns

- **Dark ink canvas.** Use a dark ink base with elevated panels and card shadows. The app should feel deep and spatial, not a flat black table.
- **Rounded control language.** Cards and chips use large radii; table rows use subtle selected fills instead of macOS default blue.
- **Metadata is monospaced.** Counts, dates, categories, labels, and provenance use the monospaced metadata voice.
- **No generic app chrome.** Avoid making settings, filters, or controls visually compete with capture and confirmation.

These patterns apply to Mac first, then web/iOS equivalents should preserve the same grammar with platform-native controls.
