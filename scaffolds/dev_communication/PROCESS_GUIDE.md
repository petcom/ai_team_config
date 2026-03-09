# Dev Communication Process Guide

A complete guide to inter-team communication, issue tracking, and architecture decision management.

---

## Overview

The dev communication system connects three workflows:

```
Issues → Messages → Architecture Suggestions → ADRs
```

**Core principle:** Messages cross team boundaries. Issues stay local. Each team triages its own inbound messages and creates its own issues.

See `.claude-workflow/teams/protocol.yaml` for the universal communication protocol.

---

## Directory Structure

```
dev_communication/
├── {team}/                      # Per-team workspace
│   ├── definition.yaml          # Team identity, responsibilities, stack
│   ├── status.md                # Current focus and blockers
│   ├── inbox/                   # Messages TO this team
│   └── issues/                  # Issue tracking
│       ├── queue/               # Ready to work
│       ├── active/              # In progress
│       └── completed/           # Done
│
├── shared/                      # Cross-team resources
│   ├── registry.yaml            # Active teams in this project
│   ├── dependencies.md          # Cross-team blockers
│   ├── architecture/            # ADRs, suggestions, gaps
│   ├── guidance/                # Development guidelines
│   ├── specs/                   # Feature specifications
│   ├── plans/                   # Planning documents
│   └── contracts/               # API endpoint contracts
│
├── templates/                   # Message and issue templates
├── archive/                     # Completed message threads
├── index.md                     # Issue tracking dashboard
└── PROCESS_GUIDE.md             # This document
```

---

## Issue Management

Issues track discrete work items for each team.

### Issue Lifecycle

```
queue/          →        active/         →       completed/
   │                        │                        │
   │ Create                 │ Start work             │ Finish work
   ▼                        ▼                        ▼
┌──────────┐          ┌──────────┐           ┌──────────┐
│ Waiting  │    →     │ In Work  │     →     │   Done   │
└──────────┘          └──────────┘           └──────────┘
```

### Creating an Issue

Use `/comms issue` or manually create a file:

**Location:** `{team}/issues/queue/`

**Filename:** `{TEAM}-ISS-{NNN}_{brief_description}.md`

**Template:** `templates/issue-template.md`

**Important:** Only create issues in **your own** team's queue. To request work from another team, send a message to their inbox.

### Moving Issues

| Action | File Move |
|--------|-----------|
| Start work | `queue/` → `active/` |
| Complete | `active/` → `completed/` |

---

## Cross-Team Messaging

Messages enable async communication between teams.

### Message Flow

```
Team A                                    Team B
──────                                    ──────
              {team_b}/inbox/
Sends ──────────────────────────────► Receives + triages

              {team_a}/inbox/
Receives ◄────────────────────────── Sends
```

### When to Send Messages

| Scenario | Action |
|----------|--------|
| Need work from other team | Send request → They triage and create issue |
| Completed cross-team work | Send notification |
| Question about their code/API | Send inquiry |
| Found bug in their code | Send bug report with evidence |
| New or changed API contracts | Send contract proposal |

### Sending a Message

**Location:** `{recipient_team}/inbox/`

**Filename:** `YYYY-MM-DD_{subject_slug}.md`

**Template:** `templates/message-request.md`

### Processing Incoming Messages

When you receive a message:

1. **Request** → Triage and create a local issue if accepted
2. **Bug report** → Verify and create a local issue if confirmed
3. **Response** → Update the related issue
4. **Info** → Acknowledge and archive

Archive processed messages to `archive/`.

---

## Architecture Decisions

### The Pipeline

```
Trigger           →    Suggestion    →    Review    →    ADR
(work completed)       (draft idea)      (approve)      (formal record)
```

### Creating a Suggestion

Use `/adr suggest [topic]` or manually create in `shared/architecture/suggestions/`.

### Formal ADRs

**Location:** `shared/architecture/decisions/`

**Format:** `ADR-{DOMAIN}-{NNN}-{TITLE}.md`

---

## Issue Lifecycle — 6 Phase Workflow

Every issue follows six mandatory phases. No phase may be skipped.

### Phase 1: Intake — *Owner: Dev*

Triage inbound work into actionable issues with contracts and context.

