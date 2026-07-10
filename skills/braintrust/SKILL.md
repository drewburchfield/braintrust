---
name: braintrust
description: Orchestrate other AI CLIs (Antigravity/agy, Codex, Grok, OpenCode, Claude Code) for second opinions, research, codebase analysis, design review, security audits, and parallel research. No Gemini CLI.
---

# Braintrust

Consult peer AI CLIs in parallel for second opinions. **No Gemini CLI.**

> **Background long CLI calls** when the host allows so one slow peer never blocks the rest.

**Deep docs (on demand):** `references/cli-contracts.md` · `references/capability-packaging.md` · `references/failure-modes.md` · `references/self-improvement.md` · durable evals under `evals/`

## Members

| Slot | CLI | Default |
|------|-----|---------|
| Anthropic | Claude | Task tool inside Claude Code; else `claude -p --model sonnet --output-format json` |
| Google | **agy only** | `agy --print "$Q" --dangerously-skip-permissions` (PTY wrapper if bare hangs) |
| OpenAI | Codex | **`gpt-5.6-sol`** (GPT-5.6 Sol); isolated clean profile; Codex CLI ≥ 0.144.0 |
| xAI | Grok | `grok-4.5` |
| Multi | OpenCode | User default model from probe |

Skip any CLI the probe marks unavailable. Host never peers with itself. Full consult is up to five independent voices.

### Host matrix

| You are in | Claude peer | Other peers |
|------------|-------------|-------------|
| Claude Code | Task tool (never nested `claude -p`) | bash: agy, codex, grok, opencode |
| Codex / Grok / OpenCode / agy | `claude -p ... --output-format json` | shell for the rest |

## Probe once per session

```bash
BT_PROBE=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/bt_probe.sh" ]; then
  BT_PROBE="$CLAUDE_PLUGIN_ROOT/scripts/bt_probe.sh"
elif [ -f scripts/bt_probe.sh ]; then
  BT_PROBE="scripts/bt_probe.sh"
elif [ -f ./plugins/braintrust/scripts/bt_probe.sh ]; then
  BT_PROBE="./plugins/braintrust/scripts/bt_probe.sh"
fi
if [ -n "$BT_PROBE" ]; then
  bash "$BT_PROBE"
else
  echo "BT_PROBE_SKIPPED: could not find scripts/bt_probe.sh (set CLAUDE_PLUGIN_ROOT or cd to the plugin root)."
fi
source /tmp/bt_models.env 2>/dev/null || true
```

Cache: `/tmp/bt_models.env` (stale after ~4h: re-run probe).

**SessionStart hook vs probe:** hook only checks binaries on **PATH**. Probe checks **auth/liveness** and writes model knobs (`bt_*_available`, `bt_*_model`, `bt_codex_home`).

## Grounding first

1. **session_anchor** for the whole thread  
2. **Goal Card** at `.braintrust/goal-cards/<slug>.md` (see `goal-card-template.md`)  
3. **Curated context** (not the whole chat dump)  
4. **Capability block** per peer (mode, paths, tools allowed/forbidden)  
5. **Skeptical Colleague protocol** in every peer prompt (see `grounding-protocol.md`)

## Launch contracts

**Portable timeout:** snippets use `timeout N`. On macOS without it: `brew install coreutils` (`gtimeout`), or  
`rt(){ command -v timeout >/dev/null && timeout "$@" || { shift; "$@"; }; }`  
The probe already detects `timeout`/`gtimeout`.

### Claude

**Claude Code host:** Task tool, `subagent_type: "general-purpose"`, background.

**Other hosts:**

```bash
claude -p "$QUERY" --model "${bt_claude_model:-sonnet}" --output-format json 2>/tmp/bt_claude.err \
  | jq -r '.result // empty'
```

### agy (Google, only path)

```bash
timeout 120 agy --print "$QUERY" --dangerously-skip-permissions 2>/tmp/bt_agy.err
# if empty/timeout:
# python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions
# NEVER fall back to gemini CLI; skip Google slot and note the gap
```

### Codex (GPT-5.6 Sol primary; identity isolated; workspace optional)

Primary model: **`gpt-5.6-sol`** (OpenAI GPT-5.6 Sol). Requires **Codex CLI ≥ 0.144.0** (`npm i -g @openai/codex@latest`). Because consults use `--ignore-user-config`, always pass **`-m`** explicitly; the user's `~/.codex/config.toml` model pin is ignored.

