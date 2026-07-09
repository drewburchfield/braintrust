# Goal Card Template

**Location:** Always create at `.braintrust/goal-cards/<slug>.md` (mkdir -p .braintrust/goal-cards)

**session_anchor:** [same value for all Goal Cards belonging to the current conversation/session/thread. Use date-based slug or the tool's session ID if available. This is the default scope for "related prior goals".]

**Goal (one sentence):** [Clear, specific statement of what success looks like]

## Success Criteria
- [ ] Criterion 1 (measurable / observable)
- [ ] Criterion 2
- [ ] ...

## Out of Scope
- ...

## Key Constraints / Non-Goals
- ...

## Relevant Context Snapshot
- Stack / key files at time of card creation: ...
- Original request / ticket: ...

## Access / Capability Map (optional but recommended when non-obvious)
| Peer role | Mode (A–G) | May use | Must not |
|-----------|------------|---------|----------|
| e.g. Claude verifier | D file-capable | paths under `src/`, `evidence/*` | network write, invent facts |
| e.g. Codex adjudicator | B inline | prompt package only | MCP, host memories |
| e.g. Grok red-team | F | same package as Codex | tools thrash |
| e.g. agy | C repo walker | project root / `--add-dir` | client surnames not in files |

Modes: A text-only · B inline package · C repo walker · D file verifier · E vision · F red-team · G MCP-assisted (allowlist + fallback). See `skills/braintrust/references/capability-packaging.md`.

## Decision Log (add as work progresses)
- [Date] Decision: ... Rationale: ... (Grounded because: ...)

---
*This Goal Card must be read and explicitly referenced by any braintrust member before giving an opinion. All claims must be grounded against it + fresh evidence allowed by the capability map.*
