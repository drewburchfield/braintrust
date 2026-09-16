# Changelog

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
