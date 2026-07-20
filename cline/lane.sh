#!/usr/bin/env zsh
# Cline plan/build lane — plan & validate with a strong reasoner, code with a fast specialist.
# Set up 2026-07-04. Mirrors the "single build lane" idea: think hard once, execute cheap.
#
# Swap the two models below to A/B on quality vs token cost — that's the only knob.
#   Plan  candidates (strong):  cline-pass/deepseek-v4-pro  cline-pass/qwen3.7-max  cline-pass/minimax-m3
#   Build candidates (fast):    cline-pass/kimi-k2.7-code   cline-pass/glm-5.2       cline-pass/deepseek-v4-flash

: ${CLINE_PLAN_MODEL:=cline-pass/deepseek-v4-pro}   # designs & validates the change (low volume, high leverage)
: ${CLINE_BUILD_MODEL:=cline-pass/kimi-k2.7-code}   # applies the change (high token volume — keep it cheap/fast)
: ${CLINE_VERIFY_MODEL:=cline-pass/qwen3.7-max}     # adversarial reviewer — deliberately DIFFERENT from plan/build (no shared blind spots)

# internal: one item = one fresh branch. Called by cbuild/clane before any edit.
#   args: <nobranch 0|1> <explicit-name-or-empty> <text-to-slug>
#   Skips silently outside a git repo. --no-branch stays on the current branch.
_cline_new_branch() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  if [ "$1" = "1" ]; then echo "cline: --no-branch → staying on '$(git branch --show-current)'"; return 0; fi
  local name="$2"
  if [ -z "$name" ]; then
    local slug
    slug=$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)
    slug=${slug%-}; [ -z "$slug" ] && slug=item
    name="cline/$slug"
  fi
  local base="$name" i=2
  while git show-ref --verify -q "refs/heads/$name"; do name="${base}-$i"; i=$((i+1)); done
  git checkout -q -b "$name" && echo "cline: new branch → $name" || { echo "cline: could not create branch '$name'"; return 1; }
}

# cplan "<task>"  → produce/validate a plan only. Strong model, plan mode, high reasoning. No edits.
cplan()  { cline -P cline-pass -m "$CLINE_PLAN_MODEL"  --plan --thinking high "$@"; }

# cbuild [--branch NAME|--no-branch] "<task>" → make the change. Fast code model, act mode.
#   Starts a fresh branch per item by default; --no-branch (or --here) stays on the current branch.
cbuild() {
  emulate -L zsh
  local nobranch=0 bname=""
  while [ $# -gt 0 ]; do case "$1" in
    --no-branch|--here) nobranch=1; shift ;;
    --branch) bname="$2"; shift 2 ;;
    *) break ;;
  esac; done
  local slugsrc=""; [ $# -gt 0 ] && slugsrc="${@[$#]}"
  _cline_new_branch "$nobranch" "$bname" "$slugsrc" || return 1
  cline -P cline-pass -m "$CLINE_BUILD_MODEL" "$@"
}

# clane [--branch NAME|--no-branch] "<task>" → full lane: plan with the strong model, then build.
#   Starts a fresh branch per item by default (--no-branch/--here to stay put).
#   Edits land in the working tree (act mode). Review the diff and open a PR — it will NOT commit/merge.
clane() {
  emulate -L zsh
  local nobranch=0 bname=""
  while [ $# -gt 0 ]; do case "$1" in
    --no-branch|--here) nobranch=1; shift ;;
    --branch) bname="$2"; shift 2 ;;
    *) break ;;
  esac; done
  local task="$*"
  [ -z "$task" ] && { echo "usage: clane [--branch NAME|--no-branch] <task description>"; return 1; }
  _cline_new_branch "$nobranch" "$bname" "$task" || return 1
  echo "▸ PLAN  ($CLINE_PLAN_MODEL)"
  local plan
  plan=$(cline -P cline-pass -m "$CLINE_PLAN_MODEL" --plan --thinking high -p "$task") || return 1
  print -r -- "$plan"
  echo ""
  echo "▸ BUILD ($CLINE_BUILD_MODEL)"
  cline -P cline-pass -m "$CLINE_BUILD_MODEL" -p "Execute this plan with surgical, minimal edits — no unrelated changes. Do NOT commit or merge; leave changes in the working tree for review.

