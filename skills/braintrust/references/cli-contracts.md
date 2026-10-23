# CLI Contracts (dogfooded 2026-10-23)

Source of truth for invocation shapes. Re-verify with `scripts/bt_probe.sh` and the self-improvement cycle when harnesses update.

## Roster (no Gemini CLI)

| Slot | Binary | Default model | Headless contract |
|------|--------|---------------|-------------------|
| Google AI | `agy` | strongest `gemini-*-high` listed (**`gemini-4-argon-high`** as of 2026-10-16; fast fallback `gemini-3.8-flash-high`) | `--print` + `--output-format json` + `--dangerously-skip-permissions` + `--model`; PTY if needed; parse `.status` / `.response` |
| OpenAI | `codex` | **`gpt-6-astra`** (GPT-6 Astra; fallback `gpt-6.1-sol`) | `exec --ephemeral --ignore-user-config --ignore-rules -s read-only --json --skip-git-repo-check -m gpt-6-astra` + isolated `CODEX_HOME` + `< /dev/null`; fail on `error` / `turn.failed` |
| xAI (primary) | `cursor-agent` | newest `grok-X.Y-high` from `--list-models` (**`grok-4.7-high`** as of 2026-10-16) | `-p` + `--model` + `--output-format json --mode ask --trust --workspace $TMPDIR` + `env -u CMUX_SURFACE_ID CMUX_CURSOR_HOOKS_DISABLED=1` + cwd `$TMPDIR` + `< /dev/null` → `jq` `.result` (check `.is_error` first) |
| xAI (fallback) | `grok` | `grok models` Default model (fallback `grok-4.7`); unverified since 1.0.30 | isolated `GROK_HOME` + `GROK_DISABLE_AUTOUPDATER=1` + `-p` + `-m` + `--output-format json --disable-web-search --no-subagents` → `jq` `.text` (check `.type=="error"` first). Large packages: `--prompt-file` |
| Multi-provider | `opencode` | **User default** (config `model`, else last non-free session; expected `zai-coding-plan/glm-5.3`) | `run --format json --auto --pure` (+ `-m` when probe set a model; `--variant max` for glm-5.3) → last `type=="text"` event; check `type=="error"` |
| Anthropic | `claude` | `claude-opus-5-5[1m]` (Opus 5.5, 1M context) | Host Claude Code: **`braintrust:peer` agent** via Task tool. Other hosts: `claude -p --model 'claude-opus-5-5[1m]' --safe-mode --settings '{"disableAllHooks":true}' --output-format json` → `.result`. No `--bare` |

**Do not call `gemini`.** Free-tier/OAuth sunset and constant thrash with agy. Google voice is **agy only**.

## Versions verified (local, 2026-10-23)

