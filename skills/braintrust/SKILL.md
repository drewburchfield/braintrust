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

**Grounding First (do this before launching members):**
- Determine `session_anchor` (e.g. 2026-06-17-my-task or current session ID/slug). Use the *same value* for the entire conversation thread (works across days if the session persists).
- Ensure a Goal Card exists: `mkdir -p .braintrust/goal-cards`; draft from user request + session context if missing; include the `session_anchor`; save to `.braintrust/goal-cards/<slug>.md`. Read it back.
- Curate the context package as described in "Context Packaging + Goal Card".
- Include the full Goal Card + Skeptical Colleague Protocol in every prompt.

**Launch all available members in a single parallel batch using multiple tool calls in one response:**

> **First call in a session?** Run the model probe (see "Model Discovery" section) first. It takes ~30-90s and decides who's in (installed + authenticated) and which models to use. If `/tmp/bt_models.env` already exists from an earlier call, skip the probe.

1. **Claude** (always available from Claude Code): Use the Task tool with `subagent_type: "general-purpose"` and `run_in_background: true`
2. **Google AI** — use exactly one path, in this priority order:
   - **Antigravity/agy** (if `bt_agy_available=true`): Use the Bash tool with `run_in_background: true`. **agy must be wrapped in a PTY** (the probe writes `/tmp/bt_agy_pty.py`):
     ```bash
     python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions
     ```
     > **Why the wrapper (REQUIRED):** `agy --print` only flushes its answer to stdout when stdout is a real TTY. As a subprocess (pipe/redirect), the model round-trip completes but stdout stays empty: on macOS this is an indefinite hang, on Windows/Linux an instant empty exit-0. This is upstream bug [antigravity-cli#76](https://github.com/google-antigravity/antigravity-cli/issues/76), open as of agy 1.0.4. The PTY wrapper gives agy a pseudo-terminal so it flushes, strips ANSI, and enforces a real timeout (agy's own `--print-timeout` is non-functional). See "Common Antigravity (agy) Failure Modes". The wrapper exits 0 with the answer, 124 on timeout, 1 on empty.
     >
     > **agy note:** No `-m` model flag (runs your Antigravity account-tier model). No `@path` file context (inline file content in the prompt). No output format control.
   - **Gemini** (only if `bt_agy_available=false` and `bt_gemini_available=true`): Use the Bash tool with `run_in_background: true`:
     ```bash
     source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-3.1-pro-preview"
     gemini -p "$QUERY" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null
     ```
     > **gemini is the power-user path.** Supports explicit model selection (`-m`), `@path` file context, and output format control. Use when `agy` is unavailable or when you need model-level control.
3. **Codex** (if `bt_codex_available=true`): Use the Bash tool with `run_in_background: true`:
   ```bash
   source /tmp/bt_models.env 2>/dev/null
   CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" codex exec --ephemeral -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "$QUERY" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
   ```

   > **Run Codex isolated.** Two non-negotiables, both proven in production failures:
   > - **`CODEX_HOME="$bt_codex_home"`** points Codex at a clean throwaway profile with no memories, no MCP servers, and no global `~/.codex/AGENTS.md`. Without this, Codex reviews arrive contaminated by prior-session memories (observed: a review that answered a completely unrelated spec) and your global writing-style instructions, which biases the synthesis. The probe builds this profile. See "Codex Isolation: Clean-Slate Reviewer" below.
   > - **`< /dev/null`** closes stdin. Codex's `exec "prompt"` reads stdin by default and hangs forever when the harness pipes to it.
   >
   > Capture stderr to a file (`2>/tmp/bt_codex.err`), not `/dev/null`, so you can read the real error if the run comes back empty. See "Common Codex Failure Modes" below.
4. **Grok** (if `bt_grok_available=true`): Use the Bash tool with `run_in_background: true`.
   **Preferred:** If the workspace has the `grounded-colleague` skill (from our Grok-side build), prefer routing through it for stronger grounding:
   ```bash
   source /tmp/bt_models.env 2>/dev/null || bt_grok_model="grok-build"
   grok -p "/grounded-colleague $QUERY" -m "$bt_grok_model" --output-format json 2>/dev/null | jq -r '.text'
   ```
   Fallback direct (embed the colleague protocol in $QUERY as described in Context Packaging):
   ```bash
   source /tmp/bt_models.env 2>/dev/null || bt_grok_model="grok-build"
   grok -p "$QUERY" -m "$bt_grok_model" --output-format json 2>/dev/null | jq -r '.text'
   ```

   > **Grok note:** `grok-build` is Grok 4.3 and needs a Grok subscription. When the new `grounded-colleague` skill is present on the Grok side, using `/grounded-colleague` + Goal Card gives you the full Skeptical Colleague persona (high reasoning effort, explicit assumptions + evidence mandate). The `json` format returns `{"text": ..., "thought": ...}`; parse the answer with `jq -r '.text'`. See "Common Grok Failure Modes" below.

> **Skip unavailable CLIs.** If the probe marked a CLI as unavailable or unauthenticated, do not launch it. Note the gap in your synthesis instead.

**Grounded Consultation Protocol (MANDATORY for rich, consistent results):**
Before building any $QUERY or prompt for braintrust members:
1. **Establish or reference a Goal Card.** Determine `session_anchor` for this thread (date-based slug or native session ID; same value across days if continuing the session). If no Goal Card exists for this task, draft one from the user's original request + session context (use the structure in goal-card-template.md). Include the `session_anchor` and use the *same value* for the thread. Write it to `.braintrust/goal-cards/<slug>.md`. Create the dir with `mkdir -p .braintrust/goal-cards`. Read it back.
2. **Curate context actively.** Do not rely solely on what the main session "has". Use tools (list_dir, grep, read_file on key files, git status/diff if relevant) to assemble a tight, relevant context package. Include:
   - The full Goal Card
   - Original user goal / request
   - Curated relevant files or diffs (inline or @path where supported)
   - Recent decisions or constraints from the conversation
3. **Inject the Skeptical Colleague Protocol** into every delegation prompt (see the full protocol below and in the Grok grounding-colleague persona for reference). This dramatically improves honesty and grounding vs generic "review this".

The main source of variable richness is weak context packaging by the host agent. By making the braintrust skill itself responsible for Goal Card + curation + protocol, outcomes become far more consistent.

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
source /tmp/bt_models.env 2>/dev/null || { bt_gemini_fast="gemini-3-flash-preview"; bt_grok_model="grok-build"; bt_codex_home="/tmp/bt-codex-home"; }
python3 /tmp/bt_agy_pty.py 60 agy --print "say ok" --dangerously-skip-permissions 2>/dev/null | grep -qi "ok" && echo "agy: OK" || echo "agy: FAILED (antigravity-cli#76; needs the PTY wrapper -> if still failing, fall back to gemini)"
gemini -p "say ok" -m "$bt_gemini_fast" --approval-mode yolo --no-sandbox -o text 2>/dev/null | grep -qi "ok" && echo "Gemini: OK" || echo "Gemini: FAILED"
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" codex exec --ephemeral -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "test" < /dev/null 2>/dev/null | head -5 && echo "Codex: OK" || echo "Codex: FAILED"
grok -p "say ok" -m "$bt_grok_model" --output-format json 2>/dev/null | jq -r 'select(.type!="error") | .text' | grep -qi "ok" && echo "Grok: OK" || echo "Grok: FAILED (parse .message for the real cause: 'out of credits/spending-limit' = billing, not login)"
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
| **Answers an unrelated topic / off-topic review** | **Context contamination.** Codex injects prior-session **memories** (`memories = true` in `~/.codex/config.toml`, globally and per-project), the global `~/.codex/AGENTS.md`, and the repo it's run in. It is **not** a blank slate. Observed: a diff review that instead critiqued a different project's spec pulled from a memory. | **Run with an isolated `CODEX_HOME`** (clean profile: no memories, no MCP, no global AGENTS.md) **and `-C` into a scratch dir.** `-C /tmp` alone is *not* enough; it escapes the repo but leaves memories and global instructions loaded. See "Codex Isolation: Clean-Slate Reviewer". |
| `You've hit your usage limit` | ChatGPT free/Plus rate limit | Wait for reset or switch to API key auth with `CODEX_API_KEY` |
| `failed to stat skills entry` (stderr) | Broken symlink in `~/.codex/skills/` | Remove the dead symlink. Non-blocking but noisy. (An isolated `CODEX_HOME` avoids it entirely.) |
| Hangs on startup / silent timeout (`rc=124`) | MCP servers in `~/.codex/config.toml` initialize on **every** `exec` call. Heavy or dead-auth servers (e.g. an expired Granola/Linear token) block startup. Observed: an isolated `-C /tmp` run still timed out because it booted the global MCP servers first. | **Use an isolated `CODEX_HOME`** with no `[mcp_servers]` (see "Codex Isolation"). This is faster *and* removes the hang. |
| `not a git repository` | Codex requires a git repo by default | Add `--skip-git-repo-check` to exec commands |
| `missing YAML frontmatter` (stderr) | Codex loading incompatible skill files | Non-blocking stderr noise. Safe to ignore. (Isolated `CODEX_HOME` avoids it.) |
| Hangs forever with `Reading additional input from stdin...` | Codex `exec "prompt"` reads stdin by default. If the harness pipes anything to stdin (or leaves it open), Codex waits or appends it as a `<stdin>` block. | **Always close stdin with `< /dev/null`.** Example: `codex exec --ephemeral -s read-only --json --skip-git-repo-check "$QUERY" < /dev/null 2>/tmp/bt_codex.err`. This is the #1 cause of Codex appearing "broken" inside Claude Code. |

### Codex Isolation: Clean-Slate Reviewer

**`codex exec --ephemeral` is not a blank slate.** `--ephemeral` only skips *persisting* the new session. It still loads, on every call:

1. **Memories** — `memories = true` in `~/.codex/config.toml` (global, plus a per-project `[projects."..."]` block). Codex injects what it decided was relevant from past sessions. This is the documented cause of an off-topic review pulling in another project's content, and it silently biases synthesis even when the answer stays on-topic.
2. **MCP servers** — every server in `[mcp_servers]` boots on each `exec`. Adds latency; a server with expired auth can hang the whole call to a `rc=124` timeout.
3. **Global instructions** — `~/.codex/AGENTS.md` (writing voice, "confirm before large changes", etc.) leaks personal preferences into a neutral peer review.

For an unbiased fourth opinion, none of that belongs. The fix is a throwaway `CODEX_HOME` that reuses only your auth:

```bash
# Build once per session (the model probe does this and exports $bt_codex_home).
bt_codex_home="${TMPDIR:-/tmp}/bt-codex-home"
mkdir -p "$bt_codex_home"
printf '# braintrust isolated profile: no memories, no MCP, no global AGENTS.md\n' > "$bt_codex_home/config.toml"
[ -f "$HOME/.codex/auth.json" ] && cp "$HOME/.codex/auth.json" "$bt_codex_home/auth.json"

# Every Codex consult then runs against the clean profile, from a scratch cwd:
CODEX_HOME="$bt_codex_home" codex exec --ephemeral -s read-only --json --skip-git-repo-check \
  -C "${TMPDIR:-/tmp}" "$QUERY" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
```

Verified clean-slate behavior: with this profile, asking Codex to enumerate any pre-loaded context returns `CLEAN SLATE`, and the call finishes in ~13s with no MCP boot. Without it, the same prompt drags in memories and MCP servers.

> **`-C /tmp` is necessary but not sufficient.** Changing the working directory stops Codex reading the *repo* you're in, but `CODEX_HOME` is what strips memories, MCP, and the global `AGENTS.md`. Use both.
>
> **When you DO want Codex to read the live repo** (rare for braintrust — we normally pass context inline), drop `-C` so its cwd is the repo, but keep the isolated `CODEX_HOME` so memories and MCP stay out. Context should come from your prompt, not from whatever Codex remembered.

### Capturing CLI Failures (Don't Blackhole stderr)

**Default to `2>/tmp/bt_<cli>.err`, not `2>/dev/null`.** Redirecting stderr to `/dev/null` is why the two most common braintrust failures get misdiagnosed:

- **agy** returning empty looks like a "transient relay hiccup" but is often a hard `rc=124` timeout that does not recover on retry. The exit code tells you which; `/dev/null` hides it.
- **grok** failing with `Auth(AuthorizationRequired)` on stderr looks like a login problem, but the **JSON error body on stdout** says the real cause (e.g. `403 ... out of credits or need a Grok subscription ... spending-limit`). `grok login` won't fix a billing cap.

Keep stderr in a file, check the exit code, and surface the captured error when a CLI comes back empty. Only suppress stderr noise *after* you've confirmed success. The per-CLI error-handling block under "Handling Errors During Consultation" does this.

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

**Root cause of the agy "hang": a known upstream bug.** `agy --print` renders its answer through a TUI drip renderer that is gated on `isatty(stdout)`. When stdout is **not** a real terminal (a pipe, a redirect, or a subprocess, which is exactly how braintrust calls it), the model round-trip completes but **the answer is never written to stdout**. The response is real: agy's own log shows `text_drip.go: Drip stopped: length=N` matching the answer, and it is even persisted to disk. Only the stdout writeback is skipped. This is upstream issue [`google-antigravity/antigravity-cli#76`](https://github.com/google-antigravity/antigravity-cli/issues/76), **open** and reproduced on agy 1.0.0 through **1.0.4**.

Failure shape is platform-dependent:
- **macOS (indefinite hang → `rc=124`):** first `-p` call after idle returns (~7s); every subsequent call hangs until killed. Verified locally on agy 1.0.4: bare call `rc=124`, empty log save for `Raising signal 15`.
- **Windows / Linux (instant empty):** `exit 0`, 0 bytes, ~6s.

**`--print-timeout` does NOT bound the hang** (confirmed upstream and locally). The external `timeout`/wrapper is the only real bound. `--output-format`/`--json` do not exist.

**The fix braintrust uses: run agy under a PTY wrapper.** Giving agy a pseudo-terminal makes `isatty(stdout)` true, so it flushes normally. The probe writes this wrapper to `/tmp/bt_agy_pty.py`; every agy consult goes through it:

```bash
# Written once by the probe (or run this block standalone before consulting agy).
cat > /tmp/bt_agy_pty.py << 'PY'
#!/usr/bin/env python3
# braintrust agy PTY wrapper: works around antigravity-cli#76 (agy --print only
# flushes stdout to a real TTY). Allocates a pseudo-terminal so isatty(stdout) is
# true, strips ANSI, and enforces a REAL external timeout (agy's --print-timeout
# is non-functional). Pure stdlib.
# Usage: bt_agy_pty.py <timeout_s> agy --print "<prompt>" --dangerously-skip-permissions
# Exit:  0 = response captured | 124 = timed out | 1 = empty/other failure
import os, pty, select, subprocess, sys, time, re, struct, fcntl, termios
if len(sys.argv) < 3:
    sys.stderr.write("usage: bt_agy_pty.py <timeout_s> <cmd...>\n"); sys.exit(2)
deadline = float(sys.argv[1]); cmd = sys.argv[2:]
master, slave = pty.openpty()
try:
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 220, 0, 0))
except Exception:
    pass
p = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)
buf = bytearray(); start = time.time(); timed_out = False
while True:
    if time.time() - start > deadline:
        p.kill(); timed_out = True; break
    r, _, _ = select.select([master], [], [], 1.0)
    if master in r:
        try:
            data = os.read(master, 65536)
        except OSError:
            break
        if not data:
            break
        buf += data
    if p.poll() is not None:
        try:
            while True:
                rr, _, _ = select.select([master], [], [], 0.2)
                if master not in rr:
                    break
                d = os.read(master, 65536)
                if not d:
                    break
                buf += d
        except OSError:
            pass
        break
try:
    p.wait(timeout=5)
except Exception:
    pass
raw = buf.decode("utf-8", "replace")
raw = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", raw)
raw = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", raw)
raw = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", raw).replace("\r", "")
clean = raw.strip()
sys.stderr.write(f"[agy-pty] rc={p.poll()} timed_out={timed_out} rawbytes={len(buf)} clean={len(clean)}\n")
if timed_out:
    sys.exit(124)
if not clean:
    sys.exit(1)
sys.stdout.write(clean + "\n")
sys.exit(0)
PY
# macOS: warm the keychain to avoid the 1s keyringAuth timeout (antigravity-cli#51)
security find-generic-password -s "Antigravity Safe Storage" >/dev/null 2>&1 || true
# Consult agy through the wrapper (120s is the REAL bound):
python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| Empty stdout / `rc=124` hang when piped or captured | **antigravity-cli#76**: `--print` only flushes to a TTY. | **Use the PTY wrapper above.** Verified: bare call hangs `rc=124`; wrapped call returns a full review in ~5-7s. |
| Wrapper itself returns `rc=124` | agy hung even under the PTY (e.g. subsequent-call hang or quota), or genuinely slow. | Retry **once**; if it times out again, treat agy as **down** and fall back to gemini. Don't loop. |
| Wrapper returns `rc=1` (empty) | Quota exhaustion surfaces as a silent empty response (antigravity-cli#56), or auth dropped. | Note the gap, fall back to gemini. Repeated empties = quota; stop calling agy this session. |
| Repeated OAuth prompts on macOS even when logged in | `keyringAuth: timed out after 1s` (antigravity-cli#51). | The wrapper block warms the keychain first (`security find-generic-password -s "Antigravity Safe Storage"`), which substantially reduces it. |
| No model control | agy has **no `-m` flag** by design. It runs your Antigravity account-tier model. | If you need a specific model, use `gemini -m` instead. See "agy vs Gemini: Two Different Model Paths". |

> **Windows caveat:** the PTY workaround is verified on **macOS**; on Windows a ConPTY wrapper does **not** help (agy takes a different MCP-loading path that stalls). On Windows, fall back to gemini, or scrape the persisted answer from `~/.gemini/antigravity-cli/brain/<conversation_id>/.system_generated/logs/transcript.jsonl` (id keyed by cwd in `cache/last_conversations.json`).
>
> **No clean-profile flag.** Unlike Codex's `CODEX_HOME`, agy exposes no isolated-home env var; its state lives in `~/.gemini/antigravity-cli/`. Isolation is not available for agy.
>
> **Revert when fixed:** once antigravity-cli#76 ships a non-TTY stdout flush (or an `--output`/`--json` flag), drop the wrapper and call `agy --print` directly.

### Common Grok Failure Modes

If Grok fails, check these in order:

| Symptom | Cause | Fix |
|---------|-------|-----|
| stderr spams `Auth(AuthorizationRequired)` / `Transport channel closed`, but stdout has a JSON error with `403 ... out of credits or need a Grok subscription ... [WKE=...spending-limit]` | **Billing cap, not a login problem.** The account is authenticated but out of credits or over its spending limit. The stderr `AuthorizationRequired` line is a misleading symptom; the real cause is the JSON error body on **stdout**. | **`grok login` will NOT fix this.** Add credits at grok.com/?_s=usage, upgrade the subscription, or switch to an `XAI_API_KEY` with available balance. Detect it by parsing the stdout JSON for `.type == "error"` and surfacing `.message` (see the error-handling block) instead of reporting a generic auth failure. |
| `A subscription is required` / access gate | `grok-build` (Grok 4.3) requires an active Grok subscription (SuperGrok). | Subscribe at grok.com, or set `XAI_API_KEY` from console.x.ai for API-key auth. |
| `run grok login` / auth error (and **no** JSON error body) | Genuinely not signed in. | Run `grok login` (OAuth) or export `XAI_API_KEY`. Only conclude this after ruling out the billing-cap row above. |
| Empty `.text` from `jq` | Wrong output format, the answer is under a different field, **or** the response was an error object. | Use `--output-format json`. First check `.type == "error"` (surface `.message`); otherwise parse `jq -r '.text'`. The `thought` field holds reasoning, not the answer. |
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
| **Antigravity (agy)** | `python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions` (**primary** Google AI path; PTY-wrapped per antigravity-cli#76) | N/A (no model flag) |
| **Codex** | `CODEX_HOME="$bt_codex_home" codex exec --ephemeral -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "query" < /dev/null 2>/tmp/bt_codex.err` (isolated clean-slate; see "Codex Isolation") | N/A |
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

# --- Clean-slate Codex profile (no memories, no MCP, no global AGENTS.md) ---
# Built once here and reused by every Codex consult. Reuses only auth.json.
# Without this, Codex exec drags in ~/.codex memories + MCP servers, which biases
# reviews and can hang startup to a timeout. See "Codex Isolation".
bt_codex_home="${TMPDIR:-/tmp}/bt-codex-home"
mkdir -p "$bt_codex_home"
printf '# braintrust isolated profile: no memories, no MCP, no global AGENTS.md\n' > "$bt_codex_home/config.toml"
[ -f "$HOME/.codex/auth.json" ] && cp "$HOME/.codex/auth.json" "$bt_codex_home/auth.json" 2>/dev/null

# --- agy PTY wrapper (works around antigravity-cli#76: --print only flushes to a TTY) ---
# Written once here; every agy probe/consult runs through it.
cat > /tmp/bt_agy_pty.py << 'PY'
#!/usr/bin/env python3
import os, pty, select, subprocess, sys, time, re, struct, fcntl, termios
if len(sys.argv) < 3:
    sys.stderr.write("usage: bt_agy_pty.py <timeout_s> <cmd...>\n"); sys.exit(2)
deadline = float(sys.argv[1]); cmd = sys.argv[2:]
master, slave = pty.openpty()
try:
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 220, 0, 0))
except Exception:
    pass
p = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)
buf = bytearray(); start = time.time(); timed_out = False
while True:
    if time.time() - start > deadline:
        p.kill(); timed_out = True; break
    r, _, _ = select.select([master], [], [], 1.0)
    if master in r:
        try:
            data = os.read(master, 65536)
        except OSError:
            break
        if not data:
            break
        buf += data
    if p.poll() is not None:
        try:
            while True:
                rr, _, _ = select.select([master], [], [], 0.2)
                if master not in rr:
                    break
                d = os.read(master, 65536)
                if not d:
                    break
                buf += d
        except OSError:
            pass
        break
try:
    p.wait(timeout=5)
except Exception:
    pass
raw = buf.decode("utf-8", "replace")
raw = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", raw)
raw = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", raw)
raw = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", raw).replace("\r", "")
clean = raw.strip()
sys.stderr.write(f"[agy-pty] rc={p.poll()} timed_out={timed_out} rawbytes={len(buf)} clean={len(clean)}\n")
if timed_out:
    sys.exit(124)
if not clean:
    sys.exit(1)
sys.stdout.write(clean + "\n")
sys.exit(0)
PY
security find-generic-password -s "Antigravity Safe Storage" >/dev/null 2>&1 || true  # macOS keyring warm-up (#51)

# --- Antigravity CLI (agy) - PRIMARY Google AI path (no -m; account-tier model) ---
probe_agy() {
  echo "bt_agy_available=false" > "$D/agy.env"
  command -v agy &>/dev/null || { echo "Antigravity (agy): not installed" > "$D/agy.log"; return; }
  local out rc
  for a in 1 2; do
    # Through the PTY wrapper (antigravity-cli#76): a bare 'agy --print' hangs here.
    out=$(python3 /tmp/bt_agy_pty.py 60 agy --print "Reply with the single word: ok" --dangerously-skip-permissions 2>/dev/null | head -5); rc=$?
    echo "$out" | grep -qi ok && { echo "bt_agy_available=true" > "$D/agy.env"; break; }
    [ "$rc" = "124" ] && break   # wrapper timed out -> treat as down, don't retry
  done
  grep -q true "$D/agy.env" && echo "Antigravity (agy): available [PRIMARY Google AI, PTY-wrapped]" > "$D/agy.log" \
    || echo "Antigravity (agy): empty/timeout (antigravity-cli#76) -> using gemini fallback" > "$D/agy.log"
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

# --- Codex (run against the isolated clean-slate home: no MCP boot, no memories) ---
probe_codex() {
  echo "bt_codex_available=false" > "$D/codex.env"
  command -v codex &>/dev/null || { echo "Codex: not installed" > "$D/codex.log"; return; }
  local out rc
  for a in 1 2; do
    out=$(rt 60 env CODEX_HOME="$bt_codex_home" codex exec --ephemeral -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "Reply with the single word: ok" < /dev/null 2>/dev/null | jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' 2>/dev/null); rc=${PIPESTATUS[0]}
    [ -n "$out" ] && [ "$out" != "null" ] && { echo "bt_codex_available=true" > "$D/codex.env"; break; }
    [ "$rc" = "124" ] && break
  done
  grep -q true "$D/codex.env" && echo "Codex: available [isolated home]" > "$D/codex.log" || echo "Codex: empty/timeout after warm-up retry" > "$D/codex.log"
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
bt_codex_home=${bt_codex_home:-${TMPDIR:-/tmp}/bt-codex-home}
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

# Codex with isolation + error detection
# - CODEX_HOME=clean profile: no memories/MCP/global AGENTS.md (unbiased reviewer; see "Codex Isolation")
# - -C scratch dir: don't read the repo we're standing in (context comes from $QUERY)
# - < /dev/null: prevents stdin hang (Codex reads stdin even when a prompt arg is passed)
# - stderr -> a file (not /dev/null): keeps it off the JSONL stream AND lets you read a hang/auth error
source /tmp/bt_models.env 2>/dev/null
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" timeout 150 codex exec --ephemeral -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "$QUERY" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
codex_exit=$?
codex_response=$(jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' /tmp/codex.json 2>/dev/null)
if [ "$codex_exit" -eq 124 ]; then
  echo "CODEX_FAILED: timed out after 150s (stderr: $(tail -1 /tmp/bt_codex.err))"
elif [ -z "$codex_response" ] || [ "$codex_response" = "null" ]; then
  echo "CODEX_FAILED: empty/unparseable response (stderr: $(tail -3 /tmp/bt_codex.err | tr '\n' ' '))"
else
  echo "$codex_response"
fi

# agy through the PTY wrapper (antigravity-cli#76: --print only flushes to a TTY).
# The wrapper IS the real bound; agy's own --print-timeout is non-functional.
# Wrapper exit: 0 = answer captured, 124 = timed out, 1 = empty (quota/auth).
agy_response=$(python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions 2>/tmp/bt_agy.err); agy_exit=$?
if [ "$agy_exit" -eq 124 ]; then
  agy_response=$(python3 /tmp/bt_agy_pty.py 120 agy --print "$QUERY" --dangerously-skip-permissions 2>/tmp/bt_agy.err); agy_exit=$?   # one retry, then give up
fi
if [ "$agy_exit" -eq 0 ] && [ -n "$agy_response" ]; then
  echo "$agy_response"
elif [ "$agy_exit" -eq 124 ]; then
  echo "AGY_FAILED: still hung under PTY after retry (antigravity-cli#76 subsequent-call hang, or quota) -> fall back to gemini ($(tail -1 /tmp/bt_agy.err))"
else
  echo "AGY_FAILED: empty response (quota exhaustion #56 or auth) -> fall back to gemini ($(tail -1 /tmp/bt_agy.err))"
fi

# Grok with error detection. The answer is .text; a failure arrives as {"type":"error","message":...} on stdout.
# Check for the error object FIRST: a 403 "out of credits / spending-limit" is a billing cap, NOT a login issue.
source /tmp/bt_models.env 2>/dev/null || bt_grok_model="grok-build"
grok_exec_out=$(timeout 120 grok -p "$QUERY" -m "$bt_grok_model" --output-format json 2>/tmp/bt_grok.err)
grok_err=$(echo "$grok_exec_out" | jq -r 'select(.type=="error") | .message' 2>/dev/null)
grok_response=$(echo "$grok_exec_out" | jq -r 'select(.type!="error") | .text' 2>/dev/null)
if [ -n "$grok_err" ]; then
  echo "GROK_FAILED: $grok_err"   # surfaces the real cause (e.g. out of credits) -- grok login will not fix a billing cap
elif [ -z "$grok_response" ] || [ "$grok_response" = "null" ]; then
  echo "GROK_FAILED: empty response (stderr: $(tail -1 /tmp/bt_grok.err)). If stderr says 'AuthorizationRequired', check credits/subscription before assuming you need 'grok login'."
else
  echo "$grok_response"
fi
```

> **Keep Codex stderr off stdout, but in a file.** Codex writes skill-loading noise and warnings to stderr; if that merges into stdout it corrupts the JSONL stream and `jq` silently returns nothing. Redirect to a **file** (`2>/tmp/bt_codex.err`), not `/dev/null`, so the stream stays clean *and* you can read the real error (timeout, auth, MCP hang) when the response is empty.
>
> **Grok parsing:** `--output-format json` returns `{"text": "...", "thought": "...", "stopReason": ...}` on success, or `{"type":"error","message":...}` on failure. Check `.type=="error"` first, then parse `.text`. The `plain` format prints the answer directly with no parsing, but `json` is required to detect the error object and capture into a variable.

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
source /tmp/bt_models.env 2>/dev/null || { bt_gemini_model="gemini-3.1-pro-preview"; bt_grok_model="grok-build"; bt_codex_home="/tmp/bt-codex-home"; }

# Consult the Google AI slot (agy preferred; gemini if agy unavailable) - ONE of these, not both
python3 /tmp/bt_agy_pty.py 120 agy --print "Review this implementation approach: [CONTEXT]" --dangerously-skip-permissions
# ...or, if bt_agy_available=false:
timeout 120 gemini -p "Review this implementation approach: [CONTEXT]" -m "$bt_gemini_model" --approval-mode yolo --no-sandbox -o text 2>/dev/null

# Consult Codex (via Bash tool) - isolated clean-slate home + scratch cwd (see "Codex Isolation")
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" codex exec --ephemeral -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "Review this implementation approach: [CONTEXT]" < /dev/null 2>/tmp/bt_codex.err | jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text'

# Consult Grok (via Bash tool) - check for an error object before parsing .text
timeout 120 grok -p "Review this implementation approach: [CONTEXT]" -m "$bt_grok_model" --output-format json 2>/tmp/bt_grok.err | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end'

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
source /tmp/bt_models.env 2>/dev/null
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" codex exec --ephemeral -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "Research: $TOPIC" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
```

Then read the results:
```bash
# Gemini result (plain text, no parsing needed)
cat /tmp/gemini.txt

# Codex result
jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' /tmp/codex.json
```

The Claude result comes back from the Task tool output directly.

## Skeptical Colleague Protocol (Grounding Standard)

Use this 6-step protocol on every braintrust member (instead of the old 2-3 bullet self-critique). It produces richer, more consistent, honest output.

**Protocol (include verbatim or via the grounding-protocol.md reference at top of prompts):**

1. **Goal Restatement (always first)**  
   Quote or paraphrase the Goal Card and original request. State success criteria in your own words.

2. **Assumptions Audit**  
   Explicitly list every assumption (stated or implicit). Flag risky ones.

3. **Evidence Mandate**  
   Do not trust the main agent's narrative. Independently verify claims by reading files, running commands, etc. Cite specific sources (file:line, output).

4. **Goal Fidelity Check**  
   Call out scope drift or loose alignment with the stated goal + success criteria.

5. **Honesty & Reasoning Review**  
   Surface optimistic thinking, unexamined risks, or reasoning gaps.

6. **Clear Verdict**  
   End with: **GROUNDED** (with evidence summary) or **NOT GROUNDED** (specific gaps + what must be fixed).

Always start prompts with the Goal Card. Reference it explicitly.

## Context Packaging + Goal Card (Critical for Consistency)

**The biggest source of "sometimes rich, sometimes not" results is inconsistent context that the main agent chooses to share.** Fix this by making the braintrust skill own the curation.

### Always Start With a Goal Card
Before any parallel calls:
- `mkdir -p .braintrust/goal-cards`
- Create or load the Goal Card at `.braintrust/goal-cards/<task-slug>.md` (see goal-card-template.md).
- It must contain: one-sentence goal, explicit success criteria, out-of-scope, key constraints.
- Include the full Goal Card text at the top of **every** prompt to braintrust members.
- Reference it explicitly: "Read the Goal Card first. Your entire response must stay grounded against it."

Example Goal Card header (full card lives at `.braintrust/goal-cards/<slug>.md`):
```
## GOAL CARD (read this first)
session_anchor: 2026-06-17-auth-work   # use the same value for the entire session/thread
Goal: [one sentence]
Success Criteria:
- ...
Out of Scope: ...
```

### Curated Context (do this in the skill, not left to the host)
Actively gather:
- Goal Card (from `.braintrust/goal-cards/<slug>.md`)
- Original request
- Key files / diffs (read them yourself with tools)
- Current state / decisions

Then package a tight block:

```
## GOAL CARD
[full card]

## CURATED CONTEXT (verified by me)
- Project: ...
- Relevant files read: [list with key excerpts]
- Recent decisions: ...
- Constraints: ...

## QUESTION / TASK
[the ask]

## SKEPTICAL COLLEAGUE PROTOCOL (apply this)
**Default history scope:** Only reference prior Goal Cards that share the exact same `session_anchor` as the current one. Broaden only if explicitly asked.

1. Restate the goal and success criteria in your own words.
2. Explicitly list every assumption you or the work is making.
3. Ground every claim in the provided context + fresh evidence you gather (read files, run commands if appropriate). Cite specific sources.
4. Call out any goal drift or loose alignment.
5. Surface optimistic thinking or unexamined risks.
6. End with a clear verdict: GROUNDED (with evidence summary) or NOT GROUNDED (specific gaps + what to fix).
```

### For Codex (still use XML for best results)
Wrap the above in the <task> and <grounding_rules> blocks, plus the protocol in <verification_loop> or additional instructions.

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
## GOAL CARD
[insert or reference .braintrust/goal-cards/<slug>.md here]

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

source /tmp/bt_models.env 2>/dev/null
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" codex exec --ephemeral -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "$REVIEW_PROMPT" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
```

## Saving Consultation Sessions

After synthesizing, save a session file to `.braintrust/sessions/` for future reference. Also keep the Goal Card at `.braintrust/goal-cards/`.

Create dirs if needed: `mkdir -p .braintrust/sessions .braintrust/goal-cards`

Filename: `YYYY-MM-DD-HMMam-slug.md` (e.g., `2026-02-16-230pm-rate-limiting-review.md`). 12-hour time, no leading zero on hour, lowercase am/pm.

Use this format to document the full consultation for future reference:

```markdown
# [Short Topic Description]

## Goal Card
Path: `.braintrust/goal-cards/<slug>.md`
session_anchor: [value from the card — this defines the default "current session" scope for prior goals]

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
source /tmp/bt_models.env 2>/dev/null
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" codex exec --ephemeral -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "$AUDIT_PROMPT" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex-security.json
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

> The Google AI leg above uses `gemini`; if `bt_agy_available=true`, replace it with `python3 /tmp/bt_agy_pty.py 120 agy --print "$AUDIT_PROMPT" --dangerously-skip-permissions > /tmp/agy-security.txt` instead (PTY-wrapped per antigravity-cli#76; one Google voice, not both).

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
source /tmp/bt_models.env 2>/dev/null
CODEX_HOME="${bt_codex_home:-/tmp/bt-codex-home}" codex exec --ephemeral -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "Research: best practices for implementing rate limiting in Node.js APIs" < /dev/null 2>/tmp/bt_codex.err > /tmp/codex.json
```

**Tool call 4** - Bash tool (run_in_background: true):
```bash
source /tmp/bt_models.env 2>/dev/null || bt_grok_model="grok-build"
timeout 120 grok -p "Research: best practices for implementing rate limiting in Node.js APIs" -m "$bt_grok_model" --output-format json 2>/dev/null | jq -r '.text' > /tmp/grok.txt
```

Then synthesize findings from every source that responded. (Swap Tool call 2 for `python3 /tmp/bt_agy_pty.py 120 agy --print "$TOPIC..." --dangerously-skip-permissions > /tmp/gemini.txt` when `bt_agy_available=true`; PTY-wrapped per antigravity-cli#76.)

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
| `--print-timeout` | Timeout for print mode (default `5m0s`). **Non-functional in non-TTY/headless use** (antigravity-cli#76); use an external bound (the PTY wrapper). |
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
| `--ephemeral` | Skip persisting the NEW session. Does **not** disable loading memories, MCP, or global AGENTS.md. |
| `--skip-git-repo-check` | Run outside a git repo |
| `--dangerously-bypass-approvals-and-sandbox` | Skip all prompts, no sandbox. For externally sandboxed envs only. |
| `--color` | ANSI color control: always/never/auto |

> **`CODEX_HOME` (env var, not a flag)** points Codex at a profile directory (default `~/.codex`). Set it to a clean throwaway dir to get an unbiased reviewer with no memories, no MCP servers, and no global `AGENTS.md`. This is the only reliable way to isolate Codex; `--ephemeral` and `-C` do not do it. The probe builds `$bt_codex_home` for this. See "Codex Isolation: Clean-Slate Reviewer".
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
13. **Always run Codex with an isolated `CODEX_HOME`** - `--ephemeral` is NOT a blank slate: Codex still loads `~/.codex` memories, MCP servers, and the global `AGENTS.md`. That contaminates reviews (observed: an off-topic answer pulled from a memory) and biases synthesis. Point `CODEX_HOME` at a clean throwaway profile (the probe builds `$bt_codex_home`) and add `-C` to a scratch dir. `-C /tmp` alone is not enough. See "Codex Isolation".
14. **Always pass `-p` to Grok** - Without it, grok opens its interactive TUI instead of answering headlessly. Parse `.text` (not `.thought`) from `--output-format json`, and check `.type=="error"` first.
15. **A Grok `AuthorizationRequired` error is usually billing, not login** - The JSON body says the real cause. `out of credits / spending-limit` means add credits or use an `XAI_API_KEY` with balance; `grok login` will not fix it.
16. **Always run agy through the PTY wrapper** - `agy --print` only flushes to a real TTY (antigravity-cli#76), so a bare subprocess call hangs (macOS) or returns empty (Win/Linux). `python3 /tmp/bt_agy_pty.py <timeout> agy --print "$QUERY" --dangerously-skip-permissions` gives it a pseudo-terminal and is the real timeout bound (agy's own `--print-timeout` is ignored). Verified on macOS; on Windows fall back to gemini. The probe writes the wrapper.
17. **Capture CLI stderr to a file, not `/dev/null`** - `2>/dev/null` is why agy timeouts and grok billing errors get misdiagnosed. Use `2>/tmp/bt_<cli>.err`, check the exit code, and surface the captured error when a response is empty.
18. **Never auto-fix review findings** - Present findings and let the user decide what to act on

## Further Reading

- [Claude Code Agent SDK (headless mode)](https://code.claude.com/docs/en/headless)
- [Gemini CLI Headless Mode](https://google-gemini.github.io/gemini-cli/docs/cli/headless.html)
- [Codex CLI Non-Interactive Mode](https://developers.openai.com/codex/noninteractive/)
- [Claude + Gemini Workflow: When AIs Start Gossiping About Your Code](https://byjos.dev/claude-gemini-workflow/)
- [Claude Code Bridge: Multi-AI Collaboration](https://github.com/bfly123/claude_code_bridge)
- [Using Gemini CLI for Large Codebase Analysis](https://gist.github.com/steipete/20ed650822f1ac835144bfd328c872b7)
- [Gemini CLI Code Review and Security Analysis](https://codelabs.developers.google.com/gemini-cli-code-analysis)
