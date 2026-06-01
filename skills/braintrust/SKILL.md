---
name: braintrust
description: Orchestrate other AI CLIs (Antigravity/agy, Gemini, Codex, Grok, Claude Code) for second opinions, research, codebase analysis, design review, security audits, and parallel research
---

# Braintrust

Consult your AI braintrust - the other AI CLIs available in your environment - for second opinions, research, and codebase analysis.

> **Important:** Run ALL braintrust CLI invocations (including health checks and consultations) as background tasks using `run_in_background: true`. This allows monitoring progress instead of blocking.

## Default Behavior: Consult EVERY AVAILABLE CLI

**Unless the user explicitly requests a specific model or narrower scope, ALWAYS consult every braintrust CLI the probe marks installed AND authenticated, in parallel.** A full consult is up to four independent voices: **Claude**, **Google AI** (agy, or gemini), **Codex**, and **Grok**.

Membership is decided by availability, not by your judgement: if a CLI is installed and authenticated, it's in. If it isn't, skip it and note the gap. Do not drop an available CLI to "save time" — multi-model coverage is the entire point; each model catches what the others miss.

> The Google AI slot is **one voice**, not two. agy and gemini are two access paths to Google's models (see "agy vs Gemini: Two Different Model Paths"). Use **agy when available** (it runs your best account-tier model); fall back to **gemini** only when agy is unavailable. Never launch both for the same query.

**Launch all available members in a single parallel batch using multiple tool calls in one response:**

> **First call in a session?** Run the model probe (see "Model Discovery" section) first. It takes ~30-90s and decides who's in (installed + authenticated) and which models to use. If `/tmp/bt_models.env` already exists from an earlier call, skip the probe.

1. **Claude** (always available from Claude Code): Use the Task tool with `subagent_type: "general-purpose"` and `run_in_background: true`
2. **Google AI** — use exactly one path, in this priority order:
   - **Antigravity/agy** (if `bt_agy_available=true`): Use the Bash tool with `run_in_background: true`:
     ```bash
     agy --print "$QUERY" --dangerously-skip-permissions 2>/dev/null
     ```
     > **agy note:** No `-m` model flag (runs your Antigravity account-tier model). No `@path` file context — inline file content in the prompt or pipe via stdin. No output format control. Cold start can take 30-60s; give it time.
   - **Gemini** (only if `bt_agy_available=false` and `bt_gemini_available=true`): Use the Bash tool with `run_in_background: true`:
     ```bash
     source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-3.1-pro-preview"
     gemini -p "$QUERY" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null
     ```
     > **gemini is the power-user path.** Supports explicit model selection (`-m`), `@path` file context, and output format control. Use when `agy` is unavailable or when you need model-level control.
3. **Codex** (if `bt_codex_available=true`): Use the Bash tool with `run_in_background: true`:
   ```bash
   codex exec --ephemeral -s read-only --json --skip-git-repo-check "$QUERY" < /dev/null 2>/dev/null > /tmp/codex.json
   ```

   > **Always include `< /dev/null`.** Codex's `exec "prompt"` reads stdin by default and hangs forever when the harness pipes to it. This is the single most common reason Codex appears broken. See "Common Codex Failure Modes" below.
4. **Grok** (if `bt_grok_available=true`): Use the Bash tool with `run_in_background: true`:
   ```bash
   source /tmp/bt_models.env 2>/dev/null || bt_grok_model="grok-build"
   grok -p "$QUERY" -m "$bt_grok_model" --output-format json 2>/dev/null | jq -r '.text'
   ```

   > **Grok note:** `grok-build` is Grok 4.3 and needs a Grok subscription. The `json` format returns `{"text": ..., "thought": ...}`; parse the answer with `jq -r '.text'`. See "Common Grok Failure Modes" below.

> **Skip unavailable CLIs.** If the probe marked a CLI as unavailable or unauthenticated, do not launch it. Note the gap in your synthesis instead.

Present each model's findings to the user as they arrive. After all available members respond, synthesize the findings and save a session file.

**Only skip an available model if:**
- The user explicitly asks for a specific model (e.g., "ask Gemini about...")
- A model fails and diagnostics show it's unavailable
- The task is a trivial single-fact lookup (rare)

**Do NOT rationalize using fewer models.** Thoughts like "Gemini is better for this" or "three should be enough" are wrong - consult every authenticated CLI unless directed otherwise.

---

## Why Multi-Model Collaboration Works

Each AI model has different training data, reasoning patterns, and blind spots. Research and developer experience consistently shows:

- **When a model introduces a bug, it struggles to fix it** - but a different model often spots it instantly
- **Combined approaches outperform individual models** on complex tasks
- **Claude excels at detailed, conversational coding work; Gemini provides strategic overview**
- **Different perspectives catch edge cases one model would miss**

The result feels like "working with a small, experienced development team" rather than a single assistant.

## Core Concept

**Every other CLI in your environment is a braintrust member.** How you call each depends on where you're running:

| You Are In | Your Braintrust | How to Call Claude |
|------------|-----------------|-------------------|
| Claude Code | Google AI (agy or gemini) + Codex + Grok + Claude | **Task tool** with subagent (the CLI blocks nested sessions) |
| Gemini CLI | Claude + Codex + Grok | `claude -p "query" --model sonnet --output-format json` |
| Antigravity (agy) | Claude + Codex + Grok | `claude -p "query" --model sonnet --output-format json` |
| Codex CLI | Claude + Google AI + Grok | `claude -p "query" --model sonnet --output-format json` |
| Grok CLI | Claude + Google AI + Codex | `claude -p "query" --model sonnet --output-format json` |

### Calling Claude from Claude Code

**You CANNOT run `claude -p` from within Claude Code.** The CLI detects nested sessions and blocks them with: "Claude Code cannot be launched inside another Claude Code session."

Instead, use the Task tool to spawn a separate Claude subagent:

```
Use the Task tool with `subagent_type: "general-purpose"` for research and code review,
or `subagent_type: "Explore"` for quick codebase searches.
This spawns an independent Claude session with its own context.
```

This means **every installed model is reachable** regardless of which harness you're in.

## Prerequisites

**Skip health checks by default** - just try to use the braintrust. Only run diagnostics if a consultation fails.

**If a CLI fails**, run these to diagnose:

```bash
# Diagnostic health checks (only run if needed)
# Note: Claude health check must run outside Claude Code (nested sessions blocked)
source /tmp/bt_models.env 2>/dev/null || { bt_gemini_fast="gemini-3-flash-preview"; bt_grok_model="grok-build"; }
agy --print "say ok" --dangerously-skip-permissions 2>/dev/null | grep -qi "ok" && echo "agy: OK" || echo "agy: FAILED (cold start? retry once)"
gemini -p "say ok" -m "$bt_gemini_fast" --approval-mode yolo --no-sandbox -o text 2>/dev/null | grep -qi "ok" && echo "Gemini: OK" || echo "Gemini: FAILED"
codex exec --ephemeral -s read-only --json --skip-git-repo-check "test" < /dev/null 2>/dev/null | head -5 && echo "Codex: OK" || echo "Codex: FAILED"
grok -p "say ok" -m "$bt_grok_model" --output-format json 2>/dev/null | jq -r '.text' | grep -qi "ok" && echo "Grok: OK" || echo "Grok: FAILED (run: grok login)"
```

When running from Claude Code, Claude itself is always available via the Task tool. No health check needed.

**If missing, install:**
- Claude: `npm install -g @anthropic-ai/claude-code`
- Gemini: `npm install -g @google/gemini-cli` (also available via `brew install gemini-cli`)
  > **Sunset notice:** Gemini CLI free-tier/OAuth access ends **2026-06-18**. Users on paid Gemini API keys or Google Cloud enterprise licenses are unaffected. After that date, free-tier users should switch to `agy`.
