---

# 2025–2026 AI-Powered Todo Systems: Full Commercial Landscape Assessment

## Research Methodology & Sources

All data gathered from official product websites (verified June 2026), official help centres, and pricing pages. Sources are cited inline. Where a product's site blocked automated rendering (Mem.ai, C5), supplementary knowledge from documented product reviews is used and marked as such.

---

## 1. Feature Assessment — Individual Products

### **Saner.AI** — `saner.ai`

**Category:** AI personal assistant (ADHD-focused), note + email + calendar  
**Platforms:** Web only (no native macOS/iOS app)  
**Pricing:** Free tier; paid at ~$8/month (from page metadata: *"Upgrade for just $8/month"*, `saner.ai/pricing`)  
**Self-hostable:** No

**Capability notes (from `saner.ai` homepage + `help.saner.ai`):**  
- Connects Google Calendar; syncs events and can suggest daily plans  
- Inbox for tasks; connector section covers Google Calendar sync  
- AI chat to search notes, manage email, schedule tasks  
- No Obsidian integration documented anywhere in the help centre  
- No autonomous "do the task" agent; no computer use  
- No Apple Calendar support (Google Calendar only)  
- No native iOS/macOS apps; web-only = slow mobile capture

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ⚠️ Partial — web only, no native iOS/macOS |
| F2: AI suggests due date + category | ✅ AI-driven inbox + scheduling suggestions |
| F3: Obsidian vault | ❌ Not found in docs |
| F4: Gmail scan → extract + auto-complete | ⚠️ Partial — email inbox AI, unclear auto-completion |
| F5: Apple Calendar feasibility | ❌ Google Calendar only |
| F6: Autonomous agent (research + do) | ❌ None |
| F7: Location + web awareness | ❌ Not documented |
| F8: Confirm before save | ✅ Inbox review flow |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Lindy** — `lindy.ai`

**Category:** AI work assistant (email/calendar/meetings/delegation)  
**Platforms:** Web, iOS, iMessage/SMS delegation  
**Pricing:** Plus $49.99/mo → Max $199.99/mo; 7-day free trial (`lindy.ai/pricing`)  
**Self-hostable:** No (cloud-only SaaS)

**Capability notes:**  
- Strongest autonomous-action product in this list: "computer use" (Pro+ tier) allows Lindy to operate browser-based tools on user's behalf  
- Gmail triage, draft replies, extract action items, surface deadlines  
- Google Calendar + Outlook scheduling; no native Apple Calendar  
- 100+ integrations (Slack, Notion, HubSpot, Zoom, etc.)  
- Approval-first design: "Lindy drafts and proposes; the user controls what gets sent" (`lindy.ai/pricing`)  
- No Obsidian integration listed  
- No dedicated task-manager UI for fast capture

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ⚠️ Partial — delegation via iMessage, no quick-add UI |
| F2: AI suggests due date + category | ⚠️ Partial — infers context, but not a traditional task form |
| F3: Obsidian vault | ❌ Not listed |
| F4: Gmail scan → extract + auto-complete | ✅ Yes — triage, extract todos, can send follow-ups |
| F5: Apple Calendar feasibility | ❌ Google/Outlook only |
| F6: Autonomous agent (research + do) | ✅ Computer use (Pro+), broad action library |
| F7: Location + web awareness | ⚠️ Web browsing yes; location no |
| F8: Confirm before save | ✅ Approval-first: proposes before sending |
| F9: Self-hosted Mac Mini agent | ❌ Cloud-only |

---

### **Motion** — `usemotion.com`

**Category:** AI task planner + project manager + calendar  
**Platforms:** iOS, Android, Desktop (Mac/Windows), Web  
**Pricing:** Pro AI $19/seat/mo (annual); Business AI $29/seat/mo (annual) (`usemotion.com/pricing`)  
**Self-hostable:** No

**Capability notes:**  
- Auto-scheduling engine: assigns tasks to calendar slots based on priority, deadlines, and existing meetings; re-optimises hundreds of times a day  
- Creates tasks from forwarded Gmail/Outlook emails, Zoom/Slack messages  
- Strong Apple integration via Siri voice commands; no direct Apple Calendar reading noted  
- No Obsidian vault integration  
- AI tasks + AI project manager + AI notetaker in one suite  
- No autonomous agent that "does" external tasks; no computer use

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ✅ All platforms, Siri voice, email-to-task |
| F2: AI suggests due date + category | ✅ Core feature — auto-schedules, assigns to projects |
| F3: Obsidian vault | ❌ Not available |
| F4: Gmail scan → extract + auto-complete | ⚠️ Forward email → task; no auto-completion of tasks |
| F5: Apple Calendar feasibility | ⚠️ Reads Google/Outlook; iCloud via forwarding, not direct |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ❌ Not documented |
| F8: Confirm before save | ⚠️ Project review prompts; no mandatory confirmation modal |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Reclaim.ai** — `reclaim.ai`

