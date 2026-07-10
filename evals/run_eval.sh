#!/usr/bin/env bash
# Durable braintrust skill eval runner.
#
# Usage:
#   bash evals/run_eval.sh                  # contract-quiz, all variants, available peers
#   bash evals/run_eval.sh contract-quiz skill-lean
#   bash evals/run_eval.sh contract-quiz skill-full agy,codex
#   bash evals/run_eval.sh matrix           # all fixtures x all variants x default peers
#
# Writes: evals/runs/<timestamp>-<fixture>/
# Does not publish or modify the skill. Public fixtures only.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIXTURE="${1:-contract-quiz}"
VARIANT="${2:-all}"          # all | ab | skill-lean | skill-hybrid | skill-current | skill-full
PEERS_CSV="${3:-all}"        # all | comma list: agy,codex,grok,opencode,claude

# Matrix mode is handled later; do not require fixtures/matrix.md
if [[ "$FIXTURE" != "matrix" ]]; then
  FIX_PATH="evals/fixtures/${FIXTURE}.md"
  [[ -f "$FIX_PATH" ]] || { echo "missing fixture: $FIX_PATH" >&2; exit 2; }
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ID="${TS}-${FIXTURE}"
RUN_ROOT="evals/runs/${RUN_ID}"
mkdir -p "$RUN_ROOT"

# Probe if available
if [[ -f scripts/bt_probe.sh ]]; then
  bash scripts/bt_probe.sh >"$RUN_ROOT/probe.log" 2>&1 || true
fi
# shellcheck disable=SC1091
source /tmp/bt_models.env 2>/dev/null || true

build_package() {
  local variant="$1"
  local out="$2"
  {
    echo "## EVAL VARIANT: $variant"
    echo "## FIXTURE: $FIXTURE"
    echo
    if [[ "$variant" == "skill-lean" ]]; then
      echo "## SKILL TEXT (LEAN — complete)"
      cat evals/variants/skill-lean.md
    elif [[ "$variant" == "skill-hybrid" ]]; then
      echo "## SKILL TEXT (HYBRID — lean + ops appendix)"
      cat evals/variants/skill-hybrid.md
    elif [[ "$variant" == "skill-current" ]]; then
      echo "## SKILL TEXT (CURRENT shipping SKILL.md only)"
      cat skills/braintrust/SKILL.md
    elif [[ "$variant" == "skill-full" ]]; then
      echo "## SKILL TEXT (FULL surface: skill + templates + key refs)"
      echo "### skills/braintrust/SKILL.md"
      cat skills/braintrust/SKILL.md
      echo
      echo "### grounding-protocol.md"
      cat grounding-protocol.md
      echo
      echo "### goal-card-template.md"
      cat goal-card-template.md
      echo
      echo "### references/capability-packaging.md"
      cat skills/braintrust/references/capability-packaging.md
      echo
      echo "### references/cli-contracts.md"
      cat skills/braintrust/references/cli-contracts.md
    else
      echo "unknown variant: $variant" >&2
      exit 2
    fi
    echo
    echo "## TASK"
    cat "$FIX_PATH"
  } >"$out"
  local chars words tok
  chars=$(wc -c <"$out" | tr -d ' ')
  words=$(wc -w <"$out" | tr -d ' ')
  tok=$((chars / 4))
  echo "$variant chars=$chars words=$words ~tok=$tok" | tee -a "$RUN_ROOT/sizes.txt"
}

