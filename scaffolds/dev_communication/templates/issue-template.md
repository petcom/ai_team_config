# {TEAM}-ISS-{NNN}: {Title}

**Priority:** Critical | High | Medium | Low
**Status:** QUEUE
**QA:** PENDING
**Created:** YYYY-MM-DD
**Requested By:** {TeamName}-Dev | {TeamName}-QA | {team or user}
**Assigned To:** {TeamName}-Dev | {TeamName}-QA | Unassigned | {agent name}

## Description

[What needs to be done]

## Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Notes

[Additional context]

## Dev Handoff to QA

- [ ] Development Complete
- [ ] Awaiting QA
- [ ] Typecheck passed
- [ ] Unit tests passed
- [ ] Integration tests passed
- [ ] UAT tests passed

## QA Verification Evidence

- QA Verdict: Pass | Pass with Conditions | Blocked | Need More Info
- Coverage Assessment: (map acceptance criteria to tests; list missing tests or "none")
- Manual Review: efficiency | accuracy | non-duplication | security | ADR conformance
- Unblock Criteria (required if blocked):

## Completion

**Completed:** (date)
**Notes:** (what was done)

**Folder-status mapping (mandatory):**
- `issues/queue/` -> `Status: QUEUE`
- `issues/active/` -> `Status: ACTIVE`
- `issues/completed/` -> `Status: COMPLETE`

**QA state mapping:**
- `QA: PENDING` -> waiting for QA start or dev re-fix handoff
- `QA: IN_PROGRESS` -> QA currently verifying
- `QA: BLOCKED` -> QA findings remain; dev action required
- `QA: PASS` -> QA accepted; issue should be completed/moved