**Category:** AI calendar optimisation + scheduling + focus-time protection  
**Platforms:** Web (Google Calendar overlay; no native apps)  
**Pricing:** Lite (free limited) → Starter → Business → Enterprise (price not shown on fetch; known to be ~$10–15/mo)  
**Self-hostable:** No

**Capability notes:**  
- AI scheduling agent that reads Google/Outlook Calendar and auto-places tasks, habits, focus blocks  
- Integrates with Jira, Asana, ClickUp, Todoist, Google Tasks for task-to-calendar scheduling (`reclaim.ai/features/tasks`)  
- Conversational planner; preview-and-approve before changes applied  
- No task manager UI (relies on external task tools)  
- No Obsidian, no autonomous agents, no location features

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ⚠️ Partial — no native capture; depends on connected task app |
| F2: AI suggests due date + category | ⚠️ Partial — suggests time slots, not categories |
| F3: Obsidian vault | ❌ No |
| F4: Gmail scan → extract + auto-complete | ❌ No |
| F5: Apple Calendar feasibility | ❌ Google + Outlook only |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ✅ Preview + approval before calendar changes |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Akiflow** — `akiflow.com`

**Category:** Time-blocking digital planner + universal task inbox + AI calendar  
**Platforms:** Desktop (Mac/Windows), Mobile (iOS/Android), Web  
**Pricing:** $34/mo monthly; $19/mo billed annually (`akiflow.com/pricing`)  
**Self-hostable:** No

**Capability notes:**  
- Universal Inbox pulls tasks from Slack, Gmail, Notion, Jira, 30+ tools  
- Quick capture via command bar, global hotkeys; capture from email, Slack, web, WhatsApp  
- "Aki" AI assistant — chat, AI workflows for routing tasks, auto project assignment  
- Email → task conversion from Gmail; "Emails Into Tasks" feature listed  
- Google Calendar + Outlook Calendar 2-way sync  
- No Apple Calendar native integration found  
- No Obsidian; no autonomous agent; no location

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ✅ All platforms, global hotkeys, command bar |
| F2: AI suggests due date + category | ✅ Auto project assignment; AI categorisation |
| F3: Obsidian vault | ❌ Not listed |
| F4: Gmail scan → extract + auto-complete | ⚠️ Gmail → task extraction; no auto-completion |
| F5: Apple Calendar feasibility | ❌ Google/Outlook only |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ⚠️ Inbox review; no explicit confirm-before-save gate |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Todoist** — `todoist.com`

**Category:** Classic task manager with AI assist  
**Platforms:** iOS, Android, macOS, Windows, Web, browser extensions  
**Pricing:** Beginner free; Pro $5/mo (annual) / $8/mo (monthly); Business $8/seat/mo annual (`todoist.com/pricing`)  
**Self-hostable:** No

**Capability notes:**  
- "Smart Quick Add" with NLP for dates/times  
- "Task Assist" (Pro+): AI rewrites, breaks down tasks, suggests next steps  
- "Ramble" feature: voice brain-dump that AI organises into tasks  
- 80+ integrations; Gmail plugin available  
- No AI-suggested categories on entry (labels are manual)  
- No Obsidian native integration (community plugins exist for two-way sync via unofficial extensions)  
- No Apple Calendar; no autonomous agents; no location

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ✅ All platforms, browser extension, widgets |
| F2: AI suggests due date + category | ⚠️ Partial — NLP dates yes; category suggestions minimal |
| F3: Obsidian vault | ❌ Unofficial community plugins only |
| F4: Gmail scan → extract + auto-complete | ⚠️ Gmail plugin extracts email → task; no auto-completion |
| F5: Apple Calendar feasibility | ❌ No native Apple Calendar integration |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ✅ Standard add-task flow |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **TickTick** — `ticktick.com`

**Category:** Feature-rich task manager + calendar + Pomodoro  
**Platforms:** iOS, Android, macOS, Windows, Web, Apple Watch  
**Pricing:** Free tier; Premium ~$2.99/mo (annual) or $35.99/year  
**Self-hostable:** No

**Capability notes:**  
- NLP for task entry; voice input; Google Calendar integration  
- Location reminders on iOS only (`ticktick.com/about/features`)  
- Kanban, timeline, calendar views  
- Habit tracker, Pomodoro built-in  
- No AI date/category suggestions beyond NLP date parsing  
- No Obsidian, no Gmail scanning, no Apple Calendar read, no agent

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ✅ All platforms, widgets, voice |
| F2: AI suggests due date + category | ⚠️ NLP dates only; no AI category suggestions |
| F3: Obsidian vault | ❌ No |
| F4: Gmail scan → extract + auto-complete | ❌ No |
| F5: Apple Calendar feasibility | ❌ Google Calendar sync only |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ⚠️ Location reminders (iOS only); no web awareness |
| F8: Confirm before save | ✅ Standard add UI |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Things 3** — `culturedcode.com/things`

