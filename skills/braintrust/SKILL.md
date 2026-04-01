---
name: braintrust
description: Orchestrate other AI CLIs (Gemini, Codex, Claude Code) for second opinions, research, codebase analysis, design review, security audits, and parallel research
---

# Braintrust

Consult your AI braintrust - the other AI CLIs available in your environment - for second opinions, research, and codebase analysis.

> **Important:** Run ALL braintrust CLI invocations (including health checks and consultations) as background tasks using `run_in_background: true`. This allows monitoring progress instead of blocking.

## Default Behavior: Consult ALL THREE

**Unless the user explicitly requests a specific model or narrower scope, ALWAYS consult all three models (Claude, Gemini, Codex) in parallel.**

This is not optional. The entire value of the braintrust is multi-model coverage - each model catches different issues. Consulting only one or two models defeats the purpose.

**Launch all three in a single parallel batch using multiple tool calls in one response:**

> **First call in a session?** Run the model probe (see "Model Discovery" section) before launching consultations. This takes ~10 seconds and ensures you use the best available Gemini model. If `/tmp/bt_models.env` already exists from an earlier call, skip the probe.

1. **Claude**: Use the Task tool with `subagent_type: "general-purpose"` and `run_in_background: true`
2. **Gemini** (if `bt_gemini_available=true`): Use the Bash tool with `run_in_background: true`:
   ```bash
   source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-2.5-pro"
   gemini -p "$QUERY" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null
   ```
3. **Codex** (if `bt_codex_available=true`): Use the Bash tool with `run_in_background: true`:
   ```bash
   codex exec --ephemeral -s read-only --json --skip-git-repo-check "$QUERY" 2>/dev/null > /tmp/codex.json
   ```

> **Skip unavailable CLIs.** If the probe marked a CLI as unavailable, do not launch it. Note the gap in your synthesis instead.

Present each model's findings to the user as they arrive. After all three respond, synthesize the findings and save a session file.

**Only skip a model if:**
- The user explicitly asks for a specific model (e.g., "ask Gemini about...")
- A model fails and diagnostics show it's unavailable
- The task is a trivial single-fact lookup (rare)

**Do NOT rationalize using fewer models.** Thoughts like "Gemini is better for this" or "two models should be enough" are wrong - always use all three unless directed otherwise.

---

## Why Multi-Model Collaboration Works

Each AI model has different training data, reasoning patterns, and blind spots. Research and developer experience consistently shows:

- **When a model introduces a bug, it struggles to fix it** - but a different model often spots it instantly
- **Combined approaches outperform individual models** on complex tasks
- **Claude excels at detailed, conversational coding work; Gemini provides strategic overview**
- **Different perspectives catch edge cases one model would miss**

The result feels like "working with a small, experienced development team" rather than a single assistant.

## Core Concept

**All three CLIs are available as your braintrust.** How you call each depends on where you're running:

| You Are In | Your Braintrust | How to Call Claude |
|------------|-----------------|-------------------|
| Claude Code | Gemini + Codex + Claude | **Task tool** with subagent (the CLI blocks nested sessions) |
| Gemini CLI | Claude + Codex | `claude -p "query" --model sonnet --output-format json` |
| Codex CLI | Claude + Gemini | `claude -p "query" --model sonnet --output-format json` |

### Calling Claude from Claude Code

**You CANNOT run `claude -p` from within Claude Code.** The CLI detects nested sessions and blocks them with: "Claude Code cannot be launched inside another Claude Code session."

Instead, use the Task tool to spawn a separate Claude subagent:

```
Use the Task tool with `subagent_type: "general-purpose"` for research and code review,
or `subagent_type: "Explore"` for quick codebase searches.
This spawns an independent Claude session with its own context.
```

This means **all three models are always available** regardless of which harness you're in.

## Prerequisites

**Skip health checks by default** - just try to use the braintrust. Only run diagnostics if a consultation fails.

**If a CLI fails**, run these to diagnose:

```bash
# Diagnostic health checks (only run if needed)
# Note: Claude health check must run outside Claude Code (nested sessions blocked)
source /tmp/bt_models.env 2>/dev/null || bt_gemini_fast="gemini-2.5-flash"
gemini -p "say ok" -m "$bt_gemini_fast" --approval-mode yolo --sandbox=none -o text 2>/dev/null | grep -qi "ok" && echo "Gemini: OK" || echo "Gemini: FAILED"
codex exec --ephemeral -s read-only --json --skip-git-repo-check "test" 2>/dev/null | head -5 && echo "Codex: OK" || echo "Codex: FAILED"
```