| CLI | Version | Notes |
|-----|---------|-------|
| claude | 2.1.309 | Nested `claude -p` blocked inside Claude Code. Consult model **`claude-opus-5-5[1m]`** is still the newest Opus (`opus` resolves to it; `claude-opus-6` is unrecognized). Fable is now `claude-fable-5-1`. `--safe-mode` drops CLAUDE.md, plugins, user skills, MCP, hooks and agents but keeps keychain auth; `--restricted` also drops Bash/WebFetch. `--bare` still skipped. Also in `--help`, unused by consults: `--permission-prompts <host|none>`, `--setting-sources`, `--exclude-dynamic-system-prompt-sections`; never pass `--bg`, `--cloud`, `--desktop` |
| agy | 1.4.6 | `agy models` lists **Gemini 4 Argon** (`gemini-4-argon-{high,medium,low}`, still the newest Google model on 2026-10-23) and Gemini 3.8 Flash (High/Medium/Low), plus Claude Opus/Sonnet 5.5 and `gpt-oss-120b-medium` display entries. 3.7/3.6 Flash and 3.1 Pro are gone. `--mode` is now `accept-edits`, `auto`, `plan`; `--effort` enum adds `xhigh`/`max` (no Gemini model accepts them). New `--remote-control` flag plus `remote-control` and `mic-serve` subcommands (never use in consults). Reads hooks from `~/.gemini/config/hooks.json` (hcom + herdr, unchanged since 2026-09-23). 1.4.6 sandbox blocks `~/.docker`, `~/.kube` and `~/_netrc` by default |
| codex | **0.160.1** | Model catalog (unchanged 2026-10-23): `gpt-6.1-sol` (priority 1, "latest workhorse"), `gpt-6-astra` (priority 2, "frontier intelligence"), `gpt-6-sol`, `gpt-6-luna`, `gpt-reserve`, `gpt-5.6-sol/terra/luna`, `codex-auto-review` (internal approval reviewer). `gpt-5.5` has left the catalog. Braintrust keeps Astra first because it is the strongest reasoner. Exec flags: `--strict-config`, `--thread-source`, `--enable/--disable <FEATURE>`, `-p/--profile` (layers `$CODEX_HOME/<name>.config.toml`), `--worktree`, `--approve-for-me`, `--dangerously-bypass-hook-trust`. Consults use none of the last three. `$CODEX_HOME/hooks.json` is honored, so the isolated home must not carry one. Upstream 0.161.0 makes `gpt-6.1-sol` the product default; consults pass `-m` so Astra stays the pin |
| cursor-agent | 2026.10.22 | `--list-models` tops out at `grok-4.7-{low,medium,high,xhigh}[-fast]` (no 4.8), plus `cursor-grok-4.6-*` and `cursor-grok-4.5-high[-fast]`. Also lists `gemini-4-argon-*`, `claude-fable-5-1-*`, `kimi-k2.7-code`, `glm-5.2-*`, `muse-*`. `--mode` choices: `plan`, `ask`. New: `-w/--worktree`, `--worktree-base`, `--skip-worktree-setup`, `--plan` (= `--mode plan`), `persist`/`worker`/`team`/`bedrock` subcommands. Still: `--sandbox`, `--plugin-dir`, `--auto-review`, `--add-dir`. Parameterized ids accept bracket overrides (`'model[effort=high]'`) |
| grok | 1.0.46 | Not in active use; still logged out on 2026-10-16 (`Not signed in … grok login --device-code`), so `grok models` only shows `grok-4.6`/`grok-4.5`. All documented flags still in `--help`. Contract last dogfooded on 1.0.30 |
| opencode | 1.18.34 | `run --format json --auto --pure`; `--variant` for reasoning effort. `zai-coding-plan/glm-5.3` still listed (also `glm-5.3-flash`, `glm-5.3-highspeed`). `glm-5.3-highspeed` is not on the Coding Plan: it returns a retryable 429 and OpenCode retries for ~80s |

## Ambient contamination (why isolation is mandatory)

This machine runs an agent bus (hcom) hooked into grok (`~/.grok/hooks/hcom.json`), codex (`~/.codex/hooks.json` + config), opencode (`opencode.json` → `plugins/hcom.ts`), claude (`~/.claude/settings.json` hooks), agy (`~/.gemini/config/hooks.json`, since 2026-09-23), and cursor (`~/.cursor/hooks.json`, cmux/hcom). Without isolation a grok consult answered "Joining the agent bus … [hcom:kemo] Here. What do you need?" instead of the question. Isolation per CLI is in the roster table; the probe builds `$TMPDIR/bt-codex-home` and `$TMPDIR/bt-grok-home` with auth only (on macOS `$TMPDIR` is under `/var/folders`, not `/tmp`; always source `/tmp/bt_models.env` for the real paths).

## agy

```bash
source /tmp/bt_models.env 2>/dev/null
AGY_ARGS=(--print "$QUERY" --dangerously-skip-permissions --output-format json)
[ -n "${bt_agy_model:-}" ] && AGY_ARGS+=(--model "$bt_agy_model")
if [ "${bt_agy_needs_pty:-false}" = "true" ]; then
  # PTY wrapper prints plain text (no --output-format json), so no jq here
  python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions ${bt_agy_model:+--model "$bt_agy_model"} 2>/tmp/bt_agy.err
else
  timeout 120 agy "${AGY_ARGS[@]}" 2>/tmp/bt_agy.err \
    | jq -r 'if .status=="SUCCESS" then .response else "AGY_FAILED: "+(.error // .status // "empty") end'
fi
```

