---
name: braintrust
description: Orchestrate other AI CLIs (Antigravity/agy, Codex, Grok, OpenCode, Claude Code) for second opinions, research, codebase analysis, design review, security audits, and parallel research. No Gemini CLI.
version: 1.12.0
---

# Braintrust

Consult peer AI CLIs in parallel for second opinions. **No Gemini CLI.**

> **Background long CLI calls** when the host allows so one slow peer never blocks the rest.

**Deep docs (on demand):** `references/cli-contracts.md` · `references/capability-packaging.md` · `references/failure-modes.md` · `references/self-improvement.md` · durable evals under `evals/`

## Members

| Slot | CLI | Default |
|------|-----|---------|
| Anthropic | Claude | `braintrust:peer` agent (Task tool) inside Claude Code; else `claude -p --model 'claude-opus-4-8[1m]' --settings '{"disableAllHooks":true}' --output-format json` |
| Google | **agy only** | newest `gemini-*-flash-high` from probe (`gemini-3.8-flash-high` as of 2026-09); `--print` + `--output-format json` + `--dangerously-skip-permissions` (PTY if bare hangs) |
| OpenAI | Codex | **`gpt-6-astra`** (GPT-6 Astra); fallback `gpt-5.6-sol`; isolated `CODEX_HOME`; Codex CLI ≥ 0.154.0 verified |
| xAI | Grok | `grok-4.6` (probe reads `grok models` Default model); isolated `GROK_HOME` |
| Multi | OpenCode | User default model from probe (expected `zai-coding-plan/glm-5.3`); `--variant max` when that id contains `glm-5.3`; `--pure` |

Skip any CLI the probe marks unavailable. Host never peers with itself. Full consult is up to five independent voices.

### Host matrix

| You are in | Claude peer | Other peers |
|------------|-------------|-------------|
| Claude Code | Task tool with `subagent_type: "braintrust:peer"` (never nested `claude -p`) | bash: agy, codex, grok, opencode |
| Codex / Grok / OpenCode / agy | `claude -p --model 'claude-opus-4-8[1m]' --settings '{"disableAllHooks":true}' --output-format json` | shell for the rest |

## Identity isolation is mandatory

Every peer runs from a clean profile. Ambient hooks (agent buses like hcom), MCP servers, memories, and plugins in the user's real home hijack headless answers. A grok consult once "joined the agent bus" instead of answering.

| CLI | Isolation |
|-----|-----------|
| Codex | `CODEX_HOME=$bt_codex_home` (auth only) + `--ignore-user-config --ignore-rules` |
| Grok | `GROK_HOME=$bt_grok_home` (auth only; compat scanning off) + `GROK_DISABLE_AUTOUPDATER=1` + `--no-subagents` |
| OpenCode | `--pure` (drops config plugins) |
| Claude | `braintrust:peer` agent (`omitClaudeMd`, read-only); other hosts add `--settings '{"disableAllHooks":true}'` |
| agy | no hook surface today; plain `--print` |

The probe creates both isolated homes. `-C` / `--cwd` alone is **not** isolation.

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

**SessionStart hook vs probe:** hook only checks binaries on **PATH**. Probe checks **auth/liveness**, builds the isolated homes, and writes model knobs (`bt_*_available`, `bt_*_model`, `bt_codex_home`, `bt_grok_home`, `bt_codex_error`, `bt_opencode_variant`).

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

**Claude Code host:** Task tool, `subagent_type: "braintrust:peer"`, background. The agent pins `claude-opus-4-8[1m]`, skips CLAUDE.md, and is read-only. If the plugin agent is unavailable, use `general-purpose` and say so in the coverage notes.

**Other hosts:**

```bash
claude -p "$QUERY" --model "${bt_claude_model:-claude-opus-4-8[1m]}" --output-format json \
  --no-session-persistence --settings '{"disableAllHooks":true}' 2>/tmp/bt_claude.err \
  | jq -r '.result // empty'
```

Do not use `--bare` for consults (skips keychain/OAuth). Stdin is capped at 10MB; large packages go in a file path in the prompt. Model stays Opus 4.8 1M until a model above Opus 5 ships.

### agy (Google, only path)

```bash
source /tmp/bt_models.env 2>/dev/null
AGY_ARGS=(--print "$QUERY" --dangerously-skip-permissions --output-format json)
[ -n "${bt_agy_model:-}" ] && AGY_ARGS+=(--model "$bt_agy_model")
timeout 120 agy "${AGY_ARGS[@]}" 2>/tmp/bt_agy.err \
  | jq -r 'if .status=="SUCCESS" then .response else "AGY_FAILED: "+(.error // .status // "empty") end'
# if empty/timeout:
# python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions ${bt_agy_model:+--model "$bt_agy_model"}
# NEVER fall back to gemini CLI; skip Google slot and note the gap
```

