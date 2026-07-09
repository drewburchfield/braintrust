# Braintrust durable evals

Fixed fixtures + skill variants so every skill change can be compared apples-to-apples.

## Why

Hosts inject skill text into context. More text is not free. This harness measures:

1. **Context cost** of each skill variant (approx tokens)
2. **Contract accuracy** on a stable public quiz (no private data)
3. **Cross-peer consistency** (same fixture, many CLIs)

## Quick start

```bash
cd /path/to/braintrust   # this plugin root
bash evals/run_eval.sh
# or
bash evals/run_eval.sh contract-quiz skill-lean agy,codex,grok,opencode
bash evals/run_eval.sh contract-quiz skill-full agy,codex,grok,opencode
```

Output: `evals/runs/<timestamp>-contract-quiz/` with packages, per-peer results, and `summary.tsv`.

`evals/runs/` is gitignored. Fixtures, variants, and the runner are tracked.

## Variants

| ID | What is injected | ~tokens (chars/4) |
|----|------------------|-------------------|
| `skill-lean` | `evals/variants/skill-lean.md` only | ~0.9–1.4k package |
| `skill-hybrid` | lean + ops appendix (billing, timeout, Mode G, hook vs probe) | ~1.2–1.7k package |
| `skill-current` | shipping `skills/braintrust/SKILL.md` only | ~3.3–3.8k package |
| `skill-full` | SKILL + grounding + goal-card + capability-packaging + cli-contracts | ~9–11k package |

```bash
# lean vs current
bash evals/run_eval.sh contract-quiz ab agy,codex,grok,opencode
# lean vs hybrid vs current
bash evals/run_eval.sh ops-edge abc agy,codex,grok,opencode
# full matrix: both fixtures x all variants x peers
bash evals/run_eval.sh matrix all agy,codex,grok,opencode
```


## Fixture: `contract-quiz`

Ten short questions about roster, Codex isolation, OpenCode model policy, Grok/agy, Claude Code nesting, capability knobs, probe cache path. Rubric in the fixture file. Auto-score is a **heuristic** (grep-based 0–10); treat it as a smoke signal and spot-check `result.txt` when scores diverge.

## Interpreting results

- **Lean wins** if scores ≈ full at far lower tokens → cut always-on skill surface; keep depth in references loaded on demand.
- **Full wins** if lean misses isolation/MCP/mode questions → lean is too thin; restore those lines to SKILL.md.
- **Peer disagreement** on the same package → clarify wording (ambiguous skill text), not peer “taste.”
- **Empty / timeout** → packaging size problem (shrink fixture or raise timeout); record as a coverage gap.

## Adding evals

1. Add `evals/fixtures/<name>.md` with goal, questions, rubric.
2. Optionally add a variant under `evals/variants/`.
3. Run `bash evals/run_eval.sh <name> all`.
4. Commit fixtures + any skill edits; do not commit `evals/runs/`.

## Rules

- Public fixtures only (no client or third-party personal data).
- Do not treat auto-score as ground truth for shipping without a human skim.
- Re-run after every material skill/probe change before tagging.
