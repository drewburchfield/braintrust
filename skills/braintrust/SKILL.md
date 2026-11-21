---
name: braintrust
description: Orchestrate other AI CLIs (Antigravity/agy, Codex, Cursor CLI or Grok for xAI, OpenCode, Claude Code) for second opinions, research, codebase analysis, design review, security audits, and parallel research. No Gemini CLI.
version: 1.17.0
---

# Braintrust

Consult peer AI CLIs in parallel for second opinions through one command, `peerpanel`. **No Gemini CLI.**

`peerpanel` lives in the plugin's `bin/`, which Claude Code puts on the Bash tool's PATH. From other hosts, call it by path (`${CLAUDE_PLUGIN_ROOT}/bin/peerpanel`) and pass `--host codex|agy|xai|opencode` so your own seat is left out. It needs Python 3.9+ and jq.

**Deep docs (on demand):** `references/cli-contracts.md` · `references/failure-modes.md` · `references/capability-packaging.md` · `references/manual-launch.md` (raw CLI lines, fallback only) · `references/self-improvement.md`

## Members

| Seat | CLI | Model |
|------|-----|-------|
| Anthropic | Claude | `braintrust:peer` agent inside Claude Code; `claude -p --safe-mode` elsewhere (Opus 5.5 1M) |
| Google | agy only | strongest `gemini-*-high` from the probe (`gemini-4-neon-high`); fast fallback `gemini-3.8-flash-high` |
| OpenAI | Codex | `gpt-6.2-astra`; fallback `gpt-6.2-sol` |
| xAI | Cursor CLI, else Grok CLI | newest `grok-X.Y-high` Cursor lists (`grok-4.7-high`) |
| Multi | OpenCode | your configured model (`zai-coding-plan/glm-5.3#max`) |

Peers run identity-isolated (clean Codex and Grok homes, empty OpenCode config, Cursor ask mode, Claude safe mode) and read-only (Codex `-s read-only`, agy `--mode plan`, Cursor `--mode ask`, OpenCode `--agent plan`). `peerpanel` sets all of it. The host never peers with itself.

## The flow

```bash
peerpanel brief new .braintrust/consults/<slug>     # scaffold the brief
# fill the files (below), then:
peerpanel brief check .braintrust/consults/<slug>   # fix every ERROR, read every WARN
peerpanel consult .braintrust/consults/<slug>       # run_in_background: true
```

`consult` probes (cached 4h), pings each peer with a check code, skips any that fail the ping, runs the rest in parallel with one retry on timeout, empty output or a dropped connection, and prints one line per seat as it lands. It writes `runs/<timestamp>/` inside the brief: `<seat>.md` answers, `prompt-<seat>.md` (exactly what each seat saw), raw stdout/stderr, `status.json` and `record.md`.

**Claude seat inside Claude Code.** `consult` writes `prompt-claude.md` and prints the line to hand it. Launch the Task tool with `subagent_type: "braintrust:peer"` in the background with that line. If the agent is missing, use `general-purpose` and say so in the record.

Ctrl-C stops the consult and kills every running seat. Other commands: `peerpanel probe [--force]`, `peerpanel ping`, `peerpanel prompt <brief> --peer codex` (preview), `peerpanel status <run>`.

## The brief (fixed shape)

The brief keeps you from handing peers only your framing. You chose what to show them, so they must be able to check you.

| File | What goes in it |
|------|-----------------|
| `request.md` | **Required.** The user's own words, pasted verbatim from the conversation. Several messages are fine. Do not paraphrase. |
| `question.md` | **Required.** What each peer must answer, the format and a word limit. Keep your conclusions out of it. |
| `sources.txt` | One absolute path per line: the files and folders the answer depends on. Peers get read access and open them themselves. |
| `claims.md` | Optional. Facts you believe. Peers see them labeled unverified and must confirm or refute each. Put every inference here, including any link you drew that the user never stated. |
| `context.md` | Optional. Material that lives in no file (a call, a meeting). Labeled as your summary. |
| `host-view.md` | Optional. Your own conclusion. Withheld unless you pass `--include-host-view`, so peers form their view first. |

Rules:
- Point at files rather than summarizing them. A summary carries your errors to every seat at once.
- When the user's numbers, dates or names come from you, list them in `claims.md`.
- Sources go to outside vendors. Keep client secrets and personal data out, and check every WARN about secret-looking files.
- `--text-only` inlines the sources instead of granting read access (60 KB cap). Use it only when a peer cannot reach the paths.
- Never invent a question the user did not ask.

## Reading results

| Status | Meaning | Action |
|--------|---------|--------|
| `ok` | answered | read `<seat>.md` |
| `host` | Claude seat for you to launch | launch `braintrust:peer` |
| `timeout` / `empty` / `connection` | retried once, still failed | note the gap |
| `cap` | plan or usage limit | note the reset time if shown |
| `auth` | signed out | tell the user which login to run |
| `cli-changed` / `model` | flags or model ids drifted | run `peerpanel probe --force`; then `references/cli-contracts.md` |
| `hijacked` / `off-task` | ambient hooks or a refusal took over | discard the answer |
| `skipped` | failed the preflight ping | the reason column says why |
| `unavailable` / `missing` | not installed or not signed in | skip the seat |

Then synthesize in `record.md`:
- Seats that saw the same brief share its framing and its errors. Weigh most the claims a seat checked against the sources (file:line).
- Name every `claims.md` item a seat refuted, and say so to the user.
- Note coverage gaps (which seats failed and why).
- **Never auto-apply** peer findings. Present them and stop for the user.

## Rules

- One `consult` per round. Do not hand-write launcher scripts; if `peerpanel` misbehaves, fix or report it, and use `references/manual-launch.md` only as a last resort.
- Run `consult` in the background so one slow seat never blocks the conversation.
- Re-verify contracts after CLI upgrades: `python3 -m unittest evals/test_peerpanel.py` (offline), then `bash evals/run_eval.sh matrix all agy,codex,cursor,grok,opencode` (live).
