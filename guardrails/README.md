# guardrails — one source of truth for consistency across repos

**The problem this solves:** across mast / cycling_manager / restaurant-brain /
repo-radar, the *quality* was there but *consistency* wasn't — good patterns
applied once not everywhere, and context/knowledge decaying silently. You can't
fix that with discipline; you fix it by moving each rule out of your head into a
place that can't forget. This directory is that place.

## The three enforcement layers

| Layer | Makes the wrong state… | Here |
|---|---|---|
| **Chokepoint** | impossible to write | one module per external dep (LLM/DB/secrets/memory) + import-linter ban (per-repo) |
| **Gate** | un-mergeable | `.pre-commit-config.yaml` + `ruff.toml` + `hooks/fail_loud_check.py` + CI running the *real* suite |
| **Routine** | visible when it drifts | weekly cross-repo audit → `SCORECARD.md` (the continuous loop) |

## Apply to a repo

```bash
# from the target repo root:
cp ~/code/Michiel-DK/dotfiles/guardrails/.pre-commit-config.yaml .
cp ~/code/Michiel-DK/dotfiles/guardrails/ruff.toml .
mkdir -p guardrails/hooks && cp ~/code/Michiel-DK/dotfiles/guardrails/hooks/fail_loud_check.py guardrails/hooks/
cat ~/code/Michiel-DK/dotfiles/guardrails/gitignore-claude.snippet >> .gitignore   # if the repo uses .claude/
pipx install pre-commit && pre-commit install
```

**Don't hand-maintain the copies.** The canonical version lives HERE; edit here,
re-sync. Two cleaner upgrades when you're ready:
- **Remote pre-commit hooks** — publish `hooks/` as its own repo; each
  `.pre-commit-config.yaml` references it by URL. Update once → every repo updates.
- **`Michiel-DK/.github` org repo** — GitHub auto-applies org-default workflows +
  community-health files to every repo. Native "same CI everywhere".

## The continuous loop

`SCORECARD.md` explains it: a weekly routine re-runs the cross-repo drift audit,
both *enforcing* (flags drift) and *measuring* (appends a scorecard row). Same
routine, two jobs — the audit run by hand on 2026-06-30, turned into a heartbeat.

**Split it by cost — this is the token-discipline point:**
- **Deterministic checks → free.** CLAUDE.md size budget, large/`deleted_*` tracked
  files, secret scan, silent-fallback grep, coverage. No LLM. Run these weekly via
  `drift_check.sh` on **local launchd** (see below) — zero tokens, zero cloud cost.
- **Semantic checks → paid.** "Is this memory still *true*", "did code drift from
  what the doc *claims*", the 4-agent deep audit. Reserve for **on-demand / monthly**,
  not weekly-by-default — that's where tokens quietly balloon.

Install the free weekly sweep:
```bash
cp guardrails/com.michieldk.guardrails-drift.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.michieldk.guardrails-drift.plist
# runs guardrails/drift_check.sh --write every Monday 09:00 → appends a SCORECARD row
```

## Best practices

Two standing rules that keep the system honest over time:

1. **The ratchet — every escaped defect becomes a permanent check.** When a bug slips
   *past* the gate, the fix isn't just fixing the bug: add the test/lint/assert that
   would have caught it. This is why `escaped_defects` is on the scorecard — each one
   should spawn a new guardrail, so coverage only ever grows. It's what makes the set
   *learn* instead of ossify. (Standard regression-per-bug discipline.)
2. **Keep the gate fast, or it gets bypassed.** If pre-commit takes more than a few
   seconds, `git commit --no-verify` becomes the habit and the whole thing rots. Gate
   speed = gate adoption. ruff is instant; keep custom hooks lint-fast; never put slow
   work (full test suites) in pre-commit — that belongs in CI.

The harness **buys assurance with tokens** — spend them only where assurance is worth
it: deterministic checks free, cheap changes on a light tier, expensive fan-out audits
on-demand.

## Status
- [x] template scaffolded (this dir)
- [x] deterministic weekly drift check (`drift_check.sh` + launchd plist) — free, local
- [ ] install the launchd plist (one-time, your machine)
- [ ] wire mast (pre-commit + real CI + tool-instruction-sync assert) — after the fleet lands
- [ ] chokepoints: route all mast LLM calls through `call_with_retry`
- [ ] (optional) promote `hooks/` to a remote pre-commit repo + `Michiel-DK/.github`