**Category:** Premium personal task manager (Apple-only)  
**Platforms:** macOS, iOS, iPadOS, Apple Watch — no web, no Windows  
**Pricing:** One-time: iPhone $9.99 / iPad $19.99 / Mac $49.99  
**Self-hostable:** N/A (local-only sync via Things Cloud)

**Capability notes:**  
- No AI features whatsoever  
- Apple Design Award winner; best-in-class UX and keyboard shortcuts  
- Apple Reminders/Calendar read via system integration  
- URL scheme and Shortcuts support (automatable)  
- No web app, no Android, no team features, no agents  
- Obsidian community has unofficial Things 3 plugins for two-way sync

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ⚠️ Excellent iOS/macOS; no web |
| F2: AI suggests due date + category | ❌ None |
| F3: Obsidian vault | ❌ Unofficial plugins only |
| F4: Gmail scan → extract + auto-complete | ❌ No |
| F5: Apple Calendar feasibility | ✅ Reads Apple Calendar natively via system |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ✅ Add task flow |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Sunsama** — `sunsama.com`

**Category:** Daily planner + mindful task management  
**Platforms:** Web, macOS desktop (Electron), iOS  
**Pricing:** $22/mo monthly; $204/year (~$17/mo) (`help.sunsama.com/docs/pricing-manifesto`)  
**Self-hostable:** No

**Capability notes:**  
- Integrations: Jira, Asana, Trello, GitHub, Todoist, Gmail, Notion, Outlook, ClickUp, Linear, Slack, Teams, Zoom, Monday, Zapier, Apple Reminders, Google Tasks, Microsoft To Do, **MCP** (`help.sunsama.com/docs/integrations`)  
- Apple Reminders integration means it can pull Apple Calendar-linked reminders  
- Gmail integration for email → task  
- Notion integration (read tasks from Notion)  
- **MCP support** — means in theory Obsidian notes can be surfaced via custom MCP server  
- No autonomous AI agent; no location; no AI categorisation

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ✅ Web + macOS + iOS |
| F2: AI suggests due date + category | ❌ No AI suggestions |
| F3: Obsidian vault | ⚠️ Via MCP only (requires custom setup) |
| F4: Gmail scan → extract + auto-complete | ⚠️ Gmail → task pull; no auto-completion |
| F5: Apple Calendar feasibility | ⚠️ Via Apple Reminders integration (indirect) |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ✅ Daily planning review ritual built-in |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Mem.ai** — `mem.ai`

**Category:** AI-first note-taking + knowledge management  
**Platforms:** Web, iOS (note: site requires modern browser; no macOS native app)  
**Pricing:** ~$8/mo (Mem AI) / ~$14.99/mo (Mem Teams) — from public sources; site blocked automated rendering  
**Self-hostable:** No

**Capability notes (from known product state as of mid-2025):**  
- AI organises notes automatically (no manual folders); finds connections  
- AI assistant chat across all your notes  
- Not a task manager — no due dates, reminders, scheduling as first-class features  
- No Obsidian vault integration  
- No Gmail scanning, no calendar read, no agents

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ⚠️ Web + iOS; no macOS native |
| F2: AI suggests due date + category | ❌ Notes-focused; no task scheduling AI |
| F3: Obsidian vault | ❌ Competing note format |
| F4: Gmail scan → extract + auto-complete | ❌ No |
| F5: Apple Calendar feasibility | ❌ No |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ✅ Notes save with review |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Notion AI / Notion Agent** — `notion.so`

**Category:** All-in-one workspace with AI agents, calendar, mail  
**Platforms:** iOS, Android, macOS, Windows, Web  
**Pricing:** Free → Plus $12/mo → Business $18/mo → Enterprise; full AI Agent requires Business tier; Notion Calendar and Notion Mail (Gmail sync) included free (`notion.so/pricing`)  
**Self-hostable:** No

