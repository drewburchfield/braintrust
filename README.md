<div align="center">

<img src="https://ghrb.waren.build/banner?header=braintrust%20%F0%9F%A7%A0&subheader=Orchestrate%20AI%20CLIs%20for%20second%20opinions%20and%20research&bg=0a1628&secondaryBg=1e3a5f&color=e8f0fe&subheaderColor=7eb8da&headerFont=Inter&subheaderFont=Inter&support=false" alt="braintrust" width="100%">

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin from the [not-my-job](https://github.com/drewburchfield/not-my-job) marketplace.

![License](https://img.shields.io/badge/license-MIT-blue)

</div>

## What it does

Delegates tasks to other AI CLIs running in parallel. Get second opinions on architecture decisions, offload research to models with larger context windows, or run design reviews across multiple models simultaneously.

Braintrust members (consulted in parallel, gated by what's installed and authenticated):

- **Antigravity CLI (agy)** — primary Google AI path (runs your Antigravity account-tier Gemini model)
- **Gemini CLI** — fallback Google AI path with explicit model selection (`-m`) and `@path` file context
- **Codex** — GPT-5.x
- **Grok Build (grok)** — Grok 4.3, a distinct xAI opinion set
- **Claude** — via Task tool subagent

agy and Gemini share one "Google AI" slot (agy preferred); the others each contribute an independent opinion, so a full consult is up to four parallel voices.

## Commands

| Command | What it does |
|---------|-------------|
| `/braintrust` | Orchestrate a task across multiple AI CLIs |
| `/consult` | Alias for `/braintrust` |

## Use Cases

- Get second opinions from different models simultaneously
- Cross-model code review (Codex `exec review` or parallel across every available CLI)
- Validate architecture decisions
- Parallel research across multiple models
- Security audits with diverse model perspectives
- Offload large-context work to Google AI (agy / gemini 1M context)

## v1.7.0 Highlights

- **Codex now runs as a true clean-slate reviewer.** `codex exec --ephemeral` was never a blank slate: it loaded `~/.codex` memories, MCP servers, and the global `AGENTS.md`, which contaminated reviews (observed: a diff review that answered an unrelated project's spec pulled from a memory) and biased synthesis. Every Codex consult now runs against an isolated throwaway `CODEX_HOME` (no memories, no MCP, no global AGENTS.md). This also removes the MCP-boot startup hangs.
- **Stop blackholing stderr.** CLI calls now capture stderr to `/tmp/bt_<cli>.err` instead of `2>/dev/null`, so failures are diagnosable. This fixed two long-standing misdiagnoses: an agy "transient empty" that is actually a hard `rc=124` timeout, and a Grok `AuthorizationRequired` that is actually a **403 billing cap** (`out of credits / spending-limit`) that `grok login` cannot fix.
- **agy failure handling is exit-code-aware.** Cold start (retry once) vs a hard hang (`rc=124`, stop retrying and fall back to gemini) are now distinguished. Calls set an explicit `--print-timeout` so agy fails fast with its own diagnostics instead of being killed silently.
- **Grok error detection.** Consults parse the `{"type":"error","message":...}` object and surface the real cause (e.g. billing) instead of a generic "empty/unauthenticated".

## v1.6.0 Highlights

- **Grok Build (Grok 4.3)** added as a first-class braintrust member. Headless: `grok -p "..." -m grok-build --output-format json | jq -r '.text'`.
- **Default consult is now "every installed + authenticated CLI"** (up to four voices), not a fixed three.
- **Reliability fix for agy ↔ gemini "thrashing"**: the model probe now uses generous cold-start timeouts and a warm-up retry per CLI, so a slow first call no longer false-negatives a CLI and silently flips the Google AI path.
- **Gemini default model is now `gemini-3.1-pro-preview`** (newest-best first). Dogfooding showed `gemini-2.5-pro` was actually the *flakier* model on current accounts; it is now a fallback only.
- **agy vs Gemini model paths documented**: agy has no `-m` flag and runs your account-tier model; Gemini lets you pick the exact model. They are different access paths, not interchangeable.
- **June 18, 2026 sunset**: Gemini CLI free-tier/OAuth access ends. agy is the primary path; the probe handles the switch automatically.

## Requirements

All CLIs are optional; braintrust consults whichever are installed and authenticated.

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — always available as a subagent from Claude Code
- [Antigravity CLI (agy)](https://antigravity.google/product/antigravity-cli) — `curl -fsSL https://antigravity.google/cli/install.sh | bash` (primary Google AI path)
- [Codex CLI](https://github.com/openai/codex)
- [Grok Build (grok)](https://x.ai) — `curl -fsSL https://x.ai/cli/install.sh | bash`, then `grok login` *(needs a Grok subscription for `grok-build`)*
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) *(power-user fallback for explicit model selection / `@path`; free-tier sunset 2026-06-18)*

## Install

```
claude plugins install braintrust@not-my-job
```

## License

MIT