TASK: $task

PLAN:
$plan"
}

# cverify [base] → adversarial review of the current diff by the STRONG model before you PR.
#   Reviews branch commits + uncommitted changes vs base (auto-detected: origin HEAD, else main/master).
#   Read-only (plan mode). Prints concrete issues or 'APPROVED'.
cverify() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "cverify: not a git repo"; return 1; }
  local base="$1"
  if [ -z "$base" ]; then
    base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#origin/##')
    [ -z "$base" ] && for b in main master; do git show-ref --verify -q "refs/heads/$b" && base=$b && break; done
  fi
  local diff
  diff="$(git diff "${base}...HEAD" 2>/dev/null; git diff)"
  [ -z "$diff" ] && { echo "cverify: no diff vs '${base:-?}'"; return 0; }
  cline -P cline-pass -m "$CLINE_VERIFY_MODEL" --plan --thinking high -p "You are an adversarial code reviewer. Assume this diff contains a bug and try to find it. Check, in order: correctness bugs; silent failures / fail-open fallbacks (errors swallowed, bad defaults, \`or True\`); degenerate or empty inputs persisted into a shared or aggregated store (a zero/blank/None row that silently corrupts a median, average, count, or rollup — the per-row test still passes); missing edge cases; and whether the change actually does what it claims. Report each concrete issue on one line as file:line — issue. If genuinely clean, reply exactly 'APPROVED — no blocking issues'. Do NOT rubber-stamp.

DIFF (base=$base):
$diff"
}

