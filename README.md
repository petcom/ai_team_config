# AI Team Config

Setup documentation and blueprint for the agent workflow system. This directory defines **how to install and configure** agent teams in a project — it is not a working data store.

## What This Is

| This directory IS | This directory IS NOT |
|-------------------|-----------------------|
| Skill definitions (canonical, shared by Claude + Codex) | A runtime vault for agent memory |
| Team structure definitions and profiles | A store for ADRs or architecture decisions |
| Sub-team role definitions for agent windows | A working directory for dev communication |
| An installer that scaffolds project working directories | An Obsidian vault with active data |
| Platform adapters for Claude Code and Codex | |

## Working Directories (created by installer)

| Directory | Purpose | Managed by |
|-----------|---------|------------|
| `./memory/` | Agent runtime memory (sessions, patterns, entities) | `/memory`, `/context`, `/reflect` skills |
| `./dev_communication/shared/architecture/` | ADRs, specs, contracts | `/adr` skill |
| `./dev_communication/{team}/` | Team comms, issues, inbox | `/comms` skill |
| `./team.json` | Team-level config (paths, allowed sub-roles) | Installer |

## Quick Start

```bash
# Interactive — prompts for team and platform
./ai_team_config/install.sh

# Non-interactive
./ai_team_config/install.sh --team frontend --platform both --devcomm create

# Tune refresh recommendation threshold (default: 5 issues)
./ai_team_config/install.sh --team frontend --platform both --refresh-threshold 8

# Force-refresh conflicting link targets (backs up old files)
./ai_team_config/install.sh --team frontend --platform both --force-refresh-links
```

The installer will:
1. Ask which **team** to install (frontend, backend, qa, etc.)
2. Ask which **platform** (Claude Code, Codex, or both)
4. Scaffold `./memory/` and seed missing baseline files if needed
5. Create `./dev_communication/` from `ai_team_config/scaffolds/dev_communication/` (or use `--devcomm` override)
6. Install skill + team-config symlinks for the selected platform
7. Write canonical `team.json` and mirror it into platform config paths
8. Run a compliance audit and recommend refresh if drift exceeds threshold

## Directory Structure

```
ai_team_config/
├── README.md                  # This file
├── install.sh                 # Main installer
│
├── skills/                    # Canonical skill definitions (ONE copy)
│   ├── comms/SKILL.md         #   Inter-team communication
│   ├── memory/SKILL.md        #   Memory vault management
│   ├── adr/SKILL.md           #   Architecture decision management
│   ├── context/SKILL.md       #   Pre-implementation context loading
│   ├── reflect/SKILL.md       #   Post-implementation reflection
│   └── refine/SKILL.md        #   Pattern refinement and promotion
│
├── teams/                     # Team structure definitions
│   ├── catalog.yaml           #   All available team types
│   ├── protocol.yaml          #   Cross-team communication rules
│   ├── checklists/            #   Shared QA and lifecycle checklists
│   └── profiles.json          #   Team profiles (consumed by installer)
│
├── roles/                     # Sub-team role definitions
│   ├── frontend-dev.yaml      #   What frontend-dev owns, gates, comms rules
│   ├── frontend-qa.yaml       #   What frontend-qa owns, verdicts, evidence rules
│   ├── backend-dev.yaml       #   What backend-dev owns
│   ├── backend-qa.yaml        #   What backend-qa owns
│   └── ...                    #   Definitions for all sub-team ids in teams/profiles.json
│
├── team-configs/              # Agent team management (for multi-agent spawning)
│   ├── agent-team-roles.json  #   Lead/implementer/tester/researcher roles
│   └── code-reviewer-config.json  # Code review gate criteria
│
├── platforms/                 # Platform-specific installation adapters
│   ├── claude/setup.sh        #   Creates .claude/commands/ symlinks
│   └── codex/setup.sh         #   Creates .codex-workflow/ config + symlinks
│
└── scaffolds/                 # Template directories created by installer
    ├── memory/                #   Template for ./memory/ vault structure
    └── dev_communication/     #   Template for ./dev_communication/ structure
```

