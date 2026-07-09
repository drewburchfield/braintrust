# Self-Improvement Cycle

Harnesses ship weekly. This plugin drifts unless it re-verifies. Run this cycle when:

- A consult fails with a new error shape
- A CLI major/minor bumps (`claude --version`, `agy --version`, `codex --version`, `grok --version`, `opencode --version`)
- The user says "refresh braintrust", "dogfood braintrust", or "update harness docs"
- Roughly monthly even if nothing failed

## Cycle (do in order)

### 1. Capture current binary truth (local, no docs)

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

1. `scripts/bt_probe.sh` (discovery + defaults)
2. `references/cli-contracts.md` (flags, models, parse paths)
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

- [ ] Probe writes a complete `/tmp/bt_models.env`
- [ ] Every `bt_*=true` CLI returns a one-word headless ok
- [ ] SKILL + references mention no `gemini` binary path
- [ ] Default Grok model matches `grok models`
- [ ] OpenCode model matches an authed provider (`opencode auth list`)
- [ ] Version bumped; session note saved under `.braintrust/sessions/`
