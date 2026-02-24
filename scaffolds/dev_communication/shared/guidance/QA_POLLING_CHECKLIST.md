# QA Polling Checklist

Use this checklist after polling for new QA-ready work.

## Scope

- Applies to `Frontend-QA` and `Backend-QA`
- Canonical source: `ai_team_config/teams/checklists/qa-gate.yaml`
- Runner script: `ai_team_config/scripts/qa_poll_cycle.sh`

## QA State Field

- Every issue must include `QA: PENDING | IN_PROGRESS | BLOCKED | PASS`.
- Dev sets `QA: PENDING` for initial QA handoff and after re-fix.
- QA sets `QA: IN_PROGRESS` when validation starts.
- QA sets `QA: BLOCKED` when findings remain.
- QA sets `QA: PASS` before completion (`Status: COMPLETE` + move to `completed/`).

## Cycle

1. Poll inbox + active issues for `Development Complete` or `Awaiting QA`.
2. Confirm issue is in `issues/active/` with `Status: ACTIVE` and `QA: PENDING` (or `QA: BLOCKED` with new dev evidence).
3. Validate test coverage evidence and record missing tests/recommendations.
4. Run automated gates:
   - Typecheck
   - Unit tests
   - Integration tests
   - UAT tests
5. Perform manual review:
   - Efficiency
   - Accuracy
   - Non-duplication
   - Security
   - ADR conformance
6. Record verdict and evidence in the issue:
   - `Pass` / `Pass with Conditions` / `Blocked` / `Need More Info`
   - Include explicit unblock criteria when blocked
7. If pass, QA moves issue to `completed/` and sets `Status: COMPLETE`.
8. Move processed handoff message from inbox:
   - Preferred: `dev_communication/{team}/inbox/completed/`
   - Fallback: `dev_communication/archive/`

## Standard Commands

Mandatory timeout policy:

- Every automated gate command must be wrapped with `timeout 120s`.
- Timeout is a blocking failure and must be recorded in QA evidence.

One-shot cycle:

```bash
QA_CMD_TYPECHECK="timeout 120s npm run type-check" \
QA_CMD_UNIT="timeout 120s npm run test:unit" \
QA_CMD_INTEGRATION="timeout 120s npm run test:integration" \
QA_CMD_UAT="timeout 120s npm run test:uat" \
ai_team_config/scripts/qa_poll_cycle.sh --once
```

Approve passing issues (after manual review):

```bash
QA_CMD_TYPECHECK="timeout 120s npm run type-check" \
QA_CMD_UNIT="timeout 120s npm run test:unit" \
QA_CMD_INTEGRATION="timeout 120s npm run test:integration" \
QA_CMD_UAT="timeout 120s npm run test:uat" \
ai_team_config/scripts/qa_poll_cycle.sh --once --manual-ok --approve
```

4-minute polling loop:

```bash
QA_CMD_TYPECHECK="timeout 120s npm run type-check" \
QA_CMD_UNIT="timeout 120s npm run test:unit" \
QA_CMD_INTEGRATION="timeout 120s npm run test:integration" \
QA_CMD_UAT="timeout 120s npm run test:uat" \
ai_team_config/scripts/qa_poll_cycle.sh --watch --interval 240
```
