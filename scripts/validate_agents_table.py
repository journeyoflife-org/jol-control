#!/usr/bin/env python3
"""Validate the enforcement-truth table in AGENTS.md.

AGENTS.md section 2 is the file an agent reads before trusting any claim about this
organization, and until now nothing checked it. Documentation-only commits are excluded from
`apply.yml`'s `paths:` filter by design, so a malformed row — a cell lost to an unescaped
pipe, a claim with no evidence column — reaches `main` with no CI signal at all. This script
is wired into compliance-scan.yml, which runs on every pull request and weekly.

Rules enforced:
  1. Section 2 exists and keeps its "verified" framing.
  2. The table header is exactly `| Statement | Reality | Evidence |`.
  3. Every row has exactly three non-empty cells (escaped `\\|` does not split a row).
  4. Every row carries a non-empty Evidence cell: a control claim without a command behind
     it is the failure mode this repository already documents as an audit finding.
  5. At least one row exists (a stripped table is a regression, not a pass).

Exit codes, same convention as the other gates: 0 pass, 1 violation, 2 cannot-check.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

HEADER = "| Statement | Reality | Evidence |"
SECTION = re.compile(r"^## 2\.\s", re.M)
NEXT_SECTION = re.compile(r"^## \d+\.\s", re.M)

# Split a markdown row on unescaped pipes only.
SPLIT = re.compile(r"(?<!\\)\|")


def fail_closed(path: Path, reason: str) -> int:
    print(f"UNEVALUATED — {reason}")
    print(f"           Failing closed: an unchecked table is not a passing table.")
    return 2


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        return fail_closed(Path("AGENTS.md"), "no path given")
    path = Path(argv[1])
    if not path.is_file():
        return fail_closed(path, f"{path} not found")
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:            # unreadable is not "compliant"
        return fail_closed(path, f"cannot read {path}: {exc}")

    m = SECTION.search(text)
    if not m:
        return fail_closed(path, f"{path} has no '## 2.' section")
    start = m.start()
    nxt = NEXT_SECTION.search(text, m.end())
    section = text[start:nxt.start()] if nxt else text[start:]

    problems: list[str] = []
    if "verified" not in section.splitlines()[0].lower():
        problems.append("section 2 heading no longer says the table is verified")
    if HEADER not in section:
        return fail_closed(path, f"header row {HEADER!r} not found in section 2")

    rows = [l for l in section.splitlines() if l.strip().startswith("|")]
    data = [r for r in rows if r.strip() not in ("|" + "|".join([])) and not set(r) <= {"|", "-", " ", ":"}]
    data = [r for r in data if HEADER not in r]
    if not data:
        problems.append("the table has no rows")

    for raw in data:
        cells = [c.strip() for c in SPLIT.split(raw)[1:-1]]
        label = (cells[0][:48] if cells else raw[:48])
        if len(cells) != 3:
            problems.append(f"row has {len(cells)} cells, expected 3: {label}")
            continue
        if not all(cells):
            problems.append(f"row has an empty cell: {label}")
            continue
        if not cells[2] or cells[2] in {"—", "-", "n/a"}:
            problems.append(f"row cites no evidence: {label}")

    print(f"enforcement-truth rows checked: {len(data)}")
    if problems:
        for p in problems:
            print(f"  ✗ {p}")
        print(f"\nREFUSED — {len(problems)} problem(s) in {path}.")
        return 1
    print(f"\nPASSED — AGENTS.md enforcement table is well-formed ({len(data)} rows, "
          f"every row cites evidence).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