## Skills

All six skills are defined once in `skills/<name>/SKILL.md`. Both Claude Code and Codex reference the same files via symlinks created by the platform setup scripts.

Both platforms also consume shared team definitions from `team-configs/`:
- `.claude/team-configs/*` -> `ai_team_config/team-configs/*`
- `.codex-workflow/team-configs/*` -> `ai_team_config/team-configs/*`

| Skill | Reads from | Writes to |
|-------|-----------|-----------|
| `/comms` | `dev_communication/{team}/` | `dev_communication/` (messages, issues) |
| `/memory` | `./memory/` | `./memory/` |
| `/adr` | `dev_communication/shared/architecture/` | `dev_communication/shared/architecture/` |
| `/context` | `./memory/` + `dev_communication/shared/` | — (read-only) |
| `/reflect` | `./memory/` + git diff | `./memory/`, `dev_communication/shared/architecture/suggestions/` |
| `/refine` | `./memory/patterns/` | `./memory/`, `dev_communication/shared/architecture/decisions/` |

## Roles

Each role file (`roles/<role-id>.yaml`) defines:
- What the sub-team **owns** (responsibilities)
- What it **does not own** (boundaries)
- **Verification gates** (dev roles) or **evidence standards** (QA roles)
- **Comms behavior** (From header, check scope, allowed recipients)

The team config is canonicalized to `./team.json` in the project root (team-level only, no sub-role identity). Sub-role is resolved at session start via prompt and held in memory only. Platform mirrors point to the same file:
- `.claude/team.json`
- `.codex-workflow/config/team.json`

## QA Polling Runner

Shared QA checklist:
- `ai_team_config/teams/checklists/qa-gate.yaml`

Agent-runnable QA cycle script:
- `ai_team_config/scripts/qa_poll_cycle.sh`

Issue QA state field (required):
- `QA: PENDING` -> awaiting QA start or dev re-fix recheck
- `QA: IN_PROGRESS` -> QA verification running
- `QA: BLOCKED` -> QA findings remain
- `QA: PASS` -> QA accepted; required before `Status: COMPLETE`

Examples:

```bash
# one-shot QA poll + verification
ai_team_config/scripts/qa_poll_cycle.sh --once

# mark passing issues complete (after manual review)
ai_team_config/scripts/qa_poll_cycle.sh --once --manual-ok --approve

# poll every 4 minutes
ai_team_config/scripts/qa_poll_cycle.sh --watch --interval 240
```

## Multi-Window Setup

Each agent controller window selects its sub-role at session start:

```
Window 1:  Start session → select "frontend-dev"
Window 2:  Start session → select "frontend-qa"
```

Both windows share the same `./memory/` and `./dev_communication/` directories. They coordinate through the `/comms` skill, using distinct `From` headers (`Frontend-Dev` vs `Frontend-QA`).

Since sub-role identity is held in each agent's conversation memory (not written to a file), multiple concurrent agents can operate from the same checkout without file contention. No worktrees or separate checkouts needed.

## Obsidian Vault Structure

The installer maintains `./memory/` as an Obsidian-friendly vault structure (folders, index files, templates, and prompt registry).

- Vault structure details and maintenance rules: `ai_team_config/docs/OBSIDIAN_VAULT.md`
- Canonical scaffold source: `ai_team_config/scaffolds/memory/`

## Idempotency and Safety

- Re-running the installer is idempotent: it only creates missing scaffold content and keeps existing `memory/` notes intact.
- Platform link setup is non-destructive by default: if a destination path already exists as a normal file/directory, setup warns and skips instead of deleting it.
- To intentionally replace conflicts, use `--force-refresh-links` (installer creates `*.legacy-YYYYMMDD-HHMMSS` backups first).
- A compliance audit runs at install end and reports missing required structure.
- If issue count meets/exceeds `--refresh-threshold` (default `5`), installer recommends a refresh command.
