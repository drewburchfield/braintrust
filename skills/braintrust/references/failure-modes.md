# Failure Modes (observed production + dogfood)

## Coverage reality from sessions

| Pattern | Frequency | Fix in skill |
|---------|-----------|--------------|
| Gemini empty / setup / sunset | High historically | **Removed Gemini.** Google = agy only |
| Grok auth / billing / MCP thrash | High | Parse JSON error object; don't recommend `grok login` for spending-limit; **default tools off**; paste evidence (Mode A/B/F) |
| Peer inherits host MCP / same tools for all | Common mistake | Specialize modes; capability block; see `capability-packaging.md` |
| Codex clean but empty evidence | Occasional | Isolation without a package → vague philosophy; pre-extract + inline |
| Vision claims to text-only peers | Occasional | One Mode E peer; others get transcription + flag vision-dependent claims |
| agy empty / hang (pre-1.1.0) | High historically | Probe bare first; PTY fallback; no gemini fallback |
| Codex off-topic / memory contamination | Documented | Isolated `CODEX_HOME` + `--ignore-user-config` + `--ignore-rules` + scratch `-C` |
| **Peer joins an agent bus (hcom) instead of answering** | Observed 2026-09-16 (grok) | Identity isolation on every CLI: `GROK_HOME`, `CODEX_HOME`, `--pure`, `braintrust:peer` / `disableAllHooks`. See "Ambient hooks" below |
| Codex stdin hang | Common in harnesses | Always `< /dev/null` |
| Codex timeout on binary-heavy tasks | Occasional | Pre-extract text artifacts; raise timeout only after context shrink |
| Probe thrash (slow cold start marks CLI down) | Historical | Parallel probe, one warm retry, timeout = down without thrash |

## Ambient hooks (hcom, cmux, herdr)

The user's real homes carry SessionStart/PreToolUse hooks and plugins that talk to an agent bus. Under those hooks a headless grok run returned `Joining the agent bus … [hcom:kemo] Here. What do you need?` with `stopReason: end_turn` and no answer. Symptoms: answer mentions "agent bus", `[hcom:…]`, "binding with --name", "identity is", or a 4-letter agent name. Fix per CLI:

| CLI | Where hcom lives | Isolation that was verified clean |
|-----|------------------|-----------------------------------|
| grok | `~/.grok/hooks/hcom.json` (SessionStart) | `GROK_HOME=$bt_grok_home` (auth + minimal config, compat scanning off) + `--no-subagents` |
| codex | `~/.codex/hooks.json` + `hcom_*` keys in `config.toml` | `CODEX_HOME=$bt_codex_home` (no `hooks.json`) + `--ignore-user-config --ignore-rules` |
| opencode | `~/.config/opencode/opencode.json` → `plugins/hcom.ts` | `--pure` |
| claude | `~/.claude/settings.json` hooks | `braintrust:peer` agent inside Claude Code; `--settings '{"disableAllHooks":true}'` for `claude -p` |
| agy | none today | plain `--print` |

The probe builds both isolated homes on every run. Never point a consult at `~/.grok` or `~/.codex`.

## Per-CLI table

### agy

