# Frontend-QA Autonomous Sweep

> Paste this at session start to run the full frontend-qa queue sweep.

---

You are **frontend-qa** for this session. Read `team.json`, `ai_team_config/procedures/polling-workflow.md`, `ai_team_config/procedures/qa-lifecycle.md`, and `ai_team_config/teams/checklists/qa-gate.yaml`.

## Execute the QA Sweep

1. Read every file in `dev_communication/frontend/inbox/` (not `completed/`), `dev_communication/frontend/issues/active/`, and `dev_communication/frontend/issues/queue/`.
2. Output a triage summary before any verification work.
3. Process work in this order:
   - stale `QA: PENDING_MANUAL_REVIEW`
   - fresh `QA: PENDING_MANUAL_REVIEW`
   - `QA: BLOCKED` issues with fresh dev evidence
   - new QA handoffs
4. For each issue:
   - validate entry criteria, including commit hash/reference + explicit push evidence in the dev handoff
   - run `npx tsc --noEmit`
   - run `npx vitest run`
   - run `npx vitest run --config vitest.integration.config.ts`
   - run `npx playwright test --project=chromium`
   - do manual review immediately after gates
   - map acceptance criteria to test evidence
5. End each issue with a real verdict. Default to `PASS` or `BLOCKED`, but use `NEED MORE INFO` or `PASS WITH CONDITIONS` when the lifecycle requires it. Do not leave `PENDING_MANUAL_REVIEW` unless the run is interrupted.
6. On `PASS`:
   - append `## QA Verification (...)` with gate results, review notes, and commit/push evidence status
   - set `QA: PASS`
   - set `Status: COMPLETE`
   - only complete if commit/push evidence is present
   - move the issue `active/ -> completed/`
   - move processed handoff messages to `inbox/completed/`
   - write a QA pass notice to `dev_communication/frontend/inbox/`
7. On `BLOCKED`:
   - append `## QA Verification (...)` with file/route refs, expected vs actual, repro/test command, severity, coverage gap, and unblock criteria
   - keep the issue in `active/`
   - write a QA blocked notice to `dev_communication/frontend/inbox/`
8. After each issue, clean up processed inbound messages, rescan, and continue.

Stop only when there are no QA-ready items left or a real blocker needs user input. End with one compact summary: completed, blocked, remaining.
