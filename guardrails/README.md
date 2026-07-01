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

`SCORECARD.md` explains it: the weekly `/schedule`d agent that re-runs the
cross-repo drift audit both *enforces* (flags drift) and *measures* (appends a
scorecard row). Same routine, two jobs. That's what makes this continuous instead
of a one-time cleanup — and it's literally the audit run by hand on 2026-06-30,
turned into a heartbeat.

## Status
- [x] template scaffolded (this dir)
- [ ] wire mast (pre-commit + real CI + tool-instruction-sync assert) — after the fleet lands
- [ ] chokepoints: route all mast LLM calls through `call_with_retry`
- [ ] schedule the weekly drift audit → append to SCORECARD
- [ ] (optional) promote `hooks/` to a remote pre-commit repo + `Michiel-DK/.github`
