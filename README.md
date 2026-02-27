<div align="center">

<img src="https://ghrb.waren.build/banner?header=braintrust%20%F0%9F%A7%A0&subheader=Orchestrate%20AI%20CLIs%20for%20second%20opinions%20and%20research&bg=0a1628&secondaryBg=1e3a5f&color=e8f0fe&subheaderColor=7eb8da&headerFont=Inter&subheaderFont=Inter&support=false" alt="braintrust" width="100%">

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin from the [not-my-job](https://github.com/drewburchfield/not-my-job) marketplace.

![License](https://img.shields.io/badge/license-MIT-blue)

</div>

## What it does

Delegates tasks to other AI CLIs (Gemini, Codex, Claude Code) running in parallel. Get second opinions on architecture decisions, offload research to models with larger context windows, or run design reviews across multiple models simultaneously.

## Commands

| Command | What it does |
|---------|-------------|
| `/braintrust` | Orchestrate a task across multiple AI CLIs |

## Use Cases

- Offload grunt work to Gemini (1M context window)
- Get second opinions from different models
- Design review with WebDev Arena leader
- Validate architecture decisions
- Parallel research across multiple models

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli)
- [Codex CLI](https://github.com/openai/codex)

## Install

```
claude plugins install braintrust@not-my-job
```

## License

MIT