**Capability notes:**  
- "Notion Agent" (Business+): takes on entire tasks using context from workspace and connected apps; creates/edits pages and databases  
- "Custom Agents": automate recurring work (route tasks, answer Slack questions)  
- Notion Mail syncs with Gmail; can surface action items  
- Notion Calendar (formerly Cron) fully integrated  
- AI Meeting Notes (Business tier): transcribes, summarises, surfaces tasks  
- **No Obsidian integration** (Notion is the competing note format; import only, no live sync)  
- Apple Calendar: Notion Calendar reads Google Calendar; Apple Calendar not natively supported  
- No self-hosting; no location awareness

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ✅ All platforms |
| F2: AI suggests due date + category | ✅ Autofill database properties, AI task suggestions |
| F3: Obsidian vault | ❌ Competing product; no live Obsidian sync |
| F4: Gmail scan → extract + auto-complete | ✅ Notion Mail + Agent can draft responses |
| F5: Apple Calendar feasibility | ❌ Google Calendar only in Notion Calendar |
| F6: Autonomous agent (research + do) | ✅ Notion Agent + Custom Agents (Business tier) |
| F7: Location + web awareness | ⚠️ Web browsing via Research Mode; no location |
| F8: Confirm before save | ⚠️ Agent proposes actions; confirmation is implicit not mandatory |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **ClickUp Brain** — `clickup.com`

**Category:** AI-powered project management + work OS  
**Platforms:** iOS, Android, macOS, Windows, Web  
**Pricing:** Free tier; Unlimited $7/mo; Business $12/mo; Business Plus $19/mo (all annual); Brain add-on was $5/seat/mo but is now bundled (`clickup.com/features/ai`)  
**Self-hostable:** No

**Capability notes:**  
- "Brain²": AI assistant with full ClickUp workspace context; can create tasks, write docs, update statuses  
- Connected to Gmail/Drive/Jira with "computer use"-like briefing  
- Can pull Gmail context into meeting prep (from site demo text)  
- AI task creation, status updates, project generation  
- No Obsidian; no Apple Calendar; no location; no self-hosting

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ✅ All platforms |
| F2: AI suggests due date + category | ✅ AI task creation with suggested properties |
| F3: Obsidian vault | ❌ No |
| F4: Gmail scan → extract + auto-complete | ⚠️ Can read Gmail context; no autonomous email completion |
| F5: Apple Calendar feasibility | ❌ Google Calendar only |
| F6: Autonomous agent (research + do) | ⚠️ AI in-workspace actions; no external "computer use" |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ⚠️ AI proposes; not mandatory gate |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Taskade** — `taskade.com`

**Category:** AI agent workspace (projects + agents + automations)  
**Platforms:** iOS, Android, macOS, Windows, Web  
**Pricing:** Free (3,000 credits); Starter $6/mo; Pro $19/mo; Business $49/mo (`taskade.com/pricing`)  
**Self-hostable:** No (Enterprise has "private cloud" option)

**Capability notes:**  
- 100+ integrations (Slack, Gmail, GitHub, Stripe, Zapier, Make)  
- AI agents can be assigned tasks: researcher, writer, reviewer — with hand-offs  
- "24/7 runtime" with durable workflows  
- Agents can act in connected apps  
- Ships "live apps" as cloneable deployable units  
- No Obsidian; no Apple Calendar; no location; no personal confirm-before-save gate (teams-focused)

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ✅ All platforms |
| F2: AI suggests due date + category | ⚠️ Partial — AI can suggest in context |
| F3: Obsidian vault | ❌ No |
| F4: Gmail scan → extract + auto-complete | ⚠️ Gmail integration; agent can draft; not personal-task focused |
| F5: Apple Calendar feasibility | ❌ No |
| F6: Autonomous agent (research + do) | ✅ Agent teams, 24/7 runtime, 100+ app actions |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ⚠️ Not a first-class personal confirmation gate |
| F9: Self-hosted Mac Mini agent | ⚠️ Enterprise "private cloud" — but not local Mac Mini |

---

### **Amie** — `amie.so`

**Category:** Calendar + AI meeting notes + Gmail AI  
**Platforms:** macOS (native with notch UI), iOS, Web  
**Pricing:** Not clearly listed on public page; known to be ~$15/mo (from community sources)  
**Self-hostable:** No

**Capability notes:**  
- Meeting recording without bot: macOS notch overlay, auto-transcription  
- "Chat Actions": draft emails, create/update meetings, rewrite summaries  
- Gmail integration: rewrites emails in your voice; AI chat with Gmail context  
- Google Calendar + Apple Calendar integration  
- AI task suggestions from meeting notes ("one-click add to tasks")  
- No Obsidian; no autonomous agent that does external tasks; no self-hosting

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ✅ macOS + iOS + Web |
| F2: AI suggests due date + category | ⚠️ Meeting-sourced task suggestions with one-click add |
| F3: Obsidian vault | ❌ No |
| F4: Gmail scan → extract + auto-complete | ✅ Gmail AI chat + action drafting |
| F5: Apple Calendar feasibility | ✅ Native Apple Calendar integration confirmed |
| F6: Autonomous agent (research + do) | ❌ Chat actions only; no external task execution |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ✅ One-click confirm from meeting suggestions |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Cron / Notion Calendar** — `calendar.notion.so`

