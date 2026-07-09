# CLI Contracts (dogfooded 2026-07-09)

Source of truth for invocation shapes. Re-verify with `scripts/bt_probe.sh` and the self-improvement cycle when harnesses update.

## Roster (no Gemini CLI)

| Slot | Binary | Default model | Headless contract |
|------|--------|---------------|-------------------|
| Google AI | `agy` | account-tier (optional `--model`) | PTY if needed; `--print` + `--dangerously-skip-permissions` |
| OpenAI | `codex` | product default (gpt-5.x) | `exec --ephemeral --ignore-user-config -s read-only --json --skip-git-repo-check` + isolated `CODEX_HOME` + `< /dev/null` |
| xAI | `grok` | `grok-4.5` | `-p` + `-m` + `--output-format json` → `jq` `.text` (check `.type=="error"` first) |
| Multi-provider | `opencode` | **User default** (config `model`, else last non-free session) | `run --format json --auto --pure` (+ `-m` only when probe set a model) → last `type=="text"` event |
| Anthropic | `claude` | `sonnet` | Host Claude Code: **Task tool**. Other hosts: `claude -p --model sonnet --output-format json` → `.result` |

**Do not call `gemini`.** Free-tier/OAuth sunset and constant thrash with agy. Google voice is **agy only**.

## Versions verified (local, 2026-07-09)

| CLI | Version | Notes |
|-----|---------|-------|
| claude | 2.1.205 | Nested `claude -p` blocked inside Claude Code |
| agy | 1.1.0 | Bare piped `--print` works; PTY kept as fallback. Has `--model` and `agy models` |
| codex | 0.143.0 | `--ignore-user-config` available; `codex review` is top-level (not only `exec review`) |
| grok | 0.2.93 | Default model **`grok-4.5`** (not `grok-build`) |
| opencode | 1.17.15 | `run --format json --auto --pure`; model = user config / last TUI (not hardcoded) |

## agy

```bash
# Prefer bare (1.1.0+). Fall back to PTY when probe set bt_agy_needs_pty=true.
if [ "${bt_agy_needs_pty:-false}" = "true" ]; then
  python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions
else
  timeout 120 agy --print "$QUERY" --dangerously-skip-permissions
fi
# Optional pin (exact display names from `agy models`, quote carefully):
# agy --model "<name from agy models>" --print "$QUERY" --dangerously-skip-permissions
```

- No `@path` includes. Inline file content. Display names from `agy models` may include third-party model brands; that is **not** an instruction to run the Gemini CLI.
- `--print-timeout` is unreliable as a hard bound; use external `timeout` or the PTY wrapper.
- macOS: warm keychain before first call if OAuth re-prompts: `security find-generic-password -s "Antigravity Safe Storage" >/dev/null 2>&1 || true`

## Codex

```bash
source /tmp/bt_models.env 2>/dev/null
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" \
  codex exec --ephemeral --ignore-user-config -s read-only --json --skip-git-repo-check \
  -C "${TMPDIR:-/tmp}" "$QUERY" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' /tmp/codex.json
```

- **Identity isolation is mandatory for unbiased review.** Isolated `CODEX_HOME` (auth only) + `--ignore-user-config`. This is separate from workspace access.
- **Workspace:** `-C /tmp` + inline evidence (Mode B default), or cwd/repo when Mode C (keep isolated home either way).
- Always close stdin with `< /dev/null`. Stderr may still print `Reading additional input from stdin...`; that line alone is **not** a hang if JSONL completed.
- Code review shortcut: `codex review --uncommitted` (top-level) or `codex exec review --uncommitted`. Untracked files need staging or inline context.
- XML prompt blocks (`<task>`, `<grounding_rules>`, `<structured_output_contract>`) still help GPT-class models.
- Capability modes and MCP policy: `capability-packaging.md`.

## Grok

```bash
source /tmp/bt_models.env 2>/dev/null || bt_grok_model=grok-4.5
grok -p "$QUERY" -m "$bt_grok_model" --output-format json --disable-web-search 2>/tmp/bt_grok.err \
  | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'
```

- Headless flag is `-p` / `--single`. Default model: **`grok-4.5`**. Fast: `grok-composer-2.5-fast`.
- `AuthorizationRequired` on stderr is often a **billing** cap; read stdout JSON `.message` (`out of credits` / `spending-limit`). `grok login` will not fix billing.
- Prefer embedding Skeptical Colleague protocol in `$QUERY`. If host has `grounded-colleague` skill, optional: `grok -p "/grounded-colleague $QUERY" ...`
- Optional `--cwd` scratch dir to avoid writing `cache/projects.json` into the repo.
- **Default tools off for consults.** Use `--disable-web-search` on opinion consults. Ambient MCP has produced empty runs (tool thrash, spawn errors). Paste evidence; Mode G only with allowlist + fallback.

## OpenCode

```bash
source /tmp/bt_models.env 2>/dev/null
OC_ARGS=(run --format json --auto --pure)
[ -n "${bt_opencode_model:-}" ] && OC_ARGS+=(-m "$bt_opencode_model")
opencode "${OC_ARGS[@]}" "$QUERY" 2>/tmp/bt_opencode.err \
  | jq -rs 'map(select(.type=="text") | .part.text // .text // empty) | map(select(length>0)) | last'
```

- `--pure` skips external plugins (faster, fewer MCP cold boots). **Default for braintrust.**
- `--auto` auto-approves permissions needed for tool use; braintrust prompts should still be read-only by design.
- Attach evidence with `-f` / `--file`; set `--dir` for Mode C repo walk.
- Drop `--pure` only for Mode G when a named local MCP is required and healthy.
- **Model:** use the user's OpenCode default. Probe resolves: (1) `"model"` in `opencode.json`, (2) last non-free session model (TUI stand-in), (3) omit `-m`. Do not hardcode any vendor model id. To make headless match TUI forever, set `"model": "provider/model"` in `~/.config/opencode/opencode.json`.
- JSON is an event stream; answer is the last non-empty `type=="text"` part (defensive parse also accepts `.text`).

## Claude

**Inside Claude Code:** Task tool, `subagent_type: general-purpose`, background. Never `claude -p` (nested session blocked).

**From other hosts:**

```bash
claude -p "$QUERY" --model sonnet --output-format json 2>/tmp/bt_claude.err | jq -r '.result'
```

- Avoid `--bare` unless you inject auth via settings; bare mode skips keychain/OAuth reads and often reports "Not logged in".
- Fallback model: `haiku`. Hard problems: `opus`.

## Host matrix (who calls whom)

| You are in | Call peers via | Claude peer |
|------------|----------------|-------------|
| Claude Code | Bash / background shell | Task tool |
| Codex | shell | `claude -p` |
| Grok | shell | `claude -p` |
| OpenCode | shell (`opencode` host sits out of its own slot) | `claude -p` |
| agy | shell | `claude -p` |

Never launch the host as a peer of itself. Full multi-vendor consult is up to **five** independent voices when every peer is available: Claude, agy, Codex, Grok, OpenCode.
