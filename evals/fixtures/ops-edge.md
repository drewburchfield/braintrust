# Fixture: ops-edge (harder operational contracts)

## Goal
From the skill text only, answer operational edge cases. If the skill text does not say, answer **UNKNOWN** (do not invent).

## Questions

1. Codex still answered an unrelated prior topic. What two isolation mistakes are most likely, and what is the fix?
2. Grok returns empty / auth-looking errors. What do you check first on stdout JSON, and why might `grok login` not help?
3. OpenCode without `-m` picked a weak free model. How does the probe choose a model, in order?
4. agy `--print` returns empty when piped. What fallback exists, and is Gemini CLI allowed?
5. You are in Codex host (not Claude Code). How do you get a Claude peer?
6. Name one case for Mode G (MCP-assisted) and the required safety rules (allowlist + fallback).
7. Where is stderr supposed to go for CLI consults, and why not `/dev/null` by default?
8. What does the SessionStart hook check vs what the probe checks?
9. Portable timeout: what if `timeout` is missing on macOS?
10. End with GROUNDED if only from skill text, else NOT GROUNDED listing guesses.

## Scoring rubric (host / heuristic)

| ID | Correct if | Pts |
|----|------------|-----|
| Q1 | CODEX_HOME / memories / MCP / ignore-user-config / not just -C | 1 |
| Q2 | .type==error / spending-limit / billing before login | 1 |
| Q3 | config model → last non-free session → omit -m | 1 |
| Q4 | PTY wrapper; no gemini | 1 |
| Q5 | claude -p (Task tool is Claude Code only) | 1 |
| Q6 | named tools + text fallback + local/no-auth | 1 |
| Q7 | /tmp/bt_*.err file | 1 |
| Q8 | hook=PATH presence; probe=auth/liveness | 1 |
| Q9 | gtimeout / coreutils / skip timeout | 1 |
| Q10 | GROUNDED only if no invention | 1 |