run_peer() {
  local peer="$1" package="$2" outdir="$3"
  mkdir -p "$outdir"
  local q
  q=$(cat "$package")
  case "$peer" in
    agy)
      if [[ "${bt_agy_available:-true}" != "true" ]] && [[ "${bt_agy_available:-}" == "false" ]]; then
        echo "SKIPPED unavailable" >"$outdir/result.txt"; return
      fi
      timeout 150 agy --print "$q" --dangerously-skip-permissions \
        >"$outdir/result.txt" 2>"$outdir/stderr.txt" || true
      ;;
    codex)
      if [[ "${bt_codex_available:-true}" == "false" ]]; then
        echo "SKIPPED unavailable" >"$outdir/result.txt"; return
      fi
      local home="${bt_codex_home:-/tmp/bt-codex-home}"
      local model_args=()
      if [[ -n "${bt_codex_model+x}" && -z "${bt_codex_model}" ]]; then
        model_args=()
      else
        model_args=(-m "${bt_codex_model:-gpt-5.6-sol}")
      fi
      CODEX_HOME="$home" timeout 150 codex exec --ephemeral --ignore-user-config \
        -s read-only --json --skip-git-repo-check "${model_args[@]}" -C "${TMPDIR:-/tmp}" "$q" \
        </dev/null 2>"$outdir/stderr.txt" >"$outdir/raw.jsonl" || true
      jq -rs 'map(select(.item.type? == "agent_message")) | last | .item.text // empty' \
        "$outdir/raw.jsonl" >"$outdir/result.txt" 2>/dev/null || true
      ;;
    grok)
      if [[ "${bt_grok_available:-true}" == "false" ]]; then
        echo "SKIPPED unavailable" >"$outdir/result.txt"; return
      fi
      timeout 150 grok -p "$q" -m "${bt_grok_model:-grok-4.5}" \
        --output-format json --disable-web-search \
        2>"$outdir/stderr.txt" \
        | jq -r 'if .type=="error" then "GROK_FAILED: "+.message else .text end' \
        >"$outdir/result.txt" || true
      ;;
    opencode)
      if [[ "${bt_opencode_available:-true}" == "false" ]]; then
        echo "SKIPPED unavailable" >"$outdir/result.txt"; return
      fi
      local args=(run --format json --auto --pure)
      [[ -n "${bt_opencode_model:-}" ]] && args+=(-m "$bt_opencode_model")
      timeout 150 opencode "${args[@]}" "$q" 2>"$outdir/stderr.txt" \
        | jq -rs 'map(select(.type=="text") | .part.text // .text // empty) | map(select(length>0)) | last // empty' \
        >"$outdir/result.txt" || true
      ;;
    claude)
      if [[ "${bt_claude_cli_available:-true}" == "false" ]]; then
        echo "SKIPPED unavailable" >"$outdir/result.txt"; return
      fi
      timeout 150 claude -p "$q" --model "${bt_claude_model:-sonnet}" --output-format json \
        2>"$outdir/stderr.txt" \
        | jq -r '.result // empty' >"$outdir/result.txt" || true
      ;;
    *)
      echo "unknown peer: $peer" >&2; return 2
      ;;
  esac
  local n
  n=$(wc -c <"$outdir/result.txt" | tr -d ' ')
  echo "$peer bytes=$n" | tee -a "$RUN_ROOT/peer_status.txt"
}

score_ops_edge() {
  local f="$1" t score=0 notes=()
  t=$(cat "$f" 2>/dev/null || true)
  [[ -z "$t" || "$t" == SKIPPED* ]] && { echo "0|empty"; return; }
  echo "$t" | grep -qiE 'CODEX_HOME|ignore-user-config|memories|MCP' && { score=$((score+1)); notes+=("Q1"); } || true
  echo "$t" | grep -qiE 'spending-limit|billing|type.*error|\.type' && { score=$((score+1)); notes+=("Q2"); } || true
  echo "$t" | grep -qiE 'opencode\.json|config' && echo "$t" | grep -qiE 'session|non-free|omit|bt_opencode' && { score=$((score+1)); notes+=("Q3"); } || true
  echo "$t" | grep -qiE 'pty|bt_agy_pty' && echo "$t" | grep -qiE 'never|not|no .*gemini|gemini' && { score=$((score+1)); notes+=("Q4"); } || true
  echo "$t" | grep -qiE 'claude -p' && { score=$((score+1)); notes+=("Q5"); } || true
  echo "$t" | grep -qiE 'Mode G|MCP-assisted|allowlist|fallback' && { score=$((score+1)); notes+=("Q6"); } || true
  echo "$t" | grep -qiE '/tmp/bt_.*\.err|bt_<cli>\.err|stderr' && { score=$((score+1)); notes+=("Q7"); } || true
  echo "$t" | grep -qiE 'PATH|SessionStart|hook' && echo "$t" | grep -qiE 'probe|auth|liveness|authenticated' && { score=$((score+1)); notes+=("Q8"); } || true
  echo "$t" | grep -qiE 'gtimeout|coreutils|timeout' && { score=$((score+1)); notes+=("Q9"); } || true
  if echo "$t" | grep -qiE 'NOT GROUNDED'; then :; elif echo "$t" | grep -qiE '\bGROUNDED\b'; then score=$((score+1)); notes+=("Q10"); fi
  local joined; joined=$(IFS=,; echo "${notes[*]-}")
  echo "${score}|${joined}"
}

