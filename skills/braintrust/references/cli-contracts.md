# CLI Contracts (dogfooded 2026-08-22)

Source of truth for invocation shapes. Re-verify with `scripts/bt_probe.sh` and the self-improvement cycle when harnesses update.

## Roster (no Gemini CLI)

| Slot | Binary | Default model | Headless contract |
|------|--------|---------------|-------------------|
| Google AI | `agy` | **`gemini-3.7-flash-high`** when listed | `--print` + `--output-format json` + `--dangerously-skip-permissions` + `--model`; PTY if needed; parse `.status` / `.response` |
| OpenAI | `codex` | **`gpt-5.6-sol`** (GPT-5.6 Sol; CLI ≥ 0.144.0) | `exec --ephemeral --ignore-user-config -s read-only --json --skip-git-repo-check -m gpt-5.6-sol` + isolated `CODEX_HOME` + `< /dev/null`; skip `error` / `turn.failed` |
| xAI | `grok` | `grok-4.6` (from `grok models` Default model) | `--no-auto-update -p` + `-m` + `--output-format json` → `jq` `.text` (check `.type=="error"` first). Large packages: `--prompt-file` |
| Multi-provider | `opencode` | **User default** (config `model`, else last non-free session) | `run --format json --auto --pure` (+ `-m` when probe set a model; `--variant` when `bt_opencode_variant` set) → last `type=="text"` event; check `type=="error"` |
| Anthropic | `claude` | `opus` | Host Claude Code: **Task tool** (prefer opus). Other hosts: `claude -p --model opus --output-format json` → `.result`. No `--bare` for consults |

**Do not call `gemini`.** Free-tier/OAuth sunset and constant thrash with agy. Google voice is **agy only**.

## Versions verified (local, 2026-08-22)

| CLI | Version | Notes |
|-----|---------|-------|
| claude | 2.1.239 | Nested `claude -p` blocked inside Claude Code. Consult alias **`opus`** (Anthropic API → Opus 5). Liveness probe uses haiku. `--bare` will become the `-p` default later; still skip it for OAuth consults |
| agy | 1.1.18 | `--output-format json`; `--model` accepts slugs. Pin **`gemini-3.7-flash-high`**. Dropped-stream empty success is fixed (non-zero now). PTY kept as fallback |
| codex | **0.149.0** (Sol needs ≥ 0.144.0) | `-m gpt-5.6-sol`; `--ignore-user-config`; `codex review` is top-level. JSONL events include `turn.failed` / `error` |
| grok | 1.0.5 | Default model **`grok-4.6`**. `--no-auto-update`, `--prompt-file`. `grok-composer-2.5-fast` is gone; cheaper remaining id is `grok-4.5` |
| opencode | 1.18.19 | `run --format json --auto --pure`; `--variant` for reasoning effort. Model = user config / last TUI (not hardcoded) |

## agy

```bash
source /tmp/bt_models.env 2>/dev/null
AGY_ARGS=(--print "$QUERY" --dangerously-skip-permissions --output-format json)
[ -n "${bt_agy_model:-}" ] && AGY_ARGS+=(--model "$bt_agy_model")
if [ "${bt_agy_needs_pty:-false}" = "true" ]; then
  python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions ${bt_agy_model:+--model "$bt_agy_model"}
else
  timeout 120 agy "${AGY_ARGS[@]}"
fi 2>/tmp/bt_agy.err | jq -r 'if .status=="SUCCESS" then .response else "AGY_FAILED: "+(.error // .status // "empty") end'
```

- Probe writes `bt_agy_model=gemini-3.7-flash-high` when `agy models` lists that slug. Empty means account-tier.
- `--model` accepts slugs (`gemini-3.7-flash-high`) and display names. Prefer slugs.
- No `@path` includes. Inline file content. Display names from `agy models` may include third-party model brands; that is **not** an instruction to run the Gemini CLI.
- `--print-timeout` is unreliable as a hard bound; use external `timeout` or the PTY wrapper.
- macOS: warm keychain before first call if OAuth re-prompts: `security find-generic-password -s "Antigravity Safe Storage" >/dev/null 2>&1 || true`
- Optional: `--effort high|medium|low` (Flash High already bakes high into the slug). `--json-schema` for structured answers. `--disable-slash-commands` for evals.

## Codex

Primary model: **`gpt-5.6-sol`** (GPT-5.6 Sol). Min CLI **0.144.0+**. Always pass `-m` with `--ignore-user-config` (user config model pin is ignored).

```bash
source /tmp/bt_models.env 2>/dev/null
CODEX_MODEL_ARGS=(-m "${bt_codex_model:-gpt-5.6-sol}")
[ -n "${bt_codex_model+x}" ] && [ -z "${bt_codex_model}" ] && CODEX_MODEL_ARGS=()
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" \
  codex exec --ephemeral --ignore-user-config -s read-only --json --skip-git-repo-check \
  "${CODEX_MODEL_ARGS[@]}" \
  -C "${TMPDIR:-/tmp}" "$QUERY" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
jq -rs '
  (map(select(.type=="error" or .type=="turn.failed")) | last) as $err
  | if $err then "CODEX_FAILED: "+(($err.error.message // $err.error // $err.type) | tostring)
    else map(select(.item.type? == "agent_message")) | last | .item.text // empty
    end
' /tmp/codex.json
```

