# Guardrail Scorecard — is this actually improving engineering?

You can't measure "my score went 6→7" (that was a subjective grade). You measure
the **proxies the guardrails are built to move**: silent decay and inconsistency.
The trick: the same scheduled drift routine that *enforces* also *emits* these
numbers. Append a row each run → the trend over time IS the performance signal.
No separate measurement system.

## Metrics (all auto-collectable)

| Metric | What it means | Direction |
|---|---|---|
| `guardrail_coverage` | repos with pre-commit + real-CI + branch protection / total | → 100% |
| `chokepoint_coverage` | e.g. mast LLM calls routed through `call_with_retry` / all call sites | → 100% |
| `drift_findings` | weekly audit hits: phantom refs, stale CLAUDE.md, unverified memories | → 0, stay low |
| `gate_catches` | pre-commit/CI rejections per week (silent-fallback, secrets, lint) | high early → low+stable |
| `escaped_defects` | bugs found in review/prod a guardrail *should* have caught | → 0 (each one spawns a new guardrail) |

Read them together: `gate_catches` high while `escaped_defects` falls = the gate is
doing its job. `drift_findings` staying near zero = decay is no longer silent.
A spike in `gate_catches` after a quiet period = a regression entering — investigate.

## Baseline — 2026-06-30 (from the 4-repo audit; before any guardrail)

| Metric | Value | Source |
|---|---|---|
| `guardrail_coverage` | 0 / 5 repos | no pre-commit anywhere; mast CI runs `--no-deps` unit only |
| `chokepoint_coverage` (mast LLM retry) | 2 / 4 call sites | matcher + ma_discovery bypass `call_with_retry` |
| `drift_findings` | ≥ 3 | phantom `get_firm_briefing` tool; ~350 dead lines in restaurant-brain CLAUDE.md; a memory asserting `:3111 not persistent` (unverified) |
| `escaped_defects` | 4 | EUR0 invoice; `or True` budget; bucket no-op; fail-open auth |

## The loop (how a row gets added)

```
weekly scheduled agent (/schedule) runs the cross-repo drift audit
  → counts drift_findings, reads gate_catches from CI, recomputes coverage
  → appends a dated row to the table below
  → also writes it to agentmemory (project memory) so the history is queryable
```

## History (append one row per weekly run)

| date | guardrail_cov | chokepoint_cov | drift | gate_catches/wk | escaped |
|---|---|---|---|---|---|
| 2026-06-30 | 0/5 | 2/4 | ≥3 | n/a (no gate yet) | 4 |
| 2026-07-01 | 0/4 | - | 83 | - | - |