Default pin: the newest `gemini-*-flash-high` slug from `agy models` (**`gemini-3.8-flash-high`** as of 2026-09-16). Empty `bt_agy_model` means account-tier.

### Codex (GPT-6 Astra primary; identity isolated; workspace optional)

Primary model: **`gpt-6-astra`** (OpenAI GPT-6 Astra). Fallback `gpt-5.6-sol`, then product default. Verified on Codex CLI 0.154.0 (`npm i -g @openai/codex@latest`). Because consults use `--ignore-user-config`, always pass **`-m`** explicitly.

```bash
source /tmp/bt_models.env 2>/dev/null
CODEX_MODEL_ARGS=()
if [ -n "${bt_codex_model+x}" ] && [ -z "${bt_codex_model}" ]; then
  : # explicit empty: do not pass -m
elif [ -n "${bt_codex_model:-}" ]; then
  CODEX_MODEL_ARGS=(-m "$bt_codex_model")
else
  CODEX_MODEL_ARGS=(-m "gpt-6-astra")
fi
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" \
  timeout 150 codex exec --ephemeral --ignore-user-config --ignore-rules -s read-only --json --skip-git-repo-check \
  "${CODEX_MODEL_ARGS[@]}" \
  -C "${TMPDIR:-/tmp}" "$QUERY" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
jq -rs '
  (map(select(.type=="error" or .type=="turn.failed")) | last) as $err
  | if $err then "CODEX_FAILED: "+(($err.error.message // $err.message // $err.error // $err.type) | tostring)
    else map(select(.item.type? == "agent_message")) | last | .item.text // empty
    end
' /tmp/codex.json
```

`CODEX_FAILED: You've hit your usage limit …` is a plan cap, not a bug. Skip the OpenAI slot, note the reset time, and continue. The probe records it in `bt_codex_error`.

For repo walk: same isolation + Astra pin, set `-C` to the repo. Always close stdin.  
**`-C` alone is not isolation.** Off-topic answers usually mean missing clean `CODEX_HOME` and/or `--ignore-user-config` (memories/MCP/hooks/user config still loaded).

### Grok

```bash
source /tmp/bt_models.env 2>/dev/null || bt_grok_model=grok-4.6
GROK_HOME="${bt_grok_home:-/tmp/bt-grok-home}" GROK_DISABLE_AUTOUPDATER=1 \
  timeout 120 grok -p "$QUERY" -m "${bt_grok_model:-grok-4.6}" \
  --output-format json --disable-web-search --no-subagents 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```

Check stdout JSON for `.type=="error"` **before** treating empty text as a hang. Billing/spending-limit failures often look like auth on stderr; the **JSON body is truth**. `grok login` will not fix a billing cap.

If the answer mentions an agent bus, a `[hcom:…]` marker, or "joining", the isolated home was not used. Re-run with `GROK_HOME` set.

For packages that may exceed argv limits, write `$QUERY` to a temp file and use `--prompt-file` instead of `-p`.

### OpenCode

```bash
source /tmp/bt_models.env 2>/dev/null
OC_ARGS=(run --format json --auto --pure)
[ -n "${bt_opencode_model:-}" ] && OC_ARGS+=(-m "$bt_opencode_model")
[ -n "${bt_opencode_variant:-}" ] && OC_ARGS+=(--variant "$bt_opencode_variant")
timeout 120 opencode "${OC_ARGS[@]}" "$QUERY" 2>/tmp/bt_opencode.err \
  | jq -rs '
      (map(select(.type=="error")) | last) as $err
      | if $err then "OPENCODE_FAILED: "+(($err.error.message // $err.error // "") | tostring)
        else map(select(.type=="text") | .part.text // .text // empty) | map(select(length>0)) | last // empty
        end
    '
```

Only pass `-m` when probe set `bt_opencode_model`. Probe model order: (1) `"model"` in OpenCode config, (2) last non-free session, (3) omit `-m`. Never hardcode a vendor model id in the launch line. Expected id on this setup: `zai-coding-plan/glm-5.3`; the probe warns when the resolved id lacks `glm-5.3`. Probe sets `bt_opencode_variant=max` when the resolved id contains `glm-5.3`. `--pure` is what keeps config plugins (hcom, cmux feeds) out of the consult.

## Capability knobs (do not collapse)

1. **Identity isolation** — whose memories/AGENTS/MCP/hooks load (default: clean, via `CODEX_HOME`, `GROK_HOME`, `--pure`, `braintrust:peer`).  
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
