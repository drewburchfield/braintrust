# Self-Improvement Cycle

Harnesses ship weekly. This plugin drifts unless it re-verifies. Run this cycle when:

- A consult fails with a new error shape
- A CLI major/minor bumps (`claude --version`, `agy --version`, `codex --version`, `grok --version`, `opencode --version`)
- The user says "refresh braintrust", "dogfood braintrust", or "update harness docs"
- Roughly monthly even if nothing failed

## Cycle (do in order)

### 1. Capture current binary truth (local, no docs)

Shell wrappers (cmux, hcom) may shadow the binaries in interactive zsh. Call them through `bash -c` or by absolute path (`~/.local/bin/<cli>`) when `--version` prints a wrapper error.

```bash
for c in claude agy codex grok opencode; do
  echo "==== $c ===="
  command -v $c && $c --version 2>&1 | head -3
  $c --help 2>&1 | head -40
done
# Subcommand help that matters
codex exec --help 2>&1 | head -80
codex review --help 2>&1 | head -40
opencode run --help 2>&1 | head -60
agy models 2>&1 | head -20
grok models 2>&1 | head -20
jq -r '.models[].slug' ~/.codex/models_cache.json 2>/dev/null   # OpenAI model catalog seen by this CLI
opencode models 2>&1 | head -40
opencode auth list 2>&1 | head -20
```

### 2. Re-run the probe

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/scripts/bt_probe.sh"
cat /tmp/bt_models.env
```

### 3. Dogfood one-word headless for every available CLI

Use the contracts in `cli-contracts.md`. Record pass/fail + latency + stderr snippets in `.braintrust/sessions/YYYY-MM-DD-dogfood.md`.

### 4. Diff against docs

Update in this order:

1. `scripts/bt_probe.sh` (discovery + defaults + isolated homes)
2. `references/cli-contracts.md` (flags, models, parse paths) and `agents/peer.md` (Claude peer model pin)
3. `references/failure-modes.md` (new rows only)
4. `skills/braintrust/SKILL.md` (orchestration defaults only; keep lean)
5. `hooks/session-start.sh` (PATH presence list)
6. `README.md` + `.claude-plugin/plugin.json` version + changelog bullet
7. Marketplace pin in `not-my-job` when releasing

### 5. Hard rules that prevent thrash

- **No Gemini CLI.** Ever. Google = agy.
- **Models come from the probe**, not from memory of last month's IDs.
- Prefer **real scripts** under `scripts/` over giant heredocs inside the skill.
- Keep SKILL.md under ~400 lines of orchestration; put encyclopedic tables in `references/`.
- When a flag is renamed, search the whole plugin for the old string before cutting a release.

### 6. Optional: official docs spot-check

| Harness | Docs entry points |
|---------|-------------------|
| Claude Code | https://code.claude.com/docs/en/headless |
| agy | https://antigravity.google/docs/cli/overview + `agy --help` |
| Codex | https://developers.openai.com/codex/noninteractive |
| Grok Build | https://docs.x.ai/build/overview |
| OpenCode | https://opencode.ai/docs/cli/ |

Treat local `--help` + dogfood as higher priority than blog posts.

## Exit criteria for a refresh

- [ ] Probe writes a complete `/tmp/bt_models.env` (includes `bt_codex_model=gpt-6-astra` when Astra works, `bt_codex_error` when it does not)
- [ ] Codex CLI ≥ 0.154.0 (`codex --version`); `~/.codex/models_cache.json` still lists `gpt-6-astra`
- [ ] Every `bt_*=true` CLI returns a one-word headless ok **from its isolated home** (no agent-bus / hcom text in the answer)
- [ ] SKILL + references mention no `gemini` binary path
- [ ] Default Grok model matches `Default model:` from `grok models` (`grok-4.6` as of 2026-09)
- [ ] agy pin is the newest `gemini-*-flash-high` in `agy models` (`gemini-3.8-flash-high` as of 2026-09)
- [ ] Claude consult model is `claude-opus-4-8[1m]` in `agents/peer.md` and the probe (haiku only for liveness); bump only when a model above Opus 5 ships
- [ ] OpenCode model matches an authed provider (`opencode auth list`) and contains `glm-5.3` (`bt_opencode_variant=max`)
- [ ] `--pure`, `GROK_HOME`, `CODEX_HOME`, and `disableAllHooks` still neutralize the hooks listed in `failure-modes.md`
- [ ] Version bumped; session note saved under `.braintrust/sessions/`