**Category:** Calendar app (Cron acquired by Notion 2022; rebranded as Notion Calendar 2024)  
**Platforms:** macOS, iOS, Web  
**Pricing:** Free (included with Notion account)  
**Self-hostable:** No

**Capability notes:**  
- Pure calendar app; no task management layer  
- Deeply integrates with Notion databases (tasks can appear as calendar events)  
- Google Calendar integration; no Apple Calendar  
- No AI agent; no Gmail scanning; no Obsidian

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ⚠️ Calendar events only; not task capture |
| F2: AI suggests due date + category | ❌ No |
| F3: Obsidian vault | ❌ No |
| F4: Gmail scan → extract + auto-complete | ❌ No |
| F5: Apple Calendar feasibility | ❌ No (Google Calendar only) |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ✅ Standard event creation |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Superhuman** — `superhuman.com`

**Category:** Premium AI email client  
**Platforms:** macOS, iOS, Web (no Android)  
**Pricing:** Starter $25/seat/mo; Business $33/seat/mo (`superhuman.com/pricing`)  
**Self-hostable:** No

**Capability notes:**  
- AI email: Auto-drafts, Auto-labels, Auto-reminders, Ask AI, Voice/Tone match  
- "Auto Drafts" (Business): AI drafts replies before you even open email  
- Calendar integration for scheduling; Zoom/Meet/Teams  
- **Superhuman Mail MCP** (Business): exposes email data to AI agents via MCP protocol  
- No task management; no Obsidian; no autonomous "do" agent; no location

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ❌ Email only, no task capture |
| F2: AI suggests due date + category | ❌ Not applicable |
| F3: Obsidian vault | ❌ No |
| F4: Gmail scan → extract + auto-complete | ✅ Auto-drafts, AI reply suggestions, action extraction |
| F5: Apple Calendar feasibility | ❌ No calendar feasibility check |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ✅ Review before send |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Shortwave** — `shortwave.com`

**Category:** AI email client with workflow automation  
**Platforms:** Web, iOS  
**Pricing:** Business $24/seat/mo; Premier $36/seat/mo; Max $100/seat/mo (`shortwave.com/pricing`)  
**Self-hostable:** No

**Capability notes:**  
- AI organises inbox, extracts todos, AI filters, AI autocomplete  
- Turns emails into Todos natively (with notes, grouping, drag-reorder)  
- Sister product **Tasklet** for 24/7 workflow automation connecting to 3,000+ apps  
- Calendar integration (check availability, create events) via AI Assistant  
- AI memory: remembers preferences about writing style/behaviour  
- MCP integration for AI integrations + web browsing  
- No Obsidian; no Apple Calendar; no location; no autonomous "do" agent

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ⚠️ Email→task only; web + iOS |
| F2: AI suggests due date + category | ⚠️ AI snooze suggestions; no category AI |
| F3: Obsidian vault | ❌ No |
| F4: Gmail scan → extract + auto-complete | ✅ Extracts todos; Tasklet can auto-draft |
| F5: Apple Calendar feasibility | ❌ No |
| F6: Autonomous agent (research + do) | ⚠️ Via Tasklet (separate product, 3,000+ app actions) |
| F7: Location + web awareness | ⚠️ Web browsing (Business+); no location |
| F8: Confirm before save | ✅ Todo review flow |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **Raycast** — `raycast.com`

**Category:** macOS launcher with AI, extensions, and automation  
**Platforms:** macOS only (no iOS, no web, no Windows)  
**Pricing:** Free (core launcher); Pro $8/mo with AI chat, cloud sync (`raycast.com` title from pricing page: *"Free Forever or Pro with AI for $8/month"*)  
**Self-hostable:** No (but runs locally on your Mac)

**Capability notes:**  
- Extension ecosystem includes **Obsidian extension** (confirmed in `raycast.com/core-features/ai` — shows Obsidian extension icon), Todoist extension, many others  
- AI chat with 32+ models; Quick AI; custom AI Commands  
- Snippets, quicklinks, scripts, window management  
- **Can bridge Obsidian → other tools** via extensions, but is a launcher not a todo system  
- No iOS; no web; no calendar AI; no task scheduling; no autonomous agent

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ⚠️ macOS only; extremely fast keyboard-first |
| F2: AI suggests due date + category | ❌ Not a task manager |
| F3: Obsidian vault | ✅ Obsidian extension (read/write notes) |
| F4: Gmail scan → extract + auto-complete | ❌ No |
| F5: Apple Calendar feasibility | ⚠️ Can read Calendar via extension; not AI-driven |
| F6: Autonomous agent (research + do) | ⚠️ AI Commands + scripts; manual, not autonomous |
| F7: Location + web awareness | ⚠️ Quick AI has web search; no location |
| F8: Confirm before save | ✅ All actions confirmed via launcher |
| F9: Self-hosted Mac Mini agent | ⚠️ Runs locally, but is a launcher not a self-hosted agent |

