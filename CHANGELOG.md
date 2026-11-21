# Changelog

## 1.17.0 — 2026-11-21

`peerpanel`: one command for the whole consult. Built from a review of 23 real braintrust consults (Aug 20 to Nov 16, 2026). About 85% of launched seats eventually answered, but most failures arrived as an empty file with exit 0, hosts hand-wrote launchers that CC Safety Net and the auto-mode classifier blocked, and in three consults the host's own errors reached every peer through its brief.

- **`bin/peerpanel`** (Python 3.9+ stdlib, on PATH inside Claude Code). `probe`, `ping`, `brief new/check`, `prompt`, `consult`, `status`. The name avoids `bt` and `braintrust`, which the npm `braintrust` package installs.
- **Named outcomes.** Every seat ends `ok`, `timeout`, `empty`, `connection`, `cap`, `auth`, `cli-changed`, `model`, `hijacked`, `off-task`, `error`, `skipped`, `unavailable`, `missing` or `host`. A timeout or structured error beats partial streamed text. Only `timeout`, `empty` and `connection` are retried, once; the agy retry drops to the fast model and Codex falls back to `gpt-6.2-sol` on a model error.
- **Fixed brief.** `request.md` (the user's words, verbatim), `question.md`, `sources.txt` (paths the peers open themselves), `claims.md` (host claims, labeled unverified), `context.md`, and `host-view.md` (withheld unless `--include-host-view`). `brief check` errors on missing paths or a host view inside the peers' read root, and warns on empty sources and secret-looking files. `--text-only` inlines sources with a 60 KB cap.
- **Preflight ping.** A check-code round trip using the exact consult command lines. Hard failures skip the seat; slow pings still run. The wording asks plainly, because Grok on Cursor refuses "reply with exactly this token".
- **Read-only peers**, each refusing a live write test: Codex `-s read-only`, agy `--mode plan` (print mode and `--sandbox` both let agy write; plan mode refused. `--dangerously-skip-permissions` stays, because without it headless agy denies every shell command and returns nothing; `--disable-slash-commands` would switch plan mode off), Cursor `--mode ask`, Grok `--permission-mode plan`, OpenCode `--agent plan` plus an isolated `opencode.json` that denies edit, bash and webfetch, `claude -p` without Write, Edit or Bash.
- **Run folder.** Each seat's exact prompt, answer, raw stdout/stderr, `status.json` and a `record.md` skeleton. Answers stay outside every read root until all seats finish.
- Output goes to files, so a helper process that outlives its CLI (MCP servers Cursor starts, a standalone OpenCode server) cannot hold a finished seat open; the whole process group is cleared after each call.
- Ctrl-C or SIGTERM kills every running seat's process group. `--host` leaves the calling CLI's seat out on hosts other than Claude Code. The `braintrust:peer` agent now disallows Bash too. OpenCode refuses to run if its deny config cannot be written.
- The xAI seat gets 1.5x the attempt timeout (720s by default): Grok on Cursor took 440 to 480+ seconds on a five-file review. A bus marker (`[hcom:…]`) marks an answer hijacked; prose about joining a bus only does in a short answer, so a review that discusses agent buses survives.
- Probe runs under a 300s limit (its process group is killed on timeout) with a Python `timeout` shim when macOS has neither `timeout` nor `gtimeout`; jq is checked first.
- **Skill rewritten around the CLI** (about half the length). Raw launch lines moved to `references/manual-launch.md` as a fallback. `cli-contracts.md` gains the read-only table; `failure-modes.md` gains the transcript findings.
- Evals: `evals/test_peerpanel.py` (offline unit tests) and a `peerpanel-quiz` fixture for the live runner.

## 1.16.0 — 2026-11-21

Model + harness refresh. Every peer CLI was updated to its latest release and answered a live call: claude 2.1.330, agy 1.5.14, codex 0.170.0, cursor-agent 2026.11.19, grok 1.0.92, opencode 2.3.2.

- Google pin moves to **Gemini 4 Neon High** (`gemini-4-neon-high`, added in agy 1.5.12). agy now lists three generation-4 families (Neon, Argon, Hydrogen), so `_agy_rank` scores families explicitly: Neon > Carbon > unknown > Argon > Hydrogen > Flash. Before, the tie fell to alphabetical order. `bt_agy_fast_model` stays `gemini-3.8-flash-high`. Neon XHigh exists but the pin stays at `-high`.
- Codex pin moves to **GPT-6.2 Astra** (`gpt-6.2-astra`, "most capable"); fallback `gpt-6.2-sol`. The catalog now labels `gpt-6-astra` and `gpt-6.1-sol` "previous generation". Verified on codex 0.170.0.
- **OpenCode 2.x.** 2.3 removed `run --pure` and `--variant`, so the old contract failed with `Unrecognized flag` and the probe marked OpenCode unavailable. Consults now run under an empty `XDG_CONFIG_HOME` (`$bt_opencode_config`, exported by the probe) with `OPENCODE_DISABLE_PROJECT_CONFIG=1`, `OPENCODE_DISABLE_CLAUDE_CODE=1`, `OPENCODE_DISABLE_AUTOUPDATE=1` and `--standalone`, and pass the variant inline (`-m zai-coding-plan/glm-5.3#max`). Auth in `~/.local/share/opencode` is untouched. The isolated run lists only built-in tools; the real config adds MCP tools. `run` has no `--dir`; Mode C `cd`s into the repo.
- Cursor: when the account is on the Free plan, which refuses `grok-4.7-high` (`ActionRequiredError: Model unavailable on Free`, empty stdout), the probe steps down to the same generation at `-medium` with a fresh attempt budget, and `bt_cursor_error` falls back to stderr text. The account is on Super again, so `grok-4.7-high` answers directly. Headless runs need `--trust`.
- Grok CLI answers again from the isolated `GROK_HOME` (`grok-4.7`). `~/.grok/hooks/herdr.json` joins hcom.json; the isolated home skips both.
- Claude: Opus 5.5 is still the newest Opus; Fable reference is `claude-fable-5-2`.
- Docs, eval variants, the contract-quiz rubric and the runner follow the new contracts. Codex catalog list now includes every slug.
- Eval 2026-11-21: contract-quiz on skill-current, agy (gemini-4-neon-high), codex (gpt-6.2-astra), cursor (grok-4.7-high), grok (grok-4.7), opencode (glm-5.3#max), claude (Opus 5.5) all 10/10; no hcom or agent-bus text in any answer.

## 1.15.1 — 2026-10-23

Doc-only harness refresh. Dogfooded against claude 2.1.309, agy 1.4.6 (gemini-4-argon-high), codex 0.160.1 (gpt-6-astra), cursor-agent 2026.10.22 (grok-4.7-high), opencode 1.18.34 (glm-5.3). Every documented flag is still in `--help`; every pin holds.

- Google: `agy models` and the Gemini API release feed still top out at Gemini 4 Argon (GA 2026-10-13). No newer OpenAI, xAI or Z.ai model in any catalog (no grok-4.8, no GLM-5.4).
- `cli-contracts.md` version table updated. Cursor catalog note fixed (`kimi-k2.7-code`, not `kimi-k3-*`; `cursor-grok-4.5` is high-only). Codex notes that upstream 0.161.0 defaults to `gpt-6.1-sol`; consults pass `-m`, so Astra stays the pin. agy 1.4.6 sandbox blocks `~/.docker`, `~/.kube`, `~/_netrc`.
- New claude flags recorded but not adopted: `--permission-prompts`, `--setting-sources`, `--exclude-dynamic-system-prompt-sections`; `--bg`/`--cloud`/`--desktop` are never-pass.
- agy hook check re-verified on 1.4.6: headless answers clean, no hcom/herdr text. Grok CLI still signed out (unchanged).
- Eval 2026-10-23: contract-quiz on skill-current, agy (gemini-4-argon-high), codex (gpt-6-astra), cursor (grok-4.7-high), opencode (glm-5.3) all 10/10.

## 1.15.0 — 2026-10-16

Harness + model refresh. Dogfooded against claude 2.1.301, agy 1.4.0, codex 0.160.0, cursor-agent 2026.10.14, opencode 1.18.34 (grok 1.0.46 still logged out). Every documented flag re-checked against `--help`; none removed or renamed.

- Google pin moves to **Gemini 4 Argon High** (`gemini-4-argon-high`). The probe picks the strongest `gemini-*-high` slug (newest generation, non-Flash wins a tie) and falls back to the newest Flash High, now exported as `bt_agy_fast_model` (`gemini-3.8-flash-high`). Argon took ~7s of agy time vs ~3-5s for Flash High. agy 1.4.0 dropped 3.7/3.6 Flash and 3.1 Pro.
- `claude -p` consults add **`--safe-mode`** (keeps keychain auth; drops CLAUDE.md, plugins, user skills, MCP, hooks, agents). `disableAllHooks` alone still loaded the global CLAUDE.md, ~20 MCP servers and every plugin: 62k cached tokens, 10.4s, $0.41 for a one-word answer vs 15.6k, 2.2s, $0.04 with safe mode. `--restricted --strict-mcp-config` documented as the strict text-only option. Probe liveness uses the same flags.
- agy: `--mode auto`, `--remote-control`, `remote-control`/`mic-serve` noted (never in consults). `--effort` enum lists `xhigh`/`max`, but every Gemini model tops out at `high` and a suffixed slug rejects any non-matching effort.
- Codex: `gpt-5.5` left the catalog. Documented `-p/--profile`, `--worktree`, `--approve-for-me`, `--dangerously-bypass-hook-trust` as never-pass flags (a profile layers config back in).
- Cursor: 2026.10.14 adds `--worktree`, `--plan`, `persist`/`worker`/`team`/`bedrock`; `grok-4.7-high` is still the newest Grok. Never pass `--worktree` or `--plan`.
- OpenCode: new failure row for `glm-5.3-highspeed` (not on the Coding Plan; retryable 429 loops ~80s).
- Claude: Opus 5.5 is still newest (`claude-opus-6` unrecognized). Fable reference is now `claude-fable-5-1`.
- Dogfood 2026-10-16 (one-word headless, current contracts): codex/gpt-6-astra 4.6s, agy/gemini-3.8-flash-high 5.5s, agy/gemini-4-argon-high 10.4s, claude/opus-5.5 5.5s (2.2s with `--safe-mode`), opencode/glm-5.3 9.3s, cursor/grok-4.7-high 14.3s, all pass with no hcom text; grok fails "Not signed in".
- Evals: contract-quiz 2026-10-18 on skill-current: agy (Argon High), codex, cursor (grok-4.7-high), opencode all 10/10.

## 1.14.0 — 2026-10-07

Harness refresh and doc catch-up. Dogfooded against claude 2.1.292, agy 1.3.1 (gemini-3.8-flash-high), codex 0.160.0 (gpt-6-astra), cursor-agent 2026.10.01 (grok-4.7-high), opencode 1.18.34 (glm-5.3). Every documented flag re-checked against `--help`.

- Codex fallback is `gpt-6.1-sol` (new catalog priority 1, "latest workhorse"). `gpt-6-astra` stays primary as the frontier model. Verified CLI is 0.160.0.
- agy now loads hcom and herdr hooks from `~/.gemini/config/hooks.json` (installed 2026-09-23) and has no switch to skip them. Docs drop the "no hook surface" claim. A headless run on 2026-10-07 answered cleanly and registered no hcom agent. New failure-mode row: skip the Google slot if bus chatter appears.
- Cursor: `cli-contracts.md` gains the full contract (it had none). Noted the new `--sandbox`, `--plugin-dir`, `--auto-review` flags and that `~/.cursor/plugins` may load; never pass `--plugin-dir`.
- Grok CLI is optional and marked unverified since 1.0.30 (not in active use; logged out on 1.0.46). Every reference now agrees on the `grok-4.7` fallback.
- References catch up with 1.13.0: Opus 5.5 in `cli-contracts.md`, `capability-packaging.md`, `failure-modes.md`, `self-improvement.md`.
- Doc fallbacks for isolated homes use `${TMPDIR:-/tmp}` to match the probe (macOS `$TMPDIR` is not `/tmp`).
- Manifests, README, SessionStart hook description, and eval rubric list Cursor. Self-improvement checklist adds hook-surface and stale-string checks.

## 1.13.0 — 2026-09-22

Cursor CLI joins as the xAI path, and Claude moves to Opus 5.5. Dogfooded against claude 2.1.280, agy (gemini-3.8-flash-high), codex 0.155.1, cursor-agent 2026.09.18, opencode (glm-5.3).

- xAI slot: Cursor CLI (`cursor-agent`) first, Grok CLI second. The probe sets `bt_xai_via` so a consult runs one xAI voice. Cursor pins the newest `grok-X.Y-high` from `--list-models` (`grok-4.7-high` today) and runs `--mode ask` (read-only).
- Cursor uses the normal login. Guardrails: `--mode ask` (read-only, no shell, so it cannot join the hcom bus), no `--approve-mcps`, cmux hooks off via `CMUX_CURSOR_HOOKS_DISABLED=1`, run from `$TMPDIR`. Cursor has no switch for `~/.cursor/hooks.json` or user rules, so the hcom notice line and rules still reach context.
- Claude consult model is `claude-opus-5-5[1m]` for `braintrust:peer` and `claude -p`.
- Grok CLI fallback default is `grok-4.7`.
- Evals: `cursor` peer in the runner; contract-quiz Q4 asks for the Cursor contract. 2026-09-22 contract-quiz on skill-current: agy, codex, cursor (grok-4.7-high), opencode, claude (Opus 5.5) all 10/10.

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