When running from Claude Code, Claude itself is always available via the Task tool. No health check needed.

**If missing, install:**
- Claude: `npm install -g @anthropic-ai/claude-code`
- Gemini: `npm install -g @google/gemini-cli` (also available via `brew install gemini-cli`)
- Codex: `npm install -g @openai/codex` (also available via `brew install --cask codex`)

**Required utilities:** `jq` is used for parsing Codex JSONL output. Pre-installed on macOS. On Linux: `apt install jq` or `brew install jq`. Gemini uses `-o text` which needs no parsing.

### Common Codex Failure Modes

If Codex fails, check these in order:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `You've hit your usage limit` | ChatGPT free/Plus rate limit | Wait for reset or switch to API key auth with `CODEX_API_KEY` |
| `failed to stat skills entry` (stderr) | Broken symlink in `~/.codex/skills/` | Remove the dead symlink. Non-blocking but noisy. |
| Hangs on startup | MCP servers in `~/.codex/config.toml` failing to initialize | Check `[mcp_servers]` section. Servers with `required = true` cause immediate exit. Remove or fix broken servers. |
| `not a git repository` | Codex requires a git repo by default | Add `--skip-git-repo-check` to exec commands |
| `missing YAML frontmatter` (stderr) | Codex loading incompatible skill files | Non-blocking stderr noise. Safe to ignore. |

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
| Slow startup | Extensions loading on every invocation. | The `--sandbox=none` flag helps. If still slow, consider `--extensions ""`. |
| `FatalTurnLimitedError` with `-o json` | `-o json` triggers internal tool use that counts against turn limits. | Use `-o text` instead (already our default). |

**Free-tier note:** As of March 2026, Google OAuth free-tier users only get Flash-level models. Pro models require either a Google One AI Pro subscription with billing linked, or an explicit `GEMINI_API_KEY` with billing enabled. The probe will fall back to `gemini-2.5-pro` (stable) automatically.

## Braintrust Defaults

**Always use explicit capable models.** CLI headless modes auto-route to weaker models when called without specifying a model. Start with the best model and fall back if it fails.

| CLI | Default Command | Fast Option |
|-----|-----------------|-------------|
| **Claude** (from Claude Code) | Task tool with `subagent_type: "general-purpose"` | Task tool with `model: "haiku"` |
| **Claude** (from other CLIs) | `claude -p "query" --model sonnet --output-format json` | `--model haiku` |
| **Gemini** | Uses `$bt_gemini_model` from model probe (see below) | Uses `$bt_gemini_fast` from model probe |
| **Codex** | `codex exec --ephemeral -s read-only --json --skip-git-repo-check "query" 2>/dev/null` | N/A |

### Gemini Standard Flags

**Every headless Gemini call must include these flags.** They prevent silent hangs and unnecessary overhead:

```bash
gemini -p "$QUERY" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null
```

| Flag | Why |
|------|-----|
| `--approval-mode yolo` | Prevents Gemini from hanging when it wants to use a tool and waits for approval that never comes in headless mode |
| `--sandbox=none` | Skips sandbox initialization overhead. Braintrust queries are read-only consultations, no sandboxing needed. |
| `-o text` | Avoids `FatalTurnLimitedError` with `-o json` when `maxSessionTurns: 1`. Text needs no parsing. |
| `2>/dev/null` | Suppresses extension/MCP loading noise on stderr |

All Gemini examples in this file assume these flags. When you see a short example like `gemini -p "query" -m "$bt_gemini_model" -o text 2>/dev/null`, always add `--approval-mode yolo --sandbox=none` in the actual command.

### Model Discovery (Run Once Per Session)

**Model names change frequently.** Instead of hardcoding model IDs, run this probe at the start of each braintrust session to discover the best available models for each CLI. Cache the results in `/tmp/bt_models.env` and source them for all subsequent calls.

