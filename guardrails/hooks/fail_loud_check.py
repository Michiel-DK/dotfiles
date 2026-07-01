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
import subprocess
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


def added_lines_from_staged_diff() -> list[tuple[str, int, str]]:
    """Return (path, new_lineno, text) for every ADDED line in the staged diff.

    This is what makes the gate ratchet: it looks only at lines the commit
    introduces, so pre-existing violations in a touched file are grandfathered
    and the gate never floods a legacy repo with red.
    """
    try:
        out = subprocess.run(
            ["git", "diff", "--cached", "-U0", "--no-color"],
            capture_output=True, text=True, check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        # our own failure must be loud, not a silent empty result
        print(f"fail-loud: could not read staged diff ({exc})", file=sys.stderr)
        raise SystemExit(2) from exc

    added: list[tuple[str, int, str]] = []
    path: str | None = None
    newno = 0
    for line in out.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            newno = int(m.group(1)) if m else 0
        elif line.startswith("+") and not line.startswith("+++"):
            added.append((path or "?", newno, line[1:]))
            newno += 1
        # '-' (removed) and context lines do not advance the new-file counter
    return added


def scan_added(added: list[tuple[str, int, str]]) -> list[str]:
    hits: list[str] = []
    for i, (path, no, text) in enumerate(added):
        if not path.endswith(".py") or "# noqa: fail-loud" in text:
            continue
        for rx, why in PATTERNS:
            if rx.search(text):
                hits.append(f"{path}:{no}: {why}\n    {text.strip()}")
        # multi-line except: only when BOTH the `except:` and its empty body are newly added
        if _EXCEPT_OPEN.match(text):
            for p2, no2, t2 in added[i + 1 : i + 3]:
                if p2 == path and no2 == no + 1:
                    if _EMPTY_BODY.match(t2) and "# noqa: fail-loud" not in t2:
                        hits.append(f"{path}:{no}: `except ...:` with empty body — swallows the error silently\n    {text.strip()}")
                    break
    return hits


def main(argv: list[str]) -> int:
    args = argv[1:]
    if "--diff" in args:
        # ratcheting gate mode (pre-commit): only lines this commit adds
        all_hits = scan_added(added_lines_from_staged_diff())
    else:
        # whole-file mode (on-demand audit / CI full scan)
        all_hits = []
        for path in args:
            all_hits.extend(scan(path))
    if all_hits:
        print("fail-loud: silent-fallback patterns found (review, or add `# noqa: fail-loud`):\n")
        print("\n".join(all_hits))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