```bash
source /tmp/bt_models.env 2>/dev/null
# Prefer probe pin; default Sol. Empty bt_codex_model = product default (Sol unavailable at probe).
CODEX_MODEL_ARGS=()
if [ -n "${bt_codex_model+x}" ] && [ -z "${bt_codex_model}" ]; then
  : # explicit empty: do not pass -m
elif [ -n "${bt_codex_model:-}" ]; then
  CODEX_MODEL_ARGS=(-m "$bt_codex_model")
else
  CODEX_MODEL_ARGS=(-m "gpt-5.6-sol")
fi
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" \
  timeout 150 codex exec --ephemeral --ignore-user-config -s read-only --json --skip-git-repo-check \
  "${CODEX_MODEL_ARGS[@]}" \
  -C "${TMPDIR:-/tmp}" "$QUERY" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' /tmp/codex.json
```

If stderr/JSON says Sol needs a newer Codex, upgrade (`npm i -g @openai/codex@latest`) and re-run the probe. Prefer fixing Sol over relying on product default.

For repo walk: same isolation + Sol pin, set `-C` to the repo. Always close stdin.  
**`-C` alone is not isolation.** Off-topic answers usually mean missing clean `CODEX_HOME` and/or `--ignore-user-config` (memories/MCP/user config still loaded).

### Grok

```bash
source /tmp/bt_models.env 2>/dev/null || bt_grok_model=grok-4.5
timeout 120 grok -p "$QUERY" -m "${bt_grok_model:-grok-4.5}" \
  --output-format json --disable-web-search 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```

Check stdout JSON for `.type=="error"` **before** treating empty text as a hang. Billing/spending-limit failures often look like auth on stderr; the **JSON body is truth**. `grok login` will not fix a billing cap.

### OpenCode

```bash
source /tmp/bt_models.env 2>/dev/null
OC_ARGS=(run --format json --auto --pure)
[ -n "${bt_opencode_model:-}" ] && OC_ARGS+=(-m "$bt_opencode_model")
timeout 120 opencode "${OC_ARGS[@]}" "$QUERY" 2>/tmp/bt_opencode.err \
  | jq -rs 'map(select(.type=="text") | .part.text // .text // empty) | map(select(length>0)) | last'
```

Only pass `-m` when probe set `bt_opencode_model`. Probe model order: (1) `"model"` in OpenCode config, (2) last non-free session, (3) omit `-m`. Never hardcode a vendor model id. Headless without config can fall to a weak free model.

## Capability knobs (do not collapse)

1. **Identity isolation** — whose memories/AGENTS/MCP load (default: clean, especially Codex via `CODEX_HOME`).  
2. **Workspace access** — which files/cwd the peer may use (default: task-shaped package).

### Modes (pick one primary per peer)

| Mode | Meaning |
|------|---------|
| **A text-only** | Goal Card + pasted evidence; tools off |
| **B inline** | Full prompt package; identity still isolated |
| **C repo walker** | cwd/repo read; identity still isolated |
| **D file verifier** | Explicit paths; re-derive claims |
| **E vision** | One peer gets media; others get transcription |
| **F red-team** | Same text as A/B; attack assumptions |
| **G MCP-assisted** | Rare; live state only if host did not pre-fetch. **Named/allowlisted** tools; prefer local/no-auth; no host MCP inheritance by default. On failure: answer from CURATED CONTEXT and mark **`LIVE_STATE_UNKNOWN`**. |

Default layout: one file/repo capable verifier + one isolated text adjudicator + optional red-team on the **same** text package.

## Parallel batch

Launch all available peers in one parallel batch. Present findings as they arrive. After the last response (or timeout): synthesize, note coverage gaps, save a session under `.braintrust/sessions/`.

**Never auto-apply** peer findings. Present and stop for the user.

## Rules

- Capture stderr to `/tmp/bt_<cli>.err` (not `/dev/null` by default) so timeouts and billing-looking noise stay diagnosable  
- One retry then skip; never block the whole consult on one failure  
- Prefer compact packages (Goal Card + curated evidence). Huge inlines time out some peers  
- Re-verify contracts after harness upgrades: `bash evals/run_eval.sh matrix all agy,codex,grok,opencode`