```bash
cat > /tmp/bt_probe.sh << 'PROBE'
#!/bin/bash
# Braintrust model probe - discovers best available model for each CLI
# Tries models in priority order (best first), picks the first that responds

echo "--- Braintrust Model Probe ---"

# Use timeout if available, otherwise run without it
if command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout"
else
  TIMEOUT_CMD=""
fi
run_with_timeout() { if [ -n "$TIMEOUT_CMD" ]; then $TIMEOUT_CMD "$@"; else shift; "$@"; fi; }

# --- Gemini ---
bt_gemini_model=""
bt_gemini_fast=""
bt_gemini_available="false"
if command -v gemini &>/dev/null; then
  gemini_probe() {
    run_with_timeout 20 gemini -p "say ok" -m "$1" --approval-mode yolo --sandbox=none -o text 2>/dev/null | grep -qi "ok"
  }
  # Order: gemini-2.5-pro first (stable), then 3.1-pro-preview (flaky: upstream bug #24290
  # causes empty responses, and availability is inconsistent with 429s on many auth tiers)
  for m in "gemini-2.5-pro" "gemini-3.1-pro-preview"; do
    if gemini_probe "$m"; then bt_gemini_model="$m"; break; fi
  done
  for m in "gemini-2.5-flash" "gemini-3-flash-preview"; do
    if gemini_probe "$m"; then bt_gemini_fast="$m"; break; fi
  done
  if [ -n "$bt_gemini_model" ]; then
    bt_gemini_available="true"
    echo "Gemini: $bt_gemini_model (fast: $bt_gemini_fast)"
  else
    echo "Gemini: CLI found but no models responded"
  fi
else
  echo "Gemini: CLI not installed"
fi

# --- Codex ---
bt_codex_available="false"
if command -v codex &>/dev/null; then
  codex_result=$(run_with_timeout 30 codex exec --ephemeral -s read-only --json --skip-git-repo-check "Say ok" 2>/dev/null | jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' 2>/dev/null)
  if [ -n "$codex_result" ] && [ "$codex_result" != "null" ]; then
    bt_codex_available="true"
    echo "Codex: available"
  else
    echo "Codex: CLI found but returned empty response"
  fi
else
  echo "Codex: CLI not installed"
fi

# --- Claude (from Claude Code) ---
# Always available via Task tool when running in Claude Code. No probe needed.
echo "Claude: available (via Task tool)"

# Write results
cat > /tmp/bt_models.env << EOF
bt_gemini_model=${bt_gemini_model:-gemini-2.5-pro}
bt_gemini_fast=${bt_gemini_fast:-gemini-2.5-flash}
bt_gemini_available=${bt_gemini_available}
bt_codex_available=${bt_codex_available}
EOF

echo "--- Results cached to /tmp/bt_models.env ---"
cat /tmp/bt_models.env
PROBE
chmod +x /tmp/bt_probe.sh && bash /tmp/bt_probe.sh
```

After the probe runs, use the discovered models in all commands:

```bash
# Source at the start of each Bash tool call that invokes Gemini or Codex
source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-2.5-pro"
```

**Graceful degradation rules:**
- If `bt_gemini_available=false`, skip Gemini and note it in the synthesis
- If `bt_codex_available=false`, skip Codex and note it in the synthesis
- Claude is always available via the Task tool when running in Claude Code
- If only one CLI is available, run it alone and note the limited coverage
- **Never let a single CLI failure block the entire braintrust consultation**

### Handling Errors During Consultation

Even after the probe, a model can fail mid-consultation (quota, rate limit, transient error). Wrap every CLI call to detect and report failures:

```bash
# Gemini with error detection and retry
source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-2.5-pro"
gemini_response=$(timeout 120 gemini -p "$QUERY" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null)
gemini_exit=$?
if [ $gemini_exit -eq 124 ]; then
  echo "GEMINI_FAILED: timed out after 120s"
elif [ $gemini_exit -eq 53 ]; then
  echo "GEMINI_FAILED: turn limit exceeded (check maxSessionTurns in ~/.gemini/settings.json)"
elif [ -z "$gemini_response" ]; then
  # Retry once: gemini-3.x has an upstream bug (#24290) where empty responses happen intermittently
  gemini_response=$(timeout 120 gemini -p "$QUERY" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null)
  if [ -z "$gemini_response" ]; then
    echo "GEMINI_FAILED: empty response after retry (check model availability or rate limits)"
  else
    echo "$gemini_response"
  fi
else
  echo "$gemini_response"
fi

# Codex with error detection (CRITICAL: always redirect stderr to avoid blank output)
codex exec --ephemeral -s read-only --json --skip-git-repo-check "$QUERY" 2>/dev/null > /tmp/codex.json
codex_response=$(jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' /tmp/codex.json 2>/dev/null)
if [ -z "$codex_response" ] || [ "$codex_response" = "null" ]; then
  echo "CODEX_FAILED: empty or unparseable response"
else
  echo "$codex_response"
fi
```