- Antigravity CLI (agy): `curl -fsSL https://antigravity.google/cli/install.sh | bash` — Go binary, no npm package. **Primary Google AI path.** Use `gemini` as fallback when `agy` is unavailable or when you need explicit model selection.
- Codex: `npm install -g @openai/codex` (also available via `brew install --cask codex`)
- Grok (Grok Build): `curl -fsSL https://x.ai/cli/install.sh | bash` (Windows PowerShell: `irm https://x.ai/cli/install.ps1 | iex`). Self-updating binary at `~/.grok/bin/grok`. Authenticate with `grok login` (OAuth) or set `XAI_API_KEY` from [console.x.ai](https://console.x.ai). The default `grok-build` model (Grok 4.3) **requires an active Grok subscription**.

**Required utilities:** `jq` is used for parsing Codex JSONL output and Grok JSON output. Pre-installed on macOS. On Linux: `apt install jq` or `brew install jq`. Gemini uses `-o text` which needs no parsing; agy returns plain text.

### Common Codex Failure Modes

If Codex fails, check these in order:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `You've hit your usage limit` | ChatGPT free/Plus rate limit | Wait for reset or switch to API key auth with `CODEX_API_KEY` |
| `failed to stat skills entry` (stderr) | Broken symlink in `~/.codex/skills/` | Remove the dead symlink. Non-blocking but noisy. |
| Hangs on startup | MCP servers in `~/.codex/config.toml` failing to initialize | Check `[mcp_servers]` section. Servers with `required = true` cause immediate exit. Remove or fix broken servers. |
| `not a git repository` | Codex requires a git repo by default | Add `--skip-git-repo-check` to exec commands |
| `missing YAML frontmatter` (stderr) | Codex loading incompatible skill files | Non-blocking stderr noise. Safe to ignore. |
| Hangs forever with `Reading additional input from stdin...` | Codex `exec "prompt"` reads stdin by default. If the harness pipes anything to stdin (or leaves it open), Codex waits or appends it as a `<stdin>` block. | **Always close stdin with `< /dev/null`.** Example: `codex exec --ephemeral -s read-only --json --skip-git-repo-check "$QUERY" < /dev/null 2>/dev/null`. This is the #1 cause of Codex appearing "broken" inside Claude Code. |

**MCP server note:** Codex loads all configured MCP servers on every `exec` call. If you have heavy servers (Playwright, Docker, etc.) in `~/.codex/config.toml`, they add startup latency. For braintrust consultations, Codex doesn't need MCP servers since it's just answering a question.

### Common Gemini Failure Modes

If Gemini fails, check these in order:

| Symptom | Cause | Fix |
|---------|-------|-----|
| Empty response (exit 0) | Upstream bug #24290: retry logic only applies to Gemini 2 models. 3.x models silently drop `InvalidStreamError`. | Retry once. If still empty, fall back to `gemini-2.5-pro`. |
| 429 rate limit / `limit: 0` | Free-tier now restricted to Flash models. Pro models need a billing account linked in AI Studio. | Use `gemini-2.5-flash` or link billing at aistudio.google.com. |
| Model 404 | Bare model names without `-preview` suffix on 3.x models. | Always use `-preview` suffix (e.g., `gemini-3.1-pro-preview`). |
| Infinite retry / hung process | `gemini-3.1-pro-preview` capacity issues on some auth tiers (#23762). | The probe catches this via timeout. Add `timeout 120` to consultation calls. |
| Exit code 53 | Turn limit exceeded (`maxSessionTurns` in `~/.gemini/settings.json`). | Increase `maxSessionTurns` or avoid `-o json` which triggers extra turns. |
| Hangs waiting for tool approval | Model tries to use a tool in headless mode but can't get approval. | Always use `--approval-mode yolo` in headless calls. |
| Slow startup | Extensions loading on every invocation. | The `--no-sandbox` flag helps. If still slow, consider `--extensions ""`. |
| `FatalTurnLimitedError` with `-o json` | `-o json` triggers internal tool use that counts against turn limits. | Use `-o text` instead (already our default). |

**Free-tier note:** As of March 2026, Google OAuth free-tier users only get Flash-level models. Pro models require either a Google One AI Pro subscription with billing linked, or an explicit `GEMINI_API_KEY` with billing enabled. The probe tries `gemini-3.1-pro-preview` first and falls back through `gemini-2.5-pro` automatically if the newer model doesn't respond.

**Sunset notice (2026-06-18):** Gemini CLI stops serving requests for free/OAuth, Google AI Pro, and Google AI Ultra users on June 18, 2026. Enterprise (Gemini Code Assist Standard/Enterprise) and paid Gemini API key users are unaffected. After this date, free-tier users should switch to `agy` (Antigravity CLI) — the probe handles this automatically via `bt_agy_available`.

### Common Antigravity (agy) Failure Modes

agy is a VS Code-fork-based CLI: `agy --print` spins up a headless Antigravity editor-agent backend that talks to a relay. It is **reliable warm (~4-5s)** but has occasional cold-start and transient-empty behavior. Its failures look like "agy is unavailable" but are almost always transient — retrying usually fixes them. (Observed directly: not a rate limit, no error on stderr; just an occasional empty or slow first call.)

| Symptom | Cause | Fix |
|---------|-------|-----|
| Times out on the first call, fast (~5s) on the next | **Cold start.** The first agy invocation spins up the editor-agent backend and can exceed a short timeout; warm calls return in ~5s. | Give the probe/consult a generous timeout (≥45s) plus one retry. **This is the #1 cause of agy↔gemini "thrashing":** a short-timeout false-negative marks agy unavailable, silently flips the Google AI slot to gemini, then the next session agy is warm and wins again. |
| Empty stdout, exit 0 | Transient backend non-response (relay hiccup). No stderr, no error message. | Retry once — the probe does this automatically. The next call almost always succeeds. |
| No model control | agy has **no `-m` flag** by design — it runs your Antigravity account-tier model. | If you need a specific model, use `gemini -m` instead. See "agy vs Gemini: Two Different Model Paths". |
| Won't report its own model name | agy returns empty for "what model are you" style identity prompts. | Expected. Don't probe agy with identity questions; use a concrete task prompt. |

> **Practical rule:** treat a single empty/timed-out agy result as transient, not terminal. Retry once with a ≥45s timeout before falling back to gemini. Don't conclude agy is "down" from one bad call.

### Common Grok Failure Modes

If Grok fails, check these in order:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `A subscription is required` / access gate | `grok-build` (Grok 4.3) requires an active Grok subscription (SuperGrok). | Subscribe at grok.com, or set `XAI_API_KEY` from console.x.ai for API-key auth. |
| `run grok login` / auth error | Not signed in. | Run `grok login` (OAuth) or export `XAI_API_KEY`. |
| Empty `.text` from `jq` | Wrong output format, or the answer is under a different field. | Use `--output-format json` and parse `jq -r '.text'`. The `thought` field holds reasoning, not the answer. |
| Hangs / interactive UI opens | Missing `-p`/`--single`. Without it, grok launches its TUI. | Always pass `-p "$QUERY"` for headless use. |
| Model 404 | Unknown model id. | Valid ids: `grok-build` (default, Grok 4.3) and `grok-composer-2.5-fast`. Run `grok models` to list. |
| A `cache/projects.json` appears in your repo | grok writes a per-project session registry into its **working directory** (observed: a bare `grok -p` inside a repo creates `./cache/projects.json`). | Harmless — safe to delete. To keep it out of the repo, add `cache/` to `.gitignore`, or pass `--cwd <scratch-dir>` (verified to keep the repo clean). |

## Braintrust Defaults

**Always use explicit capable models.** CLI headless modes auto-route to weaker models when called without specifying a model. Start with the best model and fall back if it fails.

| CLI | Default Command | Fast Option |
|-----|-----------------|-------------|
| **Claude** (from Claude Code) | Task tool with `subagent_type: "general-purpose"` | Task tool with `model: "haiku"` |
| **Claude** (from other CLIs) | `claude -p "query" --model sonnet --output-format json` | `--model haiku` |
| **Gemini** | Uses `$bt_gemini_model` from model probe (see below) | Uses `$bt_gemini_fast` from model probe |
| **Antigravity (agy)** | `agy --print "$QUERY" --dangerously-skip-permissions 2>/dev/null` (**primary** Google AI path) | N/A (no model flag) |
| **Codex** | `codex exec --ephemeral -s read-only --json --skip-git-repo-check "query" < /dev/null 2>/dev/null` | N/A |
| **Grok** | `grok -p "query" -m grok-build --output-format json 2>/dev/null \| jq -r '.text'` | `-m grok-composer-2.5-fast` |

### Gemini Standard Flags

**Every headless Gemini call must include these flags.** They prevent silent hangs and unnecessary overhead:

```bash
gemini -p "$QUERY" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null
```

| Flag | Why |
|------|-----|
| `--approval-mode yolo` | Prevents Gemini from hanging when it wants to use a tool and waits for approval that never comes in headless mode |
| `--no-sandbox` | Skips sandbox initialization overhead. Braintrust queries are read-only consultations, no sandboxing needed. |
| `-o text` | Avoids `FatalTurnLimitedError` with `-o json` when `maxSessionTurns: 1`. Text needs no parsing. |
| `2>/dev/null` | Suppresses extension/MCP loading noise on stderr |

All Gemini examples in this file assume these flags. When you see a short example like `gemini -p "query" -m "$bt_gemini_model" -o text 2>/dev/null`, always add `--approval-mode yolo --no-sandbox` in the actual command.

### agy vs Gemini: Two Different Model Paths

**`agy` and `gemini` are not interchangeable.** They are two different ways to reach Google's models, with different models behind each. They fill **one** Google AI slot in the braintrust — pick one per query (agy preferred), never both. Confusing them is what makes the model "thrash" between the two.

| | **Antigravity CLI (`agy`)** | **Gemini CLI (`gemini`)** |
|---|---|---|
| **Role** | **Primary** Google AI path | **Fallback** / power-user path |
| **Model selection** | **None.** No `-m` flag. Runs your Antigravity **account-tier** model (a high-tier Gemini 3.x on paid Antigravity; a Flash-class model on free). You cannot pin a specific model. | **Explicit.** `-m gemini-3.1-pro-preview`, `-m gemini-2.5-pro`, etc. You choose the exact model. |
| **File context** | None. Inline file content in the prompt or pipe via stdin. | `@path` includes (e.g. `-p "@src/ review this"`), `-a` for all files. |
| **Output format** | Plain text only. | `-o text` (use this), `-o json`, `-o stream-json`. |
| **Headless flag** | `--print` / `-p`, with `--dangerously-skip-permissions` | `-p`, with `--approval-mode yolo --no-sandbox -o text` |
| **Cold start** | Slow first call; sensitive to concurrency (see "Common agy Failure Modes"). | Faster, but 3.x can return intermittent empty (#24290). |
| **Best for** | The default Google opinion — runs your best account-tier model with zero config. | When you need a **specific** model, `@path` file context, or output-format control; and after the 2026-06-18 Gemini free-tier sunset, when `agy` is unavailable. |

**Decision rule (this is what the probe encodes):**

1. If `bt_agy_available=true` → use **agy**. It runs your best account-tier model and needs no model id.
2. Else if `bt_gemini_available=true` → use **gemini** with `$bt_gemini_model` (newest-best, currently `gemini-3.1-pro-preview`).
3. Else → skip the Google AI slot and note the gap.

Never run both agy and gemini for the same query — they're the same vendor's models and would double-count one voice.

> **Model note (verified by dogfooding, 2026-06):** on a current Google account, `gemini-3.1-pro-preview` and `gemini-3-flash-preview` were **2/2 reliable**, while `gemini-2.5-pro` was only **1/2** (one call timed out). That's why the probe now tries **3.1-pro-preview first** and treats 2.5-pro as a fallback — the reverse of older guidance. Re-verify periodically; model reliability shifts with account tier and capacity.

### Model Discovery (Run Once Per Session)

**Model names change frequently.** Instead of hardcoding model IDs, run this probe at the start of each braintrust session to discover the best available models for each CLI. Cache the results in `/tmp/bt_models.env` and source them for all subsequent calls.

```bash
cat > /tmp/bt_probe.sh << 'PROBE'
#!/bin/bash
# Braintrust model probe - discovers installed + AUTHENTICATED CLIs and best models.
#
# Design (this is what fixes the agy<->gemini "thrashing"):
#  * Runs all four CLI checks in PARALLEL, so a slow/cold CLI never blocks the others.
#  * Per CLI: attempt 1 absorbs cold start; a *fast empty* (exit != 124) triggers ONE
#    warm-up retry, but a *timeout* (exit 124) is treated as down (no retry) to bound time.
#  * Gemini tries newest-best FIRST (gemini-3.1-pro-preview), 2.5-pro only as fallback.
# Typical run ~25-45s; worst case ~one timeout window. Cache to /tmp/bt_models.env.

echo "--- Braintrust Model Probe (parallel) ---"
D=$(mktemp -d "${TMPDIR:-/tmp}/bt_probe.XXXXXX")

if command -v timeout &>/dev/null; then TO="timeout"
elif command -v gtimeout &>/dev/null; then TO="gtimeout"
else TO=""; fi
rt() { if [ -n "$TO" ]; then $TO "$@"; else shift; "$@"; fi; }   # exit 124 == timed out

# --- Antigravity CLI (agy) - PRIMARY Google AI path (no -m; account-tier model) ---
probe_agy() {
  echo "bt_agy_available=false" > "$D/agy.env"
  command -v agy &>/dev/null || { echo "Antigravity (agy): not installed" > "$D/agy.log"; return; }
  local out rc
  for a in 1 2; do
    out=$(rt 50 agy --print "Reply with the single word: ok" --dangerously-skip-permissions 2>/dev/null | head -5); rc=${PIPESTATUS[0]}
    [ -n "$out" ] && { echo "bt_agy_available=true" > "$D/agy.env"; break; }
    [ "$rc" = "124" ] && break   # timed out -> treat as down, don't retry
  done
  grep -q true "$D/agy.env" && echo "Antigravity (agy): available [PRIMARY Google AI]" > "$D/agy.log" \
    || echo "Antigravity (agy): empty/timeout after warm-up retry -> using gemini fallback" > "$D/agy.log"
}

# --- Gemini - FALLBACK Google AI path. Newest-best first; retry-on-empty per model. ---
probe_gemini() {
  printf 'bt_gemini_available=false\nbt_gemini_model=\nbt_gemini_fast=\n' > "$D/gemini.env"
  command -v gemini &>/dev/null || { echo "Gemini: not installed" > "$D/gemini.log"; return; }
  gp() { local m="$1" o rc; for a in 1 2; do o=$(rt 45 gemini -p "Reply with the single word: ok" -m "$m" --approval-mode yolo --no-sandbox -o text 2>/dev/null); rc=$?; echo "$o" | grep -qi ok && return 0; [ "$rc" = "124" ] && return 1; done; return 1; }
  local model="" fast=""
  for m in gemini-3.1-pro-preview gemini-2.5-pro; do gp "$m" && { model="$m"; break; }; done
  for m in gemini-3-flash-preview gemini-2.5-flash; do gp "$m" && { fast="$m"; break; }; done
  if [ -n "$model" ]; then
    printf 'bt_gemini_available=true\nbt_gemini_model=%s\nbt_gemini_fast=%s\n' "$model" "$fast" > "$D/gemini.env"
    echo "Gemini: $model (fast: $fast) [fallback]" > "$D/gemini.log"
  else
    echo "Gemini: found but no models responded" > "$D/gemini.log"
  fi
}

# --- Codex (loads MCP servers + skills on every exec; allow for slow cold start) ---
probe_codex() {
  echo "bt_codex_available=false" > "$D/codex.env"
  command -v codex &>/dev/null || { echo "Codex: not installed" > "$D/codex.log"; return; }
  local out rc
  for a in 1 2; do
    out=$(rt 60 codex exec --ephemeral -s read-only --json --skip-git-repo-check "Reply with the single word: ok" < /dev/null 2>/dev/null | jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' 2>/dev/null); rc=${PIPESTATUS[0]}
    [ -n "$out" ] && [ "$out" != "null" ] && { echo "bt_codex_available=true" > "$D/codex.env"; break; }
    [ "$rc" = "124" ] && break
  done
  grep -q true "$D/codex.env" && echo "Codex: available" > "$D/codex.log" || echo "Codex: empty/timeout after warm-up retry" > "$D/codex.log"
}

# --- Grok (Grok Build / Grok 4.3; grok-build needs a Grok subscription) ---
probe_grok() {
  printf 'bt_grok_available=false\nbt_grok_model=grok-build\nbt_grok_fast=grok-composer-2.5-fast\n' > "$D/grok.env"
  command -v grok &>/dev/null || { echo "Grok: not installed" > "$D/grok.log"; return; }
  local out rc
  for a in 1 2; do
    out=$(rt 50 grok -p "Reply with the single word: ok" -m grok-build --output-format json 2>/dev/null | jq -r '.text' 2>/dev/null); rc=${PIPESTATUS[0]}
    [ -n "$out" ] && [ "$out" != "null" ] && { printf 'bt_grok_available=true\nbt_grok_model=grok-build\nbt_grok_fast=grok-composer-2.5-fast\n' > "$D/grok.env"; break; }
    [ "$rc" = "124" ] && break
  done
  grep -q "bt_grok_available=true" "$D/grok.env" && echo "Grok: available (grok-build = Grok 4.3)" > "$D/grok.log" || echo "Grok: empty/unauthenticated (run: grok login)" > "$D/grok.log"
}

probe_agy & probe_gemini & probe_codex & probe_grok &
wait

cat "$D"/agy.log "$D"/gemini.log "$D"/codex.log "$D"/grok.log 2>/dev/null
echo "Claude: available (via Task tool)"   # always available via Task tool from Claude Code

set -a; . "$D/agy.env"; . "$D/gemini.env"; . "$D/codex.env"; . "$D/grok.env"; set +a
cat > /tmp/bt_models.env << EOF
bt_gemini_model=${bt_gemini_model:-gemini-3.1-pro-preview}
bt_gemini_fast=${bt_gemini_fast:-gemini-3-flash-preview}
bt_gemini_available=${bt_gemini_available:-false}
bt_agy_available=${bt_agy_available:-false}
bt_codex_available=${bt_codex_available:-false}
bt_grok_available=${bt_grok_available:-false}
bt_grok_model=${bt_grok_model:-grok-build}
bt_grok_fast=${bt_grok_fast:-grok-composer-2.5-fast}
EOF
rm -rf "$D"
echo "--- Results cached to /tmp/bt_models.env ---"
cat /tmp/bt_models.env
PROBE
chmod +x /tmp/bt_probe.sh && bash /tmp/bt_probe.sh
```

After the probe runs, use the discovered models in all commands:

```bash
# Source at the start of each Bash tool call that invokes Gemini or Codex
source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-3.1-pro-preview"
```

**Graceful degradation rules:**
- **Google AI is one slot.** Use `agy` if `bt_agy_available=true`; fall back to `gemini` (with `$bt_gemini_model`) only if `bt_agy_available=false` and `bt_gemini_available=true`. Never run both for the same query.
- If both `bt_agy_available=false` and `bt_gemini_available=false`, skip Google AI entirely and note the gap.
- If `bt_codex_available=false`, skip Codex and note it in the synthesis.
- If `bt_grok_available=false`, skip Grok and note it (likely not installed or not subscribed — `grok login`).
- Claude is always available via the Task tool when running in Claude Code.
- If only one CLI is available, run it alone and note the limited coverage.
- **Never let a single CLI failure block the entire braintrust consultation.**
- A single empty/timed-out result is **transient** (especially for agy and gemini 3.x). The probe already retries; at consult time, retry once before declaring a CLI down.

### Handling Errors During Consultation

Even after the probe, a model can fail mid-consultation (quota, rate limit, transient error). Wrap every CLI call to detect and report failures:

```bash
# Gemini with error detection and retry
source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-3.1-pro-preview"
gemini_response=$(timeout 120 gemini -p "$QUERY" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null)
gemini_exit=$?
if [ $gemini_exit -eq 124 ]; then
  echo "GEMINI_FAILED: timed out after 120s"
elif [ $gemini_exit -eq 53 ]; then
  echo "GEMINI_FAILED: turn limit exceeded (check maxSessionTurns in ~/.gemini/settings.json)"
elif [ -z "$gemini_response" ]; then
  # Retry once: gemini-3.x has an upstream bug (#24290) where empty responses happen intermittently
  gemini_response=$(timeout 120 gemini -p "$QUERY" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null)
  if [ -z "$gemini_response" ]; then
    echo "GEMINI_FAILED: empty response after retry (check model availability or rate limits)"
  else
    echo "$gemini_response"
  fi
else
  echo "$gemini_response"
fi

# Codex with error detection (CRITICAL: always close stdin AND redirect stderr)
# - `< /dev/null` prevents stdin hang (Codex reads stdin even when a prompt arg is passed)
# - `2>/dev/null` prevents stderr noise from corrupting the JSONL stream
codex exec --ephemeral -s read-only --json --skip-git-repo-check "$QUERY" < /dev/null 2>/dev/null > /tmp/codex.json
codex_response=$(jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' /tmp/codex.json 2>/dev/null)
if [ -z "$codex_response" ] || [ "$codex_response" = "null" ]; then
  echo "CODEX_FAILED: empty or unparseable response"
else
  echo "$codex_response"
fi

# agy with warm-up retry (transient empties are common; a timeout means cold start)
agy_response=$(timeout 90 agy --print "$QUERY" --dangerously-skip-permissions 2>/dev/null)
if [ -z "$agy_response" ]; then
  agy_response=$(timeout 90 agy --print "$QUERY" --dangerously-skip-permissions 2>/dev/null)  # one retry warms it up
  [ -z "$agy_response" ] && echo "AGY_FAILED: empty after retry (fall back to gemini)" || echo "$agy_response"
else
  echo "$agy_response"
fi

# Grok with error detection (parse .text; .thought holds reasoning, not the answer)
source /tmp/bt_models.env 2>/dev/null || bt_grok_model="grok-build"
grok_exec_out=$(timeout 120 grok -p "$QUERY" -m "$bt_grok_model" --output-format json 2>/dev/null)
grok_response=$(echo "$grok_exec_out" | jq -r '.text' 2>/dev/null)
if [ -z "$grok_response" ] || [ "$grok_response" = "null" ]; then
  echo "GROK_FAILED: empty/unauthenticated (run: grok login; grok-build needs a subscription)"
else
  echo "$grok_response"
fi
```

> **Codex blank output fix:** Codex writes skill-loading noise and warnings to stderr. If stderr is not redirected with `2>/dev/null`, it corrupts the JSONL stream and `jq` silently returns nothing. **Always use `2>/dev/null`** when piping Codex output.
>
> **Grok parsing:** `--output-format json` returns `{"text": "...", "thought": "...", "stopReason": ...}`. Parse the answer with `jq -r '.text'`. The `plain` format prints the answer directly with no parsing, but `json` is safer for capturing into a variable.

### Model Fallback Chains

If a model returns an error (404, quota, etc.), fall back to the next model in the chain. The probe handles Gemini automatically. For manual fallback:

| CLI | Primary | Fallback 1 | Fallback 2 |
|-----|---------|------------|------------|
| **Claude** | `opus` | `sonnet` | `haiku` |
| **Gemini** | `gemini-3.1-pro-preview` (newest-best) | `gemini-2.5-pro` | N/A |
| **Gemini (fast)** | `gemini-3-flash-preview` | `gemini-2.5-flash` | N/A |
| **Codex** | (default, currently gpt-5.4) | N/A | N/A |
| **Grok** | `grok-build` (Grok 4.3) | `grok-composer-2.5-fast` | N/A |

> **Gemini ordering reversed (verified 2026-06):** the probe now tries `gemini-3.1-pro-preview` first. Dogfooding found 3.1-pro-preview and 3-flash-preview were 2/2 reliable on a current account while `gemini-2.5-pro` was 1/2 — so 2.5 is now the fallback, not the primary. The per-model retry-on-empty in the probe handles the intermittent #24290 empty-response case.
>
> **Gemini model naming:** All 3.x models require `-preview` suffix. Bare names return 404. The 3.1 generation has Pro and Flash Lite only (no regular Flash). The best fast model is `gemini-3-flash-preview` (3.0 generation). The probe handles fallbacks automatically.

### Codex Model Aliases

When the user requests a model by shorthand, map it before passing to `--model`:

| Alias | Resolves To | Auth Required | Notes |
|-------|-------------|---------------|-------|
| `spark` | `gpt-5.3-codex-spark` | ChatGPT Pro or API key | Research preview, fast |
| `mini` | `gpt-5.4-mini` | ChatGPT Plus/Pro or API key | 70% cheaper, good for simple lookups |

Leave `--model` unset by default (uses gpt-5.4). Only add it when the user explicitly requests a model or when the task is a trivial lookup (use `mini`).

> **Auth note:** Model selection with `--model` works with both ChatGPT subscription auth and API key auth. However, not all models are available on all subscription tiers. If a model returns an auth or availability error, fall back to the default (gpt-5.4).

### Codex Sandbox Modes

All braintrust Codex calls default to `--ephemeral -s read-only` because consultations don't need to persist sessions or write files.

| Mode | Flag | When to Use |
|------|------|-------------|
| **Read-only** (default) | `-s read-only` | Questions, research, reviews, second opinions |
| **Write** | `-s workspace-write` | Only when the user explicitly asks Codex to make changes |
| **Full access** | `-s danger-full-access` | Never use in braintrust consultations |

### Codex Code Review

For code review specifically, use the dedicated `codex exec review` subcommand instead of crafting a review prompt. It auto-reads git diffs:

```bash
# Review uncommitted changes (staged + unstaged diffs only)
codex exec review --uncommitted

# Review branch against base
codex exec review --base main

# Review a specific commit
codex exec review --commit <SHA>
```

These are read-only by design. The output is plain text (not JSONL), so no `jq` parsing needed.

> **Limitation:** `exec review --uncommitted` only sees tracked file diffs. Brand-new untracked files are invisible to it. If the user has new files, either stage them first (`git add`) or use a standard consultation prompt that includes the file contents instead.

## Handling Braintrust Results

**Never auto-fix review findings.** After presenting review output from any model, STOP. Do not make code changes. Do not fix issues. Ask the user which findings, if any, they want addressed. This applies to all models (Claude subagent, Gemini, Codex).

Auto-applying suggestions defeats the purpose of a second opinion. The user should evaluate the findings and decide what to act on.

**Preserve evidence boundaries.** If a model marked something as an inference, uncertainty, or hypothesis, keep that distinction when presenting findings. Do not upgrade guesses to facts.

**If Codex returns structured JSON** (from `--output-schema`), present the parsed structure. If it returns malformed output or fails, show the relevant stderr and stop. Do not fabricate a substitute answer.

## When to Consult the Braintrust

### High-Value Use Cases

| Use Case | Best Model(s) | Why It Works |
|----------|---------------|--------------|
| **Design & Frontend Review** | Gemini (best available) | Strong on WebDev benchmarks, high accuracy on UI challenges, generates pixel-perfect code from sketches |
| **Architecture Review** | Gemini (primary) | 1M context analyzes 40K+ lines holistically; understands how components interact across entire codebase |
| **Cross-Model Code Review** | Different than author | The model that wrote code has blind spots to its own bugs; fresh eyes catch issues instantly |
| **System-Wide Bug Investigation** | Gemini + Claude | Gemini for cross-file pattern detection, Claude for detailed fix implementation |
| **Security Audit** | Parallel, every available CLI | Verify auth patterns, SQL injection protection, rate limiting - each model catches different vulnerabilities |
| **Design System Extraction** | Gemini (best available) | Analyzes brand elements (colors, fonts, spacing), generates consistent component libraries |
| **Framework Migration** | Gemini | Side-by-side comparisons (React->Vue, Django->Flask), translates patterns with full context |
| **Parallel Research** | Every available CLI | Speed, diverse sources, cross-validate findings across vendors |

### Recommended Workflows

**The Peer Review Pattern** (most impressive results):
1. Implement with your primary harness (e.g., Claude Code)
2. Request braintrust review: "Ask Gemini to review these changes as if they're a peer developer"
3. Braintrust catches issues the implementation pair missed (wrong patterns, memory leaks, inconsistencies)

**The Strategic + Tactical Pattern**:
1. Gemini for big-picture strategy (architecture, codebase-wide patterns)
2. Claude/Codex for detailed implementation
3. Different model for final review

**The Bug Investigation Pattern**:
1. Claude handles individual components well
2. For system-wide issues spanning multiple files, Gemini's 1M context sees the full picture
3. Back to Claude for implementing the fix

## Invocation Patterns

### Standard Consultation (from Claude Code)

Get a second opinion from the braintrust. **Always source the model probe first:**

```bash
source /tmp/bt_models.env 2>/dev/null || { bt_gemini_model="gemini-3.1-pro-preview"; bt_grok_model="grok-build"; }

# Consult the Google AI slot (agy preferred; gemini if agy unavailable) - ONE of these, not both
agy --print "Review this implementation approach: [CONTEXT]" --dangerously-skip-permissions 2>/dev/null
# ...or, if bt_agy_available=false:
timeout 120 gemini -p "Review this implementation approach: [CONTEXT]" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null

# Consult Codex (via Bash tool)
codex exec --ephemeral -s read-only --json --skip-git-repo-check "Review this implementation approach: [CONTEXT]" < /dev/null 2>/dev/null | jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text'

# Consult Grok (via Bash tool)
timeout 120 grok -p "Review this implementation approach: [CONTEXT]" -m "$bt_grok_model" --output-format json 2>/dev/null | jq -r '.text'

# Consult Claude (via Task tool, NOT bash)
# Use Task tool with subagent_type: "general-purpose" and the query as the prompt
```

### Standard Consultation (from other CLIs)

```bash
# From Gemini or Codex - consult Claude
claude -p "Review this implementation approach: [CONTEXT]" --model sonnet --output-format json | jq -r '.result'
```

### Design & Frontend Review (Gemini's Strength)

Gemini shows strong performance on frontend challenges. It thinks in design systems, not individual components:

```bash
# All examples below assume: source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-3.1-pro-preview"

# Review UI component design
gemini -p "@src/components/ Review the design consistency. Are we following a coherent design system? Check spacing, typography scale, color usage." -m "$bt_gemini_model" -o text 2>/dev/null

# Generate component from sketch (drag image into terminal)
gemini -p "@sketch.png Generate a React component with Tailwind CSS that matches this design exactly" -m "$bt_gemini_model" -o text 2>/dev/null

# Extract design system from existing code
gemini -p "@src/styles/ @src/components/ Extract the implicit design system: color palette, spacing scale, typography, component patterns" -m "$bt_gemini_model" -o text 2>/dev/null

# Review accessibility
gemini -p "@src/components/ Audit for accessibility: semantic HTML, ARIA attributes, keyboard navigation, color contrast" -m "$bt_gemini_model" -o text 2>/dev/null
```

### Codebase Analysis (Gemini's 1M Context)

Gemini has 1M token native context, ideal for whole-codebase work. Testing shows it can analyze 40K+ lines while maintaining architectural understanding:

```bash
# All examples below assume: source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-3.1-pro-preview"

# Analyze entire codebase
gemini -p "@src/ @lib/ What architectural patterns are used?" -m "$bt_gemini_model" -o text 2>/dev/null

# Find patterns across files
gemini -p "@./ How is error handling implemented across the codebase?" -m "$bt_gemini_model" -o text 2>/dev/null

# Compare implementations
gemini -p "@src/auth/ @src/api/ Are these using consistent patterns?" -m "$bt_gemini_model" -o text 2>/dev/null

# Holistic refactoring suggestions
gemini -p "@src/ Suggest refactoring improvements that require understanding of the full system, not just individual files" -m "$bt_gemini_model" -o text 2>/dev/null
```

### Maximum Reasoning (Hard Problems)

For the hardest problems, use flagship models:

```bash
source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-3.1-pro-preview"

# Claude Opus - use Task tool with model: "opus" from Claude Code
# Or from other CLIs:
claude -p "[HARD PROBLEM]" --model opus --output-format json

# Gemini (best available, 1M context)
gemini -p "[HARD PROBLEM]" -m "$bt_gemini_model" -o text 2>/dev/null
```

### Fast Consultations

When speed matters more than depth:

```bash
# Claude - use Task tool with model: "haiku" from Claude Code
# Or from other CLIs:
claude -p "[QUERY]" --model haiku --output-format json

# Gemini Flash
source /tmp/bt_models.env 2>/dev/null || bt_gemini_fast="gemini-3-flash-preview"
gemini -p "[QUERY]" -m "$bt_gemini_fast" --approval-mode yolo --no-sandbox -o text 2>/dev/null
```

### Parallel Research (from Claude Code)

Run all braintrust members simultaneously using multiple tool calls in one response:

**Tool call 1** - Task tool (run_in_background: true):
```
subagent_type: "general-purpose"
prompt: "Research: $TOPIC"
model: "sonnet"
```

**Tool call 2** - Bash tool (run_in_background: true):
```bash
source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-3.1-pro-preview"
timeout 120 gemini -p "Research: $TOPIC" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null > /tmp/gemini.txt
```

**Tool call 3** - Bash tool (run_in_background: true):
```bash
codex exec --ephemeral -s read-only --json --skip-git-repo-check "Research: $TOPIC" < /dev/null 2>/dev/null > /tmp/codex.json
```

Then read the results:
```bash
# Gemini result (plain text, no parsing needed)
cat /tmp/gemini.txt

# Codex result
jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' /tmp/codex.json
```

The Claude result comes back from the Task tool output directly.

## Prompt Enhancement: Self-Critique Pattern

**Tested and validated:** Adding a self-critique requirement to consultation prompts improves response quality by triggering deeper analysis.

### The Pattern

Append this to consultation prompts:

```
IMPORTANT: After your analysis, include a 'Self-Critique' section with 2-3 bullets identifying limitations or uncertainties in your review.
```

### When to Use

- **Code reviews** - Models acknowledge edge cases they may have missed
- **Architecture analysis** - Surfaces assumptions about context
- **Security audits** - Identifies scope limitations
- **Any high-stakes consultation** - When you need to know what the model didn't consider

### Why It Works

In practice:
- All CLIs (agy/Gemini, Codex, Grok, Claude) consistently follow the self-critique instruction
- The primary analysis tends to be more thorough when self-critique is requested
- Models surface context dependencies, scope limitations, and assumptions

### Example

```bash
# Without self-critique (finds 1 bug)
gemini -p "Review this function for bugs: async function fetchUser(id) {
  const response = await fetch('/api/users/' + id);
  const data = response.json();
  return data;
}" -m "$bt_gemini_fast" -o text 2>/dev/null

# With self-critique (finds 4 bugs)
gemini -p "Review this function for bugs: async function fetchUser(id) {
  const response = await fetch('/api/users/' + id);
  const data = response.json();
  return data;
}

IMPORTANT: After your analysis, include a 'Self-Critique' section with 2-3 bullets identifying limitations or uncertainties in your review." -m "$bt_gemini_fast" -o text 2>/dev/null
```

## Context Packaging: Project-Aware Queries

**Include project context in every outbound query.** Gemini and Codex start from zero. Fill in what you already know from the session:

```
## Project Context
- Stack: [languages, frameworks, key libraries]
- Structure: [key directories and what they contain]
- Build/Test: [how to build and test, if known]

## Task Context
- What we're working on and why
- Relevant files already examined

## Question
[The actual consultation query]

## Constraints
[API compatibility, performance requirements, style conventions, etc.]

IMPORTANT: After your analysis, include a 'Self-Critique' section with 2-3 bullets identifying limitations or uncertainties in your review.
```

**Note:** The self-critique suffix is baked into the template. Don't add it separately - it's already included above.

## Codex Prompt Structure: XML Blocks

**For Codex specifically**, use XML-tagged prompt blocks instead of plain text. GPT-5.4 responds better to block-structured prompts with explicit contracts. This does not apply to Gemini or Claude queries.

### Core Blocks

Always include `<task>`:

```xml
<task>
[Concrete job description, relevant context, expected end state]
</task>
```

Add an output contract when the response shape matters:

```xml
<structured_output_contract>
Return:
1. [first required section]
2. [second required section]
3. [third required section]
Keep the answer compact. Put highest-value findings first.
</structured_output_contract>
```

Or for concise prose instead of structured output:

```xml
<compact_output_contract>
Keep the final answer compact and structured.
Do not include long scene-setting or repeated recap.
</compact_output_contract>
```

### Verification and Grounding Blocks

Add these selectively based on task type:

```xml
<!-- For debugging, implementation, or risky fixes -->
<verification_loop>
Before finalizing, verify the result against the task requirements and the changed files or tool outputs.
If a check fails, revise the answer instead of reporting the first draft.
</verification_loop>

<!-- For review, research, or root-cause analysis -->
<grounding_rules>
Ground every claim in the provided context or your tool outputs.
Do not present inferences as facts. If a point is a hypothesis, label it clearly.
</grounding_rules>

<!-- When Codex might otherwise guess missing info -->
<missing_context_gating>
Do not guess missing repository facts.
If required context is absent, state exactly what remains unknown.
</missing_context_gating>

<!-- For write-capable tasks to prevent scope creep -->
<action_safety>
Keep changes tightly scoped to the stated task.
Avoid unrelated refactors, renames, or cleanup unless required for correctness.
</action_safety>
```

### When to Use Which Blocks

| Task Type | Required Blocks |
|-----------|----------------|
| **Code review** | `task` + `grounding_rules` + `structured_output_contract` |
| **Debugging** | `task` + `verification_loop` + `missing_context_gating` |
| **Research** | `task` + `grounding_rules` + `compact_output_contract` |
| **Implementation** | `task` + `verification_loop` + `action_safety` |

### Anti-Patterns

- **Vague framing.** "Take a look at this and let me know" produces vague output. State the concrete job.
- **Missing output contract.** "Investigate and report back" gives unpredictable structure. Specify what sections you want.
- **"Think harder" instead of better contracts.** Don't raise reasoning effort first. Tighten the prompt structure and add verification rules before escalating.
- **Mixing unrelated jobs.** One task per Codex run. Split unrelated asks into separate invocations.

### Example: Code Review Query to Codex

```bash
REVIEW_PROMPT='<task>
Review the authentication middleware for correctness and security issues.
Focus on session handling, token validation, and authorization checks.
</task>

<structured_output_contract>
Return:
1. Findings ordered by severity (critical, high, medium)
2. Supporting evidence for each finding (file, line, code snippet)
3. Concrete fix recommendation per finding
4. Brief summary of what looks correct
</structured_output_contract>

<grounding_rules>
Ground every claim in the repository context.
If a point is an inference, label it clearly.
</grounding_rules>

<verification_loop>
Before finalizing, verify each finding is material and actionable.
Prefer one strong finding over several weak ones.
</verification_loop>'

codex exec --ephemeral -s read-only --json --skip-git-repo-check "$REVIEW_PROMPT" < /dev/null 2>/dev/null > /tmp/codex.json
```

## Saving Consultation Sessions

After synthesizing, save a session file to `.braintrust/sessions/` for future reference. Create the directory if it doesn't exist (`mkdir -p .braintrust/sessions`).

Filename: `YYYY-MM-DD-HMMam-slug.md` (e.g., `2026-02-16-230pm-rate-limiting-review.md`). 12-hour time, no leading zero on hour, lowercase am/pm.

Use this format to document the full consultation for future reference:

```markdown
# [Short Topic Description]

## Query
[The context-packaged prompt sent to all models]

## Google AI (agy or gemini)
[Parsed response. Note which path ran, e.g. "agy (account-tier model)" or "gemini-3.1-pro-preview", or "Model unavailable" / "Model skipped"]

## Codex
[Parsed response, or "Model unavailable" / "Model skipped"]

## Grok
[Parsed `.text`, or "Model unavailable" / "Model skipped"]

## Claude
[Subagent response, or "Model unavailable" / "Model skipped"]

## Synthesis
[Consensus, divergence, and actionable recommendations. Note any CLI that was skipped so the coverage gap is explicit.]
```

## Model Reference

> **Note:** Model names change frequently. Use the model probe (see "Model Discovery") instead of hardcoding. The table below is a reference snapshot. Run the probe to get current model IDs.

### Claude Code

| Model | Flag Value | Context | Use Case |
|-------|-----------|---------|----------|
| **Sonnet 4.6** | `sonnet` | 200K | Default, balanced performance |
| **Opus 4.6** | `opus` | 200K | Hardest reasoning problems |
| **Haiku 4.5** | `haiku` | 200K | Speed, cost efficiency |

### Gemini (as of June 2026)

| Model | Flag Value | Context | Status |
|-------|-----------|---------|--------|
| **Gemini 3.1 Pro** | `gemini-3.1-pro-preview` | 1M | **Recommended default.** Probe tries this first. Verified 2/2 reliable on a current account (2026-06). |
| **Gemini 3 Flash** | `gemini-3-flash-preview` | 1M | **Recommended fast default.** Fast (~9-11s) and reliable. |
| **Gemini 3.1 Flash Lite** | `gemini-3.1-flash-lite-preview` | 1M | Preview, cost-efficient. |
| **Gemini 2.5 Pro** | `gemini-2.5-pro` | 1M | Fallback only. Was the old default, but dogfooding found it *less* reliable than 3.1-pro-preview (1/2, one timeout). |
| **Gemini 2.5 Flash** | `gemini-2.5-flash` | 1M | Stable fast fallback. |

> **Why 3.x before 2.5 now?** Older guidance preferred 2.5-pro for stability against the 3.x empty-response bug (#24290). Direct dogfooding in 2026-06 reversed this: on a current account, `gemini-3.1-pro-preview` and `gemini-3-flash-preview` were 2/2 reliable while `gemini-2.5-pro` was 1/2 (one 70s timeout). The probe now tries 3.1-pro-preview first and handles the occasional 3.x empty with a per-model retry. Re-verify periodically — reliability varies by account tier and capacity.
>
> **Deprecated:** `gemini-3-pro-preview` was shut down March 9, 2026. Use `gemini-3.1-pro-preview` instead.
>
> **No "3.1 Flash":** The 3.1 generation has Pro and Flash Lite, but no regular Flash. The best fast model remains `gemini-3-flash-preview` (3.0 generation).
>
> **Auto-routing:** Without `-m`, Gemini CLI auto-routes to weaker models. Always specify `-m`. The model probe handles this automatically.
>
> **Naming pattern:** All 3.x models require `-preview` suffix. Bare names (e.g., `gemini-3-pro`) return 404.
>
> **Output format:** Use `-o text` for headless mode. `-o json` triggers internal tool use which fails if `maxSessionTurns` is set to 1 in `~/.gemini/settings.json`.
>
> **Free-tier restriction:** As of March 2026, free-tier Google OAuth only gets Flash-level models. Pro models require a billing account linked in AI Studio or a `GEMINI_API_KEY`.

### Codex (as of March 2026)

| Model | Flag Value | Context | Availability |
|-------|-----------|---------|--------------|
| **GPT-5.4** | (default) | 192K | ChatGPT auth (Plus/Pro/Team/Enterprise) |
| **GPT-5.3 Codex** | `gpt-5.3-codex` | 192K | Previous default |
| **GPT-5.3 Codex Spark** | `gpt-5.3-codex-spark` | varies | ChatGPT Pro only (research preview) |
| Custom | `-m model-name` | varies | Any auth method |

### Grok (Grok Build, as of June 2026)

| Model | Flag Value | Backing Model | Availability |
|-------|-----------|---------------|--------------|
| **Grok Build** | `grok-build` (default) | Grok 4.3 | Grok subscription (SuperGrok) or `XAI_API_KEY` |
| **Grok Composer Fast** | `grok-composer-2.5-fast` | Grok Composer 2.5 | Same auth; faster, lighter |

> **Headless:** `grok -p "$QUERY" -m grok-build --output-format json 2>/dev/null | jq -r '.text'`. Run `grok models` to list what your account can use. Verified: `grok 0.2.14`, `grok-build` answered cleanly in ~5-15s.
>
> **Auth:** `grok login` (OAuth via grok.com) or `XAI_API_KEY` from console.x.ai. The default `grok-build` model needs an active Grok subscription; without one you'll hit a "subscription required" gate.

## Output Parsing

### Claude JSON Output (from other CLIs)
```json
{
  "type": "result",
  "result": "response text here",
  "session_id": "uuid",
  "total_cost_usd": 0.05
}
```
Parse with: `jq -r '.result'`

### Claude Task Tool Output (from Claude Code)
The Task tool returns the response text directly. No JSON parsing needed.

### Gemini Text Output
With `-o text`, Gemini returns plain text directly to stdout. No JSON parsing needed.

```bash
# Direct usage - response prints to stdout
gemini -p "your query" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null

# Capture to variable
gemini_response=$(timeout 120 gemini -p "your query" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null)

# Save to file for later reading
timeout 120 gemini -p "your query" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null > /tmp/gemini.txt
```

> **Why `-o text` instead of `-o json`?** `-o json` triggers internal tool use, which counts against `maxSessionTurns` in `~/.gemini/settings.json`. With `maxSessionTurns: 1` (a common headless setting), `-o json` fails with `FatalTurnLimitedError`. `-o text` avoids this entirely.
>
> **Stderr noise:** Gemini prints warnings (extension loading, MCP notifications) to stderr. Always use `2>/dev/null` to suppress these.
>
> **File context in headless mode:** `@path` references work when placed *inside* the `-p` string (e.g., `-p "@src/ Review this"`). They fail when passed as a *separate positional argument* alongside `-p` (e.g., `-p "Review this" @src/`). For files not in the working directory, pipe content via stdin: `cat file.txt | gemini -p "Review this:" -m "$bt_gemini_model" -o text 2>/dev/null`

### Codex JSONL Output (streaming)
```jsonl
{"type":"thread.started","thread_id":"uuid"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"response here"}}
{"type":"turn.completed","usage":{"input_tokens":1000,"output_tokens":50}}
```
Parse with: `jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text'`

**Alternative:** Use `--output-schema` for structured responses or `-o path` to write the final message to a file:
```bash
codex exec --ephemeral -s read-only --json --skip-git-repo-check "query" -o /tmp/codex-result.txt < /dev/null
```

### Grok JSON Output

With `--output-format json`, Grok returns a single JSON object (not a stream):
```json
{
  "text": "the answer here",
  "stopReason": "EndTurn",
  "sessionId": "uuid",
  "requestId": "uuid",
  "thought": "the model's reasoning (NOT the answer)"
}
```
Parse the answer with: `jq -r '.text'`. **Do not** use `.thought` — that's the reasoning trace.

```bash
# Capture to variable
grok_response=$(grok -p "your query" -m grok-build --output-format json 2>/dev/null | jq -r '.text')
```

**Alternative:** `--output-format plain` (the default) prints the answer text directly to stdout with no parsing, which is fine when you're piping straight to the user. Use `json` + `jq -r '.text'` when capturing into a variable so stray formatting can't leak in.

## Common Use Cases

> **Note:** All examples below assume the model probe has been run and `source /tmp/bt_models.env` is called at the start of each Bash tool invocation.

### 1. Design & Frontend Review

```bash
# Have Gemini review your React components for design quality
gemini -p "@src/components/ Review these components for:
1. Design consistency (spacing, colors, typography)
2. Accessibility compliance
3. Responsive design patterns
4. Component API design (props, composition)
What's working well? What needs improvement?" -m "$bt_gemini_model" -o text 2>/dev/null

# Generate pixel-perfect code from a design mockup
gemini -p "@mockup.png Implement this design as a React component with Tailwind CSS. Match the exact spacing, colors, and typography." -m "$bt_gemini_model" -o text 2>/dev/null
```

### 2. Architecture Review

```bash
# Get Gemini's take on overall architecture (uses 1M context)
gemini -p "@src/ Analyze the architecture. What are the main components and how do they interact? Identify any architectural debt or inconsistencies." -m "$bt_gemini_model" -o text 2>/dev/null
```

### 3. Cross-Model Code Review

```bash
# After implementing with Claude, get Gemini's review as a peer
gemini -p "@src/features/auth/ Review these changes as if you're a senior developer on the team. Look for:
- Bugs or logic errors
- Security issues
- Performance concerns
- Patterns inconsistent with the rest of the codebase
- Missed edge cases" -m "$bt_gemini_model" -o text 2>/dev/null
```

### 4. Security Audit (Parallel, from Claude Code)

Run every available CLI in parallel using multiple tool calls (the Google AI slot is agy *or* gemini, not both):

**Tool call 1** - Task tool (run_in_background: true):
```
subagent_type: "general-purpose"
prompt: "Review this codebase for security vulnerabilities: [paste relevant code or describe scope]
1. Authentication/authorization flaws
2. SQL injection or NoSQL injection
3. XSS vulnerabilities
4. CSRF protection
5. Secrets in code
6. Rate limiting gaps"
```

**Tool call 2** - Bash tool (run_in_background: true):
```bash
gemini -p "@src/ Review this codebase for security vulnerabilities:
1. Authentication/authorization flaws
2. SQL injection or NoSQL injection
3. XSS vulnerabilities
4. CSRF protection
5. Secrets in code
6. Rate limiting gaps" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null > /tmp/gemini-security.txt
```

**Tool call 3** - Bash tool (run_in_background: true):
```bash
AUDIT_PROMPT="Review this codebase for security vulnerabilities:
1. Authentication/authorization flaws
2. SQL injection or NoSQL injection
3. XSS vulnerabilities
4. CSRF protection
5. Secrets in code
6. Rate limiting gaps"
codex exec --ephemeral -s read-only --json --skip-git-repo-check "$AUDIT_PROMPT" < /dev/null 2>/dev/null > /tmp/codex-security.json
```

**Tool call 4** - Bash tool (run_in_background: true):
```bash
source /tmp/bt_models.env 2>/dev/null || bt_grok_model="grok-build"
grok -p "Review this codebase for security vulnerabilities:
1. Authentication/authorization flaws
2. SQL injection or NoSQL injection
3. XSS vulnerabilities
4. CSRF protection
5. Secrets in code
6. Rate limiting gaps" -m "$bt_grok_model" --output-format json 2>/dev/null | jq -r '.text' > /tmp/grok-security.txt
```

> The Google AI leg above uses `gemini`; if `bt_agy_available=true`, replace it with `agy --print "$AUDIT_PROMPT" --dangerously-skip-permissions 2>/dev/null > /tmp/agy-security.txt` instead (one Google voice, not both).

Then collect and compare findings from every CLI that responded.

### 5. System-Wide Bug Investigation

```bash
# When bugs span multiple files, use Gemini's full-context view
BUG="Users report intermittent 500 errors on /api/checkout. Logs show connection timeout."
gemini -p "@src/ Debug this system-wide issue: $BUG

Trace the request flow from entry point to database. Identify:
1. All code paths involved
2. Connection pooling configuration
3. Timeout settings
4. Retry logic (or lack thereof)
5. Error handling gaps" -m "$bt_gemini_model" -o text 2>/dev/null
```

### 6. Framework Migration Planning

```bash
# Get side-by-side comparison for migration
gemini -p "@src/ We're considering migrating from React class components to hooks. Analyze:
1. Current patterns used
2. Migration complexity per component
3. Suggested migration order
4. Potential breaking changes
5. Testing strategy" -m "$bt_gemini_model" -o text 2>/dev/null
```

### 7. Parallel Research (from Claude Code)

Run every available CLI using multiple tool calls in one response:

**Tool call 1** - Task tool (run_in_background: true):
```
subagent_type: "general-purpose"
prompt: "Research: best practices for implementing rate limiting in Node.js APIs"
model: "sonnet"
```

**Tool call 2** - Bash tool (run_in_background: true):
```bash
timeout 120 gemini -p "Research: best practices for implementing rate limiting in Node.js APIs" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null > /tmp/gemini.txt
```

**Tool call 3** - Bash tool (run_in_background: true):
```bash
codex exec --ephemeral -s read-only --json --skip-git-repo-check "Research: best practices for implementing rate limiting in Node.js APIs" < /dev/null 2>/dev/null > /tmp/codex.json
```

**Tool call 4** - Bash tool (run_in_background: true):
```bash
source /tmp/bt_models.env 2>/dev/null || bt_grok_model="grok-build"
timeout 120 grok -p "Research: best practices for implementing rate limiting in Node.js APIs" -m "$bt_grok_model" --output-format json 2>/dev/null | jq -r '.text' > /tmp/grok.txt
```

Then synthesize findings from every source that responded. (Swap Tool call 2 for `agy --print ... 2>/dev/null > /tmp/gemini.txt` when `bt_agy_available=true`.)

## Key Flags Reference

### Claude Code (from other CLIs only)
| Flag | Purpose |
|------|---------|
| `-p, --print` | Non-interactive mode |
| `--model` | Model selection (haiku/sonnet/opus) |
| `--output-format` | text/json/stream-json |
| `--effort` | Reasoning depth: low/medium/high/max |
| `--fallback-model` | Auto-fallback when primary is overloaded (only with `--print`) |
| `--system-prompt` | Custom system prompt |
| `--append-system-prompt` | Append to default system prompt |
| `--max-turns` | Limit agentic turns |
| `--json-schema` | Structured output schema (with --output-format json) |
| `--allowedTools` | Auto-approve specific tools |
| `--bare` | Minimal mode: skips hooks, plugins, LSP, auto-memory |
| `--no-session-persistence` | Don't save session to disk (only with `--print`) |

> **From within Claude Code:** Use the Task tool instead. The `claude` CLI blocks nested sessions.

### Gemini
| Flag | Purpose |
|------|---------|
| `-p, --prompt` | Non-interactive (headless) mode (**required** for headless) |
| `-m, --model` | Model selection (also supports aliases: `pro`, `flash`, `flash-lite`, `auto`) |
| `-o, --output-format` | **Use `text`** for headless. `json` triggers tool use and breaks with `maxSessionTurns: 1`. `stream-json` returns JSONL events. |
| `--approval-mode` | **Use `yolo`** for headless. Prevents tool-approval hangs. Replaces deprecated `-y/--yolo`. |
| `--sandbox` | Sandbox mode. **Use `none`** for braintrust queries. Options: none/docker/podman/sandbox-exec/runsc/lxc. |
| `@path` | Include file/directory in context |
| `-a, --all-files` | Include all repo files in context (no `@` needed) |
| `--include-directories` | Additional directories for context |
| `--extensions` | Control extension loading. Use `""` to skip all extensions for faster startup. |
| `--policy` | User-defined tool/action policies (replaces deprecated `--allowed-tools`) |
| `--raw-output` | Disable output sanitization (allows ANSI escapes) |
| `-r, --resume` | Resume previous session (`latest` or session ID) |
| `-d, --debug` | Enable debug output for diagnosing failures |

> **Positional args run interactive mode.** Always use `-p` for headless/scripted usage.
>
> **Free tier limits (Google OAuth):** Free tier is now restricted to Flash-level models only. Pro models require a billing account linked in AI Studio or an API key (`GEMINI_API_KEY`) with billing enabled.
>
> **Exit codes:** `0` success, `1` general error, `42` input error, `53` turn limit exceeded.

### Antigravity CLI (agy)
| Flag | Purpose |
|------|---------|
| `-p, --print, --prompt` | Non-interactive (headless) print mode |
| `--print-timeout` | Timeout for print mode (default `5m0s`) |
| `--dangerously-skip-permissions` | Auto-approve all tool permission requests (replaces `--approval-mode yolo`) |
| `--sandbox` | Enable sandbox with terminal restrictions (boolean; omit to disable) |
| `--continue` / `-c` | Continue the most recent conversation |
| `--conversation` | Resume a previous conversation by ID |
| `--add-dir` | Add a directory to the workspace (repeatable) |
| `--prompt-interactive` / `-i` | Run initial prompt then continue interactively |

> **No model selection.** `agy` has no `-m` flag. The model used depends on your Antigravity account tier (a high-tier Gemini 3.x on paid Antigravity; a Flash-class model on free). You can't pin a specific model — if you need one, use `gemini -m` instead.
>
> **No `@path` file context.** Unlike `gemini`, `agy` does not support `@src/` style file includes in headless mode. Pass file content via stdin or inline in the prompt string.
>
> **No output format control.** `agy --print` always returns plain text. No JSON or stream-json mode.
>
> **agy is the primary path.** Use `gemini` as a fallback when `agy` is unavailable, or when you need explicit model selection (`-m`) or `@path` file context — capabilities `agy` does not support.

### Codex
| Flag | Purpose |
|------|---------|
| `exec` | Non-interactive subcommand (alias: `e`) |
| `exec review` | Dedicated code review (`--uncommitted`, `--base <BRANCH>`, `--commit <SHA>`). Auto-reads diffs. Plain text output. |
| `--json` | JSONL output stream |
| `--full-auto` | Low-friction preset: workspace-write + on-request approvals |
| `-s, --sandbox` | Sandbox policy: read-only/workspace-write/danger-full-access |
| `-m, --model` | Model selection (works with ChatGPT auth and API key) |
| `--oss` | Use open-source provider (LM Studio or Ollama) |
| `--local-provider` | Specify local provider: lmstudio/ollama (with `--oss`) |
| `-i, --image` | Attach images for visual context (repeatable, comma-separated) |
| `-C, --cd` | Set working directory before executing |
| `--add-dir` | Additional writable directories alongside workspace |
| `--output-schema` | Structured JSON response matching a schema |
| `-o, --output-last-message` | Write final message to file |
| `--ephemeral` | Skip persisting session files |
| `--skip-git-repo-check` | Run outside a git repo |
| `--dangerously-bypass-approvals-and-sandbox` | Skip all prompts, no sandbox. For externally sandboxed envs only. |
| `--color` | ANSI color control: always/never/auto |

### Grok (Grok Build)
| Flag | Purpose |
|------|---------|
| `-p, --single` | Single-turn headless prompt. Prints the response and exits (**required** for headless; without it grok opens its TUI) |
| `--prompt-file <PATH>` | Single-turn prompt read from a file |
| `--output-format` | `plain` (default), `json`, or `streaming-json`. Use `json` + `jq -r '.text'` when capturing to a variable. |
| `-m, --model` | Model id: `grok-build` (default, Grok 4.3) or `grok-composer-2.5-fast`. `grok models` lists them. |
| `--effort` | Effort level: `low`/`medium`/`high`/`xhigh`/`max` |
| `--reasoning-effort` | Reasoning effort for reasoning models |
| `--check` | Append a self-verification loop to the prompt (headless only) |
| `--best-of-n <N>` | Run the task N ways in parallel and pick the best (headless only) |
| `--disable-web-search` | Disable web search/fetch tools |
| `--permission-mode` | `default`/`acceptEdits`/`auto`/`dontAsk`/`bypassPermissions`/`plan` |
| `--always-approve` | Auto-approve all tool executions |
| `models` (subcommand) | List available models and exit |

> **Headless contract:** `grok -p "$QUERY" -m grok-build --output-format json 2>/dev/null | jq -r '.text'`. Always pass `-p` or grok launches its interactive UI. Parse `.text`, not `.thought` (which is the reasoning trace).
>
> **Auth:** `grok login` (OAuth) or `XAI_API_KEY` (console.x.ai). `grok-build` requires a Grok subscription.
>
> **Read-only by default:** A bare consultation doesn't edit files. If you ever need write access add `--permission-mode acceptEdits`; for braintrust second opinions, leave it off.

## Tips

1. **Use Gemini for design & frontend** - Strong performance on UI challenges and design system analysis
2. **Use Gemini for large context** - 1M tokens native vs 200K for Claude / 192K for Codex; can analyze 40K+ lines holistically
3. **Cross-model review catches bugs** - When a model writes code, it's blind to its own mistakes; different models spot issues instantly
4. **Use the model probe** - Run the model discovery probe once per session; never hardcode Gemini model names
5. **Use `-o text` for Gemini** - `-o json` breaks with `maxSessionTurns: 1`. Text output needs no parsing.
6. **Parallel is fast** - Run every available CLI simultaneously (up to four voices) for speed and diverse perspectives
7. **Different models, different blind spots** - Each AI has different training; combined approaches outperform individuals
8. **Always redirect Gemini stderr** - Use `2>/dev/null` to suppress extension warnings and MCP noise
9. **Never run `claude -p` from Claude Code** - It will fail. Use the Task tool for the Claude leg of any consultation
10. **Always close Codex stdin with `< /dev/null`** - Codex `exec "prompt"` reads stdin by default. Without `< /dev/null`, it hangs forever inside Claude Code's Bash tool with "Reading additional input from stdin...". This is the single most common reason Codex "doesn't work" in harnesses.
11. **Use `codex exec review` for code review** - The dedicated review subcommand auto-reads git diffs; no need to craft review prompts manually
12. **Always use `--ephemeral -s read-only` for Codex** - Braintrust consultations are stateless and read-only. Only switch to `-s workspace-write` when the user explicitly asks Codex to make changes.
13. **Always pass `-p` to Grok** - Without it, grok opens its interactive TUI instead of answering headlessly. Parse `.text` (not `.thought`) from `--output-format json`.
14. **agy is one warm-up away** - A single empty/slow agy call is transient (cold start or a relay hiccup, not a rate limit). Retry once before falling back to gemini; don't let it flip the Google AI slot.
15. **Never auto-fix review findings** - Present findings and let the user decide what to act on

## Further Reading

- [Claude Code Agent SDK (headless mode)](https://code.claude.com/docs/en/headless)
- [Gemini CLI Headless Mode](https://google-gemini.github.io/gemini-cli/docs/cli/headless.html)
- [Codex CLI Non-Interactive Mode](https://developers.openai.com/codex/noninteractive/)
- [Claude + Gemini Workflow: When AIs Start Gossiping About Your Code](https://byjos.dev/claude-gemini-workflow/)
- [Claude Code Bridge: Multi-AI Collaboration](https://github.com/bfly123/claude_code_bridge)
- [Using Gemini CLI for Large Codebase Analysis](https://gist.github.com/steipete/20ed650822f1ac835144bfd328c872b7)
- [Gemini CLI Code Review and Security Analysis](https://codelabs.developers.google.com/gemini-cli-code-analysis)
