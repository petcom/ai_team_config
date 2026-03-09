# QA Lifecycle Procedure

**Applies to:** All QA roles (backend-qa, frontend-qa)

```
LOOP: Poll → Validate → Verify → Review → Verdict → Complete or Iterate
```

---

## Phase 0: Scan & Triage (BLOCKING)

Every iteration starts here. Do not proceed until complete.

1. Read CONTENTS of every file in team `inbox/` (not `completed/`)
2. Read CONTENTS of every file in `issues/active/`
3. Classify inbox messages:

| Type | Action |
|------|--------|
| Dev handoff | → Phase 1 |
| Dev re-fix | → Phase 1 (re-validate) |
| Cross-team update | → Acknowledge |

4. Look for QA-ready markers: "Development Complete", "Awaiting QA", "Resolution Notes", `QA: PENDING_MANUAL_REVIEW`
5. Stale block recheck: `QA: BLOCKED` with last verification >12h → include for re-check
6. Stale manual review: `QA: PENDING_MANUAL_REVIEW` >30 min → prioritize ahead of new work
7. Output triage summary before proceeding

**Priority:** stale PENDING_MANUAL_REVIEW → fresh PENDING_MANUAL_REVIEW → re-fixes → new handoffs

## Phase 1: Entry Validation

1. Issue in `active/` with Status ACTIVE or DEV_COMPLETE
2. Resolution notes present
3. Acceptance criteria defined
4. **Freshness (previously BLOCKED):** Both required, each newer than last `## QA Verification`:
   - A fresh inbox handoff/re-handoff message from Dev
   - A `## Dev Response ({ISO timestamp})` section in the issue file
   Either alone is stale. First-time handoffs without prior QA verification use normal markers.
5. **Commit/push evidence required:** Dev handoff must include a commit reference and evidence the work was pushed to the shared remote branch.
   - Minimum acceptable evidence: commit hash in issue resolution/dev response notes, plus an explicit push statement in the Dev Response or handoff message
   - If commit/push evidence is missing, emit Need More Info — do not proceed
6. Implementation evidence: commits, changed files, or tests
7. If planning-only (no code), emit Need More Info — skip gates

## Phase 2: Automated Gates (BLOCKING)

### Backend-QA:
| Check | Command | Criteria |
|-------|---------|----------|
| Typecheck | `npx tsc --noEmit` | 0 errors |
| Unit tests | `npm run test:unit` | All pass |
| Integration | `npm run test:integration` | All pass |
| UAT | `npm run contracts:validate` | All pass |

### Frontend-QA:
| Check | Command | Criteria |
|-------|---------|----------|
| Typecheck | `npx tsc --noEmit` | 0 errors |
| Unit tests | `npx vitest run` | All pass |
| Integration | `npx vitest run --config vitest.integration.config.ts` | All pass |
| UAT | `npx playwright test --project=chromium` | All pass |

**On all pass:** Proceed to Phase 3. If manual review cannot be done this run, set `QA: PENDING_MANUAL_REVIEW` temporarily.
**On failure:** Record failures, move to Phase 4 with BLOCKED verdict.

## Phase 3: Manual Review

| Check | Look For |
|-------|----------|
| Accuracy | Logic matches acceptance criteria and spec |
| Efficiency | No unnecessary loops, queries, allocations |
| Non-duplication | Uses existing patterns/services |
| Security | No injection, proper auth, no PII leaks |
| ADR conformance | Follows architectural decisions |
| Contract alignment | Response shapes match contract DTOs exactly |
| Regression | Changes don't break unrelated functionality |

Map acceptance criteria → test evidence. Document gaps.

## Phase 4: Verdict

| Verdict | QA State | Next |
|---------|----------|------|
| **Pass** | PASS | → Phase 5 |
| **Pass with Conditions** | PASS | → Phase 5 with notes |
| **Blocked** | BLOCKED | → Phase 6 (dev fixes) |
| **Need More Info** | BLOCKED | → Phase 6 (iterate) |

`PENDING_MANUAL_REVIEW` is a **temporary checkpoint only** — not a dev blocker, not a resting state. QA must resolve it to PASS or BLOCKED promptly. Do NOT notify Dev for this state. If stale >30 min, resolve before taking new work.

**Evidence for every verdict:** issue ref, file/route ref, gate results, criteria-to-test mapping, manual review notes, commit/push evidence status, unblock criteria (for blocked).

**Severity:** Critical (security/data loss) → High (capability broken) → Medium (workflow gap) → Low (docs/naming)

## Phase 5: Completion (QA Only)

1. Set `QA: PASS`, `Status: COMPLETE` in issue file
2. Move issue `active/` → `completed/`
3. Move processed messages to `inbox/completed/`
4. Send completion notice to Dev's inbox

QA must NOT complete an issue if commit hash or push evidence is missing from the dev handoff.

Dev CANNOT execute this phase.

## Phase 6: Iterate

**Blocked/Need More Info:** Send findings to Dev inbox with gate results, unblock criteria, expected vs actual. Wait for Dev to re-submit with both a fresh inbox message and a fresh `## Dev Response (...)` section.

**While waiting:** Pick next QA-ready item.

**Exit:** All active issues completed, inbox clear.

Ownership boundaries: see `procedures/comms-protocol.md`.

---

## Loop Control

Continuous loop — runs until 30 idle minutes with no work.
- **Work done** → reset idle timer, return to Phase 0
- **No work** → idle timer continues; exit at 30 min
- Do NOT pause to ask user
- PENDING_MANUAL_REVIEW is required follow-through, not "done for now"
- Resolve stale manual reviews before new gate passes

## Autonomous Mode

```bash
ai_team_config/scripts/qa_poll_cycle.sh --autonomous
```

Implies `--watch --approve --recheck-existing --emit-dev-message`. Explicit flags override.
