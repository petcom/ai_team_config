# Feature Development Checklist

## Core Principle

**Verify before inventing.** Never guess API values, permission strings, or
endpoint paths. Check existing code, contracts, or ask the responsible team.

---

## Quick Reference

| Code | Rule | Verify Before Using |
|------|------|---------------------|
| P1 | Permission strings | Search codebase for existing permissions |
| P2 | Endpoint paths | Check contracts or ask API team |
| P3 | Field/type names | Check existing types and models |
| T1 | Tests per phase | Write tests at end of each dev phase/issue |
| T2 | Tests at milestone | Run full test suite at end of major milestone |
| T3 | TypeScript check | Run `npx tsc --noEmit` before marking issue complete |
| C1 | Commit protocol | Follow format from `git log -5`, include Co-Authored-By |
| E1 | Error handling | Appropriate strategy per error type |
| D1 | Stay in project | Never leave project dir; hand off via messages/issues |

---

## Index Details

### P1: Permission Strings
Search your codebase for existing permission patterns before creating new ones.

### P2-P3: API Contracts
Check `contracts/` or `dev_communication/shared/contracts/` for agreed-upon shapes.
If uncertain, create a message to the responsible team.

### T1-T3: Testing + Type Safety
- Write tests after completing each dev phase or issue (not during)
- At major milestone: run full test suite to verify nothing is broken
- Before marking any issue complete: `npx tsc --noEmit` for type safety

### C1: Commit Protocol
Format: `type(scope): description` + body + `Co-Authored-By: <agent> <noreply@anthropic.com>`
Check recent commits: `git log -5 --format="%s"` to match project style.

### E1: Error Handling
- **API errors**: Catch and surface appropriately to the user
- **Form validation**: Validate with schemas, display inline errors
- **Dev errors**: Log with context for debugging
- **Network failures**: Provide retry option where applicable

### D1: Stay in Project
Never `cd` into other repos. For cross-team work:
- API requests → `dev_communication/{team}/inbox/`
- New issues → `dev_communication/{team}/issues/queue/`
Hand off and wait for response.

---

## Architecture Decisions

*Record significant architecture decisions here as you make them, or link to
the full ADR in `dev_communication/shared/architecture/decisions/`.*

---

## Lessons Log

*Record lessons learned during development. Format:*

```
**YYYY-MM-DD | Category**
Brief description of the lesson and what to do differently.
```

---