- Probe writes `bt_agy_model` as the strongest `gemini-*-high` slug in `agy models`: newest generation first, non-Flash wins a tie (`gemini-4-argon-high` on 2026-10-16). `bt_agy_fast_model` is the newest `gemini-*-flash-high` (`gemini-3.8-flash-high`); the probe falls back to it when the pin fails. Use it for quick Goal Card checks. Empty `bt_agy_model` means account-tier.
- Latency (2026-10-16, one-word answer): Argon High ~6.7s of agy time, Flash High ~2.7s.
- **Hooks.** `~/.gemini/config/hooks.json` carries hcom (PreInvocation, PreToolUse, PostToolUse, PostInvocation, Stop) and herdr hooks. agy has no flag or env var to skip them. Verified 2026-10-23 on agy 1.4.6: headless `--print` answers stayed on topic and no agent joined the hcom bus. If an answer mentions hcom, an agent bus, or a 4-letter agent name, skip the Google slot and note it.
- `--model` accepts slugs and display names. Prefer slugs. Gemini 3.1 Pro is gone from agy 1.4.0.
- No `@path` includes. Inline file content. Display names from `agy models` may include third-party brands (Claude, GPT-OSS); that is **not** an instruction to run the Gemini CLI or to route Claude through agy.
- `--print-timeout` is unreliable as a hard bound; use external `timeout` or the PTY wrapper.
- macOS: warm keychain before first call if OAuth re-prompts: `security find-generic-password -s "Antigravity Safe Storage" >/dev/null 2>&1 || true`
- `--effort`: every Gemini model in agy tops out at `high`. A suffixed slug (`gemini-4-argon-high`) fixes the effort, so omit `--effort` or pass the matching value; any other value errors (`conflicts with --effort=max`). `xhigh`/`max` exist in the enum but are invalid for Gemini. Never `--remote-control` or `--mode auto` in a consult. `--json-schema` for structured answers. `--disable-slash-commands` for evals. `--sandbox` when the peer may run commands.

## Codex

Primary model: **`gpt-6-astra`** (GPT-6 Astra, "frontier intelligence for the most demanding work"; reasoning efforts low/medium/high/xhigh/max/ultra). Fallback `gpt-6.1-sol` ("latest workhorse", catalog priority 1 since 0.160.0), then product default. Always pass `-m` with `--ignore-user-config` (user config model pin is ignored).

```bash
source /tmp/bt_models.env 2>/dev/null
CODEX_MODEL_ARGS=(-m "${bt_codex_model:-gpt-6-astra}")
[ -n "${bt_codex_model+x}" ] && [ -z "${bt_codex_model}" ] && CODEX_MODEL_ARGS=()
CODEX_HOME="${bt_codex_home:-${TMPDIR:-/tmp}/bt-codex-home}" \
  codex exec --ephemeral --ignore-user-config --ignore-rules -s read-only --json --skip-git-repo-check \
  "${CODEX_MODEL_ARGS[@]}" \
  -C "${TMPDIR:-/tmp}" "$QUERY" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
jq -rs '
  (map(select(.type=="error" or .type=="turn.failed")) | last) as $err
  | if $err then "CODEX_FAILED: "+(($err.error.message // $err.message // $err.error // $err.type) | tostring)
    else map(select(.item.type? == "agent_message")) | last | .item.text // empty
    end
' /tmp/codex.json
```

- **Identity isolation is mandatory for unbiased review.** Isolated `CODEX_HOME` (auth only, no `hooks.json`, no MCP) + `--ignore-user-config` + `--ignore-rules`. This is separate from workspace access.
- **Model:** default `gpt-6-astra`. Probe writes `bt_codex_model`. Empty means product default (Astra and 6.1 Sol unavailable; upgrade CLI). `bt_codex_error` carries the last error text when the probe marked Codex unavailable.
- **Usage limit:** `You've hit your usage limit … try again at <date>` is a plan cap. Skip the slot, record the reset time, do not retry other models (the probe stops on the first such error).
- **Never** pass `--approve-for-me`, `--dangerously-bypass-hook-trust`, `--worktree`, or `-p/--profile` in a consult. A profile layers config back in and defeats `--ignore-user-config`.
- **Effort:** `-c model_reasoning_effort="high"` (or `xhigh`/`max`) when the package is hard; `ultra` enables automatic delegation and is not for consults.
- **Workspace:** `-C /tmp` + inline evidence (Mode B default), or cwd/repo when Mode C (keep isolated home either way).
- Always close stdin with `< /dev/null`. Stderr may still print `Reading additional input from stdin...`; that line alone is **not** a hang if JSONL completed.
- Treat `type==error` and `type==turn.failed` as failure before reading `agent_message`. The `error` event puts its text on `.message`; `turn.failed` on `.error.message`.
- Parse fallback: `--output-last-message /tmp/bt_codex_last.txt` writes the final text and still prints it on stdout (without `--json`).
- Structured Mode A: `--output-schema FILE`.
- Code review shortcut: `codex review --uncommitted` (top-level) or `codex exec review --uncommitted`. Untracked files need staging or inline context.
- XML prompt blocks (`<task>`, `<grounding_rules>`, `<structured_output_contract>`) still help GPT-class models.
- Capability modes and MCP policy: `capability-packaging.md`.

