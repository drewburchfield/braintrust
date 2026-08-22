#!/usr/bin/env bash
# Braintrust model probe - discovers installed + AUTHENTICATED CLIs and best models.
#
# Members (no Gemini CLI): Claude (host-dependent), agy, Codex, Grok, OpenCode.
# Runs checks in PARALLEL. Cache: /tmp/bt_models.env
#
# Usage:
#   bash scripts/bt_probe.sh
#   # or, when skill is installed as a plugin:
#   bash "${CLAUDE_PLUGIN_ROOT:-.}/scripts/bt_probe.sh"
#
# Design notes (2026-08 dogfood):
#  * Gemini CLI is NOT probed. Google voice = agy only.
#  * Grok default comes from `grok models` ("Default model:"); fallback grok-4.6.
#  * Codex uses isolated CODEX_HOME + --ignore-user-config for clean-slate.
#  * Codex primary model is gpt-5.6-sol (GPT-5.6 Sol). Requires Codex CLI >= 0.144.0.
#    Because --ignore-user-config is set, we MUST pass -m explicitly (user config is ignored).
#  * OpenCode uses the user's configured/default model (opencode.json "model",
#    else last non-free session model). Never hardcode a specific GLM id.
#    If the resolved id contains glm-5.3, set bt_opencode_variant=max (thinking).
#  * agy default Google pin is gemini-3.7-flash-high when `agy models` lists it.
#  * Claude consult default is opus (liveness probe uses haiku).
#  * agy 1.1.0+ often works bare-piped; PTY wrapper is durable fallback.

set -u
echo "--- Braintrust Model Probe (parallel) ---"
D=$(mktemp -d "${TMPDIR:-/tmp}/bt_probe.XXXXXX")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v timeout &>/dev/null; then TO="timeout"
elif command -v gtimeout &>/dev/null; then TO="gtimeout"
else TO=""; fi
rt() { if [ -n "$TO" ]; then $TO "$@"; else shift; "$@"; fi; }  # exit 124 == timed out

# --- Clean-slate Codex profile (no memories, no MCP, no global AGENTS.md) ---
_bt_tmp="${TMPDIR:-/tmp}"
_bt_tmp="${_bt_tmp%/}"
bt_codex_home="${_bt_tmp}/bt-codex-home"
mkdir -p "$bt_codex_home"
printf '# braintrust isolated profile: no memories, no MCP, no global AGENTS.md\n' > "$bt_codex_home/config.toml"
[ -f "$HOME/.codex/auth.json" ] && cp "$HOME/.codex/auth.json" "$bt_codex_home/auth.json" 2>/dev/null

# --- agy PTY wrapper (fallback for non-TTY flush bugs) ---
PTY_SRC="$SCRIPT_DIR/bt_agy_pty.py"
if [ -f "$PTY_SRC" ]; then
  cp "$PTY_SRC" /tmp/bt_agy_pty.py
else
  # Inline minimal fallback if script missing from install
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
if timed_out: sys.exit(124)
if not clean: sys.exit(1)
sys.stdout.write(clean + "\n"); sys.exit(0)
PY
fi
# macOS keychain warm-up (antigravity-cli#51)
security find-generic-password -s "Antigravity Safe Storage" >/dev/null 2>&1 || true

