# Capture vision

## North star

Capture turns loose intent into confirmed, owner-scoped work and safe agent follow-through without making the user wait at capture time or trust AI silently. It is an instant inbox, confirmation workflow, personal-context organiser, and agent workbench with one lifecycle across iOS, macOS, and web.

Evidence: [README](README.md), [architecture](docs/architecture.md), [rebuild feature specification](docs/rebuild-feature-spec.md).

## Why now

Commercial AI todo tools solve pieces of the workflow, but none combine local personal context, a self-hosted Mac Mini agent, autonomous task execution, and mandatory confirmation before durable task state. The gap is structural because SaaS products cannot reliably read a local Obsidian vault, run tools on private hardware, and own the task lifecycle across Gmail, calendar, location, web, and local files.

Evidence: [commercial landscape verdict](docs/research-commercial-landscape.md#6-verdict), [critical four-feature test](docs/research-commercial-landscape.md#3-the-critical-four-feature-test).

## Core belief

A trustworthy AI task system separates speed from judgement: capture happens instantly, software proposes structure, background workers enrich with evidence, and the human decides what becomes durable state. Agents can help do work only when their attempts are observable, attributable, idempotent, and approval-gated before consequential external changes.

Evidence: [architecture item lifecycle](docs/architecture.md#item-lifecycle), [ADR 0001](docs/adr-0001-architecture-planes.md).

## Product model

Capture is a command cockpit, not a generic project manager with AI features. The product model is a command deck for input, a triage queue for proposed items, an active outline for real tasks, and an inspector card stack for structure, evidence, subtasks, and agent history.

Every item moves through the same conceptual path: proposed, confirmed, active, done. Projects are ordinary tasks with recursive child tasks, and parent views roll up child progress and recent history without mutating child records.

Evidence: [UX patterns](docs/capture-ux-patterns.md), [architecture projects and recursive subtasks](docs/architecture.md#projects-and-recursive-subtasks).

## Who it serves

Capture is for a user who works across Apple devices, web, email, notes, calendar, and a private always-on machine, and who wants less inbox labour without giving software final authority over commitments. It serves people whose tasks are scattered across personal context and whose real need is trusted follow-through, not another list to maintain.

## Principles

1. **Conceptual integrity:** every surface uses the same grammar of instant capture, proposed state, human confirmation, active work, and evidence-led history.
2. **Production stability:** durable state is owner-scoped, constrained, idempotent, observable, and safe under retries.
3. **Outcome over output:** the product wins when work is captured, organised, confirmed, synced, and safely advanced, not when it produces more AI suggestions.
4. **Human-centred automation:** AI may suggest and agents may attempt, but humans approve structure and consequential action.
5. **Deep modules, narrow boundaries:** clients, backend, sync, data, and worker planes keep stable contracts while hiding internal mechanics.
6. **Evidence before trust:** AI and agent output carries provenance, confidence, and task history so decisions are fast without being blind.

Evidence: [conformance profile in rebuild specification](docs/rebuild-feature-spec.md#design-philosophies), [UX product grammar](docs/capture-ux-patterns.md#product-grammar).

## First market wedge

The first credible wedge is a personal AI todo system for the Obsidian, Gmail, Apple Calendar, and Mac Mini workflow that commercial tools cannot serve. The wedge starts with instant cross-surface capture, confirmation-first task state, background enrichment, and task history; it expands into personal-context retrieval and approval-gated agent execution once the trust loop is proven.

Evidence: [commercial gap analysis](docs/research-commercial-landscape.md#6-verdict), [recommended open-source patterns](docs/research-prior-art.md#summary-recommended-stack-per-sub-problem).

## Success criteria

Capture is working when mobile, desktop, and web can sign in to the same account, capture offline-first, sync when connectivity returns, require confirmation before activation, and show background enrichment without mutating confirmed fields. It is working strategically when personal-context suggestions reduce review effort, agent attempts leave auditable events, and parent task views make nested work legible without duplicating child history.

Evidence: [rebuild completion definition](docs/rebuild-feature-spec.md#rebuild-completion-definition), [behavioural acceptance suite](docs/rebuild-feature-spec.md#behavioural-acceptance-test-suite).

## What the project must prove

Capture must prove that a local-first command surface can stay faster than commercial task capture while adding personal-context intelligence later. It must prove that a self-hosted agent can be useful without becoming a hidden actor that changes durable state or external systems without approval. It must prove that recursive projects, task history, and enrichment can share one task model instead of splitting into separate project, automation, and notes products.

## Non-goals

Capture should not become a generic project management suite, a tag-based project system, a silent automation engine, or a vendor-specific demo for one sync provider, host, database, or UI framework. It should not expose raw datastore access to clients, block capture on remote AI, or let workers promote proposed items to active tasks.

Evidence: [non-goals for the rebuild](docs/rebuild-feature-spec.md#non-goals-for-the-rebuild).

## Strategic bets

The project bets on a modular monolith with narrow client-server boundaries, a hosted sync core for account-agnostic data, repository-owned task lifecycle writes, materialised parent rollups, and idempotent worker/agent operations. It also bets that personal-context integrations are more defensible than another AI planner, because the durable value is in the user's local vault, email threads, calendar constraints, task history, and private execution environment.

Evidence: [architecture planes](docs/architecture.md#planes), [open-source pattern research](docs/research-prior-art.md).

## Review questions

1. Which personal-context source proves the wedge first: Obsidian, Gmail, calendar, or agent attempts?
2. What evidence shows that confirmation is faster than manual organisation rather than just safer?
3. What action types are low-risk enough for agent execution without weakening user trust?
4. When should Capture expand beyond the single-user private-agent workflow into shared or team work?
5. Which success metric best captures the promise: time-to-capture, confirmation rate, avoided inbox work, completed agent attempts, or reduced missed commitments?