score_result() {
  local f="$1"
  if [[ "${EVAL_FIXTURE:-contract-quiz}" == "ops-edge" ]]; then
    score_ops_edge "$f"
    return
  fi
  # Heuristic auto-score for contract-quiz (host can override manually)
  local score=0
  local notes=()
  local t
  t=$(cat "$f" 2>/dev/null || true)
  [[ -z "$t" || "$t" == SKIPPED* ]] && { echo "0|empty"; return; }

  # Q1: five members present; Gemini may be mentioned only as excluded
  local q1=0
  echo "$t" | grep -qiE '\bagy\b' && echo "$t" | grep -qiE '\bcodex\b' && echo "$t" | grep -qiE '\bgrok\b' \
    && echo "$t" | grep -qiE '\bopencode\b' && echo "$t" | grep -qiE '\bclaude\b' && q1=1
  if echo "$t" | grep -qiE '\bgemini\b' && ! echo "$t" | grep -qiE 'not|never|no .*gemini|excluded|removed|not a member'; then
    q1=0
  fi
  score=$((score+q1)); [[ $q1 -eq 1 ]] && notes+=("Q1")

  echo "$t" | grep -qiE 'CODEX_HOME' && echo "$t" | grep -qiE 'ignore-user-config|/dev/null|stdin' \
    && { score=$((score+1)); notes+=("Q2"); } || true

  echo "$t" | grep -qiE 'opencode run' && echo "$t" | grep -qiE -- '--pure|bt_opencode_model|-m' \
    && { score=$((score+1)); notes+=("Q3"); } || true

  echo "$t" | grep -qiE 'grok-4\.5' && echo "$t" | grep -qiE -- '-p|headless|output-format json' \
    && { score=$((score+1)); notes+=("Q4"); } || true

  echo "$t" | grep -qiE 'agy' && echo "$t" | grep -qiE -- '--print' \
    && echo "$t" | grep -qiE 'never|not|no .*gemini|gemini' \
    && { score=$((score+1)); notes+=("Q5"); } || true

  echo "$t" | grep -qiE 'Task tool|subagent|general-purpose' \
    && { score=$((score+1)); notes+=("Q6"); } || true

  echo "$t" | grep -qiE 'identity' && echo "$t" | grep -qiE 'workspace|files|cwd' \
    && { score=$((score+1)); notes+=("Q7"); } || true

  echo "$t" | grep -qiE 'Mode A|text-only' && echo "$t" | grep -qiE 'Mode C|repo walker|repo' \
    && { score=$((score+1)); notes+=("Q8"); } || true

  echo "$t" | grep -qiE '/tmp/bt_models\.env' \
    && { score=$((score+1)); notes+=("Q9"); } || true

  if echo "$t" | grep -qiE 'NOT GROUNDED'; then
    :
  elif echo "$t" | grep -qiE '\bGROUNDED\b'; then
    score=$((score+1)); notes+=("Q10")
  fi

  local joined
  joined=$(IFS=,; echo "${notes[*]-}")
  echo "${score}|${joined}"
}

resolve_variants() {
  local v="$1"
  case "$v" in
    ab) echo "skill-lean skill-current" ;;
    abc|ab-hybrid) echo "skill-lean skill-hybrid skill-current" ;;
    all) echo "skill-lean skill-hybrid skill-current skill-full" ;;
    skill-lean|skill-hybrid|skill-current|skill-full) echo "$v" ;;
    *) echo "$v" ;;
  esac
}

resolve_peers() {
  local p="$1"
  if [[ "$p" == "all" ]]; then
    echo "agy codex grok opencode claude"
  else
    echo "${p//,/ }"
  fi
}