## Cursor CLI (xAI primary)

```bash
source /tmp/bt_models.env 2>/dev/null
( cd "${TMPDIR:-/tmp}" && env -u CMUX_SURFACE_ID CMUX_CURSOR_HOOKS_DISABLED=1 \
  cursor-agent -p "$QUERY" --model "${bt_cursor_model:-grok-4.7-high}" \
  --output-format json --mode ask --trust --workspace "${TMPDIR:-/tmp}" < /dev/null ) 2>/tmp/bt_cursor.err \
  | jq -r 'if .is_error then "CURSOR_FAILED: "+(.result // .error // "error" | tostring) else .result end'
```

- **Login.** Uses the normal Cursor login (`cursor-agent status` must say "Logged in as"). The probe writes `bt_cursor_error="not logged in"` otherwise.
- **Model.** Probe picks the newest `grok-X.Y-high` (or `cursor-grok-X.Y-high`) slug from `--list-models`. `grok-4.7-xhigh` exists for hard packages; pass it explicitly.
- **Guardrails.** `--mode ask` is read-only Q&A with no shell, so ambient hooks and rules cannot turn into actions. Never add `--force`/`--yolo`, `--approve-mcps`, `--auto-review`, `--plugin-dir`, `-w/--worktree`, or `--plan`.
- **Leaks.** Cursor has no switch for `~/.cursor/hooks.json`, user rules, or `~/.cursor/plugins`. `CMUX_CURSOR_HOOKS_DISABLED=1` silences the cmux hooks; the hcom notice line and rules still reach context.
- **Mode C.** Point `--workspace` (and `--add-dir`) at the repo; keep `--mode ask`.
- Success JSON: `.result`, `.is_error`, `.session_id`. Always close stdin.

## Grok (xAI fallback; not in active use)

Contract last dogfooded on grok 1.0.30. Re-verify before relying on it.

```bash
source /tmp/bt_models.env 2>/dev/null || bt_grok_model=grok-4.7
GROK_HOME="${bt_grok_home:-${TMPDIR:-/tmp}/bt-grok-home}" GROK_DISABLE_AUTOUPDATER=1 \
  grok -p "$QUERY" -m "$bt_grok_model" --output-format json --disable-web-search --no-subagents 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```

Large packages:

```bash
printf '%s' "$QUERY" > /tmp/bt_grok_prompt.txt
GROK_HOME="${bt_grok_home:-${TMPDIR:-/tmp}/bt-grok-home}" GROK_DISABLE_AUTOUPDATER=1 \
  grok --prompt-file /tmp/bt_grok_prompt.txt -m "$bt_grok_model" \
  --output-format json --disable-web-search --no-subagents 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```

- **Isolated home.** The probe builds `$bt_grok_home` with a copied `auth.json` and a `config.toml` that sets `[cli] auto_update=false`, `[models] default="grok-4.7"`, and turns off `[compat.claude]` / `[compat.cursor]` hooks, MCPs, skills, rules, agents. No `hooks/`, no `[mcp_servers.*]`, no plugins. Verified: one-word answer in ~6s with no agent-bus chatter.
- Headless flag is `-p` / `--single`. Probe parses `Default model:` from `grok models` (fallback `grok-4.7`). Logged out, 1.0.46 only advertises `grok-4.6`/`grok-4.5`.
- Success JSON has `.text`, `.stopReason`, and spend fields. Failures are `{"type":"error","message":"..."}` with non-zero exit.
- `AuthorizationRequired` on stderr is often a **billing** cap; read stdout JSON `.message` (`out of credits` / `spending-limit`). `grok login` will not fix billing.
- `--no-auto-update` disappeared from `--help` in 1.0.30 (still accepted). Prefer the env var + config key above.
- Optional `--reasoning-effort` / `--effort` (`low` … `xhigh`). Optional `--cwd` scratch dir to avoid writing `cache/projects.json` into the repo. `--permission-mode plan` or `--tools ""` for strict text-only.
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

