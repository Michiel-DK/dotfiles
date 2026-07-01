#!/usr/bin/env python3
"""fail-loud: flag silent fallbacks at data seams.

The recurring bug class across the repos (audit 2026-06-30): code degrades
quietly to a valid-looking-but-wrong state instead of failing loud —
  restaurant-brain: empty OCR -> InvoiceExtract() (=EUR0 invoice)
  repo-radar:       markup change -> parse returns []
  cycling_manager:  `budget_ok = price_delta <= 0 or True`  (dead constraint)
  cycling_manager:  missing `bucket` col -> jersey filter no-ops
  mast:             API_KEY unset -> auth serves open

This is a HEURISTIC gate, not a proof. It flags patterns for human review and
exits non-zero so pre-commit/CI go red. Silence a real false-positive with a
trailing  # noqa: fail-loud  comment. Tune the patterns per repo as needed.
"""
from __future__ import annotations

import re
import sys

# Single-line smells: (regex, why) — ordered by how often it bit us.
PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\bor\s+True\b"), "`or True` — makes the whole expression unconditionally true (dead guard)"),
    (re.compile(r"except[^\n:]*:\s*(pass|\.\.\.)\s*$"), "bare `except ...: pass` (one-liner) — swallows the error silently"),
    (re.compile(r"\.get\([^)]*\)\s+or\s+"), "`.get(...) or <default>` — masks missing/empty data at a seam"),
]

# Multi-line smell: an `except ...:` whose body is only `pass`/`...` on the next line.
_EXCEPT_OPEN = re.compile(r"^\s*except\b.*:\s*(#.*)?$")
_EMPTY_BODY = re.compile(r"^\s*(pass|\.\.\.)\s*(#.*)?$")


def scan(path: str) -> list[str]:
    hits: list[str] = []
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError as exc:  # be loud about our own failure, too
        return [f"{path}: could not read ({exc})"]
    for n, line in enumerate(lines, 1):
        if "# noqa: fail-loud" in line:
            continue
        for rx, why in PATTERNS:
            if rx.search(line):
                hits.append(f"{path}:{n}: {why}\n    {line.strip()}")
        # multi-line `except:` then a sole `pass`/`...` on the next non-blank line
        if _EXCEPT_OPEN.match(line):
            nxt = next((lines[j] for j in range(n, len(lines)) if lines[j].strip()), "")
            if _EMPTY_BODY.match(nxt) and "# noqa: fail-loud" not in nxt:
                hits.append(f"{path}:{n}: `except ...:` with empty body — swallows the error silently\n    {line.strip()}")
    return hits


def main(argv: list[str]) -> int:
    all_hits: list[str] = []
    for path in argv[1:]:
        all_hits.extend(scan(path))
    if all_hits:
        print("fail-loud: silent-fallback patterns found (review, or add `# noqa: fail-loud`):\n")
        print("\n".join(all_hits))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