1. **Check comms** — `/comms` to read inbox messages and identify pending requests
2. **Create issues** — Convert accepted inbound messages into local issues (`{team}/issues/queue/`)
3. **Read checklist** — `dev_communication/guidance/FEATURE_DEVELOPMENT_CHECKLIST.md`
4. **Define contracts** — If the work involves new or changed API endpoints, define contracts first and send to the other team (`/comms send`). Get agreement before implementation.
5. **Check ADRs** — `/adr` or read `dev_communication/shared/architecture/decisions/` for relevant decisions

Move issue from `queue/` to `active/` when starting work.

### Phase 2: Implementation — *Owner: Dev*

Build the feature or fix, with tests, in a verified state.

1. **Implement** — Write the code for the feature or fix
2. **Write tests** — Create unit and/or integration tests for the implementation
3. **Run tests** — `npx vitest run` to verify tests pass
4. **Verify TypeScript** — `npx tsc --noEmit` must report 0 errors

### Phase 3: Dev Verification — *Owner: Dev*

Validate the implementation against dev gate criteria. This is the developer's self-check before handing off to QA.

1. **Run dev gate checks:**
   - [ ] `npx tsc --noEmit` — 0 errors
   - [ ] `npx vitest run` — all tests pass
   - [ ] `npx vitest run --config vitest.integration.config.ts` — integration tests pass
   - [ ] New functionality has corresponding tests
2. **Create session file** — `memory/sessions/{date}-{issue-slug}.md`
3. **Append resolution notes** — Add implementation summary to the issue file under a dated "Resolution" or "Implementation Notes" section
4. **Review against code-reviewer-config** — Check `ai_team_config/team-configs/code-reviewer-config.json` criteria

If any check fails, return to Phase 2.

**IMPORTANT:** Dev does NOT move the issue to `completed/` or set `Status: COMPLETE`. The issue remains in `active/` with `Status: ACTIVE` after this phase. Dev work is done — the issue is now ready for QA.

### Phase 4: QA Verification — *Owner: QA Team or QA Sub-team*

Independent verification by QA before the issue can be closed. Dev does not perform this phase.

Use shared checklist:
- `ai_team_config/teams/checklists/qa-gate.yaml`
- `dev_communication/shared/guidance/QA_POLLING_CHECKLIST.md`
- Runner: `ai_team_config/scripts/qa_poll_cycle.sh`

1. **Recheck implementation** — Run the same gate checks independently:
   - [ ] `npx tsc --noEmit` — 0 errors
   - [ ] `npx vitest run` — all tests pass
   - [ ] `npx vitest run --config vitest.integration.config.ts` — integration tests pass
2. **Review acceptance criteria** — Verify all acceptance criteria in the issue file are met
3. **Verify commit/push evidence** — Confirm the dev handoff includes a commit hash/reference and explicit evidence the work was pushed to the shared remote branch
4. **Verify test coverage** — Confirm new functionality has meaningful test coverage
5. **Decision:**
   - **Pass** → Proceed to Phase 5 (Completion)
   - **Fail** → Append QA recheck findings to issue file, set `QA decision: Blocked`, issue returns to dev for Phase 2

Recommended QA polling command:
- `ai_team_config/scripts/qa_poll_cycle.sh --watch --interval 240`

### Phase 5: Completion — *Owner: QA Team or QA Sub-team*

Only QA moves issues to completed. This happens after QA verification passes.

1. **Update issue file** — Set `Status: COMPLETE`, add commit hash, and only complete if push evidence was verified during QA
2. **Move issue** — `active/` to `completed/`

### Phase 6: Comms Response — *Owner: Dev*

Send a response to the originating team. **This phase is NOT optional.**

If the work was triggered by an inbound message from another team:

1. **Send response** — `/comms send` to the originating team's inbox
2. **Include in the response:**
   - What was fixed or built
   - What changed (endpoints, contracts, behavior)
   - Any action required on their side (e.g., update imports, use new field)
3. **Archive** — Move the original inbound message to `archive/` if not already done

---

## Quick Reference

### Commands

| Command | Description |
|---------|-------------|
| `/comms` | Check inbox and pending issues |
| `/comms send` | Send message to other team |
| `/comms issue` | Create new issue |
| `/comms status` | Update team status |
| `/comms move ISS-XXX {stage}` | Move issue (active/completed) |
| `/adr` | Show architecture status |
| `/adr suggest [topic]` | Create architecture suggestion |

### Priority Levels

| Priority | Response Time | Use When |
|----------|---------------|----------|
| Critical | Immediate | Blocking production/other team |
| High | Same session | Important, time-sensitive |
| Medium | Next session | Normal priority |
| Low | When convenient | Nice to have |
