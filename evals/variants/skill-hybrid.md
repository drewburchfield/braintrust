# Braintrust (HYBRID variant for eval)

Consult peer AI CLIs in parallel for second opinions. **No Gemini CLI.**

## Members
| Slot | CLI | Default |
|------|-----|---------|
| Anthropic | Claude | Task tool inside Claude Code; else `claude -p --model sonnet --output-format json` |
| Google | **agy only** | `agy --print "$Q" --dangerously-skip-permissions` (PTY wrapper if bare hangs) |
| OpenAI | Codex | **gpt-5.6-sol** (GPT-5.6 Sol); isolated clean profile; CLI ≥ 0.144.0 |
| xAI | Grok | `grok-4.5` |
| Multi | OpenCode | User default model from probe |

Skip any CLI the probe marks unavailable. Host never peers with itself.

## Probe once
```bash
# Prefer: $CLAUDE_PLUGIN_ROOT/scripts/bt_probe.sh, else scripts/bt_probe.sh in plugin cwd
# If not found: skip probe and use documented defaults (do not use dirname "$0")
bash scripts/bt_probe.sh
source /tmp/bt_models.env 2>/dev/null || true
```
Cache: `/tmp/bt_models.env`

**SessionStart hook vs probe:** hook only checks binaries on **PATH**. Probe checks **auth/liveness** and writes model knobs (`bt_*_available`, `bt_*_model`, `bt_codex_home`).

## Launch (copy)

**Portable timeout:** snippets use `timeout N`. On macOS without it: `brew install coreutils` (use `gtimeout`), or  
`rt(){ command -v timeout >/dev/null && timeout "$@" || { shift; "$@"; }; }`  
Probe already detects `timeout`/`gtimeout`.

**Claude Code host → Claude peer:** Task tool `general-purpose` (never nested `claude -p`).

**agy:**
```bash
timeout 120 agy --print "$QUERY" --dangerously-skip-permissions
# if empty/timeout: python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions
# NEVER fall back to gemini CLI; skip Google slot and note the gap
```

**Codex (GPT-5.6 Sol primary; identity isolated; workspace optional):**
```bash
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" \
  timeout 150 codex exec --ephemeral --ignore-user-config -s read-only --json --skip-git-repo-check \
  -m "${bt_codex_model:-gpt-5.6-sol}" \
  -C "${TMPDIR:-/tmp}" "$QUERY" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' /tmp/codex.json
```
Primary model: **`gpt-5.6-sol`**. Codex CLI ≥ 0.144.0. Always pass `-m` with `--ignore-user-config`. For repo walk: same isolation + Sol pin, set `-C` to the repo. Always close stdin.  
**`-C` alone is not isolation.** Off-topic answers usually mean missing clean `CODEX_HOME` and/or `--ignore-user-config` (memories/MCP/user config still loaded).

**Grok:**
```bash
timeout 120 grok -p "$QUERY" -m "${bt_grok_model:-grok-4.5}" --output-format json --disable-web-search 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```
Check stdout JSON for `.type=="error"` **before** treating empty text as a hang. Billing/spending-limit failures often look like auth on stderr; the **JSON body is truth**. `grok login` will not fix a billing cap.

**OpenCode:**
```bash
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
- **A text-only** — Goal Card + pasted evidence; tools off
- **B inline** — full prompt package; identity still isolated
- **C repo walker** — cwd/repo read; identity still isolated
- **D file verifier** — explicit paths; re-derive claims
- **E vision** — one peer gets media; others get transcription
- **F red-team** — same text as A/B; attack assumptions
- **G MCP-assisted** — rare; only when live state is required and host did not pre-fetch. **Named/allowlisted** tools only; prefer local/no-auth healthy servers; peers do **not** inherit host MCP by default. If MCP fails: answer from CURATED CONTEXT and mark **`LIVE_STATE_UNKNOWN`**.

Default layout: one file/repo capable verifier + one isolated text adjudicator + optional red-team on the same text package.

## Grounding
Before launch: session_anchor, Goal Card, curated context, capability block, Skeptical Colleague protocol (restate → assumptions → evidence → fidelity → honesty → GROUNDED/NOT GROUNDED).

## Rules
- Never auto-apply peer findings
- Capture stderr to `/tmp/bt_<cli>.err` (not `/dev/null` by default) so timeouts, billing-looking noise, and empty failures stay diagnosable
- One retry then skip; never block the consult on one failure
- Present findings and stop for user decision
