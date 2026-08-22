<div align="center">

<img src="https://ghrb.waren.build/banner?header=braintrust%20%F0%9F%A7%A0&subheader=Orchestrate%20AI%20CLIs%20for%20second%20opinions%20and%20research&bg=0a1628&secondaryBg=1e3a5f&color=e8f0fe&subheaderColor=7eb8da&headerFont=Inter&subheaderFont=Inter&support=false" alt="braintrust" width="100%">

A multi-harness plugin from the [not-my-job](https://github.com/drewburchfield/not-my-job) marketplace. Primary host: [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Also designed to work when the skill is loaded from Codex, Grok Build, OpenCode, or agy.

![License](https://img.shields.io/badge/license-MIT-blue)

</div>

## What it does

Delegates a task to peer AI CLIs in parallel. Second opinions on architecture, research across model families, security audits, design reviews.

**Grounding** (Skeptical Colleague + Goal Cards):

- Goal Cards at `.braintrust/goal-cards/<slug>.md` with a `session_anchor`
- 6-step protocol: restatement, assumptions, evidence, fidelity, honesty, GROUNDED / NOT GROUNDED
- Host actively curates context before delegating (not "whatever is in the chat")

## Members (v1.11)

| Slot | CLI | Notes |
|------|-----|-------|
| Anthropic | Claude | Task tool inside Claude Code; `claude -p --model opus` from other hosts |
| Google | **agy only** | No Gemini CLI. Default pin **`gemini-3.7-flash-high`**; `--output-format json` |
| OpenAI | Codex | **`gpt-5.6-sol`** (GPT-5.6 Sol); isolated `CODEX_HOME` + `--ignore-user-config`; CLI ≥ **0.144.0** |
| xAI | Grok | Default model `grok-4.6` (from `grok models`) |
| Multi | OpenCode | User's configured/default model (probe discovers); `--variant max` for GLM-5.3 |

Up to **five** independent voices when everything is installed and authenticated. Availability is decided by `scripts/bt_probe.sh`, not by preference.

## Commands

| Command | What it does |
|---------|--------------|
| `/braintrust` | Orchestrate a task across peer CLIs |
| `/consult` | Alias for `/braintrust` |

## v1.11.0 Highlights

- Claude consult default **`opus`**. agy pin **`gemini-3.7-flash-high`**. Grok **`grok-4.6`**. OpenCode `--variant max` when the resolved model contains `glm-5.3`.
- Probe reads Grok's advertised `Default model:` (no longer prefers `grok-4.5` just because it is still listed).
- agy `--output-format json` (`.status` / `.response`). Grok `--no-auto-update` and `--prompt-file` for large packages. Codex JSONL checks `error` / `turn.failed`.
- Harness versions dogfooded 2026-08-22: claude 2.1.239, agy 1.1.18, codex 0.149.0, grok 1.0.5, opencode 1.18.19.

## Earlier (v1.10)

- **Codex primary model: GPT-5.6 Sol** (`gpt-5.6-sol`). Explicit `-m` because consults use `--ignore-user-config`.
- Probe prefers Sol, falls back to product default if Sol is unavailable, and records `bt_codex_model`.
- Documented minimum **Codex CLI 0.144.0+** for Sol (`npm i -g @openai/codex@latest`).

## Earlier (v1.9)

- Hybrid always-on skill (eval-backed); Gemini CLI removed; OpenCode user-default model discovery
- Grok default `grok-4.5`; Codex clean `CODEX_HOME` + `--ignore-user-config`
- Multi-host matrix; durable evals under `evals/`

## Requirements

All peers optional; braintrust uses whatever the probe authenticates.

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Antigravity CLI (agy)](https://antigravity.google/product/antigravity-cli) — `curl -fsSL https://antigravity.google/cli/install.sh | bash`
- [Codex CLI](https://developers.openai.com/codex) — **≥ 0.144.0** for GPT-5.6 Sol (`npm i -g @openai/codex@latest`)
- [Grok Build](https://docs.x.ai/build/overview) — `curl -fsSL https://x.ai/cli/install.sh | bash`
- [OpenCode](https://opencode.ai/docs/cli/) — with an authed provider; set `"model"` in `~/.config/opencode/opencode.json` so headless matches your TUI default

`jq` required for Codex / Grok / OpenCode / agy JSON parsing.

## Install

```
claude plugins install braintrust@not-my-job
```

## Refresh / dogfood / evals

```bash
bash scripts/bt_probe.sh
bash evals/run_eval.sh matrix all agy,codex,grok,opencode
# deeper harness drift notes: skills/braintrust/references/self-improvement.md
```

## License

MIT
