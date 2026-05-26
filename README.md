<div align="center">

<img src="https://ghrb.waren.build/banner?header=braintrust%20%F0%9F%A7%A0&subheader=Orchestrate%20AI%20CLIs%20for%20second%20opinions%20and%20research&bg=0a1628&secondaryBg=1e3a5f&color=e8f0fe&subheaderColor=7eb8da&headerFont=Inter&subheaderFont=Inter&support=false" alt="braintrust" width="100%">

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin from the [not-my-job](https://github.com/drewburchfield/not-my-job) marketplace.

![License](https://img.shields.io/badge/license-MIT-blue)

</div>

## What it does

Delegates tasks to other AI CLIs running in parallel. Get second opinions on architecture decisions, offload research to models with larger context windows, or run design reviews across multiple models simultaneously.

Supports three CLIs as braintrust members: **Antigravity CLI (agy)**, **Codex**, and **Claude** (via Task tool subagent). Gemini CLI is also supported as a power-user fallback with explicit model selection and `@path` file context.

## Commands

| Command | What it does |
|---------|-------------|
| `/braintrust` | Orchestrate a task across multiple AI CLIs |
| `/consult` | Alias for `/braintrust` |

## Use Cases

- Get second opinions from different models simultaneously
- Cross-model code review (Codex `exec review` or parallel all three)
- Validate architecture decisions
- Parallel research across multiple models
- Security audits with diverse model perspectives
- Offload large-context work to Google AI (agy / gemini 1M context)

## v2.0.0 Highlights

- **Antigravity CLI (agy)** is now the primary Google AI path. `gemini` is retained as a fallback for users who need explicit model selection or `@path` file context.
- **`--no-sandbox`** replaces `--sandbox=none` for Gemini CLI (correct boolean flag form).
- **Session probe** now checks `agy` first, then `gemini`, and caches `bt_agy_available` alongside existing env vars.
- **June 18, 2026 sunset**: Gemini CLI free-tier/OAuth access ends. The probe handles the switch automatically.

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- [Antigravity CLI (agy)](https://antigravity.google/product/antigravity-cli) — `curl -fsSL https://antigravity.google/cli/install.sh | bash`
- [Codex CLI](https://github.com/openai/codex)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) *(optional — power-user fallback; free-tier sunset 2026-06-18)*

## Install

```
claude plugins install braintrust@not-my-job
```

## License

MIT