# Matrix mode: every fixture x every variant x peers
if [[ "$FIXTURE" == "matrix" ]]; then
  MATRIX_ROOT="evals/runs/$(date -u +%Y%m%dT%H%M%SZ)-matrix"
  mkdir -p "$MATRIX_ROOT"
  COMBINED="$MATRIX_ROOT/combined.tsv"
  echo -e "fixture\tvariant\tpeer\tscore\thits\tbytes\t~pkg_tok" >"$COMBINED"
  PEERS_CSV_SAVE="$PEERS_CSV"
  VARIANT_SAVE="${VARIANT:-all}"
  for fix in contract-quiz ops-edge; do
    echo "======== MATRIX fixture=$fix variants=$VARIANT_SAVE peers=$PEERS_CSV_SAVE ========"
    # re-enter as single-fixture run into a nested dir under matrix
    FIXTURE="$fix" VARIANT="$VARIANT_SAVE" PEERS_CSV="$PEERS_CSV_SAVE" \
      bash "$ROOT/evals/run_eval.sh" "$fix" "$VARIANT_SAVE" "$PEERS_CSV_SAVE" \
      | tee "$MATRIX_ROOT/${fix}.log"
    # append latest summary for this fixture
    latest=$(ls -1dt evals/runs/*-"$fix" 2>/dev/null | head -1)
    if [[ -n "$latest" && -f "$latest/summary.tsv" ]]; then
      tail -n +2 "$latest/summary.tsv" | while IFS= read -r line; do
        echo -e "${fix}\t${line}"
      done >>"$COMBINED"
      # also copy run pointer
      echo "$latest" >>"$MATRIX_ROOT/run_paths.txt"
    fi
  done
  echo
  echo "=== MATRIX COMBINED ==="
  column -t -s $'\t' "$COMBINED" 2>/dev/null || cat "$COMBINED"
  echo
  echo "=== MATRIX AVERAGES (score by fixture x variant) ==="
  python3 - "$COMBINED" <<'PY'
import sys, collections
path = sys.argv[1]
rows = []
with open(path) as f:
    header = f.readline()
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 6: continue
        fixture, variant, peer, score, hits, bytes_, pkg = parts[:7]
        try: score = int(score)
        except: continue
        rows.append((fixture, variant, peer, score, int(bytes_ or 0), int(pkg or 0)))
if not rows:
    print("no rows"); sys.exit(0)
# avg by fixture,variant
key_av = collections.defaultdict(list)
pkg_by = {}
for fixture, variant, peer, score, bytes_, pkg in rows:
    key_av[(fixture, variant)].append(score)
    pkg_by[(fixture, variant)] = pkg
print(f"{'fixture':<16} {'variant':<16} {'avg':>5} {'n':>3} {'min':>3} {'max':>3} {'~pkg_tok':>8}")
for (fixture, variant) in sorted(key_av):
    xs = key_av[(fixture, variant)]
    avg = sum(xs)/len(xs)
    print(f"{fixture:<16} {variant:<16} {avg:5.2f} {len(xs):3d} {min(xs):3d} {max(xs):3d} {pkg_by[(fixture,variant)]:8d}")
# overall by variant
print()
print(f"{'variant':<16} {'avg_all':>7} {'n':>3} {'~pkg_tok':>8}")
ov = collections.defaultdict(list)
for fixture, variant, peer, score, bytes_, pkg in rows:
    ov[variant].append((score, pkg))
for variant in sorted(ov):
    xs = [s for s,_ in ov[variant]]
    pkg = ov[variant][0][1]
    print(f"{variant:<16} {sum(xs)/len(xs):7.2f} {len(xs):3d} {pkg:8d}")
PY
  echo "Matrix root: $MATRIX_ROOT"
  exit 0
fi

read -r -a VARIANTS <<<"$(resolve_variants "$VARIANT")"
read -r -a PEERS <<<"$(resolve_peers "$PEERS_CSV")"

echo "run_id=$RUN_ID" | tee "$RUN_ROOT/meta.txt"
export EVAL_FIXTURE="$FIXTURE"
echo "fixture=$FIXTURE variant=$VARIANT peers=${PEERS[*]}" | tee -a "$RUN_ROOT/meta.txt"
echo "variants=${VARIANTS[*]}" | tee -a "$RUN_ROOT/meta.txt"

SUMMARY="$RUN_ROOT/summary.tsv"
echo -e "variant\tpeer\tscore\thits\tbytes\t~pkg_tok" >"$SUMMARY"

for v in "${VARIANTS[@]}"; do
  pkg="$RUN_ROOT/package-${v}.md"
  build_package "$v" "$pkg"
  pkg_tok=$(( $(wc -c <"$pkg") / 4 ))
  for peer in "${PEERS[@]}"; do
    outdir="$RUN_ROOT/${v}/${peer}"
    echo "→ $v / $peer"
    run_peer "$peer" "$pkg" "$outdir"
    sc=$(score_result "$outdir/result.txt")
    score="${sc%%|*}"
    hits="${sc#*|}"
    bytes=$(wc -c <"$outdir/result.txt" | tr -d ' ')
    echo -e "${v}\t${peer}\t${score}\t${hits}\t${bytes}\t${pkg_tok}" | tee -a "$SUMMARY"
  done
done

echo
echo "=== SUMMARY ==="
column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
echo
echo "Artifacts: $RUN_ROOT"
echo "Manual review: read */result.txt; auto-score is heuristic (0-10)."