# --- Antigravity (agy) - ONLY Google path ---
# Pin Gemini 3.7 Flash High when the account lists it. Parse --output-format json
# (.status / .response). Text + PTY remain fallbacks for older CLIs / hangs.
probe_agy() {
  printf 'bt_agy_available=false\nbt_agy_needs_pty=false\nbt_agy_model=\n' > "$D/agy.env"
  command -v agy &>/dev/null || { echo "Antigravity (agy): not installed" > "$D/agy.log"; return; }
  local model="" listing out rc needs_pty=false response=""
  listing=$(agy models 2>/dev/null) || true
  if printf '%s\n' "$listing" | grep -q 'gemini-3.7-flash-high'; then
    model="gemini-3.7-flash-high"
  fi
  local args=(agy --print "Reply with the single word: ok" --dangerously-skip-permissions --output-format json)
  [ -n "$model" ] && args+=(--model "$model")
  out=$(rt 45 "${args[@]}" 2>/dev/null); rc=$?
  response=$(printf '%s\n' "$out" | jq -r '.response // empty' 2>/dev/null)
  if ! echo "$response" | grep -qi ok; then
    args=(agy --print "Reply with the single word: ok" --dangerously-skip-permissions)
    [ -n "$model" ] && args+=(--model "$model")
    out=$(rt 45 "${args[@]}" 2>/dev/null | head -5); rc=$?
    response=$out
  fi
  if ! echo "$response" | grep -qi ok; then
    if [ "$rc" = "124" ] || [ -z "$response" ]; then
      args=(agy --print "Reply with the single word: ok" --dangerously-skip-permissions)
      [ -n "$model" ] && args+=(--model "$model")
      out=$(python3 /tmp/bt_agy_pty.py 60 "${args[@]}" 2>/dev/null | head -5); rc=$?
      needs_pty=true
      response=$out
    fi
  fi
  if echo "$response" | grep -qi ok; then
    printf 'bt_agy_available=true\nbt_agy_needs_pty=%s\nbt_agy_model=%s\n' "$needs_pty" "$model" > "$D/agy.env"
    echo "Antigravity (agy): available [Google AI only; pty=$needs_pty; model=${model:-account-tier}]" > "$D/agy.log"
  else
    echo "Antigravity (agy): empty/timeout (auth or quota)" > "$D/agy.log"
  fi
}

