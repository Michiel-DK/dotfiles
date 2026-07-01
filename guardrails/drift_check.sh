#!/usr/bin/env bash
# Deterministic cross-repo drift check — pure code, NO LLM, zero tokens.
# Weekly heartbeat for the guardrail system (see README.md). Semantic checks
# ("is this memory still true?") are deliberately NOT here — those cost tokens
# and belong in an on-demand deep audit.
#
#   ./drift_check.sh            # print report only
#   ./drift_check.sh --write    # also append a dated row to SCORECARD.md
#
set -uo pipefail   # NOT -e: one repo's failure must not abort the whole sweep

BASE="${GUARDRAILS_BASE:-$HOME/code/Michiel-DK}"
REPOS=(mast cycling_manager restaurant-brain repo-radar)
CLAUDE_BUDGET=50          # CLAUDE.md lines before it's "bloated"
LARGE_KB=200              # tracked-file size that's "too big for git"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/hooks/fail_loud_check.py"
SCORECARD="$HERE/SCORECARD.md"

total_drift=0
repos_with_gate=0
repos_seen=0

printf '%-18s %8s %8s %8s %10s %6s\n' REPO CLAUDEmd LARGEf DELETED "silent(i)" GATE
printf '%-18s %8s %8s %8s %10s %6s\n' ------ -------- ------ ------- ---------- ----

for name in "${REPOS[@]}"; do
  repo="$BASE/$name"
  if [ ! -d "$repo/.git" ]; then
    printf '%-18s %8s\n' "$name" "MISSING"
    continue
  fi
  repos_seen=$((repos_seen + 1))

  # CLAUDE.md over budget? (report lines-over, 0 if fine/absent)
  claude_over=0
  if [ -f "$repo/CLAUDE.md" ]; then
    lines=$(wc -l < "$repo/CLAUDE.md" | tr -d ' ')
    [ "$lines" -gt "$CLAUDE_BUDGET" ] && claude_over=$((lines - CLAUDE_BUDGET))
  fi

  # tracked files larger than LARGE_KB
  large=$(git -C "$repo" ls-tree -r -l HEAD 2>/dev/null \
            | awk -v max=$((LARGE_KB * 1024)) '$4+0 > max' | wc -l | tr -d ' ')

  # tracked deleted_* dumping grounds
  deleted=$(git -C "$repo" ls-files 2>/dev/null | grep -cE '(^|/)deleted_' || true)

  # silent-fallback whole-repo count: INFORMATIONAL ONLY, excluded from drift.
  # This grep is a GATE check (runs on diffs in pre-commit); swept over an entire
  # existing codebase it is dominated by legitimate .get()/except patterns, so it
  # would flood the drift metric with false positives. Shown as a baseline the gate
  # drives down on *new* code, not as drift.
  silent=0
  if [ -f "$HOOK" ]; then
    pyfiles=$(git -C "$repo" ls-files '*.py' 2>/dev/null | sed "s#^#$repo/#")
    if [ -n "$pyfiles" ]; then
      silent=$(echo "$pyfiles" | xargs python3 "$HOOK" 2>/dev/null \
                 | grep -cE ':[0-9]+: ' || true)
    fi
  fi

  # gate present? (coverage)
  gate="no"
  if [ -f "$repo/.pre-commit-config.yaml" ]; then gate="yes"; repos_with_gate=$((repos_with_gate + 1)); fi

  # drift = true structural rot only: context bloat, oversized tracked files, dumping grounds.
  repo_drift=$((claude_over > 0 ? 1 : 0))
  repo_drift=$((repo_drift + large + deleted))
  total_drift=$((total_drift + repo_drift))

  printf '%-18s %8s %8s %8s %10s %6s\n' "$name" "$claude_over" "$large" "$deleted" "$silent" "$gate"
done

echo
echo "TOTAL drift findings: $total_drift    gate coverage: ${repos_with_gate}/${repos_seen}"
echo "(drift = CLAUDEmd-over-budget + LARGEf + DELETED — true structural rot.)"
echo " CLAUDEmd = lines over ${CLAUDE_BUDGET}; LARGEf = tracked files > ${LARGE_KB}KB;"
echo " DELETED = tracked deleted_* paths; silent(i) = informational baseline (gate handles new code), NOT in drift."

if [ "${1:-}" = "--write" ]; then
  if [ ! -f "$SCORECARD" ]; then
    echo "drift_check: SCORECARD.md not found at $SCORECARD — not appending" >&2
    exit 1
  fi
  # Date is passed in (launchd sets it); fall back to `date` when run by hand.
  today="${DRIFT_DATE:-$(date +%F)}"
  row="| $today | ${repos_with_gate}/${repos_seen} | - | $total_drift | - | - |"
  printf '%s\n' "$row" >> "$SCORECARD"
  echo "appended to SCORECARD.md: $row"
fi
