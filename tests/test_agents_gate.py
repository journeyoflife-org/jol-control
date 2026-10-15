#!/usr/bin/env python3
"""Self-tests for scripts/validate_agents_table.py — the enforcement-truth table gate.

The fixture tests/fixtures/agents_table/agents_real.md is captured verbatim from
AGENTS.md section 2 on 2026-10-16 — real content, not a hand-written sample — and the
broken variants below are derived from it by mutation, so each case reproduces a mistake a
person can actually make while editing that table: an unescaped pipe that silently adds a
cell, a row whose evidence column was left blank, a table with no rows, and a file with no
section 2 at all.

Why this gate exists: AGENTS.md section 2 is what an agent reads before trusting any claim
about this organization, and documentation-only commits are excluded from apply.yml's
``paths:`` filter by design, so a broken row reaches main without any CI run. A gate that
checks prose must itself be proven not to go inert.

Exit-code convention shared with the other gates: 0 pass, 1 violation, 2 cannot-check.

Run directly (no pytest required):
    python3 tests/test_agents_gate.py
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GATE = REPO_ROOT / "scripts" / "validate_agents_table.py"
FIXTURE = REPO_ROOT / "tests" / "fixtures" / "agents_table" / "agents_real.md"

EXIT_PASS = 0
EXIT_VIOLATION = 1
EXIT_UNEVALUATED = 2

SPLIT = re.compile(r"(?<!\\)\|")

FAILURES: list[str] = []


def run_gate(text_or_path: Path | str, *, is_path: bool = False) -> tuple[int, str]:
    """Invoke the gate as a subprocess; return (exit_code, combined_output)."""
    target = str(text_or_path)
    proc = subprocess.run(
        [sys.executable, str(GATE), target],
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ✓ {name}" + (f": {detail}" if detail else ""))
    else:
        FAILURES.append(f"{name} — {detail or 'condition false'}")
        print(f"  ✗ {name}" + (f": {detail}" if detail else ""))


def mutate(fn) -> str:
    return fn(FIXTURE.read_text(encoding="utf-8"))


def split_cells(row: str) -> list[str]:
    return [c.strip() for c in SPLIT.split(row)[1:-1]]


# --------------------------------------------------------------------------- tests

def test_real_fixture_passes() -> None:
    rc, out = run_gate(FIXTURE)
    check("captured AGENTS.md section 2 passes", rc == EXIT_PASS, f"exit={rc}")
    check("and reports PASSED, not a silent zero", "PASSED" in out)


def test_fixture_has_rows_not_just_header() -> None:
    rows = [l for l in FIXTURE.read_text().splitlines() if l.startswith('| "') ]
    check("fixture carries real rows", len(rows) >= 5, f"{len(rows)} rows")


def test_unescaped_pipe_adds_a_cell() -> None:
    def break_it(text: str) -> str:
        out, done = [], False
        for line in text.splitlines():
            if not done and line.startswith('| "CI applies changes'):
                line = line.replace("| `apply.yml` run history", "| apply.yml run | history")
                done = True
            out.append(line)
        assert done, "mutation target row missing from fixture"
        return "\n".join(out) + "\n"

    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write(mutate(break_it))
        path = Path(fh.name)
    rc, out = run_gate(path)
    path.unlink()
    check("unescaped pipe inside a cell is refused", rc == EXIT_VIOLATION, f"exit={rc}")
    check("and the row is named", "cells" in out and "4 cells" in out, out.strip().splitlines()[-1][:60])


def test_empty_evidence_cell() -> None:
    def break_it(text: str) -> str:
        return text.replace(
            "| \"Squash-merge only\" | **False.** Merge commits disabled, squash *and* rebase enabled "
            "| `allow_merge_commit=false`, `allow_squash_merge=true`, `allow_rebase_merge=true` |",
            "| \"Squash-merge only\" | **False.** whatever it says |  |",
        )

    broken = mutate(break_it)
    assert broken != FIXTURE.read_text(), "mutation did not apply (fixture line drifted)"
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write(broken)
        path = Path(fh.name)
    rc, out = run_gate(path)
    path.unlink()
    check("a row with no evidence is refused", rc == EXIT_VIOLATION, f"exit={rc}")
    check("and is described as an empty cell", "empty cell" in out or "no evidence" in out)


def test_no_rows_is_not_a_pass() -> None:
    stripped = "\n".join(
        l for l in FIXTURE.read_text().splitlines() if not l.startswith('| "')
    ) + "\n"
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write(stripped)
        path = Path(fh.name)
    rc, out = run_gate(path)
    path.unlink()
    check("header-only table never passes", rc in (EXIT_VIOLATION, EXIT_UNEVALUATED), f"exit={rc}")


def test_missing_header_fails_closed() -> None:
    text = "\n".join(
        l for l in FIXTURE.read_text().splitlines() if not l.startswith("| Statement")
    ) + "\n"
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write(text)
        path = Path(fh.name)
    rc, out = run_gate(path)
    path.unlink()
    check("absent header is UNEVALUATED, not compliant", rc == EXIT_UNEVALUATED, f"exit={rc}")
    check("and 'PASSED' never appears for it", "PASSED" not in out)


def test_missing_section_and_file_fail_closed() -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write("# Nothing relevant\n")
        path = Path(fh.name)
    rc, out = run_gate(path)
    path.unlink()
    check("file with no section 2 is UNEVALUATED", rc == EXIT_UNEVALUATED, f"exit={rc}")

    rc, out = run_gate(REPO_ROOT / "tests" / "definitely-not-here.md")
    check("unreadable path is UNEVALUATED", rc == EXIT_UNEVALUATED, f"exit={rc}")
    check("a missing file is never reported as passing", "PASSED" not in out)


def test_no_argument_fails_closed() -> None:
    proc = subprocess.run([sys.executable, str(GATE)], capture_output=True, text=True)
    check("running with no path is UNEVALUATED", proc.returncode == EXIT_UNEVALUATED,
          f"exit={proc.returncode}")


def test_live_agents_md_agrees_with_fixture() -> None:
    """The gate's own repo must pass: if AGENTS.md rots, this test says so on every PR."""
    rc, out = run_gate(REPO_ROOT / "AGENTS.md")
    check("live AGENTS.md passes the gate", rc == EXIT_PASS, f"exit={rc}")


def main() -> int:
    if not GATE.is_file():
        print(f"FAILED — gate not found: {GATE}", file=sys.stderr)
        return 1
    if not FIXTURE.is_file():
        print(f"FAILED — fixture not found: {FIXTURE}", file=sys.stderr)
        return 1

    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        print(f"{t.__name__}:")
        t()

    if FAILURES:
        print(f"\nFAILED — {len(FAILURES)} assertion(s) across {len(tests)} test(s):", file=sys.stderr)
        for f in FAILURES:
            print(f"  ✗ {f}", file=sys.stderr)
        return 1

    print(f"\nPASSED — {len(tests)} agents-table-gate tests, 0 failures.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