# --- Codex (isolated clean-slate + ignore-user-config; primary model gpt-5.6-sol) ---
# GPT-5.6 Sol is the flagship OpenAI model for this slot. Model id: gpt-5.6-sol.
# Requires Codex CLI >= 0.144.0. Older CLIs return 400 "requires a newer version of Codex".
probe_codex() {
  printf 'bt_codex_available=false\nbt_codex_model=gpt-5.6-sol\n' > "$D/codex.env"
  command -v codex &>/dev/null || { echo "Codex: not installed" > "$D/codex.log"; return; }
  local out rc model="" ver
  ver=$(codex --version 2>/dev/null | head -1)
  # Prefer Sol; fall back to product default only if Sol is unavailable (old CLI / no access).
  for model in "gpt-5.6-sol" ""; do
    for a in 1 2; do
      if [ -n "$model" ]; then
        out=$(rt 70 env CODEX_HOME="$bt_codex_home" codex exec --ephemeral --ignore-user-config -s read-only --json --skip-git-repo-check -m "$model" -C "${TMPDIR:-/tmp}" "Reply with the single word: ok" < /dev/null 2>/dev/null | jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' 2>/dev/null); rc=${PIPESTATUS[0]:-0}
      else
        out=$(rt 70 env CODEX_HOME="$bt_codex_home" codex exec --ephemeral --ignore-user-config -s read-only --json --skip-git-repo-check -C "${TMPDIR:-/tmp}" "Reply with the single word: ok" < /dev/null 2>/dev/null | jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text' 2>/dev/null); rc=${PIPESTATUS[0]:-0}
      fi
      if [ -n "$out" ] && [ "$out" != "null" ]; then
        printf 'bt_codex_available=true\nbt_codex_model=%s\n' "${model:-}" > "$D/codex.env"
        break 2
      fi
      [ "$rc" = "124" ] && break
    done
  done
  if grep -q 'bt_codex_available=true' "$D/codex.env"; then
    # shellcheck disable=SC1090
    . "$D/codex.env"
    if [ "${bt_codex_model:-}" = "gpt-5.6-sol" ]; then
      echo "Codex: available ($ver; model=gpt-5.6-sol / GPT-5.6 Sol; isolated + --ignore-user-config)" > "$D/codex.log"
    elif [ -z "${bt_codex_model:-}" ]; then
      echo "Codex: available ($ver; product default; Sol unavailable — upgrade to Codex CLI >= 0.144.0 for gpt-5.6-sol)" > "$D/codex.log"
    else
      echo "Codex: available ($ver; model=${bt_codex_model}; isolated + --ignore-user-config)" > "$D/codex.log"
    fi
  else
    echo "Codex: empty/timeout after Sol + default warm-up ($ver). For GPT-5.6 Sol need CLI >= 0.144.0: npm i -g @openai/codex@latest" > "$D/codex.log"
  fi
}

# --- Grok (Grok Build; advertised default from `grok models`, fallback grok-4.6) ---
resolve_grok_model() {
  local listing default cand
  listing=$(grok models 2>/dev/null) || true
  default=$(printf '%s\n' "$listing" | sed -n 's/^Default model:[[:space:]]*//p' | head -1 | tr -d '[:space:]')
  if [ -n "$default" ]; then
    echo "$default"
    return
  fi
  for cand in grok-4.6 grok-4.5 grok-build; do
    printf '%s\n' "$listing" | grep -q "$cand" && { echo "$cand"; return; }
  done
  echo "grok-4.6"
}

probe_grok() {
  printf 'bt_grok_available=false\nbt_grok_model=grok-4.6\n' > "$D/grok.env"
  command -v grok &>/dev/null || { echo "Grok: not installed" > "$D/grok.log"; return; }
  local out rc model
  model=$(resolve_grok_model)
  for a in 1 2; do
    out=$(rt 50 grok --no-auto-update -p "Reply with the single word: ok" -m "$model" --output-format json 2>/dev/null | jq -r 'select(.type!="error") | .text // empty' 2>/dev/null); rc=${PIPESTATUS[0]:-0}
    if [ -n "$out" ] && [ "$out" != "null" ]; then
      printf 'bt_grok_available=true\nbt_grok_model=%s\n' "$model" > "$D/grok.env"
      break
    fi
    [ "$rc" = "124" ] && break
  done
  grep -q "bt_grok_available=true" "$D/grok.env" \
    && echo "Grok: available ($model)" > "$D/grok.log" \
    || echo "Grok: empty/unauthenticated/billing (parse JSON .message; grok login only if not a billing cap)" > "$D/grok.log"
}

# --- OpenCode (user's configured/default model; never hardcode a vendor id) ---
# Resolution matches "what I get when I open opencode":
#   1) opencode.json "model" (project, then global)
#   2) most recent non-free session model in local DB (TUI last-selection stand-in)
#   3) omit -m (OpenCode headless default — often a weak free model)
resolve_opencode_model() {
  local m="" cfg
  for cfg in \
    "${OPENCODE_CONFIG:-}" \
    "$PWD/opencode.json" \
    "$PWD/.opencode/opencode.json" \
    "$HOME/.config/opencode/opencode.json"
  do
    [ -n "$cfg" ] && [ -f "$cfg" ] || continue
    m=$(jq -r '.model // empty' "$cfg" 2>/dev/null)
    [ -n "$m" ] && [ "$m" != "null" ] && { echo "$m"; return; }
  done
  if command -v sqlite3 &>/dev/null && [ -f "$HOME/.local/share/opencode/opencode.db" ]; then
    m=$(sqlite3 "$HOME/.local/share/opencode/opencode.db" \
      "SELECT model FROM session WHERE model IS NOT NULL AND model != '' ORDER BY time_updated DESC LIMIT 40;" 2>/dev/null \
      | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        m = json.loads(line)
    except Exception:
        continue
    mid = str(m.get("id") or "")
    pid = str(m.get("providerID") or "")
    if not mid:
        continue
    if mid.endswith(":free") or ":free/" in mid:
        continue
    if pid and mid.startswith(pid + "/"):
        full = mid
    elif pid:
        full = f"{pid}/{mid}"
    else:
        full = mid
    print(full)
    break
' 2>/dev/null)
    [ -n "$m" ] && { echo "$m"; return; }
  fi
  echo ""
}

probe_opencode() {
  printf 'bt_opencode_available=false\nbt_opencode_model=\nbt_opencode_variant=\n' > "$D/opencode.env"
  command -v opencode &>/dev/null || { echo "OpenCode: not installed" > "$D/opencode.log"; return; }
  local model out rc src="default" variant=""
  model=$(resolve_opencode_model)
  if [ -n "$model" ]; then
    if ( [ -f "$HOME/.config/opencode/opencode.json" ] && jq -e --arg m "$model" '(.model // "") == $m' "$HOME/.config/opencode/opencode.json" >/dev/null 2>&1 ) \
      || ( [ -f "$PWD/opencode.json" ] && jq -e --arg m "$model" '(.model // "") == $m' "$PWD/opencode.json" >/dev/null 2>&1 ); then
      src="config"
    else
      src="last-session"
    fi
  fi
  local cmd=(opencode run --format json --auto --pure)
  [ -n "$model" ] && cmd+=(-m "$model")
  cmd+=("Reply with the single word: ok")
  for a in 1 2; do
    out=$(rt 60 "${cmd[@]}" 2>/dev/null | jq -rs 'map(select(.type=="text") | .part.text // .text // empty) | map(select(length>0)) | last // empty' 2>/dev/null)
    rc=${PIPESTATUS[0]:-0}
    if echo "$out" | grep -qi ok; then
      if [ -z "$model" ] && command -v sqlite3 &>/dev/null && [ -f "$HOME/.local/share/opencode/opencode.db" ]; then
        model=$(sqlite3 "$HOME/.local/share/opencode/opencode.db" \
          "SELECT model FROM session WHERE model IS NOT NULL ORDER BY time_updated DESC LIMIT 1;" 2>/dev/null \
          | python3 -c 'import sys,json; m=json.loads(sys.stdin.read() or "{}"); mid=m.get("id") or ""; pid=m.get("providerID") or "";
print(mid if (pid and mid.startswith(pid+"/")) else (f"{pid}/{mid}" if pid and mid else mid))' 2>/dev/null)
        src="headless-default"
      fi
      variant=""
      case "$model" in
        *glm-5.3*) variant="max" ;;
      esac
      printf 'bt_opencode_available=true\nbt_opencode_model=%s\nbt_opencode_variant=%s\n' "$model" "$variant" > "$D/opencode.env"
      break
    fi
    [ "$rc" = "124" ] && break
  done
  if grep -q true "$D/opencode.env"; then
    echo "OpenCode: available (model=${model:-unset}; source=$src; variant=${variant:-})" > "$D/opencode.log"
  else
    echo "OpenCode: found but no model responded (auth: opencode auth login; set model in ~/.config/opencode/opencode.json)" > "$D/opencode.log"
  fi
}

# --- Claude CLI (for hosts that are NOT Claude Code) ---
probe_claude() {
  printf 'bt_claude_cli_available=false\nbt_claude_model=opus\n' > "$D/claude.env"
  command -v claude &>/dev/null || { echo "Claude CLI: not installed" > "$D/claude.log"; return; }
  # Nested sessions inside Claude Code are blocked; probe still records CLI presence.
  # Liveness: only when not already inside Claude Code.
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
    printf 'bt_claude_cli_available=false\nbt_claude_model=opus\n' > "$D/claude.env"
    echo "Claude: host is Claude Code (use Task tool; nested claude -p blocked)" > "$D/claude.log"
    return
  fi
  local out
  out=$(rt 45 claude -p "Reply with the single word: ok" --model haiku --output-format json 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
  if echo "$out" | grep -qi ok; then
    printf 'bt_claude_cli_available=true\nbt_claude_model=opus\n' > "$D/claude.env"
    echo "Claude CLI: available (haiku probe ok; default consult opus)" > "$D/claude.log"
  else
    echo "Claude CLI: installed but not authenticated (claude /login) or nested" > "$D/claude.log"
  fi
}

probe_agy & probe_codex & probe_grok & probe_opencode & probe_claude &
wait

cat "$D"/agy.log "$D"/codex.log "$D"/grok.log "$D"/opencode.log "$D"/claude.log 2>/dev/null
echo "Claude host path: Task tool when inside Claude Code; claude -p otherwise"

set -a
# shellcheck disable=SC1090
. "$D/agy.env"
. "$D/codex.env"
. "$D/grok.env"
. "$D/opencode.env"
. "$D/claude.env"
set +a

cat > /tmp/bt_models.env << EOF
bt_agy_available=${bt_agy_available:-false}
bt_agy_needs_pty=${bt_agy_needs_pty:-false}
bt_agy_model=${bt_agy_model:-}
bt_codex_available=${bt_codex_available:-false}
bt_codex_home=${bt_codex_home:-${TMPDIR:-/tmp}/bt-codex-home}
bt_codex_model=${bt_codex_model-gpt-5.6-sol}
bt_grok_available=${bt_grok_available:-false}
bt_grok_model=${bt_grok_model:-grok-4.6}
bt_opencode_available=${bt_opencode_available:-false}
bt_opencode_model=${bt_opencode_model:-}
bt_opencode_variant=${bt_opencode_variant:-}
bt_claude_cli_available=${bt_claude_cli_available:-false}
bt_claude_model=${bt_claude_model:-opus}
bt_probe_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
bt_probe_version=1.11.0
EOF

rm -rf "$D"
echo "--- Results cached to /tmp/bt_models.env ---"
cat /tmp/bt_models.env
