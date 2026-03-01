---
name: context
description: Load relevant ADRs, patterns, and memory before implementation
argument-hint: "[quick|work-type|topic]"
---

# Context Loading Skill

Pre-implementation context loading. Combines ADR lookup, pattern loading, and memory recall.

## Usage

```
/context                    # Auto-detect work type from conversation
/context quick              # Quick orientation (memory + recent activity only)
/context new-endpoint       # Explicit work type
/context certificates       # Search by topic
```

## Quick Mode (`/context quick`)

Fast orientation for session start or context recovery:

1. Read `memory/memory-log.md` for recent activity
2. Read `memory/context/project-overview.md`
3. If topic mentioned, search `memory/` for keywords
4. Output brief summary:
   ```
   ## Context Loaded
   **Recent Activity:** [from memory-log]
   **Relevant:** [matching entities/patterns]
   ```

## Full Mode (default)

1. **Detect Work Type** from conversation keywords:
   | Work Type | Keywords |
   |-----------|----------|
   | new-endpoint | route, endpoint, api, controller |
   | new-model | model, schema, collection, mongoose |
   | bug-fix | fix, bug, issue, broken, error |
   | auth-change | auth, permission, access, role |
   | testing | test, spec, vitest, coverage |
   | ui-component | component, widget, page, layout |

2. **Load ADRs** (max 3) from `dev_communication/shared/architecture/decisions/` — decision section only, skip rationale unless requested

3. **Load Patterns** (max 4) from `memory/patterns/` matching work type

4. **Load Memory** — search `memory/entities/` and `memory/context/` for topic keywords

5. **Load Backend Context Packs (backend only)** — if `team.json` indicates backend team, load relevant notes from `memory/context/backend/` (for example restart checklist or backend issue snapshots)

6. **Load Role Guidance** — read the role guidance file for the active sub-team from `dev_communication/shared/guidance/`

7. **Output:**
   ```
   ## Context for: {work-type}

   ### ADRs
   - **{ID}**: {one-line decision}

   ### Patterns
   - **{name}**: {summary}

   ### Memory
   - **{entity/context}**: {relevant notes}

   ### Role Guidance
   - **{key points from role guidance}**

   ### Checklist
   - [ ] {applicable checklist items}
   ```

## Token Budget

Target: <2000 tokens per invocation
- Index scan: ~200 tokens
- ADR summaries: ~150 each (450 max)
- Pattern loads: ~300 each (1200 max)
