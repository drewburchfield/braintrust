#!/usr/bin/env bash
#
# SessionStart hook: Check AI CLI availability
# Reports which CLIs (agy, codex, grok, opencode, claude) are installed so the
# host knows what tools are available before the user asks.
#
# Note: this only checks that the binary is on PATH (command -v). Authentication
# and cold-start liveness are verified separately by scripts/bt_probe.sh.
#

# Consume hook input from stdin
cat > /dev/null

results=()

check_cli() {
  local name="$1"
  local install_hint="$2"

  if command -v "$name" > /dev/null 2>&1; then
    results+=("$name (available)")
  else
    results+=("$name (NOT FOUND - $install_hint)")
  fi
}

check_cli "agy" "install with: curl -fsSL https://antigravity.google/cli/install.sh | bash (Google AI path; no Gemini CLI)"
check_cli "codex" "install with: npm install -g @openai/codex"
check_cli "grok" "install with: curl -fsSL https://x.ai/cli/install.sh | bash (Grok Build; auth: grok login; default model grok-4.6)"
check_cli "opencode" "install from https://opencode.ai (uses your configured default model)"
check_cli "claude" "install with: npm install -g @anthropic-ai/claude-code"

# Explicitly do NOT check gemini — not a braintrust member.

joined=$(printf '%s, ' "${results[@]}")
echo "Braintrust CLIs: ${joined%, }"
exit 0
