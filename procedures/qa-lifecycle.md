# QA Lifecycle Procedure

**Applies to:** All QA roles (backend-qa, frontend-qa)
**Machine-readable:** `teams/checklists/qa-gate.yaml`

---

## Overview

QA operates independently from Dev. QA polls for work that Dev has handed off,
verifies it meets acceptance criteria, and either approves (moves to completed)
or rejects (sends findings back to Dev for iteration).

```
LOOP: Poll → Validate → Verify → Review → Verdict → Complete or Iterate
```

---

## Phase 0: Poll for QA-Ready Items

**When:** Start of every iteration.

1. Read your team's inbox for new messages
2. Read your team's `issues/active/` for issues marked QA-ready
3. Look for QA-ready markers in issue files:
   - "Development Complete"
   - "Awaiting QA"
   - "QA Ready"
   - "Resolution Notes" (appended by Dev)
4. Check for stale blocks: if an issue has `QA: BLOCKED` and the last QA
   verification is older than 12 hours, include it in the candidate set
   for automatic re-check
5. Classify inbox messages:

| Message Type | Action |
|-------------|--------|
| Dev handoff notification | → Phase 1 (validate entry) |
| Dev re-fix after rejection | → Phase 1 (re-validate) |
| Cross-team status update | → Acknowledge |

6. Prioritize: re-fixes of previously blocked issues first, then new handoffs

---

## Phase 1: Entry Validation

Before running any checks, confirm the issue is ready:

1. Issue has Status: ACTIVE
2. Resolution notes are present (Dev filled these in during Phase 5)
3. Acceptance criteria are defined
4. Dev verification gate results are documented (typecheck, tests)
5. **Freshness check:** Issue has a QA Review Request or Dev Response timestamp
   newer than the last QA verification. Prevents re-running QA on stale stubs.
6. **Implementation evidence:** Issue has commit references, changed files, or
   test additions. If the issue is planning-only (no code evidence), emit
   "Need More Info" — do not run the full gate suite.

**If entry criteria are not met:** Send "Need More Info" back to Dev's inbox
with specific missing items. Do not proceed.

---

## Phase 2: Automated Verification (BLOCKING)

Run the automated test gates. All must pass for the issue to proceed.

### Backend-QA checks:
| Check | Command | Criteria |
|-------|---------|----------|
| Typecheck | `npx tsc --noEmit` | 0 errors |
| Unit tests | `npm run test:unit` | All pass |
| Integration tests | `npm run test:integration` | All pass |
| UAT (contract validation) | `npm run contracts:validate` | All pass |

### Frontend-QA checks:
| Check | Command | Criteria |
|-------|---------|----------|
| Typecheck | `npx tsc --noEmit` | 0 errors |
| Unit tests | `npx vitest run` | All pass |
| Integration tests | `npx vitest run --config integration` | All pass |
| UAT (E2E) | `npx playwright test` | All pass |

**Per-check timeout:** As configured in role yaml (default 120s).

**On failure:** Record which gate failed. Move to Phase 4 with "Blocked" verdict.

---

## Phase 3: Manual Review

Human-judgment checks that automation cannot catch:

| Check | What to Look For |
|-------|-----------------|
| Efficiency | No unnecessary loops, queries, or allocations |
| Accuracy | Logic matches acceptance criteria and spec |
| Non-duplication | No copy-paste code; uses existing patterns/services |
| Security | No injection vectors, proper auth checks, no PII leaks |
| ADR conformance | Follows architectural decisions (check relevant ADRs) |
| Contract alignment | Response shapes match shared contract DTOs exactly |
| Regression scope | Changes don't break unrelated functionality |

**Coverage assessment:**
- Check that acceptance criteria have corresponding tests
- If tests are missing, document which criteria need test coverage
- Include the acceptance-criteria-to-test mapping in your verdict

---

## Phase 4: Verdict & Evidence

Emit one of four verdicts:

| Verdict | When | Next Step |
|---------|------|-----------|
| **Pass** | All gates green, manual review clean | → Phase 5 (complete) |
| **Pass with Conditions** | Minor issues, non-blocking | → Phase 5 with notes |
| **Blocked** | Any gate failed or critical manual finding | → Phase 6 (iterate) |
| **Need More Info** | Cannot determine pass/fail | → Phase 6 (iterate) |

**Required evidence for every verdict:**
- Issue reference (ISS-xxx)
- File or route reference
- Automated gate results (pass/fail per gate)
- Coverage assessment (criteria-to-test mapping)
- Manual review notes
- For Blocked/Need More Info: clear unblock criteria

**Severity classification (for findings):**
- Critical: release-blocking, security, data loss
- High: role/capability broken
- Medium: workflow gap, non-blocking contract drift
- Low: minor UX/docs mismatch

**Write the verdict** to the issue file as an appended QA Verification section.

---

## Phase 5: Completion (Pass Only)

**QA owns this phase EXCLUSIVELY.** Dev cannot move issues to completed.

1. Update issue status to COMPLETE
2. Move issue file from `active/` to `completed/`
3. Send completion notification to Dev's inbox
4. If cross-team impact, notify the other team

---

## Phase 6: Iterate

For Blocked or Need More Info verdicts:

1. Send findings to Dev's inbox with:
   - Which gates failed and why
   - Specific unblock criteria
   - Expected behavior vs actual
2. Wait for Dev to re-fix and re-submit
3. When Dev responds, return to Phase 0

**While waiting:** Pick the next QA-ready item and begin Phase 1.

**Exit condition:** All issues in `active/` have been moved to `completed/`,
no unprocessed messages remain in inbox.

---

## Ownership Boundaries

| Action | Owner |
|--------|-------|
| Run verification gates | QA |
| Perform manual review | QA |
| Emit verdicts | QA |
| Move issue active/ → completed/ | **QA only** |
| Set Status: COMPLETE | **QA only** |
| Write implementation code | **Dev only** |
| Create issues | Dev (QA can create QA-specific blocker issues) |
