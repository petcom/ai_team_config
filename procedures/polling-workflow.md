# Polling Workflow

**Triggers:** "start polling", "poll", "begin polling", "check for work"

This document routes the polling command to the correct lifecycle based on your
active role. It is NOT a passive file-watch — it is the full end-to-end
development or QA workflow executed in a continuous loop.

---

## Step 1: Determine Your Role

Confirm sub-role is established (prompted at session start). Read `team.json` for team paths.
Read `ai_team_config/roles/{sub-role}.yaml` for:
- `role_id` — which lifecycle to follow
- `team_id` — which communication directories to check (also available in `team.json`)
- `function` — `dev` or `qa`

## Step 2: Load Your Lifecycle

Based on `function`:

| Function | Procedure | Checklist (machine-readable) |
|----------|-----------|------------------------------|
| `dev` | `procedures/dev-lifecycle.md` | `teams/checklists/dev-issue-lifecycle-backend.yaml` (backend) or `dev-issue-lifecycle.yaml` (frontend) |
| `qa` | `procedures/qa-lifecycle.md` | `teams/checklists/qa-gate.yaml` |

## Step 3: Execute the Lifecycle Loop

**Dev roles:** Execute the full dev lifecycle — poll comms, assess incoming work,
decompose plans into issues, define contracts, implement, verify, document, hand
off to QA, then loop back to poll for more work.

**QA roles:** Execute the full QA lifecycle — poll for QA-ready items, validate
entry criteria, run automated verification, perform manual review, emit verdict,
complete or iterate, then loop back to poll.

## Step 4: Loop Until Exit

Continue the outer loop until ALL of:
- No unprocessed messages remain in your inbox
- No issues remain in queue/ or active/ (all moved to completed/ by QA)
- No new work has arrived since last poll

### Autonomous Polling Rules

- **Do NOT pause to ask the user** before continuing to the next issue, commit, or poll cycle. Execute continuously.
- **QA findings**: When QA returns findings (BLOCKED, FAIL, Need More Info), fix the issues immediately and re-handoff without asking the user.
- **Idle timeout**: If no new work arrives and no QA responses appear for 30 contiguous minutes of polling, stop the loop and report final status to the user.
- **Commits**: Commit completed work in batches as phases finish. Do not ask permission to commit — just commit and continue.
- **Handoff messages**: Always create QA handoff messages in the team inbox immediately after marking an issue DEV_COMPLETE.

---

## What Polling Is NOT

- NOT passive file watching that only reports new files
- NOT running the QA test suite (that is QA's job, not Dev's)
- NOT a single check — it is a continuous loop with real work between polls
- NOT limited to single issues — plans, crosswalk requests, and multi-phase
  implementations all flow through the same lifecycle