| Symptom | Cause | Fix |
|---------|-------|-----|
| Empty / hang under pipe | Older TTY flush bug (#76) or quota | PTY wrapper; one retry; then skip Google slot |
| OAuth re-prompt macOS | keyringAuth 1s timeout (#51) | Keychain warm-up before call |
| Empty after success previously | Quota (#56) | Stop calling agy this session; note gap |
| Exit 0 with empty stdout | Dropped agent stream (fixed in 1.1.18) | Treat empty as failure; prefer `--output-format json` and check `.status` |
| Pinned slug 404 | Older Flash generation retired | Probe picks the newest `gemini-*-flash-high` from `agy models`; re-run probe |

### Codex

| Symptom | Cause | Fix |
|---------|-------|-----|
| Off-topic review | Memories / global AGENTS.md / MCP | Isolated `CODEX_HOME` + `--ignore-user-config` |
| Hang startup `rc=124` | MCP boot on every exec | Isolated home with no MCP |
| `Reading additional input from stdin...` | stdin open | `< /dev/null` (line on stderr alone is OK if JSONL finished) |
| `{"type":"error","message":"You've hit your usage limit…"}` | ChatGPT plan cap (reset time in message) | Skip slot; probe stores `bt_codex_error`; wait or `CODEX_API_KEY`. Do not retry other models |
| `CODEX_FAILED: error` with no text | jq read `.error.message` only | `error` events put text on `.message`; use `$err.error.message // $err.message` |
| Hook ran inside consult | `$CODEX_HOME/hooks.json` present | Isolated home must contain only `auth.json` + one-line `config.toml` |

### Grok

| Symptom | Cause | Fix |
|---------|-------|-----|
| `AuthorizationRequired` + 403 spending-limit | Billing cap | Credits / subscription / API key; **not** re-login |
| Empty `.text` | Error object on stdout | Check `.type=="error"` first |
| Opens TUI | Missing `-p` | Always `-p` for headless |
| Model 404 on `grok-build` | Model renamed | Use `grok-4.6` (probe `Default model:`) |
| Probe stuck on `grok-4.5` | Probe grepped for 4.5 while 4.6 is default | Parse `Default model:` from `grok models` |
| `grok-composer-2.5-fast` 404 | Fast id removed | Use `grok-4.5` if you want the cheaper remaining id |
| Answer is agent-bus chatter | `~/.grok/hooks/hcom.json` fired | `GROK_HOME=$bt_grok_home` (probe builds it) |
| `--no-auto-update` missing from help | 1.0.30 hid the flag | `GROK_DISABLE_AUTOUPDATER=1` + `[cli] auto_update=false` in isolated config |

### OpenCode

| Symptom | Cause | Fix |
|---------|-------|-----|
| Slow / MCP noise | Default plugins + MCP | `--pure` for braintrust |
| Permission wait | Tools need approval | `--auto` for headless consults |
| Wrong/weak free model on headless | `run` without config `model` often picks openrouter `:free` | Set `"model"` in `~/.config/opencode/opencode.json`; probe uses last non-free session as fallback |
| Empty text events | Auth / provider down | `opencode auth list`; retry once |
| Plugin chatter in answer | Ran without `--pure` | Always `--pure`; probe log says "--pure drops config plugins" |
| Resolved model is not glm-5.3 | Config `model` changed | Set `"model": "zai-coding-plan/glm-5.3"` in `~/.config/opencode/opencode.json`; probe warns |

### Claude

| Symptom | Cause | Fix |
|---------|-------|-----|
| Nested session error | `claude -p` inside Claude Code | Task tool only |
| Not logged in with `--bare` | Bare skips keychain | Drop `--bare` for consults (even when docs recommend it for CI) |
| Consult landed on Sonnet / parent model | Task inherits parent unless an agent pins model | Use `subagent_type: "braintrust:peer"` (pins `claude-opus-4-8[1m]`) |
| Hooks fired inside `claude -p` consult | User `settings.json` hooks | `--settings '{"disableAllHooks":true}'` (keeps OAuth) |

## Diagnostics (only when a consult fails)

```bash
source /tmp/bt_models.env 2>/dev/null
# Re-run probe if env missing or older than ~4h
bash "${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/bt_probe.sh"

# agy
timeout 60 agy --print "say ok" --dangerously-skip-permissions --output-format json \
  ${bt_agy_model:+--model "$bt_agy_model"} 2>/tmp/bt_agy.err \
  | jq -r 'if .status=="SUCCESS" then .response else .error // .status end'

# codex (GPT-6 Astra primary; CLI 0.154.0 verified)
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" \
  codex exec --ephemeral --ignore-user-config --ignore-rules -s read-only --json --skip-git-repo-check \
  -m "${bt_codex_model:-gpt-6-astra}" \
  -C "${TMPDIR:-/tmp}" "say ok" < /dev/null 2>/tmp/bt_codex.err \
  | jq -rs '(map(select(.type=="error" or .type=="turn.failed")) | last) as $e
            | if $e then ($e.error.message // $e.message) else (map(select(.item.type?=="agent_message")) | last | .item.text) end'

# grok (isolated home; no hooks)
GROK_HOME="${bt_grok_home:-/tmp/bt-grok-home}" GROK_DISABLE_AUTOUPDATER=1 \
  grok -p "say ok" -m "${bt_grok_model:-grok-4.6}" --output-format json --disable-web-search --no-subagents 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then .message else .text end'

# opencode
OC_ARGS=(run --format json --auto --pure)
[ -n "${bt_opencode_model:-}" ] && OC_ARGS+=(-m "$bt_opencode_model")
[ -n "${bt_opencode_variant:-}" ] && OC_ARGS+=(--variant "$bt_opencode_variant")
opencode "${OC_ARGS[@]}" "say ok" 2>/tmp/bt_opencode.err \
  | jq -rs 'map(select(.type=="text") | .part.text // .text // empty) | map(select(length>0)) | last'
```

**Always** capture stderr to `/tmp/bt_<cli>.err`, not `/dev/null`, until the call succeeds.
