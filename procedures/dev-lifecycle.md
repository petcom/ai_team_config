# Dev Lifecycle Procedure

**Applies to:** All dev roles (backend-dev, frontend-dev)

```
OUTER LOOP: Poll → Assess → Contracts → [INNER LOOP per issue]
INNER LOOP: Implement → Verify → Handoff → Iterate
```

---

## Phase 0: Scan & Triage (BLOCKING)

Every iteration starts here. Do not proceed until complete.

1. Read CONTENTS of every file in team `inbox/` (not `completed/`)
2. Read CONTENTS of every file in `issues/queue/` and `issues/active/`
3. Check active issues for `## Awaiting Response` entries
4. Classify each message:

| Type | Action |
|------|--------|
| Contract request | → Phase 1 |
| Plan / crosswalk | → Phase 0b |
| QA finding | → Match to active issue, prioritize re-fix |
| Bug report | → Phase 0b (assess, create issue) |
| Reply to outbound | → Match to thread, unblock issue |
| Question | → Respond directly |
| Status update | → Acknowledge |

5. Output triage summary (message count, action items) before proceeding

## Phase 0b: Assess & Decompose

For plans or multi-endpoint features:
1. Identify distinct work items, group by dependency
2. Create issues in `issues/queue/` for each
3. Proceed to Phase 1

## Phase 1: Contracts

**Backend-Dev (owner):** Define contract DTOs, send ONE consolidated confirmation.
**Frontend-Dev (consumer):** Check `contracts/types/`, request if missing. Never write normalizers.

Track outbound requests in issue file under `## Awaiting Response`.

## Phase 2: Context Loading

Load relevant ADRs, memory patterns, issue acceptance criteria, and existing code.

## Phase 2b: Design Principle Gate (BLOCKING)

Before writing any new type, API hook, endpoint shape, or backend message:

| Rule | Detail |
|------|--------|
| **No compatibility** | New features get ideal design. No shims, no graceful degradation, no `@deprecated`. |
| **Nullable, not optional** | New fields: `T \| null` (always present). Never `T?` (omittable). The endpoint returns every field — `null` if unset. |
| **Prescriptive contracts** | Backend messages state "the endpoint MUST return X" — not "it would be nice if." Types define the contract. |
| **Update callers, don't shim** | When a shape changes, update all consumers. Don't add compat layers. |
| **Spec silent on compat?** | Default to ideal design. |

Source: `dev_communication/shared/guidance/DEVELOPMENT_PRINCIPLES.md`

### Content entity rule (ADR-DEV-005)

All authored content entities (LearningUnit, Exercise, QuestionBank, ContentItem, Media, Module, Course) MUST have `departmentId`, `createdBy`, `sharedWithDepartment` at top level. Missing any field is a bug. See `dev_communication/shared/architecture/decisions/ADR-DEV-005-CONTENT-OWNERSHIP-DEPARTMENT-SCOPING.md`.

## Phase 3: Implementation

1. Move issue from `queue/` to `active/`
2. Implement; ensure response shapes match contract DTOs exactly
3. Write tests for new functionality
4. If QA re-fix, address specific findings first

## Phase 4: Dev Verification Gate (BLOCKING)

All must pass. Fix and re-run on failure.

### Backend-Dev:
| Check | Command | Criteria |
|-------|---------|----------|
| Typecheck | `npx tsc --noEmit` | 0 errors |
| Unit tests | `npm run test:unit` | All pass |
| Integration | `npm run test:integration` | All pass |
| Tests exist | (manual) | New code has tests |

### Frontend-Dev:
| Check | Command | Criteria |
|-------|---------|----------|
| Typecheck | `npx tsc --noEmit` | 0 errors |
| Unit tests | `npx vitest run` | All pass |
| Integration | `npx vitest run --config integration` | All pass |
| Tests exist | (manual) | New code has tests |

## Phase 5: Documentation & Handoff

1. Create session file: `memory/sessions/{date}-{issue-slug}.md`
2. Append resolution notes to issue file
3. Update `contracts/types/` if changed
4. If cross-team impact, send message to other team's inbox
5. Commit and push
6. **QA Handoff (BLOCKING — both steps required):**
   - **Step A:** Append `## Dev Response ({ISO timestamp})` to the issue file.
     Include: status, what was done, file refs, gate results.
   - **Step B:** Create handoff message in team inbox.
     First: `{date}_qa-handoff-{prefix}-{NNN}.md`
     Re-fix: `{date}_dev-rehandoff-{prefix}-{NNN}.md`
     Include From/To headers, fix summary, file refs, gate results.
   - **Both required.** Inbox-only fails QA freshness check. Issue-only fails
     because QA polls from inbox. Omitting either → QA skips the issue.

Issue stays in `active/`. Do NOT move to `completed/` or set COMPLETE — QA owns that.

## Phase 5b: Inbox Cleanup

Move processed messages to `inbox/completed/`. Inbox root = unprocessed only.

## Phase 6: Iterate

While waiting for QA, pick next unblocked issue.

| QA Verdict | Action |
|-----------|--------|
| Pass | QA moves to `completed/` — done |
| Blocked | Fix → run Phase 4 gates → **Phase 5 Step 6 (both A+B)** → move QA message to `inbox/completed/` |
| Need More Info | Respond → **Phase 5 Step 6 (both A+B)** → move QA message to `inbox/completed/` |

**Exit:** All issues completed by QA, queue empty, inbox clear, no open threads.

Ownership boundaries: see `procedures/comms-protocol.md`.

---

## Loop Control

This is a continuous loop, not a single pass. Runs until 30 idle minutes.
- **Work done** → reset idle timer, return to Phase 0
- **No work** → idle timer continues; exit at 30 min
- Do NOT pause to ask user before continuing
- Commit completed work as phases finish
- Send handoff messages immediately after Phase 5