---

### **C5 (Mac)** — App Store only (niche product)

**Category:** Minimalist macOS/iOS widget-based task list  
**Platforms:** macOS, iOS  
**Pricing:** ~$4.99 one-time or free with in-app (App Store; exact price unconfirmed; not officially reachable)  
**Self-hostable:** N/A

**Capability notes (from known product state):**  
- Ultra-minimal widget-first task app for macOS/iOS  
- No AI features, no calendar, no integrations  
- Apple Reminders-based or standalone storage  
- Purpose: frictionless quick-add from menu bar or lock screen

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ✅ macOS/iOS widget; extremely fast; no web |
| F2: AI suggests due date + category | ❌ None |
| F3: Obsidian vault | ❌ No |
| F4: Gmail scan → extract + auto-complete | ❌ No |
| F5: Apple Calendar feasibility | ❌ No |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ❌ No |
| F8: Confirm before save | ✅ Widget tap to add |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

### **GoodTask** — `goodtaskapp.com`

**Category:** Apple Reminders/Calendar enhancer  
**Platforms:** macOS, iOS, iPadOS, Apple Watch — no web, no Windows  
**Pricing:** $9.99 one-time (iOS) / $39.99 one-time (Mac)  
**Self-hostable:** N/A (local)

**Capability notes:**  
- Built **entirely on top of Apple Reminders and Calendars** — reads and writes natively  
- Smart Lists, quick actions, text snippets, themes  
- **Apple Calendar + Apple Reminders full integration** — best in class for Apple ecosystem  
- No AI features beyond Apple's own Siri suggestions  
- No web, no Obsidian, no agents

| Feature | Status |
|---|---|
| F1: Fast capture iOS/macOS/web | ⚠️ iOS/macOS only; very fast via Apple integration |
| F2: AI suggests due date + category | ❌ None |
| F3: Obsidian vault | ❌ No |
| F4: Gmail scan → extract + auto-complete | ❌ No |
| F5: Apple Calendar feasibility | ✅ Native — built on Apple Calendar |
| F6: Autonomous agent (research + do) | ❌ No |
| F7: Location + web awareness | ✅ Location reminders via Apple Reminders |
| F8: Confirm before save | ✅ Standard Apple Reminders flow |
| F9: Self-hosted Mac Mini agent | ❌ No |

---

## 2. Full Feature-Comparison Matrix

> **Legend:** ✅ Full support | ⚠️ Partial / requires workaround | ❌ Not supported

| Product | F1: Fast Capture (iOS+Mac+Web) | F2: AI Date+Category | F3: Obsidian Vault | F4: Gmail Scan+Auto-Complete | F5: Apple Calendar Feasibility | F6: Autonomous Agent (Do Task) | F7: Location+Web Aware | F8: Confirm Before Save | F9: Self-Host Mac Agent | Platforms | Price/mo |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|---|
| **Saner.AI** | ⚠️ | ✅ | ❌ | ⚠️ | ❌ | ❌ | ❌ | ✅ | ❌ | Web only | ~$8 |
| **Lindy** | ⚠️ | ⚠️ | ❌ | ✅ | ❌ | ✅ | ⚠️ | ✅ | ❌ | Web, iOS, iMsg | $50–200 |
| **Motion** | ✅ | ✅ | ❌ | ⚠️ | ⚠️ | ❌ | ❌ | ⚠️ | ❌ | All | $19–29 |
| **Reclaim.ai** | ⚠️ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | Web | ~$10–15 |
| **Akiflow** | ✅ | ✅ | ❌ | ⚠️ | ❌ | ❌ | ❌ | ⚠️ | ❌ | All | $19–34 |
| **Todoist** | ✅ | ⚠️ | ❌ | ⚠️ | ❌ | ❌ | ❌ | ✅ | ❌ | All | Free–$8 |
| **TickTick** | ✅ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ⚠️ | ✅ | ❌ | All | ~$3 |
| **Things 3** | ⚠️ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | Apple only | $50–80 (one-time) |
| **Sunsama** | ✅ | ❌ | ⚠️ | ⚠️ | ⚠️ | ❌ | ❌ | ✅ | ❌ | Web, Mac, iOS | $17–22 |
| **Mem.ai** | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | Web, iOS | ~$8–15 |
| **Notion AI** | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ⚠️ | ⚠️ | ❌ | All | $15–18+ |
| **ClickUp Brain** | ✅ | ✅ | ❌ | ⚠️ | ❌ | ⚠️ | ❌ | ⚠️ | ❌ | All | $7–19 |
| **Taskade** | ✅ | ⚠️ | ❌ | ⚠️ | ❌ | ✅ | ❌ | ⚠️ | ⚠️ | All | Free–$49 |
| **Amie** | ✅ | ⚠️ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | Mac, iOS, Web | ~$15 |
| **Notion Calendar** | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | Mac, iOS, Web | Free |
| **Superhuman** | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | Mac, iOS, Web | $25–33 |
| **Shortwave** | ⚠️ | ⚠️ | ❌ | ✅ | ❌ | ⚠️ | ⚠️ | ✅ | ❌ | Web, iOS | $24–100 |
| **Raycast** | ⚠️ | ❌ | ✅ | ❌ | ⚠️ | ⚠️ | ⚠️ | ✅ | ⚠️ | macOS only | Free–$8 |
| **C5 (Mac)** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | Mac, iOS | ~$5 (one-time) |
| **GoodTask** | ⚠️ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | Apple only | $40–50 (one-time) |

