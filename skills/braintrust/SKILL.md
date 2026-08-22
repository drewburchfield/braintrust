---
name: braintrust
description: Orchestrate other AI CLIs (Antigravity/agy, Codex, Grok, OpenCode, Claude Code) for second opinions, research, codebase analysis, design review, security audits, and parallel research. No Gemini CLI.
version: 1.11.0
---

# Braintrust

Consult peer AI CLIs in parallel for second opinions. **No Gemini CLI.**

> **Background long CLI calls** when the host allows so one slow peer never blocks the rest.

**Deep docs (on demand):** `references/cli-contracts.md` · `references/capability-packaging.md` · `references/failure-modes.md` · `references/self-improvement.md` · durable evals under `evals/`

## Members

| Slot | CLI | Default |
|------|-----|---------|
| Anthropic | Claude | Task tool inside Claude Code; else `claude -p --model opus --output-format json` |
| Google | **agy only** | `gemini-3.7-flash-high` via `--model`; `--print` + `--output-format json` + `--dangerously-skip-permissions` (PTY if bare hangs) |
| OpenAI | Codex | **`gpt-5.6-sol`** (GPT-5.6 Sol); isolated clean profile; Codex CLI ≥ 0.144.0 |
| xAI | Grok | `grok-4.6` (probe reads `grok models` Default model) |
| Multi | OpenCode | User default model from probe; `--variant max` when that id contains `glm-5.3` |

Skip any CLI the probe marks unavailable. Host never peers with itself. Full consult is up to five independent voices.

### Host matrix

| You are in | Claude peer | Other peers |
|------------|-------------|-------------|
| Claude Code | Task tool (never nested `claude -p`); prefer model opus | bash: agy, codex, grok, opencode |
| Codex / Grok / OpenCode / agy | `claude -p --model opus --output-format json` | shell for the rest |

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

**SessionStart hook vs probe:** hook only checks binaries on **PATH**. Probe checks **auth/liveness** and writes model knobs (`bt_*_available`, `bt_*_model`, `bt_codex_home`, `bt_opencode_variant`).

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

**Claude Code host:** Task tool, `subagent_type: "general-purpose"`, background. Prefer model **opus** when the host lets you set the subagent model.

**Other hosts:**

```bash
claude -p "$QUERY" --model "${bt_claude_model:-opus}" --output-format json 2>/tmp/bt_claude.err \
  | jq -r '.result // empty'
```

Do not use `--bare` for consults (skips keychain/OAuth). Stdin is capped at 10MB; large packages go in a file path in the prompt.

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

Default pin: **`gemini-3.7-flash-high`** when the probe found it. Empty `bt_agy_model` means account-tier.

### Codex (GPT-5.6 Sol primary; identity isolated; workspace optional)

Primary model: **`gpt-5.6-sol`** (OpenAI GPT-5.6 Sol). Requires **Codex CLI ≥ 0.144.0** (`npm i -g @openai/codex@latest`). Because consults use `--ignore-user-config`, always pass **`-m`** explicitly; the user's `~/.codex/config.toml` model pin is ignored.

```bash
source /tmp/bt_models.env 2>/dev/null
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
jq -rs '
  (map(select(.type=="error" or .type=="turn.failed")) | last) as $err
  | if $err then "CODEX_FAILED: "+(($err.error.message // $err.error // $err.type) | tostring)
    else map(select(.item.type? == "agent_message")) | last | .item.text // empty
    end
' /tmp/codex.json
```

If stderr/JSON says Sol needs a newer Codex, upgrade (`npm i -g @openai/codex@latest`) and re-run the probe. Prefer fixing Sol over relying on product default.

For repo walk: same isolation + Sol pin, set `-C` to the repo. Always close stdin.  
**`-C` alone is not isolation.** Off-topic answers usually mean missing clean `CODEX_HOME` and/or `--ignore-user-config` (memories/MCP/user config still loaded).

### Grok

```bash
source /tmp/bt_models.env 2>/dev/null || bt_grok_model=grok-4.6
timeout 120 grok --no-auto-update -p "$QUERY" -m "${bt_grok_model:-grok-4.6}" \
  --output-format json --disable-web-search 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```

Check stdout JSON for `.type=="error"` **before** treating empty text as a hang. Billing/spending-limit failures often look like auth on stderr; the **JSON body is truth**. `grok login` will not fix a billing cap.

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

Only pass `-m` when probe set `bt_opencode_model`. Probe model order: (1) `"model"` in OpenCode config, (2) last non-free session, (3) omit `-m`. Never hardcode a vendor model id. Headless without config can fall to a weak free model. Probe sets `bt_opencode_variant=max` when the resolved id contains `glm-5.3`.

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
