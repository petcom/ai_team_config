# Codex Workflow Translation

This directory is a Codex-native translation of the workflow currently defined in `./.claude-workflow/`.

## Why this shape

Codex skills work best as:

- One folder per skill
- A required `SKILL.md` file in each folder
- Optional extra references/scripts only when needed

This keeps each skill triggerable by metadata (`name`, `description`) and lightweight in context.

## Skill map (Claude -> Codex)

- `.claude-workflow/skills/comms.md` -> `.codex-workflow/skills/comms/SKILL.md`
- `.claude-workflow/skills/adr.md` -> `.codex-workflow/skills/adr/SKILL.md`
- `.claude-workflow/skills/memory.md` -> `.codex-workflow/skills/memory/SKILL.md`
- `.claude-workflow/skills/context.skill.md` -> `.codex-workflow/skills/context/SKILL.md`
- `.claude-workflow/skills/reflect.skill.md` -> `.codex-workflow/skills/reflect/SKILL.md`
- `.claude-workflow/skills/refine.skill.md` -> `.codex-workflow/skills/refine/SKILL.md`

## Team-aware installation

Unified setup entrypoint (recommended):

```bash
# run Claude setup + Codex install in one command
./agent-coord-setup.sh --team backend

# or let installer auto-detect team from dev_communication definitions
./agent-coord-setup.sh
```

Use the installer and select a team profile:

```bash
# list available teams
./.codex-workflow/install.sh --list-teams

# install for backend team (default target: ~/.codex/skills/codex-workflow)
./.codex-workflow/install.sh --team backend

# detect team from current repository and print it
./.codex-workflow/install.sh --detect-team --workspace-root .

# install using auto-detected team
./.codex-workflow/install.sh --auto-team --workspace-root .

# install for data warehousing to custom target
./.codex-workflow/install.sh --team data-warehousing --target /tmp/codex-skills/dw-pack
```

Installer behavior:

- Installs only the skills enabled for the selected team.
- Writes team metadata and protocol into the installed pack.
- Writes active team config to:
  - installed pack: `config/active-team.json`
  - local workflow: `.codex-workflow/config/active-team.json` (unless `--no-local-config`)
- Verifies and creates team vault stores under:
  - `./ai_team_config/memory_store/` (shared memory vault)
  - `./ai_team_config/<team>/adr_store/`
  - `./ai_team_config/<team>/memory_store/`
  - `./ai_team_config/<team>/context_store/`
  - `./ai_team_config/<team>/skill_store/<skill>/memory_store/`
- Ensures `TEAM_CONFIG_CONTRACT.md` exists at project root.
- If `dev_communication/shared/registry.yaml` and team definitions exist, installer overlays static `profiles.json` with repository-specific values:
  - team name/alias/issue prefix
  - inbox/issues default paths
  - cross-team inbox mapping
  - sub-team metadata and role guidance links

Team definitions are maintained in:

- `.codex-workflow/teams/catalog.yaml` (role catalog translation)
- `.codex-workflow/teams/protocol.yaml` (cross-team protocol translation)
- `.codex-workflow/teams/profiles.json` (Codex installer profiles and defaults)
- `dev_communication/shared/registry.yaml` + `dev_communication/*/definition.yaml` (repository-specific overlays)

## Usage style in Codex

Instead of relying on slash-commands, these skills should be invoked based on user intent, e.g.:

- "check inbox and pending issues" -> `comms`
- "create an ADR suggestion" -> `adr`
- "add a memory note" -> `memory`
- "load context before implementing" -> `context`
- "reflect on this implementation" -> `reflect`
- "review and promote patterns" -> `refine`

## QA Polling Runner

Frontend-QA and Backend-QA can run the shared cycle script from repository root:

```bash
ai_team_config/scripts/qa_poll_cycle.sh --once
ai_team_config/scripts/qa_poll_cycle.sh --once --manual-ok --approve
ai_team_config/scripts/qa_poll_cycle.sh --watch --interval 240
```

Issue QA state field:

- `QA: PENDING` -> ready for QA start or dev re-fix recheck
- `QA: IN_PROGRESS` -> QA verification running
- `QA: BLOCKED` -> QA findings remain; dev action required
- `QA: PASS` -> QA accepted (required before `Status: COMPLETE`)

## Team profile usage inside skills

Skills should resolve team defaults from:

1. `.codex-workflow/config/active-team.json` in the project (preferred)
2. installed pack `config/active-team.json`

This keeps behavior aligned with the installed team (issue prefix, local inbox/issue paths, architecture root, memory root).

## Unified team storage

Project-wide team storage contract:

- `TEAM_CONFIG_CONTRACT.md`

Obsidian-compatible team vault root:

- `./ai_team_config/`
