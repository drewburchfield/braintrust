<div align="center">

<img src="https://ghrb.waren.build/banner?header=braintrust%20%F0%9F%A7%A0&subheader=Orchestrate%20AI%20CLIs%20for%20second%20opinions%20and%20research&bg=0a1628&secondaryBg=1e3a5f&color=e8f0fe&subheaderColor=7eb8da&headerFont=Inter&subheaderFont=Inter&support=false" alt="braintrust" width="100%">

A multi-harness plugin from the [not-my-job](https://github.com/drewburchfield/not-my-job) marketplace. Primary host: [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Also designed to work when the skill is loaded from Codex, Cursor CLI, Grok Build, OpenCode, or agy.

![License](https://img.shields.io/badge/license-MIT-blue)

</div>

## What it does

Delegates a task to peer AI CLIs in parallel. Second opinions on architecture, research across model families, security audits, design reviews.

**Grounding** (Skeptical Colleague + Goal Cards):

- Goal Cards at `.braintrust/goal-cards/<slug>.md` with a `session_anchor`
- 6-step protocol: restatement, assumptions, evidence, fidelity, honesty, GROUNDED / NOT GROUNDED
- Host actively curates context before delegating (not "whatever is in the chat")

## Quick start (v1.17)

```bash
peerpanel brief new .braintrust/consults/my-question   # scaffold the brief
# fill request.md (the user's words, verbatim), question.md, sources.txt
peerpanel brief check .braintrust/consults/my-question
peerpanel consult .braintrust/consults/my-question     # one line per seat as it lands
```

`peerpanel` ships in the plugin's `bin/`, which Claude Code puts on PATH. It probes and pings the peers, runs them read-only and identity-isolated in parallel, retries once on a timeout, empty answer or dropped connection, names every other failure (`cap`, `auth`, `cli-changed`, `model`, `hijacked`, `off-task`), and writes each seat's prompt and answer plus `status.json` and `record.md`. It needs Python 3.9+ and nothing else. The name avoids `bt` and `braintrust`, which the npm `braintrust` package already installs.

The brief has a fixed shape so the host model cannot quietly narrow what peers see: the user's request verbatim, source paths the peers open themselves, host claims labeled unverified, and the host's own view held back unless asked for.

## Members (v1.17)

| Slot | CLI | Notes |
|------|-----|-------|
| Anthropic | Claude | `braintrust:peer` agent (Opus 5.5, 1M) inside Claude Code; `claude -p --model 'claude-opus-5-5[1m]' --safe-mode --settings '{"disableAllHooks":true}'` from other hosts |
| Google | **agy only** | No Gemini CLI. Strongest Gemini High from `agy models` (**`gemini-4-neon-high`**, Gemini 4 Neon, as of 2026-11), falling back to the newest Flash High (`gemini-3.8-flash-high`); `--output-format json`. Loads user hooks (no switch) |
| OpenAI | Codex | **`gpt-6.2-astra`** (GPT-6.2 Astra; fallback `gpt-6.2-sol`); isolated `CODEX_HOME` + `--ignore-user-config --ignore-rules`; CLI **0.170.0** verified (0.170.0 minimum for 6.2) |
| xAI | Cursor CLI, else Grok CLI | Cursor: newest `grok-X.Y-high` (`grok-4.7-high` today; `grok-4.7-medium` if the account drops to Cursor Free), `--mode ask`. Grok CLI (optional fallback): `grok models` default, isolated `GROK_HOME` |
| Multi | OpenCode | User's configured/default model (expected `zai-coding-plan/glm-5.3`); `-m <model>#max` for GLM-5.3; isolated config root (OpenCode 2.x) |

Up to **five** independent voices when everything is installed and authenticated. Availability is decided by `scripts/bt_probe.sh`, not by preference.

Every peer runs **identity-isolated**. The probe builds `$TMPDIR/bt-codex-home` and `$TMPDIR/bt-grok-home` (auth only), Cursor runs read-only (`--mode ask`, cmux hooks off, no MCP approval), OpenCode runs from an empty `$TMPDIR/bt-opencode-config` with `--standalone`, and the Claude peer skips CLAUDE.md and user hooks. The `claude -p` path runs `--safe-mode`, so it gets no CLAUDE.md, MCP servers or plugins. Ambient agent-bus hooks (hcom) in the real homes otherwise hijack headless answers. agy has no isolation switch for its hooks; braintrust watches its answers for bus chatter.

## Commands

| Command | What it does |
|---------|--------------|
| `/braintrust` | Orchestrate a task across peer CLIs |
| `/consult` | Alias for `/braintrust` |
| `braintrust:peer` agent | Claude peer voice (Opus 5.5 1M, read-only) used by the Task tool |
| `peerpanel` | CLI: `probe`, `ping`, `brief new/check`, `prompt`, `consult`, `status` |

## v1.17.0 Highlights

- **`peerpanel` CLI.** One command replaces the hand-built launch lines. Built from a review of 23 real consults (Aug to Nov 2026), where most failures were silent empty outputs and host guardrails blocking long inline commands.
- **Fixed brief shape.** Three of those consults showed the host's own errors reaching every peer through its brief. Peers now read the sources themselves and check the host's claims.
- **Preflight ping.** A check-code round trip before each consult skips dead or hijacked peers instead of waiting out their timeouts.
- **Read-only peers.** Codex `-s read-only`, agy `--mode plan`, Cursor `--mode ask`, OpenCode `--agent plan`.

## v1.16.0 Highlights

- **Google → Gemini 4 Neon High** (`gemini-4-neon-high`). The probe ranks Gemini families explicitly (Neon > Carbon > Argon > Hydrogen > Flash) because several share generation 4.
- **Codex → GPT-6.2 Astra** (`gpt-6.2-astra`), fallback `gpt-6.2-sol`.
- **OpenCode 2.x support.** OpenCode 2.3 removed `--pure` and `--variant`. Consults now run from an empty `XDG_CONFIG_HOME` with `--standalone` and pass the variant as `-m <model>#max`.
- **Cursor Free plan handled.** If Cursor refuses `grok-4.7-high` as a Free-plan model, the probe steps down to `grok-4.7-medium` and reports Cursor's stderr error when nothing answers.
- **Harness refresh** dogfooded 2026-11-21: claude 2.1.330, agy 1.5.14, codex 0.170.0, cursor-agent 2026.11.19, grok 1.0.92, opencode 2.3.2. Grok CLI answers again from its isolated home.

## v1.15.1 Highlights

- **Harness refresh** dogfooded 2026-10-23: claude 2.1.309, agy 1.4.6, codex 0.160.1, cursor-agent 2026.10.22, opencode 1.18.34. Every pin holds; Gemini 4 Argon is still Google's newest model.

## v1.15.0 Highlights

- **Google → Gemini 4 Argon High** (`gemini-4-argon-high`). The probe now pins the strongest `gemini-*-high` slug and falls back to the newest Flash High (`bt_agy_fast_model`). Argon is ~2.5x slower than Flash High.
- **Claude `claude -p` peer runs `--safe-mode`.** Hooks were already off, but the peer still loaded your CLAUDE.md, ~20 MCP servers and every plugin. Safe mode keeps keychain auth and cuts a one-word consult from ~62k tokens, 10s and $0.41 to ~15.6k tokens, 2.2s and $0.04.
- **Harness refresh** dogfooded 2026-10-16: claude 2.1.301, agy 1.4.0, codex 0.160.0, cursor-agent 2026.10.14, opencode 1.18.34. Pins unchanged elsewhere: `gpt-6-astra`, `claude-opus-5-5[1m]`, `grok-4.7-high`, `glm-5.3`.
- New "never pass" flags documented (agy `--remote-control`, Codex `--dangerously-bypass-hook-trust`/`--approve-for-me`/`-p`, Cursor `--worktree`/`--plan`) plus agy's Gemini effort ceiling and OpenCode's `glm-5.3-highspeed` 429 retry loop.

## v1.14.0 Highlights

- **Harness refresh** dogfooded 2026-10-07: claude 2.1.292, agy 1.3.1, codex 0.160.0, cursor-agent 2026.10.01, opencode 1.18.34.
- **Codex fallback → `gpt-6.1-sol`** (new catalog priority 1). Astra stays primary as the frontier model.
- **agy hooks documented.** hcom and herdr hooks now load from `~/.gemini/config/hooks.json`; agy has no switch, so consults watch for bus chatter.
- `cli-contracts.md` gains a Cursor contract and current versions; all references agree on Opus 5.5 and `grok-4.7`.
- Doc fallbacks for isolated homes use `${TMPDIR:-/tmp}`, matching the probe.
- Grok CLI marked optional and unverified since 1.0.30.

## v1.13.0 Highlights

- **xAI slot via Cursor CLI** (`cursor-agent`) with the newest Grok High model it lists (`grok-4.7-high` today). Grok CLI stays as the fallback; the probe picks one (`bt_xai_via`).
- Cursor uses your normal login and runs `--mode ask` (read-only, no shell) with cmux hooks off and no MCP approval. Its hcom notice and user rules still reach context; ask mode keeps them from becoming actions.
- **Claude → Opus 5.5 1M** (`claude-opus-5-5[1m]`) for `braintrust:peer` and `claude -p`.
- Grok CLI fallback default `grok-4.7`.

## v1.12.0 Highlights

- **Codex → GPT-6 Astra** (`gpt-6-astra`), fallback `gpt-5.6-sol`. Probe reports usage-limit errors verbatim (`bt_codex_error`) instead of "empty/timeout".
- **agy → newest Flash High** (`gemini-3.8-flash-high` today); probe auto-selects the newest `gemini-*-flash-high` slug.
- **Claude → Opus 4.8 1M** (`claude-opus-4-8[1m]`) via the new `braintrust:peer` plugin agent (read-only, no CLAUDE.md) and `claude -p --settings '{"disableAllHooks":true}'`.
- **Grok isolated `GROK_HOME`** (hooks/MCP/compat scanning off) + `--no-subagents`; fixes hcom agent-bus hijack of headless consults. `--no-auto-update` replaced by `GROK_DISABLE_AUTOUPDATER=1`.
- OpenCode `--pure` verified to drop config plugins; expected model `zai-coding-plan/glm-5.3` with `--variant max`.
- Harness versions dogfooded 2026-09-16: claude 2.1.273, agy 1.2.3, codex 0.154.0, grok 1.0.30, opencode 1.18.31.

## Earlier (v1.11)

- Claude consult default `opus`. agy pin `gemini-3.7-flash-high`. Grok `grok-4.6`. OpenCode `--variant max` when the resolved model contains `glm-5.3`.
- Probe reads Grok's advertised `Default model:`. agy `--output-format json`. Codex JSONL checks `error` / `turn.failed`.

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
- [Codex CLI](https://developers.openai.com/codex) — **0.170.0** verified for GPT-6.2 Astra (`npm i -g @openai/codex@latest`)
- [Cursor CLI](https://cursor.com/docs/cli/overview) — `curl https://cursor.com/install -fsS | bash`, then `cursor-agent login` (xAI slot)
- [Grok Build](https://docs.x.ai/build/overview) — optional xAI fallback, `curl -fsSL https://x.ai/cli/install.sh | bash`
- [OpenCode](https://opencode.ai/docs/cli/) — with an authed provider; set `"model"` in `~/.config/opencode/opencode.json` so headless matches your TUI default

`jq` required for Codex / Cursor / Grok / OpenCode / agy JSON parsing.

## Install

```
claude plugins install braintrust@not-my-job
```

## Refresh / dogfood / evals

```bash
bash scripts/bt_probe.sh
bash evals/run_eval.sh matrix all agy,codex,cursor,opencode
# deeper harness drift notes: skills/braintrust/references/self-improvement.md
```

## License

MIT
