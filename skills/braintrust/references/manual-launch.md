# Manual launch (fallback)

Use these only when `peerpanel` cannot run (no Python 3.9+, or a host that cannot execute files from the plugin). `bin/peerpanel` wraps every line below and adds status names, one retry, read-only modes and the run record. Keep both in step when a CLI changes its flags.


**Portable timeout:** snippets use `timeout N`. On macOS without it: `brew install coreutils` (`gtimeout`), or  
`rt(){ command -v timeout >/dev/null && timeout "$@" || { shift; "$@"; }; }`  
The probe already detects `timeout`/`gtimeout`.

### Claude

**Claude Code host:** Task tool, `subagent_type: "braintrust:peer"`, background. The agent pins `claude-opus-5-5[1m]`, skips CLAUDE.md, and is read-only. If the plugin agent is unavailable, use `general-purpose` and say so in the coverage notes.

**Other hosts:**

```bash
claude -p "$QUERY" --model "${bt_claude_model:-claude-opus-5-5[1m]}" --output-format json \
  --no-session-persistence --safe-mode --settings '{"disableAllHooks":true}' 2>/tmp/bt_claude.err \
  | jq -r '.result // empty'
```

Do not use `--bare` for consults (skips keychain/OAuth). Stdin is capped at 10MB; large packages go in a file path in the prompt.

### agy (Google, only path)

```bash
source /tmp/bt_models.env 2>/dev/null
AGY_ARGS=(--print "$QUERY" --dangerously-skip-permissions --output-format json --mode plan)  # plan mode keeps agy read-only
[ -n "${bt_agy_model:-}" ] && AGY_ARGS+=(--model "$bt_agy_model")
timeout 120 agy "${AGY_ARGS[@]}" 2>/tmp/bt_agy.err \
  | jq -r 'if .status=="SUCCESS" then .response else "AGY_FAILED: "+(.error // .status // "empty") end'
# if empty/timeout:
# python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions --mode plan ${bt_agy_model:+--model "$bt_agy_model"}
# NEVER fall back to gemini CLI; skip Google slot and note the gap
```

Default pin: the strongest `gemini-*-high` slug from `agy models`, newest generation first, then family rank Neon > Carbon > Argon > Hydrogen (**`gemini-4-neon-high`**, Gemini 4 Neon, as of 2026-11-21). `bt_agy_fast_model` (`gemini-3.8-flash-high`) is the fallback and the quick option; Neon High takes ~1.5x longer. Empty `bt_agy_model` means account-tier.

### Codex (GPT-6.2 Astra primary; identity isolated; workspace optional)

Primary model: **`gpt-6.2-astra`** (OpenAI GPT-6.2 Astra, frontier). Fallback `gpt-6.2-sol` (latest workhorse), then product default. Verified on Codex CLI 0.170.0 (`npm i -g @openai/codex@latest`). Because consults use `--ignore-user-config`, always pass **`-m`** explicitly.

```bash
source /tmp/bt_models.env 2>/dev/null
CODEX_MODEL_ARGS=()
if [ -n "${bt_codex_model+x}" ] && [ -z "${bt_codex_model}" ]; then
  : # explicit empty: do not pass -m
elif [ -n "${bt_codex_model:-}" ]; then
  CODEX_MODEL_ARGS=(-m "$bt_codex_model")
else
  CODEX_MODEL_ARGS=(-m "gpt-6.2-astra")
fi
CODEX_HOME="${bt_codex_home:-${TMPDIR:-/tmp}/bt-codex-home}" \
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

### xAI slot

One xAI voice per consult. Use the CLI named in `bt_xai_via` (`cursor` or `grok`); skip the slot when it is empty.

#### Cursor CLI (`bt_xai_via=cursor`)

```bash
source /tmp/bt_models.env 2>/dev/null
( cd "${TMPDIR:-/tmp}" && env -u CMUX_SURFACE_ID CMUX_CURSOR_HOOKS_DISABLED=1 \
  timeout 150 cursor-agent -p "$QUERY" --model "${bt_cursor_model:-grok-4.7-high}" \
  --output-format json --mode ask --trust --workspace "${TMPDIR:-/tmp}" < /dev/null ) 2>/tmp/bt_cursor.err \
  | jq -r 'if .is_error then "CURSOR_FAILED: "+(.result // .error // "error" | tostring) else .result end'
```

`--mode ask` is read-only Q&A and is what keeps ambient hooks and rules from turning into actions. Never add `--force`, `--yolo`, or `--approve-mcps`. For repo walk (Mode C), point `--workspace` at the repo. Always close stdin.

#### Grok CLI (`bt_xai_via=grok`)

Fallback only. Contract last verified on grok 1.0.30; re-dogfood before relying on it.

```bash
source /tmp/bt_models.env 2>/dev/null || bt_grok_model=grok-4.7
GROK_HOME="${bt_grok_home:-${TMPDIR:-/tmp}/bt-grok-home}" GROK_DISABLE_AUTOUPDATER=1 \
  timeout 120 grok -p "$QUERY" -m "${bt_grok_model:-grok-4.7}" \
  --output-format json --disable-web-search --no-subagents 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```

Check stdout JSON for `.type=="error"` **before** treating empty text as a hang. Billing/spending-limit failures often look like auth on stderr; the **JSON body is truth**. `grok login` will not fix a billing cap.

If the answer mentions an agent bus, a `[hcom:…]` marker, or "joining", the isolated home was not used. Re-run with `GROK_HOME` set.

For packages that may exceed argv limits, write `$QUERY` to a temp file and use `--prompt-file` instead of `-p`.

### OpenCode

```bash
source /tmp/bt_models.env 2>/dev/null
OC_ARGS=(run --standalone --format json --auto)
oc_m="${bt_opencode_model:-}"; [[ -n "$oc_m" && -n "${bt_opencode_variant:-}" ]] && oc_m="$oc_m#$bt_opencode_variant"
[[ -n "$oc_m" ]] && OC_ARGS+=(-m "$oc_m")
timeout 120 env XDG_CONFIG_HOME="${bt_opencode_config:-${TMPDIR:-/tmp}/bt-opencode-config}" \
  OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_CLAUDE_CODE=1 OPENCODE_DISABLE_AUTOUPDATE=1 \
  opencode "${OC_ARGS[@]}" "$QUERY" 2>/tmp/bt_opencode.err \
  | jq -rs '
      (map(select(.type=="error")) | last) as $err
      | if $err then "OPENCODE_FAILED: "+(($err.error.message // $err.error // "") | tostring)
        else map(select(.type=="text") | .part.text // .text // empty) | map(select(length>0)) | last // empty
        end
    '
```

Only pass `-m` when probe set `bt_opencode_model`. Probe model order: (1) `"model"` in OpenCode config, (2) last non-free session, (3) omit `-m`. Never hardcode a vendor model id in the launch line. Expected id on this setup: `zai-coding-plan/glm-5.3`; the probe warns when the resolved id lacks `glm-5.3`. Probe sets `bt_opencode_variant=max` when the resolved id contains `glm-5.3`. The empty config root is what keeps config plugins (hcom, herdr, cmux feeds), MCP servers and user skills out of the consult.