> **Codex blank output fix:** Codex writes skill-loading noise and warnings to stderr. If stderr is not redirected with `2>/dev/null`, it corrupts the JSONL stream and `jq` silently returns nothing. **Always use `2>/dev/null`** when piping Codex output.

### Model Fallback Chains

If a model returns an error (404, quota, etc.), fall back to the next model in the chain. The probe handles Gemini automatically. For manual fallback:

| CLI | Primary | Fallback 1 | Fallback 2 |
|-----|---------|------------|------------|
| **Claude** | `opus` | `sonnet` | `haiku` |
| **Gemini** | `gemini-2.5-pro` (stable) | `gemini-3.1-pro-preview` (flaky) | N/A |
| **Gemini (fast)** | `gemini-2.5-flash` (stable) | `gemini-3-flash-preview` | N/A |
| **Codex** | (default, currently gpt-5.4) | N/A | N/A |

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
| **Security Audit** | Parallel all three | Verify auth patterns, SQL injection protection, rate limiting - each model catches different vulnerabilities |
| **Design System Extraction** | Gemini (best available) | Analyzes brand elements (colors, fonts, spacing), generates consistent component libraries |
| **Framework Migration** | Gemini | Side-by-side comparisons (React->Vue, Django->Flask), translates patterns with full context |
| **Parallel Research** | All three | 3x speed, diverse sources, cross-validate findings |

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
# Consult Gemini (via Bash tool) - uses probed model
source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-2.5-pro"
timeout 120 gemini -p "Review this implementation approach: [CONTEXT]" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null

# Consult Codex (via Bash tool)
codex exec --ephemeral -s read-only --json --skip-git-repo-check "Review this implementation approach: [CONTEXT]" 2>/dev/null | jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text'

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
# All examples below assume: source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-2.5-pro"

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
# All examples below assume: source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-2.5-pro"

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
source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-2.5-pro"

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
source /tmp/bt_models.env 2>/dev/null || bt_gemini_fast="gemini-2.5-flash"
gemini -p "[QUERY]" -m "$bt_gemini_fast" --approval-mode yolo --sandbox=none -o text 2>/dev/null
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
source /tmp/bt_models.env 2>/dev/null || bt_gemini_model="gemini-2.5-pro"
timeout 120 gemini -p "Research: $TOPIC" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null > /tmp/gemini.txt
```

**Tool call 3** - Bash tool (run_in_background: true):
```bash
codex exec --ephemeral -s read-only --json --skip-git-repo-check "Research: $TOPIC" 2>/dev/null > /tmp/codex.json
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
- All models (Gemini, Codex, Claude) consistently follow the self-critique instruction
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

codex exec --ephemeral -s read-only --json --skip-git-repo-check "$REVIEW_PROMPT" 2>/dev/null > /tmp/codex.json
```

## Saving Consultation Sessions

After synthesizing, save a session file to `.braintrust/sessions/` for future reference. Create the directory if it doesn't exist (`mkdir -p .braintrust/sessions`).

Filename: `YYYY-MM-DD-HMMam-slug.md` (e.g., `2026-02-16-230pm-rate-limiting-review.md`). 12-hour time, no leading zero on hour, lowercase am/pm.

Use this format to document the full consultation for future reference:

```markdown
# [Short Topic Description]

## Query
[The context-packaged prompt sent to all models]

## Gemini
[Parsed response, or "Model unavailable" / "Model skipped"]

## Codex
[Parsed response, or "Model unavailable" / "Model skipped"]

## Claude
[Subagent response, or "Model unavailable" / "Model skipped"]

