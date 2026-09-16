# Braintrust (LEAN variant for eval)

Consult peer AI CLIs in parallel for second opinions. **No Gemini CLI.**

## Members
| Slot | CLI | Default |
|------|-----|---------|
| Anthropic | Claude | `braintrust:peer` agent (Task tool) inside Claude Code; else `claude -p --model 'claude-opus-4-8[1m]' --settings '{"disableAllHooks":true}' --output-format json` |
| Google | **agy only** | newest `gemini-*-flash-high` from probe (`gemini-3.8-flash-high`); `agy --print` + `--output-format json` + `--dangerously-skip-permissions` (PTY wrapper if bare hangs) |
| OpenAI | Codex | **gpt-6-astra** (GPT-6 Astra; fallback gpt-5.6-sol); isolated clean profile; CLI 0.154.0 |
| xAI | Grok | `grok-4.6`; isolated `GROK_HOME` |
| Multi | OpenCode | User default model from probe (expected `zai-coding-plan/glm-5.3`); `--variant max` when id contains `glm-5.3`; `--pure` |

Skip any CLI the probe marks unavailable. Host never peers with itself.

## Probe once
```bash
# find scripts/bt_probe.sh via CLAUDE_PLUGIN_ROOT or plugin cwd; else skip
bash scripts/bt_probe.sh
source /tmp/bt_models.env 2>/dev/null || true
```
Cache: `/tmp/bt_models.env`

## Launch (copy)

**Claude Code host → Claude peer:** Task tool `subagent_type: "braintrust:peer"` (pins `claude-opus-4-8[1m]`, read-only, no CLAUDE.md; never nested `claude -p`).

**Identity isolation (every peer):** Codex `CODEX_HOME` + `--ignore-user-config --ignore-rules`; Grok `GROK_HOME` + `--no-subagents`; OpenCode `--pure`; Claude `braintrust:peer` or `--settings '{"disableAllHooks":true}'`. Ambient agent-bus hooks (hcom) in the real homes hijack headless answers otherwise.

**agy:**
```bash
timeout 120 agy --print "$QUERY" --dangerously-skip-permissions --output-format json \
  ${bt_agy_model:+--model "$bt_agy_model"}
# if empty/timeout: python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions
# NEVER fall back to gemini CLI
```

**Codex (GPT-6 Astra primary; identity isolated; workspace optional):**
```bash
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" \
  timeout 150 codex exec --ephemeral --ignore-user-config --ignore-rules -s read-only --json --skip-git-repo-check \
  -m "${bt_codex_model:-gpt-6-astra}" \
  -C "${TMPDIR:-/tmp}" "$QUERY" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
jq -rs '(map(select(.type=="error" or .type=="turn.failed")) | last) as $e
  | if $e then "CODEX_FAILED: "+($e.error.message // $e.message) else (map(select(.item.type? == "agent_message")) | last | .item.text) end' /tmp/codex.json
```
Primary model id: **`gpt-6-astra`**. Verified on Codex CLI 0.154.0. Always pass `-m` with `--ignore-user-config`. A usage-limit error is a plan cap: skip the slot. For repo walk: same isolation + Astra pin, set `-C` to the repo. Always close stdin.

**Grok:**
```bash
GROK_HOME="${bt_grok_home:-/tmp/bt-grok-home}" GROK_DISABLE_AUTOUPDATER=1 \
  timeout 120 grok -p "$QUERY" -m "${bt_grok_model:-grok-4.6}" --output-format json --disable-web-search --no-subagents 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```

**OpenCode:**
```bash
OC_ARGS=(run --format json --auto --pure)
[ -n "${bt_opencode_model:-}" ] && OC_ARGS+=(-m "$bt_opencode_model")
[ -n "${bt_opencode_variant:-}" ] && OC_ARGS+=(--variant "$bt_opencode_variant")
timeout 120 opencode "${OC_ARGS[@]}" "$QUERY" 2>/tmp/bt_opencode.err \
  | jq -rs 'map(select(.type=="text") | .part.text // .text // empty) | map(select(length>0)) | last'
```
Only pass `-m` when probe set `bt_opencode_model` (from user's OpenCode config or last non-free session). Never hardcode a vendor model id.

## Capability knobs (do not collapse)
1. **Identity isolation** — whose memories/AGENTS/MCP/hooks load (default: clean via `CODEX_HOME`, `GROK_HOME`, `--pure`, `braintrust:peer`).
2. **Workspace access** — which files/cwd the peer may use (default: task-shaped package).

### Modes (pick one primary per peer)
- **A text-only** — Goal Card + pasted evidence; tools off
- **B inline** — full prompt package; identity still isolated
- **C repo walker** — cwd/repo read; identity still isolated
- **D file verifier** — explicit paths; re-derive claims
- **E vision** — one peer gets media; others get transcription
- **F red-team** — same text as A/B; attack assumptions
- **G MCP-assisted** — rare; named local tools + text fallback

Default layout: one file/repo capable verifier + one isolated text adjudicator + optional red-team on the same text package.

**MCP:** peers do not inherit host MCP by default.

## Grounding
Before launch: session_anchor, Goal Card, curated context, capability block, Skeptical Colleague protocol (restate → assumptions → evidence → fidelity → honesty → GROUNDED/NOT GROUNDED).

## Rules
- Never auto-apply peer findings
- Capture stderr to `/tmp/bt_<cli>.err`
- One retry then skip; never block the consult on one failure
- Present findings and stop for user decision