# cship [--yes] [--dry-run] [--watch] [base] → gate, then open a PR.
#   The build models are small, so every gate here is DETERMINISTIC (shell-checked, not model-judged)
#   and FAIL-CLOSED: anything unclear aborts before anything is pushed.
#
#   Hard gates (any failure => nothing is pushed):
#     1. inside a git repo, on a feature branch (not the base), clean working tree
#     2. there are commits to PR vs the base branch
#     3. the resolved test command exits 0   (no test command found => ABORT — never ship untested)
#   Advisory (printed, does NOT gate — model output is too noisy to hard-gate on): cverify review.
#   Then: git push -u origin <branch> && gh pr create --fill --base <base>.
#   --watch: after PR, wait for CI (gh pr checks) and record pass AND fail — to agentmemory
#            (best-effort) and to docs/run-ledger.jsonl (the countable record).
#
#   Test command resolution (first hit wins): $CLINE_TEST_CMD > ./.cline/test.sh > detect(pytest|npm test|make test)
cship() {
  emulate -L zsh
  local yes=0 dry=0 watch=0 base=""
  local a; for a in "$@"; do case "$a" in
    --yes) yes=1 ;; --dry-run) dry=1 ;; --watch) watch=1 ;;
    --*) echo "cship: unknown flag $a"; return 2 ;; *) base="$a" ;;
  esac; done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "cship: not a git repo"; return 1; }
  local branch; branch=$(git branch --show-current)
  [ -z "$branch" ] && { echo "cship: detached HEAD — checkout a feature branch first"; return 1; }

  if [ -z "$base" ]; then
    base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#origin/##')
    [ -z "$base" ] && { local b; for b in main master; do git show-ref --verify -q "refs/heads/$b" && base=$b && break; done; }
  fi
  [ -z "$base" ] && { echo "cship: can't determine base branch — pass it: cship <base>"; return 1; }
  [ "$branch" = "$base" ] && { echo "cship: you're ON the base ('$base') — won't PR from the base branch"; return 1; }

  [ -n "$(git status --porcelain)" ] && { echo "cship: uncommitted changes — commit them first (no auto-commit, kept deterministic):"; git status --short; return 1; }

  local n; n=$(git rev-list --count "$base..HEAD" 2>/dev/null || echo 0)
  [ "$n" -eq 0 ] && { echo "cship: no commits vs '$base' — nothing to PR"; return 1; }

  # --- resolve the test command, FAIL-CLOSED ---
  local testcmd=""
  if   [ -n "$CLINE_TEST_CMD" ];                             then testcmd="$CLINE_TEST_CMD"
  elif [ -x ./.cline/test.sh ];                              then testcmd="./.cline/test.sh"
  elif [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -d tests ]; then command -v pytest >/dev/null 2>&1 && testcmd="pytest -q"
  elif [ -f package.json ] && grep -q '"test"' package.json; then testcmd="npm test"
  elif [ -f Makefile ] && grep -qE '^test:' Makefile;        then testcmd="make test"
  fi
  [ -z "$testcmd" ] && { echo "cship: no test command found — set CLINE_TEST_CMD or add ./.cline/test.sh. Refusing to ship untested (fail-closed)."; return 1; }

  echo "cship: '$branch' → '$base'  |  $n commit(s)"
  echo "cship: ── TEST GATE ── $testcmd"
  if ! eval "$testcmd"; then
    echo "cship: ❌ TESTS FAILED — not pushing, not opening a PR."; return 1
  fi
  echo "cship: ✅ tests passed"

  if [ "$dry" -eq 1 ]; then
    echo "cship: [dry-run] gates passed — would run: git push -u origin $branch && gh pr create --fill --base $base"
    return 0
  fi

  echo "cship: ── adversarial review ($CLINE_VERIFY_MODEL) ──"
  cverify "$base"

  if [ "$yes" -ne 1 ]; then
    if [ -t 0 ]; then
      local ans; echo -n "cship: push '$branch' and open PR vs '$base'? [y/N] "; read -r ans
      [[ "$ans" == [yY]* ]] || { echo "cship: aborted (nothing pushed)."; return 1; }
    else
      echo "cship: non-interactive and no --yes — refusing to auto-push. Re-run with --yes."; return 1
    fi
  fi

  command -v gh >/dev/null 2>&1 || { echo "cship: gh CLI not found — install it or push/PR by hand."; return 1; }
  git push -u origin "$branch" || { echo "cship: push failed."; return 1; }
  gh pr create --fill --base "$base" || { echo "cship: gh pr create failed."; return 1; }

  if [ "$watch" -eq 1 ]; then
    echo "cship: ── watching CI ──"
    local proj; proj=$(basename "$(git rev-parse --show-toplevel)")
    local result
    if gh pr checks --watch --interval 30; then
      echo "cship: ✅ CI green"; result="green"
    else
      echo "cship: ❌ CI RED — fix before merge"; result="red"
    fi
    # Record BOTH outcomes. Logging only failures gives a numerator with no denominator —
    # no pass rate can be computed from it. This feeds the harness outcome ledger.
    local url; url=$(gh pr view --json url -q .url 2>/dev/null)
    curl -s -m 4 -X POST http://localhost:3111/agentmemory/observe -H "Content-Type: application/json" \
      -d "{\"hookType\":\"post_tool_use\",\"sessionId\":\"cship\",\"project\":\"$proj\",\"data\":{\"tool_name\":\"cship_ci_result\",\"tool_output\":\"CI ${result} for ${url:-$branch} (base $base)\"}}" >/dev/null 2>&1 || true
    # Ledger lives OUTSIDE the repo, deliberately. An in-repo append would leave the working
    # tree dirty after every ship, and gate 1 above (clean tree, no auto-commit) would then
    # refuse the NEXT cship. Instrumentation must never block a ship.
    mkdir -p "$HOME/.cline" 2>/dev/null
    printf '{"date":"%s","lane":"cline","project":"%s","branch":"%s","ci":"%s","pr":"%s"}\n' \
      "$(date -u +%F)" "$proj" "$branch" "$result" "${url:-}" >> "$HOME/.cline/run-ledger.jsonl" 2>/dev/null || true
  fi
}