---

## 3. The Critical Four-Feature Test

You explicitly highlighted four blockers as the hardest combination. Here is how every product scores on **F3 (Obsidian) + F6 (Autonomous Do) + F9 (Self-host) + F8 (Confirm before save)**:

| Product | F3 Obsidian | F6 Autonomous Do | F9 Self-Host | F8 Confirm | **All 4?** |
|---|:---:|:---:|:---:|:---:|:---:|
| Lindy | ❌ | ✅ | ❌ | ✅ | ❌ |
| Notion AI | ❌ | ✅ | ❌ | ⚠️ | ❌ |
| Taskade | ❌ | ✅ | ⚠️ | ⚠️ | ❌ |
| Raycast | ✅ | ⚠️ | ⚠️ | ✅ | ❌ |
| Sunsama | ⚠️ | ❌ | ❌ | ✅ | ❌ |
| All others | ❌ | ❌ | ❌ | ✅/⚠️ | ❌ |

**Result: Zero products satisfy all four critical features simultaneously.** Not one comes close.

### Why each gap is hard to close:

**F3 — Obsidian vault:** Obsidian stores notes as local `.md` files. Commercial SaaS products store data in their own cloud schema. The only path to Obsidian integration is (a) reading local files via a local background process, (b) using the Obsidian Local REST API plugin, or (c) bidirectional sync via a custom MCP server. No commercial todo product does any of this natively. Raycast can *open* Obsidian notes via extension, but that is not vault-aware semantic integration (it doesn't understand your note graph, pull tasks from your vault, or push back).

**F6 — Autonomous "do the task":** Lindy (computer use, Pro plan) and Taskade (agents) come closest, but these are cloud agents that operate inside your connected SaaS apps. They cannot run a local Mac process, call local tools, access your local file system, or self-host. They also do not have the task-domain model needed to know *which* task to act on and when.

**F9 — Self-hosted Mac Mini:** **Zero** commercial products support this. This is the single hardest requirement to satisfy off-the-shelf. All autonomous-agent features in commercial products are cloud-computed. Self-hosting implies running an LLM inference layer (e.g. Ollama), an agent framework (e.g. LangGraph, AutoGen, CrewAI), and a tool-execution layer on your own hardware. None of the 20 products above expose this.

**F4 + F6 combined (Gmail scan → suggest task completion automatically):** The "suggest task completion automatically" part — i.e., the agent *offers* to actually *do* the task extracted from email — exists nowhere in a full personal-task workflow. Lindy is nearest (it can draft a reply and send it upon approval), but it is not integrated with a task list that has items from Obsidian, Apple Calendar, or other personal sources.

---

## 4. Best-in-Class by Feature

| Feature | Best Off-the-Shelf Option | Notes |
|---|---|---|
| Fastest capture (all 3 platforms) | **Motion** or **Akiflow** | Akiflow has best universal inbox + global hotkey |
| AI date + category suggestions | **Motion** | Auto-scheduling engine is genuinely autonomous |
| Obsidian vault | **Raycast** (extension) | Functional but shallow; no semantic graph integration |
| Gmail → task extraction + action | **Lindy** | Best autonomous Gmail handler in the list |
| Apple Calendar feasibility check | **Amie** or **GoodTask** | Amie = AI-powered; GoodTask = deepest Apple native |
| Autonomous "do the task" agent | **Lindy** (computer use) or **Notion Agent** | Lindy broader; Notion Agent deeper in workspace |
| Location awareness | **GoodTask** / **TickTick** | Via Apple Reminders; not AI-driven |
| Confirm before save | **Lindy** / **Sunsama** | Lindy: explicit approval-first; Sunsama: daily review ritual |
| Self-hosted agent | **None commercially** | Must build (Ollama + LangGraph/AutoGen + local tools) |

---

## 5. Closest Frankenstein Stack (if you refuse to build)

The best approximation of your feature list using existing commercial products requires **at minimum 3–4 tools duct-taped together**:

1. **Akiflow or Motion** — fast capture + AI scheduling + universal inbox + calendar feasibility (F1, F2, F5 partially)
2. **Lindy** — Gmail scanning + autonomous actions + approval workflow (F4, F6, F8)
3. **Raycast** — Obsidian bridge on macOS (F3 partially)
4. **Custom MCP / local script** — Obsidian REST API → Sunsama or Notion (F3 properly)
5. **GoodTask or Things 3** — Apple Calendar/Reminders native read (F5)

**Cost:** ~$70–90/month + significant integration engineering. **Reliability:** Fragile. **True self-hosting:** Still zero.

---

## 6. Verdict

### Is there an off-the-shelf product that makes building unnecessary?

**No. The gap is real, wide, and structural — not a matter of timing.**

Here is exactly where the frontier lies:

| Dimension | Off-the-shelf ceiling (2025-2026) | Your requirement |
|---|---|---|
| Capture | ✅ Excellent (Motion, Akiflow) | ✅ Solved |
| AI date/category | ✅ Good (Motion, Notion) | ✅ Solved |
| **Obsidian live vault sync** | ❌ Zero native support anywhere | **Gap** |
| Gmail → extract + complete | ✅ Good (Lindy, Shortwave) | ✅ Mostly solved |
| Apple Calendar read | ⚠️ Partial (Amie, GoodTask, not in AI tools) | **Gap in AI tools** |
| **Autonomous "do" agent** | ⚠️ Cloud-only (Lindy, Notion, Taskade) | **Half-solved** |
| **Self-hosted Mac Mini** | ❌ Zero commercial support | **Hard gap** |
| Confirm before save | ✅ Partial (Lindy, Sunsama) | ✅ Mostly solved |
| Location + web | ⚠️ Fragmented | Minor gap |

Three requirements — **Obsidian vault integration, self-hosted agent infrastructure, and the combined Gmail-to-completion autonomous loop with personal confirmation** — are not available off-the-shelf in any single product, or in any combination of products without substantial custom engineering. These are not gaps that will be closed in 6 months: they are *architectural* requirements that commercial SaaS tools are structurally unfit to provide (they cannot access your local vault, they cannot run on your hardware, and they cannot own your data end-to-end across these sources simultaneously).

### What you should build (and what you can buy to accelerate it)

The good news: you do **not** need to reinvent everything. A practical hybrid architecture is:

- **Buy:** Akiflow or Motion for UI/capture/scheduling front-end (or Sunsama for the calm planning ritual), plus Lindy or Shortwave for the Gmail intelligence layer
- **Build:** A local Mac Mini agent using Ollama (local LLM), LangGraph or AutoGen (agent framework), Obsidian Local REST API plugin, Apple Calendar EventKit bridge, and a confirmation-gated webhook that feeds items into your chosen front-end via API

The custom build surface is **much smaller** than a from-scratch app: it is a local agent + connector layer, not a UI. Your front-end can remain a polished commercial app; the intelligence and integration fabric lives on the Mac Mini. That is the architecture no single commercial product will give you, and it is the only path to satisfying all 9 features with high fidelity.

---

### Sources Referenced

- `saner.ai` + `help.saner.ai` (product + help docs)
- `lindy.ai` + `lindy.ai/pricing` (verified June 2026)
- `usemotion.com` + `usemotion.com/pricing`
- `reclaim.ai` + `reclaim.ai/features/tasks` + `reclaim.ai/integrations`
- `akiflow.com` + `akiflow.com/pricing`
- `todoist.com/features` + `todoist.com/pricing`
- `ticktick.com/about/features`
- `culturedcode.com/things`
- `sunsama.com` + `help.sunsama.com/docs/pricing-manifesto` + `help.sunsama.com/docs/integrations`
- `notion.so/product/ai` + `notion.so/pricing`
- `clickup.com/features/ai`
- `taskade.com` + `taskade.com/pricing`
- `amie.so` (main + pricing)
- `calendar.notion.so` (Cron → Notion Calendar confirmed)
- `superhuman.com` + `superhuman.com/pricing`
- `shortwave.com` + `shortwave.com/pricing`
- `raycast.com` + `raycast.com/core-features/ai` (Obsidian extension confirmed in extension gallery)
- `goodtaskapp.com`
- C5 (Mac): limited public information; assessed from known App Store presence