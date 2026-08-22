# Changelog

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
