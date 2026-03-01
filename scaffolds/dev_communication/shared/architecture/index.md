# Architecture Hub

Central hub for architecture decisions, gaps, and suggestions.

## Quick Links

- [[decision-log|Decision Log]]
- [[decisions/index|All Decisions]]
- [[suggestions/index|Pending Suggestions]]
- [[gaps/index|Known Gaps]]
- [[../specs/index|Specifications]]
- [[templates/adr-template|ADR Template]]

## Skill

Use `/adr` skill for architecture management:

| Command | Purpose |
|---------|---------|
| `/adr` | Show status: ADRs, gaps, suggestions |
| `/adr check` | Full traversal and gap analysis |
| `/adr gaps` | Gap analysis only |
| `/adr suggest` | Create suggestion for review |
| `/adr poll` | Scan messages/issues for decisions |
| `/adr create` | Create ADR from suggestion |
| `/adr review` | Review/update existing ADR |

---

## Decision Tree (by domain)

*Add your ADRs here, grouped by domain.*

---

## Current Status

| Domain | Count | Status |
|--------|-------|--------|
| *(none yet)* | 0 | — |

---

## Known Gaps

| Domain | Gap | Priority |
|--------|-----|----------|
| *(none identified yet)* | — | — |

*See [[gaps/index]] for details*

---

## Feedback Loop

Architecture suggestions come from:
1. **Development work** — Patterns discovered during implementation
2. **Code review** — Decisions that should be documented
3. **Problem resolution** — Solutions that establish precedent
4. **Cross-team coordination** — Shared architectural concerns

---

## Creating New ADRs

1. Create suggestion via `/adr suggest`
2. Review in architecture review
3. If accepted, create ADR via `/adr create`
4. Update [[decision-log]] and this index

Template: [[templates/adr-template]]

---

[[../index|← Back to Dev Communication Hub]]