- `--pure` skips config plugins (`opencode.json` → `plugin: [...]`), which is where hcom.ts and cmux feeds live. Verified: no plugin output in a `--pure` run. **Default for braintrust.**
- `--auto` auto-approves permissions needed for tool use; braintrust prompts should still be read-only by design.
- Attach evidence with `-f` / `--file`; set `--dir` for Mode C repo walk.
- Drop `--pure` only for Mode G when a named local MCP is required and healthy.
- **Model:** use the user's OpenCode default. Probe resolves: (1) `"model"` in `opencode.json`, (2) last non-free session model (TUI stand-in), (3) omit `-m`. Expected on this setup: `zai-coding-plan/glm-5.3` (probe warns when the resolved id lacks `glm-5.3`). Do not hardcode a vendor id in the launch line; fix the config instead.
- **Variant:** probe sets `bt_opencode_variant=max` when the resolved id contains `glm-5.3` (GLM-5.3 thinking; max is the coding default).
- JSON is an event stream (`text`, `tool_use`, `step_start`, `step_finish`, `error`; `reasoning` only with `--thinking`). Answer is the last non-empty `type=="text"` part. Treat `type=="error"` as failure.

## Claude

**Inside Claude Code:** Task tool, `subagent_type: "braintrust:peer"`, background. The plugin agent (`agents/peer.md`) pins `model: claude-opus-5-5[1m]`, `effort: high`, `omitClaudeMd: true`, and disallows Write/Edit. If the plugin agent is not loaded (older install), use `general-purpose` and note it. Never `claude -p` (nested session blocked).

**From other hosts:**

```bash
claude -p "$QUERY" --model "${bt_claude_model:-claude-opus-5-5[1m]}" --output-format json \
  --no-session-persistence --safe-mode --settings '{"disableAllHooks":true}' 2>/tmp/bt_claude.err | jq -r '.result'
```

- Consult default: **`claude-opus-5-5[1m]`** (Opus 5.5, 1M context). Bump when a newer Opus ships. `opus[1m]` is the alias form. Liveness probe uses haiku. Fable 5.1 (`claude-fable-5-1`) is opt-in for long-horizon work.
- **`--safe-mode` is the isolation switch** (claude 2.1.301). It drops CLAUDE.md, plugins, user skills, MCP servers, hooks and agents, and keeps keychain auth and built-in tools. `--settings '{"disableAllHooks":true}'` stays as belt and braces. Dogfooded 2026-10-16: without `--safe-mode` the peer received the global CLAUDE.md, ~20 MCP servers (Gmail, Slack, Mercury…) and every plugin, about 62k cached tokens, 10s and $0.41 for a one-word answer. With it: ~15.6k tokens, 2.2s, $0.04, no hcom activity.
- Strict text-only alternative: `--restricted --strict-mcp-config` (also removes Bash/WebFetch and ignores user/project settings files; ~13.9k tokens). Use it for Mode A consults.
- Avoid `--bare` for consults (skips keychain; "Not logged in").
- `--no-session-persistence` keeps consults out of `/resume`.
- Piped stdin is capped at 10MB. Larger packages: write a file and name the path in the prompt.
- Optional: `--effort high|xhigh|max`. `--json-schema` puts structured output on `.structured_output`. `modelUsage` in the JSON result confirms which model answered.
- Fallback model for cheap/fast Goal Cards: `haiku`.

## Host matrix (who calls whom)

| You are in | Call peers via | Claude peer |
|------------|----------------|-------------|
| Claude Code | Bash / background shell | Task tool → `braintrust:peer` |
| Codex | shell | `claude -p --model 'claude-opus-5-5[1m]' --safe-mode --settings '{"disableAllHooks":true}'` |
| Cursor / Grok | shell | same |
| OpenCode | shell (`opencode` host sits out of its own slot) | same |
| agy | shell | same |

Never launch the host as a peer of itself. Full multi-vendor consult is up to **five** independent voices when every peer is available: Claude, agy, Codex, one xAI voice (Cursor, else Grok), OpenCode.
