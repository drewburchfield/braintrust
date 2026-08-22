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
| Codex off-topic / memory contamination | Documented | Isolated `CODEX_HOME` + `--ignore-user-config` + scratch `-C` |
| Codex stdin hang | Common in harnesses | Always `< /dev/null` |
| Codex timeout on binary-heavy tasks | Occasional | Pre-extract text artifacts; raise timeout only after context shrink |
| Probe thrash (slow cold start marks CLI down) | Historical | Parallel probe, one warm retry, timeout = down without thrash |

## Per-CLI table

### agy

| Symptom | Cause | Fix |
|---------|-------|-----|
| Empty / hang under pipe | Older TTY flush bug (#76) or quota | PTY wrapper; one retry; then skip Google slot |
| OAuth re-prompt macOS | keyringAuth 1s timeout (#51) | Keychain warm-up before call |
| Empty after success previously | Quota (#56) | Stop calling agy this session; note gap |
| Exit 0 with empty stdout | Dropped agent stream (fixed in 1.1.18) | Treat empty as failure; prefer `--output-format json` and check `.status` |

### Codex

| Symptom | Cause | Fix |
|---------|-------|-----|
| Off-topic review | Memories / global AGENTS.md / MCP | Isolated `CODEX_HOME` + `--ignore-user-config` |
| Hang startup `rc=124` | MCP boot on every exec | Isolated home with no MCP |
| `Reading additional input from stdin...` | stdin open | `< /dev/null` (line on stderr alone is OK if JSONL finished) |
| Usage limit | ChatGPT tier | Wait or `CODEX_API_KEY` |

### Grok

| Symptom | Cause | Fix |
|---------|-------|-----|
| `AuthorizationRequired` + 403 spending-limit | Billing cap | Credits / subscription / API key; **not** re-login |
| Empty `.text` | Error object on stdout | Check `.type=="error"` first |
| Opens TUI | Missing `-p` | Always `-p` for headless |
| Model 404 on `grok-build` | Model renamed | Use `grok-4.6` (probe `Default model:`) |
| Probe stuck on `grok-4.5` | Probe grepped for 4.5 while 4.6 is default | Parse `Default model:` from `grok models` |
| `grok-composer-2.5-fast` 404 | Fast id removed | Use `grok-4.5` if you want the cheaper remaining id |

### OpenCode

| Symptom | Cause | Fix |
|---------|-------|-----|
| Slow / MCP noise | Default plugins + MCP | `--pure` for braintrust |
| Permission wait | Tools need approval | `--auto` for headless consults |
| Wrong/weak free model on headless | `run` without config `model` often picks openrouter `:free` | Set `"model"` in `~/.config/opencode/opencode.json`; probe uses last non-free session as fallback |
| Empty text events | Auth / provider down | `opencode auth list`; retry once |

### Claude

| Symptom | Cause | Fix |
|---------|-------|-----|
| Nested session error | `claude -p` inside Claude Code | Task tool only |
| Not logged in with `--bare` | Bare skips keychain | Drop `--bare` for consults (even when docs recommend it for CI) |
| Consult landed on Sonnet | 1.10 defaulted `sonnet` | Use `opus`; Task inherits parent unless you set model |

## Diagnostics (only when a consult fails)

```bash
source /tmp/bt_models.env 2>/dev/null
# Re-run probe if env missing or older than ~4h
bash "${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/bt_probe.sh"

# agy
timeout 60 agy --print "say ok" --dangerously-skip-permissions --output-format json \
  ${bt_agy_model:+--model "$bt_agy_model"} 2>/tmp/bt_agy.err \
  | jq -r 'if .status=="SUCCESS" then .response else .error // .status end'

# codex (GPT-5.6 Sol primary; CLI >= 0.144.0)
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" \
  codex exec --ephemeral --ignore-user-config -s read-only --json --skip-git-repo-check \
  -m "${bt_codex_model:-gpt-5.6-sol}" \
  -C "${TMPDIR:-/tmp}" "say ok" < /dev/null 2>/tmp/bt_codex.err | head -5

# grok
grok --no-auto-update -p "say ok" -m "${bt_grok_model:-grok-4.6}" --output-format json 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then .message else .text end'

# opencode
OC_ARGS=(run --format json --auto --pure)
[ -n "${bt_opencode_model:-}" ] && OC_ARGS+=(-m "$bt_opencode_model")
[ -n "${bt_opencode_variant:-}" ] && OC_ARGS+=(--variant "$bt_opencode_variant")
opencode "${OC_ARGS[@]}" "say ok" 2>/tmp/bt_opencode.err \
  | jq -rs 'map(select(.type=="text") | .part.text // .text // empty) | map(select(length>0)) | last'
```

**Always** capture stderr to `/tmp/bt_<cli>.err`, not `/dev/null`, until the call succeeds.