- **Identity isolation is mandatory for unbiased review.** Isolated `CODEX_HOME` (auth only) + `--ignore-user-config`. This is separate from workspace access.
- **Model:** default `gpt-5.6-sol`. Probe writes `bt_codex_model`. Empty means product default (Sol unavailable; upgrade CLI).
- **Workspace:** `-C /tmp` + inline evidence (Mode B default), or cwd/repo when Mode C (keep isolated home either way).
- Always close stdin with `< /dev/null`. Stderr may still print `Reading additional input from stdin...`; that line alone is **not** a hang if JSONL completed.
- Treat `type==error` and `type==turn.failed` as failure before reading `agent_message`.
- Parse fallback: `--output-last-message /tmp/bt_codex_last.txt` writes the final text and still prints it on stdout (without `--json`).
- Extra isolation: `--ignore-rules` skips user/project execpolicy `.rules`.
- Structured Mode A: `--output-schema FILE`.
- `--full-auto` is deprecated; braintrust already uses `-s read-only`.
- Code review shortcut: `codex review --uncommitted` (top-level) or `codex exec review --uncommitted`. Untracked files need staging or inline context.
- XML prompt blocks (`<task>`, `<grounding_rules>`, `<structured_output_contract>`) still help GPT-class models.
- Capability modes and MCP policy: `capability-packaging.md`.

## Grok

```bash
source /tmp/bt_models.env 2>/dev/null || bt_grok_model=grok-4.6
grok --no-auto-update -p "$QUERY" -m "$bt_grok_model" --output-format json --disable-web-search 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```

Large packages:

```bash
printf '%s' "$QUERY" > /tmp/bt_grok_prompt.txt
grok --no-auto-update --prompt-file /tmp/bt_grok_prompt.txt -m "$bt_grok_model" \
  --output-format json --disable-web-search 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```

- Headless flag is `-p` / `--single`. Default model: **`grok-4.6`**. Probe parses `Default model:` from `grok models`. Do not prefer `grok-4.5` just because it is still listed.
- Success JSON has `.text` (and spend fields). Failures are `{"type":"error","message":"..."}` with non-zero exit.
- `AuthorizationRequired` on stderr is often a **billing** cap; read stdout JSON `.message` (`out of credits` / `spending-limit`). `grok login` will not fix billing.
- `--no-auto-update` on scripted runs.
- Optional `--reasoning-effort` / `--effort` (`low` … `xhigh` / `max`). Optional `--cwd` scratch dir to avoid writing `cache/projects.json` into the repo.
- **Default tools off for consults.** Use `--disable-web-search` on opinion consults. Ambient MCP has produced empty runs (tool thrash, spawn errors). Paste evidence; Mode G only with allowlist + fallback.

## OpenCode

```bash
source /tmp/bt_models.env 2>/dev/null
OC_ARGS=(run --format json --auto --pure)
[ -n "${bt_opencode_model:-}" ] && OC_ARGS+=(-m "$bt_opencode_model")
[ -n "${bt_opencode_variant:-}" ] && OC_ARGS+=(--variant "$bt_opencode_variant")
opencode "${OC_ARGS[@]}" "$QUERY" 2>/tmp/bt_opencode.err \
  | jq -rs '
      (map(select(.type=="error")) | last) as $err
      | if $err then "OPENCODE_FAILED: "+(($err.error.message // $err.error // "") | tostring)
        else map(select(.type=="text") | .part.text // .text // empty) | map(select(length>0)) | last // empty
        end
    '
```

- `--pure` skips external plugins (faster, fewer MCP cold boots). **Default for braintrust.**
- `--auto` auto-approves permissions needed for tool use; braintrust prompts should still be read-only by design.
- Attach evidence with `-f` / `--file`; set `--dir` for Mode C repo walk.
- Drop `--pure` only for Mode G when a named local MCP is required and healthy.
- **Model:** use the user's OpenCode default. Probe resolves: (1) `"model"` in `opencode.json`, (2) last non-free session model (TUI stand-in), (3) omit `-m`. Do not hardcode any vendor model id. To make headless match TUI forever, set `"model": "provider/model"` in `~/.config/opencode/opencode.json`.
- **Variant:** probe sets `bt_opencode_variant=max` when the resolved id contains `glm-5.3` (GLM-5.3 thinking; max is the coding default).
- JSON is an event stream (`text`, `tool_use`, `step_start`, `step_finish`, `error`; `reasoning` only with `--thinking`). Answer is the last non-empty `type=="text"` part. Treat `type=="error"` as failure.

## Claude

**Inside Claude Code:** Task tool, `subagent_type: general-purpose`, background. Prefer **opus** when the host lets you set the subagent model. Never `claude -p` (nested session blocked).

**From other hosts:**

```bash
claude -p "$QUERY" --model "${bt_claude_model:-opus}" --output-format json 2>/tmp/bt_claude.err | jq -r '.result'
```

- Consult default: **`opus`** (latest Opus for the provider; Anthropic API → Opus 5). Liveness probe uses haiku. Fable (`fable` / `best`) is opt-in for long-horizon work, not the default.
- Avoid `--bare` for consults. Bare skips keychain/OAuth and often reports "Not logged in". Docs recommend `--bare` for CI and say it will become the `-p` default in a future release; keep OAuth consults off bare until auth is injected via `ANTHROPIC_API_KEY` or `--settings`.
- Piped stdin is capped at 10MB. Larger packages: write a file and name the path in the prompt.
- Optional: `--effort high|xhigh|max`. `--json-schema` puts structured output on `.structured_output`.
- Fallback model for cheap/fast Goal Cards: `haiku`.

## Host matrix (who calls whom)

| You are in | Call peers via | Claude peer |
|------------|----------------|-------------|
| Claude Code | Bash / background shell | Task tool |
| Codex | shell | `claude -p --model opus` |
| Grok | shell | `claude -p --model opus` |
| OpenCode | shell (`opencode` host sits out of its own slot) | `claude -p --model opus` |
| agy | shell | `claude -p --model opus` |

Never launch the host as a peer of itself. Full multi-vendor consult is up to **five** independent voices when every peer is available: Claude, agy, Codex, Grok, OpenCode.
