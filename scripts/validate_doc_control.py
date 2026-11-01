#!/usr/bin/env python3
"""Validate the document-control block of a governance Markdown file.

A behaviour-policy file is only worth what its metadata says: who owns it, how it classifies,
what it defers to, and when a human last read it. Without a checker, a rule document silently
ages into a false statement — the "overstated control" this repository already records as an
audit finding (see `docs/drift-findings.md` S2-004, where AGENTS.md cited a resolved mismatch as
current truth). This gate keeps QODER.md's own §8 claim honest by measuring it instead of
asserting it.

Rules enforced:
  1. A `## Document control` section exists and carries a `| Field | Value |` table.
  2. All six fields are present: Status, Classification, Owner, Last reviewed,
     Review cadence, Authority. Each must have exactly two non-empty cells.
  3. `Authority` must name a governing file — a precedence row that points at nothing leaves
     two rule documents in charge, which is the failure this document's preamble forbids.
  4. `Last reviewed` must be an ISO date, must not be in the future, and must be within
     --max-age-days (default 92, i.e. quarterly) of today. An expired review is a violation,
     not a note: cadence is the only control that keeps a policy file current.

Exit codes, same convention as the other gates: 0 pass, 1 violation, 2 cannot-check.
Usage: python3 scripts/validate_doc_control.py <file.md> [--today YYYY-MM-DD]
            [--max-age-days N]
"""
from __future__ import annotations

import re
import sys
from datetime import date
from pathlib import Path

HEADER = "| Field | Value |"
SECTION = re.compile(r"^## Document control\s*$", re.M)
ANY_HEADING = re.compile(r"^#{2,6} ", re.M)
SPLIT = re.compile(r"(?<!\\)\|")
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

REQUIRED = ("Status", "Classification", "Owner", "Last reviewed", "Review cadence", "Authority")
DEFAULT_MAX_AGE_DAYS = 92


def fail_closed(path: Path, reason: str) -> int:
    print(f"UNEVALUATED — {reason}")
    print("           Failing closed: an unchecked document is not a compliant document.")
    return 2


def parse_iso(text: str) -> date | None:
    if not ISO_DATE.match(text):
        return None
    try:
        return date.fromisoformat(text)
    except ValueError:
        return None


def main(argv: list[str]) -> int:
    args = argv[1:]
    if not args or args[0].startswith("-"):
        return fail_closed(Path("QODER.md"), "no document path given")
    path = Path(args[0])
    if not path.is_file():
        return fail_closed(path, f"{path} not found")

    today = date.today()
    max_age = DEFAULT_MAX_AGE_DAYS
    flags = iter(args[1:])
    for flag in flags:
        if flag in ("--today", "--max-age-days"):
            value = next(flags, None)
            if value is None:
                return fail_closed(path, f"{flag} needs a value")
            if flag == "--today":
                parsed = parse_iso(value)
                if parsed is None:
                    return fail_closed(path, f"--today {value!r} is not an ISO date")
                today = parsed
            else:
                try:
                    max_age = int(value)
                except ValueError:
                    return fail_closed(path, f"--max-age-days {value!r} is not an integer")
        else:
            return fail_closed(path, f"unrecognised argument {flag!r}")

    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:            # unreadable is not "compliant"
        return fail_closed(path, f"cannot read {path}: {exc}")

    m = SECTION.search(text)
    if not m:
        return fail_closed(path, f"{path} has no '## Document control' section")
    nxt = ANY_HEADING.search(text, m.end())
    section = text[m.end():nxt.start()] if nxt else text[m.end():]

    if HEADER not in section:
        return fail_closed(path, f"header row {HEADER!r} not found in the document-control block")

    rows = [l for l in section.splitlines() if l.strip().startswith("|")]
    rows = [r for r in rows if HEADER not in r and not set(r) <= {"|", "-", " ", ":"}]

    problems: list[str] = []
    fields: dict[str, str] = {}
    for raw in rows:
        cells = [c.strip() for c in SPLIT.split(raw)[1:-1]]
        if len(cells) != 2:
            problems.append(f"field row has {len(cells)} cells, expected 2: {raw[:60]}")
            continue
        if not cells[1]:
            problems.append(f"field {cells[0]!r} has no value")
        fields.setdefault(cells[0], cells[1])

    for name in REQUIRED:
        if name not in fields:
            problems.append(f"document control has no {name!r} row")

    authority = fields.get("Authority", "")
    if authority and "AGENTS.md" not in authority:
        problems.append("Authority row declares no governing file, so precedence is ambiguous")

    reviewed = fields.get("Last reviewed", "")
    if reviewed:
        parsed = parse_iso(reviewed)
        if parsed is None:
            problems.append(f"'Last reviewed' is not an ISO date: {reviewed[:40]!r}")
        elif parsed > today:
            problems.append(f"'Last reviewed' {reviewed} is dated in the future")
        elif (today - parsed).days > max_age:
            problems.append(f"review overdue: last reviewed {reviewed}, "
                            f"{(today - parsed).days} days old against a {max_age}-day cadence")

    print(f"document-control fields checked: {len(fields)} (reviewed {today.isoformat()}, "
          f"cadence {max_age}d)")
    if problems:
        for p in problems:
            print(f"  ✗ {p}")
        print(f"\nREFUSED — {len(problems)} problem(s) in {path}.")
        return 1
    print(f"\nPASSED — {path} document control is complete, subordinate to AGENTS.md, "
          f"and within its review cadence.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
