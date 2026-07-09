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

## Members (v1.9)

| Slot | CLI | Notes |
|------|-----|-------|
| Anthropic | Claude | Task tool inside Claude Code; `claude -p` from other hosts |
| Google | **agy only** | No Gemini CLI. Account-tier model; optional `--model` |
| OpenAI | Codex | Isolated `CODEX_HOME` + `--ignore-user-config` |
| xAI | Grok | Default model `grok-4.5` |
| Multi | OpenCode | User's configured/default model (probe discovers) |

Up to **five** independent voices when everything is installed and authenticated. Availability is decided by `scripts/bt_probe.sh`, not by preference.

## Commands

| Command | What it does |
|---------|--------------|
| `/braintrust` | Orchestrate a task across peer CLIs |
| `/consult` | Alias for `/braintrust` |

## v1.9.0 Highlights

- **Hybrid always-on skill** (eval-backed): lean launch contracts + ops appendix. Deep material in `references/` on demand.
- **Removed Gemini CLI**; Google path is **agy only**.
- **OpenCode** first-class member with user-default model discovery (no hardcoded vendor id).
- **Grok** default **`grok-4.5`**; **Codex** clean `CODEX_HOME` + `--ignore-user-config`.
- **Multi-host matrix**: Claude Code, Codex, Grok, OpenCode, agy.
- **Scripts as assets**: `scripts/bt_probe.sh`, `scripts/bt_agy_pty.py`.
- **Durable evals**: `bash evals/run_eval.sh matrix all agy,codex,grok,opencode`

## Earlier (v1.8 / v1.7)

- Skeptical Colleague + Goal Cards + session_anchor
- agy PTY workaround for antigravity-cli#76
- Codex clean-slate via isolated `CODEX_HOME`
- stderr capture instead of blackholing failures
- Grok billing-cap diagnosis via JSON error body

## Requirements

All peers optional; braintrust uses whatever the probe authenticates.

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Antigravity CLI (agy)](https://antigravity.google/product/antigravity-cli) — `curl -fsSL https://antigravity.google/cli/install.sh | bash`
- [Codex CLI](https://developers.openai.com/codex)
- [Grok Build](https://docs.x.ai/build/overview) — `curl -fsSL https://x.ai/cli/install.sh | bash`
- [OpenCode](https://opencode.ai/docs/cli/) — with an authed provider; set `"model"` in `~/.config/opencode/opencode.json` so headless matches your TUI default

`jq` required for Codex / Grok / OpenCode JSON parsing.

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
