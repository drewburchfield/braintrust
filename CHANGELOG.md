# Changelog

## 1.14.0 — 2026-10-07

Harness refresh and doc catch-up. Dogfooded against claude 2.1.292, agy 1.3.1 (gemini-3.8-flash-high), codex 0.160.0 (gpt-6-astra), cursor-agent 2026.10.01 (grok-4.7-high), opencode 1.18.34 (glm-5.3). Every documented flag re-checked against `--help`.

- Codex fallback is `gpt-6.1-sol` (new catalog priority 1, "latest workhorse"). `gpt-6-astra` stays primary as the frontier model. Verified CLI is 0.160.0.
- agy now loads hcom and herdr hooks from `~/.gemini/config/hooks.json` (installed 2026-09-23) and has no switch to skip them. Docs drop the "no hook surface" claim. A headless run on 2026-10-07 answered cleanly and registered no hcom agent. New failure-mode row: skip the Google slot if bus chatter appears.
- Cursor: `cli-contracts.md` gains the full contract (it had none). Noted the new `--sandbox`, `--plugin-dir`, `--auto-review` flags and that `~/.cursor/plugins` may load; never pass `--plugin-dir`.
- Grok CLI is optional and marked unverified since 1.0.30 (not in active use; logged out on 1.0.46). Every reference now agrees on the `grok-4.7` fallback.
- References catch up with 1.13.0: Opus 5.5 in `cli-contracts.md`, `capability-packaging.md`, `failure-modes.md`, `self-improvement.md`.
- Doc fallbacks for isolated homes use `${TMPDIR:-/tmp}` to match the probe (macOS `$TMPDIR` is not `/tmp`).
- Manifests, README, SessionStart hook description, and eval rubric list Cursor. Self-improvement checklist adds hook-surface and stale-string checks.

## 1.13.0 — 2026-09-22

Cursor CLI joins as the xAI path, and Claude moves to Opus 5.5. Dogfooded against claude 2.1.280, agy (gemini-3.8-flash-high), codex 0.155.1, cursor-agent 2026.09.18, opencode (glm-5.3).

- xAI slot: Cursor CLI (`cursor-agent`) first, Grok CLI second. The probe sets `bt_xai_via` so a consult runs one xAI voice. Cursor pins the newest `grok-X.Y-high` from `--list-models` (`grok-4.7-high` today) and runs `--mode ask` (read-only).
- Cursor uses the normal login. Guardrails: `--mode ask` (read-only, no shell, so it cannot join the hcom bus), no `--approve-mcps`, cmux hooks off via `CMUX_CURSOR_HOOKS_DISABLED=1`, run from `$TMPDIR`. Cursor has no switch for `~/.cursor/hooks.json` or user rules, so the hcom notice line and rules still reach context.
- Claude consult model is `claude-opus-5-5[1m]` for `braintrust:peer` and `claude -p`.
- Grok CLI fallback default is `grok-4.7`.
- Evals: `cursor` peer in the runner; contract-quiz Q4 asks for the Cursor contract. 2026-09-22 contract-quiz on skill-current: agy, codex, cursor (grok-4.7-high), opencode, claude (Opus 5.5) all 10/10.

## 1.12.0 — 2026-09-16

Harness + model refresh with mandatory identity isolation. Dogfooded against claude 2.1.273, agy 1.2.3, codex 0.154.0, grok 1.0.30, opencode 1.18.31.

- Codex primary model is `gpt-6-astra` (GPT-6 Astra); fallback `gpt-5.6-sol`, then product default. Launch adds `--ignore-rules`. jq parser reads `error` events from `.message` (was silently `error`). Probe stops on usage-limit errors and records `bt_codex_error`.
- agy pin is the newest `gemini-*-flash-high` slug in `agy models` (`gemini-3.8-flash-high` today); no hardcoded generation.
- Claude consult model is `claude-opus-4-8[1m]` (Opus 4.8, 1M context). New plugin agent `agents/peer.md` (`braintrust:peer`) pins it for the Task tool with `omitClaudeMd` and read-only tools. `claude -p` consults add `--settings '{"disableAllHooks":true}'` and `--no-session-persistence`.
- Grok runs from an isolated `GROK_HOME` the probe builds (auth only; `[compat.*]` scanning off) with `GROK_DISABLE_AUTOUPDATER=1` and `--no-subagents`. This stops `~/.grok/hooks/hcom.json` from turning consults into agent-bus chatter. `--no-auto-update` dropped (hidden in 1.0.30).
- OpenCode `--pure` verified to skip config plugins (hcom.ts). Probe warns when the resolved model lacks `glm-5.3`; expected `zai-coding-plan/glm-5.3` with `--variant max`.
- New failure-modes section on ambient hooks (hcom/cmux/herdr) with per-CLI isolation table.
- Evals: fixtures, variants, and runner follow the new contracts (Astra, isolated grok, Opus 4.8 1M). Scorer judges GROUNDED on the last lines only and treats `*_FAILED:` as failure only when it is the first line. Matrix 2026-09-16: agy, grok, opencode 10/10 on both fixtures and all four variants; codex skipped (usage cap).

## 1.11.0 — 2026-08-22

Harness + model refresh. Dogfooded against claude 2.1.239, agy 1.1.18, codex 0.149.0, grok 1.0.5, opencode 1.18.19.

- Claude consult default is `opus` (liveness probe still uses haiku).
- agy default pin is `gemini-3.7-flash-high` when listed; launch uses `--output-format json`.
- Grok default is `grok-4.6`. Probe parses `Default model:` from `grok models`. Dropped `grok-composer-2.5-fast`.
- OpenCode still uses the user's configured model. Probe sets `bt_opencode_variant=max` when that id contains `glm-5.3`.
- Codex stays on `gpt-5.6-sol`. JSONL parse now treats `error` / `turn.failed` as failure.
- Grok scripted runs pass `--no-auto-update`. Large packages may use `--prompt-file`.
- Eval fixture Q4 and runner contracts follow the new defaults.

## 1.10.0

- Codex primary model: GPT-5.6 Sol (`gpt-5.6-sol`). Explicit `-m` with `--ignore-user-config`.
- Minimum Codex CLI 0.144.0+ for Sol.

## 1.9.0

- Hybrid always-on skill (eval-backed). Gemini CLI removed. OpenCode user-default model discovery.
- Grok default `grok-4.5`. Codex clean `CODEX_HOME` + `--ignore-user-config`.