## Synthesis
[Consensus, divergence, and actionable recommendations]
```

## Model Reference

> **Note:** Model names change frequently. Use the model probe (see "Model Discovery") instead of hardcoding. The table below is a reference snapshot. Run the probe to get current model IDs.

### Claude Code

| Model | Flag Value | Context | Use Case |
|-------|-----------|---------|----------|
| **Sonnet 4.6** | `sonnet` | 200K | Default, balanced performance |
| **Opus 4.6** | `opus` | 200K | Hardest reasoning problems |
| **Haiku 4.5** | `haiku` | 200K | Speed, cost efficiency |

### Gemini (as of April 2026)

| Model | Flag Value | Context | Status |
|-------|-----------|---------|--------|
| **Gemini 2.5 Pro** | `gemini-2.5-pro` | 1M | **Stable, recommended default.** Probe tries this first. |
| **Gemini 2.5 Flash** | `gemini-2.5-flash` | 1M | **Stable, recommended fast default.** |
| **Gemini 3.1 Pro** | `gemini-3.1-pro-preview` | 1M | Preview. Flaky: empty responses (#24290), 429s, retry loops (#23762). Probe fallback only. |
| **Gemini 3 Flash** | `gemini-3-flash-preview` | 1M | Preview, fast. More reliable than 3.1 Pro but still preview. |
| **Gemini 3.1 Flash Lite** | `gemini-3.1-flash-lite-preview` | 1M | Preview, cost-efficient |

> **Why 2.5 before 3.x?** Gemini 3.x models have an upstream bug (#24290) where the InvalidStreamError retry logic only applies to Gemini 2 models. On 3.x, empty responses happen intermittently and are not retried. Combined with capacity limits (429s) and auth-tier restrictions, 2.5-pro is more reliable for automated consultations. The probe will still discover and use 3.x if it responds successfully.
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
gemini -p "your query" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null

# Capture to variable
gemini_response=$(timeout 120 gemini -p "your query" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null)

# Save to file for later reading
timeout 120 gemini -p "your query" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null > /tmp/gemini.txt
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
codex exec --ephemeral -s read-only --json --skip-git-repo-check "query" -o /tmp/codex-result.txt
```

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

Run all three in parallel using multiple tool calls:

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
6. Rate limiting gaps" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null > /tmp/gemini-security.txt
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
codex exec --ephemeral -s read-only --json --skip-git-repo-check "$AUDIT_PROMPT" 2>/dev/null > /tmp/codex-security.json
```

Then collect and compare findings from all three.

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

Run all three using multiple tool calls in one response:

**Tool call 1** - Task tool (run_in_background: true):
```
subagent_type: "general-purpose"
prompt: "Research: best practices for implementing rate limiting in Node.js APIs"
model: "sonnet"
```

**Tool call 2** - Bash tool (run_in_background: true):
```bash
timeout 120 gemini -p "Research: best practices for implementing rate limiting in Node.js APIs" -m "$bt_gemini_model" --approval-mode yolo --sandbox=none -o text 2>/dev/null > /tmp/gemini.txt
```

**Tool call 3** - Bash tool (run_in_background: true):
```bash
codex exec --ephemeral -s read-only --json --skip-git-repo-check "Research: best practices for implementing rate limiting in Node.js APIs" 2>/dev/null > /tmp/codex.json
```

Then synthesize findings from all three sources.

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

## Tips

1. **Use Gemini for design & frontend** - Strong performance on UI challenges and design system analysis
2. **Use Gemini for large context** - 1M tokens native vs 200K for Claude / 192K for Codex; can analyze 40K+ lines holistically
3. **Cross-model review catches bugs** - When a model writes code, it's blind to its own mistakes; different models spot issues instantly
4. **Use the model probe** - Run the model discovery probe once per session; never hardcode Gemini model names
5. **Use `-o text` for Gemini** - `-o json` breaks with `maxSessionTurns: 1`. Text output needs no parsing.
6. **Parallel is fast** - Run all three simultaneously for 3x speed and diverse perspectives
7. **Different models, different blind spots** - Each AI has different training; combined approaches outperform individuals
8. **Always redirect Gemini stderr** - Use `2>/dev/null` to suppress extension warnings and MCP noise
9. **Never run `claude -p` from Claude Code** - It will fail. Use the Task tool for the Claude leg of any consultation
10. **Use `codex exec review` for code review** - The dedicated review subcommand auto-reads git diffs; no need to craft review prompts manually
11. **Always use `--ephemeral -s read-only` for Codex** - Braintrust consultations are stateless and read-only. Only switch to `-s workspace-write` when the user explicitly asks Codex to make changes.
12. **Never auto-fix review findings** - Present findings and let the user decide what to act on

## Further Reading

- [Claude Code Agent SDK (headless mode)](https://code.claude.com/docs/en/headless)
- [Gemini CLI Headless Mode](https://google-gemini.github.io/gemini-cli/docs/cli/headless.html)
- [Codex CLI Non-Interactive Mode](https://developers.openai.com/codex/noninteractive/)
- [Claude + Gemini Workflow: When AIs Start Gossiping About Your Code](https://byjos.dev/claude-gemini-workflow/)
- [Claude Code Bridge: Multi-AI Collaboration](https://github.com/bfly123/claude_code_bridge)
- [Using Gemini CLI for Large Codebase Analysis](https://gist.github.com/steipete/20ed650822f1ac835144bfd328c872b7)
- [Gemini CLI Code Review and Security Analysis](https://codelabs.developers.google.com/gemini-cli-code-analysis)
